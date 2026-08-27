defmodule Predicator.Visitors.StringVisitorProgramsTest do
  use ExUnit.Case, async: true

  alias Predicator.Visitors.StringVisitor

  describe "visit/2 - object keys" do
    test "renders each key style as it was written" do
      for source <- ["{a: 1}", ~s({"a b": 1}), "{'a b': 1}"] do
        {:ok, ast} = Predicator.parse(source)
        assert StringVisitor.visit(ast, []) == source
      end
    end

    test "escapes a quote character inside a key" do
      {:ok, ast} = Predicator.parse(~s({"say \\"hi\\"": 1}))
      decompiled = StringVisitor.visit(ast, [])

      assert decompiled == ~s({"say \\"hi\\"": 1})
      assert Predicator.parse(decompiled) == {:ok, ast}
    end

    test "renders a hand-built key from its style" do
      identifier_key =
        {:object, [{{:object_key, "a", :identifier, nil}, {:literal, 1, nil}}], nil}

      assert StringVisitor.visit(identifier_key, []) == "{a: 1}"

      double_key = {:object, [{{:object_key, "a b", :double, nil}, {:literal, 1, nil}}], nil}
      assert StringVisitor.visit(double_key, []) == ~s({"a b": 1})
    end
  end

  describe "visit/2 - program and assignment round-trip" do
    test "single-statement program round-trips" do
      assert_program_round_trip("a = 1")
    end

    test "multi-statement program round-trips" do
      assert_program_round_trip("a = 1; b = a + 1")
    end

    test "trailing semicolon normalizes away on re-parse" do
      {:ok, ast} = Predicator.parse_program("a = 1;")
      decompiled = Predicator.decompile(ast)

      assert decompiled == "a = 1"
      assert Predicator.parse_program(decompiled) == {:ok, ast}
    end

    test "assignment to a property/bracket chain round-trips" do
      assert_program_round_trip("user.items[0].name = 'Ada'")
    end

    test "mixed assignment and expression statements round-trip" do
      assert_program_round_trip("a = 1; b = a + 1; a > 0")
    end

    test "renders a program as its statements joined by \"; \"" do
      {:ok, ast} = Predicator.parse_program("a = 1; b = 2; a > b")
      assert StringVisitor.visit(ast, []) == "a = 1; b = 2; a > b"
    end

    test "renders an assignment as \"lhs = rhs\"" do
      ast = {:assignment, {:identifier, "a", nil}, {:literal, 1, nil}, nil}
      assert StringVisitor.visit(ast, []) == "a = 1"
    end

    test "statement separator and assignment spacing ignore the :spacing option" do
      {:ok, ast} = Predicator.parse_program("a = 1; b = 2")
      assert StringVisitor.visit(ast, spacing: :compact) == "a = 1; b = 2"
      assert StringVisitor.visit(ast, spacing: :verbose) == "a = 1; b = 2"
    end

    defp assert_program_round_trip(source) do
      {:ok, ast} = Predicator.parse_program(source)
      decompiled = Predicator.decompile(ast)

      assert Predicator.parse_program(decompiled) == {:ok, ast}
    end
  end

  describe "visit/2 - while round-trip (ADR-0013, px-3so.4 Phase 2)" do
    test "a single-statement body round-trips" do
      assert_program_round_trip("while c { x = 1 }")
    end

    test "an empty body round-trips" do
      assert_program_round_trip("while c { }")
    end

    test "a multi-statement body round-trips" do
      assert_program_round_trip("while c { x = 1; y = 2 }")
    end

    test "a nested while round-trips" do
      assert_program_round_trip("while a { while b { x = 1 } }")
    end

    test "renders \"while <condition> { <statements> }\"" do
      {:ok, ast} = Predicator.parse_program("while c { x = 1 }")
      assert Predicator.decompile(ast) == "while c { x = 1 }"
    end

    test "an empty body renders \"{ }\"" do
      {:ok, ast} = Predicator.parse_program("while c { }")
      assert Predicator.decompile(ast) == "while c { }"
    end
  end

  describe "visit/2 - cast nodes" do
    test "renders a simple cast as \"expr::type\"" do
      ast = {:cast, {:identifier, "limit", nil}, "integer", nil}

      assert StringVisitor.visit(ast, []) == "limit::integer"
    end

    test "renders a cast of a string literal" do
      ast = {:cast, {:string_literal, "42", :double, nil}, "integer", nil}

      assert StringVisitor.visit(ast, []) == "\"42\"::integer"
    end

    test "chains casts without parenthesizing the inner cast" do
      inner = {:cast, {:identifier, "x", nil}, "integer", nil}
      ast = {:cast, inner, "string", nil}

      assert StringVisitor.visit(ast, []) == "x::integer::string"
    end

    test "parenthesizes an arithmetic operand" do
      inner = {:arithmetic, :add, {:literal, 1, nil}, {:literal, 2, nil}, nil}
      ast = {:cast, inner, "string", nil}

      assert StringVisitor.visit(ast, []) == "(1 + 2)::string"
    end

    test "parenthesizes a unary minus operand" do
      inner = {:unary, :minus, {:literal, 1, nil}, nil}
      ast = {:cast, inner, "integer", nil}

      assert StringVisitor.visit(ast, []) == "(-1)::integer"
    end

    test "parenthesizes a logical operand" do
      inner = {:logical_and, {:identifier, "a", nil}, {:identifier, "b", nil}, nil}
      ast = {:cast, inner, "boolean", nil}

      assert StringVisitor.visit(ast, []) == "(a AND b)::boolean"
    end

    test "parenthesizes a comparison operand" do
      inner = {:comparison, :gt, {:identifier, "a", nil}, {:literal, 1, nil}, nil}
      ast = {:cast, inner, "boolean", nil}

      assert StringVisitor.visit(ast, []) == "(a > 1)::boolean"
    end

    test "does not parenthesize a property access operand" do
      inner = {:property_access, {:identifier, "a", nil}, "b", nil}
      ast = {:cast, inner, "string", nil}

      assert StringVisitor.visit(ast, []) == "a.b::string"
    end

    test "does not parenthesize a bracket access operand" do
      inner = {:bracket_access, {:identifier, "list", nil}, {:literal, 0, nil}, nil}
      ast = {:cast, inner, "integer", nil}

      assert StringVisitor.visit(ast, []) == "list[0]::integer"
    end

    test "does not parenthesize a function call operand" do
      inner = {:function_call, "f", [{:identifier, "x", nil}], nil}
      ast = {:cast, inner, "integer", nil}

      assert StringVisitor.visit(ast, []) == "f(x)::integer"
    end

    test "a cast does not need parentheses as an arithmetic operand" do
      ast =
        {:arithmetic, :add, {:cast, {:identifier, "x", nil}, "integer", nil}, {:literal, 1, nil},
         nil}

      assert StringVisitor.visit(ast, []) == "x::integer + 1"
    end

    test "does not add parentheses in :none mode even when precedence would otherwise require them" do
      inner = {:arithmetic, :add, {:literal, 1, nil}, {:literal, 2, nil}, nil}
      ast = {:cast, inner, "string", nil}

      assert StringVisitor.visit(ast, parentheses: :none) == "1 + 2::string"
    end

    test "explicit mode adds no parens around a primary operand (matches :minimal)" do
      ast = {:cast, {:identifier, "limit", nil}, "integer", nil}

      assert StringVisitor.visit(ast, parentheses: :explicit) == "limit::integer"
    end

    test "explicit mode relies on the operand's own self-wrapping, not cast-level wrapping" do
      # The arithmetic child already self-wraps under :explicit, so the cast
      # clause does not need to (and does not) add a second layer of parens.
      inner = {:arithmetic, :add, {:literal, 1, nil}, {:literal, 2, nil}, nil}
      ast = {:cast, inner, "string", nil}

      assert StringVisitor.visit(ast, parentheses: :explicit) == "(1 + 2)::string"
    end

    test "the round-trip: nested casts inside a larger expression" do
      {:ok, ast} = Predicator.parse("a::integer + b::float > 3")
      decompiled = StringVisitor.visit(ast, [])

      assert {:ok, reparsed} = Predicator.parse(decompiled)
      assert Predicator.ASTShape.strip(reparsed) == Predicator.ASTShape.strip(ast)
    end
  end
end
