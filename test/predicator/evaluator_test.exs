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

  alias Predicator.Errors.{EvaluationError, UndefinedVariableError}
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
      instructions = [["load", "score"]]
      context = %{"score" => 85}

      assert Evaluator.evaluate(instructions, context) == 85
    end

    test "returns :undefined for missing key" do
      instructions = [["load", "missing"]]
      context = %{"score" => 85}

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
      instructions = [["load", "score"]]
      context = %{"score" => 85}
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

  describe "retired and/or opcodes" do
    test "and is refused with retired_opcode, naming ISA v3 and upgrade/1" do
      instructions = [["lit", true], ["lit", true], ["and"]]
      result = Evaluator.evaluate(instructions)

      assert {:error, %Predicator.Errors.EvaluationError{reason: "retired_opcode", message: msg}} =
               result

      assert msg =~ "and"
      assert msg =~ "ISA v3"
      assert msg =~ "Predicator.Instructions.upgrade/1"
    end

    test "or is refused with retired_opcode, naming ISA v3 and upgrade/1" do
      instructions = [["lit", false], ["lit", true], ["or"]]
      result = Evaluator.evaluate(instructions)

      assert {:error, %Predicator.Errors.EvaluationError{reason: "retired_opcode", message: msg}} =
               result

      assert msg =~ "or"
      assert msg =~ "ISA v3"
      assert msg =~ "Predicator.Instructions.upgrade/1"
    end

    test "and is refused regardless of operand types or stack depth" do
      assert {:error, %Predicator.Errors.EvaluationError{reason: "retired_opcode"}} =
               Evaluator.evaluate([["lit", 1], ["lit", "hello"], ["and"]])

      assert {:error, %Predicator.Errors.EvaluationError{reason: "retired_opcode"}} =
               Evaluator.evaluate([["lit", true], ["and"]])

      assert {:error, %Predicator.Errors.EvaluationError{reason: "retired_opcode"}} =
               Evaluator.evaluate([["and"]])
    end

    test "or is refused regardless of operand types or stack depth" do
      assert {:error, %Predicator.Errors.EvaluationError{reason: "retired_opcode"}} =
               Evaluator.evaluate([["lit", 42], ["lit", true], ["or"]])

      assert {:error, %Predicator.Errors.EvaluationError{reason: "retired_opcode"}} =
               Evaluator.evaluate([["lit", false], ["or"]])

      assert {:error, %Predicator.Errors.EvaluationError{reason: "retired_opcode"}} =
               Evaluator.evaluate([["or"]])
    end
  end

  describe "logical operators" do
    test "evaluates logical NOT with true value" do
      instructions = [["lit", true], ["not"]]
      assert Evaluator.evaluate(instructions) == false
    end

    test "evaluates logical NOT with false value" do
      instructions = [["lit", false], ["not"]]
      assert Evaluator.evaluate(instructions) == true
    end

    test "returns error for logical NOT with non-boolean value" do
      instructions = [["lit", 123], ["not"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} = result
      assert msg =~ "Logical NOT requires a boolean, got 123"
    end

    test "returns error for logical NOT with empty stack" do
      instructions = [["not"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg =~ "Logical NOT requires 1 value on stack, got: 0"
    end

    test "complex logical expression with variables" do
      # (score > 85 AND age >= 18) OR admin = true, in jump form (the compiler
      # has emitted jumps rather than and/or since 3.7.0; and/or is retired at
      # ISA v3 and this expresses the same program the two opcodes used to).
      instructions = [
        ["load", "score"],
        ["lit", 85],
        ["compare", "GT"],
        ["jump_if_falsy_or_pop", 4],
        ["load", "age"],
        ["lit", 18],
        ["compare", "GTE"],
        ["jump_if_true_or_pop", 4],
        ["load", "admin"],
        ["lit", true],
        ["compare", "EQ"]
      ]

      context = %{"score" => 90, "age" => 20, "admin" => false}
      assert Evaluator.evaluate(instructions, context) == true

      context = %{"score" => 80, "age" => 16, "admin" => false}
      assert Evaluator.evaluate(instructions, context) == false

      context = %{"score" => 80, "age" => 16, "admin" => true}
      assert Evaluator.evaluate(instructions, context) == true
    end

    test "nested NOT expressions" do
      # NOT (NOT true)
      instructions = [["lit", true], ["not"], ["not"]]
      assert Evaluator.evaluate(instructions) == true

      # NOT (NOT (NOT false))
      instructions = [["lit", false], ["not"], ["not"], ["not"]]
      assert Evaluator.evaluate(instructions) == true
    end

    test "mixed comparison and logical operations" do
      # score > 85 AND NOT expired, in jump form (see the composite test
      # above for why)
      instructions = [
        ["load", "score"],
        ["lit", 85],
        ["compare", "GT"],
        ["jump_if_falsy_or_pop", 3],
        ["load", "expired"],
        ["not"]
      ]

      context = %{"score" => 90, "expired" => false}
      assert Evaluator.evaluate(instructions, context) == true

      context = %{"score" => 80, "expired" => false}
      assert Evaluator.evaluate(instructions, context) == false

      context = %{"score" => 90, "expired" => true}
      assert Evaluator.evaluate(instructions, context) == false
    end
  end

  describe "short-circuit jump instructions" do
    test "jump_if_falsy_or_pop with false on top jumps, leaving false as the result" do
      instructions = [["lit", false], ["jump_if_falsy_or_pop", 3], ["lit", 1], ["divide"]]
      assert Evaluator.evaluate(instructions) == false
    end

    test "jump_if_falsy_or_pop with :undefined on top jumps, leaving :undefined as the result" do
      instructions = [["load", "missing"], ["jump_if_falsy_or_pop", 3], ["lit", 1], ["divide"]]
      assert Evaluator.evaluate(instructions) == :undefined
    end

    test "jump_if_falsy_or_pop with true on top pops and falls through" do
      instructions = [["lit", true], ["jump_if_falsy_or_pop", 2], ["lit", 5]]
      assert Evaluator.evaluate(instructions) == 5
    end

    test "jump_if_falsy_or_pop with a non-boolean, non-undefined top is a type mismatch" do
      instructions = [["lit", 42], ["jump_if_falsy_or_pop", 2], ["lit", 5]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} = result
      assert msg =~ "Logical AND"
    end

    test "jump_if_falsy_or_pop with empty stack is an insufficient-operands error" do
      instructions = [["jump_if_falsy_or_pop", 2]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg =~ "requires 1 value"
    end

    test "jump_if_true_or_pop with true on top jumps, leaving true as the result" do
      instructions = [["lit", true], ["jump_if_true_or_pop", 3], ["lit", 1], ["divide"]]
      assert Evaluator.evaluate(instructions) == true
    end

    test "jump_if_true_or_pop with :undefined on top pops and falls through" do
      instructions = [["load", "missing"], ["jump_if_true_or_pop", 2], ["lit", 5]]
      assert Evaluator.evaluate(instructions) == 5
    end

    test "jump_if_true_or_pop with false on top pops and falls through" do
      instructions = [["lit", false], ["jump_if_true_or_pop", 2], ["lit", 5]]
      assert Evaluator.evaluate(instructions) == 5
    end

    test "jump_if_true_or_pop with a non-boolean, non-undefined top is a type mismatch" do
      instructions = [["lit", 42], ["jump_if_true_or_pop", 2], ["lit", 5]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} = result
      assert msg =~ "Logical OR"
    end

    test "jump_if_true_or_pop with empty stack is an insufficient-operands error" do
      instructions = [["jump_if_true_or_pop", 2]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg =~ "requires 1 value"
    end

    test "malformed offset falls through to unknown instruction" do
      instructions = [["lit", true], ["jump_if_falsy_or_pop", 0]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg =~ "Unknown instruction"

      instructions = [["lit", true], ["jump_if_falsy_or_pop", "2"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg =~ "Unknown instruction"
    end

    test "a jump landing exactly at the end of the instruction list finishes cleanly" do
      instructions = [["lit", false], ["jump_if_falsy_or_pop", 1]]
      assert Evaluator.evaluate(instructions) == false
    end
  end

  describe "date and datetime evaluation" do
    test "evaluates date comparisons" do
      date1 = ~D[2024-01-15]
      date2 = ~D[2024-01-20]

      # Date GT
      instructions = [["lit", date2], ["lit", date1], ["compare", "GT"]]
      assert Evaluator.evaluate(instructions) == true

      # Date LT
      instructions = [["lit", date1], ["lit", date2], ["compare", "LT"]]
      assert Evaluator.evaluate(instructions) == true

      # Date EQ
      instructions = [["lit", date1], ["lit", date1], ["compare", "EQ"]]
      assert Evaluator.evaluate(instructions) == true

      # Date NE
      instructions = [["lit", date1], ["lit", date2], ["compare", "NE"]]
      assert Evaluator.evaluate(instructions) == true
    end

    test "evaluates datetime comparisons" do
      {:ok, dt1, _offset1} = DateTime.from_iso8601("2024-01-15T10:00:00Z")
      {:ok, dt2, _offset2} = DateTime.from_iso8601("2024-01-15T15:00:00Z")

      # DateTime GT
      instructions = [["lit", dt2], ["lit", dt1], ["compare", "GT"]]
      assert Evaluator.evaluate(instructions) == true

      # DateTime GTE (equal)
      instructions = [["lit", dt1], ["lit", dt1], ["compare", "GTE"]]
      assert Evaluator.evaluate(instructions) == true

      # DateTime LTE
      instructions = [["lit", dt1], ["lit", dt2], ["compare", "LTE"]]
      assert Evaluator.evaluate(instructions) == true
    end

    test "date and datetime membership operations" do
      dates = [~D[2024-01-15], ~D[2024-01-16]]
      {:ok, dt1, _offset1} = DateTime.from_iso8601("2024-01-15T10:00:00Z")
      {:ok, dt2, _offset2} = DateTime.from_iso8601("2024-01-15T15:00:00Z")
      datetimes = [dt1, dt2]

      # Date IN list
      instructions = [["lit", ~D[2024-01-15]], ["lit", dates], ["in"]]
      assert Evaluator.evaluate(instructions) == true

      # Date NOT IN list
      instructions = [["lit", ~D[2024-01-17]], ["lit", dates], ["in"]]
      assert Evaluator.evaluate(instructions) == false

      # DateTime CONTAINS
      instructions = [["lit", datetimes], ["lit", dt1], ["contains"]]
      assert Evaluator.evaluate(instructions) == true

      # DateTime NOT CONTAINS
      {:ok, dt3, _offset3} = DateTime.from_iso8601("2024-01-20T10:00:00Z")
      instructions = [["lit", datetimes], ["lit", dt3], ["contains"]]
      assert Evaluator.evaluate(instructions) == false
    end
  end

  describe "mixed date/datetime comparison" do
    test "orders a Date against a later DateTime in both operand orders" do
      date = ~D[2024-01-15]
      later = ~U[2024-01-20 10:00:00Z]

      assert Evaluator.evaluate([["lit", date], ["lit", later], ["compare", "LT"]]) == true
      assert Evaluator.evaluate([["lit", date], ["lit", later], ["compare", "LTE"]]) == true
      assert Evaluator.evaluate([["lit", date], ["lit", later], ["compare", "GT"]]) == false

      assert Evaluator.evaluate([["lit", later], ["lit", date], ["compare", "GT"]]) == true
      assert Evaluator.evaluate([["lit", later], ["lit", date], ["compare", "GTE"]]) == true
      assert Evaluator.evaluate([["lit", later], ["lit", date], ["compare", "LT"]]) == false
    end

    test "a Date equals the midnight-UTC DateTime of the same day" do
      date = ~D[2024-01-15]
      midnight = ~U[2024-01-15 00:00:00Z]
      one_second_later = ~U[2024-01-15 00:00:01Z]

      assert Evaluator.evaluate([["lit", date], ["lit", midnight], ["compare", "EQ"]]) == true
      assert Evaluator.evaluate([["lit", midnight], ["lit", date], ["compare", "EQ"]]) == true
      assert Evaluator.evaluate([["lit", date], ["lit", midnight], ["compare", "GTE"]]) == true
      assert Evaluator.evaluate([["lit", date], ["lit", midnight], ["compare", "LTE"]]) == true

      assert Evaluator.evaluate([["lit", date], ["lit", one_second_later], ["compare", "EQ"]]) ==
               false

      assert Evaluator.evaluate([["lit", date], ["lit", one_second_later], ["compare", "NE"]]) ==
               true
    end

    test "strict equality never crosses the Date/DateTime boundary" do
      date = ~D[2024-01-15]
      midnight = ~U[2024-01-15 00:00:00Z]

      assert Evaluator.evaluate([["lit", date], ["lit", midnight], ["compare", "STRICT_EQ"]]) ==
               false

      assert Evaluator.evaluate([["lit", date], ["lit", midnight], ["compare", "STRICT_NE"]]) ==
               true
    end

    test "membership coerces the same way" do
      date = ~D[2024-01-15]
      datetimes = [~U[2024-01-15 00:00:00Z], ~U[2024-01-16 12:00:00Z]]
      dates = [~D[2024-01-15], ~D[2024-01-16]]

      assert Evaluator.evaluate([["lit", date], ["lit", datetimes], ["in"]]) == true
      assert Evaluator.evaluate([["lit", ~D[2024-01-17]], ["lit", datetimes], ["in"]]) == false

      assert Evaluator.evaluate([["lit", dates], ["lit", ~U[2024-01-15 00:00:00Z]], ["contains"]]) ==
               true

      assert Evaluator.evaluate([["lit", dates], ["lit", ~U[2024-01-15 09:00:00Z]], ["contains"]]) ==
               false
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

  describe "evaluate/2 with bracket_access instructions" do
    test "accesses object property with string key" do
      instructions = [
        ["load", "user"],
        ["lit", "name"],
        ["bracket_access"]
      ]

      context = %{"user" => %{"name" => "John", "age" => 30}}

      assert Evaluator.evaluate(instructions, context) == "John"
    end

    test "accesses object property with atom key" do
      instructions = [
        ["load", "user"],
        ["lit", :role],
        ["bracket_access"]
      ]

      context = %{"user" => %{:name => "Alice", role: "admin"}}

      assert Evaluator.evaluate(instructions, context) == "admin"
    end

    test "accesses array element with integer index" do
      instructions = [
        ["load", "items"],
        ["lit", 1],
        ["bracket_access"]
      ]

      context = %{"items" => ["apple", "banana", "cherry"]}

      assert Evaluator.evaluate(instructions, context) == "banana"
    end

    test "accesses array element with variable index" do
      instructions = [
        ["load", "scores"],
        ["load", "index"],
        ["bracket_access"]
      ]

      context = %{"scores" => [85, 92, 78], "index" => 2}

      assert Evaluator.evaluate(instructions, context) == 78
    end

    test "returns :undefined for missing object key" do
      instructions = [
        ["load", "user"],
        ["lit", "missing"],
        ["bracket_access"]
      ]

      context = %{"user" => %{"name" => "John"}}

      assert Evaluator.evaluate(instructions, context) == :undefined
    end

    test "returns :undefined for out of bounds array access" do
      instructions = [
        ["load", "items"],
        ["lit", 10],
        ["bracket_access"]
      ]

      context = %{"items" => ["a", "b", "c"]}

      assert Evaluator.evaluate(instructions, context) == :undefined
    end

    test "returns :undefined for negative array index" do
      instructions = [
        ["load", "items"],
        ["lit", -1],
        ["bracket_access"]
      ]

      context = %{"items" => ["a", "b", "c"]}

      assert Evaluator.evaluate(instructions, context) == :undefined
    end

    test "returns :undefined when accessing non-object/non-array" do
      instructions = [
        ["load", "name"],
        ["lit", "length"],
        ["bracket_access"]
      ]

      context = %{"name" => "John"}

      assert Evaluator.evaluate(instructions, context) == :undefined
    end

    test "returns :undefined for an atom-keyed property reached via the raw Evaluator API" do
      instructions = [
        ["load", "user"],
        ["lit", "role"],
        ["bracket_access"]
      ]

      # atom key only, and this context reaches Evaluator.evaluate/3 directly,
      # bypassing Predicator.Context.new/2 - so nothing normalizes the atom
      # key to a string first. access_value/3 no longer falls back to
      # String.to_existing_atom/1 (px-8um.2), so the property is :undefined.
      # Atom-keyed nested data works when the context is built through
      # Predicator.Context.new/2 instead; see context_test.exs.
      context = %{"user" => %{role: "admin"}}

      assert Evaluator.evaluate(instructions, context) == :undefined
    end

    test "returns :undefined for a bracket-access key with no matching entry" do
      instructions = [
        ["load", "user"],
        ["lit", "missing_key_that_cannot_be_atom"],
        ["bracket_access"]
      ]

      context = %{"user" => %{"name" => "John"}}

      assert Evaluator.evaluate(instructions, context) == :undefined
    end

    test "supports chained bracket access" do
      instructions = [
        ["load", "data"],
        ["lit", "users"],
        ["bracket_access"],
        ["lit", 0],
        ["bracket_access"],
        ["lit", "name"],
        ["bracket_access"]
      ]

      context = %{"data" => %{"users" => [%{"name" => "Alice"}, %{"name" => "Bob"}]}}

      assert Evaluator.evaluate(instructions, context) == "Alice"
    end

    test "supports mixed map and array access" do
      instructions = [
        ["load", "data"],
        ["lit", "scores"],
        ["bracket_access"],
        ["lit", 1],
        ["bracket_access"]
      ]

      context = %{"data" => %{"scores" => [85, 92, 78]}}

      assert Evaluator.evaluate(instructions, context) == 92
    end

    test "supports integer keys in maps" do
      instructions = [
        ["load", "config"],
        ["lit", 100],
        ["bracket_access"]
      ]

      context = %{"config" => %{100 => "port_setting", "name" => "app"}}

      assert Evaluator.evaluate(instructions, context) == "port_setting"
    end

    test "returns error for invalid key type (list)" do
      instructions = [
        ["load", "user"],
        ["lit", [1, 2, 3]],
        ["bracket_access"]
      ]

      context = %{"user" => %{"name" => "John"}}

      result = Evaluator.evaluate(instructions, context)
      assert {:error, %Predicator.Errors.TypeMismatchError{operation: :bracket_access}} = result
    end

    test "returns error for invalid key type (boolean)" do
      instructions = [
        ["load", "user"],
        ["lit", true],
        ["bracket_access"]
      ]

      context = %{"user" => %{"name" => "John"}}

      # Note: This should work since booleans are atoms in Elixir
      assert Evaluator.evaluate(instructions, context) == :undefined
    end

    test "returns error for invalid key type (float)" do
      instructions = [
        ["load", "user"],
        ["lit", 3.14],
        ["bracket_access"]
      ]

      context = %{"user" => %{"name" => "John"}}

      result = Evaluator.evaluate(instructions, context)
      assert {:error, %Predicator.Errors.TypeMismatchError{operation: :bracket_access}} = result
    end

    test "returns error for insufficient operands" do
      instructions = [
        ["load", "user"],
        # Missing key operand
        ["bracket_access"]
      ]

      context = %{"user" => %{"name" => "John"}}

      result = Evaluator.evaluate(instructions, context)
      assert {:error, %Predicator.Errors.EvaluationError{}} = result
    end

    test "returns error for empty stack" do
      instructions = [
        # No operands at all
        ["bracket_access"]
      ]

      result = Evaluator.evaluate(instructions, %{})
      assert {:error, %Predicator.Errors.EvaluationError{}} = result
    end

    test "works with expression-based keys" do
      instructions = [
        ["load", "items"],
        ["load", "i"],
        ["lit", 1],
        ["add"],
        ["bracket_access"]
      ]

      context = %{"items" => ["a", "b", "c", "d"], "i" => 1}

      assert Evaluator.evaluate(instructions, context) == "c"
    end

    test "integrates with arithmetic operations" do
      instructions = [
        ["load", "scores"],
        ["lit", 0],
        ["bracket_access"],
        ["load", "scores"],
        ["lit", 1],
        ["bracket_access"],
        ["add"]
      ]

      context = %{"scores" => [10, 20, 30]}

      assert Evaluator.evaluate(instructions, context) == 30
    end

    test "integrates with comparison operations" do
      instructions = [
        ["load", "user"],
        ["lit", "age"],
        ["bracket_access"],
        ["lit", 18],
        ["compare", "GT"]
      ]

      context = %{"user" => %{"age" => 25}}

      assert Evaluator.evaluate(instructions, context) == true
    end

    test "handles complex nested structures" do
      instructions = [
        ["load", "app"],
        ["lit", "config"],
        ["bracket_access"],
        ["lit", "database"],
        ["bracket_access"],
        ["lit", "connections"],
        ["bracket_access"],
        ["lit", 0],
        ["bracket_access"],
        ["lit", "host"],
        ["bracket_access"]
      ]

      context = %{
        "app" => %{
          "config" => %{
            "database" => %{
              "connections" => [
                %{"host" => "localhost", "port" => 5432},
                %{"host" => "remote", "port" => 5433}
              ]
            }
          }
        }
      }

      assert Evaluator.evaluate(instructions, context) == "localhost"
    end
  end

  describe "access_value/3 is total (px-tmy)" do
    # A boolean key against a list target used to raise FunctionClauseError
    # from ordinary user-authored source (the bead's reproduction). It must
    # now return a typed error instead - from source and from a hand-built
    # instruction list.
    test "a boolean bracket key against a list target errors, from source" do
      assert {:error,
              %Predicator.Errors.TypeMismatchError{
                operation: :bracket_access,
                expected: :integer,
                got: :boolean
              }} = Predicator.evaluate("xs[flag]", %{"xs" => ["a"], "flag" => true})
    end

    test "a boolean bracket key against a map target is a miss, from source" do
      assert {:ok, :undefined} =
               Predicator.evaluate("m[flag]", %{"m" => %{"a" => 1}, "flag" => true})
    end

    test "a boolean bracket key against a map target hits, from source" do
      assert {:ok, "on"} =
               Predicator.evaluate("config[true]", %{"config" => %{true => "on"}})
    end

    test "a boolean bracket key against a list target errors, hand-built" do
      instructions = [["lit", ["a"]], ["lit", true], ["bracket_access"]]

      assert {:error, %Predicator.Errors.TypeMismatchError{operation: :bracket_access}} =
               Evaluator.evaluate(instructions, %{})
    end

    test "a boolean bracket key against a map target is a miss, hand-built" do
      instructions = [["lit", %{"a" => 1}], ["lit", true], ["bracket_access"]]

      assert Evaluator.evaluate(instructions, %{}) == :undefined
    end

    test "a boolean bracket key against a map target hits, hand-built" do
      instructions = [["lit", %{true => "on"}], ["lit", true], ["bracket_access"]]

      assert Evaluator.evaluate(instructions, %{}) == "on"
    end

    test "a string key against a list target errors, not just booleans" do
      instructions = [["lit", ["a"]], ["lit", "k"], ["bracket_access"]]

      assert {:error,
              %Predicator.Errors.TypeMismatchError{operation: :bracket_access, expected: :integer}} =
               Evaluator.evaluate(instructions, %{})
    end

    test "an :undefined key against a list target errors" do
      instructions = [["lit", ["a"]], ["lit", :undefined], ["bracket_access"]]

      assert {:error, %Predicator.Errors.TypeMismatchError{operation: :bracket_access}} =
               Evaluator.evaluate(instructions, %{})
    end

    test "the access opcode never errors, even on a list target (dot property)" do
      assert {:ok, :undefined} = Predicator.evaluate("xs.name", %{"xs" => [1, 2]})
    end

    test "a float key against a list target still errors, now naming an integer" do
      instructions = [["lit", ["a"]], ["lit", 1.5], ["bracket_access"]]

      assert {:error,
              %Predicator.Errors.TypeMismatchError{operation: :bracket_access, expected: :integer}} =
               Evaluator.evaluate(instructions, %{})
    end
  end

  describe "evaluate/2 with duration instructions" do
    test "evaluates simple duration instruction" do
      instructions = [["duration", [[5, "d"]]]]
      result = Evaluator.evaluate(instructions)

      expected = %{years: 0, months: 0, weeks: 0, days: 5, hours: 0, minutes: 0, seconds: 0}
      assert result == expected
    end

    test "evaluates duration with multiple units" do
      instructions = [["duration", [[1, "d"], [8, "h"], [30, "m"]]]]
      result = Evaluator.evaluate(instructions)

      expected = %{years: 0, months: 0, weeks: 0, days: 1, hours: 8, minutes: 30, seconds: 0}
      assert result == expected
    end

    test "evaluates duration with all unit types" do
      instructions = [
        ["duration", [[2, "y"], [3, "mo"], [4, "w"], [5, "d"], [6, "h"], [7, "m"], [8, "s"]]]
      ]

      result = Evaluator.evaluate(instructions)

      expected = %{years: 2, months: 3, weeks: 4, days: 5, hours: 6, minutes: 7, seconds: 8}
      assert result == expected
    end

    test "evaluates duration with long unit names" do
      instructions = [["duration", [[1, "year"], [2, "months"], [3, "weeks"]]]]
      result = Evaluator.evaluate(instructions)

      expected = %{years: 1, months: 2, weeks: 3, days: 0, hours: 0, minutes: 0, seconds: 0}
      assert result == expected
    end

    test "evaluates duration with mixed unit formats" do
      instructions = [
        [
          "duration",
          [[1, "y"], [2, "month"], [3, "w"], [4, "day"], [5, "h"], [6, "min"], [7, "sec"]]
        ]
      ]

      result = Evaluator.evaluate(instructions)

      expected = %{years: 1, months: 2, weeks: 3, days: 4, hours: 5, minutes: 6, seconds: 7}
      assert result == expected
    end

    test "evaluates duration with zero values" do
      instructions = [["duration", [[0, "d"], [0, "h"]]]]
      result = Evaluator.evaluate(instructions)

      expected = %{years: 0, months: 0, weeks: 0, days: 0, hours: 0, minutes: 0, seconds: 0}
      assert result == expected
    end

    test "evaluates duration with large values" do
      instructions = [["duration", [[999, "y"], [365, "d"]]]]
      result = Evaluator.evaluate(instructions)

      expected = %{years: 999, months: 0, weeks: 0, days: 365, hours: 0, minutes: 0, seconds: 0}
      assert result == expected
    end

    test "returns error for invalid duration unit format" do
      instructions = [["duration", [["invalid"]]]]
      result = Evaluator.evaluate(instructions)

      assert {:error, _message} = result
    end

    test "returns error for invalid duration unit" do
      instructions = [["duration", [[5, "invalid_unit"]]]]
      result = Evaluator.evaluate(instructions)

      assert {:error, _message} = result
    end
  end

  describe "evaluate/2 with relative_date instructions" do
    test "evaluates relative date with ago direction" do
      instructions = [
        ["duration", [[1, "d"], [8, "h"]]],
        ["relative_date", "ago"]
      ]

      before_test = DateTime.utc_now()
      result = Evaluator.evaluate(instructions)

      # Result should be a DateTime roughly 1 day 8 hours ago
      assert %DateTime{} = result

      # Calculate expected time range (1d8h = 32 hours = 115200 seconds)
      expected_seconds_ago = 32 * 3600

      # Check the result is within reasonable bounds (allowing for test execution time)
      seconds_diff = DateTime.diff(before_test, result, :second)

      assert seconds_diff >= expected_seconds_ago - 10 and
               seconds_diff <= expected_seconds_ago + 10
    end

    test "evaluates relative date with future direction" do
      instructions = [
        ["duration", [[2, "h"], [30, "m"]]],
        ["relative_date", "future"]
      ]

      before_test = DateTime.utc_now()
      result = Evaluator.evaluate(instructions)

      # Result should be a DateTime roughly 2.5 hours in the future
      assert %DateTime{} = result

      # Calculate expected time (2h30m = 9000 seconds)
      expected_seconds_future = 2.5 * 3600

      # Check the result is within reasonable bounds
      seconds_diff = DateTime.diff(result, before_test, :second)

      assert seconds_diff >= expected_seconds_future - 10 and
               seconds_diff <= expected_seconds_future + 10
    end

    test "evaluates relative date with next direction" do
      instructions = [
        ["duration", [[1, "w"]]],
        ["relative_date", "next"]
      ]

      before_test = DateTime.utc_now()
      result = Evaluator.evaluate(instructions)

      # Result should be a DateTime roughly 1 week in the future
      assert %DateTime{} = result

      # Calculate expected time (1w = 7 * 24 * 3600 = 604800 seconds)
      expected_seconds_future = 7 * 24 * 3600

      # Check the result is within reasonable bounds
      seconds_diff = DateTime.diff(result, before_test, :second)

      assert seconds_diff >= expected_seconds_future - 10 and
               seconds_diff <= expected_seconds_future + 10
    end

    test "evaluates relative date with last direction" do
      instructions = [
        ["duration", [[6, "mo"]]],
        ["relative_date", "last"]
      ]

      before_test = DateTime.utc_now()
      result = Evaluator.evaluate(instructions)

      # Result should be a DateTime roughly 6 months ago
      assert %DateTime{} = result

      # Calculate expected time (6mo ≈ 6 * 30 * 24 * 3600 = 15552000 seconds)
      expected_seconds_ago = 6 * 30 * 24 * 3600

      # Check the result is within reasonable bounds
      seconds_diff = DateTime.diff(before_test, result, :second)

      assert seconds_diff >= expected_seconds_ago - 1000 and
               seconds_diff <= expected_seconds_ago + 1000
    end

    test "evaluates complex relative date with multiple units" do
      instructions = [
        ["duration", [[1, "y"], [2, "mo"], [3, "d"]]],
        ["relative_date", "ago"]
      ]

      before_test = DateTime.utc_now()
      result = Evaluator.evaluate(instructions)

      # Result should be a DateTime roughly 1 year 2 months 3 days ago
      assert %DateTime{} = result
      assert DateTime.compare(result, before_test) == :lt

      # Should be significantly in the past (approximate calculation)
      seconds_diff = DateTime.diff(before_test, result, :second)
      # Allow some variance
      expected_min = (365 + 60 + 3) * 24 * 3600 - 100_000
      expected_max = (365 + 60 + 3) * 24 * 3600 + 100_000
      assert seconds_diff >= expected_min and seconds_diff <= expected_max
    end

    test "returns error for unknown relative date direction" do
      instructions = [
        ["duration", [[1, "d"]]],
        ["relative_date", "unknown"]
      ]

      result = Evaluator.evaluate(instructions)
      assert {:error, _message} = result
    end

    test "returns error for relative_date without duration on stack" do
      instructions = [["relative_date", "ago"]]

      result = Evaluator.evaluate(instructions)
      assert {:error, _error_struct} = result
    end

    test "returns error for relative_date with non-duration on stack" do
      instructions = [
        ["lit", "not a duration"],
        ["relative_date", "ago"]
      ]

      result = Evaluator.evaluate(instructions)
      assert {:error, _message} = result
    end

    test "integrates with comparisons - date greater than relative date" do
      # Simulate: some_recent_date > 1d ago (recent date is more recent than 1 day ago)
      # 12 hours ago
      recent_date = DateTime.add(DateTime.utc_now(), -12 * 3600, :second)

      instructions = [
        ["lit", recent_date],
        ["duration", [[1, "d"]]],
        ["relative_date", "ago"],
        ["compare", "GT"]
      ]

      result = Evaluator.evaluate(instructions)
      # 12 hours ago is greater than (more recent than) 1 day ago
      assert result == true
    end

    test "integrates with logical operations" do
      # Simulate: created_at > 1d ago AND updated_at < 1h from now, in jump
      # form (see the composite tests in the "logical operators" describe
      # block for why)
      now = DateTime.utc_now()
      # 1 hour ago
      recent_past = DateTime.add(now, -3600, :second)
      # 30 minutes from now
      near_future = DateTime.add(now, 1800, :second)

      instructions = [
        ["lit", recent_past],
        ["duration", [[1, "d"]]],
        ["relative_date", "ago"],
        ["compare", "GT"],
        ["jump_if_falsy_or_pop", 5],
        ["lit", near_future],
        ["duration", [[1, "h"]]],
        ["relative_date", "future"],
        ["compare", "LT"]
      ]

      result = Evaluator.evaluate(instructions)
      # Both conditions should be true
      assert result == true
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

  describe "unbound_loads/1" do
    test "records executed unbound loads in execution order" do
      evaluator = %Evaluator{
        instructions: [["load", "a"], ["load", "b"], ["load", "c"]],
        context: %{"b" => 1}
      }

      {:ok, _result, final} = Evaluator.run_prepared(evaluator)
      assert Evaluator.unbound_loads(final) == ["a", "c"]
    end

    test "does not record a name bound to :undefined" do
      evaluator = %Evaluator{
        instructions: [["load", "a"]],
        context: %{"a" => :undefined}
      }

      {:ok, :undefined, final} = Evaluator.run_prepared(evaluator)
      assert Evaluator.unbound_loads(final) == []
    end

    test "does not record a name bound under an atom key" do
      # Intentional asymmetry for this Context-bypassing, low-level API
      # (px-8um.2): load_from_context/2 no longer falls back to an atom key,
      # so the *value* comes back :undefined - the string key "score" is
      # genuinely absent from this hand-built context. But resolve_key/2
      # (deliberately out of scope for px-8um.2 - it powers Context.bound?/2
      # and unbound-load bookkeeping, a presence check, not a value read)
      # still finds the atom key :score present, so unbound_loads stays []
      # rather than recording "score". This asymmetry is only reachable by
      # bypassing Predicator.Context.new/2; Predicator.evaluate/3's
      # unbound_loads reporting only ever sees Context.new/2-normalized data,
      # where the atom key would already be a string key and both checks
      # would agree.
      evaluator = %Evaluator{instructions: [["load", "score"]], context: %{score: 85}}

      {:ok, :undefined, final} = Evaluator.run_prepared(evaluator)
      assert Evaluator.unbound_loads(final) == []
    end

    test "records a repeated unbound load once" do
      evaluator = %Evaluator{instructions: [["load", "a"], ["load", "a"]], context: %{}}

      {:ok, :undefined, final} = Evaluator.run_prepared(evaluator)
      assert Evaluator.unbound_loads(final) == ["a"]
    end

    test "is empty for a program with no loads" do
      {:ok, 42, final} = Evaluator.run_prepared(%Evaluator{instructions: [["lit", 42]]})
      assert Evaluator.unbound_loads(final) == []
    end

    test "survives a failing run - run_prepared/1 returns the state on the error path" do
      evaluator = %Evaluator{
        instructions: [["load", "a"], ["load", "b"], ["not"]],
        context: %{"a" => 1}
      }

      assert {:error, %Predicator.Errors.TypeMismatchError{}, final} =
               Evaluator.run_prepared(evaluator)

      assert Evaluator.unbound_loads(final) == ["b"]
    end
  end

  describe "unbound_loads_with_locations/1" do
    test "a covered index records its {line, column}" do
      evaluator = %Evaluator{
        instructions: [["load", "a"]],
        context: %{},
        positions: %{0 => {1, 1}}
      }

      {:ok, :undefined, final} = Evaluator.run_prepared(evaluator)
      assert Evaluator.unbound_loads_with_locations(final) == [{"a", {1, 1}}]
    end

    test "an uncovered index records nil" do
      evaluator = %Evaluator{
        instructions: [["load", "a"]],
        context: %{},
        positions: %{1 => {1, 1}}
      }

      {:ok, :undefined, final} = Evaluator.run_prepared(evaluator)
      assert Evaluator.unbound_loads_with_locations(final) == [{"a", nil}]
    end

    test "an absent positions table records nil" do
      evaluator = %Evaluator{instructions: [["load", "a"]], context: %{}}

      {:ok, :undefined, final} = Evaluator.run_prepared(evaluator)
      assert Evaluator.unbound_loads_with_locations(final) == [{"a", nil}]
    end

    test "a span table records the span unchanged, not narrowed to its start" do
      evaluator = %Evaluator{
        instructions: [["load", "a"]],
        context: %{},
        positions: %{0 => {{1, 1}, {1, 2}}}
      }

      {:ok, :undefined, final} = Evaluator.run_prepared(evaluator)
      assert Evaluator.unbound_loads_with_locations(final) == [{"a", {{1, 1}, {1, 2}}}]
    end

    test "a repeated load keeps the first occurrence's location" do
      evaluator = %Evaluator{
        instructions: [["load", "a"], ["load", "a"]],
        context: %{},
        positions: %{0 => {1, 1}, 1 => {1, 9}}
      }

      {:ok, :undefined, final} = Evaluator.run_prepared(evaluator)
      assert Evaluator.unbound_loads_with_locations(final) == [{"a", {1, 1}}]
    end
  end

  describe "evaluate/3 with on_unbound: :error" do
    test "an unbound root errors instead of loading :undefined" do
      assert Evaluator.evaluate([["load", "x"]], %{}, on_unbound: :error) ==
               {:error, UndefinedVariableError.new("x")}
    end

    test "the same call without the option keeps today's :undefined" do
      assert Evaluator.evaluate([["load", "x"]], %{}) == :undefined
    end

    test "bound to :undefined is bound - presence, not value" do
      assert Evaluator.evaluate([["load", "x"]], %{"x" => :undefined}, on_unbound: :error) ==
               :undefined
    end

    test "bound to nil is bound too - only Context.new/2 normalizes nil" do
      assert Evaluator.evaluate([["load", "x"]], %{"x" => nil}, on_unbound: :error) == nil
    end

    test "a hand-built atom key resolves as bound, so the policy does not fire" do
      assert Evaluator.evaluate([["load", "x"]], %{x: 1}, on_unbound: :error) == :undefined
    end

    test "an unrecognized policy value behaves as the default - no validation here" do
      assert Evaluator.evaluate([["load", "x"]], %{}, on_unbound: :bogus) == :undefined
    end

    test "evaluate!/3 raises where it returned :undefined before" do
      assert_raise RuntimeError, fn ->
        Evaluator.evaluate!([["load", "x"]], %{}, on_unbound: :error)
      end
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
