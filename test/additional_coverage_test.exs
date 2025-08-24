defmodule AdditionalCoverageTest do
  use ExUnit.Case, async: true

  import Predicator

  describe "predicator.ex error conversion coverage" do
    test "extract_types_from_arithmetic_error with edge cases" do
      # Test malformed error messages that don't follow expected format
      # These test the fallback paths in the private functions

      # Test case where string split doesn't find "got "
      context = %{"a" => "hello", "b" => 5}

      assert {:error,
              %Predicator.Errors.TypeMismatchError{
                expected: :integer,
                got: {:string, :integer},
                values: {"hello", 5}
              }} =
               evaluate("a + b", context)
    end

    test "extract_type_from_unary_error edge cases" do
      # Test unary operations with various types
      assert {:error, %Predicator.Errors.TypeMismatchError{expected: :integer, got: :list}} =
               evaluate("-[1, 2, 3]", %{})

      assert {:error, %Predicator.Errors.TypeMismatchError{expected: :boolean, got: :date}} =
               evaluate("!#2024-01-01#", %{})
    end

    test "string_to_type function coverage" do
      # Test various type conversions through error messages
      test_cases = [
        {%{"x" => ~D[2024-01-01]}, "-x", :date},
        {%{"x" => ~U[2024-01-01 10:00:00Z]}, "-x", :datetime},
        {%{"x" => [1, 2]}, "-x", :list},
        {%{"x" => :undefined}, "-x", :undefined}
      ]

      for {context, expr, expected_type} <- test_cases do
        assert {:error, %Predicator.Errors.TypeMismatchError{got: ^expected_type}} =
                 evaluate(expr, context)
      end
    end

    test "check_for_undefined_variables edge cases" do
      # Test complex expressions that result in :undefined
      context = %{"maybe_undef" => :undefined}

      # This should return {:ok, :undefined} rather than error
      assert {:ok, :undefined} = evaluate("maybe_undef", context)

      # Test with complex expression involving undefined - this will be a type error
      assert {:error, %Predicator.Errors.TypeMismatchError{}} =
               evaluate("maybe_undef AND true", context)
    end

    test "convert_to_structured_error fallback cases" do
      # Test the catch-all case that returns generic evaluation error
      # We can trigger this by making a custom function return a complex error

      custom_functions = %{
        "weird_error" =>
          {0,
           fn [], _context ->
             {:error, "This is a custom error message that doesn't match any patterns"}
           end}
      }

      assert {:error, %Predicator.Errors.EvaluationError{}} =
               evaluate("weird_error()", %{}, functions: custom_functions)
    end
  end

  describe "parser edge cases for coverage" do
    test "deeply nested parentheses" do
      # Test parser with maximum nesting
      nested_expr = String.duplicate("(", 10) <> "true" <> String.duplicate(")", 10)
      assert {:ok, true} = evaluate(nested_expr, %{})
    end

    test "function calls with maximum arguments" do
      # Test function parsing with multiple nested calls
      expr = "max(min(1, 2), max(3, min(4, 5)))"
      assert {:ok, 4} = evaluate(expr, %{})
    end

    test "complex logical expressions with all operators" do
      # Test parser with all logical operators combined
      expr = "NOT (true AND false) OR (true AND NOT false)"
      assert {:ok, true} = evaluate(expr, %{})
    end

    test "list expressions with various types" do
      # Test list parsing with literal types (nested lists not supported yet)
      expr = "[1, 'string', true, #2024-01-01#]"
      assert {:ok, [1, "string", true, ~D[2024-01-01]]} = evaluate(expr, %{})
    end

    test "membership operations with complex expressions" do
      # Test membership parsing with complex operands
      expr = "(1 + 2) in [1, 2, 3, 4] AND [1, 2, 3] contains (2 * 1)"
      assert {:ok, true} = evaluate(expr, %{})
    end

    test "comparison chains with various operators" do
      # Test all comparison operators
      context = %{"a" => 5, "b" => 10, "c" => 5}

      test_cases = [
        {"a < b", true},
        {"b > a", true},
        {"a <= c", true},
        {"b >= a", true},
        {"a = c", true},
        {"a != b", true}
      ]

      for {expr, expected} <- test_cases do
        assert {:ok, ^expected} = evaluate(expr, context)
      end
    end

    test "arithmetic with all operators" do
      # Test all arithmetic operators in complex expressions
      expr = "((10 + 5) - 3) * 2 / 4 % 5"
      assert {:ok, 1} = evaluate(expr, %{})
    end

    test "nested data access variations" do
      # Test various nested access patterns
      context = %{
        "user" => %{
          "profile" => %{
            "settings" => %{
              "theme" => "dark",
              "lang" => "en"
            }
          },
          "name" => "John"
        }
      }

      assert {:ok, "dark"} = evaluate("user.profile.settings.theme", context)
      assert {:ok, "en"} = evaluate("user.profile.settings.lang", context)
      assert {:ok, "John"} = evaluate("user.name", context)
    end
  end

  describe "compiler edge cases" do
    test "AST to string conversion with complex expressions" do
      # Test decompile functionality with various AST structures
      test_cases = [
        "true AND false OR NOT true",
        "user.profile.name = 'John'",
        "[1, 2, 3] contains 2",
        "max(min(a, b), c) > 10",
        "#2024-01-01# < #2024-12-31#"
      ]

      for expr <- test_cases do
        {:ok, ast} = parse(expr)
        decompiled = decompile(ast)
        # Should be able to parse and evaluate the decompiled expression
        assert {:ok, _result} =
                 evaluate(decompiled, %{
                   "a" => 5,
                   "b" => 10,
                   "c" => 15,
                   "user" => %{"profile" => %{"name" => "John"}}
                 })
      end
    end

    test "decompile with formatting options" do
      # Test various formatting options
      {:ok, ast} = parse("a > b")

      # Test different formatting modes
      assert is_binary(decompile(ast, parentheses: :minimal))
      assert is_binary(decompile(ast, parentheses: :explicit))
      assert is_binary(decompile(ast, spacing: :compact))
      assert is_binary(decompile(ast, spacing: :verbose))
    end
  end

  describe "system functions comprehensive coverage" do
    test "date functions with edge cases" do
      # Test leap year dates
      leap_date = ~D[2024-02-29]
      assert {:ok, 2024} = evaluate("year(dt)", %{"dt" => leap_date})
      assert {:ok, 2} = evaluate("month(dt)", %{"dt" => leap_date})
      assert {:ok, 29} = evaluate("day(dt)", %{"dt" => leap_date})

      # Test end of year/month dates
      end_year = ~D[2023-12-31]
      assert {:ok, 12} = evaluate("month(dt)", %{"dt" => end_year})
      assert {:ok, 31} = evaluate("day(dt)", %{"dt" => end_year})
    end

    test "string functions with unicode and special characters" do
      context = %{
        "unicode" => "héllo wörld 🌍",
        "mixed" => "MiXeD cAsE",
        "special" => "  \t\n  spaced  \r\n  "
      }

      assert {:ok, 13} = evaluate("len(unicode)", context)
      assert {:ok, "HÉLLO WÖRLD 🌍"} = evaluate("upper(unicode)", context)
      assert {:ok, "héllo wörld 🌍"} = evaluate("lower(unicode)", context)

      assert {:ok, "MIXED CASE"} = evaluate("upper(mixed)", context)
      assert {:ok, "mixed case"} = evaluate("lower(mixed)", context)

      assert {:ok, "spaced"} = evaluate("trim(special)", context)
    end

    test "numeric functions with edge values" do
      # Test with zero, negative numbers, decimals
      test_cases = [
        {"abs(0)", 0},
        {"abs(-42)", 42},
        {"max(0, 0)", 0},
        {"min(-5, -10)", -10},
        {"max(-1, -2)", -1}
      ]

      for {expr, expected} <- test_cases do
        assert {:ok, ^expected} = evaluate(expr, %{})
      end
    end
  end

  describe "evaluator edge cases" do
    test "empty context operations" do
      # Test operations that work without any context
      expressions = [
        "true",
        "false",
        "42",
        "'hello'",
        "[1, 2, 3]",
        "1 + 2 * 3",
        "NOT false",
        "true AND true",
        "false OR true"
      ]

      for expr <- expressions do
        assert {:ok, _result} = evaluate(expr, %{})
      end
    end

    test "mixed type comparisons" do
      # Test comparisons that should work
      assert {:ok, true} = evaluate("5 > 3", %{})
      assert {:ok, false} = evaluate("'a' = 'b'", %{})
      assert {:ok, true} = evaluate("#2024-01-01# = #2024-01-01#", %{})
      assert {:ok, false} = evaluate("[1, 2] = [1, 3]", %{})
    end

    test "complex membership operations" do
      context = %{
        "numbers" => [1, 2, 3, 4, 5],
        "nested_lists" => [[1, 2], [3, 4], [5, 6]],
        "mixed" => [1, "string", true, ~D[2024-01-01]]
      }

      assert {:ok, true} = evaluate("3 in numbers", context)
      assert {:ok, false} = evaluate("6 in numbers", context)
      assert {:ok, true} = evaluate("numbers contains 1", context)
      assert {:ok, false} = evaluate("numbers contains 10", context)

      assert {:ok, true} = evaluate("[1, 2] in nested_lists", context)
      assert {:ok, true} = evaluate("nested_lists contains [3, 4]", context)

      assert {:ok, true} = evaluate("'string' in mixed", context)
      assert {:ok, true} = evaluate("#2024-01-01# in mixed", context)
    end
  end
end
