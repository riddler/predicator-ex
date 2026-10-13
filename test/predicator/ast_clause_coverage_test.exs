defmodule Predicator.ASTClauseCoverageTest do
  @moduledoc """
  Binding test for `Predicator.Parser`'s `t:visitable/0` typespec versus the
  `map_children/3` clauses of `Predicator.AST`.

  `Predicator.AST.prewalk/3`, `postwalk/3` and `reduce/3` all reach a node's
  children through one private function, `map_children/3`, with one clause per
  constructor of `visitable/0`. A node kind with no clause there would raise a
  `FunctionClauseError` the first time a tree holding it was walked, and
  nothing at compile time ties the clause heads to the typespec. This test
  computes both sides at test time: the constructor set via
  `Code.Typespec.fetch_types/1` on the compiled `Parser` beam, and the clause
  tags by parsing `lib/predicator/ast.ex` with `Code.string_to_quoted/1`, the
  approach `visitor_clause_coverage_test.exs` uses for the visitors.
  """

  use ExUnit.Case, async: true

  alias Predicator.Parser

  # The 18 members of `ast/0` plus program, assignment, if, while and block,
  # the same literal `visitor_clause_coverage_test.exs` asserts, so an
  # expansion that silently matches nothing fails loudly.
  @constructor_count 23

  setup do
    {:ok, types} = Code.Typespec.fetch_types(Parser)

    {:ok,
     parser_types: Map.new(types, fn {_kind, {name, type_ast, _vars}} -> {name, type_ast} end),
     source: File.read!("lib/predicator/ast.ex")}
  end

  # sabotage: added `| {:sabotage_probe, ast(), position()}` to ast/0 with no
  # matching map_children/3 clause in ast.ex -> the "missing" assertion went
  # red, naming :sabotage_probe
  #
  # sabotage (reverse direction): renamed the `{:duration, ...}` map_children/3
  # clause head's tag to `:durationx` -> the "missing" assertion went red on
  # :duration and the "extra" assertion went red on :durationx
  test "map_children/3 covers exactly the constructors of Parser.visitable/0, both ways", %{
    parser_types: parser_types,
    source: source
  } do
    constructors = visitable_constructors(parser_types)
    clause_tags = clause_head_tags(source, :map_children)

    assert MapSet.size(constructors) == @constructor_count,
           "expected #{@constructor_count} constructors reachable from " <>
             "Parser.visitable/0, got #{MapSet.size(constructors)}: " <>
             "#{inspect(Enum.sort(constructors))}"

    assert MapSet.size(clause_tags) == @constructor_count,
           "expected #{@constructor_count} distinct map_children/3 clause tags " <>
             "in ast.ex, got #{MapSet.size(clause_tags)}: " <>
             "#{inspect(Enum.sort(clause_tags))}"

    missing = MapSet.difference(constructors, clause_tags)
    extra = MapSet.difference(clause_tags, constructors)

    assert missing == MapSet.new(),
           "Parser.visitable/0 has constructor(s) #{inspect(Enum.sort(missing))} " <>
             "with no map_children/3 clause in lib/predicator/ast.ex - add one"

    assert extra == MapSet.new(),
           "lib/predicator/ast.ex has map_children/3 clause(s) for " <>
             "#{inspect(Enum.sort(extra))}, which Parser.visitable/0 no longer " <>
             "produces - remove the dead clause(s)"
  end

  # Expands Parser.visitable/0's transitive union to the set of tuple-tag
  # atoms it can produce, by walking Code.Typespec.fetch_types/1's abstract
  # form rather than a hand-written list - see the moduledoc.
  @spec visitable_constructors(map()) :: MapSet.t(atom())
  defp visitable_constructors(parser_types) do
    parser_types
    |> Map.fetch!(:visitable)
    |> expand_type(parser_types, MapSet.new())
  end

  # A union expands to the union of each member's expansion.
  @spec expand_type(term(), map(), MapSet.t(atom())) :: MapSet.t(atom())
  defp expand_type({:type, _anno, :union, members}, parser_types, visited) do
    Enum.reduce(members, MapSet.new(), fn member, acc ->
      MapSet.union(acc, expand_type(member, parser_types, visited))
    end)
  end

  # A user_type reference is looked up by name and expanded in turn.
  # `visited` guards against infinite recursion through a recursive type
  # (ast/0 references itself in comparison/arithmetic/etc.) by stopping once a
  # name has already been expanded on this path - safe because a type name
  # revisited on a cycle contributes no tag that the first visit didn't
  # already contribute.
  defp expand_type({:user_type, _anno, name, []}, parser_types, visited) do
    if MapSet.member?(visited, name) do
      MapSet.new()
    else
      parser_types
      |> Map.fetch!(name)
      |> expand_type(parser_types, MapSet.put(visited, name))
    end
  end

  # A tuple whose first element is a literal atom is a constructor: the atom
  # is the tag.
  defp expand_type(
         {:type, _anno, :tuple, [{:atom, _anno2, tag} | _rest]},
         _parser_types,
         _visited
       ) do
    MapSet.new([tag])
  end

  # Anything else (a bare `binary()`, `integer()`, etc.) contributes no tag.
  defp expand_type(_other, _parser_types, _visited), do: MapSet.new()

  # Parses `source` and collects the tuple tag of the first argument of every
  # private `function_name` clause that has a body. The first argument is a
  # tuple pattern, possibly bound with `= node`; a tuple of three or more
  # elements quotes as `{:{}, meta, elements}` with a literal leading tag.
  # Bodyless heads (a shared @spec carries none) are not `defp` forms and are
  # skipped.
  @spec clause_head_tags(String.t(), atom()) :: MapSet.t(atom())
  defp clause_head_tags(source, function_name) do
    {:ok, quoted} = Code.string_to_quoted(source)

    {_quoted, heads} =
      Macro.prewalk(quoted, [], fn
        {:defp, _meta, [head, _body]} = node, acc -> {node, [head | acc]}
        node, acc -> {node, acc}
      end)

    for head <- heads,
        {^function_name, _meta, [pattern | _rest]} <- [unwrap_guard(head)],
        tag = pattern_tag(pattern),
        into: MapSet.new(),
        do: tag
  end

  defp unwrap_guard({:when, _meta, [head, _guard]}), do: head
  defp unwrap_guard(head), do: head

  defp pattern_tag({:=, _meta, [pattern, _bound]}), do: pattern_tag(pattern)
  defp pattern_tag({:{}, _meta, [tag | _rest]}) when is_atom(tag), do: tag
  defp pattern_tag(_other), do: nil
end
