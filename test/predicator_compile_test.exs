defmodule PredicatorCompileTest do
  use ExUnit.Case, async: true

  alias Predicator.Errors.ParseError

  describe "compile/1" do
    test "compiles simple expression" do
      {:ok, instructions} = Predicator.compile("score > 85")

      expected = [
        ["load", "score"],
        ["lit", 85],
        ["compare", "GT"]
      ]

      assert instructions == expected
    end

    test "compiles different operators" do
      test_cases = [
        {"x > 5", [["load", "x"], ["lit", 5], ["compare", "GT"]]},
        {"x < 5", [["load", "x"], ["lit", 5], ["compare", "LT"]]},
        {"x >= 5", [["load", "x"], ["lit", 5], ["compare", "GTE"]]},
        {"x <= 5", [["load", "x"], ["lit", 5], ["compare", "LTE"]]},
        {"x == 5", [["load", "x"], ["lit", 5], ["compare", "EQ"]]},
        {"x != 5", [["load", "x"], ["lit", 5], ["compare", "NE"]]}
      ]

      for {expression, expected_instructions} <- test_cases do
        {:ok, instructions} = Predicator.compile(expression)
        assert instructions == expected_instructions
      end
    end

    test "compiles string expressions" do
      {:ok, instructions} = Predicator.compile("name == \"John\"")

      expected = [
        ["load", "name"],
        ["lit", "John"],
        ["compare", "EQ"]
      ]

      assert instructions == expected
    end

    test "compiles boolean expressions" do
      {:ok, instructions} = Predicator.compile("active == true")

      expected = [
        ["load", "active"],
        ["lit", true],
        ["compare", "EQ"]
      ]

      assert instructions == expected
    end

    test "handles parentheses" do
      {:ok, instructions} = Predicator.compile("(score > 85)")

      expected = [
        ["load", "score"],
        ["lit", 85],
        ["compare", "GT"]
      ]

      assert instructions == expected
    end

    test "returns error for invalid syntax" do
      result = Predicator.compile("score >")

      assert {:error, %Predicator.Errors.ParseError{message: message, position: {1, 8}}} =
               result

      assert message =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input"
    end
  end

  describe "compile_with_positions/1" do
    test "returns a %Predicator.Compiled{} with the instruction list and a side table" do
      assert {:ok, compiled} = Predicator.compile_with_positions("score > 85")
      assert %Predicator.Compiled{} = compiled
      assert compiled.instructions == [["load", "score"], ["lit", 85], ["compare", "GT"]]
      assert compiled.positions == %{0 => {1, 1}, 1 => {1, 9}, 2 => {1, 7}}
    end

    test "the instruction list is identical to compile/1's" do
      for expression <- [
            "score > 85",
            "a and b or not c",
            "len(name) + 1",
            "[1, 2, 3] contains x",
            "{a: 1, 'b': items[0]}",
            "-x % 3 == 0"
          ] do
        assert {:ok, plain} = Predicator.compile(expression)

        assert {:ok, %Predicator.Compiled{instructions: positioned}} =
                 Predicator.compile_with_positions(expression)

        assert plain == positioned
      end
    end

    test "reports parse errors the same way compile/1 does" do
      assert Predicator.compile_with_positions("score >") == Predicator.compile("score >")
    end
  end

  describe "parse/2 with spans" do
    test "puts a span in every node's trailing slot" do
      assert Predicator.parse("score > 85", spans: true) ==
               {:ok,
                {:comparison, :gt, {:identifier, "score", {{1, 1}, {1, 6}}},
                 {:literal, 85, {{1, 9}, {1, 11}}}, {{1, 1}, {1, 11}}}}
    end

    test "spans: false is the default and byte-identical to parse/1" do
      assert Predicator.parse("score > 85", spans: false) == Predicator.parse("score > 85")
    end

    test "reports lexer errors the same way" do
      assert Predicator.parse("score > @", spans: true) == Predicator.parse("score > @")
    end
  end

  describe "compile_with_spans/1" do
    test "returns a %Predicator.Compiled{} with the instruction list and a span table" do
      assert {:ok, compiled} = Predicator.compile_with_spans("score > 85")
      assert %Predicator.Compiled{} = compiled
      assert compiled.instructions == [["load", "score"], ["lit", 85], ["compare", "GT"]]

      assert compiled.positions ==
               %{0 => {{1, 1}, {1, 6}}, 1 => {{1, 9}, {1, 11}}, 2 => {{1, 1}, {1, 11}}}
    end

    test "the instruction list is identical to compile/1's" do
      for expression <- [
            "score > 85",
            "a and b or not c",
            "len(name) + 1",
            "[1, 2, 3] contains x",
            "{a: 1, 'b': items[0]}",
            "-x % 3 == 0"
          ] do
        assert {:ok, plain} = Predicator.compile(expression)

        assert {:ok, %Predicator.Compiled{instructions: spanned}} =
                 Predicator.compile_with_spans(expression)

        assert plain == spanned
      end
    end

    test "reports parse errors the same way compile/1 does" do
      assert Predicator.compile_with_spans("score >") == Predicator.compile("score >")
    end
  end

  describe "the compile arm carries a span in every mode (Phase 4)" do
    test "all six compile entry points return a ParseError with a non-nil span on a parse failure" do
      assert {:error, %Predicator.Errors.ParseError{span: span}} = Predicator.compile("score >")
      refute is_nil(span)

      assert {:error, %Predicator.Errors.ParseError{span: span}} =
               Predicator.compile_with_positions("score >")

      refute is_nil(span)

      assert {:error, %Predicator.Errors.ParseError{span: span}} =
               Predicator.compile_with_spans("score >")

      refute is_nil(span)

      assert {:error, %Predicator.Errors.ParseError{span: span}} =
               Predicator.compile_program("x =")

      refute is_nil(span)

      assert {:error, %Predicator.Errors.ParseError{span: span}} =
               Predicator.compile_program_with_positions("x =")

      refute is_nil(span)

      assert {:error, %Predicator.Errors.ParseError{span: span}} =
               Predicator.compile_program_with_spans("x =")

      refute is_nil(span)
    end

    test "all six compile entry points return a ParseError with a non-nil span on a lex failure" do
      lex_failing_source = "\"unterminated"

      for compile_fn <- [
            &Predicator.compile/1,
            &Predicator.compile_with_positions/1,
            &Predicator.compile_with_spans/1,
            &Predicator.compile_program/1,
            &Predicator.compile_program_with_positions/1,
            &Predicator.compile_program_with_spans/1
          ] do
        assert {:error, %Predicator.Errors.ParseError{span: span}} =
                 compile_fn.(lex_failing_source)

        refute is_nil(span)
      end
    end

    test "compile/1 and compile_with_spans/1 return the same span for the same failing source" do
      assert {:error, plain_error} = Predicator.compile("score >")
      assert {:error, spanned_error} = Predicator.compile_with_spans("score >")

      assert plain_error.span == spanned_error.span
    end
  end

  describe "parse_program/2" do
    test "parses a single-statement program" do
      assert Predicator.parse_program("a = 1") ==
               {:ok,
                {:program,
                 [{:assignment, {:identifier, "a", {1, 1}}, {:literal, 1, {1, 5}}, {1, 3}}],
                 {1, 1}}}
    end

    test "parses a multi-statement program with a trailing separator" do
      assert {:ok, {:program, statements, _pos}} = Predicator.parse_program("a = 1; b = 2;")
      assert length(statements) == 2

      assert Enum.all?(statements, fn
               {:assignment, _lhs, _rhs, _pos} -> true
               _other -> false
             end)
    end

    test "a bare expression statement mixes with assignments" do
      assert {:ok, {:program, statements, _pos}} =
               Predicator.parse_program("a = 1; a > 0; b = 2")

      assert [
               {:assignment, _lhs1, _rhs1, _pos1},
               {:comparison, :gt, _left, _right, _pos2},
               {:assignment, _lhs2, _rhs2, _pos3}
             ] = statements
    end

    test "assigns through a property.bracket.property chain" do
      assert {:ok, {:program, [{:assignment, lhs, _rhs, _pos}], _program_pos}} =
               Predicator.parse_program("user.items[0].name = 'Ada'")

      assert {:property_access,
              {:bracket_access,
               {:property_access, {:identifier, "user", _user_pos}, "items", _items_pos}, _key,
               _bracket_pos}, "name", _prop_pos} = lhs
    end

    test "non-assignable lhs gives the location-shape error, not the == fix-it" do
      assert {:error,
              "Left side of '=' must be an assignable location - an identifier, a property " <>
                "access, or a bracket access.", 1, 4, _span} = Predicator.parse_program("42 = 1")
    end

    test "nested = gives the == fix-it error" do
      assert {:error, message, _line, _col, _span} = Predicator.parse_program("a = b = 1")
      assert message =~ "is not an equality operator"
    end

    test "empty input, a lone ';', and adjacent ';;' are all parse errors" do
      assert {:error, _message, _line, _col, _span} = Predicator.parse_program("")
      assert {:error, _message, _line, _col, _span} = Predicator.parse_program(";")
      assert {:error, _message, _line, _col, _span} = Predicator.parse_program("a;;b")
    end

    test "leftover tokens after a statement report a pointed error" do
      assert {:error, "Unexpected token identifier 'extra' after statement", 1, 7, _span} =
               Predicator.parse_program("a = 1 extra")
    end

    test "propagates lexer errors the same way parse/2 does" do
      assert Predicator.parse_program("a = @") == Predicator.parse("a = @")
    end

    test "spans: true puts a span in every node's trailing slot" do
      assert Predicator.parse_program("a = 1", spans: true) ==
               {:ok,
                {:program,
                 [
                   {:assignment, {:identifier, "a", {{1, 1}, {1, 2}}},
                    {:literal, 1, {{1, 5}, {1, 6}}}, {{1, 1}, {1, 6}}}
                 ], {{1, 1}, {1, 6}}}}
    end

    test "spans: false is the default and byte-identical to spans-less parse_program/2" do
      assert Predicator.parse_program("a = 1; b = 2", spans: false) ==
               Predicator.parse_program("a = 1; b = 2")
    end
  end

  describe "compile!/1" do
    test "compiles successfully" do
      instructions = Predicator.compile!("score > 85")

      expected = [
        ["load", "score"],
        ["lit", 85],
        ["compare", "GT"]
      ]

      assert instructions == expected
    end

    test "raises exception for parse errors" do
      # Pinned to the struct's own fields, not a hardcoded sentence, so this
      # is exactly the byte-identical-to-7.0.0 claim: the raised text is
      # "Compilation failed: " followed by the error's :message, " at line ",
      # its :position line, ", column ", and its :position column.
      {:error, error} = Predicator.compile("score >")
      {line, column} = error.position
      expected = "Compilation failed: #{error.message} at line #{line}, column #{column}"

      assert_raise RuntimeError, expected, fn ->
        Predicator.compile!("score >")
      end
    end
  end

  describe "structured compile errors (px-d71, ADR-0015)" do
    test "all six entry points return the same %ParseError{} for the same bad expression" do
      expected =
        ParseError.new(
          "Expected number, string, boolean, date, datetime, identifier, function call, list, " <>
            "object, or '(' but found end of input",
          1,
          8,
          {{1, 8}, {1, 8}}
        )

      assert {:error, ^expected} = Predicator.compile("score >")
      assert {:error, ^expected} = Predicator.compile_with_positions("score >")
      assert {:error, ^expected} = Predicator.compile_with_spans("score >")
    end

    test "both program entry points return the same %ParseError{} for the same bad program" do
      expected =
        ParseError.new(
          "Expected number, string, boolean, date, datetime, identifier, function call, list, " <>
            "object, or '(' but found end of input",
          1,
          4,
          {{1, 4}, {1, 4}}
        )

      assert {:error, ^expected} = Predicator.compile_program("x =")
      assert {:error, ^expected} = Predicator.compile_program_with_positions("x =")
      assert {:error, ^expected} = Predicator.compile_program_with_spans("x =")
    end

    test "the message never carries the location" do
      for source <- ["score >", "score > >"] do
        assert {:error, %Predicator.Errors.ParseError{message: message}} =
                 Predicator.compile(source)

        refute message =~ "at line"
      end
    end

    test "a compile/1 error equals the evaluate/3 error for the same source" do
      assert Predicator.compile("score >") == Predicator.evaluate("score >", %{})
    end
  end
end
