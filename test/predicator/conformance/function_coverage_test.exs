defmodule Predicator.Conformance.FunctionCoverageTest do
  @moduledoc """
  The function-level sibling of `opcode_coverage_test.exs` (`px-1ka`): every
  builtin registered in `Predicator.Evaluator.merge_functions([])` appears in
  at least one authored case's `instructions` as a `call` operand, except the
  documented non-deterministic exclusions.

  `opcode_coverage_test.exs` guards *opcodes*, not the function names a `call`
  opcode carries as its operand - one `call` case anywhere satisfies it, so a
  builtin with no case of its own was invisible to that gate. This module
  closes that hole.

  The exclusion list is **not** re-declared here. It is read straight from
  `Predicator.Conformance.Coverage.documented_exclusion_functions/0`, which
  `Predicator.Conformance.CoverageTest`'s "documented_exclusion_functions/0"
  describe block already binds to `conformance/README.md`'s "Functions
  excluded from the coverage rule" section - reusing that single declaration
  here keeps there being exactly one hardcoded list, one README section, one
  place they are checked against each other.
  """

  use ExUnit.Case, async: true

  alias Predicator.Conformance.{Coverage, Generator}

  # sabotage: conformance/cases/functions.json drops the functions/upper case -> red
  test "every registered builtin except the documented exclusions appears in at least one case" do
    covered = covered_functions()

    expected =
      registered_functions()
      |> MapSet.difference(Coverage.documented_exclusion_functions())

    missing = MapSet.difference(expected, covered)

    assert MapSet.new() == missing,
           "builtin function(s) with no conformance case: #{inspect(MapSet.to_list(missing))} - " <>
             "author a case in conformance/cases/*.json, or add the function to " <>
             "Coverage.documented_exclusion_functions/0 and conformance/README.md's " <>
             "\"Functions excluded from the coverage rule\" section"
  end

  # sabotage: coverage.ex @documented_exclusion_functions gains "upper", which is covered by a case -> red
  test "the excluded function(s) genuinely have no case, so the exclusion is not stale" do
    covered = covered_functions()

    stale =
      Coverage.documented_exclusion_functions()
      |> Enum.filter(&MapSet.member?(covered, &1))

    assert stale == [],
           "function(s) #{inspect(stale)} are both excluded from the coverage rule and " <>
             "covered by a case - drop the now-unnecessary exclusion"
  end

  # sabotage: coverage.ex @documented_exclusion_functions "Date.now" -> "Date.nowww" -> red
  test "the exclusion list only names functions that are actually registered" do
    stale_names =
      Coverage.documented_exclusion_functions()
      |> MapSet.difference(registered_functions())

    assert MapSet.new() == stale_names,
           "Coverage.documented_exclusion_functions/0 names " <>
             "#{inspect(MapSet.to_list(stale_names))}, which is not a key of " <>
             "Predicator.Evaluator.merge_functions([]) - the exclusion is stale"
  end

  @spec registered_functions() :: MapSet.t(String.t())
  defp registered_functions do
    [] |> Predicator.Evaluator.merge_functions() |> Map.keys() |> MapSet.new()
  end

  @spec covered_functions() :: MapSet.t(String.t())
  defp covered_functions do
    cases =
      "conformance/cases/*.json"
      |> Path.wildcard()
      |> Enum.flat_map(fn path -> path |> File.read!() |> JSON.decode!() end)

    assert {:ok, %{tiers: tiers}} = Generator.generate(cases)

    tiers
    |> Map.values()
    |> List.flatten()
    |> Enum.flat_map(& &1["instructions"])
    |> Enum.flat_map(&function_name/1)
    |> MapSet.new()
  end

  @spec function_name(list()) :: [String.t()]
  defp function_name(["call", function_name | _rest]) when is_binary(function_name),
    do: [function_name]

  defp function_name(_instruction), do: []
end
