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

  describe "evaluate/2 with nested context access (dot notation)" do
    test "loads nested value with string keys" do
      instructions = [["load", "user.name.first"]]
      context = %{"user" => %{"name" => %{"first" => "John", "last" => "Doe"}, "age" => 47}}

      assert Evaluator.evaluate(instructions, context) == "John"
    end

    test "loads nested value with atom keys" do
      instructions = [["load", "user.name.first"]]
      context = %{user: %{name: %{first: "John", last: "Doe"}, age: 47}}

      assert Evaluator.evaluate(instructions, context) == "John"
    end

    test "loads nested value with mixed string and atom keys" do
      instructions = [["load", "user.name.first"]]
      context = %{"user" => %{name: %{"first" => "John", "last" => "Doe"}, age: 47}}

      assert Evaluator.evaluate(instructions, context) == "John"
    end

    test "loads top-level nested value" do
      instructions = [["load", "user.age"]]
      context = %{"user" => %{"name" => %{"first" => "John"}, "age" => 47}}

      assert Evaluator.evaluate(instructions, context) == 47
    end

    test "returns :undefined for missing nested key" do
      instructions = [["load", "user.name.middle"]]
      context = %{"user" => %{"name" => %{"first" => "John", "last" => "Doe"}}}

      assert Evaluator.evaluate(instructions, context) == :undefined
    end

    test "returns :undefined for missing parent key" do
      instructions = [["load", "user.profile.name"]]
      context = %{"user" => %{"name" => "John"}}

      assert Evaluator.evaluate(instructions, context) == :undefined
    end

    test "returns :undefined when intermediate value is not a map" do
      instructions = [["load", "user.name.first"]]
      context = %{"user" => %{"name" => "John Doe"}}

      assert Evaluator.evaluate(instructions, context) == :undefined
    end

    test "returns :undefined for completely missing root key" do
      instructions = [["load", "profile.name.first"]]
      context = %{"user" => %{"name" => "John"}}

      assert Evaluator.evaluate(instructions, context) == :undefined
    end

    test "handles deeply nested structures" do
      instructions = [["load", "data.level1.level2.level3.value"]]

      context = %{
        "data" => %{
          "level1" => %{
            "level2" => %{
              "level3" => %{
                "value" => "deep_value"
              }
            }
          }
        }
      }

      assert Evaluator.evaluate(instructions, context) == "deep_value"
    end

    test "nested access with list values" do
      instructions = [["load", "user.hobbies"]]
      context = %{"user" => %{"name" => "John", "hobbies" => ["reading", "coding"]}}

      assert Evaluator.evaluate(instructions, context) == ["reading", "coding"]
    end

    test "nested access with various data types" do
      instructions = [["load", "config.settings.enabled"]]
      context = %{"config" => %{"settings" => %{"enabled" => true, "count" => 42}}}

      assert Evaluator.evaluate(instructions, context) == true
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

  describe "error handling edge cases" do
    test "handles unknown instruction gracefully" do
      instructions = [["unknown_instruction", "arg"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, message} = result
      assert message =~ "Unknown instruction"
    end

    test "handles comparison with insufficient stack values" do
      # Only one value on stack
      instructions = [["lit", 42], ["compare", "GT"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, message} = result
      assert message =~ "Comparison requires two values on stack, got: 1"
    end

    test "handles logical operations with insufficient stack values" do
      # AND with only one value
      instructions = [["lit", true], ["and"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, message} = result
      assert message =~ "Logical AND requires two values on stack, got: 1"

      # OR with only one value
      instructions = [["lit", false], ["or"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, message} = result
      assert message =~ "Logical OR requires two values on stack, got: 1"

      # NOT with no values
      instructions = [["not"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, message} = result
      assert message =~ "Logical NOT requires one value on stack, got: 0"
    end

    test "handles membership operations with insufficient stack values" do
      # IN with only one value
      instructions = [["lit", 1], ["in"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, message} = result
      assert message =~ "IN requires two values on stack, got: 1"

      # CONTAINS with only one value
      instructions = [["lit", [1, 2]], ["contains"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, message} = result
      assert message =~ "CONTAINS requires two values on stack, got: 1"
    end

    test "handles type mismatches in logical operations" do
      # AND with non-boolean values
      instructions = [["lit", 1], ["lit", "hello"], ["and"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, message} = result
      assert message =~ "Logical AND requires two boolean values"

      # OR with non-boolean values
      instructions = [["lit", 42], ["lit", true], ["or"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, message} = result
      assert message =~ "Logical OR requires two boolean values"

      # NOT with non-boolean value
      instructions = [["lit", "not_boolean"], ["not"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, message} = result
      assert message =~ "Logical NOT requires a boolean value"
    end

    test "handles invalid membership operations" do
      # IN with non-list on right side
      instructions = [["lit", 1], ["lit", "not_a_list"], ["in"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, message} = result
      assert message =~ "IN operator requires a list on the right side"

      # CONTAINS with non-list on left side
      instructions = [["lit", "not_a_list"], ["lit", 1], ["contains"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, message} = result
      assert message =~ "CONTAINS operator requires a list on the left side"
    end

    test "handles atom key lookup in context" do
      # Test loading from context with atom keys
      instructions = [["load", "score"]]
      # atom key
      context = %{score: 85}
      assert Evaluator.evaluate(instructions, context) == 85

      # Test when both string and atom keys exist (string takes precedence)
      instructions = [["load", "name"]]
      context = %{"name" => "string_key", name: "atom_key"}
      assert Evaluator.evaluate(instructions, context) == "string_key"

      # Test loading non-existent key that can't be converted to atom
      instructions = [["load", "very_long_key_that_does_not_exist_anywhere"]]
      context = %{}
      assert Evaluator.evaluate(instructions, context) == :undefined
    end
  end
end
