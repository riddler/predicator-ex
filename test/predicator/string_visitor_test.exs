defmodule Predicator.StringVisitorTest do
  use ExUnit.Case, async: true

  alias Predicator.StringVisitor

  doctest Predicator.StringVisitor

  describe "visit/2 - literal nodes" do
    test "converts integer literal to string" do
      ast = {:literal, 42}
      result = StringVisitor.visit(ast, [])

      assert result == "42"
    end

    test "converts negative integer literal to string" do
      ast = {:literal, -15}
      result = StringVisitor.visit(ast, [])

      assert result == "-15"
    end

    test "converts zero to string" do
      ast = {:literal, 0}
      result = StringVisitor.visit(ast, [])

      assert result == "0"
    end

    test "converts boolean true literal to string" do
      ast = {:literal, true}
      result = StringVisitor.visit(ast, [])

      assert result == "true"
    end

    test "converts boolean false literal to string" do
      ast = {:literal, false}
      result = StringVisitor.visit(ast, [])

      assert result == "false"
    end

    test "converts string literal with quotes" do
      ast = {:literal, "hello"}
      result = StringVisitor.visit(ast, [])

      assert result == ~s("hello")
    end

    test "converts empty string literal" do
      ast = {:literal, ""}
      result = StringVisitor.visit(ast, [])

      assert result == ~s("")
    end

    test "converts string with escaped quotes" do
      ast = {:literal, "hello \"world\""}
      result = StringVisitor.visit(ast, [])

      assert result == ~s("hello \\"world\\"")
    end

    test "converts string with special characters" do
      ast = {:literal, "line1\nline2\ttab"}
      result = StringVisitor.visit(ast, [])

      assert result == "\"line1\nline2\ttab\""
    end

    test "converts list literal" do
      ast = {:literal, [1, 2, 3]}
      result = StringVisitor.visit(ast, [])

      assert result == "[1, 2, 3]"
    end

    test "converts mixed type list literal" do
      ast = {:literal, [1, "hello", true]}
      result = StringVisitor.visit(ast, [])

      assert result == ~s([1, "hello", true])
    end

    test "converts empty list literal" do
      ast = {:literal, []}
      result = StringVisitor.visit(ast, [])

      assert result == "[]"
    end
  end

  describe "visit/2 - identifier nodes" do
    test "converts simple identifier" do
      ast = {:identifier, "score"}
      result = StringVisitor.visit(ast, [])

      assert result == "score"
    end

    test "converts identifier with underscores" do
      ast = {:identifier, "user_age"}
      result = StringVisitor.visit(ast, [])

      assert result == "user_age"
    end

    test "converts identifier with numbers" do
      ast = {:identifier, "var123"}
      result = StringVisitor.visit(ast, [])

      assert result == "var123"
    end
  end

  describe "visit/2 - comparison nodes" do
    test "converts greater than comparison" do
      ast = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      result = StringVisitor.visit(ast, [])

      assert result == "score > 85"
    end

    test "converts less than comparison" do
      ast = {:comparison, :lt, {:identifier, "age"}, {:literal, 18}}
      result = StringVisitor.visit(ast, [])

      assert result == "age < 18"
    end

    test "converts greater than or equal comparison" do
      ast = {:comparison, :gte, {:identifier, "score"}, {:literal, 85}}
      result = StringVisitor.visit(ast, [])

      assert result == "score >= 85"
    end

    test "converts less than or equal comparison" do
      ast = {:comparison, :lte, {:identifier, "age"}, {:literal, 65}}
      result = StringVisitor.visit(ast, [])

      assert result == "age <= 65"
    end

    test "converts equality comparison" do
      ast = {:comparison, :eq, {:identifier, "name"}, {:literal, "John"}}
      result = StringVisitor.visit(ast, [])

      assert result == ~s(name = "John")
    end

    test "converts not equal comparison" do
      ast = {:comparison, :ne, {:identifier, "status"}, {:literal, "inactive"}}
      result = StringVisitor.visit(ast, [])

      assert result == ~s(status != "inactive")
    end

    test "converts literal-to-literal comparison" do
      ast = {:comparison, :gt, {:literal, 10}, {:literal, 5}}
      result = StringVisitor.visit(ast, [])

      assert result == "10 > 5"
    end

    test "converts identifier-to-identifier comparison" do
      ast = {:comparison, :eq, {:identifier, "score"}, {:identifier, "threshold"}}
      result = StringVisitor.visit(ast, [])

      assert result == "score = threshold"
    end

    test "converts boolean comparisons" do
      ast = {:comparison, :eq, {:identifier, "active"}, {:literal, true}}
      result = StringVisitor.visit(ast, [])

      assert result == "active = true"
    end
  end

  describe "visit/2 - spacing options" do
    test "normal spacing (default)" do
      ast = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      result = StringVisitor.visit(ast, spacing: :normal)

      assert result == "score > 85"
    end

    test "compact spacing" do
      ast = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      result = StringVisitor.visit(ast, spacing: :compact)

      assert result == "score>85"
    end

    test "verbose spacing" do
      ast = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      result = StringVisitor.visit(ast, spacing: :verbose)

      assert result == "score  >  85"
    end

    test "spacing affects all operators" do
      operators_and_expected = [
        {:gt, "score  >  85"},
        {:lt, "score  <  85"},
        {:gte, "score  >=  85"},
        {:lte, "score  <=  85"},
        {:eq, "score  =  85"},
        {:ne, "score  !=  85"}
      ]

      for {op, expected} <- operators_and_expected do
        ast = {:comparison, op, {:identifier, "score"}, {:literal, 85}}
        result = StringVisitor.visit(ast, spacing: :verbose)
        assert result == expected
      end
    end
  end

  describe "visit/2 - parentheses options" do
    test "minimal parentheses (default)" do
      ast = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      result = StringVisitor.visit(ast, parentheses: :minimal)

      assert result == "score > 85"
    end

    test "explicit parentheses" do
      ast = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      result = StringVisitor.visit(ast, parentheses: :explicit)

      assert result == "(score > 85)"
    end

    test "no parentheses" do
      ast = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      result = StringVisitor.visit(ast, parentheses: :none)

      assert result == "score > 85"
    end
  end

  describe "visit/2 - combined options" do
    test "explicit parentheses with compact spacing" do
      ast = {:comparison, :gte, {:identifier, "age"}, {:literal, 18}}
      result = StringVisitor.visit(ast, parentheses: :explicit, spacing: :compact)

      assert result == "(age>=18)"
    end

    test "verbose spacing with explicit parentheses" do
      ast = {:comparison, :ne, {:identifier, "name"}, {:literal, "test"}}
      result = StringVisitor.visit(ast, parentheses: :explicit, spacing: :verbose)

      assert result == "(name  !=  \"test\")"
    end
  end

  describe "visit/2 - integration with parser output" do
    test "round-trip with simple expression" do
      alias Predicator.{Lexer, Parser}

      original = "score > 85"
      {:ok, tokens} = Lexer.tokenize(original)
      {:ok, ast} = Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])

      assert result == original
    end

    test "round-trip with string comparison" do
      alias Predicator.{Lexer, Parser}

      original = ~s(name = "John")
      {:ok, tokens} = Lexer.tokenize(original)
      {:ok, ast} = Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])

      assert result == original
    end

    test "round-trip with boolean comparison" do
      alias Predicator.{Lexer, Parser}

      original = "active = true"
      {:ok, tokens} = Lexer.tokenize(original)
      {:ok, ast} = Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])

      assert result == original
    end

    test "round-trip with all comparison operators" do
      alias Predicator.{Lexer, Parser}

      expressions = [
        "x > 5",
        "x < 5",
        "x >= 5",
        "x <= 5",
        "x = 5",
        "x != 5"
      ]

      for original <- expressions do
        {:ok, tokens} = Lexer.tokenize(original)
        {:ok, ast} = Parser.parse(tokens)
        result = StringVisitor.visit(ast, [])

        assert result == original, "Failed round-trip for: #{original}"
      end
    end

    test "handles parenthesized expressions" do
      alias Predicator.{Lexer, Parser}

      # Note: Parser removes unnecessary parentheses from AST
      original = "(score > 85)"
      {:ok, tokens} = Lexer.tokenize(original)
      {:ok, ast} = Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])
      # Parentheses are removed by parser since they're not needed
      assert result == "score > 85"

      # But we can add them back with explicit mode
      result_explicit = StringVisitor.visit(ast, parentheses: :explicit)
      assert result_explicit == "(score > 85)"
    end

    test "handles complex expressions with whitespace normalization" do
      alias Predicator.{Lexer, Parser}

      original_with_extra_spaces = "  score   >    85  "
      {:ok, tokens} = Lexer.tokenize(original_with_extra_spaces)
      {:ok, ast} = Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])

      # StringVisitor normalizes spacing
      assert result == "score > 85"
    end
  end

  describe "visit/2 - edge cases" do
    test "handles strings with quotes that need escaping" do
      ast = {:comparison, :eq, {:identifier, "message"}, {:literal, ~s(He said "hello")}}
      result = StringVisitor.visit(ast, [])

      assert result == ~s(message = "He said \\"hello\\"")
    end

    test "handles empty string comparisons" do
      ast = {:comparison, :ne, {:identifier, "name"}, {:literal, ""}}
      result = StringVisitor.visit(ast, [])

      assert result == ~s(name != "")
    end

    test "handles zero comparisons" do
      ast = {:comparison, :gt, {:identifier, "count"}, {:literal, 0}}
      result = StringVisitor.visit(ast, [])

      assert result == "count > 0"
    end

    test "handles negative number comparisons" do
      ast = {:comparison, :lt, {:identifier, "temp"}, {:literal, -10}}
      result = StringVisitor.visit(ast, [])

      assert result == "temp < -10"
    end
  end
end
