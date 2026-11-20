defmodule Predicator.PresenceTest do
  @moduledoc """
  The presence operators of ADR-0021: `expr is [not] blank`, `present` and
  `defined`, read by position, compiled to one `presence` opcode, answering a
  boolean for every value.
  """

  use ExUnit.Case, async: true

  alias Predicator.Analysis
  alias Predicator.AST
  alias Predicator.Errors.EvaluationError
  alias Predicator.Errors.UndefinedVariableError
  alias Predicator.Instructions
  alias Predicator.Simple
  alias Predicator.Vocabulary

  @spellings [
    {"is blank", :blank, false, [["presence", "blank"]]},
    {"is not blank", :blank, true, [["presence", "blank"], ["not"]]},
    {"is present", :present, false, [["presence", "blank"], ["not"]]},
    {"is not present", :present, true, [["presence", "blank"]]},
    {"is defined", :defined, false, [["presence", "defined"]]},
    {"is not defined", :defined, true, [["presence", "defined"], ["not"]]}
  ]

  # The Unicode White_Space set ADR-0021 and docs/isa.md list by code point.
  @white_space [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x85, 0xA0, 0x1680] ++
                 Enum.to_list(0x2000..0x200A) ++ [0x2028, 0x2029, 0x202F, 0x205F, 0x3000]

  defp eval(source, context, opts \\ []), do: Predicator.evaluate(source, context, opts)

  describe "parsing" do
    test "each spelling parses to a presence node with its kind, negation and operand" do
      for {spelling, kind, negated?, _instructions} <- @spellings do
        assert {:ok, {:presence, ^kind, ^negated?, {:identifier, "title", {1, 1}}, {1, 7}}} =
                 Predicator.parse("title " <> spelling)
      end
    end

    test "the node spans from the operand to the end of the last word" do
      assert {:ok, {:presence, :blank, true, {:property_access, _part1, "note", _part2}, span}} =
               Predicator.parse("loan.note is not blank", spans: true)

      assert span == {{1, 1}, {1, 23}}
    end

    test "each word is accepted in lower case and in upper case, as in and IN are" do
      for source <- ["x IS BLANK", "x IS NOT PRESENT", "x is NOT defined", "x IS defined"] do
        assert {:ok, {:presence, _kind, _negated?, _operand, _pos}} = Predicator.parse(source),
               source
      end
    end

    test "a mixed-case word is not a presence word" do
      assert {:error, _message, 1, 3, _span} = Predicator.parse("x Is blank")
      assert {:error, _message, 1, 3, _span} = Predicator.parse("x is Blank")
    end

    test "the operators sit at comparison precedence" do
      assert {:ok, {:logical_not, {:presence, :blank, false, _part3, _part4}, _part5}} =
               Predicator.parse("not x is blank")

      assert {:ok,
              {:logical_and, {:presence, :blank, false, _part6, _part7},
               {:presence, :present, false, _part8, _part9},
               _part10}} =
               Predicator.parse("a is blank AND b is present")

      assert {:ok, {:logical_or, {:presence, :defined, true, _part11, _part12}, _part13, _part14}} =
               Predicator.parse("a is not defined OR b")

      assert {:ok,
              {:presence, :blank, false, {:arithmetic, :add, _part15, _part16, _part17}, _part18}} =
               Predicator.parse("a + 1 is blank")
    end

    test "the operators do not chain" do
      assert {:error, "Unexpected token identifier 'is' after expression", 1, 12, _span} =
               Predicator.parse("a is blank is blank")

      assert {:error, _message, 1, 8, _span} = Predicator.parse("a == b is blank")
      assert {:error, _message, 1, 12, _span} = Predicator.parse("a is blank == true")

      assert {:ok,
              {:comparison, :equal_equal, {:presence, :blank, false, _part19, _part20}, _part21,
               _part22}} =
               Predicator.parse("(a is blank) == true")
    end

    test "an incomplete or parenthesised suffix is the parse error it already was" do
      for source <- ["x is", "x is not", "x is foo", "x is not not blank", "x is not (blank)"] do
        assert {:error, "Unexpected token identifier 'is' after expression", 1, 3, _span} =
                 Predicator.parse(source),
               source
      end

      # `is` directly before `(` lexes as a function name, as any identifier does
      assert {:error, "Unexpected token function 'is' after expression", 1, 3, _span} =
               Predicator.parse("x is (blank)")
    end
  end

  describe "the words stay ordinary identifiers everywhere else" do
    test "as variable names, in every operand position" do
      assert {:ok, {:comparison, :equal_equal, {:identifier, "blank", _part23}, _part24, _part25}} =
               Predicator.parse("blank == 1")

      assert {:ok, {:presence, :blank, false, {:identifier, "is", _part26}, _part27}} =
               Predicator.parse("is is blank")

      assert {:ok, true} =
               eval("is == 1 AND blank == 2 AND present == 3 AND defined == 4", %{
                 "is" => 1,
                 "blank" => 2,
                 "present" => 3,
                 "defined" => 4
               })
    end

    test "as property names, object keys and function arguments" do
      assert {:ok, {:property_access, {:identifier, "is", _part28}, "defined", _part29}} =
               Predicator.parse("is.defined")

      assert {:ok, 0} = eval("parcel.is.blank", %{"parcel" => %{"is" => %{"blank" => 0}}})
      assert {:ok, %{"is" => 1, "blank" => 2}} = eval("{is: 1, blank: 2}", %{})
      assert {:ok, "DUNE"} = eval("upper(is)", %{"is" => "Dune"})
    end

    test "as assignment targets, and after a block's closing brace" do
      assert {:ok, %Predicator.Context{data: %{"is" => 1}}} = Predicator.execute("is = 1", %{})

      assert {:ok,
              {:program,
               [
                 {:if, _condition, _block, nil, _pos},
                 {:assignment, {:identifier, "is", _part30}, {:literal, 1, _part31}, _part32}
               ], _part33}} = Predicator.parse_program("if a { b } is = 1")
    end
  end

  describe "compiling" do
    test "each spelling compiles as ADR-0021's table states" do
      for {spelling, _kind, _negated?, instructions} <- @spellings do
        assert {:ok, [["load", "x"] | ^instructions]} = Predicator.compile("x " <> spelling)
      end
    end

    test "a list holding the opcode requires ISA v7" do
      assert Predicator.isa_version() == 7
      {:ok, instructions} = Predicator.compile("x is defined")
      assert {:ok, 7} = Instructions.required_isa(instructions)
      assert {:ok, 10} = Instructions.tier("presence")
    end

    test "both instructions carry the node's position" do
      {:ok, compiled} = Predicator.compile_with_positions("x is present")
      assert compiled.instructions == [["load", "x"], ["presence", "blank"], ["not"]]
      assert compiled.positions == %{0 => {1, 1}, 1 => {1, 3}, 2 => {1, 3}}
    end
  end

  describe "evaluating" do
    @kinds [
      {"undefined", :undefined, true, false},
      {"null", nil, true, true},
      {"the empty string", "", true, true},
      {"a non-empty string", "Dune", false, true},
      {"0", 0, false, true},
      {"0.0", 0.0, false, true},
      {"1", 1, false, true},
      {"true", true, false, true},
      {"false", false, false, true},
      {"an empty list", [], true, true},
      {"[\"\"]", [""], false, true},
      {"[null]", [nil], false, true},
      {"[[]]", [[]], false, true},
      {"an empty object", %{}, true, true},
      {"a one-key object", %{"title" => "Dune"}, false, true},
      {"a date", ~D[2026-11-20], false, true},
      {"a datetime", ~U[2026-11-20 09:30:00Z], false, true}
    ]

    test "every spelling answers as the record states for every value kind" do
      for {label, value, blank?, defined?} <- @kinds,
          {spelling, _kind, _negated?, _instructions} <- @spellings do
        expected =
          case spelling do
            "is blank" -> blank?
            "is not blank" -> not blank?
            "is present" -> not blank?
            "is not present" -> blank?
            "is defined" -> defined?
            "is not defined" -> not defined?
          end

        assert {:ok, ^expected} = eval("value " <> spelling, %{"value" => value}),
               "value #{spelling} for #{label}"
      end
    end

    test "a zero-length duration is defined and not blank" do
      assert {:ok, false} = eval("0d is blank", %{})
      assert {:ok, true} = eval("0d is defined", %{})
    end

    test "a string holding only White_Space code points is blank, each one alone and all together" do
      for code_point <- @white_space do
        assert {:ok, true} = eval("s is blank", %{"s" => <<code_point::utf8>>}),
               "U+#{Integer.to_string(code_point, 16)}"
      end

      all = for code_point <- @white_space, into: "", do: <<code_point::utf8>>
      assert {:ok, true} = eval("s is blank", %{"s" => all})
      assert length(@white_space) == 25
    end

    test "U+200B and U+FEFF are not White_Space, so a string of either is not blank" do
      assert {:ok, false} = eval("s is blank", %{"s" => "​"})
      assert {:ok, false} = eval("s is blank", %{"s" => "﻿"})
      assert {:ok, false} = eval("s is blank", %{"s" => "  a  "})
    end

    test "an unbound root is blank and not defined under the default on_unbound" do
      assert {:ok, true} = eval("missing is blank", %{})
      assert {:ok, false} = eval("missing is defined", %{})
      assert {:ok, true} = eval("loan.note is not defined", %{"loan" => %{}})
    end

    test "under on_unbound: :error the load keeps its own contract" do
      assert {:error, %UndefinedVariableError{variable: "missing"}} =
               eval("missing is blank", %{}, on_unbound: :error)
    end

    test "the opcode never errors on a value, and refuses a malformed instruction" do
      assert {:ok, true} = Predicator.evaluate([["lit", nil], ["presence", "blank"]], %{})

      assert {:error, %EvaluationError{reason: "unknown_instruction"}} =
               Predicator.evaluate([["lit", 1], ["presence", "present"]], %{})

      assert {:error, %EvaluationError{reason: "insufficient_operands"}} =
               Predicator.evaluate([["presence", "defined"]], %{})
    end
  end

  describe "decompiling" do
    test "each spelling round-trips as written" do
      for {spelling, _kind, _negated?, _instructions} <- @spellings do
        source = "patron.email " <> spelling
        {:ok, ast} = Predicator.parse(source)
        assert Predicator.decompile(ast) == source
        assert Predicator.decompile(ast, spacing: :compact) == source
      end
    end

    test "upper case decompiles to lower case, and parentheses survive where needed" do
      {:ok, ast} = Predicator.parse("x IS NOT BLANK")
      assert Predicator.decompile(ast) == "x is not blank"

      for source <- ["(a == 1) is blank", "(a is blank) == true", "NOT x is defined"] do
        {:ok, ast} = Predicator.parse(source)
        assert Predicator.decompile(ast) == source
      end

      {:ok, ast} = Predicator.parse("a + 1 is present")
      assert Predicator.decompile(ast, parentheses: :explicit) == "((a + 1) is present)"
    end
  end

  describe "the reading surfaces" do
    test "Predicator.Analysis reads the operand, never the words" do
      source = "loan.note is not blank AND is is defined"
      expected = [["loan", "note"], ["is"]]

      assert {:ok, refs} = Analysis.references(source)
      assert Enum.map(refs, & &1.path) == expected

      {:ok, instructions} = Predicator.compile(source)
      assert {:ok, refs} = Analysis.references(instructions)
      assert Enum.map(refs, & &1.path) == expected
    end

    test "Predicator.AST walks into the operand" do
      {:ok, ast} = Predicator.parse("f(x) is blank")
      tags = AST.reduce(ast, [], fn node, acc -> [elem(node, 0) | acc] end)
      assert Enum.reverse(tags) == [:presence, :function_call, :identifier]
    end

    test "Predicator.Vocabulary lists the words under :presence, in both cases, as identifiers" do
      lexemes = Enum.map(Vocabulary.by_category(:presence), & &1.lexeme)

      assert lexemes == ["is", "IS", "blank", "BLANK", "present", "PRESENT", "defined", "DEFINED"]
      assert :presence in Vocabulary.categories()
    end
  end

  describe "Predicator.Simple" do
    test "admits each spelling on a field path as a clause with no value, both ways" do
      ops = [:is_blank, :is_not_blank, :is_present, :is_not_present, :is_defined, :is_not_defined]

      for {{spelling, _kind, _negated?, _instructions}, op} <- Enum.zip(@spellings, ops) do
        source = "patron.email " <> spelling

        assert {:ok, %Simple{clauses: [{[root: "patron", property: "email"], ^op, nil}]} = simple} =
                 Simple.from_source(source)

        assert Simple.to_source(simple) == source
        assert Simple.well_formed?(simple)
        assert Simple.from_ast(Simple.to_ast(simple)) == {:ok, simple}
      end
    end

    test "joins presence clauses with comparison clauses" do
      source = "patron.email is present AND loan.days >= 14"

      assert {:ok, %Simple{connective: :and, clauses: [_presence, _comparison]} = simple} =
               Simple.from_source(source)

      assert Simple.to_source(simple) == source
    end

    test "a presence test on anything but a field path is outside" do
      assert Simple.from_source("len(x) is blank") == :outside
      assert Simple.from_source("(a == 1) is blank") == :outside
    end

    test "a presence clause must carry nil, and a comparison cannot" do
      refute Simple.well_formed?(%Simple{
               connective: nil,
               clauses: [{[root: "a"], :is_blank, {:integer, 1}}]
             })

      refute Simple.well_formed?(%Simple{connective: nil, clauses: [{[root: "a"], :gte, nil}]})
    end
  end
end
