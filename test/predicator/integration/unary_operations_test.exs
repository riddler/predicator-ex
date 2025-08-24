defmodule UnaryEvaluationTest do
  use ExUnit.Case, async: true

  import Predicator

  alias Predicator.Evaluator

  describe "unary minus instruction evaluation" do
    test "evaluates unary minus with positive integer" do
      instructions = [["lit", 42], ["unary_minus"]]
      result = Evaluator.evaluate(instructions, %{})
      assert result == -42
    end

    test "evaluates unary minus with negative integer" do
      instructions = [["lit", -17], ["unary_minus"]]
      result = Evaluator.evaluate(instructions, %{})
      assert result == 17
    end

    test "evaluates unary minus with zero" do
      instructions = [["lit", 0], ["unary_minus"]]
      result = Evaluator.evaluate(instructions, %{})
      assert result == 0
    end

    test "evaluates unary minus with variable" do
      instructions = [["load", "num"], ["unary_minus"]]
      result = Evaluator.evaluate(instructions, %{"num" => 25})
      assert result == -25
    end

    test "chained unary minus operations" do
      instructions = [["lit", 10], ["unary_minus"], ["unary_minus"]]
      result = Evaluator.evaluate(instructions, %{})
      # -(-10) = 10
      assert result == 10
    end

    test "unary minus in arithmetic context" do
      instructions = [["lit", 5], ["lit", 3], ["unary_minus"], ["add"]]
      result = Evaluator.evaluate(instructions, %{})
      # 5 + (-3) = 5 - 3 = 2
      assert result == 2
    end
  end

  describe "unary bang instruction evaluation" do
    test "evaluates unary bang with true" do
      instructions = [["lit", true], ["unary_bang"]]
      result = Evaluator.evaluate(instructions, %{})
      assert result == false
    end

    test "evaluates unary bang with false" do
      instructions = [["lit", false], ["unary_bang"]]
      result = Evaluator.evaluate(instructions, %{})
      assert result == true
    end

    test "evaluates unary bang with boolean variable" do
      instructions = [["load", "active"], ["unary_bang"]]
      result = Evaluator.evaluate(instructions, %{"active" => true})
      assert result == false
    end

    test "chained unary bang operations" do
      instructions = [["lit", true], ["unary_bang"], ["unary_bang"]]
      result = Evaluator.evaluate(instructions, %{})
      # !(!true) = !false = true
      assert result == true
    end

    test "unary bang in logical context" do
      instructions = [["lit", true], ["unary_bang"], ["lit", false], ["or"]]
      result = Evaluator.evaluate(instructions, %{})
      # (!true) OR false = false OR false = false
      assert result == false
    end
  end

  describe "unary error conditions" do
    test "unary minus with non-integer value" do
      instructions = [["lit", "hello"], ["unary_minus"]]

      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert String.contains?(msg, "Unary minus requires") and String.contains?(msg, "hello")
    end

    test "unary minus with boolean value" do
      instructions = [["lit", true], ["unary_minus"]]

      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert String.contains?(msg, "Unary minus requires") and String.contains?(msg, "true")
    end

    test "unary minus with list value" do
      instructions = [["lit", [1, 2, 3]], ["unary_minus"]]

      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert String.contains?(msg, "Unary minus requires an integer, got [1, 2, 3] (list)")
    end

    test "unary minus with empty stack" do
      instructions = [["unary_minus"]]

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert String.contains?(msg, "Unary minus requires") and String.contains?(msg, "value") and
               String.contains?(msg, "stack")
    end

    test "unary bang with non-boolean value" do
      instructions = [["lit", 42], ["unary_bang"]]

      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert String.contains?(msg, "Logical NOT requires a boolean, got 42 (integer)")
    end

    test "unary bang with string value" do
      instructions = [["lit", "text"], ["unary_bang"]]

      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert String.contains?(msg, "Logical NOT requires") and String.contains?(msg, "text")
    end

    test "unary bang with integer value" do
      instructions = [["lit", 0], ["unary_bang"]]

      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert String.contains?(msg, "Logical NOT requires") and String.contains?(msg, "boolean") and
               String.contains?(msg, "0")
    end

    test "unary bang with empty stack" do
      instructions = [["unary_bang"]]

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert String.contains?(msg, "Logical NOT requires") and
               String.contains?(msg, "value on stack")
    end

    test "unary minus with undefined variable" do
      instructions = [["load", "undefined_var"], ["unary_minus"]]

      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert String.contains?(msg, "Unary minus requires") and String.contains?(msg, "undefined")
    end

    test "unary bang with undefined variable" do
      instructions = [["load", "undefined_var"], ["unary_bang"]]

      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               Evaluator.evaluate(instructions, %{})

      assert String.contains?(msg, "Logical NOT requires a boolean, got :undefined (undefined)")
    end
  end

  describe "integration with full pipeline" do
    test "simple unary minus expression" do
      assert {:ok, result} = evaluate("-5", %{})
      assert result == -5
    end

    test "unary minus with variable" do
      assert {:ok, result} = evaluate("-score", %{"score" => 85})
      assert result == -85
    end

    test "unary bang expression" do
      assert {:ok, result} = evaluate("!active", %{"active" => true})
      assert result == false
    end

    test "unary bang with boolean literal" do
      assert {:ok, result} = evaluate("!false", %{})
      assert result == true
    end

    test "unary minus in arithmetic" do
      assert {:ok, result} = evaluate("10 + -3", %{})
      assert result == 7
    end

    test "unary minus in comparison" do
      assert {:ok, result} = evaluate("-x > -10", %{"x" => 5})
      # -5 > -10 = true
      assert result == true
    end

    test "unary bang in logical expression" do
      assert {:ok, result} =
               evaluate("!expired AND active", %{"expired" => false, "active" => true})

      # !false AND true = true AND true = true
      assert result == true
    end

    test "complex expression with both unary operators" do
      assert {:ok, result} = evaluate("!flag OR -count > -5", %{"flag" => false, "count" => 3})
      # !false OR -3 > -5 = true OR true = true
      assert result == true
    end

    test "nested unary operations" do
      assert {:ok, result} = evaluate("!(!active)", %{"active" => false})
      # !(!false) = !true = false
      assert result == false
    end

    test "unary minus with parentheses" do
      assert {:ok, result} = evaluate("-(x + y)", %{"x" => 3, "y" => 7})
      # -(3 + 7) = -10
      assert result == -10
    end

    test "mixed unary and binary operations" do
      # This should fail because we can't add integer and boolean
      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               evaluate("-a * b + !flag", %{"a" => 4, "b" => 5, "flag" => false})

      assert String.contains?(msg, "Arithmetic add requires integers, got") and
               String.contains?(msg, "integer") and String.contains?(msg, "boolean")
    end

    test "unary minus type error in pipeline" do
      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               evaluate("-name", %{"name" => "Alice"})

      assert String.contains?(msg, "Unary minus requires an integer, got") and
               String.contains?(msg, "Alice") and String.contains?(msg, "string")
    end

    test "unary bang type error in pipeline" do
      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} =
               evaluate("!count", %{"count" => 42})

      assert String.contains?(msg, "Logical NOT requires") and String.contains?(msg, "boolean") and
               String.contains?(msg, "42")
    end
  end

  describe "complex expressions with unary operators" do
    test "multiple unary minus in arithmetic" do
      assert {:ok, result} = evaluate("-a + -b - -c", %{"a" => 10, "b" => 5, "c" => 3})
      # -10 + -5 - -3 = -10 + -5 + 3 = -12
      assert result == -12
    end

    test "unary operators in comparison chains" do
      assert {:ok, result} =
               evaluate(
                 "-x > -y AND !flag1 OR !flag2",
                 %{"x" => 8, "y" => 12, "flag1" => true, "flag2" => false}
               )

      # -8 > -12 AND !true OR !false = true AND false OR true = false OR true = true
      assert result == true
    end

    test "unary minus with function calls" do
      assert {:ok, result} = evaluate("-abs(value)", %{"value" => -15})
      # -abs(-15) = -15 = -15
      assert result == -15
    end

    test "unary bang with comparisons" do
      assert {:ok, result} = evaluate("!(score > 90)", %{"score" => 85})
      # !(85 > 90) = !false = true
      assert result == true
    end
  end
end
