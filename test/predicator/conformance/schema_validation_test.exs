defmodule Predicator.Conformance.SchemaValidationTest do
  @moduledoc """
  Validates every generated conformance artifact against its own JSON Schema
  (`px-35i.4` Phase 5), so a schema that drifts from the generator - a field
  renamed in one but not the other, a type that no longer matches - is caught
  here rather than surfacing in a sibling's CI.

  No JSON Schema library is used or added as a dependency (per this repo's
  constraint: predicator has zero runtime dependencies, and none may be
  reintroduced for dev/test either without cause). What follows is a small,
  targeted structural validator - required keys, JSON types, `enum`,
  `pattern`, one level of `items`, and `oneOf` over `required` - not a general
  JSON Schema engine: no `$ref` resolution, no `allOf`/`not`, no `format`.
  That is a deliberate proportionality call: the goal these tests exist for
  is "a schema that drifts from the generator is caught", and a hand-rolled
  check against the handful of schema features this repo's own schemas
  actually use accomplishes that without the weight (or the new dependency)
  of a full validator.
  """

  use ExUnit.Case, async: true

  alias Mix.Tasks.Corpus.Generate, as: CorpusGenerate

  @schema_dir "conformance/schema"

  describe "every checked-in corpus tier file validates against schema/corpus.json" do
    test "each case in each tier-N.json satisfies the schema" do
      schema = read_schema("corpus.json")

      for path <- Path.wildcard("conformance/corpus/tier-*.json") do
        for line <- path |> File.read!() |> String.split("\n", trim: true) do
          case_json = JSON.decode!(line)

          assert :ok == validate(schema, case_json),
                 "#{path}: case #{inspect(case_json["id"])} fails schema/corpus.json: " <>
                   inspect(validate(schema, case_json))
        end
      end
    end
  end

  describe "the checked-in manifest.json validates against schema/manifest.json" do
    test "the manifest satisfies the schema" do
      schema = read_schema("manifest.json")
      manifest = "conformance/manifest.json" |> File.read!() |> JSON.decode!()

      assert :ok == validate(schema, manifest)
    end
  end

  describe "every authored case validates against schema/case.json" do
    test "each case in conformance/cases/*.json satisfies the schema" do
      schema = read_schema("case.json")

      for path <- Path.wildcard("conformance/cases/*.json") do
        for authored_case <- path |> File.read!() |> JSON.decode!() do
          assert :ok == validate(schema, authored_case),
                 "#{path}: case #{inspect(authored_case["id"])} fails schema/case.json: " <>
                   inspect(validate(schema, authored_case))
        end
      end
    end
  end

  describe "schema/report.json is internally consistent" do
    test ~s(the result enum is exactly ["pass", "fail"] - the structural half of never-skip) do
      schema = read_schema("report.json")
      result_schema = get_in(schema, ["properties", "results", "items", "properties", "result"])

      assert result_schema["enum"] == ["pass", "fail"]
    end

    test "a well-formed report instance validates" do
      schema = read_schema("report.json")

      report = %{
        "isa_version" => 2,
        "corpus_hash" => "sha256:" <> String.duplicate("a", 64),
        "tier" => 1,
        "surface" => "evaluator",
        "results" => [%{"id" => "core/literal-true", "result" => "pass"}]
      }

      assert :ok == validate(schema, report)
    end

    test "a report containing a skip result fails validation" do
      schema = read_schema("report.json")

      report = %{
        "isa_version" => 2,
        "corpus_hash" => "sha256:" <> String.duplicate("a", 64),
        "tier" => 1,
        "surface" => "evaluator",
        "results" => [%{"id" => "core/literal-true", "result" => "skip"}]
      }

      assert {:error, _reason} = validate(schema, report)
    end
  end

  # Builds the exact file map mix corpus.generate writes and asserts it
  # matches what is checked in, so a validation run here is never silently
  # exercising a stale corpus.
  test "the checked-in corpus matches what generation would produce right now" do
    assert {:ok, files} = CorpusGenerate.build_files()

    for {path, expected_content} <- files do
      assert File.read!(path) == expected_content, "#{path} is stale - run `mix corpus.generate`"
    end
  end

  @spec read_schema(String.t()) :: map()
  defp read_schema(filename) do
    @schema_dir |> Path.join(filename) |> File.read!() |> JSON.decode!()
  end

  # --- minimal structural validator -----------------------------------

  @spec validate(map(), term()) :: :ok | {:error, term()}
  defp validate(schema, instance) do
    with :ok <- validate_type(schema["type"], instance),
         :ok <- validate_enum(schema["enum"], instance),
         :ok <- validate_pattern(schema["pattern"], instance),
         :ok <- validate_required(schema["required"], instance),
         :ok <- validate_properties(schema["properties"], instance),
         :ok <- validate_additional_properties(schema, instance),
         :ok <- validate_items(schema["items"], instance) do
      validate_one_of(schema["oneOf"], instance)
    end
  end

  @spec validate_type(String.t() | [String.t()] | nil, term()) :: :ok | {:error, term()}
  defp validate_type(nil, _instance), do: :ok
  defp validate_type(true, _instance), do: :ok

  defp validate_type(type, instance) when is_binary(type) do
    if json_type?(type, instance), do: :ok, else: {:error, {:wrong_type, type, instance}}
  end

  defp validate_type(types, instance) when is_list(types) do
    if Enum.any?(types, &json_type?(&1, instance)),
      do: :ok,
      else: {:error, {:wrong_type, types, instance}}
  end

  @spec json_type?(String.t(), term()) :: boolean()
  defp json_type?("string", v), do: is_binary(v)
  defp json_type?("integer", v), do: is_integer(v)
  defp json_type?("number", v), do: is_number(v)
  defp json_type?("boolean", v), do: is_boolean(v)
  defp json_type?("array", v), do: is_list(v)
  defp json_type?("null", v), do: is_nil(v)
  defp json_type?("object", v), do: is_map(v)

  @spec validate_enum([term()] | nil, term()) :: :ok | {:error, term()}
  defp validate_enum(nil, _instance), do: :ok

  defp validate_enum(allowed, instance) do
    if instance in allowed, do: :ok, else: {:error, {:not_in_enum, allowed, instance}}
  end

  @spec validate_pattern(String.t() | nil, term()) :: :ok | {:error, term()}
  defp validate_pattern(nil, _instance), do: :ok

  defp validate_pattern(pattern, instance) when is_binary(instance) do
    if Regex.match?(Regex.compile!(pattern), instance),
      do: :ok,
      else: {:error, {:pattern_mismatch, pattern, instance}}
  end

  defp validate_pattern(_pattern, _instance), do: :ok

  @spec validate_required([String.t()] | nil, term()) :: :ok | {:error, term()}
  defp validate_required(nil, _instance), do: :ok

  defp validate_required(keys, instance) when is_map(instance) do
    missing = Enum.reject(keys, &Map.has_key?(instance, &1))
    if missing == [], do: :ok, else: {:error, {:missing_required, missing}}
  end

  defp validate_required(_keys, _instance), do: :ok

  @spec validate_properties(map() | nil, term()) :: :ok | {:error, term()}
  defp validate_properties(nil, _instance), do: :ok

  defp validate_properties(properties, instance) when is_map(instance) do
    properties
    |> Enum.filter(fn {key, _subschema} -> Map.has_key?(instance, key) end)
    |> Enum.reduce_while(:ok, fn {key, subschema}, :ok ->
      case validate(subschema, instance[key]) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:property, key, reason}}}
      end
    end)
  end

  defp validate_properties(_properties, _instance), do: :ok

  @spec validate_additional_properties(map(), term()) :: :ok | {:error, term()}
  defp validate_additional_properties(%{"additionalProperties" => false} = schema, instance)
       when is_map(instance) do
    known = schema |> Map.get("properties", %{}) |> Map.keys() |> MapSet.new()
    extra = instance |> Map.keys() |> Enum.reject(&MapSet.member?(known, &1))

    if extra == [], do: :ok, else: {:error, {:unexpected_properties, extra}}
  end

  defp validate_additional_properties(_schema, _instance), do: :ok

  @spec validate_items(map() | nil, term()) :: :ok | {:error, term()}
  defp validate_items(nil, _instance), do: :ok
  defp validate_items(true, _instance), do: :ok

  defp validate_items(item_schema, instance) when is_list(instance) do
    instance
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {item, index}, :ok ->
      case validate(item_schema, item) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:item, index, reason}}}
      end
    end)
  end

  defp validate_items(_item_schema, _instance), do: :ok

  @spec validate_one_of([map()] | nil, term()) :: :ok | {:error, term()}
  defp validate_one_of(nil, _instance), do: :ok

  defp validate_one_of(subschemas, instance) do
    matches = Enum.count(subschemas, &(validate(&1, instance) == :ok))

    if matches == 1, do: :ok, else: {:error, {:one_of_matched, matches, subschemas}}
  end
end
