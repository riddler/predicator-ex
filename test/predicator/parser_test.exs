defmodule Predicator.ParserTest do
  use ExUnit.Case, async: true

  alias Predicator.Lexer

  doctest Predicator.Parser

  describe "parse/1 - primary expressions" do
    test "parses integer literal" do
      {:ok, tokens} = Lexer.tokenize("42")
      assert parse_positionless(tokens) == {:ok, {:literal, 42}}
    end

    test "parses string literal" do
      {:ok, tokens} = Lexer.tokenize("\"hello\"")
      assert parse_positionless(tokens) == {:ok, {:string_literal, "hello", :double}}
    end

    test "parses single quoted string literal" do
      {:ok, tokens} = Lexer.tokenize("'hello'")
      assert parse_positionless(tokens) == {:ok, {:string_literal, "hello", :single}}
    end

    test "parses boolean literal true" do
      {:ok, tokens} = Lexer.tokenize("true")
      assert parse_positionless(tokens) == {:ok, {:literal, true}}
    end

    test "parses boolean literal false" do
      {:ok, tokens} = Lexer.tokenize("false")
      assert parse_positionless(tokens) == {:ok, {:literal, false}}
    end

    test "parses identifier" do
      {:ok, tokens} = Lexer.tokenize("score")
      assert parse_positionless(tokens) == {:ok, {:identifier, "score"}}
    end

    test "parses parenthesized expression" do
      {:ok, tokens} = Lexer.tokenize("(42)")
      assert parse_positionless(tokens) == {:ok, {:literal, 42}}
    end

    test "parses nested parentheses" do
      {:ok, tokens} = Lexer.tokenize("((score))")
      assert parse_positionless(tokens) == {:ok, {:identifier, "score"}}
    end
  end

  describe "parse/1 - comparison expressions" do
    test "parses greater than comparison" do
      {:ok, tokens} = Lexer.tokenize("score > 85")

      expected = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses less than comparison" do
      {:ok, tokens} = Lexer.tokenize("age < 18")

      expected = {:comparison, :lt, {:identifier, "age"}, {:literal, 18}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses greater than or equal comparison" do
      {:ok, tokens} = Lexer.tokenize("score >= 85")

      expected = {:comparison, :gte, {:identifier, "score"}, {:literal, 85}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses less than or equal comparison" do
      {:ok, tokens} = Lexer.tokenize("age <= 65")

      expected = {:comparison, :lte, {:identifier, "age"}, {:literal, 65}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses equality comparison" do
      {:ok, tokens} = Lexer.tokenize("name == \"John\"")

      expected =
        {:comparison, :equal_equal, {:identifier, "name"}, {:string_literal, "John", :double}}

      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses equality comparison with single quotes" do
      {:ok, tokens} = Lexer.tokenize("name == 'John'")

      expected =
        {:comparison, :equal_equal, {:identifier, "name"}, {:string_literal, "John", :single}}

      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses not equal comparison" do
      {:ok, tokens} = Lexer.tokenize("status != \"inactive\"")

      expected =
        {:comparison, :ne, {:identifier, "status"}, {:string_literal, "inactive", :double}}

      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses number to number comparison" do
      {:ok, tokens} = Lexer.tokenize("10 > 5")

      expected = {:comparison, :gt, {:literal, 10}, {:literal, 5}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses boolean comparison" do
      {:ok, tokens} = Lexer.tokenize("active == true")

      expected = {:comparison, :equal_equal, {:identifier, "active"}, {:literal, true}}
      assert parse_positionless(tokens) == {:ok, expected}
    end
  end

  describe "parse/1 - parenthesized comparisons" do
    test "parses comparison in parentheses" do
      {:ok, tokens} = Lexer.tokenize("(score > 85)")

      expected = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses parenthesized left operand" do
      {:ok, tokens} = Lexer.tokenize("(score) > 85")

      expected = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses parenthesized right operand" do
      {:ok, tokens} = Lexer.tokenize("score > (85)")

      expected = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses both operands parenthesized" do
      {:ok, tokens} = Lexer.tokenize("(score) > (85)")

      expected = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      assert parse_positionless(tokens) == {:ok, expected}
    end
  end

  describe "parse/1 - complex expressions" do
    test "handles whitespace correctly" do
      {:ok, tokens} = Lexer.tokenize("  score   >    85  ")

      expected = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "handles mixed types" do
      {:ok, tokens} = Lexer.tokenize(~s("apple" > "banana"))

      expected =
        {:comparison, :gt, {:string_literal, "apple", :double},
         {:string_literal, "banana", :double}}

      assert parse_positionless(tokens) == {:ok, expected}
    end
  end

  describe "parse/1 - error cases" do
    test "returns error for empty token list" do
      result = parse_positionless([])
      assert {:error, "Unexpected end of input", 1, 1} = result
    end

    test "returns error for only EOF token" do
      tokens = [{:eof, 1, 1, 0, nil}]
      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input",
              1, 1} = result
    end

    test "returns error for incomplete comparison" do
      {:ok, tokens} = Lexer.tokenize("score >")

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input",
              1, 8} = result
    end

    test "returns error for invalid left operand" do
      # This would be caught by the lexer, but let's test with a constructed token
      tokens = [{:gt, 1, 1, 1, ">"}, {:integer, 1, 3, 2, 85}, {:eof, 1, 5, 0, nil}]
      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found '>'",
              1,
              1} =
               result
    end

    test "returns error for missing right operand" do
      {:ok, tokens} = Lexer.tokenize("score > >")

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found '>'",
              1,
              9} =
               result
    end

    test "returns error for unterminated parentheses" do
      {:ok, tokens} = Lexer.tokenize("(score")

      result = parse_positionless(tokens)
      assert {:error, "Expected ')' but found end of input", 1, 7} = result
    end

    test "returns error for mismatched parentheses" do
      # The lexer rejects ']' as invalid, so let's test with constructed tokens
      tokens = [
        {:lparen, 1, 1, 1, "("},
        {:identifier, 1, 2, 5, "score"},
        # Simulating a different token type
        {:identifier, 1, 7, 1, "]"},
        {:eof, 1, 8, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:error, "Expected ')' but found identifier ']'", 1, 7} = result
    end

    test "returns error for extra tokens after expression" do
      {:ok, tokens} = Lexer.tokenize("score > 85 extra")

      result = parse_positionless(tokens)
      assert {:error, "Unexpected token identifier 'extra' after expression", 1, 12} = result
    end

    test "returns error for multiple operators" do
      {:ok, tokens} = Lexer.tokenize("score > > 85")

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found '>'",
              1,
              9} =
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
      input = "((score) >= (threshold))"
      {:ok, tokens} = Lexer.tokenize(input)

      expected = {:comparison, :gte, {:identifier, "score"}, {:identifier, "threshold"}}
      assert parse_positionless(tokens) == {:ok, expected}
    end
  end

  describe "parse/1 - additional error coverage" do
    test "returns error when parentheses reach end of input without closing" do
      # This creates tokens that end abruptly inside parentheses
      tokens = [
        {:lparen, 1, 1, 1, "("},
        {:identifier, 1, 2, 5, "score"}
        # Note: no closing paren and no EOF token to test nil case
      ]

      result = parse_positionless(tokens)
      assert {:error, "Expected ')' but reached end of input", 1, 1} = result
    end

    test "handles nested error propagation from inner expressions" do
      # Test error propagation through parentheses
      {:ok, tokens} = Lexer.tokenize("(score > )")

      result = parse_positionless(tokens)
      assert {:error, message, 1, 10} = result

      assert message =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found ')'"
    end

    test "handles comparison operator followed by EOF" do
      tokens = [
        {:identifier, 1, 1, 5, "score"},
        {:gt, 1, 7, 1, ">"},
        {:eof, 1, 8, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input",
              1, 8} = result
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
        assert {:error, ^expected_message, 1, 1} = result
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
        assert {:error, _message, 1, 1} = result
      end

      # Test parentheses and other tokens in wrong positions
      other_tokens = [
        {:rparen, 1, 1, 1, ")"},
        {:eof, 1, 1, 0, nil}
      ]

      for token <- other_tokens do
        tokens = [token, {:eof, 1, 3, 0, nil}]
        result = parse_positionless(tokens)
        assert {:error, _message, 1, 1} = result
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
              1,
              1} =
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
              1,
              2} =
               result
    end
  end

  describe "logical operators" do
    test "parses simple AND expression" do
      tokens = [
        {:identifier, 1, 1, 5, "score"},
        {:gt, 1, 7, 1, ">"},
        {:integer, 1, 9, 2, 85},
        {:and_op, 1, 12, 3, "AND"},
        {:identifier, 1, 16, 3, "age"},
        {:gte, 1, 20, 2, ">="},
        {:integer, 1, 23, 2, 18},
        {:eof, 1, 25, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:ok,
              {:logical_and, {:comparison, :gt, {:identifier, "score"}, {:literal, 85}},
               {:comparison, :gte, {:identifier, "age"}, {:literal, 18}}}} = result
    end

    test "parses simple OR expression" do
      tokens = [
        {:identifier, 1, 1, 4, "role"},
        {:equal_equal, 1, 6, 2, "=="},
        {:string, 1, 9, 7, "admin", :double},
        {:or_op, 1, 17, 2, "OR"},
        {:identifier, 1, 20, 4, "role"},
        {:equal_equal, 1, 25, 2, "=="},
        {:string, 1, 28, 9, "manager", :double},
        {:eof, 1, 38, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:ok,
              {:logical_or,
               {:comparison, :equal_equal, {:identifier, "role"},
                {:string_literal, "admin", :double}},
               {:comparison, :equal_equal, {:identifier, "role"},
                {:string_literal, "manager", :double}}}} =
               result
    end

    test "parses simple NOT expression" do
      tokens = [
        {:not_op, 1, 1, 3, "NOT"},
        {:identifier, 1, 5, 7, "expired"},
        {:equal_equal, 1, 13, 2, "=="},
        {:boolean, 1, 16, 4, true},
        {:eof, 1, 20, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:ok,
              {:logical_not,
               {:comparison, :equal_equal, {:identifier, "expired"}, {:literal, true}}}} =
               result
    end

    test "parses nested NOT expression" do
      tokens = [
        {:not_op, 1, 1, 3, "NOT"},
        {:not_op, 1, 5, 3, "NOT"},
        {:boolean, 1, 9, 4, true},
        {:eof, 1, 13, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:ok, {:logical_not, {:logical_not, {:literal, true}}}} = result
    end

    test "parses operator precedence correctly - AND has higher precedence than OR" do
      # true OR false AND true should parse as: true OR (false AND true)
      tokens = [
        {:boolean, 1, 1, 4, true},
        {:or_op, 1, 6, 2, "OR"},
        {:boolean, 1, 9, 5, false},
        {:and_op, 1, 15, 3, "AND"},
        {:boolean, 1, 19, 4, true},
        {:eof, 1, 23, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:ok,
              {:logical_or, {:literal, true}, {:logical_and, {:literal, false}, {:literal, true}}}} =
               result
    end

    test "parses operator precedence correctly - NOT has highest precedence" do
      # NOT false AND true should parse as: (NOT false) AND true
      tokens = [
        {:not_op, 1, 1, 3, "NOT"},
        {:boolean, 1, 5, 5, false},
        {:and_op, 1, 11, 3, "AND"},
        {:boolean, 1, 15, 4, true},
        {:eof, 1, 19, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:ok, {:logical_and, {:logical_not, {:literal, false}}, {:literal, true}}} = result
    end

    test "parses complex precedence expression" do
      # NOT false OR true AND false should parse as: (NOT false) OR (true AND false)
      tokens = [
        {:not_op, 1, 1, 3, "NOT"},
        {:boolean, 1, 5, 5, false},
        {:or_op, 1, 11, 2, "OR"},
        {:boolean, 1, 14, 4, true},
        {:and_op, 1, 19, 3, "AND"},
        {:boolean, 1, 23, 5, false},
        {:eof, 1, 28, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:ok,
              {:logical_or, {:logical_not, {:literal, false}},
               {:logical_and, {:literal, true}, {:literal, false}}}} = result
    end

    test "parses left-associative AND operations" do
      # true AND false AND true should parse as: (true AND false) AND true
      tokens = [
        {:boolean, 1, 1, 4, true},
        {:and_op, 1, 6, 3, "AND"},
        {:boolean, 1, 10, 5, false},
        {:and_op, 1, 16, 3, "AND"},
        {:boolean, 1, 20, 4, true},
        {:eof, 1, 24, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:ok,
              {:logical_and, {:logical_and, {:literal, true}, {:literal, false}},
               {:literal, true}}} = result
    end

    test "parses left-associative OR operations" do
      # true OR false OR true should parse as: (true OR false) OR true
      tokens = [
        {:boolean, 1, 1, 4, true},
        {:or_op, 1, 6, 2, "OR"},
        {:boolean, 1, 9, 5, false},
        {:or_op, 1, 15, 2, "OR"},
        {:boolean, 1, 18, 4, true},
        {:eof, 1, 22, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:ok,
              {:logical_or, {:logical_or, {:literal, true}, {:literal, false}}, {:literal, true}}} =
               result
    end

    test "parses parenthesized logical expressions" do
      # (true OR false) AND true
      tokens = [
        {:lparen, 1, 1, 1, "("},
        {:boolean, 1, 2, 4, true},
        {:or_op, 1, 7, 2, "OR"},
        {:boolean, 1, 10, 5, false},
        {:rparen, 1, 15, 1, ")"},
        {:and_op, 1, 17, 3, "AND"},
        {:boolean, 1, 21, 4, true},
        {:eof, 1, 25, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:ok,
              {:logical_and, {:logical_or, {:literal, true}, {:literal, false}}, {:literal, true}}} =
               result
    end

    test "handles error when AND missing right operand" do
      tokens = [
        {:boolean, 1, 1, 4, true},
        {:and_op, 1, 6, 3, "AND"},
        {:eof, 1, 9, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input",
              1, 9} = result
    end

    test "handles error when OR missing right operand" do
      tokens = [
        {:boolean, 1, 1, 4, true},
        {:or_op, 1, 6, 2, "OR"},
        {:eof, 1, 8, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input",
              1, 8} = result
    end

    test "handles error when NOT missing operand" do
      tokens = [
        {:not_op, 1, 1, 3, "NOT"},
        {:eof, 1, 4, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input",
              1, 4} = result
    end

    test "complex mixed expression with comparisons and logical operators" do
      # score > 85 AND age >= 18 OR admin == true
      tokens = [
        {:identifier, 1, 1, 5, "score"},
        {:gt, 1, 7, 1, ">"},
        {:integer, 1, 9, 2, 85},
        {:and_op, 1, 12, 3, "AND"},
        {:identifier, 1, 16, 3, "age"},
        {:gte, 1, 20, 2, ">="},
        {:integer, 1, 23, 2, 18},
        {:or_op, 1, 26, 2, "OR"},
        {:identifier, 1, 29, 5, "admin"},
        {:equal_equal, 1, 35, 2, "=="},
        {:boolean, 1, 38, 4, true},
        {:eof, 1, 42, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:ok,
              {:logical_or,
               {:logical_and, {:comparison, :gt, {:identifier, "score"}, {:literal, 85}},
                {:comparison, :gte, {:identifier, "age"}, {:literal, 18}}},
               {:comparison, :equal_equal, {:identifier, "admin"}, {:literal, true}}}} = result
    end
  end

  describe "date and datetime parsing" do
    test "parses date literals correctly" do
      tokens = [
        {:date, 1, 1, 12, ~D[2024-01-15]},
        {:eof, 1, 13, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:ok, {:literal, ~D[2024-01-15]}} = result
    end

    test "parses datetime literals correctly" do
      {:ok, datetime, _offset} = DateTime.from_iso8601("2024-01-15T10:30:00Z")

      tokens = [
        {:datetime, 1, 1, 21, datetime},
        {:eof, 1, 22, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:ok, {:literal, ^datetime}} = result
    end

    test "parses date comparisons" do
      tokens = [
        {:date, 1, 1, 12, ~D[2024-01-15]},
        {:gt, 1, 14, 1, ">"},
        {:date, 1, 16, 12, ~D[2024-01-10]},
        {:eof, 1, 28, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:ok, {:comparison, :gt, {:literal, ~D[2024-01-15]}, {:literal, ~D[2024-01-10]}}} =
               result
    end
  end

  describe "additional edge cases for coverage" do
    test "handles multiple consecutive parentheses" do
      tokens = [
        {:lparen, 1, 1, 1, "("},
        {:lparen, 1, 2, 1, "("},
        {:integer, 1, 3, 2, 42},
        {:rparen, 1, 5, 1, ")"},
        {:rparen, 1, 6, 1, ")"},
        {:eof, 1, 7, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:ok, {:literal, 42}} = result
    end

    test "handles list with mixed literal types" do
      date = ~D[2024-01-15]

      tokens = [
        {:lbracket, 1, 1, 1, "["},
        {:integer, 1, 2, 2, 42},
        {:comma, 1, 4, 1, ","},
        {:string, 1, 6, 7, "hello", :double},
        {:comma, 1, 13, 1, ","},
        {:boolean, 1, 15, 4, true},
        {:comma, 1, 19, 1, ","},
        {:date, 1, 21, 12, date},
        {:rbracket, 1, 33, 1, "]"},
        {:eof, 1, 34, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:ok,
              {:list,
               [
                 {:literal, 42},
                 {:string_literal, "hello", :double},
                 {:literal, true},
                 {:literal, ^date}
               ]}} = result
    end

    test "handles missing comma in list" do
      tokens = [
        {:lbracket, 1, 1, 1, "["},
        {:integer, 1, 2, 1, 1},
        {:integer, 1, 4, 1, 2},
        {:eof, 1, 5, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:error, "Expected ']' but found number '2'", 1, 4} = result
    end

    test "handles comparison with missing left operand in complex expression" do
      tokens = [
        {:and_op, 1, 1, 3, "AND"},
        {:integer, 1, 5, 2, 42},
        {:eof, 1, 7, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found 'AND'",
              1, 1} = result
    end

    test "handles membership operator with empty list" do
      tokens = [
        {:integer, 1, 1, 1, 1},
        {:in_op, 1, 3, 2, "in"},
        {:lbracket, 1, 6, 1, "["},
        {:rbracket, 1, 7, 1, "]"},
        {:eof, 1, 8, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:ok, {:membership, :in, {:literal, 1}, {:list, []}}} = result
    end
  end

  describe "parse/1 - function call expressions" do
    test "parses function call with no arguments" do
      {:ok, tokens} = Lexer.tokenize("len()")
      assert parse_positionless(tokens) == {:ok, {:function_call, "len", []}}
    end

    test "parses function call with one argument" do
      {:ok, tokens} = Lexer.tokenize("len(name)")
      assert parse_positionless(tokens) == {:ok, {:function_call, "len", [{:identifier, "name"}]}}
    end

    test "parses function call with multiple arguments" do
      {:ok, tokens} = Lexer.tokenize("max(score1, score2)")

      assert parse_positionless(tokens) ==
               {:ok, {:function_call, "max", [{:identifier, "score1"}, {:identifier, "score2"}]}}
    end

    test "parses function call with complex arguments" do
      {:ok, tokens} = Lexer.tokenize("max(score + bonus, 100)")

      assert parse_positionless(tokens) ==
               {:ok,
                {:function_call, "max",
                 [
                   {:arithmetic, :add, {:identifier, "score"}, {:identifier, "bonus"}},
                   {:literal, 100}
                 ]}}
    end

    test "parses nested function calls" do
      {:ok, tokens} = Lexer.tokenize("upper(trim(name))")

      assert parse_positionless(tokens) ==
               {:ok,
                {:function_call, "upper",
                 [
                   {:function_call, "trim", [{:identifier, "name"}]}
                 ]}}
    end

    test "returns error when function name followed by non-parenthesis" do
      tokens = [
        {:function_name, 1, 1, 3, "len"},
        {:integer, 1, 4, 1, 42},
        {:eof, 1, 5, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:error, "Expected '(' after function name but found number '42'", 1, 4} = result
    end

    test "returns error when function name at end of input" do
      tokens = [
        {:function_name, 1, 1, 3, "len"},
        {:eof, 1, 4, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:error, "Expected '(' after function name but found end of input", 1, 4} = result
    end

    test "returns error for unterminated function call" do
      tokens = [
        {:function_name, 1, 1, 3, "len"},
        {:lparen, 1, 4, 1, "("},
        {:identifier, 1, 5, 4, "name"},
        {:eof, 1, 9, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:error, "Expected ')' but found end of input", 1, 9} = result
    end

    test "returns error for function call with invalid closing token" do
      tokens = [
        {:function_name, 1, 1, 3, "len"},
        {:lparen, 1, 4, 1, "("},
        {:identifier, 1, 5, 4, "name"},
        {:rbracket, 1, 9, 1, "]"},
        {:eof, 1, 10, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:error, "Expected ')' but found ']'", 1, 9} = result
    end
  end

  describe "parse/1 - complex nested expressions" do
    test "parses deeply nested arithmetic expressions" do
      {:ok, tokens} = Lexer.tokenize("((((a + b) * c) - d) / e)")
      result = parse_positionless(tokens)

      expected_ast =
        {:arithmetic, :divide,
         {:arithmetic, :subtract,
          {:arithmetic, :multiply, {:arithmetic, :add, {:identifier, "a"}, {:identifier, "b"}},
           {:identifier, "c"}}, {:identifier, "d"}}, {:identifier, "e"}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses complex logical expressions with mixed operators" do
      {:ok, tokens} = Lexer.tokenize("a && b || c && d")
      result = parse_positionless(tokens)

      expected_ast =
        {:logical_or, {:logical_and, {:identifier, "a"}, {:identifier, "b"}},
         {:logical_and, {:identifier, "c"}, {:identifier, "d"}}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses mixed arithmetic and logical with proper precedence" do
      {:ok, tokens} = Lexer.tokenize("a + b > c && d - e < f")
      result = parse_positionless(tokens)

      expected_ast =
        {:logical_and,
         {:comparison, :gt, {:arithmetic, :add, {:identifier, "a"}, {:identifier, "b"}},
          {:identifier, "c"}},
         {:comparison, :lt, {:arithmetic, :subtract, {:identifier, "d"}, {:identifier, "e"}},
          {:identifier, "f"}}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses expressions with multiple unary operators" do
      {:ok, tokens} = Lexer.tokenize("!!active")
      result = parse_positionless(tokens)

      expected_ast = {:logical_not, {:logical_not, {:identifier, "active"}}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses multiple nested unary minus operators" do
      {:ok, tokens} = Lexer.tokenize("---value")
      result = parse_positionless(tokens)

      expected_ast = {:unary, :minus, {:unary, :minus, {:unary, :minus, {:identifier, "value"}}}}

      assert {:ok, ^expected_ast} = result
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
              1, 4} = result
    end

    test "returns error for malformed unary expression" do
      tokens = [
        {:minus, 1, 1, 1, "-"},
        {:eof, 1, 2, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input",
              1, 2} = result
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
              1, 4} = result
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
      assert {:error, "Expected ']' but found number '2'", 1, 3} = result
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
              1, 3} = result
    end
  end

  describe "parse/1 - edge cases for format_token" do
    test "format_token handles all date/datetime formats" do
      date = ~D[2024-01-15]
      {:ok, dt, _offset} = DateTime.from_iso8601("2024-01-15T10:30:00Z")

      # Test direct calls to private function via token parsing errors
      tokens = [
        {:date, 1, 1, 11, date},
        {:plus, 1, 12, 1, "+"},
        {:eof, 1, 13, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:error, message, 1, 13} = result

      assert message =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input"

      tokens = [
        {:datetime, 1, 1, 20, dt},
        {:plus, 1, 21, 1, "+"},
        {:eof, 1, 22, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:error, message, 1, 22} = result

      assert message =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input"
    end

    test "format_token handles function names in error messages" do
      tokens = [
        {:function_name, 1, 1, 3, "len"},
        {:plus, 1, 4, 1, "+"},
        {:eof, 1, 5, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:error, "Expected '(' after function name but found '+'", 1, 4} = result
    end

    test "a stray :: in expression position returns an error tuple, not a raise" do
      assert {:error, message, 1, 1} = Predicator.parse("::integer")
      assert message =~ "'::'"
    end
  end

  describe "parse/1 - operator precedence edge cases" do
    test "verifies complex precedence with all operators" do
      # Test expression: a + b * c / d - e % f > g && h || i
      {:ok, tokens} = Lexer.tokenize("a + b * c / d - e % f > g && h || i")
      result = parse_positionless(tokens)

      # Expected precedence:
      # 1. *, /, % (left-to-right)
      # 2. +, - (left-to-right)
      # 3. > (comparison)
      # 4. && (logical and)
      # 5. || (logical or)

      # ((a + ((b * c) / d)) - (e % f)) > g && h || i
      expected_ast =
        {:logical_or,
         {:logical_and,
          {:comparison, :gt,
           {:arithmetic, :subtract,
            {:arithmetic, :add, {:identifier, "a"},
             {:arithmetic, :divide,
              {:arithmetic, :multiply, {:identifier, "b"}, {:identifier, "c"}},
              {:identifier, "d"}}},
            {:arithmetic, :modulo, {:identifier, "e"}, {:identifier, "f"}}}, {:identifier, "g"}},
          {:identifier, "h"}}, {:identifier, "i"}}

      assert {:ok, ^expected_ast} = result
    end

    test "verifies equality operator precedence" do
      {:ok, tokens} = Lexer.tokenize("a + b == c * d")
      result = parse_positionless(tokens)

      expected_ast =
        {:comparison, :equal_equal, {:arithmetic, :add, {:identifier, "a"}, {:identifier, "b"}},
         {:arithmetic, :multiply, {:identifier, "c"}, {:identifier, "d"}}}

      assert {:ok, ^expected_ast} = result
    end

    test "verifies unary operator precedence with arithmetic" do
      {:ok, tokens} = Lexer.tokenize("-a + b")
      result = parse_positionless(tokens)

      expected_ast = {:arithmetic, :add, {:unary, :minus, {:identifier, "a"}}, {:identifier, "b"}}

      assert {:ok, ^expected_ast} = result
    end
  end

  describe "parse/1 - bracket access expressions" do
    test "parses simple bracket access" do
      {:ok, tokens} = Lexer.tokenize("user['name']")
      result = parse_positionless(tokens)

      expected_ast = {:bracket_access, {:identifier, "user"}, {:string_literal, "name", :single}}
      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with double quotes" do
      {:ok, tokens} = Lexer.tokenize("user[\"name\"]")
      result = parse_positionless(tokens)

      expected_ast = {:bracket_access, {:identifier, "user"}, {:string_literal, "name", :double}}
      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with numeric index" do
      {:ok, tokens} = Lexer.tokenize("items[0]")
      result = parse_positionless(tokens)

      expected_ast = {:bracket_access, {:identifier, "items"}, {:literal, 0}}
      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with variable index" do
      {:ok, tokens} = Lexer.tokenize("items[index]")
      result = parse_positionless(tokens)

      expected_ast = {:bracket_access, {:identifier, "items"}, {:identifier, "index"}}
      assert {:ok, ^expected_ast} = result
    end

    test "parses chained bracket access" do
      {:ok, tokens} = Lexer.tokenize("data['users'][0]['name']")
      result = parse_positionless(tokens)

      expected_ast = {
        :bracket_access,
        {:bracket_access,
         {:bracket_access, {:identifier, "data"}, {:string_literal, "users", :single}},
         {:literal, 0}},
        {:string_literal, "name", :single}
      }

      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with arithmetic expression as key" do
      {:ok, tokens} = Lexer.tokenize("items[i + 1]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access, {:identifier, "items"},
         {:arithmetic, :add, {:identifier, "i"}, {:literal, 1}}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses mixed dot and bracket access" do
      # Test the new property access parsing
      {:ok, tokens} = Lexer.tokenize("user.settings")
      result = parse_positionless(tokens)

      expected_ast = {:property_access, {:identifier, "user"}, "settings"}
      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access in comparison" do
      {:ok, tokens} = Lexer.tokenize("user['age'] > 18")
      result = parse_positionless(tokens)

      expected_ast =
        {:comparison, :gt,
         {:bracket_access, {:identifier, "user"}, {:string_literal, "age", :single}},
         {:literal, 18}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access in arithmetic" do
      {:ok, tokens} = Lexer.tokenize("scores[0] + scores[1]")
      result = parse_positionless(tokens)

      expected_ast =
        {:arithmetic, :add, {:bracket_access, {:identifier, "scores"}, {:literal, 0}},
         {:bracket_access, {:identifier, "scores"}, {:literal, 1}}}

      assert {:ok, ^expected_ast} = result
    end

    test "returns error for unclosed bracket" do
      {:ok, tokens} = Lexer.tokenize("user['name'")
      result = parse_positionless(tokens)

      assert {:error, "Expected ']' but found end of input", 1, 12} = result
    end

    test "returns error for empty bracket access" do
      {:ok, tokens} = Lexer.tokenize("user[]")
      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found ']'",
              1, 6} = result
    end

    test "returns error for missing closing bracket" do
      {:ok, tokens} = Lexer.tokenize("user['name' + 'suffix'")
      result = parse_positionless(tokens)

      assert {:error, "Expected ']' but found end of input", 1, 23} = result
    end

    test "parses bracket access with boolean key" do
      {:ok, tokens} = Lexer.tokenize("config[true]")
      result = parse_positionless(tokens)

      expected_ast = {:bracket_access, {:identifier, "config"}, {:literal, true}}
      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with false key" do
      {:ok, tokens} = Lexer.tokenize("settings[false]")
      result = parse_positionless(tokens)

      expected_ast = {:bracket_access, {:identifier, "settings"}, {:literal, false}}
      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with function call key" do
      {:ok, tokens} = Lexer.tokenize("data[len('key')]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access, {:identifier, "data"},
         {:function_call, "len", [{:string_literal, "key", :single}]}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with nested brackets in key" do
      {:ok, tokens} = Lexer.tokenize("matrix[users[0]]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access, {:identifier, "matrix"},
         {:bracket_access, {:identifier, "users"}, {:literal, 0}}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with comparison expression key" do
      {:ok, tokens} = Lexer.tokenize("data[i > 5]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access, {:identifier, "data"},
         {:comparison, :gt, {:identifier, "i"}, {:literal, 5}}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with logical AND key" do
      {:ok, tokens} = Lexer.tokenize("cache[active AND valid]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access, {:identifier, "cache"},
         {:logical_and, {:identifier, "active"}, {:identifier, "valid"}}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with logical OR key" do
      {:ok, tokens} = Lexer.tokenize("flags[debug OR test]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access, {:identifier, "flags"},
         {:logical_or, {:identifier, "debug"}, {:identifier, "test"}}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with logical NOT key" do
      {:ok, tokens} = Lexer.tokenize("options[NOT disabled]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access, {:identifier, "options"}, {:logical_not, {:identifier, "disabled"}}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with list key" do
      {:ok, tokens} = Lexer.tokenize("lookup[[1, 2, 3]]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access, {:identifier, "lookup"},
         {:list, [{:literal, 1}, {:literal, 2}, {:literal, 3}]}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with parenthesized key" do
      {:ok, tokens} = Lexer.tokenize("data[(index + 1)]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access, {:identifier, "data"},
         {:arithmetic, :add, {:identifier, "index"}, {:literal, 1}}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses deeply chained bracket access" do
      {:ok, tokens} = Lexer.tokenize("a[0][1][2][3]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access,
         {:bracket_access,
          {:bracket_access, {:bracket_access, {:identifier, "a"}, {:literal, 0}}, {:literal, 1}},
          {:literal, 2}}, {:literal, 3}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with mixed operators in complex expressions" do
      {:ok, tokens} = Lexer.tokenize("data[key] + values[index * 2] > threshold['max']")
      result = parse_positionless(tokens)

      expected_ast =
        {:comparison, :gt,
         {:arithmetic, :add, {:bracket_access, {:identifier, "data"}, {:identifier, "key"}},
          {:bracket_access, {:identifier, "values"},
           {:arithmetic, :multiply, {:identifier, "index"}, {:literal, 2}}}},
         {:bracket_access, {:identifier, "threshold"}, {:string_literal, "max", :single}}}

      assert {:ok, ^expected_ast} = result
    end

    test "returns error for bracket access with invalid token after bracket" do
      {:ok, tokens} = Lexer.tokenize("user[>]")
      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found '>'",
              1, 6} = result
    end

    test "returns error for unmatched left bracket" do
      {:ok, tokens} = Lexer.tokenize("user[key")
      result = parse_positionless(tokens)

      assert {:error, "Expected ']' but found end of input", 1, 9} = result
    end

    test "returns error for nested unmatched brackets" do
      {:ok, tokens} = Lexer.tokenize("data[users[index")
      result = parse_positionless(tokens)

      assert {:error, "Expected ']' but found end of input", 1, 17} = result
    end

    test "parses bracket access with complex nested expression" do
      {:ok, tokens} = Lexer.tokenize("cache[users[active AND valid]['name']]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access, {:identifier, "cache"},
         {:bracket_access,
          {:bracket_access, {:identifier, "users"},
           {:logical_and, {:identifier, "active"}, {:identifier, "valid"}}},
          {:string_literal, "name", :single}}}

      assert {:ok, ^expected_ast} = result
    end
  end

  describe "type casts" do
    test "casts an identifier to integer" do
      {:ok, tokens} = Lexer.tokenize("x::integer")
      result = parse_positionless(tokens)

      assert {:ok, {:cast, {:identifier, "x"}, "integer"}} = result
    end

    test "each of the seven scalar type names parses" do
      for type_name <- ~w(integer float string boolean date datetime duration) do
        {:ok, tokens} = Lexer.tokenize("x::#{type_name}")

        assert {:ok, {:cast, {:identifier, "x"}, ^type_name}} = parse_positionless(tokens)
      end
    end

    # The parser's @cast_type_names is defined as Predicator.Cast.type_names/0
    # (one definition, no drift possible); this guard survives even if that
    # changes back to a hand-written list.
    test "the parser's vocabulary agrees with Predicator.Cast.type_names/0" do
      for type_name <- Predicator.Cast.type_names() do
        {:ok, tokens} = Lexer.tokenize("x::#{type_name}")

        assert {:ok, {:cast, {:identifier, "x"}, ^type_name}} = parse_positionless(tokens)
      end

      assert {:error, message, _line, _col} = Predicator.parse("x::not_a_real_type")
      assert message =~ "Unknown cast type 'not_a_real_type'"

      for type_name <- Predicator.Cast.type_names() do
        assert message =~ type_name
      end
    end

    test "casts a string literal" do
      {:ok, tokens} = Lexer.tokenize(~s("42"::integer))
      result = parse_positionless(tokens)

      assert {:ok, {:cast, {:string_literal, "42", :double}, "integer"}} = result
    end

    test "binds tighter than unary minus" do
      {:ok, tokens} = Lexer.tokenize("-1::integer")
      result = parse_positionless(tokens)

      assert {:ok, {:unary, :minus, {:cast, {:literal, 1}, "integer"}}} = result
    end

    test "binds tighter than logical not" do
      {:ok, tokens} = Lexer.tokenize("!x::boolean")
      result = parse_positionless(tokens)

      assert {:ok, {:logical_not, {:cast, {:identifier, "x"}, "boolean"}}} = result
    end

    test "casts a property access" do
      {:ok, tokens} = Lexer.tokenize("x.y::string")
      result = parse_positionless(tokens)

      assert {:ok, {:cast, {:property_access, {:identifier, "x"}, "y"}, "string"}} = result
    end

    test "casts a function call" do
      {:ok, tokens} = Lexer.tokenize("f(x)::integer")
      result = parse_positionless(tokens)

      assert {:ok, {:cast, {:function_call, "f", [{:identifier, "x"}]}, "integer"}} = result
    end

    test "casts a bracket access" do
      {:ok, tokens} = Lexer.tokenize("x[0]::integer")
      result = parse_positionless(tokens)

      assert {:ok, {:cast, {:bracket_access, {:identifier, "x"}, {:literal, 0}}, "integer"}} =
               result
    end

    test "brackets a cast" do
      {:ok, tokens} = Lexer.tokenize("x::string[0]")
      result = parse_positionless(tokens)

      assert {:ok, {:bracket_access, {:cast, {:identifier, "x"}, "string"}, {:literal, 0}}} =
               result
    end

    test "a cast is the left side of a comparison" do
      {:ok, tokens} = Lexer.tokenize("x::integer > 5")
      result = parse_positionless(tokens)

      assert {:ok, {:comparison, :gt, {:cast, {:identifier, "x"}, "integer"}, {:literal, 5}}} =
               result
    end

    test "a cast is the left side of an arithmetic expression" do
      {:ok, tokens} = Lexer.tokenize("x::integer + 1")
      result = parse_positionless(tokens)

      assert {:ok, {:arithmetic, :add, {:cast, {:identifier, "x"}, "integer"}, {:literal, 1}}} =
               result
    end

    test "casts a parenthesized expression" do
      {:ok, tokens} = Lexer.tokenize("(x + 1)::integer")
      result = parse_positionless(tokens)

      assert {:ok, {:cast, {:arithmetic, :add, {:identifier, "x"}, {:literal, 1}}, "integer"}} =
               result
    end

    test "chains left-to-right" do
      {:ok, tokens} = Lexer.tokenize(~s("2026-08-09"::date::datetime))
      result = parse_positionless(tokens)

      assert {:ok, {:cast, {:cast, {:string_literal, "2026-08-09", :double}, "date"}, "datetime"}} =
               result
    end

    test "an unknown type name is a parse error naming the type's own column" do
      assert {:error, message, 1, 4} = Predicator.parse("x::foo")

      assert message ==
               "Unknown cast type 'foo' - expected one of: integer, float, string, " <>
                 "boolean, date, datetime, duration"
    end

    test "a missing type name at end of input is a parse error" do
      assert {:error, "Expected a type name after '::' but found end of input", 1, 4} =
               Predicator.parse("x::")
    end

    test "a number after '::' is a parse error" do
      assert {:error, message, 1, 4} = Predicator.parse("x::5")
      assert message =~ "Expected a type name after '::' but found number '5'"
    end

    test "'::' followed by a function-call-shaped name reports a missing type name" do
      assert {:error, message, 1, 4} = Predicator.parse("x::integer(1)")
      assert message =~ "Expected a type name after '::' but found function 'integer'"
    end

    test "a chained unknown type names the first unknown name, not the last" do
      assert {:error, message, 1, 4} = Predicator.parse("x::foo::integer")
      assert message =~ "Unknown cast type 'foo'"
    end

    test "a cast is not an assignable location" do
      {:ok, tokens} = Lexer.tokenize("x::integer = 1")

      assert {:error, message, _line, _col} = Predicator.Parser.parse_program(tokens)
      assert message =~ "must be an assignable location"
    end

    test "the seven type names are still contextual identifiers, not keywords" do
      {:ok, tokens} = Lexer.tokenize("integer > 5")
      result = parse_positionless(tokens)

      assert {:ok, {:comparison, :gt, {:identifier, "integer"}, {:literal, 5}}} = result
    end

    test "each of the seven type names parses alone as a plain identifier" do
      for type_name <- ~w(integer float string boolean date datetime duration) do
        {:ok, tokens} = Lexer.tokenize(type_name)

        assert {:ok, {:identifier, ^type_name}} = parse_positionless(tokens)
      end
    end

    test "a type name is still a valid property name" do
      {:ok, tokens} = Lexer.tokenize("x.date")
      result = parse_positionless(tokens)

      assert {:ok, {:property_access, {:identifier, "x"}, "date"}} = result
    end

    test "a type name is still a valid object key" do
      {:ok, tokens} = Lexer.tokenize("{date: 1, string: 2}")
      result = parse_positionless(tokens)

      assert {:ok,
              {:object,
               [
                 {{:object_key, "date", :identifier}, {:literal, 1}},
                 {{:object_key, "string", :identifier}, {:literal, 2}}
               ]}} = result
    end

    test "a type name is still a valid assignment target" do
      {:ok, tokens} = Lexer.tokenize("string = 1")

      assert {:ok, {:program, [{:assignment, {:identifier, "string"}, {:literal, 1}}]}} =
               parse_program_positionless(tokens)
    end

    test "a variable named after a type name can itself be cast" do
      {:ok, tokens} = Lexer.tokenize("duration::string")
      result = parse_positionless(tokens)

      assert {:ok, {:cast, {:identifier, "duration"}, "string"}} = result
    end

    test "a type name is still a valid function argument" do
      {:ok, tokens} = Lexer.tokenize("f(integer)")
      result = parse_positionless(tokens)

      assert {:ok, {:function_call, "f", [{:identifier, "integer"}]}} = result
    end
  end

  describe "parse/1 - duration expressions" do
    test "parses simple duration with single unit" do
      {:ok, tokens} = Lexer.tokenize("5d")
      result = parse_positionless(tokens)
      assert {:ok, {:duration, [{5, "d"}]}} = result
    end

    test "parses duration with multiple units" do
      {:ok, tokens} = Lexer.tokenize("1d8h30m")
      result = parse_positionless(tokens)
      assert {:ok, {:duration, [{1, "d"}, {8, "h"}, {30, "m"}]}} = result
    end

    test "parses duration with all unit types" do
      {:ok, tokens} = Lexer.tokenize("2y3mo4w5d6h7m8s")
      result = parse_positionless(tokens)

      assert {:ok,
              {:duration, [{2, "y"}, {3, "mo"}, {4, "w"}, {5, "d"}, {6, "h"}, {7, "m"}, {8, "s"}]}} =
               result
    end

    test "parses duration with single character units" do
      {:ok, tokens} = Lexer.tokenize("1y2mo3w4d5h6m7s")
      result = parse_positionless(tokens)

      assert {:ok,
              {:duration, [{1, "y"}, {2, "mo"}, {3, "w"}, {4, "d"}, {5, "h"}, {6, "m"}, {7, "s"}]}} =
               result
    end

    test "parses relative date with 'ago'" do
      {:ok, tokens} = Lexer.tokenize("1d8h ago")
      result = parse_positionless(tokens)
      assert {:ok, {:relative_date, {:duration, [{1, "d"}, {8, "h"}]}, :ago}} = result
    end

    test "parses relative date with 'from now'" do
      {:ok, tokens} = Lexer.tokenize("2h30m from now")
      result = parse_positionless(tokens)
      assert {:ok, {:relative_date, {:duration, [{2, "h"}, {30, "m"}]}, :future}} = result
    end

    test "parses relative date with 'next'" do
      {:ok, tokens} = Lexer.tokenize("next 1w")
      result = parse_positionless(tokens)
      assert {:ok, {:relative_date, {:duration, [{1, "w"}]}, :next}} = result
    end

    test "parses relative date with 'last'" do
      {:ok, tokens} = Lexer.tokenize("last 6mo")
      result = parse_positionless(tokens)
      assert {:ok, {:relative_date, {:duration, [{6, "mo"}]}, :last}} = result
    end

    test "duration in comparison expression" do
      {:ok, tokens} = Lexer.tokenize("created_at > 1d ago")
      result = parse_positionless(tokens)

      expected_ast =
        {:comparison, :gt, {:identifier, "created_at"},
         {:relative_date, {:duration, [{1, "d"}]}, :ago}}

      assert {:ok, ^expected_ast} = result
    end

    test "duration in complex expression" do
      {:ok, tokens} = Lexer.tokenize("created_at > 1d ago AND updated_at < 1h from now")
      result = parse_positionless(tokens)

      expected_ast =
        {:logical_and,
         {:comparison, :gt, {:identifier, "created_at"},
          {:relative_date, {:duration, [{1, "d"}]}, :ago}},
         {:comparison, :lt, {:identifier, "updated_at"},
          {:relative_date, {:duration, [{1, "h"}]}, :future}}}

      assert {:ok, ^expected_ast} = result
    end

    test "returns error for invalid duration sequence" do
      {:ok, tokens} = Lexer.tokenize("1d8x")
      result = parse_positionless(tokens)
      assert {:error, _message, _line, _col} = result
    end

    test "returns error for missing 'now' after 'from'" do
      {:ok, tokens} = Lexer.tokenize("1d from yesterday")
      result = parse_positionless(tokens)
      assert {:error, _message, _line, _col} = result
    end

    test "returns error for 'from' without duration" do
      {:ok, tokens} = Lexer.tokenize("from now")
      result = parse_positionless(tokens)
      assert {:error, _message, _line, _col} = result
    end

    test "returns error for 'ago' without duration" do
      {:ok, tokens} = Lexer.tokenize("ago")
      result = parse_positionless(tokens)
      assert {:error, _message, _line, _col} = result
    end

    test "returns error for 'next' without duration" do
      {:ok, tokens} = Lexer.tokenize("next")
      result = parse_positionless(tokens)
      assert {:error, _message, _line, _col} = result
    end

    test "returns error for 'last' without duration" do
      {:ok, tokens} = Lexer.tokenize("last")
      result = parse_positionless(tokens)
      assert {:error, _message, _line, _col} = result
    end

    test "parses zero duration" do
      {:ok, tokens} = Lexer.tokenize("0d")
      result = parse_positionless(tokens)
      assert {:ok, {:duration, [{0, "d"}]}} = result
    end

    test "parses large duration numbers" do
      {:ok, tokens} = Lexer.tokenize("999y365d24h60m60s")
      result = parse_positionless(tokens)

      assert {:ok, {:duration, [{999, "y"}, {365, "d"}, {24, "h"}, {60, "m"}, {60, "s"}]}} =
               result
    end
  end

  describe "parse_program/2" do
    test "parses a single-statement program" do
      {:ok, tokens} = Lexer.tokenize("a = 1")

      assert parse_program_positionless(tokens) ==
               {:ok, {:program, [{:assignment, {:identifier, "a"}, {:literal, 1}}]}}
    end

    test "parses a multi-statement program" do
      {:ok, tokens} = Lexer.tokenize("a = 1; b = 2")

      assert parse_program_positionless(tokens) ==
               {:ok,
                {:program,
                 [
                   {:assignment, {:identifier, "a"}, {:literal, 1}},
                   {:assignment, {:identifier, "b"}, {:literal, 2}}
                 ]}}
    end

    test "a single trailing semicolon is optional and normalizes away" do
      {:ok, tokens} = Lexer.tokenize("a = 1;")

      assert parse_program_positionless(tokens) ==
               {:ok, {:program, [{:assignment, {:identifier, "a"}, {:literal, 1}}]}}
    end

    test "a bare expression is a valid statement" do
      {:ok, tokens} = Lexer.tokenize("score > 85")

      assert parse_program_positionless(tokens) ==
               {:ok, {:program, [{:comparison, :gt, {:identifier, "score"}, {:literal, 85}}]}}
    end

    test "assignments and expression statements mix freely" do
      {:ok, tokens} = Lexer.tokenize("a = 1; score > 85; b = 2")

      assert parse_program_positionless(tokens) ==
               {:ok,
                {:program,
                 [
                   {:assignment, {:identifier, "a"}, {:literal, 1}},
                   {:comparison, :gt, {:identifier, "score"}, {:literal, 85}},
                   {:assignment, {:identifier, "b"}, {:literal, 2}}
                 ]}}
    end

    test "assigns to a property chain" do
      {:ok, tokens} = Lexer.tokenize("user.profile.name = 'Ada'")

      assert {:ok,
              {:program,
               [
                 {:assignment,
                  {:property_access, {:property_access, {:identifier, "user"}, "profile"},
                   "name"}, {:string_literal, "Ada", :single}}
               ]}} = parse_program_positionless(tokens)
    end

    test "assigns to a bracket access" do
      {:ok, tokens} = Lexer.tokenize("items[0] = 1")

      assert parse_program_positionless(tokens) ==
               {:ok,
                {:program,
                 [
                   {:assignment, {:bracket_access, {:identifier, "items"}, {:literal, 0}},
                    {:literal, 1}}
                 ]}}
    end

    test "assigns to a mixed property/bracket chain" do
      {:ok, tokens} = Lexer.tokenize("a.b[0].c = 1")

      assert parse_program_positionless(tokens) ==
               {:ok,
                {:program,
                 [
                   {:assignment,
                    {:property_access,
                     {:bracket_access, {:property_access, {:identifier, "a"}, "b"},
                      {:literal, 0}}, "c"}, {:literal, 1}}
                 ]}}
    end

    test "assigns through a computed bracket key" do
      {:ok, tokens} = Lexer.tokenize("a[k] = 1")

      assert parse_program_positionless(tokens) ==
               {:ok,
                {:program,
                 [
                   {:assignment, {:bracket_access, {:identifier, "a"}, {:identifier, "k"}},
                    {:literal, 1}}
                 ]}}
    end

    test "the rhs is a full expression - arithmetic" do
      {:ok, tokens} = Lexer.tokenize("b = a + 1")

      assert parse_program_positionless(tokens) ==
               {:ok,
                {:program,
                 [
                   {:assignment, {:identifier, "b"},
                    {:arithmetic, :add, {:identifier, "a"}, {:literal, 1}}}
                 ]}}
    end

    test "the rhs is a full expression - comparison and logical and" do
      {:ok, tokens} = Lexer.tokenize("b = x > 1 and y")

      assert parse_program_positionless(tokens) ==
               {:ok,
                {:program,
                 [
                   {:assignment, {:identifier, "b"},
                    {:logical_and, {:comparison, :gt, {:identifier, "x"}, {:literal, 1}},
                     {:identifier, "y"}}}
                 ]}}
    end

    test "parentheses are transparent, so (a) = 1 parses as an assignment" do
      {:ok, tokens} = Lexer.tokenize("(a) = 1")

      assert parse_program_positionless(tokens) ==
               {:ok, {:program, [{:assignment, {:identifier, "a"}, {:literal, 1}}]}}
    end

    test "non-assignable lhs: integer literal gives the location-shape error" do
      {:ok, tokens} = Lexer.tokenize("42 = 1")

      assert {:error, message, 1, 4} = Predicator.Parser.parse_program(tokens)

      assert message ==
               "Left side of '=' must be an assignable location - an identifier, a property " <>
                 "access, or a bracket access."
    end

    test "non-assignable lhs: function call gives the location-shape error" do
      {:ok, tokens} = Lexer.tokenize("len(x) = 1")

      assert {:error, message, _line, _col} = Predicator.Parser.parse_program(tokens)
      assert message =~ "must be an assignable location"
    end

    test "non-assignable lhs: string literal gives the location-shape error" do
      {:ok, tokens} = Lexer.tokenize("'s' = 1")

      assert {:error, message, _line, _col} = Predicator.Parser.parse_program(tokens)
      assert message =~ "must be an assignable location"
    end

    test "non-assignable lhs: list literal gives the location-shape error" do
      {:ok, tokens} = Lexer.tokenize("[1] = 2")

      assert {:error, message, _line, _col} = Predicator.Parser.parse_program(tokens)
      assert message =~ "must be an assignable location"
    end

    test "non-assignable lhs: unary minus gives the location-shape error, not the == fix-it" do
      {:ok, tokens} = Lexer.tokenize("-a = 1")

      assert {:error, message, _line, _col} = Predicator.Parser.parse_program(tokens)
      assert message =~ "must be an assignable location"
      refute message =~ "is not an equality operator"
    end

    test "nested assignment in a parenthesized rhs gives the == fix-it error" do
      {:ok, tokens} = Lexer.tokenize("a = (b = 1)")

      assert {:error, message, _line, _col} = Predicator.Parser.parse_program(tokens)
      assert message =~ "is not an equality operator"
    end

    test "chained assignment a = b = 1 gives the == fix-it error" do
      {:ok, tokens} = Lexer.tokenize("a = b = 1")

      assert {:error, message, _line, _col} = Predicator.Parser.parse_program(tokens)
      assert message =~ "is not an equality operator"
    end

    test "empty input is a parse error" do
      {:ok, tokens} = Lexer.tokenize("")
      assert {:error, _message, _line, _col} = Predicator.Parser.parse_program(tokens)
    end

    test "a lone semicolon is a parse error - no empty statements" do
      {:ok, tokens} = Lexer.tokenize(";")
      assert {:error, _message, _line, _col} = Predicator.Parser.parse_program(tokens)
    end

    test "two semicolons in a row is a parse error - no empty statements" do
      {:ok, tokens} = Lexer.tokenize("a;;b")
      assert {:error, _message, _line, _col} = Predicator.Parser.parse_program(tokens)
    end

    test "leftover tokens after a statement report a pointed error" do
      {:ok, tokens} = Lexer.tokenize("a = 1 extra")

      assert Predicator.Parser.parse_program(tokens) ==
               {:error, "Unexpected token identifier 'extra' after statement", 1, 7}
    end
  end

  describe "parse_program/2 - positions and spans" do
    test "an assignment's point position is the '=' token, span lhs start to rhs end" do
      {:ok, tokens} = Lexer.tokenize("a = 1")

      assert Predicator.Parser.parse_program(tokens) ==
               {:ok,
                {:program,
                 [{:assignment, {:identifier, "a", {1, 1}}, {:literal, 1, {1, 5}}, {1, 3}}],
                 {1, 1}}}

      assert Predicator.Parser.parse_program(tokens, spans: true) ==
               {:ok,
                {:program,
                 [
                   {:assignment, {:identifier, "a", {{1, 1}, {1, 2}}},
                    {:literal, 1, {{1, 5}, {1, 6}}}, {{1, 1}, {1, 6}}}
                 ], {{1, 1}, {1, 6}}}}
    end

    test "the program's span covers all statements and excludes a trailing ';'" do
      {:ok, tokens} = Lexer.tokenize("a = 1; b = 2;")

      assert {:ok, {:program, _statements, {{1, 1}, {1, 13}}}} =
               Predicator.Parser.parse_program(tokens, spans: true)
    end

    test "position mode gives the program's point as its first token's position" do
      {:ok, tokens} = Lexer.tokenize("score > 85; a = 1")

      assert {:ok, {:program, _statements, {1, 1}}} = Predicator.Parser.parse_program(tokens)
    end
  end

  describe "Predicator.parse_program/2 - the façade" do
    test "parses a multi-statement program from source" do
      assert {:ok, {:program, statements, _pos}} = Predicator.parse_program("a = 1; b = a + 1")
      assert length(statements) == 2
    end

    test "propagates lexer errors" do
      assert Predicator.parse_program("a = @") == Predicator.parse("a = @")
    end

    test "propagates parser errors" do
      assert Predicator.parse_program("42 = 1") ==
               {:error,
                "Left side of '=' must be an assignable location - an identifier, a property " <>
                  "access, or a bracket access.", 1, 4}
    end

    test "accepts spans: true" do
      assert {:ok, {:program, _statements, {{1, 1}, _end}}} =
               Predicator.parse_program("a = 1", spans: true)
    end
  end

  describe "guard: the deliberate px-tbv.2 gaps" do
    test "Compiler.to_instructions/2 compiles a program AST" do
      {:ok, program} = Predicator.parse_program("a = 1")

      assert Predicator.Compiler.to_instructions(program) == [
               ["lit", "a"],
               ["lit", 1],
               ["store", 1]
             ]
    end

    test "Compiler.to_instructions/2 compiles an assignment AST" do
      {:ok, {:program, [assignment], _pos}} = Predicator.parse_program("a = 1")

      assert Predicator.Compiler.to_instructions(assignment) == [
               ["lit", "a"],
               ["lit", 1],
               ["store", 1]
             ]
    end

    # ContextLocation.resolve/2 has a catch-all (context_location.ex:307-309)
    # that reads any unhandled node as :invalid_node - correct here, since
    # assigning to a program or an assignment is nonsense and neither is
    # reachable through resolve_expression/2, which parses with parse/2.
    test "ContextLocation.resolve/2 returns :invalid_node for a program AST" do
      {:ok, program} = Predicator.parse_program("a = 1")

      assert {:error, %Predicator.Errors.LocationError{type: :invalid_node}} =
               Predicator.ContextLocation.resolve(program, %{})
    end

    test "ContextLocation.resolve/2 returns :invalid_node for an assignment AST" do
      {:ok, {:program, [assignment], _pos}} = Predicator.parse_program("a = 1")

      assert {:error, %Predicator.Errors.LocationError{type: :invalid_node}} =
               Predicator.ContextLocation.resolve(assignment, %{})
    end
  end

  # These assertions are about AST *shape*, so they read the slot-free form;
  # positions and spans have their own suites.
  defp parse_positionless(input) do
    result =
      if is_binary(input),
        do: Predicator.parse(input),
        else: Predicator.Parser.parse(input)

    case result do
      {:ok, ast} -> {:ok, Predicator.ASTShape.strip(ast)}
      other -> other
    end
  end

  defp parse_program_positionless(tokens) do
    case Predicator.Parser.parse_program(tokens) do
      {:ok, program} -> {:ok, Predicator.ASTShape.strip(program)}
      other -> other
    end
  end
end
