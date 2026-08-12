defmodule Predicator.VisitorClauseCoverageTest do
  @moduledoc """
  Binding test for `Predicator.Parser`'s `t:visitable/0` typespec versus the
  dispatch clauses of both AST visitors.

  `visitable/0` expands (through `program/0`, `statement/0`, `assignment/0`,
  `if_statement/0`, `block/0`, and `ast/0`) to a fixed set of tuple
  constructors: whatever a visitor can be handed. `StringVisitor.do_visit/2`
  and `InstructionsVisitor.visit_annotated/2` are each a private, exhaustive-
  looking case over that set, with two declining clauses (`{:if, ...}` and
  `{:block, ...}`) standing in for the control-flow lowering px-3so.3 and
  px-3so.5 have not landed yet. Nothing at compile time keeps a visitor's
  clause heads in sync with the typespec: `visitable/0` is a union of tuple
  shapes, not a behaviour callback, so a 23rd constructor added there compiles
  cleanly and only fails at run time, as a `FunctionClauseError`, the first
  time some AST reaches the missing clause - the exact contract breach
  ADR-0004 exists to prevent.

  This test computes both sides at test time instead of comparing against a
  hand-written list: the constructor set via `Code.Typespec.fetch_types/1` on
  the compiled `Parser` beam, expanding `visitable/0`'s union and every
  `user_type` reference it names transitively down to tuple literals; the
  clause-tag sets by parsing `string_visitor.ex` and `instructions_visitor.ex`
  with `Code.string_to_quoted/1` and reading the first element of each
  `do_visit/2` and `visit_annotated/2` clause head's tuple pattern - the same
  source-parsing approach `isa_sync_test.exs` uses for
  `evaluator.ex`'s `execute_instruction/2` clause heads, since both dispatch
  functions are private and so have no clause-level introspection at the beam
  level. A hand-written list would not go red when a constructor is added,
  which is the whole point of this test.
  """

  use ExUnit.Case, async: true

  alias Predicator.Parser

  # `visitable/0`'s union expands to 22 tuple constructors today: the 18
  # members of `ast/0` (literal, string_literal, identifier, comparison,
  # arithmetic, unary, membership, logical_and, logical_or, logical_not,
  # list, object, function_call, bracket_access, property_access, cast,
  # duration, relative_date) plus `program/0`, `assignment/0`, `if_statement/0`
  # (tag `:if`), and `block/0`. Asserted as a literal rather than only
  # "non-empty" so a typespec-expansion bug that silently walks past most of
  # the union - or a source parse that silently matches nothing - fails
  # loudly instead of passing vacuously, the same guard
  # `isa_sync_test.exs` uses for `@opcode_count`.
  @constructor_count 22

  describe "Parser.visitable/0's constructor set" do
    setup do
      {:ok, types} = Code.Typespec.fetch_types(Parser)

      {:ok,
       parser_types: Map.new(types, fn {_kind, {name, type_ast, _vars}} -> {name, type_ast} end)}
    end

    # sabotage: added `| {:while, ast(), block(), position()}` to visitable/0's
    # expansion (via a throwaway member on ast/0) -> constructor count went to
    # 23 -> red, naming :while as unexpected
    test "expands to exactly the 22 known tuple constructors", %{parser_types: parser_types} do
      constructors = visitable_constructors(parser_types)

      assert constructors != MapSet.new(),
             "expanding Parser.visitable/0 found no tuple constructors - " <>
               "Code.Typespec.fetch_types/1's shape likely changed, or the " <>
               "expansion in this test needs updating to match it"

      assert MapSet.size(constructors) == @constructor_count,
             "expected #{@constructor_count} constructors reachable from " <>
               "Parser.visitable/0, got #{MapSet.size(constructors)}: " <>
               "#{inspect(Enum.sort(constructors))}"
    end
  end

  describe "StringVisitor.do_visit/2 versus Parser.visitable/0" do
    setup do
      {:ok, types} = Code.Typespec.fetch_types(Parser)

      {:ok,
       parser_types: Map.new(types, fn {_kind, {name, type_ast, _vars}} -> {name, type_ast} end),
       source: File.read!("lib/predicator/visitors/string_visitor.ex")}
    end

    # sabotage: added `| {:while, ast(), block(), position()}` to ast/0 with no
    # matching do_visit/2 clause in string_visitor.ex -> the "missing" assertion
    # went red, naming :while and pointing at StringVisitor
    #
    # sabotage (reverse direction): renamed the `{:duration, ...}` do_visit/2
    # clause head's tag to `:durationx` -> the "missing" assertion went red on
    # :duration (no clause covers it) and the "extra" assertion went red on
    # :durationx (a clause with no matching constructor) -> red
    test "covers exactly the same constructors as Parser.visitable/0, both ways", %{
      parser_types: parser_types,
      source: source
    } do
      constructors = visitable_constructors(parser_types)
      clause_tags = clause_head_tags(source, :do_visit)

      assert clause_tags != MapSet.new(),
             "parsing lib/predicator/visitors/string_visitor.ex found no " <>
               "do_visit/2 clause heads - the source-parsing logic in this " <>
               "test likely needs updating to match the module's current shape"

      assert MapSet.size(clause_tags) == @constructor_count,
             "expected #{@constructor_count} distinct do_visit/2 clause tags " <>
               "in string_visitor.ex, got #{MapSet.size(clause_tags)}: " <>
               "#{inspect(Enum.sort(clause_tags))}"

      missing = MapSet.difference(constructors, clause_tags)
      extra = MapSet.difference(clause_tags, constructors)

      assert missing == MapSet.new(),
             "Parser.visitable/0 has constructor(s) #{inspect(Enum.sort(missing))} " <>
               "with no matching do_visit/2 clause in " <>
               "lib/predicator/visitors/string_visitor.ex - add one (or a " <>
               "declining clause, if the construct isn't renderable yet)"

      assert extra == MapSet.new(),
             "lib/predicator/visitors/string_visitor.ex has do_visit/2 " <>
               "clause(s) for #{inspect(Enum.sort(extra))}, which Parser.visitable/0 " <>
               "no longer produces - remove the dead clause(s)"
    end
  end

  describe "InstructionsVisitor.visit_annotated/2 versus Parser.visitable/0" do
    setup do
      {:ok, types} = Code.Typespec.fetch_types(Parser)

      {:ok,
       parser_types: Map.new(types, fn {_kind, {name, type_ast, _vars}} -> {name, type_ast} end),
       source: File.read!("lib/predicator/visitors/instructions_visitor.ex")}
    end

    # sabotage: added `| {:while, ast(), block(), position()}` to ast/0 with no
    # matching visit_annotated/2 clause in instructions_visitor.ex -> the
    # "missing" assertion went red, naming :while and pointing at
    # InstructionsVisitor
    #
    # sabotage (reverse direction): renamed the `{:duration, ...}`
    # visit_annotated/2 clause head's tag to `:durationx` -> the "missing"
    # assertion went red on :duration and the "extra" assertion went red on
    # :durationx -> red
    test "covers exactly the same constructors as Parser.visitable/0, both ways", %{
      parser_types: parser_types,
      source: source
    } do
      constructors = visitable_constructors(parser_types)
      clause_tags = clause_head_tags(source, :visit_annotated)

      assert clause_tags != MapSet.new(),
             "parsing lib/predicator/visitors/instructions_visitor.ex found " <>
               "no visit_annotated/2 clause heads - the source-parsing logic " <>
               "in this test likely needs updating to match the module's " <>
               "current shape"

      assert MapSet.size(clause_tags) == @constructor_count,
             "expected #{@constructor_count} distinct visit_annotated/2 clause " <>
               "tags in instructions_visitor.ex, got #{MapSet.size(clause_tags)}: " <>
               "#{inspect(Enum.sort(clause_tags))}"

      missing = MapSet.difference(constructors, clause_tags)
      extra = MapSet.difference(clause_tags, constructors)

      assert missing == MapSet.new(),
             "Parser.visitable/0 has constructor(s) #{inspect(Enum.sort(missing))} " <>
               "with no matching visit_annotated/2 clause in " <>
               "lib/predicator/visitors/instructions_visitor.ex - add one (or " <>
               "a declining clause, if the construct doesn't lower yet)"

      assert extra == MapSet.new(),
             "lib/predicator/visitors/instructions_visitor.ex has " <>
               "visit_annotated/2 clause(s) for #{inspect(Enum.sort(extra))}, " <>
               "which Parser.visitable/0 no longer produces - remove the dead " <>
               "clause(s)"
    end
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

  # Parses `source` and collects the tuple tag each `function_name/2` private
  # clause head dispatches on, whether or not the clause carries a `when`
  # guard. A bodyless clause head (used to attach a shared @spec, as both
  # do_visit/2 and visit_annotated/2 do) has no `do:` block and so matches
  # neither pattern below - it is silently skipped, same as any other node
  # this walk doesn't recognize.
  @spec clause_head_tags(String.t(), atom()) :: MapSet.t(atom())
  defp clause_head_tags(source, function_name) do
    {:ok, quoted} = Code.string_to_quoted(source)

    {_ast, tags} =
      Macro.prewalk(quoted, [], fn
        {:defp, _meta,
         [{:when, _wmeta, [{^function_name, _fmeta, [pattern | _rest_args]}, _guard]}, _body]} =
            node,
        acc ->
          {node, [tuple_pattern_tag(pattern) | acc]}

        {:defp, _meta, [{^function_name, _fmeta, [pattern | _rest_args]}, _body]} = node, acc ->
          {node, [tuple_pattern_tag(pattern) | acc]}

        node, acc ->
          {node, acc}
      end)

    tags
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  # A 3+-element tuple pattern quotes as `{:{}, meta, elements}`; a literal
  # atom in leading position (the tag every clause head matches on) quotes as
  # the bare atom itself. Any other pattern shape (a bodyless head's bare
  # variable, for instance) contributes no tag.
  @spec tuple_pattern_tag(term()) :: atom() | nil
  defp tuple_pattern_tag({:{}, _meta, [tag | _rest]}) when is_atom(tag), do: tag
  defp tuple_pattern_tag(_other), do: nil
end
