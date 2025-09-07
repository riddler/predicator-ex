defmodule Predicator.ParserEdgeCasesTest do
  use ExUnit.Case

  alias Predicator.{Lexer, Parser}

  describe "parser error handling" do
    test "handles empty token list" do
      {:error, message, line, col} = Parser.parse([])
      assert message == "Unexpected end of input"
      assert line == 1
      assert col == 1
    end

    test "handles unexpected end of input" do
      {:ok, tokens} = Lexer.tokenize("x +")
      {:error, message, line, _col} = Parser.parse(tokens)
      assert String.contains?(message, "end of input")
      assert line == 1
    end

    test "handles unexpected token" do
      {:ok, tokens} = Lexer.tokenize("(")
      {:error, message, line, col} = Parser.parse(tokens)
      assert String.contains?(message, "Expected")
      assert line == 1
      assert col > 0
    end

    test "handles missing closing paren" do
      {:ok, tokens} = Lexer.tokenize("(x")
      {:error, message, line, _col} = Parser.parse(tokens)
      assert String.contains?(message, "Expected ')' but found end of input")
      assert line == 1
    end

    test "handles missing closing bracket in list" do
      {:ok, tokens} = Lexer.tokenize("[1, 2")
      {:error, message, line, _col} = Parser.parse(tokens)
      assert String.contains?(message, "Expected")
      assert line == 1
    end

    test "handles missing closing brace in object" do
      {:ok, tokens} = Lexer.tokenize("{name: 'test'")
      {:error, message, line, _col} = Parser.parse(tokens)
      assert String.contains?(message, "Expected")
      assert line == 1
    end

    test "handles invalid object key" do
      {:ok, tokens} = Lexer.tokenize("{123: 'value'}")
      {:error, message, line, _col} = Parser.parse(tokens)
      assert String.contains?(message, "Expected identifier or string for object key")
      assert line == 1
    end

    test "handles missing colon in object" do
      {:ok, tokens} = Lexer.tokenize("{name 'test'}")
      {:error, message, line, _col} = Parser.parse(tokens)
      assert String.contains?(message, "Expected ':' after object key")
      assert line == 1
    end

    test "handles missing value after colon in object" do
      {:ok, tokens} = Lexer.tokenize("{name:}")
      {:error, message, line, _col} = Parser.parse(tokens)
      assert String.contains?(message, "Expected")
      assert line == 1
    end
  end

  describe "primary expression parsing" do
    test "parses boolean literals" do
      {:ok, tokens} = Lexer.tokenize("true")
      {:ok, ast} = Parser.parse(tokens)
      assert ast == {:literal, true}
    end

    test "parses date literals" do
      {:ok, tokens} = Lexer.tokenize("#2024-01-15#")
      {:ok, ast} = Parser.parse(tokens)
      assert match?({:literal, %Date{}}, ast)
    end

    test "parses datetime literals" do
      {:ok, tokens} = Lexer.tokenize("#2024-01-15T10:30:00Z#")
      {:ok, ast} = Parser.parse(tokens)
      assert match?({:literal, %DateTime{}}, ast)
    end

    test "parses float literals" do
      {:ok, tokens} = Lexer.tokenize("3.14")
      {:ok, ast} = Parser.parse(tokens)
      assert ast == {:literal, 3.14}
    end

    test "parses string literals with quote types" do
      {:ok, tokens} = Lexer.tokenize("'single quoted'")
      {:ok, ast} = Parser.parse(tokens)
      assert ast == {:string_literal, "single quoted", :single}
    end
  end

  describe "list parsing edge cases" do
    test "parses empty list" do
      {:ok, tokens} = Lexer.tokenize("[]")
      {:ok, ast} = Parser.parse(tokens)
      assert ast == {:list, []}
    end

    test "parses single element list" do
      {:ok, tokens} = Lexer.tokenize("[42]")
      {:ok, ast} = Parser.parse(tokens)
      assert ast == {:list, [{:literal, 42}]}
    end

    test "parses nested lists" do
      {:ok, tokens} = Lexer.tokenize("[[1, 2], [3, 4]]")
      {:ok, ast} = Parser.parse(tokens)

      expected =
        {:list,
         [
           {:list, [{:literal, 1}, {:literal, 2}]},
           {:list, [{:literal, 3}, {:literal, 4}]}
         ]}

      assert ast == expected
    end
  end

  describe "object parsing edge cases" do
    test "parses empty object" do
      {:ok, tokens} = Lexer.tokenize("{}")
      {:ok, ast} = Parser.parse(tokens)
      assert ast == {:object, []}
    end

    test "parses object with identifier key" do
      {:ok, tokens} = Lexer.tokenize("{name: 'John'}")
      {:ok, ast} = Parser.parse(tokens)
      expected = {:object, [{{:identifier, "name"}, {:string_literal, "John", :single}}]}
      assert ast == expected
    end

    test "parses object with string key" do
      {:ok, tokens} = Lexer.tokenize("{\"key\": 'value'}")
      {:ok, ast} = Parser.parse(tokens)
      expected = {:object, [{{:string_literal, "key"}, {:string_literal, "value", :single}}]}
      assert ast == expected
    end

    test "parses nested objects" do
      {:ok, tokens} = Lexer.tokenize("{user: {name: 'John'}}")
      {:ok, ast} = Parser.parse(tokens)

      expected =
        {:object,
         [
           {{:identifier, "user"},
            {:object, [{{:identifier, "name"}, {:string_literal, "John", :single}}]}}
         ]}

      assert ast == expected
    end
  end

  describe "function call parsing" do
    test "parses function with no arguments" do
      {:ok, tokens} = Lexer.tokenize("len()")
      {:ok, ast} = Parser.parse(tokens)
      assert ast == {:function_call, "len", []}
    end

    test "parses function with single argument" do
      {:ok, tokens} = Lexer.tokenize("len('test')")
      {:ok, ast} = Parser.parse(tokens)
      expected = {:function_call, "len", [{:string_literal, "test", :single}]}
      assert ast == expected
    end

    test "parses function with multiple arguments" do
      {:ok, tokens} = Lexer.tokenize("max(1, 2, 3)")
      {:ok, ast} = Parser.parse(tokens)
      expected = {:function_call, "max", [{:literal, 1}, {:literal, 2}, {:literal, 3}]}
      assert ast == expected
    end

    test "parses qualified function calls" do
      {:ok, tokens} = Lexer.tokenize("Math.pow(2, 3)")
      {:ok, ast} = Parser.parse(tokens)
      expected = {:function_call, "Math.pow", [{:literal, 2}, {:literal, 3}]}
      assert ast == expected
    end
  end

  describe "bracket access parsing" do
    test "parses simple bracket access" do
      {:ok, tokens} = Lexer.tokenize("arr[0]")
      {:ok, ast} = Parser.parse(tokens)
      expected = {:bracket_access, {:identifier, "arr"}, {:literal, 0}}
      assert ast == expected
    end

    test "parses nested bracket access" do
      {:ok, tokens} = Lexer.tokenize("matrix[0][1]")
      {:ok, ast} = Parser.parse(tokens)

      expected =
        {:bracket_access, {:bracket_access, {:identifier, "matrix"}, {:literal, 0}},
         {:literal, 1}}

      assert ast == expected
    end

    test "parses bracket access with expression key" do
      {:ok, tokens} = Lexer.tokenize("arr[i + 1]")
      {:ok, ast} = Parser.parse(tokens)

      expected =
        {:bracket_access, {:identifier, "arr"},
         {:arithmetic, :add, {:identifier, "i"}, {:literal, 1}}}

      assert ast == expected
    end
  end

  describe "property access parsing" do
    test "parses simple property access" do
      {:ok, tokens} = Lexer.tokenize("obj.prop")
      {:ok, ast} = Parser.parse(tokens)
      expected = {:property_access, {:identifier, "obj"}, "prop"}
      assert ast == expected
    end

    test "parses chained property access" do
      {:ok, tokens} = Lexer.tokenize("user.profile.name")
      {:ok, ast} = Parser.parse(tokens)
      expected = {:property_access, {:property_access, {:identifier, "user"}, "profile"}, "name"}
      assert ast == expected
    end

    test "parses mixed bracket and property access" do
      {:ok, tokens} = Lexer.tokenize("users[0].name")
      {:ok, ast} = Parser.parse(tokens)

      expected =
        {:property_access, {:bracket_access, {:identifier, "users"}, {:literal, 0}}, "name"}

      assert ast == expected
    end
  end

  describe "unary expressions" do
    test "parses unary minus on numbers" do
      {:ok, tokens} = Lexer.tokenize("-42")
      {:ok, ast} = Parser.parse(tokens)
      assert ast == {:unary, :minus, {:literal, 42}}
    end

    test "parses unary bang on boolean" do
      {:ok, tokens} = Lexer.tokenize("!true")
      {:ok, ast} = Parser.parse(tokens)
      assert ast == {:logical_not, {:literal, true}}
    end

    test "parses nested unary expressions" do
      {:ok, tokens} = Lexer.tokenize("--x")
      {:ok, ast} = Parser.parse(tokens)
      expected = {:unary, :minus, {:unary, :minus, {:identifier, "x"}}}
      assert ast == expected
    end
  end

  describe "complex nested expressions" do
    test "parses function calls in arithmetic" do
      {:ok, tokens} = Lexer.tokenize("len(name) + 5")
      {:ok, ast} = Parser.parse(tokens)

      expected =
        {:arithmetic, :add, {:function_call, "len", [{:identifier, "name"}]}, {:literal, 5}}

      assert ast == expected
    end

    test "parses object access in comparisons" do
      {:ok, tokens} = Lexer.tokenize("user.age >= 18")
      {:ok, ast} = Parser.parse(tokens)

      expected =
        {:comparison, :gte, {:property_access, {:identifier, "user"}, "age"}, {:literal, 18}}

      assert ast == expected
    end

    test "parses list membership with complex expressions" do
      {:ok, tokens} = Lexer.tokenize("user.role in ['admin', 'manager']")
      {:ok, ast} = Parser.parse(tokens)

      expected =
        {:membership, :in, {:property_access, {:identifier, "user"}, "role"},
         {:list, [{:string_literal, "admin", :single}, {:string_literal, "manager", :single}]}}

      assert ast == expected
    end
  end
end
