defmodule PredicatorLiteralsTest do
  use ExUnit.Case, async: true

  import Predicator.ParseShape

  alias Predicator.Errors.UndefinedVariableError

  describe "date literals and comparisons" do
    test "evaluates date literals" do
      assert Predicator.evaluate("#2024-01-15#", %{}) == {:ok, ~D[2024-01-15]}
    end

    test "evaluates datetime literals" do
      result = Predicator.evaluate("#2024-01-15T10:30:00Z#", %{})
      expected = DateTime.from_iso8601("2024-01-15T10:30:00Z") |> elem(1)
      assert result == {:ok, expected}
    end

    test "evaluates date comparisons with literals" do
      assert Predicator.evaluate("#2024-01-15# > #2024-01-10#", %{}) == {:ok, true}
      assert Predicator.evaluate("#2024-01-15# < #2024-01-10#", %{}) == {:ok, false}
      assert Predicator.evaluate("#2024-01-15# >= #2024-01-15#", %{}) == {:ok, true}
      assert Predicator.evaluate("#2024-01-15# <= #2024-01-15#", %{}) == {:ok, true}
      assert Predicator.evaluate("#2024-01-15# == #2024-01-15#", %{}) == {:ok, true}
      assert Predicator.evaluate("#2024-01-15# != #2024-01-10#", %{}) == {:ok, true}
    end

    test "evaluates date comparisons chronologically across months and years" do
      # Regression for px-ddc: Erlang's term order compares Date structs by
      # map key (day, month, year), so day-first ordering used to win over
      # chronological ordering whenever the days disagreed.
      assert Predicator.evaluate("#2026-08-14# < #2030-01-01#", %{}) == {:ok, true}
      assert Predicator.evaluate("#2024-01-10# < #2030-01-01#", %{}) == {:ok, true}
      assert Predicator.evaluate("#2030-01-01# > #2026-08-14#", %{}) == {:ok, true}
    end

    test "evaluates datetime comparisons with literals" do
      dt1 = "#2024-01-15T10:30:00Z#"
      dt2 = "#2024-01-15T09:30:00Z#"
      dt3 = "#2024-01-15T10:30:00Z#"

      assert Predicator.evaluate("#{dt1} > #{dt2}", %{}) == {:ok, true}
      assert Predicator.evaluate("#{dt1} < #{dt2}", %{}) == {:ok, false}
      assert Predicator.evaluate("#{dt1} >= #{dt3}", %{}) == {:ok, true}
      assert Predicator.evaluate("#{dt1} <= #{dt3}", %{}) == {:ok, true}
      assert Predicator.evaluate("#{dt1} == #{dt3}", %{}) == {:ok, true}
      assert Predicator.evaluate("#{dt1} != #{dt2}", %{}) == {:ok, true}
    end

    test "evaluates date comparisons with variables" do
      context = %{
        "start_date" => ~D[2024-01-15],
        "end_date" => ~D[2024-01-20]
      }

      assert Predicator.evaluate("start_date < end_date", context) == {:ok, true}
      assert Predicator.evaluate("start_date > end_date", context) == {:ok, false}
      assert Predicator.evaluate("start_date <= start_date", context) == {:ok, true}
      assert Predicator.evaluate("#2024-01-18# > start_date", context) == {:ok, true}
      assert Predicator.evaluate("#2024-01-18# < end_date", context) == {:ok, true}
    end

    test "evaluates datetime comparisons with variables" do
      {:ok, start_dt, _offset1} = DateTime.from_iso8601("2024-01-15T10:00:00Z")
      {:ok, end_dt, _offset2} = DateTime.from_iso8601("2024-01-15T18:00:00Z")

      context = %{
        "meeting_start" => start_dt,
        "meeting_end" => end_dt
      }

      assert Predicator.evaluate("meeting_start < meeting_end", context) == {:ok, true}
      assert Predicator.evaluate("#2024-01-15T14:00:00Z# > meeting_start", context) == {:ok, true}
      assert Predicator.evaluate("#2024-01-15T14:00:00Z# < meeting_end", context) == {:ok, true}
    end

    test "evaluates datetime comparisons chronologically across months and years" do
      # Regression for px-ddc: Erlang's term order compares DateTime structs
      # by map key, putting day and microsecond ahead of month and year.
      assert Predicator.evaluate("#2026-08-14T00:00:00Z# < #2030-01-01T00:00:00Z#", %{}) ==
               {:ok, true}
    end

    test "evaluates DateTime equality and ordering across time zones" do
      {:ok, utc, _offset} = DateTime.from_iso8601("2024-01-15T12:00:00Z")
      {:ok, same_instant_offset, _offset} = DateTime.from_iso8601("2024-01-15T07:00:00-05:00")
      later_offset = DateTime.add(same_instant_offset, 3600, :second)

      context = %{
        "utc" => utc,
        "same_instant_offset" => same_instant_offset,
        "later_offset" => later_offset
      }

      assert Predicator.evaluate("utc == same_instant_offset", context) == {:ok, true}
      assert Predicator.evaluate("utc != same_instant_offset", context) == {:ok, false}
      assert Predicator.evaluate("utc < later_offset", context) == {:ok, true}
      assert Predicator.evaluate("later_offset > utc", context) == {:ok, true}
    end

    test "handles mixed date and datetime comparisons" do
      # The Date coerces to 00:00:00 UTC of that day
      assert Predicator.evaluate("#2024-01-15# > #2024-01-15T10:00:00Z#", %{}) == {:ok, false}
      assert Predicator.evaluate("#2024-01-15# < #2024-01-15T10:00:00Z#", %{}) == {:ok, true}
      assert Predicator.evaluate("#2024-01-15# == #2024-01-15T00:00:00Z#", %{}) == {:ok, true}
    end

    test "combines with logical operators" do
      context = %{
        "start_date" => ~D[2024-01-15],
        "end_date" => ~D[2024-01-20],
        "active" => true
      }

      assert Predicator.evaluate("start_date < end_date AND active", context) == {:ok, true}
      assert Predicator.evaluate("start_date > end_date OR active", context) == {:ok, true}
      assert Predicator.evaluate("NOT start_date > end_date", context) == {:ok, true}
    end

    test "works in list membership operations" do
      dates = [~D[2024-01-15], ~D[2024-01-16], ~D[2024-01-17]]
      context = %{"dates" => dates}

      assert Predicator.evaluate("#2024-01-15# in dates", context) == {:ok, true}
      assert Predicator.evaluate("#2024-01-18# in dates", context) == {:ok, false}
      assert Predicator.evaluate("dates contains #2024-01-16#", context) == {:ok, true}
      assert Predicator.evaluate("dates contains #2024-01-18#", context) == {:ok, false}
    end

    test "returns an UndefinedVariableError for an unbound root date variable" do
      assert Predicator.evaluate("missing_date > #2024-01-15#", %{}) ==
               {:error,
                Predicator.Errors.put_position(
                  UndefinedVariableError.new("missing_date"),
                  {1, 1}
                )}

      assert Predicator.evaluate("#2024-01-15# < missing_date", %{}) ==
               {:error,
                Predicator.Errors.put_position(
                  UndefinedVariableError.new("missing_date"),
                  {1, 16}
                )}
    end

    test "parses date expressions correctly" do
      {:ok, ast} = parse_positionless("#2024-01-15#")
      assert match?({:literal, %Date{}}, ast)

      {:ok, ast} = parse_positionless("#2024-01-15T10:30:00Z#")
      assert match?({:literal, %DateTime{}}, ast)

      {:ok, ast} = parse_positionless("#2024-01-15# > #2024-01-10#")
      assert match?({:comparison, :gt, {:literal, %Date{}}, {:literal, %Date{}}}, ast)
    end

    test "compiles date expressions correctly" do
      {:ok, instructions} = Predicator.compile("#2024-01-15#")
      assert [["lit", %Date{}]] = instructions

      {:ok, instructions} = Predicator.compile("#2024-01-15# > #2024-01-10#")
      assert [["lit", %Date{}], ["lit", %Date{}], ["compare", "GT"]] = instructions
    end

    test "decompiles date expressions" do
      {:ok, ast} = Predicator.parse("#2024-01-15#")
      assert Predicator.decompile(ast) == "#2024-01-15#"

      {:ok, ast} = Predicator.parse("#2024-01-15T10:30:00Z#")
      decompiled = Predicator.decompile(ast)
      assert String.starts_with?(decompiled, "#2024-01-15T10:30:00")
      assert String.ends_with?(decompiled, "#")

      {:ok, ast} = Predicator.parse("#2024-01-15# > #2024-01-10#")
      assert Predicator.decompile(ast) == "#2024-01-15# > #2024-01-10#"
    end

    test "handles error cases" do
      # Invalid date format
      result = Predicator.evaluate("#invalid-date#", %{})
      assert {:error, _message} = result

      # Syntax errors
      result = Predicator.evaluate("#2024-01-15", %{})
      assert {:error, _message} = result
    end

    test "works with complex expressions" do
      {:ok, start_dt, _offset1} = DateTime.from_iso8601("2024-01-15T09:00:00Z")
      {:ok, end_dt, _offset2} = DateTime.from_iso8601("2024-01-15T17:00:00Z")

      context = %{
        "event_start" => start_dt,
        "event_end" => end_dt,
        "published" => true,
        "deadline" => ~D[2024-01-20]
      }

      # Complex date and boolean logic
      result =
        Predicator.evaluate(
          "published AND event_start < #2024-01-15T12:00:00Z# AND deadline > #2024-01-18#",
          context
        )

      assert result == {:ok, true}

      result =
        Predicator.evaluate(
          "(event_start > #2024-01-15T10:00:00Z# OR published) AND deadline < #2024-01-19#",
          context
        )

      assert result == {:ok, false}
    end
  end

  describe "single quoted strings" do
    test "evaluates single quoted string comparisons" do
      context = %{"name" => "John"}

      assert Predicator.evaluate("name == 'John'", context) == {:ok, true}
      assert Predicator.evaluate("name == 'Jane'", context) == {:ok, false}
    end

    test "handles mixed single and double quotes" do
      context = %{"quote" => "don't", "apostrophe" => "he said \"hello\""}

      assert Predicator.evaluate("quote == 'don\\'t'", context) == {:ok, true}
      assert Predicator.evaluate("apostrophe == 'he said \"hello\"'", context) == {:ok, true}
    end

    test "preserves quote type in round trip compilation" do
      # Test that single quotes are preserved through parsing and decompilation
      single_quoted = "name == 'John'"
      double_quoted = "name == \"John\""

      {:ok, single_ast} = Predicator.parse(single_quoted)
      {:ok, double_ast} = Predicator.parse(double_quoted)

      single_decompiled = Predicator.decompile(single_ast)
      double_decompiled = Predicator.decompile(double_ast)

      assert single_decompiled == "name == 'John'"
      assert double_decompiled == "name == \"John\""
    end

    test "single quoted strings in complex expressions" do
      context = %{"status" => "active", "role" => "admin"}

      assert Predicator.evaluate("status == 'active' AND role == 'admin'", context) == {:ok, true}

      assert Predicator.evaluate("status == 'inactive' OR role == 'admin'", context) ==
               {:ok, true}
    end

    test "single quoted strings in lists and membership" do
      context = %{"roles" => ["admin", "user"]}

      assert Predicator.evaluate("'admin' in roles", context) == {:ok, true}
      assert Predicator.evaluate("'guest' in roles", context) == {:ok, false}
    end
  end
end
