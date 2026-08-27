defmodule Predicator.EvaluatorTest.RaisingProvider do
  @moduledoc false
  @behaviour Predicator.FunctionProvider

  @impl Predicator.FunctionProvider
  def functions, do: %{"boom" => {1, :call_boom}}

  @spec call_boom([term()], Predicator.Context.t()) :: no_return()
  def call_boom([_arg], _context), do: raise("provider exploded")
end

defmodule Predicator.EvaluatorTest do
  use ExUnit.Case, async: true

  alias Predicator.Errors.EvaluationError
  alias Predicator.Evaluator
  alias Predicator.EvaluatorTest.RaisingProvider

  doctest Predicator.Evaluator

  describe "evaluate/2 with lit instructions" do
    test "evaluates single literal integer" do
      instructions = [["lit", 42]]
      assert Evaluator.evaluate(instructions) == 42
    end

    test "evaluates single literal boolean" do
      instructions = [["lit", true]]
      assert Evaluator.evaluate(instructions) == true

      instructions = [["lit", false]]
      assert Evaluator.evaluate(instructions) == false
    end

    test "evaluates single literal string" do
      instructions = [["lit", "hello"]]
      assert Evaluator.evaluate(instructions) == "hello"
    end

    test "evaluates single literal list" do
      instructions = [["lit", [1, 2, 3]]]
      assert Evaluator.evaluate(instructions) == [1, 2, 3]
    end

    test "evaluates literal :undefined" do
      instructions = [["lit", :undefined]]
      assert Evaluator.evaluate(instructions) == :undefined
    end

    test "multiple literals - returns last one pushed (top of stack)" do
      instructions = [
        ["lit", 1],
        ["lit", 2],
        ["lit", 3]
      ]

      assert Evaluator.evaluate(instructions) == 3
    end
  end

  describe "evaluate/2 with load instructions" do
    test "loads existing string key from context" do
      instructions = [["load", "limit"]]
      context = %{"limit" => 85}

      assert Evaluator.evaluate(instructions, context) == 85
    end

    test "returns :undefined for missing key" do
      instructions = [["load", "missing"]]
      context = %{"limit" => 85}

      assert Evaluator.evaluate(instructions, context) == :undefined
    end

    test "returns :undefined for empty context" do
      instructions = [["load", "anything"]]
      context = %{}

      assert Evaluator.evaluate(instructions, context) == :undefined
    end
  end

  describe "evaluate/2 with mixed instructions" do
    test "load then literal" do
      instructions = [
        ["load", "name"],
        ["lit", 42]
      ]

      context = %{"name" => "Alice"}

      # Should return 42 (last value on stack)
      assert Evaluator.evaluate(instructions, context) == 42
    end

    test "literal then load" do
      instructions = [
        ["lit", "hello"],
        ["load", "name"]
      ]

      context = %{"name" => "Alice"}

      # Should return "Alice" (last value on stack)
      assert Evaluator.evaluate(instructions, context) == "Alice"
    end
  end

  describe "make_list instruction" do
    test "pops n values and pushes them as a list, preserving order" do
      instructions = [["lit", 1], ["lit", 2], ["make_list", 2]]
      assert Evaluator.evaluate(instructions) == [1, 2]
    end

    test "make_list 0 pushes an empty list" do
      instructions = [["make_list", 0]]
      assert Evaluator.evaluate(instructions) == []
    end

    test "returns insufficient_operands error when the stack is too short" do
      instructions = [["lit", 1], ["make_list", 2]]
      result = Evaluator.evaluate(instructions)

      assert {:error, %Predicator.Errors.EvaluationError{reason: "insufficient_operands"}} =
               result
    end

    test "leaves values beneath count untouched" do
      instructions = [["lit", 1], ["lit", 2], ["make_list", 1]]
      assert Evaluator.evaluate(instructions) == [2]
    end

    test "handles mixed types" do
      instructions = [["lit", 1], ["lit", "a"], ["lit", true], ["make_list", 3]]
      assert Evaluator.evaluate(instructions) == [1, "a", true]
    end

    test "handles nested lists" do
      instructions = [
        ["lit", 1],
        ["lit", 2],
        ["make_list", 2],
        ["lit", 3],
        ["make_list", 2]
      ]

      assert Evaluator.evaluate(instructions) == [[1, 2], 3]
    end

    test "malformed count falls through to unknown-instruction error" do
      instructions = [["make_list", "2"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg =~ "Unknown instruction:"
    end
  end

  describe "list concatenation with add instruction" do
    test "concatenates two lists, preserving order" do
      instructions = [["lit", [1, 2]], ["lit", [3, 4]], ["add"]]
      assert Evaluator.evaluate(instructions) == [1, 2, 3, 4]
    end

    test "left-empty list is an identity" do
      instructions = [["lit", []], ["lit", [1]], ["add"]]
      assert Evaluator.evaluate(instructions) == [1]
    end

    test "right-empty list is an identity" do
      instructions = [["lit", [1]], ["lit", []], ["add"]]
      assert Evaluator.evaluate(instructions) == [1]
    end

    test "list plus number is rejected" do
      instructions = [["lit", [1]], ["lit", 2], ["add"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.TypeMismatchError{operation: :add}} = result
    end
  end

  describe "evaluate/2 error cases" do
    test "returns error for empty instruction list" do
      result = Evaluator.evaluate([])
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg == "Evaluation completed with empty stack"
    end

    test "returns error for invalid instruction" do
      instructions = [["invalid_op"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg =~ "Unknown instruction:"
    end

    test "returns error for malformed instruction" do
      # missing argument
      instructions = [["lit"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg =~ "Unknown instruction:"
    end
  end

  describe "step/1 and run/1 - low level API" do
    test "step executes single instruction" do
      evaluator = %Evaluator{
        instructions: [["lit", 42]],
        instruction_pointer: 0,
        stack: [],
        context: %{}
      }

      {:ok, new_evaluator} = Evaluator.step(evaluator)

      assert new_evaluator.stack == [42]
      assert new_evaluator.instruction_pointer == 1
      refute new_evaluator.halted
    end

    test "step halts when all instructions completed" do
      evaluator = %Evaluator{
        instructions: [["lit", 42]],
        # Past the end
        instruction_pointer: 1,
        stack: [42],
        context: %{}
      }

      {:ok, final_evaluator} = Evaluator.step(evaluator)

      assert final_evaluator.halted
    end

    test "run executes all instructions" do
      evaluator = %Evaluator{
        instructions: [["lit", 1], ["lit", 2]],
        instruction_pointer: 0,
        stack: [],
        context: %{}
      }

      {:ok, final_evaluator} = Evaluator.run(evaluator)

      # Stack order: most recent first
      assert final_evaluator.stack == [2, 1]
      assert final_evaluator.instruction_pointer == 2
      assert final_evaluator.halted
    end
  end

  describe "evaluate!/2" do
    test "returns result directly for successful evaluation" do
      instructions = [["lit", 42]]
      assert Evaluator.evaluate!(instructions) == 42
    end

    test "returns result for load instruction" do
      instructions = [["load", "limit"]]
      context = %{"limit" => 85}
      assert Evaluator.evaluate!(instructions, context) == 85
    end

    test "returns result for comparison instruction" do
      instructions = [["load", "x"], ["lit", 5], ["compare", "GT"]]
      context = %{"x" => 10}
      assert Evaluator.evaluate!(instructions, context) == true
    end

    test "returns :undefined for missing context" do
      instructions = [["load", "missing"]]
      assert Evaluator.evaluate!(instructions) == :undefined
    end

    test "raises exception for evaluation errors" do
      instructions = [["unknown_operation"]]

      assert_raise RuntimeError, ~r/Evaluation failed:/, fn ->
        Evaluator.evaluate!(instructions)
      end
    end

    test "raises exception for empty stack error" do
      instructions = []

      assert_raise RuntimeError, ~r/Evaluation failed:/, fn ->
        Evaluator.evaluate!(instructions)
      end
    end
  end

  describe "error handling edge cases" do
    test "handles unknown instruction gracefully" do
      instructions = [["unknown_instruction", "arg"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: message}} = result
      assert message =~ "Unknown instruction"
    end

    test "handles comparison with insufficient stack values" do
      # Only one value on stack
      instructions = [["lit", 42], ["compare", "GT"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: message}} = result
      assert message =~ "Comparison requires 2 values on stack, got: 1"
    end

    test "handles logical NOT with insufficient stack values" do
      # NOT with no values
      instructions = [["not"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: message}} = result
      assert message =~ "Logical NOT requires 1 value on stack, got: 0"
    end

    test "handles membership operations with insufficient stack values" do
      # IN with only one value
      instructions = [["lit", 1], ["in"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: message}} = result
      assert message =~ "In requires 2 values on stack, got: 1"

      # CONTAINS with only one value
      instructions = [["lit", [1, 2]], ["contains"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: message}} = result
      assert message =~ "Contains requires 2 values on stack, got: 1"
    end

    test "handles type mismatches in logical NOT" do
      # NOT with non-boolean value
      instructions = [["lit", "not_boolean"], ["not"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.TypeMismatchError{message: message}} = result
      assert message =~ "Logical NOT requires a boolean"
    end

    test "handles invalid membership operations" do
      # IN with non-list on right side
      instructions = [["lit", 1], ["lit", "not_a_list"], ["in"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.TypeMismatchError{message: message}} = result
      assert message =~ "requires a list"

      # CONTAINS with non-list on left side
      instructions = [["lit", "not_a_list"], ["lit", 1], ["contains"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.TypeMismatchError{message: message}} = result
      assert message =~ "requires a list"
    end
  end

  describe "cast instruction" do
    test "converts the stack top to the named type" do
      instructions = [["lit", "42"], ["cast", "integer"]]

      assert Evaluator.evaluate(instructions) == 42
    end

    test "a failed conversion pushes :undefined, never an error" do
      instructions = [["lit", "abc"], ["cast", "integer"]]

      assert Evaluator.evaluate(instructions) == :undefined
    end

    test ":undefined propagates through cast" do
      instructions = [["lit", :undefined], ["cast", "integer"]]

      assert Evaluator.evaluate(instructions) == :undefined
    end

    test "an empty stack is insufficient_operands naming :cast" do
      instructions = [["cast", "integer"]]

      assert {:error,
              %Predicator.Errors.EvaluationError{
                reason: "insufficient_operands",
                operation: :cast
              }} = Evaluator.evaluate(instructions)
    end

    test "a type name outside the seven-name vocabulary is unknown_instruction" do
      instructions = [["lit", 1], ["cast", "widget"]]

      assert {:error, %Predicator.Errors.EvaluationError{reason: "unknown_instruction"}} =
               Evaluator.evaluate(instructions)
    end

    test "a non-string operand is unknown_instruction" do
      instructions = [["lit", 1], ["cast", 5]]

      assert {:error, %Predicator.Errors.EvaluationError{reason: "unknown_instruction"}} =
               Evaluator.evaluate(instructions)
    end

    test "none of the cast paths raise" do
      for instructions <- [
            [["lit", "42"], ["cast", "integer"]],
            [["lit", "abc"], ["cast", "integer"]],
            [["lit", :undefined], ["cast", "integer"]],
            [["cast", "integer"]],
            [["lit", 1], ["cast", "widget"]],
            [["lit", 1], ["cast", 5]]
          ] do
        Evaluator.evaluate(instructions)
      end
    end

    test "chained casts run left to right" do
      instructions = [["lit", "2026-08-09"], ["cast", "date"], ["cast", "datetime"]]

      assert Evaluator.evaluate(instructions) == ~U[2026-08-09 00:00:00Z]
    end
  end

  describe "evaluate/3 with :loop_budget (ISA v6, ADR-0013)" do
    # An unconditionally infinite loop - the condition is always true, so it
    # exhausts any finite budget, including the default.
    @infinite_loop [["lit", true], ["pop_jump_if_falsy", 2], ["jump_backward", 2]]

    test "loop_budget: 5 exhausts after five back edges" do
      assert {:error, %EvaluationError{reason: "loop_budget_exceeded"}} =
               Evaluator.evaluate(@infinite_loop, %{}, loop_budget: 5)
    end

    test "loop_budget: 0 exhausts on the first back edge" do
      assert {:error, %EvaluationError{reason: "loop_budget_exceeded"}} =
               Evaluator.evaluate(@infinite_loop, %{}, loop_budget: 0)
    end

    test "with no option, the default budget is honored" do
      assert {:error, %EvaluationError{reason: "loop_budget_exceeded"}} =
               Evaluator.evaluate(@infinite_loop, %{})
    end

    test "loop_budget: -1 raises ArgumentError" do
      assert_raise ArgumentError, fn ->
        Evaluator.evaluate(@infinite_loop, %{}, loop_budget: -1)
      end
    end

    test "loop_budget: :lots raises ArgumentError" do
      assert_raise ArgumentError, fn ->
        Evaluator.evaluate(@infinite_loop, %{}, loop_budget: :lots)
      end
    end
  end

  describe "call_function/4 dispatch - MFA entries alongside closures" do
    test "an MFA entry (from a resolved provider) dispatches via apply/3" do
      instructions = [["lit", "x"], ["call", "len", 1]]

      assert Evaluator.evaluate(instructions, %{}) == 1
    end

    test "a closure entry (from :functions) still dispatches directly" do
      instructions = [["lit", 21], ["call", "double", 1]]
      functions = %{"double" => {1, fn [n], _context -> {:ok, n * 2} end}}

      assert Evaluator.evaluate(instructions, %{}, functions: functions) == 42
    end

    test "an MFA entry's arity-mismatch message matches a closure entry's, byte for byte" do
      instructions = [["lit", "a"], ["lit", "b"], ["call", "len", 2]]

      assert {:error, %{message: mfa_message}} =
               Evaluator.evaluate(instructions, %{},
                 providers: [Predicator.Functions.SystemFunctions]
               )

      closure_functions = %{"len" => {1, fn [_arg], _ctx -> {:ok, 0} end}}

      assert {:error, %{message: closure_message}} =
               Evaluator.evaluate(instructions, %{},
                 functions: closure_functions,
                 builtins: false
               )

      assert mfa_message == closure_message
      assert mfa_message == "Function len() expects 1 arguments, got 2"
    end

    test "an unknown function reports the same message regardless of what else is registered" do
      instructions = [["call", "nope", 0]]

      assert Evaluator.evaluate(instructions, %{}) ==
               {:error,
                %Predicator.Errors.EvaluationError{
                  message: "Unknown function: nope",
                  reason: "Unknown function: nope",
                  operation: :function_call,
                  position: nil
                }}
    end

    test "an MFA entry that raises is rescued into the same error shape a closure raise produces" do
      instructions = [["lit", 1], ["call", "boom", 1]]

      assert {:error, %{message: mfa_message}} =
               Evaluator.evaluate(instructions, %{}, providers: [RaisingProvider])

      assert mfa_message =~ "Function boom() raised:"
      assert mfa_message =~ "provider exploded"
    end
  end
end
