defmodule Predicator.ObjectParserTest do
  use ExUnit.Case
  alias Predicator.{Lexer, Parser}

  describe "object literal parsing" do
    test "empty object" do
      {:ok, tokens} = Lexer.tokenize("{}")
      assert {:ok, {:object, []}} = Parser.parse(tokens)
    end

    test "simple object with identifier key" do
      {:ok, tokens} = Lexer.tokenize("{a: 1}")
      assert {:ok, {:object, [{{:identifier, "a"}, {:literal, 1}}]}} = Parser.parse(tokens)
    end

    test "object with multiple properties" do
      {:ok, tokens} = Lexer.tokenize("{name: 'John', age: 30}")

      assert {:ok, {:object, entries}} = Parser.parse(tokens)
      assert length(entries) == 2
      assert {{:identifier, "name"}, {:string_literal, "John", :single}} in entries
      assert {{:identifier, "age"}, {:literal, 30}} in entries
    end

    test "object with string key" do
      {:ok, tokens} = Lexer.tokenize("{'key-with-dash': 'value'}")

      assert {:ok,
              {:object,
               [{{:string_literal, "key-with-dash"}, {:string_literal, "value", :single}}]}} =
               Parser.parse(tokens)
    end

    test "nested object" do
      {:ok, tokens} = Lexer.tokenize("{user: {name: 'John'}}")

      assert {:ok, {:object, [{{:identifier, "user"}, nested_obj}]}} = Parser.parse(tokens)
      assert {:object, [{{:identifier, "name"}, {:string_literal, "John", :single}}]} = nested_obj
    end

    test "object with various value types" do
      {:ok, tokens} = Lexer.tokenize("{num: 42, str: 'hello', bool: true, arr: [1, 2]}")

      assert {:ok, {:object, entries}} = Parser.parse(tokens)
      assert length(entries) == 4
    end

    test "object with float values" do
      {:ok, tokens} = Lexer.tokenize("{pi: 3.14}")
      assert {:ok, {:object, [{{:identifier, "pi"}, {:literal, 3.14}}]}} = Parser.parse(tokens)
    end

    test "object with date and datetime values" do
      {:ok, tokens} = Lexer.tokenize("{date: #2024-01-15#, datetime: #2024-01-15T10:30:00Z#}")
      assert {:ok, {:object, entries}} = Parser.parse(tokens)
      assert length(entries) == 2
    end

    test "object with function call as value" do
      {:ok, tokens} = Lexer.tokenize("{length: len('hello')}")

      assert {:ok, {:object, [{{:identifier, "length"}, {:function_call, "len", [_arg]}}]}} =
               Parser.parse(tokens)
    end

    test "object with computed expression as value" do
      {:ok, tokens} = Lexer.tokenize("{result: 5 + 3}")

      assert {:ok,
              {:object,
               [{{:identifier, "result"}, {:arithmetic, :add, {:literal, 5}, {:literal, 3}}}]}} =
               Parser.parse(tokens)
    end

    test "object with single-quoted string key" do
      {:ok, tokens} = Lexer.tokenize("{'single-quote': 'value'}")

      assert {:ok,
              {:object,
               [{{:string_literal, "single-quote"}, {:string_literal, "value", :single}}]}} =
               Parser.parse(tokens)
    end

    test "object with double-quoted string key" do
      {:ok, tokens} = Lexer.tokenize("{\"double-quote\": 'value'}")

      assert {:ok,
              {:object,
               [{{:string_literal, "double-quote"}, {:string_literal, "value", :single}}]}} =
               Parser.parse(tokens)
    end
  end

  describe "object parsing errors" do
    test "missing closing brace" do
      {:ok, tokens} = Lexer.tokenize("{a: 1")
      assert {:error, "Expected '}' but found end of input", 1, 6} = Parser.parse(tokens)
    end

    test "missing colon after key" do
      {:ok, tokens} = Lexer.tokenize("{a 1}")

      assert {:error, "Expected ':' after object key but found number '1'", _line, _col} =
               Parser.parse(tokens)
    end

    test "missing value after colon" do
      {:ok, tokens} = Lexer.tokenize("{a:}")
      assert {:error, _message, _line, _col} = Parser.parse(tokens)
    end

    test "invalid key type" do
      {:ok, tokens} = Lexer.tokenize("{123: 'value'}")

      assert {:error, "Expected identifier or string for object key but found number '123'",
              _line,
              _col} =
               Parser.parse(tokens)
    end

    test "missing key in object entry" do
      {:ok, tokens} = Lexer.tokenize("{: 'value'}")

      assert {:error, "Expected identifier or string for object key but found ':'", _line, _col} =
               Parser.parse(tokens)
    end

    test "missing comma between entries" do
      {:ok, tokens} = Lexer.tokenize("{a: 1 b: 2}")
      assert {:error, "Expected '}' but found identifier 'b'", _line, _col} = Parser.parse(tokens)
    end

    test "trailing comma (error case)" do
      {:ok, tokens} = Lexer.tokenize("{a: 1,}")

      assert {:error, "Expected identifier or string for object key but found '}'", _line, _col} =
               Parser.parse(tokens)
    end

    test "empty key after comma" do
      {:ok, tokens} = Lexer.tokenize("{a: 1, }")

      assert {:error, "Expected identifier or string for object key but found '}'", _line, _col} =
               Parser.parse(tokens)
    end
  end
end
