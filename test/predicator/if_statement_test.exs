defmodule Predicator.IfStatementTest do
  use ExUnit.Case, async: true

  describe "shape" do
    test "if with no else" do
      assert Predicator.parse_program("if c { a = 1 }") ==
               {:ok,
                {:program,
                 [
                   {:if, {:identifier, "c", {1, 4}},
                    {:block,
                     [{:assignment, {:identifier, "a", {1, 8}}, {:literal, 1, {1, 12}}, {1, 10}}],
                     {1, 6}}, nil, {1, 1}}
                 ], {1, 1}}}
    end

    test "if with an else" do
      assert Predicator.parse_program("if c { a = 1 } else { a = 2 }") ==
               {:ok,
                {:program,
                 [
                   {:if, {:identifier, "c", {1, 4}},
                    {:block,
                     [{:assignment, {:identifier, "a", {1, 8}}, {:literal, 1, {1, 12}}, {1, 10}}],
                     {1, 6}},
                    {:block,
                     [
                       {:assignment, {:identifier, "a", {1, 23}}, {:literal, 2, {1, 27}}, {1, 25}}
                     ], {1, 21}}, {1, 1}}
                 ], {1, 1}}}
    end

    test "chained else-if desugars to a synthetic block with no chain node" do
      source = "if a { x = 1 } else if b { x = 2 } else if c { x = 3 } else { x = 4 }"

      assert {:ok, {:program, [{:if, _cond_a, _then_a, else_a, _pos_a}], _prog_pos}} =
               Predicator.parse_program(source)

      # else_a is a single-statement block whose sole statement is the
      # nested `if b ...`, per ADR-0013 - not a chain node.
      assert {:block, [{:if, {:identifier, "b", _cond_pos_b}, _then_b, else_b, _pos_b}],
              _block_pos_a} = else_a

      assert {:block, [{:if, {:identifier, "c", _cond_pos_c}, _then_c, else_c, _pos_c}],
              _block_pos_b} = else_b

      assert {:block, [{:assignment, _lhs, _rhs, _assignment_pos}], _block_pos_c} = else_c
    end

    test "nesting an if inside both a then and an else block" do
      source = "if a { if b { x = 1 } } else { if c { x = 2 } }"

      assert {:ok,
              {:program,
               [
                 {:if, {:identifier, "a", _cond_pos},
                  {:block, [{:if, _nested_cond, _nested_then, _nested_else, _nested_pos}],
                   _then_pos},
                  {:block, [{:if, _else_cond, _else_then, _else_nested_else, _else_nested_pos}],
                   _else_pos}, _pos}
               ], _prog_pos}} = Predicator.parse_program(source)
    end

    test "multi-statement blocks" do
      assert {:ok,
              {:program,
               [
                 {:if, _cond,
                  {:block,
                   [
                     {:assignment, _lhs_a, _rhs_a, _pos_a},
                     {:assignment, _lhs_b, _rhs_b, _pos_b}
                   ], _block_pos}, nil, _if_pos}
               ], _prog_pos}} = Predicator.parse_program("if c { a = 1; b = 2 }")
    end

    test "empty then block" do
      assert Predicator.parse_program("if c { }") ==
               {:ok,
                {:program, [{:if, {:identifier, "c", {1, 4}}, {:block, [], {1, 6}}, nil, {1, 1}}],
                 {1, 1}}}
    end

    test "an empty else block is distinguishable from an absent one" do
      assert {:ok, {:program, [{:if, _cond, _then, nil, _pos}], _prog_pos}} =
               Predicator.parse_program("if c { }")

      assert {:ok, {:program, [{:if, _cond, _then, {:block, [], _else_pos}, _pos}], _prog_pos}} =
               Predicator.parse_program("if c { } else { }")
    end
  end

  describe "separators" do
    test "no ';' is required after a closing '}'" do
      assert {:ok,
              {:program, [{:if, _cond, _then, nil, _if_pos}, {:assignment, _lhs, _rhs, _pos}],
               _prog_pos}} = Predicator.parse_program("if c { } a = 1")
    end

    test "an explicit ';' after a closing '}' is still accepted" do
      assert {:ok,
              {:program, [{:if, _cond, _then, nil, _if_pos}, {:assignment, _lhs, _rhs, _pos}],
               _prog_pos}} = Predicator.parse_program("if c { }; a = 1")
    end

    test "statements inside a block are ';'-separated" do
      assert {:ok,
              {:program,
               [
                 {:if, _cond,
                  {:block,
                   [
                     {:assignment, _lhs_a, _rhs_a, _pos_a},
                     {:assignment, _lhs_b, _rhs_b, _pos_b}
                   ], _block_pos}, nil, _if_pos}
               ], _prog_pos}} = Predicator.parse_program("if c { a = 1; b = 2 }")
    end

    test "a trailing ';' inside a block is allowed" do
      assert {:ok,
              {:program,
               [
                 {:if, _cond, {:block, [{:assignment, _lhs, _rhs, _pos}], _block_pos}, nil,
                  _if_pos}
               ], _prog_pos}} = Predicator.parse_program("if c { a = 1; }")
    end

    test "';;' inside a block is still an error" do
      assert Predicator.parse_program("if c { ;; }") ==
               {:error,
                "Expected number, string, boolean, date, datetime, identifier, function call, " <>
                  "list, object, or '(' but found ';'", 1, 8}
    end
  end

  describe "conditions" do
    test "a comparison condition" do
      assert {:ok,
              {:program, [{:if, {:comparison, :gt, _left, _right, _op_pos}, _then, nil, _if_pos}],
               _prog_pos}} = Predicator.parse_program("if a > 1 { }")
    end

    test "an AND/OR condition" do
      assert {:ok,
              {:program, [{:if, {:logical_and, _left, _right, _op_pos}, _then, nil, _if_pos}],
               _prog_pos}} = Predicator.parse_program("if a AND b { }")

      assert {:ok,
              {:program, [{:if, {:logical_or, _left, _right, _op_pos}, _then, nil, _if_pos}],
               _prog_pos}} = Predicator.parse_program("if a OR b { }")
    end

    test "a parenthesized condition" do
      assert {:ok,
              {:program, [{:if, {:identifier, "a", _cond_pos}, _then, nil, _if_pos}], _prog_pos}} =
               Predicator.parse_program("if (a) { }")
    end

    test "a function-call condition" do
      assert {:ok,
              {:program, [{:if, {:function_call, "f", [], _cond_pos}, _then, nil, _if_pos}],
               _prog_pos}} = Predicator.parse_program("if f() { }")
    end

    test "an object-literal condition - '{' disambiguates by position" do
      assert {:ok,
              {:program,
               [{:if, {:object, [], _cond_pos}, {:block, [], _block_pos}, nil, _if_pos}],
               _prog_pos}} = Predicator.parse_program("if {} { }")
    end
  end

  describe "errors with positions" do
    test "a missing '{' after the condition" do
      assert Predicator.parse_program("if c a = 1") ==
               {:error, "Expected '{' to open a block but found identifier 'a'", 1, 6}
    end

    test "an unterminated block reports the end-of-input position" do
      assert Predicator.parse_program("if c { a = 1") ==
               {:error, "Expected '}' to close the block but found end of input", 1, 13}
    end

    test "'if c { } else' with a missing else block" do
      assert Predicator.parse_program("if c { } else") ==
               {:error, "Expected '{' to open a block but found end of input", 1, 14}
    end

    test "'if { }' - the condition parses as an object, then there is no block" do
      assert Predicator.parse_program("if { }") ==
               {:error, "Expected '{' to open a block but found end of input", 1, 7}
    end

    test "'else { }' alone" do
      assert Predicator.parse_program("else { }") ==
               {:error, "Unexpected 'else' - an 'else' block must follow an 'if' block.", 1, 1}
    end

    test "'while c { }' parses - while is a statement now, not a reserved-but-unsupported keyword" do
      assert {:ok,
              {:program, [{:while, {:identifier, "c", {1, 7}}, {:block, [], {1, 9}}, {1, 1}}],
               {1, 1}}} = Predicator.parse_program("while c { }")
    end

    test "a dangling 'else' after a completed statement gets the dedicated message, not the generic one" do
      assert Predicator.parse_program("x = 1\nelse { y = 2 }") ==
               {:error, "Unexpected 'else' - an 'else' block must follow an 'if' block.", 2, 1}
    end

    test "a dangling 'while' with no separator gets the generic unexpected-token message, not the reserved-word one - the walker only consumes it after a brace-terminated statement" do
      assert Predicator.parse_program("x = 1\nwhile y { z = 2 }") ==
               {:error, "Unexpected token 'while' after statement", 2, 1}
    end
  end

  describe "entry-point separation" do
    test "Predicator.parse/2 rejects 'if c { }' with the statement-keyword message" do
      assert Predicator.parse("if c { }") ==
               {:error,
                "'if' is a statement keyword, not an expression - control flow is only valid " <>
                  "in a program (Predicator.parse_program/2).", 1, 1}
    end

    test "Predicator.parse_program/2 accepts 'if c { }'" do
      assert {:ok, {:program, [{:if, _cond, _then, nil, _if_pos}], _prog_pos}} =
               Predicator.parse_program("if c { }")
    end
  end

  test "Predicator.parse_program(\"if a { b = 1 } else if c { b = 2 } else { b = 3 }\") has no chain node" do
    assert {:ok,
            {:program,
             [
               {:if, {:identifier, "a", _cond_pos_a},
                {:block, [{:assignment, _lhs_a, _rhs_a, _pos_a}], _then_pos_a},
                {:block,
                 [
                   {:if, {:identifier, "c", _cond_pos_c},
                    {:block, [{:assignment, _lhs_b, _rhs_b, _pos_b}], _then_pos_c},
                    {:block, [{:assignment, _lhs_c, _rhs_c, _pos_c}], _else_pos_c}, _if_pos_c}
                 ], _else_block_pos_a}, _if_pos_a}
             ],
             _prog_pos}} =
             Predicator.parse_program("if a { b = 1 } else if c { b = 2 } else { b = 3 }")
  end
end
