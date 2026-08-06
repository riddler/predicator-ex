defmodule Predicator.ObjectParserTest do
  use ExUnit.Case
  alias Predicator.Lexer

  describe "object literal parsing" do
    test "empty object" do
      {:ok, tokens} = Lexer.tokenize("{}")
      assert {:ok, {:object, []}} = parse_positionless(tokens)
    end

    test "simple object with identifier key" do
      {:ok, tokens} = Lexer.tokenize("{a: 1}")

      assert {:ok, {:object, [{{:object_key, "a", :identifier}, {:literal, 1}}]}} =
               parse_positionless(tokens)
    end

    test "object with multiple properties" do
      {:ok, tokens} = Lexer.tokenize("{name: 'John', age: 30}")

      assert {:ok, {:object, entries}} = parse_positionless(tokens)
      assert length(entries) == 2
      assert {{:object_key, "name", :identifier}, {:string_literal, "John", :single}} in entries
      assert {{:object_key, "age", :identifier}, {:literal, 30}} in entries
    end

    test "object with string key" do
      {:ok, tokens} = Lexer.tokenize("{'key-with-dash': 'value'}")

      assert {:ok,
              {:object,
               [{{:object_key, "key-with-dash", :single}, {:string_literal, "value", :single}}]}} =
               parse_positionless(tokens)
    end

    test "nested object" do
      {:ok, tokens} = Lexer.tokenize("{user: {name: 'John'}}")

      assert {:ok, {:object, [{{:object_key, "user", :identifier}, nested_obj}]}} =
               parse_positionless(tokens)

      assert {:object, [{{:object_key, "name", :identifier}, {:string_literal, "John", :single}}]} =
               nested_obj
    end

    test "object with various value types" do
      {:ok, tokens} = Lexer.tokenize("{num: 42, str: 'hello', bool: true, arr: [1, 2]}")

      assert {:ok, {:object, entries}} = parse_positionless(tokens)
      assert length(entries) == 4
    end

    test "object with float values" do
      {:ok, tokens} = Lexer.tokenize("{pi: 3.14}")

      assert {:ok, {:object, [{{:object_key, "pi", :identifier}, {:literal, 3.14}}]}} =
               parse_positionless(tokens)
    end

    test "object with date and datetime values" do
      {:ok, tokens} = Lexer.tokenize("{date: #2024-01-15#, datetime: #2024-01-15T10:30:00Z#}")
      assert {:ok, {:object, entries}} = parse_positionless(tokens)
      assert length(entries) == 2
    end

    test "object with function call as value" do
      {:ok, tokens} = Lexer.tokenize("{length: len('hello')}")

      assert {:ok,
              {:object, [{{:object_key, "length", :identifier}, {:function_call, "len", [_arg]}}]}} =
               parse_positionless(tokens)
    end

    test "object with computed expression as value" do
      {:ok, tokens} = Lexer.tokenize("{result: 5 + 3}")

      assert {:ok,
              {:object,
               [
                 {{:object_key, "result", :identifier},
                  {:arithmetic, :add, {:literal, 5}, {:literal, 3}}}
               ]}} =
               parse_positionless(tokens)
    end

    test "object with single-quoted string key" do
      {:ok, tokens} = Lexer.tokenize("{'single-quote': 'value'}")

      assert {:ok,
              {:object,
               [{{:object_key, "single-quote", :single}, {:string_literal, "value", :single}}]}} =
               parse_positionless(tokens)
    end

    test "object with double-quoted string key" do
      {:ok, tokens} = Lexer.tokenize("{\"double-quote\": 'value'}")

      assert {:ok,
              {:object,
               [{{:object_key, "double-quote", :double}, {:string_literal, "value", :single}}]}} =
               parse_positionless(tokens)
    end
  end

  describe "object parsing errors" do
    test "missing closing brace" do
      {:ok, tokens} = Lexer.tokenize("{a: 1")
      assert {:error, "Expected '}' but found end of input", 1, 6} = parse_positionless(tokens)
    end

    test "missing colon after key" do
      {:ok, tokens} = Lexer.tokenize("{a 1}")

      assert {:error, "Expected ':' after object key but found number '1'", _line, _col} =
               parse_positionless(tokens)
    end

    test "missing value after colon" do
      {:ok, tokens} = Lexer.tokenize("{a:}")
      assert {:error, _message, _line, _col} = parse_positionless(tokens)
    end

    test "invalid key type" do
      {:ok, tokens} = Lexer.tokenize("{123: 'value'}")

      assert {:error, "Expected identifier or string for object key but found number '123'",
              _line,
              _col} =
               parse_positionless(tokens)
    end

    test "missing key in object entry" do
      {:ok, tokens} = Lexer.tokenize("{: 'value'}")

      assert {:error, "Expected identifier or string for object key but found ':'", _line, _col} =
               parse_positionless(tokens)
    end

    test "missing comma between entries" do
      {:ok, tokens} = Lexer.tokenize("{a: 1 b: 2}")

      assert {:error, "Expected '}' but found identifier 'b'", _line, _col} =
               parse_positionless(tokens)
    end

    test "trailing comma (error case)" do
      {:ok, tokens} = Lexer.tokenize("{a: 1,}")

      assert {:error, "Expected identifier or string for object key but found '}'", _line, _col} =
               parse_positionless(tokens)
    end

    test "empty key after comma" do
      {:ok, tokens} = Lexer.tokenize("{a: 1, }")

      assert {:error, "Expected identifier or string for object key but found '}'", _line, _col} =
               parse_positionless(tokens)
    end
  end

  describe "object key round trips" do
    test "one key of each style survives parse -> decompile -> parse" do
      source = ~s({a: 1, "b c": 2, 'd e': 3})
      {:ok, ast} = Predicator.parse(source)

      assert Predicator.decompile(ast) == source
      assert Predicator.parse(Predicator.decompile(ast)) == {:ok, ast}
    end

    test "a hand-built object compiles like its parsed equivalent" do
      {:ok, parsed} = Predicator.parse(~s({a: 1}))

      hand_built =
        {:object, [{{:object_key, "a", :identifier, nil}, {:literal, 1, nil}}], nil}

      assert Predicator.Compiler.to_instructions(hand_built) ==
               Predicator.Compiler.to_instructions(parsed)
    end
  end

  # These assertions are about AST *shape*, so they read the slot-free form;
  # positions and spans have their own suites.
  defp parse_positionless(input) do
    result =
      if is_binary(input),
        do: Predicator.parse(input),
        else: Predicator.Parser.parse(input)

    case result do
      {:ok, ast} -> {:ok, Predicator.ASTShape.strip(ast)}
      other -> other
    end
  end
end
