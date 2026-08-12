defmodule Mix.Tasks.Corpus.Coverage do
  @shortdoc "Reports opcode/pattern gaps between the ExUnit suite and the corpus"

  @moduledoc """
  Prints a checklist of behaviors the existing ExUnit suite exercises that
  the shipped conformance corpus does not (`px-35i.4` Phase 6).

  The corpus is authored JSON completed by the real pipeline, not extracted
  from the suite (see `docs/plans/260807-px-35i.4-conformance-corpus.md`'s
  "The generation mechanism" section) - so nothing else tells an author what
  the 16k-line suite exercises that the corpus does not. This task closes
  that loop, using the existing suite as an authoring checklist rather than
  as the corpus's source of truth.

  ## What it does

  1. Reads every `test/**/*.exs` file **except** `test/predicator/conformance/**`
     (the corpus's own test suite, not "the existing suite" this task
     checklists) and statically extracts literal `Predicator.evaluate/2,3` and
     `Predicator.compile/1` source strings via
     `Predicator.Conformance.Coverage.extract_sources/1`.
  2. Compiles each extracted source through the real compiler and counts
     opcode/operand patterns via
     `Predicator.Conformance.Coverage.suite_pattern_frequencies/1`.
  3. Reads the shipped `conformance/corpus/tier-*.json` cases and computes the
     same patterns via `corpus_pattern_frequencies/1`.
  4. Diffs the two, keeping every pattern the suite hits more than the
     corpus.
  5. Classifies each tier-5 (`call:<name>`) gap against the real builtin
     registry (`Predicator.Context.new().functions`'s keys) via
     `Coverage.classify/2`, and prints the result grouped by tier -
     `px-q1f`, so a test-registered function name (`boom`, `double`, ...)
     reads as "not a corpus candidate" rather than as an unauthored gap, and
     a non-deterministic builtin (`Date.now`, `Math.random`, same for the
     `relative_date` opcode) reads as a documented exclusion rather than a
     bare `corpus: 0`.

  This is dev-only tooling: it never writes a conformance case, never touches
  `conformance/cases/`, and never fails the gate - a wide report is expected
  and is not itself a failure. It is a **heuristic** report (see
  `Predicator.Conformance.Coverage`'s moduledoc for exactly what it can and
  cannot see); its top entries need a human read before being authored as
  cases, since some will still be Elixir-internal test scaffolding that
  `classify/2`'s registry check does not catch (e.g. an opts-handling
  assertion that happens to compile) rather than genuine corpus gaps.

  ## Usage

      mix corpus.coverage
  """

  use Mix.Task

  alias Predicator.Conformance.Coverage
  alias Predicator.Context

  @test_glob "test/**/*.exs"
  @excluded_prefix "test/predicator/conformance/"
  @corpus_glob "conformance/corpus/tier-*.json"

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(_args) do
    sources = suite_sources()

    suite_freqs = Coverage.suite_pattern_frequencies(sources)

    corpus_freqs = Coverage.corpus_pattern_frequencies(corpus_cases())

    gaps =
      suite_freqs
      |> Coverage.diff(corpus_freqs)
      |> Coverage.classify(builtin_function_names())

    Mix.shell().info(
      "Scanned #{length(suite_test_files())} suite file(s), extracted #{length(sources)} " <>
        "literal source(s) (#{map_size(suite_freqs)} distinct pattern(s))."
    )

    Mix.shell().info("")
    Mix.shell().info(Coverage.format_report(gaps))
  end

  @spec suite_sources() :: [String.t()]
  defp suite_sources do
    suite_test_files()
    |> Enum.flat_map(fn path -> path |> File.read!() |> Coverage.extract_sources() end)
    |> Enum.uniq()
  end

  @spec suite_test_files() :: [String.t()]
  defp suite_test_files do
    @test_glob
    |> Path.wildcard()
    |> Enum.reject(&String.starts_with?(&1, @excluded_prefix))
    |> Enum.sort()
  end

  @spec corpus_cases() :: [map()]
  defp corpus_cases do
    @corpus_glob
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(&decode_corpus_file/1)
  end

  # The builtin registry `Coverage.classify/2` sorts tier-5 gaps against -
  # `opts[:functions]` deliberately excluded, since a name only registered
  # there by a test is exactly what should classify as suite-local.
  @spec builtin_function_names() :: MapSet.t(String.t())
  defp builtin_function_names do
    Context.new().functions |> Map.keys() |> MapSet.new()
  end

  @spec decode_corpus_file(String.t()) :: [map()]
  defp decode_corpus_file(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&JSON.decode!/1)
  end
end
