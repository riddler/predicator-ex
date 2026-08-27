defmodule Predicator.Visitors.StringVisitorPrecedenceTest do
  use ExUnit.Case, async: true

  alias Predicator.Visitors.StringVisitor

  describe "visit/2 - :minimal adds parens exactly when precedence requires it" do
    test "parenthesizes a looser left child of a tighter parent" do
      # (1 + 2) * 3
      inner = {:arithmetic, :add, {:literal, 1, nil}, {:literal, 2, nil}, nil}
      ast = {:arithmetic, :multiply, inner, {:literal, 3, nil}, nil}

      assert StringVisitor.visit(ast, []) == "(1 + 2) * 3"
    end

    test "parenthesizes a looser right child of a tighter parent" do
      # 3 * (1 + 2)
      inner = {:arithmetic, :add, {:literal, 1, nil}, {:literal, 2, nil}, nil}
      ast = {:arithmetic, :multiply, {:literal, 3, nil}, inner, nil}

      assert StringVisitor.visit(ast, []) == "3 * (1 + 2)"
    end

    test "does not parenthesize when precedence already holds the shape" do
      # 1 + 2 * 3, unambiguous as-is
      inner = {:arithmetic, :multiply, {:literal, 2, nil}, {:literal, 3, nil}, nil}
      ast = {:arithmetic, :add, {:literal, 1, nil}, inner, nil}

      assert StringVisitor.visit(ast, []) == "1 + 2 * 3"
    end

    test "parenthesizes a same-precedence right child to preserve left-associativity" do
      # 1 - (2 - 3): without parens this would re-parse as (1 - 2) - 3
      inner = {:arithmetic, :subtract, {:literal, 2, nil}, {:literal, 3, nil}, nil}
      ast = {:arithmetic, :subtract, {:literal, 1, nil}, inner, nil}

      assert StringVisitor.visit(ast, []) == "1 - (2 - 3)"
    end

    test "does not parenthesize a same-precedence left child (matches left-associativity)" do
      # (1 - 2) - 3 renders as "1 - 2 - 3", which re-parses to the same AST
      inner = {:arithmetic, :subtract, {:literal, 1, nil}, {:literal, 2, nil}, nil}
      ast = {:arithmetic, :subtract, inner, {:literal, 3, nil}, nil}

      assert StringVisitor.visit(ast, []) == "1 - 2 - 3"
    end

    test "parenthesizes a looser logical_or child under logical_and" do
      # (a OR b) AND c
      inner_or =
        {:logical_or, {:identifier, "a", nil}, {:identifier, "b", nil}, nil}

      ast = {:logical_and, inner_or, {:identifier, "c", nil}, nil}

      assert StringVisitor.visit(ast, []) == "(a OR b) AND c"
    end

    test "does not parenthesize logical_and under logical_or (already correct shape)" do
      # a AND b OR c, unambiguous as-is
      inner_and =
        {:logical_and, {:identifier, "a", nil}, {:identifier, "b", nil}, nil}

      ast = {:logical_or, inner_and, {:identifier, "c", nil}, nil}

      assert StringVisitor.visit(ast, []) == "a AND b OR c"
    end

    test "parenthesizes a looser operand under NOT" do
      # NOT (a AND b)
      inner_and =
        {:logical_and, {:identifier, "a", nil}, {:identifier, "b", nil}, nil}

      ast = {:logical_not, inner_and, nil}

      assert StringVisitor.visit(ast, []) == "NOT (a AND b)"
    end

    test "parenthesizes a looser operand under unary minus" do
      # -(1 + 2)
      inner = {:arithmetic, :add, {:literal, 1, nil}, {:literal, 2, nil}, nil}
      ast = {:unary, :minus, inner, nil}

      assert StringVisitor.visit(ast, []) == "-(1 + 2)"
    end

    test "parenthesizes a looser operand under unary bang" do
      # !(a AND b)
      inner_and =
        {:logical_and, {:identifier, "a", nil}, {:identifier, "b", nil}, nil}

      ast = {:unary, :bang, inner_and, nil}

      assert StringVisitor.visit(ast, []) == "!(a AND b)"
    end

    test "does not add parens in :none mode even when precedence would otherwise require them" do
      inner = {:arithmetic, :add, {:literal, 1, nil}, {:literal, 2, nil}, nil}
      ast = {:arithmetic, :multiply, inner, {:literal, 3, nil}, nil}

      assert StringVisitor.visit(ast, parentheses: :none) == "1 + 2 * 3"
    end

    test "spacing mode does not suppress the parentheses" do
      inner = {:arithmetic, :add, {:literal, 1, nil}, {:literal, 2, nil}, nil}
      ast = {:arithmetic, :multiply, inner, {:literal, 3, nil}, nil}

      assert StringVisitor.visit(ast, spacing: :compact) == "(1+2)*3"
      assert StringVisitor.visit(ast, spacing: :verbose) == "(1  +  2)  *  3"
    end

    test "the expression-layer round-trip: (1 + 2) * 3" do
      {:ok, ast} = Predicator.parse("(1 + 2) * 3")
      decompiled = Predicator.decompile(ast)

      assert Predicator.parse(decompiled) == {:ok, ast}
    end

    test "the statement-layer round-trip: x = (1 + 2) * 3" do
      {:ok, ast} = Predicator.parse_program("x = (1 + 2) * 3")
      decompiled = Predicator.decompile(ast)

      assert Predicator.parse_program(decompiled) == {:ok, ast}
    end

    @precedence_corpus [
      "1 + 2 * 3",
      "(1 + 2) * 3",
      "3 * (1 + 2)",
      "1 - 2 - 3",
      "1 - (2 - 3)",
      "10 / 2 / 5",
      "a AND b OR c",
      "(a OR b) AND c",
      "NOT (a AND b)",
      "NOT a AND b",
      "-(1 + 2)",
      "!(a AND b)",
      "a > 1 AND b < 2 OR c == 3",
      "(a > 1 AND b < 2) OR c == 3",
      "a > 1 AND (b < 2 OR c == 3)",
      "1 + 2 * 3 - 4 / 2",
      "x = (1 + 2) * 3",
      "x = 1 + 2 * 3",
      "limit::integer",
      "x::integer::string",
      "(1 + 2)::string",
      "(-1)::integer",
      "(a AND b)::boolean",
      "a::integer + b::float > 3",
      "f(x)::integer",
      "a.b::string",
      "list[0]::integer"
    ]

    test "a corpus of precedence-sensitive expressions round-trips under default :minimal" do
      for source <- @precedence_corpus do
        assert_tree_fixpoint(source)
      end
    end
  end

  describe "visit/2 - if/block rendering (ADR-0013)" do
    @control_flow_corpus [
      "if a { x = 1 }",
      "if a { }",
      "if a { x = 1 } else { x = 2 }",
      "if a { } else { }",
      "if a { x = 1; y = 2 } else { x = 2 }",
      "if a { x = 1 } else if b { x = 2 }",
      "if a { x = 1 } else if b { x = 2 } else { x = 3 }",
      "if a { x = 1 } else if b { x = 2 } else if c { x = 3 } else { x = 4 }",
      "if a { if b { x = 1 } }",
      "if a { if b { x = 1 } else { x = 2 } } else { x = 3 }",
      "if a > 1 AND b < 2 { x = 1 }",
      "z = 0; if a { x = 1 }; y = 2",
      "if a { x = 1 } if b { y = 2 }"
    ]

    test "a corpus of control-flow programs round-trips (tree fixpoint)" do
      for source <- @control_flow_corpus do
        assert_tree_fixpoint(source)
      end
    end

    test "a corpus of control-flow programs round-trips (string fixpoint)" do
      for source <- @control_flow_corpus do
        assert_string_fixpoint(source)
      end
    end

    test "renders a bare if with no else" do
      {:ok, ast} = Predicator.parse_program("if a { x = 1 }")

      assert Predicator.decompile(ast) == "if a { x = 1 }"
    end

    test "renders an empty block as '{ }'" do
      {:ok, ast} = Predicator.parse_program("if a { }")

      assert Predicator.decompile(ast) == "if a { }"
    end

    test "renders an if/else" do
      {:ok, ast} = Predicator.parse_program("if a { x = 1 } else { x = 2 }")

      assert Predicator.decompile(ast) == "if a { x = 1 } else { x = 2 }"
    end

    test "prints an else slot holding a single hand-nested if as 'else if'" do
      {:ok, ast} = Predicator.parse_program("if a { x = 1 } else { if b { x = 2 } }")

      decompiled = Predicator.decompile(ast)
      assert decompiled == "if a { x = 1 } else if b { x = 2 }"

      assert {:ok, reparsed} = Predicator.parse_program(decompiled)
      assert Predicator.ASTShape.strip(reparsed) == Predicator.ASTShape.strip(ast)
    end

    test "keeps braces when the else block holds more than a single if" do
      {:ok, ast} = Predicator.parse_program("if a { x = 1 } else { if b { x = 2 }; y = 3 }")

      assert Predicator.decompile(ast) == "if a { x = 1 } else { if b { x = 2 }; y = 3 }"
    end

    test "statement-layer punctuation ignores :spacing" do
      {:ok, ast} = Predicator.parse_program("if a { x = 1 }")

      assert Predicator.decompile(ast, spacing: :compact) == "if a { x = 1 }"
      assert Predicator.decompile(ast, spacing: :verbose) == "if a { x = 1 }"
    end

    test "negative control: decompile/2 on an ordinary expression still returns a binary" do
      {:ok, ast} = Predicator.parse("a > 1")

      assert Predicator.decompile(ast) == "a > 1"
    end

    test "negative control: decompile/2 on a program of assignments still returns a binary" do
      {:ok, ast} = Predicator.parse_program("a = 1; b = 2")

      assert Predicator.decompile(ast) == "a = 1; b = 2"
    end
  end

  # Shared by the precedence-sensitive and control-flow corpus tests above:
  # parse -> decompile -> reparse, then compare the stripped trees (tree
  # fixpoint) or the two decompiled strings (string fixpoint).
  defp assert_tree_fixpoint(source) do
    {:ok, ast} = Predicator.parse_program(source)
    decompiled = Predicator.decompile(ast)

    assert {:ok, reparsed} = Predicator.parse_program(decompiled)

    assert Predicator.ASTShape.strip(reparsed) == Predicator.ASTShape.strip(ast),
           "Failed round-trip for: #{source} -> #{decompiled}"
  end

  defp assert_string_fixpoint(source) do
    {:ok, ast} = Predicator.parse_program(source)
    decompiled = Predicator.decompile(ast)

    {:ok, reparsed} = Predicator.parse_program(decompiled)
    redecompiled = Predicator.decompile(reparsed)

    assert redecompiled == decompiled,
           "String fixpoint failed for: #{source} -> #{decompiled} -> #{redecompiled}"
  end
end
