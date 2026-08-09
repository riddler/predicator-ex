defmodule Predicator.CompilerTest do
  use ExUnit.Case, async: true

  alias Predicator.Compiler

  doctest Predicator.Compiler

  describe "to_instructions/2" do
    test "compiles literal to instructions" do
      ast = {:literal, 42, nil}
      result = Compiler.to_instructions(ast)

      assert result == [["lit", 42]]
    end

    test "compiles identifier to instructions" do
      ast = {:identifier, "score", nil}
      result = Compiler.to_instructions(ast)

      assert result == [["load", "score"]]
    end

    test "compiles comparison to instructions" do
      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
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
        ast = {:comparison, ast_op, {:identifier, "x", nil}, {:literal, 1, nil}, nil}
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
        :eq => "EQ",
        :ne => "NE"
      }

      for {ast_op, instruction_op} <- equality_operators do
        ast = {:comparison, ast_op, {:identifier, "x", nil}, {:literal, 1, nil}, nil}
        result = Compiler.to_instructions(ast)

        assert result == [
                 ["load", "x"],
                 ["lit", 1],
                 ["compare", instruction_op]
               ]
      end
    end

    test "compiles with opts parameter" do
      ast = {:literal, 42, nil}
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
      ast = {:literal, 42, nil}
      result = Compiler.to_string(ast)

      assert result == "42"
    end

    test "converts identifier to string" do
      ast = {:identifier, "score", nil}
      result = Compiler.to_string(ast)

      assert result == "score"
    end

    test "converts comparison to string" do
      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      result = Compiler.to_string(ast)

      assert result == "score > 85"
    end

    test "works with all comparison operators" do
      operators_map = %{
        :gt => ">",
        :lt => "<",
        :gte => ">=",
        :lte => "<=",
        :eq => "==",
        :ne => "!="
      }

      for {ast_op, string_op} <- operators_map do
        ast = {:comparison, ast_op, {:identifier, "x", nil}, {:literal, 5, nil}, nil}
        result = Compiler.to_string(ast)

        assert result == "x #{string_op} 5"
      end
    end

    test "converts with formatting options" do
      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}

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
      ast = {:comparison, :eq, {:identifier, "name", nil}, {:literal, "John", nil}, nil}
      result = Compiler.to_string(ast)

      assert result == ~s(name == "John")
    end

    test "converts boolean literals correctly" do
      ast = {:comparison, :ne, {:identifier, "active", nil}, {:literal, true, nil}, nil}
      result = Compiler.to_string(ast)

      assert result == "active != true"
    end

    test "converts with opts parameter" do
      ast = {:literal, 42, nil}
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
        ~s(name == "John"),
        "active != true",
        "count <= 100",
        "status == \"active\""
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

      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
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

  describe "to_instructions_with_positions/2" do
    test "returns the same instruction list to_instructions/2 does" do
      {:ok, ast} = Predicator.parse("score > 85 AND name == 'John'")

      {instructions, _positions} = Compiler.to_instructions_with_positions(ast)

      assert instructions == Compiler.to_instructions(ast)
    end

    test "maps each instruction index to its node's position" do
      {:ok, ast} = Predicator.parse("score > 85")

      assert Compiler.to_instructions_with_positions(ast) ==
               {[["load", "score"], ["lit", 85], ["compare", "GT"]],
                %{0 => {1, 1}, 1 => {1, 9}, 2 => {1, 7}}}
    end

    test "a nil-slotted AST compiles to an empty table" do
      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}

      assert Compiler.to_instructions_with_positions(ast) ==
               {[["load", "score"], ["lit", 85], ["compare", "GT"]], %{}}
    end

    test "passes visitor options through" do
      {:ok, ast} = Predicator.parse("42")

      assert Compiler.to_instructions_with_positions(ast, []) ==
               {[["lit", 42]], %{0 => {1, 1}}}
    end
  end

  describe "to_instructions_with_segment_positions/2" do
    test "returns the same instructions and positions to_instructions_with_positions/2 does, plus a segment table" do
      {:ok, ast} = Predicator.parse_program("a.b = 1")

      {instructions, positions} = Compiler.to_instructions_with_positions(ast)

      {segment_instructions, segment_positions, segment_table} =
        Compiler.to_instructions_with_segment_positions(ast)

      assert segment_instructions == instructions
      assert segment_positions == positions
      assert segment_table == %{3 => [{1, 1}, {1, 3}]}
    end
  end

  describe "to_instructions/2 and to_string/2 with a hand-built AST" do
    test "a positioned AST compiles and renders the same as a nil-slotted one" do
      {:ok, positioned} = Predicator.parse("score > 85")

      hand_built =
        {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}

      assert Compiler.to_instructions(positioned) == Compiler.to_instructions(hand_built)
      assert Compiler.to_string(positioned) == Compiler.to_string(hand_built)
      assert Compiler.to_string(positioned) == "score > 85"
    end
  end
end
