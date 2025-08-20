defmodule Predicator.ParserTest do
  use ExUnit.Case, async: true

  alias Predicator.{Lexer, Parser}

  doctest Predicator.Parser

  describe "parse/1 - primary expressions" do
    test "parses integer literal" do
      {:ok, tokens} = Lexer.tokenize("42")
      assert Parser.parse(tokens) == {:ok, {:literal, 42}}
    end

    test "parses string literal" do
      {:ok, tokens} = Lexer.tokenize("\"hello\"")
      assert Parser.parse(tokens) == {:ok, {:string_literal, "hello", :double}}
    end

    test "parses single quoted string literal" do
      {:ok, tokens} = Lexer.tokenize("'hello'")
      assert Parser.parse(tokens) == {:ok, {:string_literal, "hello", :single}}
    end

    test "parses boolean literal true" do
      {:ok, tokens} = Lexer.tokenize("true")
      assert Parser.parse(tokens) == {:ok, {:literal, true}}
    end

    test "parses boolean literal false" do
      {:ok, tokens} = Lexer.tokenize("false")
      assert Parser.parse(tokens) == {:ok, {:literal, false}}
    end

    test "parses identifier" do
      {:ok, tokens} = Lexer.tokenize("score")
      assert Parser.parse(tokens) == {:ok, {:identifier, "score"}}
    end

    test "parses parenthesized expression" do
      {:ok, tokens} = Lexer.tokenize("(42)")
      assert Parser.parse(tokens) == {:ok, {:literal, 42}}
    end

    test "parses nested parentheses" do
      {:ok, tokens} = Lexer.tokenize("((score))")
      assert Parser.parse(tokens) == {:ok, {:identifier, "score"}}
    end
  end

  describe "parse/1 - comparison expressions" do
    test "parses greater than comparison" do
      {:ok, tokens} = Lexer.tokenize("score > 85")

      expected = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      assert Parser.parse(tokens) == {:ok, expected}
    end

    test "parses less than comparison" do
      {:ok, tokens} = Lexer.tokenize("age < 18")

      expected = {:comparison, :lt, {:identifier, "age"}, {:literal, 18}}
      assert Parser.parse(tokens) == {:ok, expected}
    end

    test "parses greater than or equal comparison" do
      {:ok, tokens} = Lexer.tokenize("score >= 85")

      expected = {:comparison, :gte, {:identifier, "score"}, {:literal, 85}}
      assert Parser.parse(tokens) == {:ok, expected}
    end

    test "parses less than or equal comparison" do
      {:ok, tokens} = Lexer.tokenize("age <= 65")

      expected = {:comparison, :lte, {:identifier, "age"}, {:literal, 65}}
      assert Parser.parse(tokens) == {:ok, expected}
    end

    test "parses equality comparison" do
      {:ok, tokens} = Lexer.tokenize("name = \"John\"")

      expected = {:comparison, :eq, {:identifier, "name"}, {:string_literal, "John", :double}}
      assert Parser.parse(tokens) == {:ok, expected}
    end

    test "parses equality comparison with single quotes" do
      {:ok, tokens} = Lexer.tokenize("name = 'John'")

      expected = {:comparison, :eq, {:identifier, "name"}, {:string_literal, "John", :single}}
      assert Parser.parse(tokens) == {:ok, expected}
    end

    test "parses not equal comparison" do
      {:ok, tokens} = Lexer.tokenize("status != \"inactive\"")

      expected =
        {:comparison, :ne, {:identifier, "status"}, {:string_literal, "inactive", :double}}

      assert Parser.parse(tokens) == {:ok, expected}
    end

    test "parses number to number comparison" do
      {:ok, tokens} = Lexer.tokenize("10 > 5")

      expected = {:comparison, :gt, {:literal, 10}, {:literal, 5}}
      assert Parser.parse(tokens) == {:ok, expected}
    end

    test "parses boolean comparison" do
      {:ok, tokens} = Lexer.tokenize("active = true")

      expected = {:comparison, :eq, {:identifier, "active"}, {:literal, true}}
      assert Parser.parse(tokens) == {:ok, expected}
    end
  end

  describe "parse/1 - parenthesized comparisons" do
    test "parses comparison in parentheses" do
      {:ok, tokens} = Lexer.tokenize("(score > 85)")

      expected = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      assert Parser.parse(tokens) == {:ok, expected}
    end

    test "parses parenthesized left operand" do
      {:ok, tokens} = Lexer.tokenize("(score) > 85")

      expected = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      assert Parser.parse(tokens) == {:ok, expected}
    end

    test "parses parenthesized right operand" do
      {:ok, tokens} = Lexer.tokenize("score > (85)")

      expected = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      assert Parser.parse(tokens) == {:ok, expected}
    end

    test "parses both operands parenthesized" do
      {:ok, tokens} = Lexer.tokenize("(score) > (85)")

      expected = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      assert Parser.parse(tokens) == {:ok, expected}
    end
  end

  describe "parse/1 - complex expressions" do
    test "handles whitespace correctly" do
      {:ok, tokens} = Lexer.tokenize("  score   >    85  ")

      expected = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      assert Parser.parse(tokens) == {:ok, expected}
    end

    test "handles mixed types" do
      {:ok, tokens} = Lexer.tokenize(~s("apple" > "banana"))

      expected =
        {:comparison, :gt, {:string_literal, "apple", :double},
         {:string_literal, "banana", :double}}

      assert Parser.parse(tokens) == {:ok, expected}
    end
  end

  describe "parse/1 - error cases" do
    test "returns error for empty token list" do
      result = Parser.parse([])
      assert {:error, "Unexpected end of input", 1, 1} = result
    end

    test "returns error for only EOF token" do
      tokens = [{:eof, 1, 1, 0, nil}]
      result = Parser.parse(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found end of input",
              1, 1} = result
    end

    test "returns error for incomplete comparison" do
      {:ok, tokens} = Lexer.tokenize("score >")

      result = Parser.parse(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found end of input",
              1, 8} = result
    end

    test "returns error for invalid left operand" do
      # This would be caught by the lexer, but let's test with a constructed token
      tokens = [{:gt, 1, 1, 1, ">"}, {:integer, 1, 3, 2, 85}, {:eof, 1, 5, 0, nil}]
      result = Parser.parse(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found '>'",
              1,
              1} =
               result
    end

    test "returns error for missing right operand" do
      {:ok, tokens} = Lexer.tokenize("score > >")

      result = Parser.parse(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found '>'",
              1,
              9} =
               result
    end

    test "returns error for unterminated parentheses" do
      {:ok, tokens} = Lexer.tokenize("(score")

      result = Parser.parse(tokens)
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

      result = Parser.parse(tokens)
      assert {:error, "Expected ')' but found identifier ']'", 1, 7} = result
    end

    test "returns error for extra tokens after expression" do
      {:ok, tokens} = Lexer.tokenize("score > 85 extra")

      result = Parser.parse(tokens)
      assert {:error, "Unexpected token identifier 'extra' after expression", 1, 12} = result
    end

    test "returns error for multiple operators" do
      {:ok, tokens} = Lexer.tokenize("score > > 85")

      result = Parser.parse(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found '>'",
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
      assert Parser.parse(tokens) == {:ok, expected}
    end

    test "handles complex parenthesized expressions" do
      input = "((score) >= (threshold))"
      {:ok, tokens} = Lexer.tokenize(input)

      expected = {:comparison, :gte, {:identifier, "score"}, {:identifier, "threshold"}}
      assert Parser.parse(tokens) == {:ok, expected}
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

      result = Parser.parse(tokens)
      assert {:error, "Expected ')' but reached end of input", 1, 1} = result
    end

    test "handles nested error propagation from inner expressions" do
      # Test error propagation through parentheses
      {:ok, tokens} = Lexer.tokenize("(score > )")

      result = Parser.parse(tokens)
      assert {:error, message, 1, 10} = result

      assert message =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found ')'"
    end

    test "handles comparison operator followed by EOF" do
      tokens = [
        {:identifier, 1, 1, 5, "score"},
        {:gt, 1, 7, 1, ">"},
        {:eof, 1, 8, 0, nil}
      ]

      result = Parser.parse(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found end of input",
              1, 8} = result
    end

    test "handles unexpected token types in primary position" do
      # Test different token types that would fail in primary position
      test_cases = [
        {[:gt],
         "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found '>'"},
        {[:lt],
         "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found '<'"},
        {[:gte],
         "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found '>='"},
        {[:lte],
         "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found '<='"},
        {[:eq],
         "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found '='"},
        {[:ne],
         "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found '!='"}
      ]

      for {token_types, expected_message} <- test_cases do
        [token_type] = token_types
        tokens = [{token_type, 1, 1, 1, to_string(token_type)}, {:eof, 1, 2, 0, nil}]

        result = Parser.parse(tokens)
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
        result = Parser.parse(tokens)
        assert {:error, _message, 1, 1} = result
      end

      # Test parentheses and other tokens in wrong positions
      other_tokens = [
        {:rparen, 1, 1, 1, ")"},
        {:eof, 1, 1, 0, nil}
      ]

      for token <- other_tokens do
        tokens = [token, {:eof, 1, 3, 0, nil}]
        result = Parser.parse(tokens)
        assert {:error, _message, 1, 1} = result
      end
    end

    test "handles rparen token in unexpected position" do
      tokens = [
        {:rparen, 1, 1, 1, ")"},
        {:eof, 1, 2, 0, nil}
      ]

      result = Parser.parse(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found ')'",
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

      result = Parser.parse(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found ')'",
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

      result = Parser.parse(tokens)

      assert {:ok,
              {:logical_and, {:comparison, :gt, {:identifier, "score"}, {:literal, 85}},
               {:comparison, :gte, {:identifier, "age"}, {:literal, 18}}}} = result
    end

    test "parses simple OR expression" do
      tokens = [
        {:identifier, 1, 1, 4, "role"},
        {:eq, 1, 6, 1, "="},
        {:string, 1, 8, 7, "admin", :double},
        {:or_op, 1, 16, 2, "OR"},
        {:identifier, 1, 19, 4, "role"},
        {:eq, 1, 24, 1, "="},
        {:string, 1, 26, 9, "manager", :double},
        {:eof, 1, 36, 0, nil}
      ]

      result = Parser.parse(tokens)

      assert {:ok,
              {:logical_or,
               {:comparison, :eq, {:identifier, "role"}, {:string_literal, "admin", :double}},
               {:comparison, :eq, {:identifier, "role"}, {:string_literal, "manager", :double}}}} =
               result
    end

    test "parses simple NOT expression" do
      tokens = [
        {:not_op, 1, 1, 3, "NOT"},
        {:identifier, 1, 5, 7, "expired"},
        {:eq, 1, 13, 1, "="},
        {:boolean, 1, 15, 4, true},
        {:eof, 1, 19, 0, nil}
      ]

      result = Parser.parse(tokens)

      assert {:ok, {:logical_not, {:comparison, :eq, {:identifier, "expired"}, {:literal, true}}}} =
               result
    end

    test "parses nested NOT expression" do
      tokens = [
        {:not_op, 1, 1, 3, "NOT"},
        {:not_op, 1, 5, 3, "NOT"},
        {:boolean, 1, 9, 4, true},
        {:eof, 1, 13, 0, nil}
      ]

      result = Parser.parse(tokens)

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

      result = Parser.parse(tokens)

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

      result = Parser.parse(tokens)

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

      result = Parser.parse(tokens)

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

      result = Parser.parse(tokens)

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

      result = Parser.parse(tokens)

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

      result = Parser.parse(tokens)

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

      result = Parser.parse(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found end of input",
              1, 9} = result
    end

    test "handles error when OR missing right operand" do
      tokens = [
        {:boolean, 1, 1, 4, true},
        {:or_op, 1, 6, 2, "OR"},
        {:eof, 1, 8, 0, nil}
      ]

      result = Parser.parse(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found end of input",
              1, 8} = result
    end

    test "handles error when NOT missing operand" do
      tokens = [
        {:not_op, 1, 1, 3, "NOT"},
        {:eof, 1, 4, 0, nil}
      ]

      result = Parser.parse(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found end of input",
              1, 4} = result
    end

    test "complex mixed expression with comparisons and logical operators" do
      # score > 85 AND age >= 18 OR admin = true
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
        {:eq, 1, 35, 1, "="},
        {:boolean, 1, 37, 4, true},
        {:eof, 1, 41, 0, nil}
      ]

      result = Parser.parse(tokens)

      assert {:ok,
              {:logical_or,
               {:logical_and, {:comparison, :gt, {:identifier, "score"}, {:literal, 85}},
                {:comparison, :gte, {:identifier, "age"}, {:literal, 18}}},
               {:comparison, :eq, {:identifier, "admin"}, {:literal, true}}}} = result
    end
  end

  describe "date and datetime parsing" do
    test "parses date literals correctly" do
      tokens = [
        {:date, 1, 1, 12, ~D[2024-01-15]},
        {:eof, 1, 13, 0, nil}
      ]

      result = Parser.parse(tokens)
      assert {:ok, {:literal, ~D[2024-01-15]}} = result
    end

    test "parses datetime literals correctly" do
      {:ok, datetime, _offset} = DateTime.from_iso8601("2024-01-15T10:30:00Z")

      tokens = [
        {:datetime, 1, 1, 21, datetime},
        {:eof, 1, 22, 0, nil}
      ]

      result = Parser.parse(tokens)
      assert {:ok, {:literal, ^datetime}} = result
    end

    test "parses date comparisons" do
      tokens = [
        {:date, 1, 1, 12, ~D[2024-01-15]},
        {:gt, 1, 14, 1, ">"},
        {:date, 1, 16, 12, ~D[2024-01-10]},
        {:eof, 1, 28, 0, nil}
      ]

      result = Parser.parse(tokens)

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

      result = Parser.parse(tokens)
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

      result = Parser.parse(tokens)

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

      result = Parser.parse(tokens)
      assert {:error, "Expected ']' but found number '2'", 1, 4} = result
    end

    test "handles comparison with missing left operand in complex expression" do
      tokens = [
        {:and_op, 1, 1, 3, "AND"},
        {:integer, 1, 5, 2, 42},
        {:eof, 1, 7, 0, nil}
      ]

      result = Parser.parse(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found 'AND'",
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

      result = Parser.parse(tokens)
      assert {:ok, {:membership, :in, {:literal, 1}, {:list, []}}} = result
    end
  end
end
