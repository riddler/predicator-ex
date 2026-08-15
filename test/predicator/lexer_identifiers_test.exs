defmodule Predicator.LexerIdentifiersTest do
  use ExUnit.Case, async: true

  alias Predicator.Lexer

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
end
