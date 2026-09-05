defmodule Predicator.Visitors.StringVisitorObjectKeyEscapeTest do
  @moduledoc """
  px-0tz: `format_object_key/1` in `StringVisitor` escaped the quote character
  of the style it was writing but never the escape character itself, so a
  quoted object key containing a backslash rendered to source the parser reads
  differently - the backslash silently gone, or, for a key ending in one, an
  unterminated literal that does not parse at all.

  A quoted object key is lexed by the same string rule as a string literal
  (`parse_object_key/1` in `parser.ex` reads a STRING token), so the law under
  test is the same round trip px-v3b pinned for literals: for every key and
  every quote style, the source the writer produces parses back to an object
  carrying an equal key, in the style it was asked for. That is why the fix
  routes both quoted clauses through the writer's shared escaping helper
  rather than growing a second implementation - two escape paths in one writer
  is how this defect survived the first fix.

  The corpus is enumerated from the characters the lexer treats specially
  rather than transcribed from examples, so it ranges over the combinations -
  a backslash immediately before the quote is the case a naive escape order
  gets wrong - instead of over the ones someone happened to think of.
  """

  use ExUnit.Case, async: true

  alias Predicator.Visitors.StringVisitor

  # The same enumeration px-v3b built for literals, shared from
  # `Predicator.EscapeCorpus` (test_helper.exs): a quoted key is read by the
  # same lexer rule, so the awkward cases are the same ones and the two suites
  # should not drift apart.
  defp keys, do: Predicator.EscapeCorpus.values()

  defp render(key, style) do
    StringVisitor.visit(
      {:object, [{{:object_key, key, style, nil}, {:literal, 1, nil}}], nil},
      []
    )
  end

  describe "a quoted object key renders to source that parses back to an equal key" do
    test "for every key in the corpus, in both quote styles" do
      corpus = keys()
      assert length(corpus) > 50

      for key <- corpus, style <- [:single, :double] do
        source = render(key, style)

        assert {:ok, {:object, [{parsed_key, _value}], _position}} = Predicator.parse(source),
               "rendered #{inspect(source)} for key #{inspect(key)} in #{style} quotes, " <>
                 "which does not parse"

        assert {:object_key, key, style, elem(parsed_key, 3)} == parsed_key,
               "key #{inspect(key)} in #{style} quotes rendered as #{inspect(source)}, " <>
                 "which parses to #{inspect(parsed_key)}"
      end
    end

    test "parse -> decompile -> parse is a fixed point for every key" do
      for key <- keys(), style <- [:single, :double] do
        expression = render(key, style)

        assert {:ok, ast} = Predicator.parse(expression)
        written = Predicator.decompile(ast)

        assert {:ok, reparsed} = Predicator.parse(written),
               "#{inspect(expression)} decompiled to #{inspect(written)}, which does not parse"

        assert reparsed == ast,
               "#{inspect(expression)} decompiled to #{inspect(written)}, which parses to a " <>
                 "different object"
      end
    end
  end

  describe "the named cases the bead calls out" do
    test "a key that is a lone backslash is a terminated literal in both styles" do
      assert render("\\", :single) == ~S({'\\': 1})
      assert render("\\", :double) == ~S({"\\": 1})
    end

    test "a backslash immediately before the quote escapes as two, not as one" do
      # Escaping the quote first would produce `{'\\'': 1}`, whose trailing
      # quote closes the key one character early.
      assert render("\\'", :single) == ~S({'\\\'': 1})
      assert render("\\\"", :double) == ~S({"\\\"": 1})
    end

    test "the quote character of the style is escaped, not switched away from" do
      assert render("'", :single) == ~S({'\'': 1})
      assert render("\"", :double) == ~S({"\"": 1})
    end

    test "the other style's quote character needs no escape" do
      assert render("\"", :single) == ~S({'"': 1})
      assert render("'", :double) == ~S({"'": 1})
    end

    test "an ordinary key gains no escapes it does not need" do
      assert render("first name", :single) == "{'first name': 1}"
      assert render("first name", :double) == ~s({"first name": 1})
    end
  end

  describe "the identifier style is untouched" do
    test "an unquoted key renders bare and round-trips" do
      source = render("cardholder_name", :identifier)
      assert source == "{cardholder_name: 1}"

      assert {:ok, {:object, [{{:object_key, "cardholder_name", :identifier, _p}, _v}], _pos}} =
               Predicator.parse(source)
    end
  end
end
