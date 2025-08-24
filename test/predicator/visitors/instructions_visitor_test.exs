defmodule Predicator.Visitors.InstructionsVisitorTest do
  use ExUnit.Case, async: true

  alias Predicator.Visitors.InstructionsVisitor

  doctest Predicator.Visitors.InstructionsVisitor

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
      ast = {:equality, :ne, {:identifier, "status"}, {:literal, "inactive"}}
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

  describe "visit/2 - logical nodes" do
    test "generates instructions for logical AND" do
      ast = {:logical_and, {:literal, true}, {:literal, false}}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["lit", true],
               ["lit", false],
               ["and"]
             ]
    end

    test "generates instructions for logical OR" do
      ast = {:logical_or, {:identifier, "admin"}, {:literal, false}}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "admin"],
               ["lit", false],
               ["or"]
             ]
    end

    test "generates instructions for logical NOT" do
      ast = {:logical_not, {:identifier, "expired"}}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "expired"],
               ["not"]
             ]
    end

    test "generates instructions for nested logical NOT" do
      ast = {:logical_not, {:logical_not, {:literal, true}}}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["lit", true],
               ["not"],
               ["not"]
             ]
    end

    test "generates instructions for complex logical expression" do
      # (score > 85 AND age >= 18) OR admin = true
      ast = {
        :logical_or,
        {:logical_and, {:comparison, :gt, {:identifier, "score"}, {:literal, 85}},
         {:comparison, :gte, {:identifier, "age"}, {:literal, 18}}},
        {:comparison, :eq, {:identifier, "admin"}, {:literal, true}}
      }

      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               # Left side of OR: (score > 85 AND age >= 18)
               ["load", "score"],
               ["lit", 85],
               ["compare", "GT"],
               ["load", "age"],
               ["lit", 18],
               ["compare", "GTE"],
               ["and"],
               # Right side of OR: admin = true
               ["load", "admin"],
               ["lit", true],
               ["compare", "EQ"],
               # Final OR
               ["or"]
             ]
    end

    test "generates instructions for logical AND with comparisons" do
      # score > 85 AND name = "John"
      ast = {
        :logical_and,
        {:comparison, :gt, {:identifier, "score"}, {:literal, 85}},
        {:comparison, :eq, {:identifier, "name"}, {:literal, "John"}}
      }

      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "score"],
               ["lit", 85],
               ["compare", "GT"],
               ["load", "name"],
               ["lit", "John"],
               ["compare", "EQ"],
               ["and"]
             ]
    end

    test "generates instructions for logical OR with comparisons" do
      # role = "admin" OR role = "manager"
      ast = {
        :logical_or,
        {:comparison, :eq, {:identifier, "role"}, {:literal, "admin"}},
        {:comparison, :eq, {:identifier, "role"}, {:literal, "manager"}}
      }

      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "role"],
               ["lit", "admin"],
               ["compare", "EQ"],
               ["load", "role"],
               ["lit", "manager"],
               ["compare", "EQ"],
               ["or"]
             ]
    end

    test "generates instructions for NOT with comparison" do
      # NOT expired = true
      ast = {
        :logical_not,
        {:comparison, :eq, {:identifier, "expired"}, {:literal, true}}
      }

      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "expired"],
               ["lit", true],
               ["compare", "EQ"],
               ["not"]
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

    test "works with logical AND expression" do
      alias Predicator.{Lexer, Parser}

      {:ok, tokens} = Lexer.tokenize("score > 85 AND age >= 18")
      {:ok, ast} = Parser.parse(tokens)

      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "score"],
               ["lit", 85],
               ["compare", "GT"],
               ["load", "age"],
               ["lit", 18],
               ["compare", "GTE"],
               ["and"]
             ]
    end

    test "works with logical OR expression" do
      alias Predicator.{Lexer, Parser}

      {:ok, tokens} = Lexer.tokenize(~s(role = "admin" OR role = "manager"))
      {:ok, ast} = Parser.parse(tokens)

      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "role"],
               ["lit", "admin"],
               ["compare", "EQ"],
               ["load", "role"],
               ["lit", "manager"],
               ["compare", "EQ"],
               ["or"]
             ]
    end

    test "works with logical NOT expression" do
      alias Predicator.{Lexer, Parser}

      {:ok, tokens} = Lexer.tokenize("NOT expired = true")
      {:ok, ast} = Parser.parse(tokens)

      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "expired"],
               ["lit", true],
               ["compare", "EQ"],
               ["not"]
             ]
    end
  end

  describe "visit/2 - arithmetic operators" do
    test "generates instructions for addition" do
      ast = {:arithmetic, :add, {:identifier, "x"}, {:identifier, "y"}}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "x"],
               ["load", "y"],
               ["add"]
             ]
    end

    test "generates instructions for subtraction" do
      ast = {:arithmetic, :subtract, {:literal, 10}, {:literal, 3}}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["lit", 10],
               ["lit", 3],
               ["subtract"]
             ]
    end

    test "generates instructions for multiplication" do
      ast = {:arithmetic, :multiply, {:identifier, "x"}, {:literal, 2}}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "x"],
               ["lit", 2],
               ["multiply"]
             ]
    end

    test "generates instructions for division" do
      ast = {:arithmetic, :divide, {:literal, 100}, {:identifier, "divisor"}}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["lit", 100],
               ["load", "divisor"],
               ["divide"]
             ]
    end

    test "generates instructions for modulo" do
      ast = {:arithmetic, :modulo, {:identifier, "n"}, {:literal, 5}}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "n"],
               ["lit", 5],
               ["modulo"]
             ]
    end

    test "generates instructions for nested arithmetic operations" do
      # (x + y) * z
      inner_add = {:arithmetic, :add, {:identifier, "x"}, {:identifier, "y"}}
      ast = {:arithmetic, :multiply, inner_add, {:identifier, "z"}}
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
      multiplication = {:arithmetic, :multiply, {:identifier, "b"}, {:identifier, "c"}}
      ast = {:arithmetic, :add, {:identifier, "a"}, multiplication}
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
      ast = {:unary, :minus, {:identifier, "x"}}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "x"],
               ["unary_minus"]
             ]
    end

    test "generates instructions for unary minus with literal" do
      ast = {:unary, :minus, {:literal, 42}}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["lit", 42],
               ["unary_minus"]
             ]
    end

    test "generates instructions for unary bang (logical NOT)" do
      ast = {:unary, :bang, {:identifier, "active"}}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "active"],
               ["unary_bang"]
             ]
    end

    test "generates instructions for unary bang with boolean literal" do
      ast = {:unary, :bang, {:literal, true}}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["lit", true],
               ["unary_bang"]
             ]
    end

    test "generates instructions for nested unary expressions" do
      # !(-x)
      inner_minus = {:unary, :minus, {:identifier, "x"}}
      ast = {:unary, :bang, inner_minus}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "x"],
               ["unary_minus"],
               ["unary_bang"]
             ]
    end

    test "generates instructions for unary with function call" do
      # !(len(name))
      function_call = {:function_call, "len", [{:identifier, "name"}]}
      ast = {:unary, :bang, function_call}
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
      ast = {:equality, :equal_equal, {:identifier, "x"}, {:identifier, "y"}}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "x"],
               ["load", "y"],
               ["compare", "EQ"]
             ]
    end

    test "generates instructions for inequality (!=) with equality syntax" do
      ast = {:equality, :ne, {:identifier, "status"}, {:literal, "active"}}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "status"],
               ["lit", "active"],
               ["compare", "NE"]
             ]
    end

    test "generates instructions for complex equality expression" do
      # x + y == 10
      arithmetic = {:arithmetic, :add, {:identifier, "x"}, {:identifier, "y"}}
      ast = {:equality, :equal_equal, arithmetic, {:literal, 10}}
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
      arithmetic = {:arithmetic, :add, {:identifier, "x"}, {:identifier, "y"}}
      ast = {:comparison, :gt, arithmetic, {:literal, 10}}
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
      left_unary = {:unary, :bang, {:identifier, "active"}}
      right_unary = {:unary, :bang, {:identifier, "expired"}}
      ast = {:logical_and, left_unary, right_unary}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "active"],
               ["unary_bang"],
               ["load", "expired"],
               ["unary_bang"],
               ["and"]
             ]
    end

    test "generates instructions for complex nested expression" do
      # !(x + y == 10)
      arithmetic = {:arithmetic, :add, {:identifier, "x"}, {:identifier, "y"}}
      equality = {:equality, :equal_equal, arithmetic, {:literal, 10}}
      ast = {:unary, :bang, equality}
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
      left_arithmetic = {:arithmetic, :add, {:identifier, "a"}, {:identifier, "b"}}
      left_comparison = {:comparison, :gt, left_arithmetic, {:literal, 5}}
      
      right_arithmetic = {:arithmetic, :subtract, {:identifier, "c"}, {:identifier, "d"}}
      right_comparison = {:comparison, :lt, right_arithmetic, {:literal, 10}}
      
      ast = {:logical_and, left_comparison, right_comparison}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "a"],
               ["load", "b"],
               ["add"],
               ["lit", 5],
               ["compare", "GT"],
               ["load", "c"],
               ["load", "d"],
               ["subtract"],
               ["lit", 10],
               ["compare", "LT"],
               ["and"]
             ]
    end
  end
end
