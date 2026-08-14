defmodule Predicator.Conformance.RatchetRegistryTest do
  @moduledoc """
  Binds `conformance/RATCHET.md` - the sibling ratchet registry spec
  (`px-35i.8`) - to this checkout: five tests, each mirroring one of the
  spec's rules, plus the R5 completeness check the worked example is the only
  place that rule is exercised at all.

  `conformance/examples/registry.example.json` is generated from this
  checkout's own `conformance/corpus/tier-1.json`, not hand-typed (see the
  file's own comments in RATCHET.md for why). These tests are what keep that
  example honest: a `mix corpus.generate` that changes the corpus, a hand
  edit to the example, or a reindent all turn this suite red, naming the
  problem, rather than letting the worked example quietly drift from the
  spec it demonstrates.

  This repo ships no ratchet runner (`lib/` gains no module here) - the check
  step below is the read-only half of RATCHET.md's `check/3` pseudocode,
  applied to the one registry this repo has: the example.
  """

  use ExUnit.Case, async: true

  alias Predicator.Conformance.JSON, as: ConformanceJSON
  alias Predicator.Conformance.SchemaValidator

  @schema_path "conformance/schema/registry.json"
  @example_path "conformance/examples/registry.example.json"
  @manifest_path "conformance/manifest.json"
  @tier1_path "conformance/corpus/tier-1.json"

  describe "conformance/examples/registry.example.json validates against schema/registry.json" do
    # sabotage: schema/registry.json required array gains "generated_at" -> red
    test "the example satisfies the schema" do
      schema = @schema_path |> File.read!() |> JSON.decode!()
      example = read_example()

      assert :ok == SchemaValidator.validate(schema, example)
    end
  end

  describe "RATCHET.md rule 1: every entry is a member of its surface's case set, at the right tier" do
    # sabotage: registry.example.json flips comparison/eq-string-true's compiler entry to tier 2 -> red
    test "every (case_id, surface) entry exists in the shipped corpus, with a matching tier" do
      example = read_example()
      entries = example["entries"]

      assert entries != [],
             "conformance/examples/registry.example.json has no entries - " <>
               "the test below would pass vacuously"

      corpus_by_id = tier1_cases_by_id()

      for entry <- entries do
        case_id = entry["case_id"]
        surface = entry["surface"]
        tier = entry["tier"]

        corpus_case =
          Map.get(corpus_by_id, case_id) ||
            flunk(
              "entry #{inspect(case_id)} (surface #{inspect(surface)}) is not a corpus case id " <>
                "(conformance/corpus/tier-1.json)"
            )

        if surface == "compiler" and is_nil(corpus_case["source"]) do
          flunk(
            "entry #{inspect(case_id)} claims the compiler surface, but the corpus case has " <>
              "source: null - a source: null case is absent from the compiler surface's case " <>
              "set (conformance/README.md), not a member of it"
          )
        end

        assert tier == corpus_case["tier"],
               "entry #{inspect(case_id)} claims tier #{tier}, but the corpus case is tier " <>
                 "#{corpus_case["tier"]}"
      end
    end
  end

  describe "RATCHET.md rule 3: entries are unique on (case_id, surface)" do
    # sabotage: registry.example.json duplicates the comparison/gt-int-true compiler entry line -> red
    test "no (case_id, surface) pair appears in entries more than once" do
      entries = read_example()["entries"]

      assert entries != [],
             "conformance/examples/registry.example.json has no entries - " <>
               "the test below would pass vacuously"

      duplicates =
        entries
        |> Enum.frequencies_by(&{&1["case_id"], &1["surface"]})
        |> Enum.filter(fn {_pair, count} -> count > 1 end)
        |> Enum.map(fn {pair, _count} -> pair end)
        |> Enum.sort()

      assert duplicates == [],
             "the registry carries repeated (case_id, surface) pairs: " <>
               inspect(duplicates) <>
               " - RATCHET.md rule 3 grows entries by a set union, so a repeated " <>
               "pair means the file was hand-edited or written by a step that is " <>
               "not verify-then-add"
    end
  end

  describe "the pin: RATCHET.md's corpus_hash and isa_version" do
    # sabotage: registry.example.json corpus_hash's leading hex digit changed f -> e -> red
    test "the example's corpus_hash and isa_version equal the manifest's" do
      example = read_example()
      manifest = @manifest_path |> File.read!() |> JSON.decode!()

      assert example["corpus_hash"] == manifest["corpus_hash"],
             "#{@example_path}'s corpus_hash does not match #{@manifest_path} - " <>
               "the corpus regenerated and the example was not: regenerate " <>
               "#{@example_path} against the new corpus"

      assert example["isa_version"] == manifest["isa_version"],
             "#{@example_path}'s isa_version does not match #{@manifest_path} - " <>
               "regenerate #{@example_path} against the current manifest"
    end
  end

  describe "RATCHET.md rule 2: the file is exactly the canonical encoding" do
    # sabotage: registry.example.json gains an extra space after "isa_version": -> red
    test "re-encoding the parsed example per RATCHET.md's rules byte-matches the file on disk" do
      raw = File.read!(@example_path)
      example = JSON.decode!(raw)

      assert reencode(example) == raw,
             "#{@example_path} is not exactly the canonical encoding RATCHET.md specifies " <>
               "(sorted top-level keys, one array element per line, no incidental " <>
               "whitespace) - a hand edit or a pretty-printer likely touched it; " <>
               "regenerate it instead of editing it directly"
    end
  end

  describe "RATCHET.md R5: completeness of the example's evaluator/tier-1 claim" do
    # sabotage: registry.example.json drops the comparison/eq-string-true evaluator entry -> red
    test "every evaluator-surface tier-1 corpus case has a matching entry" do
      example = read_example()

      assert Enum.any?(example["claims"], &(&1 == %{"surface" => "evaluator", "tier" => 1})),
             ~s(the example no longer carries an {"surface":"evaluator","tier":1} claim - ) <>
               "this test exercises R5 against that specific claim"

      claimed_ids =
        example["entries"]
        |> Enum.filter(&(&1["surface"] == "evaluator"))
        |> MapSet.new(& &1["case_id"])

      corpus_ids = tier1_cases_by_id() |> Map.keys() |> MapSet.new()

      missing = MapSet.difference(corpus_ids, claimed_ids)

      assert MapSet.size(corpus_ids) > 0

      assert Enum.empty?(missing),
             "the example claims evaluator/tier 1 complete, but is missing entries for: " <>
               inspect(Enum.sort(missing))
    end
  end

  @spec read_example() :: map()
  defp read_example do
    @example_path |> File.read!() |> JSON.decode!()
  end

  @spec tier1_cases_by_id() :: %{optional(String.t()) => map()}
  defp tier1_cases_by_id do
    @tier1_path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&JSON.decode!/1)
    |> Map.new(&{&1["id"], &1})
  end

  # Re-implements RATCHET.md's normative encoding independently of however
  # conformance/examples/registry.example.json was produced: top-level keys
  # in codepoint order, each array element encoded with
  # Predicator.Conformance.JSON.encode_canonical/1 on its own line, top-level
  # scalars as "key": value, exactly one trailing newline.
  @spec reencode(map()) :: binary()
  defp reencode(registry) do
    top_keys = ["claims", "corpus_hash", "entries", "implementation", "isa_version"]

    body =
      Enum.map(top_keys, fn key ->
        case Map.fetch!(registry, key) do
          list when is_list(list) ->
            elements = Enum.map(list, &ConformanceJSON.encode_canonical/1)
            ~s("#{key}": [\n) <> Enum.join(elements, ",\n") <> "\n]"

          scalar ->
            ~s("#{key}": ) <> ConformanceJSON.encode_canonical(scalar)
        end
      end)

    "{\n" <> Enum.join(body, ",\n") <> "\n}\n"
  end
end
