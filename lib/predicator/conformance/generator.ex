defmodule Predicator.Conformance.Generator do
  @moduledoc """
  The pure half of conformance corpus generation (`px-35i.4`).

  `generate/1` takes decoded authored cases - already-`JSON.decode/1`-ed maps
  from `conformance/cases/*.json` - and runs each through the real compiler
  and evaluator, deriving everything the authored case does not spell out:
  `instructions` (when a case authors `source`), `expected_result` or
  `expected_error`, `tier`, and `features`.

  An authored `expected` or `tier` is an **assertion**, not data: if either
  disagrees with what the real pipeline computes, generation fails naming the
  case and both values, so a sibling author's belief about semantics gets
  checked against Elixir's behavior rather than silently overwritten.

  Failures accumulate rather than halting on the first one - a contributor
  fixing five broken cases should see five errors in one run, not one at a
  time.

  This module writes nothing to disk and knows nothing about
  `conformance/cases/*.json` as files; `mix corpus.generate` (`px-35i.4`
  Phase 4) is the thin I/O shell around it.
  """

  alias Predicator.Conformance.{Features, Values}
  alias Predicator.Errors.{EvaluationError, TypeMismatchError, UndefinedVariableError}
  alias Predicator.Instructions
  alias Predicator.Types

  @typedoc "An authored case, already JSON-decoded: string keys, JSON-shaped values."
  @type authored_case :: %{optional(String.t()) => term()}

  @typedoc "A completed case: the authored fields plus everything the generator derived."
  @type completed_case :: %{optional(String.t()) => term()}

  @typedoc "One per-case generation failure: the case id (`nil` if unknown) and a human-readable problem."
  @type case_error :: %{id: String.t() | nil, problem: String.t()}

  # Tier names (docs/isa.md's tier table, also in the plan's Phase 1 note).
  # Tier 6 (statements) has no opcodes yet, so it never appears in a real
  # manifest today, but the name is here so the day `store` lands this table
  # does not need editing.
  @tier_names %{
    1 => "core",
    2 => "arithmetic",
    3 => "access",
    4 => "rich types",
    5 => "functions",
    6 => "statements"
  }

  @doc """
  Runs every authored case through the real compiler and evaluator.

  Returns `{:ok, %{tiers: %{1 => [case], ...}, manifest: manifest}}` when
  every case generates cleanly, or `{:error, [case_error, ...]}` with **every**
  failing case's problem, not just the first.

  Accepts an options keyword list. The only option is `:retired_opcodes`, a
  `MapSet` of opcode names this build's reference evaluator can no longer run
  (`docs/isa.md` section 4, "Retired opcodes"). It defaults to the opcodes
  present in `Instructions.opcodes/0` but absent from
  `Instructions.opcode_set(Instructions.isa_version())` - today that default
  is empty, since no opcode carries `:removed_in` yet. A case that uses a
  retired opcode is classified in `generate_case/3` and takes a frozen-
  expectation path instead of running the pipeline below.

  ## Examples

      iex> {:ok, result} = Predicator.Conformance.Generator.generate([
      ...>   %{"id" => "core/literal-true", "source" => "true", "expected" => %{"result" => true}}
      ...> ])
      iex> result.tiers[1]
      [
        %{
          "id" => "core/literal-true",
          "source" => "true",
          "instructions" => [["lit", true]],
          "context" => %{},
          "expected_result" => true,
          "tier" => 1,
          "features" => []
        }
      ]

      iex> Predicator.Conformance.Generator.generate([%{"id" => "bad", "source" => "score >"}])
      {:error, [%{id: "bad", problem: "source \\"score >\\" failed to compile: Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input at line 1, column 8"}]}
  """
  @spec generate([authored_case()], keyword()) ::
          {:ok, %{tiers: %{pos_integer() => [completed_case()]}, manifest: map()}}
          | {:error, [case_error()]}
  def generate(cases, opts \\ []) when is_list(cases) and is_list(opts) do
    retired_opcodes = Keyword.get(opts, :retired_opcodes, default_retired_opcodes())
    duplicate_ids = duplicate_ids(cases)

    {oks, errors} =
      cases
      |> Enum.map(&generate_case(&1, duplicate_ids, retired_opcodes))
      |> Enum.split_with(&match?({:ok, _completed}, &1))

    case errors do
      [] ->
        completed = Enum.map(oks, fn {:ok, completed} -> completed end)
        {:ok, %{tiers: group_by_tier(completed), manifest: build_manifest(completed)}}

      _some_errors ->
        {:error, Enum.map(errors, fn {:error, error} -> error end)}
    end
  end

  # The opcodes this build's Instructions table knows about but this build's
  # ISA version no longer includes (docs/isa.md section 1's half-open
  # interval). `and` and `or` are the only members since ISA v3 retired them
  # (px-tbv.9); generate/2 with an explicit :retired_opcodes of that same set
  # agrees with generate/1's default.
  @spec default_retired_opcodes() :: MapSet.t(String.t())
  defp default_retired_opcodes do
    all_opcodes = Instructions.opcodes() |> Map.keys() |> MapSet.new()
    MapSet.difference(all_opcodes, Instructions.opcode_set(Instructions.isa_version()))
  end

  @spec duplicate_ids([authored_case()]) :: MapSet.t(term())
  defp duplicate_ids(cases) do
    cases
    |> Enum.map(&Map.get(&1, "id"))
    |> Enum.frequencies()
    |> Enum.filter(fn {_id, count} -> count > 1 end)
    |> Enum.into(MapSet.new(), fn {id, _count} -> id end)
  end

  @spec generate_case(authored_case(), MapSet.t(term()), MapSet.t(String.t())) ::
          {:ok, completed_case()} | {:error, case_error()}
  defp generate_case(raw, duplicate_ids, retired_opcodes) do
    id_for_error = Map.get(raw, "id")

    with {:ok, id} <- fetch_id(raw, duplicate_ids),
         {:ok, endpoint} <- fetch_endpoint(raw),
         {:ok, context} <- decode_context(raw),
         {:ok, instructions} <- resolve_instructions(endpoint),
         retired_used = retired_opcodes_used(instructions, retired_opcodes),
         {:ok, {outcome, expected}} <- resolve_outcome(raw, instructions, context, retired_used),
         {:ok, {tier, forcing_opcode}} <- compute_tier(instructions),
         :ok <- check_tier(raw, tier, forcing_opcode),
         {:ok, encoded_instructions} <- encode_instructions(instructions) do
      extra_tags = authored_features(raw) ++ retired_feature_tags(retired_used)
      features = Features.compute(instructions, context, outcome, extra_tags)
      {:ok, assemble_case(id, raw, encoded_instructions, expected, tier, features)}
    else
      {:error, problem} -> {:error, %{id: id_for_error, problem: problem}}
    end
  end

  # A case using an opcode this build's ISA version has retired cannot be
  # completed by the reference evaluator - there is no clause left to run it
  # (docs/isa.md section 4, "Retired opcodes"). Its authored `expected` is
  # frozen as data instead: the case keeps its id, its tier, and its place in
  # the live corpus so a sibling claiming an earlier version still has it, and
  # so the ratchet's case ids keep resolving.
  @spec resolve_outcome(authored_case(), Types.instruction_list(), map(), [String.t()]) ::
          {:ok, {Features.outcome(), {:result, Values.json()} | {:error, map()}}}
          | {:error, String.t()}
  defp resolve_outcome(raw, instructions, context, [] = _retired_used) do
    with {:ok, outcome} <- evaluate_case(instructions, context),
         {:ok, expected} <- expected_fields(outcome),
         :ok <- check_expected(raw, expected) do
      {:ok, {outcome, expected}}
    end
  end

  defp resolve_outcome(raw, _instructions, _context, retired_used) do
    with :ok <- check_no_source(raw, retired_used),
         {:ok, expected} <- fetch_frozen_expected(raw, retired_used),
         {:ok, outcome} <- synthesize_outcome(expected) do
      {:ok, {outcome, expected}}
    end
  end

  @spec retired_opcodes_used(Types.instruction_list(), MapSet.t(String.t())) :: [String.t()]
  defp retired_opcodes_used(instructions, retired_opcodes) do
    instructions
    |> Enum.flat_map(fn
      [opcode | _operands] when is_binary(opcode) -> [opcode]
      _malformed -> []
    end)
    |> Enum.filter(&MapSet.member?(retired_opcodes, &1))
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec check_no_source(authored_case(), [String.t()]) :: :ok | {:error, String.t()}
  defp check_no_source(raw, retired_used) do
    case Map.get(raw, "source") do
      source when is_binary(source) ->
        {:error,
         "case uses retired opcode(s) #{inspect(retired_used)} and authors \"source\" - " <>
           "the compiler cannot emit a retired opcode; author \"instructions\" directly"}

      _no_source ->
        :ok
    end
  end

  @spec fetch_frozen_expected(authored_case(), [String.t()]) ::
          {:ok, {:result, Values.json()} | {:error, map()}} | {:error, String.t()}
  defp fetch_frozen_expected(raw, retired_used) do
    case Map.get(raw, "expected") do
      %{"result" => result} = expected when map_size(expected) == 1 ->
        {:ok, {:result, result}}

      %{"error" => error} = expected when map_size(expected) == 1 ->
        {:ok, {:error, error}}

      nil ->
        {:error,
         "case uses retired opcode(s) #{inspect(retired_used)} and must author \"expected\" - " <>
           "the reference evaluator can no longer compute it"}

      other ->
        {:error,
         ~s("expected" must be exactly {"result": ...} or {"error": {...}}, got #{inspect(other)})}
    end
  end

  # Synthesizes an outcome from the frozen `expected` so Features.compute/4
  # still has something to derive value-level tags from. `{:error, :retired}`
  # is not a real error struct, but Features.outcome_tags/1's
  # `{:error, _other}` catch-all maps any error term to the "errors" tag, the
  # same tag a real struct would produce - so this is a safe stand-in.
  @spec synthesize_outcome({:result, Values.json()} | {:error, map()}) ::
          {:ok, Features.outcome()} | {:error, String.t()}
  defp synthesize_outcome({:result, json}) do
    case Values.from_json(json) do
      {:ok, decoded} ->
        {:ok, {:result, decoded}}

      {:error, reason} ->
        {:error,
         "authored expected result #{inspect(json)} could not be decoded: #{inspect(reason)}"}
    end
  end

  defp synthesize_outcome({:error, _error_map}), do: {:ok, {:error, :retired}}

  @spec retired_feature_tags([String.t()]) :: [String.t()]
  defp retired_feature_tags([]), do: []
  defp retired_feature_tags(_retired_used), do: ["retired"]

  # `instructions` (from Predicator.compile/1 or an authored "instructions"
  # list) carries real ISA values as operands - a "lit" pushing a Date,
  # DateTime, or duration map is common once a case exercises tier 4. Those
  # are not JSON-encodable as-is (Predicator.Conformance.JSON's canonical
  # encoder only sorts and escapes; it does not know the ISA value domain),
  # so every operand is round-tripped through the same tagged-value codec
  # used for context and expected_result/expected_error before the
  # instructions list is shipped. Values.to_json/1 already walks nested
  # lists generically, so passing it the whole instructions list handles
  # every opcode's operand shape (string, integer, [integer, string] pairs,
  # value literals) uniformly.
  @spec encode_instructions(Types.instruction_list()) ::
          {:ok, [Values.json()]} | {:error, String.t()}
  defp encode_instructions(instructions) do
    case Values.to_json(instructions) do
      {:ok, encoded} ->
        {:ok, encoded}

      {:error, reason} ->
        {:error, "instructions #{inspect(instructions)} could not be encoded: #{inspect(reason)}"}
    end
  end

  @spec fetch_id(authored_case(), MapSet.t(term())) :: {:ok, String.t()} | {:error, String.t()}
  defp fetch_id(raw, duplicate_ids) do
    case Map.get(raw, "id") do
      id when is_binary(id) and id != "" ->
        if MapSet.member?(duplicate_ids, id) do
          {:error, "duplicate case id #{inspect(id)} - case ids must be globally unique"}
        else
          {:ok, id}
        end

      other ->
        {:error,
         "case is missing a required, non-empty string \"id\" field, got #{inspect(other)}"}
    end
  end

  @spec fetch_endpoint(authored_case()) ::
          {:ok, {:source, String.t()} | {:instructions, list()}} | {:error, String.t()}
  defp fetch_endpoint(raw) do
    source = Map.get(raw, "source")
    instructions = Map.get(raw, "instructions")
    has_source = is_binary(source)
    has_instructions = is_list(instructions)

    cond do
      has_source and has_instructions ->
        {:error, ~s(case has both "source" and "instructions" - exactly one is required)}

      has_source ->
        {:ok, {:source, source}}

      has_instructions ->
        {:ok, {:instructions, instructions}}

      true ->
        {:error, ~s(case has neither "source" nor "instructions" - exactly one is required)}
    end
  end

  @spec decode_context(authored_case()) :: {:ok, map()} | {:error, String.t()}
  defp decode_context(raw) do
    case Map.get(raw, "context", %{}) do
      context when is_map(context) ->
        case Values.from_json(context) do
          {:ok, decoded} when is_map(decoded) ->
            {:ok, decoded}

          {:error, reason} ->
            {:error, "\"context\" failed to decode: #{inspect(reason)}"}
        end

      other ->
        {:error, "\"context\" must be a JSON object, got #{inspect(other)}"}
    end
  end

  @spec resolve_instructions({:source, String.t()} | {:instructions, list()}) ::
          {:ok, Types.instruction_list()} | {:error, String.t()}
  defp resolve_instructions({:source, source}) do
    case Predicator.compile(source) do
      {:ok, instructions} -> {:ok, instructions}
      {:error, message} -> {:error, "source #{inspect(source)} failed to compile: #{message}"}
    end
  end

  defp resolve_instructions({:instructions, instructions}), do: {:ok, instructions}

  @spec evaluate_case(Types.instruction_list(), map()) ::
          {:ok, Features.outcome()} | {:error, String.t()}
  defp evaluate_case(instructions, context) do
    case Predicator.evaluate(instructions, context, []) do
      {:ok, result} -> {:ok, {:result, result}}
      {:error, error} -> {:ok, {:error, error}}
    end
  rescue
    exception -> {:error, "evaluation raised #{inspect(exception)}"}
  end

  @spec expected_fields(Features.outcome()) ::
          {:ok, {:result, Values.json()} | {:error, %{String.t() => String.t()}}}
          | {:error, String.t()}
  defp expected_fields({:result, result}) do
    case Values.to_json(result) do
      {:ok, json} ->
        {:ok, {:result, json}}

      {:error, reason} ->
        {:error, "computed result #{inspect(result)} could not be encoded: #{inspect(reason)}"}
    end
  end

  defp expected_fields({:error, error_struct}), do: {:ok, {:error, encode_error(error_struct)}}

  # Error type is the struct's short module name; error reason is normative
  # per docs/isa.md, but only EvaluationError carries a `reason` string field
  # directly - TypeMismatchError and UndefinedVariableError have no such
  # field, so this derives the closest stable token from what they do carry
  # (the failing operation, or a fixed token for an unbound variable). The
  # error message is never carried, per the plan. No catch-all clause: three
  # error types are the whole documented taxonomy (docs/isa.md); a fourth
  # showing up here is a spec change worth a loud crash, not a silent
  # "unknown" reason.
  @spec encode_error(EvaluationError.t() | TypeMismatchError.t() | UndefinedVariableError.t()) ::
          %{String.t() => String.t()}
  defp encode_error(%EvaluationError{reason: reason}) do
    %{"type" => "EvaluationError", "reason" => reason}
  end

  defp encode_error(%TypeMismatchError{operation: operation}) do
    %{"type" => "TypeMismatchError", "reason" => to_string(operation)}
  end

  defp encode_error(%UndefinedVariableError{}) do
    %{"type" => "UndefinedVariableError", "reason" => "unbound_variable"}
  end

  @spec check_expected(authored_case(), {:result, Values.json()} | {:error, map()}) ::
          :ok | {:error, String.t()}
  defp check_expected(raw, computed) do
    case Map.get(raw, "expected") do
      nil ->
        :ok

      %{"result" => authored} = expected when map_size(expected) == 1 ->
        check_expected_result(authored, computed)

      %{"error" => authored} = expected when map_size(expected) == 1 ->
        check_expected_error(authored, computed)

      other ->
        {:error,
         ~s("expected" must be exactly {"result": ...} or {"error": {...}}, got #{inspect(other)})}
    end
  end

  @spec check_expected_result(term(), {:result, Values.json()} | {:error, map()}) ::
          :ok | {:error, String.t()}
  defp check_expected_result(authored, {:result, computed}) do
    if authored == computed do
      :ok
    else
      {:error,
       "authored expected result #{inspect(authored)} does not match computed result #{inspect(computed)}"}
    end
  end

  defp check_expected_result(authored, {:error, computed}) do
    {:error,
     "authored expected a result (#{inspect(authored)}) but evaluation produced an error: #{inspect(computed)}"}
  end

  @spec check_expected_error(term(), {:result, Values.json()} | {:error, map()}) ::
          :ok | {:error, String.t()}
  defp check_expected_error(authored, {:error, computed}) do
    if authored == computed do
      :ok
    else
      {:error,
       "authored expected error #{inspect(authored)} does not match computed error #{inspect(computed)}"}
    end
  end

  defp check_expected_error(authored, {:result, computed}) do
    {:error,
     "authored expected an error (#{inspect(authored)}) but evaluation produced a result: #{inspect(computed)}"}
  end

  # Computes tier and the opcode that forced it in one pass, so a mismatch
  # can name that opcode without a second traversal - and without a
  # defensive "shape didn't match after all" branch that a single pass
  # already rules out for every instruction it accepted.
  @spec compute_tier(Types.instruction_list()) ::
          {:ok, {pos_integer(), String.t() | nil}} | {:error, String.t()}
  defp compute_tier(instructions) do
    Enum.reduce_while(instructions, {:ok, {1, nil}}, fn instruction,
                                                        {:ok, {acc_tier, acc_opcode}} ->
      case instruction_tier(instruction) do
        {:ok, {tier, opcode}} when tier > acc_tier -> {:cont, {:ok, {tier, opcode}}}
        {:ok, {_tier, _opcode}} -> {:cont, {:ok, {acc_tier, acc_opcode}}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @spec instruction_tier(term()) :: {:ok, {pos_integer(), String.t()}} | {:error, String.t()}
  defp instruction_tier([opcode | _operands]) when is_binary(opcode) do
    case Instructions.tier(opcode) do
      {:ok, tier} -> {:ok, {tier, opcode}}
      {:error, %{message: message}} -> {:error, "instructions use #{message}"}
    end
  end

  defp instruction_tier(malformed), do: {:error, "malformed instruction: #{inspect(malformed)}"}

  @spec check_tier(authored_case(), pos_integer(), String.t() | nil) ::
          :ok | {:error, String.t()}
  defp check_tier(raw, computed_tier, forcing_opcode) do
    case Map.get(raw, "tier") do
      nil ->
        :ok

      ^computed_tier ->
        :ok

      authored when is_integer(authored) ->
        {:error,
         "authored tier #{authored} does not match computed tier #{computed_tier} " <>
           "(forced by opcode #{inspect(forcing_opcode)})"}

      other ->
        {:error, "\"tier\" must be an integer, got #{inspect(other)}"}
    end
  end

  @spec authored_features(authored_case()) :: [String.t()]
  defp authored_features(raw) do
    case Map.get(raw, "features") do
      list when is_list(list) -> list
      _other -> []
    end
  end

  @spec assemble_case(
          String.t(),
          authored_case(),
          [Values.json()],
          {:result, Values.json()} | {:error, map()},
          pos_integer(),
          [String.t()]
        ) :: completed_case()
  defp assemble_case(id, raw, instructions, expected, tier, features) do
    base = %{
      "id" => id,
      "source" => Map.get(raw, "source"),
      "instructions" => instructions,
      "context" => Map.get(raw, "context", %{}),
      "tier" => tier,
      "features" => features
    }

    base =
      case expected do
        {:result, json} -> Map.put(base, "expected_result", json)
        {:error, error} -> Map.put(base, "expected_error", error)
      end

    case Map.get(raw, "notes") do
      nil -> base
      notes -> Map.put(base, "notes", notes)
    end
  end

  # The opcode table restricted to what this build's ISA version currently
  # includes (docs/isa.md section 1's half-open interval, via
  # `Instructions.opcode_set/1`). A retired opcode keeps its case(s) in the
  # corpus (see the retired-case path above) but leaves this view, so a
  # tier's "opcodes" array in the manifest lists what that tier unlocks *at
  # this build's ISA version* - a no-op today, since no opcode carries
  # :removed_in yet.
  @spec current_opcodes() :: %{String.t() => Instructions.opcode_info()}
  defp current_opcodes do
    live = Instructions.opcode_set(Instructions.isa_version())
    Instructions.opcodes() |> Map.filter(fn {opcode, _info} -> MapSet.member?(live, opcode) end)
  end

  @spec group_by_tier([completed_case()]) :: %{pos_integer() => [completed_case()]}
  defp group_by_tier(cases) do
    known_tiers = current_opcodes() |> Map.values() |> Enum.map(& &1.tier) |> Enum.uniq()
    base = Map.new(known_tiers, &{&1, []})

    cases
    |> Enum.group_by(& &1["tier"])
    |> Enum.reduce(base, fn {tier, tier_cases}, acc ->
      Map.put(acc, tier, Enum.sort_by(tier_cases, & &1["id"]))
    end)
  end

  @spec build_manifest([completed_case()]) :: map()
  defp build_manifest(cases) do
    opcodes_by_tier =
      current_opcodes()
      |> Enum.group_by(fn {_opcode, %{tier: tier}} -> tier end, fn {opcode, _info} -> opcode end)

    case_counts = Enum.frequencies_by(cases, & &1["tier"])

    tiers =
      opcodes_by_tier
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map(fn tier ->
        %{
          "tier" => tier,
          "name" => Map.get(@tier_names, tier, "tier #{tier}"),
          "opcodes" => Enum.sort(opcodes_by_tier[tier]),
          "case_count" => Map.get(case_counts, tier, 0)
        }
      end)

    %{"isa_version" => Predicator.isa_version(), "tiers" => tiers}
  end
end
