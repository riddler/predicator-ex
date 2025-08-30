defmodule Predicator.Visitor do
  @moduledoc """
  Behaviour for AST visitors.

  Visitors implement the visitor pattern to traverse and transform
  Abstract Syntax Trees into various representations.

  ## Examples

      defmodule MyVisitor do
        @behaviour Predicator.Visitor

        @impl true
        def visit({:literal, value}, _opts) do
          value
        end

        @impl true
        def visit({:identifier, name}, _opts) do
          name
        end

        @impl true
        def visit({:comparison, op, left, right}, opts) do
          left_result = visit(left, opts)
          right_result = visit(right, opts)
          {op, left_result, right_result}
        end
      end
  """

  alias Predicator.Parser

  @doc """
  Visits an AST node and returns the transformed result.

  ## Parameters

  - `ast_node` - The AST node to visit
  - `opts` - Optional visitor-specific options

  ## Returns

  The transformed representation (type depends on visitor implementation)
  """
  @callback visit(ast_node :: Parser.ast(), opts :: keyword()) :: term()

  @doc """
  Utility function to accept a visitor and process an AST.

  This provides a convenient interface for applying visitors to AST nodes.

  ## Examples

      iex> ast = {:literal, 42}
      iex> Predicator.Visitor.accept(ast, MyVisitor)
      42
  """
  @spec accept(Parser.ast(), module(), keyword()) :: term()
  def accept(ast_node, visitor_module, opts \\ []) do
    visitor_module.visit(ast_node, opts)
  end
end
