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

    test "tokenizes uppercase logical operators" do
      assert {:ok, tokens} = Lexer.tokenize("AND")

      assert tokens == [
               {:and_op, 1, 1, 3, "AND"},
               {:eof, 1, 4, 0, nil}
             ]

      assert {:ok, tokens} = Lexer.tokenize("OR")

      assert tokens == [
               {:or_op, 1, 1, 2, "OR"},
               {:eof, 1, 3, 0, nil}
             ]

      assert {:ok, tokens} = Lexer.tokenize("NOT")

      assert tokens == [
               {:not_op, 1, 1, 3, "NOT"},
               {:eof, 1, 4, 0, nil}
             ]
    end

    test "tokenizes lowercase logical operators" do
      assert {:ok, tokens} = Lexer.tokenize("and")

      assert tokens == [
               {:and_op, 1, 1, 3, "and"},
               {:eof, 1, 4, 0, nil}
             ]

      assert {:ok, tokens} = Lexer.tokenize("or")

      assert tokens == [
               {:or_op, 1, 1, 2, "or"},
               {:eof, 1, 3, 0, nil}
             ]

      assert {:ok, tokens} = Lexer.tokenize("not")

      assert tokens == [
               {:not_op, 1, 1, 3, "not"},
               {:eof, 1, 4, 0, nil}
             ]
    end

    test "tokenizes membership operators" do
      assert {:ok, tokens} = Lexer.tokenize("IN")

      assert tokens == [
               {:in_op, 1, 1, 2, "IN"},
               {:eof, 1, 3, 0, nil}
             ]

      assert {:ok, tokens} = Lexer.tokenize("in")

      assert tokens == [
               {:in_op, 1, 1, 2, "in"},
               {:eof, 1, 3, 0, nil}
             ]

      assert {:ok, tokens} = Lexer.tokenize("CONTAINS")

      assert tokens == [
               {:contains_op, 1, 1, 8, "CONTAINS"},
               {:eof, 1, 9, 0, nil}
             ]

      assert {:ok, tokens} = Lexer.tokenize("contains")

      assert tokens == [
               {:contains_op, 1, 1, 8, "contains"},
               {:eof, 1, 9, 0, nil}
             ]
    end
  end

  describe "tokenize/1 - list literals" do
    test "tokenizes empty list" do
      assert {:ok, tokens} = Lexer.tokenize("[]")

      assert tokens == [
               {:lbracket, 1, 1, 1, "["},
               {:rbracket, 1, 2, 1, "]"},
               {:eof, 1, 3, 0, nil}
             ]
    end

    test "tokenizes list with commas" do
      assert {:ok, tokens} = Lexer.tokenize("[1, 2, 3]")

      assert tokens == [
               {:lbracket, 1, 1, 1, "["},
               {:integer, 1, 2, 1, 1},
               {:comma, 1, 3, 1, ","},
               {:integer, 1, 5, 1, 2},
               {:comma, 1, 6, 1, ","},
               {:integer, 1, 8, 1, 3},
               {:rbracket, 1, 9, 1, "]"},
               {:eof, 1, 10, 0, nil}
             ]
    end

    test "tokenizes string list" do
      assert {:ok, tokens} = Lexer.tokenize(~s(["admin", "manager"]))

      assert tokens == [
               {:lbracket, 1, 1, 1, "["},
               {:string, 1, 2, 7, "admin"},
               {:comma, 1, 9, 1, ","},
               {:string, 1, 11, 9, "manager"},
               {:rbracket, 1, 20, 1, "]"},
               {:eof, 1, 21, 0, nil}
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
      assert {:error, "Unterminated date literal", 1, 9} = Lexer.tokenize("score > #")
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

  describe "date literal tokenization" do
    test "tokenizes valid date literals" do
      assert {:ok,
              [
                {:date, 1, 1, 12, ~D[2024-01-15]},
                {:eof, 1, 13, 0, nil}
              ]} = Lexer.tokenize("#2024-01-15#")
    end

    test "tokenizes valid datetime literals" do
      input = "#2024-01-15T10:30:00Z#"
      {:ok, tokens} = Lexer.tokenize(input)

      assert [
               {:datetime, 1, 1, 22, %DateTime{}},
               {:eof, 1, 23, 0, nil}
             ] = tokens
    end

    test "handles date with comparison" do
      input = "#2024-01-15# > #2024-01-10#"

      assert {:ok,
              [
                {:date, 1, 1, 12, ~D[2024-01-15]},
                {:gt, 1, 14, 1, ">"},
                {:date, 1, 16, 12, ~D[2024-01-10]},
                {:eof, 1, 28, 0, nil}
              ]} = Lexer.tokenize(input)
    end

    test "returns error for invalid date format" do
      assert {:error, "Invalid date format: not-a-date", 1, 1} = Lexer.tokenize("#not-a-date#")
    end

    test "returns error for invalid datetime format" do
      assert {:error, "Invalid datetime format: 2024-01-15T25:00:00Z", 1, 1} =
               Lexer.tokenize("#2024-01-15T25:00:00Z#")
    end

    test "returns error for unterminated date literal" do
      assert {:error, "Unterminated date literal", 1, 1} = Lexer.tokenize("#2024-01-15")
      assert {:error, "Unterminated date literal", 1, 9} = Lexer.tokenize("score > #")
    end
  end

  describe "additional edge cases for coverage" do
    test "handles carriage return characters" do
      input = "score > 85\r\nAND age >= 18"
      {:ok, tokens} = Lexer.tokenize(input)

      # Should handle \r properly and continue on next line
      # identifier, gt, integer, and_op, identifier, gte, integer, eof
      assert length(tokens) == 8
      assert {:and_op, 2, 1, 3, "AND"} = Enum.at(tokens, 3)
    end

    test "handles escaped characters in strings" do
      input = ~s("Hello \\\"World\\\" with \\n newline")

      assert {:ok,
              [
                {:string, 1, 1, 33, "Hello \"World\" with \n newline"},
                {:eof, 1, 34, 0, nil}
              ]} = Lexer.tokenize(input)
    end

    test "handles all escape sequences" do
      input = ~s("Test \\t\\r\\n\\\\ sequences")

      assert {:ok,
              [
                {:string, 1, 1, 25, "Test \t\r\n\\ sequences"},
                {:eof, 1, 26, 0, nil}
              ]} = Lexer.tokenize(input)
    end

    test "handles unknown escape sequences as literal characters" do
      input = ~s("Unknown \\x escape")

      assert {:ok,
              [
                {:string, 1, 1, 19, "Unknown x escape"},
                {:eof, 1, 20, 0, nil}
              ]} = Lexer.tokenize(input)
    end

    test "tokenizes numbers at start of input" do
      assert {:ok,
              [
                {:integer, 1, 1, 3, 123},
                {:eof, 1, 4, 0, nil}
              ]} = Lexer.tokenize("123")
    end

    test "handles identifiers with numbers and underscores" do
      input = "test_var_123 = value_2"

      assert {:ok,
              [
                {:identifier, 1, 1, 12, "test_var_123"},
                {:eq, 1, 14, 1, "="},
                {:identifier, 1, 16, 7, "value_2"},
                {:eof, 1, 23, 0, nil}
              ]} = Lexer.tokenize(input)
    end
  end

  describe "function calls" do
    test "tokenizes simple function call" do
      input = "len(name)"

      assert {:ok,
              [
                {:function_name, 1, 1, 3, "len"},
                {:lparen, 1, 4, 1, "("},
                {:identifier, 1, 5, 4, "name"},
                {:rparen, 1, 9, 1, ")"},
                {:eof, 1, 10, 0, nil}
              ]} = Lexer.tokenize(input)
    end

    test "tokenizes function call with whitespace" do
      input = "upper ( name )"

      assert {:ok,
              [
                {:function_name, 1, 1, 5, "upper"},
                {:lparen, 1, 7, 1, "("},
                {:identifier, 1, 9, 4, "name"},
                {:rparen, 1, 14, 1, ")"},
                {:eof, 1, 15, 0, nil}
              ]} = Lexer.tokenize(input)
    end

    test "tokenizes function call with multiple arguments" do
      input = "max(score, 100)"

      assert {:ok,
              [
                {:function_name, 1, 1, 3, "max"},
                {:lparen, 1, 4, 1, "("},
                {:identifier, 1, 5, 5, "score"},
                {:comma, 1, 10, 1, ","},
                {:integer, 1, 12, 3, 100},
                {:rparen, 1, 15, 1, ")"},
                {:eof, 1, 16, 0, nil}
              ]} = Lexer.tokenize(input)
    end

    test "tokenizes function call in expression" do
      input = "len(name) > 5"

      assert {:ok,
              [
                {:function_name, 1, 1, 3, "len"},
                {:lparen, 1, 4, 1, "("},
                {:identifier, 1, 5, 4, "name"},
                {:rparen, 1, 9, 1, ")"},
                {:gt, 1, 11, 1, ">"},
                {:integer, 1, 13, 1, 5},
                {:eof, 1, 14, 0, nil}
              ]} = Lexer.tokenize(input)
    end

    test "tokenizes nested function calls" do
      input = "upper(trim(name))"

      assert {:ok,
              [
                {:function_name, 1, 1, 5, "upper"},
                {:lparen, 1, 6, 1, "("},
                {:function_name, 1, 7, 4, "trim"},
                {:lparen, 1, 11, 1, "("},
                {:identifier, 1, 12, 4, "name"},
                {:rparen, 1, 16, 1, ")"},
                {:rparen, 1, 17, 1, ")"},
                {:eof, 1, 18, 0, nil}
              ]} = Lexer.tokenize(input)
    end

    test "distinguishes function calls from parenthesized expressions" do
      # This should be a regular identifier with parentheses (not a function call)
      input = "name AND (score > 85)"

      assert {:ok,
              [
                {:identifier, 1, 1, 4, "name"},
                {:and_op, 1, 6, 3, "AND"},
                {:lparen, 1, 10, 1, "("},
                {:identifier, 1, 11, 5, "score"},
                {:gt, 1, 17, 1, ">"},
                {:integer, 1, 19, 2, 85},
                {:rparen, 1, 21, 1, ")"},
                {:eof, 1, 22, 0, nil}
              ]} = Lexer.tokenize(input)
    end

    test "handles keywords that could be function names" do
      # "not" is a keyword, so "not(" should NOT be a function call - it stays as NOT keyword
      input = "not(active)"

      assert {:ok,
              [
                {:not_op, 1, 1, 3, "not"},
                {:lparen, 1, 4, 1, "("},
                {:identifier, 1, 5, 6, "active"},
                {:rparen, 1, 11, 1, ")"},
                {:eof, 1, 12, 0, nil}
              ]} = Lexer.tokenize(input)
    end
  end
end
