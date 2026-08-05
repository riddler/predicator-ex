defmodule Predicator.Integration.PositionsTest do
  use ExUnit.Case, async: true

  # One expression per node type, plus the shapes most likely to get positions
  # wrong: nested calls, chained bracket access, and multi-line input.
  @corpus [
    "42",
    "'text'",
    ~s("text"),
    "score",
    "score > 85",
    "1 + 2 - 3 * 4 / 5 % 6",
    "-x",
    "!flag",
    "not flag",
    "a and b",
    "a or b",
    "x in [1, 2, 3]",
    "[1, 2, 3] contains x",
    "[a, b, c]",
    "[]",
    "{a: 1, 'b': 2}",
    "{}",
    "len(name)",
    "len(upper(name))",
    "Math.max(1, 2)",
    "items[0]",
    "a[0][1]",
    "user.name",
    "3d8h",
    "3d ago",
    "3d from now",
    "next 2d",
    "last 2d",
    "a > 1 and b < 2 or c == 3",
    "1 +\n2",
    "len(\n  name\n) > 3"
  ]

  describe "compile/1 and compile_with_positions/1 agree" do
    test "the instruction lists are identical across the corpus" do
      for expression <- @corpus do
        assert {:ok, plain} = Predicator.compile(expression)
        assert {:ok, positioned, _table} = Predicator.compile_with_positions(expression)

        assert plain == positioned,
               "instruction list moved for #{inspect(expression)}"
      end
    end
  end

  describe "table coverage" do
    test "every instruction index has an entry across the corpus" do
      for expression <- @corpus do
        assert {:ok, instructions, table} = Predicator.compile_with_positions(expression)
        expected = MapSet.new(0..(length(instructions) - 1)//1)

        assert MapSet.new(Map.keys(table)) == expected,
               "table did not cover every index for #{inspect(expression)}"
      end
    end

    test "every position names a real line and column in the source" do
      for expression <- @corpus do
        {:ok, _instructions, table} = Predicator.compile_with_positions(expression)
        lines = String.split(expression, "\n")

        for {index, {line, column}} <- table do
          assert line >= 1 and line <= length(lines),
                 "index #{index} of #{inspect(expression)} names line #{line}"

          source_line = Enum.at(lines, line - 1)

          assert column >= 1 and column <= String.length(source_line),
                 "index #{index} of #{inspect(expression)} names column #{column} " <>
                   "of #{inspect(source_line)}"

          refute String.at(source_line, column - 1) == " ",
                 "index #{index} of #{inspect(expression)} names whitespace"
        end
      end
    end
  end

  describe "positions name the token a reader would blame" do
    test "the reported column holds the expected token text" do
      cases = [
        {"a * true", "*"},
        {"10 / 0", "/"},
        {"10 % 0", "%"},
        {"-name", "-"},
        {"len(1)", "l"},
        {"1 +\n2 * true", "*"}
      ]

      for {expression, expected_char} <- cases do
        {:ok, instructions, positions} = Predicator.compile_with_positions(expression)

        assert {:error, error} =
                 Predicator.evaluate(instructions, %{"name" => "text"}, positions: positions)

        {line, column} = error.position
        source_line = expression |> String.split("\n") |> Enum.at(line - 1)

        assert String.at(source_line, column - 1) == expected_char,
               "#{inspect(expression)} blamed #{inspect(String.at(source_line, column - 1))}"
      end
    end
  end
end
