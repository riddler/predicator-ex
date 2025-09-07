defmodule Predicator.LexerEdgeCasesTest do
  use ExUnit.Case

  alias Predicator.Lexer

  describe "lexer error handling" do
    test "handles unterminated date literal" do
      {:error, message, line, col} = Lexer.tokenize("#2024-01-01")
      assert message == "Unterminated date literal"
      assert line == 1
      assert col == 1
    end

    test "handles invalid date format" do
      {:error, message, line, col} = Lexer.tokenize("#invalid-date#")
      assert String.contains?(message, "Invalid date format")
      assert line == 1
      assert col == 1
    end

    test "handles invalid datetime format" do
      {:error, message, line, col} = Lexer.tokenize("#2024-01-01Tinvalid#")
      assert String.contains?(message, "Invalid datetime format")
      assert line == 1
      assert col == 1
    end

    test "handles unexpected characters" do
      {:error, message, line, col} = Lexer.tokenize("@")
      assert message == "Unexpected character '@'"
      assert line == 1
      assert col == 1
    end

    test "handles carriage return characters" do
      {:ok, tokens} = Lexer.tokenize("x\r\ny")

      assert tokens == [
               {:identifier, 1, 1, 1, "x"},
               {:identifier, 2, 1, 1, "y"},
               {:eof, 2, 2, 0, nil}
             ]
    end

    test "handles tab characters" do
      {:ok, tokens} = Lexer.tokenize("x\ty")

      assert tokens == [
               {:identifier, 1, 1, 1, "x"},
               {:identifier, 1, 3, 1, "y"},
               {:eof, 1, 4, 0, nil}
             ]
    end

    test "handles unterminated string" do
      {:error, message, line, col} = Lexer.tokenize("\"unterminated")
      assert message == "Unterminated double-quoted string literal"
      assert line == 1
      assert col == 1
    end

    test "handles unterminated single quote string" do
      {:error, message, line, col} = Lexer.tokenize("'unterminated")
      assert message == "Unterminated single-quoted string literal"
      assert line == 1
      assert col == 1
    end
  end

  describe "qualified identifiers" do
    test "handles regular qualified identifiers" do
      {:ok, tokens} = Lexer.tokenize("Math.pow(2, 3)")

      assert tokens == [
               {:qualified_function_name, 1, 1, 8, "Math.pow"},
               {:lparen, 1, 9, 1, "("},
               {:integer, 1, 10, 1, 2},
               {:comma, 1, 11, 1, ","},
               {:integer, 1, 13, 1, 3},
               {:rparen, 1, 14, 1, ")"},
               {:eof, 1, 15, 0, nil}
             ]
    end

    test "handles nested qualified identifiers" do
      {:ok, tokens} = Lexer.tokenize("Deep.Nested.Module.func()")

      assert tokens == [
               {:qualified_function_name, 1, 1, 23, "Deep.Nested.Module.func"},
               {:lparen, 1, 24, 1, "("},
               {:rparen, 1, 25, 1, ")"},
               {:eof, 1, 26, 0, nil}
             ]
    end

    test "handles qualified identifier not followed by function call" do
      {:ok, tokens} = Lexer.tokenize("obj.prop")

      assert tokens == [
               {:identifier, 1, 1, 3, "obj"},
               {:dot, 1, 4, 1, "."},
               {:identifier, 1, 5, 4, "prop"},
               {:eof, 1, 9, 0, nil}
             ]
    end
  end

  describe "number parsing edge cases" do
    test "handles decimal point without trailing digits" do
      {:ok, tokens} = Lexer.tokenize("42.")

      assert tokens == [
               {:integer, 1, 1, 2, 42},
               {:dot, 1, 3, 1, "."},
               {:eof, 1, 4, 0, nil}
             ]
    end

    test "handles large integers" do
      {:ok, tokens} = Lexer.tokenize("999999999")

      assert tokens == [
               {:integer, 1, 1, 9, 999_999_999},
               {:eof, 1, 10, 0, nil}
             ]
    end

    test "handles small floats" do
      {:ok, tokens} = Lexer.tokenize("0.001")

      assert tokens == [
               {:float, 1, 1, 5, 0.001},
               {:eof, 1, 6, 0, nil}
             ]
    end
  end

  describe "string parsing edge cases" do
    test "handles empty string" do
      {:ok, tokens} = Lexer.tokenize("\"\"")

      assert tokens == [
               {:string, 1, 1, 2, "", :double},
               {:eof, 1, 3, 0, nil}
             ]
    end

    test "handles empty single quote string" do
      {:ok, tokens} = Lexer.tokenize("''")

      assert tokens == [
               {:string, 1, 1, 2, "", :single},
               {:eof, 1, 3, 0, nil}
             ]
    end

    test "handles string with escaped quotes" do
      {:ok, tokens} = Lexer.tokenize(~s{"He said \\"hello\\""})

      assert tokens == [
               {:string, 1, 1, 19, "He said \"hello\"", :double},
               {:eof, 1, 20, 0, nil}
             ]
    end

    test "handles single quote string with escaped quotes" do
      {:ok, tokens} = Lexer.tokenize("'It\\'s working'")

      assert tokens == [
               {:string, 1, 1, 15, "It's working", :single},
               {:eof, 1, 16, 0, nil}
             ]
    end
  end

  describe "operator edge cases" do
    test "handles strict equality operators" do
      {:ok, tokens} = Lexer.tokenize("x === y !== z")

      assert tokens == [
               {:identifier, 1, 1, 1, "x"},
               {:strict_equal, 1, 3, 3, "==="},
               {:identifier, 1, 7, 1, "y"},
               {:strict_ne, 1, 9, 3, "!=="},
               {:identifier, 1, 13, 1, "z"},
               {:eof, 1, 14, 0, nil}
             ]
    end

    test "handles modulo operator" do
      {:ok, tokens} = Lexer.tokenize("x % y")

      assert tokens == [
               {:identifier, 1, 1, 1, "x"},
               {:modulo, 1, 3, 1, "%"},
               {:identifier, 1, 5, 1, "y"},
               {:eof, 1, 6, 0, nil}
             ]
    end
  end

  describe "whitespace handling" do
    test "handles multiple spaces" do
      {:ok, tokens} = Lexer.tokenize("x    y")

      assert tokens == [
               {:identifier, 1, 1, 1, "x"},
               {:identifier, 1, 6, 1, "y"},
               {:eof, 1, 7, 0, nil}
             ]
    end

    test "handles mixed whitespace" do
      {:ok, tokens} = Lexer.tokenize("x \t \n y")

      assert tokens == [
               {:identifier, 1, 1, 1, "x"},
               {:identifier, 2, 2, 1, "y"},
               {:eof, 2, 3, 0, nil}
             ]
    end
  end
end
