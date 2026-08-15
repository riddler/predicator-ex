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
               seconds: 0,
               milliseconds: 0
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
               seconds: 0,
               milliseconds: 0
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
          seconds: 7,
          milliseconds: 123
        )

      assert duration.years == 1
      assert duration.months == 2
      assert duration.weeks == 3
      assert duration.days == 4
      assert duration.hours == 5
      assert duration.minutes == 6
      assert duration.seconds == 7
      assert duration.milliseconds == 123
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

    test "formats milliseconds" do
      duration = Duration.new(milliseconds: 500)
      assert Duration.to_string(duration) == "500ms"
    end

    test "formats complex duration with milliseconds" do
      duration = Duration.new(seconds: 30, milliseconds: 250)
      assert Duration.to_string(duration) == "30s250ms"
    end
  end

  describe "milliseconds support" do
    test "creates duration with milliseconds only" do
      duration = Duration.new(milliseconds: 500)
      assert duration.milliseconds == 500
    end

    test "adds milliseconds unit" do
      duration = Duration.new() |> Duration.add_unit("ms", 750)
      assert duration.milliseconds == 750
    end

    test "accumulates millisecond values" do
      duration = Duration.new(milliseconds: 200) |> Duration.add_unit("ms", 300)
      assert duration.milliseconds == 500
    end

    test "from_units handles milliseconds" do
      {:ok, duration} = Duration.from_units([{"500", "ms"}])
      assert duration.milliseconds == 500
    end

    test "from_units handles mixed units with milliseconds" do
      {:ok, duration} = Duration.from_units([{"1", "s"}, {"500", "ms"}])
      assert duration.seconds == 1
      assert duration.milliseconds == 500
    end
  end

  describe "to_milliseconds/1" do
    test "converts simple milliseconds" do
      duration = Duration.new(milliseconds: 500)
      assert Duration.to_milliseconds(duration) == 500
    end

    test "converts seconds to milliseconds" do
      duration = Duration.new(seconds: 2)
      assert Duration.to_milliseconds(duration) == 2000
    end

    test "converts mixed seconds and milliseconds" do
      duration = Duration.new(seconds: 1, milliseconds: 500)
      assert Duration.to_milliseconds(duration) == 1500
    end

    test "converts minutes to milliseconds" do
      duration = Duration.new(minutes: 1, seconds: 30, milliseconds: 250)
      expected = 1 * 60_000 + 30 * 1_000 + 250
      assert Duration.to_milliseconds(duration) == expected
    end

    test "converts hours to milliseconds" do
      duration = Duration.new(hours: 1)
      assert Duration.to_milliseconds(duration) == 3_600_000
    end

    test "converts days to milliseconds" do
      duration = Duration.new(days: 1)
      assert Duration.to_milliseconds(duration) == 86_400_000
    end

    test "converts zero duration" do
      duration = Duration.new()
      assert Duration.to_milliseconds(duration) == 0
    end

    test "converts complex duration to milliseconds" do
      duration = Duration.new(hours: 1, minutes: 30, seconds: 45, milliseconds: 123)
      expected = 1 * 3_600_000 + 30 * 60_000 + 45 * 1_000 + 123
      assert Duration.to_milliseconds(duration) == expected
    end
  end

  describe "datetime operations with milliseconds" do
    test "add_to_datetime uses millisecond precision when milliseconds present" do
      datetime = ~U[2024-01-15T10:30:00.000Z]
      duration = Duration.new(seconds: 1, milliseconds: 500)
      result = Duration.add_to_datetime(datetime, duration)
      assert result == ~U[2024-01-15T10:30:01.500Z]
    end

    test "add_to_datetime uses second precision when no milliseconds" do
      datetime = ~U[2024-01-15T10:30:00.000Z]
      duration = Duration.new(seconds: 5)
      result = Duration.add_to_datetime(datetime, duration)
      assert result == ~U[2024-01-15T10:30:05.000Z]
    end

    test "subtract_from_datetime uses millisecond precision when milliseconds present" do
      datetime = ~U[2024-01-15T10:30:02.750Z]
      duration = Duration.new(seconds: 1, milliseconds: 250)
      result = Duration.subtract_from_datetime(datetime, duration)
      assert result == ~U[2024-01-15T10:30:01.500Z]
    end

    test "subtract_from_datetime uses second precision when no milliseconds" do
      datetime = ~U[2024-01-15T10:30:05.000Z]
      duration = Duration.new(seconds: 2)
      result = Duration.subtract_from_datetime(datetime, duration)
      assert result == ~U[2024-01-15T10:30:03.000Z]
    end

    test "millisecond precision with complex durations" do
      datetime = ~U[2024-01-15T10:30:00.000Z]
      duration = Duration.new(minutes: 1, seconds: 30, milliseconds: 750)
      result = Duration.add_to_datetime(datetime, duration)
      assert result == ~U[2024-01-15T10:31:30.750Z]
    end
  end

  describe "expand_fraction/3" do
    # Every row of the worked-expectations table in
    # docs/plans/260814-px-5c5-fractional-durations.md's Phase 1, exhaustive
    # over docs/research/260814-px-5c5-fractional-durations-decisions.md's
    # Decision 2 (integer-arithmetic exactness) and Decision 3 (greedy
    # decomposition through d/h/m/s/ms only).
    test "expands the fractional part onto the remainder ladder, per unit" do
      assert Duration.expand_fraction(1, "5", "s") == {:ok, [{1, "s"}, {500, "ms"}]}
      assert Duration.expand_fraction(1, "5", "m") == {:ok, [{1, "m"}, {30, "s"}]}
      assert Duration.expand_fraction(1, "5", "h") == {:ok, [{1, "h"}, {30, "m"}]}
      assert Duration.expand_fraction(1, "5", "d") == {:ok, [{1, "d"}, {12, "h"}]}
      assert Duration.expand_fraction(0, "5", "w") == {:ok, [{3, "d"}, {12, "h"}]}
      assert Duration.expand_fraction(0, "5", "mo") == {:ok, [{15, "d"}]}
      assert Duration.expand_fraction(1, "5", "y") == {:ok, [{1, "y"}, {182, "d"}, {12, "h"}]}
    end

    test "omits a zero remainder, and keeps only the integer part's pair" do
      assert Duration.expand_fraction(1, "0", "s") == {:ok, [{1, "s"}]}
      assert Duration.expand_fraction(1, "0", "ms") == {:ok, [{1, "ms"}]}
    end

    test "a zero integer part with a zero fraction still yields one pair on the source unit" do
      # This is what keeps the AST's unit list non-empty and keeps
      # StringVisitor's rendering round-trippable (Decision 6, worked
      # expectations, and plan step 6 of the expansion helper).
      assert Duration.expand_fraction(0, "0", "s") == {:ok, [{0, "s"}]}
    end

    test "sub-second cases named by hand in the decision record" do
      assert Duration.expand_fraction(0, "25", "s") == {:ok, [{250, "ms"}]}
      assert Duration.expand_fraction(0, "1", "s") == {:ok, [{100, "ms"}]}
    end

    test "rejects a sub-millisecond remainder" do
      assert Duration.expand_fraction(0, "5", "ms") == {:error, :subunit_remainder}
    end

    test "rejects an inexact fraction with more digits than the unit can hold" do
      assert Duration.expand_fraction(1, "0005", "s") == {:error, :subunit_remainder}
    end

    test "rejects an unknown unit" do
      assert Duration.expand_fraction(1, "5", "x") == {:error, :unknown_unit}
    end
  end

  describe "parse/1" do
    test "parses each of the eight units alone" do
      assert Duration.parse("1y") == {:ok, Duration.new(years: 1)}
      assert Duration.parse("1mo") == {:ok, Duration.new(months: 1)}
      assert Duration.parse("1w") == {:ok, Duration.new(weeks: 1)}
      assert Duration.parse("1d") == {:ok, Duration.new(days: 1)}
      assert Duration.parse("1h") == {:ok, Duration.new(hours: 1)}
      assert Duration.parse("1m") == {:ok, Duration.new(minutes: 1)}
      assert Duration.parse("1s") == {:ok, Duration.new(seconds: 1)}
      assert Duration.parse("1ms") == {:ok, Duration.new(milliseconds: 1)}
    end

    test "parses a multi-unit string" do
      assert Duration.parse("3d8h30m") ==
               {:ok, Duration.new(days: 3, hours: 8, minutes: 30)}
    end

    test "disambiguates mo from m and ms from m" do
      assert Duration.parse("1mo") == {:ok, Duration.new(months: 1)}
      assert Duration.parse("1m") == {:ok, Duration.new(minutes: 1)}
      assert Duration.parse("1ms") == {:ok, Duration.new(milliseconds: 1)}

      assert Duration.parse("2mo3m4ms") ==
               {:ok, Duration.new(months: 2, minutes: 3, milliseconds: 4)}
    end

    test "accumulates on a repeated unit" do
      assert Duration.parse("1d2d") == {:ok, Duration.new(days: 3)}
      assert Duration.parse("1h1h1h") == {:ok, Duration.new(hours: 3)}
    end

    test "round-trips through to_string/1, including the 0s case" do
      for duration <- [
            Duration.new(),
            Duration.new(seconds: 0),
            Duration.new(days: 3, hours: 8, minutes: 30),
            Duration.new(weeks: 2),
            Duration.new(
              years: 1,
              months: 2,
              weeks: 3,
              days: 4,
              hours: 5,
              minutes: 6,
              seconds: 7
            ),
            Duration.new(milliseconds: 500)
          ] do
        assert Duration.parse(Duration.to_string(duration)) == {:ok, duration}
      end
    end

    test "rejects the empty string" do
      assert Duration.parse("") == :error
    end

    test "rejects a negative value" do
      assert Duration.parse("-1d") == :error
    end

    test "accepts a fractional value and expands it to whole units" do
      assert Duration.parse("1.5d") == {:ok, Duration.new(days: 1, hours: 12)}
    end

    test "accepts a fractional component on every unit" do
      assert Duration.parse("1.5s") == {:ok, Duration.new(seconds: 1, milliseconds: 500)}
      assert Duration.parse("0.5s") == {:ok, Duration.new(milliseconds: 500)}
      assert Duration.parse("0.25s") == {:ok, Duration.new(milliseconds: 250)}
      assert Duration.parse("0.1s") == {:ok, Duration.new(milliseconds: 100)}
      assert Duration.parse("1.0s") == {:ok, Duration.new(seconds: 1)}
      assert Duration.parse("0.0s") == {:ok, Duration.new(seconds: 0)}
      assert Duration.parse("1.5m") == {:ok, Duration.new(minutes: 1, seconds: 30)}
      assert Duration.parse("1.5h") == {:ok, Duration.new(hours: 1, minutes: 30)}
      assert Duration.parse("0.5w") == {:ok, Duration.new(days: 3, hours: 12)}

      # 0.5mo commits the documented 30-day approximation at parse time - no
      # months key in the result (Decision 3).
      assert Duration.parse("0.5mo") == {:ok, Duration.new(days: 15)}

      assert Duration.parse("1.5y") == {:ok, Duration.new(years: 1, days: 182, hours: 12)}
      assert Duration.parse("1.0ms") == {:ok, Duration.new(milliseconds: 1)}
    end

    test "accumulates a mixed fractional and integer literal, unlike the compiled literal grammar" do
      # Duration.parse/1 stays a lenient accumulator uniformly, expansions
      # included (Decision 6c): "1.5s200ms" expands "1.5s" to 1s500ms and then
      # accumulates the "200ms" component onto the same milliseconds field,
      # giving 1s700ms. The compiled duration *literal* `1.5s200ms` takes a
      # different, stricter path (a compile-time collision error, Phase 2) -
      # this divergence is deliberate and documented in
      # docs/reference/language.md's canonicalizer section.
      assert Duration.parse("1.5s200ms") == {:ok, Duration.new(seconds: 1, milliseconds: 700)}
    end

    test "rejects an unknown unit" do
      assert Duration.parse("1x") == :error
    end

    test "rejects trailing junk" do
      assert Duration.parse("1dabc") == :error
    end

    test "rejects leading whitespace" do
      assert Duration.parse(" 1d") == :error
    end

    test "rejects embedded whitespace" do
      assert Duration.parse("1d 2h") == :error
    end

    test "rejects a sub-millisecond remainder" do
      assert Duration.parse("0.5ms") == :error
    end

    test "rejects an inexact fraction" do
      assert Duration.parse("1.0005s") == :error
    end

    test "rejects a leading-dot fraction" do
      assert Duration.parse(".5s") == :error
    end

    test "rejects a trailing-dot fraction" do
      assert Duration.parse("1.s") == :error
    end

    test "rejects a bare unit" do
      assert Duration.parse("s") == :error
    end

    test "rejects a double dot" do
      assert Duration.parse("1..5s") == :error
    end

    test "rejects a fraction with no unit" do
      assert Duration.parse("1.5") == :error
    end

    test "rejects a bare number with no unit" do
      assert Duration.parse("42") == :error
    end

    test "rejects trailing whitespace" do
      assert Duration.parse("1d ") == :error
    end

    test "rejects a trailing newline" do
      assert Duration.parse("1d\n") == :error
    end

    test "rejects a leading newline" do
      assert Duration.parse("\n1d") == :error
    end
  end
end
