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

  # JSON.encode!/1 raises for anything it cannot represent - tuples, PIDs,
  # refs, funs, non-string map keys, invalid UTF-8. All of those fall back to
  # inspect/1, which is what a predicate has always seen for such values.
  defp call_stringify([value], _context) do
    {:ok, JSON.encode!(value)}
  rescue
    _error -> {:ok, inspect(value)}
  end

  defp call_parse([json_string], _context) when is_binary(json_string) do
    case JSON.decode(json_string) do
      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        {:error, "Invalid JSON: #{describe_decode_error(reason)}"}
    end
  end

  defp call_parse([_value], _context) do
    {:error, "JSON.parse expects a string argument"}
  end

  # JSON.decode/1 reports failures as bare tuples rather than exception
  # structs, so there is no Exception.message/1 to lean on. The inspect/1
  # fallback keeps an unrecognized future shape readable instead of raising.
  defp describe_decode_error({:invalid_byte, position, byte}) do
    "unexpected byte 0x#{Base.encode16(<<byte>>)} at position #{position}"
  end

  defp describe_decode_error({:unexpected_end, position}) do
    "unexpected end of input at position #{position}"
  end

  defp describe_decode_error(reason) do
    inspect(reason)
  end
end
