defmodule Predicator.Integration.WhileExecutionTest do
  use ExUnit.Case, async: true

  alias Predicator.Errors.{EvaluationError, TypeMismatchError}

  describe "Predicator.execute/2 end to end - while (ADR-0013, px-3so.4 Phase 2)" do
    test "a counted loop reaches its exit condition" do
      assert {:ok, ctx} = Predicator.execute("i = 0; while i < 3 { i = i + 1 }", %{})
      assert ctx.data == %{"i" => 3}
    end

    test "a condition false on entry runs the body zero times" do
      assert {:ok, ctx} = Predicator.execute("i = 5; while i < 3 { i = i + 1 }", %{})
      assert ctx.data == %{"i" => 5}
    end

    test "a variable written by the loop is readable after it - the flat scope ADR-0013 requires" do
      assert {:ok, ctx} = Predicator.execute("i = 0; while i < 3 { i = i + 1 }; j = i + 1", %{})
      assert ctx.data == %{"i" => 3, "j" => 4}
    end

    test "a non-boolean condition is a TypeMismatchError naming pop_jump_if_falsy" do
      assert {:error,
              %TypeMismatchError{operation: :pop_jump_if_falsy, expected: :boolean} = error,
              _ctx} = Predicator.execute("while 1 { x = 1 }", %{})

      assert error.got == :integer
    end

    test "an unbound condition takes the falsy path under the default on_unbound, not an error" do
      assert {:ok, ctx} = Predicator.execute("while unbound { x = 1 }", %{})
      refute Map.has_key?(ctx.data, "x")
    end

    test "an unconditionally true loop exhausts the default loop budget" do
      assert {:error, %EvaluationError{reason: "loop_budget_exceeded"}, _ctx} =
               Predicator.execute("while true { }", %{})
    end

    test "a :loop_budget option is honored - three back edges then the error" do
      assert {:error, %EvaluationError{reason: "loop_budget_exceeded"} = error, _ctx} =
               Predicator.execute("while true { }", %{}, loop_budget: 3)

      assert error.operation == :jump_backward
    end

    test "two sequential loops in one program share a single budget" do
      source = "while true { }; while true { }"

      assert {:error, %EvaluationError{reason: "loop_budget_exceeded"}, _ctx} =
               Predicator.execute(source, %{}, loop_budget: 3)
    end
  end
end
