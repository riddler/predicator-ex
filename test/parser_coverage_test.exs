defmodule ParserCoverageTest do
  use ExUnit.Case, async: true

  import Predicator
  alias Predicator.{Lexer, Parser}

  describe "parser edge cases for coverage" do
    test "parse error propagation from lexer" do
      # Test that lexer errors are properly passed through
      assert {:error, msg, 1, 1} = parse("\"unterminated string")
      assert msg =~ "Unterminated"
    end

    test "unexpected end of input in various contexts" do
      # Missing closing parenthesis
      assert {:error, %Predicator.Errors.ParseError{message: msg}} = evaluate("(true", %{})
      assert msg =~ "Expected ')' but found end of input"

      # Missing closing bracket
      assert {:error, %Predicator.Errors.ParseError{message: msg}} = evaluate("[1, 2", %{})
      assert msg =~ "Expected ']' but found end of input"

      # Missing function closing parenthesis
      assert {:error, %Predicator.Errors.ParseError{message: msg}} = evaluate("len('hello'", %{})
      assert msg =~ "Expected ')' but found end of input"
    end

    test "empty token list parsing" do
      # Empty expression should fail
      empty_tokens = [{:eof, 1, 1, 0, nil}]
      assert {:error, msg, 1, 1} = Parser.parse(empty_tokens)

      assert msg =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found end of input"
    end

    test "unexpected tokens in primary expressions" do
      # Test various invalid token positions
      assert {:error, %Predicator.Errors.ParseError{message: msg}} = evaluate("AND true", %{})

      assert msg =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found 'AND'"

      assert {:error, %Predicator.Errors.ParseError{message: msg}} = evaluate("OR false", %{})

      assert msg =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found 'OR'"

      assert {:error, %Predicator.Errors.ParseError{message: msg}} = evaluate("NOT", %{})

      assert msg =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found end of input"
    end

    test "malformed function calls" do
      # Missing opening parenthesis after function name
      modified_tokens = [
        {:function_name, 1, 1, 3, "len"},
        {:string, 1, 5, 7, "hello"},
        {:eof, 1, 12, 0, nil}
      ]

      assert {:error, msg, 1, 5} = Parser.parse(modified_tokens)
      assert msg =~ "Expected '(' after function name"
    end

    test "invalid tokens in various contexts" do
      # Invalid token after parenthesized expression
      assert {:error, %Predicator.Errors.ParseError{message: msg}} = evaluate("(true) AND", %{})

      assert msg =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found end of input"

      # Invalid token in list
      # Missing comma
      assert {:error, %Predicator.Errors.ParseError{message: msg}} = evaluate("[1 2]", %{})
      assert msg =~ "Expected ']' but found number"

      # Multiple operators
      assert {:error, %Predicator.Errors.ParseError{message: msg}} =
               evaluate("true AND AND false", %{})

      assert msg =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found 'AND'"
    end

    test "token after complete expression" do
      # Extra tokens after valid expression - test simpler case
      assert {:error, %Predicator.Errors.ParseError{message: msg}} = evaluate("true false", %{})
      assert msg =~ "Unexpected token"
    end
  end

  describe "lexer edge cases for coverage" do
    test "various unterminated string scenarios" do
      # Double-quoted unterminated
      assert {:error, msg, 1, 1} = Lexer.tokenize("\"hello")
      assert msg =~ "Unterminated double-quoted string"

      # Single-quoted unterminated
      assert {:error, msg, 1, 1} = Lexer.tokenize("'world")
      assert msg =~ "Unterminated single-quoted string"
    end

    test "invalid date and datetime formats" do
      # Malformed date
      assert {:error, msg, 1, 1} = Lexer.tokenize("#invalid-date#")
      assert msg =~ "Invalid date format"

      # Malformed datetime
      assert {:error, msg, 1, 1} = Lexer.tokenize("#2024-01-01Tinvalid#")
      assert msg =~ "Invalid datetime format"
    end

    test "invalid number formats" do
      # Numbers starting with multiple zeros
      # Should still work
      {:ok, tokens} = Lexer.tokenize("00123")
      assert [{:integer, 1, 1, 5, 123}, {:eof, 1, 6, 0, nil}] = tokens
    end
  end

  describe "integration with new arithmetic operators" do
    test "parser can handle arithmetic expressions and evaluator processes them correctly" do
      # These expressions should parse successfully and now also evaluate correctly
      # because arithmetic instructions are now implemented in the evaluator
      assert {:ok, result} = evaluate("2 + 3", %{})
      assert result == 5

      assert {:ok, result} = evaluate("5 * 2", %{})
      assert result == 10

      # Unary operators are also implemented in evaluator
      assert {:ok, result} = evaluate("-5", %{})
      assert result == -5
    end
  end
end
