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
      {1, year_func} = DateFunctions.all_functions()["Date.year"]

      # Test with no arguments
      assert {:error, "Date.year() expects exactly 1 argument"} = year_func.([], %{})

      # Test with too many arguments
      date = Date.from_iso8601!("2024-01-15")
      assert {:error, "Date.year() expects exactly 1 argument"} = year_func.([date, date], %{})
    end

    test "month/2 with wrong number of arguments" do
      {1, month_func} = DateFunctions.all_functions()["Date.month"]

      # Test with no arguments
      assert {:error, "Date.month() expects exactly 1 argument"} = month_func.([], %{})

      # Test with too many arguments
      date = Date.from_iso8601!("2024-01-15")
      assert {:error, "Date.month() expects exactly 1 argument"} = month_func.([date, date], %{})
    end

    test "day/2 with wrong number of arguments" do
      {1, day_func} = DateFunctions.all_functions()["Date.day"]

      # Test with no arguments
      assert {:error, "Date.day() expects exactly 1 argument"} = day_func.([], %{})

      # Test with too many arguments
      date = Date.from_iso8601!("2024-01-15")
      assert {:error, "Date.day() expects exactly 1 argument"} = day_func.([date, date], %{})
    end

    test "starts_with/2 with wrong number of arguments" do
      {2, starts_with_func} = SystemFunctions.all_functions()["starts_with"]

      assert {:error, "starts_with() expects exactly 2 arguments"} = starts_with_func.([], %{})

      assert {:error, "starts_with() expects exactly 2 arguments"} =
               starts_with_func.(["a", "b", "c"], %{})
    end

    test "ends_with/2 with wrong number of arguments" do
      {2, ends_with_func} = SystemFunctions.all_functions()["ends_with"]

      assert {:error, "ends_with() expects exactly 2 arguments"} = ends_with_func.([], %{})

      assert {:error, "ends_with() expects exactly 2 arguments"} =
               ends_with_func.(["a", "b", "c"], %{})
    end

    test "index_of/2 with wrong number of arguments" do
      {2, index_of_func} = SystemFunctions.all_functions()["index_of"]

      assert {:error, "index_of() expects exactly 2 arguments"} = index_of_func.([], %{})

      assert {:error, "index_of() expects exactly 2 arguments"} =
               index_of_func.(["a", "b", "c"], %{})
    end

    test "substring/2 with wrong number of arguments" do
      {[2, 3], substring_func} = SystemFunctions.all_functions()["substring"]

      assert {:error, "substring() expects 2 or 3 arguments"} = substring_func.([], %{})

      assert {:error, "substring() expects 2 or 3 arguments"} =
               substring_func.(["a"], %{})
    end
  end

  describe "date functions with DateTime objects" do
    test "year/2 with DateTime" do
      {1, year_func} = DateFunctions.all_functions()["Date.year"]

      datetime = ~U[2024-01-15 10:30:00Z]
      assert {:ok, 2024} = year_func.([datetime], %{})
    end

    test "month/2 with DateTime" do
      {1, month_func} = DateFunctions.all_functions()["Date.month"]

      datetime = ~U[2024-01-15 10:30:00Z]
      assert {:ok, 1} = month_func.([datetime], %{})
    end

    test "day/2 with DateTime" do
      {1, day_func} = DateFunctions.all_functions()["Date.day"]

      datetime = ~U[2024-01-15 10:30:00Z]
      assert {:ok, 15} = day_func.([datetime], %{})
    end
  end
end
