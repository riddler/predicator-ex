defmodule Predicator.EqualsGrammarBreakTest do
  use ExUnit.Case, async: true

  alias Predicator.Errors.ParseError
  alias Predicator.Parser

  @fixit_message "'=' is not an equality operator - use '==' for equality. " <>
                   "Assignment is only valid at the start of a statement."

  describe "the fix-it error, from every entry point" do
    test "Parser.parse/2" do
      {:ok, tokens} = Predicator.Lexer.tokenize("a = 1")
      assert {:error, @fixit_message, 1, 3, _span} = Parser.parse(tokens)
    end

    test "Predicator.parse/2" do
      assert {:error, @fixit_message, 1, 3, _span} = Predicator.parse("a = 1")
    end

    test "Predicator.evaluate/3" do
      assert {:error, %ParseError{message: @fixit_message, position: {1, 3}}} =
               Predicator.evaluate("a = 1", %{"a" => 1})
    end

    test "Predicator.evaluate!/3 raises" do
      assert_raise RuntimeError, ~r/#{Regex.escape(@fixit_message)}/, fn ->
        Predicator.evaluate!("a = 1", %{"a" => 1})
      end
    end

    test "Predicator.compile/1" do
      assert {:error, %ParseError{message: @fixit_message, position: {1, 3}}} =
               Predicator.compile("a = 1")
    end

    test "Predicator.context_assign/4" do
      assert {:error, %ParseError{message: @fixit_message, position: {1, 3}}} =
               Predicator.context_assign(%{}, "a = 1", 5)
    end
  end

  describe "the fix-it error from nested expression positions" do
    test "a parenthesized subexpression" do
      assert {:error, @fixit_message, 1, 4, _span} = Predicator.parse("(a = 1) and b")
    end

    test "a list element" do
      assert {:error, @fixit_message, 1, 4, _span} = Predicator.parse("[a = 1]")
    end

    test "a function argument" do
      assert {:error, @fixit_message, 1, 7, _span} = Predicator.parse("len(a = 1)")
    end

    test "a bracket key" do
      assert {:error, @fixit_message, 1, 5, _span} = Predicator.parse("x[a = 1]")
    end

    test "an object value" do
      assert {:error, @fixit_message, 1, 7, _span} = Predicator.parse("{k: a = 1}")
    end
  end

  describe "other operators are unaffected" do
    test "==" do
      assert {:ok, {:comparison, :equal_equal, _left, _right, _pos}} = Predicator.parse("a == 1")
    end

    test "===" do
      assert {:ok, {:comparison, :strict_eq, _left, _right, _pos}} = Predicator.parse("a === 1")
    end

    test "!=" do
      assert {:ok, {:comparison, :ne, _left, _right, _pos}} = Predicator.parse("a != 1")
    end

    test "!==" do
      assert {:ok, {:comparison, :strict_ne, _left, _right, _pos}} = Predicator.parse("a !== 1")
    end

    test ">=" do
      assert {:ok, {:comparison, :gte, _left, _right, _pos}} = Predicator.parse("a >= 1")
    end

    test "<=" do
      assert {:ok, {:comparison, :lte, _left, _right, _pos}} = Predicator.parse("a <= 1")
    end
  end

  test "a `=` inside a string literal is still just text" do
    assert Predicator.parse("a == '='") ==
             {:ok,
              {:comparison, :equal_equal, {:identifier, "a", {1, 1}},
               {:string_literal, "=", :single, {1, 6}}, {1, 3}}}
  end

  test ~s(a hand-built {:comparison, :eq, ...} AST still compiles to ["compare", "EQ"]) do
    ast = {:comparison, :eq, {:identifier, "a", nil}, {:literal, 1, nil}, nil}

    assert Predicator.Compiler.to_instructions(ast) == [
             ["load", "a"],
             ["lit", 1],
             ["compare", "EQ"]
           ]
  end

  describe "the removed config key is inert" do
    setup do
      on_exit(fn -> Application.delete_env(:predicator, :deprecation_warnings) end)
      :ok
    end

    test "setting deprecation_warnings: false has no effect and logs nothing" do
      Application.put_env(:predicator, :deprecation_warnings, false)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:error, @fixit_message, 1, 3, _span} = Predicator.parse("a = 1")
        end)

      assert log == ""
    end
  end
end
