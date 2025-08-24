defmodule EvaluatorEdgeCasesTest do
  use ExUnit.Case, async: true

  import Predicator
  alias Predicator.Evaluator

  describe "evaluator edge cases" do
    test "evaluator with instruction pointer beyond bounds finishes normally" do
      # Create evaluator with instruction pointer beyond instructions
      evaluator = %Evaluator{
        instructions: [["lit", 42]],
        # Beyond array bounds
        instruction_pointer: 5,
        stack: [],
        context: %{}
      }

      # Should halt normally, not error
      assert {:ok, final_evaluator} = Evaluator.step(evaluator)
      assert final_evaluator.halted == true
    end

    test "comparison with insufficient stack values" do
      # Missing second value
      instructions = [["lit", 42], ["compare", "GT"]]

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert msg =~ "Comparison requires 2 values on stack, got: 1"
    end

    test "logical operators with insufficient stack values" do
      # AND with only one value
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate([["lit", true], ["and"]], %{})

      assert msg =~ "Logical AND requires 2 values on stack, got: 1"

      # OR with no values
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate([["or"]], %{})

      assert msg =~ "Logical OR requires 2 values on stack, got: 0"

      # NOT with no values
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate([["not"]], %{})

      assert msg =~ "Logical NOT requires 1 value on stack, got: 0"
    end

    test "logical operators with wrong types" do
      # AND with non-boolean values
      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               Evaluator.evaluate([["lit", 42], ["lit", "text"], ["and"]], %{})

      assert msg =~ "Logical AND requires booleans"

      # OR with non-boolean values
      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               Evaluator.evaluate([["lit", [1, 2, 3]], ["lit", true], ["or"]], %{})

      assert msg =~ "Logical OR requires booleans"

      # NOT with non-boolean value
      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               Evaluator.evaluate([["lit", 42], ["not"]], %{})

      assert msg =~ "Logical NOT requires a boolean, got 42"
    end

    test "membership with insufficient stack values" do
      # IN with only one value
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate([["lit", 1], ["in"]], %{})

      assert msg =~ "In requires 2 values on stack, got: 1"

      # CONTAINS with no values
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate([["contains"]], %{})

      assert msg =~ "Contains requires 2 values on stack, got: 0"
    end

    test "membership with non-list values" do
      # IN with right operand not being a list
      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               Evaluator.evaluate([["lit", 1], ["lit", "not_a_list"], ["in"]], %{})

      assert msg =~ "requires a list"

      # CONTAINS with left operand not being a list
      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               Evaluator.evaluate([["lit", "not_a_list"], ["lit", 1], ["contains"]], %{})

      assert msg =~ "requires a list"
    end

    test "function call with insufficient stack values" do
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate([["call", "len", 1]], %{})

      assert msg =~ "Function len() expects 1 arguments, but only 0 values on stack"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate([["lit", "hello"], ["call", "max", 2]], %{})

      assert msg =~ "Function max() expects 2 arguments, but only 1 values on stack"
    end

    test "function call with unknown function" do
      instructions = [["lit", 42], ["call", "unknown_function", 1]]

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert msg =~ "Unknown function: unknown_function"
    end

    test "function call with negative arg count" do
      instructions = [["call", "len", -1]]

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert msg =~ "Unknown instruction:"
    end

    test "undefined variable comparison edge cases" do
      # Both values undefined should be equal
      assert {:ok, :undefined} = evaluate("undefined_a = undefined_b", %{})

      # Undefined with defined should be undefined
      assert {:ok, :undefined} = evaluate("undefined_var > 5", %{})
      assert {:ok, :undefined} = evaluate("5 < undefined_var", %{})
    end

    test "mixed type comparisons return undefined" do
      # String to number comparison
      assert {:ok, :undefined} = evaluate("'hello' > 42", %{})

      # Boolean to number comparison
      assert {:ok, :undefined} = evaluate("true = 1", %{})

      # List to string comparison
      assert {:ok, :undefined} = evaluate("[1,2,3] != 'hello'", %{})

      # Date to number comparison
      assert {:ok, :undefined} = evaluate("#2024-01-01# > 100", %{})
    end

    test "values_equal helper function edge cases with undefined" do
      # Test membership operations with undefined values
      assert {:ok, :undefined} = evaluate("undefined_var in [1, 2, 3]", %{})
      assert {:ok, :undefined} = evaluate("1 in undefined_list", %{})
      assert {:ok, :undefined} = evaluate("[1, 2, 3] contains undefined_var", %{})
      assert {:ok, :undefined} = evaluate("undefined_list contains 1", %{})
    end

    test "unknown instruction type" do
      # Instructions with invalid format
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate([["invalid_instruction", "param"]], %{})

      assert msg =~ "Unknown instruction:"

      # Malformed instruction
      # Missing operator
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate([["compare"]], %{})

      assert msg =~ "Unknown instruction:"

      # Instructions with wrong number of params
      # Missing value
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate([["lit"]], %{})

      assert msg =~ "Unknown instruction:"
    end
  end

  describe "evaluator state management" do
    test "step on finished evaluator" do
      evaluator = %Evaluator{
        instructions: [["lit", 42]],
        # Past end of instructions
        instruction_pointer: 1,
        stack: [42],
        context: %{}
      }

      {:ok, final_evaluator} = Evaluator.step(evaluator)
      assert final_evaluator.halted == true
    end
  end
end
