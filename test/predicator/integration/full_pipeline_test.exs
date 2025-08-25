defmodule Predicator.IntegrationTest do
  use ExUnit.Case, async: true

  alias Predicator.{Compiler, Evaluator, Lexer, Parser}

  describe "full pipeline integration" do
    test "string -> tokens -> ast -> instructions -> evaluation" do
      input = "score > 85"
      context = %{"score" => 90}

      # Lex
      {:ok, tokens} = Lexer.tokenize(input)

      # Parse
      {:ok, ast} = Parser.parse(tokens)

      # Compile
      instructions = Compiler.to_instructions(ast)

      assert instructions == [
               ["load", "score"],
               ["lit", 85],
               ["compare", "GT"]
             ]

      # Evaluate
      result = Evaluator.evaluate!(instructions, context)
      assert result == true
    end

    test "complex expression with parentheses" do
      input = "(age >= 18)"
      context = %{"age" => 21}

      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)
      instructions = Compiler.to_instructions(ast)

      assert instructions == [
               ["load", "age"],
               ["lit", 18],
               ["compare", "GTE"]
             ]

      result = Evaluator.evaluate!(instructions, context)
      assert result == true
    end

    test "string comparison" do
      input = "name = \"John\""
      context = %{"name" => "John"}

      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)
      instructions = Compiler.to_instructions(ast)

      assert instructions == [
               ["load", "name"],
               ["lit", "John"],
               ["compare", "EQ"]
             ]

      result = Evaluator.evaluate!(instructions, context)
      assert result == true
    end

    test "boolean comparison" do
      input = "active = true"
      context = %{"active" => true}

      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)
      instructions = Compiler.to_instructions(ast)

      assert instructions == [
               ["load", "active"],
               ["lit", true],
               ["compare", "EQ"]
             ]

      result = Evaluator.evaluate!(instructions, context)
      assert result == true
    end

    test "not equal comparison evaluates to false" do
      input = "status != \"active\""
      context = %{"status" => "active"}

      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)
      instructions = Compiler.to_instructions(ast)

      result = Evaluator.evaluate!(instructions, context)
      assert result == false
    end

    test "all comparison operators work correctly" do
      test_cases = [
        {"x > 5", %{"x" => 10}, true},
        {"x > 5", %{"x" => 3}, false},
        {"x < 5", %{"x" => 3}, true},
        {"x < 5", %{"x" => 10}, false},
        {"x >= 5", %{"x" => 5}, true},
        {"x >= 5", %{"x" => 4}, false},
        {"x <= 5", %{"x" => 5}, true},
        {"x <= 5", %{"x" => 6}, false},
        {"x = 5", %{"x" => 5}, true},
        {"x = 5", %{"x" => 6}, false},
        {"x != 5", %{"x" => 6}, true},
        {"x != 5", %{"x" => 5}, false}
      ]

      for {input, context, expected} <- test_cases do
        {:ok, tokens} = Lexer.tokenize(input)
        {:ok, ast} = Parser.parse(tokens)
        instructions = Compiler.to_instructions(ast)
        result = Evaluator.evaluate!(instructions, context)

        assert result == expected, "Failed for input: #{input} with context: #{inspect(context)}"
      end
    end

    test "handles missing context keys" do
      input = "missing_key > 5"
      context = %{}

      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)
      instructions = Compiler.to_instructions(ast)

      _result = Evaluator.evaluate!(instructions, context)
      result = Evaluator.evaluate(instructions, context)
      assert result == :undefined
    end

    test "nested context access integration" do
      input = "user.name.first = \"John\""
      context = %{"user" => %{"name" => %{"first" => "John", "last" => "Doe"}, "age" => 47}}

      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)
      instructions = Compiler.to_instructions(ast)

      assert instructions == [
               ["load", "user"],
               ["access", "name"],
               ["access", "first"],
               ["lit", "John"],
               ["compare", "EQ"]
             ]

      result = Evaluator.evaluate!(instructions, context)
      assert result == true
    end

    test "nested context access with numeric comparison" do
      input = "user.age > 18"
      context = %{"user" => %{"name" => "John", "age" => 47}}

      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)
      instructions = Compiler.to_instructions(ast)

      assert instructions == [
               ["load", "user"],
               ["access", "age"],
               ["lit", 18],
               ["compare", "GT"]
             ]

      result = Evaluator.evaluate!(instructions, context)
      assert result == true
    end

    test "nested context access with missing path" do
      input = "user.profile.name = \"John\""
      context = %{"user" => %{"name" => "John", "age" => 47}}

      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)
      instructions = Compiler.to_instructions(ast)

      assert instructions == [
               ["load", "user"],
               ["access", "profile"],
               ["access", "name"],
               ["lit", "John"],
               ["compare", "EQ"]
             ]

      result = Evaluator.evaluate!(instructions, context)
      assert result == :undefined
    end

    test "nested context access in complex expressions" do
      input = "user.name.first = \"John\" AND user.age >= 18"
      context = %{"user" => %{"name" => %{"first" => "John"}, "age" => 47}}

      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)
      instructions = Compiler.to_instructions(ast)

      result = Evaluator.evaluate!(instructions, context)
      assert result == true
    end

    test "mixed nested and simple context access" do
      input = "score > 85 AND user.name.first = \"John\""
      context = %{"score" => 90, "user" => %{"name" => %{"first" => "John"}}}

      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)
      instructions = Compiler.to_instructions(ast)

      result = Evaluator.evaluate!(instructions, context)
      assert result == true
    end
  end
end
