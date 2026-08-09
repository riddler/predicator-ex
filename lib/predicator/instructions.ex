defmodule Predicator.Instructions do
  @moduledoc """
  Version and tier queries over a compiled instruction list.

  The instruction set is versioned (ADR-0003): there is a current ISA version
  this build emits and can run, and any instruction list can be asked what
  version it requires. A consumer holding a stored artifact, or a sibling
  handed a list, compares the two and refuses up front rather than failing
  partway through a run.

  Every opcode also carries a **conformance tier** (`px-35i.4`): a
  conformance-corpus grouping, a function of opcode only, that never depends
  on the value types an expression happens to use. A lower tier is a smaller,
  more foundational surface, so an implementation that has only tier 1 can
  run only tier 1's cases and get a green.

  The opcode set, the ISA version each opcode was introduced at, and each
  opcode's tier are specified in [`docs/isa.md`](../../docs/isa.md) section 4;
  the table below is its executable form - one table with two columns, not
  two tables - and a test asserts the two agree.

  A retired opcode keeps its row rather than losing it: the row gains an
  optional `:removed_in` key naming the ISA version that retired it, so
  `required_isa/1` and `tier/1` keep answering with a version instead of
  falling back to `unknown_opcode` for an artifact that predates the
  retirement. A version's opcode set is therefore an interval - introduced at
  one version and, if ever retired, removed at another - and is fixed once
  minted: retiring an opcode at a later version does not change what an
  earlier version's set was. `in_isa?/2`, `opcode_set/1`, and `retired_in/1`
  are the queries built on that interval.

  ## Migration

  Retiring an opcode requires an upgrade path (ADR-0003), so a stored
  artifact holding a retired opcode is never simply stranded: `upgrade/1`
  rewrites it onto the current instruction set. See its `@doc` for the
  guarantee, the divergences it documents, and worked examples.
  """

  alias Predicator.Errors.EvaluationError
  alias Predicator.Instructions.Upgrade
  alias Predicator.Types

  # The ISA version this build emits and can run (docs/isa.md, section 1).
  @isa_version 4

  @typedoc """
  One opcode's table entry: the ISA version that introduced it, its conformance
  tier, and - only when it has been retired - the ISA version that removed it.
  An opcode is in ISA version `v` iff `isa <= v < removed_in` (docs/isa.md §1);
  an entry with no `:removed_in` key has never been retired.
  """
  @type opcode_info :: %{
          :isa => pos_integer(),
          :tier => pos_integer(),
          optional(:removed_in) => pos_integer()
        }

  # Opcode -> the ISA version that introduced it, and the conformance tier it
  # belongs to (docs/isa.md, section 4). An opcode's semantics never change
  # under its own name (ADR-0003), which is what makes a name scan a sound
  # answer rather than a best-effort one. isa_sync_test binds both columns to
  # docs/isa.md.
  @opcodes %{
    "lit" => %{isa: 1, tier: 1},
    "load" => %{isa: 1, tier: 1},
    "access" => %{isa: 1, tier: 3},
    "compare" => %{isa: 1, tier: 1},
    "and" => %{isa: 1, tier: 1, removed_in: 3},
    "or" => %{isa: 1, tier: 1, removed_in: 3},
    "not" => %{isa: 1, tier: 1},
    "in" => %{isa: 1, tier: 3},
    "contains" => %{isa: 1, tier: 3},
    "add" => %{isa: 1, tier: 2},
    "subtract" => %{isa: 1, tier: 2},
    "multiply" => %{isa: 1, tier: 2},
    "divide" => %{isa: 1, tier: 2},
    "modulo" => %{isa: 1, tier: 2},
    "unary_minus" => %{isa: 1, tier: 1},
    "unary_bang" => %{isa: 1, tier: 1},
    "bracket_access" => %{isa: 1, tier: 3},
    "call" => %{isa: 1, tier: 5},
    "object_new" => %{isa: 1, tier: 4},
    "object_set" => %{isa: 1, tier: 4},
    "duration" => %{isa: 1, tier: 4},
    "relative_date" => %{isa: 1, tier: 4},
    "make_list" => %{isa: 2, tier: 3},
    "jump_if_falsy_or_pop" => %{isa: 2, tier: 1},
    "jump_if_true_or_pop" => %{isa: 2, tier: 1},
    "store" => %{isa: 3, tier: 6},
    "pop" => %{isa: 3, tier: 6},
    "cast" => %{isa: 4, tier: 7}
  }

  @doc """
  Returns the ISA version this build emits and can run.
  """
  @spec isa_version() :: pos_integer()
  def isa_version, do: @isa_version

  @doc """
  Returns the full opcode table: every known opcode mapped to the ISA version
  that introduced it and its conformance tier (`docs/isa.md` section 4).

  ## Examples

      iex> Predicator.Instructions.opcodes()["lit"]
      %{isa: 1, tier: 1}
  """
  @spec opcodes() :: %{optional(String.t()) => opcode_info()}
  def opcodes, do: @opcodes

  @doc """
  Returns the conformance tier for a single `opcode`.

  Tier is a conformance-corpus grouping (`px-35i.4`), a function of opcode
  only - it never depends on the value types an expression happens to use
  (`docs/isa.md` section 4). Returns
  `{:error, %EvaluationError{reason: "unknown_opcode"}}` for an opcode not in
  the table, the same reason `required_isa/1` uses.

  ## Examples

      iex> Predicator.Instructions.tier("lit")
      {:ok, 1}

      iex> Predicator.Instructions.tier("make_list")
      {:ok, 3}

      iex> Predicator.Instructions.tier("nope")
      {:error, %Predicator.Errors.EvaluationError{reason: "unknown_opcode", message: "Unknown opcode: \\"nope\\"", operation: :tier}}
  """
  @spec tier(String.t()) :: {:ok, pos_integer()} | {:error, EvaluationError.t()}
  def tier(opcode) when is_binary(opcode) do
    case Map.fetch(@opcodes, opcode) do
      {:ok, %{tier: tier}} ->
        {:ok, tier}

      :error ->
        {:error,
         EvaluationError.new(
           "Unknown opcode: #{inspect(opcode)}",
           "unknown_opcode",
           :tier
         )}
    end
  end

  @doc """
  Returns whether an opcode's table entry is a member of `version`'s opcode set.

  A live entry (no `:removed_in` key) is in every version at or after the one
  that introduced it. A retired entry is in every version from the one that
  introduced it up to, but not including, the one that removed it - the
  half-open interval `[isa, removed_in)` (`docs/isa.md` §1). This is the
  membership test `opcode_set/1` is built from, and it is what a consumer
  should apply instead of a bare `required_isa(list) <= isa_version()`
  comparison once any opcode is retired: a retired opcode still reports the
  version that introduced it, so the `<=` comparison alone cannot see that a
  later build no longer runs it.

  Takes an explicit `opcode_info()` rather than an opcode name so the retired
  branch is doctestable and unit-testable today, before any real opcode
  carries a `:removed_in` value.

  ## Examples

      iex> Predicator.Instructions.in_isa?(%{isa: 1, tier: 1}, 1)
      true

      iex> Predicator.Instructions.in_isa?(%{isa: 2, tier: 3}, 1)
      false

      iex> Predicator.Instructions.in_isa?(%{isa: 1, tier: 1, removed_in: 3}, 2)
      true

      iex> Predicator.Instructions.in_isa?(%{isa: 1, tier: 1, removed_in: 3}, 3)
      false

      iex> Predicator.Instructions.in_isa?(%{isa: 1, tier: 1, removed_in: 3}, 4)
      false
  """
  @spec in_isa?(opcode_info(), pos_integer()) :: boolean()
  def in_isa?(%{isa: introduced} = info, version)
      when is_integer(version) and version > 0 do
    case Map.fetch(info, :removed_in) do
      {:ok, removed_in} -> introduced <= version and version < removed_in
      :error -> introduced <= version
    end
  end

  @doc """
  Returns the set of opcode names that are members of `version`'s opcode set.

  A build running ISA version `v` can run an instruction list iff every
  opcode it uses is a member of `opcode_set(v)`. This is the check that
  supersedes a bare `required_isa(list) <= isa_version()` comparison once any
  opcode is retired - `required_isa/1` alone stops being sufficient because a
  retired opcode still reports the version that introduced it, not the
  version that removed it.

  ## Examples

      iex> Predicator.Instructions.opcode_set(1) |> MapSet.member?("make_list")
      false

      iex> Predicator.Instructions.opcode_set(2) |> MapSet.member?("make_list")
      true
  """
  @spec opcode_set(pos_integer()) :: MapSet.t(String.t())
  def opcode_set(version) when is_integer(version) and version > 0 do
    for {opcode, info} <- @opcodes, in_isa?(info, version), into: MapSet.new(), do: opcode
  end

  @doc """
  Returns the ISA version that retired a single `opcode`, or `nil` if it has
  never been retired.

  Mirrors `tier/1`'s shape, including its `unknown_opcode` error for an
  opcode not in the table. Together with `required_isa/1`, this is what lets
  a refusal name both halves of ADR-0003's promised message: the version an
  instruction list needs, and, when that opcode has since been retired, the
  version that removed it.

  ## Examples

      iex> Predicator.Instructions.retired_in("lit")
      {:ok, nil}

      iex> Predicator.Instructions.retired_in("nope")
      {:error, %Predicator.Errors.EvaluationError{reason: "unknown_opcode", message: "Unknown opcode: \\"nope\\"", operation: :retired_in}}
  """
  @spec retired_in(String.t()) :: {:ok, pos_integer() | nil} | {:error, EvaluationError.t()}
  def retired_in(opcode) when is_binary(opcode) do
    case Map.fetch(@opcodes, opcode) do
      {:ok, info} ->
        {:ok, Map.get(info, :removed_in)}

      :error ->
        {:error,
         EvaluationError.new(
           "Unknown opcode: #{inspect(opcode)}",
           "unknown_opcode",
           :retired_in
         )}
    end
  end

  @doc """
  Returns the minimum ISA version required to run `instructions`.

  Scans only the opcode - the head of each top-level element - and never
  recurses into operands. That is deliberate, not incomplete: a list literal
  compiles to a nested list that looks like an instruction, e.g.
  `['load', 'x']` compiles to `[["lit", ["load", "x"]]]`
  (`lib/predicator/visitors/instructions_visitor.ex:223`). Recursing into
  operands would read `"load"` there and report a version the program does
  not actually require. Every real operand the compiler emits is a value or
  an integer, never a nested instruction (`docs/isa.md` sections 2 and 5), so
  a flat scan is sufficient as well as safe.

  Returns `{:ok, 1}` for an empty list - there is no v0, and the floor keeps
  `required_isa(list) <= isa_version()` correct without a `:none` case.

  Returns `{:error, %EvaluationError{reason: "unknown_opcode"}}` when an
  element's head is a binary not in the opcode table, and
  `{:error, %EvaluationError{reason: "malformed_instruction"}}` when an
  element is not a non-empty list headed by a binary. Both carry
  `operation: :required_isa`, distinct from the evaluator's
  `"unknown_instruction"`, which covers malformed *operands* too - this
  function does not look at operands.

  ## Examples

      iex> {:ok, instructions} = Predicator.compile("a > 1")
      iex> Predicator.Instructions.required_isa(instructions)
      {:ok, 1}

      iex> {:ok, instructions} = Predicator.compile("a and b")
      iex> Predicator.Instructions.required_isa(instructions)
      {:ok, 2}

      iex> Predicator.Instructions.required_isa([])
      {:ok, 1}

      iex> Predicator.Instructions.required_isa([["nope"]])
      {:error, %Predicator.Errors.EvaluationError{reason: "unknown_opcode", message: "Unknown opcode \\"nope\\"; this build supports ISA v4", operation: :required_isa}}
  """
  @spec required_isa(Types.instruction_list()) ::
          {:ok, pos_integer()} | {:error, EvaluationError.t()}
  def required_isa(instructions) when is_list(instructions) do
    instructions
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, 1}, fn {instruction, index}, {:ok, acc} ->
      case opcode_version(instruction, index) do
        {:ok, version} -> {:cont, {:ok, max(acc, version)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @spec opcode_version(term(), non_neg_integer()) ::
          {:ok, pos_integer()} | {:error, EvaluationError.t()}
  defp opcode_version([opcode | _operands], _index) when is_binary(opcode) do
    case Map.fetch(@opcodes, opcode) do
      {:ok, %{isa: version}} ->
        {:ok, version}

      :error ->
        {:error,
         EvaluationError.new(
           "Unknown opcode #{inspect(opcode)}; this build supports ISA v#{@isa_version}",
           "unknown_opcode",
           :required_isa
         )}
    end
  end

  defp opcode_version(_bad_instruction, index) do
    {:error,
     EvaluationError.new(
       "Malformed instruction at index #{index}",
       "malformed_instruction",
       :required_isa
     )}
  end

  @doc """
  Rewrites a pre-3.7 instruction list containing the retired `"and"`/`"or"`
  opcodes into current jump form.

  **Identity guarantee**: a list containing neither retired opcode is
  returned unchanged. A consumer can therefore call `upgrade/1`
  unconditionally over every stored artifact instead of pre-filtering for
  the ones that need it.

  Returns `{:error, %EvaluationError{reason: "unsupported_upgrade"}}`,
  `operation: :upgrade`, rather than a wrong answer, when the list is not
  something `upgrade/1` can safely rewrite: it mixes a v2 opcode with a
  retired opcode (a genuine pre-3.7 artifact cannot be in that state), it
  underflows its own stack, it contains an opcode `upgrade/1` does not
  recognize (including a `"call"` whose count operand is not a
  non-negative integer), or it contains a malformed element.

  ## Semantic divergences

  The rewritten list is not answer-preserving against the legacy opcodes -
  by design, per ADR-0001's Consequences, which already calls the
  short-circuit change on 3.7.0's compiler-emitted jumps "a bugfix" that
  breaks a consumer relying on the old behavior. `upgrade/1` moves a stored
  artifact onto the same semantics every source-compiled expression has had
  since 3.7.0. Against the legacy opcodes, the upgraded list differs when
  and only when:

  1. **Short-circuiting.** The right operand is no longer evaluated once the
     left operand decides the result. Observable when the right operand
     would have errored or loaded an unbound variable: legacy raised: the
     upgraded form returns the left value without touching the right.
  2. **`:undefined` operands.** Legacy raises a `TypeMismatchError`.
     Upgraded: `undefined and x` is `:undefined`; `undefined or x` is `x`'s
     value (ECMAScript-aligned, ADR-0001).
  3. **A non-boolean *right* operand the left operand did not decide.**
     `true and 1` was a `TypeMismatchError` and is now `1`. A non-boolean
     **left** operand still errors, since the guard sits on the operand the
     expression actually depends on - but the error moves from the retired
     opcode to the jump, so a consumer matching on it sees `operation:
     :jump_if_falsy_or_pop` / `:jump_if_true_or_pop` where it saw
     `:logical_and` / `:logical_or`, and a correspondingly reworded message.
     The struct is a `TypeMismatchError` either way.

  ## The upgraded list requires ISA v2

  Jumps are ISA v2 opcodes (`docs/isa.md` section 4), so upgrading raises a
  list's `required_isa/1` answer from `1` to `2`. This matters only where a
  stored artifact is shared with another implementation: both the Ruby and
  JavaScript siblings claim ISA v1 today, and a v1 implementation that ran
  the legacy list will refuse the upgraded one. Upgrade in step with the
  consumers of the artifact, not ahead of them.

  ## Examples

      iex> Predicator.Instructions.upgrade([["lit", 1], ["lit", 2], ["add"]])
      {:ok, [["lit", 1], ["lit", 2], ["add"]]}

      iex> Predicator.Instructions.upgrade([["lit", true], ["lit", false], ["and"]])
      {:ok, [["lit", true], ["jump_if_falsy_or_pop", 2], ["lit", false]]}

      iex> instructions = [
      ...>   ["lit", true], ["lit", false], ["and"],
      ...>   ["lit", true], ["or"]
      ...> ]
      iex> Predicator.Instructions.upgrade(instructions)
      {:ok,
       [
         ["lit", true],
         ["jump_if_falsy_or_pop", 2],
         ["lit", false],
         ["jump_if_true_or_pop", 2],
         ["lit", true]
       ]}

      iex> Predicator.Instructions.upgrade([["and"]])
      {:error, %Predicator.Errors.EvaluationError{reason: "unsupported_upgrade", message: "Cannot upgrade: stack underflow at index 0 ([\\"and\\"]) - needs 2 value(s), only 0 available", operation: :upgrade}}
  """
  @spec upgrade(Types.instruction_list()) ::
          {:ok, Types.instruction_list()} | {:error, EvaluationError.t()}
  def upgrade(instructions) when is_list(instructions), do: Upgrade.upgrade(instructions)
end
