defmodule CoverageImprovementTest do
  use ExUnit.Case, async: true

  import Predicator
  alias Predicator.Evaluator

  describe "system functions error coverage" do
    test "date functions with invalid arguments" do
      # year() with non-date argument
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("year('not_a_date')", %{})

      assert msg =~ "year() expects a date or datetime argument"

      # month() with non-date argument
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("month(42)", %{})

      assert msg =~ "month() expects a date or datetime argument"

      # day() with non-date argument
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("day(true)", %{})

      assert msg =~ "day() expects a date or datetime argument"

      # Wrong number of arguments
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = evaluate("year()", %{})
      assert msg =~ "Function year() expects 1 arguments, got 0"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("month(#2024-01-01#, #2024-01-02#)", %{})

      assert msg =~ "Function month() expects 1 arguments, got 2"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("day([1, 2, 3])", %{})

      assert msg =~ "day() expects a date or datetime argument"
    end

    test "string functions with invalid arguments" do
      # len() with non-string
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = evaluate("len(42)", %{})
      assert msg =~ "len() expects a string argument"

      # upper() with non-string
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("upper([1, 2])", %{})

      assert msg =~ "upper() expects a string argument"

      # lower() with non-string
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("lower(true)", %{})

      assert msg =~ "lower() expects a string argument"

      # trim() with non-string
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("trim(#2024-01-01#)", %{})

      assert msg =~ "trim() expects a string argument"

      # Wrong argument count
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("len('a', 'b')", %{})

      assert msg =~ "Function len() expects 1 arguments, got 2"
    end

    test "numeric functions with invalid arguments" do
      # abs() with non-numeric
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("abs('not_a_number')", %{})

      assert msg =~ "abs() expects a numeric argument"

      # max() with non-numeric arguments
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("max('a', 'b')", %{})

      assert msg =~ "max() expects two numeric arguments"

      # min() with non-numeric arguments
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("min(true, false)", %{})

      assert msg =~ "min() expects two numeric arguments"

      # Wrong argument count
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               evaluate("abs(1, 2)", %{})

      assert msg =~ "Function abs() expects 1 arguments, got 2"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = evaluate("max(5)", %{})
      assert msg =~ "Function max() expects 2 arguments, got 1"

      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} = evaluate("min()", %{})
      assert msg =~ "Function min() expects 2 arguments, got 0"
    end
  end

  describe "error conversion coverage" do
    test "convert_to_structured_error with various error types" do
      # Test division by zero conversion
      assert {:error, %Predicator.Errors.EvaluationError{reason: "division_by_zero"}} =
               evaluate("10 / 0", %{})

      # Test modulo by zero conversion
      assert {:error, %Predicator.Errors.EvaluationError{reason: "modulo_by_zero"}} =
               evaluate("10 % 0", %{})

      # Test arithmetic type errors
      assert {:error,
              %Predicator.Errors.TypeMismatchError{
                expected: :integer,
                got: {:string, :integer},
                values: {"hello", 5}
              }} =
               evaluate("'hello' + 5", %{})

      # Test unary type errors
      assert {:error,
              %Predicator.Errors.TypeMismatchError{
                expected: :integer,
                got: :string,
                values: "text"
              }} =
               evaluate("-'text'", %{})

      assert {:error,
              %Predicator.Errors.TypeMismatchError{expected: :boolean, got: :integer, values: 42}} =
               evaluate("!42", %{})
    end

    test "extract_types_from_arithmetic_error edge cases" do
      # This tests the private functions indirectly through evaluate_value

      # Single type error (when one operand is correct type)
      assert {:error,
              %Predicator.Errors.TypeMismatchError{
                expected: :integer,
                got: {:integer, :string},
                values: {5, "hello"}
              }} =
               evaluate("5 + 'hello'", %{})

      # Mixed types
      assert {:error,
              %Predicator.Errors.TypeMismatchError{
                expected: :integer,
                got: {:boolean, :list},
                values: {true, [1, 2, 3]}
              }} =
               evaluate("true * [1, 2, 3]", %{})
    end

    test "undefined variable handling" do
      # Simple undefined variable
      assert {:error, %Predicator.Errors.UndefinedVariableError{variable: "missing_var"}} =
               evaluate("missing_var", %{})

      # Undefined in arithmetic
      assert {:ok, :undefined} =
               evaluate("undefined_value", %{"undefined_value" => :undefined})
    end

    test "pre-compiled instructions with evaluate_value" do
      # Test the instruction list path of evaluate_value
      instructions = [["lit", 5], ["lit", 3], ["add"]]
      assert {:ok, 8} = evaluate(instructions, %{})

      # Test error with pre-compiled instructions
      instructions = [["lit", "hello"], ["lit", 5], ["add"]]

      assert {:error,
              %Predicator.Errors.TypeMismatchError{
                expected: :integer,
                got: {:string, :integer},
                values: {"hello", 5}
              }} =
               evaluate(instructions, %{})
    end
  end

  describe "edge case instruction handling" do
    test "unknown instruction types" do
      # Test unknown instruction directly through evaluator
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate([["completely_unknown", "arg1", "arg2"]], %{})

      assert msg =~ "Unknown instruction"
    end

    test "malformed comparison operators" do
      # Test invalid comparison operators
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate([["lit", 5], ["lit", 3], ["compare", "INVALID"]], %{})

      assert msg =~ "Unknown instruction"
    end

    test "function calls with undefined functions" do
      # Test calling completely unknown function
      assert {:error, %Predicator.Errors.EvaluationError{message: msg}} =
               Evaluator.evaluate([["lit", 5], ["call", "nonexistent_function", 1]], %{})

      assert msg =~ "Unknown function: nonexistent_function"
    end
  end

  describe "datetime function coverage" do
    test "year/month/day functions with DateTime values" do
      datetime = ~U[2024-03-15 14:30:00Z]
      context = %{"dt" => datetime}

      assert {:ok, 2024} = evaluate("year(dt)", context)
      assert {:ok, 3} = evaluate("month(dt)", context)
      assert {:ok, 15} = evaluate("day(dt)", context)
    end

    test "string functions comprehensive coverage" do
      context = %{"text" => "  Hello World  ", "empty" => ""}

      # Test trim with various whitespace
      assert {:ok, "Hello World"} = evaluate("trim(text)", context)
      assert {:ok, ""} = evaluate("trim(empty)", context)

      # Test upper/lower with empty strings and special characters
      assert {:ok, ""} = evaluate("upper(empty)", context)
      assert {:ok, "  HELLO WORLD  "} = evaluate("upper(text)", context)
      assert {:ok, ""} = evaluate("lower(empty)", context)
      assert {:ok, "  hello world  "} = evaluate("lower(text)", context)
    end
  end

  describe "parser edge cases" do
    test "deeply nested expressions" do
      # Test parser with complex nesting
      assert {:ok, true} = evaluate("((((true))))", %{})
      assert {:ok, 30} = evaluate("(((2 + 3)) * ((4 + 2)))", %{})
    end

    test "complex function call parsing" do
      # Test parsing of functions with multiple arguments
      assert {:ok, 7} = evaluate("max(3, max(5, 7))", %{})
      assert {:ok, 3} = evaluate("min(min(8, 5), 3)", %{})
    end

    test "mixed operator precedence" do
      # Test complex precedence scenarios
      assert {:ok, true} = evaluate("2 + 3 * 4 > 10 AND 5 < 10", %{})
      assert {:ok, true} = evaluate("NOT false AND 2 > 3 OR true", %{})
    end
  end
end
