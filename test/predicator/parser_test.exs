defmodule Predicator.ParserTest do
  use ExUnit.Case, async: true

  import Predicator.ParseShape

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

    test "parses the undefined literal" do
      {:ok, tokens} = Lexer.tokenize("undefined")
      assert parse_positionless(tokens) == {:ok, {:literal, :undefined}}
    end

    test "parses the undefined literal with its position" do
      {:ok, tokens} = Lexer.tokenize("undefined")
      assert Predicator.Parser.parse(tokens) == {:ok, {:literal, :undefined, {1, 1}}}
    end

    test "parses undefined inside a list literal" do
      {:ok, tokens} = Lexer.tokenize("[undefined, 1]")

      assert parse_positionless(tokens) ==
               {:ok, {:list, [{:literal, :undefined}, {:literal, 1}]}}
    end

    test "parses undefined as an object value" do
      {:ok, tokens} = Lexer.tokenize("{k: undefined}")

      assert parse_positionless(tokens) ==
               {:ok, {:object, [{{:object_key, "k", :identifier}, {:literal, :undefined}}]}}
    end

    test "parses the null literal" do
      {:ok, tokens} = Lexer.tokenize("null")
      assert parse_positionless(tokens) == {:ok, {:literal, nil}}
    end

    test "parses the null literal with its position" do
      {:ok, tokens} = Lexer.tokenize("null")
      assert Predicator.Parser.parse(tokens) == {:ok, {:literal, nil, {1, 1}}}
    end

    test "parses null inside a list literal" do
      {:ok, tokens} = Lexer.tokenize("[null, 1]")

      assert parse_positionless(tokens) ==
               {:ok, {:list, [{:literal, nil}, {:literal, 1}]}}
    end

    test "parses null as an object value" do
      {:ok, tokens} = Lexer.tokenize("{k: null}")

      assert parse_positionless(tokens) ==
               {:ok, {:object, [{{:object_key, "k", :identifier}, {:literal, nil}}]}}
    end

    test "parses identifier" do
      {:ok, tokens} = Lexer.tokenize("limit")
      assert parse_positionless(tokens) == {:ok, {:identifier, "limit"}}
    end

    test "parses parenthesized expression" do
      {:ok, tokens} = Lexer.tokenize("(42)")
      assert parse_positionless(tokens) == {:ok, {:literal, 42}}
    end

    test "parses nested parentheses" do
      {:ok, tokens} = Lexer.tokenize("((limit))")
      assert parse_positionless(tokens) == {:ok, {:identifier, "limit"}}
    end
  end

  describe "parse/1 - undefined as an operand" do
    test "parses undefined as the right operand of ===" do
      {:ok, tokens} = Lexer.tokenize("x === undefined")

      expected = {:comparison, :strict_eq, {:identifier, "x"}, {:literal, :undefined}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses undefined as the right operand of !==" do
      {:ok, tokens} = Lexer.tokenize("x !== undefined")

      expected = {:comparison, :strict_ne, {:identifier, "x"}, {:literal, :undefined}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses undefined as the right operand of ==" do
      {:ok, tokens} = Lexer.tokenize("x == undefined")

      expected = {:comparison, :equal_equal, {:identifier, "x"}, {:literal, :undefined}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses undefined negated with !" do
      {:ok, tokens} = Lexer.tokenize("!undefined")

      assert parse_positionless(tokens) == {:ok, {:logical_not, {:literal, :undefined}}}
    end

    test "parses undefined cast with ::string" do
      {:ok, tokens} = Lexer.tokenize("undefined::string")

      assert parse_positionless(tokens) == {:ok, {:cast, {:literal, :undefined}, "string"}}
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

  describe "parse/1 - complex expressions" do
    test "handles whitespace correctly" do
      {:ok, tokens} = Lexer.tokenize("  limit   >    85  ")

      expected = {:comparison, :gt, {:identifier, "limit"}, {:literal, 85}}
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
        {:string, 1, 6, 7, "hello", :double, {1, 13}},
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
      assert {:error, "Expected ']' but found number '2'", 1, 4, _span} = result
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
              1, 1, _span} = result
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
      {:ok, tokens} = Lexer.tokenize("max(limit1, limit2)")

      assert parse_positionless(tokens) ==
               {:ok, {:function_call, "max", [{:identifier, "limit1"}, {:identifier, "limit2"}]}}
    end

    test "parses function call with complex arguments" do
      {:ok, tokens} = Lexer.tokenize("max(limit + bonus, 100)")

      assert parse_positionless(tokens) ==
               {:ok,
                {:function_call, "max",
                 [
                   {:arithmetic, :add, {:identifier, "limit"}, {:identifier, "bonus"}},
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

      assert {:error, "Expected '(' after function name but found number '42'", 1, 4, _span} =
               result
    end

    test "returns error when function name at end of input" do
      tokens = [
        {:function_name, 1, 1, 3, "len"},
        {:eof, 1, 4, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:error, "Expected '(' after function name but found end of input", 1, 4, _span} =
               result
    end

    test "returns error for unterminated function call" do
      tokens = [
        {:function_name, 1, 1, 3, "len"},
        {:lparen, 1, 4, 1, "("},
        {:identifier, 1, 5, 4, "name"},
        {:eof, 1, 9, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:error, "Expected ')' but found end of input", 1, 9, _span} = result
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
      assert {:error, "Expected ')' but found ']'", 1, 9, _span} = result
    end
  end
end
