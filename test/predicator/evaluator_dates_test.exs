defmodule Predicator.EvaluatorDatesTest do
  use ExUnit.Case, async: true

  alias Predicator.Evaluator

  describe "date and datetime evaluation" do
    test "evaluates date comparisons" do
      date1 = ~D[2024-01-15]
      date2 = ~D[2024-01-20]

      # Date GT
      instructions = [["lit", date2], ["lit", date1], ["compare", "GT"]]
      assert Evaluator.evaluate(instructions) == true

      # Date LT
      instructions = [["lit", date1], ["lit", date2], ["compare", "LT"]]
      assert Evaluator.evaluate(instructions) == true

      # Date EQ
      instructions = [["lit", date1], ["lit", date1], ["compare", "EQ"]]
      assert Evaluator.evaluate(instructions) == true

      # Date NE
      instructions = [["lit", date1], ["lit", date2], ["compare", "NE"]]
      assert Evaluator.evaluate(instructions) == true
    end

    test "evaluates datetime comparisons" do
      {:ok, dt1, _offset1} = DateTime.from_iso8601("2024-01-15T10:00:00Z")
      {:ok, dt2, _offset2} = DateTime.from_iso8601("2024-01-15T15:00:00Z")

      # DateTime GT
      instructions = [["lit", dt2], ["lit", dt1], ["compare", "GT"]]
      assert Evaluator.evaluate(instructions) == true

      # DateTime GTE (equal)
      instructions = [["lit", dt1], ["lit", dt1], ["compare", "GTE"]]
      assert Evaluator.evaluate(instructions) == true

      # DateTime LTE
      instructions = [["lit", dt1], ["lit", dt2], ["compare", "LTE"]]
      assert Evaluator.evaluate(instructions) == true
    end

    test "date and datetime membership operations" do
      dates = [~D[2024-01-15], ~D[2024-01-16]]
      {:ok, dt1, _offset1} = DateTime.from_iso8601("2024-01-15T10:00:00Z")
      {:ok, dt2, _offset2} = DateTime.from_iso8601("2024-01-15T15:00:00Z")
      datetimes = [dt1, dt2]

      # Date IN list
      instructions = [["lit", ~D[2024-01-15]], ["lit", dates], ["in"]]
      assert Evaluator.evaluate(instructions) == true

      # Date NOT IN list
      instructions = [["lit", ~D[2024-01-17]], ["lit", dates], ["in"]]
      assert Evaluator.evaluate(instructions) == false

      # DateTime CONTAINS
      instructions = [["lit", datetimes], ["lit", dt1], ["contains"]]
      assert Evaluator.evaluate(instructions) == true

      # DateTime NOT CONTAINS
      {:ok, dt3, _offset3} = DateTime.from_iso8601("2024-01-20T10:00:00Z")
      instructions = [["lit", datetimes], ["lit", dt3], ["contains"]]
      assert Evaluator.evaluate(instructions) == false
    end
  end

  describe "mixed date/datetime comparison" do
    test "orders a Date against a later DateTime in both operand orders" do
      date = ~D[2024-01-15]
      later = ~U[2024-01-20 10:00:00Z]

      assert Evaluator.evaluate([["lit", date], ["lit", later], ["compare", "LT"]]) == true
      assert Evaluator.evaluate([["lit", date], ["lit", later], ["compare", "LTE"]]) == true
      assert Evaluator.evaluate([["lit", date], ["lit", later], ["compare", "GT"]]) == false

      assert Evaluator.evaluate([["lit", later], ["lit", date], ["compare", "GT"]]) == true
      assert Evaluator.evaluate([["lit", later], ["lit", date], ["compare", "GTE"]]) == true
      assert Evaluator.evaluate([["lit", later], ["lit", date], ["compare", "LT"]]) == false
    end

    test "a Date equals the midnight-UTC DateTime of the same day" do
      date = ~D[2024-01-15]
      midnight = ~U[2024-01-15 00:00:00Z]
      one_second_later = ~U[2024-01-15 00:00:01Z]

      assert Evaluator.evaluate([["lit", date], ["lit", midnight], ["compare", "EQ"]]) == true
      assert Evaluator.evaluate([["lit", midnight], ["lit", date], ["compare", "EQ"]]) == true
      assert Evaluator.evaluate([["lit", date], ["lit", midnight], ["compare", "GTE"]]) == true
      assert Evaluator.evaluate([["lit", date], ["lit", midnight], ["compare", "LTE"]]) == true

      assert Evaluator.evaluate([["lit", date], ["lit", one_second_later], ["compare", "EQ"]]) ==
               false

      assert Evaluator.evaluate([["lit", date], ["lit", one_second_later], ["compare", "NE"]]) ==
               true
    end

    test "strict equality never crosses the Date/DateTime boundary" do
      date = ~D[2024-01-15]
      midnight = ~U[2024-01-15 00:00:00Z]

      assert Evaluator.evaluate([["lit", date], ["lit", midnight], ["compare", "STRICT_EQ"]]) ==
               false

      assert Evaluator.evaluate([["lit", date], ["lit", midnight], ["compare", "STRICT_NE"]]) ==
               true
    end

    test "membership coerces the same way" do
      date = ~D[2024-01-15]
      datetimes = [~U[2024-01-15 00:00:00Z], ~U[2024-01-16 12:00:00Z]]
      dates = [~D[2024-01-15], ~D[2024-01-16]]

      assert Evaluator.evaluate([["lit", date], ["lit", datetimes], ["in"]]) == true
      assert Evaluator.evaluate([["lit", ~D[2024-01-17]], ["lit", datetimes], ["in"]]) == false

      assert Evaluator.evaluate([["lit", dates], ["lit", ~U[2024-01-15 00:00:00Z]], ["contains"]]) ==
               true

      assert Evaluator.evaluate([["lit", dates], ["lit", ~U[2024-01-15 09:00:00Z]], ["contains"]]) ==
               false
    end
  end

  describe "evaluate/2 with duration instructions" do
    test "evaluates simple duration instruction" do
      instructions = [["duration", [[5, "d"]]]]
      result = Evaluator.evaluate(instructions)

      expected = %{years: 0, months: 0, weeks: 0, days: 5, hours: 0, minutes: 0, seconds: 0}
      assert result == expected
    end

    test "evaluates duration with multiple units" do
      instructions = [["duration", [[1, "d"], [8, "h"], [30, "m"]]]]
      result = Evaluator.evaluate(instructions)

      expected = %{years: 0, months: 0, weeks: 0, days: 1, hours: 8, minutes: 30, seconds: 0}
      assert result == expected
    end

    test "evaluates duration with all unit types" do
      instructions = [
        ["duration", [[2, "y"], [3, "mo"], [4, "w"], [5, "d"], [6, "h"], [7, "m"], [8, "s"]]]
      ]

      result = Evaluator.evaluate(instructions)

      expected = %{years: 2, months: 3, weeks: 4, days: 5, hours: 6, minutes: 7, seconds: 8}
      assert result == expected
    end

    test "evaluates duration with long unit names" do
      instructions = [["duration", [[1, "year"], [2, "months"], [3, "weeks"]]]]
      result = Evaluator.evaluate(instructions)

      expected = %{years: 1, months: 2, weeks: 3, days: 0, hours: 0, minutes: 0, seconds: 0}
      assert result == expected
    end

    test "evaluates duration with mixed unit formats" do
      instructions = [
        [
          "duration",
          [[1, "y"], [2, "month"], [3, "w"], [4, "day"], [5, "h"], [6, "min"], [7, "sec"]]
        ]
      ]

      result = Evaluator.evaluate(instructions)

      expected = %{years: 1, months: 2, weeks: 3, days: 4, hours: 5, minutes: 6, seconds: 7}
      assert result == expected
    end

    test "evaluates duration with zero values" do
      instructions = [["duration", [[0, "d"], [0, "h"]]]]
      result = Evaluator.evaluate(instructions)

      expected = %{years: 0, months: 0, weeks: 0, days: 0, hours: 0, minutes: 0, seconds: 0}
      assert result == expected
    end

    test "evaluates duration with large values" do
      instructions = [["duration", [[999, "y"], [365, "d"]]]]
      result = Evaluator.evaluate(instructions)

      expected = %{years: 999, months: 0, weeks: 0, days: 365, hours: 0, minutes: 0, seconds: 0}
      assert result == expected
    end

    test "returns error for invalid duration unit format" do
      instructions = [["duration", [["invalid"]]]]
      result = Evaluator.evaluate(instructions)

      assert {:error, _message} = result
    end

    test "returns error for invalid duration unit" do
      instructions = [["duration", [[5, "invalid_unit"]]]]
      result = Evaluator.evaluate(instructions)

      assert {:error, _message} = result
    end
  end

  describe "evaluate/2 with relative_date instructions" do
    test "evaluates relative date with ago direction" do
      instructions = [
        ["duration", [[1, "d"], [8, "h"]]],
        ["relative_date", "ago"]
      ]

      before_test = DateTime.utc_now()
      result = Evaluator.evaluate(instructions)

      # Result should be a DateTime roughly 1 day 8 hours ago
      assert %DateTime{} = result

      # Calculate expected time range (1d8h = 32 hours = 115200 seconds)
      expected_seconds_ago = 32 * 3600

      # Check the result is within reasonable bounds (allowing for test execution time)
      seconds_diff = DateTime.diff(before_test, result, :second)

      assert seconds_diff >= expected_seconds_ago - 10 and
               seconds_diff <= expected_seconds_ago + 10
    end

    test "evaluates relative date with future direction" do
      instructions = [
        ["duration", [[2, "h"], [30, "m"]]],
        ["relative_date", "future"]
      ]

      before_test = DateTime.utc_now()
      result = Evaluator.evaluate(instructions)

      # Result should be a DateTime roughly 2.5 hours in the future
      assert %DateTime{} = result

      # Calculate expected time (2h30m = 9000 seconds)
      expected_seconds_future = 2.5 * 3600

      # Check the result is within reasonable bounds
      seconds_diff = DateTime.diff(result, before_test, :second)

      assert seconds_diff >= expected_seconds_future - 10 and
               seconds_diff <= expected_seconds_future + 10
    end

    test "evaluates relative date with next direction" do
      instructions = [
        ["duration", [[1, "w"]]],
        ["relative_date", "next"]
      ]

      before_test = DateTime.utc_now()
      result = Evaluator.evaluate(instructions)

      # Result should be a DateTime roughly 1 week in the future
      assert %DateTime{} = result

      # Calculate expected time (1w = 7 * 24 * 3600 = 604800 seconds)
      expected_seconds_future = 7 * 24 * 3600

      # Check the result is within reasonable bounds
      seconds_diff = DateTime.diff(result, before_test, :second)

      assert seconds_diff >= expected_seconds_future - 10 and
               seconds_diff <= expected_seconds_future + 10
    end

    test "evaluates relative date with last direction" do
      instructions = [
        ["duration", [[6, "mo"]]],
        ["relative_date", "last"]
      ]

      before_test = DateTime.utc_now()
      result = Evaluator.evaluate(instructions)

      # Result should be a DateTime roughly 6 months ago
      assert %DateTime{} = result

      # Calculate expected time (6mo ≈ 6 * 30 * 24 * 3600 = 15552000 seconds)
      expected_seconds_ago = 6 * 30 * 24 * 3600

      # Check the result is within reasonable bounds
      seconds_diff = DateTime.diff(before_test, result, :second)

      assert seconds_diff >= expected_seconds_ago - 1000 and
               seconds_diff <= expected_seconds_ago + 1000
    end

    test "evaluates complex relative date with multiple units" do
      instructions = [
        ["duration", [[1, "y"], [2, "mo"], [3, "d"]]],
        ["relative_date", "ago"]
      ]

      before_test = DateTime.utc_now()
      result = Evaluator.evaluate(instructions)

      # Result should be a DateTime roughly 1 year 2 months 3 days ago
      assert %DateTime{} = result
      assert DateTime.compare(result, before_test) == :lt

      # Should be significantly in the past (approximate calculation)
      seconds_diff = DateTime.diff(before_test, result, :second)
      # Allow some variance
      expected_min = (365 + 60 + 3) * 24 * 3600 - 100_000
      expected_max = (365 + 60 + 3) * 24 * 3600 + 100_000
      assert seconds_diff >= expected_min and seconds_diff <= expected_max
    end

    test "returns error for unknown relative date direction" do
      instructions = [
        ["duration", [[1, "d"]]],
        ["relative_date", "unknown"]
      ]

      result = Evaluator.evaluate(instructions)
      assert {:error, _message} = result
    end

    test "returns error for relative_date without duration on stack" do
      instructions = [["relative_date", "ago"]]

      result = Evaluator.evaluate(instructions)
      assert {:error, _error_struct} = result
    end

    test "returns error for relative_date with non-duration on stack" do
      instructions = [
        ["lit", "not a duration"],
        ["relative_date", "ago"]
      ]

      result = Evaluator.evaluate(instructions)
      assert {:error, _message} = result
    end

    test "integrates with comparisons - date greater than relative date" do
      # Simulate: some_recent_date > 1d ago (recent date is more recent than 1 day ago)
      # 12 hours ago
      recent_date = DateTime.add(DateTime.utc_now(), -12 * 3600, :second)

      instructions = [
        ["lit", recent_date],
        ["duration", [[1, "d"]]],
        ["relative_date", "ago"],
        ["compare", "GT"]
      ]

      result = Evaluator.evaluate(instructions)
      # 12 hours ago is greater than (more recent than) 1 day ago
      assert result == true
    end

    test "integrates with logical operations" do
      # Simulate: created_at > 1d ago AND updated_at < 1h from now, in jump
      # form (see the composite tests in the "logical operators" describe
      # block for why)
      now = DateTime.utc_now()
      # 1 hour ago
      recent_past = DateTime.add(now, -3600, :second)
      # 30 minutes from now
      near_future = DateTime.add(now, 1800, :second)

      instructions = [
        ["lit", recent_past],
        ["duration", [[1, "d"]]],
        ["relative_date", "ago"],
        ["compare", "GT"],
        ["jump_if_falsy_or_pop", 5],
        ["lit", near_future],
        ["duration", [[1, "h"]]],
        ["relative_date", "future"],
        ["compare", "LT"]
      ]

      result = Evaluator.evaluate(instructions)
      # Both conditions should be true
      assert result == true
    end
  end
end
