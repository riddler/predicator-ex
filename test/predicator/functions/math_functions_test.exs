defmodule Predicator.Functions.MathFunctionsTest do
  @moduledoc """
  Tests for Math functions in Predicator expressions.
  """

  use ExUnit.Case

  alias Predicator.Functions.MathFunctions

  doctest MathFunctions

  describe "Math functions" do
    setup do
      %{functions: [MathFunctions]}
    end

    test "Math.pow raises base to power", %{functions: functions} do
      {:ok, result} =
        Predicator.evaluate(
          "Math.pow(2, 3)",
          %{},
          providers: functions
        )

      assert result === 8
    end

    test "Math.pow handles negative exponents", %{functions: functions} do
      {:ok, result} =
        Predicator.evaluate(
          "Math.pow(2, -1)",
          %{},
          providers: functions
        )

      assert result === 0.5
    end

    test "Math.pow returns a float when either argument is a float", %{functions: functions} do
      {:ok, result1} =
        Predicator.evaluate(
          "Math.pow(2.0, 3)",
          %{},
          providers: functions
        )

      assert result1 === 8.0

      {:ok, result2} =
        Predicator.evaluate(
          "Math.pow(2, 3.0)",
          %{},
          providers: functions
        )

      assert result2 === 8.0
    end

    test "Math.pow returns an integer, not a float, for zero exponent", %{functions: functions} do
      {:ok, result1} =
        Predicator.evaluate(
          "Math.pow(2, 0)",
          %{},
          providers: functions
        )

      assert result1 === 1

      {:ok, result2} =
        Predicator.evaluate(
          "Math.pow(0, 0)",
          %{},
          providers: functions
        )

      assert result2 === 1
    end

    test "Math.pow computes exact integers beyond float precision", %{functions: functions} do
      {:ok, result} =
        Predicator.evaluate(
          "Math.pow(10, 20)",
          %{},
          providers: functions
        )

      assert result === 100_000_000_000_000_000_000
    end

    test "Math.pow handles a negative base with a non-negative exponent", %{
      functions: functions
    } do
      {:ok, result} =
        Predicator.evaluate(
          "Math.pow(-2, 3)",
          %{},
          providers: functions
        )

      assert result === -8
    end

    test "Math.pow returns error for non-numeric arguments", %{functions: functions} do
      {:error, %{message: message}} =
        Predicator.evaluate(
          "Math.pow('not', 'numbers')",
          %{},
          providers: functions
        )

      assert String.contains?(message, "Math.pow expects two numeric arguments")
    end

    test "Math.sqrt returns an integer for a perfect square", %{functions: functions} do
      {:ok, result} =
        Predicator.evaluate(
          "Math.sqrt(16)",
          %{},
          providers: functions
        )

      assert result === 4
    end

    test "Math.sqrt of 0 and 1 are integers", %{functions: functions} do
      {:ok, result0} =
        Predicator.evaluate(
          "Math.sqrt(0)",
          %{},
          providers: functions
        )

      assert result0 === 0

      {:ok, result1} =
        Predicator.evaluate(
          "Math.sqrt(1)",
          %{},
          providers: functions
        )

      assert result1 === 1
    end

    test "Math.sqrt returns a float for a non-perfect-square integer", %{functions: functions} do
      {:ok, result} =
        Predicator.evaluate(
          "Math.sqrt(2)",
          %{},
          providers: functions
        )

      assert is_float(result)
      assert result === 1.4142135623730951
    end

    test "Math.sqrt returns floats for the neighbours of a perfect square", %{
      functions: functions
    } do
      {:ok, result15} =
        Predicator.evaluate(
          "Math.sqrt(15)",
          %{},
          providers: functions
        )

      assert is_float(result15)

      {:ok, result17} =
        Predicator.evaluate(
          "Math.sqrt(17)",
          %{},
          providers: functions
        )

      assert is_float(result17)
    end

    test "Math.sqrt of a float stays a float, even for an exact root", %{functions: functions} do
      {:ok, result} =
        Predicator.evaluate(
          "Math.sqrt(2.25)",
          %{},
          providers: functions
        )

      assert result === 1.5
    end

    test "Math.sqrt computes an exact integer root beyond float precision", %{
      functions: functions
    } do
      {:ok, result} =
        Predicator.evaluate(
          "Math.sqrt(10000000000000000000000)",
          %{},
          providers: functions
        )

      assert result === 100_000_000_000
    end

    test "Math.sqrt returns error for negative numbers", %{functions: functions} do
      {:error, %{message: message}} =
        Predicator.evaluate(
          "Math.sqrt(-1)",
          %{},
          providers: functions
        )

      assert String.contains?(message, "Math.sqrt expects a non-negative number")
    end

    test "Math.sqrt returns error for non-numeric arguments", %{functions: functions} do
      {:error, %{message: message}} =
        Predicator.evaluate(
          "Math.sqrt('not_a_number')",
          %{},
          providers: functions
        )

      assert String.contains?(message, "Math.sqrt expects a numeric argument")
    end

    test "Math.abs returns absolute value", %{functions: functions} do
      test_cases = [
        {-5, 5},
        {5, 5},
        {0, 0},
        {-3.14, 3.14}
      ]

      for {input, expected} <- test_cases do
        {:ok, result} =
          Predicator.evaluate(
            "Math.abs(value)",
            %{"value" => input},
            providers: functions
          )

        assert result == expected
      end
    end

    test "Math.abs returns error for non-numeric arguments", %{functions: functions} do
      {:error, %{message: message}} =
        Predicator.evaluate(
          "Math.abs('not_a_number')",
          %{},
          providers: functions
        )

      assert String.contains?(message, "Math.abs expects a numeric argument")
    end

    test "Math.floor rounds down", %{functions: functions} do
      test_cases = [
        {3.7, 3},
        {-3.2, -4},
        {5, 5},
        {0.1, 0}
      ]

      for {input, expected} <- test_cases do
        {:ok, result} =
          Predicator.evaluate(
            "Math.floor(value)",
            %{"value" => input},
            providers: functions
          )

        assert result == expected
      end
    end

    test "Math.ceil rounds up", %{functions: functions} do
      test_cases = [
        {3.2, 4},
        {-3.7, -3},
        {5, 5},
        {0.1, 1}
      ]

      for {input, expected} <- test_cases do
        {:ok, result} =
          Predicator.evaluate(
            "Math.ceil(value)",
            %{"value" => input},
            providers: functions
          )

        assert result == expected
      end
    end

    test "Math.round rounds to nearest integer", %{functions: functions} do
      test_cases = [
        {3.2, 3},
        {3.7, 4},
        {-3.2, -3},
        {-3.7, -4},
        {5, 5}
      ]

      for {input, expected} <- test_cases do
        {:ok, result} =
          Predicator.evaluate(
            "Math.round(value)",
            %{"value" => input},
            providers: functions
          )

        assert result == expected
      end
    end

    test "Math.min returns smaller value", %{functions: functions} do
      {:ok, result} =
        Predicator.evaluate(
          "Math.min(5, 3)",
          %{},
          providers: functions
        )

      assert result == 3
    end

    test "Math.max returns larger value", %{functions: functions} do
      {:ok, result} =
        Predicator.evaluate(
          "Math.max(5, 3)",
          %{},
          providers: functions
        )

      assert result == 5
    end

    test "Math.min and Math.max return error for non-numeric arguments", %{functions: functions} do
      {:error, %{message: message1}} =
        Predicator.evaluate(
          "Math.min('not', 'numbers')",
          %{},
          providers: functions
        )

      assert String.contains?(message1, "Math.min expects two numeric arguments")

      {:error, %{message: message2}} =
        Predicator.evaluate(
          "Math.max('not', 'numbers')",
          %{},
          providers: functions
        )

      assert String.contains?(message2, "Math.max expects two numeric arguments")
    end

    test "Math.random returns value between 0 and 1", %{functions: functions} do
      {:ok, result} =
        Predicator.evaluate(
          "Math.random()",
          %{},
          providers: functions
        )

      assert is_float(result)
      assert result >= 0.0
      assert result <= 1.0
    end

    test "complex expression with multiple Math functions", %{functions: functions} do
      {:ok, result} =
        Predicator.evaluate(
          "Math.pow(Math.abs(-2), 3)",
          %{},
          providers: functions
        )

      assert result === 8
    end

    test "Math functions in conditional expressions", %{functions: functions} do
      {:ok, result} =
        Predicator.evaluate(
          "Math.max(limit, 0) > 50",
          %{"limit" => 75},
          providers: functions
        )

      assert result == true
    end

    test "Math.floor returns error for non-numeric arguments", %{functions: functions} do
      {:error, %{message: message}} =
        Predicator.evaluate(
          "Math.floor('not_a_number')",
          %{},
          providers: functions
        )

      assert String.contains?(message, "Math.floor expects a numeric argument")
    end

    test "Math.ceil returns error for non-numeric arguments", %{functions: functions} do
      {:error, %{message: message}} =
        Predicator.evaluate(
          "Math.ceil('not_a_number')",
          %{},
          providers: functions
        )

      assert String.contains?(message, "Math.ceil expects a numeric argument")
    end

    test "Math.round returns error for non-numeric arguments", %{functions: functions} do
      {:error, %{message: message}} =
        Predicator.evaluate(
          "Math.round('not_a_number')",
          %{},
          providers: functions
        )

      assert String.contains?(message, "Math.round expects a numeric argument")
    end
  end
end
