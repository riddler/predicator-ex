defmodule Predicator.Functions.SystemFunctionsCoverageTest do
  use ExUnit.Case, async: true

  alias Predicator.Context
  alias Predicator.Functions.{DateFunctions, SystemFunctions}

  @context Context.new()

  describe "error cases for function arity and types" do
    test "len/2 with wrong number of arguments" do
      # Test with no arguments
      assert {:error, "len() expects exactly 1 argument"} = SystemFunctions.call_len([], @context)

      # Test with too many arguments
      assert {:error, "len() expects exactly 1 argument"} =
               SystemFunctions.call_len(["a", "b"], @context)
    end

    test "upper/2 with wrong number of arguments" do
      # Test with no arguments
      assert {:error, "upper() expects exactly 1 argument"} =
               SystemFunctions.call_upper([], @context)

      # Test with too many arguments
      assert {:error, "upper() expects exactly 1 argument"} =
               SystemFunctions.call_upper(["a", "b"], @context)
    end

    test "lower/2 with wrong number of arguments" do
      # Test with no arguments
      assert {:error, "lower() expects exactly 1 argument"} =
               SystemFunctions.call_lower([], @context)

      # Test with too many arguments
      assert {:error, "lower() expects exactly 1 argument"} =
               SystemFunctions.call_lower(["a", "b"], @context)
    end

    test "trim/2 with wrong number of arguments" do
      # Test with no arguments
      assert {:error, "trim() expects exactly 1 argument"} =
               SystemFunctions.call_trim([], @context)

      # Test with too many arguments
      assert {:error, "trim() expects exactly 1 argument"} =
               SystemFunctions.call_trim(["a", "b"], @context)
    end

    test "year/2 with wrong number of arguments" do
      # Test with no arguments
      assert {:error, "Date.year() expects exactly 1 argument"} =
               DateFunctions.call_year([], @context)

      # Test with too many arguments
      date = Date.from_iso8601!("2024-01-15")

      assert {:error, "Date.year() expects exactly 1 argument"} =
               DateFunctions.call_year([date, date], @context)
    end

    test "month/2 with wrong number of arguments" do
      # Test with no arguments
      assert {:error, "Date.month() expects exactly 1 argument"} =
               DateFunctions.call_month([], @context)

      # Test with too many arguments
      date = Date.from_iso8601!("2024-01-15")

      assert {:error, "Date.month() expects exactly 1 argument"} =
               DateFunctions.call_month([date, date], @context)
    end

    test "day/2 with wrong number of arguments" do
      # Test with no arguments
      assert {:error, "Date.day() expects exactly 1 argument"} =
               DateFunctions.call_day([], @context)

      # Test with too many arguments
      date = Date.from_iso8601!("2024-01-15")

      assert {:error, "Date.day() expects exactly 1 argument"} =
               DateFunctions.call_day([date, date], @context)
    end

    test "starts_with/2 with wrong number of arguments" do
      assert {:error, "starts_with() expects exactly 2 arguments"} =
               SystemFunctions.call_starts_with([], @context)

      assert {:error, "starts_with() expects exactly 2 arguments"} =
               SystemFunctions.call_starts_with(["a", "b", "c"], @context)
    end

    test "ends_with/2 with wrong number of arguments" do
      assert {:error, "ends_with() expects exactly 2 arguments"} =
               SystemFunctions.call_ends_with([], @context)

      assert {:error, "ends_with() expects exactly 2 arguments"} =
               SystemFunctions.call_ends_with(["a", "b", "c"], @context)
    end

    test "index_of/2 with wrong number of arguments" do
      assert {:error, "index_of() expects exactly 2 arguments"} =
               SystemFunctions.call_index_of([], @context)

      assert {:error, "index_of() expects exactly 2 arguments"} =
               SystemFunctions.call_index_of(["a", "b", "c"], @context)
    end

    test "substring/2 with wrong number of arguments" do
      assert {:error, "substring() expects 2 or 3 arguments"} =
               SystemFunctions.call_substring([], @context)

      assert {:error, "substring() expects 2 or 3 arguments"} =
               SystemFunctions.call_substring(["a"], @context)
    end
  end

  describe "date functions with DateTime objects" do
    test "year/2 with DateTime" do
      datetime = ~U[2024-01-15 10:30:00Z]
      assert {:ok, 2024} = DateFunctions.call_year([datetime], @context)
    end

    test "month/2 with DateTime" do
      datetime = ~U[2024-01-15 10:30:00Z]
      assert {:ok, 1} = DateFunctions.call_month([datetime], @context)
    end

    test "day/2 with DateTime" do
      datetime = ~U[2024-01-15 10:30:00Z]
      assert {:ok, 15} = DateFunctions.call_day([datetime], @context)
    end
  end
end
