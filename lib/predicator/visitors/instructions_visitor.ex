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

      iex> ast = {:if, {:literal, true, nil}, {:block, [], nil}, nil, nil}
      iex> Predicator.Visitors.InstructionsVisitor.visit(ast, [])
      [["lit", true], ["pop_jump_if_falsy", 1]]
  """

  @behaviour Predicator.Visitor

  alias Predicator.{Parser, Types}

  @typedoc """
  One instruction paired with the source position of the node that emitted it.

  Every clause but one produces the two-element form. A `["store", n]`
  instruction produces the three-element form instead, whose third element is
  `location_segment_annotations/1`'s list - one annotation per lhs segment,
  root-first. Nothing else in this module ever emits or reads a third element.
  """
  @type annotated ::
          {[binary() | term()], Types.position() | Types.span() | nil}
          | {[binary() | term()], Types.position() | Types.span() | nil,
             [Types.position() | Types.span() | nil]}

  @doc """
  Visits an AST node and returns stack machine instructions.

  Uses post-order traversal to ensure operands are pushed onto the stack
  before operators are applied.

  ## Parameters

  - `ast_node` - The AST node to convert to instructions
  - `opts` - Optional visitor options (currently unused)

  ## Returns

  List of instructions in the format `[["operation", ...args]]`.
  """
  @impl Predicator.Visitor
  @spec visit(Parser.visitable(), keyword()) :: [[binary() | term()]]
  def visit(ast_node, opts \\ []) do
    ast_node
    |> visit_annotated(opts)
    |> Enum.map(&elem(&1, 0))
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
  @spec visit_with_positions(Parser.visitable(), keyword()) ::
          {[[binary() | term()]], Types.position_table() | Types.span_table()}
  def visit_with_positions(ast_node, opts \\ []) do
    {instructions, positions, _segment_positions} = tables(visit_annotated(ast_node, opts))
    {instructions, positions}
  end

  @doc """
  Returns the instruction list, the position table `visit_with_positions/2`
  returns, and a per-store segment-position table.

  The segment table maps each `["store", n]` instruction's 0-based index to
  the list `location_segment_annotations/1` built for its lhs chain - one
  annotation per location segment, root-first, whatever `n` counts as depth
  (`location_depth/1`). Every other instruction contributes no entry. The
  instruction list and the position table are identical to what
  `visit_with_positions/2` returns for the same AST - this function differs
  only in returning the third table alongside them.

  ## Examples

      iex> {:ok, program} = Predicator.parse_program("a.b = 1", spans: false)
      iex> Predicator.Visitors.InstructionsVisitor.visit_with_segment_positions(program)
      {[["lit", "a"], ["lit", "b"], ["lit", 1], ["store", 2]],
       %{0 => {1, 1}, 1 => {1, 3}, 2 => {1, 7}, 3 => {1, 1}},
       %{3 => [{1, 1}, {1, 3}]}}
  """
  @spec visit_with_segment_positions(Parser.visitable(), keyword()) ::
          {[[binary() | term()]], Types.position_table() | Types.span_table(),
           Types.segment_position_table()}
  def visit_with_segment_positions(ast_node, opts \\ []) do
    tables(visit_annotated(ast_node, opts))
  end

  # One walk of the annotated list builds all three tables together, so the
  # position table and the segment table cannot disagree about an index.
  @spec tables([annotated()]) ::
          {[[binary() | term()]], Types.position_table() | Types.span_table(),
           Types.segment_position_table()}
  defp tables(annotated) do
    indexed = Enum.with_index(annotated)

    positions =
      indexed
      |> Enum.flat_map(fn
        {entry, _index} when elem(entry, 1) == nil -> []
        {entry, index} -> [{index, elem(entry, 1)}]
      end)
      |> Map.new()

    segment_positions =
      indexed
      |> Enum.flat_map(fn
        {{_instruction, _position, segments}, index} -> [{index, segments}]
        {_entry, _index} -> []
      end)
      |> Map.new()

    {Enum.map(annotated, &elem(&1, 0)), positions, segment_positions}
  end

  # Each clause pairs the instructions the node emits *itself* with that node's
  # own position; instructions contributed by children keep the position their
  # own node gave them.
  @spec visit_annotated(Parser.visitable(), keyword()) :: [annotated()]
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

  defp visit_annotated({:cast, expr, type_name, position}, opts) do
    # Post-order: the operand's instructions, then the cast opcode. The node's
    # own position slot is the type-name token (docs/reference/ast.md), so a
    # failed cast blames the type the author wrote.
    visit_annotated(expr, opts) ++ [{["cast", type_name], position}]
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

  # ADR-0013:  if c { A }  ->  c; pop_jump_if_falsy +(lenA + 1); A
  # The block's statements are stack-neutral (each ends in a store or a pop),
  # so the jump target is one past A and nothing needs mopping up.
  defp visit_annotated({:if, condition, then_block, nil, position}, opts) do
    condition_instructions = visit_annotated(condition, opts)
    then_instructions = visit_annotated(then_block, opts)
    offset = length(then_instructions) + 1

    condition_instructions ++
      [{["pop_jump_if_falsy", offset], position}] ++
      then_instructions
  end

  # ADR-0013:  if c { A } else { B }
  #   ->  c; pop_jump_if_falsy +(lenA + 2); A; jump +(lenB + 1); B
  # The +2 clears A and the unconditional jump that ends it; the +1 clears B.
  defp visit_annotated({:if, condition, then_block, else_block, position}, opts) do
    condition_instructions = visit_annotated(condition, opts)
    then_instructions = visit_annotated(then_block, opts)
    else_instructions = visit_annotated(else_block, opts)

    condition_instructions ++
      [{["pop_jump_if_falsy", length(then_instructions) + 2], position}] ++
      then_instructions ++
      [{["jump", length(else_instructions) + 1], position}] ++
      else_instructions
  end

  # ADR-0013:  while c { A }
  #   ->  c; pop_jump_if_falsy +(lenA + 2); A; jump_backward -(lenC + lenA + 1)
  # The +2 clears A and the back edge that ends it; the back edge's offset is
  # measured from its own index to the condition's first instruction, which is
  # why it counts lenC as well.
  defp visit_annotated({:while, condition, body, position}, opts) do
    condition_instructions = visit_annotated(condition, opts)
    body_instructions = visit_annotated(body, opts)

    back_offset = length(condition_instructions) + length(body_instructions) + 1

    condition_instructions ++
      [{["pop_jump_if_falsy", length(body_instructions) + 2], position}] ++
      body_instructions ++
      [{["jump_backward", back_offset], position}]
  end

  # A block is a statement sequence with no scope of its own (ADR-0013) - the
  # same body as {:program, ...}, and the reason each block is stack-neutral.
  defp visit_annotated({:block, statements, _position}, opts) do
    Enum.flat_map(statements, &visit_statement(&1, opts))
  end

  defp visit_annotated({:program, statements, _position}, opts) do
    Enum.flat_map(statements, &visit_statement(&1, opts))
  end

  defp visit_annotated({:assignment, lhs, rhs, position}, opts) do
    [{_root_instruction, root_annotation} | _rest] = segments = location_segments(lhs, opts)
    depth = location_depth(lhs)

    segments ++
      visit_annotated(rhs, opts) ++
      [
        {["store", depth], store_annotation(position, root_annotation),
         location_segment_annotations(lhs)}
      ]
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

  # An `if` is stack-neutral by construction - its condition is consumed by
  # pop_jump_if_falsy and its blocks end stack-neutral - so unlike a bare
  # expression statement it takes no trailing pop. Without this clause the
  # catch-all below would emit one against an empty stack.
  defp visit_statement({:if, _condition, _then_block, _else_block, _position} = node, opts) do
    visit_annotated(node, opts)
  end

  # Stack-neutral by construction, exactly as an `if` is: the condition is
  # consumed by pop_jump_if_falsy on every iteration including the last, and
  # the body's statements each end in a store or a pop. Without this clause the
  # catch-all would append a ["pop"] against an empty stack.
  defp visit_statement({:while, _condition, _body, _position} = node, opts) do
    visit_annotated(node, opts)
  end

  defp visit_statement(expression, opts) do
    visit_annotated(expression, opts) ++ [{["pop"], node_annotation(expression)}]
  end

  # Every AST node's trailing element is its position slot, whatever the
  # node's arity - reach it structurally rather than adding a clause per node
  # type. Used both for a bare statement's `pop` and, via
  # `location_segment_annotations/1`, for a location segment's own annotation.
  @spec node_annotation(Parser.ast()) :: Types.position() | Types.span() | nil
  defp node_annotation(node), do: elem(node, tuple_size(node) - 1)

  # Walks an assignment's lhs chain root-to-leaf, emitting one `["lit", ...]`
  # segment per accessor. A bracket key is an arbitrary expression, so its
  # segment may be more than one instruction (Q2).
  @spec location_segments(Parser.ast(), keyword()) :: [annotated()]
  defp location_segments({:identifier, name, position}, _opts), do: [{["lit", name], position}]

  defp location_segments({:property_access, object, property, position}, opts),
    do: location_segments(object, opts) ++ [{["lit", property], position}]

  defp location_segments({:bracket_access, object, key, _position}, opts),
    do: location_segments(object, opts) ++ visit_annotated(key, opts)

  # One annotation per location segment, root-first - the segment-level echo
  # of `location_segments/2`, whose list a computed bracket key inflates
  # (`a[k+1]` is one segment in several instructions). Its length is
  # `location_depth/1` by construction, which is what makes `["store", n]`'s
  # operand an index bound for this list.
  #
  # A segment's annotation is the annotation of the node that produced its
  # *value*: the identifier for the root, the `property_access` node for a
  # dotted segment (its point position is the property name, its span runs
  # from the chain root - docs/reference/ast.md), and the *key expression* for a
  # bracket segment, since the key is what a bad or out-of-range segment value
  # came from.
  @spec location_segment_annotations(Parser.ast()) ::
          [Types.position() | Types.span() | nil]
  defp location_segment_annotations({:identifier, _name, annotation}), do: [annotation]

  defp location_segment_annotations({:property_access, object, _property, annotation}),
    do: location_segment_annotations(object) ++ [annotation]

  defp location_segment_annotations({:bracket_access, object, key, _annotation}),
    do: location_segment_annotations(object) ++ [node_annotation(key)]

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
