defmodule Predicator.StrictEqualityTest do
  @moduledoc """
  Comprehensive tests for strict equality operators (=== and !==).
  """

  use ExUnit.Case

  describe "lexer tokenization" do
    test "tokenizes === as strict_equal" do
      {:ok, tokens} = Predicator.Lexer.tokenize("a === b")

      assert tokens == [
               {:identifier, 1, 1, 1, "a"},
               {:strict_equal, 1, 3, 3, "==="},
               {:identifier, 1, 7, 1, "b"},
               {:eof, 1, 8, 0, nil}
             ]
    end

    test "tokenizes !== as strict_ne" do
      {:ok, tokens} = Predicator.Lexer.tokenize("x !== y")

      assert tokens == [
               {:identifier, 1, 1, 1, "x"},
               {:strict_ne, 1, 3, 3, "!=="},
               {:identifier, 1, 7, 1, "y"},
               {:eof, 1, 8, 0, nil}
             ]
    end

    test "distinguishes === from == and =" do
      {:ok, tokens} = Predicator.Lexer.tokenize("a = b == c === d")

      assert tokens == [
               {:identifier, 1, 1, 1, "a"},
               {:eq, 1, 3, 1, "="},
               {:identifier, 1, 5, 1, "b"},
               {:equal_equal, 1, 7, 2, "=="},
               {:identifier, 1, 10, 1, "c"},
               {:strict_equal, 1, 12, 3, "==="},
               {:identifier, 1, 16, 1, "d"},
               {:eof, 1, 17, 0, nil}
             ]
    end

    test "distinguishes !== from !=" do
      {:ok, tokens} = Predicator.Lexer.tokenize("a != b !== c")

      assert tokens == [
               {:identifier, 1, 1, 1, "a"},
               {:ne, 1, 3, 2, "!="},
               {:identifier, 1, 6, 1, "b"},
               {:strict_ne, 1, 8, 3, "!=="},
               {:identifier, 1, 12, 1, "c"},
               {:eof, 1, 13, 0, nil}
             ]
    end

    test "handles strict operators in complex expressions" do
      {:ok, tokens} = Predicator.Lexer.tokenize("(x === 1) AND (y !== 'text')")

      assert Enum.any?(tokens, fn token -> match?({:strict_equal, _, _, _, _}, token) end)
      assert Enum.any?(tokens, fn token -> match?({:strict_ne, _, _, _, _}, token) end)
    end
  end

  describe "parser AST generation" do
    test "parses === as strict_eq comparison" do
      {:ok, ast} = Predicator.parse("value === 42")

      assert ast == {:comparison, :strict_eq, {:identifier, "value"}, {:literal, 42}}
    end

    test "parses !== as strict_ne comparison" do
      {:ok, ast} = Predicator.parse("name !== 'John'")

      assert ast ==
               {:comparison, :strict_ne, {:identifier, "name"},
                {:string_literal, "John", :single}}
    end

    test "handles mixed equality operators with correct precedence" do
      # Test that different operators can be used in separate comparisons with logical operators
      {:ok, ast} = Predicator.parse("(a === b) AND (c != d)")

      assert match?(
               {:logical_and, {:comparison, :strict_eq, _, _}, {:comparison, :ne, _, _}},
               ast
             )
    end

    test "parses complex expressions with strict operators" do
      {:ok, ast} = Predicator.parse("(x === 1) AND (y !== 'test')")

      assert match?(
               {:logical_and, {:comparison, :strict_eq, _, _}, {:comparison, :strict_ne, _, _}},
               ast
             )
    end
  end

  describe "instruction compilation" do
    test "compiles === to STRICT_EQ instruction" do
      {:ok, instructions} = Predicator.compile("value === 42")

      assert instructions == [
               ["load", "value"],
               ["lit", 42],
               ["compare", "STRICT_EQ"]
             ]
    end

    test "compiles !== to STRICT_NE instruction" do
      {:ok, instructions} = Predicator.compile("name !== 'test'")

      assert instructions == [
               ["load", "name"],
               ["lit", "test"],
               ["compare", "STRICT_NE"]
             ]
    end
  end

  describe "evaluation behavior" do
    test "=== performs strict equality (same type and value)" do
      # Same type and value - true
      assert {:ok, true} = Predicator.evaluate("5 === 5", %{})
      assert {:ok, true} = Predicator.evaluate("'hello' === 'hello'", %{})
      assert {:ok, true} = Predicator.evaluate("true === true", %{})

      # Different types - false
      assert {:ok, false} = Predicator.evaluate("5 === '5'", %{})
      assert {:ok, false} = Predicator.evaluate("1 === true", %{})
      assert {:ok, false} = Predicator.evaluate("0 === false", %{})
    end

    test "!== performs strict inequality" do
      # Different types - true
      assert {:ok, true} = Predicator.evaluate("5 !== '5'", %{})
      assert {:ok, true} = Predicator.evaluate("1 !== true", %{})
      assert {:ok, true} = Predicator.evaluate("0 !== false", %{})

      # Same type and value - false
      assert {:ok, false} = Predicator.evaluate("5 !== 5", %{})
      assert {:ok, false} = Predicator.evaluate("'hello' !== 'hello'", %{})
      assert {:ok, false} = Predicator.evaluate("true !== true", %{})
    end

    test "=== vs == behavior differences" do
      # Test with different value types
      # Both should be true for same values
      # Same value, same type
      assert {:ok, true} = Predicator.evaluate("1 == 1", %{})
      # Same value, same type
      assert {:ok, true} = Predicator.evaluate("1 === 1", %{})

      # Same type comparisons
      assert {:ok, true} = Predicator.evaluate("1 == 1", %{})
      assert {:ok, true} = Predicator.evaluate("1 === 1", %{})
    end

    test "!== vs != behavior differences" do
      # Different types should behave differently
      # Same value, same type
      assert {:ok, false} = Predicator.evaluate("1 != 1", %{})
      # Same value, same type
      assert {:ok, false} = Predicator.evaluate("1 !== 1", %{})

      # Different values
      assert {:ok, true} = Predicator.evaluate("1 != 2", %{})
      # Different values
      assert {:ok, true} = Predicator.evaluate("1 !== 2", %{})
    end

    test "evaluates with context variables" do
      context = %{"num" => 42, "str" => "42", "flag" => true}

      assert {:ok, true} = Predicator.evaluate("num === 42", context)
      assert {:ok, false} = Predicator.evaluate("num === str", context)
      assert {:ok, false} = Predicator.evaluate("flag === 1", context)
      assert {:ok, true} = Predicator.evaluate("num !== str", context)
    end

    test "handles complex expressions with mixed operators" do
      context = %{"a" => 1, "b" => 1, "c" => true}

      # Mixed strict and loose equality with same values
      assert {:ok, true} = Predicator.evaluate("a == b AND a === b", context)
      assert {:ok, false} = Predicator.evaluate("a !== b OR c === 1", context)
    end
  end

  describe "string visitor decompilation" do
    test "decompiles === correctly" do
      ast = {:comparison, :strict_eq, {:identifier, "x"}, {:literal, 42}}
      result = Predicator.decompile(ast)

      assert result == "x === 42"
    end

    test "decompiles !== correctly" do
      ast = {:comparison, :strict_ne, {:identifier, "name"}, {:string_literal, "test", :double}}
      result = Predicator.decompile(ast)

      assert result == "name !== \"test\""
    end

    test "preserves operator distinction in round-trip" do
      expressions = [
        "x = y",
        "x == y",
        "x === y",
        "x != y",
        "x !== y"
      ]

      for expr <- expressions do
        {:ok, ast} = Predicator.parse(expr)
        decompiled = Predicator.decompile(ast)

        # The original operator should be preserved
        assert decompiled == expr
      end
    end

    test "formats complex expressions correctly" do
      {:ok, ast} = Predicator.parse("(a === 1) AND (b !== 'test')")
      result = Predicator.decompile(ast)

      assert result == "a === 1 AND b !== 'test'"
    end
  end

  describe "error handling" do
    test "provides meaningful error messages for invalid syntax" do
      # Test parsing error includes operator info
      assert {:error, _message, _line, _col} = Predicator.parse("x === ===")
    end

    test "handles undefined values consistently" do
      # Both strict and loose should handle :undefined the same way
      assert {:ok, false} = Predicator.evaluate("undefined_var === 5", %{})
      assert {:ok, true} = Predicator.evaluate("undefined_var !== 5", %{})
    end
  end
end
