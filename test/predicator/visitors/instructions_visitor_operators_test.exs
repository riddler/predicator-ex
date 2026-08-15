defmodule Predicator.Visitors.InstructionsVisitorOperatorsTest do
  use ExUnit.Case, async: true

  alias Predicator.Visitors.InstructionsVisitor

  describe "visit/2 - arithmetic operators" do
    test "generates instructions for addition" do
      ast = {:arithmetic, :add, {:identifier, "x", nil}, {:identifier, "y", nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "x"],
               ["load", "y"],
               ["add"]
             ]
    end

    test "generates instructions for subtraction" do
      ast = {:arithmetic, :subtract, {:literal, 10, nil}, {:literal, 3, nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["lit", 10],
               ["lit", 3],
               ["subtract"]
             ]
    end

    test "generates instructions for multiplication" do
      ast = {:arithmetic, :multiply, {:identifier, "x", nil}, {:literal, 2, nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "x"],
               ["lit", 2],
               ["multiply"]
             ]
    end

    test "generates instructions for division" do
      ast = {:arithmetic, :divide, {:literal, 100, nil}, {:identifier, "divisor", nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["lit", 100],
               ["load", "divisor"],
               ["divide"]
             ]
    end

    test "generates instructions for modulo" do
      ast = {:arithmetic, :modulo, {:identifier, "n", nil}, {:literal, 5, nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "n"],
               ["lit", 5],
               ["modulo"]
             ]
    end

    test "generates instructions for nested arithmetic operations" do
      # (x + y) * z
      inner_add = {:arithmetic, :add, {:identifier, "x", nil}, {:identifier, "y", nil}, nil}
      ast = {:arithmetic, :multiply, inner_add, {:identifier, "z", nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "x"],
               ["load", "y"],
               ["add"],
               ["load", "z"],
               ["multiply"]
             ]
    end

    test "generates instructions for complex arithmetic expression" do
      # a + b * c (should be: a + (b * c) due to precedence)
      multiplication =
        {:arithmetic, :multiply, {:identifier, "b", nil}, {:identifier, "c", nil}, nil}

      ast = {:arithmetic, :add, {:identifier, "a", nil}, multiplication, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "a"],
               ["load", "b"],
               ["load", "c"],
               ["multiply"],
               ["add"]
             ]
    end
  end

  describe "visit/2 - unary operators" do
    test "generates instructions for unary minus" do
      ast = {:unary, :minus, {:identifier, "x", nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "x"],
               ["unary_minus"]
             ]
    end

    test "generates instructions for unary minus with literal" do
      ast = {:unary, :minus, {:literal, 42, nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["lit", 42],
               ["unary_minus"]
             ]
    end

    test "generates instructions for unary bang (logical NOT)" do
      ast = {:unary, :bang, {:identifier, "active", nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "active"],
               ["unary_bang"]
             ]
    end

    test "generates instructions for unary bang with boolean literal" do
      ast = {:unary, :bang, {:literal, true, nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["lit", true],
               ["unary_bang"]
             ]
    end

    test "generates instructions for nested unary expressions" do
      # !(-x)
      inner_minus = {:unary, :minus, {:identifier, "x", nil}, nil}
      ast = {:unary, :bang, inner_minus, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "x"],
               ["unary_minus"],
               ["unary_bang"]
             ]
    end

    test "generates instructions for unary with function call" do
      # !(len(name))
      function_call = {:function_call, "len", [{:identifier, "name", nil}], nil}
      ast = {:unary, :bang, function_call, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "name"],
               ["call", "len", 1],
               ["unary_bang"]
             ]
    end
  end

  describe "visit/2 - equality operators" do
    test "generates instructions for equality (==)" do
      ast = {:comparison, :eq, {:identifier, "x", nil}, {:identifier, "y", nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "x"],
               ["load", "y"],
               ["compare", "EQ"]
             ]
    end

    test "generates instructions for inequality (!=) with equality syntax" do
      ast = {:comparison, :ne, {:identifier, "status", nil}, {:literal, "active", nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "status"],
               ["lit", "active"],
               ["compare", "NE"]
             ]
    end

    test "generates instructions for complex equality expression" do
      # x + y == 10
      arithmetic = {:arithmetic, :add, {:identifier, "x", nil}, {:identifier, "y", nil}, nil}
      ast = {:comparison, :eq, arithmetic, {:literal, 10, nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "x"],
               ["load", "y"],
               ["add"],
               ["lit", 10],
               ["compare", "EQ"]
             ]
    end
  end

  describe "visit/2 - mixed operator expressions" do
    test "generates instructions for arithmetic in comparison" do
      # x + y > 10
      arithmetic = {:arithmetic, :add, {:identifier, "x", nil}, {:identifier, "y", nil}, nil}
      ast = {:comparison, :gt, arithmetic, {:literal, 10, nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "x"],
               ["load", "y"],
               ["add"],
               ["lit", 10],
               ["compare", "GT"]
             ]
    end

    test "generates instructions for unary in logical expression" do
      # !active AND !expired
      left_unary = {:unary, :bang, {:identifier, "active", nil}, nil}
      right_unary = {:unary, :bang, {:identifier, "expired", nil}, nil}
      ast = {:logical_and, left_unary, right_unary, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "active"],
               ["unary_bang"],
               ["jump_if_falsy_or_pop", 3],
               ["load", "expired"],
               ["unary_bang"]
             ]
    end

    test "generates instructions for complex nested expression" do
      # !(x + y == 10)
      arithmetic = {:arithmetic, :add, {:identifier, "x", nil}, {:identifier, "y", nil}, nil}
      equality = {:comparison, :eq, arithmetic, {:literal, 10, nil}, nil}
      ast = {:unary, :bang, equality, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "x"],
               ["load", "y"],
               ["add"],
               ["lit", 10],
               ["compare", "EQ"],
               ["unary_bang"]
             ]
    end

    test "generates instructions for arithmetic with logical operators" do
      # (a + b) > 5 AND (c - d) < 10
      left_arithmetic = {:arithmetic, :add, {:identifier, "a", nil}, {:identifier, "b", nil}, nil}
      left_comparison = {:comparison, :gt, left_arithmetic, {:literal, 5, nil}, nil}

      right_arithmetic =
        {:arithmetic, :subtract, {:identifier, "c", nil}, {:identifier, "d", nil}, nil}

      right_comparison = {:comparison, :lt, right_arithmetic, {:literal, 10, nil}, nil}

      ast = {:logical_and, left_comparison, right_comparison, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "a"],
               ["load", "b"],
               ["add"],
               ["lit", 5],
               ["compare", "GT"],
               ["jump_if_falsy_or_pop", 6],
               ["load", "c"],
               ["load", "d"],
               ["subtract"],
               ["lit", 10],
               ["compare", "LT"]
             ]
    end
  end
end
