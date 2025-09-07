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
      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} = result
      assert msg =~ "Logical AND requires booleans"
    end

    test "returns error for logical AND with insufficient stack" do
      instructions = [["lit", true], ["and"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg =~ "Logical AND requires 2 values on stack, got: 1"
    end

    test "returns error for logical AND with empty stack" do
      instructions = [["and"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg =~ "Logical AND requires 2 values on stack, got: 0"
    end

    test "returns error for logical OR with non-boolean values" do
      instructions = [["lit", "hello"], ["lit", false], ["or"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.TypeMismatchError{message: msg}} = result
      assert msg =~ "Logical OR requires booleans"
    end

    test "returns error for logical OR with insufficient stack" do
      instructions = [["lit", false], ["or"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg =~ "Logical OR requires 2 values on stack, got: 1"
    end

    test "returns error for logical OR with empty stack" do
      instructions = [["or"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = result
      assert msg =~ "Logical OR requires 2 values on stack, got: 0"
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

    test "handles logical operations with insufficient stack values" do
      # AND with only one value
      instructions = [["lit", true], ["and"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: message}} = result
      assert message =~ "Logical AND requires 2 values on stack, got: 1"

      # OR with only one value
      instructions = [["lit", false], ["or"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.EvaluationError{message: message}} = result
      assert message =~ "Logical OR requires 2 values on stack, got: 1"

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

    test "handles type mismatches in logical operations" do
      # AND with non-boolean values
      instructions = [["lit", 1], ["lit", "hello"], ["and"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.TypeMismatchError{message: message}} = result
      assert message =~ "Logical AND requires booleans"

      # OR with non-boolean values
      instructions = [["lit", 42], ["lit", true], ["or"]]
      result = Evaluator.evaluate(instructions)
      assert {:error, %Predicator.Errors.TypeMismatchError{message: message}} = result
      assert message =~ "Logical OR requires booleans"

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

    test "handles string key fallback to atom key" do
      instructions = [
        ["load", "user"],
        ["lit", "role"],
        ["bracket_access"]
      ]

      # atom key only
      context = %{"user" => %{role: "admin"}}

      assert Evaluator.evaluate(instructions, context) == "admin"
    end

    test "handles atom key fallback gracefully" do
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
      # Simulate: created_at > 1d ago AND updated_at < 1h from now
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
        ["lit", near_future],
        ["duration", [[1, "h"]]],
        ["relative_date", "future"],
        ["compare", "LT"],
        ["and"]
      ]

      result = Evaluator.evaluate(instructions)
      # Both conditions should be true
      assert result == true
    end
  end
end
