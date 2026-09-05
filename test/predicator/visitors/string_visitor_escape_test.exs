defmodule Predicator.Visitors.StringVisitorEscapeTest do
  @moduledoc """
  px-v3b: `StringVisitor` escaped the quote character of the style it was
  writing but never the escape character itself, in either style, so a value
  containing a backslash rendered to source the parser reads differently - or,
  for a value of a single backslash, to the unterminated literal `'\\'`.

  The law under test is the round trip: for every value and every quote style,
  the source the writer produces parses back to a node carrying an equal
  value, in the same style it was asked for. The corpus is enumerated from the
  characters the lexer treats specially rather than transcribed from examples,
  so it ranges over the combinations - a backslash immediately before a quote
  is the case a naive escape order gets wrong - instead of over the ones
  someone happened to think of.

  The operator's ruling on this bead (2026-09-04) settles the quote-style
  question: the writer escapes within the style it was given and never
  switches to the other one, because the consumers of the structured-authoring
  subset derive their quoting by round-tripping probe values through this
  writer. A test below pins that.
  """

  use ExUnit.Case, async: true

  alias Predicator.Visitors.StringVisitor

  # Every character the lexer's string rule gives meaning to, plus ordinary
  # text to sit them next to. `take_string/6` in `lexer.ex` decodes `\\`, `\"`,
  # `\'`, `\n`, `\t` and `\r`, and keeps a raw newline, tab or return verbatim.
  @special ["\\", "'", "\"", "\n", "\t", "\r"]
  @filler ["", "a", "ab"]

  defp values do
    singles = @special ++ @filler

    pairs =
      for left <- @special, right <- @special, do: left <> right

    surrounded =
      for prefix <- @filler,
          special <- @special,
          suffix <- @filler,
          do: prefix <> special <> suffix

    triples =
      for left <- @special, right <- @special, do: left <> right <> "z"

    Enum.uniq(singles ++ pairs ++ surrounded ++ triples)
  end

  describe "a string literal renders to source that parses back to an equal node" do
    test "for every value in the corpus, in both quote styles" do
      corpus = values()
      assert length(corpus) > 50

      for value <- corpus, style <- [:single, :double] do
        source = StringVisitor.visit({:string_literal, value, style, nil}, [])

        assert {:ok, reparsed} = Predicator.parse(source),
               "rendered #{inspect(source)} for #{inspect(value)} in #{style} quotes, " <>
                 "which does not parse"

        assert reparsed == {:string_literal, value, style, {1, 1}},
               "#{inspect(value)} in #{style} quotes rendered as #{inspect(source)}, " <>
                 "which parses to #{inspect(reparsed)}"
      end
    end

    test "parse -> decompile -> parse is a fixed point for every value" do
      for value <- values(), style <- [:single, :double] do
        source = StringVisitor.visit({:string_literal, value, style, nil}, [])
        expression = "name == " <> source

        assert {:ok, ast} = Predicator.parse(expression)
        written = Predicator.decompile(ast)

        assert {:ok, reparsed} = Predicator.parse(written),
               "#{inspect(expression)} decompiled to #{inspect(written)}, which does not parse"

        assert reparsed == ast,
               "#{inspect(expression)} decompiled to #{inspect(written)}, which parses to a " <>
                 "different node"
      end
    end

    test "the requested quote style is the style that comes back" do
      for value <- values() do
        assert StringVisitor.visit({:string_literal, value, :single, nil}, []) =~ ~r/\A'/
        assert StringVisitor.visit({:string_literal, value, :double, nil}, []) =~ ~r/\A"/
      end
    end
  end

  describe "the named cases the bead calls out" do
    test "a lone backslash is a terminated literal in both styles" do
      assert StringVisitor.visit({:string_literal, "\\", :single, nil}, []) == ~S('\\')
      assert StringVisitor.visit({:string_literal, "\\", :double, nil}, []) == ~S("\\")
    end

    test "the quote character of the style is escaped, not switched away from" do
      assert StringVisitor.visit({:string_literal, "'", :single, nil}, []) == ~S('\'')
      assert StringVisitor.visit({:string_literal, "\"", :double, nil}, []) == ~S("\"")
    end

    test "the other style's quote character needs no escape" do
      assert StringVisitor.visit({:string_literal, "\"", :single, nil}, []) == ~S('"')
      assert StringVisitor.visit({:string_literal, "'", :double, nil}, []) == ~S("'")
    end

    test "a backslash immediately before the quote escapes as two, not as one" do
      # The order matters: escaping the quote first would produce `'\\''`, whose
      # trailing quote closes the literal one character early.
      assert StringVisitor.visit({:string_literal, "\\'", :single, nil}, []) == ~S('\\\'')
      assert StringVisitor.visit({:string_literal, "\\\"", :double, nil}, []) == ~S("\\\"")
    end

    test "an empty string is a pair of quotes" do
      assert StringVisitor.visit({:string_literal, "", :single, nil}, []) == "''"
      assert StringVisitor.visit({:string_literal, "", :double, nil}, []) == ~s("")
    end

    test "an ordinary value gains no escapes it does not need" do
      assert StringVisitor.visit({:string_literal, "John", :single, nil}, []) == "'John'"
      assert StringVisitor.visit({:string_literal, "John", :double, nil}, []) == ~s("John")
    end
  end

  describe "the back-compat {:literal, binary} clause carries the same escaping" do
    test "a value with a backslash parses back to the same string" do
      for value <- values() do
        source = StringVisitor.visit({:literal, value, nil}, [])

        assert {:ok, {:string_literal, ^value, :double, _position}} = Predicator.parse(source),
               "rendered #{inspect(source)} for #{inspect(value)}"
      end
    end
  end

  describe "a card-domain expression survives the trip" do
    test "a cardholder name containing a quote round-trips" do
      expression = ~S(cardholder_name == "O\"Hara")

      assert {:ok, ast} = Predicator.parse(expression)
      assert Predicator.decompile(ast) == expression
    end
  end
end
