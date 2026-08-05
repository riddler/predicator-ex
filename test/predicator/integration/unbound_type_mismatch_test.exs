defmodule Predicator.Integration.UnboundTypeMismatchTest do
  use ExUnit.Case, async: true

  alias Predicator.Errors.{TypeMismatchError, UndefinedVariableError}

  describe "opcodes that reject an :undefined operand name the unbound root (px-8um.7)" do
    test "logical not" do
      assert Predicator.evaluate("not unbound", %{}) ==
               {:error, UndefinedVariableError.new("unbound")}
    end

    test "bang, which compiles to the same not opcode" do
      assert Predicator.evaluate("!unbound", %{}) ==
               {:error, UndefinedVariableError.new("unbound")}
    end

    test "unary minus" do
      assert Predicator.evaluate("-unbound", %{}) ==
               {:error, UndefinedVariableError.new("unbound")}
    end

    test "unary_bang, reachable only from a hand-written instruction list" do
      assert Predicator.evaluate([["load", "unbound"], ["unary_bang"]], %{}) ==
               {:error, UndefinedVariableError.new("unbound")}
    end

    for {op, expression} <- [
          add: "unbound + 1",
          subtract: "unbound - 1",
          multiply: "unbound * 1",
          divide: "unbound / 1",
          modulo: "unbound % 1"
        ] do
      test "arithmetic #{op}" do
        assert Predicator.evaluate(unquote(expression), %{}) ==
                 {:error, UndefinedVariableError.new("unbound")}
      end
    end

    test "the unbound operand on the right side is reported too" do
      assert Predicator.evaluate("1 + unbound", %{}) ==
               {:error, UndefinedVariableError.new("unbound")}
    end

    test "legacy [\"and\"], which the compiler no longer emits (px-e3g.1)" do
      assert Predicator.evaluate([["load", "a"], ["load", "b"], ["and"]], %{"a" => false}) ==
               {:error, UndefinedVariableError.new("b")}
    end

    test "legacy [\"or\"], which the compiler no longer emits (px-e3g.1)" do
      assert Predicator.evaluate([["load", "a"], ["load", "b"], ["or"]], %{"a" => true}) ==
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
      assert Predicator.evaluate("unbound in [1, 2]", %{}) ==
               {:error, UndefinedVariableError.new("unbound")}
    end

    test "an unbound right operand of in, which is not even a list" do
      assert Predicator.evaluate("1 in unbound", %{}) ==
               {:error, UndefinedVariableError.new("unbound")}
    end

    test "an unbound left operand of contains, which is not even a list" do
      assert Predicator.evaluate("unbound contains 1", %{}) ==
               {:error, UndefinedVariableError.new("unbound")}
    end

    test "an unbound right operand of contains" do
      assert Predicator.evaluate("[1, 2] contains unbound", %{}) ==
               {:error, UndefinedVariableError.new("unbound")}
    end
  end

  describe "the low-level Evaluator API is unchanged" do
    test "Evaluator.evaluate/2 still returns the bare TypeMismatchError" do
      assert {:error, %TypeMismatchError{operation: :logical_not, got: :undefined}} =
               Predicator.Evaluator.evaluate([["load", "unbound"], ["not"]], %{})
    end
  end
end
