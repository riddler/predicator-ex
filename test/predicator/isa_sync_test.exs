defmodule Predicator.IsaSyncTest do
  @moduledoc """
  Anti-drift tests for the ISA version map.

  `Predicator.Instructions`'s `@opcode_isa` map, `docs/isa.md` section 4's
  opcode table, and `lib/predicator/evaluator.ex`'s `execute_instruction/2`
  clause heads are three representations of one fact: which opcodes exist and
  which ISA version each requires. Nothing at compile time keeps them in sync
  - the map is a literal, the doc is prose, and the evaluator's clauses carry
  no version at all - so these tests parse the doc and the evaluator source at
  test time and compare what they say against the map, through the public
  `required_isa/1` function. This is the cheapest place a disagreement between
  the three surfaces, and a red suite naming the offending opcode is a more
  actionable failure than a stale doc or a silently-unreachable evaluator
  clause discovered some other way.
  """

  use ExUnit.Case, async: true

  alias Predicator.Instructions

  # The opcode set is 25 (docs/isa.md section 4; lib/predicator/evaluator.ex
  # execute_instruction/2 clause heads at :371-509). Both parsing tests guard
  # against a regex that silently matches nothing - and passes vacuously - by
  # asserting this literal count rather than only "non-empty".
  @opcode_count 25

  describe "docs/isa.md section 4 table versus the opcode map" do
    setup do
      {:ok, isa_doc: File.read!("docs/isa.md")}
    end

    test "every table row round-trips through required_isa/1", %{isa_doc: isa_doc} do
      rows = parse_isa_table(isa_doc)

      assert rows != [],
             "the docs/isa.md section 4 table regex matched no rows - " <>
               "it likely needs updating to match the table's current column layout"

      assert length(rows) == @opcode_count,
             "expected #{@opcode_count} opcode rows in docs/isa.md section 4, " <>
               "got #{length(rows)}: #{inspect(Enum.map(rows, &elem(&1, 0)))}"

      for {opcode, version} <- rows do
        assert Instructions.required_isa([[opcode]]) == {:ok, version},
               "docs/isa.md lists `#{opcode}` as ISA v#{version}, but " <>
                 "Predicator.Instructions.required_isa/1 disagrees - update the " <>
                 "@opcode_isa map in lib/predicator/instructions.ex (or the table, " <>
                 "if the table is the one that's wrong)"
      end
    end

    test "isa_version/0 is the maximum version in the table", %{isa_doc: isa_doc} do
      rows = parse_isa_table(isa_doc)
      max_table_version = rows |> Enum.map(&elem(&1, 1)) |> Enum.max()

      assert Instructions.isa_version() == max_table_version
    end

    test "section 1's current-version line agrees with isa_version/0", %{isa_doc: isa_doc} do
      assert isa_doc =~ "Current version: **ISA v#{Instructions.isa_version()}**."
    end
  end

  describe "evaluator clause heads versus the opcode map" do
    setup do
      {:ok, evaluator_src: File.read!("lib/predicator/evaluator.ex")}
    end

    test "every execute_instruction/2 clause head opcode is a known opcode", %{
      evaluator_src: evaluator_src
    } do
      opcodes = parse_evaluator_opcodes(evaluator_src)

      assert opcodes != MapSet.new(),
             "the evaluator.ex clause-head regex matched no opcodes - it likely " <>
               "needs updating to match execute_instruction/2's current shape"

      assert MapSet.size(opcodes) == @opcode_count,
             "expected #{@opcode_count} execute_instruction/2 clause heads in " <>
               "lib/predicator/evaluator.ex, got #{MapSet.size(opcodes)}: " <>
               "#{inspect(Enum.sort(opcodes))}"

      for opcode <- opcodes do
        assert {:ok, _version} = Instructions.required_isa([[opcode]]),
               "the evaluator has an execute_instruction/2 clause for `#{opcode}`, " <>
                 "but it is missing from the @opcode_isa map in " <>
                 "lib/predicator/instructions.ex - add it there"
      end
    end
  end

  # Matches rows like:
  #   | `lit` | value | 0 | 1 | v1 | 1 | yes |
  # Column 1 is the opcode (backtick-quoted), column 5 is the ISA version
  # (`v` + digits). If the table gains or loses a column, this regex still
  # matches as long as columns 1 and 5 keep their positions and shape - it
  # does not validate the other columns at all. If the table's shape changes
  # (columns reordered, or the opcode/version columns move), this regex will
  # need updating to match.
  @isa_table_row_regex ~r/^\|\s*`([a-z_]+)`\s*\|[^|]*\|[^|]*\|[^|]*\|\s*v(\d+)\s*\|/m

  @spec parse_isa_table(String.t()) :: [{String.t(), pos_integer()}]
  defp parse_isa_table(isa_doc) do
    @isa_table_row_regex
    |> Regex.scan(isa_doc)
    |> Enum.map(fn [_line, opcode, version] -> {opcode, String.to_integer(version)} end)
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
