defmodule Predicator.VocabularySyncTest do
  @moduledoc """
  Binding tests for `Predicator.Vocabulary` against the lexer it describes.

  The vocabulary is a hand-written table, and a hand-written table is exactly
  the artifact px-15q exists to stop consumers from keeping: publishing one
  here and letting it drift would move the maintenance problem rather than
  solve it. These six tests are what make the published table a derived one
  in practice - the lexer stays the single source of truth, and a token added
  there without an entry here turns the suite red.

  The lexer is checked from three angles, because the three families of fixed
  lexeme live in three different places in it and no single angle reaches all
  of them:

  - The **symbols** are the literal token tuples `tokenize_chars/4` builds -
    `{:gte, line, col, 2, ">="}` and its forty-odd siblings. Parsing them out
    of the source yields the lexeme and the token type together, so a new
    operator added to the lexer with no vocabulary entry is caught. Compared
    both ways.
  - The **words** are `classify_identifier/1`'s clause heads. Compared both
    ways.
  - The **duration units** are `duration_unit?/1`'s clause heads, reachable
    from neither of the above: `:duration_unit` is one token type covering
    eight lexemes, and the unit never appears as a literal in a token tuple.
    Compared both ways.

  `t:Predicator.Lexer.token/0`'s union was considered for the first angle and
  passed over: it names the token types but not their lexemes, so it would
  have needed the tuple-literal parse anyway to say what text to offer - and
  reading it here would have been a second copy of
  `parser_format_token_coverage_test.exs`'s expansion, which is where that
  type's shape is already bound.

  And every enumerated lexeme is then round-tripped through
  `Predicator.Lexer.tokenize/1`, which is the check that a `:token_type` in
  the table is the type the lexer actually produces rather than the one the
  table's author believed it produced.

  Source is parsed rather than introspected throughout because all three of
  these are private, the same reason
  `parser_format_token_coverage_test.exs`, `visitor_clause_coverage_test.exs`
  and `isa_sync_test.exs` parse source.
  """

  use ExUnit.Case, async: true

  alias Predicator.Lexer
  alias Predicator.Vocabulary

  # The number of literal token tuples tokenize_chars/4 builds today,
  # asserted as a literal so a source parse that silently matches nothing -
  # and would then pass vacuously - fails loudly instead. This is the same
  # guard isa_sync_test.exs uses for @opcode_count.
  @symbol_count 28

  describe "Vocabulary versus the lexer's symbol tokens" do
    setup do
      {:ok, source: File.read!("lib/predicator/lexer.ex")}
    end

    # sabotage: renamed the `{:modulo, line, col, 1, "%"}` tuple in
    # tokenize_chars/4 to `:modulox` -> two failures: this test's "the lexer
    # emits" assertion naming {"%", :modulox}, and the round-trip below;
    # restored, confirmed green
    #
    # sabotage (vocabulary side): deleted the `{"%", :modulo, ...}` row from
    # @tokens -> one failure, this test's "the lexer emits" assertion naming
    # {"%", :modulo}; restored, confirmed green
    test "every literal token tuple is enumerated with the same lexeme and type, both ways", %{
      source: source
    } do
      emitted = symbol_tokens(source)

      assert MapSet.size(emitted) == @symbol_count,
             "expected #{@symbol_count} literal token tuples in " <>
               "lib/predicator/lexer.ex, got #{MapSet.size(emitted)}: " <>
               "#{inspect(Enum.sort(emitted))} - the source-parsing logic in " <>
               "this test may need updating to match the module's shape"

      enumerated = MapSet.new(Vocabulary.tokens(), &{&1.lexeme, &1.token_type})

      assert MapSet.difference(emitted, enumerated) == MapSet.new(),
             "the lexer emits #{inspect(Enum.sort(MapSet.difference(emitted, enumerated)))} " <>
               "with no matching Predicator.Vocabulary row - add one. An " <>
               "unenumerated token is one an editor built on the vocabulary " <>
               "cannot offer."

      unmatched =
        Vocabulary.tokens()
        |> Enum.filter(
          &(&1.category in [:comparison, :arithmetic, :grouping, :punctuation, :cast])
        )
        |> Enum.map(&{&1.lexeme, &1.token_type})
        |> MapSet.new()
        |> MapSet.difference(emitted)

      assert unmatched == MapSet.new(),
             "Predicator.Vocabulary enumerates #{inspect(Enum.sort(unmatched))}, " <>
               "which lib/predicator/lexer.ex never emits - remove the stale row(s)"
    end
  end

  describe "Vocabulary versus the lexer's clause heads" do
    setup do
      {:ok, source: File.read!("lib/predicator/lexer.ex")}
    end

    # sabotage: renamed the `classify_identifier("last")` clause head and its
    # returned value to `"lastx"` -> three failures, this one naming
    # {"lastx", :last_op}, plus the reverse-direction test below and the
    # lexeme round-trip (`"last"` now lexes as an identifier); restored,
    # confirmed green
    #
    # sabotage (vocabulary side): changed the `{"CONTAINS", :contains_op, ...}`
    # row's token type to `:in_op` -> two failures: this one naming
    # {"CONTAINS", :contains_op}, since the pair no longer matched, and the
    # round-trip naming both types; restored, confirmed green
    test "every classify_identifier/1 keyword is enumerated with the same token type", %{
      source: source
    } do
      clauses = classify_identifier_clauses(source)

      assert clauses != MapSet.new(),
             "parsing lib/predicator/lexer.ex found no classify_identifier/1 " <>
               "clause heads with a literal lexeme - the source-parsing logic " <>
               "in this test likely needs updating to match the module's shape"

      enumerated = MapSet.new(Vocabulary.tokens(), &{&1.lexeme, &1.token_type})

      assert MapSet.difference(clauses, enumerated) == MapSet.new(),
             "the lexer classifies #{inspect(Enum.sort(MapSet.difference(clauses, enumerated)))} " <>
               "but Predicator.Vocabulary is missing that {lexeme, token_type} " <>
               "pair - add or correct the @tokens row"
    end

    # sabotage: dropped the `{"NOT", :not_op, ...}` row from @tokens -> one
    # failure, on the keyword-coverage test above, naming {"NOT", :not_op}.
    # This direction stayed green, correctly: dropping an entry cannot make
    # the vocabulary offer a word the lexer does not know, which is the only
    # thing this test looks for. The two are deliberately not redundant -
    # see the sabotage on `classify_identifier("last")` above, where this
    # test is one of the three that fire; restored, confirmed green
    test "every word-shaped vocabulary entry is a real classify_identifier/1 clause", %{
      source: source
    } do
      lexemes = MapSet.new(classify_identifier_clauses(source), &elem(&1, 0))
      keywords = MapSet.new(Vocabulary.keywords(), & &1.lexeme)

      assert MapSet.difference(keywords, lexemes) == MapSet.new(),
             "Predicator.Vocabulary.keywords/0 offers " <>
               "#{inspect(Enum.sort(MapSet.difference(keywords, lexemes)))}, which " <>
               "the lexer does not classify as a keyword at all - it would lex " <>
               "as a plain identifier, so offering it as a reserved word is wrong"
    end

    # sabotage: removed the `duration_unit?("mo")` clause -> two failures:
    # this test's second assertion naming ["mo"], and the round-trip below
    # ("1mo" lexes to [:integer] once the unit is unknown); restored,
    # confirmed green
    test "the duration units match duration_unit?/1's clause heads, both ways", %{source: source} do
      units = duration_unit_clauses(source)

      assert units != MapSet.new(),
             "parsing lib/predicator/lexer.ex found no duration_unit?/1 clause " <>
               "heads - the source-parsing logic in this test likely needs " <>
               "updating to match the module's shape"

      enumerated = MapSet.new(Vocabulary.by_category(:duration_unit), & &1.lexeme)

      assert MapSet.difference(units, enumerated) == MapSet.new(),
             "the lexer accepts duration unit(s) " <>
               "#{inspect(Enum.sort(MapSet.difference(units, enumerated)))} that " <>
               "Predicator.Vocabulary does not enumerate"

      assert MapSet.difference(enumerated, units) == MapSet.new(),
             "Predicator.Vocabulary enumerates duration unit(s) " <>
               "#{inspect(Enum.sort(MapSet.difference(enumerated, units)))} that " <>
               "the lexer does not accept"
    end
  end

  describe "round-tripping the vocabulary through the lexer" do
    # sabotage: changed the `{"===", :strict_equal, ...}` row's token type to
    # `:equal_equal` -> two failures: this one naming "===" and both types,
    # and the symbol test, since the lexer's `{:strict_equal, ...}` tuple then
    # matched no row; restored, confirmed green
    test "every enumerated lexeme lexes to the token type its entry declares" do
      for entry <- Vocabulary.tokens() do
        source = round_trip_source(entry)

        assert {:ok, tokens} = Lexer.tokenize(source),
               "#{inspect(entry.lexeme)} does not lex at all, as #{inspect(source)}"

        actual = tokens |> Enum.map(&elem(&1, 0)) |> Enum.reject(&(&1 == :eof))

        assert entry.token_type in actual,
               "Predicator.Vocabulary says #{inspect(entry.lexeme)} lexes to " <>
                 "#{inspect(entry.token_type)}, but #{inspect(source)} lexes to " <>
                 "#{inspect(actual)}"
      end
    end

    # sabotage: broke function_token_type/1's `String.contains?(name, ".")`
    # test so every name came back :function_name -> one failure, naming
    # "Date.day" (the first qualified builtin in sort order); restored,
    # confirmed green
    test "every function name lexes to the token type its entry declares" do
      for entry <- Vocabulary.functions() do
        source = entry.lexeme <> "()"

        assert {:ok, [{actual, _line, _col, _len, _value} | _rest]} = Lexer.tokenize(source),
               "#{inspect(source)} does not lex at all"

        assert actual == entry.token_type,
               "Predicator.Vocabulary says #{inspect(entry.lexeme)} lexes to " <>
                 "#{inspect(entry.token_type)}, but #{inspect(source)} opens with " <>
                 "#{inspect(actual)}"
      end
    end
  end

  # A duration unit is only a unit directly after a number - `d` on its own is
  # an identifier - so it round-trips as `1d`, not as `d`.
  @spec round_trip_source(map()) :: binary()
  defp round_trip_source(%{category: :duration_unit, lexeme: lexeme}), do: "1" <> lexeme
  defp round_trip_source(%{lexeme: lexeme}), do: lexeme

  # Parses `source` and collects `{lexeme, token_type}` for every five-element
  # token tuple built from a literal atom tag and a literal binary value -
  # `{:gte, line, col, 2, ">="}`. A tuple whose value is a variable is a token
  # whose text comes from the program (`{:integer, line, col, consumed,
  # number}`) or from a unit match (`{:duration_unit, ..., unit}`), and is
  # skipped by the is_binary guard: those two families are covered by the
  # other angles, or not fixed at all.
  @spec symbol_tokens(String.t()) :: MapSet.t({binary(), atom()})
  defp symbol_tokens(source) do
    {:ok, quoted} = Code.string_to_quoted(source)

    {_ast, pairs} =
      Macro.prewalk(quoted, [], fn
        {:{}, _meta, [tag, _line, _col, _length, lexeme]} = node, acc
        when is_atom(tag) and is_binary(lexeme) ->
          {node, [{lexeme, tag} | acc]}

        node, acc ->
          {node, acc}
      end)

    MapSet.new(pairs)
  end

  # Parses `source` and collects `{lexeme, token_type}` for every
  # `classify_identifier/1` clause whose argument is a literal binary. The
  # catch-all clause takes a variable and returns `{:identifier, id}`; it is
  # skipped by the same is_binary guard.
  @spec classify_identifier_clauses(String.t()) :: MapSet.t({binary(), atom()})
  defp classify_identifier_clauses(source) do
    source
    |> private_clauses(:classify_identifier)
    |> Enum.flat_map(fn
      {lexeme, {token_type, _value}} when is_binary(lexeme) and is_atom(token_type) ->
        [{lexeme, token_type}]

      _other_clause ->
        []
    end)
    |> MapSet.new()
  end

  # Parses `source` and collects the literal binary of every `duration_unit?/1`
  # clause returning true. The catch-all returns false and is dropped.
  @spec duration_unit_clauses(String.t()) :: MapSet.t(binary())
  defp duration_unit_clauses(source) do
    source
    |> private_clauses(:duration_unit?)
    |> Enum.flat_map(fn
      {unit, true} when is_binary(unit) -> [unit]
      _other_clause -> []
    end)
    |> MapSet.new()
  end

  # Every single-argument `defp name(...), do: body` in `source`, as
  # `{argument, body}` pairs, both still quoted.
  @spec private_clauses(String.t(), atom()) :: [{Macro.t(), Macro.t()}]
  defp private_clauses(source, name) do
    {:ok, quoted} = Code.string_to_quoted(source)

    {_ast, clauses} =
      Macro.prewalk(quoted, [], fn
        {:defp, _meta, [{^name, _fmeta, [arg]}, [do: body]]} = node, acc ->
          {node, [{arg, body} | acc]}

        node, acc ->
          {node, acc}
      end)

    clauses
  end
end
