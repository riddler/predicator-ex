defmodule Predicator.EvaluatorBracketAccessTest do
  use ExUnit.Case, async: true

  alias Predicator.Evaluator

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
end
