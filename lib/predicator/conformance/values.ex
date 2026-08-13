defmodule Predicator.Conformance.Values do
  @moduledoc """
  The tagged-value codec for the conformance corpus (`px-35i.4`).

  Plain JSON scalars, arrays, and objects mean themselves - including a bare
  JSON `null`, which decodes to predicator's null value with no tag of its own
  (px-o9v). `docs/isa.md` section 3's value domain also includes `Date`,
  `DateTime`, duration, and `:undefined`, none of which JSON can represent
  directly, so each of those is carried as an object with a `$type` key:

      {"$type": "date", "value": "2026-08-06"}
      {"$type": "datetime", "value": "2026-08-06T12:00:00Z"}
      {"$type": "datetime", "value": "2026-08-06T12:00:00.500000Z"}
      {"$type": "duration", "value": {"years":0,"months":0,"weeks":0,"days":3,"hours":0,"minutes":0,"seconds":0}}
      {"$type": "undefined"}

  A `duration` tag's `value` carries the normative seven-key map from
  `docs/isa.md:100-106` - `years`, `months`, `weeks`, `days`, `hours`,
  `minutes`, `seconds`, always present, plus `milliseconds` only when it is
  non-zero (predicator's own duration values default `milliseconds` to `0`
  the same way the other six units do, so an absent key and a zero key decode
  identically).

  An object with a literal `"$type"` key that is *not* one of predicator's own
  values (i.e. supplied inside an authored case's plain map) would be
  ambiguous with the tag namespace, so `to_json/1` rejects it rather than
  silently emitting a tag.
  """

  @typedoc "A JSON-shaped term: what `Predicator.Conformance.JSON` writes and `JSON.decode/1` reads."
  @type json ::
          nil
          | boolean()
          | number()
          | binary()
          | [json()]
          | %{optional(binary()) => json()}

  @duration_keys ~w(years months weeks days hours minutes seconds)a

  @doc """
  Encodes a predicator value (`Predicator.Types.value/0`, plus plain maps
  and lists of the same) into the tagged JSON encoding.

  Returns `{:error, {:unencodable, term}}` for anything outside the ISA
  value domain, and for a plain map that contains a literal `"$type"` key.

  ## Examples

      iex> Predicator.Conformance.Values.to_json(:undefined)
      {:ok, %{"$type" => "undefined"}}

      iex> Predicator.Conformance.Values.to_json(~D[2026-08-06])
      {:ok, %{"$type" => "date", "value" => "2026-08-06"}}

      iex> Predicator.Conformance.Values.to_json(~U[2026-08-06T12:00:00Z])
      {:ok, %{"$type" => "datetime", "value" => "2026-08-06T12:00:00Z"}}

      iex> Predicator.Conformance.Values.to_json(~U[2026-08-06T12:00:00.5Z])
      {:ok, %{"$type" => "datetime", "value" => "2026-08-06T12:00:00.500000Z"}}

      iex> Predicator.Conformance.Values.to_json(42)
      {:ok, 42}

      iex> Predicator.Conformance.Values.to_json(%{"$type" => "oops"})
      {:error, {:unencodable, %{"$type" => "oops"}}}

      iex> Predicator.Conformance.Values.to_json({:not, :a, :json, :value})
      {:error, {:unencodable, {:not, :a, :json, :value}}}
  """
  @spec to_json(term()) :: {:ok, json()} | {:error, {:unencodable, term()}}
  def to_json(:undefined), do: {:ok, %{"$type" => "undefined"}}

  # Null is JSON-native: it encodes as a bare JSON null, with no $type tag.
  # `:undefined` above needs a tag because JSON has no absence; null does not
  # (px-o9v).
  def to_json(nil), do: {:ok, nil}

  def to_json(%Date{} = date) do
    {:ok, %{"$type" => "date", "value" => Date.to_iso8601(date)}}
  end

  def to_json(%DateTime{} = datetime) do
    value = datetime |> canonicalize_microsecond() |> DateTime.to_iso8601()
    {:ok, %{"$type" => "datetime", "value" => value}}
  end

  def to_json(value) when is_map(value) and not is_struct(value) do
    if duration_map?(value) do
      {:ok, %{"$type" => "duration", "value" => encode_duration(value)}}
    else
      encode_plain_map(value)
    end
  end

  def to_json(value) when is_list(value), do: encode_list(value)

  def to_json(value) when is_binary(value) or is_number(value) or is_boolean(value) do
    {:ok, value}
  end

  def to_json(value), do: {:error, {:unencodable, value}}

  @doc """
  Decodes a tagged-JSON term back into a predicator value.

  The inverse of `to_json/1` up to canonicalization: `to_json(from_json(to_json(v)))
  == to_json(v)` for every value `to_json/1` accepts, and `from_json(to_json(v))
  == {:ok, v}` for every value except a `DateTime` whose precision field
  disagrees with its own sub-second component, which comes back canonicalized.
  Returns `{:error, {:unknown_type, type}}` for an object whose `$type` is not
  one of `"date"`, `"datetime"`, `"duration"`, or `"undefined"`.

  ## Examples

      iex> Predicator.Conformance.Values.from_json(%{"$type" => "undefined"})
      {:ok, :undefined}

      iex> Predicator.Conformance.Values.from_json(%{"$type" => "date", "value" => "2026-08-06"})
      {:ok, ~D[2026-08-06]}

      iex> Predicator.Conformance.Values.from_json(42)
      {:ok, 42}

      iex> Predicator.Conformance.Values.from_json(%{"$type" => "nope"})
      {:error, {:unknown_type, "nope"}}
  """
  @spec from_json(json()) :: {:ok, term()} | {:error, term()}
  def from_json(%{"$type" => "undefined"}), do: {:ok, :undefined}

  def from_json(nil), do: {:ok, nil}

  def from_json(%{"$type" => "date", "value" => value}) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, reason} -> {:error, {:invalid_date, reason}}
    end
  end

  def from_json(%{"$type" => "datetime", "value" => value}) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _utc_offset} -> {:ok, canonicalize_microsecond(datetime)}
      {:error, reason} -> {:error, {:invalid_datetime, reason}}
    end
  end

  def from_json(%{"$type" => "duration", "value" => value}) when is_map(value) do
    decode_duration(value)
  end

  def from_json(%{"$type" => type}), do: {:error, {:unknown_type, type}}

  def from_json(value) when is_map(value), do: decode_plain_map(value)

  def from_json(value) when is_list(value), do: decode_list(value)

  def from_json(value) when is_binary(value) or is_number(value) or is_boolean(value) do
    {:ok, value}
  end

  def from_json(value), do: {:error, {:undecodable, value}}

  # The tagged datetime encoding carries the same canonical fractional-seconds
  # form as datetime::string (docs/isa.md section 5, px-7t8): the fraction
  # omitted entirely when the sub-second component is zero, exactly six digits
  # when it is not. Elixir's precision field has no representation in the
  # encoding, so canonicalizing on both directions is what makes the encoding a
  # function of the instant rather than of whichever code path produced the
  # struct. Deliberately duplicated from Cast's private clause rather than
  # shared - see docs/research/260811-px-qq6-tagged-datetime-precision.md.
  @spec canonicalize_microsecond(DateTime.t()) :: DateTime.t()
  defp canonicalize_microsecond(%DateTime{microsecond: {0, _precision}} = datetime),
    do: %{datetime | microsecond: {0, 0}}

  defp canonicalize_microsecond(%DateTime{microsecond: {microseconds, _precision}} = datetime),
    do: %{datetime | microsecond: {microseconds, 6}}

  @spec duration_map?(map()) :: boolean()
  defp duration_map?(value), do: Enum.all?(@duration_keys, &Map.has_key?(value, &1))

  @spec encode_duration(map()) :: %{optional(binary()) => integer()}
  defp encode_duration(duration) do
    base = Map.new(@duration_keys, &{Atom.to_string(&1), Map.fetch!(duration, &1)})

    case Map.get(duration, :milliseconds, 0) do
      0 -> base
      milliseconds -> Map.put(base, "milliseconds", milliseconds)
    end
  end

  @spec decode_duration(map()) :: {:ok, map()} | {:error, {:invalid_duration, term()}}
  defp decode_duration(value) do
    case decode_duration_units(value) do
      {:ok, units} -> {:ok, Map.put(units, :milliseconds, Map.get(value, "milliseconds", 0))}
      :error -> {:error, {:invalid_duration, value}}
    end
  end

  @spec decode_duration_units(map()) :: {:ok, map()} | :error
  defp decode_duration_units(value) do
    Enum.reduce_while(@duration_keys, {:ok, %{}}, fn key, {:ok, acc} ->
      case Map.fetch(value, Atom.to_string(key)) do
        {:ok, unit_value} -> {:cont, {:ok, Map.put(acc, key, unit_value)}}
        :error -> {:halt, :error}
      end
    end)
  end

  @spec encode_plain_map(map()) :: {:ok, %{optional(binary()) => json()}} | {:error, term()}
  defp encode_plain_map(map) do
    if Map.has_key?(map, "$type") do
      {:error, {:unencodable, map}}
    else
      encode_map_members(map)
    end
  end

  @spec encode_map_members(map()) :: {:ok, %{optional(binary()) => json()}} | {:error, term()}
  defp encode_map_members(map) do
    Enum.reduce_while(map, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case to_json(value) do
        {:ok, encoded} -> {:cont, {:ok, Map.put(acc, to_string(key), encoded)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @spec decode_plain_map(map()) :: {:ok, map()} | {:error, term()}
  defp decode_plain_map(map) do
    Enum.reduce_while(map, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case from_json(value) do
        {:ok, decoded} -> {:cont, {:ok, Map.put(acc, key, decoded)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @spec encode_list(list()) :: {:ok, [json()]} | {:error, term()}
  defp encode_list(list) do
    with {:ok, reversed} <-
           Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
             case to_json(item) do
               {:ok, encoded} -> {:cont, {:ok, [encoded | acc]}}
               {:error, _reason} = error -> {:halt, error}
             end
           end) do
      {:ok, Enum.reverse(reversed)}
    end
  end

  @spec decode_list(list()) :: {:ok, list()} | {:error, term()}
  defp decode_list(list) do
    with {:ok, reversed} <-
           Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
             case from_json(item) do
               {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
               {:error, _reason} = error -> {:halt, error}
             end
           end) do
      {:ok, Enum.reverse(reversed)}
    end
  end
end
