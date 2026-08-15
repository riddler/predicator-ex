defmodule Predicator.ParserErrorSpansTest do
  use ExUnit.Case, async: true

  import Predicator.ParseShape

  alias Predicator.Lexer

  describe "parse/1 - edge cases for format_token" do
    test "format_token handles all date/datetime formats" do
      date = ~D[2024-01-15]
      {:ok, dt, _offset} = DateTime.from_iso8601("2024-01-15T10:30:00Z")

      # Test direct calls to private function via token parsing errors
      tokens = [
        {:date, 1, 1, 11, date},
        {:plus, 1, 12, 1, "+"},
        {:eof, 1, 13, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:error, message, 1, 13, _span} = result

      assert message =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input"

      tokens = [
        {:datetime, 1, 1, 20, dt},
        {:plus, 1, 21, 1, "+"},
        {:eof, 1, 22, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:error, message, 1, 22, _span} = result

      assert message =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input"
    end

    test "format_token handles function names in error messages" do
      tokens = [
        {:function_name, 1, 1, 3, "len"},
        {:plus, 1, 4, 1, "+"},
        {:eof, 1, 5, 0, nil}
      ]

      result = parse_positionless(tokens)
      assert {:error, "Expected '(' after function name but found '+'", 1, 4, _span} = result
    end

    test "a stray :: in expression position returns an error tuple, not a raise" do
      assert {:error, message, 1, 1, _span} = Predicator.parse("::integer")
      assert message =~ "'::'"
    end
  end

  describe "parse/1 - error spans" do
    test "a single-token failure spans exactly that token, for a token longer than one character" do
      {:ok, tokens} = Lexer.tokenize("score > 85 extra")

      assert {:error, message, line, col, {start, stop}} = Predicator.Parser.parse(tokens)

      assert message == "Unexpected token identifier 'extra' after expression"
      assert {line, col} == {1, 12}
      assert start == {line, col}
      assert stop == {1, 17}
    end

    test "a :string token's span is derived from the 7-element token shape via token_start/1 and token_end/1" do
      source = ~s({age "next": 1})
      {:ok, tokens} = Lexer.tokenize(source)

      string_token =
        Enum.find(tokens, &match?({:string, _line, _col, _len, _value, _q, _end}, &1))

      {:string, expected_line, expected_col, _len, _value, _quote_type, _end_position} =
        string_token

      assert {:error, message, line, col, {start, stop}} = Predicator.Parser.parse(tokens)

      assert message =~ "Expected ':' after object key but found"
      assert {line, col} == {expected_line, expected_col}
      assert start == {line, col}
      assert Predicator.SpanSlicing.slice(source, {start, stop}) == ~s("next")
    end

    test "the span-start invariant holds for an unexpected-token, a lexical, and an end-of-input failure" do
      {:ok, unexpected_token_tokens} = Lexer.tokenize("score > 85 extra")
      unexpected_token_error = Predicator.Parser.parse(unexpected_token_tokens)

      lexical_error = Predicator.Lexer.tokenize("@")

      {:ok, end_of_input_tokens} = Lexer.tokenize("score >")
      end_of_input_error = Predicator.Parser.parse(end_of_input_tokens)

      for err <- [unexpected_token_error, lexical_error, end_of_input_error] do
        assert elem(err, 4) |> elem(0) == {elem(err, 2), elem(err, 3)}
      end
    end
  end

  describe "parse/1 - end of input reports the end of the source" do
    test "a multi-line source reports the last line, not line 1" do
      {:ok, tokens} = Lexer.tokenize("[1,\n2,\n")

      assert {:error, message, line, col, span} = Predicator.Parser.parse(tokens)

      assert message =~ "but found end of input"
      assert {line, col} == {3, 1}
      assert span == {{3, 1}, {3, 1}}
    end

    test "a multi-line program source reports the last line via the :eof sentinel" do
      {:ok, tokens} = Lexer.tokenize("a =\n  b +\n")

      assert {:error, _message, line, col, span} = Predicator.Parser.parse_program(tokens)

      assert {line, col} == {3, 1}
      assert span == {{3, 1}, {3, 1}}
    end

    test "every end-of-input span is zero-width with its start equal to the reported point" do
      sources = [
        "[1,",
        "{a:",
        "(1 +",
        "score.",
        "score::",
        "f(",
        "1d from"
      ]

      for source <- sources do
        {:ok, tokens} = Lexer.tokenize(source)

        assert {:error, _message, line, col, {start, stop}} = Predicator.Parser.parse(tokens)
        assert start == {line, col}
        assert stop == {line, col}
      end
    end
  end

  describe "failures after a multi-line string literal" do
    test "an end-of-input failure reports the true end of the source" do
      source = "\"ab\ncd\" > "

      assert {:error, _message, line, col, span} = Predicator.parse(source)

      lines = String.split(source, "\n")
      assert line == length(lines)
      assert col == String.length(List.last(lines)) + 1
      assert Predicator.SpanSlicing.slice(source, span) == ""
    end

    test "an unexpected-token failure reports the offending token's real position" do
      source = "\"ab\ncd\" > 5 extra"

      assert {:error, message, line, col, span} = Predicator.parse(source)

      assert message =~ "extra"
      assert {line, col} == {2, 9}
      assert Predicator.SpanSlicing.slice(source, span) == "extra"
    end

    test "a lexical failure reports the offending character's real position" do
      source = "\"ab\ncd\" > @"

      assert {:error, _message, line, col, _span} = Predicator.parse(source)

      assert {line, col} == {2, 7}
    end

    test "the span-start invariant holds for all three failure kinds" do
      sources = [
        "\"ab\ncd\" > ",
        "\"ab\ncd\" > 5 extra",
        "\"ab\ncd\" > @"
      ]

      for source <- sources do
        assert {:error, _message, line, col, span} = Predicator.parse(source)
        assert elem(span, 0) == {line, col}
      end
    end
  end

  describe "guard: the deliberate px-tbv.2 gaps" do
    test "Compiler.to_instructions/2 compiles a program AST" do
      {:ok, program} = Predicator.parse_program("a = 1")

      assert Predicator.Compiler.to_instructions(program) == [
               ["lit", "a"],
               ["lit", 1],
               ["store", 1]
             ]
    end

    test "Compiler.to_instructions/2 compiles an assignment AST" do
      {:ok, {:program, [assignment], _pos}} = Predicator.parse_program("a = 1")

      assert Predicator.Compiler.to_instructions(assignment) == [
               ["lit", "a"],
               ["lit", 1],
               ["store", 1]
             ]
    end

    # ContextLocation.resolve/2 has a catch-all (context_location.ex:307-309)
    # that reads any unhandled node as :invalid_node - correct here, since
    # assigning to a program or an assignment is nonsense and neither is
    # reachable through resolve_expression/2, which parses with parse/2.
    test "ContextLocation.resolve/2 returns :invalid_node for a program AST" do
      {:ok, program} = Predicator.parse_program("a = 1")

      assert {:error, %Predicator.Errors.LocationError{type: :invalid_node}} =
               Predicator.ContextLocation.resolve(program, %{})
    end

    test "ContextLocation.resolve/2 returns :invalid_node for an assignment AST" do
      {:ok, {:program, [assignment], _pos}} = Predicator.parse_program("a = 1")

      assert {:error, %Predicator.Errors.LocationError{type: :invalid_node}} =
               Predicator.ContextLocation.resolve(assignment, %{})
    end
  end
end
