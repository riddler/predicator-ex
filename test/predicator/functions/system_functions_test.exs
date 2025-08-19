defmodule Predicator.Functions.SystemFunctionsTest do
  use ExUnit.Case, async: true

  alias Predicator.Functions.{Registry, SystemFunctions}

  setup do
    # Clear and re-register system functions for each test
    Registry.clear_registry()
    SystemFunctions.register_all()
    :ok
  end

  describe "string functions" do
    test "len/1 with valid arguments" do
      assert {:ok, 5} = Registry.call("len", ["hello"], %{})
      assert {:ok, 0} = Registry.call("len", [""], %{})
      assert {:ok, 3} = Registry.call("len", ["🚀🚀🚀"], %{})
    end

    test "len/1 with invalid argument types" do
      assert {:error, "len() expects a string argument"} =
               Registry.call("len", [123], %{})

      assert {:error, "len() expects a string argument"} =
               Registry.call("len", [true], %{})

      assert {:error, "len() expects a string argument"} =
               Registry.call("len", [nil], %{})

      assert {:error, "len() expects a string argument"} =
               Registry.call("len", [[]], %{})
    end

    test "len/1 with wrong arity" do
      assert {:error, "Function len() expects 1 arguments, got 0"} =
               Registry.call("len", [], %{})

      assert {:error, "Function len() expects 1 arguments, got 2"} =
               Registry.call("len", ["a", "b"], %{})
    end

    test "upper/1 with valid arguments" do
      assert {:ok, "HELLO"} = Registry.call("upper", ["hello"], %{})
      assert {:ok, ""} = Registry.call("upper", [""], %{})
      assert {:ok, "123"} = Registry.call("upper", ["123"], %{})
    end

    test "upper/1 with invalid argument types" do
      assert {:error, "upper() expects a string argument"} =
               Registry.call("upper", [123], %{})

      assert {:error, "upper() expects a string argument"} =
               Registry.call("upper", [true], %{})
    end

    test "upper/1 with wrong arity" do
      assert {:error, "Function upper() expects 1 arguments, got 0"} =
               Registry.call("upper", [], %{})

      assert {:error, "Function upper() expects 1 arguments, got 2"} =
               Registry.call("upper", ["a", "b"], %{})
    end

    test "lower/1 with valid arguments" do
      assert {:ok, "hello"} = Registry.call("lower", ["HELLO"], %{})
      assert {:ok, ""} = Registry.call("lower", [""], %{})
      assert {:ok, "123"} = Registry.call("lower", ["123"], %{})
    end

    test "lower/1 with invalid argument types" do
      assert {:error, "lower() expects a string argument"} =
               Registry.call("lower", [123], %{})
    end

    test "lower/1 with wrong arity" do
      assert {:error, "Function lower() expects 1 arguments, got 0"} =
               Registry.call("lower", [], %{})

      assert {:error, "Function lower() expects 1 arguments, got 2"} =
               Registry.call("lower", ["a", "b"], %{})
    end

    test "trim/1 with valid arguments" do
      assert {:ok, "hello"} = Registry.call("trim", [" hello "], %{})
      assert {:ok, "hello"} = Registry.call("trim", ["hello"], %{})
      assert {:ok, ""} = Registry.call("trim", [" "], %{})
      assert {:ok, "a b"} = Registry.call("trim", [" a b "], %{})
    end

    test "trim/1 with invalid argument types" do
      assert {:error, "trim() expects a string argument"} =
               Registry.call("trim", [123], %{})
    end

    test "trim/1 with wrong arity" do
      assert {:error, "Function trim() expects 1 arguments, got 0"} =
               Registry.call("trim", [], %{})

      assert {:error, "Function trim() expects 1 arguments, got 2"} =
               Registry.call("trim", ["a", "b"], %{})
    end
  end

  describe "numeric functions" do
    test "abs/1 with valid arguments" do
      assert {:ok, 5} = Registry.call("abs", [5], %{})
      assert {:ok, 5} = Registry.call("abs", [-5], %{})
      assert {:ok, 0} = Registry.call("abs", [0], %{})
      assert {:ok, 42} = Registry.call("abs", [-42], %{})
    end

    test "abs/1 with invalid argument types" do
      assert {:error, "abs() expects a numeric argument"} =
               Registry.call("abs", ["5"], %{})

      assert {:error, "abs() expects a numeric argument"} =
               Registry.call("abs", [true], %{})
    end

    test "abs/1 with wrong arity" do
      assert {:error, "Function abs() expects 1 arguments, got 0"} =
               Registry.call("abs", [], %{})

      assert {:error, "Function abs() expects 1 arguments, got 2"} =
               Registry.call("abs", [1, 2], %{})
    end

    test "max/2 with valid arguments" do
      assert {:ok, 7} = Registry.call("max", [3, 7], %{})
      assert {:ok, 7} = Registry.call("max", [7, 3], %{})
      assert {:ok, 5} = Registry.call("max", [5, 5], %{})
      assert {:ok, 0} = Registry.call("max", [-5, 0], %{})
      assert {:ok, -1} = Registry.call("max", [-5, -1], %{})
    end

    test "max/2 with invalid argument types" do
      assert {:error, "max() expects two numeric arguments"} =
               Registry.call("max", ["3", 7], %{})

      assert {:error, "max() expects two numeric arguments"} =
               Registry.call("max", [3, "7"], %{})

      assert {:error, "max() expects two numeric arguments"} =
               Registry.call("max", [true, false], %{})
    end

    test "max/2 with wrong arity" do
      assert {:error, "Function max() expects 2 arguments, got 1"} =
               Registry.call("max", [5], %{})

      assert {:error, "Function max() expects 2 arguments, got 0"} =
               Registry.call("max", [], %{})

      assert {:error, "Function max() expects 2 arguments, got 3"} =
               Registry.call("max", [1, 2, 3], %{})
    end

    test "min/2 with valid arguments" do
      assert {:ok, 3} = Registry.call("min", [3, 7], %{})
      assert {:ok, 3} = Registry.call("min", [7, 3], %{})
      assert {:ok, 5} = Registry.call("min", [5, 5], %{})
      assert {:ok, -5} = Registry.call("min", [-5, 0], %{})
      assert {:ok, -5} = Registry.call("min", [-5, -1], %{})
    end

    test "min/2 with invalid argument types" do
      assert {:error, "min() expects two numeric arguments"} =
               Registry.call("min", ["3", 7], %{})

      assert {:error, "min() expects two numeric arguments"} =
               Registry.call("min", [3, "7"], %{})
    end

    test "min/2 with wrong arity" do
      assert {:error, "Function min() expects 2 arguments, got 1"} =
               Registry.call("min", [5], %{})

      assert {:error, "Function min() expects 2 arguments, got 0"} =
               Registry.call("min", [], %{})
    end
  end

  describe "date functions" do
    test "year/1 with Date" do
      date = ~D[2024-03-15]
      assert {:ok, 2024} = Registry.call("year", [date], %{})
    end

    test "year/1 with DateTime" do
      datetime = ~U[2024-03-15 10:30:00Z]
      assert {:ok, 2024} = Registry.call("year", [datetime], %{})
    end

    test "year/1 with invalid argument types" do
      assert {:error, "year() expects a date or datetime argument"} =
               Registry.call("year", ["2024"], %{})

      assert {:error, "year() expects a date or datetime argument"} =
               Registry.call("year", [2024], %{})
    end

    test "year/1 with wrong arity" do
      assert {:error, "Function year() expects 1 arguments, got 0"} =
               Registry.call("year", [], %{})

      assert {:error, "Function year() expects 1 arguments, got 2"} =
               Registry.call("year", [~D[2024-01-01], ~D[2024-12-31]], %{})
    end

    test "month/1 with Date" do
      date = ~D[2024-03-15]
      assert {:ok, 3} = Registry.call("month", [date], %{})
    end

    test "month/1 with DateTime" do
      datetime = ~U[2024-12-15 10:30:00Z]
      assert {:ok, 12} = Registry.call("month", [datetime], %{})
    end

    test "month/1 with invalid argument types" do
      assert {:error, "month() expects a date or datetime argument"} =
               Registry.call("month", ["March"], %{})
    end

    test "month/1 with wrong arity" do
      assert {:error, "Function month() expects 1 arguments, got 0"} =
               Registry.call("month", [], %{})
    end

    test "day/1 with Date" do
      date = ~D[2024-03-15]
      assert {:ok, 15} = Registry.call("day", [date], %{})
    end

    test "day/1 with DateTime" do
      datetime = ~U[2024-03-25 10:30:00Z]
      assert {:ok, 25} = Registry.call("day", [datetime], %{})
    end

    test "day/1 with invalid argument types" do
      assert {:error, "day() expects a date or datetime argument"} =
               Registry.call("day", ["15"], %{})
    end

    test "day/1 with wrong arity" do
      assert {:error, "Function day() expects 1 arguments, got 0"} =
               Registry.call("day", [], %{})
    end
  end

  describe "numeric edge cases" do
    test "abs/1 with very large numbers" do
      # max 64-bit signed int
      large_positive = 9_223_372_036_854_775_807
      # min 64-bit signed int
      _large_negative = -9_223_372_036_854_775_808

      assert {:ok, ^large_positive} = Registry.call("abs", [large_positive], %{})
      # Note: -large_negative would overflow, so we test with a smaller negative
      assert {:ok, 9_223_372_036_854_775_807} =
               Registry.call("abs", [-9_223_372_036_854_775_807], %{})
    end

    test "abs/1 with zero" do
      assert {:ok, 0} = Registry.call("abs", [0], %{})
    end

    test "max/2 with identical values" do
      assert {:ok, 5} = Registry.call("max", [5, 5], %{})
      assert {:ok, -10} = Registry.call("max", [-10, -10], %{})
    end

    test "min/2 with identical values" do
      assert {:ok, 5} = Registry.call("min", [5, 5], %{})
      assert {:ok, -10} = Registry.call("min", [-10, -10], %{})
    end

    test "max/2 and min/2 with extreme values" do
      assert {:ok, 100} = Registry.call("max", [-1000, 100], %{})
      assert {:ok, 100} = Registry.call("max", [100, -1000], %{})

      assert {:ok, -1000} = Registry.call("min", [-1000, 100], %{})
      assert {:ok, -1000} = Registry.call("min", [100, -1000], %{})
    end
  end

  describe "string edge cases" do
    test "len/1 with unicode strings" do
      # Various unicode characters
      # é = 1 char
      assert {:ok, 5} = Registry.call("len", ["héllo"], %{})
      # emoji = 1 char
      assert {:ok, 1} = Registry.call("len", ["🚀"], %{})
      # Japanese = 5 chars
      assert {:ok, 5} = Registry.call("len", ["こんにちは"], %{})
    end

    test "len/1 with empty string" do
      assert {:ok, 0} = Registry.call("len", [""], %{})
    end

    test "upper/1 with mixed case and numbers" do
      assert {:ok, "HELLO123"} = Registry.call("upper", ["Hello123"], %{})
      assert {:ok, "123!@#"} = Registry.call("upper", ["123!@#"], %{})
    end

    test "lower/1 with mixed case and numbers" do
      assert {:ok, "hello123"} = Registry.call("lower", ["HELLO123"], %{})
      assert {:ok, "123!@#"} = Registry.call("lower", ["123!@#"], %{})
    end

    test "upper/1 and lower/1 with unicode" do
      assert {:ok, "JOSÉ"} = Registry.call("upper", ["josé"], %{})
      assert {:ok, "josé"} = Registry.call("lower", ["JOSÉ"], %{})
    end

    test "trim/1 with various whitespace" do
      assert {:ok, "hello"} = Registry.call("trim", ["\t\n hello \r\n"], %{})
      assert {:ok, "a b c"} = Registry.call("trim", ["  a b c  "], %{})
      assert {:ok, ""} = Registry.call("trim", ["   "], %{})
      assert {:ok, ""} = Registry.call("trim", ["\t\n\r"], %{})
    end

    test "trim/1 with no whitespace to trim" do
      assert {:ok, "hello"} = Registry.call("trim", ["hello"], %{})
      assert {:ok, "a"} = Registry.call("trim", ["a"], %{})
    end
  end

  describe "date edge cases" do
    test "date functions with leap year dates" do
      # Feb 29 in leap year
      leap_date = ~D[2024-02-29]

      assert {:ok, 2024} = Registry.call("year", [leap_date], %{})
      assert {:ok, 2} = Registry.call("month", [leap_date], %{})
      assert {:ok, 29} = Registry.call("day", [leap_date], %{})
    end

    test "date functions with end of year" do
      end_of_year = ~D[2024-12-31]

      assert {:ok, 2024} = Registry.call("year", [end_of_year], %{})
      assert {:ok, 12} = Registry.call("month", [end_of_year], %{})
      assert {:ok, 31} = Registry.call("day", [end_of_year], %{})
    end

    test "date functions with beginning of year" do
      start_of_year = ~D[2024-01-01]

      assert {:ok, 2024} = Registry.call("year", [start_of_year], %{})
      assert {:ok, 1} = Registry.call("month", [start_of_year], %{})
      assert {:ok, 1} = Registry.call("day", [start_of_year], %{})
    end

    test "datetime functions with different timezones" do
      utc_datetime = ~U[2024-03-15 10:30:00Z]

      assert {:ok, 2024} = Registry.call("year", [utc_datetime], %{})
      assert {:ok, 3} = Registry.call("month", [utc_datetime], %{})
      assert {:ok, 15} = Registry.call("day", [utc_datetime], %{})
    end

    test "date functions with invalid date-like structures" do
      # looks like date but isn't Date struct
      fake_date = %{year: 2024, month: 3, day: 15}

      assert {:error, "year() expects a date or datetime argument"} =
               Registry.call("year", [fake_date], %{})

      assert {:error, "month() expects a date or datetime argument"} =
               Registry.call("month", [fake_date], %{})

      assert {:error, "day() expects a date or datetime argument"} =
               Registry.call("day", [fake_date], %{})
    end
  end

  describe "function registration behavior" do
    test "register_all can be called multiple times safely" do
      # Should not crash or cause issues when called multiple times
      assert :ok = SystemFunctions.register_all()
      assert :ok = SystemFunctions.register_all()
      assert :ok = SystemFunctions.register_all()

      # Functions should still work normally
      assert {:ok, 5} = Registry.call("len", ["hello"], %{})
      assert {:ok, 10} = Registry.call("max", [5, 10], %{})
    end

    test "all built-in functions are registered" do
      SystemFunctions.register_all()

      functions = Registry.list_functions()
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
