defmodule Predicator.ParserProgramTest do
  use ExUnit.Case, async: true

  import Predicator.ParseShape

  alias Predicator.Lexer

  describe "parse_program/2" do
    test "parses a single-statement program" do
      {:ok, tokens} = Lexer.tokenize("a = 1")

      assert parse_program_positionless(tokens) ==
               {:ok, {:program, [{:assignment, {:identifier, "a"}, {:literal, 1}}]}}
    end

    test "parses a multi-statement program" do
      {:ok, tokens} = Lexer.tokenize("a = 1; b = 2")

      assert parse_program_positionless(tokens) ==
               {:ok,
                {:program,
                 [
                   {:assignment, {:identifier, "a"}, {:literal, 1}},
                   {:assignment, {:identifier, "b"}, {:literal, 2}}
                 ]}}
    end

    test "a single trailing semicolon is optional and normalizes away" do
      {:ok, tokens} = Lexer.tokenize("a = 1;")

      assert parse_program_positionless(tokens) ==
               {:ok, {:program, [{:assignment, {:identifier, "a"}, {:literal, 1}}]}}
    end

    test "a bare expression is a valid statement" do
      {:ok, tokens} = Lexer.tokenize("score > 85")

      assert parse_program_positionless(tokens) ==
               {:ok, {:program, [{:comparison, :gt, {:identifier, "score"}, {:literal, 85}}]}}
    end

    test "assignments and expression statements mix freely" do
      {:ok, tokens} = Lexer.tokenize("a = 1; score > 85; b = 2")

      assert parse_program_positionless(tokens) ==
               {:ok,
                {:program,
                 [
                   {:assignment, {:identifier, "a"}, {:literal, 1}},
                   {:comparison, :gt, {:identifier, "score"}, {:literal, 85}},
                   {:assignment, {:identifier, "b"}, {:literal, 2}}
                 ]}}
    end

    test "assigns to a property chain" do
      {:ok, tokens} = Lexer.tokenize("user.profile.name = 'Ada'")

      assert {:ok,
              {:program,
               [
                 {:assignment,
                  {:property_access, {:property_access, {:identifier, "user"}, "profile"},
                   "name"}, {:string_literal, "Ada", :single}}
               ]}} = parse_program_positionless(tokens)
    end

    test "assigns to a bracket access" do
      {:ok, tokens} = Lexer.tokenize("items[0] = 1")

      assert parse_program_positionless(tokens) ==
               {:ok,
                {:program,
                 [
                   {:assignment, {:bracket_access, {:identifier, "items"}, {:literal, 0}},
                    {:literal, 1}}
                 ]}}
    end

    test "assigns to a mixed property/bracket chain" do
      {:ok, tokens} = Lexer.tokenize("a.b[0].c = 1")

      assert parse_program_positionless(tokens) ==
               {:ok,
                {:program,
                 [
                   {:assignment,
                    {:property_access,
                     {:bracket_access, {:property_access, {:identifier, "a"}, "b"},
                      {:literal, 0}}, "c"}, {:literal, 1}}
                 ]}}
    end

    test "assigns through a computed bracket key" do
      {:ok, tokens} = Lexer.tokenize("a[k] = 1")

      assert parse_program_positionless(tokens) ==
               {:ok,
                {:program,
                 [
                   {:assignment, {:bracket_access, {:identifier, "a"}, {:identifier, "k"}},
                    {:literal, 1}}
                 ]}}
    end

    test "the rhs is a full expression - arithmetic" do
      {:ok, tokens} = Lexer.tokenize("b = a + 1")

      assert parse_program_positionless(tokens) ==
               {:ok,
                {:program,
                 [
                   {:assignment, {:identifier, "b"},
                    {:arithmetic, :add, {:identifier, "a"}, {:literal, 1}}}
                 ]}}
    end

    test "the rhs is a full expression - comparison and logical and" do
      {:ok, tokens} = Lexer.tokenize("b = x > 1 and y")

      assert parse_program_positionless(tokens) ==
               {:ok,
                {:program,
                 [
                   {:assignment, {:identifier, "b"},
                    {:logical_and, {:comparison, :gt, {:identifier, "x"}, {:literal, 1}},
                     {:identifier, "y"}}}
                 ]}}
    end

    test "parentheses are transparent, so (a) = 1 parses as an assignment" do
      {:ok, tokens} = Lexer.tokenize("(a) = 1")

      assert parse_program_positionless(tokens) ==
               {:ok, {:program, [{:assignment, {:identifier, "a"}, {:literal, 1}}]}}
    end

    test "non-assignable lhs: integer literal gives the location-shape error" do
      {:ok, tokens} = Lexer.tokenize("42 = 1")

      assert {:error, message, 1, 4, _span} = Predicator.Parser.parse_program(tokens)

      assert message ==
               "Left side of '=' must be an assignable location - an identifier, a property " <>
                 "access, or a bracket access."
    end

    test "non-assignable lhs: function call gives the location-shape error" do
      {:ok, tokens} = Lexer.tokenize("len(x) = 1")

      assert {:error, message, _line, _col, _span} = Predicator.Parser.parse_program(tokens)
      assert message =~ "must be an assignable location"
    end

    test "non-assignable lhs: string literal gives the location-shape error" do
      {:ok, tokens} = Lexer.tokenize("'s' = 1")

      assert {:error, message, _line, _col, _span} = Predicator.Parser.parse_program(tokens)
      assert message =~ "must be an assignable location"
    end

    test "non-assignable lhs: list literal gives the location-shape error" do
      {:ok, tokens} = Lexer.tokenize("[1] = 2")

      assert {:error, message, _line, _col, _span} = Predicator.Parser.parse_program(tokens)
      assert message =~ "must be an assignable location"
    end

    test "non-assignable lhs: unary minus gives the location-shape error, not the == fix-it" do
      {:ok, tokens} = Lexer.tokenize("-a = 1")

      assert {:error, message, _line, _col, _span} = Predicator.Parser.parse_program(tokens)
      assert message =~ "must be an assignable location"
      refute message =~ "is not an equality operator"
    end

    test "nested assignment in a parenthesized rhs gives the == fix-it error" do
      {:ok, tokens} = Lexer.tokenize("a = (b = 1)")

      assert {:error, message, _line, _col, _span} = Predicator.Parser.parse_program(tokens)
      assert message =~ "is not an equality operator"
    end

    test "chained assignment a = b = 1 gives the == fix-it error" do
      {:ok, tokens} = Lexer.tokenize("a = b = 1")

      assert {:error, message, _line, _col, _span} = Predicator.Parser.parse_program(tokens)
      assert message =~ "is not an equality operator"
    end

    test "empty input is a parse error" do
      {:ok, tokens} = Lexer.tokenize("")
      assert {:error, _message, _line, _col, _span} = Predicator.Parser.parse_program(tokens)
    end

    test "a lone semicolon is a parse error - no empty statements" do
      {:ok, tokens} = Lexer.tokenize(";")
      assert {:error, _message, _line, _col, _span} = Predicator.Parser.parse_program(tokens)
    end

    test "two semicolons in a row is a parse error - no empty statements" do
      {:ok, tokens} = Lexer.tokenize("a;;b")
      assert {:error, _message, _line, _col, _span} = Predicator.Parser.parse_program(tokens)
    end

    test "leftover tokens after a statement report a pointed error" do
      {:ok, tokens} = Lexer.tokenize("a = 1 extra")

      assert {:error, "Unexpected token identifier 'extra' after statement", 1, 7, _span} =
               Predicator.Parser.parse_program(tokens)
    end
  end

  describe "parse_program/2 - positions and spans" do
    test "an assignment's point position is the '=' token, span lhs start to rhs end" do
      {:ok, tokens} = Lexer.tokenize("a = 1")

      assert Predicator.Parser.parse_program(tokens) ==
               {:ok,
                {:program,
                 [{:assignment, {:identifier, "a", {1, 1}}, {:literal, 1, {1, 5}}, {1, 3}}],
                 {1, 1}}}

      assert Predicator.Parser.parse_program(tokens, spans: true) ==
               {:ok,
                {:program,
                 [
                   {:assignment, {:identifier, "a", {{1, 1}, {1, 2}}},
                    {:literal, 1, {{1, 5}, {1, 6}}}, {{1, 1}, {1, 6}}}
                 ], {{1, 1}, {1, 6}}}}
    end

    test "the program's span covers all statements and excludes a trailing ';'" do
      {:ok, tokens} = Lexer.tokenize("a = 1; b = 2;")

      assert {:ok, {:program, _statements, {{1, 1}, {1, 13}}}} =
               Predicator.Parser.parse_program(tokens, spans: true)
    end

    test "position mode gives the program's point as its first token's position" do
      {:ok, tokens} = Lexer.tokenize("score > 85; a = 1")

      assert {:ok, {:program, _statements, {1, 1}}} = Predicator.Parser.parse_program(tokens)
    end
  end

  describe "Predicator.parse_program/2 - the façade" do
    test "parses a multi-statement program from source" do
      assert {:ok, {:program, statements, _pos}} = Predicator.parse_program("a = 1; b = a + 1")
      assert length(statements) == 2
    end

    test "propagates lexer errors" do
      assert Predicator.parse_program("a = @") == Predicator.parse("a = @")
    end

    test "propagates parser errors" do
      assert {:error,
              "Left side of '=' must be an assignable location - an identifier, a property " <>
                "access, or a bracket access.", 1, 4, _span} = Predicator.parse_program("42 = 1")
    end

    test "accepts spans: true" do
      assert {:ok, {:program, _statements, {{1, 1}, _end}}} =
               Predicator.parse_program("a = 1", spans: true)
    end
  end
end
