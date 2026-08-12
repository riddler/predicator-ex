defmodule Predicator.Functions.DateFunctionsTest do
  use ExUnit.Case, async: true

  alias Predicator.Context
  alias Predicator.Functions.DateFunctions

  @context Context.new()

  describe "functions/0" do
    test "returns map with expected functions" do
      functions = DateFunctions.functions()

      # Check that all expected functions are present
      expected_functions = [
        "Date.year",
        "Date.month",
        "Date.day",
        "Date.now"
      ]

      for func_name <- expected_functions do
        assert Map.has_key?(functions, func_name), "Missing function: #{func_name}"
        {arity, fun_atom} = functions[func_name]
        assert is_integer(arity) and arity >= 0
        assert function_exported?(DateFunctions, fun_atom, 2)
      end
    end

    test "function arities are correct" do
      functions = DateFunctions.functions()

      # Check specific arities
      assert {1, :call_year} = functions["Date.year"]
      assert {1, :call_month} = functions["Date.month"]
      assert {1, :call_day} = functions["Date.day"]
      assert {0, :call_date_now} = functions["Date.now"]
    end
  end

  describe "Date.year function" do
    test "extracts year from Date" do
      date = ~D[2023-05-15]
      assert {:ok, 2023} = DateFunctions.call_year([date], @context)
    end

    test "extracts year from DateTime" do
      datetime = ~U[2023-05-15 10:30:00Z]
      assert {:ok, 2023} = DateFunctions.call_year([datetime], @context)
    end

    test "returns error for non-date argument" do
      assert {:error, "Date.year() expects a date or datetime argument"} =
               DateFunctions.call_year(["not a date"], @context)
    end

    test "returns error for wrong argument count" do
      assert {:error, "Date.year() expects exactly 1 argument"} =
               DateFunctions.call_year([], @context)

      date = ~D[2023-05-15]

      assert {:error, "Date.year() expects exactly 1 argument"} =
               DateFunctions.call_year([date, date], @context)
    end
  end

  describe "Date.month function" do
    test "extracts month from Date" do
      date = ~D[2023-05-15]
      assert {:ok, 5} = DateFunctions.call_month([date], @context)
    end

    test "extracts month from DateTime" do
      datetime = ~U[2023-05-15 10:30:00Z]
      assert {:ok, 5} = DateFunctions.call_month([datetime], @context)
    end

    test "returns error for non-date argument" do
      assert {:error, "Date.month() expects a date or datetime argument"} =
               DateFunctions.call_month(["not a date"], @context)
    end

    test "returns error for wrong argument count" do
      assert {:error, "Date.month() expects exactly 1 argument"} =
               DateFunctions.call_month([], @context)

      date = ~D[2023-05-15]

      assert {:error, "Date.month() expects exactly 1 argument"} =
               DateFunctions.call_month([date, date], @context)
    end
  end

  describe "Date.day function" do
    test "extracts day from Date" do
      date = ~D[2023-05-15]
      assert {:ok, 15} = DateFunctions.call_day([date], @context)
    end

    test "extracts day from DateTime" do
      datetime = ~U[2023-05-15 10:30:00Z]
      assert {:ok, 15} = DateFunctions.call_day([datetime], @context)
    end

    test "returns error for non-date argument" do
      assert {:error, "Date.day() expects a date or datetime argument"} =
               DateFunctions.call_day(["not a date"], @context)
    end

    test "returns error for wrong argument count" do
      assert {:error, "Date.day() expects exactly 1 argument"} =
               DateFunctions.call_day([], @context)

      date = ~D[2023-05-15]

      assert {:error, "Date.day() expects exactly 1 argument"} =
               DateFunctions.call_day([date, date], @context)
    end
  end

  describe "Date.now function" do
    test "returns current datetime" do
      assert {:ok, datetime} = DateFunctions.call_date_now([], @context)
      assert %DateTime{} = datetime

      # Check that the datetime is recent (within the last minute)
      now = DateTime.utc_now()
      diff_seconds = DateTime.diff(now, datetime, :second)
      assert diff_seconds >= 0 and diff_seconds < 60
    end

    test "returns error for wrong argument count" do
      assert {:error, "Date.now() expects no arguments"} =
               DateFunctions.call_date_now(["arg"], @context)
    end
  end
end
