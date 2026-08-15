defmodule Predicator.EvaluatorLogicalTest do
  use ExUnit.Case, async: true

  alias Predicator.Evaluator

  describe "retired and/or opcodes" do
    test "and is refused with retired_opcode, naming ISA v3 and upgrade/1" do
      instructions = [["lit", true], ["lit", true], ["and"]]
      result = Evaluator.evaluate(instructions)

      assert {:error, %Predicator.Errors.EvaluationError{reason: "retired_opcode", message: msg}} =
               result

      assert msg =~ "and"
      assert msg =~ "ISA v3"
      assert msg =~ "Predicator.Instructions.upgrade/1"
    end

    test "or is refused with retired_opcode, naming ISA v3 and upgrade/1" do
      instructions = [["lit", false], ["lit", true], ["or"]]
      result = Evaluator.evaluate(instructions)

      assert {:error, %Predicator.Errors.EvaluationError{reason: "retired_opcode", message: msg}} =
               result

      assert msg =~ "or"
      assert msg =~ "ISA v3"
      assert msg =~ "Predicator.Instructions.upgrade/1"
    end

    test "and is refused regardless of operand types or stack depth" do
      assert {:error, %Predicator.Errors.EvaluationError{reason: "retired_opcode"}} =
               Evaluator.evaluate([["lit", 1], ["lit", "hello"], ["and"]])

      assert {:error, %Predicator.Errors.EvaluationError{reason: "retired_opcode"}} =
               Evaluator.evaluate([["lit", true], ["and"]])

      assert {:error, %Predicator.Errors.EvaluationError{reason: "retired_opcode"}} =
               Evaluator.evaluate([["and"]])
    end

    test "or is refused regardless of operand types or stack depth" do
      assert {:error, %Predicator.Errors.EvaluationError{reason: "retired_opcode"}} =
               Evaluator.evaluate([["lit", 42], ["lit", true], ["or"]])

      assert {:error, %Predicator.Errors.EvaluationError{reason: "retired_opcode"}} =
               Evaluator.evaluate([["lit", false], ["or"]])

      assert {:error, %Predicator.Errors.EvaluationError{reason: "retired_opcode"}} =
               Evaluator.evaluate([["or"]])
    end
  end

  describe "logical operators" do
    test "evaluates logical NOT with true value" do
      instructions = [["lit", true], ["not"]]
      assert Evaluator.evaluate(instructions) == false
    end

    test "evaluates logical NOT with false value" do
      instructions = [["lit", false], ["not"]]
      assert Evaluator.evaluate(instructions) == true
    end

    test "returns error for logical NOT with non-boolean value" do
      instructions = [["lit", 123], ["not"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} = result
      assert msg =~ "Logical NOT requires a boolean, got 123"
    end

    test "returns error for logical NOT with empty stack" do
      instructions = [["not"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg =~ "Logical NOT requires 1 value on stack, got: 0"
    end

    test "complex logical expression with variables" do
      # (score > 85 AND age >= 18) OR admin = true, in jump form (the compiler
      # has emitted jumps rather than and/or since 3.7.0; and/or is retired at
      # ISA v3 and this expresses the same program the two opcodes used to).
      instructions = [
        ["load", "score"],
        ["lit", 85],
        ["compare", "GT"],
        ["jump_if_falsy_or_pop", 4],
        ["load", "age"],
        ["lit", 18],
        ["compare", "GTE"],
        ["jump_if_true_or_pop", 4],
        ["load", "admin"],
        ["lit", true],
        ["compare", "EQ"]
      ]

      context = %{"score" => 90, "age" => 20, "admin" => false}
      assert Evaluator.evaluate(instructions, context) == true

      context = %{"score" => 80, "age" => 16, "admin" => false}
      assert Evaluator.evaluate(instructions, context) == false

      context = %{"score" => 80, "age" => 16, "admin" => true}
      assert Evaluator.evaluate(instructions, context) == true
    end

    test "nested NOT expressions" do
      # NOT (NOT true)
      instructions = [["lit", true], ["not"], ["not"]]
      assert Evaluator.evaluate(instructions) == true

      # NOT (NOT (NOT false))
      instructions = [["lit", false], ["not"], ["not"], ["not"]]
      assert Evaluator.evaluate(instructions) == true
    end

    test "mixed comparison and logical operations" do
      # score > 85 AND NOT expired, in jump form (see the composite test
      # above for why)
      instructions = [
        ["load", "score"],
        ["lit", 85],
        ["compare", "GT"],
        ["jump_if_falsy_or_pop", 3],
        ["load", "expired"],
        ["not"]
      ]

      context = %{"score" => 90, "expired" => false}
      assert Evaluator.evaluate(instructions, context) == true

      context = %{"score" => 80, "expired" => false}
      assert Evaluator.evaluate(instructions, context) == false

      context = %{"score" => 90, "expired" => true}
      assert Evaluator.evaluate(instructions, context) == false
    end
  end

  describe "short-circuit jump instructions" do
    test "jump_if_falsy_or_pop with false on top jumps, leaving false as the result" do
      instructions = [["lit", false], ["jump_if_falsy_or_pop", 3], ["lit", 1], ["divide"]]
      assert Evaluator.evaluate(instructions) == false
    end

    test "jump_if_falsy_or_pop with :undefined on top jumps, leaving :undefined as the result" do
      instructions = [["load", "missing"], ["jump_if_falsy_or_pop", 3], ["lit", 1], ["divide"]]
      assert Evaluator.evaluate(instructions) == :undefined
    end

    test "jump_if_falsy_or_pop with true on top pops and falls through" do
      instructions = [["lit", true], ["jump_if_falsy_or_pop", 2], ["lit", 5]]
      assert Evaluator.evaluate(instructions) == 5
    end

    test "jump_if_falsy_or_pop with a non-boolean, non-undefined top is a type mismatch" do
      instructions = [["lit", 42], ["jump_if_falsy_or_pop", 2], ["lit", 5]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} = result
      assert msg =~ "Logical AND"
    end

    test "jump_if_falsy_or_pop with empty stack is an insufficient-operands error" do
      instructions = [["jump_if_falsy_or_pop", 2]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg =~ "requires 1 value"
    end

    test "jump_if_true_or_pop with true on top jumps, leaving true as the result" do
      instructions = [["lit", true], ["jump_if_true_or_pop", 3], ["lit", 1], ["divide"]]
      assert Evaluator.evaluate(instructions) == true
    end

    test "jump_if_true_or_pop with :undefined on top pops and falls through" do
      instructions = [["load", "missing"], ["jump_if_true_or_pop", 2], ["lit", 5]]
      assert Evaluator.evaluate(instructions) == 5
    end

    test "jump_if_true_or_pop with false on top pops and falls through" do
      instructions = [["lit", false], ["jump_if_true_or_pop", 2], ["lit", 5]]
      assert Evaluator.evaluate(instructions) == 5
    end

    test "jump_if_true_or_pop with a non-boolean, non-undefined top is a type mismatch" do
      instructions = [["lit", 42], ["jump_if_true_or_pop", 2], ["lit", 5]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} = result
      assert msg =~ "Logical OR"
    end

    test "jump_if_true_or_pop with empty stack is an insufficient-operands error" do
      instructions = [["jump_if_true_or_pop", 2]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg =~ "requires 1 value"
    end

    test "malformed offset falls through to unknown instruction" do
      instructions = [["lit", true], ["jump_if_falsy_or_pop", 0]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg =~ "Unknown instruction"

      instructions = [["lit", true], ["jump_if_falsy_or_pop", "2"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg =~ "Unknown instruction"
    end

    test "a jump landing exactly at the end of the instruction list finishes cleanly" do
      instructions = [["lit", false], ["jump_if_falsy_or_pop", 1]]
      assert Evaluator.evaluate(instructions) == false
    end
  end
end
