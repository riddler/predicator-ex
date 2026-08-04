defmodule Predicator.Functions.SystemFunctionsTest do
  use ExUnit.Case, async: true

  import Predicator
  alias Predicator.Functions.SystemFunctions

  doctest SystemFunctions

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

      # starts_with() with wrong arity
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("starts_with('a')", %{})

      assert msg =~ "starts_with() expects 2 arguments, got 1"

      # ends_with() with wrong arity
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("ends_with('a')", %{})

      assert msg =~ "ends_with() expects 2 arguments, got 1"

      # index_of() with wrong arity
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("index_of('a')", %{})

      assert msg =~ "index_of() expects 2 arguments, got 1"

      # substring() with too few arguments accepts 2 or 3
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("substring('a')", %{})

      assert msg =~ "substring() expects 2 or 3 arguments, got 1"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("substring('a', 0, 1, 2)", %{})

      assert msg =~ "substring() expects 2 or 3 arguments, got 4"
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

    test "starts_with with invalid argument types" do
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("starts_with(123, 'a')", %{})

      assert msg =~ "starts_with() expects two string arguments"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("starts_with('a', 123)", %{})

      assert msg =~ "starts_with() expects two string arguments"
    end

    test "ends_with with invalid argument types" do
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("ends_with(123, 'a')", %{})

      assert msg =~ "ends_with() expects two string arguments"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("ends_with('a', 123)", %{})

      assert msg =~ "ends_with() expects two string arguments"
    end

    test "index_of with invalid argument types" do
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("index_of(123, 'a')", %{})

      assert msg =~ "index_of() expects two string arguments"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("index_of('a', 123)", %{})

      assert msg =~ "index_of() expects two string arguments"
    end

    test "substring with invalid argument types" do
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("substring(123, 0)", %{})

      assert msg =~ "substring() expects a string and an integer start index"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("substring('a', 'not_an_int')", %{})

      assert msg =~ "substring() expects a string and an integer start index"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("substring(123, 0, 1)", %{})

      assert msg =~
               "substring() expects a string, an integer start index, and an integer length"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("substring('a', -1)", %{})

      assert msg =~ "substring() expects a non-negative start index"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("substring('a', 0, -1)", %{})

      assert msg =~ "substring() expects a non-negative start index and length"
    end
  end

  describe "string functions success cases" do
    test "starts_with" do
      assert evaluate("starts_with('hello world', 'hello')", %{}) == {:ok, true}
      assert evaluate("starts_with('hello world', 'world')", %{}) == {:ok, false}
      assert evaluate("starts_with('hello', '')", %{}) == {:ok, true}
    end

    test "ends_with" do
      assert evaluate("ends_with('hello world', 'world')", %{}) == {:ok, true}
      assert evaluate("ends_with('hello world', 'hello')", %{}) == {:ok, false}
      assert evaluate("ends_with('hello', '')", %{}) == {:ok, true}
    end

    test "substring without length" do
      assert evaluate("substring('hello world', 6)", %{}) == {:ok, "world"}
      assert evaluate("substring('hello world', 0)", %{}) == {:ok, "hello world"}
      assert evaluate("substring('hello', 100)", %{}) == {:ok, ""}
    end

    test "substring with length" do
      assert evaluate("substring('hello world', 0, 5)", %{}) == {:ok, "hello"}
      assert evaluate("substring('hello world', 6, 5)", %{}) == {:ok, "world"}
      assert evaluate("substring('hello', 0, 100)", %{}) == {:ok, "hello"}
      assert evaluate("substring('hello', 2, 0)", %{}) == {:ok, ""}
    end

    test "index_of" do
      assert evaluate("index_of('hello world', 'world')", %{}) == {:ok, 6}
      assert evaluate("index_of('hello world', 'hello')", %{}) == {:ok, 0}
      assert evaluate("index_of('hello world', 'nope')", %{}) == {:ok, -1}
      assert evaluate("index_of('hello', '')", %{}) == {:ok, 0}
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
        "trim",
        "starts_with",
        "ends_with",
        "substring",
        "index_of"
      ]

      for func_name <- expected_functions do
        assert Map.has_key?(functions, func_name), "Missing function: #{func_name}"
        {arity, function} = functions[func_name]
        assert (is_integer(arity) and arity >= 0) or (is_list(arity) and arity != [])
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
      assert {2, _starts_with_func} = functions["starts_with"]
      assert {2, _ends_with_func} = functions["ends_with"]
      assert {[2, 3], _substring_func} = functions["substring"]
      assert {2, _index_of_func} = functions["index_of"]
    end
  end
end
