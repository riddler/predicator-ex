defmodule Predicator.CastTest do
  use ExUnit.Case

  alias Predicator.Cast
  alias Predicator.Duration

  describe "type_names/0" do
    test "returns exactly the seven names in ISA order" do
      assert Cast.type_names() == ~w(integer float string boolean date datetime duration)
    end
  end

  describe "propagation rule" do
    test ":undefined casts to :undefined for every target" do
      for type_name <- Cast.type_names() do
        assert Cast.cast(:undefined, type_name) == :undefined
      end
    end
  end

  describe "totality rule" do
    test "an unconvertible value against every target is :undefined, never a raise" do
      unconvertible_by_type = %{
        "integer" => ["abc", true, %{}, []],
        "float" => ["abc", true, %{}, []],
        "string" => [[1, 2], %{"a" => 1}],
        "boolean" => ["1", "yes", 1, 0.0, %{}, []],
        "date" => [true, 1, %{}, []],
        "datetime" => [true, 1, %{}, []],
        "duration" => [true, 1, "abc", %{}, []]
      }

      for {type_name, values} <- unconvertible_by_type, value <- values do
        assert Cast.cast(value, type_name) == :undefined
      end
    end

    test "lists and maps are :undefined for every target, including ::string" do
      for value <- [[1, 2], %{"a" => 1}], type_name <- Cast.type_names() do
        assert Cast.cast(value, type_name) == :undefined
      end
    end
  end

  describe "cast/2 to integer" do
    test "identity" do
      assert Cast.cast(42, "integer") == 42
      assert Cast.cast(-7, "integer") == -7
    end

    test "float truncates toward zero" do
      assert Cast.cast(-1.5, "integer") == -1
      assert Cast.cast(1.9, "integer") == 1
      assert Cast.cast(0.0, "integer") == 0
    end

    test "string parses a whole optionally-negated decimal integer" do
      assert Cast.cast("42", "integer") == 42
      assert Cast.cast("-42", "integer") == -42
      assert Cast.cast("0", "integer") == 0
    end

    test "whole-string strictness" do
      assert Cast.cast(" 42", "integer") == :undefined
      assert Cast.cast("42 ", "integer") == :undefined
      assert Cast.cast("42abc", "integer") == :undefined
      assert Cast.cast("+42", "integer") == :undefined
      assert Cast.cast("4_2", "integer") == :undefined
      assert Cast.cast("", "integer") == :undefined
    end

    test "a leading or trailing newline is not end-of-string, not a raise" do
      assert Cast.cast("42\n", "integer") == :undefined
      assert Cast.cast("\n42", "integer") == :undefined
    end

    test "no boolean/number bridge" do
      assert Cast.cast(true, "integer") == :undefined
      assert Cast.cast(false, "integer") == :undefined
    end
  end

  describe "cast/2 to float" do
    test "identity" do
      assert Cast.cast(1.5, "float") == 1.5
    end

    test "integer widens exactly" do
      assert Cast.cast(42, "float") == 42.0
      assert Cast.cast(-7, "float") == -7.0
    end

    test "string parses a whole optionally-negated decimal with optional fraction" do
      assert Cast.cast("3.5", "float") == 3.5
      assert Cast.cast("-3.5", "float") == -3.5
      assert Cast.cast("3", "float") == 3.0
    end

    test "whole-string strictness rejects exponent and partial forms" do
      assert Cast.cast("1e3", "float") == :undefined
      assert Cast.cast(".5", "float") == :undefined
      assert Cast.cast("3.", "float") == :undefined
      assert Cast.cast(" 3.5", "float") == :undefined
      assert Cast.cast("3.5 ", "float") == :undefined
      assert Cast.cast("+3.5", "float") == :undefined
      assert Cast.cast("", "float") == :undefined
    end

    test "a leading or trailing newline is not end-of-string, not a raise" do
      assert Cast.cast("3.5\n", "float") == :undefined
      assert Cast.cast("\n3.5", "float") == :undefined
    end

    test "no boolean/number bridge" do
      assert Cast.cast(true, "float") == :undefined
      assert Cast.cast(false, "float") == :undefined
    end
  end

  describe "cast/2 to string" do
    test "identity" do
      assert Cast.cast("hello", "string") == "hello"
    end

    test "integer formats as decimal" do
      assert Cast.cast(42, "string") == "42"
      assert Cast.cast(-7, "string") == "-7"
    end

    test "float formats via shortest round-trip" do
      assert Cast.cast(3.5, "string") == "3.5"
      assert Cast.cast(0.1, "string") == "0.1"
    end

    test "boolean formats as true/false" do
      assert Cast.cast(true, "string") == "true"
      assert Cast.cast(false, "string") == "false"
    end

    test "date formats as ISO 8601" do
      assert Cast.cast(~D[2026-08-09], "string") == "2026-08-09"
    end

    test "datetime with a zero sub-second component formats with no fraction" do
      # docs/isa.md section 5 pins this: the fraction is omitted entirely when
      # the sub-second component is zero. normalize_to_utc/1 still forces
      # microsecond precision internally - that is what keeps UTC
      # normalization tz-database-free - but the precision field is an Elixir
      # struct detail and no longer reaches the output.
      assert Cast.cast(~U[2026-08-09T10:00:00Z], "string") == "2026-08-09T10:00:00Z"

      {:ok, offset_dt, _offset} = DateTime.from_iso8601("2026-08-09T12:00:00+02:00")
      assert Cast.cast(offset_dt, "string") == "2026-08-09T10:00:00Z"
    end

    test "datetime with a non-zero sub-second component formats with six digits" do
      assert Cast.cast(~U[2026-08-09T10:00:00.5Z], "string") ==
               "2026-08-09T10:00:00.500000Z"

      assert Cast.cast(~U[2026-08-09T10:00:00.123456Z], "string") ==
               "2026-08-09T10:00:00.123456Z"
    end

    test "datetime::string is a canonicalization, not a string identity" do
      # A seventh input digit is truncated by the ::datetime parse, and a
      # one-digit fraction widens to six. Both are docs/isa.md section 5's
      # stated behavior, not an accident of the host type.
      assert "2026-08-09T10:00:00.123456789Z" |> Cast.cast("datetime") |> Cast.cast("string") ==
               "2026-08-09T10:00:00.123456Z"

      assert "2026-08-09T10:00:00.5Z" |> Cast.cast("datetime") |> Cast.cast("string") ==
               "2026-08-09T10:00:00.500000Z"

      assert "2026-08-09T10:00:00Z" |> Cast.cast("datetime") |> Cast.cast("string") ==
               "2026-08-09T10:00:00Z"
    end

    test "duration formats via the duration-literal grammar" do
      assert Cast.cast(Duration.new(days: 3, hours: 8, minutes: 30), "string") == "3d8h30m"
      assert Cast.cast(Duration.new(), "string") == "0s"
    end
  end

  describe "cast/2 to boolean" do
    test "identity" do
      assert Cast.cast(true, "boolean") == true
      assert Cast.cast(false, "boolean") == false
    end

    test "string is exactly true/false, case-sensitive" do
      assert Cast.cast("true", "boolean") == true
      assert Cast.cast("false", "boolean") == false
    end

    test "boolean strictness" do
      assert Cast.cast("TRUE", "boolean") == :undefined
      assert Cast.cast("True", "boolean") == :undefined
      assert Cast.cast("1", "boolean") == :undefined
      assert Cast.cast("yes", "boolean") == :undefined
    end

    test "no boolean/number bridge" do
      assert Cast.cast(1, "boolean") == :undefined
      assert Cast.cast(0, "boolean") == :undefined
      assert Cast.cast(1.0, "boolean") == :undefined
    end
  end

  describe "cast/2 to date" do
    test "identity" do
      assert Cast.cast(~D[2026-08-09], "date") == ~D[2026-08-09]
    end

    test "string parses an ISO 8601 calendar date" do
      assert Cast.cast("2026-08-09", "date") == ~D[2026-08-09]
    end

    test "date strictness rejects a datetime-shaped or malformed string" do
      assert Cast.cast("2026-08-09T00:00:00Z", "date") == :undefined
      assert Cast.cast("2026-8-9", "date") == :undefined
    end

    test "datetime->date drops the time" do
      assert Cast.cast(~U[2026-08-09T10:30:00Z], "date") == ~D[2026-08-09]
    end

    test "no boolean/number bridge" do
      assert Cast.cast(true, "date") == :undefined
      assert Cast.cast(1, "date") == :undefined
    end
  end

  describe "cast/2 to datetime" do
    test "identity" do
      assert Cast.cast(~U[2026-08-09T10:00:00Z], "datetime") == ~U[2026-08-09T10:00:00Z]
    end

    test "string requires a UTC offset and normalizes to UTC" do
      assert Cast.cast("2026-08-09T10:00:00", "datetime") == :undefined

      expected = normalize_to_utc_for_test(~U[2026-08-09T10:00:00Z])
      assert Cast.cast("2026-08-09T10:00:00Z", "datetime") == expected

      from_offset = Cast.cast("2026-08-09T12:00:00+02:00", "datetime")
      assert from_offset == expected
      assert DateTime.to_unix(from_offset) == DateTime.to_unix(expected)
    end

    test "date->datetime bridge is midnight UTC" do
      {:ok, expected} = DateTime.new(~D[2026-08-09], ~T[00:00:00], "Etc/UTC")
      assert Cast.cast(~D[2026-08-09], "datetime") == expected
    end

    test "no boolean/number bridge" do
      assert Cast.cast(true, "datetime") == :undefined
      assert Cast.cast(1, "datetime") == :undefined
    end
  end

  describe "cast/2 to duration" do
    test "identity" do
      duration = Duration.new(days: 3, hours: 8)
      assert Cast.cast(duration, "duration") == duration
    end

    test "string parses the duration-literal grammar" do
      assert Cast.cast("1d2h30m", "duration") == Duration.new(days: 1, hours: 2, minutes: 30)
    end

    test "string rejects a malformed duration literal" do
      assert Cast.cast("abc", "duration") == :undefined
      assert Cast.cast("1x", "duration") == :undefined
    end

    test "a leading or trailing newline is not end-of-string, not a silent accept" do
      assert Cast.cast("1d\n", "duration") == :undefined
      assert Cast.cast("\n1d", "duration") == :undefined
    end

    test "no boolean/number bridge" do
      assert Cast.cast(true, "duration") == :undefined
      assert Cast.cast(1, "duration") == :undefined
    end
  end

  describe "duration round-trip through ::string and back" do
    test "to_string then parse recovers the original duration, including 0s" do
      for duration <- [
            Duration.new(),
            Duration.new(days: 3, hours: 8, minutes: 30),
            Duration.new(weeks: 2),
            Duration.new(milliseconds: 500)
          ] do
        as_string = Cast.cast(duration, "string")
        assert Cast.cast(as_string, "duration") == duration
      end
    end

    test "mo vs ms disambiguation survives the round trip" do
      months_only = Duration.new(months: 1)
      ms_only = Duration.new(milliseconds: 1)

      assert Cast.cast(months_only, "string") == "1mo"
      assert Cast.cast(ms_only, "string") == "1ms"
      assert Cast.cast("1mo", "duration") == months_only
      assert Cast.cast("1ms", "duration") == ms_only
    end
  end

  describe "chained composition" do
    test "date::datetime::date round-trips through the bridge" do
      date = ~D[2026-08-09]
      assert date |> Cast.cast("datetime") |> Cast.cast("date") == date
    end

    test "string::date::datetime is the supported spelling for date-shaped strings" do
      {:ok, expected} = DateTime.new(~D[2026-08-09], ~T[00:00:00], "Etc/UTC")

      result =
        "2026-08-09"
        |> Cast.cast("date")
        |> Cast.cast("datetime")

      assert result == expected
    end
  end

  describe "representative - cells per source type" do
    test "integer has no path to date, datetime, or duration" do
      for type_name <- ["date", "datetime", "duration"] do
        assert Cast.cast(1, type_name) == :undefined
      end
    end

    test "float has no path to date, datetime, or duration" do
      for type_name <- ["date", "datetime", "duration"] do
        assert Cast.cast(1.0, type_name) == :undefined
      end
    end

    test "boolean has no path to integer, float, date, datetime, or duration" do
      for type_name <- ["integer", "float", "date", "datetime", "duration"] do
        assert Cast.cast(true, type_name) == :undefined
      end
    end

    test "date has no path to integer, float, boolean, or duration" do
      for type_name <- ["integer", "float", "boolean", "duration"] do
        assert Cast.cast(~D[2026-08-09], type_name) == :undefined
      end
    end

    test "datetime has no path to integer, float, boolean, or duration" do
      for type_name <- ["integer", "float", "boolean", "duration"] do
        assert Cast.cast(~U[2026-08-09T10:00:00Z], type_name) == :undefined
      end
    end

    test "duration has no path to integer, float, boolean, date, or datetime" do
      for type_name <- ["integer", "float", "boolean", "date", "datetime"] do
        assert Cast.cast(Duration.new(days: 1), type_name) == :undefined
      end
    end
  end

  # Mirrors Predicator.Cast's private tzdb-free UTC normalization, so tests
  # can build an expected value at the same microsecond precision the
  # implementation produces without depending on a time zone database.
  defp normalize_to_utc_for_test(datetime) do
    DateTime.from_unix!(DateTime.to_unix(datetime, :microsecond), :microsecond)
  end
end
