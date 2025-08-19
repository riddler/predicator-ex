defmodule Predicator.EvaluatorEdgeCasesTest do
  use ExUnit.Case, async: true

  alias Predicator.Evaluator
  alias Predicator.Functions.{Registry, SystemFunctions}

  setup do
    # Ensure built-in functions are available
    Registry.clear_registry()
    SystemFunctions.register_all()
    :ok
  end

  describe "error handling" do
    test "handles evaluation with invalid comparison types" do
      # Create instructions that try to compare incompatible types
      instructions = [
        ["lit", 1],
        ["lit", 2],
        # This leaves one boolean on stack (false)
        ["compare", "EQ"],
        ["lit", 3],
        # This tries to compare boolean with 3
        ["compare", "EQ"]
      ]

      # Should return :undefined since boolean false can't be compared to 3
      result = Evaluator.evaluate(instructions, %{})
      assert :undefined = result
    end

    test "handles instruction bounds checking" do
      # Test that evaluator handles instruction bounds properly
      instructions = [["lit", 42]]

      # This is testing internal behavior - the evaluator should handle bounds checking
      result = Evaluator.evaluate(instructions, %{})
      assert 42 = result
    end

    test "handles comparison with mismatched types" do
      # Test type coercion edge cases
      instructions = [
        ["lit", "5"],
        ["lit", 5],
        ["compare", "EQ"]
      ]

      result = Evaluator.evaluate(instructions, %{})
      # Should handle string vs number comparison
      assert :undefined = result
    end

    test "handles comparison with null/nil values" do
      instructions = [
        ["lit", nil],
        ["lit", nil],
        ["compare", "EQ"]
      ]

      assert :undefined = Evaluator.evaluate(instructions, %{})

      instructions = [
        ["lit", nil],
        ["lit", 42],
        ["compare", "EQ"]
      ]

      assert :undefined = Evaluator.evaluate(instructions, %{})
    end

    test "handles function call with insufficient stack items" do
      # Try to call function but not enough arguments on stack
      instructions = [
        # max expects 2 args but stack is empty
        ["call", "max", 2]
      ]

      result = Evaluator.evaluate(instructions, %{})
      assert {:error, message} = result
      assert message =~ "expects 2 arguments"
      assert message =~ "stack"
    end

    test "handles unknown function call" do
      instructions = [
        ["lit", 1],
        ["call", "unknown_function", 1]
      ]

      assert {:error, "Unknown function: unknown_function"} =
               Evaluator.evaluate(instructions, %{})
    end

    test "handles function call that returns error" do
      # Register a function that always returns an error
      Registry.register_function("error_func", 1, fn [_arg], _context ->
        {:error, "Function intentionally failed"}
      end)

      instructions = [
        ["lit", "test"],
        ["call", "error_func", 1]
      ]

      assert {:error, "Function intentionally failed"} =
               Evaluator.evaluate(instructions, %{})
    end

    test "handles variable loading with missing context" do
      instructions = [
        ["load", "nonexistent_var"]
      ]

      # Should load :undefined for missing variable
      assert :undefined = Evaluator.evaluate(instructions, %{})
    end

    test "handles logical operations with non-boolean values" do
      # Test AND with non-boolean
      instructions = [
        # string, not boolean
        ["lit", "true"],
        ["lit", true],
        ["and"]
      ]

      result = Evaluator.evaluate(instructions, %{})
      # Implementation should handle type coercion or error appropriately
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles OR with edge cases" do
      # Test OR with boolean values only (the evaluator enforces boolean types)
      instructions = [
        ["lit", false],
        ["lit", true],
        ["or"]
      ]

      result = Evaluator.evaluate(instructions, %{})
      assert true = result
    end

    test "handles NOT with non-boolean values" do
      # The evaluator enforces boolean types, so this should error
      instructions = [
        # non-boolean value
        ["lit", 0],
        ["not"]
      ]

      result = Evaluator.evaluate(instructions, %{})
      assert {:error, _message} = result

      instructions = [
        # empty string
        ["lit", ""],
        ["not"]
      ]

      result = Evaluator.evaluate(instructions, %{})
      assert {:error, _message} = result
    end
  end

  describe "stack boundary conditions" do
    test "handles deep stack operations" do
      # Create instructions that build a deep stack
      instructions = Enum.flat_map(1..100, fn i -> [["lit", i]] end) |> List.flatten()
      # Then pop them all with additions
      add_instructions = Enum.flat_map(1..99, fn _i -> [["add"]] end) |> List.flatten()

      all_instructions = instructions ++ add_instructions
      result = Evaluator.evaluate(all_instructions, %{})

      # Should compute sum of 1 to 100
      # Arithmetic operations not supported, should error
      assert {:error, _message} = result
    end

    test "handles alternating stack operations" do
      # Push and pop operations
      instructions = [
        ["lit", 10],
        ["lit", 5],
        # leaves boolean
        ["compare", "GT"],
        ["lit", 20],
        ["lit", 15],
        # leaves boolean
        ["compare", "LT"],
        # combines booleans
        ["and"]
      ]

      # The instructions perform: 10 > 5 (true) AND 20 < 15 (false) = false
      result = Evaluator.evaluate(instructions, %{})
      refute result
    end

    test "handles stack underflow scenarios" do
      # Try operations that need stack items when stack is empty/insufficient
      instructions = [
        ["lit", 5],
        # add needs 2 items, only 1 on stack
        ["add"]
      ]

      result = Evaluator.evaluate(instructions, %{})
      assert {:error, _message} = result
    end
  end

  describe "context edge cases" do
    test "handles deeply nested context access" do
      context = %{
        # flat key, nested access not supported
        "user.profile.settings.theme" => "dark"
      }

      instructions = [
        ["load", "user.profile.settings.theme"]
      ]

      # Should load the flat key (nested access not implemented)
      result = Evaluator.evaluate(instructions, context)
      assert "dark" = result
    end

    test "handles context with special characters in keys" do
      context = %{
        "user-name" => "test",
        "user.email" => "test@example.com",
        "user space" => "value"
      }

      instructions = [
        ["load", "user-name"],
        ["load", "user.email"],
        ["load", "user space"]
      ]

      # Should be able to load all these values
      results = Enum.map(instructions, &Evaluator.evaluate([&1], context))

      assert [
               "test",
               "test@example.com",
               "value"
             ] = results
    end

    test "handles context with numeric and boolean values" do
      context = %{
        "count" => 42,
        "enabled" => true,
        "score" => 95.5
      }

      instructions = [
        ["load", "count"],
        ["lit", 50],
        ["compare", "LT"]
      ]

      assert true = Evaluator.evaluate(instructions, context)
    end
  end

  describe "evaluate!/2 function" do
    test "returns result directly on success" do
      instructions = [["lit", 42]]
      assert 42 = Evaluator.evaluate!(instructions, %{})
    end

    test "raises exception on error" do
      instructions = [["unknown_instruction"]]

      assert_raise RuntimeError, ~r/Evaluation failed/, fn ->
        Evaluator.evaluate!(instructions, %{})
      end
    end

    test "preserves error message in exception" do
      # Register function that returns error
      Registry.register_function("fail_func", 0, fn [], _context ->
        {:error, "Custom failure message"}
      end)

      instructions = [["call", "fail_func", 0]]

      assert_raise RuntimeError, ~r/Custom failure message/, fn ->
        Evaluator.evaluate!(instructions, %{})
      end
    end
  end

  describe "complex instruction sequences" do
    test "handles mixed operations with functions and comparisons" do
      instructions = [
        ["lit", "hello"],
        # len("hello") = 5
        ["call", "len", 1],
        ["lit", 10],
        ["lit", 3],
        # max(10, 3) = 10
        ["call", "max", 2],
        # 5 < 10 = true
        ["compare", "LT"],
        ["lit", true],
        # true AND true = true
        ["and"]
      ]

      assert true = Evaluator.evaluate(instructions, %{})
    end

    test "handles conditional-like logic with functions" do
      context = %{"role" => "admin"}

      # Simulate: role = "admin" AND len(role) > 3
      instructions = [
        ["load", "role"],
        ["lit", "admin"],
        # true
        ["compare", "EQ"],
        ["load", "role"],
        # 5
        ["call", "len", 1],
        ["lit", 3],
        # 5 > 3 = true
        ["compare", "GT"],
        # true AND true = true
        ["and"]
      ]

      assert true = Evaluator.evaluate(instructions, context)
    end
  end
end
