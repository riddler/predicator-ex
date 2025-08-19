defmodule Predicator.LexerTest do
  use ExUnit.Case, async: true

  alias Predicator.Lexer

  doctest Predicator.Lexer

  describe "tokenize/1 - integers" do
    test "tokenizes single integer" do
      assert {:ok, tokens} = Lexer.tokenize("42")

      assert tokens == [
               {:integer, 1, 1, 2, 42},
               {:eof, 1, 3, 0, nil}
             ]
    end

    test "tokenizes multi-digit integer" do
      assert {:ok, tokens} = Lexer.tokenize("1234")

      assert tokens == [
               {:integer, 1, 1, 4, 1234},
               {:eof, 1, 5, 0, nil}
             ]
    end

    test "tokenizes zero" do
      assert {:ok, tokens} = Lexer.tokenize("0")

      assert tokens == [
               {:integer, 1, 1, 1, 0},
               {:eof, 1, 2, 0, nil}
             ]
    end
  end

  describe "tokenize/1 - identifiers and keywords" do
    test "tokenizes simple identifier" do
      assert {:ok, tokens} = Lexer.tokenize("score")

      assert tokens == [
               {:identifier, 1, 1, 5, "score"},
               {:eof, 1, 6, 0, nil}
             ]
    end

    test "tokenizes identifier with underscores" do
      assert {:ok, tokens} = Lexer.tokenize("user_age")

      assert tokens == [
               {:identifier, 1, 1, 8, "user_age"},
               {:eof, 1, 9, 0, nil}
             ]
    end

    test "tokenizes identifier with numbers" do
      assert {:ok, tokens} = Lexer.tokenize("var123")

      assert tokens == [
               {:identifier, 1, 1, 6, "var123"},
               {:eof, 1, 7, 0, nil}
             ]
    end

    test "tokenizes boolean keywords" do
      assert {:ok, tokens} = Lexer.tokenize("true")

      assert tokens == [
               {:boolean, 1, 1, 4, true},
               {:eof, 1, 5, 0, nil}
             ]

      assert {:ok, tokens} = Lexer.tokenize("false")

      assert tokens == [
               {:boolean, 1, 1, 5, false},
               {:eof, 1, 6, 0, nil}
             ]
    end
  end

  describe "tokenize/1 - string literals" do
    test "tokenizes simple string" do
      assert {:ok, tokens} = Lexer.tokenize(~s("hello"))

      assert tokens == [
               {:string, 1, 1, 7, "hello"},
               {:eof, 1, 8, 0, nil}
             ]
    end

    test "tokenizes empty string" do
      assert {:ok, tokens} = Lexer.tokenize(~s(""))

      assert tokens == [
               {:string, 1, 1, 2, ""},
               {:eof, 1, 3, 0, nil}
             ]
    end

    test "tokenizes string with spaces" do
      assert {:ok, tokens} = Lexer.tokenize(~s("hello world"))

      assert tokens == [
               {:string, 1, 1, 13, "hello world"},
               {:eof, 1, 14, 0, nil}
             ]
    end

    test "tokenizes string with escape sequences" do
      # Input: "hello\"world" (with escaped quote)
      input = "\"hello\\\"world\""
      assert {:ok, tokens} = Lexer.tokenize(input)

      assert tokens == [
               {:string, 1, 1, 14, "hello\"world"},
               {:eof, 1, 15, 0, nil}
             ]
    end

    test "tokenizes string with newline escape" do
      # Input: "line1\nline2" (with escaped newline) 
      input = "\"line1\\nline2\""
      assert {:ok, tokens} = Lexer.tokenize(input)

      assert tokens == [
               {:string, 1, 1, 14, "line1\nline2"},
               {:eof, 1, 15, 0, nil}
             ]
    end

    test "returns error for unterminated string" do
      assert {:error, "Unterminated string literal", 1, 1} = Lexer.tokenize(~s("hello))
    end
  end

  describe "tokenize/1 - comparison operators" do
    test "tokenizes greater than" do
      assert {:ok, tokens} = Lexer.tokenize(">")

      assert tokens == [
               {:gt, 1, 1, 1, ">"},
               {:eof, 1, 2, 0, nil}
             ]
    end

    test "tokenizes greater than or equal" do
      assert {:ok, tokens} = Lexer.tokenize(">=")

      assert tokens == [
               {:gte, 1, 1, 2, ">="},
               {:eof, 1, 3, 0, nil}
             ]
    end

    test "tokenizes less than" do
      assert {:ok, tokens} = Lexer.tokenize("<")

      assert tokens == [
               {:lt, 1, 1, 1, "<"},
               {:eof, 1, 2, 0, nil}
             ]
    end

    test "tokenizes less than or equal" do
      assert {:ok, tokens} = Lexer.tokenize("<=")

      assert tokens == [
               {:lte, 1, 1, 2, "<="},
               {:eof, 1, 3, 0, nil}
             ]
    end

    test "tokenizes equal" do
      assert {:ok, tokens} = Lexer.tokenize("=")

      assert tokens == [
               {:eq, 1, 1, 1, "="},
               {:eof, 1, 2, 0, nil}
             ]
    end

    test "tokenizes not equal" do
      assert {:ok, tokens} = Lexer.tokenize("!=")

      assert tokens == [
               {:ne, 1, 1, 2, "!="},
               {:eof, 1, 3, 0, nil}
             ]
    end
  end

  describe "tokenize/1 - parentheses" do
    test "tokenizes parentheses" do
      assert {:ok, tokens} = Lexer.tokenize("()")

      assert tokens == [
               {:lparen, 1, 1, 1, "("},
               {:rparen, 1, 2, 1, ")"},
               {:eof, 1, 3, 0, nil}
             ]
    end
  end

  describe "tokenize/1 - complex expressions" do
    test "tokenizes simple comparison" do
      assert {:ok, tokens} = Lexer.tokenize("score > 85")

      assert tokens == [
               {:identifier, 1, 1, 5, "score"},
               {:gt, 1, 7, 1, ">"},
               {:integer, 1, 9, 2, 85},
               {:eof, 1, 11, 0, nil}
             ]
    end

    test "tokenizes comparison with string" do
      assert {:ok, tokens} = Lexer.tokenize(~s(name = "John"))

      assert tokens == [
               {:identifier, 1, 1, 4, "name"},
               {:eq, 1, 6, 1, "="},
               {:string, 1, 8, 6, "John"},
               {:eof, 1, 14, 0, nil}
             ]
    end

    test "tokenizes comparison with boolean" do
      assert {:ok, tokens} = Lexer.tokenize("active = true")

      assert tokens == [
               {:identifier, 1, 1, 6, "active"},
               {:eq, 1, 8, 1, "="},
               {:boolean, 1, 10, 4, true},
               {:eof, 1, 14, 0, nil}
             ]
    end

    test "tokenizes expression with parentheses" do
      assert {:ok, tokens} = Lexer.tokenize("(age >= 18)")

      assert tokens == [
               {:lparen, 1, 1, 1, "("},
               {:identifier, 1, 2, 3, "age"},
               {:gte, 1, 6, 2, ">="},
               {:integer, 1, 9, 2, 18},
               {:rparen, 1, 11, 1, ")"},
               {:eof, 1, 12, 0, nil}
             ]
    end

    test "handles multiple whitespace" do
      assert {:ok, tokens} = Lexer.tokenize("  score   >    85  ")

      assert tokens == [
               {:identifier, 1, 3, 5, "score"},
               {:gt, 1, 11, 1, ">"},
               {:integer, 1, 16, 2, 85},
               {:eof, 1, 20, 0, nil}
             ]
    end
  end

  describe "tokenize/1 - position tracking" do
    test "tracks line numbers correctly" do
      input = """
      score > 85
      age >= 18
      """

      assert {:ok, tokens} = Lexer.tokenize(input)

      assert tokens == [
               {:identifier, 1, 1, 5, "score"},
               {:gt, 1, 7, 1, ">"},
               {:integer, 1, 9, 2, 85},
               {:identifier, 2, 1, 3, "age"},
               {:gte, 2, 5, 2, ">="},
               {:integer, 2, 8, 2, 18},
               {:eof, 3, 1, 0, nil}
             ]
    end

    test "tracks columns with tabs" do
      assert {:ok, tokens} = Lexer.tokenize("score\t>\t85")

      assert tokens == [
               {:identifier, 1, 1, 5, "score"},
               {:gt, 1, 7, 1, ">"},
               {:integer, 1, 9, 2, 85},
               {:eof, 1, 11, 0, nil}
             ]
    end
  end

  describe "tokenize/1 - error cases" do
    test "returns error for unexpected character" do
      assert {:error, "Unexpected character '@'", 1, 1} = Lexer.tokenize("@")
    end

    test "returns error for standalone exclamation" do
      assert {:error, "Unexpected character '!'", 1, 1} = Lexer.tokenize("!")
    end

    test "returns error with correct position" do
      assert {:error, "Unexpected character '#'", 1, 9} = Lexer.tokenize("score > #")
    end

    test "returns error on multiline with correct position" do
      input = """
      score > 85
      name @ "John"
      """

      assert {:error, "Unexpected character '@'", 2, 6} = Lexer.tokenize(input)
    end
  end

  describe "tokenize/1 - edge cases" do
    test "tokenizes empty string" do
      assert {:ok, tokens} = Lexer.tokenize("")

      assert tokens == [
               {:eof, 1, 1, 0, nil}
             ]
    end

    test "tokenizes only whitespace" do
      assert {:ok, tokens} = Lexer.tokenize("   \n\t  ")

      assert tokens == [
               {:eof, 2, 4, 0, nil}
             ]
    end
  end
end
