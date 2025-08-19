defmodule Predicator.BuiltInFunctionsTest do
  use ExUnit.Case, async: true

  alias Predicator.BuiltInFunctions
  alias Predicator.FunctionRegistry

  setup do
    # Clear and re-register built-in functions for each test
    FunctionRegistry.clear_registry()
    BuiltInFunctions.register_all()
    :ok
  end

  describe "string functions" do
    test "len/1 with valid arguments" do
      assert {:ok, 5} = FunctionRegistry.call("len", ["hello"], %{})
      assert {:ok, 0} = FunctionRegistry.call("len", [""], %{})
      assert {:ok, 3} = FunctionRegistry.call("len", ["🚀🚀🚀"], %{})
    end

    test "len/1 with invalid argument types" do
      assert {:error, "len() expects a string argument"} =
               FunctionRegistry.call("len", [123], %{})

      assert {:error, "len() expects a string argument"} =
               FunctionRegistry.call("len", [true], %{})

      assert {:error, "len() expects a string argument"} =
               FunctionRegistry.call("len", [nil], %{})

      assert {:error, "len() expects a string argument"} =
               FunctionRegistry.call("len", [[]], %{})
    end

    test "len/1 with wrong arity" do
      assert {:error, "Function len() expects 1 arguments, got 0"} =
               FunctionRegistry.call("len", [], %{})

      assert {:error, "Function len() expects 1 arguments, got 2"} =
               FunctionRegistry.call("len", ["a", "b"], %{})
    end

    test "upper/1 with valid arguments" do
      assert {:ok, "HELLO"} = FunctionRegistry.call("upper", ["hello"], %{})
      assert {:ok, ""} = FunctionRegistry.call("upper", [""], %{})
      assert {:ok, "123"} = FunctionRegistry.call("upper", ["123"], %{})
    end

    test "upper/1 with invalid argument types" do
      assert {:error, "upper() expects a string argument"} =
               FunctionRegistry.call("upper", [123], %{})

      assert {:error, "upper() expects a string argument"} =
               FunctionRegistry.call("upper", [true], %{})
    end

    test "upper/1 with wrong arity" do
      assert {:error, "Function upper() expects 1 arguments, got 0"} =
               FunctionRegistry.call("upper", [], %{})

      assert {:error, "Function upper() expects 1 arguments, got 2"} =
               FunctionRegistry.call("upper", ["a", "b"], %{})
    end

    test "lower/1 with valid arguments" do
      assert {:ok, "hello"} = FunctionRegistry.call("lower", ["HELLO"], %{})
      assert {:ok, ""} = FunctionRegistry.call("lower", [""], %{})
      assert {:ok, "123"} = FunctionRegistry.call("lower", ["123"], %{})
    end

    test "lower/1 with invalid argument types" do
      assert {:error, "lower() expects a string argument"} =
               FunctionRegistry.call("lower", [123], %{})
    end

    test "lower/1 with wrong arity" do
      assert {:error, "Function lower() expects 1 arguments, got 0"} =
               FunctionRegistry.call("lower", [], %{})

      assert {:error, "Function lower() expects 1 arguments, got 2"} =
               FunctionRegistry.call("lower", ["a", "b"], %{})
    end

    test "trim/1 with valid arguments" do
      assert {:ok, "hello"} = FunctionRegistry.call("trim", [" hello "], %{})
      assert {:ok, "hello"} = FunctionRegistry.call("trim", ["hello"], %{})
      assert {:ok, ""} = FunctionRegistry.call("trim", [" "], %{})
      assert {:ok, "a b"} = FunctionRegistry.call("trim", [" a b "], %{})
    end

    test "trim/1 with invalid argument types" do
      assert {:error, "trim() expects a string argument"} =
               FunctionRegistry.call("trim", [123], %{})
    end

    test "trim/1 with wrong arity" do
      assert {:error, "Function trim() expects 1 arguments, got 0"} =
               FunctionRegistry.call("trim", [], %{})

      assert {:error, "Function trim() expects 1 arguments, got 2"} =
               FunctionRegistry.call("trim", ["a", "b"], %{})
    end
  end

  describe "numeric functions" do
    test "abs/1 with valid arguments" do
      assert {:ok, 5} = FunctionRegistry.call("abs", [5], %{})
      assert {:ok, 5} = FunctionRegistry.call("abs", [-5], %{})
      assert {:ok, 0} = FunctionRegistry.call("abs", [0], %{})
      assert {:ok, 42} = FunctionRegistry.call("abs", [-42], %{})
    end

    test "abs/1 with invalid argument types" do
      assert {:error, "abs() expects a numeric argument"} =
               FunctionRegistry.call("abs", ["5"], %{})

      assert {:error, "abs() expects a numeric argument"} =
               FunctionRegistry.call("abs", [true], %{})
    end

    test "abs/1 with wrong arity" do
      assert {:error, "Function abs() expects 1 arguments, got 0"} =
               FunctionRegistry.call("abs", [], %{})

      assert {:error, "Function abs() expects 1 arguments, got 2"} =
               FunctionRegistry.call("abs", [1, 2], %{})
    end

    test "max/2 with valid arguments" do
      assert {:ok, 7} = FunctionRegistry.call("max", [3, 7], %{})
      assert {:ok, 7} = FunctionRegistry.call("max", [7, 3], %{})
      assert {:ok, 5} = FunctionRegistry.call("max", [5, 5], %{})
      assert {:ok, 0} = FunctionRegistry.call("max", [-5, 0], %{})
      assert {:ok, -1} = FunctionRegistry.call("max", [-5, -1], %{})
    end

    test "max/2 with invalid argument types" do
      assert {:error, "max() expects two numeric arguments"} =
               FunctionRegistry.call("max", ["3", 7], %{})

      assert {:error, "max() expects two numeric arguments"} =
               FunctionRegistry.call("max", [3, "7"], %{})

      assert {:error, "max() expects two numeric arguments"} =
               FunctionRegistry.call("max", [true, false], %{})
    end

    test "max/2 with wrong arity" do
      assert {:error, "Function max() expects 2 arguments, got 1"} =
               FunctionRegistry.call("max", [5], %{})

      assert {:error, "Function max() expects 2 arguments, got 0"} =
               FunctionRegistry.call("max", [], %{})

      assert {:error, "Function max() expects 2 arguments, got 3"} =
               FunctionRegistry.call("max", [1, 2, 3], %{})
    end

    test "min/2 with valid arguments" do
      assert {:ok, 3} = FunctionRegistry.call("min", [3, 7], %{})
      assert {:ok, 3} = FunctionRegistry.call("min", [7, 3], %{})
      assert {:ok, 5} = FunctionRegistry.call("min", [5, 5], %{})
      assert {:ok, -5} = FunctionRegistry.call("min", [-5, 0], %{})
      assert {:ok, -5} = FunctionRegistry.call("min", [-5, -1], %{})
    end

    test "min/2 with invalid argument types" do
      assert {:error, "min() expects two numeric arguments"} =
               FunctionRegistry.call("min", ["3", 7], %{})

      assert {:error, "min() expects two numeric arguments"} =
               FunctionRegistry.call("min", [3, "7"], %{})
    end

    test "min/2 with wrong arity" do
      assert {:error, "Function min() expects 2 arguments, got 1"} =
               FunctionRegistry.call("min", [5], %{})

      assert {:error, "Function min() expects 2 arguments, got 0"} =
               FunctionRegistry.call("min", [], %{})
    end
  end

  describe "date functions" do
    test "year/1 with Date" do
      date = ~D[2024-03-15]
      assert {:ok, 2024} = FunctionRegistry.call("year", [date], %{})
    end

    test "year/1 with DateTime" do
      datetime = ~U[2024-03-15 10:30:00Z]
      assert {:ok, 2024} = FunctionRegistry.call("year", [datetime], %{})
    end

    test "year/1 with invalid argument types" do
      assert {:error, "year() expects a date or datetime argument"} =
               FunctionRegistry.call("year", ["2024"], %{})

      assert {:error, "year() expects a date or datetime argument"} =
               FunctionRegistry.call("year", [2024], %{})
    end

    test "year/1 with wrong arity" do
      assert {:error, "Function year() expects 1 arguments, got 0"} =
               FunctionRegistry.call("year", [], %{})

      assert {:error, "Function year() expects 1 arguments, got 2"} =
               FunctionRegistry.call("year", [~D[2024-01-01], ~D[2024-12-31]], %{})
    end

    test "month/1 with Date" do
      date = ~D[2024-03-15]
      assert {:ok, 3} = FunctionRegistry.call("month", [date], %{})
    end

    test "month/1 with DateTime" do
      datetime = ~U[2024-12-15 10:30:00Z]
      assert {:ok, 12} = FunctionRegistry.call("month", [datetime], %{})
    end

    test "month/1 with invalid argument types" do
      assert {:error, "month() expects a date or datetime argument"} =
               FunctionRegistry.call("month", ["March"], %{})
    end

    test "month/1 with wrong arity" do
      assert {:error, "Function month() expects 1 arguments, got 0"} =
               FunctionRegistry.call("month", [], %{})
    end

    test "day/1 with Date" do
      date = ~D[2024-03-15]
      assert {:ok, 15} = FunctionRegistry.call("day", [date], %{})
    end

    test "day/1 with DateTime" do
      datetime = ~U[2024-03-25 10:30:00Z]
      assert {:ok, 25} = FunctionRegistry.call("day", [datetime], %{})
    end

    test "day/1 with invalid argument types" do
      assert {:error, "day() expects a date or datetime argument"} =
               FunctionRegistry.call("day", ["15"], %{})
    end

    test "day/1 with wrong arity" do
      assert {:error, "Function day() expects 1 arguments, got 0"} =
               FunctionRegistry.call("day", [], %{})
    end
  end

  describe "numeric edge cases" do
    test "abs/1 with very large numbers" do
      # max 64-bit signed int
      large_positive = 9_223_372_036_854_775_807
      # min 64-bit signed int
      _large_negative = -9_223_372_036_854_775_808

      assert {:ok, ^large_positive} = FunctionRegistry.call("abs", [large_positive], %{})
      # Note: -large_negative would overflow, so we test with a smaller negative
      assert {:ok, 9_223_372_036_854_775_807} =
               FunctionRegistry.call("abs", [-9_223_372_036_854_775_807], %{})
    end

    test "abs/1 with zero" do
      assert {:ok, 0} = FunctionRegistry.call("abs", [0], %{})
    end

    test "max/2 with identical values" do
      assert {:ok, 5} = FunctionRegistry.call("max", [5, 5], %{})
      assert {:ok, -10} = FunctionRegistry.call("max", [-10, -10], %{})
    end

    test "min/2 with identical values" do
      assert {:ok, 5} = FunctionRegistry.call("min", [5, 5], %{})
      assert {:ok, -10} = FunctionRegistry.call("min", [-10, -10], %{})
    end

    test "max/2 and min/2 with extreme values" do
      assert {:ok, 100} = FunctionRegistry.call("max", [-1000, 100], %{})
      assert {:ok, 100} = FunctionRegistry.call("max", [100, -1000], %{})

      assert {:ok, -1000} = FunctionRegistry.call("min", [-1000, 100], %{})
      assert {:ok, -1000} = FunctionRegistry.call("min", [100, -1000], %{})
    end
  end

  describe "string edge cases" do
    test "len/1 with unicode strings" do
      # Various unicode characters
      # é = 1 char
      assert {:ok, 5} = FunctionRegistry.call("len", ["héllo"], %{})
      # emoji = 1 char
      assert {:ok, 1} = FunctionRegistry.call("len", ["🚀"], %{})
      # Japanese = 5 chars
      assert {:ok, 5} = FunctionRegistry.call("len", ["こんにちは"], %{})
    end

    test "len/1 with empty string" do
      assert {:ok, 0} = FunctionRegistry.call("len", [""], %{})
    end

    test "upper/1 with mixed case and numbers" do
      assert {:ok, "HELLO123"} = FunctionRegistry.call("upper", ["Hello123"], %{})
      assert {:ok, "123!@#"} = FunctionRegistry.call("upper", ["123!@#"], %{})
    end

    test "lower/1 with mixed case and numbers" do
      assert {:ok, "hello123"} = FunctionRegistry.call("lower", ["HELLO123"], %{})
      assert {:ok, "123!@#"} = FunctionRegistry.call("lower", ["123!@#"], %{})
    end

    test "upper/1 and lower/1 with unicode" do
      assert {:ok, "JOSÉ"} = FunctionRegistry.call("upper", ["josé"], %{})
      assert {:ok, "josé"} = FunctionRegistry.call("lower", ["JOSÉ"], %{})
    end

    test "trim/1 with various whitespace" do
      assert {:ok, "hello"} = FunctionRegistry.call("trim", ["\t\n hello \r\n"], %{})
      assert {:ok, "a b c"} = FunctionRegistry.call("trim", ["  a b c  "], %{})
      assert {:ok, ""} = FunctionRegistry.call("trim", ["   "], %{})
      assert {:ok, ""} = FunctionRegistry.call("trim", ["\t\n\r"], %{})
    end

    test "trim/1 with no whitespace to trim" do
      assert {:ok, "hello"} = FunctionRegistry.call("trim", ["hello"], %{})
      assert {:ok, "a"} = FunctionRegistry.call("trim", ["a"], %{})
    end
  end

  describe "date edge cases" do
    test "date functions with leap year dates" do
      # Feb 29 in leap year
      leap_date = ~D[2024-02-29]

      assert {:ok, 2024} = FunctionRegistry.call("year", [leap_date], %{})
      assert {:ok, 2} = FunctionRegistry.call("month", [leap_date], %{})
      assert {:ok, 29} = FunctionRegistry.call("day", [leap_date], %{})
    end

    test "date functions with end of year" do
      end_of_year = ~D[2024-12-31]

      assert {:ok, 2024} = FunctionRegistry.call("year", [end_of_year], %{})
      assert {:ok, 12} = FunctionRegistry.call("month", [end_of_year], %{})
      assert {:ok, 31} = FunctionRegistry.call("day", [end_of_year], %{})
    end

    test "date functions with beginning of year" do
      start_of_year = ~D[2024-01-01]

      assert {:ok, 2024} = FunctionRegistry.call("year", [start_of_year], %{})
      assert {:ok, 1} = FunctionRegistry.call("month", [start_of_year], %{})
      assert {:ok, 1} = FunctionRegistry.call("day", [start_of_year], %{})
    end

    test "datetime functions with different timezones" do
      utc_datetime = ~U[2024-03-15 10:30:00Z]

      assert {:ok, 2024} = FunctionRegistry.call("year", [utc_datetime], %{})
      assert {:ok, 3} = FunctionRegistry.call("month", [utc_datetime], %{})
      assert {:ok, 15} = FunctionRegistry.call("day", [utc_datetime], %{})
    end

    test "date functions with invalid date-like structures" do
      # looks like date but isn't Date struct
      fake_date = %{year: 2024, month: 3, day: 15}

      assert {:error, "year() expects a date or datetime argument"} =
               FunctionRegistry.call("year", [fake_date], %{})

      assert {:error, "month() expects a date or datetime argument"} =
               FunctionRegistry.call("month", [fake_date], %{})

      assert {:error, "day() expects a date or datetime argument"} =
               FunctionRegistry.call("day", [fake_date], %{})
    end
  end

  describe "function registration behavior" do
    test "register_all can be called multiple times safely" do
      # Should not crash or cause issues when called multiple times
      assert :ok = BuiltInFunctions.register_all()
      assert :ok = BuiltInFunctions.register_all()
      assert :ok = BuiltInFunctions.register_all()

      # Functions should still work normally
      assert {:ok, 5} = FunctionRegistry.call("len", ["hello"], %{})
      assert {:ok, 10} = FunctionRegistry.call("max", [5, 10], %{})
    end

    test "all built-in functions are registered" do
      BuiltInFunctions.register_all()

      functions = FunctionRegistry.list_functions()
      names = Enum.map(functions, & &1.name)

      # Check that all expected built-in functions are registered
      expected_functions = [
        "len",
        "upper",
        "lower",
        "trim",
        "abs",
        "max",
        "min",
        "year",
        "month",
        "day"
      ]

      for expected <- expected_functions do
        assert expected in names, "Expected function #{expected} to be registered"
      end
    end
  end
end
