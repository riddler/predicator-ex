defmodule Predicator.EvaluatorEdgeCasesTest do
  use ExUnit.Case

  alias Predicator.Errors.EvaluationError
  alias Predicator.Evaluator
  alias Predicator.Functions.SystemFunctions

  describe "evaluator edge cases" do
    test "handles division by zero" do
      instructions = [["lit", 10], ["lit", 0], ["divide"]]
      result = Evaluator.evaluate(instructions, %{})
      assert match?({:error, _}, result)
    end

    test "handles modulo by zero" do
      instructions = [["lit", 10], ["lit", 0], ["modulo"]]
      result = Evaluator.evaluate(instructions, %{})
      assert match?({:error, _}, result)
    end

    test "handles type mismatch in arithmetic" do
      instructions = [["lit", "string"], ["lit", 5], ["add"]]
      result = Evaluator.evaluate(instructions, %{}, providers: [SystemFunctions])
      # String concatenation should work
      assert result == "string5"
    end

    test "handles type mismatch in logical operations" do
      instructions = [["lit", "not_boolean"], ["not"]]
      result = Evaluator.evaluate(instructions, %{})
      assert match?({:error, _}, result)
    end

    test "handles empty stack in operations" do
      instructions = [["add"]]
      result = Evaluator.evaluate(instructions, %{})
      assert match?({:error, _}, result)
    end

    test "handles unknown instruction" do
      instructions = [["unknown_instruction"]]
      result = Evaluator.evaluate(instructions, %{})
      assert match?({:error, _}, result)
    end

    test "handles call to undefined function" do
      instructions = [["call", "undefined_function", 0]]
      result = Evaluator.evaluate(instructions, %{})
      assert match?({:error, _}, result)
    end

    test "handles function call with wrong arity" do
      # Call len with 2 args, but len expects 1
      instructions = [["call", "len", 2]]
      result = Evaluator.evaluate(instructions, %{}, providers: [SystemFunctions])
      assert match?({:error, _}, result)
    end

    test "handles access on non-map/non-list values" do
      instructions = [["lit", "not_a_map"], ["lit", "key"], ["bracket_access"]]
      result = Evaluator.evaluate(instructions, %{})
      assert result == :undefined
    end

    test "handles access with invalid key types" do
      instructions = [["lit", %{"key" => "value"}], ["lit", [1, 2, 3]], ["bracket_access"]]
      result = Evaluator.evaluate(instructions, %{})
      assert match?({:error, _}, result)
    end

    test "handles comparison with incompatible types" do
      instructions = [["lit", "string"], ["lit", 42], ["compare", "GT"]]
      result = Evaluator.evaluate(instructions, %{})
      assert result == :undefined
    end

    test "handles object operations with non-object stack top" do
      instructions = [["lit", "not_an_object"], ["object_set", "key"]]
      result = Evaluator.evaluate(instructions, %{})
      assert match?({:error, _}, result)
    end

    test "object_set on a non-map target returns an EvaluationError, not a crash" do
      instructions = [["lit", 5], ["lit", 1], ["object_set", "key"]]

      assert {:error, %EvaluationError{reason: "invalid_stack_value", operation: :object_set}} =
               Evaluator.evaluate(instructions, %{})
    end

    test "object_set with too few operands still reports insufficient_operands" do
      instructions = [["lit", "not_an_object"], ["object_set", "key"]]

      assert {:error, %EvaluationError{reason: "insufficient_operands", operation: :object_set}} =
               Evaluator.evaluate(instructions, %{})
    end

    test "object_set's non-map error carries a source position when one is available" do
      instructions = [["lit", 5], ["lit", 1], ["object_set", "key"]]

      assert {:error, %EvaluationError{position: position}} =
               Evaluator.evaluate(instructions, %{}, positions: %{2 => {1, 5}})

      assert position != nil
    end

    test "handles contains operation with incompatible types" do
      instructions = [["lit", "not_a_list"], ["lit", "item"], ["contains"]]
      result = Evaluator.evaluate(instructions, %{})
      assert match?({:error, _}, result)
    end

    test "handles in operation with incompatible types" do
      instructions = [["lit", "item"], ["lit", "not_a_list"], ["in"]]
      result = Evaluator.evaluate(instructions, %{})
      assert match?({:error, _}, result)
    end
  end
end
