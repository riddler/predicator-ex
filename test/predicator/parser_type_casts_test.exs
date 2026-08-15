defmodule Predicator.ParserTypeCastsTest do
  use ExUnit.Case, async: true

  import Predicator.ParseShape

  alias Predicator.Lexer

  describe "type casts" do
    test "casts an identifier to integer" do
      {:ok, tokens} = Lexer.tokenize("x::integer")
      result = parse_positionless(tokens)

      assert {:ok, {:cast, {:identifier, "x"}, "integer"}} = result
    end

    test "each of the seven scalar type names parses" do
      for type_name <- ~w(integer float string boolean date datetime duration) do
        {:ok, tokens} = Lexer.tokenize("x::#{type_name}")

        assert {:ok, {:cast, {:identifier, "x"}, ^type_name}} = parse_positionless(tokens)
      end
    end

    # The parser's @cast_type_names is defined as Predicator.Cast.type_names/0
    # (one definition, no drift possible); this guard survives even if that
    # changes back to a hand-written list.
    test "the parser's vocabulary agrees with Predicator.Cast.type_names/0" do
      for type_name <- Predicator.Cast.type_names() do
        {:ok, tokens} = Lexer.tokenize("x::#{type_name}")

        assert {:ok, {:cast, {:identifier, "x"}, ^type_name}} = parse_positionless(tokens)
      end

      assert {:error, message, _line, _col, _span} = Predicator.parse("x::not_a_real_type")
      assert message =~ "Unknown cast type 'not_a_real_type'"

      for type_name <- Predicator.Cast.type_names() do
        assert message =~ type_name
      end
    end

    test "casts a string literal" do
      {:ok, tokens} = Lexer.tokenize(~s("42"::integer))
      result = parse_positionless(tokens)

      assert {:ok, {:cast, {:string_literal, "42", :double}, "integer"}} = result
    end

    test "binds tighter than unary minus" do
      {:ok, tokens} = Lexer.tokenize("-1::integer")
      result = parse_positionless(tokens)

      assert {:ok, {:unary, :minus, {:cast, {:literal, 1}, "integer"}}} = result
    end

    test "binds tighter than logical not" do
      {:ok, tokens} = Lexer.tokenize("!x::boolean")
      result = parse_positionless(tokens)

      assert {:ok, {:logical_not, {:cast, {:identifier, "x"}, "boolean"}}} = result
    end

    test "casts a property access" do
      {:ok, tokens} = Lexer.tokenize("x.y::string")
      result = parse_positionless(tokens)

      assert {:ok, {:cast, {:property_access, {:identifier, "x"}, "y"}, "string"}} = result
    end

    test "casts a function call" do
      {:ok, tokens} = Lexer.tokenize("f(x)::integer")
      result = parse_positionless(tokens)

      assert {:ok, {:cast, {:function_call, "f", [{:identifier, "x"}]}, "integer"}} = result
    end

    test "casts a bracket access" do
      {:ok, tokens} = Lexer.tokenize("x[0]::integer")
      result = parse_positionless(tokens)

      assert {:ok, {:cast, {:bracket_access, {:identifier, "x"}, {:literal, 0}}, "integer"}} =
               result
    end

    test "brackets a cast" do
      {:ok, tokens} = Lexer.tokenize("x::string[0]")
      result = parse_positionless(tokens)

      assert {:ok, {:bracket_access, {:cast, {:identifier, "x"}, "string"}, {:literal, 0}}} =
               result
    end

    test "a cast is the left side of a comparison" do
      {:ok, tokens} = Lexer.tokenize("x::integer > 5")
      result = parse_positionless(tokens)

      assert {:ok, {:comparison, :gt, {:cast, {:identifier, "x"}, "integer"}, {:literal, 5}}} =
               result
    end

    test "a cast is the left side of an arithmetic expression" do
      {:ok, tokens} = Lexer.tokenize("x::integer + 1")
      result = parse_positionless(tokens)

      assert {:ok, {:arithmetic, :add, {:cast, {:identifier, "x"}, "integer"}, {:literal, 1}}} =
               result
    end

    test "casts a parenthesized expression" do
      {:ok, tokens} = Lexer.tokenize("(x + 1)::integer")
      result = parse_positionless(tokens)

      assert {:ok, {:cast, {:arithmetic, :add, {:identifier, "x"}, {:literal, 1}}, "integer"}} =
               result
    end

    test "chains left-to-right" do
      {:ok, tokens} = Lexer.tokenize(~s("2026-08-09"::date::datetime))
      result = parse_positionless(tokens)

      assert {:ok, {:cast, {:cast, {:string_literal, "2026-08-09", :double}, "date"}, "datetime"}} =
               result
    end

    test "an unknown type name is a parse error naming the type's own column" do
      assert {:error, message, 1, 4, _span} = Predicator.parse("x::foo")

      assert message ==
               "Unknown cast type 'foo' - expected one of: integer, float, string, " <>
                 "boolean, date, datetime, duration"
    end

    test "a missing type name at end of input is a parse error" do
      assert {:error, "Expected a type name after '::' but found end of input", 1, 4, _span} =
               Predicator.parse("x::")
    end

    test "a number after '::' is a parse error" do
      assert {:error, message, 1, 4, _span} = Predicator.parse("x::5")
      assert message =~ "Expected a type name after '::' but found number '5'"
    end

    test "'::' followed by a function-call-shaped name reports a missing type name" do
      assert {:error, message, 1, 4, _span} = Predicator.parse("x::integer(1)")
      assert message =~ "Expected a type name after '::' but found function 'integer'"
    end

    test "a chained unknown type names the first unknown name, not the last" do
      assert {:error, message, 1, 4, _span} = Predicator.parse("x::foo::integer")
      assert message =~ "Unknown cast type 'foo'"
    end

    test "a cast is not an assignable location" do
      {:ok, tokens} = Lexer.tokenize("x::integer = 1")

      assert {:error, message, _line, _col, _span} = Predicator.Parser.parse_program(tokens)
      assert message =~ "must be an assignable location"
    end

    test "the seven type names are still contextual identifiers, not keywords" do
      {:ok, tokens} = Lexer.tokenize("integer > 5")
      result = parse_positionless(tokens)

      assert {:ok, {:comparison, :gt, {:identifier, "integer"}, {:literal, 5}}} = result
    end

    test "each of the seven type names parses alone as a plain identifier" do
      for type_name <- ~w(integer float string boolean date datetime duration) do
        {:ok, tokens} = Lexer.tokenize(type_name)

        assert {:ok, {:identifier, ^type_name}} = parse_positionless(tokens)
      end
    end

    test "a type name is still a valid property name" do
      {:ok, tokens} = Lexer.tokenize("x.date")
      result = parse_positionless(tokens)

      assert {:ok, {:property_access, {:identifier, "x"}, "date"}} = result
    end

    test "a type name is still a valid object key" do
      {:ok, tokens} = Lexer.tokenize("{date: 1, string: 2}")
      result = parse_positionless(tokens)

      assert {:ok,
              {:object,
               [
                 {{:object_key, "date", :identifier}, {:literal, 1}},
                 {{:object_key, "string", :identifier}, {:literal, 2}}
               ]}} = result
    end

    test "a type name is still a valid assignment target" do
      {:ok, tokens} = Lexer.tokenize("string = 1")

      assert {:ok, {:program, [{:assignment, {:identifier, "string"}, {:literal, 1}}]}} =
               parse_program_positionless(tokens)
    end

    test "a variable named after a type name can itself be cast" do
      {:ok, tokens} = Lexer.tokenize("duration::string")
      result = parse_positionless(tokens)

      assert {:ok, {:cast, {:identifier, "duration"}, "string"}} = result
    end

    test "a type name is still a valid function argument" do
      {:ok, tokens} = Lexer.tokenize("f(integer)")
      result = parse_positionless(tokens)

      assert {:ok, {:function_call, "f", [{:identifier, "integer"}]}} = result
    end
  end
end
