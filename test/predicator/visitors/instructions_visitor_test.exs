defmodule Predicator.Visitors.InstructionsVisitorTest do
  use ExUnit.Case, async: true

  alias Predicator.Visitors.InstructionsVisitor

  doctest Predicator.Visitors.InstructionsVisitor

  describe "visit/2 - literal nodes" do
    test "generates lit instruction for integer literal" do
      ast = {:literal, 42, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["lit", 42]]
    end

    test "generates lit instruction for string literal" do
      ast = {:literal, "hello", nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["lit", "hello"]]
    end

    test "generates lit instruction for boolean literal" do
      ast = {:literal, true, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["lit", true]]
    end
  end

  describe "visit/2 - identifier nodes" do
    test "generates load instruction for identifier" do
      ast = {:identifier, "score", nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["load", "score"]]
    end

    test "generates load instruction for underscore identifier" do
      ast = {:identifier, "user_age", nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["load", "user_age"]]
    end
  end

  describe "visit/2 - comparison nodes" do
    test "generates instructions for greater than comparison" do
      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "score"],
               ["lit", 85],
               ["compare", "GT"]
             ]
    end

    test "generates instructions for less than comparison" do
      ast = {:comparison, :lt, {:identifier, "age", nil}, {:literal, 18, nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "age"],
               ["lit", 18],
               ["compare", "LT"]
             ]
    end

    test "generates instructions for greater than or equal comparison" do
      ast = {:comparison, :gte, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "score"],
               ["lit", 85],
               ["compare", "GTE"]
             ]
    end

    test "generates instructions for less than or equal comparison" do
      ast = {:comparison, :lte, {:identifier, "age", nil}, {:literal, 65, nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "age"],
               ["lit", 65],
               ["compare", "LTE"]
             ]
    end

    test "generates instructions for equality comparison" do
      ast = {:comparison, :eq, {:identifier, "name", nil}, {:literal, "John", nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "name"],
               ["lit", "John"],
               ["compare", "EQ"]
             ]
    end

    test "generates instructions for not equal comparison" do
      ast = {:comparison, :ne, {:identifier, "status", nil}, {:literal, "inactive", nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "status"],
               ["lit", "inactive"],
               ["compare", "NE"]
             ]
    end

    test "generates instructions with literal-to-literal comparison" do
      ast = {:comparison, :gt, {:literal, 10, nil}, {:literal, 5, nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["lit", 10],
               ["lit", 5],
               ["compare", "GT"]
             ]
    end

    test "generates instructions with identifier-to-identifier comparison" do
      ast = {:comparison, :eq, {:identifier, "score", nil}, {:identifier, "threshold", nil}, nil}
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
      ast = {:logical_and, {:literal, true, nil}, {:literal, false, nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["lit", true],
               ["jump_if_falsy_or_pop", 2],
               ["lit", false]
             ]
    end

    test "generates instructions for logical OR" do
      ast = {:logical_or, {:identifier, "admin", nil}, {:literal, false, nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "admin"],
               ["jump_if_true_or_pop", 2],
               ["lit", false]
             ]
    end

    test "generates instructions for logical NOT" do
      ast = {:logical_not, {:identifier, "expired", nil}, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "expired"],
               ["not"]
             ]
    end

    test "generates instructions for nested logical NOT" do
      ast = {:logical_not, {:logical_not, {:literal, true, nil}, nil}, nil}
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
        {:logical_and, {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil},
         {:comparison, :gte, {:identifier, "age", nil}, {:literal, 18, nil}, nil}, nil},
        {:comparison, :eq, {:identifier, "admin", nil}, {:literal, true, nil}, nil},
        nil
      }

      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               # Left side of OR: (score > 85 AND age >= 18)
               ["load", "score"],
               ["lit", 85],
               ["compare", "GT"],
               ["jump_if_falsy_or_pop", 4],
               ["load", "age"],
               ["lit", 18],
               ["compare", "GTE"],
               # Final OR
               ["jump_if_true_or_pop", 4],
               # Right side of OR: admin = true
               ["load", "admin"],
               ["lit", true],
               ["compare", "EQ"]
             ]
    end

    test "generates instructions for logical AND with comparisons" do
      # score > 85 AND name = "John"
      ast = {
        :logical_and,
        {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil},
        {:comparison, :eq, {:identifier, "name", nil}, {:literal, "John", nil}, nil},
        nil
      }

      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "score"],
               ["lit", 85],
               ["compare", "GT"],
               ["jump_if_falsy_or_pop", 4],
               ["load", "name"],
               ["lit", "John"],
               ["compare", "EQ"]
             ]
    end

    test "generates instructions for logical OR with comparisons" do
      # role = "admin" OR role = "manager"
      ast = {
        :logical_or,
        {:comparison, :eq, {:identifier, "role", nil}, {:literal, "admin", nil}, nil},
        {:comparison, :eq, {:identifier, "role", nil}, {:literal, "manager", nil}, nil},
        nil
      }

      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "role"],
               ["lit", "admin"],
               ["compare", "EQ"],
               ["jump_if_true_or_pop", 4],
               ["load", "role"],
               ["lit", "manager"],
               ["compare", "EQ"]
             ]
    end

    test "generates instructions for NOT with comparison" do
      # NOT expired = true
      ast = {
        :logical_not,
        {:comparison, :eq, {:identifier, "expired", nil}, {:literal, true, nil}, nil},
        nil
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
      alias Predicator.Lexer

      {:ok, tokens} = Lexer.tokenize("score > 85")
      {:ok, ast} = Predicator.Parser.parse(tokens)

      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "score"],
               ["lit", 85],
               ["compare", "GT"]
             ]
    end

    test "works with complex parenthesized expression" do
      alias Predicator.Lexer

      {:ok, tokens} = Lexer.tokenize("(age >= 18)")
      {:ok, ast} = Predicator.Parser.parse(tokens)

      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "age"],
               ["lit", 18],
               ["compare", "GTE"]
             ]
    end

    test "works with logical AND expression" do
      alias Predicator.Lexer

      {:ok, tokens} = Lexer.tokenize("score > 85 AND age >= 18")
      {:ok, ast} = Predicator.Parser.parse(tokens)

      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "score"],
               ["lit", 85],
               ["compare", "GT"],
               ["jump_if_falsy_or_pop", 4],
               ["load", "age"],
               ["lit", 18],
               ["compare", "GTE"]
             ]
    end

    test "works with logical OR expression" do
      alias Predicator.Lexer

      {:ok, tokens} = Lexer.tokenize(~s(role == "admin" OR role == "manager"))
      {:ok, ast} = Predicator.Parser.parse(tokens)

      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "role"],
               ["lit", "admin"],
               ["compare", "EQ"],
               ["jump_if_true_or_pop", 4],
               ["load", "role"],
               ["lit", "manager"],
               ["compare", "EQ"]
             ]
    end

    test "works with logical NOT expression" do
      alias Predicator.Lexer

      {:ok, tokens} = Lexer.tokenize("NOT expired == true")
      {:ok, ast} = Predicator.Parser.parse(tokens)

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

  describe "visit/2 - duration nodes" do
    test "generates duration instruction for simple duration" do
      ast = {:duration, [{5, "d"}], nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["duration", [[5, "d"]]]]
    end

    test "generates duration instruction for multiple units" do
      ast = {:duration, [{1, "d"}, {8, "h"}, {30, "m"}], nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["duration", [[1, "d"], [8, "h"], [30, "m"]]]]
    end

    test "generates duration instruction for all unit types" do
      ast =
        {:duration, [{2, "y"}, {3, "mo"}, {4, "w"}, {5, "d"}, {6, "h"}, {7, "m"}, {8, "s"}], nil}

      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               [
                 "duration",
                 [[2, "y"], [3, "mo"], [4, "w"], [5, "d"], [6, "h"], [7, "m"], [8, "s"]]
               ]
             ]
    end

    test "generates duration instruction for long unit names" do
      ast = {:duration, [{1, "year"}, {2, "months"}, {3, "weeks"}], nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["duration", [[1, "year"], [2, "months"], [3, "weeks"]]]]
    end

    test "generates duration instruction for zero values" do
      ast = {:duration, [{0, "d"}, {0, "h"}], nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["duration", [[0, "d"], [0, "h"]]]]
    end

    test "generates duration instruction for large values" do
      ast = {:duration, [{999, "y"}, {365, "d"}], nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["duration", [[999, "y"], [365, "d"]]]]
    end
  end

  describe "visit/2 - relative date nodes" do
    test "generates instructions for relative date with ago" do
      duration_ast = {:duration, [{1, "d"}, {8, "h"}], nil}
      ast = {:relative_date, duration_ast, :ago, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["duration", [[1, "d"], [8, "h"]]], ["relative_date", "ago"]]
    end

    test "generates instructions for relative date with future" do
      duration_ast = {:duration, [{2, "h"}, {30, "m"}], nil}
      ast = {:relative_date, duration_ast, :future, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["duration", [[2, "h"], [30, "m"]]], ["relative_date", "future"]]
    end

    test "generates instructions for relative date with next" do
      duration_ast = {:duration, [{1, "w"}], nil}
      ast = {:relative_date, duration_ast, :next, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["duration", [[1, "w"]]], ["relative_date", "next"]]
    end

    test "generates instructions for relative date with last" do
      duration_ast = {:duration, [{6, "mo"}], nil}
      ast = {:relative_date, duration_ast, :last, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["duration", [[6, "mo"]]], ["relative_date", "last"]]
    end

    test "generates instructions for complex relative date" do
      duration_ast = {:duration, [{1, "y"}, {2, "mo"}, {3, "d"}], nil}
      ast = {:relative_date, duration_ast, :ago, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["duration", [[1, "y"], [2, "mo"], [3, "d"]]], ["relative_date", "ago"]]
    end

    test "generates instructions for relative date in comparison" do
      duration_ast = {:duration, [{1, "d"}], nil}
      relative_date_ast = {:relative_date, duration_ast, :ago, nil}
      ast = {:comparison, :gt, {:identifier, "created_at", nil}, relative_date_ast, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "created_at"],
               ["duration", [[1, "d"]]],
               ["relative_date", "ago"],
               ["compare", "GT"]
             ]
    end

    test "generates instructions for complex expression with multiple relative dates" do
      # created_at > 1d ago AND updated_at < 1h from now
      created_duration = {:duration, [{1, "d"}], nil}
      created_relative = {:relative_date, created_duration, :ago, nil}

      created_comparison =
        {:comparison, :gt, {:identifier, "created_at", nil}, created_relative, nil}

      updated_duration = {:duration, [{1, "h"}], nil}
      updated_relative = {:relative_date, updated_duration, :future, nil}

      updated_comparison =
        {:comparison, :lt, {:identifier, "updated_at", nil}, updated_relative, nil}

      ast = {:logical_and, created_comparison, updated_comparison, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "created_at"],
               ["duration", [[1, "d"]]],
               ["relative_date", "ago"],
               ["compare", "GT"],
               ["jump_if_falsy_or_pop", 5],
               ["load", "updated_at"],
               ["duration", [[1, "h"]]],
               ["relative_date", "future"],
               ["compare", "LT"]
             ]
    end
  end

  describe "visit/2 - list nodes" do
    test "all-literal integer list compiles to a single lit instruction" do
      ast = {:list, [{:literal, 1, nil}, {:literal, 2, nil}, {:literal, 3, nil}], nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["lit", [1, 2, 3]]]
    end

    test "all-literal string list compiles to a single lit instruction" do
      ast =
        {:list, [{:string_literal, "a", :double, nil}, {:string_literal, "b", :double, nil}], nil}

      result = InstructionsVisitor.visit(ast, [])

      assert result == [["lit", ["a", "b"]]]
    end

    test "empty list compiles to a single lit instruction" do
      ast = {:list, [], nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["lit", []]]
    end

    test "identifier-only list compiles to make_list" do
      ast = {:list, [{:identifier, "x", nil}, {:identifier, "y", nil}], nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["load", "x"], ["load", "y"], ["make_list", 2]]
    end

    test "list with an arithmetic element compiles to make_list" do
      ast =
        {:list,
         [
           {:arithmetic, :add, {:identifier, "x", nil}, {:literal, 1, nil}, nil},
           {:identifier, "y", nil}
         ], nil}

      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "x"],
               ["lit", 1],
               ["add"],
               ["load", "y"],
               ["make_list", 2]
             ]
    end

    test "mixed literal and non-literal list compiles to make_list" do
      ast = {:list, [{:literal, 1, nil}, {:identifier, "x", nil}], nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["lit", 1], ["load", "x"], ["make_list", 2]]
    end

    test "nested list with a non-literal outer element compiles to make_list" do
      ast =
        {:list, [{:list, [{:literal, 1, nil}, {:literal, 2, nil}], nil}, {:identifier, "x", nil}],
         nil}

      result = InstructionsVisitor.visit(ast, [])

      assert result == [["lit", [1, 2]], ["load", "x"], ["make_list", 2]]
    end

    test "list with a function call element compiles to make_list" do
      ast =
        {:list,
         [
           {:function_call, "len", [{:identifier, "name", nil}], nil},
           {:literal, 3, nil}
         ], nil}

      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "name"],
               ["call", "len", 1],
               ["lit", 3],
               ["make_list", 2]
             ]
    end
  end

  describe "visit/2 - assignment statements" do
    test "a root-level assignment stores depth 1" do
      {:ok, {:program, [assignment], _pos}} = Predicator.parse_program("x = 1")
      result = InstructionsVisitor.visit(assignment, [])

      assert result == [["lit", "x"], ["lit", 1], ["store", 1]]
    end

    test "a property-access assignment stores depth 2" do
      {:ok, {:program, [assignment], _pos}} = Predicator.parse_program(~s(user.name = 'Ada'))
      result = InstructionsVisitor.visit(assignment, [])

      assert result == [["lit", "user"], ["lit", "name"], ["lit", "Ada"], ["store", 2]]
    end

    test "a bracket-access assignment with a literal key stores depth 2" do
      {:ok, {:program, [assignment], _pos}} = Predicator.parse_program("a[0] = 1")
      result = InstructionsVisitor.visit(assignment, [])

      assert result == [["lit", "a"], ["lit", 0], ["lit", 1], ["store", 2]]
    end

    test "a computed bracket key proves n is depth, not instruction count" do
      {:ok, {:program, [assignment], _pos}} = Predicator.parse_program("a[k + 1] = 1")
      result = InstructionsVisitor.visit(assignment, [])

      assert result == [
               ["lit", "a"],
               ["load", "k"],
               ["lit", 1],
               ["add"],
               ["lit", 1],
               ["store", 2]
             ]
    end

    test "a mixed property/bracket chain stores depth 4" do
      {:ok, {:program, [assignment], _pos}} =
        Predicator.parse_program(~s(user.items[0].name = 'Ada'))

      result = InstructionsVisitor.visit(assignment, [])

      assert result == [
               ["lit", "user"],
               ["lit", "items"],
               ["lit", 0],
               ["lit", "name"],
               ["lit", "Ada"],
               ["store", 4]
             ]
    end
  end

  describe "visit/2 - programs" do
    test "a bare expression statement gains a trailing pop" do
      {:ok, program} = Predicator.parse_program("x + 1")
      result = InstructionsVisitor.visit(program, [])

      assert result == [["load", "x"], ["lit", 1], ["add"], ["pop"]]
    end

    test "an assignment statement gains no trailing pop" do
      {:ok, program} = Predicator.parse_program("x = 1")
      result = InstructionsVisitor.visit(program, [])

      assert result == [["lit", "x"], ["lit", 1], ["store", 1]]
    end

    test "a multi-statement program of assignments concatenates them uniformly" do
      {:ok, program} = Predicator.parse_program("x = 1; y = 2")
      result = InstructionsVisitor.visit(program, [])

      assert result == [
               ["lit", "x"],
               ["lit", 1],
               ["store", 1],
               ["lit", "y"],
               ["lit", 2],
               ["store", 1]
             ]
    end

    test "a mixed program of assignments and bare expressions compiles each in order" do
      {:ok, program} = Predicator.parse_program("x = 1; y = 2; z + 1")
      result = InstructionsVisitor.visit(program, [])

      assert result == [
               ["lit", "x"],
               ["lit", 1],
               ["store", 1],
               ["lit", "y"],
               ["lit", 2],
               ["store", 1],
               ["load", "z"],
               ["lit", 1],
               ["add"],
               ["pop"]
             ]
    end
  end

  describe "visit/2 - cast nodes" do
    test "generates a cast instruction after the operand's instructions" do
      ast = {:cast, {:identifier, "x", nil}, "integer", nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["load", "x"], ["cast", "integer"]]
    end

    test "a chained cast produces two cast instructions in source order" do
      ast =
        {:cast, {:cast, {:string_literal, "2026-08-09", :double, nil}, "date", nil}, "datetime",
         nil}

      result = InstructionsVisitor.visit(ast, [])

      assert result == [["lit", "2026-08-09"], ["cast", "date"], ["cast", "datetime"]]
    end

    test "a cast over a nested expression visits the operand first" do
      ast =
        {:cast, {:arithmetic, :add, {:identifier, "x", nil}, {:literal, 1, nil}, nil}, "integer",
         nil}

      result = InstructionsVisitor.visit(ast, [])

      assert result == [["load", "x"], ["lit", 1], ["add"], ["cast", "integer"]]
    end
  end

  describe "visit/2, visit_with_positions/2, visit_with_segment_positions/2 - unsupported nodes" do
    test "visit/2 declines an if node instead of raising" do
      ast = {:if, {:identifier, "a", nil}, {:block, [], nil}, nil, {1, 1}}

      assert {:error, %Predicator.Errors.EvaluationError{reason: "unsupported_node"} = error} =
               InstructionsVisitor.visit(ast, [])

      assert error.position == {1, 1}
    end

    test "visit/2 declines a bare block node - the hand-built-AST case" do
      assert {:error, %Predicator.Errors.EvaluationError{reason: "unsupported_node"}} =
               InstructionsVisitor.visit({:block, [], nil}, [])
    end

    test "visit_with_positions/2 declines an if node and carries its position" do
      ast = {:if, {:identifier, "a", nil}, {:block, [], nil}, nil, {1, 4}}

      assert {:error,
              %Predicator.Errors.EvaluationError{reason: "unsupported_node", position: {1, 4}}} =
               InstructionsVisitor.visit_with_positions(ast, [])
    end

    test "visit_with_positions/2 carries a span in span mode" do
      ast = {:if, {:identifier, "a", nil}, {:block, [], nil}, nil, {{1, 1}, {1, 9}}}

      assert {:error, %Predicator.Errors.EvaluationError{reason: "unsupported_node"} = error} =
               InstructionsVisitor.visit_with_positions(ast, [])

      assert error.span == {{1, 1}, {1, 9}}
      assert error.position == {1, 1}
    end

    test "visit_with_segment_positions/2 declines an if node" do
      ast = {:if, {:identifier, "a", nil}, {:block, [], nil}, nil, {1, 1}}

      assert {:error, %Predicator.Errors.EvaluationError{reason: "unsupported_node"}} =
               InstructionsVisitor.visit_with_segment_positions(ast, [])
    end

    test "an if nested inside an else block is caught at depth, not only at the top" do
      {:ok, program} = Predicator.parse_program("if a { } else if b { }")

      assert {:error, %Predicator.Errors.EvaluationError{reason: "unsupported_node"}} =
               InstructionsVisitor.visit(program, [])
    end

    test "negative control: an ordinary program still returns a plain instruction list" do
      {:ok, program} = Predicator.parse_program("x = 1; x + 1")

      assert InstructionsVisitor.visit(program, []) == [
               ["lit", "x"],
               ["lit", 1],
               ["store", 1],
               ["load", "x"],
               ["lit", 1],
               ["add"],
               ["pop"]
             ]
    end
  end
end
