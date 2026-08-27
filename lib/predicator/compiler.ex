defmodule Predicator.Compiler do
  @moduledoc """
  Compiler that converts AST to various representations using visitors.

  The compiler orchestrates different visitors to transform Abstract Syntax Trees
  into executable instructions, string representations, or other formats.

  ## Examples

      iex> ast = {:comparison, :gt, {:identifier, "limit", nil}, {:literal, 85, nil}, nil}
      iex> Predicator.Compiler.to_instructions(ast)
      [["load", "limit"], ["lit", 85], ["compare", "GT"]]

      # Future visitors will enable:
      # iex> Predicator.Compiler.to_string(ast)
      # "limit > 85"

      # iex> Predicator.Compiler.to_dot(ast)
      # "digraph {...}"
  """

  alias Predicator.{Parser, Types, Visitor}
  alias Predicator.Visitors.{InstructionsVisitor, StringVisitor}

  @doc """
  Converts an AST to stack machine instructions.

  Uses the InstructionsVisitor to generate a list of instructions that can
  be executed by the stack-based evaluator.

  ## Parameters

  - `ast` - The Abstract Syntax Tree to compile - a bare expression, or a
    `t:Predicator.Parser.program/0`, which compiles to a flat statement
    program (each statement followed by a `store` or a `pop`)
  - `opts` - Optional compiler options

  ## Returns

  List of instructions in the format `[["operation", ...args]]`.

  ## Examples

      iex> ast = {:literal, 42, nil}
      iex> Predicator.Compiler.to_instructions(ast)
      [["lit", 42]]

      iex> ast = {:comparison, :eq, {:identifier, "name", nil}, {:literal, "John", nil}, nil}
      iex> Predicator.Compiler.to_instructions(ast)
      [["load", "name"], ["lit", "John"], ["compare", "EQ"]]

      iex> {:ok, program} = Predicator.parse_program("x = 1")
      iex> Predicator.Compiler.to_instructions(program)
      [["lit", "x"], ["lit", 1], ["store", 1]]
  """
  @spec to_instructions(Parser.visitable(), keyword()) ::
          [[binary() | term()]] | {:error, struct()}
  def to_instructions(ast, opts \\ []) do
    Visitor.accept(ast, InstructionsVisitor, opts)
  end

  @doc """
  Converts an AST to stack machine instructions plus a source-position side
  table.

  The instruction list is identical to `to_instructions/2`'s - the side table is
  a separate Elixir-side value, so the interchange format and any stored
  compiled artifacts are unaffected (ADR-0001). The table maps each
  instruction's 0-based index to the `{line, column}` of the AST node that
  emitted it; nodes with no position contribute no entry, so a caller-supplied
  position-free AST yields an empty table. An AST parsed with `spans: true`
  yields a `t:Predicator.Types.span_table/0` instead - see
  `Predicator.compile_with_spans/1`.

  ## Examples

      iex> ast = {:comparison, :gt, {:identifier, "limit", {1, 1}}, {:literal, 85, {1, 9}}, {1, 7}}
      iex> Predicator.Compiler.to_instructions_with_positions(ast)
      {[["load", "limit"], ["lit", 85], ["compare", "GT"]],
       %{0 => {1, 1}, 1 => {1, 9}, 2 => {1, 7}}}

      iex> Predicator.Compiler.to_instructions_with_positions({:literal, 42, nil})
      {[["lit", 42]], %{}}

      iex> {:ok, program} = Predicator.parse_program("x = 1", spans: false)
      iex> Predicator.Compiler.to_instructions_with_positions(program)
      {[["lit", "x"], ["lit", 1], ["store", 1]], %{0 => {1, 1}, 1 => {1, 5}, 2 => {1, 1}}}

  """
  @spec to_instructions_with_positions(Parser.visitable(), keyword()) ::
          {[[binary() | term()]], Types.position_table() | Types.span_table()}
          | {:error, struct()}
  def to_instructions_with_positions(ast, opts \\ []) do
    InstructionsVisitor.visit_with_positions(ast, opts)
  end

  @doc """
  Converts an AST to stack machine instructions, a source-position side table,
  and a per-store segment-position side table.

  The instruction list and position table are identical to what
  `to_instructions_with_positions/2` returns for the same AST - this function
  adds a third table mapping each `["store", n]` instruction's 0-based index
  to one source annotation per location segment in its lhs chain, root-first
  (`t:Predicator.Types.segment_position_table/0`). An assignment-free AST
  contributes no entry, so an expression compiles to an empty segment table.

  ## Examples

      iex> {:ok, program} = Predicator.parse_program("a.b = 1", spans: false)
      iex> Predicator.Compiler.to_instructions_with_segment_positions(program)
      {[["lit", "a"], ["lit", "b"], ["lit", 1], ["store", 2]],
       %{0 => {1, 1}, 1 => {1, 3}, 2 => {1, 7}, 3 => {1, 1}},
       %{3 => [{1, 1}, {1, 3}]}}

  """
  @spec to_instructions_with_segment_positions(Parser.visitable(), keyword()) ::
          {[[binary() | term()]], Types.position_table() | Types.span_table(),
           Types.segment_position_table()}
          | {:error, struct()}
  def to_instructions_with_segment_positions(ast, opts \\ []) do
    InstructionsVisitor.visit_with_segment_positions(ast, opts)
  end

  @doc """
  Converts an AST to a string representation.

  Uses the StringVisitor to generate a readable string representation
  of the Abstract Syntax Tree. This is useful for debugging, documentation,
  and displaying expressions to users.

  ## Parameters

  - `ast` - The Abstract Syntax Tree to convert - a bare expression, or a
    `t:Predicator.Parser.program/0`, which renders as its statements joined by
    `"; "`
  - `opts` - Optional formatting options:
    - `:parentheses` - `:minimal` (default) | `:explicit` | `:none`
    - `:spacing` - `:normal` (default) | `:compact` | `:verbose`

  ## Returns

  String representation of the AST.

  ## Examples

      iex> ast = {:literal, 42, nil}
      iex> Predicator.Compiler.to_string(ast)
      "42"

      iex> ast = {:comparison, :gt, {:identifier, "limit", nil}, {:literal, 85, nil}, nil}
      iex> Predicator.Compiler.to_string(ast)
      "limit > 85"

      iex> ast = {:comparison, :gt, {:identifier, "age", nil}, {:literal, 21, nil}, nil}
      iex> Predicator.Compiler.to_string(ast, parentheses: :explicit)
      "(age > 21)"
  """
  @spec to_string(Parser.visitable(), keyword()) :: binary()
  def to_string(ast, opts \\ []) do
    Visitor.accept(ast, StringVisitor, opts)
  end
end
