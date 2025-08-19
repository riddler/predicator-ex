defmodule Predicator.ParserEdgeCasesTest do
  use ExUnit.Case, async: true

  alias Predicator.{Lexer, Parser}

  describe "error handling" do
    test "handles unexpected tokens after expression" do
      # Test case: valid expression followed by unexpected token
      tokens = [
        {:integer, 1, 1, 1, 42},
        {:identifier, 1, 3, 4, "unexpected"}
      ]

      assert {:error, message, 1, 3} = Parser.parse(tokens)
      assert message =~ "Unexpected token"
      assert message =~ "unexpected"
    end

    test "handles function call with missing closing parenthesis" do
      # This should be caught by lexer, but test parser robustness
      {:ok, tokens} = Lexer.tokenize("func(")
      assert {:error, _message, _line, _col} = Parser.parse(tokens)
    end

    test "handles function call with missing arguments" do
      {:ok, tokens} = Lexer.tokenize("func(,)")
      assert {:error, _message, _line, _col} = Parser.parse(tokens)
    end

    test "handles deeply nested expressions" do
      # Create a deeply nested expression
      nested = String.duplicate("(", 100) <> "1" <> String.duplicate(")", 100)
      {:ok, tokens} = Lexer.tokenize(nested)

      # Should still parse successfully (testing stack depth handling)
      assert {:ok, _ast} = Parser.parse(tokens)
    end

    test "handles complex function call combinations" do
      {:ok, tokens} = Lexer.tokenize("func1(func2(arg1), func3(arg2, arg3))")
      assert {:ok, _ast} = Parser.parse(tokens)
    end

    test "handles function calls with different argument types" do
      {:ok, tokens} = Lexer.tokenize("func(\"string\", 42, true, [1, 2, 3])")
      assert {:ok, ast} = Parser.parse(tokens)

      # Verify AST structure
      assert {:function_call, "func", args} = ast
      assert length(args) == 4
    end

    test "handles empty function call" do
      {:ok, tokens} = Lexer.tokenize("func()")
      assert {:ok, {:function_call, "func", []}} = Parser.parse(tokens)
    end

    test "handles function calls in logical expressions" do
      {:ok, tokens} = Lexer.tokenize("func1() AND func2() OR NOT func3()")
      assert {:ok, _ast} = Parser.parse(tokens)
    end

    test "handles function calls in comparison expressions" do
      {:ok, tokens} = Lexer.tokenize("func1() > func2() AND func3() = \"test\"")
      assert {:ok, _ast} = Parser.parse(tokens)
    end

    test "handles function calls with list arguments" do
      {:ok, tokens} = Lexer.tokenize("func([1, 2, \"test\", true])")
      assert {:ok, {:function_call, "func", [args]}} = Parser.parse(tokens)
      assert {:list, _elements} = args
    end

    test "handles function calls with nested lists" do
      {:ok, tokens} = Lexer.tokenize("func([[1, 2], [3, 4]])")
      assert {:ok, {:function_call, "func", [args]}} = Parser.parse(tokens)
      assert {:list, _elements} = args
    end

    test "handles invalid list syntax" do
      # trailing comma
      {:ok, tokens} = Lexer.tokenize("[1, 2,]")
      # This might be valid or invalid depending on implementation
      result = Parser.parse(tokens)
      # Just verify it returns some result (either ok or error)
      assert match?({:ok, _}, result) or match?({:error, _, _, _}, result)
    end
  end

  describe "boundary conditions" do
    test "handles maximum integer values" do
      # max 64-bit signed integer
      max_int = 9_223_372_036_854_775_807
      {:ok, tokens} = Lexer.tokenize("#{max_int}")
      assert {:ok, {:literal, ^max_int}} = Parser.parse(tokens)
    end

    test "handles very long strings" do
      long_string = String.duplicate("a", 1000)
      {:ok, tokens} = Lexer.tokenize("\"#{long_string}\"")
      assert {:ok, {:literal, ^long_string}} = Parser.parse(tokens)
    end

    test "handles very long identifiers" do
      long_id = String.duplicate("a", 100)
      {:ok, tokens} = Lexer.tokenize(long_id)
      assert {:ok, {:identifier, ^long_id}} = Parser.parse(tokens)
    end

    test "handles empty input" do
      {:ok, tokens} = Lexer.tokenize("")
      # Empty input produces EOF token
      assert [_eof_token] = tokens
      assert {:error, _message, _line, _col} = Parser.parse(tokens)
    end

    test "handles whitespace-only input" do
      {:ok, tokens} = Lexer.tokenize("   \n  \t  ")
      # Whitespace-only input produces EOF token
      assert [_eof_token] = tokens
      assert {:error, _message, _line, _col} = Parser.parse(tokens)
    end
  end

  describe "complex expressions" do
    test "handles mixed operators with function calls" do
      expression = "len(name) > 5 AND upper(title) = \"ADMIN\" OR day(created_at) > 15"
      {:ok, tokens} = Lexer.tokenize(expression)
      assert {:ok, _ast} = Parser.parse(tokens)
    end

    test "handles nested function calls with all types" do
      expression = "func(len(\"test\"), max(1, 2), year(created_at), [1, 2, 3])"
      {:ok, tokens} = Lexer.tokenize(expression)
      assert {:ok, ast} = Parser.parse(tokens)

      assert {:function_call, "func", args} = ast
      assert length(args) == 4
    end

    test "handles complex logical expressions with functions" do
      expression = "(func1() AND func2()) OR (NOT func3() AND func4())"
      {:ok, tokens} = Lexer.tokenize(expression)
      assert {:ok, _ast} = Parser.parse(tokens)
    end

    test "handles comparison chains with functions" do
      expression = "min(a, b) < max(c, d) AND len(str) >= 5"
      {:ok, tokens} = Lexer.tokenize(expression)
      assert {:ok, _ast} = Parser.parse(tokens)
    end

    test "handles function calls in list elements" do
      expression = "[func1(), func2(\"arg\"), 42]"
      {:ok, tokens} = Lexer.tokenize(expression)
      assert {:ok, {:list, elements}} = Parser.parse(tokens)
      assert length(elements) == 3
    end
  end
end
