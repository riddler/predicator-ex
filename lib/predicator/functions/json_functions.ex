defmodule Predicator.Functions.JSONFunctions do
  @moduledoc """
  JSON manipulation functions for Predicator expressions.

  Provides SCXML-compatible JSON functions for serializing and parsing data.

  ## Available Functions

  - `JSON.stringify(value)` - Converts a value to a JSON string
  - `JSON.parse(string)` - Parses a JSON string into a value

  ## Examples

      iex> {:ok, result} = Predicator.evaluate("JSON.stringify(user)",
      ...>   %{"user" => %{"name" => "John", "age" => 30}},
      ...>   functions: Predicator.Functions.JSONFunctions.all_functions())
      iex> result
      ~s({"age":30,"name":"John"})

      iex> {:ok, result} = Predicator.evaluate("JSON.parse(data)",
      ...>   %{"data" => ~s({"status":"ok"})},
      ...>   functions: Predicator.Functions.JSONFunctions.all_functions())
      iex> result
      %{"status" => "ok"}
  """

  @spec all_functions() :: %{binary() => {non_neg_integer(), function()}}
  def all_functions do
    %{
      "JSON.stringify" => {1, &call_stringify/2},
      "JSON.parse" => {1, &call_parse/2}
    }
  end

  defp call_stringify([value], _context) do
    case Jason.encode(value) do
      {:ok, json} ->
        {:ok, json}

      {:error, _encode_error} ->
        # For values that can't be JSON encoded, convert to string
        {:ok, inspect(value)}
    end
  rescue
    error -> {:error, "JSON.stringify failed: #{Exception.message(error)}"}
  end

  defp call_parse([json_string], _context) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, value} ->
        {:ok, value}

      {:error, error} ->
        {:error, "Invalid JSON: #{Exception.message(error)}"}
    end
  rescue
    error -> {:error, "JSON.parse failed: #{Exception.message(error)}"}
  end

  defp call_parse([_value], _context) do
    {:error, "JSON.parse expects a string argument"}
  end
end
