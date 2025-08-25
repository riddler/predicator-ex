defmodule Predicator.Visitors.InstructionsVisitor do
  @moduledoc """
  Visitor that converts AST nodes to stack machine instructions.

  This visitor implements post-order traversal to generate instruction lists
  that can be executed by the stack-based evaluator. Instructions are generated
  in the correct order for stack-based evaluation.

  ## Examples

      iex> ast = {:literal, 42}
      iex> Predicator.Visitors.InstructionsVisitor.visit(ast, [])
      [["lit", 42]]

      iex> ast = {:identifier, "score"}
      iex> Predicator.Visitors.InstructionsVisitor.visit(ast, [])
      [["load", "score"]]

      iex> ast = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      iex> Predicator.Visitors.InstructionsVisitor.visit(ast, [])
      [["load", "score"], ["lit", 85], ["compare", "GT"]]

      iex> ast = {:logical_and, {:literal, true}, {:literal, false}}
      iex> Predicator.Visitors.InstructionsVisitor.visit(ast, [])
      [["lit", true], ["lit", false], ["and"]]

      iex> ast = {:function_call, "len", [{:identifier, "name"}]}
      iex> Predicator.Visitors.InstructionsVisitor.visit(ast, [])
      [["load", "name"], ["call", "len", 1]]
  """

  @behaviour Predicator.Visitor

  alias Predicator.Parser

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
  @spec visit(Parser.ast(), keyword()) :: [[binary() | term()]]
  def visit(ast_node, _opts \\ [])

  def visit({:literal, value}, _opts) do
    [["lit", value]]
  end

  def visit({:string_literal, value, _quote_type}, _opts) do
    # For instruction generation, quote type doesn't matter - just treat as literal
    [["lit", value]]
  end

  def visit({:identifier, name}, _opts) do
    [["load", name]]
  end

  def visit({:property_access, left, property}, opts) do
    # Generate instructions for property access: left_object, property_name, access
    left_instructions = visit(left, opts)
    left_instructions ++ [["access", property]]
  end

  def visit({:comparison, op, left, right}, opts) do
    # Post-order traversal: left operand, right operand, then operator
    left_instructions = visit(left, opts)
    right_instructions = visit(right, opts)
    op_instruction = [["compare", map_comparison_op(op)]]

    left_instructions ++ right_instructions ++ op_instruction
  end

  def visit({:equality, op, left, right}, opts) do
    # Post-order traversal: left operand, right operand, then operator
    left_instructions = visit(left, opts)
    right_instructions = visit(right, opts)
    op_instruction = [["compare", map_equality_op(op)]]

    left_instructions ++ right_instructions ++ op_instruction
  end

  def visit({:arithmetic, op, left, right}, opts) do
    # Post-order traversal: left operand, right operand, then operator
    left_instructions = visit(left, opts)
    right_instructions = visit(right, opts)
    op_instruction = [[map_arithmetic_op(op)]]

    left_instructions ++ right_instructions ++ op_instruction
  end

  def visit({:unary, op, operand}, opts) do
    # Post-order traversal: operand first, then operator
    operand_instructions = visit(operand, opts)
    op_instruction = [[map_unary_op(op)]]

    operand_instructions ++ op_instruction
  end

  def visit({:bracket_access, object, key}, opts) do
    # Post-order traversal: object first, then key, then access operation
    # Stack will be: [key, object] with key on top
    object_instructions = visit(object, opts)
    key_instructions = visit(key, opts)
    access_instruction = [["bracket_access"]]

    object_instructions ++ key_instructions ++ access_instruction
  end

  def visit({:logical_and, left, right}, opts) do
    # Post-order traversal: left operand, right operand, then operator
    left_instructions = visit(left, opts)
    right_instructions = visit(right, opts)
    op_instruction = [["and"]]

    left_instructions ++ right_instructions ++ op_instruction
  end

  def visit({:logical_or, left, right}, opts) do
    # Post-order traversal: left operand, right operand, then operator
    left_instructions = visit(left, opts)
    right_instructions = visit(right, opts)
    op_instruction = [["or"]]

    left_instructions ++ right_instructions ++ op_instruction
  end

  def visit({:logical_not, operand}, opts) do
    # Post-order traversal: operand first, then operator
    operand_instructions = visit(operand, opts)
    op_instruction = [["not"]]

    operand_instructions ++ op_instruction
  end

  def visit({:list, elements}, _opts) do
    # For list literals with only literal values, create a single "lit" instruction
    # For more complex lists, this would need more sophisticated handling
    case all_literals?(elements) do
      true ->
        literal_values =
          Enum.map(elements, fn
            {:literal, value} -> value
            {:string_literal, value, _quote_type} -> value
          end)

        [["lit", literal_values]]

      false ->
        # For now, we'll require all list elements to be literals
        # TODO: Handle mixed expressions in lists
        raise "Non-literal list elements are not yet supported"
    end
  end

  def visit({:membership, op, left, right}, opts) do
    # Post-order traversal: operands first, then operator
    left_instructions = visit(left, opts)
    right_instructions = visit(right, opts)
    op_instruction = [[map_membership_op(op)]]

    left_instructions ++ right_instructions ++ op_instruction
  end

  def visit({:function_call, function_name, arguments}, opts) do
    # Post-order traversal: arguments first (in order), then function call
    arg_instructions =
      arguments
      |> Enum.flat_map(fn arg -> visit(arg, opts) end)

    call_instruction = [["call", function_name, length(arguments)]]

    arg_instructions ++ call_instruction
  end

  # Helper function to map AST comparison operators to instruction format
  @spec map_comparison_op(Parser.comparison_op()) :: binary()
  defp map_comparison_op(:gt), do: "GT"
  defp map_comparison_op(:lt), do: "LT"
  defp map_comparison_op(:gte), do: "GTE"
  defp map_comparison_op(:lte), do: "LTE"
  defp map_comparison_op(:eq), do: "EQ"

  # Helper function to map AST equality operators to instruction format
  @spec map_equality_op(Parser.equality_op()) :: binary()
  defp map_equality_op(:equal_equal), do: "EQ"
  defp map_equality_op(:ne), do: "NE"

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

  # Helper function to check if all elements in a list are literals
  @spec all_literals?([Parser.ast()]) :: boolean()
  defp all_literals?(elements) do
    Enum.all?(elements, fn
      {:literal, _value} -> true
      {:string_literal, _value, _quote_type} -> true
      _other -> false
    end)
  end
end
