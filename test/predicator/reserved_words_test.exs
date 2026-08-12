defmodule Predicator.ReservedWordsTest do
  use ExUnit.Case, async: true

  alias Predicator.Errors.ParseError

  defp expression_message(word) do
    "'#{word}' is a statement keyword, not an expression - control flow is " <>
      "only valid in a program (Predicator.parse_program/2)."
  end

  @else_statement_message "Unexpected 'else' - an 'else' block must follow an 'if' block."

  describe "'if' used as a variable name, from every entry point" do
    test "Predicator.parse/2 reports the expression-position message" do
      assert Predicator.parse("if = 3") == {:error, expression_message("if"), 1, 1}
    end

    test "Predicator.parse_program/2 - 'if' is consumed as the keyword, not a variable name" do
      # Phase 2: `if` now opens a real if_statement, so "if = 3" fails where
      # the condition expression meets the bare "=" - the same fix-it-free
      # rejection any invalid condition gets, not a statement-keyword message.
      assert Predicator.parse_program("if = 3") ==
               {:error,
                "Expected number, string, boolean, date, datetime, identifier, function call, " <>
                  "list, object, or '(' but found '='", 1, 4}
    end

    test "Predicator.evaluate/3" do
      assert {:error, %ParseError{message: message, position: {1, 1}}} =
               Predicator.evaluate("if = 3", %{})

      assert message == expression_message("if")
    end

    test "Predicator.compile/1" do
      assert Predicator.compile("if = 3") ==
               {:error, "#{expression_message("if")} at line 1, column 1"}
    end
  end

  describe "'else' used as a variable name, from every entry point" do
    test "Predicator.parse/2" do
      assert Predicator.parse("else = 3") == {:error, expression_message("else"), 1, 1}
    end

    test "Predicator.parse_program/2" do
      assert Predicator.parse_program("else = 3") == {:error, @else_statement_message, 1, 1}
    end

    test "Predicator.evaluate/3" do
      assert {:error, %ParseError{message: message, position: {1, 1}}} =
               Predicator.evaluate("else = 3", %{})

      assert message == expression_message("else")
    end

    test "Predicator.compile/1" do
      assert Predicator.compile("else = 3") ==
               {:error, "#{expression_message("else")} at line 1, column 1"}
    end
  end

  describe "'while' used as a variable name, from every entry point" do
    test "Predicator.parse/2 reports the expression-position message" do
      assert Predicator.parse("while = 3") == {:error, expression_message("while"), 1, 1}
    end

    test "Predicator.parse_program/2 - 'while' is consumed as the keyword, not a variable name" do
      # Phase 2: `while` now opens a real while_statement, so "while = 3"
      # fails where the condition expression meets the bare "=" - the same
      # fix-it-free rejection any invalid condition gets, not a
      # statement-keyword message.
      assert Predicator.parse_program("while = 3") ==
               {:error,
                "Expected number, string, boolean, date, datetime, identifier, function call, " <>
                  "list, object, or '(' but found '='", 1, 7}
    end

    test "Predicator.evaluate/3" do
      assert {:error, %ParseError{message: message, position: {1, 1}}} =
               Predicator.evaluate("while = 3", %{})

      assert message == expression_message("while")
    end

    test "Predicator.compile/1" do
      assert Predicator.compile("while = 3") ==
               {:error, "#{expression_message("while")} at line 1, column 1"}
    end
  end

  @user_if_message "Expected property name after '.' but found 'if'"

  describe "'user.if' as a bare property name, from every entry point" do
    test "Predicator.parse/2" do
      assert Predicator.parse("user.if") == {:error, @user_if_message, 1, 6}
    end

    test "Predicator.parse_program/2" do
      assert Predicator.parse_program("user.if") == {:error, @user_if_message, 1, 6}
    end

    test "Predicator.evaluate/3" do
      assert {:error, %ParseError{message: @user_if_message, position: {1, 6}}} =
               Predicator.evaluate("user.if", %{})
    end

    test "Predicator.compile/1" do
      assert Predicator.compile("user.if") == {:error, "#{@user_if_message} at line 1, column 6"}
    end
  end

  @if_key_message "Expected identifier or string for object key but found 'if'"

  describe "'{if: 1}' as a bare object key, from every entry point" do
    test "Predicator.parse/2" do
      assert Predicator.parse("{if: 1}") == {:error, @if_key_message, 1, 2}
    end

    test "Predicator.parse_program/2" do
      assert Predicator.parse_program("{if: 1}") == {:error, @if_key_message, 1, 2}
    end

    test "Predicator.evaluate/3" do
      assert {:error, %ParseError{message: @if_key_message, position: {1, 2}}} =
               Predicator.evaluate("{if: 1}", %{})
    end

    test "Predicator.compile/1" do
      assert Predicator.compile("{if: 1}") == {:error, "#{@if_key_message} at line 1, column 2"}
    end
  end

  test ~s({"if": 1} still parses - a quoted object key is not a reserved word) do
    assert {:ok,
            {:object, [{{:object_key, "if", :double, _key_pos}, {:literal, 1, _value_pos}}], _pos}} =
             Predicator.parse(~s({"if": 1}))
  end

  describe "the statement-position messages, through Predicator.parse_program/2" do
    test "'while x { }' parses - while is a statement now, not a reserved-but-unsupported keyword" do
      assert {:ok,
              {:program, [{:while, {:identifier, "x", {1, 7}}, {:block, [], {1, 9}}, {1, 1}}],
               {1, 1}}} =
               Predicator.parse_program("while x { }")
    end

    test "'else { }'" do
      assert Predicator.parse_program("else { }") == {:error, @else_statement_message, 1, 1}
    end
  end

  describe "'while' at expression position, through Predicator.parse/2" do
    test "'while > 1' gets the statement-keyword message naming parse_program/2, same as 'if'/'else'" do
      assert Predicator.parse("while > 1") == {:error, expression_message("while"), 1, 1}
    end
  end
end
