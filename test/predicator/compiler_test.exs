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
        :eq => "EQ",
        :ne => "NE"
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
end