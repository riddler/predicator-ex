defmodule Predicator.Cast do
  @moduledoc """
  The `::` cast conversion matrix.

  Implements every legal source-to-target conversion for the seven scalar
  ISA type names. The normative matrix is
  [`docs/isa.md`](../../docs/isa.md) section 5, under `cast`; ADR-0011
  records why casting is an opcode rather than a lowering to `call`.

  `cast/2` is total over values and never raises or returns an error tuple:
  `:undefined` propagates, and a conversion that cannot produce a value of the
  target type also yields `:undefined`. This module is not part of the
  predicate surface - the only way an author reaches it is through `::` - it
  is public for the same reason `Predicator.Duration` is: a value-layer
  helper worth documenting and testing on its own.
  """

  alias Predicator.Duration

  @type_names ~w(integer float string boolean date datetime duration)

  @integer_string_regex ~r/\A-?[0-9]+\z/
  @float_string_regex ~r/\A-?[0-9]+(\.[0-9]+)?\z/

  @doc "The seven scalar ISA type names casts accept (docs/isa.md section 3)."
  @spec type_names() :: [binary()]
  def type_names, do: @type_names

  @doc """
  Converts `value` to the named type, or `:undefined` when it cannot.

  `type_name` must be one of `type_names/0`; passing anything else is a
  `FunctionClauseError` at this module's boundary, since the caller (the
  evaluator, guarded on the same list) never passes one.
  """
  @spec cast(term(), binary()) :: term()
  def cast(value, type_name)

  # Rule 1: :undefined propagates to every target.
  def cast(:undefined, type_name) when type_name in @type_names, do: :undefined

  # Identity clauses, matched on shape.
  def cast(value, "integer") when is_integer(value), do: value
  def cast(value, "float") when is_float(value), do: value
  def cast(value, "string") when is_binary(value), do: value
  def cast(value, "boolean") when is_boolean(value), do: value
  def cast(%Date{} = value, "date"), do: value
  def cast(%DateTime{} = value, "datetime"), do: value

  def cast(
        %{
          years: _years,
          months: _months,
          weeks: _weeks,
          days: _days,
          hours: _hours,
          minutes: _minutes,
          seconds: _seconds
        } = value,
        "duration"
      ) do
    value
  end

  # Numeric conversions.
  def cast(value, "float") when is_integer(value), do: value * 1.0
  def cast(value, "integer") when is_float(value), do: trunc(value)

  # Numeric formats.
  def cast(value, "string") when is_integer(value), do: Integer.to_string(value)
  def cast(value, "string") when is_float(value), do: Float.to_string(value)

  # String parses.
  def cast(value, "integer") when is_binary(value) do
    if Regex.match?(@integer_string_regex, value) do
      String.to_integer(value)
    else
      :undefined
    end
  end

  def cast(value, "float") when is_binary(value) do
    if Regex.match?(@float_string_regex, value) do
      String.to_float(ensure_decimal_point(value))
    else
      :undefined
    end
  end

  def cast(value, "boolean") when is_binary(value) do
    case value do
      "true" -> true
      "false" -> false
      _other -> :undefined
    end
  end

  def cast(value, "date") when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> :undefined
    end
  end

  def cast(value, "datetime") when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> normalize_to_utc(datetime)
      {:error, _reason} -> :undefined
    end
  end

  def cast(value, "duration") when is_binary(value) do
    case Duration.parse(value) do
      {:ok, duration} -> duration
      :error -> :undefined
    end
  end

  # Boolean format.
  def cast(true, "string"), do: "true"
  def cast(false, "string"), do: "false"

  # Date/datetime formats and bridge.
  def cast(%Date{} = value, "string"), do: Date.to_iso8601(value)

  def cast(%Date{} = value, "datetime") do
    {:ok, datetime} = DateTime.new(value, ~T[00:00:00], "Etc/UTC")
    datetime
  end

  def cast(%DateTime{} = value, "string") do
    value
    |> normalize_to_utc()
    |> canonicalize_microsecond()
    |> DateTime.to_iso8601()
  end

  def cast(%DateTime{} = value, "date"), do: DateTime.to_date(value)

  # Duration format.
  def cast(
        %{
          years: _years,
          months: _months,
          weeks: _weeks,
          days: _days,
          hours: _hours,
          minutes: _minutes,
          seconds: _seconds
        } = value,
        "string"
      ) do
    Duration.to_string(value)
  end

  # Rule 2: total over values. Every unlisted source/target pair - lists,
  # maps, the boolean/number non-bridge, and anything else - lands here.
  def cast(_value, type_name) when type_name in @type_names, do: :undefined

  @spec ensure_decimal_point(binary()) :: binary()
  defp ensure_decimal_point(value) do
    if String.contains?(value, "."), do: value, else: value <> ".0"
  end

  @spec normalize_to_utc(DateTime.t()) :: DateTime.t()
  defp normalize_to_utc(datetime) do
    DateTime.from_unix!(DateTime.to_unix(datetime, :microsecond), :microsecond)
  end

  # docs/isa.md section 5: datetime::string omits the fractional-seconds field
  # entirely when the sub-second component is zero and emits exactly six digits
  # when it is not. normalize_to_utc/1 forces precision 6 to stay
  # tz-database-free, so this is where that internal artifact stops.
  @spec canonicalize_microsecond(DateTime.t()) :: DateTime.t()
  defp canonicalize_microsecond(%DateTime{microsecond: {0, _precision}} = datetime),
    do: %{datetime | microsecond: {0, 0}}

  defp canonicalize_microsecond(%DateTime{microsecond: {microseconds, _precision}} = datetime),
    do: %{datetime | microsecond: {microseconds, 6}}
end
