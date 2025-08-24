defmodule Predicator.CompilerTest do
  use ExUnit.Case, async: true

  alias Predicator.Compiler

  doctest Predicator.Compiler

  describe "to_instructions/2" do
    test "compiles literal to instructions" do
      ast = {:literal, 42}
      result = Compiler.to_instructions(ast)

      assert result == [["lit", 42]]
    end

    test "compiles identifier to instructions" do
      ast = {:identifier, "score"}
      result = Compiler.to_instructions(ast)

      assert result == [["load", "score"]]
    end

    test "compiles comparison to instructions" do
      ast = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      result = Compiler.to_instructions(ast)

      assert result == [
               ["load", "score"],
               ["lit", 85],
               ["compare", "GT"]
             ]
    end

    test "works with all comparison operators" do
      operators_map = %{
        :gt => "GT",
        :lt => "LT",
        :gte => "GTE",
        :lte => "LTE",
        :eq => "EQ"
      }

      for {ast_op, instruction_op} <- operators_map do
        ast = {:comparison, ast_op, {:identifier, "x"}, {:literal, 1}}
        result = Compiler.to_instructions(ast)

        assert result == [
                 ["load", "x"],
                 ["lit", 1],
                 ["compare", instruction_op]
               ]
      end
    end

    test "works with equality operators" do
      equality_operators = %{
        :equal_equal => "EQ",
        :ne => "NE"
      }

      for {ast_op, instruction_op} <- equality_operators do
        ast = {:equality, ast_op, {:identifier, "x"}, {:literal, 1}}
        result = Compiler.to_instructions(ast)

        assert result == [
                 ["load", "x"],
                 ["lit", 1],
                 ["compare", instruction_op]
               ]
      end
    end

    test "compiles with opts parameter" do
      ast = {:literal, 42}
      result = Compiler.to_instructions(ast, some_option: true)

      assert result == [["lit", 42]]
    end
  end

  describe "integration with full pipeline" do
    test "compiles from string to instructions via lexer and parser" do
      alias Predicator.{Lexer, Parser}

      input = "user_age >= 21"
      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)

      result = Compiler.to_instructions(ast)

      assert result == [
               ["load", "user_age"],
               ["lit", 21],
               ["compare", "GTE"]
             ]
    end

    test "compiles complex expressions" do
      alias Predicator.{Lexer, Parser}

      input = "(status != \"inactive\")"
      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)

      result = Compiler.to_instructions(ast)

      assert result == [
               ["load", "status"],
               ["lit", "inactive"],
               ["compare", "NE"]
             ]
    end
  end

  describe "to_string/2" do
    test "converts literal to string" do
      ast = {:literal, 42}
      result = Compiler.to_string(ast)

      assert result == "42"
    end

    test "converts identifier to string" do
      ast = {:identifier, "score"}
      result = Compiler.to_string(ast)

      assert result == "score"
    end

    test "converts comparison to string" do
      ast = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      result = Compiler.to_string(ast)

      assert result == "score > 85"
    end

    test "works with all comparison operators" do
      operators_map = %{
        :gt => ">",
        :lt => "<",
        :gte => ">=",
        :lte => "<=",
        :eq => "=",
        :ne => "!="
      }

      for {ast_op, string_op} <- operators_map do
        ast = {:comparison, ast_op, {:identifier, "x"}, {:literal, 5}}
        result = Compiler.to_string(ast)

        assert result == "x #{string_op} 5"
      end
    end

    test "converts with formatting options" do
      ast = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}

      # Test different spacing
      assert Compiler.to_string(ast, spacing: :normal) == "score > 85"
      assert Compiler.to_string(ast, spacing: :compact) == "score>85"
      assert Compiler.to_string(ast, spacing: :verbose) == "score  >  85"

      # Test different parentheses
      assert Compiler.to_string(ast, parentheses: :minimal) == "score > 85"
      assert Compiler.to_string(ast, parentheses: :explicit) == "(score > 85)"
      assert Compiler.to_string(ast, parentheses: :none) == "score > 85"
    end

    test "converts string literals correctly" do
      ast = {:comparison, :eq, {:identifier, "name"}, {:literal, "John"}}
      result = Compiler.to_string(ast)

      assert result == ~s(name = "John")
    end

    test "converts boolean literals correctly" do
      ast = {:comparison, :ne, {:identifier, "active"}, {:literal, true}}
      result = Compiler.to_string(ast)

      assert result == "active != true"
    end

    test "converts with opts parameter" do
      ast = {:literal, 42}
      result = Compiler.to_string(ast, spacing: :compact)

      assert result == "42"
    end
  end

  describe "round-trip compilation" do
    test "string -> AST -> string produces equivalent result" do
      alias Predicator.{Lexer, Parser}

      original_expressions = [
        "score > 85",
        "age >= 18",
        ~s(name = "John"),
        "active != true",
        "count <= 100",
        "status = \"active\""
      ]

      for original <- original_expressions do
        {:ok, tokens} = Lexer.tokenize(original)
        {:ok, ast} = Parser.parse(tokens)

        # Convert back to string
        result = Compiler.to_string(ast)

        # Should be equivalent (may have normalized spacing)
        assert result == original, "Round-trip failed for: #{original}"
      end
    end

    test "AST -> instructions -> evaluation works with string representation" do
      alias Predicator.Evaluator

      ast = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      context = %{"score" => 90}

      # Convert to instructions and evaluate
      instructions = Compiler.to_instructions(ast)
      result = Evaluator.evaluate!(instructions, context)
      assert result == true

      # Convert to string for debugging/display
      string_repr = Compiler.to_string(ast)
      assert string_repr == "score > 85"
    end
  end
end
