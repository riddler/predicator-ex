defmodule Predicator.Functions.DateFunctions do
  @moduledoc """
  Date and time related functions for use in predicator expressions.

  This module provides temporal functions for working with dates, times,
  durations, and relative date calculations.

  ## Available Functions

  ### Date/Time Functions
  - `year(date)` - Extracts the year from a date or datetime
  - `month(date)` - Extracts the month from a date or datetime
  - `day(date)` - Extracts the day from a date or datetime
  - `now()` - Returns the current UTC datetime (alias for Date.now())

  ## Examples

      iex> Predicator.Functions.DateFunctions.call_year([~D[2023-05-15]], %{})
      {:ok, 2023}

      iex> Predicator.Functions.DateFunctions.call_date_now([], %{})
      {:ok, %DateTime{}}
  """

  alias Predicator.Types

  @type function_result :: {:ok, Types.value()} | {:error, binary()}

  @doc """
  Returns all date functions as a map in the format expected by the evaluator.

  ## Returns

  A map where keys are function names and values are `{arity, function}` tuples.

  ## Examples

      iex> functions = Predicator.Functions.DateFunctions.all_functions()
      iex> Map.has_key?(functions, "year")
      true

      iex> {arity, _function} = functions["year"]
      iex> arity
      1
  """
  @spec all_functions() :: %{binary() => {non_neg_integer(), function()}}
  def all_functions do
    %{
      # Date functions
      "Date.year" => {1, &call_year/2},
      "Date.month" => {1, &call_month/2},
      "Date.day" => {1, &call_day/2},
      "Date.now" => {0, &call_date_now/2}
    }
  end

  # Date function implementations

  @spec call_year([Types.value()], Types.context()) :: function_result()
  def call_year([%Date{year: year}], _context) do
    {:ok, year}
  end

  def call_year([%DateTime{year: year}], _context) do
    {:ok, year}
  end

  def call_year([_value], _context) do
    {:error, "Date.year() expects a date or datetime argument"}
  end

  def call_year(_args, _context) do
    {:error, "Date.year() expects exactly 1 argument"}
  end

  @spec call_month([Types.value()], Types.context()) :: function_result()
  def call_month([%Date{month: month}], _context) do
    {:ok, month}
  end

  def call_month([%DateTime{month: month}], _context) do
    {:ok, month}
  end

  def call_month([_value], _context) do
    {:error, "Date.month() expects a date or datetime argument"}
  end

  def call_month(_args, _context) do
    {:error, "Date.month() expects exactly 1 argument"}
  end

  @spec call_day([Types.value()], Types.context()) :: function_result()
  def call_day([%Date{day: day}], _context) do
    {:ok, day}
  end

  def call_day([%DateTime{day: day}], _context) do
    {:ok, day}
  end

  def call_day([_value], _context) do
    {:error, "Date.day() expects a date or datetime argument"}
  end

  def call_day(_args, _context) do
    {:error, "Date.day() expects exactly 1 argument"}
  end

  @spec call_date_now([Types.value()], Types.context()) :: function_result()
  def call_date_now([], _context) do
    # Return current UTC datetime
    {:ok, DateTime.utc_now()}
  end

  def call_date_now(_args, _context) do
    {:error, "Date.now() expects no arguments"}
  end
end
