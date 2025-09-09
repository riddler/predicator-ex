defmodule Predicator.Duration do
  @moduledoc """
  Duration utilities for time span calculations in Predicator expressions.

  This module provides functions to create, manipulate, and convert duration
  values for use in relative date expressions and date arithmetic.

  ## Examples

      iex> Predicator.Duration.new(days: 3, hours: 8)
      %{years: 0, months: 0, weeks: 0, days: 3, hours: 8, minutes: 0, seconds: 0, milliseconds: 0}

      iex> Predicator.Duration.from_units([{"3", "d"}, {"8", "h"}])
      {:ok, %{years: 0, months: 0, weeks: 0, days: 3, hours: 8, minutes: 0, seconds: 0, milliseconds: 0}}

      iex> Predicator.Duration.to_seconds(%{days: 1, hours: 2, minutes: 30})
      95400
  """

  alias Predicator.Types

  @doc """
  Creates a new duration with specified time units.

  All unspecified units default to 0.

  ## Examples

      iex> Predicator.Duration.new(days: 2, hours: 3)
      %{years: 0, months: 0, weeks: 0, days: 2, hours: 3, minutes: 0, seconds: 0, milliseconds: 0}

      iex> Predicator.Duration.new()
      %{years: 0, months: 0, weeks: 0, days: 0, hours: 0, minutes: 0, seconds: 0, milliseconds: 0}
  """
  @spec new(keyword()) :: Types.duration()
  def new(opts \\ []) do
    %{
      years: Keyword.get(opts, :years, 0),
      months: Keyword.get(opts, :months, 0),
      weeks: Keyword.get(opts, :weeks, 0),
      days: Keyword.get(opts, :days, 0),
      hours: Keyword.get(opts, :hours, 0),
      minutes: Keyword.get(opts, :minutes, 0),
      seconds: Keyword.get(opts, :seconds, 0),
      milliseconds: Keyword.get(opts, :milliseconds, 0)
    }
  end

  @doc """
  Creates a duration from parsed unit pairs.

  Takes a list of {value, unit} tuples and converts them to a duration.

  ## Examples

      iex> Predicator.Duration.from_units([{"3", "d"}, {"8", "h"}])
      {:ok, %{years: 0, months: 0, weeks: 0, days: 3, hours: 8, minutes: 0, seconds: 0, milliseconds: 0}}

      iex> Predicator.Duration.from_units([{"invalid", "d"}])
      {:error, "Invalid duration value: invalid"}
  """
  @spec from_units([{binary(), binary()}]) :: {:ok, Types.duration()} | {:error, binary()}
  def from_units(unit_pairs) do
    case build_duration_from_units(unit_pairs, new()) do
      {:ok, duration} -> {:ok, duration}
      {:error, message} -> {:error, message}
    end
  end

  defp build_duration_from_units([], duration), do: {:ok, duration}

  defp build_duration_from_units([{value_str, unit} | rest], acc) do
    case Integer.parse(value_str) do
      {value, ""} ->
        try do
          updated_acc = add_unit(acc, unit, value)
          build_duration_from_units(rest, updated_acc)
        catch
          {:error, message} -> {:error, message}
        end

      _parse_error ->
        {:error, "Invalid duration value: #{value_str}"}
    end
  end

  @doc """
  Adds a specific unit amount to a duration.

  ## Examples

      iex> duration = Predicator.Duration.new(days: 1)
      iex> Predicator.Duration.add_unit(duration, "h", 3)
      %{years: 0, months: 0, weeks: 0, days: 1, hours: 3, minutes: 0, seconds: 0, milliseconds: 0}
  """
  @spec add_unit(Types.duration(), binary(), non_neg_integer()) :: Types.duration()
  def add_unit(duration, "y", value), do: %{duration | years: duration.years + value}
  def add_unit(duration, "mo", value), do: %{duration | months: duration.months + value}
  def add_unit(duration, "w", value), do: %{duration | weeks: duration.weeks + value}
  def add_unit(duration, "d", value), do: %{duration | days: duration.days + value}
  def add_unit(duration, "h", value), do: %{duration | hours: duration.hours + value}
  def add_unit(duration, "m", value), do: %{duration | minutes: duration.minutes + value}
  def add_unit(duration, "s", value), do: %{duration | seconds: duration.seconds + value}

  def add_unit(duration, "ms", value),
    do: %{duration | milliseconds: duration.milliseconds + value}

  def add_unit(_duration, unit, _value) do
    throw({:error, "Unknown duration unit: #{unit}"})
  end

  @doc """
  Converts a duration to total seconds (approximate for months and years).

  Uses approximate conversions:
  - 1 month = 30 days
  - 1 year = 365 days

  ## Examples

      iex> Predicator.Duration.to_seconds(%{days: 1, hours: 2, minutes: 30, seconds: 15})
      95415

      iex> Predicator.Duration.to_seconds(%{weeks: 2})
      1209600
  """
  @spec to_seconds(Types.duration()) :: integer()
  def to_seconds(duration) do
    Map.get(duration, :seconds, 0) +
      Map.get(duration, :minutes, 0) * 60 +
      Map.get(duration, :hours, 0) * 3600 +
      Map.get(duration, :days, 0) * 86_400 +
      Map.get(duration, :weeks, 0) * 604_800 +
      Map.get(duration, :months, 0) * 2_592_000 +
      Map.get(duration, :years, 0) * 31_536_000
  end

  @doc """
  Converts a duration to total milliseconds (approximate for months and years).

  Uses approximate conversions:
  - 1 month = 30 days
  - 1 year = 365 days

  ## Examples

      iex> Predicator.Duration.to_milliseconds(%{seconds: 1, milliseconds: 500})
      1500

      iex> Predicator.Duration.to_milliseconds(%{minutes: 1, seconds: 30, milliseconds: 250})
      90250
  """
  @spec to_milliseconds(Types.duration()) :: integer()
  def to_milliseconds(duration) do
    Map.get(duration, :milliseconds, 0) +
      Map.get(duration, :seconds, 0) * 1_000 +
      Map.get(duration, :minutes, 0) * 60_000 +
      Map.get(duration, :hours, 0) * 3_600_000 +
      Map.get(duration, :days, 0) * 86_400_000 +
      Map.get(duration, :weeks, 0) * 604_800_000 +
      Map.get(duration, :months, 0) * 2_592_000_000 +
      Map.get(duration, :years, 0) * 31_536_000_000
  end

  @doc """
  Adds a duration to a Date, returning a Date.

  ## Examples

      iex> date = ~D[2024-01-15]
      iex> duration = Predicator.Duration.new(days: 3, weeks: 1)
      iex> Predicator.Duration.add_to_date(date, duration)
      ~D[2024-01-25]
  """
  @spec add_to_date(Date.t(), Types.duration()) :: Date.t()
  def add_to_date(date, duration) do
    # Convert duration to days (approximate for months/years)
    total_days =
      Map.get(duration, :days, 0) +
        Map.get(duration, :weeks, 0) * 7 +
        Map.get(duration, :months, 0) * 30 +
        Map.get(duration, :years, 0) * 365

    # Add hours/minutes/seconds as additional days if they add up to full days
    additional_seconds =
      Map.get(duration, :hours, 0) * 3600 + Map.get(duration, :minutes, 0) * 60 +
        Map.get(duration, :seconds, 0)

    additional_days = div(additional_seconds, 86_400)

    Date.add(date, total_days + additional_days)
  end

  @doc """
  Adds a duration to a DateTime, returning a DateTime.

  ## Examples

      iex> datetime = ~U[2024-01-15T10:30:00Z]
      iex> duration = Predicator.Duration.new(days: 2, hours: 3, minutes: 30)
      iex> Predicator.Duration.add_to_datetime(datetime, duration)
      ~U[2024-01-17T14:00:00Z]
  """
  @spec add_to_datetime(DateTime.t(), Types.duration()) :: DateTime.t()
  def add_to_datetime(datetime, %{milliseconds: ms} = duration) when ms > 0 do
    total_ms = to_milliseconds(duration)
    DateTime.add(datetime, total_ms, :millisecond)
  end

  def add_to_datetime(datetime, duration) do
    total_seconds = to_seconds(duration)
    DateTime.add(datetime, total_seconds, :second)
  end

  @doc """
  Subtracts a duration from a Date, returning a Date.

  ## Examples

      iex> date = ~D[2024-01-25]
      iex> duration = Predicator.Duration.new(days: 3, weeks: 1)
      iex> Predicator.Duration.subtract_from_date(date, duration)
      ~D[2024-01-15]
  """
  @spec subtract_from_date(Date.t(), Types.duration()) :: Date.t()
  def subtract_from_date(date, duration) do
    # Convert duration to days (approximate for months/years)
    total_days =
      Map.get(duration, :days, 0) +
        Map.get(duration, :weeks, 0) * 7 +
        Map.get(duration, :months, 0) * 30 +
        Map.get(duration, :years, 0) * 365

    # Add hours/minutes/seconds as additional days if they add up to full days
    additional_seconds =
      Map.get(duration, :hours, 0) * 3600 + Map.get(duration, :minutes, 0) * 60 +
        Map.get(duration, :seconds, 0)

    additional_days = div(additional_seconds, 86_400)

    Date.add(date, -(total_days + additional_days))
  end

  @doc """
  Subtracts a duration from a DateTime, returning a DateTime.

  ## Examples

      iex> datetime = ~U[2024-01-17T14:00:00Z]
      iex> duration = Predicator.Duration.new(days: 2, hours: 3, minutes: 30)
      iex> Predicator.Duration.subtract_from_datetime(datetime, duration)
      ~U[2024-01-15T10:30:00Z]
  """
  @spec subtract_from_datetime(DateTime.t(), Types.duration()) :: DateTime.t()
  def subtract_from_datetime(datetime, %{milliseconds: ms} = duration) when ms > 0 do
    total_ms = to_milliseconds(duration)
    DateTime.add(datetime, -total_ms, :millisecond)
  end

  def subtract_from_datetime(datetime, duration) do
    total_seconds = to_seconds(duration)
    DateTime.add(datetime, -total_seconds, :second)
  end

  @doc """
  Converts a duration to a human-readable string.

  ## Examples

      iex> duration = Predicator.Duration.new(days: 3, hours: 8, minutes: 30)
      iex> Predicator.Duration.to_string(duration)
      "3d8h30m"

      iex> duration = Predicator.Duration.new(weeks: 2)
      iex> Predicator.Duration.to_string(duration)
      "2w"
  """
  @spec to_string(Types.duration()) :: binary()
  def to_string(duration) do
    units = [
      {:years, "y"},
      {:months, "mo"},
      {:weeks, "w"},
      {:days, "d"},
      {:hours, "h"},
      {:minutes, "m"},
      {:seconds, "s"},
      {:milliseconds, "ms"}
    ]

    parts =
      units
      |> Enum.reduce([], &build_duration_part(&1, &2, duration))
      |> Enum.reverse()

    format_duration_parts(parts)
  end

  defp build_duration_part({unit, suffix}, acc, duration) do
    value = Map.get(duration, unit, 0)

    if value > 0 do
      ["#{value}#{suffix}" | acc]
    else
      acc
    end
  end

  defp format_duration_parts([]), do: "0s"
  defp format_duration_parts(parts), do: Enum.join(parts, "")
end
