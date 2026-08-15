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

    test "tokenizes the undefined keyword" do
      assert {:ok, tokens} = Lexer.tokenize("undefined")

      assert tokens == [
               {:undefined, 1, 1, 9, :undefined},
               {:eof, 1, 10, 0, nil}
             ]
    end

    test "does not classify UNDEFINED or Undefined as the undefined keyword" do
      assert {:ok, tokens} = Lexer.tokenize("UNDEFINED")

      assert tokens == [
               {:identifier, 1, 1, 9, "UNDEFINED"},
               {:eof, 1, 10, 0, nil}
             ]

      assert {:ok, tokens} = Lexer.tokenize("Undefined")

      assert tokens == [
               {:identifier, 1, 1, 9, "Undefined"},
               {:eof, 1, 10, 0, nil}
             ]
    end

    test "does not turn undefined( into a function_name" do
      assert {:ok, tokens} = Lexer.tokenize("undefined(1)")

      assert tokens == [
               {:undefined, 1, 1, 9, :undefined},
               {:lparen, 1, 10, 1, "("},
               {:integer, 1, 11, 1, 1},
               {:rparen, 1, 12, 1, ")"},
               {:eof, 1, 13, 0, nil}
             ]
    end

    test "tokenizes the null keyword" do
      assert {:ok, tokens} = Lexer.tokenize("null")

      assert tokens == [
               {:null, 1, 1, 4, nil},
               {:eof, 1, 5, 0, nil}
             ]
    end

    test "does not classify NULL or Null as the null keyword" do
      assert {:ok, tokens} = Lexer.tokenize("NULL")

      assert tokens == [
               {:identifier, 1, 1, 4, "NULL"},
               {:eof, 1, 5, 0, nil}
             ]

      assert {:ok, tokens} = Lexer.tokenize("Null")

      assert tokens == [
               {:identifier, 1, 1, 4, "Null"},
               {:eof, 1, 5, 0, nil}
             ]
    end

    test "does not classify nullable or null_count as the null keyword" do
      assert {:ok, tokens} = Lexer.tokenize("nullable")

      assert tokens == [
               {:identifier, 1, 1, 8, "nullable"},
               {:eof, 1, 9, 0, nil}
             ]

      assert {:ok, tokens} = Lexer.tokenize("null_count")

      assert tokens == [
               {:identifier, 1, 1, 10, "null_count"},
               {:eof, 1, 11, 0, nil}
             ]
    end

    test "does not turn null( into a function_name" do
      assert {:ok, tokens} = Lexer.tokenize("null(1)")

      assert tokens == [
               {:null, 1, 1, 4, nil},
               {:lparen, 1, 5, 1, "("},
               {:integer, 1, 6, 1, 1},
               {:rparen, 1, 7, 1, ")"},
               {:eof, 1, 8, 0, nil}
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

    test "tokenizes the statement keywords if, else, and while" do
      assert {:ok, tokens} = Lexer.tokenize("if")

      assert tokens == [
               {:if_kw, 1, 1, 2, "if"},
               {:eof, 1, 3, 0, nil}
             ]

      assert {:ok, tokens} = Lexer.tokenize("else")

      assert tokens == [
               {:else_kw, 1, 1, 4, "else"},
               {:eof, 1, 5, 0, nil}
             ]

      assert {:ok, tokens} = Lexer.tokenize("while")

      assert tokens == [
               {:while_kw, 1, 1, 5, "while"},
               {:eof, 1, 6, 0, nil}
             ]
    end

    test "only the lowercase spelling of if/else/while is reserved" do
      assert {:ok, tokens} = Lexer.tokenize("IF")

      assert tokens == [
               {:identifier, 1, 1, 2, "IF"},
               {:eof, 1, 3, 0, nil}
             ]

      assert {:ok, tokens} = Lexer.tokenize("Else")

      assert tokens == [
               {:identifier, 1, 1, 4, "Else"},
               {:eof, 1, 5, 0, nil}
             ]

      assert {:ok, tokens} = Lexer.tokenize("WHILE")

      assert tokens == [
               {:identifier, 1, 1, 5, "WHILE"},
               {:eof, 1, 6, 0, nil}
             ]
    end

    test "identifiers that merely contain a reserved word stay identifiers" do
      assert {:ok, tokens} = Lexer.tokenize("iffy")

      assert tokens == [
               {:identifier, 1, 1, 4, "iffy"},
               {:eof, 1, 5, 0, nil}
             ]

      assert {:ok, tokens} = Lexer.tokenize("elsewhere")

      assert tokens == [
               {:identifier, 1, 1, 9, "elsewhere"},
               {:eof, 1, 10, 0, nil}
             ]

      assert {:ok, tokens} = Lexer.tokenize("whilst")

      assert tokens == [
               {:identifier, 1, 1, 6, "whilst"},
               {:eof, 1, 7, 0, nil}
             ]
    end

    test "'if (x)' does not lex as a function call" do
      assert {:ok, tokens} = Lexer.tokenize("if (x)")

      assert tokens == [
               {:if_kw, 1, 1, 2, "if"},
               {:lparen, 1, 4, 1, "("},
               {:identifier, 1, 5, 1, "x"},
               {:rparen, 1, 6, 1, ")"},
               {:eof, 1, 7, 0, nil}
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
               {:string, 1, 2, 7, "admin", :double, {1, 9}},
               {:comma, 1, 9, 1, ","},
               {:string, 1, 11, 9, "manager", :double, {1, 20}},
               {:rbracket, 1, 20, 1, "]"},
               {:eof, 1, 21, 0, nil}
             ]
    end
  end

  describe "tokenize/1 - string literals" do
    test "tokenizes simple string" do
      assert {:ok, tokens} = Lexer.tokenize(~s("hello"))

      assert tokens == [
               {:string, 1, 1, 7, "hello", :double, {1, 8}},
               {:eof, 1, 8, 0, nil}
             ]
    end

    test "tokenizes empty string" do
      assert {:ok, tokens} = Lexer.tokenize(~s(""))

      assert tokens == [
               {:string, 1, 1, 2, "", :double, {1, 3}},
               {:eof, 1, 3, 0, nil}
             ]
    end

    test "tokenizes string with spaces" do
      assert {:ok, tokens} = Lexer.tokenize(~s("hello world"))

      assert tokens == [
               {:string, 1, 1, 13, "hello world", :double, {1, 14}},
               {:eof, 1, 14, 0, nil}
             ]
    end

    test "tokenizes string with escape sequences" do
      # Input: "hello\"world" (with escaped quote)
      input = "\"hello\\\"world\""
      assert {:ok, tokens} = Lexer.tokenize(input)

      assert tokens == [
               {:string, 1, 1, 14, "hello\"world", :double, {1, 15}},
               {:eof, 1, 15, 0, nil}
             ]
    end

    test "tokenizes string with newline escape" do
      # Input: "line1\nline2" (with escaped newline)
      input = "\"line1\\nline2\""
      assert {:ok, tokens} = Lexer.tokenize(input)

      assert tokens == [
               {:string, 1, 1, 14, "line1\nline2", :double, {1, 15}},
               {:eof, 1, 15, 0, nil}
             ]
    end

    test "returns error for unterminated string" do
      assert {:error, "Unterminated double-quoted string literal", 1, 1, _span} =
               Lexer.tokenize(~s("hello))
    end
  end

  describe "tokenize/1 - single quoted string literals" do
    test "tokenizes simple single quoted string" do
      assert {:ok, tokens} = Lexer.tokenize("'hello'")

      assert tokens == [
               {:string, 1, 1, 7, "hello", :single, {1, 8}},
               {:eof, 1, 8, 0, nil}
             ]
    end

    test "tokenizes empty single quoted string" do
      assert {:ok, tokens} = Lexer.tokenize("''")

      assert tokens == [
               {:string, 1, 1, 2, "", :single, {1, 3}},
               {:eof, 1, 3, 0, nil}
             ]
    end

    test "tokenizes single quoted string with spaces" do
      assert {:ok, tokens} = Lexer.tokenize("'hello world'")

      assert tokens == [
               {:string, 1, 1, 13, "hello world", :single, {1, 14}},
               {:eof, 1, 14, 0, nil}
             ]
    end

    test "tokenizes single quoted string with escaped single quotes" do
      # Input: 'hello\'world' (with escaped quote)
      input = "'hello\\'world'"
      assert {:ok, tokens} = Lexer.tokenize(input)

      assert tokens == [
               {:string, 1, 1, 14, "hello'world", :single, {1, 15}},
               {:eof, 1, 15, 0, nil}
             ]
    end

    test "tokenizes single quoted string with double quotes (no escaping needed)" do
      input = "'hello\"world'"
      assert {:ok, tokens} = Lexer.tokenize(input)

      assert tokens == [
               {:string, 1, 1, 13, "hello\"world", :single, {1, 14}},
               {:eof, 1, 14, 0, nil}
             ]
    end

    test "tokenizes single quoted string with escape sequences" do
      # Input: 'line1\nline2' (with escaped newline)
      input = "'line1\\nline2'"
      assert {:ok, tokens} = Lexer.tokenize(input)

      assert tokens == [
               {:string, 1, 1, 14, "line1\nline2", :single, {1, 15}},
               {:eof, 1, 15, 0, nil}
             ]
    end

    test "returns error for unterminated single quoted string" do
      assert {:error, "Unterminated single-quoted string literal", 1, 1, _span} =
               Lexer.tokenize("'hello")
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

  describe "tokenize/1 - arithmetic operators" do
    test "tokenizes plus operator" do
      assert {:ok, tokens} = Lexer.tokenize("2 + 3")

      assert tokens == [
               {:integer, 1, 1, 1, 2},
               {:plus, 1, 3, 1, "+"},
               {:integer, 1, 5, 1, 3},
               {:eof, 1, 6, 0, nil}
             ]
    end

    test "tokenizes minus operator" do
      assert {:ok, tokens} = Lexer.tokenize("5 - 2")

      assert tokens == [
               {:integer, 1, 1, 1, 5},
               {:minus, 1, 3, 1, "-"},
               {:integer, 1, 5, 1, 2},
               {:eof, 1, 6, 0, nil}
             ]
    end

    test "tokenizes multiply operator" do
      assert {:ok, tokens} = Lexer.tokenize("3 * 4")

      assert tokens == [
               {:integer, 1, 1, 1, 3},
               {:multiply, 1, 3, 1, "*"},
               {:integer, 1, 5, 1, 4},
               {:eof, 1, 6, 0, nil}
             ]
    end

    test "tokenizes divide operator" do
      assert {:ok, tokens} = Lexer.tokenize("8 / 2")

      assert tokens == [
               {:integer, 1, 1, 1, 8},
               {:divide, 1, 3, 1, "/"},
               {:integer, 1, 5, 1, 2},
               {:eof, 1, 6, 0, nil}
             ]
    end

    test "tokenizes modulo operator" do
      assert {:ok, tokens} = Lexer.tokenize("7 % 3")

      assert tokens == [
               {:integer, 1, 1, 1, 7},
               {:modulo, 1, 3, 1, "%"},
               {:integer, 1, 5, 1, 3},
               {:eof, 1, 6, 0, nil}
             ]
    end

    test "tokenizes double equals operator" do
      assert {:ok, tokens} = Lexer.tokenize("x == y")

      assert tokens == [
               {:identifier, 1, 1, 1, "x"},
               {:equal_equal, 1, 3, 2, "=="},
               {:identifier, 1, 6, 1, "y"},
               {:eof, 1, 7, 0, nil}
             ]
    end

    test "tokenizes logical and operator" do
      assert {:ok, tokens} = Lexer.tokenize("true && false")

      assert tokens == [
               {:boolean, 1, 1, 4, true},
               {:and_and, 1, 6, 2, "&&"},
               {:boolean, 1, 9, 5, false},
               {:eof, 1, 14, 0, nil}
             ]
    end

    test "tokenizes logical or operator" do
      assert {:ok, tokens} = Lexer.tokenize("true || false")

      assert tokens == [
               {:boolean, 1, 1, 4, true},
               {:or_or, 1, 6, 2, "||"},
               {:boolean, 1, 9, 5, false},
               {:eof, 1, 14, 0, nil}
             ]
    end

    test "tokenizes bang (not) operator" do
      assert {:ok, tokens} = Lexer.tokenize("!active")

      assert tokens == [
               {:bang, 1, 1, 1, "!"},
               {:identifier, 1, 2, 6, "active"},
               {:eof, 1, 8, 0, nil}
             ]
    end

    test "tokenizes complex arithmetic expression" do
      assert {:ok, tokens} = Lexer.tokenize("(x + y) * z / 2")

      assert tokens == [
               {:lparen, 1, 1, 1, "("},
               {:identifier, 1, 2, 1, "x"},
               {:plus, 1, 4, 1, "+"},
               {:identifier, 1, 6, 1, "y"},
               {:rparen, 1, 7, 1, ")"},
               {:multiply, 1, 9, 1, "*"},
               {:identifier, 1, 11, 1, "z"},
               {:divide, 1, 13, 1, "/"},
               {:integer, 1, 15, 1, 2},
               {:eof, 1, 16, 0, nil}
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
      assert {:error, "Invalid date format: not-a-date", 1, 1, {{1, 1}, {1, 13}}} =
               Lexer.tokenize("#not-a-date#")
    end

    test "returns error for invalid datetime format" do
      assert {:error, "Invalid datetime format: 2024-01-15T25:00:00Z", 1, 1, {{1, 1}, {1, 23}}} =
               Lexer.tokenize("#2024-01-15T25:00:00Z#")
    end

    test "returns error for unterminated date literal" do
      assert {:error, "Unterminated date literal", 1, 1, {{1, 1}, {1, 12}}} =
               Lexer.tokenize("#2024-01-15")

      assert {:error, "Unterminated date literal", 1, 9, {{1, 9}, {1, 10}}} =
               Lexer.tokenize("score > #")
    end
  end

  describe "raw newlines inside literals" do
    test "a date literal broken across lines gets a multi-line error span" do
      assert {:error, "Invalid date format: " <> _content, 1, 1, {{1, 1}, {2, 7}}} =
               Lexer.tokenize("#2024-\n01-01#")
    end

    test "advances line and resets column across a multi-line double-quoted string" do
      assert {:ok, tokens} = Lexer.tokenize("\"ab\ncd\" > 5")

      assert tokens == [
               {:string, 1, 1, 7, "ab\ncd", :double, {2, 4}},
               {:gt, 2, 5, 1, ">"},
               {:integer, 2, 7, 1, 5},
               {:eof, 2, 8, 0, nil}
             ]
    end

    test "advances line and resets column across a multi-line single-quoted string" do
      assert {:ok, tokens} = Lexer.tokenize("'ab\ncd' > 5")

      assert tokens == [
               {:string, 1, 1, 7, "ab\ncd", :single, {2, 4}},
               {:gt, 2, 5, 1, ">"},
               {:integer, 2, 7, 1, 5},
               {:eof, 2, 8, 0, nil}
             ]
    end

    test "an escaped \\n is not a raw newline - every token stays on line 1" do
      assert {:ok, tokens} = Lexer.tokenize(~S|"a\nb" > 5|)

      assert tokens == [
               {:string, 1, 1, 6, "a\nb", :double, {1, 7}},
               {:gt, 1, 8, 1, ">"},
               {:integer, 1, 10, 1, 5},
               {:eof, 1, 11, 0, nil}
             ]
    end

    test "a CRLF line ending inside a string crosses to line 2" do
      assert {:ok, tokens} = Lexer.tokenize("\"ab\r\ncd\" > 5")

      assert tokens == [
               {:string, 1, 1, 8, "ab\r\ncd", :double, {2, 4}},
               {:gt, 2, 5, 1, ">"},
               {:integer, 2, 7, 1, 5},
               {:eof, 2, 8, 0, nil}
             ]
    end

    test "two consecutive multi-line literals accumulate line advances" do
      assert {:ok, tokens} = Lexer.tokenize(~s("ab\ncd" "ef\ngh" x))

      assert tokens == [
               {:string, 1, 1, 7, "ab\ncd", :double, {2, 4}},
               {:string, 2, 5, 7, "ef\ngh", :double, {3, 4}},
               {:identifier, 3, 5, 1, "x"},
               {:eof, 3, 6, 0, nil}
             ]
    end

    test "a bare newline outside a literal is unaffected" do
      assert {:ok, tokens} = Lexer.tokenize("x\n> 5")

      assert tokens == [
               {:identifier, 1, 1, 1, "x"},
               {:gt, 2, 1, 1, ">"},
               {:integer, 2, 3, 1, 5},
               {:eof, 2, 4, 0, nil}
             ]
    end

    test "a date literal containing a raw newline is a lex error" do
      # parse_date_content/1 rejects the embedded newline before a token can
      # be built, so a multi-line date token can never exist - this pins the
      # invariant that lets token_end/1 keep treating every date token as
      # single-line.
      assert {:error, _message, 1, 1, _span} = Lexer.tokenize("#2024-01-\n01# > 5")
    end
  end

  describe ":: token" do
    test "tokenizes a postfix cast" do
      assert {:ok, tokens} = Lexer.tokenize("x::integer")

      assert tokens == [
               {:identifier, 1, 1, 1, "x"},
               {:double_colon, 1, 2, 2, "::"},
               {:identifier, 1, 4, 7, "integer"},
               {:eof, 1, 11, 0, nil}
             ]
    end

    test "does not affect single-colon object literal tokenization" do
      assert {:ok, tokens} = Lexer.tokenize("{a: 1}")

      assert tokens == [
               {:lbrace, 1, 1, 1, "{"},
               {:identifier, 1, 2, 1, "a"},
               {:colon, 1, 3, 1, ":"},
               {:integer, 1, 5, 1, 1},
               {:rbrace, 1, 6, 1, "}"},
               {:eof, 1, 7, 0, nil}
             ]

      refute Enum.any?(tokens, &match?({:double_colon, _, _, _, _}, &1))
    end

    test "does not affect nested object literal tokenization" do
      assert {:ok, tokens} = Lexer.tokenize("{a: {b: 1}}")

      refute Enum.any?(tokens, &match?({:double_colon, _, _, _, _}, &1))
    end

    test "lexes ::: greedily as double_colon followed by colon" do
      assert {:ok, tokens} = Lexer.tokenize(":::")

      assert tokens == [
               {:double_colon, 1, 1, 2, "::"},
               {:colon, 1, 3, 1, ":"},
               {:eof, 1, 4, 0, nil}
             ]
    end

    test "tokenizes :: with surrounding spaces" do
      assert {:ok, tokens} = Lexer.tokenize("x :: integer")

      assert tokens == [
               {:identifier, 1, 1, 1, "x"},
               {:double_colon, 1, 3, 2, "::"},
               {:identifier, 1, 6, 7, "integer"},
               {:eof, 1, 13, 0, nil}
             ]
    end

    test "does not affect datetime literal colon consumption" do
      input = "#2024-01-15T10:30:00Z#"
      {:ok, tokens} = Lexer.tokenize(input)

      assert [
               {:datetime, 1, 1, 22, %DateTime{}},
               {:eof, 1, 23, 0, nil}
             ] = tokens

      refute Enum.any?(tokens, &match?({:colon, _, _, _, _}, &1))
      refute Enum.any?(tokens, &match?({:double_colon, _, _, _, _}, &1))
    end

    test "the seven cast type names still lex as plain identifiers" do
      for type_name <- ~w(integer float string boolean date datetime duration) do
        assert {:ok, tokens} = Lexer.tokenize(type_name)

        assert [
                 {:identifier, 1, 1, _len, ^type_name},
                 {:eof, _eof_line, _eof_col, 0, nil}
               ] = tokens
      end
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
