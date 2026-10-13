defmodule Predicator.ASTTest do
  use ExUnit.Case, async: true

  alias Predicator.AST

  doctest Predicator.AST

  # The kind of every node, in the order the pre-order walk reaches it.
  defp pre_tags(ast),
    do: ast |> AST.reduce([], fn n, acc -> [elem(n, 0) | acc] end) |> Enum.reverse()

  defp expr!(source) do
    {:ok, ast} = Predicator.parse(source)
    ast
  end

  defp program!(source) do
    {:ok, ast} = Predicator.parse_program(source)
    ast
  end

  describe "children in source order" do
    test "binary nodes visit left then right" do
      for source <- ["a > b", "a + b", "a in b", "a and b", "a or b"] do
        names =
          source
          |> expr!()
          |> AST.reduce([], fn
            {:identifier, name, _pos}, acc -> [name | acc]
            _other, acc -> acc
          end)
          |> Enum.reverse()

        assert names == ["a", "b"], source
      end
    end

    test "unary, not, cast and property access walk their one child" do
      assert pre_tags(expr!("-a")) == [:unary, :identifier]
      assert pre_tags(expr!("not a")) == [:logical_not, :identifier]
      assert pre_tags(expr!("a::string")) == [:cast, :identifier]
      assert pre_tags(expr!("a.b")) == [:property_access, :identifier]
    end

    test "bracket access visits the object then the key" do
      assert pre_tags(expr!("a[b + 1]")) ==
               [:bracket_access, :identifier, :arithmetic, :identifier, :literal]
    end

    test "list elements and call arguments in order" do
      assert pre_tags(expr!("[a, 1, b]")) == [:list, :identifier, :literal, :identifier]
      assert pre_tags(expr!("f(a, 1, b)")) == [:function_call, :identifier, :literal, :identifier]
    end

    test "leaf nodes have no children" do
      assert pre_tags(expr!("1")) == [:literal]
      assert pre_tags(expr!("'x'")) == [:string_literal]
      assert pre_tags(expr!("a")) == [:identifier]
      assert pre_tags(expr!("3d8h")) == [:duration]
    end

    test "a relative date walks its duration as a child" do
      assert pre_tags(expr!("3d ago")) == [:relative_date, :duration]
    end

    test "an object visits entry values in order and never the keys" do
      ast = expr!("{b: x, 'a': y + 1}")

      assert pre_tags(ast) == [:object, :identifier, :arithmetic, :identifier, :literal]

      {_ast, keys_seen} =
        AST.prewalk(ast, 0, fn
          {:object_key, _name, _style, _pos} = node, n -> {node, n + 1}
          node, n -> {node, n}
        end)

      assert keys_seen == 0
    end

    test "an object's keys pass through a rewrite untouched" do
      ast = expr!("{b: x}")

      {{:object, [{key, _value}], _pos}, _acc} =
        AST.postwalk(ast, :ok, fn
          {:identifier, _name, pos}, acc -> {{:literal, 1, pos}, acc}
          node, acc -> {node, acc}
        end)

      assert {:object_key, "b", :identifier, {1, 2}} = key
    end

    test "an assignment visits its location chain then its value" do
      assert pre_tags(program!("a.b[c] = d")) ==
               [
                 :program,
                 :assignment,
                 :bracket_access,
                 :property_access,
                 :identifier,
                 :identifier,
                 :identifier
               ]
    end

    test "if, else if and while walk condition, blocks and nested statements" do
      program = program!("if a { b = 1 } else if c { d = 2 } else { e = 3 }; while f { g = 4 }")

      names =
        AST.reduce(program, [], fn
          {:identifier, name, _pos}, acc -> [name | acc]
          _other, acc -> acc
        end)
        |> Enum.reverse()

      assert names == ~w(a b c d e f g)

      assert pre_tags(program!("if a { b }")) == [:program, :if, :identifier, :block, :identifier]

      assert pre_tags(program!("while a { b }")) == [
               :program,
               :while,
               :identifier,
               :block,
               :identifier
             ]
    end

    test "an if with no else carries nil through" do
      assert {{:program, [{:if, _cond, _then, nil, _if_pos}], _prog_pos}, _count} =
               AST.prewalk(program!("if a { b }"), 0, fn n, acc -> {n, acc + 1} end)
    end

    test "an empty else block stays distinct from no else" do
      program = program!("if a { b } else { }")
      assert pre_tags(program) == [:program, :if, :identifier, :block, :identifier, :block]
    end

    test "a bare block and a bare statement are walkable roots" do
      assert pre_tags({:block, [{:identifier, "a", nil}], nil}) == [:block, :identifier]
    end
  end

  describe "prewalk/3 and postwalk/3 order" do
    test "prewalk visits a parent before its children, postwalk after" do
      ast = expr!("a + 1 > b")
      collect = fn node, acc -> {node, [elem(node, 0) | acc]} end

      {_ast, pre} = AST.prewalk(ast, [], collect)
      {_ast, post} = AST.postwalk(ast, [], collect)

      assert Enum.reverse(pre) == [:comparison, :arithmetic, :identifier, :literal, :identifier]
      assert Enum.reverse(post) == [:identifier, :literal, :arithmetic, :identifier, :comparison]
    end

    test "prewalk walks the children of the replacement node" do
      ast = expr!("a")
      replacement = {:logical_not, {:identifier, "z", nil}, nil}

      {out, seen} =
        AST.prewalk(ast, [], fn
          {:identifier, "a", _pos}, acc -> {replacement, ["a" | acc]}
          {:identifier, name, _pos} = n, acc -> {n, [name | acc]}
          n, acc -> {n, acc}
        end)

      assert out == replacement
      assert Enum.reverse(seen) == ["a", "z"]
    end

    test "postwalk hands the callback the rebuilt children and does not re-walk its result" do
      ast = expr!("a + b")

      {out, calls} =
        AST.postwalk(ast, 0, fn
          {:identifier, _name, pos}, n ->
            {{:literal, 1, pos}, n + 1}

          {:arithmetic, :add, {:literal, 1, _left_pos}, {:literal, 1, _right_pos}, pos}, n ->
            {{:literal, 2, pos}, n + 1}

          n, acc ->
            {n, acc}
        end)

      assert {:literal, 2, {1, 3}} = out
      assert calls == 3
    end

    test "an identity walk returns an equal tree and the position slot untouched" do
      for source <- ["a > 1 and f(b, [1, 2]) or {k: c.d[e]}::string", "3d ago in x", "-a + 2"] do
        ast = expr!(source)
        assert {^ast, _acc} = AST.prewalk(ast, 0, &{&1, &2 + 1})
        assert {^ast, _acc} = AST.postwalk(ast, 0, &{&1, &2 + 1})
      end

      {:ok, spanned} = Predicator.parse("a > 1", spans: true)
      assert {^spanned, _acc} = AST.prewalk(spanned, 0, &{&1, &2})
    end

    test "a position can be rewritten by the callback and a nil position walks" do
      node = {:comparison, :gt, {:identifier, "a", nil}, {:literal, 1, nil}, nil}
      assert AST.reduce(node, 0, fn _node, n -> n + 1 end) == 3
    end
  end

  describe "reduce/3" do
    test "threads the accumulator through every node, pre-order" do
      assert AST.reduce(expr!("f(a, b)"), 0, fn _node, n -> n + 1 end) == 3
    end

    test "walks a program's statements in order" do
      assert pre_tags(program!("a = 1; b")) == [
               :program,
               :assignment,
               :identifier,
               :literal,
               :identifier
             ]
    end
  end

  test "an unknown node kind raises" do
    assert_raise FunctionClauseError, fn ->
      AST.reduce({:no_such_kind, 1, nil}, 0, fn _node, n -> n end)
    end
  end
end
