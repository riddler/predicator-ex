defmodule Predicator.Conformance.SchemaValidationTest do
  @moduledoc """
  Validates every generated conformance artifact against its own JSON Schema
  (`px-35i.4` Phase 5), so a schema that drifts from the generator - a field
  renamed in one but not the other, a type that no longer matches - is caught
  here rather than surfacing in a sibling's CI.

  No JSON Schema library is used or added as a dependency (per this repo's
  constraint: predicator has zero runtime dependencies, and none may be
  reintroduced for dev/test either without cause). Validation runs through
  `Predicator.Conformance.SchemaValidator.validate/2` (`test/test_helper.exs`)
  - a small, targeted structural validator: required keys, JSON types,
  `enum`, `pattern`, one level of `items`, and `oneOf` over `required` - not a
  general JSON Schema engine: no `$ref` resolution, no `allOf`/`not`, no
  `format`. That is a deliberate proportionality call: the goal these tests
  exist for is "a schema that drifts from the generator is caught", and a
  hand-rolled check against the handful of schema features this repo's own
  schemas actually use accomplishes that without the weight (or the new
  dependency) of a full validator. `test/predicator/conformance/ratchet_registry_test.exs`
  (`px-35i.8`) shares the same validator against `schema/registry.json`.
  """

  use ExUnit.Case, async: true

  alias Mix.Tasks.Corpus.Generate, as: CorpusGenerate
  alias Predicator.Conformance.SchemaValidator

  @schema_dir "conformance/schema"

  describe "every checked-in corpus tier file validates against schema/corpus.json" do
    # sabotage: schema/corpus.json root required gains "provenance" -> red
    test "each case in each tier-N.json satisfies the schema" do
      schema = read_schema("corpus.json")

      for path <- Path.wildcard("conformance/corpus/tier-*.json") do
        for line <- path |> File.read!() |> String.split("\n", trim: true) do
          case_json = JSON.decode!(line)

          assert :ok == SchemaValidator.validate(schema, case_json),
                 "#{path}: case #{inspect(case_json["id"])} fails schema/corpus.json: " <>
                   inspect(SchemaValidator.validate(schema, case_json))
        end
      end
    end
  end

  describe "the checked-in manifest.json validates against schema/manifest.json" do
    # sabotage: schema/manifest.json isa_version type "integer" -> "string" -> red
    test "the manifest satisfies the schema" do
      schema = read_schema("manifest.json")
      manifest = "conformance/manifest.json" |> File.read!() |> JSON.decode!()

      assert :ok == SchemaValidator.validate(schema, manifest)
    end
  end

  describe "every authored case validates against schema/case.json" do
    # sabotage: schema/case.json root required gains "notes" -> red
    test "each case in conformance/cases/*.json satisfies the schema" do
      schema = read_schema("case.json")

      for path <- Path.wildcard("conformance/cases/*.json") do
        for authored_case <- path |> File.read!() |> JSON.decode!() do
          assert :ok == SchemaValidator.validate(schema, authored_case),
                 "#{path}: case #{inspect(authored_case["id"])} fails schema/case.json: " <>
                   inspect(SchemaValidator.validate(schema, authored_case))
        end
      end
    end
  end

  describe "schema/report.json is internally consistent" do
    # sabotage: schema/report.json results.items.properties.result.enum gains "skip" -> red
    test ~s(the result enum is exactly ["pass", "fail"] - the structural half of never-skip) do
      schema = read_schema("report.json")
      result_schema = get_in(schema, ["properties", "results", "items", "properties", "result"])

      assert result_schema["enum"] == ["pass", "fail"]
    end

    # sabotage: schema/report.json root required gains "produced_at" -> red
    test "a well-formed report instance validates" do
      schema = read_schema("report.json")

      report = %{
        "isa_version" => 2,
        "corpus_hash" => "sha256:" <> String.duplicate("a", 64),
        "tier" => 1,
        "surface" => "evaluator",
        "results" => [%{"id" => "core/literal-true", "result" => "pass"}]
      }

      assert :ok == SchemaValidator.validate(schema, report)
    end

    # sabotage: schema/report.json results.items.properties.result.enum gains "skip" -> red
    test "a report containing a skip result fails validation" do
      schema = read_schema("report.json")

      report = %{
        "isa_version" => 2,
        "corpus_hash" => "sha256:" <> String.duplicate("a", 64),
        "tier" => 1,
        "surface" => "evaluator",
        "results" => [%{"id" => "core/literal-true", "result" => "skip"}]
      }

      assert {:error, _reason} = SchemaValidator.validate(schema, report)
    end
  end

  # Builds the exact file map mix corpus.generate writes and asserts it
  # matches what is checked in, so a validation run here is never silently
  # exercising a stale corpus.
  # sabotage: conformance/corpus/tier-2.json arithmetic/add-int source gains an extra space -> red
  test "the checked-in corpus matches what generation would produce right now" do
    assert {:ok, files} = CorpusGenerate.build_files()

    for {path, expected_content} <- files do
      assert File.read!(path) == expected_content, "#{path} is stale - run `mix corpus.generate`"
    end
  end

  describe "every schema file in conformance/schema has the expected top-level shape" do
    # sabotage: schema/registry.json $id host github.com/riddler -> example.com -> red
    test "each schema declares draft 2020-12, an $id under this repo, and an object root" do
      paths = Path.wildcard(Path.join(@schema_dir, "*.json"))

      assert paths != [],
             "conformance/schema/*.json matched no files - the glob likely needs updating"

      for path <- paths do
        schema = path |> File.read!() |> JSON.decode!()

        assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema",
               "#{path}: $schema is not draft 2020-12"

        assert String.starts_with?(
                 schema["$id"] || "",
                 "https://github.com/riddler/predicator-ex/conformance/schema/"
               ),
               "#{path}: $id does not follow the sibling schemas' convention"

        assert is_binary(schema["title"]) and schema["title"] != "", "#{path}: missing title"

        assert is_binary(schema["description"]) and schema["description"] != "",
               "#{path}: missing description"

        assert schema["type"] == "object", "#{path}: root type is not \"object\""
      end
    end
  end

  @spec read_schema(String.t()) :: map()
  defp read_schema(filename) do
    @schema_dir |> Path.join(filename) |> File.read!() |> JSON.decode!()
  end
end
