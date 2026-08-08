defmodule Predicator.Visitors.InstructionsVisitorPositionsTest do
  use ExUnit.Case, async: true

  alias Predicator.Visitors.InstructionsVisitor

  # A corpus wide enough to hit every node type. Reused by the invariant tests
  # at the bottom, which are the ones that would catch the annotated traversal
  # drifting away from the plain one.
  @corpus [
    "42",
    ~s("hello"),
    "score",
    "score > 85",
    "1 + 2 * 3",
    "-x",
    "!flag",
    "a AND b",
    "a OR b",
    "NOT a",
    "[1, 2, 3]",
    "[a, 2]",
    "[]",
    "{name: 'John'}",
    "{}",
    ~s({"first name": 1}),
    "x IN [1, 2]",
    "tags CONTAINS 'a'",
    "len(name)",
    "len(upper(name))",
    "Math.max(a, b)",
    "items[0]",
    "a[0][1]",
    "user.name",
    "user.profile.email",
    "3d8h",
    "3d ago",
    "2w from now",
    "next 1d",
    "last 1d",
    "a > 1 AND b < 2 OR c == 3"
  ]

  defp table(expression) do
    {:ok, ast} = Predicator.parse(expression)
    InstructionsVisitor.visit_with_positions(ast)
  end

  describe "visit_with_positions/2 - leaves" do
    test "a literal takes its own token's position" do
      assert table("42") == {[["lit", 42]], %{0 => {1, 1}}}
    end

    test "a string literal takes its own token's position" do
      assert table(~s(  "hi")) == {[["lit", "hi"]], %{0 => {1, 3}}}
    end

    test "an identifier takes its own token's position" do
      assert table("  score") == {[["load", "score"]], %{0 => {1, 3}}}
    end

    test "a duration takes its first number's position" do
      assert table("3d8h") == {[["duration", [[3, "d"], [8, "h"]]]], %{0 => {1, 1}}}
    end
  end

  describe "visit_with_positions/2 - operators point at the operator token" do
    test "comparison" do
      assert table("score > 85") ==
               {[["load", "score"], ["lit", 85], ["compare", "GT"]],
                %{0 => {1, 1}, 1 => {1, 9}, 2 => {1, 7}}}
    end

    test "arithmetic" do
      {instructions, positions} = table("a * b")

      assert instructions == [["load", "a"], ["load", "b"], ["multiply"]]
      assert positions == %{0 => {1, 1}, 1 => {1, 5}, 2 => {1, 3}}
    end

    test "membership" do
      {instructions, positions} = table("a IN [1]")

      assert instructions == [["load", "a"], ["lit", [1]], ["in"]]
      assert positions == %{0 => {1, 1}, 1 => {1, 6}, 2 => {1, 3}}
    end

    test "unary minus" do
      {instructions, positions} = table("-a")

      assert instructions == [["load", "a"], ["unary_minus"]]
      assert positions == %{0 => {1, 2}, 1 => {1, 1}}
    end

    test "logical not" do
      {instructions, positions} = table("NOT a")

      assert instructions == [["load", "a"], ["not"]]
      assert positions == %{0 => {1, 5}, 1 => {1, 1}}
    end
  end

  describe "visit_with_positions/2 - short-circuit jumps" do
    test "the AND jump carries the operator's position and keeps its offset" do
      {instructions, positions} = table("a > 1 AND b < 2")

      assert instructions == [
               ["load", "a"],
               ["lit", 1],
               ["compare", "GT"],
               ["jump_if_falsy_or_pop", 4],
               ["load", "b"],
               ["lit", 2],
               ["compare", "LT"]
             ]

      assert positions == %{
               0 => {1, 1},
               1 => {1, 5},
               2 => {1, 3},
               3 => {1, 7},
               4 => {1, 11},
               5 => {1, 15},
               6 => {1, 13}
             }
    end

    test "the OR jump carries the operator's position and keeps its offset" do
      {instructions, positions} = table("a OR b")

      assert instructions == [
               ["load", "a"],
               ["jump_if_true_or_pop", 2],
               ["load", "b"]
             ]

      assert positions == %{0 => {1, 1}, 1 => {1, 3}, 2 => {1, 6}}
    end

    test "a jump offset still lands past the right branch when it is long" do
      {instructions, _positions} = table("a AND (b + c + d + e)")

      assert Enum.at(instructions, 1) == ["jump_if_falsy_or_pop", 8]
      assert length(instructions) == 9
    end
  end

  describe "visit_with_positions/2 - lists and objects" do
    test "the all-literal fast path collapses to one instruction at the list's bracket" do
      {instructions, positions} = table("  [1, 2, 3]")

      assert instructions == [["lit", [1, 2, 3]]]
      assert positions == %{0 => {1, 3}}
    end

    test "a non-literal list gives each element its own position" do
      {instructions, positions} = table("[a, 2]")

      assert instructions == [["load", "a"], ["lit", 2], ["make_list", 2]]
      assert positions == %{0 => {1, 2}, 1 => {1, 5}, 2 => {1, 1}}
    end

    test "an empty list has a position but no children" do
      assert table("[]") == {[["lit", []]], %{0 => {1, 1}}}
    end

    test "object_new takes the brace and each object_set takes its key" do
      {instructions, positions} = table("{name: a}")

      assert instructions == [["object_new"], ["load", "a"], ["object_set", "name"]]
      assert positions == %{0 => {1, 1}, 1 => {1, 8}, 2 => {1, 2}}
    end

    test "a string-literal object key carries its own position" do
      {instructions, positions} = table(~s({"first name": a}))

      assert instructions == [["object_new"], ["load", "a"], ["object_set", "first name"]]
      assert positions == %{0 => {1, 1}, 1 => {1, 16}, 2 => {1, 2}}
    end

    test "an empty object has a position but no children" do
      assert table("{}") == {[["object_new"]], %{0 => {1, 1}}}
    end
  end

  describe "visit_with_positions/2 - calls and access chains" do
    test "a nested call does not leak the inner call's position to the outer" do
      {instructions, positions} = table("len(upper(name))")

      assert instructions == [["load", "name"], ["call", "upper", 1], ["call", "len", 1]]
      assert positions == %{0 => {1, 11}, 1 => {1, 5}, 2 => {1, 1}}
    end

    test "a bracket access chain gives each access its own position" do
      {instructions, positions} = table("a[0][1]")

      assert instructions == [
               ["load", "a"],
               ["lit", 0],
               ["bracket_access"],
               ["lit", 1],
               ["bracket_access"]
             ]

      assert positions == %{0 => {1, 1}, 1 => {1, 3}, 2 => {1, 2}, 3 => {1, 6}, 4 => {1, 5}}
    end

    test "property access points at the dot" do
      {instructions, positions} = table("user.name")

      assert instructions == [["load", "user"], ["access", "name"]]
      assert positions == %{0 => {1, 1}, 1 => {1, 5}}
    end

    test "a relative date points at its direction keyword" do
      {instructions, positions} = table("3d ago")

      assert instructions == [["duration", [[3, "d"]]], ["relative_date", "ago"]]
      assert positions == %{0 => {1, 1}, 1 => {1, 4}}
    end
  end

  describe "visit_with_positions/2 - multi-line input" do
    test "second-line tokens report line 2" do
      {instructions, positions} = table("a >\n  85")

      assert instructions == [["load", "a"], ["lit", 85], ["compare", "GT"]]
      assert positions == %{0 => {1, 1}, 1 => {2, 3}, 2 => {1, 3}}
    end
  end

  describe "visit_with_positions/2 - position-free input" do
    test "a fully position-free AST yields an empty table" do
      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}

      assert InstructionsVisitor.visit_with_positions(ast) ==
               {[["load", "score"], ["lit", 85], ["compare", "GT"]], %{}}
    end

    test "a mixed AST yields a partial table" do
      ast = {:comparison, :gt, {:identifier, "score", {1, 1}}, {:literal, 85, nil}, nil}

      assert InstructionsVisitor.visit_with_positions(ast) ==
               {[["load", "score"], ["lit", 85], ["compare", "GT"]], %{0 => {1, 1}}}
    end

    test "an explicit nil position is omitted rather than stored" do
      assert InstructionsVisitor.visit_with_positions({:literal, 42, nil}) ==
               {[["lit", 42]], %{}}
    end
  end

  describe "visit_with_positions/2 - statements" do
    defp program_table(source) do
      {:ok, program} = Predicator.parse_program(source)
      InstructionsVisitor.visit_with_positions(program)
    end

    test "the store instruction carries the lhs root segment's position" do
      {instructions, positions} = program_table("x = 1")

      assert instructions == [["lit", "x"], ["lit", 1], ["store", 1]]
      # segment "x" at its own token, rhs "1" at its own token, store at the
      # lhs root "x" (not the "=")
      assert positions == %{0 => {1, 1}, 1 => {1, 5}, 2 => {1, 1}}
    end

    test "segment lit instructions carry their own accessor's position" do
      {instructions, positions} = program_table(~s(user.name = 'Ada'))

      assert instructions == [
               ["lit", "user"],
               ["lit", "name"],
               ["lit", "Ada"],
               ["store", 2]
             ]

      # "user" at its token, "name" at the dot-property token, "Ada" at its
      # token, store at the lhs root "user" (not the "=")
      assert positions == %{0 => {1, 1}, 1 => {1, 5}, 2 => {1, 13}, 3 => {1, 1}}
    end

    test "a bracket-access segment's key carries its own token's position" do
      {instructions, positions} = program_table("a[0] = 1")

      assert instructions == [["lit", "a"], ["lit", 0], ["lit", 1], ["store", 2]]
      # store at the lhs root "a" (not the "=")
      assert positions == %{0 => {1, 1}, 1 => {1, 3}, 2 => {1, 8}, 3 => {1, 1}}
    end

    test "a bare expression statement's pop takes the statement node's own position" do
      {instructions, positions} = program_table("x + 1")

      assert instructions == [["load", "x"], ["lit", 1], ["add"], ["pop"]]
      assert positions == %{0 => {1, 1}, 1 => {1, 5}, 2 => {1, 3}, 3 => {1, 3}}
    end

    test "a mixed program keeps each statement's positions independent" do
      {instructions, positions} = program_table("x = 1; y + 1")

      assert instructions == [
               ["lit", "x"],
               ["lit", 1],
               ["store", 1],
               ["load", "y"],
               ["lit", 1],
               ["add"],
               ["pop"]
             ]

      assert positions == %{
               0 => {1, 1},
               1 => {1, 5},
               2 => {1, 1},
               3 => {1, 8},
               4 => {1, 12},
               5 => {1, 10},
               6 => {1, 10}
             }
    end

    test "span mode keeps the assignment's span" do
      {:ok, program} = Predicator.parse_program("a = 1; a.b = 2", spans: true)

      {instructions, positions} = InstructionsVisitor.visit_with_positions(program)

      assert instructions == [
               ["lit", "a"],
               ["lit", 1],
               ["store", 1],
               ["lit", "a"],
               ["lit", "b"],
               ["lit", 2],
               ["store", 2]
             ]

      assert positions[2] == {{1, 1}, {1, 6}}
      assert positions[6] == {{1, 8}, {1, 15}}
    end

    test "a deep chain still blames the root" do
      {instructions, positions} = program_table("a.b.c = 1")

      assert instructions == [
               ["lit", "a"],
               ["lit", "b"],
               ["lit", "c"],
               ["lit", 1],
               ["store", 3]
             ]

      # store blames the lhs root "a", not ".b", ".c", or the "="
      assert positions[4] == {1, 1}
    end
  end

  describe "invariants over the corpus" do
    test "visit/2 returns exactly the instruction list visit_with_positions/2 returns" do
      for expression <- @corpus do
        {:ok, ast} = Predicator.parse(expression)
        {instructions, _positions} = InstructionsVisitor.visit_with_positions(ast)

        assert InstructionsVisitor.visit(ast) == instructions,
               "instruction lists diverged for #{inspect(expression)}"
      end
    end

    test "Predicator.compile/1 is unchanged by the annotated traversal" do
      for expression <- @corpus do
        {:ok, ast} = Predicator.parse(expression)
        {instructions, _positions} = InstructionsVisitor.visit_with_positions(ast)

        assert Predicator.compile(expression) == {:ok, instructions},
               "compile/1 diverged for #{inspect(expression)}"
      end
    end

    test "every instruction from a parsed expression has a position" do
      for expression <- @corpus do
        {:ok, ast} = Predicator.parse(expression)
        {instructions, positions} = InstructionsVisitor.visit_with_positions(ast)

        assert map_size(positions) == length(instructions),
               "#{inspect(expression)} left some instruction without a position"
      end
    end

    test "blanking every slot yields the same instructions and an empty table" do
      for expression <- @corpus do
        {:ok, ast} = Predicator.parse(expression)
        blanked = Predicator.ASTShape.blank(ast)

        assert InstructionsVisitor.visit_with_positions(blanked) ==
                 {InstructionsVisitor.visit(ast), %{}},
               "blanked AST diverged for #{inspect(expression)}"
      end
    end
  end
end
