defmodule Predicator.Conformance.OpcodeCoverageTest do
  @moduledoc """
  The mechanical coverage rule from the plan (`px-35i.4` Phase 5): every
  opcode in this build's ISA version - `Instructions.opcode_set(Instructions.
  isa_version())`, not the full `Instructions.opcodes/0` table - appears in
  at least one authored case's `instructions`, except the opcodes named in
  `conformance/README.md`'s "Opcodes excluded from the coverage rule"
  section - today just `relative_date` (Open Question #2: its result depends
  on the system clock, so no case can pin an expected value).

  A retired opcode drops out of `opcode_set/1` at its `:removed_in` version,
  so it stops being required here - a version boundary, not an exclusion. Its
  case(s) stay in the corpus regardless (`docs/isa.md` section 4, "Retired
  opcodes"); this test only asserts what must be *newly* covered, not what
  must be absent.

  `@excluded_opcodes` below is the one place this exclusion is declared for
  the test; a second assertion parses `conformance/README.md` and requires
  the two lists to agree exactly, so removing (or adding) an exclusion in one
  place without the other fails the suite rather than silently drifting.
  """

  use ExUnit.Case, async: true

  alias Predicator.Conformance.Generator
  alias Predicator.Instructions

  # docs/isa.md section 5 / plan Open Question #2.
  @excluded_opcodes ~w(relative_date)

  test "every opcode except the documented exclusions appears in at least one case" do
    covered = covered_opcodes()

    expected =
      Instructions.opcode_set(Instructions.isa_version()) |> MapSet.difference(excluded())

    missing = MapSet.difference(expected, covered)

    assert MapSet.new() == missing,
           "opcode(s) with no conformance case: #{inspect(MapSet.to_list(missing))} - " <>
             "author a case in conformance/cases/*.json, or add the opcode to the " <>
             "documented exclusions in both this test and conformance/README.md"
  end

  test "the excluded opcode(s) genuinely have no case, so the exclusion is not stale" do
    covered = covered_opcodes()

    stale = Enum.filter(@excluded_opcodes, &MapSet.member?(covered, &1))

    assert stale == [],
           "opcode(s) #{inspect(stale)} are both excluded from the coverage rule and " <>
             "covered by a case - drop the now-unnecessary exclusion"
  end

  test "the exclusion list here matches conformance/README.md's documented exclusions exactly" do
    documented = readme_excluded_opcodes()

    assert MapSet.new(@excluded_opcodes) == documented,
           "this test's @excluded_opcodes #{inspect(@excluded_opcodes)} disagrees with " <>
             "conformance/README.md's \"Opcodes excluded from the coverage rule\" section " <>
             "(found #{inspect(MapSet.to_list(documented))}) - keep both in sync"
  end

  @spec excluded() :: MapSet.t(String.t())
  defp excluded, do: MapSet.new(@excluded_opcodes)

  @spec covered_opcodes() :: MapSet.t(String.t())
  defp covered_opcodes do
    cases =
      "conformance/cases/*.json"
      |> Path.wildcard()
      |> Enum.flat_map(fn path -> path |> File.read!() |> JSON.decode!() end)

    assert {:ok, %{tiers: tiers}} = Generator.generate(cases)

    tiers
    |> Map.values()
    |> List.flatten()
    |> Enum.flat_map(& &1["instructions"])
    |> Enum.map(fn [opcode | _operands] -> opcode end)
    |> MapSet.new()
  end

  # A structural, targeted parse of one README section - not a markdown
  # parser. It finds the "### Opcodes excluded from the coverage rule"
  # heading, takes the text up to the next "##"/"###" heading, and collects
  # every backtick-quoted token on a top-level "- `name`" bullet that is
  # itself a known opcode name. This is deliberately narrow: it is a binding
  # check between two hand-maintained lists, not a markdown renderer.
  @spec readme_excluded_opcodes() :: MapSet.t(String.t())
  defp readme_excluded_opcodes do
    section =
      "conformance/README.md"
      |> File.read!()
      |> extract_section("### Opcodes excluded from the coverage rule")

    known_opcodes = Instructions.opcodes() |> Map.keys() |> MapSet.new()

    ~r/^- `([a-z_]+)`/m
    |> Regex.scan(section, capture: :all_but_first)
    |> Enum.map(fn [name] -> name end)
    |> Enum.filter(&MapSet.member?(known_opcodes, &1))
    |> MapSet.new()
  end

  @spec extract_section(String.t(), String.t()) :: String.t()
  defp extract_section(readme, heading) do
    [_before, after_heading] = String.split(readme, heading, parts: 2)

    case Regex.split(~r/\n###? /, after_heading, parts: 2) do
      [section | _rest] -> section
      [] -> ""
    end
  end
end
