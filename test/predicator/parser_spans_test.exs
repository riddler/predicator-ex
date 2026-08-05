defmodule Predicator.ParserSpansTest do
  use ExUnit.Case, async: true

  alias Predicator.Lexer
  alias Predicator.Parser

  @corpus [
    "42",
    "3.5",
    "true",
    ~s("hello"),
    "'hello'",
    "#2024-01-15#",
    "score",
    "a > 1",
    "a in [1, 2]",
    "a contains 1",
    "a + 1 * 2 - 3 / 4 % 5",
    "-a",
    "!a",
    "NOT a",
    "a > 1 AND b < 2",
    "a > 1 OR b < 2",
    "a > 1 && b < 2",
    "a > 1 || b < 2",
    "[a, b, 3]",
    "[]",
    "{a: 1, \"b\": x}",
    "{'c d': 1}",
    "{}",
    "len(upper(name))",
    "f()",
    "a[0][1]",
    "user.name.first",
    "3d8h",
    "3d ago",
    "3d from now",
    "next 2w",
    "last 1d",
    "(a + b)"
  ]

  describe "leaves" do
    test "an integer literal spans its own token" do
      assert_span("42", "42")
    end

    test "a float literal spans its own token" do
      assert_span("3.5", "3.5")
    end

    test "a boolean literal spans its own token" do
      assert_span("true", "true")
    end

    test "a double-quoted string spans both quotes" do
      assert_span(~s("hi"), ~s("hi"))
    end

    test "a single-quoted string spans both quotes" do
      assert_span("'hi'", "'hi'")
    end

    test "a date literal spans both # fences" do
      assert_span("#2024-01-15#", "#2024-01-15#")
    end

    test "a datetime literal spans both # fences" do
      source = "#2024-01-15T10:30:00Z#"
      assert_span(source, source)
    end

    test "an identifier spans its own token" do
      assert_span("score", "score")
    end
  end

  describe "binary operators" do
    test "a comparison spans both operands" do
      assert_span("score > 85", "score > 85")
    end

    test "membership spans both operands" do
      assert_span("a in [1, 2]", "a in [1, 2]")
    end

    test "arithmetic spans both operands" do
      assert_span("a * true", "a * true")
    end

    test "logical AND spans both operands" do
      assert_span("a > 1 AND b < 2", "a > 1 AND b < 2")
    end

    test "logical OR spans both operands" do
      assert_span("a > 1 OR b < 2", "a > 1 OR b < 2")
    end

    test "a left-nested chain gives each level its own span" do
      source = "a + a + a"
      {:ok, {:arithmetic, :add, left, _right, outer}} = parse_spans(source)

      assert slice(source, outer) == "a + a + a"
      assert slice(source, span_of(left)) == "a + a"
    end
  end

  describe "prefix operators" do
    test "unary minus spans the operator and its operand" do
      assert_span("-x", "-x")
    end

    test "unary bang spans the operator and its operand" do
      assert_span("a > -x", "a > -x")
    end

    test "logical not spans the keyword and its operand" do
      assert_span("NOT a", "NOT a")
    end

    test "a chained not extends the span leftward one level at a time" do
      source = "!!a"
      {:ok, {:logical_not, inner, outer}} = parse_spans(source)

      assert slice(source, outer) == "!!a"
      assert slice(source, span_of(inner)) == "!a"
    end
  end

  describe "delimited forms" do
    test "a list spans both brackets" do
      assert_span("[1, 2]", "[1, 2]")
    end

    test "an empty list spans both brackets" do
      assert_span("[]", "[]")
    end

    test "an object spans both braces" do
      assert_span(~s({a: 1, "b": 2}), ~s({a: 1, "b": 2}))
    end

    test "an empty object spans both braces" do
      assert_span("{}", "{}")
    end

    test "a function call spans from the name past the closing paren" do
      assert_span("len(name)", "len(name)")
    end

    test "an empty argument list still spans both parens" do
      assert_span("f()", "f()")
    end

    test "a qualified function call spans its whole name" do
      assert_span("String.upper(name)", "String.upper(name)")
    end

    test "a nested call's span does not leak into its caller" do
      source = "len(upper(name))"
      {:ok, {:function_call, "len", [inner], outer}} = parse_spans(source)

      assert slice(source, outer) == source
      assert slice(source, span_of(inner)) == "upper(name)"
    end
  end

  describe "object keys" do
    test "each key style spans its own token, quotes included" do
      source = ~s({a: 1, "b": 2, 'c': 3})
      {:ok, {:object, entries, _span}} = parse_spans(source)

      assert Enum.map(entries, fn {key, _value} -> slice(source, span_of(key)) end) ==
               ["a", ~s("b"), "'c'"]
    end
  end

  describe "postfix access" do
    test "chained bracket access spans from the target past each bracket" do
      source = "a[0][1]"
      {:ok, {:bracket_access, inner, _key, outer}} = parse_spans(source)

      assert slice(source, outer) == "a[0][1]"
      assert slice(source, span_of(inner)) == "a[0]"
    end

    test "chained property access spans from the target past each name" do
      source = "a.b.c"
      {:ok, {:property_access, inner, "c", outer}} = parse_spans(source)

      assert slice(source, outer) == "a.b.c"
      assert slice(source, span_of(inner)) == "a.b"
    end
  end

  describe "durations and relative dates" do
    test "a single-unit duration spans number and unit" do
      assert_span("3d", "3d")
    end

    test "a multi-unit duration spans through the last unit" do
      assert_span("3d8h", "3d8h")
    end

    test "a spaced multi-unit duration spans through the last unit" do
      assert_span("3d 8h", "3d 8h")
    end

    test "an ago expression spans through the keyword" do
      assert_span("3d ago", "3d ago")
    end

    test "a from-now expression spans through 'now'" do
      assert_span("3d from now", "3d from now")
    end

    test "a next expression spans from the keyword through the duration" do
      assert_span("next 2w", "next 2w")
    end

    test "a last expression spans from the keyword through the duration" do
      assert_span("last 1d", "last 1d")
    end
  end

  describe "spans that are not a single token" do
    test "a parenthesized expression's span excludes its parentheses" do
      assert_span("(a + b)", "a + b")
    end

    test "a span crosses a line boundary" do
      source = "a > 1\nAND b < 2"
      {:ok, {:logical_and, _left, _right, span}} = parse_spans(source)

      assert span == {{1, 1}, {2, 10}}
    end
  end

  describe "the default parse" do
    test "is byte-identical to an explicit spans: false parse" do
      for source <- @corpus do
        {:ok, tokens} = Lexer.tokenize(source)

        assert Parser.parse(tokens) == Parser.parse(tokens, spans: false),
               "default parse of #{source} diverged from spans: false"
      end
    end

    test "still points a binary operator at its operator token" do
      {:ok, tokens} = Lexer.tokenize("a * true")

      assert {:ok,
              {:arithmetic, :multiply, {:identifier, "a", {1, 1}}, {:literal, true, {1, 5}},
               {1, 3}}} = Parser.parse(tokens)
    end

    test "still points a property access at its dot" do
      {:ok, tokens} = Lexer.tokenize("a.b")

      assert {:ok, {:property_access, {:identifier, "a", {1, 1}}, "b", {1, 2}}} =
               Parser.parse(tokens)
    end

    test "is unaffected by a non-boolean :spans value" do
      {:ok, tokens} = Lexer.tokenize("a * true")

      assert Parser.parse(tokens, spans: :yes) == Parser.parse(tokens)
    end
  end

  describe "the whole corpus" do
    test "gives every node a span whose slice is non-empty and contained in its parent" do
      for source <- @corpus do
        {:ok, ast} = parse_spans(source)
        assert_well_formed(ast, source)
      end
    end

    test "produces the same bare AST as the default parse" do
      for source <- @corpus do
        {:ok, tokens} = Lexer.tokenize(source)
        {:ok, positioned} = Parser.parse(tokens)
        {:ok, spanned} = Parser.parse(tokens, spans: true)

        assert Parser.strip_positions(spanned) == Parser.strip_positions(positioned)
      end
    end
  end

  defp parse_spans(source) do
    {:ok, tokens} = Lexer.tokenize(source)
    Parser.parse(tokens, spans: true)
  end

  defp assert_span(source, expected) do
    {:ok, ast} = parse_spans(source)
    assert slice(source, span_of(ast)) == expected
  end

  defp span_of(node), do: elem(node, tuple_size(node) - 1)

  defp slice(source, span), do: Predicator.SpanSlicing.slice(source, span)

  @node_tags ~w(literal string_literal identifier comparison arithmetic unary membership
                logical_and logical_or logical_not list object function_call bracket_access
                property_access duration relative_date object_key)a

  defp assert_well_formed(node, source, parent_span \\ nil)

  defp assert_well_formed(node, source, parent_span) when is_tuple(node) do
    if elem(node, 0) in @node_tags do
      span = span_of(node)

      assert slice(source, span) != "",
             "#{elem(node, 0)} in #{inspect(source)} has an empty span #{inspect(span)}"

      if parent_span, do: assert_contained(span, parent_span, node, source)

      node |> Tuple.to_list() |> Enum.each(&assert_well_formed(&1, source, span))
    else
      node |> Tuple.to_list() |> Enum.each(&assert_well_formed(&1, source, parent_span))
    end
  end

  defp assert_well_formed(list, source, parent_span) when is_list(list) do
    Enum.each(list, &assert_well_formed(&1, source, parent_span))
  end

  defp assert_well_formed(_other, _source, _parent_span), do: :ok

  defp assert_contained({child_start, child_end}, {parent_start, parent_end}, node, source) do
    assert child_start >= parent_start and child_end <= parent_end,
           "#{elem(node, 0)} in #{inspect(source)} escapes its parent: " <>
             "#{inspect({child_start, child_end})} outside #{inspect({parent_start, parent_end})}"
  end
end
