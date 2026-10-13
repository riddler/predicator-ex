defmodule Predicator.AnalysisTest do
  use ExUnit.Case, async: true

  alias Predicator.Analysis
  alias Predicator.Errors.{EvaluationError, ParseError}

  doctest Predicator.Analysis

  defp paths({:ok, items}), do: Enum.map(items, & &1.path)

  describe "references/1" do
    test "lists every occurrence in source order, duplicates included" do
      assert paths(Analysis.references("a > b and a < c")) == [["a"], ["b"], ["a"], ["c"]]
    end

    test "a literal key folds to a segment; any other key is dynamic" do
      assert paths(Analysis.references("a['s'][2][x][1.5][true][-1]")) ==
               [["a", "s", 2, :dynamic, :dynamic, :dynamic, :dynamic], ["x"]]
    end

    test "the path continues past a dynamic segment" do
      assert paths(Analysis.references("rows[i].cells[j].value")) ==
               [["rows", :dynamic, "cells", :dynamic, "value"], ["i"], ["j"]]
    end

    test "a chain rooted at a call or a literal reads no variable" do
      assert paths(Analysis.references("f(x).y")) == [["x"]]
      assert paths(Analysis.references("[a, b][i]")) == [["a"], ["b"], ["i"]]
      assert paths(Analysis.references("{k: v}.k")) == [["v"]]
    end

    test "an object literal's keys are not reads" do
      assert paths(Analysis.references("{name: first, 'other': second}")) ==
               [["first"], ["second"]]
    end

    test "a path's position is its root's point, or the whole chain's span" do
      assert Analysis.references("1 < a.b[0]") ==
               {:ok, [%{path: ["a", "b", 0], position: {1, 5}}]}

      {:ok, ast} = Predicator.parse("1 < a.b[0]", spans: true)

      assert Analysis.references(ast) ==
               {:ok, [%{path: ["a", "b", 0], position: {{1, 5}, {1, 11}}}]}
    end

    test "a hand-built AST with no positions answers nil positions" do
      ast = {:property_access, {:identifier, "a", nil}, "b", nil}
      assert Analysis.references(ast) == {:ok, [%{path: ["a", "b"], position: nil}]}
    end

    test "a program's reads include its bracket keys and values, never its stores" do
      {:ok, program} = Predicator.parse_program("a[k].b = c; d = a.b")
      assert paths(Analysis.references(program)) == [["k"], ["c"], ["a", "b"]]
    end

    test "a single statement or block is accepted" do
      {:ok, {:program, [assignment], _pos}} = Predicator.parse_program("x = y")
      assert paths(Analysis.references(assignment)) == [["y"]]
      assert paths(Analysis.references({:block, [assignment], nil})) == [["y"]]
    end

    test "if and while read their conditions and bodies" do
      {:ok, program} = Predicator.parse_program("while i < n { if ok { t = t + i } }")
      assert paths(Analysis.references(program)) == [["i"], ["n"], ["ok"], ["t"], ["i"]]
    end
  end

  describe "calls/1" do
    test "lists nested calls outer first, with arity" do
      assert {:ok, calls} = Analysis.calls("a(b(), c(d(1), 2)) or e(x)")

      assert Enum.map(calls, &{&1.name, &1.arity}) ==
               [{"a", 2}, {"b", 0}, {"c", 2}, {"d", 1}, {"e", 1}]
    end

    test "a call in an assignment's key or value is listed" do
      {:ok, program} = Predicator.parse_program("m[key(k)] = val(v)")
      assert {:ok, calls} = Analysis.calls(program)
      assert Enum.map(calls, & &1.name) == ["key", "val"]
    end

    test "the instruction form orders calls by source" do
      {:ok, instructions} = Predicator.compile("f(g(1), h(i(2)))")
      assert {:ok, calls} = Analysis.calls(instructions)
      assert Enum.map(calls, & &1.name) == ["f", "g", "h", "i"]
    end
  end

  describe "assignments/1" do
    test "a source string is read as a program; an expression stores nothing" do
      assert paths(Analysis.assignments("a = 1; b.c = a")) == [["a"], ["b", "c"]]
      assert Analysis.assignments("a == 1") == {:ok, []}
      assert paths(Analysis.references("a == 1")) == [["a"]]
    end

    test "the position is the root's point, or the assignment's span" do
      {:ok, points} = Predicator.parse_program("x = 1; a.b[c] = 2")
      {:ok, spans} = Predicator.parse_program("x = 1; a.b[c] = 2", spans: true)

      assert Analysis.assignments(points) ==
               {:ok,
                [
                  %{path: ["x"], position: {1, 1}},
                  %{path: ["a", "b", :dynamic], position: {1, 8}}
                ]}

      assert Analysis.assignments(spans) ==
               {:ok,
                [
                  %{path: ["x"], position: {{1, 1}, {1, 6}}},
                  %{path: ["a", "b", :dynamic], position: {{1, 8}, {1, 18}}}
                ]}
    end

    test "a hand-built location the parser never builds is one dynamic segment" do
      ast =
        {:assignment, {:function_call, "f", [{:identifier, "x", nil}], nil}, {:literal, 1, nil},
         nil}

      assert Analysis.assignments(ast) == {:ok, [%{path: [:dynamic], position: nil}]}
      assert paths(Analysis.references(ast)) == [["x"]]
      assert {:ok, [%{name: "f"}]} = Analysis.calls(ast)
    end
  end

  describe "instruction lists" do
    test "the retired and/or read both operands" do
      list = [["load", "a"], ["load", "b"], ["and"], ["load", "c"], ["or"]]
      assert paths(Analysis.references(list)) == [["a"], ["b"], ["c"]]
    end

    test "a value left on the stack is read" do
      assert paths(Analysis.references([["load", "a"], ["access", "b"]])) == [["a", "b"]]
    end

    test "a list that underflows is read as far as it goes" do
      assert Analysis.references([["access", "x"], ["compare", "EQ"]]) == {:ok, []}

      assert Analysis.assignments([["store", 2]]) ==
               {:ok, [%{path: [:dynamic, :dynamic], position: nil}]}
    end

    test "store 0 stores an empty path" do
      assert Analysis.assignments([["lit", 1], ["store", 0]]) ==
               {:ok, [%{path: [], position: nil}]}
    end

    test "a load segment in a store is dynamic and read" do
      list = [["lit", "a"], ["load", "k"], ["lit", 1], ["store", 2]]
      assert paths(Analysis.assignments(list)) == [["a", :dynamic]]
      assert paths(Analysis.references(list)) == [["k"]]
    end

    test "an unknown opcode is refused with the evaluator's reason" do
      assert {:error, %EvaluationError{reason: "unknown_instruction", operation: :analysis}} =
               Analysis.references([["load", "a"], ["nope"]])
    end

    test "an operand of the wrong shape is refused" do
      for bad <- [["load", 5], ["call", "f", -1], ["jump", 0], ["store", "x"], "load", []] do
        assert {:error, %EvaluationError{reason: "unknown_instruction"}} =
                 Analysis.calls([bad]),
               inspect(bad)
      end
    end

    test "a compiled envelope without a table answers nil positions" do
      compiled = Predicator.Compiled.new([["load", "a"], ["call", "f", 1]])

      assert Analysis.references(compiled) == {:ok, [%{path: ["a"], position: nil}]}
      assert Analysis.calls(compiled) == {:ok, [%{name: "f", arity: 1, position: nil}]}
    end
  end

  describe "source strings" do
    test "a source that does not parse answers the compile error" do
      assert {:error, %ParseError{} = error} = Analysis.references("limit >")
      assert {:error, ^error} = Predicator.compile("limit >")
      assert {:error, %ParseError{}} = Analysis.calls("f(")
      assert {:error, %ParseError{}} = Analysis.assignments("@")
    end
  end
end
