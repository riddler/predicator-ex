defmodule Predicator.Functions.DateFunctionsTest do
  use ExUnit.Case, async: true

  alias Predicator.Functions.DateFunctions

  describe "all_functions/0" do
    test "returns map with expected functions" do
      functions = DateFunctions.all_functions()

      # Check that all expected functions are present
      expected_functions = [
        "Date.year",
        "Date.month",
        "Date.day",
        "Date.now"
      ]

      for func_name <- expected_functions do
        assert Map.has_key?(functions, func_name), "Missing function: #{func_name}"
        {arity, function} = functions[func_name]
        assert is_integer(arity) and arity >= 0
        assert is_function(function, 2)
      end
    end

    test "function arities are correct" do
      functions = DateFunctions.all_functions()

      # Check specific arities
      assert {1, _year_func} = functions["Date.year"]
      assert {1, _month_func} = functions["Date.month"]
      assert {1, _day_func} = functions["Date.day"]
      assert {0, _date_now_func} = functions["Date.now"]
    end
  end

  describe "Date.year function" do
    test "extracts year from Date" do
      {1, year_func} = DateFunctions.all_functions()["Date.year"]

      date = ~D[2023-05-15]
      assert {:ok, 2023} = year_func.([date], %{})
    end

    test "extracts year from DateTime" do
      {1, year_func} = DateFunctions.all_functions()["Date.year"]

      datetime = ~U[2023-05-15 10:30:00Z]
      assert {:ok, 2023} = year_func.([datetime], %{})
    end

    test "returns error for non-date argument" do
      {1, year_func} = DateFunctions.all_functions()["Date.year"]

      assert {:error, "Date.year() expects a date or datetime argument"} =
               year_func.(["not a date"], %{})
    end

    test "returns error for wrong argument count" do
      {1, year_func} = DateFunctions.all_functions()["Date.year"]

      assert {:error, "Date.year() expects exactly 1 argument"} = year_func.([], %{})

      date = ~D[2023-05-15]
      assert {:error, "Date.year() expects exactly 1 argument"} = year_func.([date, date], %{})
    end
  end

  describe "Date.month function" do
    test "extracts month from Date" do
      {1, month_func} = DateFunctions.all_functions()["Date.month"]

      date = ~D[2023-05-15]
      assert {:ok, 5} = month_func.([date], %{})
    end

    test "extracts month from DateTime" do
      {1, month_func} = DateFunctions.all_functions()["Date.month"]

      datetime = ~U[2023-05-15 10:30:00Z]
      assert {:ok, 5} = month_func.([datetime], %{})
    end

    test "returns error for non-date argument" do
      {1, month_func} = DateFunctions.all_functions()["Date.month"]

      assert {:error, "Date.month() expects a date or datetime argument"} =
               month_func.(["not a date"], %{})
    end

    test "returns error for wrong argument count" do
      {1, month_func} = DateFunctions.all_functions()["Date.month"]

      assert {:error, "Date.month() expects exactly 1 argument"} = month_func.([], %{})

      date = ~D[2023-05-15]
      assert {:error, "Date.month() expects exactly 1 argument"} = month_func.([date, date], %{})
    end
  end

  describe "Date.day function" do
    test "extracts day from Date" do
      {1, day_func} = DateFunctions.all_functions()["Date.day"]

      date = ~D[2023-05-15]
      assert {:ok, 15} = day_func.([date], %{})
    end

    test "extracts day from DateTime" do
      {1, day_func} = DateFunctions.all_functions()["Date.day"]

      datetime = ~U[2023-05-15 10:30:00Z]
      assert {:ok, 15} = day_func.([datetime], %{})
    end

    test "returns error for non-date argument" do
      {1, day_func} = DateFunctions.all_functions()["Date.day"]

      assert {:error, "Date.day() expects a date or datetime argument"} =
               day_func.(["not a date"], %{})
    end

    test "returns error for wrong argument count" do
      {1, day_func} = DateFunctions.all_functions()["Date.day"]

      assert {:error, "Date.day() expects exactly 1 argument"} = day_func.([], %{})

      date = ~D[2023-05-15]
      assert {:error, "Date.day() expects exactly 1 argument"} = day_func.([date, date], %{})
    end
  end

  describe "Date.now function" do
    test "returns current datetime" do
      {0, date_now_func} = DateFunctions.all_functions()["Date.now"]

      assert {:ok, datetime} = date_now_func.([], %{})
      assert %DateTime{} = datetime

      # Check that the datetime is recent (within the last minute)
      now = DateTime.utc_now()
      diff_seconds = DateTime.diff(now, datetime, :second)
      assert diff_seconds >= 0 and diff_seconds < 60
    end

    test "returns error for wrong argument count" do
      {0, date_now_func} = DateFunctions.all_functions()["Date.now"]

      assert {:error, "Date.now() expects no arguments"} = date_now_func.(["arg"], %{})
    end
  end
end
