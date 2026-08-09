defmodule Predicator do
  @moduledoc """
  A secure, non-evaluative condition engine for processing end-user boolean predicates.

  Predicator transforms string conditions into executable instructions that can be
  safely evaluated without direct code execution. It uses a stack-based virtual machine
  to process instructions and supports flexible context-based condition checking.

  ## Basic Usage

  The simplest way to use Predicator is with the `evaluate/2` function:

      iex> instructions = [["lit", 42]]
      iex> Predicator.evaluate(instructions)
      {:ok, 42}

      iex> instructions = [["load", "score"]]
      iex> context = %{"score" => 85}
      iex> Predicator.evaluate(instructions, context)
      {:ok, 85}

  ## Instruction Format

  Instructions are lists where:
  - First element is the operation name (string)
  - Remaining elements are operation arguments

  The full opcode set is specified in [`docs/isa.md`](../docs/isa.md).

  ## Context

  The context is a map containing variable bindings. Both string and atom keys
  are supported for flexibility:

      %{"score" => 85, "name" => "Alice"}
      %{score: 85, name: "Alice"}

  A bare map is merged with the builtin functions on every `evaluate/3` call -
  fine for one-off evaluation, wasteful when the same bindings are evaluated
  against repeatedly. `Predicator.Context.new/2` builds that merge once into a
  `%Predicator.Context{}`, which `evaluate/3` also accepts directly:

      iex> context = Predicator.Context.new(%{"score" => 85})
      iex> Predicator.evaluate("score > 80", context)
      {:ok, true}
      iex> context = Predicator.Context.bind(context, "score", 90)
      iex> Predicator.evaluate("score > 80", context)
      {:ok, true}

  A context also carries the unbound-variable policy. By default a load of an
  unbound root pushes the `:undefined` sentinel, which three-valued logic can
  absorb into a defined result; under `on_unbound: :error` the load fails
  instead, naming the variable:

      iex> context = Predicator.Context.new(%{}, on_unbound: :error)
      iex> {:error, error} = Predicator.evaluate("missing OR true", context)
      iex> error.variable
      "missing"

  The same option works on a bare map, which `evaluate/3` routes through
  `Predicator.Context.new/2`:

      iex> Predicator.evaluate("missing OR true", %{})
      {:ok, true}
      iex> {:error, error} = Predicator.evaluate("missing OR true", %{}, on_unbound: :error)
      iex> error.variable
      "missing"

  ## Architecture

  Predicator uses a stack-based evaluation model:
  1. Instructions are processed sequentially
  2. Each instruction manipulates a stack
  3. The final result is the top value on the stack when execution completes
  """

  alias Predicator.{
    Compiled,
    Compiler,
    Context,
    ContextLocation,
    Errors,
    Evaluator,
    Instructions,
    Lexer,
    Parser,
    Types
  }

  alias Predicator.Errors.{ParseError, TypeMismatchError, UndefinedVariableError}

  @doc """
  Evaluates a predicate expression or instruction list.

  This is the main entry point for Predicator evaluation. It accepts either:
  - A string expression (e.g., "score > 85") which gets compiled automatically
  - A pre-compiled instruction list for maximum performance

  ## Parameters

  - `input` - String expression, instruction list, or a `t:Predicator.Compiled.t/0`
    from `compile_with_positions/1` or `compile_with_spans/1`, whose table is
    threaded automatically
  - `context` - Optional context map with variable bindings (default: `%{}`)
  - `opts` - Optional keyword list of options:
    - `:functions` - Map of custom functions to make available during evaluation
    - `:positions` - the table from `compiled.positions`, for a caller passing a
      **bare** instruction list, used to populate `:position` (and `:span`) on
      runtime errors. String input threads its own table automatically; an
      instruction-list caller who omits this sees `position: nil`. Passing it
      alongside a `%Compiled{}` raises `ArgumentError`. `evaluate/3` compiles
      no `store`, so the companion `:segment_positions` table (see
      `execute/3`) is always empty here and has no observable effect.
    - `:spans` - when `true`, string input compiles with spans instead of point
      positions, so runtime errors carry `:span` and `:position` names the
      span's start. Ignored for instruction-list input, which has no source;
      such a caller passes `compile_with_spans/1`'s struct, or `positions:`
      from `compiled.positions`.

  ## Returns

  - `{:ok, result}` on successful evaluation
  - `{:error, error_struct}` if parsing or execution fails

  ## Error Types

  - `Predicator.Errors.TypeMismatchError` - Type mismatch in operation
  - `Predicator.Errors.UndefinedVariableError` - Variable not found in context
  - `Predicator.Errors.EvaluationError` - General evaluation error (division by zero, etc.)
  - `Predicator.Errors.ParseError` - Expression parsing error

  ## Examples

      # Simple expressions
      iex> Predicator.evaluate("true")
      {:ok, true}

      iex> Predicator.evaluate("2 + 3")
      {:ok, 5}

      # With context
      iex> Predicator.evaluate("score > 85", %{"score" => 90})
      {:ok, true}

      # With custom functions
      iex> custom_functions = %{"double" => {1, fn [n], _context -> {:ok, n * 2} end}}
      iex> Predicator.evaluate("double(21)", %{}, functions: custom_functions)
      {:ok, 42}

      # Pre-compiled instruction lists
      iex> Predicator.evaluate([["lit", 42]])
      {:ok, 42}

      # Type coercion with + operator (string concatenation)
      iex> Predicator.evaluate("score + 'hello'", %{"score" => 5})
      {:ok, "5hello"}

      # Error handling for incompatible types
      iex> {:error, error} = Predicator.evaluate("score * true", %{"score" => 5})
      iex> String.contains?(error.message, "multiply requires")
      true
  """
  @spec evaluate(
          binary() | Types.instruction_list() | Compiled.t(),
          Types.context() | Context.t(),
          keyword()
        ) :: {:ok, Types.value()} | {:error, struct()}
  def evaluate(input, context \\ %{}, opts \\ [])

  def evaluate(%Compiled{} = compiled, context, opts) when is_map(context) do
    opts = reject_positions_option!(opts)

    evaluate_instructions(
      compiled.instructions,
      context,
      opts
      |> Keyword.put(:positions, compiled.positions)
      |> Keyword.put(:segment_positions, compiled.segment_positions)
    )
  end

  def evaluate(expression, context, opts) when is_binary(expression) and is_map(context) do
    case Lexer.tokenize(expression) do
      {:ok, tokens} ->
        case Parser.parse(tokens, opts) do
          {:ok, ast} ->
            {instructions, positions} = Compiler.to_instructions_with_positions(ast)

            evaluate_instructions(
              instructions,
              context,
              opts
              |> Keyword.put(:positions, positions)
              |> Keyword.put(:segment_positions, %{})
            )

          {:error, message, line, column} ->
            {:error, ParseError.new(message, line, column)}
        end

      {:error, message, line, column} ->
        {:error, ParseError.new(message, line, column)}
    end
  end

  def evaluate(instructions, context, opts) when is_list(instructions) and is_map(context) do
    evaluate_instructions(instructions, context, opts)
  end

  # Helper function to evaluate instructions and convert errors to new format
  defp evaluate_instructions(instructions, %Context{} = context, opts) do
    evaluator = %Evaluator{
      instructions: instructions,
      context: context.data,
      functions: context.functions,
      positions: Keyword.get(opts, :positions, %{}),
      segment_positions: Keyword.get(opts, :segment_positions, %{}),
      on_unbound: context.on_unbound
    }

    case Evaluator.run_prepared(evaluator) do
      {:error, error_struct, final_evaluator} when is_struct(error_struct) ->
        {:error, unbound_or_type_mismatch(error_struct, final_evaluator)}

      {:ok, :undefined, final_evaluator} ->
        undefined_result(final_evaluator)

      {:ok, result, _final_evaluator} ->
        {:ok, result}
    end
  end

  defp evaluate_instructions(instructions, context, opts) when is_map(context) do
    evaluate_instructions(instructions, Context.new(context, opts), opts)
  end

  # A %Compiled{} already carries its tables, so an explicit :positions or
  # :segment_positions option alongside it is a contradiction with no correct
  # resolution: whichever side won, the caller would not be told the other was
  # discarded - which is the silent loss the envelope exists to remove
  # (ADR-0009). This is a caller bug written in the host's own source, not
  # something a predicate author can reach, so it raises rather than becoming
  # a value; ADR-0004's "errors are values" is about predicate-derived
  # failure. Predicator.Context.new/2 draws the same line for a malformed
  # :on_unbound.
  @spec reject_positions_option!(keyword()) :: keyword()
  defp reject_positions_option!(opts) do
    opts
    |> reject_positions_option!(Keyword.has_key?(opts, :positions))
    |> reject_segment_positions_option!(Keyword.has_key?(opts, :segment_positions))
  end

  @spec reject_positions_option!(keyword(), boolean()) :: keyword()
  defp reject_positions_option!(opts, false), do: opts

  defp reject_positions_option!(_opts, true) do
    raise ArgumentError,
          "Predicator.evaluate/3 was given a %Predicator.Compiled{}, which already " <>
            "carries its own position table, and an explicit :positions option. Pass " <>
            "one or the other: drop the option to use compiled.positions, or pass " <>
            "compiled.instructions with the option."
  end

  @spec reject_segment_positions_option!(keyword(), boolean()) :: keyword()
  defp reject_segment_positions_option!(opts, false), do: opts

  defp reject_segment_positions_option!(_opts, true) do
    raise ArgumentError,
          "Predicator.evaluate/3 was given a %Predicator.Compiled{}, which already " <>
            "carries its own segment-position table, and an explicit :segment_positions " <>
            "option. Pass one or the other: drop the option to use " <>
            "compiled.segment_positions, or pass compiled.instructions with the option."
  end

  @doc """
  Evaluates a predicate expression or instruction list, raising on errors.

  Similar to `evaluate/3` but raises an exception for error results instead
  of returning error tuples. Follows the Elixir convention of bang functions.

  ## Examples

      iex> Predicator.evaluate!("score > 85", %{"score" => 90})
      true

      iex> Predicator.evaluate!([["lit", 42]])
      42

      # With custom functions
      iex> custom_functions = %{"double" => {1, fn [n], _context -> {:ok, n * 2} end}}
      iex> Predicator.evaluate!("double(21)", %{}, functions: custom_functions)
      42

      # A pre-compiled %Predicator.Compiled{}
      iex> {:ok, compiled} = Predicator.compile_with_positions("score > 85")
      iex> Predicator.evaluate!(compiled, %{"score" => 90})
      true

      # This would raise an exception:
      # Predicator.evaluate!("score >", %{})
  """
  @spec evaluate!(
          binary() | Types.instruction_list() | Compiled.t(),
          Types.context(),
          keyword()
        ) :: Types.value()
  def evaluate!(input, context \\ %{}, opts \\ []) do
    case evaluate(input, context, opts) do
      {:ok, result} -> result
      {:error, error_struct} -> raise "Evaluation failed: #{error_struct.message}"
    end
  end

  @doc """
  Runs a statement program - a source string, an instruction list, or a
  `t:Predicator.Compiled.t/0` - and returns the resulting context.

  This is statement mode's entry point (`docs/isa.md` section 2), the sibling
  of `evaluate/3` for the `{:program, ...}` / `{:assignment, ...}` grammar
  `parse_program/2` produces. Where `evaluate/3` returns the value an
  expression reduces to, `execute/3` returns the **context** a program's
  writes produced - a program halts with an empty stack by design, so there
  is no expression result to return.

  ## Parameters

  Same shape as `evaluate/3`:

  - `program_or_source` - a source string (parsed with `parse_program/2`, not
    `parse/2`), a pre-compiled instruction list, or a `t:Predicator.Compiled.t/0`
    from `compile_program_with_positions/1`
  - `context` - a bare map or a `t:Predicator.Context.t/0` (default `%{}`)
  - `opts` - same options `evaluate/3` accepts (`:functions`, `:positions`,
    `:segment_positions`, `:on_unbound`); `:positions` or `:segment_positions`
    alongside a `%Compiled{}` raises `ArgumentError`, same as `evaluate/3`.
    Unlike `evaluate/3`, a program can compile a `store`, so
    `:segment_positions` - the table from `compiled.segment_positions` - can
    change a store failure's reported position here; see
    `Predicator.Evaluator.evaluate/3`'s option list.

  ## Returns

  - `{:ok, context}` - every statement ran; `context.data` holds every write
  - `{:error, error_struct, context}` - execution stopped at the failing
    statement. `context` is the context **as of the last successfully
    completed statement** - every earlier write survives, the failing
    statement's write does not happen, and no later statement runs. Handing
    back this partial context costs nothing (contexts are immutable) and
    commit-or-discard is left to the caller: a caller wanting all-or-nothing
    drops the third element and keeps the context it already had.

        case Predicator.execute(program, ctx) do
          {:ok, ctx} -> ctx
          {:error, _error, _partial} -> ctx    # all-or-nothing is a caller policy
        end

  A caller who also wants the program's last expression statement's value
  calls `execute_value/3` instead.

  ## Examples

      iex> {:ok, ctx} = Predicator.execute("x = 1; y = x + 2", %{})
      iex> ctx.data
      %{"x" => 1, "y" => 3}

      iex> {:error, %Predicator.Errors.EvaluationError{reason: "not_a_container"}, ctx} =
      ...>   Predicator.execute("a = 1; a.b = 2; c = 3", %{})
      iex> ctx.data
      %{"a" => 1}
  """
  @spec execute(
          binary() | Types.instruction_list() | Compiled.t(),
          Types.context() | Context.t(),
          keyword()
        ) :: {:ok, Context.t()} | {:error, struct(), Context.t()}
  def execute(program_or_source, context \\ %{}, opts \\ [])

  def execute(program_or_source, context, opts) when is_map(context) do
    program_or_source
    |> execute_value(context, opts)
    |> drop_last_value()
  end

  @doc """
  Runs a statement program - a source string, an instruction list, or a
  `t:Predicator.Compiled.t/0` - and returns the resulting context plus the
  value the program's last expression statement produced.

  This is `execute/3` plus the last expression statement's value; call
  `execute/3` instead when the value is not wanted.

  The value is **the value of the program's last expression statement**:
  `:undefined` when the program has none (a program of assignments only), and
  `:undefined` for a hand-built instruction list that pops nothing. See
  `Predicator.Evaluator.last_value/1` for the exact definition, which this
  function projects.

  ## Parameters

  Same as `execute/3`: `program_or_source`, `context` (default `%{}`), and
  `opts` (default `[]`), including `:positions` or `:segment_positions`
  alongside a `%Compiled{}` raising `ArgumentError`.

  ## Returns

  - `{:ok, value, context}` - every statement ran; `value` is the last
    expression statement's value (or `:undefined`), `context.data` holds every
    write
  - `{:error, error_struct, context}` - **identical to `execute/3`'s error
    arm**: no value is reported for a run that stopped early. A caller who
    wants the partial run's last value has `Evaluator.run_state/1` and
    `Evaluator.last_value/1` directly.

  This is a host-API convenience, not an ISA guarantee - see
  `docs/isa.md` section 2's host-convenience paragraph. A sibling
  implementation need not offer it.

  ## Examples

      iex> {:ok, value, ctx} = Predicator.execute_value("x = 2; x * 10", %{})
      iex> value
      20
      iex> ctx.data
      %{"x" => 2}

      iex> {:ok, value, _ctx} = Predicator.execute_value("x = 1", %{})
      iex> value
      :undefined

      iex> {:error, %Predicator.Errors.EvaluationError{reason: "not_a_container"}, ctx} =
      ...>   Predicator.execute_value("a = 1; a.b = 2; c = 3", %{})
      iex> ctx.data
      %{"a" => 1}
  """
  @spec execute_value(
          binary() | Types.instruction_list() | Compiled.t(),
          Types.context() | Context.t(),
          keyword()
        ) :: {:ok, Types.value(), Context.t()} | {:error, struct(), Context.t()}
  def execute_value(program_or_source, context \\ %{}, opts \\ [])

  def execute_value(%Compiled{} = compiled, context, opts) when is_map(context) do
    opts = reject_positions_option!(opts)

    execute_instructions(
      compiled.instructions,
      context,
      opts
      |> Keyword.put(:positions, compiled.positions)
      |> Keyword.put(:segment_positions, compiled.segment_positions)
    )
  end

  def execute_value(source, context, opts) when is_binary(source) and is_map(context) do
    case Lexer.tokenize(source) do
      {:ok, tokens} ->
        case Parser.parse_program(tokens, opts) do
          {:ok, ast} ->
            {instructions, positions, segment_positions} =
              Compiler.to_instructions_with_segment_positions(ast)

            execute_instructions(
              instructions,
              context,
              opts
              |> Keyword.put(:positions, positions)
              |> Keyword.put(:segment_positions, segment_positions)
            )

          {:error, message, line, column} ->
            {:error, ParseError.new(message, line, column), normalize_context(context, opts)}
        end

      {:error, message, line, column} ->
        {:error, ParseError.new(message, line, column), normalize_context(context, opts)}
    end
  end

  def execute_value(instructions, context, opts) when is_list(instructions) and is_map(context) do
    execute_instructions(instructions, context, opts)
  end

  # A parse failure never built an evaluator, so there is no run to have
  # written anything - the "partial context" on this path is just the input,
  # normalized the same way a successful run's would be.
  @spec normalize_context(Types.context() | Context.t(), keyword()) :: Context.t()
  defp normalize_context(%Context{} = context, _opts), do: context
  defp normalize_context(context, opts) when is_map(context), do: Context.new(context, opts)

  # Runs a statement program and returns the final context plus the value the
  # program's last ["pop"] discarded. execute/3 drops the value via
  # drop_last_value/1; execute_value/3 keeps it (px-tbv.10). Errors keep
  # evaluate/3's shapes and the partial context on both paths.
  @spec execute_instructions(Types.instruction_list(), Context.t() | Types.context(), keyword()) ::
          {:ok, Types.value(), Context.t()} | {:error, struct(), Context.t()}
  defp execute_instructions(instructions, %Context{} = context, opts) do
    evaluator = %Evaluator{
      instructions: instructions,
      context: context.data,
      functions: context.functions,
      positions: Keyword.get(opts, :positions, %{}),
      segment_positions: Keyword.get(opts, :segment_positions, %{}),
      on_unbound: context.on_unbound
    }

    case Evaluator.run_state(evaluator) do
      {:ok, final} ->
        {:ok, Evaluator.last_value(final), %{context | data: final.context}}

      {:error, error_struct, final} ->
        {:error, unbound_or_type_mismatch(error_struct, final), %{context | data: final.context}}
    end
  end

  defp execute_instructions(instructions, context, opts) when is_map(context) do
    execute_instructions(instructions, Context.new(context, opts), opts)
  end

  # Narrows execute_instructions/3's richer {:ok, value, context} shape down
  # to execute/3's documented {:ok, context} - the value is not part of
  # execute/3's contract (px-tbv.10). The error arm is already the shape
  # execute/3 returns, so it passes through unchanged.
  @spec drop_last_value({:ok, Types.value(), Context.t()} | {:error, struct(), Context.t()}) ::
          {:ok, Context.t()} | {:error, struct(), Context.t()}
  defp drop_last_value({:ok, _value, context}), do: {:ok, context}
  defp drop_last_value({:error, _error, _context} = error), do: error

  # An :undefined result is ambiguous on its own: it's either a genuinely
  # unbound root variable or a value that legitimately evaluates to
  # :undefined (a missing nested path, an out-of-bounds index, a type
  # mismatch). The evaluator records the unbound loads it actually executed,
  # so ask it rather than scanning the program - a load the short-circuit
  # jumps skipped is present in the instruction list but was never read, and
  # naming it would report a variable the author was entitled to leave
  # unbound (px-8um.8).
  @spec undefined_result(Evaluator.t()) :: {:ok, :undefined} | {:error, struct()}
  defp undefined_result(evaluator) do
    case Evaluator.unbound_loads_with_locations(evaluator) do
      [] -> {:ok, :undefined}
      [unbound_load | _rest] -> {:error, undefined_variable_error(unbound_load)}
    end
  end

  # An opcode that *rejects* an :undefined operand - not, unary_minus,
  # unary_bang, the five arithmetic opcodes, the legacy ["and"]/["or"] - errors
  # before evaluation ever produces an :undefined result, so undefined_result/1
  # never sees it and the caller gets a TypeMismatchError naming no variable at
  # all. When that operand came from a root the run loaded and did not find
  # bound, report the variable instead: the same answer "unbound > 5" already
  # gives, for the same cause (px-8um.7).
  #
  # Gated on both halves. A TypeMismatchError with no :undefined operand is an
  # ordinary type error ("name" * 5) and passes through; an :undefined operand
  # with no unbound load came from bound data (%{"b" => :undefined}) or a
  # missing nested path (user.nope), which is a genuine type mismatch on data
  # the caller supplied, and also passes through.
  #
  # The rewritten error is positioned at the variable's own load, not at the
  # rejecting operator: the operator's position went out with the
  # TypeMismatchError this replaces, along with the struct it was on. That is
  # the right trade - a caller's editor wants the caret on the variable, not
  # on the `+` or `not` that merely noticed it was undefined (px-1e1).
  @spec unbound_or_type_mismatch(struct(), Evaluator.t()) :: struct()
  defp unbound_or_type_mismatch(%TypeMismatchError{got: got} = error, evaluator) do
    with true <- undefined_operand?(got),
         [unbound_load | _rest] <- Evaluator.unbound_loads_with_locations(evaluator) do
      undefined_variable_error(unbound_load)
    else
      _no_rewrite -> error
    end
  end

  defp unbound_or_type_mismatch(error, _evaluator), do: error

  # `got` is a single type for a unary operation and a {left, right} tuple for
  # a binary one; either position may be the rejected :undefined operand.
  @spec undefined_operand?(term()) :: boolean()
  defp undefined_operand?(:undefined), do: true
  defp undefined_operand?({:undefined, _right}), do: true
  defp undefined_operand?({_left, :undefined}), do: true
  defp undefined_operand?(_got), do: false

  # The location is the raw positions-table entry the evaluator recorded at the
  # load - nil, a point position, or a span. Errors.put_position/2 discriminates
  # all three, setting :span as well when it is handed one, so nothing here has
  # to know which mode the program was compiled in.
  @spec undefined_variable_error(Evaluator.unbound_load()) :: UndefinedVariableError.t()
  defp undefined_variable_error({variable_name, location}) do
    variable_name
    |> UndefinedVariableError.new()
    |> Errors.put_position(location)
  end

  @doc """
  Returns the ISA version this build emits and can run.

  ISA versions are integers, independent of this library's semantic version
  (ADR-0003). Compare it against `Predicator.Instructions.required_isa/1`
  before running a stored instruction list, so a version mismatch is caught
  up front instead of failing partway through evaluation. See
  [`docs/isa.md`](../docs/isa.md) for the full versioning scheme.

  ## Examples

      iex> Predicator.isa_version()
      4
  """
  @spec isa_version() :: pos_integer()
  defdelegate isa_version(), to: Instructions

  @doc """
  Compiles a string expression to instruction list.

  This function allows you to pre-compile expressions for maximum performance
  when evaluating the same expression multiple times with different contexts.

  ## Parameters

  - `expression` - String expression to compile

  ## Returns

  - `{:ok, instructions}` - Successfully compiled instructions
  - `{:error, message}` - Parse error with details

  ## Examples

      iex> {:ok, instructions} = Predicator.compile("score > 85")
      iex> instructions
      [["load", "score"], ["lit", 85], ["compare", "GT"]]

      iex> Predicator.compile("score >")
      {:error, "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input at line 1, column 8"}
  """
  @spec compile(binary()) :: {:ok, Types.instruction_list()} | {:error, binary()}
  def compile(expression) when is_binary(expression) do
    case parse(expression) do
      {:ok, ast} ->
        instructions = Compiler.to_instructions(ast)
        {:ok, instructions}

      {:error, message, line, column} ->
        {:error, "#{message} at line #{line}, column #{column}"}
    end
  end

  @doc """
  Compiles a string expression to a `t:Predicator.Compiled.t/0` - the
  instruction list plus a source-position side table, as one value.

  `compiled.instructions` is identical to `compile/1`'s output;
  `compiled.positions` maps each instruction's 0-based index to the
  `{line, column}` of the AST node that emitted it. Pass the struct straight
  to `evaluate/3`, which threads the table itself.

  Store `compiled.instructions`, not the struct - see `Predicator.Compiled`.

  ## Examples

      iex> {:ok, compiled} = Predicator.compile_with_positions("score > 85")
      iex> compiled.instructions
      [["load", "score"], ["lit", 85], ["compare", "GT"]]
      iex> compiled.positions
      %{0 => {1, 1}, 1 => {1, 9}, 2 => {1, 7}}
  """
  @spec compile_with_positions(binary()) :: {:ok, Compiled.t()} | {:error, binary()}
  def compile_with_positions(expression) when is_binary(expression) do
    expression |> parse() |> build_compiled_result()
  end

  @doc """
  Compiles a string expression to a `t:Predicator.Compiled.t/0` - the
  instruction list plus a source-span side table, as one value.

  `compiled.instructions` is identical to `compile/1`'s output;
  `compiled.positions` maps each instruction's 0-based index to the
  `t:Predicator.Types.span/0` of the AST node that emitted it. Pass the struct
  straight to `evaluate/3`, which threads the table itself.

  Store `compiled.instructions`, not the struct - see `Predicator.Compiled`.

  ## Examples

      iex> {:ok, compiled} = Predicator.compile_with_spans("score > 85")
      iex> compiled.instructions
      [["load", "score"], ["lit", 85], ["compare", "GT"]]
      iex> compiled.positions
      %{0 => {{1, 1}, {1, 6}}, 1 => {{1, 9}, {1, 11}}, 2 => {{1, 1}, {1, 11}}}
  """
  @spec compile_with_spans(binary()) :: {:ok, Compiled.t()} | {:error, binary()}
  def compile_with_spans(expression) when is_binary(expression) do
    expression |> parse(spans: true) |> build_compiled_result()
  end

  @doc """
  Compiles a statement-sequence string to an instruction list.

  The program-shaped echo of `compile/1`: parses with `parse_program/2`
  instead of `parse/2`, then compiles the resulting `t:Predicator.Parser.program/0`
  with `Compiler.to_instructions/2`, which already accepts one. Returns the
  same `{:error, binary()}` shape `compile/1` does - not `parse_program/2`'s
  raw 4-tuple.

  ## Examples

      iex> {:ok, instructions} = Predicator.compile_program("x = 1; x + 1")
      iex> instructions
      [["lit", "x"], ["lit", 1], ["store", 1], ["load", "x"], ["lit", 1], ["add"], ["pop"]]

      iex> Predicator.compile_program("x =")
      {:error, "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input at line 1, column 4"}
  """
  @spec compile_program(binary()) :: {:ok, Types.instruction_list()} | {:error, binary()}
  def compile_program(source) when is_binary(source) do
    case parse_program(source) do
      {:ok, ast} ->
        instructions = Compiler.to_instructions(ast)
        {:ok, instructions}

      {:error, message, line, column} ->
        {:error, "#{message} at line #{line}, column #{column}"}
    end
  end

  @doc """
  Compiles a statement-sequence string to a `t:Predicator.Compiled.t/0` - the
  instruction list plus a source-position side table, as one value.

  The program-shaped echo of `compile_with_positions/1`. Pass the struct
  straight to `execute/3`, which threads the table itself.

  ## Examples

      iex> {:ok, compiled} = Predicator.compile_program_with_positions("x = 1")
      iex> compiled.instructions
      [["lit", "x"], ["lit", 1], ["store", 1]]
  """
  @spec compile_program_with_positions(binary()) :: {:ok, Compiled.t()} | {:error, binary()}
  def compile_program_with_positions(source) when is_binary(source) do
    source |> parse_program() |> build_compiled_result()
  end

  # Shared by compile_with_positions/1, compile_with_spans/1, and
  # compile_program_with_positions/1: each differs only in how it parses (an
  # expression vs a program, point positions vs spans), never in how the
  # parse result becomes a %Compiled{} or a binary error.
  @spec build_compiled_result(
          {:ok, Parser.ast() | Parser.program()}
          | {:error, binary(), pos_integer(), pos_integer()}
        ) :: {:ok, Compiled.t()} | {:error, binary()}
  defp build_compiled_result({:ok, ast}) do
    {instructions, positions, segment_positions} =
      Compiler.to_instructions_with_segment_positions(ast)

    {:ok, Compiled.new(instructions, positions, segment_positions)}
  end

  defp build_compiled_result({:error, message, line, column}) do
    {:error, "#{message} at line #{line}, column #{column}"}
  end

  @doc """
  Parses an expression string into an Abstract Syntax Tree.

  Every node carries a trailing `{line, column}` source position. Pass
  `spans: true` for a `t:Predicator.Types.span/0` in that slot instead - the
  source text the node covers, which is what a diagnostic underlines.

  ## Examples

      iex> Predicator.parse("score > 85")
      {:ok, {:comparison, :gt, {:identifier, "score", {1, 1}}, {:literal, 85, {1, 9}}, {1, 7}}}

      iex> Predicator.parse("score > 85", spans: true)
      {:ok, {:comparison, :gt, {:identifier, "score", {{1, 1}, {1, 6}}}, {:literal, 85, {{1, 9}, {1, 11}}}, {{1, 1}, {1, 11}}}}
  """
  @spec parse(binary(), keyword()) ::
          {:ok, Parser.ast()} | {:error, binary(), pos_integer(), pos_integer()}
  def parse(expression, opts \\ []) when is_binary(expression) do
    case Lexer.tokenize(expression) do
      {:ok, tokens} -> Parser.parse(tokens, opts)
      {:error, message, line, column} -> {:error, message, line, column}
    end
  end

  @doc """
  Parses a statement-sequence string into a `t:Predicator.Parser.program/0`.

  Implements `program := statement (";" statement)* [";"]`, where a statement
  is either an assignment (`location "=" expression`) or an ordinary
  expression. This is a separate entry point from `parse/2`, not an option on
  it: `parse/2` never returns a program, and `parse_program/2` always returns
  one, even for a single statement.

  ## Examples

      iex> Predicator.parse_program("a = 1; b = a + 1")
      {:ok,
       {:program,
        [
          {:assignment, {:identifier, "a", {1, 1}}, {:literal, 1, {1, 5}}, {1, 3}},
          {:assignment, {:identifier, "b", {1, 8}},
           {:arithmetic, :add, {:identifier, "a", {1, 12}}, {:literal, 1, {1, 16}}, {1, 14}},
           {1, 10}}
        ], {1, 1}}}

      iex> Predicator.parse_program("42 = 1")
      {:error, "Left side of '=' must be an assignable location - an identifier, a property access, or a bracket access.", 1, 4}
  """
  @spec parse_program(binary(), keyword()) :: Parser.program_result()
  def parse_program(source, opts \\ []) when is_binary(source) do
    case Lexer.tokenize(source) do
      {:ok, tokens} -> Parser.parse_program(tokens, opts)
      {:error, message, line, column} -> {:error, message, line, column}
    end
  end

  @doc """
  Converts an AST back to a string representation.

  This function takes an Abstract Syntax Tree and generates a readable string
  representation. This is useful for debugging, displaying expressions to users,
  and documentation purposes.

  ## Parameters

  - `ast` - The Abstract Syntax Tree to convert - a bare expression, or a
    `t:Predicator.Parser.program/0`, which renders as its statements joined by
    `"; "`
  - `opts` - Optional formatting options:
    - `:parentheses` - `:minimal` (default) | `:explicit` | `:none`
    - `:spacing` - `:normal` (default) | `:compact` | `:verbose`

  ## Returns

  String representation of the AST

  ## Examples

      iex> ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      iex> Predicator.decompile(ast)
      "score > 85"

      iex> ast = {:literal, 42, nil}
      iex> Predicator.decompile(ast)
      "42"

      iex> ast = {:comparison, :eq, {:identifier, "active", nil}, {:literal, true, nil}, nil}
      iex> Predicator.decompile(ast, parentheses: :explicit, spacing: :verbose)
      "(active  ==  true)"
  """
  @spec decompile(Parser.ast() | Parser.program(), keyword()) :: binary()
  def decompile(ast, opts \\ []) do
    Compiler.to_string(ast, opts)
  end

  @doc """
  Compiles a string expression to instruction list, raising on errors.

  Similar to `compile/1` but raises an exception for parse errors.

  ## Examples

      iex> Predicator.compile!("score > 85")
      [["load", "score"], ["lit", 85], ["compare", "GT"]]
  """
  @spec compile!(binary()) :: Types.instruction_list()
  def compile!(expression) when is_binary(expression) do
    case compile(expression) do
      {:ok, instructions} -> instructions
      {:error, reason} -> raise "Compilation failed: #{reason}"
    end
  end

  @doc """
  Creates a new evaluator state for low-level instruction processing.

  This function is useful when you need fine-grained control over the
  evaluation process or want to inspect the evaluator state.

  ## Parameters

  - `instructions` - List of instructions to prepare for execution
  - `context` - Optional context map with variable bindings (default: `%{}`)

  ## Returns

  An `%Predicator.Evaluator{}` struct ready for execution.

  ## Examples

      iex> evaluator = Predicator.evaluator([["lit", 42]])
      iex> evaluator.instructions
      [["lit", 42]]

      iex> evaluator = Predicator.evaluator([["load", "x"]], %{"x" => 10})
      iex> evaluator.context
      %{"x" => 10}
  """
  @spec evaluator(Types.instruction_list(), Types.context()) :: Evaluator.t()
  def evaluator(instructions, context \\ %{}) when is_list(instructions) and is_map(context) do
    %Evaluator{
      instructions: instructions,
      context: context
    }
  end

  @doc """
  Runs an evaluator until completion.

  This provides direct access to the low-level evaluator API for cases
  where you need more control than the `execute/2` function provides.

  ## Parameters

  - `evaluator` - An `%Predicator.Evaluator{}` struct

  ## Returns

  - `{:ok, final_evaluator_state}` on success
  - `{:error, reason}` on failure

  ## Examples

      iex> evaluator = Predicator.evaluator([["lit", 42]])
      iex> {:ok, final_state} = Predicator.run_evaluator(evaluator)
      iex> final_state.stack
      [42]
  """
  @spec run_evaluator(Evaluator.t()) :: {:ok, Evaluator.t()} | {:error, term()}
  def run_evaluator(%Evaluator{} = evaluator) do
    Evaluator.run(evaluator)
  end

  @doc """
  Resolves a location path for assignment operations in SCXML datamodel expressions.

  Takes an expression string and returns a location path that can be used for
  assignment operations. Validates that the expression represents an assignable
  location (l-value) rather than a computed value.

  This function is specifically designed for SCXML `<assign location="...">` operations
  where the location attribute must specify where to assign a value in the datamodel.

  ## Location Path Format

  Location paths are returned as lists of keys/indices that represent the path
  to a specific location in the context data structure:

  - `["user"]` - top-level variable `user`
  - `["user", "name"]` - property access `user.name`
  - `["items", 0]` - array access `items[0]`
  - `["user", "profile", "settings", "theme"]` - nested `user.profile.settings.theme`

  ## Assignable vs Non-Assignable

  **Assignable (valid locations):**
  - Simple identifiers: `user`
  - Property access: `user.name`, `obj.prop`
  - Bracket access: `items[0]`, `obj["key"]`
  - Mixed notation: `user.items[0].name`

  **Non-Assignable (invalid locations):**
  - Literals: `42`, `"string"`, `true`
  - Function calls: `len(items)`, `upper(name)`
  - Arithmetic expressions: `user.age + 1`
  - Any computed values

  ## Parameters

  - `expression` - The location expression string to resolve
  - `context` - The evaluation context (used for resolving variable keys)
  - `opts` - Options (currently unused, reserved for future extensions)

  ## Examples

      # Simple identifier
      iex> Predicator.context_location("user", %{"user" => %{"name" => "John"}})
      {:ok, ["user"]}

      # Property access
      iex> Predicator.context_location("user.name", %{"user" => %{"name" => "John"}})
      {:ok, ["user", "name"]}

      # Bracket access with literal key
      iex> Predicator.context_location("items[0]", %{"items" => [1, 2, 3]})
      {:ok, ["items", 0]}

      # Bracket access with string key
      iex> Predicator.context_location("user['profile']", %{"user" => %{"profile" => %{}}})
      {:ok, ["user", "profile"]}

      # Mixed notation
      iex> Predicator.context_location("data.users[0]['name']", %{"data" => %{"users" => [%{"name" => "Alice"}]}})
      {:ok, ["data", "users", 0, "name"]}

      # Variable as bracket key
      iex> Predicator.context_location("items[index]", %{"items" => [1, 2, 3], "index" => 1})
      {:ok, ["items", 1]}

      # Error: cannot assign to literal
      iex> {:error, %Predicator.Errors.LocationError{type: :not_assignable}} =
      ...>   Predicator.context_location("42", %{})

      # Error: cannot assign to function call
      iex> {:error, %Predicator.Errors.LocationError{type: :not_assignable}} =
      ...>   Predicator.context_location("len(items)", %{"items" => [1, 2, 3]})

      # Error: cannot assign to computed expression
      iex> {:error, %Predicator.Errors.LocationError{type: :not_assignable}} =
      ...>   Predicator.context_location("user.age + 1", %{"user" => %{"age" => 30}})

  ## SCXML Usage Example

      # In an SCXML state machine
      location_expr = "user.profile.settings['theme']"

      case Predicator.context_location(location_expr, datamodel_context) do
        {:ok, path} ->
          # Use path for assignment: ["user", "profile", "settings", "theme"]
          update_datamodel_at_path(datamodel, path, new_value)

        {:error, %Predicator.Errors.LocationError{} = error} ->
          # Handle invalid assignment target
          {:error, "Invalid assignment location: \#{error.message}"}
      end

  """
  @spec context_location(binary(), Types.context(), keyword()) ::
          {:ok, ContextLocation.location_path()} | {:error, struct()}
  def context_location(expression, context \\ %{}, _opts \\ [])
      when is_binary(expression) and is_map(context) do
    ContextLocation.resolve_expression(expression, context)
  end

  @doc """
  Assigns `value` at the location `expression` names within `context`.

  Resolves the location expression the same way `context_location/3` does, then
  writes through `Predicator.ContextLocation.put/3`, creating any missing
  intermediate maps and lists. See `Predicator.ContextLocation.put/3` for the
  full auto-vivification and collision rules.

  The expression is resolved against the *pre-assignment* context, which matches
  SCXML: a variable bracket key such as `items[index]` reads `index` as it stands
  before the write.

  > #### Argument order {: .info}
  >
  > `context` comes first because this function *transforms* a context and
  > returns a new one, which makes it pipeline-friendly, whereas
  > `context_location/3` merely inspects one.

  ## Parameters

  - `context` - The context map to write into
  - `expression` - The location expression naming where to write
  - `value` - The value to write
  - `opts` - Reserved for future options

  ## Returns

  - `{:ok, context}` - The updated context
  - `{:error, %Predicator.Errors.LocationError{}}` - The expression is not an
    assignable location, or the write collided with existing data
  - `{:error, %Predicator.Errors.ParseError{}}` - The expression did not parse

  ## Examples

      iex> Predicator.context_assign(%{}, "user.profile.name", "Ada")
      {:ok, %{"user" => %{"profile" => %{"name" => "Ada"}}}}

      iex> Predicator.context_assign(%{"items" => [1, 2, 3]}, "items[1]", "x")
      {:ok, %{"items" => [1, "x", 3]}}

      iex> {:error, error} = Predicator.context_assign(%{}, "len(items)", 1)
      iex> error.type
      :not_assignable

  """
  @spec context_assign(Types.context(), binary(), term(), keyword()) ::
          {:ok, Types.context()} | {:error, struct()}
  def context_assign(context, expression, value, opts \\ [])
      when is_map(context) and is_binary(expression) do
    case context_location(expression, context, opts) do
      {:ok, path} -> ContextLocation.put(context, path, value)
      {:error, _error} = error -> error
    end
  end
end
