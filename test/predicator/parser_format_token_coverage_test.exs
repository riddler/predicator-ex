defmodule Predicator.ParserFormatTokenCoverageTest do
  @moduledoc """
  Binding test for `Predicator.Lexer`'s `t:token/0` typespec versus
  `Predicator.Parser`'s private `format_token/2` dispatch.

  `token/0` is a union of five-element tuples whose first element is the
  token-type atom; `format_token/2` renders one of those atoms (plus its
  value) into the human-readable fragment every "expected X but found Y"
  message quotes. It carries one clause per token type and **no catch-all
  clause** - a token type with no matching clause raises `FunctionClauseError`
  the first time it reaches `format_token/2`, instead of the `ParseError`
  value ADR-0004 requires.

  This is not hypothetical: it has happened twice. px-yoq (`b49dd97`) found a
  `:string`-token arity mismatch in this family; px-ty0's own notes record
  that `:fractional_number` (fixed on this branch, `6f78179`) and `:dot`
  (fixed by this change) were both gaps in the same clause list, found by
  literally counting `format_token/2`'s clauses against the lexer's token
  types by hand. That manual count is exactly the check this test now runs on
  every future token type, at test time instead of by hand.

  Both sides are computed at test time rather than compared against a
  hand-written list: the token-type set via `Code.Typespec.fetch_types/1` on
  the compiled `Lexer` beam, reading `token/0`'s union members' leading tuple
  element; the clause-tag set by parsing `parser.ex` with
  `Code.string_to_quoted/1` and reading `format_token/2`'s clause heads'
  first argument - `format_token/2` is private, so it has no clause-level
  introspection at the beam level, the same reason
  `visitor_clause_coverage_test.exs` and `isa_sync_test.exs` parse source
  instead of inspecting a compiled module. A hand-written list would not go
  red when a token type is added, which is the whole point of this test.
  """

  use ExUnit.Case, async: true

  alias Predicator.Lexer

  # Lexer.token/0 expands to 55 distinct tuple constructors today (counted at
  # test-authoring time via Code.Typespec.fetch_types/1, the same way this
  # test computes it). Asserted as a literal rather than only "non-empty" so a
  # typespec-shape change - or a source parse that silently matches nothing -
  # fails loudly instead of passing vacuously, the same guard
  # `isa_sync_test.exs` uses for `@opcode_count` and
  # `visitor_clause_coverage_test.exs` uses for `@constructor_count`.
  @token_type_count 55

  describe "Lexer.token/0's tag set" do
    setup do
      {:ok, types} = Code.Typespec.fetch_types(Lexer)

      {:ok,
       lexer_types: Map.new(types, fn {_kind, {name, type_ast, _vars}} -> {name, type_ast} end)}
    end

    # sabotage: added `| {:sabotage_probe, pos_integer(), pos_integer(),
    # pos_integer(), binary()}` to token/0's union -> both tests in this file
    # went red: this one on the count (got 56, :sabotage_probe present in the
    # listed tags) and the format_token/2 comparison below on the "missing"
    # assertion, naming :sabotage_probe; reverted, confirmed green
    test "expands to exactly the 55 known tuple constructors", %{lexer_types: lexer_types} do
      tags = token_type_tags(lexer_types)

      assert tags != MapSet.new(),
             "expanding Lexer.token/0 found no tuple constructors - " <>
               "Code.Typespec.fetch_types/1's shape likely changed, or the " <>
               "expansion in this test needs updating to match it"

      assert MapSet.size(tags) == @token_type_count,
             "expected #{@token_type_count} token types reachable from " <>
               "Lexer.token/0, got #{MapSet.size(tags)}: #{inspect(Enum.sort(tags))}"
    end
  end

  describe "Parser.format_token/2 versus Lexer.token/0" do
    setup do
      {:ok, types} = Code.Typespec.fetch_types(Lexer)

      {:ok,
       lexer_types: Map.new(types, fn {_kind, {name, type_ast, _vars}} -> {name, type_ast} end),
       source: File.read!("lib/predicator/parser.ex")}
    end

    # sabotage: removed the `defp format_token(:dot, _value), do: "'.'"`
    # clause -> the clause-count assertion went red (got 54, :dot absent from
    # the listed tags - ExUnit stops at a test's first failed assertion, so
    # this fired before "missing" was ever computed); restored, confirmed
    # green
    #
    # sabotage (reverse direction): renamed that clause's head to
    # `format_token(:dotx, _value)`, which holds the clause count at 55 and so
    # reaches the "missing"/"extra" assertions instead -> the "missing"
    # assertion went red naming exactly [:dot] and pointing at this defect
    # class; verified independently (ExUnit stops at a test's first failed
    # assertion) that the parsed clause-tag set contained :dotx and not :dot,
    # confirming the "extra" assertion would have caught it too; restored,
    # confirmed green
    #
    # sabotage (lexer side): added `| {:sabotage_probe, pos_integer(),
    # pos_integer(), pos_integer(), binary()}` to Lexer.token/0's union ->
    # this test's "missing" assertion went red naming exactly
    # [:sabotage_probe]; reverted, confirmed green
    test "covers exactly the same token types as Lexer.token/0, both ways", %{
      lexer_types: lexer_types,
      source: source
    } do
      tags = token_type_tags(lexer_types)
      clause_tags = format_token_clause_tags(source)

      assert clause_tags != MapSet.new(),
             "parsing lib/predicator/parser.ex found no format_token/2 " <>
               "clause heads - the source-parsing logic in this test likely " <>
               "needs updating to match the module's current shape"

      assert MapSet.size(clause_tags) == @token_type_count,
             "expected #{@token_type_count} distinct format_token/2 clause " <>
               "tags in lib/predicator/parser.ex, got " <>
               "#{MapSet.size(clause_tags)}: #{inspect(Enum.sort(clause_tags))}"

      missing = MapSet.difference(tags, clause_tags)
      extra = MapSet.difference(clause_tags, tags)

      assert missing == MapSet.new(),
             "Lexer.token/0 has token type(s) #{inspect(Enum.sort(missing))} " <>
               "with no matching format_token/2 clause in " <>
               "lib/predicator/parser.ex - add one (this is the exact defect " <>
               "class px-ty0 and px-5c5's :fractional_number fix both closed: " <>
               "a missing clause raises FunctionClauseError instead of " <>
               "returning a ParseError value)"

      assert extra == MapSet.new(),
             "lib/predicator/parser.ex has format_token/2 clause(s) for " <>
               "#{inspect(Enum.sort(extra))}, which Lexer.token/0 no longer " <>
               "produces - remove the dead clause(s)"
    end
  end

  # Reads Lexer.token/0's union to the set of tuple-tag atoms it can produce,
  # by walking Code.Typespec.fetch_types/1's abstract form rather than a
  # hand-written list - see the moduledoc. token/0 is a flat union of tuple
  # literals (no user_type indirection), unlike Parser.visitable/0.
  @spec token_type_tags(map()) :: MapSet.t(atom())
  defp token_type_tags(lexer_types) do
    case Map.fetch!(lexer_types, :token) do
      {:type, _anno, :union, members} ->
        members
        |> Enum.map(fn {:type, _anno, :tuple, [{:atom, _anno2, tag} | _rest]} -> tag end)
        |> MapSet.new()

      other ->
        raise "Lexer.token/0 is no longer a union - this test's expansion " <>
                "needs updating to match its current shape: #{inspect(other)}"
    end
  end

  # Parses `source` and collects the token-type atom each private
  # `format_token/2` clause head dispatches on - the clause's first argument,
  # which is always a literal atom (`:integer`, `:fractional_number`, ...),
  # never a deeper pattern, so no tuple-unwrapping is needed here the way
  # `visitor_clause_coverage_test.exs` needs for AST node patterns.
  @spec format_token_clause_tags(String.t()) :: MapSet.t(atom())
  defp format_token_clause_tags(source) do
    {:ok, quoted} = Code.string_to_quoted(source)

    {_ast, tags} =
      Macro.prewalk(quoted, [], fn
        {:defp, _meta, [{:format_token, _fmeta, [tag | _rest_args]}, _body]} = node, acc
        when is_atom(tag) ->
          {node, [tag | acc]}

        node, acc ->
          {node, acc}
      end)

    tags
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end
end
