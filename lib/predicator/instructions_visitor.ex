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

  # Helper function to map AST comparison operators to instruction format
  @spec map_comparison_op(Parser.comparison_op()) :: binary()
  defp map_comparison_op(:gt), do: "GT"
  defp map_comparison_op(:lt), do: "LT"
  defp map_comparison_op(:gte), do: "GTE"
  defp map_comparison_op(:lte), do: "LTE"
  defp map_comparison_op(:eq), do: "EQ"
  defp map_comparison_op(:ne), do: "NE"
end
