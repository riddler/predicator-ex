defmodule Predicator.InstructionsVisitor do
  @moduledoc """
  Visitor that converts AST nodes to stack machine instructions.

  This visitor implements post-order traversal to generate instruction lists
  that can be executed by the stack-based evaluator. Instructions are generated
  in the correct order for stack-based evaluation.

  ## Examples

      iex> ast = {:literal, 42}
      iex> Predicator.InstructionsVisitor.visit(ast, [])
      [["lit", 42]]

      iex> ast = {:identifier, "score"}
      iex> Predicator.InstructionsVisitor.visit(ast, [])
      [["load", "score"]]

      iex> ast = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      iex> Predicator.InstructionsVisitor.visit(ast, [])
      [["load", "score"], ["lit", 85], ["compare", "GT"]]

      iex> ast = {:logical_and, {:literal, true}, {:literal, false}}
      iex> Predicator.InstructionsVisitor.visit(ast, [])
      [["lit", true], ["lit", false], ["and"]]

      iex> ast = {:function_call, "len", [{:identifier, "name"}]}
      iex> Predicator.InstructionsVisitor.visit(ast, [])
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

  def visit({:identifier, name}, _opts) do
    [["load", name]]
  end

  def visit({:comparison, op, left, right}, opts) do
    # Post-order traversal: left operand, right operand, then operator
    left_instructions = visit(left, opts)
    right_instructions = visit(right, opts)
    op_instruction = [["compare", map_comparison_op(op)]]

    left_instructions ++ right_instructions ++ op_instruction
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
        literal_values = Enum.map(elements, fn {:literal, value} -> value end)
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
  defp map_comparison_op(:ne), do: "NE"

  # Helper function to map AST membership operators to instruction format
  @spec map_membership_op(Parser.membership_op()) :: binary()
  defp map_membership_op(:in), do: "in"
  defp map_membership_op(:contains), do: "contains"

  # Helper function to check if all elements in a list are literals
  @spec all_literals?([Parser.ast()]) :: boolean()
  defp all_literals?(elements) do
    Enum.all?(elements, fn
      {:literal, _value} -> true
      _other -> false
    end)
  end
end
