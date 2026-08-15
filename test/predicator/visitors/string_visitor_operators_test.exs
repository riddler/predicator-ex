defmodule Predicator.Visitors.StringVisitorOperatorsTest do
  use ExUnit.Case, async: true

  alias Predicator.Visitors.StringVisitor

  describe "visit/2 - logical operators" do
    test "formats simple logical AND" do
      ast = {:logical_and, {:literal, true, nil}, {:literal, false, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "true AND false"
    end

    test "formats simple logical OR" do
      ast = {:logical_or, {:literal, true, nil}, {:literal, false, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "true OR false"
    end

    test "formats simple logical NOT" do
      ast = {:logical_not, {:literal, true, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "NOT true"
    end

    test "formats logical AND with comparisons" do
      ast =
        {:logical_and, {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil},
         {:comparison, :gte, {:identifier, "age", nil}, {:literal, 18, nil}, nil}, nil}

      result = StringVisitor.visit(ast, [])

      assert result == "score > 85 AND age >= 18"
    end

    test "formats logical OR with comparisons" do
      ast =
        {:logical_or,
         {:comparison, :eq, {:identifier, "role", nil}, {:literal, "admin", nil}, nil},
         {:comparison, :eq, {:identifier, "role", nil}, {:literal, "manager", nil}, nil}, nil}

      result = StringVisitor.visit(ast, [])

      assert result == ~s(role == "admin" OR role == "manager")
    end

    test "formats logical NOT with comparison" do
      ast =
        {:logical_not,
         {:comparison, :eq, {:identifier, "expired", nil}, {:literal, true, nil}, nil}, nil}

      result = StringVisitor.visit(ast, [])

      assert result == "NOT expired == true"
    end

    test "formats nested logical NOT" do
      ast = {:logical_not, {:logical_not, {:literal, false, nil}, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "NOT NOT false"
    end

    test "formats complex nested logical expression" do
      # (score > 85 AND age >= 18) OR admin = true
      ast =
        {:logical_or,
         {:logical_and, {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil},
          {:comparison, :gte, {:identifier, "age", nil}, {:literal, 18, nil}, nil}, nil},
         {:comparison, :eq, {:identifier, "admin", nil}, {:literal, true, nil}, nil}, nil}

      result = StringVisitor.visit(ast, [])

      assert result == "score > 85 AND age >= 18 OR admin == true"
    end

    test "formats logical operators with compact spacing" do
      ast = {:logical_and, {:literal, true, nil}, {:literal, false, nil}, nil}
      result = StringVisitor.visit(ast, spacing: :compact)

      assert result == "trueANDfalse"
    end

    test "formats logical operators with verbose spacing" do
      ast = {:logical_or, {:literal, true, nil}, {:literal, false, nil}, nil}
      result = StringVisitor.visit(ast, spacing: :verbose)

      assert result == "true  OR  false"
    end

    test "formats logical operators with explicit parentheses" do
      ast = {:logical_and, {:literal, true, nil}, {:literal, false, nil}, nil}
      result = StringVisitor.visit(ast, parentheses: :explicit)

      assert result == "(true AND false)"
    end

    test "formats logical NOT with explicit parentheses" do
      ast = {:logical_not, {:literal, true, nil}, nil}
      result = StringVisitor.visit(ast, parentheses: :explicit)

      assert result == "(NOT true)"
    end

    test "formats logical NOT with no parentheses mode" do
      ast = {:logical_not, {:literal, false, nil}, nil}
      result = StringVisitor.visit(ast, parentheses: :none)

      assert result == "NOT false"
    end

    test "formats complex logical expression with all formatting options" do
      ast =
        {:logical_not, {:logical_and, {:literal, true, nil}, {:literal, false, nil}, nil}, nil}

      result = StringVisitor.visit(ast, spacing: :verbose, parentheses: :explicit)

      assert result == "(NOT  (true  AND  false))"
    end

    test "formats left-associative AND operations" do
      # ((true AND false) AND true)
      ast =
        {:logical_and, {:logical_and, {:literal, true, nil}, {:literal, false, nil}, nil},
         {:literal, true, nil}, nil}

      result = StringVisitor.visit(ast, [])

      assert result == "true AND false AND true"
    end

    test "formats left-associative OR operations" do
      # ((true OR false) OR true)
      ast =
        {:logical_or, {:logical_or, {:literal, true, nil}, {:literal, false, nil}, nil},
         {:literal, true, nil}, nil}

      result = StringVisitor.visit(ast, [])

      assert result == "true OR false OR true"
    end

    test "formats mixed comparison and logical operations" do
      # score > 85 AND NOT expired
      ast =
        {:logical_and, {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil},
         {:logical_not, {:identifier, "expired", nil}, nil}, nil}

      result = StringVisitor.visit(ast, [])

      assert result == "score > 85 AND NOT expired"
    end
  end

  describe "visit/2 - arithmetic operators" do
    test "converts addition expression" do
      ast = {:arithmetic, :add, {:identifier, "a", nil}, {:identifier, "b", nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "a + b"
    end

    test "converts subtraction expression" do
      ast = {:arithmetic, :subtract, {:literal, 10, nil}, {:literal, 3, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "10 - 3"
    end

    test "converts multiplication expression" do
      ast = {:arithmetic, :multiply, {:identifier, "x", nil}, {:literal, 2, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "x * 2"
    end

    test "converts division expression" do
      ast = {:arithmetic, :divide, {:literal, 100, nil}, {:identifier, "divisor", nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "100 / divisor"
    end

    test "converts modulo expression" do
      ast = {:arithmetic, :modulo, {:identifier, "n", nil}, {:literal, 5, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "n % 5"
    end

    test "converts nested arithmetic expressions" do
      # (a + b) * c
      inner_add = {:arithmetic, :add, {:identifier, "a", nil}, {:identifier, "b", nil}, nil}
      ast = {:arithmetic, :multiply, inner_add, {:identifier, "c", nil}, nil}
      result = StringVisitor.visit(ast, [])

      # The `+` binds looser than `*`, so the left child needs parens or the
      # string would re-parse as a + (b * c) - a different AST (px-ek5).
      assert result == "(a + b) * c"
    end

    test "converts arithmetic with explicit parentheses mode" do
      ast = {:arithmetic, :add, {:identifier, "x", nil}, {:literal, 5, nil}, nil}
      result = StringVisitor.visit(ast, parentheses: :explicit)

      assert result == "(x + 5)"
    end

    test "converts arithmetic with compact spacing" do
      ast = {:arithmetic, :multiply, {:literal, 3, nil}, {:literal, 4, nil}, nil}
      result = StringVisitor.visit(ast, spacing: :compact)

      assert result == "3*4"
    end

    test "converts arithmetic with verbose spacing" do
      ast = {:arithmetic, :subtract, {:identifier, "total", nil}, {:literal, 10, nil}, nil}
      result = StringVisitor.visit(ast, spacing: :verbose)

      assert result == "total  -  10"
    end
  end

  describe "visit/2 - unary operators" do
    test "converts unary minus expression" do
      ast = {:unary, :minus, {:identifier, "x", nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "-x"
    end

    test "converts unary minus with literal" do
      ast = {:unary, :minus, {:literal, 42, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "-42"
    end

    test "converts unary bang (logical NOT) expression" do
      ast = {:unary, :bang, {:identifier, "active", nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "!active"
    end

    test "converts unary bang with boolean literal" do
      ast = {:unary, :bang, {:literal, true, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "!true"
    end

    test "converts nested unary expressions" do
      # !(-x)
      inner_minus = {:unary, :minus, {:identifier, "x", nil}, nil}
      ast = {:unary, :bang, inner_minus, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "!-x"
    end

    test "converts unary with function call" do
      # !(len(name))
      function_call = {:function_call, "len", [{:identifier, "name", nil}], nil}
      ast = {:unary, :bang, function_call, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "!len(name)"
    end
  end

  describe "visit/2 - equality operators" do
    test "converts equality (==) expression" do
      ast = {:comparison, :eq, {:identifier, "x", nil}, {:identifier, "y", nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "x == y"
    end

    test "converts inequality (!=) with equality syntax" do
      ast = {:comparison, :ne, {:identifier, "status", nil}, {:literal, "active", nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == ~s(status != "active")
    end

    test "converts equality with explicit parentheses" do
      ast = {:comparison, :eq, {:literal, 1, nil}, {:literal, 1, nil}, nil}
      result = StringVisitor.visit(ast, parentheses: :explicit)

      assert result == "(1 == 1)"
    end

    test "converts equality with compact spacing" do
      ast = {:comparison, :eq, {:identifier, "a", nil}, {:identifier, "b", nil}, nil}
      result = StringVisitor.visit(ast, spacing: :compact)

      assert result == "a==b"
    end
  end

  describe "visit/2 - mixed operator expressions" do
    test "converts arithmetic within comparison" do
      # x + y > 10
      arithmetic = {:arithmetic, :add, {:identifier, "x", nil}, {:identifier, "y", nil}, nil}
      ast = {:comparison, :gt, arithmetic, {:literal, 10, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "x + y > 10"
    end

    test "converts unary in logical expression" do
      # !active AND !expired
      left_unary = {:unary, :bang, {:identifier, "active", nil}, nil}
      right_unary = {:unary, :bang, {:identifier, "expired", nil}, nil}
      ast = {:logical_and, left_unary, right_unary, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "!active AND !expired"
    end

    test "converts complex nested expression" do
      # !(x + y == 10)
      arithmetic = {:arithmetic, :add, {:identifier, "x", nil}, {:identifier, "y", nil}, nil}
      equality = {:comparison, :eq, arithmetic, {:literal, 10, nil}, nil}
      ast = {:unary, :bang, equality, nil}
      result = StringVisitor.visit(ast, [])

      # Comparison binds looser than unary `!`, so the operand needs parens
      # or the string would re-parse as (!x) + y == 10 (px-ek5).
      assert result == "!(x + y == 10)"
    end
  end
end
