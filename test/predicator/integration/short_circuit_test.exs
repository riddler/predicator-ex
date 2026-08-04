defmodule Predicator.Integration.ShortCircuitTest do
  use ExUnit.Case, async: true

  alias Predicator.Evaluator

  describe "the three verified 3.5.0 failures now evaluate" do
    test "AND with an unbound right side no longer raises" do
      assert Predicator.evaluate("false AND score > 5", %{}) == {:ok, false}
    end

    test "AND with an unbound left property no longer raises" do
      assert Predicator.evaluate("user.age > 18 AND user.name == 'x'", %{}) ==
               {:ok, :undefined}
    end

    test "OR skips a division error on its right side" do
      assert Predicator.evaluate("true OR (1 / 0) > 1", %{}) == {:ok, true}
    end
  end

  describe "the skipped side is provably never evaluated" do
    test "false AND boom() does not call boom" do
      functions = %{"boom" => {0, fn _args, _context -> raise "should not be called" end}}
      assert Predicator.evaluate("false AND boom()", %{}, functions: functions) == {:ok, false}
    end

    test "true OR boom() does not call boom" do
      functions = %{"boom" => {0, fn _args, _context -> raise "should not be called" end}}
      assert Predicator.evaluate("true OR boom()", %{}, functions: functions) == {:ok, true}
    end
  end

  describe "the ECMAScript-aligned :undefined asymmetry" do
    test "missing_var OR true takes the right side's value" do
      assert Predicator.evaluate("missing_var OR true", %{}) == {:ok, true}
    end

    test "missing_var AND true short-circuits to :undefined" do
      assert Predicator.evaluate("missing_var AND true", %{}) == {:ok, :undefined}
    end

    test "true AND missing_var falls through to the right side's :undefined" do
      assert Predicator.evaluate("true AND missing_var", %{}) == {:ok, :undefined}
    end

    test "false OR missing_var falls through to the right side's :undefined" do
      assert Predicator.evaluate("false OR missing_var", %{}) == {:ok, :undefined}
    end
  end

  describe "type validation is preserved, not coerced" do
    test "a non-boolean, non-undefined left side is a type mismatch" do
      assert {:error, %Predicator.Errors.TypeMismatchError{}} =
               Predicator.evaluate("42 AND true", %{})
    end
  end

  describe "old compiled artifacts still evaluate" do
    test "a hand-written [\"and\"] instruction list still works" do
      assert Evaluator.evaluate([["lit", false], ["lit", true], ["and"]], %{}) == false
    end
  end

  describe "the compiler no longer emits and/or" do
    test "compile/1 emits jump opcodes instead of and/or" do
      {:ok, instructions} = Predicator.compile("a AND b OR c")
      refute Enum.any?(instructions, &(&1 in [["and"], ["or"]]))
    end
  end
end
