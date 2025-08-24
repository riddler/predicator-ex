defmodule PredicatorApiCoverageTest do
  use ExUnit.Case, async: true

  import Predicator

  describe "predicator.ex API coverage" do
    test "compile! function with errors" do
      # Test the bang version that raises on errors
      assert_raise RuntimeError, ~r/Compilation failed/, fn ->
        compile!("invalid >> syntax")
      end
    end

    test "evaluate! edge cases" do
      # Test evaluate! with various error types
      assert_raise RuntimeError, ~r/Evaluation failed/, fn ->
        evaluate!("10 / 0", %{})
      end

      # Test with custom functions
      custom_functions = %{
        "double" => {1, fn [n], _context -> {:ok, n * 2} end}
      }

      assert 84 =
               evaluate!([["lit", 42], ["call", "double", 1]], %{}, functions: custom_functions)

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

    test "decompile function with various formatting options" do
      {:ok, ast} = parse("score > 85")

      # Test different formatting modes
      assert is_binary(decompile(ast))
      assert is_binary(decompile(ast, parentheses: :minimal))
      assert is_binary(decompile(ast, parentheses: :explicit))
      assert is_binary(decompile(ast, spacing: :compact))
      assert is_binary(decompile(ast, spacing: :verbose))
    end

    test "evaluate_value with undefined variables" do
      # Simple undefined variable
      assert {:error, %Predicator.Errors.UndefinedVariableError{variable: "missing_var"}} =
               evaluate("missing_var", %{})

      # Undefined in context but with :undefined value
      assert {:ok, :undefined} =
               evaluate("undefined_value", %{"undefined_value" => :undefined})

      # Test with atom key context
      assert {:ok, :undefined} =
               evaluate("undefined_value", %{undefined_value: :undefined})
    end

    test "evaluate_value with pre-compiled instructions" do
      # Test the instruction list path of evaluate_value
      instructions = [["lit", 5], ["lit", 3], ["add"]]
      assert {:ok, 8} = evaluate(instructions, %{})

      # Test error with pre-compiled instructions
      instructions = [["lit", "hello"], ["lit", 5], ["add"]]

      assert {:error, %Predicator.Errors.TypeMismatchError{expected: :integer}} =
               evaluate(instructions, %{})
    end

    test "evaluate_value parse error handling" do
      # Test parse error conversion to structured format
      assert {:error, %Predicator.Errors.ParseError{message: msg, line: 1, column: _col}} =
               evaluate("invalid >>", %{})

      assert is_binary(msg)
    end

    test "convert_to_structured_error with various error messages" do
      # Test different error message patterns that trigger different conversions

      # Test insufficient operands error
      assert {:error, %Predicator.Errors.EvaluationError{reason: "insufficient_operands"}} =
               evaluate([["add"]], %{})

      # Test custom function error
      custom_functions = %{
        "custom_error" =>
          {0,
           fn [], _context ->
             {:error, "Custom function failed"}
           end}
      }

      assert {:error, %Predicator.Errors.EvaluationError{reason: "Custom function failed"}} =
               evaluate("custom_error()", %{}, functions: custom_functions)
    end

    test "type extraction from error messages" do
      # Test various type combinations to exercise type extraction functions

      # Test with list type
      assert {:error,
              %Predicator.Errors.TypeMismatchError{
                expected: :integer,
                got: :list,
                values: [1, 2, 3]
              }} =
               evaluate("-[1, 2, 3]", %{})

      # Test with date type
      assert {:error, %Predicator.Errors.TypeMismatchError{expected: :boolean, got: :date}} =
               evaluate("!#2024-01-01#", %{})

      # Test with datetime type
      assert {:error, %Predicator.Errors.TypeMismatchError{expected: :integer, got: :datetime}} =
               evaluate("-#2024-01-01T10:00:00Z#", %{})

      # Test with undefined type
      context = %{"undef_val" => :undefined}

      assert {:error,
              %Predicator.Errors.TypeMismatchError{
                expected: :integer,
                got: {:undefined, :integer},
                values: {:undefined, 5}
              }} =
               evaluate("undef_val + 5", context)
    end

    test "complex arithmetic error type extraction" do
      # Test scenarios that exercise different branches of type extraction

      # Test mixed types in arithmetic
      assert {:error, %Predicator.Errors.TypeMismatchError{expected: :integer}} =
               evaluate("true * 'hello'", %{})

      # Test date arithmetic with string
      assert {:error, %Predicator.Errors.TypeMismatchError{expected: :integer}} =
               evaluate("#2024-01-01# * 'hello'", %{})
    end

    test "nested variable access in undefined detection" do
      # Test complex expressions that result in undefined variable detection
      context = %{"user" => %{"name" => "John"}}

      # This should be an undefined variable error
      assert {:error, %Predicator.Errors.UndefinedVariableError{variable: "user.missing"}} =
               evaluate("user.missing", context)
    end

    test "check_for_undefined_variables edge cases" do
      # Test the edge case handling in check_for_undefined_variables

      # Test with String.to_atom raising ArgumentError
      # This should cause ArgumentError in to_atom
      very_long_var = String.duplicate("a", 1000)

      assert {:error, %Predicator.Errors.UndefinedVariableError{variable: ^very_long_var}} =
               evaluate(very_long_var, %{})
    end

    test "binary type mismatch error handling" do
      # Test scenarios that generate binary type mismatch errors

      # These test different branches in the type mismatch error handling
      assert {:error,
              %Predicator.Errors.TypeMismatchError{
                expected: :integer,
                got: {:integer, :string},
                values: {5, "hello"}
              }} =
               evaluate("5 + 'hello'", %{})

      assert {:error,
              %Predicator.Errors.TypeMismatchError{
                expected: :integer,
                got: {:integer, :boolean},
                values: {10, true}
              }} =
               evaluate("10 - true", %{})
    end

    test "evaluate with RuntimeError conversion" do
      # Test the main evaluate functions handle RuntimeError conversion properly

      # String expression with error
      assert {:error, %Predicator.Errors.EvaluationError{message: message}} =
               evaluate("10 / 0", %{})

      assert is_binary(message)
      assert message =~ "Division by zero"

      # Instruction list with error
      assert {:error, %Predicator.Errors.TypeMismatchError{message: message}} =
               evaluate([["lit", "hello"], ["lit", 5], ["add"]], %{})

      assert is_binary(message)
    end

    test "evaluate with various input types" do
      # Test different clause matching in evaluate/3

      # Binary expression with empty context
      assert {:ok, true} = evaluate("true", %{})

      # Instruction list with context
      assert {:ok, 5} = evaluate([["lit", 5]], %{"x" => 10})

      # With options
      custom_functions = %{"double" => {1, fn [n], _context -> {:ok, n * 2} end}}
      assert {:ok, 10} = evaluate("double(5)", %{}, functions: custom_functions)
    end

    test "edge cases in string_to_type function" do
      # These test the private string_to_type function through error messages
      # by creating errors that contain various type names

      test_cases = [
        {%{"val" => "string"}, "!val", :string},
        {%{"val" => 42}, "!val", :integer},
        {%{"val" => true}, "-val", :boolean},
        {%{"val" => [1, 2]}, "!val", :list},
        {%{"val" => ~D[2024-01-01]}, "!val", :date},
        {%{"val" => ~U[2024-01-01 10:00:00Z]}, "-val", :datetime},
        {%{"val" => :undefined}, "-val", :undefined}
      ]

      for {context, expr, expected_type} <- test_cases do
        assert {:error, %Predicator.Errors.TypeMismatchError{got: ^expected_type}} =
                 evaluate(expr, context)
      end
    end
  end
end
