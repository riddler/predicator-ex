defmodule Predicator.AnalysisClauseCoverageTest do
  @moduledoc """
  Binding test for `Predicator.Analysis` against the two vocabularies it reads:
  the AST's node kinds and the instruction set's opcodes.

  `Predicator.Analysis` reads an AST through `node_step/2`, one clause per
  constructor of `t:Predicator.Parser.visitable/0`, and an instruction list
  through `step/3`, one clause per opcode of
  `Predicator.Instructions.opcodes/0`. A node kind with no clause would raise
  inside the walk; an opcode with no clause would answer
  `"unknown_instruction"` for a list the evaluator runs. Nothing at compile
  time ties either clause list to its source, so this test computes both sides
  at test time: the constructor set from `Code.Typespec.fetch_types/1` on the
  compiled `Parser` beam, the opcode set from `opcodes/0` itself (the retired
  `and` and `or` included), and the clause heads by parsing
  `lib/predicator/analysis.ex` with `Code.string_to_quoted/1`, as
  `ast_clause_coverage_test.exs` does for `Predicator.AST`.
  """

  use ExUnit.Case, async: true

  alias Predicator.{Instructions, Parser}

  # The 18 members of `ast/0` plus program, assignment, if, while and block,
  # the literal `ast_clause_coverage_test.exs` asserts.
  @constructor_count 23

  # Every row of docs/isa.md section 4's opcode table, retired rows included.
  @opcode_count 31

  setup do
    {:ok, types} = Code.Typespec.fetch_types(Parser)

    {:ok,
     parser_types: Map.new(types, fn {_kind, {name, type_ast, _vars}} -> {name, type_ast} end),
     source: File.read!("lib/predicator/analysis.ex")}
  end

  # sabotage: added `| {:sabotage_probe, ast(), position()}` to ast/0 in
  # parser.ex with no matching node_step/2 clause in analysis.ex -> the
  # constructor-count assertion went red
  #
  # sabotage (reverse direction): renamed the `{:duration, ...}` node_step/2
  # clause head's tag to `:durationx` -> the "missing" assertion went red,
  # naming :duration
  test "node_step/2 covers exactly the constructors of Parser.visitable/0, both ways", %{
    parser_types: parser_types,
    source: source
  } do
    constructors =
      parser_types |> Map.fetch!(:visitable) |> expand_type(parser_types, MapSet.new())

    clause_tags = clause_heads(source, :node_step) |> Enum.map(&tuple_tag/1) |> as_set()

    assert MapSet.size(constructors) == @constructor_count,
           "expected #{@constructor_count} constructors reachable from " <>
             "Parser.visitable/0, got #{MapSet.size(constructors)}: " <>
             "#{inspect(Enum.sort(constructors))}"

    assert MapSet.size(clause_tags) == @constructor_count,
           "expected #{@constructor_count} distinct node_step/2 clause tags in " <>
             "analysis.ex, got #{MapSet.size(clause_tags)}: #{inspect(Enum.sort(clause_tags))}"

    missing = MapSet.difference(constructors, clause_tags)
    extra = MapSet.difference(clause_tags, constructors)

    assert missing == MapSet.new(),
           "Parser.visitable/0 has constructor(s) #{inspect(Enum.sort(missing))} with no " <>
             "node_step/2 clause in lib/predicator/analysis.ex - add one"

    assert extra == MapSet.new(),
           "lib/predicator/analysis.ex has node_step/2 clause(s) for " <>
             "#{inspect(Enum.sort(extra))}, which Parser.visitable/0 no longer produces"
  end

  # sabotage: added `"sabotage_probe" => %{isa: 6, tier: 9}` to @opcodes in
  # instructions.ex with no matching step/3 clause in analysis.ex -> the
  # opcode-count assertion went red, listing "sabotage_probe"
  #
  # sabotage (reverse direction): renamed the `["or"]` step/3 clause head to
  # `["orx"]` -> the "missing" assertion went red, naming "or"
  test "step/3 covers exactly the opcodes of Instructions.opcodes/0, both ways", %{
    source: source
  } do
    opcodes = Instructions.opcodes() |> Map.keys() |> as_set()
    clause_opcodes = clause_heads(source, :step) |> Enum.map(&list_head/1) |> as_set()

    assert MapSet.size(opcodes) == @opcode_count,
           "expected #{@opcode_count} opcodes in Instructions.opcodes/0, got " <>
             "#{MapSet.size(opcodes)}: #{inspect(Enum.sort(opcodes))}"

    assert MapSet.size(clause_opcodes) == @opcode_count,
           "expected #{@opcode_count} distinct step/3 clause opcodes in analysis.ex, got " <>
             "#{MapSet.size(clause_opcodes)}: #{inspect(Enum.sort(clause_opcodes))}"

    missing = MapSet.difference(opcodes, clause_opcodes)
    extra = MapSet.difference(clause_opcodes, opcodes)

    assert missing == MapSet.new(),
           "Instructions.opcodes/0 has opcode(s) #{inspect(Enum.sort(missing))} with no " <>
             "step/3 clause in lib/predicator/analysis.ex - add one"

    assert extra == MapSet.new(),
           "lib/predicator/analysis.ex has step/3 clause(s) for #{inspect(Enum.sort(extra))}, " <>
             "which Instructions.opcodes/0 does not list"
  end

  @spec as_set([term()]) :: MapSet.t()
  defp as_set(items), do: items |> Enum.reject(&is_nil/1) |> MapSet.new()

  # The same expansion ast_clause_coverage_test.exs uses: a union expands to
  # its members, a user type is looked up once per path, and a tuple whose
  # first element is a literal atom contributes that atom.
  @spec expand_type(term(), map(), MapSet.t(atom())) :: MapSet.t(atom())
  defp expand_type({:type, _anno, :union, members}, parser_types, visited) do
    Enum.reduce(members, MapSet.new(), fn member, acc ->
      MapSet.union(acc, expand_type(member, parser_types, visited))
    end)
  end

  defp expand_type({:user_type, _anno, name, []}, parser_types, visited) do
    if MapSet.member?(visited, name) do
      MapSet.new()
    else
      parser_types
      |> Map.fetch!(name)
      |> expand_type(parser_types, MapSet.put(visited, name))
    end
  end

  defp expand_type({:type, _anno, :tuple, [{:atom, _anno2, tag} | _rest]}, _types, _visited),
    do: MapSet.new([tag])

  defp expand_type(_other, _parser_types, _visited), do: MapSet.new()

  # The first-argument pattern of every private `function_name` clause with a
  # body, guard unwrapped.
  @spec clause_heads(String.t(), atom()) :: [Macro.t()]
  defp clause_heads(source, function_name) do
    {:ok, quoted} = Code.string_to_quoted(source)

    {_quoted, heads} =
      Macro.prewalk(quoted, [], fn
        {:defp, _meta, [head, _body]} = node, acc -> {node, [head | acc]}
        node, acc -> {node, acc}
      end)

    for head <- heads,
        {^function_name, _meta, [pattern | _rest]} <- [unwrap_guard(head)],
        do: pattern
  end

  defp unwrap_guard({:when, _meta, [head, _guard]}), do: head
  defp unwrap_guard(head), do: head

  # A node pattern is a tuple, possibly bound with `= node`; a tuple of three
  # or more elements quotes as `{:{}, meta, elements}`.
  defp tuple_tag({:=, _meta, [pattern, _bound]}), do: tuple_tag(pattern)
  defp tuple_tag({:{}, _meta, [tag | _rest]}) when is_atom(tag), do: tag
  defp tuple_tag(_other), do: nil

  # An instruction pattern is a list literal headed by the opcode string; the
  # catch-all clause's bare variable contributes nothing.
  defp list_head([opcode | _operands]) when is_binary(opcode), do: opcode
  defp list_head(_other), do: nil
end
