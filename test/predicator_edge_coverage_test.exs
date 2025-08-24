defmodule PredicatorEdgeCoverageTest do
  use ExUnit.Case, async: true

  import Predicator

  describe "predicator.ex specific coverage" do
    test "compile! function with errors" do
      # Test the bang version that raises on errors
      assert_raise RuntimeError, ~r/Compilation failed/, fn ->
        compile!("invalid >> syntax")
      end
    end

    test "evaluate! edge cases" do
      # Test evaluate! with various error types
      # Note: undefined variables don't raise errors in evaluate!, they return {:error, ...}
      # So test with a real evaluation error instead
      assert_raise RuntimeError, ~r/Evaluation failed/, fn ->
        evaluate!("10 / 0", %{})
      end

      assert_raise RuntimeError, ~r/Evaluation failed/, fn ->
        evaluate!("10 / 0", %{})
      end

      # Test successful cases
      assert 42 = evaluate!([["lit", 42]], %{})
      assert true = evaluate!("true", %{})
    end

    test "evaluate_value! edge cases" do
      # Test the bang version with errors
      assert_raise RuntimeError, ~r/Evaluation failed:/, fn ->
        evaluate!("undefined_var", %{})
      end

      assert_raise RuntimeError, ~r/Evaluation failed:/, fn ->
        evaluate!("'hello' + 5", %{})
      end

      # Test with custom functions
      custom_functions = %{
        "double" => {1, fn [n], _context -> {:ok, n * 2} end}
      }

      assert 84 = evaluate!("double(42)", %{}, functions: custom_functions)
    end

    test "evaluator and run_evaluator functions" do
      # Test the low-level evaluator API
      evaluator_state = evaluator([["lit", 42]], %{})
      assert evaluator_state.instructions == [["lit", 42]]
      assert evaluator_state.context == %{}

      {:ok, final_state} = run_evaluator(evaluator_state)
      assert final_state.stack == [42]
    end

    test "parse function edge cases" do
      # Test successful parsing
      assert {:ok, ast} = parse("true AND false")
      assert is_tuple(ast)

      # Test parse errors
      assert {:error, message, line, column} = parse("invalid >>")
      assert is_binary(message)
      assert is_integer(line) and is_integer(column)
    end

    test "various context key types" do
      # Test with atom keys
      atom_context = %{score: 85, active: true}
      assert {:ok, 85} = evaluate("score", atom_context)
      assert {:ok, true} = evaluate("active", atom_context)

      # Test mixed key types
      mixed_context = %{"score" => 85, :active => true}
      assert {:ok, 85} = evaluate("score", mixed_context)
      assert {:ok, true} = evaluate("active", mixed_context)
    end

    test "edge case expressions for error path coverage" do
      # Test expressions that trigger different error conversion paths

      # Test insufficient operands error conversion
      assert {:error, %Predicator.Errors.EvaluationError{reason: "insufficient_operands"}} =
               evaluate([["add"]], %{})

      # Test custom function error that doesn't match known patterns
      custom_functions = %{
        "custom_error" =>
          {0,
           fn [], _context ->
             {:error, "Some very specific custom error message"}
           end}
      }

      assert {:error,
              %Predicator.Errors.EvaluationError{
                reason: "Some very specific custom error message"
              }} =
               evaluate("custom_error()", %{}, functions: custom_functions)
    end

    test "arithmetic error extraction edge cases" do
      # Test scenarios that exercise the type extraction functions

      # Test with undefined values in arithmetic
      context = %{"undef_val" => :undefined}

      assert {:error,
              %Predicator.Errors.TypeMismatchError{
                expected: :integer,
                got: {:undefined, :integer},
                values: {:undefined, 5}
              }} =
               evaluate("undef_val + 5", context)

      # Test with complex type combinations
      assert {:error, %Predicator.Errors.TypeMismatchError{expected: :integer}} =
               evaluate("#2024-01-01# * 'hello'", %{})
    end

    test "string_to_type function coverage through errors" do
      # Create errors with different type names to cover all branches
      test_cases = [
        {%{"val" => "string"}, "!val", :string},
        {%{"val" => 42}, "!val", :integer},
        {%{"val" => true}, "-val", :boolean},
        {%{"val" => [1, 2]}, "!val", :list},
        {%{"val" => ~D[2024-01-01]}, "!val", :date},
        {%{"val" => ~U[2024-01-01 10:00:00Z]}, "-val", :datetime}
      ]

      for {context, expr, expected_type} <- test_cases do
        assert {:error, %Predicator.Errors.TypeMismatchError{got: ^expected_type}} =
                 evaluate(expr, context)
      end
    end

    test "nested variable access error cases" do
      # Test undefined nested access
      context = %{"user" => %{"name" => "John"}}

      # Undefined nested access returns an undefined_variable error
      assert {:error, %Predicator.Errors.UndefinedVariableError{variable: "user.undefined_field"}} =
               evaluate("user.undefined_field", context)

      # Test access on non-map value - this also becomes undefined_variable error
      context2 = %{"user" => "not_a_map"}

      assert {:error, %Predicator.Errors.UndefinedVariableError{variable: "user.name"}} =
               evaluate("user.name", context2)
    end

    test "comprehensive operator coverage" do
      # Test all operators in various combinations to ensure complete coverage
      context = %{
        "a" => 5,
        "b" => 10,
        "c" => true,
        "d" => false,
        "str1" => "hello",
        "str2" => "world",
        "list1" => [1, 2, 3],
        "item" => 2,
        "date1" => ~D[2024-01-01],
        "date2" => ~D[2024-12-31]
      }

      # Arithmetic combinations
      assert {:ok, 15} = evaluate("a + b", context)
      assert {:ok, -5} = evaluate("a - b", context)
      assert {:ok, 50} = evaluate("a * b", context)
      # Integer division
      assert {:ok, 0} = evaluate("a / b", context)
      assert {:ok, 5} = evaluate("a % b", context)

      # Comparison combinations
      assert {:ok, true} = evaluate("a < b", context)
      assert {:ok, false} = evaluate("a > b", context)
      assert {:ok, true} = evaluate("a <= b", context)
      assert {:ok, false} = evaluate("a >= b", context)
      assert {:ok, false} = evaluate("a = b", context)
      assert {:ok, true} = evaluate("a != b", context)

      # Logical combinations
      assert {:ok, false} = evaluate("c AND d", context)
      assert {:ok, true} = evaluate("c OR d", context)
      assert {:ok, false} = evaluate("NOT c", context)

      # Membership combinations
      assert {:ok, true} = evaluate("item in list1", context)
      assert {:ok, true} = evaluate("list1 contains item", context)

      # Date comparisons
      assert {:ok, true} = evaluate("date1 < date2", context)
      assert {:ok, false} = evaluate("date1 > date2", context)
    end
  end

  describe "instruction evaluation edge cases" do
    test "direct instruction evaluation with various instruction types" do
      # Test instructions that might not be hit by string expressions

      # Test literal instructions with various types
      instructions = [
        ["lit", 42],
        ["lit", "hello"],
        ["lit", true],
        ["lit", [1, 2, 3]],
        ["lit", ~D[2024-01-01]]
      ]

      for [op, value] <- instructions do
        assert {:ok, ^value} = evaluate([[op, value]], %{})
      end
    end

    test "load instruction with nested keys" do
      context = %{
        "user" => %{
          "profile" => %{
            "settings" => %{"theme" => "dark"}
          }
        }
      }

      # Test the nested load functionality
      assert {:ok, "dark"} = evaluate([["load", "user.profile.settings.theme"]], context)
    end

    test "function call instructions" do
      # Test function call instructions directly

      # Built-in function
      assert {:ok, 5} = evaluate([["lit", "hello"], ["call", "len", 1]], %{})

      # Custom function
      custom_functions = %{
        "add_ten" => {1, fn [n], _context -> {:ok, n + 10} end}
      }

      assert {:ok, 15} =
               evaluate([["lit", 5], ["call", "add_ten", 1]], %{}, functions: custom_functions)
    end
  end
end
