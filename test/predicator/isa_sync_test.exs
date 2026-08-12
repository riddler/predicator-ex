defmodule Predicator.IsaSyncTest do
  @moduledoc """
  Anti-drift tests for the ISA version and conformance-tier map.

  `Predicator.Instructions`'s `@opcodes` map, `docs/isa.md` section 4's opcode
  table, and `lib/predicator/evaluator.ex`'s `execute_instruction/2` clause
  heads are three representations of one fact: which opcodes exist, which ISA
  version each requires, and which conformance tier each belongs to. Nothing
  at compile time keeps them in sync - the map is a literal, the doc is prose,
  and the evaluator's clauses carry no version or tier at all - so these tests
  parse the doc and the evaluator source at test time and compare what they
  say against the map, through the public `required_isa/1` and `tier/1`
  functions. This is the cheapest place a disagreement between the three
  surfaces, and a red suite naming the offending opcode is a more actionable
  failure than a stale doc or a silently-unreachable evaluator clause
  discovered some other way.
  """

  use ExUnit.Case, async: true

  alias Predicator.Instructions

  # The opcode *table* size is 30 (docs/isa.md section 4) - retired rows
  # included, since a retired opcode keeps its row (docs/isa.md section 4,
  # "Retired opcodes"). The evaluator clause-head count is derived from this
  # via opcode_set/1 below rather than asserted against this literal, because
  # that surface shrinks on retirement while the table does not. Both parsing
  # tests guard against a regex that silently matches nothing - and passes
  # vacuously - by asserting this literal count rather than only "non-empty".
  @opcode_count 30

  describe "docs/isa.md section 4 table versus the opcode map" do
    setup do
      {:ok, isa_doc: File.read!("docs/isa.md")}
    end

    # sabotage: instructions.ex @opcodes gives `load` tier 2 -> red
    test "every table row round-trips through required_isa/1 and tier/1", %{isa_doc: isa_doc} do
      rows = parse_isa_table(isa_doc)

      assert rows != [],
             "the docs/isa.md section 4 table regex matched no rows - " <>
               "it likely needs updating to match the table's current column layout"

      assert length(rows) == @opcode_count,
             "expected #{@opcode_count} opcode rows in docs/isa.md section 4, " <>
               "got #{length(rows)}: #{inspect(Enum.map(rows, &elem(&1, 0)))}"

      for {opcode, version, doc_tier} <- rows do
        assert Instructions.required_isa([[opcode]]) == {:ok, version},
               "docs/isa.md lists `#{opcode}` as ISA v#{version}, but " <>
                 "Predicator.Instructions.required_isa/1 disagrees - update the " <>
                 "@opcodes map in lib/predicator/instructions.ex (or the table, " <>
                 "if the table is the one that's wrong)"

        assert Instructions.tier(opcode) == {:ok, doc_tier},
               "docs/isa.md lists `#{opcode}` as tier #{doc_tier}, but " <>
                 "Predicator.Instructions.tier/1 disagrees - update the @opcodes " <>
                 "map in lib/predicator/instructions.ex (or the table, if the " <>
                 "table is the one that's wrong)"
      end
    end

    # sabotage: instructions.ex @isa_version 3 -> 4 -> red
    test "isa_version/0 is the maximum version in the table", %{isa_doc: isa_doc} do
      rows = parse_isa_table(isa_doc)
      introduced_versions = Enum.map(rows, &elem(&1, 1))

      # A retirement-only version mints the next ISA integer without
      # introducing any opcode at it (docs/isa.md section 1), so it appears
      # nowhere in column 5 (ISA) - only in column 8 (Removed in). The
      # maximum must therefore be taken over both columns, or isa_version/0
      # could move ahead of this assertion with no way for it to notice.
      removed_versions =
        isa_doc
        |> parse_removed_column()
        |> Enum.map(&elem(&1, 1))
        |> Enum.reject(&is_nil/1)

      max_table_version = Enum.max(introduced_versions ++ removed_versions)

      assert Instructions.isa_version() == max_table_version
    end

    # sabotage: docs/isa.md's "Current version: **ISA v3**." -> "**ISA v2**." -> red
    test "section 1's current-version line agrees with isa_version/0", %{isa_doc: isa_doc} do
      assert isa_doc =~ "Current version: **ISA v#{Instructions.isa_version()}**."
    end
  end

  describe "docs/isa.md section 4 table's Removed in column versus retired_in/1" do
    setup do
      {:ok, isa_doc: File.read!("docs/isa.md")}
    end

    # sabotage: docs/isa.md's `and` row Removed in cell v3 -> - -> red
    test "every row's Removed in cell agrees with retired_in/1", %{isa_doc: isa_doc} do
      rows = parse_removed_column(isa_doc)

      assert rows != [],
             "the docs/isa.md section 4 Removed-in column regex matched no " <>
               "rows - it likely needs updating to match the table's current " <>
               "column layout"

      assert length(rows) == @opcode_count,
             "expected #{@opcode_count} opcode rows with a Removed-in cell " <>
               "in docs/isa.md section 4, got #{length(rows)}: " <>
               "#{inspect(Enum.map(rows, &elem(&1, 0)))}"

      for {opcode, removed_in} <- rows do
        assert Instructions.retired_in(opcode) == {:ok, removed_in},
               "docs/isa.md lists `#{opcode}`'s Removed in cell as " <>
                 "#{inspect(removed_in)}, but " <>
                 "Predicator.Instructions.retired_in/1 disagrees - update " <>
                 "the @opcodes map in lib/predicator/instructions.ex (or " <>
                 "the table, if the table is the one that's wrong)"
      end
    end
  end

  describe "docs/isa.md tier names table versus the opcode map" do
    setup do
      {:ok, isa_doc: File.read!("docs/isa.md")}
    end

    # sabotage: docs/isa.md tier-6 row drops `pop` -> red
    test "each tier's opcode list matches exactly what the map assigns to that tier", %{
      isa_doc: isa_doc
    } do
      tier_rows = parse_tier_names_table(isa_doc)

      assert tier_rows != [],
             "the docs/isa.md tier names table regex matched no rows - it " <>
               "likely needs updating to match the table's current shape"

      opcodes_by_tier =
        Instructions.opcodes()
        |> Enum.group_by(fn {_opcode, %{tier: tier}} -> tier end, fn {opcode, _isa_and_tier} ->
          opcode
        end)
        |> Map.new(fn {tier, opcodes} -> {tier, Enum.sort(opcodes)} end)

      for {tier, doc_opcodes} <- tier_rows do
        map_opcodes = Map.get(opcodes_by_tier, tier, []) |> Enum.sort()
        doc_opcodes = Enum.sort(doc_opcodes)

        assert doc_opcodes == map_opcodes,
               "docs/isa.md's tier names table lists tier #{tier} as " <>
                 "#{inspect(doc_opcodes)}, but the @opcodes map in " <>
                 "lib/predicator/instructions.ex assigns tier #{tier} to " <>
                 "#{inspect(map_opcodes)} - a new opcode was added to one table " <>
                 "and not the other"
      end
    end
  end

  describe "evaluator clause heads versus the opcode map" do
    setup do
      {:ok, evaluator_src: File.read!("lib/predicator/evaluator.ex")}
    end

    # sabotage: evaluator.ex renames the `pop` clause head to `popp` -> red
    test "every execute_instruction/2 clause head opcode is a known opcode", %{
      evaluator_src: evaluator_src
    } do
      clause_head_opcodes = parse_evaluator_opcodes(evaluator_src)

      assert clause_head_opcodes != MapSet.new(),
             "the evaluator.ex clause-head regex matched no opcodes - it likely " <>
               "needs updating to match execute_instruction/2's current shape"

      # Retired opcodes keep their table row and lose their evaluator clause
      # (docs/isa.md section 4, "Retired opcodes"), so the clause-head count
      # is the live opcode count, not the table size. Deriving it means a
      # retirement needs no edit here - and the two assertions below are what
      # the literal was really guarding: no live opcode without a clause, no
      # retired opcode with one.
      live_opcodes = Instructions.opcode_set(Instructions.isa_version())

      retired_opcodes =
        Instructions.opcodes()
        |> Enum.filter(fn {_opcode, info} -> Map.has_key?(info, :removed_in) end)
        |> Enum.map(fn {opcode, _info} -> opcode end)
        |> MapSet.new()

      assert MapSet.size(clause_head_opcodes) == MapSet.size(live_opcodes),
             "expected #{MapSet.size(live_opcodes)} execute_instruction/2 clause " <>
               "heads (the live opcode count) in lib/predicator/evaluator.ex, got " <>
               "#{MapSet.size(clause_head_opcodes)}: " <>
               "#{inspect(Enum.sort(clause_head_opcodes))}"

      assert MapSet.difference(live_opcodes, clause_head_opcodes) == MapSet.new(),
             "every live opcode must have an execute_instruction/2 clause"

      assert MapSet.intersection(clause_head_opcodes, retired_opcodes) == MapSet.new(),
             "a retired opcode must not have an execute_instruction/2 clause"

      for opcode <- clause_head_opcodes do
        assert {:ok, _version} = Instructions.required_isa([[opcode]]),
               "the evaluator has an execute_instruction/2 clause for `#{opcode}`, " <>
                 "but it is missing from the @opcodes map in " <>
                 "lib/predicator/instructions.ex - add it there"
      end
    end
  end

  # Matches rows like:
  #   | `lit` | value | 0 | 1 | v1 | 1 | yes |
  # Column 1 is the opcode (backtick-quoted), column 5 is the ISA version
  # (`v` + digits), column 6 is the tier (bare digits). If the table gains or
  # loses a column, this regex still matches as long as columns 1, 5, and 6
  # keep their positions and shape - it does not validate the other columns
  # at all. If the table's shape changes (columns reordered, or the
  # opcode/version/tier columns move), this regex will need updating to
  # match.
  @isa_table_row_regex ~r/^\|\s*`([a-z_]+)`\s*\|[^|]*\|[^|]*\|[^|]*\|\s*v(\d+)\s*\|\s*(\d+)\s*\|/m

  @spec parse_isa_table(String.t()) :: [{String.t(), pos_integer(), pos_integer()}]
  defp parse_isa_table(isa_doc) do
    @isa_table_row_regex
    |> Regex.scan(isa_doc)
    |> Enum.map(fn [_line, opcode, version, tier] ->
      {opcode, String.to_integer(version), String.to_integer(tier)}
    end)
  end

  # Matches the same rows as @isa_table_row_regex, capturing column 1 (the
  # opcode) and column 8 ("Removed in"): "-" for a live opcode, "vN" for one
  # retired at ISA vN. Kept separate from @isa_table_row_regex so that regex -
  # and the row count and round-trip assertions built on it - is unchanged by
  # the column's arrival.
  @isa_removed_column_regex ~r/^\|\s*`([a-z_]+)`\s*\|(?:[^|]*\|){6}\s*(\S+)\s*\|\s*$/m

  @spec parse_removed_column(String.t()) :: [{String.t(), pos_integer() | nil}]
  defp parse_removed_column(isa_doc) do
    @isa_removed_column_regex
    |> Regex.scan(isa_doc)
    |> Enum.map(fn [_line, opcode, cell] -> {opcode, parse_removed_cell(opcode, cell)} end)
  end

  @spec parse_removed_cell(String.t(), String.t()) :: pos_integer() | nil
  defp parse_removed_cell(_opcode, "-"), do: nil

  defp parse_removed_cell(opcode, "v" <> digits) do
    case Integer.parse(digits) do
      {version, ""} -> version
      _invalid -> flunk_removed_cell(opcode, "v" <> digits)
    end
  end

  defp parse_removed_cell(opcode, cell), do: flunk_removed_cell(opcode, cell)

  @spec flunk_removed_cell(String.t(), String.t()) :: no_return()
  defp flunk_removed_cell(opcode, cell) do
    flunk(
      "docs/isa.md's Removed in cell for `#{opcode}` is #{inspect(cell)}, but only " <>
        "\"-\" (live) or \"vN\" (retired at ISA vN) are accepted forms"
    )
  end

  # Matches rows of the tier *names* table (docs/isa.md:130-137), e.g.:
  #   | 1 | core | `lit`, `load`, `compare`, ... |
  # Column 1 is the tier number, column 3 is the opcode list. A cell starting
  # with "(" is treated as an empty opcode list instead of scanning it for
  # backtick spans - a general rule for a tier whose opcode list is still
  # reserved-but-unfilled prose rather than a comma-separated backtick list.
  # No tier's cell is in that state today (tier 6 filled in with `store` and
  # `pop` at px-tbv.2), but the branch stays: it is what the *next* reserved
  # tier's cell needs, not a tier-6-specific workaround.
  @tier_table_row_regex ~r/^\|\s*(\d+)\s*\|[^|]*\|\s*(.+?)\s*\|\s*$/m
  @tier_table_opcode_regex ~r/`([a-z_]+)`/

  @spec parse_tier_names_table(String.t()) :: [{pos_integer(), [String.t()]}]
  defp parse_tier_names_table(isa_doc) do
    @tier_table_row_regex
    |> Regex.scan(isa_doc)
    |> Enum.map(fn [_line, tier, opcodes_cell] ->
      {String.to_integer(tier), tier_row_opcodes(opcodes_cell)}
    end)
  end

  @spec tier_row_opcodes(String.t()) :: [String.t()]
  defp tier_row_opcodes(opcodes_cell) do
    if String.starts_with?(opcodes_cell, "(") do
      []
    else
      @tier_table_opcode_regex
      |> Regex.scan(opcodes_cell)
      |> Enum.map(fn [_match, opcode] -> opcode end)
    end
  end

  # Matches execute_instruction/2 clause heads, e.g.:
  #   defp execute_instruction(%__MODULE__{} = evaluator, ["lit", value]) do
  # The catch-all clause - `defp execute_instruction(%__MODULE__{}, unknown)` -
  # binds the second argument to a bare variable rather than a list literal
  # starting with a string, so it does not match.
  @evaluator_clause_regex ~r/defp execute_instruction\(%__MODULE__\{\}[^,]*, \["([a-z_]+)"/

  @spec parse_evaluator_opcodes(String.t()) :: MapSet.t(String.t())
  defp parse_evaluator_opcodes(evaluator_src) do
    @evaluator_clause_regex
    |> Regex.scan(evaluator_src)
    |> Enum.map(fn [_line, opcode] -> opcode end)
    |> MapSet.new()
  end
end
