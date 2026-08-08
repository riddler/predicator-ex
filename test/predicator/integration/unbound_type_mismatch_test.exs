defmodule Predicator.Integration.UnboundTypeMismatchTest do
  use ExUnit.Case, async: true

  alias Predicator.Errors.{TypeMismatchError, UndefinedVariableError}

  # Since px-1e1 the rewritten error carries the position the evaluator
  # recorded at the variable's own load, not the rejecting operator's.
  defp unbound_at(name, position) do
    {:error, Predicator.Errors.put_position(UndefinedVariableError.new(name), position)}
  end

  describe "opcodes that reject an :undefined operand name the unbound root (px-8um.7)" do
    test "logical not" do
      assert Predicator.evaluate("not unbound", %{}) == unbound_at("unbound", {1, 5})
    end

    test "bang, which compiles to the same not opcode" do
      assert Predicator.evaluate("!unbound", %{}) == unbound_at("unbound", {1, 2})
    end

    test "unary minus" do
      assert Predicator.evaluate("-unbound", %{}) == unbound_at("unbound", {1, 2})
    end

    # No positions: table is passed for a hand-built instruction list, so this
    # doubles as the no-table regression test (px-1e1).
    test "unary_bang, reachable only from a hand-written instruction list" do
      assert Predicator.evaluate([["load", "unbound"], ["unary_bang"]], %{}) ==
               {:error, UndefinedVariableError.new("unbound")}
    end

    for {op, expression, position} <- [
          {:add, "unbound + 1", {1, 1}},
          {:subtract, "unbound - 1", {1, 1}},
          {:multiply, "unbound * 1", {1, 1}},
          {:divide, "unbound / 1", {1, 1}},
          {:modulo, "unbound % 1", {1, 1}}
        ] do
      test "arithmetic #{op}" do
        assert Predicator.evaluate(unquote(expression), %{}) ==
                 unbound_at("unbound", unquote(Macro.escape(position)))
      end
    end

    test "the unbound operand on the right side is reported too" do
      assert Predicator.evaluate("1 + unbound", %{}) == unbound_at("unbound", {1, 5})
    end

    # No positions: table is passed, so this doubles as a no-table
    # regression test (px-1e1). Previously carried by the legacy and/or
    # opcodes, which px-tbv.9 retired at ISA v3 - a hand-authored arithmetic
    # list keeps both properties (no table, rejects :undefined) that made
    # and/or useful here in the first place.
    test "hand-written arithmetic list, no compiler-produced position table" do
      assert Predicator.evaluate([["load", "a"], ["load", "b"], ["add"]], %{"a" => 1}) ==
               {:error, UndefinedVariableError.new("b")}
    end
  end

  describe "a bound-to-:undefined operand keeps its TypeMismatchError" do
    test "not, against a key bound to :undefined" do
      assert {:error, %TypeMismatchError{operation: :logical_not, got: :undefined}} =
               Predicator.evaluate("not b", %{"b" => :undefined})
    end

    test "arithmetic, against a key bound to :undefined" do
      assert {:error, %TypeMismatchError{operation: :add}} =
               Predicator.evaluate("b + 1", %{"b" => :undefined})
    end

    test "a missing nested path on a bound root is not an unbound root" do
      assert {:error, %TypeMismatchError{operation: :logical_not}} =
               Predicator.evaluate("not user.nope", %{"user" => %{}})
    end
  end

  describe "an ordinary type mismatch is untouched" do
    test "no :undefined operand, no rewrite" do
      assert {:error, %TypeMismatchError{operation: :multiply}} =
               Predicator.evaluate("name * 5", %{"name" => "Alice"})
    end

    test "not against a bound non-boolean" do
      assert {:error, %TypeMismatchError{operation: :logical_not, got: :integer}} =
               Predicator.evaluate("not 5", %{})
    end
  end

  describe "in/contains already propagate :undefined and need no rewrite" do
    test "an unbound left operand of in" do
      assert Predicator.evaluate("unbound in [1, 2]", %{}) == unbound_at("unbound", {1, 1})
    end

    test "an unbound right operand of in, which is not even a list" do
      assert Predicator.evaluate("1 in unbound", %{}) == unbound_at("unbound", {1, 6})
    end

    test "an unbound left operand of contains, which is not even a list" do
      assert Predicator.evaluate("unbound contains 1", %{}) == unbound_at("unbound", {1, 1})
    end

    test "an unbound right operand of contains" do
      assert Predicator.evaluate("[1, 2] contains unbound", %{}) ==
               unbound_at("unbound", {1, 17})
    end
  end

  describe "the low-level Evaluator API is unchanged" do
    test "Evaluator.evaluate/2 still returns the bare TypeMismatchError" do
      assert {:error, %TypeMismatchError{operation: :logical_not, got: :undefined}} =
               Predicator.Evaluator.evaluate([["load", "unbound"], ["not"]], %{})
    end
  end
end
