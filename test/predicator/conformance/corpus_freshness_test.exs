defmodule Predicator.Conformance.CorpusFreshnessTest do
  @moduledoc """
  The load-bearing test of `px-35i.4`: regenerates the corpus in memory from
  `conformance/cases/*.json` and byte-compares it against the checked-in
  `conformance/corpus/tier-*.json` and `conformance/manifest.json`.

  A semantic change nobody meant to make - an evaluator clause, an opcode's
  tier, a feature tag rule - shows up here as a diff between what the real
  pipeline computes now and what is on disk, without anyone needing to
  remember to run `mix corpus.generate` first. A deliberate change is expected
  to land as a reviewable corpus diff in the same PR: run `mix corpus.generate`
  and commit the result.
  """

  use ExUnit.Case, async: true

  alias Mix.Tasks.Corpus.Generate, as: CorpusGenerate

  # sabotage: instructions.ex @opcodes moves `access` from tier 3 to tier 4 -> red
  test "the checked-in corpus is exactly what mix corpus.generate would write" do
    assert {:ok, expected_files} = CorpusGenerate.build_files()

    failures =
      expected_files
      |> Enum.map(&compare/1)
      |> Enum.reject(&is_nil/1)

    assert failures == [],
           "conformance/ is stale - run `mix corpus.generate` and review the diff:\n\n" <>
             Enum.join(failures, "\n\n")
  end

  @spec compare({String.t(), binary()}) :: String.t() | nil
  defp compare({path, expected}) do
    case File.read(path) do
      {:ok, ^expected} ->
        nil

      {:ok, actual} ->
        describe_mismatch(path, expected, actual)

      {:error, reason} ->
        "#{path}: missing on disk (#{inspect(reason)}) - run `mix corpus.generate`"
    end
  end

  # Tier files are one case per line; naming the differing ids is far more
  # useful than a raw byte diff - both a case whose *content* changed (same
  # id, different line) and a case that was added or removed (id present on
  # only one side) count as "affected". The manifest is a single object, so
  # its mismatch is reported whole.
  @spec describe_mismatch(String.t(), binary(), binary()) :: String.t()
  defp describe_mismatch(path, expected, actual) do
    if String.starts_with?(path, "conformance/corpus/") do
      expected_lines = lines_by_id(expected)
      actual_lines = lines_by_id(actual)

      affected =
        expected_lines
        |> Map.keys()
        |> Kernel.++(Map.keys(actual_lines))
        |> Enum.uniq()
        |> Enum.filter(fn id -> Map.get(expected_lines, id) != Map.get(actual_lines, id) end)
        |> Enum.sort()

      "#{path}: differs, affected case id(s): #{inspect(affected)}"
    else
      "#{path}: differs from the generated content"
    end
  end

  @spec lines_by_id(binary()) :: %{optional(String.t()) => String.t()}
  defp lines_by_id(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      case JSON.decode(line) do
        {:ok, %{"id" => id}} -> {id, line}
        _other -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end
end
