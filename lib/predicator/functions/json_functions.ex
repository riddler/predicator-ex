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
      ...>   providers: [Predicator.Functions.JSONFunctions])
      iex> result
      ~s({"age":30,"name":"John"})

      iex> {:ok, result} = Predicator.evaluate("JSON.parse(data)",
      ...>   %{"data" => ~s({"status":"ok"})},
      ...>   providers: [Predicator.Functions.JSONFunctions])
      iex> result
      %{"status" => "ok"}
  """

  @behaviour Predicator.FunctionProvider

  alias Predicator.{Context, Types}

  @type function_result :: {:ok, Types.value()} | {:error, binary()}

  @doc """
  Returns all JSON functions as a `Predicator.FunctionProvider` map.
  """
  @impl Predicator.FunctionProvider
  @spec functions() :: %{
          Predicator.FunctionProvider.name() => Predicator.FunctionProvider.entry()
        }
  def functions do
    %{
      "JSON.stringify" => {1, :call_stringify},
      "JSON.parse" => {1, :call_parse}
    }
  end

  # JSON.encode!/1 raises for anything it cannot represent - tuples, PIDs,
  # refs, funs, non-string map keys, invalid UTF-8. All of those fall back to
  # inspect/1, which is what a predicate has always seen for such values.
  @doc "Converts a value to a JSON string."
  @spec call_stringify([Types.value()], Context.t()) :: function_result()
  def call_stringify([value], _context) do
    {:ok, JSON.encode!(value)}
  rescue
    _error -> {:ok, inspect(value)}
  end

  @doc "Parses a JSON string into a value."
  @spec call_parse([Types.value()], Context.t()) :: function_result()
  def call_parse([json_string], _context) when is_binary(json_string) do
    case JSON.decode(json_string) do
      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        {:error, "Invalid JSON: #{describe_decode_error(reason)}"}
    end
  end

  def call_parse([_value], _context) do
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
