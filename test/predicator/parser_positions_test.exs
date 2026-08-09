defmodule Predicator.ParserPositionsTest do
  use ExUnit.Case, async: true

  describe "leaf positions" do
    test "integer literal points at its own token" do
      assert {:ok, {:literal, 42, {1, 1}}} = Predicator.parse("42")
    end

    test "float literal" do
      assert {:ok, {:literal, 1.5, {1, 1}}} = Predicator.parse("1.5")
    end

    test "boolean literal" do
      assert {:ok, {:literal, true, {1, 1}}} = Predicator.parse("true")
    end

    test "date literal" do
      assert {:ok, {:literal, %Date{}, {1, 1}}} = Predicator.parse("#2024-01-15#")
    end

    test "datetime literal" do
      assert {:ok, {:literal, %DateTime{}, {1, 1}}} =
               Predicator.parse("#2024-01-15T10:30:00Z#")
    end

    test "string literal carries quote type and position" do
      assert {:ok, {:string_literal, "hi", :double, {1, 1}}} = Predicator.parse(~s("hi"))
      assert {:ok, {:string_literal, "hi", :single, {1, 1}}} = Predicator.parse("'hi'")
    end

    test "identifier" do
      assert {:ok, {:identifier, "score", {1, 1}}} = Predicator.parse("score")
    end

    test "a parenthesized expression keeps the inner node's own position" do
      assert {:ok, {:identifier, "score", {1, 2}}} = Predicator.parse("(score)")
    end
  end

  describe "binary operators point at the operator token" do
    test "each comparison operator" do
      for {source, op, col} <- [
            {"a > 1", :gt, 3},
            {"a < 1", :lt, 3},
            {"a >= 1", :gte, 3},
            {"a <= 1", :lte, 3},
            {"a == 1", :equal_equal, 3},
            {"a != 1", :ne, 3},
            {"a === 1", :strict_eq, 3},
            {"a !== 1", :strict_ne, 3}
          ] do
        assert {:ok, {:comparison, ^op, _left, _right, {1, ^col}}} = Predicator.parse(source)
      end
    end

    test "each arithmetic operator" do
      for {source, op} <- [
            {"a + 1", :add},
            {"a - 1", :subtract},
            {"a * 1", :multiply},
            {"a / 1", :divide},
            {"a % 1", :modulo}
          ] do
        assert {:ok, {:arithmetic, ^op, _left, _right, {1, 3}}} = Predicator.parse(source)
      end
    end

    test "membership operators" do
      assert {:ok, {:membership, :in, _l, _r, {1, 3}}} = Predicator.parse("a in [1]")
      assert {:ok, {:membership, :contains, _l, _r, {1, 3}}} = Predicator.parse("a contains 1")
    end

    test "logical operators, both spellings" do
      assert {:ok, {:logical_and, _l, _r, {1, 7}}} = Predicator.parse("a > 1 AND b < 2")
      assert {:ok, {:logical_and, _l, _r, {1, 7}}} = Predicator.parse("a > 1 && b < 2")
      assert {:ok, {:logical_or, _l, _r, {1, 7}}} = Predicator.parse("a > 1 OR b < 2")
      assert {:ok, {:logical_or, _l, _r, {1, 7}}} = Predicator.parse("a > 1 || b < 2")
    end

    test "the operator's position is not the left operand's" do
      assert {:ok, {:arithmetic, :multiply, {:identifier, "a", {1, 1}}, _right, {1, 3}}} =
               Predicator.parse("a * true")
    end
  end

  describe "unary operators" do
    test "unary minus and bang point at the operator" do
      assert {:ok, {:unary, :minus, {:identifier, "a", {1, 2}}, {1, 1}}} = Predicator.parse("-a")

      assert {:ok,
              {:comparison, :gt, _l, {:unary, :bang, {:identifier, "b", {1, 6}}, {1, 5}}, {1, 3}}} =
               Predicator.parse("a > !b")
    end

    test "logical not points at the NOT keyword" do
      assert {:ok, {:logical_not, _operand, {1, 1}}} = Predicator.parse("NOT a > 1")
    end
  end

  describe "collections" do
    test "list points at its opening bracket, elements at their own tokens" do
      assert {:ok, {:list, [{:identifier, "a", {1, 2}}, {:identifier, "b", {1, 5}}], {1, 1}}} =
               Predicator.parse("[a, b]")
    end

    test "empty list has a position and no children" do
      assert {:ok, {:list, [], {1, 1}}} = Predicator.parse("[]")
    end

    test "object points at its opening brace and keys carry their own positions" do
      assert {:ok,
              {:object, [{{:object_key, "a", :identifier, {1, 2}}, {:literal, 1, {1, 5}}}],
               {1, 1}}} =
               Predicator.parse("{a: 1}")
    end

    test "string object keys carry positions" do
      assert {:ok,
              {:object, [{{:object_key, "a", :double, {1, 2}}, {:literal, 1, {1, 7}}}], {1, 1}}} =
               Predicator.parse(~s({"a": 1}))
    end

    test "an object key carries its quote style" do
      assert {:ok, {:object, [{{:object_key, "a b", :single, {1, 2}}, _v}], {1, 1}}} =
               Predicator.parse("{'a b': 1}")

      assert {:ok, {:object, [{{:object_key, "a b", :double, {1, 2}}, _v}], {1, 1}}} =
               Predicator.parse(~s({"a b": 1}))

      assert {:ok, {:object, [{{:object_key, "a", :identifier, {1, 2}}, _v}], {1, 1}}} =
               Predicator.parse("{a: 1}")
    end

    test "empty object has a position and no children" do
      assert {:ok, {:object, [], {1, 1}}} = Predicator.parse("{}")
    end
  end

  describe "function calls, bracket and property access" do
    test "function call points at its name token" do
      assert {:ok, {:function_call, "len", [{:identifier, "name", {1, 5}}], {1, 1}}} =
               Predicator.parse("len(name)")
    end

    test "qualified function call points at its name token" do
      assert {:ok, {:function_call, "Math.abs", [_arg], {1, 1}}} = Predicator.parse("Math.abs(a)")
    end

    test "empty argument list" do
      assert {:ok, {:function_call, "len", [], {1, 1}}} = Predicator.parse("len()")
    end

    test "a nested call's position does not leak to the outer call" do
      assert {:ok, {:function_call, "len", [{:function_call, "upper", [_arg], {1, 5}}], {1, 1}}} =
               Predicator.parse("len(upper(name))")
    end

    test "bracket access points at the key's first token, one position per link" do
      assert {:ok, {:bracket_access, {:bracket_access, _base, _k0, {1, 3}}, _k1, {1, 6}}} =
               Predicator.parse("a[0][1]")
    end

    test "property access points at the property name" do
      assert {:ok, {:property_access, {:identifier, "user", {1, 1}}, "name", {1, 6}}} =
               Predicator.parse("user.name")
    end

    test "bracket access points at the key's first token, not the key node's own token" do
      assert {:ok, {:bracket_access, _base, {:arithmetic, :add, _l, _r, {1, 5}}, {1, 3}}} =
               Predicator.parse("a[x + 1]")

      assert {:ok, {:bracket_access, _b, {:literal, 1, {1, 4}}, {1, 3}}} =
               Predicator.parse("a[(1)]")
    end

    test "a cast points at the type-name token, not '::' and not the operand" do
      assert {:ok, {:cast, {:identifier, "x", {1, 1}}, "integer", {1, 4}}} =
               Predicator.parse("x::integer")
    end

    test "a chained cast gives the inner and outer casts their own distinct points" do
      assert {:ok,
              {:cast, {:cast, {:string_literal, "a", :double, {1, 1}}, "date", {1, 6}},
               "datetime", {1, 12}}} = Predicator.parse(~s("a"::date::datetime))
    end
  end

  describe "durations and relative dates" do
    test "duration points at its first number" do
      assert {:ok, {:duration, [{3, "d"}, {8, "h"}], {1, 1}}} = Predicator.parse("3d8h")
    end

    test "each relative-date direction points at its direction keyword" do
      assert {:ok, {:relative_date, _d, :ago, {1, 4}}} = Predicator.parse("3d ago")
      assert {:ok, {:relative_date, _d, :future, {1, 4}}} = Predicator.parse("3d from now")
      assert {:ok, {:relative_date, _d, :next, {1, 1}}} = Predicator.parse("next 2w")
      assert {:ok, {:relative_date, _d, :last, {1, 1}}} = Predicator.parse("last 2w")
    end
  end

  describe "multi-line and repeated tokens" do
    test "tokens on the second line report line 2" do
      assert {:ok,
              {:logical_and, _left, {:comparison, :lt, {:identifier, "b", {2, 1}}, _r, {2, 3}},
               {1, 7}}} =
               Predicator.parse("a > 1 AND\nb < 2")
    end

    test "repeated identical tokens do not share a column" do
      assert {:ok,
              {:arithmetic, :add,
               {:arithmetic, :add, {:identifier, "a", {1, 1}}, {:identifier, "a", {1, 5}},
                {1, 3}}, {:identifier, "a", {1, 9}}, {1, 7}}} = Predicator.parse("a + a + a")
    end
  end
end
