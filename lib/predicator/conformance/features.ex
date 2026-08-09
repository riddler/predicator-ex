defmodule Predicator.Conformance.Features do
  @moduledoc """
  Feature tags for the conformance corpus (`px-35i.4`).

  Tiers (`Predicator.Instructions.tier/1`) are the coarse cut: "everything a
  tier-N implementation needs". Feature tags are the finer cut *across*
  tiers - `durations`, `strict_equality`, `short_circuit` - so an
  implementation that wants one advanced feature early can select for it
  without taking its whole tier, and a sibling reports what it lacks in these
  terms (bead px-35i.4's description).

  The full tag vocabulary: `comparison`, `strict_equality`, `short_circuit`,
  `arithmetic`, `membership`, `access`, `objects`, `dates`, `datetimes`,
  `durations`, `functions`, `legacy_logical`, `undefined`, `errors`, `casts`.

  This is a good-faith mapping, not an exhaustive one - see the per-clause
  comments below for the simplifications taken. `lit`, `load`, `not`, and
  `unary_bang` carry no tag of their own; they show up in nearly every case
  and would just add noise.
  """

  alias Predicator.Errors.{EvaluationError, TypeMismatchError, UndefinedVariableError}

  @typedoc """
  A case outcome, as computed by the generator - what the tags are derived
  from. `:retired` stands in for a real error struct when a case's `expected`
  is frozen data rather than a live evaluation (`Predicator.Conformance.
  Generator`'s retired-opcode path) - `outcome_tags/1`'s `{:error, _other}`
  catch-all maps it to the same `"errors"` tag a real struct would produce.
  """
  @type outcome :: {:result, term()} | {:error, struct() | :retired}

  # Opcode -> the tag(s) it always contributes, regardless of operands.
  # `compare` and the legacy `and`/`or` opcodes are handled separately below
  # because their tag depends on an operand, not just the opcode name.
  @opcode_tags %{
    "jump_if_falsy_or_pop" => ~w(short_circuit),
    "jump_if_true_or_pop" => ~w(short_circuit),
    "add" => ~w(arithmetic),
    "subtract" => ~w(arithmetic),
    "multiply" => ~w(arithmetic),
    "divide" => ~w(arithmetic),
    "modulo" => ~w(arithmetic),
    "unary_minus" => ~w(arithmetic),
    "in" => ~w(membership),
    "contains" => ~w(membership),
    "access" => ~w(access),
    "bracket_access" => ~w(access),
    "make_list" => ~w(access),
    "object_new" => ~w(objects),
    "object_set" => ~w(objects),
    "duration" => ~w(durations),
    "relative_date" => ~w(dates),
    "call" => ~w(functions),
    "cast" => ~w(casts)
  }

  @doc """
  Computes the feature tag set for a case: opcode-derived tags from
  `instructions`, plus value-derived tags from `context` and the case
  `outcome`, merged with any authored `extra_tags`.

  Returns a sorted, deduplicated list of tag strings - sorted so the shipped
  corpus is deterministic (`Predicator.Conformance.JSON`'s canonical encoder
  sorts map keys but not list contents, so this function does its own
  sorting).

  ## Examples

      iex> Predicator.Conformance.Features.compute([["lit", 1]], %{}, {:result, 1}, [])
      []

      iex> Predicator.Conformance.Features.compute([["compare", "GT"]], %{}, {:result, true}, [])
      ["comparison"]

      iex> Predicator.Conformance.Features.compute([["compare", "STRICT_EQ"]], %{}, {:result, true}, [])
      ["comparison", "strict_equality"]

      iex> Predicator.Conformance.Features.compute([["and"]], %{}, {:result, true}, [])
      ["legacy_logical"]

      iex> Predicator.Conformance.Features.compute([["add"]], %{}, {:result, :undefined}, ["custom"])
      ["arithmetic", "custom", "undefined"]
  """
  @spec compute(Predicator.Types.instruction_list(), map(), outcome(), [String.t()]) :: [
          String.t()
        ]
  def compute(instructions, context, outcome, extra_tags)
      when is_list(instructions) and is_map(context) and is_list(extra_tags) do
    opcode_tags = instructions |> Enum.flat_map(&instruction_tags/1) |> MapSet.new()
    value_tags = context |> Map.values() |> Enum.reduce(MapSet.new(), &collect_value_tags/2)
    outcome_tags = outcome_tags(outcome)

    opcode_tags
    |> MapSet.union(value_tags)
    |> MapSet.union(outcome_tags)
    |> MapSet.union(MapSet.new(extra_tags))
    |> Enum.sort()
  end

  @spec instruction_tags(term()) :: [String.t()]
  defp instruction_tags(["compare", operator | _rest])
       when operator in ["STRICT_EQ", "STRICT_NEQ"] do
    ~w(comparison strict_equality)
  end

  defp instruction_tags(["compare" | _rest]), do: ~w(comparison)

  # ["and"]/["or"] appear in an instruction list only as the legacy
  # evaluator-only opcodes (ADR-0001) - the compiler always emits
  # jump_if_falsy_or_pop/jump_if_true_or_pop for source-level `and`/`or`, so
  # seeing the bare opcode name is itself the signal.
  defp instruction_tags(["and" | _rest]), do: ~w(legacy_logical)
  defp instruction_tags(["or" | _rest]), do: ~w(legacy_logical)

  defp instruction_tags([opcode | _rest]) when is_binary(opcode) do
    Map.get(@opcode_tags, opcode, [])
  end

  defp instruction_tags(_malformed), do: []

  # Value-derived tags scan context values one level deep only - a good-faith
  # effort per the plan, not a full recursive walk. A date/datetime/duration
  # buried inside a nested list or map context value will not pick up its tag
  # this way; broadening this is left to a later bead if the seed corpus needs
  # it (Phase 5 authors can always add the tag explicitly via `features`).
  @spec collect_value_tags(term(), MapSet.t()) :: MapSet.t()
  defp collect_value_tags(%Date{}, acc), do: MapSet.put(acc, "dates")
  defp collect_value_tags(%DateTime{}, acc), do: MapSet.put(acc, "datetimes")
  defp collect_value_tags(:undefined, acc), do: MapSet.put(acc, "undefined")

  defp collect_value_tags(value, acc) when is_map(value) do
    if duration_map?(value), do: MapSet.put(acc, "durations"), else: acc
  end

  defp collect_value_tags(_value, acc), do: acc

  @duration_keys ~w(years months weeks days hours minutes seconds)a
  @spec duration_map?(map()) :: boolean()
  defp duration_map?(value), do: Enum.all?(@duration_keys, &Map.has_key?(value, &1))

  @spec outcome_tags(outcome()) :: MapSet.t()
  defp outcome_tags({:result, :undefined}), do: MapSet.new(["undefined"])
  defp outcome_tags({:result, _value}), do: MapSet.new()

  defp outcome_tags({:error, %UndefinedVariableError{}}), do: MapSet.new(["errors", "undefined"])

  defp outcome_tags({:error, %EvaluationError{}}), do: MapSet.new(["errors"])
  defp outcome_tags({:error, %TypeMismatchError{}}), do: MapSet.new(["errors"])
  defp outcome_tags({:error, _other}), do: MapSet.new(["errors"])
end
