defmodule Predicator.Visitors.StringVisitorTest do
  use ExUnit.Case, async: true

  alias Predicator.Visitors.StringVisitor

  doctest Predicator.Visitors.StringVisitor

  describe "visit/2 - literal nodes" do
    test "converts integer literal to string" do
      ast = {:literal, 42, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "42"
    end

    test "converts negative integer literal to string" do
      ast = {:literal, -15, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "-15"
    end

    test "converts zero to string" do
      ast = {:literal, 0, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "0"
    end

    test "converts boolean true literal to string" do
      ast = {:literal, true, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "true"
    end

    test "converts boolean false literal to string" do
      ast = {:literal, false, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "false"
    end

    test "converts string literal with quotes" do
      ast = {:literal, "hello", nil}
      result = StringVisitor.visit(ast, [])

      assert result == ~s("hello")
    end

    test "converts empty string literal" do
      ast = {:literal, "", nil}
      result = StringVisitor.visit(ast, [])

      assert result == ~s("")
    end

    test "converts string with escaped quotes" do
      ast = {:literal, "hello \"world\"", nil}
      result = StringVisitor.visit(ast, [])

      assert result == ~s("hello \\"world\\"")
    end

    test "converts string with special characters" do
      ast = {:literal, "line1\nline2\ttab", nil}
      result = StringVisitor.visit(ast, [])

      assert result == "\"line1\nline2\ttab\""
    end

    test "converts list literal" do
      ast = {:literal, [1, 2, 3], nil}
      result = StringVisitor.visit(ast, [])

      assert result == "[1, 2, 3]"
    end

    test "converts mixed type list literal" do
      ast = {:literal, [1, "hello", true], nil}
      result = StringVisitor.visit(ast, [])

      assert result == ~s([1, "hello", true])
    end

    test "converts empty list literal" do
      ast = {:literal, [], nil}
      result = StringVisitor.visit(ast, [])

      assert result == "[]"
    end

    test "converts the undefined literal to string" do
      ast = {:literal, :undefined, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "undefined"
    end

    test "converts undefined nested in a list literal" do
      ast = {:literal, [1, :undefined], nil}
      result = StringVisitor.visit(ast, [])

      assert result == "[1, undefined]"
    end

    test "converts the null literal to string" do
      ast = {:literal, nil, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "null"
    end

    test "converts null nested in a list literal" do
      ast = {:literal, [1, nil], nil}
      result = StringVisitor.visit(ast, [])

      assert result == "[1, null]"
    end
  end

  describe "visit/2 - identifier nodes" do
    test "converts simple identifier" do
      ast = {:identifier, "score", nil}
      result = StringVisitor.visit(ast, [])

      assert result == "score"
    end

    test "converts identifier with underscores" do
      ast = {:identifier, "user_age", nil}
      result = StringVisitor.visit(ast, [])

      assert result == "user_age"
    end

    test "converts identifier with numbers" do
      ast = {:identifier, "var123", nil}
      result = StringVisitor.visit(ast, [])

      assert result == "var123"
    end
  end

  describe "visit/2 - comparison nodes" do
    test "converts greater than comparison" do
      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "score > 85"
    end

    test "converts less than comparison" do
      ast = {:comparison, :lt, {:identifier, "age", nil}, {:literal, 18, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "age < 18"
    end

    test "converts greater than or equal comparison" do
      ast = {:comparison, :gte, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "score >= 85"
    end

    test "converts less than or equal comparison" do
      ast = {:comparison, :lte, {:identifier, "age", nil}, {:literal, 65, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "age <= 65"
    end

    test "converts equality comparison" do
      ast = {:comparison, :eq, {:identifier, "name", nil}, {:literal, "John", nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == ~s(name == "John")
    end

    test "converts not equal comparison" do
      ast = {:comparison, :ne, {:identifier, "status", nil}, {:literal, "inactive", nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == ~s(status != "inactive")
    end

    test "converts literal-to-literal comparison" do
      ast = {:comparison, :gt, {:literal, 10, nil}, {:literal, 5, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "10 > 5"
    end

    test "converts identifier-to-identifier comparison" do
      ast = {:comparison, :eq, {:identifier, "score", nil}, {:identifier, "threshold", nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "score == threshold"
    end

    test "converts boolean comparisons" do
      ast = {:comparison, :eq, {:identifier, "active", nil}, {:literal, true, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "active == true"
    end
  end

  describe "visit/2 - spacing options" do
    test "normal spacing (default)" do
      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      result = StringVisitor.visit(ast, spacing: :normal)

      assert result == "score > 85"
    end

    test "compact spacing" do
      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      result = StringVisitor.visit(ast, spacing: :compact)

      assert result == "score>85"
    end

    test "verbose spacing" do
      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      result = StringVisitor.visit(ast, spacing: :verbose)

      assert result == "score  >  85"
    end

    test "spacing affects all operators" do
      operators_and_expected = [
        {:gt, "score  >  85"},
        {:lt, "score  <  85"},
        {:gte, "score  >=  85"},
        {:lte, "score  <=  85"},
        {:eq, "score  ==  85"},
        {:ne, "score  !=  85"}
      ]

      for {op, expected} <- operators_and_expected do
        ast = {:comparison, op, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
        result = StringVisitor.visit(ast, spacing: :verbose)
        assert result == expected
      end
    end
  end

  describe "visit/2 - parentheses options" do
    test "minimal parentheses (default)" do
      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      result = StringVisitor.visit(ast, parentheses: :minimal)

      assert result == "score > 85"
    end

    test "explicit parentheses" do
      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      result = StringVisitor.visit(ast, parentheses: :explicit)

      assert result == "(score > 85)"
    end

    test "no parentheses" do
      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      result = StringVisitor.visit(ast, parentheses: :none)

      assert result == "score > 85"
    end
  end

  describe "visit/2 - combined options" do
    test "explicit parentheses with compact spacing" do
      ast = {:comparison, :gte, {:identifier, "age", nil}, {:literal, 18, nil}, nil}
      result = StringVisitor.visit(ast, parentheses: :explicit, spacing: :compact)

      assert result == "(age>=18)"
    end

    test "verbose spacing with explicit parentheses" do
      ast = {:comparison, :ne, {:identifier, "name", nil}, {:literal, "test", nil}, nil}
      result = StringVisitor.visit(ast, parentheses: :explicit, spacing: :verbose)

      assert result == "(name  !=  \"test\")"
    end
  end

  describe "visit/2 - edge cases" do
    test "handles strings with quotes that need escaping" do
      ast =
        {:comparison, :eq, {:identifier, "message", nil}, {:literal, ~s(He said "hello"), nil},
         nil}

      result = StringVisitor.visit(ast, [])

      assert result == ~s(message == "He said \\"hello\\"")
    end

    test "handles empty string comparisons" do
      ast = {:comparison, :ne, {:identifier, "name", nil}, {:literal, "", nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == ~s(name != "")
    end

    test "handles zero comparisons" do
      ast = {:comparison, :gt, {:identifier, "count", nil}, {:literal, 0, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "count > 0"
    end

    test "handles negative number comparisons" do
      ast = {:comparison, :lt, {:identifier, "temp", nil}, {:literal, -10, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "temp < -10"
    end
  end

  describe "visit/2 - :eq renders as valid 4.0 source" do
    test "a hand-built :eq comparison renders \"==\"" do
      ast = {:comparison, :eq, {:identifier, "a", nil}, {:literal, 1, nil}, nil}

      assert StringVisitor.visit(ast, []) == "a == 1"
    end

    test "the rendered string re-parses to :equal_equal, not :eq" do
      ast = {:comparison, :eq, {:identifier, "a", nil}, {:literal, 1, nil}, nil}
      decompiled = StringVisitor.visit(ast, [])

      assert {:ok, {:comparison, :equal_equal, _left, _right, _pos}} =
               Predicator.parse(decompiled)
    end
  end
end
