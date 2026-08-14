defmodule Predicator.EvaluatorPositionsTest do
  use ExUnit.Case, async: true

  alias Predicator.Evaluator

  defp error_for(expression, context \\ %{}, opts \\ []) do
    {:ok, compiled} = Predicator.compile_with_positions(expression)

    assert {:error, error} =
             Predicator.evaluate(
               compiled.instructions,
               context,
               Keyword.put_new(opts, :positions, compiled.positions)
             )

    error
  end

  describe "positions attached to runtime errors" do
    test "a type mismatch reports the operator's position" do
      assert error_for("a * true", %{"a" => 1}).position == {1, 3}
    end

    test "division by zero reports the operator's position" do
      assert error_for("10 / 0").position == {1, 4}
    end

    test "modulo by zero reports the operator's position" do
      assert error_for("10 % 0").position == {1, 4}
    end

    test "a unary type mismatch reports the operator's position" do
      assert error_for("-name", %{"name" => "text"}).position == {1, 1}
    end

    test "a function call error reports the call's position" do
      assert error_for("len(1)").position == {1, 1}
    end

    test "an unknown function reports the call's position" do
      assert error_for("nope(1)").position == {1, 1}
    end

    # Since px-1e1 the evaluator records each unbound load's own location, so the
    # UndefinedVariableError that Predicator.evaluate/3 builds after the run points
    # at the variable - not at the operator that rejected its :undefined, and not
    # at nothing.
    test "an unbound load rejected by an operator reports the variable's position" do
      error = error_for("1 + missing")

      assert %Predicator.Errors.UndefinedVariableError{variable: "missing"} = error
      assert error.position == {1, 5}
    end

    test "an UndefinedVariableError from a bare load reports the load's position" do
      assert {:error, error} = Predicator.evaluate("missing", %{})

      assert error.variable == "missing"
      assert error.position == {1, 1}
    end

    test "an instruction-list caller with no positions table keeps position: nil" do
      assert {:error, error} = Predicator.evaluate([["load", "missing"]], %{})

      assert error.variable == "missing"
      assert error.position == nil
      assert error.span == nil
    end

    test "a multi-line expression reports the failing line" do
      assert error_for("1 +\n2 * true").position == {2, 3}
    end

    test "a repeated operator reports the one that actually failed" do
      assert error_for("a * 2 * true", %{"a" => 1}).position == {1, 7}
    end
  end

  describe "short circuiting" do
    test "an error in an executed branch reports that branch's position" do
      assert error_for("true and 1 * false").position == {1, 12}
    end

    test "a skipped branch's error never happens" do
      assert Predicator.evaluate("false and 1 * false") == {:ok, false}
    end
  end

  describe "tables that do not cover the failure" do
    test "an empty table leaves the position nil" do
      assert error_for("a * true", %{"a" => 1}, positions: %{}).position == nil
    end

    test "a partial table leaves uncovered indices nil" do
      instructions = [["lit", 1], ["lit", true], ["multiply"]]

      assert {:error, error} =
               Predicator.evaluate(instructions, %{}, positions: %{0 => {1, 1}})

      assert error.position == nil
    end

    test "an instruction-list caller who passes no table sees nil" do
      assert {:error, error} =
               Predicator.evaluate([["lit", 1], ["lit", true], ["multiply"]], %{})

      assert error.position == nil
    end
  end

  describe "errors that belong to no instruction" do
    test "an unknown instruction is still positioned when the table covers it" do
      assert {:error, error} =
               Predicator.evaluate([["lit", 1], ["bogus"]], %{}, positions: %{1 => {1, 5}})

      assert error.position == {1, 5}
    end

    test "insufficient operands is positioned from the failing instruction" do
      assert {:error, error} =
               Predicator.evaluate([["lit", 1], ["multiply"]], %{}, positions: %{1 => {1, 3}})

      assert error.position == {1, 3}
    end

    test "an empty-stack completion has no position" do
      assert {:error, error} = Evaluator.evaluate([], %{}, positions: %{0 => {1, 1}})

      assert error.reason == "empty_stack"
      assert error.position == nil
    end
  end

  describe "Evaluator.evaluate/3" do
    test "accepts a :positions option" do
      assert {:error, error} =
               Evaluator.evaluate([["lit", 1], ["lit", true], ["multiply"]], %{},
                 positions: %{2 => {4, 2}}
               )

      assert error.position == {4, 2}
    end

    test "defaults to an empty table" do
      assert {:error, error} = Evaluator.evaluate([["lit", 1], ["lit", true], ["multiply"]], %{})

      assert error.position == nil
    end
  end

  describe "spans attached to runtime errors" do
    defp error_for_spans(expression, context \\ %{}, opts \\ []) do
      {:ok, compiled} = Predicator.compile_with_spans(expression)

      assert {:error, error} =
               Predicator.evaluate(
                 compiled.instructions,
                 context,
                 Keyword.put_new(opts, :positions, compiled.positions)
               )

      error
    end

    test "a type mismatch carries the span and the span's start" do
      error = error_for_spans("a * true", %{"a" => 1})

      assert error.span == {{1, 1}, {1, 9}}
      assert error.position == {1, 1}
    end

    test "a multi-line failure spans both lines" do
      error = error_for_spans("1 +\n2 * true")

      assert error.span == {{2, 1}, {2, 9}}
      assert error.position == {2, 1}
    end

    test "an uncovered index leaves both fields nil" do
      instructions = [["lit", 1], ["lit", true], ["multiply"]]

      assert {:error, error} =
               Predicator.evaluate(instructions, %{}, positions: %{0 => {{1, 1}, {1, 2}}})

      assert error.span == nil
      assert error.position == nil
    end

    test "the on_unbound: :error load site reports the variable's own span" do
      {:ok, compiled} = Predicator.compile_with_spans("missing + 1")

      assert {:error, error} =
               Predicator.evaluate(compiled.instructions, %{},
                 positions: compiled.positions,
                 on_unbound: :error
               )

      assert %Predicator.Errors.UndefinedVariableError{variable: "missing"} = error
      assert error.span == {{1, 1}, {1, 8}}
      assert error.position == {1, 1}
    end

    test "a spans-compiled program's runtime error carries a span, alongside its position" do
      {:ok, compiled} = Predicator.compile_program_with_spans("x = 1; missing + 1")

      assert {:error, error, _ctx} = Predicator.execute(compiled, %{})

      assert %Predicator.Errors.UndefinedVariableError{variable: "missing"} = error
      assert error.span == {{1, 8}, {1, 15}}
      assert error.position == {1, 8}
    end

    test "the same program compiled with positions only yields a nil span" do
      {:ok, compiled} = Predicator.compile_program_with_positions("x = 1; missing + 1")

      assert {:error, error, _ctx} = Predicator.execute(compiled, %{})

      assert %Predicator.Errors.UndefinedVariableError{variable: "missing"} = error
      assert error.span == nil
      assert error.position == {1, 8}
    end
  end

  describe "messages are unchanged" do
    test "a positioned error renders the same message as an unpositioned one" do
      positioned = error_for("a * true", %{"a" => 1})

      assert {:error, plain} =
               Predicator.evaluate([["load", "a"], ["lit", true], ["multiply"]], %{"a" => 1})

      assert positioned.message == plain.message
      assert %{positioned | position: nil} == plain
    end
  end
end
