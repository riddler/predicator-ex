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
  """

  alias Predicator.Errors.EvaluationError
  alias Predicator.Types

  # The ISA version this build emits and can run (docs/isa.md, section 1).
  @isa_version 2

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
    "and" => %{isa: 1, tier: 1},
    "or" => %{isa: 1, tier: 1},
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
    "jump_if_true_or_pop" => %{isa: 2, tier: 1}
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
  @spec opcodes() :: %{optional(String.t()) => %{isa: pos_integer(), tier: pos_integer()}}
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
      {:error, %Predicator.Errors.EvaluationError{reason: "unknown_opcode", message: "Unknown opcode: \\"nope\\"", operation: :required_isa}}
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
           "Unknown opcode: #{inspect(opcode)}",
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
end
