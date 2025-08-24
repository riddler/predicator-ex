defmodule ArithmeticOperatorParserTest do
  use ExUnit.Case, async: true

  import Predicator

  describe "arithmetic operators - evaluator rejection (not yet implemented)" do
    test "addition operator produces evaluation error" do
      assert {:error, message} = evaluate("2 + 3", %{})
      assert message =~ "Unknown instruction: [\"add\"]"
    end

    test "subtraction operator produces evaluation error" do
      assert {:error, message} = evaluate("5 - 2", %{})
      assert message =~ "Unknown instruction: [\"subtract\"]"
    end

    test "multiplication operator produces evaluation error" do
      assert {:error, message} = evaluate("3 * 4", %{})
      assert message =~ "Unknown instruction: [\"multiply\"]"
    end

    test "division operator produces evaluation error" do
      assert {:error, message} = evaluate("8 / 2", %{})
      assert message =~ "Unknown instruction: [\"divide\"]"
    end

    test "modulo operator produces evaluation error" do
      assert {:error, message} = evaluate("7 % 3", %{})
      assert message =~ "Unknown instruction: [\"modulo\"]"
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

    test "complex arithmetic expression produces evaluation error" do
      assert {:error, message} = evaluate("(2 + 3) * 4", %{})
      assert message =~ "Unknown instruction: [\"add\"]"
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

        # But evaluation should fail with "Unknown instruction"
        assert {:error, message} = evaluate(expr, %{})
        assert message =~ "Unknown instruction:"
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

  describe "operator precedence expectations (for future implementation)" do
    test "documents expected operator precedence through error messages" do
      # These complex expressions should produce consistent error patterns
      # that will help verify precedence when parser is implemented

      complex_expressions = [
        # Should be: 2 + (3 * 4) = 14
        "2 + 3 * 4",
        # Should be: (2 + 3) * 4 = 20
        "(2 + 3) * 4",
        # Should be: 5 - (2 * 3) = -1
        "5 - 2 * 3",
        # Should be: (10 / 2) + 3 = 8
        "10 / 2 + 3",
        # Should be: (x && y) || z
        "x && y || z",
        # Should be: (!x) && y
        "!x && y",
        # Should be: (a == b) && c
        "a == b && c"
      ]

      for expr <- complex_expressions do
        assert {:error, message} = evaluate(expr, %{})
        # Should get a parsing error (specific message varies by context)
        assert is_binary(message)
        assert String.length(message) > 0
      end
    end
  end
end
