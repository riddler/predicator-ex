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

  describe "tokenize/1 - duration literals (px-5c5)" do
    test "tokenizes an integer duration as integer plus duration-unit tokens" do
      assert {:ok, tokens} = Lexer.tokenize("3d8h")

      assert tokens == [
               {:integer, 1, 1, 1, 3},
               {:duration_unit, 1, 2, 1, "d"},
               {:integer, 1, 3, 1, 8},
               {:duration_unit, 1, 4, 1, "h"},
               {:eof, 1, 5, 0, nil}
             ]
    end

    test "tokenizes a fractional duration as a fractional_number token" do
      assert {:ok, tokens} = Lexer.tokenize("1.5s")

      assert tokens == [
               {:fractional_number, 1, 1, 3, {1, "5"}},
               {:duration_unit, 1, 4, 1, "s"},
               {:eof, 1, 5, 0, nil}
             ]
    end

    test "a decimal number with no duration unit still tokenizes as a float" do
      assert {:ok, tokens} = Lexer.tokenize("1.5")

      assert tokens == [
               {:float, 1, 1, 3, 1.5},
               {:eof, 1, 4, 0, nil}
             ]
    end

    test "a decimal number followed by a non-unit tokenizes as float then identifier" do
      assert {:ok, tokens} = Lexer.tokenize("1.5x")

      assert tokens == [
               {:float, 1, 1, 3, 1.5},
               {:identifier, 1, 4, 1, "x"},
               {:eof, 1, 5, 0, nil}
             ]
    end
  end

  describe "tokenize/1 - semicolon" do
    test "tokenizes a lone semicolon" do
      assert {:ok, tokens} = Lexer.tokenize(";")

      assert tokens == [
               {:semicolon, 1, 1, 1, ";"},
               {:eof, 1, 2, 0, nil}
             ]
    end

    test "tokenizes semicolon at the start of input" do
      assert {:ok, tokens} = Lexer.tokenize(";a")

      assert tokens == [
               {:semicolon, 1, 1, 1, ";"},
               {:identifier, 1, 2, 1, "a"},
               {:eof, 1, 3, 0, nil}
             ]
    end

    test "tokenizes semicolon in the middle of input, adjacent to identifiers" do
      assert {:ok, tokens} = Lexer.tokenize("a;b")

      assert tokens == [
               {:identifier, 1, 1, 1, "a"},
               {:semicolon, 1, 2, 1, ";"},
               {:identifier, 1, 3, 1, "b"},
               {:eof, 1, 4, 0, nil}
             ]
    end

    test "tokenizes semicolon at the end of input" do
      assert {:ok, tokens} = Lexer.tokenize("a;")

      assert tokens == [
               {:identifier, 1, 1, 1, "a"},
               {:semicolon, 1, 2, 1, ";"},
               {:eof, 1, 3, 0, nil}
             ]
    end

    test "tracks columns correctly with surrounding whitespace" do
      assert {:ok, tokens} = Lexer.tokenize("a ; b")

      assert tokens == [
               {:identifier, 1, 1, 1, "a"},
               {:semicolon, 1, 3, 1, ";"},
               {:identifier, 1, 5, 1, "b"},
               {:eof, 1, 6, 0, nil}
             ]
    end

    test "tokenizes semicolon adjacent to other punctuation" do
      assert {:ok, tokens} = Lexer.tokenize("(a);[b]")

      assert tokens == [
               {:lparen, 1, 1, 1, "("},
               {:identifier, 1, 2, 1, "a"},
               {:rparen, 1, 3, 1, ")"},
               {:semicolon, 1, 4, 1, ";"},
               {:lbracket, 1, 5, 1, "["},
               {:identifier, 1, 6, 1, "b"},
               {:rbracket, 1, 7, 1, "]"},
               {:eof, 1, 8, 0, nil}
             ]
    end

    test "does not affect colon and comma tokenization" do
      assert {:ok, tokens} = Lexer.tokenize("{a: 1, b: 2}")

      assert tokens == [
               {:lbrace, 1, 1, 1, "{"},
               {:identifier, 1, 2, 1, "a"},
               {:colon, 1, 3, 1, ":"},
               {:integer, 1, 5, 1, 1},
               {:comma, 1, 6, 1, ","},
               {:identifier, 1, 8, 1, "b"},
               {:colon, 1, 9, 1, ":"},
               {:integer, 1, 11, 1, 2},
               {:rbrace, 1, 12, 1, "}"},
               {:eof, 1, 13, 0, nil}
             ]
    end

    test "multiple semicolons in sequence each tokenize independently" do
      assert {:ok, tokens} = Lexer.tokenize("a;;b")

      assert tokens == [
               {:identifier, 1, 1, 1, "a"},
               {:semicolon, 1, 2, 1, ";"},
               {:semicolon, 1, 3, 1, ";"},
               {:identifier, 1, 4, 1, "b"},
               {:eof, 1, 5, 0, nil}
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
               {:string, 1, 8, 6, "John", :double, {1, 14}},
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
      assert {:error, "Unexpected character '@'", 1, 1, _span} = Lexer.tokenize("@")
    end

    test "tokenizes standalone exclamation as bang" do
      assert {:ok, [{:bang, 1, 1, 1, "!"}, {:eof, 1, 2, 0, nil}]} = Lexer.tokenize("!")
    end

    test "returns error with correct position" do
      assert {:error, "Unterminated date literal", 1, 9, {{1, 9}, {1, 10}}} =
               Lexer.tokenize("score > #")
    end

    test "returns error on multiline with correct position" do
      input = """
      score > 85
      name @ "John"
      """

      assert {:error, "Unexpected character '@'", 2, 6, _span} = Lexer.tokenize(input)
    end

    test "an 'unexpected character' failure spans exactly one character" do
      assert {:error, "Unexpected character '@'", 1, 1, {{1, 1}, {1, 2}}} = Lexer.tokenize("@")
    end

    test "an unterminated string's span lands the caret on the opening quote" do
      assert {:error, "Unterminated double-quoted string literal", 1, 1, {{1, 1}, {1, 2}}} =
               Lexer.tokenize(~s("unterminated))
    end

    test "an unterminated single-quoted string also keeps a one-character span" do
      assert {:error, "Unterminated single-quoted string literal", 1, 1, {{1, 1}, {1, 2}}} =
               Lexer.tokenize(~s('unterminated))
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
                {:string, 1, 1, 33, "Hello \"World\" with \n newline", :double, {1, 34}},
                {:eof, 1, 34, 0, nil}
              ]} = Lexer.tokenize(input)
    end

    test "handles all escape sequences" do
      input = ~s("Test \\t\\r\\n\\\\ sequences")

      assert {:ok,
              [
                {:string, 1, 1, 25, "Test \t\r\n\\ sequences", :double, {1, 26}},
                {:eof, 1, 26, 0, nil}
              ]} = Lexer.tokenize(input)
    end

    test "handles unknown escape sequences as literal characters" do
      input = ~s("Unknown \\x escape")

      assert {:ok,
              [
                {:string, 1, 1, 19, "Unknown x escape", :double, {1, 20}},
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
