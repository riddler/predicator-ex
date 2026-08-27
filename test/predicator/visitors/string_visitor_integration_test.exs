defmodule Predicator.Visitors.StringVisitorIntegrationTest do
  use ExUnit.Case, async: true

  alias Predicator.Visitors.StringVisitor

  @corpus [
    "42",
    ~s("hello"),
    "'hello'",
    "limit",
    "a > 1",
    "a + 1 * 2",
    "-a",
    "a in [1, 2]",
    "a > 1 AND b < 2",
    "a > 1 OR b < 2",
    "NOT a",
    "[a, b, 3]",
    "[]",
    "{a: 1, \"b\": x}",
    "{'c d': 1}",
    "{}",
    "len(upper(name))",
    "a[0][1]",
    "user.name.first",
    "3d8h",
    "3d ago",
    "next 2w",
    "limit::integer",
    "\"42\"::integer",
    "x::integer::string",
    "(1 + 2)::string",
    "(-1)::integer",
    "(a AND b)::boolean",
    "a::integer + b::float > 3",
    "f(x)::integer",
    "a.b::string",
    "list[0]::integer"
  ]

  describe "raw parser output" do
    test "every corpus expression round-trips from raw parser output" do
      for source <- @corpus do
        {:ok, ast} = Predicator.parse(source)

        # No normalization step: the visitors take parser output as it comes.
        assert {:ok, reparsed} = Predicator.parse(Predicator.decompile(ast))
        assert Predicator.ASTShape.strip(reparsed) == Predicator.ASTShape.strip(ast)
      end
    end
  end

  describe "visit/2 - integration with parser output" do
    test "round-trip with simple expression" do
      alias Predicator.Lexer

      original = "limit > 85"
      {:ok, tokens} = Lexer.tokenize(original)
      {:ok, ast} = Predicator.Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])

      assert result == original
    end

    test "round-trip with string comparison" do
      alias Predicator.Lexer

      original = ~s(name == "John")
      {:ok, tokens} = Lexer.tokenize(original)
      {:ok, ast} = Predicator.Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])

      assert result == original
    end

    test "round-trip with boolean comparison" do
      alias Predicator.Lexer

      original = "active == true"
      {:ok, tokens} = Lexer.tokenize(original)
      {:ok, ast} = Predicator.Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])

      assert result == original
    end

    test "parse -> decompile -> parse fixpoint for the undefined literal" do
      original = "x === undefined"
      {:ok, ast} = Predicator.parse(original)

      decompiled = Predicator.decompile(ast)
      assert decompiled == original

      assert {:ok, reparsed} = Predicator.parse(decompiled)
      assert Predicator.ASTShape.strip(reparsed) == Predicator.ASTShape.strip(ast)
    end

    test "parse -> decompile -> parse fixpoint for undefined in a list literal" do
      original = "[undefined]"
      {:ok, ast} = Predicator.parse(original)

      decompiled = Predicator.decompile(ast)
      assert decompiled == original

      assert {:ok, reparsed} = Predicator.parse(decompiled)
      assert Predicator.ASTShape.strip(reparsed) == Predicator.ASTShape.strip(ast)
    end

    test "parse -> decompile -> parse fixpoint for the null literal" do
      original = "x === null"
      {:ok, ast} = Predicator.parse(original)

      decompiled = Predicator.decompile(ast)
      assert decompiled == original

      assert {:ok, reparsed} = Predicator.parse(decompiled)
      assert Predicator.ASTShape.strip(reparsed) == Predicator.ASTShape.strip(ast)
    end

    test "parse -> decompile -> parse fixpoint for null in a list literal" do
      original = "[null]"
      {:ok, ast} = Predicator.parse(original)

      decompiled = Predicator.decompile(ast)
      assert decompiled == original

      assert {:ok, reparsed} = Predicator.parse(decompiled)
      assert Predicator.ASTShape.strip(reparsed) == Predicator.ASTShape.strip(ast)
    end

    test "round-trip with all comparison operators" do
      alias Predicator.Lexer

      expressions = [
        "x > 5",
        "x < 5",
        "x >= 5",
        "x <= 5",
        "x == 5",
        "x != 5"
      ]

      for original <- expressions do
        {:ok, tokens} = Lexer.tokenize(original)
        {:ok, ast} = Predicator.Parser.parse(tokens)
        result = StringVisitor.visit(ast, [])

        assert result == original, "Failed round-trip for: #{original}"
      end
    end

    test "round-trip with property access" do
      alias Predicator.Lexer

      original = "user.name"
      {:ok, tokens} = Lexer.tokenize(original)
      {:ok, ast} = Predicator.Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])

      assert result == original
    end

    test "round-trip with chained property access" do
      alias Predicator.Lexer

      original = ~s(user.profile.email == "test@example.com")
      {:ok, tokens} = Lexer.tokenize(original)
      {:ok, ast} = Predicator.Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])

      assert result == original
    end

    test "round-trip with mixed property and bracket access" do
      alias Predicator.Lexer

      original = ~s(user.settings["theme"].name)
      {:ok, tokens} = Lexer.tokenize(original)
      {:ok, ast} = Predicator.Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])

      assert result == original
    end

    test "handles parenthesized expressions" do
      alias Predicator.Lexer

      # Note: Parser removes unnecessary parentheses from AST
      original = "(limit > 85)"
      {:ok, tokens} = Lexer.tokenize(original)
      {:ok, ast} = Predicator.Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])
      # Parentheses are removed by parser since they're not needed
      assert result == "limit > 85"

      # But we can add them back with explicit mode
      result_explicit = StringVisitor.visit(ast, parentheses: :explicit)
      assert result_explicit == "(limit > 85)"
    end

    test "handles complex expressions with whitespace normalization" do
      alias Predicator.Lexer

      original_with_extra_spaces = "  limit   >    85  "
      {:ok, tokens} = Lexer.tokenize(original_with_extra_spaces)
      {:ok, ast} = Predicator.Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])

      # StringVisitor normalizes spacing
      assert result == "limit > 85"
    end
  end

  describe "visit/2 - integration with parser" do
    test "round-trip with logical AND expression" do
      alias Predicator.Lexer

      expression = "limit > 85 AND age >= 18"
      {:ok, tokens} = Lexer.tokenize(expression)
      {:ok, ast} = Predicator.Parser.parse(tokens)
      result = StringVisitor.visit(ast, [])

      assert result == expression
    end

    test "round-trip with logical OR expression" do
      alias Predicator.Lexer

      expression = ~s(role == "admin" OR role == "manager")
      {:ok, tokens} = Lexer.tokenize(expression)
      {:ok, ast} = Predicator.Parser.parse(tokens)
      result = StringVisitor.visit(ast, [])

      assert result == expression
    end

    test "round-trip with logical NOT expression" do
      alias Predicator.Lexer

      expression = "NOT expired == true"
      {:ok, tokens} = Lexer.tokenize(expression)
      {:ok, ast} = Predicator.Parser.parse(tokens)
      result = StringVisitor.visit(ast, [])

      assert result == expression
    end

    test "round-trip with complex logical expression" do
      alias Predicator.Lexer

      expression = "limit > 85 AND age >= 18 OR admin == true"
      {:ok, tokens} = Lexer.tokenize(expression)
      {:ok, ast} = Predicator.Parser.parse(tokens)
      result = StringVisitor.visit(ast, [])

      assert result == expression
    end
  end
end
