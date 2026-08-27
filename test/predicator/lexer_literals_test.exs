defmodule Predicator.LexerLiteralsTest do
  use ExUnit.Case, async: true

  alias Predicator.Lexer

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
               Lexer.tokenize("limit > #")
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
end
