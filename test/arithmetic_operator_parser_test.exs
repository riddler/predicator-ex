defmodule ArithmeticOperatorParserTest do
  use ExUnit.Case, async: true

  import Predicator

  describe "arithmetic operators - parser rejection (not yet implemented)" do
    test "addition operator produces parse error" do
      assert {:error, message} = evaluate("2 + 3", %{})
      assert message =~ "Unexpected token '+'"
    end

    test "subtraction operator produces parse error" do
      assert {:error, message} = evaluate("5 - 2", %{})
      assert message =~ "Unexpected token '-'"
    end

    test "multiplication operator produces parse error" do
      assert {:error, message} = evaluate("3 * 4", %{})
      assert message =~ "Unexpected token '*'"
    end

    test "division operator produces parse error" do
      assert {:error, message} = evaluate("8 / 2", %{})
      assert message =~ "Unexpected token '/'"
    end

    test "modulo operator produces parse error" do
      assert {:error, message} = evaluate("7 % 3", %{})
      assert message =~ "Unexpected token '%'"
    end

    test "double equals operator produces parse error" do
      assert {:error, message} = evaluate("x == y", %{})
      assert message =~ "Unexpected token '=='"
    end

    test "logical and operator produces parse error" do
      assert {:error, message} = evaluate("true && false", %{})
      assert message =~ "Unexpected token '&&'"
    end

    test "logical or operator produces parse error" do
      assert {:error, message} = evaluate("true || false", %{})
      assert message =~ "Unexpected token '||'"
    end

    test "bang operator produces parse error" do
      assert {:error, message} = evaluate("!active", %{})

      assert message =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found '!'"
    end

    test "complex arithmetic expression produces parse error" do
      assert {:error, message} = evaluate("(2 + 3) * 4", %{})
      assert message =~ "Expected ')' but found '+'"
    end
  end

  describe "lexer tokenization verification" do
    test "arithmetic operators are properly tokenized" do
      # These should successfully tokenize (lexer works)
      # but fail at parse time (parser not implemented yet)

      expressions = [
        "2 + 3",
        "5 - 2",
        "3 * 4",
        "8 / 2",
        "7 % 3",
        "x == y",
        "true && false",
        "true || false",
        "!active"
      ]

      for expr <- expressions do
        # Should tokenize successfully
        assert {:ok, tokens} = Predicator.Lexer.tokenize(expr)
        # at least operand + operator + operand + eof
        assert length(tokens) >= 3

        # But parsing should fail with meaningful error
        assert {:error, message} = evaluate(expr, %{})
        # Different operators produce different specific error messages
        assert message =~ "Unexpected token" or
                 message =~ "Expected ')' but found" or
                 message =~
                   "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found"
      end
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
