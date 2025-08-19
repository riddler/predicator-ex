defmodule Predicator.BuiltInFunctions do
  @moduledoc """
  Built-in helper functions for use in predicator expressions.

  This module provides a collection of utility functions that can be called
  within predicator expressions using function call syntax. These functions
  operate on values from the evaluation context and return computed results.

  ## Available Functions

  ### String Functions
  - `len(string)` - Returns the length of a string
  - `upper(string)` - Converts string to uppercase
  - `lower(string)` - Converts string to lowercase
  - `trim(string)` - Removes leading and trailing whitespace

  ### Numeric Functions
  - `abs(number)` - Returns the absolute value of a number
  - `max(a, b)` - Returns the larger of two numbers
  - `min(a, b)` - Returns the smaller of two numbers

  ### Date Functions
  - `year(date)` - Extracts the year from a date or datetime
  - `month(date)` - Extracts the month from a date or datetime
  - `day(date)` - Extracts the day from a date or datetime

  ## Examples

      iex> Predicator.BuiltInFunctions.call("len", ["hello"])
      {:ok, 5}

      iex> Predicator.BuiltInFunctions.call("upper", ["world"])
      {:ok, "WORLD"}

      iex> Predicator.BuiltInFunctions.call("max", [10, 5])
      {:ok, 10}

      iex> Predicator.BuiltInFunctions.call("unknown", [])
      {:error, "Unknown function: unknown"}
  """

  alias Predicator.Types

  @type function_result :: {:ok, Types.value()} | {:error, binary()}

  @doc """
  Calls a built-in function with the given arguments.

  ## Parameters

  - `function_name` - The name of the function to call
  - `arguments` - List of argument values

  ## Returns

  - `{:ok, result}` - Function executed successfully with result
  - `{:error, message}` - Function call error with description

  ## Examples

      iex> Predicator.BuiltInFunctions.call("len", ["test"])
      {:ok, 4}

      iex> Predicator.BuiltInFunctions.call("max", [3, 7])
      {:ok, 7}

      iex> Predicator.BuiltInFunctions.call("invalid", [])
      {:error, "Unknown function: invalid"}
  """
  @spec call(binary(), [Types.value()]) :: function_result()
  def call(function_name, arguments) when is_binary(function_name) and is_list(arguments) do
    case function_name do
      # String functions
      "len" -> call_len(arguments)
      "upper" -> call_upper(arguments)
      "lower" -> call_lower(arguments)
      "trim" -> call_trim(arguments)
      # Numeric functions
      "abs" -> call_abs(arguments)
      "max" -> call_max(arguments)
      "min" -> call_min(arguments)
      # Date functions
      "year" -> call_year(arguments)
      "month" -> call_month(arguments)
      "day" -> call_day(arguments)
      # Unknown function
      _ -> {:error, "Unknown function: #{function_name}"}
    end
  end

  # String function implementations

  @spec call_len([Types.value()]) :: function_result()
  defp call_len([value]) when is_binary(value) do
    {:ok, String.length(value)}
  end

  defp call_len([_value]) do
    {:error, "len() expects a string argument"}
  end

  defp call_len(_args) do
    {:error, "len() expects exactly 1 argument"}
  end

  @spec call_upper([Types.value()]) :: function_result()
  defp call_upper([value]) when is_binary(value) do
    {:ok, String.upcase(value)}
  end

  defp call_upper([_value]) do
    {:error, "upper() expects a string argument"}
  end

  defp call_upper(_args) do
    {:error, "upper() expects exactly 1 argument"}
  end

  @spec call_lower([Types.value()]) :: function_result()
  defp call_lower([value]) when is_binary(value) do
    {:ok, String.downcase(value)}
  end

  defp call_lower([_value]) do
    {:error, "lower() expects a string argument"}
  end

  defp call_lower(_args) do
    {:error, "lower() expects exactly 1 argument"}
  end

  @spec call_trim([Types.value()]) :: function_result()
  defp call_trim([value]) when is_binary(value) do
    {:ok, String.trim(value)}
  end

  defp call_trim([_value]) do
    {:error, "trim() expects a string argument"}
  end

  defp call_trim(_args) do
    {:error, "trim() expects exactly 1 argument"}
  end

  # Numeric function implementations

  @spec call_abs([Types.value()]) :: function_result()
  defp call_abs([value]) when is_integer(value) do
    {:ok, abs(value)}
  end

  defp call_abs([_value]) do
    {:error, "abs() expects a numeric argument"}
  end

  defp call_abs(_args) do
    {:error, "abs() expects exactly 1 argument"}
  end

  @spec call_max([Types.value()]) :: function_result()
  defp call_max([a, b]) when is_integer(a) and is_integer(b) do
    {:ok, max(a, b)}
  end

  defp call_max([_a, _b]) do
    {:error, "max() expects two numeric arguments"}
  end

  defp call_max(_args) do
    {:error, "max() expects exactly 2 arguments"}
  end

  @spec call_min([Types.value()]) :: function_result()
  defp call_min([a, b]) when is_integer(a) and is_integer(b) do
    {:ok, min(a, b)}
  end

  defp call_min([_a, _b]) do
    {:error, "min() expects two numeric arguments"}
  end

  defp call_min(_args) do
    {:error, "min() expects exactly 2 arguments"}
  end

  # Date function implementations

  @spec call_year([Types.value()]) :: function_result()
  defp call_year([%Date{year: year}]) do
    {:ok, year}
  end

  defp call_year([%DateTime{year: year}]) do
    {:ok, year}
  end

  defp call_year([_value]) do
    {:error, "year() expects a date or datetime argument"}
  end

  defp call_year(_args) do
    {:error, "year() expects exactly 1 argument"}
  end

  @spec call_month([Types.value()]) :: function_result()
  defp call_month([%Date{month: month}]) do
    {:ok, month}
  end

  defp call_month([%DateTime{month: month}]) do
    {:ok, month}
  end

  defp call_month([_value]) do
    {:error, "month() expects a date or datetime argument"}
  end

  defp call_month(_args) do
    {:error, "month() expects exactly 1 argument"}
  end

  @spec call_day([Types.value()]) :: function_result()
  defp call_day([%Date{day: day}]) do
    {:ok, day}
  end

  defp call_day([%DateTime{day: day}]) do
    {:ok, day}
  end

  defp call_day([_value]) do
    {:error, "day() expects a date or datetime argument"}
  end

  defp call_day(_args) do
    {:error, "day() expects exactly 1 argument"}
  end
end
