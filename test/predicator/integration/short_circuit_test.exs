defmodule Predicator.Integration.ShortCircuitTest do
  use ExUnit.Case, async: true

  alias Predicator.Evaluator

  describe "the three verified 3.5.0 failures now evaluate" do
    test "AND with an unbound right side no longer raises" do
      assert Predicator.evaluate("false AND score > 5", %{}) == {:ok, false}
    end

    test "AND with a missing nested left property no longer raises" do
      # `user` is bound but has no `age` key, so `user.age` evaluates to
      # :undefined via access/2's missing-key fallback, not an unbound root -
      # px-8um.4 made the unbound-root case (bare `missing_var`) its own
      # UndefinedVariableError, so this test uses the bound-root shape that
      # stays :undefined to keep exercising the AND short-circuit itself.
      assert Predicator.evaluate("user.age > 18 AND user.name == 'x'", %{"user" => %{}}) ==
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

    test "false AND an unbound root on the right side does not raise" do
      # Since px-8um.4, evaluating a bare unbound root anywhere in a reached
      # expression is UndefinedVariableError. Short-circuiting means the
      # right side is never reached here, so no error - a stronger proof the
      # skipped side is truly skipped, not merely tolerated.
      assert Predicator.evaluate("false AND missing_var", %{}) == {:ok, false}
    end

    test "true OR an unbound root on the right side does not raise" do
      assert Predicator.evaluate("true OR missing_var", %{}) == {:ok, true}
    end
  end

  describe "the ECMAScript-aligned :undefined asymmetry" do
    # Each case uses a bound `user` root with a missing nested key, so the
    # left/right operand evaluates to :undefined (not an unbound-root error)
    # while still exercising the asymmetry between AND and OR.
    setup do
      %{context: %{"user" => %{}}}
    end

    test "user.missing OR true takes the right side's value", %{context: context} do
      assert Predicator.evaluate("user.missing OR true", context) == {:ok, true}
    end

    test "user.missing AND true short-circuits to :undefined", %{context: context} do
      assert Predicator.evaluate("user.missing AND true", context) == {:ok, :undefined}
    end

    test "true AND user.missing falls through to the right side's :undefined", %{
      context: context
    } do
      assert Predicator.evaluate("true AND user.missing", context) == {:ok, :undefined}
    end

    test "false OR user.missing falls through to the right side's :undefined", %{
      context: context
    } do
      assert Predicator.evaluate("false OR user.missing", context) == {:ok, :undefined}
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
