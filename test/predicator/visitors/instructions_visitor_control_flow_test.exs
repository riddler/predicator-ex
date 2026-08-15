defmodule Predicator.Visitors.InstructionsVisitorControlFlowTest do
  use ExUnit.Case, async: true

  alias Predicator.Visitors.InstructionsVisitor

  describe "visit/2 - assignment statements" do
    test "a root-level assignment stores depth 1" do
      {:ok, {:program, [assignment], _pos}} = Predicator.parse_program("x = 1")
      result = InstructionsVisitor.visit(assignment, [])

      assert result == [["lit", "x"], ["lit", 1], ["store", 1]]
    end

    test "a property-access assignment stores depth 2" do
      {:ok, {:program, [assignment], _pos}} = Predicator.parse_program(~s(user.name = 'Ada'))
      result = InstructionsVisitor.visit(assignment, [])

      assert result == [["lit", "user"], ["lit", "name"], ["lit", "Ada"], ["store", 2]]
    end

    test "a bracket-access assignment with a literal key stores depth 2" do
      {:ok, {:program, [assignment], _pos}} = Predicator.parse_program("a[0] = 1")
      result = InstructionsVisitor.visit(assignment, [])

      assert result == [["lit", "a"], ["lit", 0], ["lit", 1], ["store", 2]]
    end

    test "a computed bracket key proves n is depth, not instruction count" do
      {:ok, {:program, [assignment], _pos}} = Predicator.parse_program("a[k + 1] = 1")
      result = InstructionsVisitor.visit(assignment, [])

      assert result == [
               ["lit", "a"],
               ["load", "k"],
               ["lit", 1],
               ["add"],
               ["lit", 1],
               ["store", 2]
             ]
    end

    test "a mixed property/bracket chain stores depth 4" do
      {:ok, {:program, [assignment], _pos}} =
        Predicator.parse_program(~s(user.items[0].name = 'Ada'))

      result = InstructionsVisitor.visit(assignment, [])

      assert result == [
               ["lit", "user"],
               ["lit", "items"],
               ["lit", 0],
               ["lit", "name"],
               ["lit", "Ada"],
               ["store", 4]
             ]
    end
  end

  describe "visit/2 - programs" do
    test "a bare expression statement gains a trailing pop" do
      {:ok, program} = Predicator.parse_program("x + 1")
      result = InstructionsVisitor.visit(program, [])

      assert result == [["load", "x"], ["lit", 1], ["add"], ["pop"]]
    end

    test "an assignment statement gains no trailing pop" do
      {:ok, program} = Predicator.parse_program("x = 1")
      result = InstructionsVisitor.visit(program, [])

      assert result == [["lit", "x"], ["lit", 1], ["store", 1]]
    end

    test "a multi-statement program of assignments concatenates them uniformly" do
      {:ok, program} = Predicator.parse_program("x = 1; y = 2")
      result = InstructionsVisitor.visit(program, [])

      assert result == [
               ["lit", "x"],
               ["lit", 1],
               ["store", 1],
               ["lit", "y"],
               ["lit", 2],
               ["store", 1]
             ]
    end

    test "a mixed program of assignments and bare expressions compiles each in order" do
      {:ok, program} = Predicator.parse_program("x = 1; y = 2; z + 1")
      result = InstructionsVisitor.visit(program, [])

      assert result == [
               ["lit", "x"],
               ["lit", 1],
               ["store", 1],
               ["lit", "y"],
               ["lit", 2],
               ["store", 1],
               ["load", "z"],
               ["lit", 1],
               ["add"],
               ["pop"]
             ]
    end
  end

  describe "visit/2 - if/else lowering (ADR-0013)" do
    defp visit_program(source) do
      {:ok, program} = Predicator.parse_program(source)
      InstructionsVisitor.visit(program, [])
    end

    test "if with no else" do
      assert visit_program("if a { x = 1 }") == [
               ["load", "a"],
               ["pop_jump_if_falsy", 4],
               ["lit", "x"],
               ["lit", 1],
               ["store", 1]
             ]
    end

    test "if with an else" do
      assert visit_program("if a { x = 1 } else { x = 2 }") == [
               ["load", "a"],
               ["pop_jump_if_falsy", 5],
               ["lit", "x"],
               ["lit", 1],
               ["store", 1],
               ["jump", 4],
               ["lit", "x"],
               ["lit", 2],
               ["store", 1]
             ]
    end

    test "a chained else-if" do
      assert visit_program("if a { } else if b { }") == [
               ["load", "a"],
               ["pop_jump_if_falsy", 2],
               ["jump", 3],
               ["load", "b"],
               ["pop_jump_if_falsy", 1]
             ]
    end

    test "an if nested inside a then block" do
      assert visit_program("if a { if b { x = 1 } }") == [
               ["load", "a"],
               ["pop_jump_if_falsy", 6],
               ["load", "b"],
               ["pop_jump_if_falsy", 4],
               ["lit", "x"],
               ["lit", 1],
               ["store", 1]
             ]
    end

    test "an if nested inside an else block" do
      assert visit_program("if a { } else { if b { x = 1 } }") == [
               ["load", "a"],
               ["pop_jump_if_falsy", 2],
               ["jump", 6],
               ["load", "b"],
               ["pop_jump_if_falsy", 4],
               ["lit", "x"],
               ["lit", 1],
               ["store", 1]
             ]
    end

    test "an empty then block jumps past nothing but the block's own end" do
      assert visit_program("if a { }") == [["load", "a"], ["pop_jump_if_falsy", 1]]
    end

    test "an empty else block still gets a jump" do
      assert visit_program("if a { x = 1 } else { }") == [
               ["load", "a"],
               ["pop_jump_if_falsy", 5],
               ["lit", "x"],
               ["lit", 1],
               ["store", 1],
               ["jump", 1]
             ]
    end

    test "a multi-statement block exercises the lenA arithmetic" do
      assert visit_program("if a { x = 1; y = 2 }") == [
               ["load", "a"],
               ["pop_jump_if_falsy", 7],
               ["lit", "x"],
               ["lit", 1],
               ["store", 1],
               ["lit", "y"],
               ["lit", 2],
               ["store", 1]
             ]
    end

    test "an if statement takes no trailing pop, even as a program's last statement" do
      instructions = visit_program("if a { x = 1 }")

      assert List.last(instructions) == ["store", 1]
      refute Enum.any?(instructions, &(&1 == ["pop"]))
    end

    test "negative control: an ordinary program still returns a plain instruction list" do
      {:ok, program} = Predicator.parse_program("x = 1; x + 1")

      assert InstructionsVisitor.visit(program, []) == [
               ["lit", "x"],
               ["lit", 1],
               ["store", 1],
               ["load", "x"],
               ["lit", 1],
               ["add"],
               ["pop"]
             ]
    end
  end

  describe "visit/2 - while lowering (ADR-0013, px-3so.4 Phase 2)" do
    test "the canonical counted loop matches Phase 1's corpus case byte-identically" do
      # conformance/cases/loops.json's "loops/counted-loop-runs-to-completion"
      # case, minus its trailing hand-authored ["load", "i"] observation
      # instruction - that instruction is not part of the while statement's
      # own lowering, it exists only so the raw-instructions corpus case has
      # something to observe on the stack.
      assert visit_program("i = 0; while i < 3 { i = i + 1 }") == [
               ["lit", "i"],
               ["lit", 0],
               ["store", 1],
               ["load", "i"],
               ["lit", 3],
               ["compare", "LT"],
               ["pop_jump_if_falsy", 7],
               ["lit", "i"],
               ["load", "i"],
               ["lit", 1],
               ["add"],
               ["store", 1],
               ["jump_backward", 9]
             ]
    end

    test "an empty body" do
      # lenC = 3, lenA = 0: pop_jump_if_falsy takes lenA + 2 = 2, landing one
      # past jump_backward; jump_backward takes lenC + lenA + 1 = 4, landing
      # back on the condition's first instruction.
      assert visit_program("while i < 3 { }") == [
               ["load", "i"],
               ["lit", 3],
               ["compare", "LT"],
               ["pop_jump_if_falsy", 2],
               ["jump_backward", 4]
             ]
    end

    test "a multi-statement body" do
      assert visit_program("while a { x = 1; y = 2 }") == [
               ["load", "a"],
               ["pop_jump_if_falsy", 8],
               ["lit", "x"],
               ["lit", 1],
               ["store", 1],
               ["lit", "y"],
               ["lit", 2],
               ["store", 1],
               ["jump_backward", 8]
             ]
    end

    test "a nested while - the inner back edge does not reach past the outer condition" do
      assert visit_program("while a { while b { x = 1 } }") == [
               ["load", "a"],
               ["pop_jump_if_falsy", 8],
               ["load", "b"],
               ["pop_jump_if_falsy", 5],
               ["lit", "x"],
               ["lit", 1],
               ["store", 1],
               ["jump_backward", 5],
               ["jump_backward", 8]
             ]
    end

    test "a while statement takes no trailing pop, even as a program's last statement" do
      instructions = visit_program("while a { x = 1 }")

      assert List.last(instructions) == ["jump_backward", 5]
      refute Enum.any?(instructions, &(&1 == ["pop"]))
    end
  end
end
