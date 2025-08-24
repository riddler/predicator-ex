defmodule SystemFunctionsIntegrationTest do
  use ExUnit.Case, async: true

  import Predicator

  describe "string functions error cases" do
    test "len with invalid argument types" do
      assert {:error, msg} = evaluate("len(123)", %{})
      assert msg =~ "len() expects a string argument"

      assert {:error, msg} = evaluate("len(true)", %{})  
      assert msg =~ "len() expects a string argument"

      assert {:error, msg} = evaluate("len(nil)", %{})
      assert msg =~ "len() expects a string argument"
    end

    test "upper with invalid argument types" do
      assert {:error, msg} = evaluate("upper(123)", %{})
      assert msg =~ "upper() expects a string argument"

      assert {:error, msg} = evaluate("upper(true)", %{})
      assert msg =~ "upper() expects a string argument"
    end

    test "lower with invalid argument types" do
      assert {:error, msg} = evaluate("lower(123)", %{})
      assert msg =~ "lower() expects a string argument"

      assert {:error, msg} = evaluate("lower(false)", %{})
      assert msg =~ "lower() expects a string argument"
    end

    test "trim with invalid argument types" do
      assert {:error, msg} = evaluate("trim(123)", %{})
      assert msg =~ "trim() expects a string argument"

      assert {:error, msg} = evaluate("trim([1,2,3])", %{})
      assert msg =~ "trim() expects a string argument"
    end
  end

  describe "numeric functions error cases" do
    test "abs with invalid argument types" do
      assert {:error, msg} = evaluate("abs('not_a_number')", %{})
      assert msg =~ "abs() expects a numeric argument"

      assert {:error, msg} = evaluate("abs(true)", %{})
      assert msg =~ "abs() expects a numeric argument"
    end

    test "max with invalid argument types" do
      assert {:error, msg} = evaluate("max('a', 5)", %{})
      assert msg =~ "max() expects two numeric arguments"

      assert {:error, msg} = evaluate("max(5, 'b')", %{})
      assert msg =~ "max() expects two numeric arguments"

      assert {:error, msg} = evaluate("max(true, false)", %{})
      assert msg =~ "max() expects two numeric arguments"
    end

    test "min with invalid argument types" do
      assert {:error, msg} = evaluate("min('a', 5)", %{})
      assert msg =~ "min() expects two numeric arguments"

      assert {:error, msg} = evaluate("min(5, 'b')", %{})
      assert msg =~ "min() expects two numeric arguments"
    end
  end

  describe "date functions error cases" do
    test "year with invalid argument types" do
      assert {:error, msg} = evaluate("year('not_a_date')", %{})
      assert msg =~ "year() expects a date or datetime argument"

      assert {:error, msg} = evaluate("year(123)", %{})
      assert msg =~ "year() expects a date or datetime argument"
    end

    test "month with invalid argument types" do
      assert {:error, msg} = evaluate("month('not_a_date')", %{})
      assert msg =~ "month() expects a date or datetime argument"

      assert {:error, msg} = evaluate("month(true)", %{})
      assert msg =~ "month() expects a date or datetime argument"
    end

    test "day with invalid argument types" do
      assert {:error, msg} = evaluate("day('not_a_date')", %{})
      assert msg =~ "day() expects a date or datetime argument"

      assert {:error, msg} = evaluate("day(false)", %{})
      assert msg =~ "day() expects a date or datetime argument"
    end
  end

  describe "all_functions/0" do
    test "returns map with expected functions" do
      functions = Predicator.Functions.SystemFunctions.all_functions()
      
      # Check that all expected functions are present
      expected_functions = [
        "len", "upper", "lower", "trim",
        "abs", "max", "min", 
        "year", "month", "day"
      ]

      for func_name <- expected_functions do
        assert Map.has_key?(functions, func_name), "Missing function: #{func_name}"
        {arity, function} = functions[func_name]
        assert is_integer(arity) and arity >= 0
        assert is_function(function, 2)
      end
    end

    test "function arities are correct" do
      functions = Predicator.Functions.SystemFunctions.all_functions()

      # Check specific arities
      assert {1, _} = functions["len"]
      assert {1, _} = functions["upper"] 
      assert {1, _} = functions["lower"]
      assert {1, _} = functions["trim"]
      assert {1, _} = functions["abs"]
      assert {2, _} = functions["max"]
      assert {2, _} = functions["min"]
      assert {1, _} = functions["year"]
      assert {1, _} = functions["month"]
      assert {1, _} = functions["day"]
    end
  end
end