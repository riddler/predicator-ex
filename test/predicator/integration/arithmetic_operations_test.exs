defmodule ArithmeticEvaluationTest do
  use ExUnit.Case, async: true

  import Predicator

  alias Predicator.Evaluator

  describe "arithmetic instruction evaluation" do
    test "evaluates addition instruction" do
      instructions = [["lit", 5], ["lit", 3], ["add"]]
      result = Evaluator.evaluate(instructions, %{})
      assert result == 8
    end

    test "evaluates subtraction instruction" do
      instructions = [["lit", 10], ["lit", 4], ["subtract"]]
      result = Evaluator.evaluate(instructions, %{})
      assert result == 6
    end

    test "evaluates multiplication instruction" do
      instructions = [["lit", 6], ["lit", 7], ["multiply"]]
      result = Evaluator.evaluate(instructions, %{})
      assert result == 42
    end

    test "evaluates division instruction" do
      instructions = [["lit", 15], ["lit", 3], ["divide"]]
      result = Evaluator.evaluate(instructions, %{})
      assert result == 5
    end

    test "evaluates modulo instruction" do
      instructions = [["lit", 17], ["lit", 5], ["modulo"]]
      result = Evaluator.evaluate(instructions, %{})
      assert result == 2
    end

    test "handles division by zero" do
      instructions = [["lit", 10], ["lit", 0], ["divide"]]

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert msg == "Division by zero"
    end

    test "handles modulo by zero" do
      instructions = [["lit", 10], ["lit", 0], ["modulo"]]

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert msg == "Modulo by zero"
    end

    test "handles negative division" do
      instructions = [["lit", -15], ["lit", 3], ["divide"]]
      result = Evaluator.evaluate(instructions, %{})
      assert result == -5
    end

    test "handles negative modulo" do
      instructions = [["lit", -17], ["lit", 5], ["modulo"]]
      result = Evaluator.evaluate(instructions, %{})
      assert result == -2
    end

    test "arithmetic with variables from context" do
      instructions = [["load", "x"], ["load", "y"], ["add"]]
      result = Evaluator.evaluate(instructions, %{"x" => 12, "y" => 8})
      assert result == 20
    end

    test "complex arithmetic expression: (a + b) * c - d" do
      # a + b
      # result * c
      # result - d
      instructions = [
        ["load", "a"],
        ["load", "b"],
        ["add"],
        ["load", "c"],
        ["multiply"],
        ["load", "d"],
        ["subtract"]
      ]

      context = %{"a" => 3, "b" => 4, "c" => 5, "d" => 10}
      result = Evaluator.evaluate(instructions, context)
      # (3 + 4) * 5 - 10 = 7 * 5 - 10 = 35 - 10 = 25
      assert result == 25
    end

    test "chained arithmetic operations" do
      instructions = [
        ["lit", 100],
        # 100 - 10 = 90
        ["lit", 10],
        ["subtract"],
        # 90 / 3 = 30
        ["lit", 3],
        ["divide"],
        # 30 + 5 = 35
        ["lit", 5],
        ["add"],
        # 35 % 3 = 2
        ["lit", 3],
        ["modulo"]
      ]

      result = Evaluator.evaluate(instructions, %{})
      assert result == 2
    end
  end

  describe "arithmetic error conditions" do
    test "addition with non-integer left operand" do
      instructions = [["lit", "hello"], ["lit", 5], ["add"]]

      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert String.contains?(msg, "Arithmetic add requires integers, got") and
               String.contains?(msg, "hello") and String.contains?(msg, "string")
    end

    test "addition with non-integer right operand" do
      instructions = [["lit", 5], ["lit", true], ["add"]]

      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert String.contains?(msg, "Arithmetic add requires integers, got") and
               String.contains?(msg, "integer") and String.contains?(msg, "boolean")
    end

    test "subtraction with boolean operands" do
      instructions = [["lit", true], ["lit", false], ["subtract"]]

      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert String.contains?(msg, "Arithmetic subtract requires integers, got") and
               String.contains?(msg, "boolean")
    end

    test "multiplication with mixed types" do
      instructions = [["lit", 5], ["lit", "text"], ["multiply"]]

      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert String.contains?(msg, "Arithmetic multiply requires integers, got") and
               String.contains?(msg, "integer") and String.contains?(msg, "string")
    end

    test "division with string operands" do
      instructions = [["lit", "ten"], ["lit", "two"], ["divide"]]

      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert String.contains?(msg, "Arithmetic divide requires integers, got") and
               String.contains?(msg, "string")
    end

    test "modulo with list operands" do
      instructions = [["lit", [1, 2]], ["lit", [3, 4]], ["modulo"]]

      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert String.contains?(msg, "Arithmetic modulo requires integers, got") and
               String.contains?(msg, "list")
    end

    test "addition with insufficient stack values" do
      instructions = [["lit", 5], ["add"]]

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert String.contains?(msg, "Arithmetic add requires") and
               String.contains?(msg, "values on stack")
    end

    test "subtraction with empty stack" do
      instructions = [["subtract"]]

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert String.contains?(msg, "Arithmetic subtract requires") and
               String.contains?(msg, "values on stack")
    end

    test "multiplication with one value on stack" do
      instructions = [["lit", 42], ["multiply"]]

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert String.contains?(msg, "Arithmetic multiply requires") and
               String.contains?(msg, "values on stack")
    end

    test "arithmetic with undefined variables" do
      instructions = [["load", "undefined_var"], ["lit", 5], ["add"]]

      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert String.contains?(msg, "add requires integers, got") and
               String.contains?(msg, "undefined")
    end
  end

  describe "integration with full pipeline" do
    test "simple arithmetic expression evaluation" do
      assert {:ok, result} = evaluate("3 + 5", %{})
      assert result == 8
    end

    test "subtraction with variables" do
      assert {:ok, result} = evaluate("x - y", %{"x" => 20, "y" => 8})
      assert result == 12
    end

    test "multiplication in comparison" do
      assert {:ok, result} = evaluate("a * b > 50", %{"a" => 8, "b" => 7})
      assert result == true
    end

    test "division with comparison" do
      assert {:ok, result} = evaluate("total / count >= 10", %{"total" => 100, "count" => 9})
      # 100 / 9 = 11 (integer division)
      assert result == true
    end

    test "modulo in boolean context" do
      assert {:ok, result} = evaluate("num % 2 = 0", %{"num" => 14})
      assert result == true
    end

    test "complex arithmetic with parentheses" do
      assert {:ok, result} =
               evaluate("(a + b) * (c - d)", %{"a" => 3, "b" => 2, "c" => 10, "d" => 4})

      # (3 + 2) * (10 - 4) = 5 * 6 = 30
      assert result == 30
    end

    test "arithmetic with logical operators" do
      assert {:ok, result} =
               evaluate(
                 "x + y > 10 AND a * b < 50",
                 %{"x" => 7, "y" => 8, "a" => 6, "b" => 7}
               )

      # 7 + 8 > 10 AND 6 * 7 < 50 = 15 > 10 AND 42 < 50 = true AND true = true
      assert result == true
    end

    test "division by zero error in full pipeline" do
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = evaluate("10 / 0", %{})
      assert msg == "Division by zero"
    end

    test "arithmetic type error in full pipeline" do
      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               evaluate("name + 5", %{"name" => "Alice"})

      assert String.contains?(msg, "Arithmetic add requires integers, got") and
               String.contains?(msg, "Alice") and String.contains?(msg, "string") and
               String.contains?(msg, "integer")
    end
  end
end
