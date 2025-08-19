defmodule Predicator.EvaluatorTest do
  use ExUnit.Case, async: true

  alias Predicator.Evaluator

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

    test "loads existing atom key from context" do
      instructions = [["load", "score"]]
      context = %{score: 85}

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

    test "prefers string key over atom key" do
      instructions = [["load", "key"]]
      context = %{"key" => "string_value", key: "atom_value"}

      assert Evaluator.evaluate(instructions, context) == "string_value"
    end

    test "falls back to atom key if string key doesn't exist" do
      instructions = [["load", "key"]]
      context = %{key: "atom_value"}

      assert Evaluator.evaluate(instructions, context) == "atom_value"
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

  describe "evaluate/2 error cases" do
    test "returns error for empty instruction list" do
      result = Evaluator.evaluate([])
      assert {:error, "Evaluation completed with empty stack"} = result
    end

    test "returns error for invalid instruction" do
      instructions = [["invalid_op"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, "Unknown instruction: " <> _error_msg} = result
    end

    test "returns error for malformed instruction" do
      # missing argument
      instructions = [["lit"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, "Unknown instruction: " <> _error_msg} = result
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

  describe "logical operators" do
    test "evaluates logical AND with true values" do
      instructions = [["lit", true], ["lit", true], ["and"]]
      assert Evaluator.evaluate(instructions) == true
    end

    test "evaluates logical AND with false values" do
      instructions = [["lit", false], ["lit", false], ["and"]]
      assert Evaluator.evaluate(instructions) == false
    end

    test "evaluates logical AND with mixed values" do
      instructions = [["lit", true], ["lit", false], ["and"]]
      assert Evaluator.evaluate(instructions) == false

      instructions = [["lit", false], ["lit", true], ["and"]]
      assert Evaluator.evaluate(instructions) == false
    end

    test "evaluates logical OR with true values" do
      instructions = [["lit", true], ["lit", true], ["or"]]
      assert Evaluator.evaluate(instructions) == true
    end

    test "evaluates logical OR with false values" do
      instructions = [["lit", false], ["lit", false], ["or"]]
      assert Evaluator.evaluate(instructions) == false
    end

    test "evaluates logical OR with mixed values" do
      instructions = [["lit", true], ["lit", false], ["or"]]
      assert Evaluator.evaluate(instructions) == true

      instructions = [["lit", false], ["lit", true], ["or"]]
      assert Evaluator.evaluate(instructions) == true
    end

    test "evaluates logical NOT with true value" do
      instructions = [["lit", true], ["not"]]
      assert Evaluator.evaluate(instructions) == false
    end

    test "evaluates logical NOT with false value" do
      instructions = [["lit", false], ["not"]]
      assert Evaluator.evaluate(instructions) == true
    end

    test "returns error for logical AND with non-boolean values" do
      instructions = [["lit", 42], ["lit", true], ["and"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, _message} = result
      assert match?({:error, "Logical AND requires two boolean values" <> _}, result)
    end

    test "returns error for logical AND with insufficient stack" do
      instructions = [["lit", true], ["and"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, "Logical AND requires two values on stack, got: 1"} = result
    end

    test "returns error for logical AND with empty stack" do
      instructions = [["and"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, "Logical AND requires two values on stack, got: 0"} = result
    end

    test "returns error for logical OR with non-boolean values" do
      instructions = [["lit", "hello"], ["lit", false], ["or"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, _message} = result
      assert match?({:error, "Logical OR requires two boolean values" <> _}, result)
    end

    test "returns error for logical OR with insufficient stack" do
      instructions = [["lit", false], ["or"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, "Logical OR requires two values on stack, got: 1"} = result
    end

    test "returns error for logical OR with empty stack" do
      instructions = [["or"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, "Logical OR requires two values on stack, got: 0"} = result
    end

    test "returns error for logical NOT with non-boolean value" do
      instructions = [["lit", 123], ["not"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, "Logical NOT requires a boolean value, got: 123"} = result
    end

    test "returns error for logical NOT with empty stack" do
      instructions = [["not"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, "Logical NOT requires one value on stack, got: 0"} = result
    end

    test "complex logical expression with variables" do
      # (score > 85 AND age >= 18) OR admin = true
      instructions = [
        ["load", "score"],
        ["lit", 85],
        ["compare", "GT"],
        ["load", "age"],
        ["lit", 18],
        ["compare", "GTE"],
        ["and"],
        ["load", "admin"],
        ["lit", true],
        ["compare", "EQ"],
        ["or"]
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
      # score > 85 AND NOT expired
      instructions = [
        ["load", "score"],
        ["lit", 85],
        ["compare", "GT"],
        ["load", "expired"],
        ["not"],
        ["and"]
      ]

      context = %{"score" => 90, "expired" => false}
      assert Evaluator.evaluate(instructions, context) == true

      context = %{"score" => 80, "expired" => false}
      assert Evaluator.evaluate(instructions, context) == false

      context = %{"score" => 90, "expired" => true}
      assert Evaluator.evaluate(instructions, context) == false
    end
  end
end
