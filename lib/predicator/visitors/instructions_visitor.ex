defmodule Predicator.Visitors.InstructionsVisitor do
  @moduledoc """
  Visitor that converts AST nodes to stack machine instructions.

  This visitor implements post-order traversal to generate instruction lists
  that can be executed by the stack-based evaluator. Instructions are generated
  in the correct order for stack-based evaluation.

  ## Source positions

  Internally the traversal pairs every instruction with the source position of
  the AST node that emitted it. `visit/2` discards those positions and returns
  the plain instruction list; `visit_with_positions/2` returns both. The
  instruction list is identical either way - positions never enter the
  instruction format itself, so cross-language interchange and stored compiled
  artifacts are unaffected (ADR-0001). The paired value is whatever the node
  carried in its trailing slot, so an AST parsed with `spans: true` yields a
  span table rather than a position table.

  Both entry points require a node with a trailing slot. A caller hand-building
  an AST supplies `nil` there, which produces no entry in the position table.

  ## Examples

      iex> ast = {:literal, 42, nil}
      iex> Predicator.Visitors.InstructionsVisitor.visit(ast, [])
      [["lit", 42]]

      iex> ast = {:identifier, "score", nil}
      iex> Predicator.Visitors.InstructionsVisitor.visit(ast, [])
      [["load", "score"]]

      iex> ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      iex> Predicator.Visitors.InstructionsVisitor.visit(ast, [])
      [["load", "score"], ["lit", 85], ["compare", "GT"]]

      iex> ast = {:logical_and, {:literal, true, nil}, {:literal, false, nil}, nil}
      iex> Predicator.Visitors.InstructionsVisitor.visit(ast, [])
      [["lit", true], ["jump_if_falsy_or_pop", 2], ["lit", false]]

      iex> ast = {:function_call, "len", [{:identifier, "name", nil}], nil}
      iex> Predicator.Visitors.InstructionsVisitor.visit(ast, [])
      [["load", "name"], ["call", "len", 1]]
  """

  @behaviour Predicator.Visitor

  alias Predicator.{Parser, Types}

  @typedoc """
  One instruction paired with the source position of the node that emitted it.
  """
  @type annotated :: {[binary() | term()], Types.position() | Types.span() | nil}

  @doc """
  Visits an AST node and returns stack machine instructions.

  Uses post-order traversal to ensure operands are pushed onto the stack
  before operators are applied.

  ## Parameters

  - `ast_node` - The AST node to convert to instructions
  - `opts` - Optional visitor options (currently unused)

  ## Returns

  List of instructions in the format `[["operation", ...args]]`
  """
  @impl Predicator.Visitor
  @spec visit(Parser.ast() | Parser.program(), keyword()) :: [[binary() | term()]]
  def visit(ast_node, opts \\ []) do
    ast_node
    |> visit_annotated(opts)
    |> Enum.map(fn {instruction, _position} -> instruction end)
  end

  @doc """
  Returns the instruction list and a side table mapping each instruction's
  0-based index to the source position of the AST node that emitted it.

  Nodes carrying a `nil` position contribute no entry, so a position-free AST
  yields an empty table. The instruction list is identical to `visit/2`'s.

  ## Examples

      iex> ast = {:comparison, :gt, {:identifier, "score", {1, 1}}, {:literal, 85, {1, 9}}, {1, 7}}
      iex> Predicator.Visitors.InstructionsVisitor.visit_with_positions(ast)
      {[["load", "score"], ["lit", 85], ["compare", "GT"]],
       %{0 => {1, 1}, 1 => {1, 9}, 2 => {1, 7}}}

      iex> Predicator.Visitors.InstructionsVisitor.visit_with_positions({:literal, 42, nil})
      {[["lit", 42]], %{}}
  """
  @spec visit_with_positions(Parser.ast() | Parser.program(), keyword()) ::
          {[[binary() | term()]], Types.position_table() | Types.span_table()}
  def visit_with_positions(ast_node, opts \\ []) do
    annotated = visit_annotated(ast_node, opts)

    positions =
      annotated
      |> Enum.with_index()
      |> Enum.flat_map(fn
        {{_instruction, nil}, _index} -> []
        {{_instruction, position}, index} -> [{index, position}]
      end)
      |> Map.new()

    {Enum.map(annotated, fn {instruction, _position} -> instruction end), positions}
  end

  # Each clause pairs the instructions the node emits *itself* with that node's
  # own position; instructions contributed by children keep the position their
  # own node gave them.
  @spec visit_annotated(Parser.ast() | Parser.program() | Parser.assignment(), keyword()) :: [
          annotated()
        ]
  defp visit_annotated(ast_node, opts)

  defp visit_annotated({:literal, value, position}, _opts) do
    [{["lit", value], position}]
  end

  defp visit_annotated({:string_literal, value, _quote_type, position}, _opts) do
    # For instruction generation, quote type doesn't matter - just treat as literal
    [{["lit", value], position}]
  end

  defp visit_annotated({:identifier, name, position}, _opts) do
    [{["load", name], position}]
  end

  defp visit_annotated({:property_access, left, property, position}, opts) do
    # Generate instructions for property access: left_object, property_name, access
    left_instructions = visit_annotated(left, opts)
    left_instructions ++ [{["access", property], position}]
  end

  defp visit_annotated({:comparison, op, left, right, position}, opts) do
    # Post-order traversal: left operand, right operand, then operator
    left_instructions = visit_annotated(left, opts)
    right_instructions = visit_annotated(right, opts)
    op_instruction = [{["compare", map_comparison_op(op)], position}]

    left_instructions ++ right_instructions ++ op_instruction
  end

  defp visit_annotated({:arithmetic, op, left, right, position}, opts) do
    # Post-order traversal: left operand, right operand, then operator
    left_instructions = visit_annotated(left, opts)
    right_instructions = visit_annotated(right, opts)
    op_instruction = [{[map_arithmetic_op(op)], position}]

    left_instructions ++ right_instructions ++ op_instruction
  end

  defp visit_annotated({:unary, op, operand, position}, opts) do
    # Post-order traversal: operand first, then operator
    operand_instructions = visit_annotated(operand, opts)
    op_instruction = [{[map_unary_op(op)], position}]

    operand_instructions ++ op_instruction
  end

  defp visit_annotated({:bracket_access, object, key, position}, opts) do
    # Post-order traversal: object first, then key, then access operation
    # Stack will be: [key, object] with key on top
    object_instructions = visit_annotated(object, opts)
    key_instructions = visit_annotated(key, opts)
    access_instruction = [{["bracket_access"], position}]

    object_instructions ++ key_instructions ++ access_instruction
  end

  defp visit_annotated({:logical_and, left, right, position}, opts) do
    # Short-circuit: if left is falsy (false or :undefined), jump past right
    # and leave left's value as the result. Otherwise pop and fall through
    # into right - the AND's value is right's value. (ADR-0001)
    #
    # The annotated list holds one entry per instruction, so the offset
    # arithmetic is the same as it was on a plain instruction list.
    left_instructions = visit_annotated(left, opts)
    right_instructions = visit_annotated(right, opts)
    offset = length(right_instructions) + 1
    jump_instruction = [{["jump_if_falsy_or_pop", offset], position}]

    left_instructions ++ jump_instruction ++ right_instructions
  end

  defp visit_annotated({:logical_or, left, right, position}, opts) do
    # Short-circuit: if left is exactly true, jump past right and leave left's
    # value as the result. Otherwise (false or :undefined) pop and fall through
    # into right - the OR's value is right's value. (ADR-0001)
    left_instructions = visit_annotated(left, opts)
    right_instructions = visit_annotated(right, opts)
    offset = length(right_instructions) + 1
    jump_instruction = [{["jump_if_true_or_pop", offset], position}]

    left_instructions ++ jump_instruction ++ right_instructions
  end

  defp visit_annotated({:logical_not, operand, position}, opts) do
    # Post-order traversal: operand first, then operator
    operand_instructions = visit_annotated(operand, opts)
    op_instruction = [{["not"], position}]

    operand_instructions ++ op_instruction
  end

  defp visit_annotated({:list, elements, position}, opts) do
    # All-literal lists compile to a single "lit" instruction: it is smaller,
    # and it runs on the Ruby and JavaScript siblings, which do not implement
    # make_list yet (ADR-0001).
    #
    # That one instruction takes the list node's own position. The elements'
    # positions are unrepresentable here, which is correct: a failure on this
    # instruction is a failure of the whole literal.
    if all_literals?(elements) do
      literal_values =
        Enum.map(elements, fn
          {:literal, value, _position} -> value
          {:string_literal, value, _quote_type, _position} -> value
        end)

      [{["lit", literal_values], position}]
    else
      element_instructions =
        Enum.flat_map(elements, fn element -> visit_annotated(element, opts) end)

      element_instructions ++ [{["make_list", length(elements)], position}]
    end
  end

  defp visit_annotated({:object, entries, position}, opts) do
    # Build object from key-value pairs. Each entry is {key_node, value_node};
    # the key emits no instructions of its own, so its `object_set` carries the
    # key's position rather than the object's.
    instructions =
      Enum.flat_map(entries, fn {key, value} ->
        value_instructions = visit_annotated(value, opts)
        value_instructions ++ [{["object_set", extract_key_string(key)], key_position(key)}]
      end)

    [{["object_new"], position}] ++ instructions
  end

  defp visit_annotated({:membership, op, left, right, position}, opts) do
    # Post-order traversal: operands first, then operator
    left_instructions = visit_annotated(left, opts)
    right_instructions = visit_annotated(right, opts)
    op_instruction = [{[map_membership_op(op)], position}]

    left_instructions ++ right_instructions ++ op_instruction
  end

  defp visit_annotated({:function_call, function_name, arguments, position}, opts) do
    # Post-order traversal: arguments first (in order), then function call
    arg_instructions =
      arguments
      |> Enum.flat_map(fn arg -> visit_annotated(arg, opts) end)

    call_instruction = [{["call", function_name, length(arguments)], position}]

    arg_instructions ++ call_instruction
  end

  defp visit_annotated({:duration, units, position}, _opts) do
    # Compile duration to a serializable instruction: ["duration", [{value, "unit"}, ...]]
    # Convert from parser format [{integer(), binary()}] to instruction format
    serializable_units = Enum.map(units, fn {value, unit} -> [value, unit] end)
    [{["duration", serializable_units], position}]
  end

  defp visit_annotated({:relative_date, duration_ast, direction, position}, opts) do
    # Compile relative date expression: duration instructions + relative_date instruction
    duration_instructions = visit_annotated(duration_ast, opts)
    direction_str = map_relative_direction(direction)
    duration_instructions ++ [{["relative_date", direction_str], position}]
  end

  defp visit_annotated({:program, statements, _position}, opts) do
    Enum.flat_map(statements, &visit_statement(&1, opts))
  end

  defp visit_annotated({:assignment, lhs, rhs, position}, opts) do
    [{_root_instruction, root_annotation} | _rest] = segments = location_segments(lhs, opts)
    depth = location_depth(lhs)

    segments ++
      visit_annotated(rhs, opts) ++
      [{["store", depth], store_annotation(position, root_annotation)}]
  end

  # Which token a store failure blames. The assignment node's own point
  # position is the `=`, which names the operator that noticed the write
  # rather than the location being written - the same complaint the unbound-load
  # rewrite answers for `load` (`lib/predicator.ex:440-442`). The lhs root's
  # position is used instead (px-tbv.11).
  #
  # A span is kept as-is: the assignment node's span already starts at the lhs
  # root, so `Errors.put_position/2` already derives the same caret from it
  # (`errors.ex:44-50`), and narrowing it to the root identifier would shrink
  # the underline from the statement to a single token for no gain.
  @spec store_annotation(
          Types.position() | Types.span() | nil,
          Types.position() | Types.span() | nil
        ) :: Types.position() | Types.span() | nil
  defp store_annotation({{_sl, _sc}, {_el, _ec}} = span, _root_annotation), do: span
  defp store_annotation(_position, root_annotation), do: root_annotation

  # Compiles one statement of a program. An assignment compiles to its own
  # instructions (a store, never a pop - the assignment's value is consumed by
  # the write itself). Any other statement is a bare expression: its
  # instructions plus a trailing pop, so every statement boundary leaves the
  # stack empty (Q3, docs/isa.md section 2).
  @spec visit_statement(Parser.statement(), keyword()) :: [annotated()]
  defp visit_statement({:assignment, _lhs, _rhs, _position} = assignment, opts) do
    visit_annotated(assignment, opts)
  end

  defp visit_statement(expression, opts) do
    visit_annotated(expression, opts) ++ [{["pop"], statement_position(expression)}]
  end

  # Every AST node's trailing element is its position slot, whatever the
  # node's arity - reach it structurally rather than adding a clause per node
  # type.
  @spec statement_position(Parser.ast()) :: Types.position() | Types.span() | nil
  defp statement_position(node), do: elem(node, tuple_size(node) - 1)

  # Walks an assignment's lhs chain root-to-leaf, emitting one `["lit", ...]`
  # segment per accessor. A bracket key is an arbitrary expression, so its
  # segment may be more than one instruction (Q2).
  @spec location_segments(Parser.ast(), keyword()) :: [annotated()]
  defp location_segments({:identifier, name, position}, _opts), do: [{["lit", name], position}]

  defp location_segments({:property_access, object, property, position}, opts),
    do: location_segments(object, opts) ++ [{["lit", property], position}]

  defp location_segments({:bracket_access, object, key, _position}, opts),
    do: location_segments(object, opts) ++ visit_annotated(key, opts)

  # `["store", n]`'s `n` is the chain's segment DEPTH, not the number of
  # instructions the segments compiled to - counted structurally here rather
  # than as `length(location_segments(lhs, opts))`, which a computed bracket
  # key (e.g. `a[k + 1] = 1`) would inflate: the key compiles to more than one
  # instruction but is still exactly one segment (Q2).
  @spec location_depth(Parser.ast()) :: pos_integer()
  defp location_depth({:identifier, _name, _position}), do: 1

  defp location_depth({:property_access, object, _property, _position}),
    do: location_depth(object) + 1

  defp location_depth({:bracket_access, object, _key, _position}), do: location_depth(object) + 1

  # Helper function to map AST comparison operators to instruction format
  @spec map_comparison_op(Parser.comparison_op()) :: binary()
  defp map_comparison_op(:gt), do: "GT"
  defp map_comparison_op(:lt), do: "LT"
  defp map_comparison_op(:gte), do: "GTE"
  defp map_comparison_op(:lte), do: "LTE"
  defp map_comparison_op(:eq), do: "EQ"
  defp map_comparison_op(:equal_equal), do: "EQ"
  defp map_comparison_op(:ne), do: "NE"
  defp map_comparison_op(:strict_eq), do: "STRICT_EQ"
  defp map_comparison_op(:strict_ne), do: "STRICT_NE"

  # Helper function to map AST arithmetic operators to instruction format
  @spec map_arithmetic_op(Parser.arithmetic_op()) :: binary()
  defp map_arithmetic_op(:add), do: "add"
  defp map_arithmetic_op(:subtract), do: "subtract"
  defp map_arithmetic_op(:multiply), do: "multiply"
  defp map_arithmetic_op(:divide), do: "divide"
  defp map_arithmetic_op(:modulo), do: "modulo"

  # Helper function to map AST unary operators to instruction format
  @spec map_unary_op(Parser.unary_op()) :: binary()
  defp map_unary_op(:minus), do: "unary_minus"
  defp map_unary_op(:bang), do: "unary_bang"

  # Helper function to map AST membership operators to instruction format
  @spec map_membership_op(Parser.membership_op()) :: binary()
  defp map_membership_op(:in), do: "in"
  defp map_membership_op(:contains), do: "contains"

  # Helper function to map relative direction atoms to instruction format
  @spec map_relative_direction(Parser.relative_direction()) :: binary()
  defp map_relative_direction(:ago), do: "ago"
  defp map_relative_direction(:future), do: "future"
  defp map_relative_direction(:next), do: "next"
  defp map_relative_direction(:last), do: "last"

  # Helper function to check if all elements in a list are literals
  @spec all_literals?([Parser.ast()]) :: boolean()
  defp all_literals?(elements) do
    Enum.all?(elements, fn
      {:literal, _value, _position} -> true
      {:string_literal, _value, _quote_type, _position} -> true
      _other -> false
    end)
  end

  # Helper function to extract string from object key node
  @spec extract_key_string(Parser.object_key()) :: binary()
  defp extract_key_string({:object_key, value, _style, _position}), do: value

  @spec key_position(Parser.object_key()) :: Types.position() | nil
  defp key_position({:object_key, _value, _style, position}), do: position
end
