defmodule Predicator.ParserBracketAccessTest do
  use ExUnit.Case, async: true

  import Predicator.ParseShape

  alias Predicator.Lexer

  describe "parse/1 - bracket access expressions" do
    test "parses simple bracket access" do
      {:ok, tokens} = Lexer.tokenize("user['name']")
      result = parse_positionless(tokens)

      expected_ast = {:bracket_access, {:identifier, "user"}, {:string_literal, "name", :single}}
      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with double quotes" do
      {:ok, tokens} = Lexer.tokenize("user[\"name\"]")
      result = parse_positionless(tokens)

      expected_ast = {:bracket_access, {:identifier, "user"}, {:string_literal, "name", :double}}
      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with numeric index" do
      {:ok, tokens} = Lexer.tokenize("items[0]")
      result = parse_positionless(tokens)

      expected_ast = {:bracket_access, {:identifier, "items"}, {:literal, 0}}
      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with variable index" do
      {:ok, tokens} = Lexer.tokenize("items[index]")
      result = parse_positionless(tokens)

      expected_ast = {:bracket_access, {:identifier, "items"}, {:identifier, "index"}}
      assert {:ok, ^expected_ast} = result
    end

    test "parses chained bracket access" do
      {:ok, tokens} = Lexer.tokenize("data['users'][0]['name']")
      result = parse_positionless(tokens)

      expected_ast = {
        :bracket_access,
        {:bracket_access,
         {:bracket_access, {:identifier, "data"}, {:string_literal, "users", :single}},
         {:literal, 0}},
        {:string_literal, "name", :single}
      }

      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with arithmetic expression as key" do
      {:ok, tokens} = Lexer.tokenize("items[i + 1]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access, {:identifier, "items"},
         {:arithmetic, :add, {:identifier, "i"}, {:literal, 1}}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses mixed dot and bracket access" do
      # Test the new property access parsing
      {:ok, tokens} = Lexer.tokenize("user.settings")
      result = parse_positionless(tokens)

      expected_ast = {:property_access, {:identifier, "user"}, "settings"}
      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access in comparison" do
      {:ok, tokens} = Lexer.tokenize("user['age'] > 18")
      result = parse_positionless(tokens)

      expected_ast =
        {:comparison, :gt,
         {:bracket_access, {:identifier, "user"}, {:string_literal, "age", :single}},
         {:literal, 18}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access in arithmetic" do
      {:ok, tokens} = Lexer.tokenize("limits[0] + limits[1]")
      result = parse_positionless(tokens)

      expected_ast =
        {:arithmetic, :add, {:bracket_access, {:identifier, "limits"}, {:literal, 0}},
         {:bracket_access, {:identifier, "limits"}, {:literal, 1}}}

      assert {:ok, ^expected_ast} = result
    end

    test "returns error for unclosed bracket" do
      {:ok, tokens} = Lexer.tokenize("user['name'")
      result = parse_positionless(tokens)

      assert {:error, "Expected ']' but found end of input", 1, 12, _span} = result
    end

    test "returns error for empty bracket access" do
      {:ok, tokens} = Lexer.tokenize("user[]")
      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found ']'",
              1, 6, _span} = result
    end

    test "returns error for missing closing bracket" do
      {:ok, tokens} = Lexer.tokenize("user['name' + 'suffix'")
      result = parse_positionless(tokens)

      assert {:error, "Expected ']' but found end of input", 1, 23, _span} = result
    end

    test "parses bracket access with boolean key" do
      {:ok, tokens} = Lexer.tokenize("config[true]")
      result = parse_positionless(tokens)

      expected_ast = {:bracket_access, {:identifier, "config"}, {:literal, true}}
      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with false key" do
      {:ok, tokens} = Lexer.tokenize("settings[false]")
      result = parse_positionless(tokens)

      expected_ast = {:bracket_access, {:identifier, "settings"}, {:literal, false}}
      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with function call key" do
      {:ok, tokens} = Lexer.tokenize("data[len('key')]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access, {:identifier, "data"},
         {:function_call, "len", [{:string_literal, "key", :single}]}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with nested brackets in key" do
      {:ok, tokens} = Lexer.tokenize("matrix[users[0]]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access, {:identifier, "matrix"},
         {:bracket_access, {:identifier, "users"}, {:literal, 0}}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with comparison expression key" do
      {:ok, tokens} = Lexer.tokenize("data[i > 5]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access, {:identifier, "data"},
         {:comparison, :gt, {:identifier, "i"}, {:literal, 5}}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with logical AND key" do
      {:ok, tokens} = Lexer.tokenize("cache[active AND valid]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access, {:identifier, "cache"},
         {:logical_and, {:identifier, "active"}, {:identifier, "valid"}}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with logical OR key" do
      {:ok, tokens} = Lexer.tokenize("flags[debug OR test]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access, {:identifier, "flags"},
         {:logical_or, {:identifier, "debug"}, {:identifier, "test"}}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with logical NOT key" do
      {:ok, tokens} = Lexer.tokenize("options[NOT disabled]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access, {:identifier, "options"}, {:logical_not, {:identifier, "disabled"}}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with list key" do
      {:ok, tokens} = Lexer.tokenize("lookup[[1, 2, 3]]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access, {:identifier, "lookup"},
         {:list, [{:literal, 1}, {:literal, 2}, {:literal, 3}]}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with parenthesized key" do
      {:ok, tokens} = Lexer.tokenize("data[(index + 1)]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access, {:identifier, "data"},
         {:arithmetic, :add, {:identifier, "index"}, {:literal, 1}}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses deeply chained bracket access" do
      {:ok, tokens} = Lexer.tokenize("a[0][1][2][3]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access,
         {:bracket_access,
          {:bracket_access, {:bracket_access, {:identifier, "a"}, {:literal, 0}}, {:literal, 1}},
          {:literal, 2}}, {:literal, 3}}

      assert {:ok, ^expected_ast} = result
    end

    test "parses bracket access with mixed operators in complex expressions" do
      {:ok, tokens} = Lexer.tokenize("data[key] + values[index * 2] > threshold['max']")
      result = parse_positionless(tokens)

      expected_ast =
        {:comparison, :gt,
         {:arithmetic, :add, {:bracket_access, {:identifier, "data"}, {:identifier, "key"}},
          {:bracket_access, {:identifier, "values"},
           {:arithmetic, :multiply, {:identifier, "index"}, {:literal, 2}}}},
         {:bracket_access, {:identifier, "threshold"}, {:string_literal, "max", :single}}}

      assert {:ok, ^expected_ast} = result
    end

    test "returns error for bracket access with invalid token after bracket" do
      {:ok, tokens} = Lexer.tokenize("user[>]")
      result = parse_positionless(tokens)

      assert {:error,
              "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found '>'",
              1, 6, _span} = result
    end

    test "returns error for unmatched left bracket" do
      {:ok, tokens} = Lexer.tokenize("user[key")
      result = parse_positionless(tokens)

      assert {:error, "Expected ']' but found end of input", 1, 9, _span} = result
    end

    test "returns error for nested unmatched brackets" do
      {:ok, tokens} = Lexer.tokenize("data[users[index")
      result = parse_positionless(tokens)

      assert {:error, "Expected ']' but found end of input", 1, 17, _span} = result
    end

    test "parses bracket access with complex nested expression" do
      {:ok, tokens} = Lexer.tokenize("cache[users[active AND valid]['name']]")
      result = parse_positionless(tokens)

      expected_ast =
        {:bracket_access, {:identifier, "cache"},
         {:bracket_access,
          {:bracket_access, {:identifier, "users"},
           {:logical_and, {:identifier, "active"}, {:identifier, "valid"}}},
          {:string_literal, "name", :single}}}

      assert {:ok, ^expected_ast} = result
    end
  end
end
