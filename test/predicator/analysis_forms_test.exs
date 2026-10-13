defmodule Predicator.AnalysisFormsTest do
  @moduledoc """
  The AST form and the instruction form of `Predicator.Analysis` agree on a
  table of sources.

  Each source is analysed four ways - its AST, its bare instruction list, and
  its compiled envelope with a position table and with a span table - and the
  answers are compared. Paths and calls agree in every form. Positions agree
  wherever the instruction form has a table: the bare list carries none, so
  its positions are all `nil` and only its paths and calls are compared.

  The table covers every node kind the parser builds and every opcode the
  compiler emits. No source in it is one where the two forms cannot agree:
  the instruction form rebuilds each path from the stack, and a constant-folded
  list literal (`["lit", [...]]`) holds no read in either form.
  """

  use ExUnit.Case, async: true

  alias Predicator.Analysis

  @expressions [
    "score > limit",
    "a.b.c == 1",
    "user.tags[0] == 'x'",
    "items['key'][k].id >= 2",
    "a[b[c]]",
    "a[-1]",
    "a[1.5]",
    "a[true]",
    "a[[1, 2]]",
    "a[x + 1].y",
    "(a and b).c",
    "f(h(a) and g(b))",
    "a or b and not c",
    "!flag or 1 + !other",
    "-n + m * 2 / 3 % 4 - k",
    "x in [1, 2, y]",
    "list contains item",
    "max(len(name), 3) > ns.limit()",
    "f(x).y[k]",
    "{k: v, 'other': w.z}.k",
    "[a, b.c, 3]",
    "amount::integer > 3",
    "due < 3d ago",
    "start > next 2w",
    "created > 1d8h ago and status == 'open'",
    "#2026-01-01# < day",
    "undefined == missing",
    "\"text\" + suffix"
  ]

  @programs [
    "a = 1",
    "a.b = x",
    "a['b'][0] = y.z",
    "totals[day] = totals[day] + amount",
    "a[k + 1].b = f(x)",
    "x = 1; y = x + 1; x",
    "if ready { a = 1 } else { b = f(c) }",
    "if p { a = 1 } else if q { a = 2 }",
    "i = 0; while i < n { i = i + 1; log(i) }",
    "a[g(h(k))] = 1"
  ]

  @functions [:references, :calls, :assignments]

  describe "expressions" do
    for source <- @expressions do
      @source source
      test "forms agree on #{inspect(source)}" do
        {:ok, points} = Predicator.parse(@source)
        {:ok, spans} = Predicator.parse(@source, spans: true)
        {:ok, instructions} = Predicator.compile(@source)
        {:ok, with_positions} = Predicator.compile_with_positions(@source)
        {:ok, with_spans} = Predicator.compile_with_spans(@source)

        assert_agree(points, spans, instructions, with_positions, with_spans)
      end
    end
  end

  describe "programs" do
    for source <- @programs do
      @source source
      test "forms agree on #{inspect(source)}" do
        {:ok, points} = Predicator.parse_program(@source)
        {:ok, spans} = Predicator.parse_program(@source, spans: true)
        {:ok, instructions} = Predicator.compile_program(@source)
        {:ok, with_positions} = Predicator.compile_program_with_positions(@source)
        {:ok, with_spans} = Predicator.compile_program_with_spans(@source)

        assert_agree(points, spans, instructions, with_positions, with_spans)
      end
    end
  end

  # sabotage: in analysis.ex's segment/2, dropped the `or is_integer(value)`
  # from the literal clause's guard -> this test went red, and so did the
  # agreement tests for the sources holding a literal index
  #
  # sabotage: in analysis.ex's pop_many/3, removed the `Enum.reverse/1` so
  # popped values come back top-first -> this test went red, and so did the
  # agreement tests for every multi-segment store and every call of two or
  # more arguments
  test "the instruction form rebuilds read and store paths from the stack" do
    source = "a[0]['b'][k + 1].c = x.y[0]"

    {:ok, instructions} = Predicator.compile_program(source)

    assert Analysis.assignments(instructions) ==
             {:ok, [%{path: ["a", 0, "b", :dynamic, "c"], position: nil}]}

    assert Analysis.references(instructions) ==
             {:ok, [%{path: ["k"], position: nil}, %{path: ["x", "y", 0], position: nil}]}

    {:ok, program} = Predicator.parse_program(source)

    assert Enum.map(elem(Analysis.assignments(program), 1), & &1.path) == [
             ["a", 0, "b", :dynamic, "c"]
           ]
  end

  test "a source string answers what its parsed form answers" do
    for source <- @expressions ++ @programs, function <- @functions do
      {:ok, program} = Predicator.parse_program(source)

      assert apply(Analysis, function, [source]) == apply(Analysis, function, [program]),
             "#{function} on #{inspect(source)}"
    end

    for source <- @expressions, function <- @functions do
      {:ok, ast} = Predicator.parse(source)
      {:ok, from_ast} = apply(Analysis, function, [ast])

      assert apply(Analysis, function, [source]) == {:ok, from_ast},
             "#{function} on #{inspect(source)}: the expression and the program parse disagree"
    end
  end

  test "the table reaches every opcode the compiler emits" do
    emitted =
      for source <- @expressions, reduce: MapSet.new() do
        acc -> MapSet.union(acc, opcodes(Predicator.compile(source)))
      end

    emitted =
      for source <- @programs, reduce: emitted do
        acc -> MapSet.union(acc, opcodes(Predicator.compile_program(source)))
      end

    compiler_opcodes =
      for {opcode, info} <- Predicator.Instructions.opcodes(),
          not Map.has_key?(info, :removed_in),
          into: MapSet.new(),
          do: opcode

    assert MapSet.difference(compiler_opcodes, emitted) == MapSet.new()
  end

  test "the table reaches every node kind the parser builds" do
    tags =
      for source <- @expressions, reduce: MapSet.new() do
        acc -> MapSet.union(acc, node_tags(Predicator.parse(source)))
      end

    tags =
      for source <- @programs, reduce: tags do
        acc -> MapSet.union(acc, node_tags(Predicator.parse_program(source)))
      end

    # Every constructor of Parser.visitable/0 (analysis_clause_coverage_test.exs
    # counts 23).
    assert MapSet.size(tags) == 23, inspect(Enum.sort(tags))
  end

  defp assert_agree(points, spans, instructions, with_positions, with_spans) do
    for function <- @functions do
      {:ok, from_points} = apply(Analysis, function, [points])
      {:ok, from_spans} = apply(Analysis, function, [spans])
      {:ok, from_list} = apply(Analysis, function, [instructions])

      assert {:ok, from_points} == apply(Analysis, function, [with_positions]),
             "#{function}: the AST and the envelope with positions disagree"

      assert {:ok, from_spans} == apply(Analysis, function, [with_spans]),
             "#{function}: the AST with spans and the envelope with spans disagree"

      assert Enum.map(from_list, &Map.delete(&1, :position)) ==
               Enum.map(from_points, &Map.delete(&1, :position)),
             "#{function}: the bare instruction list and the AST disagree"

      assert Enum.all?(from_list, &is_nil(&1.position))
    end
  end

  defp opcodes({:ok, instructions}),
    do: instructions |> Enum.map(&hd/1) |> MapSet.new()

  defp node_tags({:ok, ast}),
    do: Predicator.AST.reduce(ast, MapSet.new(), &MapSet.put(&2, elem(&1, 0)))
end
