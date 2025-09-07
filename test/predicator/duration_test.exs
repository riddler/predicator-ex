defmodule Predicator.DurationTest do
  use ExUnit.Case
  doctest Predicator.Duration

  alias Predicator.Duration

  describe "new/1" do
    test "creates duration with default values" do
      duration = Duration.new()

      assert duration == %{
               years: 0,
               months: 0,
               weeks: 0,
               days: 0,
               hours: 0,
               minutes: 0,
               seconds: 0
             }
    end

    test "creates duration with specified values" do
      duration = Duration.new(days: 3, hours: 8, minutes: 30)

      assert duration == %{
               years: 0,
               months: 0,
               weeks: 0,
               days: 3,
               hours: 8,
               minutes: 30,
               seconds: 0
             }
    end

    test "creates duration with all units" do
      duration =
        Duration.new(
          years: 1,
          months: 2,
          weeks: 3,
          days: 4,
          hours: 5,
          minutes: 6,
          seconds: 7
        )

      assert duration.years == 1
      assert duration.months == 2
      assert duration.weeks == 3
      assert duration.days == 4
      assert duration.hours == 5
      assert duration.minutes == 6
      assert duration.seconds == 7
    end
  end

  describe "from_units/1" do
    test "creates duration from valid unit pairs" do
      {:ok, duration} = Duration.from_units([{"3", "d"}, {"8", "h"}])

      assert duration.days == 3
      assert duration.hours == 8
      assert duration.weeks == 0
    end

    test "handles multiple units of same type" do
      {:ok, duration} = Duration.from_units([{"2", "d"}, {"3", "d"}])
      assert duration.days == 5
    end

    test "handles all unit types" do
      {:ok, duration} =
        Duration.from_units([
          {"1", "y"},
          {"2", "mo"},
          {"3", "w"},
          {"4", "d"},
          {"5", "h"},
          {"6", "m"},
          {"7", "s"}
        ])

      assert duration.years == 1
      assert duration.months == 2
      assert duration.weeks == 3
      assert duration.days == 4
      assert duration.hours == 5
      assert duration.minutes == 6
      assert duration.seconds == 7
    end

    test "returns error for invalid value" do
      {:error, message} = Duration.from_units([{"invalid", "d"}])
      assert message == "Invalid duration value: invalid"
    end

    test "returns error for unknown unit" do
      {:error, message} = Duration.from_units([{"3", "x"}])
      assert message == "Unknown duration unit: x"
    end

    test "returns error for empty value" do
      {:error, message} = Duration.from_units([{"", "d"}])
      assert message == "Invalid duration value: "
    end

    test "handles zero values" do
      {:ok, duration} = Duration.from_units([{"0", "d"}, {"0", "h"}])
      assert duration.days == 0
      assert duration.hours == 0
    end
  end

  describe "add_unit/3" do
    test "adds years" do
      duration = Duration.new() |> Duration.add_unit("y", 3)
      assert duration.years == 3
    end

    test "adds months" do
      duration = Duration.new() |> Duration.add_unit("mo", 6)
      assert duration.months == 6
    end

    test "adds weeks" do
      duration = Duration.new() |> Duration.add_unit("w", 2)
      assert duration.weeks == 2
    end

    test "adds days" do
      duration = Duration.new() |> Duration.add_unit("d", 5)
      assert duration.days == 5
    end

    test "adds hours" do
      duration = Duration.new() |> Duration.add_unit("h", 12)
      assert duration.hours == 12
    end

    test "adds minutes" do
      duration = Duration.new() |> Duration.add_unit("m", 45)
      assert duration.minutes == 45
    end

    test "adds seconds" do
      duration = Duration.new() |> Duration.add_unit("s", 30)
      assert duration.seconds == 30
    end

    test "accumulates values" do
      duration = Duration.new(days: 2) |> Duration.add_unit("d", 3)
      assert duration.days == 5
    end
  end

  describe "to_seconds/1" do
    test "converts simple duration" do
      duration = Duration.new(minutes: 5, seconds: 30)
      assert Duration.to_seconds(duration) == 330
    end

    test "converts complex duration" do
      duration = Duration.new(days: 1, hours: 2, minutes: 30, seconds: 15)
      expected = 1 * 86_400 + 2 * 3600 + 30 * 60 + 15
      assert Duration.to_seconds(duration) == expected
    end

    test "converts weeks" do
      duration = Duration.new(weeks: 2)
      assert Duration.to_seconds(duration) == 2 * 604_800
    end

    test "converts months (approximate)" do
      duration = Duration.new(months: 1)
      assert Duration.to_seconds(duration) == 2_592_000
    end

    test "converts years (approximate)" do
      duration = Duration.new(years: 1)
      assert Duration.to_seconds(duration) == 31_536_000
    end

    test "converts zero duration" do
      duration = Duration.new()
      assert Duration.to_seconds(duration) == 0
    end
  end

  describe "add_to_date/2" do
    test "adds days to date" do
      date = ~D[2024-01-15]
      duration = Duration.new(days: 3)
      result = Duration.add_to_date(date, duration)
      assert result == ~D[2024-01-18]
    end

    test "adds weeks to date" do
      date = ~D[2024-01-01]
      duration = Duration.new(weeks: 2)
      result = Duration.add_to_date(date, duration)
      assert result == ~D[2024-01-15]
    end

    test "adds complex duration" do
      date = ~D[2024-01-01]
      duration = Duration.new(weeks: 1, days: 3)
      result = Duration.add_to_date(date, duration)
      assert result == ~D[2024-01-11]
    end

    test "adds hours as additional days" do
      date = ~D[2024-01-01]
      # More than 24 hours
      duration = Duration.new(hours: 25)
      result = Duration.add_to_date(date, duration)
      assert result == ~D[2024-01-02]
    end

    test "adds approximate months" do
      date = ~D[2024-01-01]
      duration = Duration.new(months: 1)
      result = Duration.add_to_date(date, duration)
      assert result == ~D[2024-01-31]
    end

    test "adds approximate years" do
      date = ~D[2024-01-01]
      duration = Duration.new(years: 1)
      result = Duration.add_to_date(date, duration)
      assert result == ~D[2024-12-31]
    end
  end

  describe "add_to_datetime/2" do
    test "adds hours to datetime" do
      datetime = ~U[2024-01-15T10:30:00Z]
      duration = Duration.new(hours: 3)
      result = Duration.add_to_datetime(datetime, duration)
      assert result == ~U[2024-01-15T13:30:00Z]
    end

    test "adds complex duration" do
      datetime = ~U[2024-01-15T10:30:00Z]
      duration = Duration.new(days: 2, hours: 3, minutes: 30)
      result = Duration.add_to_datetime(datetime, duration)
      assert result == ~U[2024-01-17T14:00:00Z]
    end

    test "adds minutes and seconds" do
      datetime = ~U[2024-01-15T10:30:00Z]
      duration = Duration.new(minutes: 30, seconds: 45)
      result = Duration.add_to_datetime(datetime, duration)
      assert result == ~U[2024-01-15T11:00:45Z]
    end

    test "wraps to next day" do
      datetime = ~U[2024-01-15T23:30:00Z]
      duration = Duration.new(hours: 2)
      result = Duration.add_to_datetime(datetime, duration)
      assert result == ~U[2024-01-16T01:30:00Z]
    end
  end

  describe "subtract_from_date/2" do
    test "subtracts days from date" do
      date = ~D[2024-01-25]
      duration = Duration.new(days: 10)
      result = Duration.subtract_from_date(date, duration)
      assert result == ~D[2024-01-15]
    end

    test "subtracts weeks" do
      date = ~D[2024-01-22]
      duration = Duration.new(weeks: 2)
      result = Duration.subtract_from_date(date, duration)
      assert result == ~D[2024-01-08]
    end

    test "subtracts complex duration" do
      date = ~D[2024-01-25]
      duration = Duration.new(weeks: 1, days: 3)
      result = Duration.subtract_from_date(date, duration)
      assert result == ~D[2024-01-15]
    end

    test "crosses month boundary" do
      date = ~D[2024-02-05]
      duration = Duration.new(days: 10)
      result = Duration.subtract_from_date(date, duration)
      assert result == ~D[2024-01-26]
    end
  end

  describe "subtract_from_datetime/2" do
    test "subtracts hours from datetime" do
      datetime = ~U[2024-01-17T14:00:00Z]
      duration = Duration.new(hours: 3)
      result = Duration.subtract_from_datetime(datetime, duration)
      assert result == ~U[2024-01-17T11:00:00Z]
    end

    test "subtracts complex duration" do
      datetime = ~U[2024-01-17T14:00:00Z]
      duration = Duration.new(days: 2, hours: 3, minutes: 30)
      result = Duration.subtract_from_datetime(datetime, duration)
      assert result == ~U[2024-01-15T10:30:00Z]
    end

    test "wraps to previous day" do
      datetime = ~U[2024-01-16T01:30:00Z]
      duration = Duration.new(hours: 3)
      result = Duration.subtract_from_datetime(datetime, duration)
      assert result == ~U[2024-01-15T22:30:00Z]
    end
  end

  describe "to_string/1" do
    test "formats simple duration" do
      duration = Duration.new(days: 3)
      assert Duration.to_string(duration) == "3d"
    end

    test "formats complex duration" do
      duration = Duration.new(days: 3, hours: 8, minutes: 30)
      assert Duration.to_string(duration) == "3d8h30m"
    end

    test "formats all units" do
      duration =
        Duration.new(
          years: 1,
          months: 2,
          weeks: 3,
          days: 4,
          hours: 5,
          minutes: 6,
          seconds: 7
        )

      assert Duration.to_string(duration) == "1y2mo3w4d5h6m7s"
    end

    test "formats zero duration" do
      duration = Duration.new()
      assert Duration.to_string(duration) == "0s"
    end

    test "formats only non-zero units" do
      duration = Duration.new(days: 2, minutes: 15)
      assert Duration.to_string(duration) == "2d15m"
    end

    test "formats weeks only" do
      duration = Duration.new(weeks: 2)
      assert Duration.to_string(duration) == "2w"
    end

    test "formats months only" do
      duration = Duration.new(months: 6)
      assert Duration.to_string(duration) == "6mo"
    end

    test "formats years only" do
      duration = Duration.new(years: 1)
      assert Duration.to_string(duration) == "1y"
    end
  end
end
