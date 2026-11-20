defmodule Predicator.Visitors.StringVisitorDatetimeRangeTest do
  @moduledoc """
  A datetime is an instant from 0000-01-01T00:00:00Z through
  9999-12-31T23:59:59.999999Z in UTC, and nothing outside that range is a
  datetime (docs/isa.md section 3). A literal outside it is refused by the
  lexer; a literal inside it decompiles to text the lexer accepts and that
  parses to the same value.

  Before the range was enforced, a literal such as
  `#9999-12-31T23:59:59-05:00#` lexed to a year-10000 instant whose decompiled
  text carried a five-digit year the lexer then refused, so the text round trip
  broke.

  The property is checked by enumeration rather than randomisation - this repo
  carries no property-testing dependency and gains none here: every UTC offset
  from -23:59 to +23:59, minute by minute, applied to several local times at
  each bound. Each candidate's expected verdict is computed independently of
  the lexer, from the local time and the offset.
  """

  use ExUnit.Case, async: true

  @local_times [
    "0000-01-01T00:00:00",
    "0000-01-01T12:30:00.5",
    "0000-01-01T23:59:59.999999",
    "9999-12-31T00:00:00",
    "9999-12-31T12:30:00.5",
    "9999-12-31T23:59:59.999999"
  ]

  @first_instant ~N[0000-01-01 00:00:00.000000]
  @last_instant ~N[9999-12-31 23:59:59.999999]

  defp offsets do
    for sign <- [1, -1], minutes <- 0..(24 * 60 - 1), not (sign == -1 and minutes == 0) do
      sign * minutes
    end
  end

  defp offset_text(offset_minutes) do
    sign = if offset_minutes < 0, do: "-", else: "+"
    minutes = abs(offset_minutes)
    sign <> pad2(div(minutes, 60)) <> ":" <> pad2(rem(minutes, 60))
  end

  defp pad2(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")

  # The UTC instant the local time and offset name, computed without the lexer:
  # local time minus the offset.
  defp in_range?(local_time, offset_minutes) do
    utc =
      local_time
      |> NaiveDateTime.from_iso8601!()
      |> NaiveDateTime.add(-offset_minutes * 60, :second)

    NaiveDateTime.compare(utc, @first_instant) != :lt and
      NaiveDateTime.compare(utc, @last_instant) != :gt
  end

  test "every candidate is accepted exactly when its UTC instant is in range" do
    for local_time <- @local_times, offset <- offsets() do
      content = local_time <> offset_text(offset)
      source = "#" <> content <> "#"

      if in_range?(local_time, offset) do
        assert {:ok, {:literal, %DateTime{year: year}, _position}} = Predicator.parse(source),
               "expected #{source} to parse"

        assert year in 0..9999
      else
        assert {:error, message, 1, 1, {{1, 1}, {1, end_col}}} = Predicator.parse(source)
        assert end_col == String.length(source) + 1
        assert message == "Invalid datetime format: " <> content
      end
    end
  end

  test "every accepted literal decompiles to text that parses to the same value" do
    accepted =
      for local_time <- @local_times,
          offset <- offsets(),
          source = "#" <> local_time <> offset_text(offset) <> "#",
          match?({:ok, _ast}, Predicator.parse(source)),
          do: source

    # Both bounds are reached, so the enumeration exercises the edge it exists for.
    assert Enum.any?(accepted, &String.starts_with?(&1, "#0000-"))
    assert Enum.any?(accepted, &String.starts_with?(&1, "#9999-"))

    for source <- accepted do
      {:ok, {:literal, value, _position} = ast} = Predicator.parse(source)
      decompiled = Predicator.decompile(ast)

      assert {:ok, {:literal, round_tripped, _round_tripped_position}} =
               Predicator.parse(decompiled),
             "#{source} decompiled to #{decompiled}, which does not parse"

      assert round_tripped == value
    end
  end

  test "the boundary literals themselves round-trip" do
    for source <- ["#0000-01-01T00:00:00Z#", "#9999-12-31T23:59:59.999999Z#"] do
      {:ok, ast} = Predicator.parse(source)
      assert Predicator.decompile(ast) == source
    end
  end
end
