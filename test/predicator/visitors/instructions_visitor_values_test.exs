defmodule Predicator.Visitors.InstructionsVisitorValuesTest do
  use ExUnit.Case, async: true

  alias Predicator.Visitors.InstructionsVisitor

  describe "visit/2 - duration nodes" do
    test "generates duration instruction for simple duration" do
      ast = {:duration, [{5, "d"}], nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["duration", [[5, "d"]]]]
    end

    test "generates duration instruction for multiple units" do
      ast = {:duration, [{1, "d"}, {8, "h"}, {30, "m"}], nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["duration", [[1, "d"], [8, "h"], [30, "m"]]]]
    end

    test "generates duration instruction for all unit types" do
      ast =
        {:duration, [{2, "y"}, {3, "mo"}, {4, "w"}, {5, "d"}, {6, "h"}, {7, "m"}, {8, "s"}], nil}

      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               [
                 "duration",
                 [[2, "y"], [3, "mo"], [4, "w"], [5, "d"], [6, "h"], [7, "m"], [8, "s"]]
               ]
             ]
    end

    test "generates duration instruction for long unit names" do
      ast = {:duration, [{1, "year"}, {2, "months"}, {3, "weeks"}], nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["duration", [[1, "year"], [2, "months"], [3, "weeks"]]]]
    end

    test "generates duration instruction for zero values" do
      ast = {:duration, [{0, "d"}, {0, "h"}], nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["duration", [[0, "d"], [0, "h"]]]]
    end

    test "generates duration instruction for large values" do
      ast = {:duration, [{999, "y"}, {365, "d"}], nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["duration", [[999, "y"], [365, "d"]]]]
    end
  end

  describe "visit/2 - relative date nodes" do
    test "generates instructions for relative date with ago" do
      duration_ast = {:duration, [{1, "d"}, {8, "h"}], nil}
      ast = {:relative_date, duration_ast, :ago, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["duration", [[1, "d"], [8, "h"]]], ["relative_date", "ago"]]
    end

    test "generates instructions for relative date with future" do
      duration_ast = {:duration, [{2, "h"}, {30, "m"}], nil}
      ast = {:relative_date, duration_ast, :future, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["duration", [[2, "h"], [30, "m"]]], ["relative_date", "future"]]
    end

    test "generates instructions for relative date with next" do
      duration_ast = {:duration, [{1, "w"}], nil}
      ast = {:relative_date, duration_ast, :next, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["duration", [[1, "w"]]], ["relative_date", "next"]]
    end

    test "generates instructions for relative date with last" do
      duration_ast = {:duration, [{6, "mo"}], nil}
      ast = {:relative_date, duration_ast, :last, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["duration", [[6, "mo"]]], ["relative_date", "last"]]
    end

    test "generates instructions for complex relative date" do
      duration_ast = {:duration, [{1, "y"}, {2, "mo"}, {3, "d"}], nil}
      ast = {:relative_date, duration_ast, :ago, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["duration", [[1, "y"], [2, "mo"], [3, "d"]]], ["relative_date", "ago"]]
    end

    test "generates instructions for relative date in comparison" do
      duration_ast = {:duration, [{1, "d"}], nil}
      relative_date_ast = {:relative_date, duration_ast, :ago, nil}
      ast = {:comparison, :gt, {:identifier, "created_at", nil}, relative_date_ast, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "created_at"],
               ["duration", [[1, "d"]]],
               ["relative_date", "ago"],
               ["compare", "GT"]
             ]
    end

    test "generates instructions for complex expression with multiple relative dates" do
      # created_at > 1d ago AND updated_at < 1h from now
      created_duration = {:duration, [{1, "d"}], nil}
      created_relative = {:relative_date, created_duration, :ago, nil}

      created_comparison =
        {:comparison, :gt, {:identifier, "created_at", nil}, created_relative, nil}

      updated_duration = {:duration, [{1, "h"}], nil}
      updated_relative = {:relative_date, updated_duration, :future, nil}

      updated_comparison =
        {:comparison, :lt, {:identifier, "updated_at", nil}, updated_relative, nil}

      ast = {:logical_and, created_comparison, updated_comparison, nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "created_at"],
               ["duration", [[1, "d"]]],
               ["relative_date", "ago"],
               ["compare", "GT"],
               ["jump_if_falsy_or_pop", 5],
               ["load", "updated_at"],
               ["duration", [[1, "h"]]],
               ["relative_date", "future"],
               ["compare", "LT"]
             ]
    end
  end

  describe "visit/2 - list nodes" do
    test "all-literal integer list compiles to a single lit instruction" do
      ast = {:list, [{:literal, 1, nil}, {:literal, 2, nil}, {:literal, 3, nil}], nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["lit", [1, 2, 3]]]
    end

    test "all-literal string list compiles to a single lit instruction" do
      ast =
        {:list, [{:string_literal, "a", :double, nil}, {:string_literal, "b", :double, nil}], nil}

      result = InstructionsVisitor.visit(ast, [])

      assert result == [["lit", ["a", "b"]]]
    end

    test "empty list compiles to a single lit instruction" do
      ast = {:list, [], nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["lit", []]]
    end

    test "identifier-only list compiles to make_list" do
      ast = {:list, [{:identifier, "x", nil}, {:identifier, "y", nil}], nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["load", "x"], ["load", "y"], ["make_list", 2]]
    end

    test "list with an arithmetic element compiles to make_list" do
      ast =
        {:list,
         [
           {:arithmetic, :add, {:identifier, "x", nil}, {:literal, 1, nil}, nil},
           {:identifier, "y", nil}
         ], nil}

      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "x"],
               ["lit", 1],
               ["add"],
               ["load", "y"],
               ["make_list", 2]
             ]
    end

    test "mixed literal and non-literal list compiles to make_list" do
      ast = {:list, [{:literal, 1, nil}, {:identifier, "x", nil}], nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["lit", 1], ["load", "x"], ["make_list", 2]]
    end

    test "nested list with a non-literal outer element compiles to make_list" do
      ast =
        {:list, [{:list, [{:literal, 1, nil}, {:literal, 2, nil}], nil}, {:identifier, "x", nil}],
         nil}

      result = InstructionsVisitor.visit(ast, [])

      assert result == [["lit", [1, 2]], ["load", "x"], ["make_list", 2]]
    end

    test "list with a function call element compiles to make_list" do
      ast =
        {:list,
         [
           {:function_call, "len", [{:identifier, "name", nil}], nil},
           {:literal, 3, nil}
         ], nil}

      result = InstructionsVisitor.visit(ast, [])

      assert result == [
               ["load", "name"],
               ["call", "len", 1],
               ["lit", 3],
               ["make_list", 2]
             ]
    end
  end

  describe "visit/2 - cast nodes" do
    test "generates a cast instruction after the operand's instructions" do
      ast = {:cast, {:identifier, "x", nil}, "integer", nil}
      result = InstructionsVisitor.visit(ast, [])

      assert result == [["load", "x"], ["cast", "integer"]]
    end

    test "a chained cast produces two cast instructions in source order" do
      ast =
        {:cast, {:cast, {:string_literal, "2026-08-09", :double, nil}, "date", nil}, "datetime",
         nil}

      result = InstructionsVisitor.visit(ast, [])

      assert result == [["lit", "2026-08-09"], ["cast", "date"], ["cast", "datetime"]]
    end

    test "a cast over a nested expression visits the operand first" do
      ast =
        {:cast, {:arithmetic, :add, {:identifier, "x", nil}, {:literal, 1, nil}, nil}, "integer",
         nil}

      result = InstructionsVisitor.visit(ast, [])

      assert result == [["load", "x"], ["lit", 1], ["add"], ["cast", "integer"]]
    end
  end
end
