defmodule Predicator.ParserErrorsTest do
  use ExUnit.Case, async: true

  import Predicator.ParseShape

  alias Predicator.Lexer

  describe "parse/1 - error cases" do
    test "returns error for empty token list" do
      result = parse_positionless([])
      assert {:error, "Unexpected end of input", 1, 1, _span} = result
    end

    test "returns error for only EOF token" do
      tokens = [{:eof, 1, 1, 0, nil}]
      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input",
              1, 1, _span} = result
    end

    test "returns error for incomplete comparison" do
      {:ok, tokens} = Lexer.tokenize("limit >")

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input",
              1, 8, _span} = result
    end

    test "returns error for invalid left operand" do
      # This would be caught by the lexer, but let's test with a constructed token
      tokens = [{:gt, 1, 1, 1, ">"}, {:integer, 1, 3, 2, 85}, {:eof, 1, 5, 0, nil}]
      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found '>'",
              1, 1,
              _span} =
               result
    end

    test "returns error for missing right operand" do
      {:ok, tokens} = Lexer.tokenize("limit > >")

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found '>'",
              1, 9,
              _span} =
               result
    end

    test "returns error for unterminated parentheses" do
      {:ok, tokens} = Lexer.tokenize("(limit")

      result = parse_positionless(tokens)
      assert {:error, "Expected ')' but found end of input", 1, 7, _span} = result
    end

    test "returns error for mismatched parentheses" do
      # The lexer rejects ']' as invalid, so let's test with constructed tokens
      tokens = [
        {:lparen, 1, 1, 1, "("},
        {:identifier, 1, 2, 5, "limit"},
        # Simulating a different token type
        {:identifier, 1, 7, 1, "]"},
        {:eof, 1, 8, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:error, "Expected ')' but found identifier ']'", 1, 7, _span} = result
    end

    test "returns error for extra tokens after expression" do
      {:ok, tokens} = Lexer.tokenize("limit > 85 extra")

      result = parse_positionless(tokens)

      assert {:error, "Unexpected token identifier 'extra' after expression", 1, 12, _span} =
               result
    end

    test "returns error for multiple operators" do
      {:ok, tokens} = Lexer.tokenize("limit > > 85")

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found '>'",
              1, 9,
              _span} =
               result
    end
  end

  describe "parse/1 - integration with lexer errors" do
    test "handles lexer tokenization into parser" do
      # Test the full pipeline: string -> tokens -> AST
      input = "user_age >= 21"
      {:ok, tokens} = Lexer.tokenize(input)

      expected = {:comparison, :gte, {:identifier, "user_age"}, {:literal, 21}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "handles complex parenthesized expressions" do
      input = "((limit) >= (threshold))"
      {:ok, tokens} = Lexer.tokenize(input)

      expected = {:comparison, :gte, {:identifier, "limit"}, {:identifier, "threshold"}}
      assert parse_positionless(tokens) == {:ok, expected}
    end
  end

  describe "parse/1 - additional error coverage" do
    test "returns error when parentheses reach end of input without closing" do
      # This creates tokens that end abruptly inside parentheses, with no
      # :eof sentinel appended. end_of_input_error/2 still finds a real token
      # (the last one in the list) and reports its position, not {1, 1}.
      tokens = [
        {:lparen, 1, 1, 1, "("},
        {:identifier, 1, 2, 5, "limit"}
        # Note: no closing paren and no EOF token
      ]

      result = parse_positionless(tokens)
      assert {:error, "Expected ')' but reached end of input", 1, 2, {{1, 2}, {1, 7}}} = result
    end

    test "returns {1, 1} point error when the token list is entirely empty" do
      # The defensive nil branch of end_of_input_error/2: no token in scope at
      # all, not even the :eof sentinel. Real entry points always append the
      # sentinel, so this is only reachable via a hand-built token list.
      result = parse_positionless([])
      assert {:error, "Unexpected end of input", 1, 1, {{1, 1}, {1, 1}}} = result
    end

    test "handles nested error propagation from inner expressions" do
      # Test error propagation through parentheses
      {:ok, tokens} = Lexer.tokenize("(limit > )")

      result = parse_positionless(tokens)
      assert {:error, message, 1, 10, _span} = result

      assert message =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found ')'"
    end

    test "handles comparison operator followed by EOF" do
      tokens = [
        {:identifier, 1, 1, 5, "limit"},
        {:gt, 1, 7, 1, ">"},
        {:eof, 1, 8, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input",
              1, 8, _span} = result
    end

    test "handles unexpected token types in primary position" do
      # Test different token types that would fail in primary position
      test_cases = [
        {[:gt],
         "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found '>'"},
        {[:lt],
         "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found '<'"},
        {[:gte],
         "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found '>='"},
        {[:lte],
         "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found '<='"},
        {[:eq],
         "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found '='"},
        {[:ne],
         "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found '!='"}
      ]

      for {token_types, expected_message} <- test_cases do
        [token_type] = token_types
        tokens = [{token_type, 1, 1, 1, to_string(token_type)}, {:eof, 1, 2, 0, nil}]

        result = parse_positionless(tokens)
        assert {:error, ^expected_message, 1, 1, _span} = result
      end
    end

    test "format_token function handles all token types correctly" do
      # Test various invalid token placements to ensure format_token is exercised

      # Test operators in primary position (should be rejected)
      operator_tokens = [
        {:gt, 1, 1, 1, ">"},
        {:lt, 1, 1, 1, "<"},
        {:gte, 1, 1, 2, ">="},
        {:lte, 1, 1, 2, "<="},
        {:eq, 1, 1, 1, "="},
        {:ne, 1, 1, 2, "!="}
      ]

      for token <- operator_tokens do
        tokens = [token, {:eof, 1, 3, 0, nil}]
        result = parse_positionless(tokens)
        assert {:error, _message, 1, 1, _span} = result
      end

      # Test parentheses and other tokens in wrong positions
      other_tokens = [
        {:rparen, 1, 1, 1, ")"},
        {:eof, 1, 1, 0, nil}
      ]

      for token <- other_tokens do
        tokens = [token, {:eof, 1, 3, 0, nil}]
        result = parse_positionless(tokens)
        assert {:error, _message, 1, 1, _span} = result
      end
    end

    test "handles rparen token in unexpected position" do
      tokens = [
        {:rparen, 1, 1, 1, ")"},
        {:eof, 1, 2, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found ')'",
              1, 1,
              _span} =
               result
    end

    test "handles empty expression inside parentheses" do
      tokens = [
        {:lparen, 1, 1, 1, "("},
        {:rparen, 1, 2, 1, ")"},
        {:eof, 1, 3, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found ')'",
              1, 2,
              _span} =
               result
    end
  end

  describe "parse/1 - advanced error cases" do
    test "returns error for malformed equality expression" do
      tokens = [
        {:identifier, 1, 1, 1, "a"},
        {:equal_equal, 1, 2, 2, "=="},
        {:eof, 1, 4, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input",
              1, 4, _span} = result
    end

    test "returns error for malformed unary expression" do
      tokens = [
        {:minus, 1, 1, 1, "-"},
        {:eof, 1, 2, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input",
              1, 2, _span} = result
    end

    test "returns error for malformed list expression" do
      tokens = [
        {:lbracket, 1, 1, 1, "["},
        {:integer, 1, 2, 1, 1},
        {:comma, 1, 3, 1, ","},
        {:eof, 1, 4, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input",
              1, 4, _span} = result
    end

    test "returns error for list with invalid separator" do
      # This actually parses successfully as [1 + 2] which is a valid list with one arithmetic expression
      # So let's test a different case that will actually fail
      tokens = [
        {:lbracket, 1, 1, 1, "["},
        {:integer, 1, 2, 1, 1},
        # Missing comma between elements
        {:integer, 1, 3, 1, 2},
        {:rbracket, 1, 4, 1, "]"},
        {:eof, 1, 5, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:error, "Expected ']' but found number '2'", 1, 3, _span} = result
    end

    test "returns error for arithmetic expression with missing operand" do
      tokens = [
        {:integer, 1, 1, 1, 5},
        {:plus, 1, 2, 1, "+"},
        {:multiply, 1, 3, 1, "*"},
        {:integer, 1, 4, 1, 3},
        {:eof, 1, 5, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found '*'",
              1, 3, _span} = result
    end
  end
end
