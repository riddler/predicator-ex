defmodule Predicator.Integration.SpansTest do
  use ExUnit.Case, async: true

  @corpus [
    "42",
    "'hello'",
    ~s("hello"),
    "#2024-01-15#",
    "score",
    "score > 85",
    "a in [1, 2, 3]",
    "a contains 1",
    "a + 1 * 2 - 3 / 4 % 5",
    "-a",
    "!a",
    "not a",
    "a > 1 and b < 2",
    "a > 1 or b < 2",
    "[a, b, 3]",
    "[]",
    "{a: 1, \"b\": x}",
    "{}",
    "len(upper(name))",
    "f()",
    "a[0][1]",
    "user.name.first",
    "created_at > 3d ago",
    "created_at < 2h from now",
    "(a + b) * c",
    "a > 1 and\nb < 2"
  ]

  @node_tags ~w(literal string_literal identifier comparison arithmetic unary membership
                logical_and logical_or logical_not list object function_call bracket_access
                property_access duration relative_date object_key)a

  describe "source cross-check" do
    test "every node's span slices to the source text it covers" do
      for source <- @corpus do
        {:ok, ast} = Predicator.parse(source, spans: true)
        assert_slices_cleanly(ast, source)
      end
    end

    test "named nodes slice to exactly the text a reader would underline" do
      cases = [
        {"score > 85", "score > 85"},
        {"len(upper(name))", "len(upper(name))"},
        {"a[0][1]", "a[0][1]"},
        {"user.name.first", "user.name.first"},
        {"#2024-01-15# > x", "#2024-01-15# > x"}
      ]

      for {source, expected} <- cases do
        {:ok, ast} = Predicator.parse(source, spans: true)
        assert slice(source, span_of(ast)) == expected
      end
    end

    # Parentheses build no AST node, so no node can claim them without
    # attributing another node's characters to itself. Documented limit.
    test "a span stops at the inner expression, not at the parentheses" do
      source = "(a + b) * c"
      {:ok, {:arithmetic, :multiply, left, _right, outer}} = Predicator.parse(source, spans: true)

      assert slice(source, span_of(left)) == "a + b"
      # The outer span inherits that start, so its slice is unbalanced.
      assert slice(source, outer) == "a + b) * c"
    end

    test "an inner call's span does not leak past its caller's" do
      source = "len(upper(name))"
      {:ok, {:function_call, "len", [inner], outer}} = Predicator.parse(source, spans: true)

      assert slice(source, outer) == "len(upper(name))"
      assert slice(source, span_of(inner)) == "upper(name)"
    end
  end

  describe "instruction-list identity" do
    test "compile_with_spans/1 emits exactly what compile/1 emits" do
      for source <- @corpus do
        assert {:ok, plain} = Predicator.compile(source)
        assert {:ok, spanned, _table} = Predicator.compile_with_spans(source)
        assert plain == spanned, "instruction list diverged for #{inspect(source)}"
      end
    end

    test "the span table is the only difference from compile_with_positions/1" do
      for source <- @corpus do
        assert {:ok, instructions, positions} = Predicator.compile_with_positions(source)
        assert {:ok, ^instructions, spans} = Predicator.compile_with_spans(source)
        assert Map.keys(positions) == Map.keys(spans)
      end
    end
  end

  describe "table completeness" do
    test "every instruction index has a span entry" do
      for source <- @corpus do
        assert {:ok, instructions, spans} = Predicator.compile_with_spans(source)

        assert Map.keys(spans) |> Enum.sort() == Enum.to_list(0..(length(instructions) - 1)),
               "incomplete span table for #{inspect(source)}"
      end
    end

    test "every entry's start precedes or equals its end in reading order" do
      for source <- @corpus do
        assert {:ok, _instructions, spans} = Predicator.compile_with_spans(source)

        for {index, {start, finish}} <- spans do
          assert start <= finish,
                 "instruction #{index} of #{inspect(source)} has a reversed span"
        end
      end
    end
  end

  describe "nesting invariant" do
    test "a child's span is contained in its parent's, for every pair in the corpus" do
      for source <- @corpus do
        {:ok, ast} = Predicator.parse(source, spans: true)
        assert_contained(ast, source, nil)
      end
    end
  end

  describe "runtime cross-check" do
    test "a reported span slices to the failing subexpression" do
      source = "1 + 2 * true"

      assert {:error, error} = Predicator.evaluate(source, %{}, spans: true)
      assert slice(source, error.span) == "2 * true"
    end

    test "a multi-line failure slices across the line boundary" do
      source = "true and\n1 * false"

      assert {:error, error} = Predicator.evaluate(source, %{}, spans: true)
      assert slice(source, error.span) == "1 * false"
    end

    test "an unbound load under on_unbound: :error slices to the variable" do
      source = "missing + 1"
      {:ok, instructions, spans} = Predicator.compile_with_spans(source)

      assert {:error, error} =
               Predicator.evaluate(instructions, %{}, positions: spans, on_unbound: :error)

      assert slice(source, error.span) == "missing"
    end
  end

  defp assert_slices_cleanly(node, source) when is_tuple(node) do
    if elem(node, 0) in @node_tags do
      span = span_of(node)

      refute slice(source, span) == "",
             "#{elem(node, 0)} in #{inspect(source)} has an empty span #{inspect(span)}"
    end

    node |> Tuple.to_list() |> Enum.each(&assert_slices_cleanly(&1, source))
  end

  defp assert_slices_cleanly(list, source) when is_list(list) do
    Enum.each(list, &assert_slices_cleanly(&1, source))
  end

  defp assert_slices_cleanly(_other, _source), do: :ok

  defp assert_contained(node, source, parent) when is_tuple(node) do
    span = if elem(node, 0) in @node_tags, do: span_of(node), else: parent

    if parent && span != parent do
      {child_start, child_end} = span
      {parent_start, parent_end} = parent

      assert child_start >= parent_start and child_end <= parent_end,
             "#{elem(node, 0)} in #{inspect(source)} escapes its parent: " <>
               "#{inspect(span)} outside #{inspect(parent)}"
    end

    node |> Tuple.to_list() |> Enum.each(&assert_contained(&1, source, span))
  end

  defp assert_contained(list, source, parent) when is_list(list) do
    Enum.each(list, &assert_contained(&1, source, parent))
  end

  defp assert_contained(_other, _source, _parent), do: :ok

  defp span_of(node), do: elem(node, tuple_size(node) - 1)

  defp slice(source, span), do: Predicator.SpanSlicing.slice(source, span)
end
