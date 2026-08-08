defmodule Predicator.Instructions.Upgrade do
  @moduledoc false

  # Implementation module behind Predicator.Instructions.upgrade/1. Split out
  # because the rewrite is its own ~120-line algorithm against
  # instructions.ex's ~316, and keeping it here holds the public API surface
  # at exactly one function wider.
  #
  # The algorithm is a forward chunk simulation, not a backward stack walk.
  # It maintains a stack whose elements are *sub-programs* (instruction
  # lists), each one producing exactly one value when run. For an ordinary
  # opcode popping k values, the k chunks beneath it on the chunk stack are
  # concatenated in the order they were originally emitted and the
  # instruction is appended - reproducing the instruction order that
  # produced them. For a legacy `["and"]`/`["or"]`, the two chunks are
  # spliced into jump form instead of being concatenated with a trailing
  # opcode:
  #
  #   left ++ [[jump_opcode, length(right) + 1]] ++ right
  #
  # The offset is relative and forward (docs/isa.md section 2): from the
  # jump's own index it must land one past the right operand's last
  # instruction, which is exactly `length(right) + 1` once `right` is
  # spliced in directly after the jump. Nesting needs no special case: an
  # inner `and`/`or` was already rewritten into the chunk this one splices,
  # so its jump offsets are internal to that chunk and unaffected by being
  # moved as a unit.
  #
  # The final output is the concatenation of the final chunk stack in
  # bottom-to-top order, which preserves the "a deeper stack at halt is not
  # an error" rule (docs/isa.md:79-81) exactly: any chunk still on the stack
  # below the top contributes its instructions ahead of the ones above it.

  alias Predicator.Errors.EvaluationError
  alias Predicator.Instructions
  alias Predicator.Types

  # Opcode -> pop count, restricted to ISA v1 (docs/isa.md section 4's Pops
  # column). This predates jumps and make_list, so every v1 opcode's pop
  # count is either fixed or, for "call", read from its own operand - never
  # from the shape of a jump target. A pre-3.7 artifact containing a legacy
  # `and`/`or` cannot contain a v2 opcode (checked separately, below), so
  # this table never needs to answer for one.
  #
  # A test asserts `MapSet.new(Map.keys(@pops)) == Instructions.opcode_set(1)`
  # via `pops/0`, so a future v1-era opcode cannot be added to the opcode
  # table without this table noticing.
  @pops %{
    "lit" => 0,
    "load" => 0,
    "access" => 1,
    "compare" => 2,
    "and" => 2,
    "or" => 2,
    "not" => 1,
    "in" => 2,
    "contains" => 2,
    "add" => 2,
    "subtract" => 2,
    "multiply" => 2,
    "divide" => 2,
    "modulo" => 2,
    "unary_minus" => 1,
    "unary_bang" => 1,
    "bracket_access" => 2,
    "call" => :operand,
    "object_new" => 0,
    "object_set" => 2,
    "duration" => 0,
    "relative_date" => 1
  }

  @legacy_logical_opcodes MapSet.new(["and", "or"])

  @jump_opcode %{"and" => "jump_if_falsy_or_pop", "or" => "jump_if_true_or_pop"}

  @doc false
  @spec pops() :: %{String.t() => non_neg_integer() | :operand}
  def pops, do: @pops

  @doc false
  @spec upgrade(Types.instruction_list()) ::
          {:ok, Types.instruction_list()} | {:error, EvaluationError.t()}
  def upgrade(instructions) when is_list(instructions) do
    if legacy_logical?(instructions) do
      rewrite(instructions)
    else
      {:ok, instructions}
    end
  end

  @spec legacy_logical?(Types.instruction_list()) :: boolean()
  defp legacy_logical?(instructions) do
    Enum.any?(instructions, fn
      [op | _operands] when is_binary(op) -> MapSet.member?(@legacy_logical_opcodes, op)
      _instruction -> false
    end)
  end

  @spec rewrite(Types.instruction_list()) ::
          {:ok, Types.instruction_list()} | {:error, EvaluationError.t()}
  defp rewrite(instructions) do
    case find_v2_opcode(instructions) do
      {:ok, v2_opcode} ->
        {:error, mixed_versions_error(v2_opcode)}

      :none ->
        instructions
        |> Enum.with_index()
        |> Enum.reduce_while({:ok, []}, &process/2)
        |> finish()
    end
  end

  # Refusal 1: an ISA v2 opcode alongside a retired opcode. A genuine
  # pre-3.7 artifact cannot be in this state - v2 opcodes and legacy
  # and/or both shipped/stopped in 3.7.0 - so re-targeting relative jumps
  # across an unplanned insertion has no known consumer and guessing is
  # worse than refusing.
  @spec find_v2_opcode(Types.instruction_list()) :: {:ok, String.t()} | :none
  defp find_v2_opcode(instructions) do
    v2_only = MapSet.difference(Instructions.opcode_set(2), Instructions.opcode_set(1))

    Enum.find_value(instructions, :none, fn
      [op | _operands] when is_binary(op) ->
        if MapSet.member?(v2_only, op), do: {:ok, op}

      _instruction ->
        nil
    end)
  end

  @spec mixed_versions_error(String.t()) :: EvaluationError.t()
  defp mixed_versions_error(v2_opcode) do
    EvaluationError.new(
      "Cannot upgrade: list mixes ISA v2 opcode #{inspect(v2_opcode)} with a retired " <>
        "and/or opcode; a pre-3.7 artifact cannot contain both, so this list cannot " <>
        "be a genuine legacy artifact",
      "unsupported_upgrade",
      :upgrade
    )
  end

  @spec process({term(), non_neg_integer()}, {:ok, [Types.instruction_list()]}) ::
          {:cont, {:ok, [Types.instruction_list()]}}
          | {:halt, {:error, EvaluationError.t()}}
  defp process({instruction, index}, {:ok, chunk_stack}) do
    with {:ok, op, operands} <- validate_shape(instruction, index),
         {:ok, count} <- pop_count(op, operands, instruction, index),
         :ok <- check_underflow(chunk_stack, count, instruction, index) do
      {:cont, {:ok, apply_instruction(op, instruction, chunk_stack, count)}}
    else
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  # Refusal 4: a malformed element, mirroring required_isa/1's
  # "malformed_instruction" distinction.
  @spec validate_shape(term(), non_neg_integer()) ::
          {:ok, String.t(), list()} | {:error, EvaluationError.t()}
  defp validate_shape([op | operands], _index) when is_binary(op), do: {:ok, op, operands}

  defp validate_shape(bad_instruction, index) do
    {:error,
     EvaluationError.new(
       "Cannot upgrade: malformed instruction at index #{index}: #{inspect(bad_instruction)} " <>
         "is not a non-empty list headed by a binary opcode name",
       "unsupported_upgrade",
       :upgrade
     )}
  end

  # Refusal 3: an unknown opcode, or a `call` whose count operand is not a
  # non-negative integer.
  @spec pop_count(String.t(), list(), term(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, EvaluationError.t()}
  defp pop_count("call", [_name, count], _instruction, _index)
       when is_integer(count) and count >= 0 do
    {:ok, count}
  end

  defp pop_count("call", _operands, instruction, index) do
    {:error,
     EvaluationError.new(
       "Cannot upgrade: \"call\"'s argument-count operand is not a non-negative " <>
         "integer at index #{index}: #{inspect(instruction)}",
       "unsupported_upgrade",
       :upgrade
     )}
  end

  defp pop_count(op, _operands, instruction, index) do
    case Map.fetch(@pops, op) do
      {:ok, count} ->
        {:ok, count}

      :error ->
        {:error,
         EvaluationError.new(
           "Cannot upgrade: unknown opcode #{inspect(op)} at index #{index}: " <>
             "#{inspect(instruction)}",
           "unsupported_upgrade",
           :upgrade
         )}
    end
  end

  # Refusal 2: stack underflow - an opcode pops more chunks than the chunk
  # stack holds. The list was already unrunnable; say so rather than
  # producing a silently different list.
  @spec check_underflow([Types.instruction_list()], non_neg_integer(), term(), non_neg_integer()) ::
          :ok | {:error, EvaluationError.t()}
  defp check_underflow(chunk_stack, count, instruction, index) do
    available = length(chunk_stack)

    if available < count do
      {:error,
       EvaluationError.new(
         "Cannot upgrade: stack underflow at index #{index} (#{inspect(instruction)}) - " <>
           "needs #{count} value(s), only #{available} available",
         "unsupported_upgrade",
         :upgrade
       )}
    else
      :ok
    end
  end

  @spec apply_instruction(String.t(), term(), [Types.instruction_list()], non_neg_integer()) ::
          [Types.instruction_list()]
  defp apply_instruction(op, _instruction, chunk_stack, 2) when op in ["and", "or"] do
    [right, left | rest] = chunk_stack
    jump_opcode = Map.fetch!(@jump_opcode, op)
    new_chunk = left ++ [[jump_opcode, length(right) + 1]] ++ right
    [new_chunk | rest]
  end

  defp apply_instruction(_op, instruction, chunk_stack, count) do
    {popped, rest} = Enum.split(chunk_stack, count)
    new_chunk = popped |> Enum.reverse() |> Enum.concat() |> Kernel.++([instruction])
    [new_chunk | rest]
  end

  @spec finish({:ok, [Types.instruction_list()]} | {:error, EvaluationError.t()}) ::
          {:ok, Types.instruction_list()} | {:error, EvaluationError.t()}
  defp finish({:ok, chunk_stack}) do
    {:ok, chunk_stack |> Enum.reverse() |> Enum.concat()}
  end

  defp finish({:error, _reason} = error), do: error
end
