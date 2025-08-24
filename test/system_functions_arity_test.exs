defmodule SystemFunctionsArityTest do
  use ExUnit.Case, async: true

  import Predicator

  describe "function arity validation" do
    test "string functions with wrong arity" do
      # len() with no arguments
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = evaluate("len()", %{})
      assert msg =~ "len() expects 1 arguments, got 0"

      # len() with multiple arguments
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("len('a', 'b')", %{})

      assert msg =~ "len() expects 1 arguments, got 2"

      # upper() with no arguments
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = evaluate("upper()", %{})
      assert msg =~ "upper() expects 1 arguments, got 0"

      # upper() with multiple arguments
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("upper('a', 'b')", %{})

      assert msg =~ "upper() expects 1 arguments, got 2"

      # lower() with wrong arity
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = evaluate("lower()", %{})
      assert msg =~ "lower() expects 1 arguments, got 0"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("lower('a', 'b')", %{})

      assert msg =~ "lower() expects 1 arguments, got 2"

      # trim() with wrong arity
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = evaluate("trim()", %{})
      assert msg =~ "trim() expects 1 arguments, got 0"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("trim('a', 'b')", %{})

      assert msg =~ "trim() expects 1 arguments, got 2"
    end

    test "numeric functions with wrong arity" do
      # abs() with no arguments
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = evaluate("abs()", %{})
      assert msg =~ "abs() expects 1 arguments, got 0"

      # abs() with multiple arguments
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("abs(1, 2)", %{})

      assert msg =~ "abs() expects 1 arguments, got 2"

      # max() with wrong arity
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = evaluate("max()", %{})
      assert msg =~ "max() expects 2 arguments, got 0"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = evaluate("max(1)", %{})
      assert msg =~ "max() expects 2 arguments, got 1"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("max(1, 2, 3)", %{})

      assert msg =~ "max() expects 2 arguments, got 3"

      # min() with wrong arity
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = evaluate("min()", %{})
      assert msg =~ "min() expects 2 arguments, got 0"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = evaluate("min(5)", %{})
      assert msg =~ "min() expects 2 arguments, got 1"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("min(1, 2, 3)", %{})

      assert msg =~ "min() expects 2 arguments, got 3"
    end

    test "date functions with wrong arity" do
      # year() with no arguments
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = evaluate("year()", %{})
      assert msg =~ "year() expects 1 arguments, got 0"

      # year() with multiple arguments
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("year(#2024-01-01#, #2024-12-31#)", %{})

      assert msg =~ "year() expects 1 arguments, got 2"

      # month() with wrong arity
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = evaluate("month()", %{})
      assert msg =~ "month() expects 1 arguments, got 0"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("month(#2024-01-01#, #2024-12-31#)", %{})

      assert msg =~ "month() expects 1 arguments, got 2"

      # day() with wrong arity
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = evaluate("day()", %{})
      assert msg =~ "day() expects 1 arguments, got 0"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("day(#2024-01-01#, #2024-12-31#)", %{})

      assert msg =~ "day() expects 1 arguments, got 2"
    end
  end

  describe "function type validation edge cases" do
    test "numeric functions with undefined values" do
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("abs(undefined_var)", %{})

      assert msg =~ "abs() expects a numeric argument"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("max(undefined_var, 5)", %{})

      assert msg =~ "max() expects two numeric arguments"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("min(5, undefined_var)", %{})

      assert msg =~ "min() expects two numeric arguments"
    end

    test "date functions with undefined values" do
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("year(undefined_var)", %{})

      assert msg =~ "year() expects a date or datetime argument"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("month(undefined_var)", %{})

      assert msg =~ "month() expects a date or datetime argument"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("day(undefined_var)", %{})

      assert msg =~ "day() expects a date or datetime argument"
    end

    test "string functions with list arguments" do
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("len([1,2,3])", %{})

      assert msg =~ "len() expects a string argument"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("upper([1,2,3])", %{})

      assert msg =~ "upper() expects a string argument"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("lower([1,2,3])", %{})

      assert msg =~ "lower() expects a string argument"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("trim([1,2,3])", %{})

      assert msg =~ "trim() expects a string argument"
    end

    test "mixed type arguments in max/min" do
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("max('string', 5)", %{})

      assert msg =~ "max() expects two numeric arguments"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("min(5, 'string')", %{})

      assert msg =~ "min() expects two numeric arguments"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("max(true, false)", %{})

      assert msg =~ "max() expects two numeric arguments"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("min([1], [2])", %{})

      assert msg =~ "min() expects two numeric arguments"
    end
  end
end
