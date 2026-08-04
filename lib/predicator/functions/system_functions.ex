defmodule Predicator.Functions.SystemFunctions do
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
  - `starts_with(string, prefix)` - Tests whether a string starts with a prefix
  - `ends_with(string, suffix)` - Tests whether a string ends with a suffix
  - `substring(string, start[, len])` - Extracts a substring from a start index
  - `index_of(string, sub)` - Finds the index of a substring, or -1

  ## Examples

      iex> Predicator.evaluate("len('hello')", %{})
      {:ok, 5}

      iex> Predicator.evaluate("upper('world')", %{})
      {:ok, "WORLD"}

      iex> Predicator.evaluate("starts_with('hello world', 'hello')", %{})
      {:ok, true}

      iex> Predicator.evaluate("ends_with('hello world', 'world')", %{})
      {:ok, true}

      iex> Predicator.evaluate("substring('hello world', 6)", %{})
      {:ok, "world"}

      iex> Predicator.evaluate("substring('hello world', 0, 5)", %{})
      {:ok, "hello"}

      iex> Predicator.evaluate("index_of('hello world', 'world')", %{})
      {:ok, 6}

      iex> Predicator.evaluate("index_of('hello world', 'nope')", %{})
      {:ok, -1}
  """

  alias Predicator.{Evaluator, Types}

  @type function_result :: {:ok, Types.value()} | {:error, binary()}

  @doc """
  Returns all system functions as a map in the format expected by the evaluator.

  ## Returns

  A map where keys are function names and values are `{arity, function}` tuples.

  ## Examples

      iex> functions = Predicator.Functions.SystemFunctions.all_functions()
      iex> Map.has_key?(functions, "len")
      true
      iex> {arity, _function} = functions["len"]
      iex> arity
      1
  """
  @spec all_functions() :: %{binary() => {Evaluator.function_arity(), function()}}
  def all_functions do
    %{
      # String functions
      "len" => {1, &call_len/2},
      "upper" => {1, &call_upper/2},
      "lower" => {1, &call_lower/2},
      "trim" => {1, &call_trim/2},
      "starts_with" => {2, &call_starts_with/2},
      "ends_with" => {2, &call_ends_with/2},
      "substring" => {[2, 3], &call_substring/2},
      "index_of" => {2, &call_index_of/2}
    }
  end

  # String function implementations

  @spec call_len([Types.value()], Types.context()) :: function_result()
  defp call_len([value], _context) when is_binary(value) do
    {:ok, String.length(value)}
  end

  defp call_len([_value], _context) do
    {:error, "len() expects a string argument"}
  end

  defp call_len(_args, _context) do
    {:error, "len() expects exactly 1 argument"}
  end

  @spec call_upper([Types.value()], Types.context()) :: function_result()
  defp call_upper([value], _context) when is_binary(value) do
    {:ok, String.upcase(value)}
  end

  defp call_upper([_value], _context) do
    {:error, "upper() expects a string argument"}
  end

  defp call_upper(_args, _context) do
    {:error, "upper() expects exactly 1 argument"}
  end

  @spec call_lower([Types.value()], Types.context()) :: function_result()
  defp call_lower([value], _context) when is_binary(value) do
    {:ok, String.downcase(value)}
  end

  defp call_lower([_value], _context) do
    {:error, "lower() expects a string argument"}
  end

  defp call_lower(_args, _context) do
    {:error, "lower() expects exactly 1 argument"}
  end

  @spec call_trim([Types.value()], Types.context()) :: function_result()
  defp call_trim([value], _context) when is_binary(value) do
    {:ok, String.trim(value)}
  end

  defp call_trim([_value], _context) do
    {:error, "trim() expects a string argument"}
  end

  defp call_trim(_args, _context) do
    {:error, "trim() expects exactly 1 argument"}
  end

  @spec call_starts_with([Types.value()], Types.context()) :: function_result()
  defp call_starts_with([value, prefix], _context)
       when is_binary(value) and is_binary(prefix) do
    {:ok, String.starts_with?(value, prefix)}
  end

  defp call_starts_with([_value, _prefix], _context) do
    {:error, "starts_with() expects two string arguments"}
  end

  defp call_starts_with(_args, _context) do
    {:error, "starts_with() expects exactly 2 arguments"}
  end

  @spec call_ends_with([Types.value()], Types.context()) :: function_result()
  defp call_ends_with([value, suffix], _context)
       when is_binary(value) and is_binary(suffix) do
    {:ok, String.ends_with?(value, suffix)}
  end

  defp call_ends_with([_value, _suffix], _context) do
    {:error, "ends_with() expects two string arguments"}
  end

  defp call_ends_with(_args, _context) do
    {:error, "ends_with() expects exactly 2 arguments"}
  end

  @spec call_substring([Types.value()], Types.context()) :: function_result()
  defp call_substring([value, start], _context)
       when is_binary(value) and is_integer(start) and start >= 0 do
    {:ok, String.slice(value, start, String.length(value))}
  end

  defp call_substring([value, start, len], _context)
       when is_binary(value) and is_integer(start) and start >= 0 and is_integer(len) and
              len >= 0 do
    {:ok, String.slice(value, start, len)}
  end

  defp call_substring([value, start], _context) when is_binary(value) and is_integer(start) do
    {:error, "substring() expects a non-negative start index"}
  end

  defp call_substring([value, start, len], _context)
       when is_binary(value) and is_integer(start) and is_integer(len) do
    {:error, "substring() expects a non-negative start index and length"}
  end

  defp call_substring([_value, _start], _context) do
    {:error, "substring() expects a string and an integer start index"}
  end

  defp call_substring([_value, _start, _len], _context) do
    {:error, "substring() expects a string, an integer start index, and an integer length"}
  end

  defp call_substring(_args, _context) do
    {:error, "substring() expects 2 or 3 arguments"}
  end

  @spec call_index_of([Types.value()], Types.context()) :: function_result()
  defp call_index_of([value, ""], _context) when is_binary(value) do
    {:ok, 0}
  end

  defp call_index_of([value, sub], _context) when is_binary(value) and is_binary(sub) do
    case :binary.match(value, sub) do
      {index, _length} -> {:ok, index}
      :nomatch -> {:ok, -1}
    end
  end

  defp call_index_of([_value, _sub], _context) do
    {:error, "index_of() expects two string arguments"}
  end

  defp call_index_of(_args, _context) do
    {:error, "index_of() expects exactly 2 arguments"}
  end
end
