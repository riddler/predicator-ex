defmodule Predicator.ParserOperatorsTest do
  use ExUnit.Case, async: true

  import Predicator.ParseShape

  alias Predicator.Lexer

  describe "parse/1 - comparison expressions" do
    test "parses greater than comparison" do
      {:ok, tokens} = Lexer.tokenize("score > 85")

      expected = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses less than comparison" do
      {:ok, tokens} = Lexer.tokenize("age < 18")

      expected = {:comparison, :lt, {:identifier, "age"}, {:literal, 18}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses greater than or equal comparison" do
      {:ok, tokens} = Lexer.tokenize("score >= 85")

      expected = {:comparison, :gte, {:identifier, "score"}, {:literal, 85}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses less than or equal comparison" do
      {:ok, tokens} = Lexer.tokenize("age <= 65")

      expected = {:comparison, :lte, {:identifier, "age"}, {:literal, 65}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses equality comparison" do
      {:ok, tokens} = Lexer.tokenize("name == \"John\"")

      expected =
        {:comparison, :equal_equal, {:identifier, "name"}, {:string_literal, "John", :double}}

      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses equality comparison with single quotes" do
      {:ok, tokens} = Lexer.tokenize("name == 'John'")

      expected =
        {:comparison, :equal_equal, {:identifier, "name"}, {:string_literal, "John", :single}}

      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses not equal comparison" do
      {:ok, tokens} = Lexer.tokenize("status != \"inactive\"")

      expected =
        {:comparison, :ne, {:identifier, "status"}, {:string_literal, "inactive", :double}}

      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses number to number comparison" do
      {:ok, tokens} = Lexer.tokenize("10 > 5")

      expected = {:comparison, :gt, {:literal, 10}, {:literal, 5}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses boolean comparison" do
      {:ok, tokens} = Lexer.tokenize("active == true")

      expected = {:comparison, :equal_equal, {:identifier, "active"}, {:literal, true}}
      assert parse_positionless(tokens) == {:ok, expected}
    end
  end

  describe "parse/1 - parenthesized comparisons" do
    test "parses comparison in parentheses" do
      {:ok, tokens} = Lexer.tokenize("(score > 85)")

      expected = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses parenthesized left operand" do
      {:ok, tokens} = Lexer.tokenize("(score) > 85")

      expected = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses parenthesized right operand" do
      {:ok, tokens} = Lexer.tokenize("score > (85)")

      expected = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      assert parse_positionless(tokens) == {:ok, expected}
    end

    test "parses both operands parenthesized" do
      {:ok, tokens} = Lexer.tokenize("(score) > (85)")

      expected = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      assert parse_positionless(tokens) == {:ok, expected}
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

      result = parse_positionless(tokens)

      assert {:ok,
              {:logical_and, {:comparison, :gt, {:identifier, "score"}, {:literal, 85}},
               {:comparison, :gte, {:identifier, "age"}, {:literal, 18}}}} = result
    end

    test "parses simple OR expression" do
      tokens = [
        {:identifier, 1, 1, 4, "role"},
        {:equal_equal, 1, 6, 2, "=="},
        {:string, 1, 9, 7, "admin", :double, {1, 16}},
        {:or_op, 1, 17, 2, "OR"},
        {:identifier, 1, 20, 4, "role"},
        {:equal_equal, 1, 25, 2, "=="},
        {:string, 1, 28, 9, "manager", :double, {1, 37}},
        {:eof, 1, 38, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:ok,
              {:logical_or,
               {:comparison, :equal_equal, {:identifier, "role"},
                {:string_literal, "admin", :double}},
               {:comparison, :equal_equal, {:identifier, "role"},
                {:string_literal, "manager", :double}}}} =
               result
    end

    test "parses simple NOT expression" do
      tokens = [
        {:not_op, 1, 1, 3, "NOT"},
        {:identifier, 1, 5, 7, "expired"},
        {:equal_equal, 1, 13, 2, "=="},
        {:boolean, 1, 16, 4, true},
        {:eof, 1, 20, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:ok,
              {:logical_not,
               {:comparison, :equal_equal, {:identifier, "expired"}, {:literal, true}}}} =
               result
    end

    test "parses nested NOT expression" do
      tokens = [
        {:not_op, 1, 1, 3, "NOT"},
        {:not_op, 1, 5, 3, "NOT"},
        {:boolean, 1, 9, 4, true},
        {:eof, 1, 13, 0, nil}
      ]

      result = parse_positionless(tokens)

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

      result = parse_positionless(tokens)

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

      result = parse_positionless(tokens)

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

      result = parse_positionless(tokens)

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

      result = parse_positionless(tokens)

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

      result = parse_positionless(tokens)

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

      result = parse_positionless(tokens)

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

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input",
              1, 9, _span} = result
    end

    test "handles error when OR missing right operand" do
      tokens = [
        {:boolean, 1, 1, 4, true},
        {:or_op, 1, 6, 2, "OR"},
        {:eof, 1, 8, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input",
              1, 8, _span} = result
    end

    test "handles error when NOT missing operand" do
      tokens = [
        {:not_op, 1, 1, 3, "NOT"},
        {:eof, 1, 4, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input",
              1, 4, _span} = result
    end

    test "complex mixed expression with comparisons and logical operators" do
      # score > 85 AND age >= 18 OR admin == true
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
        {:equal_equal, 1, 35, 2, "=="},
        {:boolean, 1, 38, 4, true},
        {:eof, 1, 42, 0, nil}
      ]

      result = parse_positionless(tokens)

      assert {:ok,
              {:logical_or,
               {:logical_and, {:comparison, :gt, {:identifier, "score"}, {:literal, 85}},
                {:comparison, :gte, {:identifier, "age"}, {:literal, 18}}},
               {:comparison, :equal_equal, {:identifier, "admin"}, {:literal, true}}}} = result
    end
  end

  describe "parse/1 - operator precedence edge cases" do
    test "verifies complex precedence with all operators" do
      # Test expression: a + b * c / d - e % f > g && h || i
      {:ok, tokens} = Lexer.tokenize("a + b * c / d - e % f > g && h || i")
      result = parse_positionless(tokens)

      # Expected precedence:
      # 1. *, /, % (left-to-right)
      # 2. +, - (left-to-right)
      # 3. > (comparison)
      # 4. && (logical and)
      # 5. || (logical or)

      # ((a + ((b * c) / d)) - (e % f)) > g && h || i
      expected_ast =
        {:logical_or,
         {:logical_and,
          {:comparison, :gt,
           {:arithmetic, :subtract,
            {:arithmetic, :add, {:identifier, "a"},
             {:arithmetic, :divide,
              {:arithmetic, :multiply, {:identifier, "b"}, {:identifier, "c"}},
              {:identifier, "d"}}},
            {:arithmetic, :modulo, {:identifier, "e"}, {:identifier, "f"}}}, {:identifier, "g"}},
          {:identifier, "h"}}, {:identifier, "i"}}

      assert {:ok, ^expected_ast} = result
    end

    test "verifies equality operator precedence" do
      {:ok, tokens} = Lexer.tokenize("a + b == c * d")
      result = parse_positionless(tokens)

      expected_ast =
        {:comparison, :equal_equal, {:arithmetic, :add, {:identifier, "a"}, {:identifier, "b"}},
         {:arithmetic, :multiply, {:identifier, "c"}, {:identifier, "d"}}}

      assert {:ok, ^expected_ast} = result
    end

    test "verifies unary operator precedence with arithmetic" do
      {:ok, tokens} = Lexer.tokenize("-a + b")
      result = parse_positionless(tokens)

      expected_ast = {:arithmetic, :add, {:unary, :minus, {:identifier, "a"}}, {:identifier, "b"}}

      assert {:ok, ^expected_ast} = result
    end
  end
end
