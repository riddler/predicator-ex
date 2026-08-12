defmodule Predicator.Evaluator.JumpBackwardTest do
  @moduledoc """
  Direct `Evaluator` coverage for the ISA v6 opcode `jump_backward` and the
  loop budget it charges (ADR-0013, `docs/isa.md` section 5).

  These are hand-built instruction lists, not source-compiled ones - the
  compiler does not emit `jump_backward` yet (`px-3so.4` Phase 1; Phase 2
  wires `while` and `InstructionsVisitor`).
  """

  use ExUnit.Case, async: true

  alias Predicator.Errors.EvaluationError
  alias Predicator.Evaluator

  describe "jump_backward" do
    test "a single step lands the instruction pointer on ip - offset, and pops/pushes nothing" do
      instructions = [["lit", 1], ["lit", 2], ["jump_backward", 2]]
      evaluator = %Evaluator{instructions: instructions, instruction_pointer: 2, stack: [:marker]}

      assert {:ok, next} = Evaluator.step(evaluator)
      assert next.instruction_pointer == 0
      assert next.stack == [:marker]
      assert next.loop_budget == Evaluator.default_loop_budget() - 1
    end

    test "a counted loop terminates with the expected stack top" do
      # while i < 3 { i = i + 1 }; load i (docs/isa.md section 5's worked example)
      instructions = [
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
        ["jump_backward", 9],
        ["load", "i"]
      ]

      assert {:ok, final} = Evaluator.run_state(%Evaluator{instructions: instructions})
      assert final.stack == [3]
      assert final.context == %{"i" => 3}
    end

    test "the budget decrements once per back edge" do
      instructions = [
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
        ["jump_backward", 9],
        ["load", "i"]
      ]

      assert {:ok, final} =
               Evaluator.run_state(%Evaluator{instructions: instructions, loop_budget: 10})

      # Three back edges taken (i goes 0 -> 1 -> 2 -> 3), so the budget is
      # decremented exactly three times: 10 - 3 = 7.
      assert final.loop_budget == 7
    end

    test "a program with no back edge leaves the budget untouched" do
      instructions = [["lit", 1], ["lit", 2], ["add"]]

      assert {:ok, final} =
               Evaluator.run_state(%Evaluator{instructions: instructions, loop_budget: 42})

      assert final.loop_budget == 42
    end

    test "exhaustion is a loop_budget_exceeded EvaluationError naming jump_backward, with the failing instruction's position" do
      instructions = [["lit", true], ["pop_jump_if_falsy", 2], ["jump_backward", 2]]
      positions = %{2 => {1, 10}}

      assert {:error, error, _final} =
               Evaluator.run_state(%Evaluator{
                 instructions: instructions,
                 loop_budget: 0,
                 positions: positions
               })

      assert %EvaluationError{
               reason: "loop_budget_exceeded",
               operation: :jump_backward,
               position: {1, 10}
             } = error
    end

    test "a budget of 0 forbids the first back edge" do
      instructions = [["lit", true], ["pop_jump_if_falsy", 2], ["jump_backward", 2]]

      assert {:error, %EvaluationError{reason: "loop_budget_exceeded"}, _final} =
               Evaluator.run_state(%Evaluator{instructions: instructions, loop_budget: 0})
    end

    test "an offset of 0 falls through to unknown_instruction" do
      instructions = [["lit", 1], ["jump_backward", 0]]

      result = Evaluator.evaluate(instructions)
      assert {:error, %EvaluationError{message: msg}} = result
      assert msg =~ "Unknown instruction"
    end

    test "a negative offset falls through to unknown_instruction" do
      instructions = [["lit", 1], ["jump_backward", -1]]

      result = Evaluator.evaluate(instructions)
      assert {:error, %EvaluationError{message: msg}} = result
      assert msg =~ "Unknown instruction"
    end

    test "a non-integer offset falls through to unknown_instruction" do
      instructions = [["lit", 1], ["jump_backward", "x"]]

      result = Evaluator.evaluate(instructions)
      assert {:error, %EvaluationError{message: msg}} = result
      assert msg =~ "Unknown instruction"
    end

    test "a target before index 0 falls through to unknown_instruction" do
      instructions = [["lit", 1], ["jump_backward", 5]]

      result = Evaluator.evaluate(instructions)
      assert {:error, %EvaluationError{message: msg}} = result
      assert msg =~ "Unknown instruction"
    end

    test "does not write the evaluator's last-popped-value field" do
      instructions = [["lit", true], ["pop_jump_if_falsy", 2], ["jump_backward", 2]]

      assert {:error, _error, final} =
               Evaluator.run_state(%Evaluator{instructions: instructions, loop_budget: 1})

      assert Evaluator.last_value(final) == :undefined
    end
  end

  describe "Predicator.execute_value/2 is unaffected by jump_backward" do
    test "the last expression statement's value is still reported correctly" do
      instructions = [
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
        ["jump_backward", 9],
        ["load", "i"],
        ["pop"],
        ["lit", 42],
        ["pop"]
      ]

      assert {:ok, 42, ctx} = Predicator.execute_value(instructions, %{})
      assert ctx.data == %{"i" => 3}
    end
  end
end
