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

  ## Examples

      iex> Predicator.Functions.SystemFunctions.call("len", ["hello"])
      {:ok, 5}

      iex> Predicator.Functions.SystemFunctions.call("upper", ["world"])
      {:ok, "WORLD"}

      iex> Predicator.Functions.SystemFunctions.call("unknown", [])
      {:error, "Unknown function: unknown"}
  """

  alias Predicator.Types

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
  @spec all_functions() :: %{binary() => {non_neg_integer(), function()}}
  def all_functions do
    %{
      # String functions
      "len" => {1, &call_len/2},
      "upper" => {1, &call_upper/2},
      "lower" => {1, &call_lower/2},
      "trim" => {1, &call_trim/2}
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
end
