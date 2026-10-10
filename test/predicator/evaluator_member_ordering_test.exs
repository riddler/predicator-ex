defmodule Predicator.EvaluatorMemberOrderingTest do
  @moduledoc """
  Ordering two lists, or two plain maps, whose members are dates or
  datetimes. Two same-kind chronological members compare by instant, as the
  same pair does at the top level (docs/isa.md, `compare`); a pair level by
  instant steps to the next member. Equality and membership keep their
  structural answers, and a mixed `Date`/`DateTime` member pair keeps its
  term-order answer (ADR-0019).
  """
  use ExUnit.Case, async: true

  defp eval!(source, context \\ %{}) do
    {:ok, result} = Predicator.evaluate(source, context)
    result
  end

  defp dt!(iso) do
    {:ok, dt, _offset} = DateTime.from_iso8601(iso)
    dt
  end

  describe "two date members inside lists" do
    test "order by instant, not by the struct's day field" do
      assert eval!("[#2026-01-02#] < [#2025-12-31#]") == false
      assert eval!("[#2026-01-02#] > [#2025-12-31#]") == true
      assert eval!("[#2025-12-31#] < [#2026-01-02#]") == true
      assert eval!("[#2026-01-02#] <= [#2025-12-31#]") == false
      assert eval!("[#2026-01-02#] >= [#2025-12-31#]") == true
    end

    test "a level date pair steps to the next member" do
      assert eval!("[#2026-01-01#, #2026-01-02#] < [#2026-01-01#, #2025-12-31#]") == false
      assert eval!("[#2026-01-01#, #2025-12-31#] < [#2026-01-01#, #2026-01-02#]") == true
      assert eval!("[#2026-01-01#, 2] < [#2026-01-01#, 3]") == true
    end

    test "the first differing member decides, before any later one" do
      assert eval!("[#2025-12-31#, #2026-01-09#] < [#2026-01-02#, #2026-01-01#]") == true
    end

    test "a proper prefix still sorts first" do
      assert eval!("[#2026-01-02#] < [#2026-01-02#, #2025-12-31#]") == true
      assert eval!("[#2026-01-02#, #2025-12-31#] > [#2026-01-02#]") == true
    end

    test "dates nested a list deeper order the same way" do
      assert eval!("[[#2026-01-02#]] < [[#2025-12-31#]]") == false
      assert eval!("[[#2026-01-02#]] > [[#2025-12-31#]]") == true
    end

    test "date members bound from the context order by instant" do
      context = %{"a" => [~D[2026-01-02]], "b" => [~D[2025-12-31]]}
      assert eval!("a < b", context) == false
      assert eval!("a > b", context) == true
    end
  end

  describe "two datetime members inside lists" do
    test "order by instant" do
      assert eval!("[#2026-01-01T00:00:00Z#] < [#2025-12-31T00:00:00Z#]") == false
      assert eval!("[#2026-01-01T00:00:00Z#] > [#2025-12-31T00:00:00Z#]") == true
      assert eval!("[#2025-12-31T00:00:00Z#] <= [#2026-01-01T00:00:00Z#]") == true
    end

    test "a pair written to different precision is level and steps to the next member" do
      assert eval!("[#2026-01-01T00:00:00Z#] < [#2026-01-01T00:00:00.000Z#]") == false
      assert eval!("[#2026-01-01T00:00:00Z#] > [#2026-01-01T00:00:00.000Z#]") == false
      assert eval!("[#2026-01-01T00:00:00Z#] <= [#2026-01-01T00:00:00.000Z#]") == true
      assert eval!("[#2026-01-01T00:00:00Z#] >= [#2026-01-01T00:00:00.000Z#]") == true

      assert eval!("[#2026-01-01T00:00:00Z#, 1] < [#2026-01-01T00:00:00.000Z#, 2]") == true
    end

    test "the same instant in two offsets is level" do
      utc = dt!("2026-01-01T12:00:00Z")

      plus_one = %DateTime{
        utc
        | hour: 13,
          time_zone: "Etc/GMT-1",
          zone_abbr: "+01",
          utc_offset: 3600
      }

      context = %{"a" => [utc, 1], "b" => [plus_one, 2], "c" => [plus_one, 0]}

      assert eval!("a < b", context) == true
      assert eval!("a > c", context) == true
    end
  end

  describe "chronological members inside plain maps" do
    test "two maps that differ only by a date member order by instant" do
      assert eval!("{d: #2026-01-02#} < {d: #2025-12-31#}") == false
      assert eval!("{d: #2026-01-02#} > {d: #2025-12-31#}") == true
    end

    test "two maps that differ only by a datetime member order by instant" do
      assert eval!("{at: #2026-01-01T00:00:00Z#} < {at: #2025-12-31T00:00:00Z#}") == false
      assert eval!("{at: #2026-01-01T00:00:00Z#} > {at: #2025-12-31T00:00:00Z#}") == true
    end

    test "values are compared in key order; a level pair steps to the next key" do
      assert eval!("{a: #2026-01-01#, b: #2026-01-02#} < {a: #2026-01-01#, b: #2025-12-31#}") ==
               false

      assert eval!("{a: #2025-12-31#, b: #2026-01-09#} < {a: #2026-01-02#, b: #2026-01-01#}") ==
               true
    end

    test "a date member inside a map inside a list orders by instant" do
      assert eval!("[{due: #2026-01-02#}] < [{due: #2025-12-31#}]") == false
    end

    test "maps of different sizes or keys keep term order" do
      assert eval!("{a: #2026-01-02#} < {a: #2025-12-31#, b: 1}") == true
      assert eval!("{a: #2026-01-02#} < {b: #2025-12-31#}") == true
      assert eval!("{b: #2025-12-31#} < {a: #2026-01-02#}") == false
    end
  end

  describe "answers this change keeps" do
    test "a mixed date and datetime member pair keeps its term-order answer" do
      # Not decided by the ordering rule (ADR-0019): a Date struct is the
      # smaller map, so it sorts first whatever the instants say.
      assert eval!("[#2026-01-01#] < [#2025-01-01T00:00:00Z#]") == true
      assert eval!("[#2025-01-01T00:00:00Z#] < [#2026-01-01#]") == false
    end

    test "container equality stays structural" do
      assert eval!("[#2026-01-01T00:00:00Z#] == [#2026-01-01T00:00:00.000Z#]") == false
      assert eval!("[#2026-01-01T00:00:00Z#] != [#2026-01-01T00:00:00.000Z#]") == true
      assert eval!("{at: #2026-01-01T00:00:00Z#} == {at: #2026-01-01T00:00:00.000Z#}") == false
      assert eval!("[#2026-01-02#] == [#2026-01-02#]") == true
    end

    test "membership of a container stays structural" do
      assert eval!("[#2026-01-01T00:00:00Z#] in [[#2026-01-01T00:00:00.000Z#]]") == false
    end

    test "the top-level pair answers by instant, as before" do
      assert eval!("#2026-01-02# < #2025-12-31#") == false
      assert eval!("#2026-01-01T00:00:00Z# == #2026-01-01T00:00:00.000Z#") == true
      assert eval!("#2026-01-01# < #2025-01-01T00:00:00Z#") == false
    end

    test "lists of other members keep their element-wise answers" do
      assert eval!("[1, 2] < [1, 3]") == true
      assert eval!("[1] < [1, 2]") == true
      assert eval!("[1] <= [1.0]") == true
      assert eval!("[1] >= [1.0]") == true
      assert eval!("[\"a\"] < [1]") == false
      assert eval!("[] < [#2026-01-01#]") == true
      assert eval!("[] <= []") == true
    end

    test "a member that is undefined does not make the pair undefined" do
      assert eval!("[#2026-01-02#, missing] > [#2025-12-31#, missing]") == true
    end
  end
end
