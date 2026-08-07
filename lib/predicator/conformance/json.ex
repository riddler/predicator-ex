defmodule Predicator.Conformance.JSON do
  @moduledoc """
  A deterministic JSON writer for the conformance corpus (`px-35i.4`).

  The built-in `JSON.encode!/1` does not guarantee map key order, which makes
  its output unusable for a byte-compared, checked-in corpus: two semantically
  identical maps built by inserting keys in a different order could encode
  differently, turning the staleness test red for no reason. `encode_canonical/1`
  fixes that by walking the term itself, sorting object keys by codepoint, and
  emitting no incidental whitespace - `JSON.encode!/1` is still used underneath
  for scalar and string escaping, so the escaping rules stay the standard
  library's.

  `encode_lines/1` is the shipped corpus format: a list of objects, one per
  line, so that changing a single case is a one-line diff instead of a
  whole-file rewrite.
  """

  @typedoc "A term encodable as JSON: what `JSON.decode/1` can produce, plus atom map keys."
  @type json_value ::
          nil
          | boolean()
          | number()
          | binary()
          | [json_value()]
          | %{optional(binary() | atom()) => json_value()}

  @doc """
  Encodes `term` as canonical JSON: object keys sorted by codepoint, no
  incidental whitespace.

  ## Examples

      iex> Predicator.Conformance.JSON.encode_canonical(%{"b" => 1, "a" => 2})
      ~s({"a":2,"b":1})

      iex> Predicator.Conformance.JSON.encode_canonical([1, "two", true, nil])
      ~s([1,"two",true,null])
  """
  @spec encode_canonical(json_value()) :: binary()
  def encode_canonical(term) do
    term |> encode_term() |> IO.iodata_to_binary()
  end

  @doc """
  Encodes a list of terms as the shipped corpus format: one canonical-JSON
  object per line, each terminated by `\\n`.

  ## Examples

      iex> Predicator.Conformance.JSON.encode_lines([%{"id" => 1}, %{"id" => 2}])
      ~s({"id":1}\\n{"id":2}\\n)
  """
  @spec encode_lines([json_value()]) :: binary()
  def encode_lines(items) when is_list(items) do
    items
    |> Enum.map(fn item -> [encode_term(item), ?\n] end)
    |> IO.iodata_to_binary()
  end

  @spec encode_term(json_value()) :: iodata()
  defp encode_term(map) when is_map(map) do
    encoded_members =
      map
      |> Enum.map(fn {key, value} -> {to_string(key), value} end)
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map(fn {key, value} -> [JSON.encode!(key), ?:, encode_term(value)] end)
      |> Enum.intersperse(?,)

    [?{, encoded_members, ?}]
  end

  defp encode_term(list) when is_list(list) do
    encoded_items = list |> Enum.map(&encode_term/1) |> Enum.intersperse(?,)
    [?[, encoded_items, ?]]
  end

  defp encode_term(scalar), do: JSON.encode!(scalar)
end
