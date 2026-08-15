defmodule Predicator.ParserDurationsTest do
  use ExUnit.Case, async: true

  import Predicator.ParseShape

  alias Predicator.Lexer

  describe "date and datetime parsing" do
    test "parses date literals correctly" do
      tokens = [
        {:date, 1, 1, 12, ~D[2024-01-15]},
        {:eof, 1, 13, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:ok, {:literal, ~D[2024-01-15]}} = result
    end

    test "parses datetime literals correctly" do
      {:ok, datetime, _offset} = DateTime.from_iso8601("2024-01-15T10:30:00Z")

      tokens = [
        {:datetime, 1, 1, 21, datetime},
        {:eof, 1, 22, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:ok, {:literal, ^datetime}} = result
    end

    test "parses date comparisons" do
      tokens = [
        {:date, 1, 1, 12, ~D[2024-01-15]},
        {:gt, 1, 14, 1, ">"},
        {:date, 1, 16, 12, ~D[2024-01-10]},
        {:eof, 1, 28, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:ok, {:comparison, :gt, {:literal, ~D[2024-01-15]}, {:literal, ~D[2024-01-10]}}} =
               result
    end
  end

  describe "parse/1 - duration expressions" do
    test "parses simple duration with single unit" do
      {:ok, tokens} = Lexer.tokenize("5d")
      result = parse_positionless(tokens)
      assert {:ok, {:duration, [{5, "d"}]}} = result
    end

    test "parses duration with multiple units" do
      {:ok, tokens} = Lexer.tokenize("1d8h30m")
      result = parse_positionless(tokens)
      assert {:ok, {:duration, [{1, "d"}, {8, "h"}, {30, "m"}]}} = result
    end

    test "parses duration with all unit types" do
      {:ok, tokens} = Lexer.tokenize("2y3mo4w5d6h7m8s")
      result = parse_positionless(tokens)

      assert {:ok,
              {:duration, [{2, "y"}, {3, "mo"}, {4, "w"}, {5, "d"}, {6, "h"}, {7, "m"}, {8, "s"}]}} =
               result
    end

    test "parses duration with single character units" do
      {:ok, tokens} = Lexer.tokenize("1y2mo3w4d5h6m7s")
      result = parse_positionless(tokens)

      assert {:ok,
              {:duration, [{1, "y"}, {2, "mo"}, {3, "w"}, {4, "d"}, {5, "h"}, {6, "m"}, {7, "s"}]}} =
               result
    end

    test "parses relative date with 'ago'" do
      {:ok, tokens} = Lexer.tokenize("1d8h ago")
      result = parse_positionless(tokens)
      assert {:ok, {:relative_date, {:duration, [{1, "d"}, {8, "h"}]}, :ago}} = result
    end

    test "parses relative date with 'from now'" do
      {:ok, tokens} = Lexer.tokenize("2h30m from now")
      result = parse_positionless(tokens)
      assert {:ok, {:relative_date, {:duration, [{2, "h"}, {30, "m"}]}, :future}} = result
    end

    test "parses relative date with 'next'" do
      {:ok, tokens} = Lexer.tokenize("next 1w")
      result = parse_positionless(tokens)
      assert {:ok, {:relative_date, {:duration, [{1, "w"}]}, :next}} = result
    end

    test "parses relative date with 'last'" do
      {:ok, tokens} = Lexer.tokenize("last 6mo")
      result = parse_positionless(tokens)
      assert {:ok, {:relative_date, {:duration, [{6, "mo"}]}, :last}} = result
    end

    test "duration in comparison expression" do
      {:ok, tokens} = Lexer.tokenize("created_at > 1d ago")
      result = parse_positionless(tokens)

      expected_ast =
        {:comparison, :gt, {:identifier, "created_at"},
         {:relative_date, {:duration, [{1, "d"}]}, :ago}}

      assert {:ok, ^expected_ast} = result
    end

    test "duration in complex expression" do
      {:ok, tokens} = Lexer.tokenize("created_at > 1d ago AND updated_at < 1h from now")
      result = parse_positionless(tokens)

      expected_ast =
        {:logical_and,
         {:comparison, :gt, {:identifier, "created_at"},
          {:relative_date, {:duration, [{1, "d"}]}, :ago}},
         {:comparison, :lt, {:identifier, "updated_at"},
          {:relative_date, {:duration, [{1, "h"}]}, :future}}}

      assert {:ok, ^expected_ast} = result
    end

    test "returns error for invalid duration sequence" do
      {:ok, tokens} = Lexer.tokenize("1d8x")
      result = parse_positionless(tokens)
      assert {:error, _message, _line, _col, _span} = result
    end

    test "returns error for missing 'now' after 'from'" do
      {:ok, tokens} = Lexer.tokenize("1d from yesterday")
      result = parse_positionless(tokens)
      assert {:error, _message, _line, _col, _span} = result
    end

    test "returns error for 'from' without duration" do
      {:ok, tokens} = Lexer.tokenize("from now")
      result = parse_positionless(tokens)
      assert {:error, _message, _line, _col, _span} = result
    end

    test "returns error for 'ago' without duration" do
      {:ok, tokens} = Lexer.tokenize("ago")
      result = parse_positionless(tokens)
      assert {:error, _message, _line, _col, _span} = result
    end

    test "returns error for 'next' without duration" do
      {:ok, tokens} = Lexer.tokenize("next")
      result = parse_positionless(tokens)
      assert {:error, _message, _line, _col, _span} = result
    end

    test "returns error for 'last' without duration" do
      {:ok, tokens} = Lexer.tokenize("last")
      result = parse_positionless(tokens)
      assert {:error, _message, _line, _col, _span} = result
    end

    test "parses zero duration" do
      {:ok, tokens} = Lexer.tokenize("0d")
      result = parse_positionless(tokens)
      assert {:ok, {:duration, [{0, "d"}]}} = result
    end

    test "parses large duration numbers" do
      {:ok, tokens} = Lexer.tokenize("999y365d24h60m60s")
      result = parse_positionless(tokens)

      assert {:ok, {:duration, [{999, "y"}, {365, "d"}, {24, "h"}, {60, "m"}, {60, "s"}]}} =
               result
    end
  end

  describe "parse/1 - fractional duration literals (px-5c5)" do
    test "expands a single fractional component" do
      {:ok, tokens} = Lexer.tokenize("1.5s")
      result = parse_positionless(tokens)
      assert {:ok, {:duration, [{1, "s"}, {500, "ms"}]}} = result
    end

    test "expands a fractional month using the 30-day approximation" do
      {:ok, tokens} = Lexer.tokenize("0.5mo")
      result = parse_positionless(tokens)
      assert {:ok, {:duration, [{15, "d"}]}} = result
    end

    test "expands a fractional year through the full remainder ladder" do
      {:ok, tokens} = Lexer.tokenize("1.5y")
      result = parse_positionless(tokens)
      assert {:ok, {:duration, [{1, "y"}, {182, "d"}, {12, "h"}]}} = result
    end

    test "expands a fractional component in the middle of a sequence" do
      {:ok, tokens} = Lexer.tokenize("1h1.5m")
      result = parse_positionless(tokens)
      assert {:ok, {:duration, [{1, "h"}, {1, "m"}, {30, "s"}]}} = result
    end

    test "a zero remainder emits nothing beyond the integer part" do
      {:ok, tokens} = Lexer.tokenize("1.0s")
      result = parse_positionless(tokens)
      assert {:ok, {:duration, [{1, "s"}]}} = result
    end

    test "an all-zero fractional component is the zero duration on its unit" do
      {:ok, tokens} = Lexer.tokenize("0.0s")
      result = parse_positionless(tokens)
      assert {:ok, {:duration, [{0, "s"}]}} = result
    end

    test "returns a spanned error for a sub-millisecond remainder" do
      {:ok, tokens} = Lexer.tokenize("0.5ms")
      result = parse_positionless(tokens)

      assert {:error, message, _line, _col, _span} = result
      assert message =~ "not a whole number of milliseconds"
    end

    test "returns a spanned error for an inexact fraction with trailing zeros" do
      {:ok, tokens} = Lexer.tokenize("1.0005s")
      result = parse_positionless(tokens)

      assert {:error, message, _line, _col, _span} = result
      assert message =~ "not a whole number of milliseconds"
    end

    test "returns a spanned error when expansion collides with another component" do
      {:ok, tokens} = Lexer.tokenize("1.5s200ms")
      result = parse_positionless(tokens)

      assert {:error, message, _line, _col, _span} = result
      assert message =~ "names the 'ms' unit twice"
    end

    test "returns a spanned error when expansion collides with a duplicate integer unit" do
      {:ok, tokens} = Lexer.tokenize("1.5s1s")
      result = parse_positionless(tokens)

      assert {:error, message, _line, _col, _span} = result
      assert message =~ "names the 's' unit twice"
    end

    test "returns a spanned error when two fractional components collide" do
      {:ok, tokens} = Lexer.tokenize("1.5s0.5s")
      result = parse_positionless(tokens)

      # "1.5s" expands to [{1,"s"},{500,"ms"}] and "0.5s" expands to
      # [{500,"ms"}] alone (its own zero integer part is omitted), so the
      # collision is on "ms", not "s".
      assert {:error, message, _line, _col, _span} = result
      assert message =~ "names the 'ms' unit twice"
    end

    test "a decimal number with no duration unit still lexes and parses as a float" do
      {:ok, tokens} = Lexer.tokenize("1.5")
      result = parse_positionless(tokens)
      assert {:ok, {:literal, 1.5}} = result
    end

    test "a fraction followed by a non-unit re-lexes as float then identifier, unchanged" do
      {:ok, tokens} = Lexer.tokenize("1.5x")
      result = parse_positionless(tokens)
      assert {:error, _message, _line, _col, _span} = result
    end

    test "integer-only literals are unaffected" do
      {:ok, tokens} = Lexer.tokenize("3d8h")
      result = parse_positionless(tokens)
      assert {:ok, {:duration, [{3, "d"}, {8, "h"}]}} = result
    end
  end
end
