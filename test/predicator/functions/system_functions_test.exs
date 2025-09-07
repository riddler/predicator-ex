defmodule Predicator.Functions.SystemFunctionsTest do
  use ExUnit.Case, async: true

  import Predicator
  alias Predicator.Functions.SystemFunctions

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
    end

    test "date functions with wrong arity" do
      # Date.year() with no arguments
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("Date.year()", %{})

      assert msg =~ "Date.year() expects 1 arguments, got 0"

      # Date.month() with no arguments
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("Date.month()", %{})

      assert msg =~ "Date.month() expects 1 arguments, got 0"

      # Date.day() with no arguments
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("Date.day()", %{})

      assert msg =~ "Date.day() expects 1 arguments, got 0"
    end
  end

  describe "string functions error cases" do
    test "len with invalid argument types" do
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("len(123)", %{})

      assert msg =~ "len() expects a string argument"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("len(true)", %{})

      assert msg =~ "len() expects a string argument"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("len(nil)", %{})

      assert msg =~ "len() expects a string argument"
    end

    test "upper with invalid argument types" do
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("upper(123)", %{})

      assert msg =~ "upper() expects a string argument"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("upper(true)", %{})

      assert msg =~ "upper() expects a string argument"
    end

    test "lower with invalid argument types" do
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("lower(123)", %{})

      assert msg =~ "lower() expects a string argument"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("lower(false)", %{})

      assert msg =~ "lower() expects a string argument"
    end

    test "trim with invalid argument types" do
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("trim(123)", %{})

      assert msg =~ "trim() expects a string argument"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("trim([1,2,3])", %{})

      assert msg =~ "trim() expects a string argument"
    end
  end

  describe "date functions error cases" do
    test "year with invalid argument types" do
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("Date.year('not_a_date')", %{})

      assert msg =~ "Date.year() expects a date or datetime argument"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("Date.year(123)", %{})

      assert msg =~ "Date.year() expects a date or datetime argument"
    end

    test "month with invalid argument types" do
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("Date.month('not_a_date')", %{})

      assert msg =~ "Date.month() expects a date or datetime argument"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("Date.month(true)", %{})

      assert msg =~ "Date.month() expects a date or datetime argument"
    end

    test "day with invalid argument types" do
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("Date.day('not_a_date')", %{})

      assert msg =~ "Date.day() expects a date or datetime argument"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("Date.day(false)", %{})

      assert msg =~ "Date.day() expects a date or datetime argument"
    end
  end

  describe "all_functions/0" do
    test "returns map with expected functions" do
      functions = SystemFunctions.all_functions()

      # Check that all expected functions are present
      expected_functions = [
        "len",
        "upper",
        "lower",
        "trim"
      ]

      for func_name <- expected_functions do
        assert Map.has_key?(functions, func_name), "Missing function: #{func_name}"
        {arity, function} = functions[func_name]
        assert is_integer(arity) and arity >= 0
        assert is_function(function, 2)
      end
    end

    test "function arities are correct" do
      functions = SystemFunctions.all_functions()

      # Check specific arities
      assert {1, _len_func} = functions["len"]
      assert {1, _upper_func} = functions["upper"]
      assert {1, _lower_func} = functions["lower"]
      assert {1, _trim_func} = functions["trim"]
    end
  end
end
