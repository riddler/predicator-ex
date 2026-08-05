defmodule Predicator.ParserNormalizationTest do
  use ExUnit.Case, async: true

  alias Predicator.Parser

  @corpus [
    "42",
    ~s("hello"),
    "'hello'",
    "score",
    "a > 1",
    "a + 1 * 2",
    "-a",
    "a in [1, 2]",
    "a > 1 AND b < 2",
    "a > 1 OR b < 2",
    "NOT a",
    "[a, b, 3]",
    "[]",
    "{a: 1, \"b\": x}",
    "{'c d': 1}",
    "{}",
    "len(upper(name))",
    "a[0][1]",
    "user.name.first",
    "3d8h",
    "3d ago",
    "next 2w"
  ]

  describe "strip_positions/1" do
    test "removes positions from every node type in the corpus" do
      for source <- @corpus do
        {:ok, ast} = Predicator.parse(source)
        stripped = Parser.strip_positions(ast)

        refute has_position?(stripped), "#{source} kept a position: #{inspect(stripped)}"
      end
    end

    test "is idempotent" do
      for source <- @corpus do
        {:ok, ast} = Predicator.parse(source)
        stripped = Parser.strip_positions(ast)

        assert Parser.strip_positions(stripped) == stripped
      end
    end

    test "passes an unrecognized node through unchanged" do
      assert Parser.strip_positions({:no_such_node, 1, 2, 3}) == {:no_such_node, 1, 2, 3}
      assert Parser.strip_positions(:not_a_node) == :not_a_node
    end

    test "leaves an already position-free string literal alone" do
      assert Parser.strip_positions({:string_literal, "a", :double}) ==
               {:string_literal, "a", :double}
    end

    test "recurses into a position-free container holding positioned children" do
      mixed = {:list, [{:literal, 1, {1, 2}}, {:identifier, "a", {1, 5}}]}
      assert Parser.strip_positions(mixed) == {:list, [{:literal, 1}, {:identifier, "a"}]}
    end

    test "recurses into both halves of an object entry" do
      mixed = {:object, [{{:object_key, "k", :identifier, {1, 2}}, {:literal, 1, {1, 5}}}]}
      assert Parser.strip_positions(mixed) == {:object, [{{:identifier, "k"}, {:literal, 1}}]}
    end

    test "strips an object key back to the 3.6 shape, discarding its style" do
      for style <- [:double, :single] do
        assert Parser.strip_positions(
                 {:object, [{{:object_key, "k", style, {1, 2}}, {:literal, 1}}]}
               ) ==
                 {:object, [{{:string_literal, "k"}, {:literal, 1}}]}
      end
    end

    test "strips an already-legacy object key idempotently" do
      legacy = {:object, [{{:string_literal, "k", {1, 2}}, {:literal, 1}}]}

      assert Parser.strip_positions(legacy) ==
               {:object, [{{:string_literal, "k"}, {:literal, 1}}]}
    end

    test "recurses into function-call arguments" do
      mixed = {:function_call, "len", [{:identifier, "a", {1, 5}}]}
      assert Parser.strip_positions(mixed) == {:function_call, "len", [{:identifier, "a"}]}
    end
  end

  describe "ensure_positions/1" do
    test "round-trips a parsed AST to the same shape with nil positions" do
      for source <- @corpus do
        {:ok, ast} = Predicator.parse(source)
        stripped = Parser.strip_positions(ast)
        restored = Parser.ensure_positions(stripped)

        assert Parser.strip_positions(restored) == stripped
        refute has_position?(restored), "#{source} kept a real position: #{inspect(restored)}"
      end
    end

    test "leaves a positioned AST unchanged" do
      for source <- @corpus do
        {:ok, ast} = Predicator.parse(source)
        assert Parser.ensure_positions(ast) == ast
      end
    end

    test "is idempotent" do
      ast = Parser.ensure_positions({:comparison, :gt, {:identifier, "a"}, {:literal, 1}})
      assert Parser.ensure_positions(ast) == ast
    end

    test "fills only the gaps in a mixed AST" do
      mixed = {:comparison, :gt, {:identifier, "a", {1, 1}}, {:literal, 1}, {1, 3}}

      assert Parser.ensure_positions(mixed) ==
               {:comparison, :gt, {:identifier, "a", {1, 1}}, {:literal, 1, nil}, {1, 3}}
    end

    test "distinguishes an object-key string literal from an expression one by position" do
      assert Parser.ensure_positions({:string_literal, "a", :double}) ==
               {:string_literal, "a", :double, nil}

      assert Parser.ensure_positions({:object, [{{:string_literal, "a"}, {:literal, 1}}]}) ==
               {:object, [{{:object_key, "a", :double, nil}, {:literal, 1, nil}}], nil}
    end

    test "lifts every pre-4.0 object key shape" do
      for {legacy, expected} <- [
            {{:identifier, "k"}, {:object_key, "k", :identifier, nil}},
            {{:identifier, "k", {1, 2}}, {:object_key, "k", :identifier, {1, 2}}},
            {{:string_literal, "k"}, {:object_key, "k", :double, nil}},
            {{:string_literal, "k", {1, 2}}, {:object_key, "k", :double, {1, 2}}},
            {{:object_key, "k", :single}, {:object_key, "k", :single, nil}}
          ] do
        assert Parser.ensure_positions({:object, [{legacy, {:literal, 1}}]}) ==
                 {:object, [{expected, {:literal, 1, nil}}], nil}
      end
    end

    test "passes an unrecognized object key through unchanged" do
      assert Parser.ensure_positions({:object, [{:not_a_key, {:literal, 1}}]}) ==
               {:object, [{:not_a_key, {:literal, 1, nil}}], nil}
    end

    test "passes an unrecognized node through unchanged" do
      assert Parser.ensure_positions({:no_such_node, 1}) == {:no_such_node, 1}
      assert Parser.ensure_positions(:not_a_node) == :not_a_node
    end

    test "recurses into list elements, object entries, and call arguments" do
      assert Parser.ensure_positions({:list, [{:literal, 1}]}) ==
               {:list, [{:literal, 1, nil}], nil}

      assert Parser.ensure_positions({:object, [{{:identifier, "k"}, {:literal, 1}}]}) ==
               {:object, [{{:object_key, "k", :identifier, nil}, {:literal, 1, nil}}], nil}

      assert Parser.ensure_positions({:function_call, "len", [{:identifier, "a"}]}) ==
               {:function_call, "len", [{:identifier, "a", nil}], nil}
    end
  end

  describe "spanned trees" do
    test "strip_positions/1 yields the same bare AST as for a positioned tree" do
      for source <- @corpus do
        {:ok, tokens} = Predicator.Lexer.tokenize(source)
        {:ok, positioned} = Parser.parse(tokens)
        {:ok, spanned} = Parser.parse(tokens, spans: true)

        assert Parser.strip_positions(spanned) == Parser.strip_positions(positioned)
        refute has_position?(Parser.strip_positions(spanned))
      end
    end

    test "ensure_positions/1 leaves a spanned tree unchanged" do
      for source <- @corpus do
        {:ok, tokens} = Predicator.Lexer.tokenize(source)
        {:ok, spanned} = Parser.parse(tokens, spans: true)

        assert Parser.ensure_positions(spanned) == spanned
      end
    end

    test "a spanned object key round-trips through both normalizers" do
      {:ok, tokens} = Predicator.Lexer.tokenize(~s({a: 1, "b": 2}))
      {:ok, spanned} = Parser.parse(tokens, spans: true)

      assert Parser.strip_positions(spanned) ==
               {:object,
                [{{:identifier, "a"}, {:literal, 1}}, {{:string_literal, "b"}, {:literal, 2}}]}

      assert Parser.ensure_positions(spanned) == spanned
    end
  end

  # A `{line, column}` position is the only two-integer tuple the AST contains -
  # duration units are `{integer, binary}` and object entries are node pairs.
  defp has_position?({line, column}) when is_integer(line) and is_integer(column), do: true

  defp has_position?(node) when is_tuple(node) do
    node |> Tuple.to_list() |> Enum.any?(&has_position?/1)
  end

  defp has_position?(list) when is_list(list), do: Enum.any?(list, &has_position?/1)
  defp has_position?(_other), do: false
end
