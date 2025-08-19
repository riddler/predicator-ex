defmodule Predicator.Compiler do
  @moduledoc """
  Compiler that converts AST to various representations using visitors.

  The compiler orchestrates different visitors to transform Abstract Syntax Trees
  into executable instructions, string representations, or other formats.

  ## Examples

      iex> ast = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      iex> Predicator.Compiler.to_instructions(ast)
      [["load", "score"], ["lit", 85], ["compare", "GT"]]

      # Future visitors will enable:
      # iex> Predicator.Compiler.to_string(ast) 
      # "score > 85"
      
      # iex> Predicator.Compiler.to_dot(ast)
      # "digraph {...}"
  """

  alias Predicator.{InstructionsVisitor, Parser, StringVisitor, Visitor}

  @doc """
  Converts an AST to stack machine instructions.

  Uses the InstructionsVisitor to generate a list of instructions that can
  be executed by the stack-based evaluator.

  ## Parameters

  - `ast` - The Abstract Syntax Tree to compile
  - `opts` - Optional compiler options

  ## Returns

  List of instructions in the format `[["operation", ...args]]`

  ## Examples

      iex> ast = {:literal, 42}
      iex> Predicator.Compiler.to_instructions(ast)
      [["lit", 42]]

      iex> ast = {:comparison, :eq, {:identifier, "name"}, {:literal, "John"}}
      iex> Predicator.Compiler.to_instructions(ast)
      [["load", "name"], ["lit", "John"], ["compare", "EQ"]]
  """
  @spec to_instructions(Parser.ast(), keyword()) :: [[binary() | term()]]
  def to_instructions(ast, opts \\ []) do
    Visitor.accept(ast, InstructionsVisitor, opts)
  end

  @doc """
  Converts an AST to a string representation.

  Uses the StringVisitor to generate a readable string representation
  of the Abstract Syntax Tree. This is useful for debugging, documentation,
  and displaying expressions to users.

  ## Parameters

  - `ast` - The Abstract Syntax Tree to convert
  - `opts` - Optional formatting options:
    - `:parentheses` - `:minimal` (default) | `:explicit` | `:none`
    - `:spacing` - `:normal` (default) | `:compact` | `:verbose`

  ## Returns

  String representation of the AST

  ## Examples

      iex> ast = {:literal, 42}
      iex> Predicator.Compiler.to_string(ast)
      "42"

      iex> ast = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      iex> Predicator.Compiler.to_string(ast)
      "score > 85"

      iex> ast = {:comparison, :gt, {:identifier, "age"}, {:literal, 21}}
      iex> Predicator.Compiler.to_string(ast, parentheses: :explicit)
      "(age > 21)"
  """
  @spec to_string(Parser.ast(), keyword()) :: binary()
  def to_string(ast, opts \\ []) do
    Visitor.accept(ast, StringVisitor, opts)
  end
end
