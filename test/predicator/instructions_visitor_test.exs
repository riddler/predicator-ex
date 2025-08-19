defmodule Predicator.InstructionsVisitorTest do
  use ExUnit.Case, async: true

  alias Predicator.InstructionsVisitor

  doctest Predicator.InstructionsVisitor

  describe "visit/2 - literal nodes" do
    test "generates lit instruction for integer literal" do
      ast = {:literal, 42}
      result = InstructionsVisitor.visit(ast, [])
      
      assert result == [["lit", 42]]
    end

    test "generates lit instruction for string literal" do
      ast = {:literal, "hello"}
      result = InstructionsVisitor.visit(ast, [])
      
      assert result == [["lit", "hello"]]
    end

    test "generates lit instruction for boolean literal" do
      ast = {:literal, true}
      result = InstructionsVisitor.visit(ast, [])
      
      assert result == [["lit", true]]
    end
  end

  describe "visit/2 - identifier nodes" do
    test "generates load instruction for identifier" do
      ast = {:identifier, "score"}
      result = InstructionsVisitor.visit(ast, [])
      
      assert result == [["load", "score"]]
    end

    test "generates load instruction for underscore identifier" do
      ast = {:identifier, "user_age"}
      result = InstructionsVisitor.visit(ast, [])
      
      assert result == [["load", "user_age"]]
    end
  end

  describe "visit/2 - comparison nodes" do
    test "generates instructions for greater than comparison" do
      ast = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      result = InstructionsVisitor.visit(ast, [])
      
      assert result == [
        ["load", "score"],
        ["lit", 85],
        ["compare", "GT"]
      ]
    end

    test "generates instructions for less than comparison" do
      ast = {:comparison, :lt, {:identifier, "age"}, {:literal, 18}}
      result = InstructionsVisitor.visit(ast, [])
      
      assert result == [
        ["load", "age"],
        ["lit", 18],
        ["compare", "LT"]
      ]
    end

    test "generates instructions for greater than or equal comparison" do
      ast = {:comparison, :gte, {:identifier, "score"}, {:literal, 85}}
      result = InstructionsVisitor.visit(ast, [])
      
      assert result == [
        ["load", "score"],
        ["lit", 85],
        ["compare", "GTE"]
      ]
    end

    test "generates instructions for less than or equal comparison" do
      ast = {:comparison, :lte, {:identifier, "age"}, {:literal, 65}}
      result = InstructionsVisitor.visit(ast, [])
      
      assert result == [
        ["load", "age"],
        ["lit", 65],
        ["compare", "LTE"]
      ]
    end

    test "generates instructions for equality comparison" do
      ast = {:comparison, :eq, {:identifier, "name"}, {:literal, "John"}}
      result = InstructionsVisitor.visit(ast, [])
      
      assert result == [
        ["load", "name"],
        ["lit", "John"],
        ["compare", "EQ"]
      ]
    end

    test "generates instructions for not equal comparison" do
      ast = {:comparison, :ne, {:identifier, "status"}, {:literal, "inactive"}}
      result = InstructionsVisitor.visit(ast, [])
      
      assert result == [
        ["load", "status"],
        ["lit", "inactive"],
        ["compare", "NE"]
      ]
    end

    test "generates instructions with literal-to-literal comparison" do
      ast = {:comparison, :gt, {:literal, 10}, {:literal, 5}}
      result = InstructionsVisitor.visit(ast, [])
      
      assert result == [
        ["lit", 10],
        ["lit", 5],
        ["compare", "GT"]
      ]
    end

    test "generates instructions with identifier-to-identifier comparison" do
      ast = {:comparison, :eq, {:identifier, "score"}, {:identifier, "threshold"}}
      result = InstructionsVisitor.visit(ast, [])
      
      assert result == [
        ["load", "score"],
        ["load", "threshold"],
        ["compare", "EQ"]
      ]
    end
  end

  describe "visit/2 - integration with full pipeline" do
    test "works with lexer and parser output" do
      alias Predicator.{Lexer, Parser}
      
      {:ok, tokens} = Lexer.tokenize("score > 85")
      {:ok, ast} = Parser.parse(tokens)
      
      result = InstructionsVisitor.visit(ast, [])
      
      assert result == [
        ["load", "score"],
        ["lit", 85],
        ["compare", "GT"]
      ]
    end

    test "works with complex parenthesized expression" do
      alias Predicator.{Lexer, Parser}
      
      {:ok, tokens} = Lexer.tokenize("(age >= 18)")
      {:ok, ast} = Parser.parse(tokens)
      
      result = InstructionsVisitor.visit(ast, [])
      
      assert result == [
        ["load", "age"],
        ["lit", 18],
        ["compare", "GTE"]
      ]
    end
  end
end