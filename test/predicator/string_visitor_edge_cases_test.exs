defmodule Predicator.StringVisitorEdgeCasesTest do
  use ExUnit.Case, async: true

  alias Predicator.StringVisitor

  describe "edge cases" do
    test "handles function calls with empty arguments" do
      expression = "func()"
      {:ok, ast} = Predicator.parse(expression)
      assert "func()" = StringVisitor.visit(ast)
    end

    test "handles function calls with single argument" do
      expression = "len(\"test\")"
      {:ok, ast} = Predicator.parse(expression)
      assert "len(\"test\")" = StringVisitor.visit(ast)
    end

    test "handles function calls with multiple arguments" do
      expression = "max(1, 2)"
      {:ok, ast} = Predicator.parse(expression)
      assert "max(1, 2)" = StringVisitor.visit(ast)
    end

    test "handles nested function calls" do
      expression = "len(upper(\"hello\"))"
      {:ok, ast} = Predicator.parse(expression)
      assert "len(upper(\"hello\"))" = StringVisitor.visit(ast)
    end

    test "handles function calls in logical expressions" do
      expression = "len(name) > 5 AND upper(role) = \"ADMIN\""
      {:ok, ast} = Predicator.parse(expression)
      result = StringVisitor.visit(ast)

      # Should reconstruct the expression (may have different formatting)
      assert result =~ "len(name)"
      assert result =~ "upper(role)"
      assert result =~ "\"ADMIN\""
    end

    test "handles function calls with complex arguments" do
      expression = "func([1, 2, 3], \"test\", true)"
      {:ok, ast} = Predicator.parse(expression)
      result = StringVisitor.visit(ast)
      assert result =~ "func("
      assert result =~ "[1, 2, 3]"
      assert result =~ "\"test\""
      assert result =~ "true"
    end

    test "handles function calls with list arguments" do
      expression = "func([\"a\", \"b\", \"c\"])"
      {:ok, ast} = Predicator.parse(expression)
      result = StringVisitor.visit(ast)
      assert result =~ "func("
      assert result =~ "[\"a\", \"b\", \"c\"]"
    end

    test "handles very long expressions" do
      # Create a long expression with many function calls
      long_expr = Enum.map_join(1..10, " AND ", fn i -> "func#{i}(\"arg#{i}\")" end)

      {:ok, ast} = Predicator.parse(long_expr)
      result = StringVisitor.visit(ast)

      # Should contain all function calls
      for i <- 1..10 do
        assert result =~ "func#{i}("
        assert result =~ "\"arg#{i}\""
      end
    end

    test "handles special characters in strings" do
      expression = "len(\"hello\\nworld\\t!\")"
      {:ok, ast} = Predicator.parse(expression)
      result = StringVisitor.visit(ast)
      assert result =~ "len("
      # The string should be properly escaped
      assert result =~ "hello"
      assert result =~ "world"
    end

    test "handles numbers with different formats" do
      expressions = [
        "func(42)",
        "func(0)"
      ]

      for expr <- expressions do
        {:ok, ast} = Predicator.parse(expr)
        result = StringVisitor.visit(ast)
        assert result =~ "func("
      end
    end

    test "handles deeply nested parentheses with functions" do
      expression = "((len(\"test\") > 3) AND (max(1, 2) = 2))"
      {:ok, ast} = Predicator.parse(expression)
      result = StringVisitor.visit(ast)

      assert result =~ "len(\"test\")"
      assert result =~ "max(1, 2)"
    end

    test "handles mixed operators with functions" do
      expression = "len(name) > 2 AND max(age, 18) >= 18 OR min(score, 100) <= 50"
      {:ok, ast} = Predicator.parse(expression)
      result = StringVisitor.visit(ast)

      assert result =~ "len(name)"
      assert result =~ "max(age, 18)"
      assert result =~ "min(score, 100)"
    end
  end

  describe "format preservation" do
    test "preserves function call structure in complex expressions" do
      expression = "NOT (len(upper(name)) > 5 AND role IN [\"admin\", \"user\"])"
      {:ok, ast} = Predicator.parse(expression)
      result = StringVisitor.visit(ast)

      # Should preserve the logical structure
      assert result =~ "len("
      assert result =~ "upper("
      assert result =~ "name"
    end

    test "handles function calls in membership operations" do
      expression = "upper(role) IN [\"ADMIN\", \"USER\"]"
      {:ok, ast} = Predicator.parse(expression)
      result = StringVisitor.visit(ast)

      assert result =~ "upper(role)"
      assert result =~ "IN"
      assert result =~ "[\"ADMIN\", \"USER\"]"
    end

    test "handles function calls in contains operations" do
      expression = "[\"admin\", \"user\"] CONTAINS lower(role)"
      {:ok, ast} = Predicator.parse(expression)
      result = StringVisitor.visit(ast)

      assert result =~ "lower(role)"
      assert result =~ "CONTAINS"
    end
  end
end
