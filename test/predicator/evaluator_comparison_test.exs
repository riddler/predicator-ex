defmodule Predicator.EvaluatorComparisonTest do
  use ExUnit.Case, async: true

  alias Predicator.Evaluator

  describe "compare instruction - GT (greater than)" do
    test "compares integers correctly" do
      instructions = [
        ["lit", 10],
        ["lit", 5],
        ["compare", "GT"]
      ]

      assert Evaluator.evaluate(instructions) == true
    end

    test "false when left is not greater" do
      instructions = [
        ["lit", 5],
        ["lit", 10],
        ["compare", "GT"]
      ]

      assert Evaluator.evaluate(instructions) == false
    end

    test "false when values are equal" do
      instructions = [
        ["lit", 5],
        ["lit", 5],
        ["compare", "GT"]
      ]

      assert Evaluator.evaluate(instructions) == false
    end

    test "compares strings correctly" do
      instructions = [
        ["lit", "zebra"],
        ["lit", "apple"],
        ["compare", "GT"]
      ]

      assert Evaluator.evaluate(instructions) == true
    end

    test "returns :undefined for mismatched types" do
      instructions = [
        ["lit", 10],
        ["lit", "hello"],
        ["compare", "GT"]
      ]

      assert Evaluator.evaluate(instructions) == :undefined
    end

    test "returns :undefined when left is :undefined" do
      instructions = [
        ["lit", :undefined],
        ["lit", 5],
        ["compare", "GT"]
      ]

      assert Evaluator.evaluate(instructions) == :undefined
    end

    test "returns :undefined when right is :undefined" do
      instructions = [
        ["lit", 5],
        ["lit", :undefined],
        ["compare", "GT"]
      ]

      assert Evaluator.evaluate(instructions) == :undefined
    end
  end

  describe "compare instruction - LT (less than)" do
    test "compares integers correctly" do
      instructions = [
        ["lit", 5],
        ["lit", 10],
        ["compare", "LT"]
      ]

      assert Evaluator.evaluate(instructions) == true
    end

    test "false when left is not less" do
      instructions = [
        ["lit", 10],
        ["lit", 5],
        ["compare", "LT"]
      ]

      assert Evaluator.evaluate(instructions) == false
    end

    test "false when values are equal" do
      instructions = [
        ["lit", 5],
        ["lit", 5],
        ["compare", "LT"]
      ]

      assert Evaluator.evaluate(instructions) == false
    end
  end

  describe "compare instruction - EQ (equal)" do
    test "true for equal integers" do
      instructions = [
        ["lit", 42],
        ["lit", 42],
        ["compare", "EQ"]
      ]

      assert Evaluator.evaluate(instructions) == true
    end

    test "true for equal strings" do
      instructions = [
        ["lit", "hello"],
        ["lit", "hello"],
        ["compare", "EQ"]
      ]

      assert Evaluator.evaluate(instructions) == true
    end

    test "true for equal booleans" do
      instructions = [
        ["lit", true],
        ["lit", true],
        ["compare", "EQ"]
      ]

      assert Evaluator.evaluate(instructions) == true
    end

    test "false for different values" do
      instructions = [
        ["lit", 42],
        ["lit", 43],
        ["compare", "EQ"]
      ]

      assert Evaluator.evaluate(instructions) == false
    end

    test "returns :undefined for mismatched types" do
      instructions = [
        ["lit", 42],
        ["lit", "42"],
        ["compare", "EQ"]
      ]

      assert Evaluator.evaluate(instructions) == :undefined
    end
  end

  describe "compare instruction - GTE (greater than or equal)" do
    test "true when greater" do
      instructions = [
        ["lit", 10],
        ["lit", 5],
        ["compare", "GTE"]
      ]

      assert Evaluator.evaluate(instructions) == true
    end

    test "true when equal" do
      instructions = [
        ["lit", 5],
        ["lit", 5],
        ["compare", "GTE"]
      ]

      assert Evaluator.evaluate(instructions) == true
    end

    test "false when less" do
      instructions = [
        ["lit", 5],
        ["lit", 10],
        ["compare", "GTE"]
      ]

      assert Evaluator.evaluate(instructions) == false
    end
  end

  describe "compare instruction - LTE (less than or equal)" do
    test "true when less" do
      instructions = [
        ["lit", 5],
        ["lit", 10],
        ["compare", "LTE"]
      ]

      assert Evaluator.evaluate(instructions) == true
    end

    test "true when equal" do
      instructions = [
        ["lit", 5],
        ["lit", 5],
        ["compare", "LTE"]
      ]

      assert Evaluator.evaluate(instructions) == true
    end

    test "false when greater" do
      instructions = [
        ["lit", 10],
        ["lit", 5],
        ["compare", "LTE"]
      ]

      assert Evaluator.evaluate(instructions) == false
    end
  end

  describe "compare instruction - NE (not equal)" do
    test "true for different values" do
      instructions = [
        ["lit", 42],
        ["lit", 43],
        ["compare", "NE"]
      ]

      assert Evaluator.evaluate(instructions) == true
    end

    test "false for equal values" do
      instructions = [
        ["lit", 42],
        ["lit", 42],
        ["compare", "NE"]
      ]

      assert Evaluator.evaluate(instructions) == false
    end

    test "returns :undefined for mismatched types" do
      instructions = [
        ["lit", 42],
        ["lit", "hello"],
        ["compare", "NE"]
      ]

      assert Evaluator.evaluate(instructions) == :undefined
    end
  end

  describe "compare instruction with context loading" do
    test "compares loaded values" do
      instructions = [
        ["load", "score"],
        ["lit", 85],
        ["compare", "GT"]
      ]

      context = %{"score" => 90}
      assert Evaluator.evaluate(instructions, context) == true
    end

    test "handles missing context values" do
      instructions = [
        ["load", "missing"],
        ["lit", 85],
        ["compare", "GT"]
      ]

      assert Evaluator.evaluate(instructions, %{}) == :undefined
    end

    test "real-world example: age check" do
      instructions = [
        ["load", "age"],
        ["lit", 18],
        ["compare", "GTE"]
      ]

      adult_context = %{"age" => 25}
      minor_context = %{"age" => 16}

      assert Evaluator.evaluate(instructions, adult_context) == true
      assert Evaluator.evaluate(instructions, minor_context) == false
    end
  end

  describe "compare instruction error cases" do
    test "returns error with insufficient stack values" do
      instructions = [
        ["lit", 42],
        ["compare", "GT"]
      ]

      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg =~ "Comparison requires 2 values on stack, got: 1"
    end

    test "returns error with empty stack" do
      instructions = [
        ["compare", "GT"]
      ]

      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg =~ "Comparison requires 2 values on stack, got: 0"
    end

    test "returns error for invalid operator" do
      instructions = [
        ["lit", 5],
        ["lit", 10],
        ["compare", "INVALID"]
      ]

      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg =~ "Unknown instruction:"
    end
  end
end
