defmodule Predicator.Evaluator.JumpOpcodesTest do
  @moduledoc """
  Direct `Evaluator` coverage for the ISA v5 opcodes `jump` and
  `pop_jump_if_falsy` (ADR-0013, `docs/isa.md` section 5).

  These are hand-built instruction lists, not source-compiled ones - the
  compiler does not emit either opcode yet (`px-3so.3`, Phase 1). Phase 2
  (`px-3so.3`'s follow-on) wires the `InstructionsVisitor` and gets its own
  coverage through `Predicator.execute/2`.
  """

  use ExUnit.Case, async: true

  alias Predicator.Errors.{EvaluationError, TypeMismatchError}
  alias Predicator.Evaluator

  describe "jump" do
    test "moves the instruction pointer to index + offset and pushes nothing" do
      instructions = [["lit", 1], ["jump", 2], ["lit", "unreached"], ["lit", 2]]

      assert {:ok, final} = Evaluator.run_state(%Evaluator{instructions: instructions})
      assert final.stack == [2, 1]
    end

    test "landing exactly past the end of the list is a normal halt" do
      instructions = [["lit", 1], ["jump", 1]]

      assert {:ok, final} = Evaluator.run_state(%Evaluator{instructions: instructions})
      assert final.stack == [1]
    end

    test "an offset of 0 falls through to unknown_instruction" do
      instructions = [["jump", 0]]

      result = Evaluator.evaluate(instructions)
      assert {:error, %EvaluationError{message: msg}} = result
      assert msg =~ "Unknown instruction"
    end

    test "a non-integer offset falls through to unknown_instruction" do
      instructions = [["jump", "2"]]

      result = Evaluator.evaluate(instructions)
      assert {:error, %EvaluationError{message: msg}} = result
      assert msg =~ "Unknown instruction"
    end
  end

  describe "pop_jump_if_falsy" do
    test "jumps and pops on false" do
      instructions = [["lit", false], ["pop_jump_if_falsy", 2], ["lit", "unreached"]]

      assert {:ok, final} = Evaluator.run_state(%Evaluator{instructions: instructions})
      assert final.stack == []
    end

    test "jumps and pops on :undefined" do
      instructions = [["load", "missing"], ["pop_jump_if_falsy", 2], ["lit", "unreached"]]

      assert {:ok, final} =
               Evaluator.run_state(%Evaluator{instructions: instructions, context: %{}})

      assert final.stack == []
    end

    test "pops and falls through on exactly true" do
      instructions = [["lit", true], ["pop_jump_if_falsy", 2], ["lit", 5]]

      assert {:ok, final} = Evaluator.run_state(%Evaluator{instructions: instructions})
      assert final.stack == [5]
    end

    test "an integer condition is a TypeMismatchError naming pop_jump_if_falsy and boolean" do
      instructions = [["lit", 1], ["pop_jump_if_falsy", 2], ["lit", "unreached"]]

      result = Evaluator.evaluate(instructions)

      assert {:error, %TypeMismatchError{operation: :pop_jump_if_falsy, expected: :boolean}} =
               result
    end

    test "a string condition is a TypeMismatchError naming pop_jump_if_falsy and boolean" do
      instructions = [["lit", "x"], ["pop_jump_if_falsy", 2], ["lit", "unreached"]]

      result = Evaluator.evaluate(instructions)

      assert {:error, %TypeMismatchError{operation: :pop_jump_if_falsy, expected: :boolean}} =
               result
    end

    test "a list condition is a TypeMismatchError naming pop_jump_if_falsy and boolean" do
      instructions = [["lit", [1, 2]], ["pop_jump_if_falsy", 2], ["lit", "unreached"]]

      result = Evaluator.evaluate(instructions)

      assert {:error, %TypeMismatchError{operation: :pop_jump_if_falsy, expected: :boolean}} =
               result
    end

    test "an empty stack is an insufficient-operands EvaluationError" do
      instructions = [["pop_jump_if_falsy", 2]]

      result = Evaluator.evaluate(instructions)
      assert {:error, %EvaluationError{message: msg}} = result
      assert msg =~ "requires 1 value"
    end

    test "an offset of 0 falls through to unknown_instruction" do
      instructions = [["lit", true], ["pop_jump_if_falsy", 0]]

      result = Evaluator.evaluate(instructions)
      assert {:error, %EvaluationError{message: msg}} = result
      assert msg =~ "Unknown instruction"
    end

    test "a non-integer offset falls through to unknown_instruction" do
      instructions = [["lit", true], ["pop_jump_if_falsy", "2"]]

      result = Evaluator.evaluate(instructions)
      assert {:error, %EvaluationError{message: msg}} = result
      assert msg =~ "Unknown instruction"
    end

    test "does not write the evaluator's last-popped-value field" do
      instructions = [["lit", false], ["pop_jump_if_falsy", 1]]

      assert {:ok, final} = Evaluator.run_state(%Evaluator{instructions: instructions})
      assert Evaluator.last_value(final) == :undefined
    end
  end

  describe "Predicator.execute_value/2 is unaffected by pop_jump_if_falsy" do
    test "the popped condition is not reported as the last statement's value" do
      instructions = [
        ["lit", false],
        ["pop_jump_if_falsy", 3],
        ["lit", "unreached"],
        ["pop"],
        ["lit", 42],
        ["pop"]
      ]

      assert {:ok, 42, _ctx} = Predicator.execute_value(instructions, %{})
    end
  end
end
