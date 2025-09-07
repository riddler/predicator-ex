defmodule Predicator.Functions.SystemFunctionsCoverageTest do
  use ExUnit.Case, async: true

  alias Predicator.Functions.{DateFunctions, SystemFunctions}

  describe "error cases for function arity and types" do
    test "len/2 with wrong number of arguments" do
      {1, len_func} = SystemFunctions.all_functions()["len"]

      # Test with no arguments
      assert {:error, "len() expects exactly 1 argument"} = len_func.([], %{})

      # Test with too many arguments
      assert {:error, "len() expects exactly 1 argument"} = len_func.(["a", "b"], %{})
    end

    test "upper/2 with wrong number of arguments" do
      {1, upper_func} = SystemFunctions.all_functions()["upper"]

      # Test with no arguments
      assert {:error, "upper() expects exactly 1 argument"} = upper_func.([], %{})

      # Test with too many arguments
      assert {:error, "upper() expects exactly 1 argument"} = upper_func.(["a", "b"], %{})
    end

    test "lower/2 with wrong number of arguments" do
      {1, lower_func} = SystemFunctions.all_functions()["lower"]

      # Test with no arguments
      assert {:error, "lower() expects exactly 1 argument"} = lower_func.([], %{})

      # Test with too many arguments
      assert {:error, "lower() expects exactly 1 argument"} = lower_func.(["a", "b"], %{})
    end

    test "trim/2 with wrong number of arguments" do
      {1, trim_func} = SystemFunctions.all_functions()["trim"]

      # Test with no arguments
      assert {:error, "trim() expects exactly 1 argument"} = trim_func.([], %{})

      # Test with too many arguments
      assert {:error, "trim() expects exactly 1 argument"} = trim_func.(["a", "b"], %{})
    end

    test "year/2 with wrong number of arguments" do
      {1, year_func} = DateFunctions.all_functions()["year"]

      # Test with no arguments
      assert {:error, "year() expects exactly 1 argument"} = year_func.([], %{})

      # Test with too many arguments
      date = Date.from_iso8601!("2024-01-15")
      assert {:error, "year() expects exactly 1 argument"} = year_func.([date, date], %{})
    end

    test "month/2 with wrong number of arguments" do
      {1, month_func} = DateFunctions.all_functions()["month"]

      # Test with no arguments
      assert {:error, "month() expects exactly 1 argument"} = month_func.([], %{})

      # Test with too many arguments
      date = Date.from_iso8601!("2024-01-15")
      assert {:error, "month() expects exactly 1 argument"} = month_func.([date, date], %{})
    end

    test "day/2 with wrong number of arguments" do
      {1, day_func} = DateFunctions.all_functions()["day"]

      # Test with no arguments
      assert {:error, "day() expects exactly 1 argument"} = day_func.([], %{})

      # Test with too many arguments
      date = Date.from_iso8601!("2024-01-15")
      assert {:error, "day() expects exactly 1 argument"} = day_func.([date, date], %{})
    end
  end

  describe "date functions with DateTime objects" do
    test "year/2 with DateTime" do
      {1, year_func} = DateFunctions.all_functions()["year"]

      datetime = ~U[2024-01-15 10:30:00Z]
      assert {:ok, 2024} = year_func.([datetime], %{})
    end

    test "month/2 with DateTime" do
      {1, month_func} = DateFunctions.all_functions()["month"]

      datetime = ~U[2024-01-15 10:30:00Z]
      assert {:ok, 1} = month_func.([datetime], %{})
    end

    test "day/2 with DateTime" do
      {1, day_func} = DateFunctions.all_functions()["day"]

      datetime = ~U[2024-01-15 10:30:00Z]
      assert {:ok, 15} = day_func.([datetime], %{})
    end
  end
end
