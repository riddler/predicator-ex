defmodule Predicator.StringVisitor do
  @moduledoc """
  Visitor that converts AST nodes back to string expressions.

  This visitor implements the inverse of parsing - it takes an Abstract Syntax Tree
  and generates a readable string representation. This is useful for debugging,
  documentation, and round-trip testing.

  ## Examples

      iex> ast = {:literal, 42}
      iex> Predicator.StringVisitor.visit(ast, [])
      "42"

      iex> ast = {:identifier, "score"}
      iex> Predicator.StringVisitor.visit(ast, [])
      "score"

      iex> ast = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      iex> Predicator.StringVisitor.visit(ast, [])
      "score > 85"

      iex> ast = {:comparison, :eq, {:identifier, "name"}, {:literal, "John"}}
      iex> Predicator.StringVisitor.visit(ast, [])
      ~s(name = "John")

      iex> ast = {:logical_and, {:literal, true}, {:literal, false}}
      iex> Predicator.StringVisitor.visit(ast, [])
      "true AND false"

      iex> ast = {:logical_not, {:literal, true}}
      iex> Predicator.StringVisitor.visit(ast, [])
      "NOT true"

      iex> ast = {:function_call, "len", [{:identifier, "name"}]}
      iex> Predicator.StringVisitor.visit(ast, [])
      "len(name)"
  """

  @behaviour Predicator.Visitor

  alias Predicator.Parser

  @doc """
  Visits an AST node and returns its string representation.

  ## Parameters

  - `ast_node` - The AST node to convert to a string
  - `opts` - Optional visitor options:
    - `:parentheses` - `:minimal` (default) | `:explicit` | `:none`
    - `:spacing` - `:normal` (default) | `:compact` | `:verbose`

  ## Returns

  String representation of the AST node

  ## Options

  - `:parentheses` controls parentheses generation:
    - `:minimal` - only add parentheses when necessary for precedence
    - `:explicit` - add parentheses around all comparisons
    - `:none` - never add parentheses (may change meaning!)

  - `:spacing` controls whitespace:
    - `:normal` - standard spacing: "score > 85"
    - `:compact` - minimal spacing: "score>85"  
    - `:verbose` - extra spacing: "score  >  85"
  """
  @impl Predicator.Visitor
  @spec visit(Parser.ast(), keyword()) :: binary()
  def visit(ast_node, opts \\ [])

  def visit({:literal, value}, _opts) when is_integer(value) do
    Integer.to_string(value)
  end

  def visit({:literal, value}, _opts) when is_boolean(value) do
    Atom.to_string(value)
  end

  def visit({:literal, value}, _opts) when is_binary(value) do
    # Escape quotes and wrap in quotes
    escaped = String.replace(value, "\"", "\\\"")
    "\"#{escaped}\""
  end

  def visit({:literal, value}, opts) when is_list(value) do
    # Handle list literals (future extension)
    items = Enum.map(value, fn item -> visit({:literal, item}, opts) end)
    "[#{Enum.join(items, ", ")}]"
  end

  def visit({:literal, %Date{} = value}, _opts) do
    "##{Date.to_iso8601(value)}#"
  end

  def visit({:literal, %DateTime{} = value}, _opts) do
    "##{DateTime.to_iso8601(value)}#"
  end

  def visit({:identifier, name}, _opts) when is_binary(name) do
    name
  end

  def visit({:comparison, op, left, right}, opts) do
    left_str = visit(left, opts)
    right_str = visit(right, opts)
    op_str = format_operator(op)

    spacing = get_spacing(opts)

    case get_parentheses_mode(opts) do
      :explicit -> "(#{left_str}#{spacing}#{op_str}#{spacing}#{right_str})"
      :none -> "#{left_str}#{spacing}#{op_str}#{spacing}#{right_str}"
      :minimal -> "#{left_str}#{spacing}#{op_str}#{spacing}#{right_str}"
    end
  end

  def visit({:logical_and, left, right}, opts) do
    left_str = visit(left, opts)
    right_str = visit(right, opts)
    spacing = get_spacing(opts)

    case get_parentheses_mode(opts) do
      :explicit -> "(#{left_str}#{spacing}AND#{spacing}#{right_str})"
      _other -> "#{left_str}#{spacing}AND#{spacing}#{right_str}"
    end
  end

  def visit({:logical_or, left, right}, opts) do
    left_str = visit(left, opts)
    right_str = visit(right, opts)
    spacing = get_spacing(opts)

    case get_parentheses_mode(opts) do
      :explicit -> "(#{left_str}#{spacing}OR#{spacing}#{right_str})"
      _other -> "#{left_str}#{spacing}OR#{spacing}#{right_str}"
    end
  end

  def visit({:logical_not, operand}, opts) do
    operand_str = visit(operand, opts)
    spacing = get_spacing(opts)

    case get_parentheses_mode(opts) do
      :explicit -> "(NOT#{spacing}#{operand_str})"
      :none -> "NOT#{spacing}#{operand_str}"
      :minimal -> "NOT#{spacing}#{operand_str}"
    end
  end

  def visit({:list, elements}, opts) do
    element_strings = Enum.map(elements, fn element -> visit(element, opts) end)
    "[#{Enum.join(element_strings, ", ")}]"
  end

  def visit({:membership, op, left, right}, opts) do
    left_str = visit(left, opts)
    right_str = visit(right, opts)
    op_str = format_membership_operator(op)
    spacing = get_spacing(opts)

    case get_parentheses_mode(opts) do
      :explicit -> "(#{left_str}#{spacing}#{op_str}#{spacing}#{right_str})"
      _other -> "#{left_str}#{spacing}#{op_str}#{spacing}#{right_str}"
    end
  end

  def visit({:function_call, function_name, arguments}, opts) do
    arg_strings = Enum.map(arguments, fn arg -> visit(arg, opts) end)
    args_str = Enum.join(arg_strings, ", ")
    "#{function_name}(#{args_str})"
  end

  # Helper functions

  @spec format_operator(Parser.comparison_op()) :: binary()
  defp format_operator(:gt), do: ">"
  defp format_operator(:lt), do: "<"
  defp format_operator(:gte), do: ">="
  defp format_operator(:lte), do: "<="
  defp format_operator(:eq), do: "="
  defp format_operator(:ne), do: "!="

  @spec format_membership_operator(Parser.membership_op()) :: binary()
  defp format_membership_operator(:in), do: "IN"
  defp format_membership_operator(:contains), do: "CONTAINS"

  @spec get_spacing(keyword()) :: binary()
  defp get_spacing(opts) do
    case Keyword.get(opts, :spacing, :normal) do
      :compact -> ""
      :verbose -> "  "
      :normal -> " "
    end
  end

  @spec get_parentheses_mode(keyword()) :: :minimal | :explicit | :none
  defp get_parentheses_mode(opts) do
    Keyword.get(opts, :parentheses, :minimal)
  end
end
