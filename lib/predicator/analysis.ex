defmodule Predicator.Analysis do
  @moduledoc """
  What an expression or a program reads, calls and stores, listed for tooling.

  A checker that compares every path a condition reads against a declared
  shape, or an editor that lists the functions a program calls, needs those
  facts without evaluating anything. This module answers three questions:

    * `references/1` - each variable read, as a path.
    * `calls/1` - each function call, with its name and arity.
    * `assignments/1` - each location a program stores to, as a path.

  It is a reading surface, not a parsing one, in the `Predicator.Vocabulary`
  mould. Nothing here participates in lexing, parsing, compiling or
  evaluating, and no answer depends on a context: a path is read off the
  program text, never resolved against data.

  ## Inputs

  Each function accepts any of five forms of one program:

    * a source string, read as a program the way
      `Predicator.parse_program/2` reads it. Every expression is a program of
      one statement, and `=` is never an equality operator (`==` is), so a
      condition and a script read alike;
    * an AST from `Predicator.parse/2`, or any single statement or block;
    * a program from `Predicator.parse_program/2`;
    * an instruction list, from `Predicator.compile/1` or from storage;
    * a `Predicator.Compiled` envelope.

  The AST forms and the instruction forms give the same paths, calls and
  stores for the same source (the instruction form rebuilds paths by tracking
  what the stack holds). Positions come from the AST's own slots, or from the
  envelope's position table; a bare instruction list carries no positions, so
  every position read from one is `nil`.

  ## Answers

  Every answer lists every occurrence, in source order, as maps. A caller that
  wants a set dedupes.

    * A reference is `%{path: [segment], position: position}`.
    * A call is `%{name: name, arity: arity, position: position}`. A qualified
      name (`ns.fn(x)`) is reported as written, dots included; calls nested in
      another call's arguments are listed too, the outer call first.
    * An assignment is `%{path: [segment], position: position}`.

  A segment is a string (a variable name or a property name, or a string
  literal key), an integer (a literal integer index), or `:dynamic` (any other
  bracket key: a computed key, or a literal that is neither a string nor an
  integer). The path continues past a `:dynamic` segment, and a computed key's
  own reads are listed as references of their own.

  A reference is a chain rooted at a variable. A chain rooted anywhere else (a
  call's result, a literal) reads no variable, so `f(x).y` lists `x` and the
  call, and no reference for `.y`. The location an assignment writes is not a
  read; the reads inside its bracket keys are.

  A position is the node's trailing slot (`t:Predicator.Parser.position/0`).
  For a path - a reference or an assignment - it is the span of the whole
  chain when the program was parsed or compiled with spans, and otherwise the
  point position of the chain's root variable: either way it starts where the
  path starts. A call's position is the call node's own.

  ## Examples

      iex> Predicator.Analysis.references("score > limit")
      {:ok, [%{path: ["score"], position: {1, 1}}, %{path: ["limit"], position: {1, 9}}]}

      iex> {:ok, program} = Predicator.parse_program("total = price * 2")
      iex> Predicator.Analysis.assignments(program)
      {:ok, [%{path: ["total"], position: {1, 1}}]}

  ## Errors

  A source string that does not parse answers the
  `%Predicator.Errors.ParseError{}` `Predicator.compile_program/1` returns for
  it. An instruction the analysis cannot read - an opcode outside
  `Predicator.Instructions.opcodes/0`, or an operand of the wrong shape -
  answers an `%Predicator.Errors.EvaluationError{}` with the evaluator's
  `"unknown_instruction"` reason. An instruction list that pops more values
  than it pushed is read as far as it goes: the missing values read nothing.

  `test/predicator/analysis_clause_coverage_test.exs` keeps the AST clauses in
  step with `t:Predicator.Parser.visitable/0` and the instruction clauses in
  step with `Predicator.Instructions.opcodes/0`, the retired opcodes included.
  """

  alias Predicator.{AST, Compiled, Parser, Types}
  alias Predicator.Errors.{EvaluationError, ParseError}

  @typedoc """
  One step of a path: a name, a literal integer index, or `:dynamic` for any
  other bracket key.
  """
  @type segment :: String.t() | integer() | :dynamic

  @typedoc """
  A source annotation: a point position, a span, or `nil` when none is known.
  """
  @type position :: Parser.position()

  @typedoc """
  One variable read.
  """
  @type read :: %{path: [segment()], position: position()}

  @typedoc """
  One function call.
  """
  @type call :: %{name: String.t(), arity: non_neg_integer(), position: position()}

  @typedoc """
  One location a program stores to.
  """
  @type assignment :: %{path: [segment()], position: position()}

  @typedoc """
  Anything the three functions accept.
  """
  @type input :: String.t() | Parser.visitable() | Types.instruction_list() | Compiled.t()

  @typedoc """
  The error arm: a parse failure for a source string, or an instruction the
  analysis cannot read.
  """
  @type error :: ParseError.t() | EvaluationError.t()

  @doc """
  Lists every variable read in `input`, in source order.

  ## Examples

      iex> Predicator.Analysis.references("user.tags[0] == 'x' or items[k].id > 1")
      {:ok,
       [
         %{path: ["user", "tags", 0], position: {1, 1}},
         %{path: ["items", :dynamic, "id"], position: {1, 24}},
         %{path: ["k"], position: {1, 30}}
       ]}

  The instruction form gives the same paths, with positions only when the
  envelope carries a table:

      iex> {:ok, instructions} = Predicator.compile("user.tags[0] == 'x'")
      iex> Predicator.Analysis.references(instructions)
      {:ok, [%{path: ["user", "tags", 0], position: nil}]}

      iex> {:ok, compiled} = Predicator.compile_with_spans("user.tags[0] == 'x'")
      iex> Predicator.Analysis.references(compiled)
      {:ok, [%{path: ["user", "tags", 0], position: {{1, 1}, {1, 13}}}]}

  A program's reads include its bracket keys, never the location it writes:

      iex> {:ok, program} = Predicator.parse_program("totals[day] = totals[day] + amount")
      iex> {:ok, refs} = Predicator.Analysis.references(program)
      iex> Enum.map(refs, & &1.path)
      [["day"], ["totals", :dynamic], ["day"], ["amount"]]
  """
  @spec references(input()) :: {:ok, [read()]} | {:error, error()}
  def references(input), do: answer(input, :references)

  @doc """
  Lists every function call in `input`, in source order, nested calls
  included.

  ## Examples

      iex> Predicator.Analysis.calls("max(len(name), 3) > ns.limit()")
      {:ok,
       [
         %{name: "max", arity: 2, position: {1, 1}},
         %{name: "len", arity: 1, position: {1, 5}},
         %{name: "ns.limit", arity: 0, position: {1, 21}}
       ]}

      iex> {:ok, instructions} = Predicator.compile("max(len(name), 3) > 1")
      iex> {:ok, calls} = Predicator.Analysis.calls(instructions)
      iex> Enum.map(calls, &{&1.name, &1.arity})
      [{"max", 2}, {"len", 1}]
  """
  @spec calls(input()) :: {:ok, [call()]} | {:error, error()}
  def calls(input), do: answer(input, :calls)

  @doc """
  Lists every location a program stores to, in source order.

  The path is read off the assignment's location chain: the root variable,
  then one segment per property or bracket access. A bracket key that is a
  string or integer literal is that segment; any other key is `:dynamic`. An
  expression stores nothing.

  ## Examples

      iex> {:ok, program} = Predicator.parse_program("a.b = 1; if ok { list[i] = 2 }")
      iex> Predicator.Analysis.assignments(program)
      {:ok, [%{path: ["a", "b"], position: {1, 1}}, %{path: ["list", :dynamic], position: {1, 18}}]}

      iex> {:ok, compiled} = Predicator.compile_program_with_positions("a['b'][0] = 1")
      iex> Predicator.Analysis.assignments(compiled)
      {:ok, [%{path: ["a", "b", 0], position: {1, 1}}]}
  """
  @spec assignments(input()) :: {:ok, [assignment()]} | {:error, error()}
  def assignments(input), do: answer(input, :assignments)

  @spec answer(input(), :references | :calls | :assignments) ::
          {:ok, [map()]} | {:error, error()}
  defp answer(input, key) do
    case analyse(input) do
      {:ok, found} -> {:ok, Map.fetch!(found, key)}
      {:error, _error} = error -> error
    end
  end

  @typep found :: %{references: [read()], calls: [call()], assignments: [assignment()]}

  @spec analyse(input()) :: {:ok, found()} | {:error, error()}
  defp analyse(source) when is_binary(source) do
    case Predicator.parse_program(source) do
      {:ok, ast} ->
        {:ok, from_ast(ast)}

      {:error, message, line, column, span} ->
        {:error, ParseError.new(message, line, column, span)}
    end
  end

  defp analyse(%Compiled{instructions: instructions, positions: positions}),
    do: from_instructions(instructions, positions)

  defp analyse(instructions) when is_list(instructions), do: from_instructions(instructions, %{})

  defp analyse(ast) when is_tuple(ast), do: {:ok, from_ast(ast)}

  # Where a path's position comes from: the chain's own span when there is
  # one, else the root variable's point position. Both start at the root.
  @spec path_position(position(), position()) :: position()
  defp path_position({{_sl, _sc}, {_el, _ec}} = span, _root), do: span
  defp path_position(_point, root), do: root

  ## The AST form

  @spec from_ast(Parser.visitable()) :: found()
  defp from_ast(ast) do
    {_ast, acc} = AST.prewalk(ast, %{references: [], calls: [], assignments: []}, &node_step/2)

    %{acc | references: Enum.reverse(acc.references)}
    |> Map.update!(:calls, &Enum.reverse/1)
    |> Map.update!(:assignments, &Enum.reverse/1)
  end

  # One clause per constructor of Parser.visitable/0, in the order Predicator.AST
  # lists them. A clause returns the node whose children the walk visits next:
  # a reference or an assignment returns a stand-in holding only the
  # expressions still to read (its bracket keys, and an assignment's value), so
  # the chain itself is not read twice. analysis_clause_coverage_test.exs reads
  # these heads against the typespec.
  @spec node_step(Parser.visitable(), found()) :: {Parser.visitable(), found()}
  defp node_step({:literal, _value, _pos} = node, acc), do: {node, acc}
  defp node_step({:string_literal, _value, _quote, _pos} = node, acc), do: {node, acc}

  defp node_step({:identifier, name, pos} = node, acc),
    do: {node, add(acc, :references, %{path: [name], position: pos})}

  defp node_step({:duration, _units, _pos} = node, acc), do: {node, acc}
  defp node_step({:comparison, _op, _left, _right, _pos} = node, acc), do: {node, acc}
  defp node_step({:arithmetic, _op, _left, _right, _pos} = node, acc), do: {node, acc}
  defp node_step({:membership, _op, _left, _right, _pos} = node, acc), do: {node, acc}
  defp node_step({:unary, _op, _operand, _pos} = node, acc), do: {node, acc}
  defp node_step({:logical_and, _left, _right, _pos} = node, acc), do: {node, acc}
  defp node_step({:logical_or, _left, _right, _pos} = node, acc), do: {node, acc}
  defp node_step({:logical_not, _operand, _pos} = node, acc), do: {node, acc}
  defp node_step({:list, _elements, _pos} = node, acc), do: {node, acc}
  defp node_step({:object, _entries, _pos} = node, acc), do: {node, acc}

  defp node_step({:function_call, name, args, pos} = node, acc),
    do: {node, add(acc, :calls, %{name: name, arity: length(args), position: pos})}

  defp node_step({:bracket_access, _object, _key, pos} = node, acc),
    do: chain_step(node, pos, acc)

  defp node_step({:property_access, _object, _prop, pos} = node, acc),
    do: chain_step(node, pos, acc)

  defp node_step({:cast, _expression, _type, _pos} = node, acc), do: {node, acc}
  defp node_step({:relative_date, _duration, _direction, _pos} = node, acc), do: {node, acc}

  defp node_step({:assignment, location, value, pos}, acc) do
    {path, root_pos, keys} = location_chain(location)
    acc = add(acc, :assignments, %{path: path, position: path_position(pos, root_pos)})
    {{:block, keys ++ [value], pos}, acc}
  end

  defp node_step({:if, _condition, _then, _else, _pos} = node, acc), do: {node, acc}
  defp node_step({:while, _condition, _body, _pos} = node, acc), do: {node, acc}
  defp node_step({:block, _statements, _pos} = node, acc), do: {node, acc}
  defp node_step({:program, _statements, _pos} = node, acc), do: {node, acc}

  # The outermost access node of a chain rooted at a variable is one
  # reference; the walk then reads only the chain's bracket keys. A chain
  # rooted anywhere else is walked as it stands.
  @spec chain_step(Parser.ast(), position(), found()) :: {Parser.visitable(), found()}
  defp chain_step(node, pos, acc) do
    case read_chain(node) do
      {:ok, path, root_pos, keys} ->
        reference = %{path: path, position: path_position(pos, root_pos)}
        {{:list, keys, nil}, add(acc, :references, reference)}

      :not_a_path ->
        {node, acc}
    end
  end

  @spec read_chain(Parser.ast()) :: {:ok, [segment()], position(), [Parser.ast()]} | :not_a_path
  defp read_chain({:identifier, name, pos}), do: {:ok, [name], pos, []}

  defp read_chain({:property_access, object, property, _pos}) do
    with {:ok, path, root_pos, keys} <- read_chain(object),
         do: {:ok, path ++ [property], root_pos, keys}
  end

  defp read_chain({:bracket_access, object, key, _pos}) do
    with {:ok, path, root_pos, keys} <- read_chain(object),
         do: {:ok, path ++ [key_segment(key)], root_pos, keys ++ [key]}
  end

  defp read_chain(_other), do: :not_a_path

  # An assignment's location chain, walked directly: an identifier wrapped in
  # property and bracket accesses (t:Predicator.Parser.assignment/0). Answers
  # the path, the root's position and the bracket keys still to read. The
  # parser builds no other location; a hand-built one is one dynamic segment
  # whose own reads are listed.
  @spec location_chain(Parser.ast()) :: {[segment()], position(), [Parser.ast()]}
  defp location_chain({:identifier, name, pos}), do: {[name], pos, []}

  defp location_chain({:property_access, object, property, _pos}) do
    {path, root_pos, keys} = location_chain(object)
    {path ++ [property], root_pos, keys}
  end

  defp location_chain({:bracket_access, object, key, _pos}) do
    {path, root_pos, keys} = location_chain(object)
    {path ++ [key_segment(key)], root_pos, keys ++ [key]}
  end

  defp location_chain(other), do: {[:dynamic], nil, [other]}

  @spec key_segment(Parser.ast()) :: segment()
  defp key_segment({:literal, value, _pos}) when is_binary(value) or is_integer(value), do: value
  defp key_segment({:string_literal, value, _quote, _pos}), do: value
  defp key_segment(_computed), do: :dynamic

  @spec add(found(), :references | :calls | :assignments, map()) :: found()
  defp add(acc, key, item), do: Map.update!(acc, key, &[item | &1])

  ## The instruction form
  #
  # The instructions run through a symbolic stack. Each entry is
  # `{start, kind}`: `start` is the index of the first instruction that built
  # the value, which orders calls by source; `kind` is `{:path, path, root,
  # top}` for a chain rooted at a `load` (`root` the load's index, `top` the
  # last access applied), `{:lit, value}` for a `lit`, or `:value`. A path
  # becomes a reference when anything other than an access consumes it.

  @typep kind ::
           {:path, [segment()], non_neg_integer(), non_neg_integer()}
           | {:lit, term()}
           | :value
  @typep entry :: {non_neg_integer(), kind()}
  @typep state :: %{
           stack: [entry()],
           merges: %{optional(non_neg_integer()) => [non_neg_integer()]},
           positions: map(),
           references: [{non_neg_integer(), read()}],
           calls: [{{non_neg_integer(), integer()}, call()}],
           assignments: [assignment()]
         }

  @spec from_instructions(term(), map()) :: {:ok, found()} | {:error, EvaluationError.t()}
  defp from_instructions(instructions, positions) when is_list(instructions) do
    initial = %{
      stack: [],
      merges: %{},
      positions: positions,
      references: [],
      calls: [],
      assignments: []
    }

    instructions
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, initial}, fn {instruction, index}, {:ok, state} ->
      case step(instruction, index, merge(state, index)) do
        {:ok, state} -> {:cont, {:ok, state}}
        :unreadable -> {:halt, {:error, unreadable(instruction)}}
      end
    end)
    |> case do
      {:ok, state} -> {:ok, finish(state, length(instructions))}
      {:error, _error} = error -> error
    end
  end

  @spec finish(state(), non_neg_integer()) :: found()
  defp finish(state, length) do
    state = merge(state, length)
    state = Enum.reduce(state.stack, %{state | stack: []}, &consume/2)

    %{
      references: state.references |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1)),
      calls: state.calls |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1)),
      assignments: Enum.reverse(state.assignments)
    }
  end

  @spec unreadable(term()) :: EvaluationError.t()
  defp unreadable(instruction) do
    EvaluationError.new(
      "Unknown instruction: #{inspect(instruction)}",
      "unknown_instruction",
      :analysis
    )
  end

  # One clause per opcode of Predicator.Instructions.opcodes/0, the retired
  # "and" and "or" included, each guarding its operands as docs/isa.md section
  # 4 states them. analysis_clause_coverage_test.exs reads these heads against
  # the opcode table.
  @spec step(term(), non_neg_integer(), state()) :: {:ok, state()} | :unreadable
  defp step(["lit", value], i, state), do: {:ok, push(state, {i, {:lit, value}})}

  defp step(["load", name], i, state) when is_binary(name),
    do: {:ok, push(state, {i, {:path, [name], i, i}})}

  defp step(["access", property], i, state) when is_binary(property) do
    {object, state} = pop(state, i)
    {:ok, extend(state, object, property, i)}
  end

  defp step(["compare", op], i, state) when is_binary(op), do: {:ok, combine(state, 2, i)}
  defp step(["and"], i, state), do: {:ok, combine(state, 2, i)}
  defp step(["or"], i, state), do: {:ok, combine(state, 2, i)}
  defp step(["not"], i, state), do: {:ok, combine(state, 1, i)}
  defp step(["in"], i, state), do: {:ok, combine(state, 2, i)}
  defp step(["contains"], i, state), do: {:ok, combine(state, 2, i)}
  defp step(["add"], i, state), do: {:ok, combine(state, 2, i)}
  defp step(["subtract"], i, state), do: {:ok, combine(state, 2, i)}
  defp step(["multiply"], i, state), do: {:ok, combine(state, 2, i)}
  defp step(["divide"], i, state), do: {:ok, combine(state, 2, i)}
  defp step(["modulo"], i, state), do: {:ok, combine(state, 2, i)}
  defp step(["unary_minus"], i, state), do: {:ok, combine(state, 1, i)}
  defp step(["unary_bang"], i, state), do: {:ok, combine(state, 1, i)}

  defp step(["bracket_access"], i, state) do
    {key, state} = pop(state, i)
    {object, state} = pop(state, i)
    {segment, state} = segment(key, state)
    {:ok, extend(state, object, segment, i)}
  end

  defp step(["call", name, arity], i, state)
       when is_binary(name) and is_integer(arity) and arity >= 0 do
    {args, state} = pop_many(state, arity, i)
    start = first_start(args, i)
    call = %{name: name, arity: arity, position: Map.get(state.positions, i)}
    state = Enum.reduce(args, %{state | calls: [{{start, -i}, call} | state.calls]}, &consume/2)
    {:ok, push(state, {start, :value})}
  end

  defp step(["object_new"], i, state), do: {:ok, push(state, {i, :value})}
  defp step(["object_set", key], i, state) when is_binary(key), do: {:ok, combine(state, 2, i)}

  defp step(["duration", units], i, state) when is_list(units),
    do: {:ok, push(state, {i, :value})}

  defp step(["relative_date", direction], i, state) when is_binary(direction),
    do: {:ok, combine(state, 1, i)}

  defp step(["make_list", count], i, state) when is_integer(count) and count >= 0,
    do: {:ok, combine(state, count, i)}

  defp step(["jump_if_falsy_or_pop", offset], i, state) when is_integer(offset) and offset > 0,
    do: {:ok, short_circuit(state, i, offset)}

  defp step(["jump_if_true_or_pop", offset], i, state) when is_integer(offset) and offset > 0,
    do: {:ok, short_circuit(state, i, offset)}

  defp step(["store", depth], i, state) when is_integer(depth) and depth >= 0 do
    {value, state} = pop(state, i)
    {segments, state} = pop_many(state, depth, i)
    {path, state} = Enum.map_reduce(segments, state, &segment/2)
    position = Map.get(state.positions, i)

    state =
      consume(value, %{
        state
        | assignments: [%{path: path, position: position} | state.assignments]
      })

    {:ok, state}
  end

  defp step(["pop"], i, state), do: {:ok, discard(state, i)}

  defp step(["cast", type_name], i, state) when is_binary(type_name),
    do: {:ok, combine(state, 1, i)}

  defp step(["jump", offset], _i, state) when is_integer(offset) and offset > 0, do: {:ok, state}

  defp step(["pop_jump_if_falsy", offset], i, state) when is_integer(offset) and offset > 0,
    do: {:ok, discard(state, i)}

  defp step(["jump_backward", offset], _i, state) when is_integer(offset) and offset > 0,
    do: {:ok, state}

  defp step(_instruction, _i, _state), do: :unreadable

  @spec push(state(), entry()) :: state()
  defp push(state, entry), do: %{state | stack: [entry | state.stack]}

  # A pop from an empty stack reads nothing: a list that underflows is read
  # as far as it goes.
  @spec pop(state(), non_neg_integer()) :: {entry(), state()}
  defp pop(%{stack: [top | rest]} = state, _i), do: {top, %{state | stack: rest}}
  defp pop(%{stack: []} = state, i), do: {{i, :value}, state}

  # Pops `count` entries and answers them bottom-first (source order).
  @spec pop_many(state(), non_neg_integer(), non_neg_integer()) :: {[entry()], state()}
  defp pop_many(state, count, i) do
    {entries, state} =
      Enum.map_reduce(List.duplicate(nil, count), state, fn nil, state -> pop(state, i) end)

    {Enum.reverse(entries), state}
  end

  @spec first_start([entry()], non_neg_integer()) :: non_neg_integer()
  defp first_start([{start, _kind} | _rest], _i), do: start
  defp first_start([], i), do: i

  # Pops `count` operands, reads them, and pushes one plain value.
  @spec combine(state(), non_neg_integer(), non_neg_integer()) :: state()
  defp combine(state, count, i) do
    {operands, state} = pop_many(state, count, i)
    state = Enum.reduce(operands, state, &consume/2)
    push(state, {first_start(operands, i), :value})
  end

  @spec discard(state(), non_neg_integer()) :: state()
  defp discard(state, i) do
    {entry, state} = pop(state, i)
    consume(entry, state)
  end

  # An access extends a path; on anything else it reads its object as it
  # stands and yields a plain value.
  @spec extend(state(), entry(), segment(), non_neg_integer()) :: state()
  defp extend(state, {start, {:path, path, root, _top}}, segment, i),
    do: push(state, {start, {:path, path ++ [segment], root, i}})

  defp extend(state, {start, _kind} = object, _segment, _i),
    do: push(consume(object, state), {start, :value})

  # A bracket key or a store segment: a string or integer literal is that
  # segment; anything else is `:dynamic`, and its own reads are listed.
  @spec segment(entry(), state()) :: {segment(), state()}
  defp segment({_start, {:lit, value}}, state) when is_binary(value) or is_integer(value),
    do: {value, state}

  defp segment(entry, state), do: {:dynamic, consume(entry, state)}

  # A short-circuit jump pops its left operand on the path that falls through
  # into the right one. Where the two paths meet, the operator's value is the
  # one value on the stack, built from the left operand's first instruction.
  @spec short_circuit(state(), non_neg_integer(), pos_integer()) :: state()
  defp short_circuit(state, i, offset) do
    {{start, _kind} = left, state} = pop(state, i)
    state = consume(left, state)
    %{state | merges: Map.update(state.merges, i + offset, [start], &[start | &1])}
  end

  @spec merge(state(), non_neg_integer()) :: state()
  defp merge(state, index) do
    case Map.pop(state.merges, index) do
      {nil, _merges} ->
        state

      {starts, merges} ->
        Enum.reduce(starts, %{state | merges: merges}, fn start, state ->
          {{right_start, _kind} = right, state} = pop(state, index)
          push(consume(right, state), {min(start, right_start), :value})
        end)
    end
  end

  # Reads an entry: a path becomes a reference, ordered by its root `load`.
  @spec consume(entry(), state()) :: state()
  defp consume({_start, {:path, path, root, top}}, state) do
    position = path_position(Map.get(state.positions, top), Map.get(state.positions, root))
    reference = {root, %{path: path, position: position}}
    %{state | references: [reference | state.references]}
  end

  defp consume(_entry, state), do: state
end
