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

  @behaviour Predicator.FunctionProvider

  alias Predicator.{Context, Types}

  @type function_result :: {:ok, Types.value()} | {:error, binary()}

  @doc """
  Returns all date functions as a `Predicator.FunctionProvider` map.

  ## Returns

  A map where keys are function names and values are `{arity, atom}` pairs -
  `atom` naming a public `call_*/2` function on this module.

  ## Examples

      iex> functions = Predicator.Functions.DateFunctions.functions()
      iex> Map.has_key?(functions, "Date.year")
      true

      iex> {arity, _atom} = functions["Date.year"]
      iex> arity
      1
  """
  @impl Predicator.FunctionProvider
  @spec functions() :: %{
          Predicator.FunctionProvider.name() => Predicator.FunctionProvider.entry()
        }
  def functions do
    %{
      "Date.year" => {1, :call_year},
      "Date.month" => {1, :call_month},
      "Date.day" => {1, :call_day},
      "Date.now" => {0, :call_date_now}
    }
  end

  # Date function implementations

  @doc "Extracts the year from a date or datetime."
  @spec call_year([Types.value()], Context.t()) :: function_result()
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

  @doc "Extracts the month from a date or datetime."
  @spec call_month([Types.value()], Context.t()) :: function_result()
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

  @doc "Extracts the day from a date or datetime."
  @spec call_day([Types.value()], Context.t()) :: function_result()
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

  @doc "Returns the current UTC datetime (alias for `Date.now()`)."
  @spec call_date_now([Types.value()], Context.t()) :: function_result()
  def call_date_now([], _context) do
    # Return current UTC datetime
    {:ok, DateTime.utc_now()}
  end

  def call_date_now(_args, _context) do
    {:error, "Date.now() expects no arguments"}
  end
end
