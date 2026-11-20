defmodule Predicator.ContainmentTest do
  @moduledoc """
  Containment that answers a value for every operand (ADR-0021): `in` and
  `contains` on two strings are a substring test, every other pairing that is
  not a list container answers `:undefined`, and `a intersects b`, read by
  position, compiles to the `intersects` opcode.
  """

  use ExUnit.Case, async: true

  alias Predicator.Analysis
  alias Predicator.AST
  alias Predicator.Errors.EvaluationError
  alias Predicator.Instructions
  alias Predicator.Simple
  alias Predicator.Vocabulary

  defp eval(source, context \\ %{}), do: Predicator.evaluate(source, context)

  # One value of every kind that is neither a list nor a string, as a context
  # binding, so each reaches the opcode as a value rather than a literal.
  @wrong_containers [
    {:null, nil},
    {:number, 7},
    {:float, 1.5},
    {:boolean, true},
    {:date, ~D[2026-03-01]},
    {:datetime, ~U[2026-03-01 09:00:00Z]},
    {:object, %{"title" => "Dune"}}
  ]

  describe "in and contains on two strings" do
    test "are a substring test, and in mirrors contains" do
      assert eval(~s("abcdef" contains "cd")) == {:ok, true}
      assert eval(~s("cd" in "abcdef")) == {:ok, true}
      assert eval(~s("abcdef" contains "dc")) == {:ok, false}
      assert eval(~s("dc" in "abcdef")) == {:ok, false}
      assert eval(~s("Moby" contains "Moby Dick")) == {:ok, false}
    end

    test "are case-sensitive" do
      assert eval(~s(title contains "moby"), %{"title" => "Moby Dick"}) == {:ok, false}
      assert eval(~s("DICK" in title), %{"title" => "Moby Dick"}) == {:ok, false}
    end

    test "contain the empty string in every string" do
      assert eval(~s(title contains ""), %{"title" => "Moby Dick"}) == {:ok, true}
      assert eval(~s("" in "")) == {:ok, true}
    end

    test "match by code point, with no normalization" do
      assert eval(~s(branch contains "ü"), %{"branch" => "Zürich"}) == {:ok, true}
      assert eval(~s("ü" in branch), %{"branch" => "Zurich"}) == {:ok, false}
      # U+00EF is one code point; it does not hold an i
      assert eval(~s(word contains "i"), %{"word" => "naïve"}) == {:ok, false}
      # the decomposed form holds the i and a combining mark
      assert eval(~s(word contains "i"), %{"word" => "naïve"}) == {:ok, true}
    end
  end

  describe "a list container" do
    test "tests membership exactly as before, matching a string member whole" do
      assert eval(~s(["Moby Dick"] contains "Moby")) == {:ok, false}
      assert eval(~s("Moby" in ["Moby Dick"])) == {:ok, false}
      assert eval(~s("Moby Dick" in ["Moby Dick"])) == {:ok, true}
      assert eval("x in [y]", %{"x" => nil, "y" => nil}) == {:ok, true}
      assert eval("[#2026-03-01#] contains d", %{"d" => ~U[2026-03-01 00:00:00Z]}) == {:ok, true}
    end

    test "propagates an undefined operand as before" do
      assert eval("user.missing in [1]", %{"user" => %{}}) == {:ok, :undefined}
      assert eval("[1] contains user.missing", %{"user" => %{}}) == {:ok, :undefined}
      assert eval(~s(user.missing in "abc"), %{"user" => %{}}) == {:ok, :undefined}
    end
  end

  describe "every other pairing" do
    test "answers undefined for each wrong-shaped container, under both operators" do
      for {kind, container} <- @wrong_containers do
        assert eval("c contains n", %{"c" => container, "n" => 1}) == {:ok, :undefined},
               "contains, #{kind} container"

        assert eval("n in c", %{"c" => container, "n" => 1}) == {:ok, :undefined},
               "in, #{kind} container"
      end

      assert eval("3d contains 3") == {:ok, :undefined}
      assert eval("3 in 3d") == {:ok, :undefined}
    end

    test "answers undefined for a string container with a needle that is not a string" do
      for needle <- [1, 1.5, true, nil, [], %{}, ~D[2026-03-01]] do
        assert eval("c contains n", %{"c" => "abc", "n" => needle}) == {:ok, :undefined}
        assert eval("n in c", %{"c" => "abc", "n" => needle}) == {:ok, :undefined}
      end
    end

    test "never stops a program: an OR whose left side is false answers the right side" do
      assert eval(~s(false OR shelf contains "a"), %{"shelf" => nil}) == {:ok, :undefined}
      assert eval(~s(true OR shelf contains "a"), %{"shelf" => nil}) == {:ok, true}
    end

    test "produce no type mismatch from either opcode" do
      for {_kind, container} <- @wrong_containers,
          opcode <- ["in", "contains"] do
        assert {:ok, :undefined} =
                 Predicator.evaluate([["lit", 1], ["lit", container], [opcode]], %{})

        assert {:ok, :undefined} =
                 Predicator.evaluate([["lit", container], ["lit", 1], [opcode]], %{})
      end
    end
  end

  describe "parsing intersects" do
    test "reads by position into a membership node" do
      assert {:ok,
              {:membership, :intersects, {:identifier, "a", {1, 1}}, {:identifier, "b", {1, 14}},
               {1, 3}}} = Predicator.parse("a intersects b")

      assert {:ok, {:membership, :intersects, _left, _right, _pos}} =
               Predicator.parse("a INTERSECTS b")
    end

    test "a parenthesised right operand parses, though `intersects (` lexes as a function name" do
      assert {:ok,
              {:membership, :intersects, {:identifier, "a", _pos1}, {:identifier, "b", _pos2},
               _pos3}} = Predicator.parse("a intersects (b)")

      assert {:ok, {:membership, :intersects, _left, {:list, _items, _pos4}, _pos5}} =
               Predicator.parse("a intersects([1, 2])")
    end

    test "a mixed-case word is not the operator" do
      assert {:error, _message, 1, 3, _span} = Predicator.parse("a Intersects b")
    end

    test "sits at the precedence of in and contains" do
      assert {:ok, {:logical_and, {:membership, :intersects, _l1, _r1, _p1}, _right, _p2}} =
               Predicator.parse("a intersects b AND c")

      assert {:ok, {:logical_not, {:membership, :intersects, _l2, _r2, _p3}, _p4}} =
               Predicator.parse("not a intersects b")

      assert {:ok, {:membership, :intersects, {:arithmetic, :add, _a, _b, _p5}, _right2, _p6}} =
               Predicator.parse("a + b intersects c")
    end

    test "does not chain" do
      assert {:error, "Unexpected token identifier 'intersects' after expression", 1, 16, _s1} =
               Predicator.parse("a intersects b intersects c")

      assert {:error, _message, 1, 8, _s2} = Predicator.parse("a in b intersects c")
      assert {:error, _message2, 1, 16, _s3} = Predicator.parse("a intersects b in c")

      assert {:ok, {:comparison, :equal_equal, {:membership, :intersects, _l, _r, _p}, _t, _p2}} =
               Predicator.parse("(a intersects b) == true")
    end

    test "an operator with no right operand is a parse error" do
      assert {:error, _message, 1, 13, _span} = Predicator.parse("a intersects")
    end
  end

  describe "intersects stays an ordinary identifier everywhere else" do
    test "as a variable, a property, an object key and a function argument" do
      assert eval("intersects == 1", %{"intersects" => 1}) == {:ok, true}
      assert eval("intersects intersects [1]", %{"intersects" => [1]}) == {:ok, true}
      assert eval("loan.intersects", %{"loan" => %{"intersects" => 2}}) == {:ok, 2}
      assert eval("{intersects: 1}.intersects") == {:ok, 1}
      assert eval("upper(intersects)", %{"intersects" => "dune"}) == {:ok, "DUNE"}
    end

    test "as an assignment target, after a statement separator and after a block's brace" do
      assert {:ok, %Predicator.Context{data: %{"intersects" => 2}}} =
               Predicator.execute("x = 1; intersects = 2", %{})

      assert {:ok,
              {:program,
               [
                 {:if, _condition, _block, nil, _pos},
                 {:assignment, {:identifier, "intersects", _p1}, {:literal, 1, _p2}, _p3}
               ], _p4}} = Predicator.parse_program("if a { b } intersects = 1")
    end

    test "a function named intersects is still callable" do
      functions = %{"intersects" => {1, fn [x], _ctx -> {:ok, x} end}}

      assert Predicator.evaluate("intersects(5)", %{}, functions: functions) == {:ok, 5}
    end
  end

  describe "compiling intersects" do
    test "compiles left, then right, then the opcode" do
      assert Predicator.compile("a intersects b") ==
               {:ok, [["load", "a"], ["load", "b"], ["intersects"]]}
    end

    test "a list holding the opcode requires ISA v7, in tier 10" do
      {:ok, instructions} = Predicator.compile("a intersects [1, 2]")
      assert Instructions.required_isa(instructions) == {:ok, 7}
      assert Instructions.tier("intersects") == {:ok, 10}
    end

    test "the opcode carries the operator's position" do
      {:ok, compiled} = Predicator.compile_with_positions("a intersects b")
      assert compiled.positions[2] == {1, 3}
    end
  end

  describe "evaluating intersects" do
    test "is true when the two lists share a member under the equality in uses" do
      context = %{"loan" => %{"tags" => ["fiction", "poetry"]}}
      assert eval(~s(loan.tags intersects ["poetry", "drama"]), context) == {:ok, true}
      assert eval(~s(loan.tags intersects ["history", "drama"]), context) == {:ok, false}
      assert eval(~s([1, "a"] intersects ["1", true])) == {:ok, false}

      assert eval("[d] intersects [#2026-03-01#]", %{"d" => ~U[2026-03-01 00:00:00Z]}) ==
               {:ok, true}

      assert eval("[null] intersects [1, null]") == {:ok, true}
      assert eval("[missing] intersects [missing]") == {:ok, false}
    end

    test "is false for an empty list on either side" do
      assert eval("[] intersects [1]") == {:ok, false}
      assert eval("[1] intersects []") == {:ok, false}
      assert eval("[] intersects []") == {:ok, false}
    end

    test "is undefined for an undefined operand or any operand that is not a list" do
      assert eval("p.missing intersects [1]", %{"p" => %{}}) == {:ok, :undefined}
      assert eval("[1] intersects p.missing", %{"p" => %{}}) == {:ok, :undefined}
      assert eval(~s("abc" intersects "cde")) == {:ok, :undefined}

      for {kind, value} <- [{:string, "a"} | @wrong_containers] do
        assert eval("v intersects [1]", %{"v" => value}) == {:ok, :undefined}, "left #{kind}"
        assert eval("[1] intersects v", %{"v" => value}) == {:ok, :undefined}, "right #{kind}"
      end
    end

    test "refuses a short stack as insufficient operands" do
      assert {:error, %EvaluationError{reason: "insufficient_operands"}} =
               Predicator.evaluate([["lit", [1]], ["intersects"]], %{})
    end
  end

  describe "decompiling intersects" do
    test "round-trips, written in upper case as IN and CONTAINS are" do
      for source <- ["a intersects b", "a INTERSECTS (b)"] do
        {:ok, ast} = Predicator.parse(source)
        decompiled = Predicator.decompile(ast)
        assert decompiled == "a INTERSECTS b"
        assert Predicator.parse(decompiled) == Predicator.parse("a INTERSECTS b")
      end

      {:ok, ast} = Predicator.parse("(a intersects b) == true")
      assert Predicator.decompile(ast) == "(a INTERSECTS b) == true"
    end
  end

  describe "the reading surfaces" do
    test "Predicator.Analysis reads both operands, never the word" do
      source = "loan.tags intersects patron.interests"
      expected = [["loan", "tags"], ["patron", "interests"]]

      assert {:ok, refs} = Analysis.references(source)
      assert Enum.map(refs, & &1.path) == expected

      {:ok, instructions} = Predicator.compile(source)
      assert {:ok, refs} = Analysis.references(instructions)
      assert Enum.map(refs, & &1.path) == expected
    end

    test "Predicator.AST walks into both operands" do
      {:ok, ast} = Predicator.parse("f(x) intersects y")
      tags = AST.reduce(ast, [], fn node, acc -> [elem(node, 0) | acc] end)
      assert Enum.reverse(tags) == [:membership, :function_call, :identifier, :identifier]
    end

    test "Predicator.Vocabulary lists intersects under :membership, as an identifier, not a keyword" do
      entries = Enum.filter(Vocabulary.by_category(:membership), &(&1.token_type == :identifier))
      assert Enum.map(entries, & &1.lexeme) == ["intersects", "INTERSECTS"]

      for entry <- entries do
        assert entry.ast_op == :intersects
        assert entry.value_kinds == [:list]
        assert entry.canonical == (entry.lexeme == "INTERSECTS")
      end

      refute Enum.any?(Vocabulary.keywords(), &(&1.lexeme in ["intersects", "INTERSECTS"]))
    end

    test "Predicator.Simple admits intersects on a field path, both ways" do
      source = "loan.tags INTERSECTS ['poetry', 'drama']"

      assert {:ok,
              %Simple{
                clauses: [
                  {[root: "loan", property: "tags"], :intersects,
                   {:list, [{:string, "poetry", :single}, {:string, "drama", :single}]}}
                ]
              } = simple} = Simple.from_source(source)

      assert Simple.to_source(simple) == source
      assert Simple.well_formed?(simple)
      assert Simple.from_ast(Simple.to_ast(simple)) == {:ok, simple}
    end
  end
end
