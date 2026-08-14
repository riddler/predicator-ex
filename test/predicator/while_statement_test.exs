defmodule Predicator.WhileStatementTest do
  @moduledoc """
  Parsing coverage for the `while_statement` production (px-3so.4 Phase 2,
  ADR-0013). Offsets and lowering live in
  `test/predicator/visitors/instructions_visitor_test.exs`; execution lives in
  `test/predicator/integration/while_execution_test.exs`; round-tripping
  through `StringVisitor` lives in
  `test/predicator/visitors/string_visitor_test.exs`.
  """

  use ExUnit.Case, async: true

  describe "shape" do
    test "an empty body" do
      assert {:ok,
              {:program, [{:while, {:identifier, "c", {1, 7}}, {:block, [], {1, 9}}, {1, 1}}],
               {1, 1}}} = Predicator.parse_program("while c { }")
    end

    test "a single-statement body" do
      assert {:ok,
              {:program,
               [
                 {:while, {:identifier, "c", {1, 7}},
                  {:block,
                   [{:assignment, {:identifier, "a", {1, 11}}, {:literal, 1, {1, 15}}, {1, 13}}],
                   {1, 9}}, {1, 1}}
               ], {1, 1}}} = Predicator.parse_program("while c { a = 1 }")
    end

    test "a multi-statement body" do
      assert {:ok,
              {:program,
               [
                 {:while, {:identifier, "c", _cond_pos},
                  {:block,
                   [
                     {:assignment, _lhs_a, _rhs_a, _pos_a},
                     {:assignment, _lhs_b, _rhs_b, _pos_b}
                   ], _block_pos}, _while_pos}
               ], _prog_pos}} = Predicator.parse_program("while c { a = 1; b = 2 }")
    end

    test "a while nested inside an if's then block" do
      assert {:ok,
              {:program,
               [
                 {:if, {:identifier, "a", _cond_pos},
                  {:block, [{:while, {:identifier, "b", _while_cond_pos}, _body, _while_pos}],
                   _then_pos}, nil, _if_pos}
               ], _prog_pos}} = Predicator.parse_program("if a { while b { } }")
    end

    test "an if nested inside a while's body" do
      assert {:ok,
              {:program,
               [
                 {:while, {:identifier, "a", _while_cond_pos},
                  {:block, [{:if, {:identifier, "b", _if_cond_pos}, _then, nil, _if_pos}],
                   _body_pos}, _while_pos}
               ], _prog_pos}} = Predicator.parse_program("while a { if b { } }")
    end

    test "a while nested inside a while" do
      assert {:ok,
              {:program,
               [
                 {:while, {:identifier, "a", _outer_cond_pos},
                  {:block,
                   [{:while, {:identifier, "b", _inner_cond_pos}, _inner_body, _inner_pos}],
                   _outer_body_pos}, _outer_pos}
               ], _prog_pos}} = Predicator.parse_program("while a { while b { } }")
    end

    test "a while followed by another statement, separated by ';'" do
      assert {:ok,
              {:program,
               [
                 {:while, {:identifier, "a", _cond_pos}, {:block, [], _body_pos}, _while_pos},
                 {:assignment, {:identifier, "x", _lhs_pos}, {:literal, 1, _rhs_pos}, _pos}
               ], _prog_pos}} = Predicator.parse_program("while a { }; x = 1")
    end

    test "a while followed by another statement, with no separator (brace-terminated)" do
      assert {:ok,
              {:program,
               [
                 {:while, {:identifier, "a", _cond_pos}, {:block, [], _body_pos}, _while_pos},
                 {:assignment, {:identifier, "x", _lhs_pos}, {:literal, 1, _rhs_pos}, _pos}
               ], _prog_pos}} = Predicator.parse_program("while a { } x = 1")
    end
  end

  describe "errors with positions" do
    test "a missing '{' after the condition" do
      assert {:error, "Expected '{' to open a block but found identifier 'a'", 1, 9, _span} =
               Predicator.parse_program("while c a = 1")
    end

    test "an unterminated block reports the end-of-input position" do
      assert {:error, "Expected '}' to close the block but found end of input", 1, 16, _span} =
               Predicator.parse_program("while c { a = 1")
    end
  end

  describe "entry-point separation" do
    test "Predicator.parse/2 rejects 'while c { }' with the statement-keyword message" do
      assert {:error,
              "'while' is a statement keyword, not an expression - control flow is only " <>
                "valid in a program (Predicator.parse_program/2).", 1, 1,
              _span} =
               Predicator.parse("while x { }")
    end

    test "Predicator.parse_program/2 accepts 'while c { }'" do
      assert {:ok, {:program, [{:while, _cond, _body, _while_pos}], _prog_pos}} =
               Predicator.parse_program("while c { }")
    end
  end
end
