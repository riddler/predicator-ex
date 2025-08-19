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
      assert Parser.parse(tokens) == {:ok, {:literal, "hello"}}
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

      expected = {:comparison, :eq, {:identifier, "name"}, {:literal, "John"}}
      assert Parser.parse(tokens) == {:ok, expected}
    end

    test "parses not equal comparison" do
      {:ok, tokens} = Lexer.tokenize("status != \"inactive\"")

      expected = {:comparison, :ne, {:identifier, "status"}, {:literal, "inactive"}}
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
      {:ok, tokens} = Lexer.tokenize("\"apple\" > \"banana\"")

      expected = {:comparison, :gt, {:literal, "apple"}, {:literal, "banana"}}
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
              "Expected number, string, boolean, identifier, or '(' but found end of input", 1,
              1} = result
    end

    test "returns error for incomplete comparison" do
      {:ok, tokens} = Lexer.tokenize("score >")

      result = Parser.parse(tokens)

      assert {:error,
              "Expected number, string, boolean, identifier, or '(' but found end of input", 1,
              8} = result
    end

    test "returns error for invalid left operand" do
      # This would be caught by the lexer, but let's test with a constructed token
      tokens = [{:gt, 1, 1, 1, ">"}, {:integer, 1, 3, 2, 85}, {:eof, 1, 5, 0, nil}]
      result = Parser.parse(tokens)

      assert {:error, "Expected number, string, boolean, identifier, or '(' but found '>'", 1, 1} =
               result
    end

    test "returns error for missing right operand" do
      {:ok, tokens} = Lexer.tokenize("score > >")

      result = Parser.parse(tokens)

      assert {:error, "Expected number, string, boolean, identifier, or '(' but found '>'", 1, 9} =
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

      assert {:error, "Expected number, string, boolean, identifier, or '(' but found '>'", 1, 9} =
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
end
