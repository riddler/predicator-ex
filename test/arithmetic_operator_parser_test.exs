defmodule ArithmeticOperatorParserTest do
  use ExUnit.Case, async: true

  import Predicator

  describe "arithmetic operators - fully implemented" do
    test "addition operator works correctly" do
      assert {:ok, result} = evaluate("2 + 3", %{})
      assert result == 5
    end

    test "subtraction operator works correctly" do
      assert {:ok, result} = evaluate("5 - 2", %{})
      assert result == 3
    end

    test "multiplication operator works correctly" do
      assert {:ok, result} = evaluate("3 * 4", %{})
      assert result == 12
    end

    test "division operator works correctly" do
      assert {:ok, result} = evaluate("8 / 2", %{})
      assert result == 4
    end

    test "modulo operator works correctly" do
      assert {:ok, result} = evaluate("7 % 3", %{})
      assert result == 1
    end

    test "double equals operator works (equality parsing implemented)" do
      # == now works because it's parsed as equality
      assert {:ok, result} = evaluate("x == y", %{})
      # Both x and y are undefined, so they're equal
      assert result == :undefined
    end

    test "logical and operator works (now parsed correctly)" do
      # && now works because it's parsed as logical_and
      assert {:ok, result} = evaluate("true && false", %{})
      assert result == false
    end

    test "logical or operator works (now parsed correctly)" do
      # || now works because it's parsed as logical_or
      assert {:ok, result} = evaluate("true || false", %{})
      assert result == true
    end

    test "bang operator works as logical NOT" do
      # ! now works as logical NOT, but since 'active' is undefined, it gives an error
      assert {:error, message} = evaluate("!active", %{})
      assert message =~ "Logical NOT requires a boolean value, got: :undefined"
    end

    test "complex arithmetic expression works correctly" do
      assert {:ok, result} = evaluate("(2 + 3) * 4", %{})
      assert result == 20
    end
  end

  describe "lexer tokenization verification" do
    test "arithmetic operators are properly tokenized" do
      # These should successfully tokenize (lexer works)
      # and parse successfully (parser now works)
      # but may fail at evaluation time if instruction not implemented

      arithmetic_expressions = [
        "2 + 3",
        "5 - 2",
        "3 * 4",
        "8 / 2",
        "7 % 3"
      ]

      working_expressions = [
        # Equality works
        "x == y",
        # Logical AND works
        "true && false",
        # Logical OR works
        "true || false"
      ]

      for expr <- arithmetic_expressions do
        # Should tokenize and parse successfully
        assert {:ok, tokens} = Predicator.Lexer.tokenize(expr)
        assert length(tokens) >= 3

        # Evaluation should now work correctly
        assert {:ok, result} = evaluate(expr, %{})
        assert is_integer(result)
      end

      for expr <- working_expressions do
        # Should tokenize, parse, AND evaluate successfully
        assert {:ok, tokens} = Predicator.Lexer.tokenize(expr)
        assert length(tokens) >= 3
        assert {:ok, _result} = evaluate(expr, %{})
      end

      # Special case: !active fails due to type error, not unknown instruction
      assert {:ok, tokens} = Predicator.Lexer.tokenize("!active")
      assert length(tokens) >= 2
      assert {:error, message} = evaluate("!active", %{})
      assert message =~ "Logical NOT requires a boolean value"
    end
  end

  describe "operator precedence verification (now implemented)" do
    test "verifies correct operator precedence in arithmetic expressions" do
      # These complex expressions should produce correct results based on precedence

      arithmetic_precedence_tests = [
        # Should be: 2 + (3 * 4) = 14
        {"2 + 3 * 4", 14},
        # Should be: (2 + 3) * 4 = 20
        {"(2 + 3) * 4", 20},
        # Should be: 5 - (2 * 3) = -1
        {"5 - 2 * 3", -1},
        # Should be: (10 / 2) + 3 = 8
        {"10 / 2 + 3", 8}
      ]

      for {expr, expected} <- arithmetic_precedence_tests do
        assert {:ok, result} = evaluate(expr, %{})
        assert result == expected, "Expression '#{expr}' should equal #{expected}, got #{result}"
      end

      # Test expressions that involve undefined variables
      logical_with_undefined = [
        # Should be: (x && y) || z - all undefined, result is :undefined
        "x && y || z",
        # Should be: (!x) && y - x is undefined, so !x fails
        "!x && y",
        # Should be: (a == b) && c - a == b is :undefined, then :undefined && c fails
        "a == b && c"
      ]

      for expr <- logical_with_undefined do
        # These should either return :undefined or produce type errors due to undefined variables
        result = evaluate(expr, %{})

        assert match?({:ok, :undefined}, result) or match?({:error, _}, result),
               "Expression '#{expr}' should return :undefined or error, got #{inspect(result)}"
      end
    end
  end
end
