defmodule Predicator.Instructions do
  @moduledoc """
  Version queries over a compiled instruction list.

  The instruction set is versioned (ADR-0003): there is a current ISA version
  this build emits and can run, and any instruction list can be asked what
  version it requires. A consumer holding a stored artifact, or a sibling
  handed a list, compares the two and refuses up front rather than failing
  partway through a run.

  The opcode set and the version each opcode was introduced at are specified
  in [`docs/isa.md`](../../docs/isa.md); the table below is its executable
  form, and a test asserts the two agree.
  """

  alias Predicator.Errors.EvaluationError
  alias Predicator.Types

  # The ISA version this build emits and can run (docs/isa.md, section 1).
  @isa_version 2

  # Opcode -> the ISA version that introduced it (docs/isa.md, sections 4
  # and 7). An opcode's semantics never change under its own name (ADR-0003),
  # which is what makes a name scan a sound answer rather than a
  # best-effort one.
  @opcode_isa %{
    "lit" => 1,
    "load" => 1,
    "access" => 1,
    "compare" => 1,
    "and" => 1,
    "or" => 1,
    "not" => 1,
    "in" => 1,
    "contains" => 1,
    "add" => 1,
    "subtract" => 1,
    "multiply" => 1,
    "divide" => 1,
    "modulo" => 1,
    "unary_minus" => 1,
    "unary_bang" => 1,
    "bracket_access" => 1,
    "call" => 1,
    "object_new" => 1,
    "object_set" => 1,
    "duration" => 1,
    "relative_date" => 1,
    "make_list" => 2,
    "jump_if_falsy_or_pop" => 2,
    "jump_if_true_or_pop" => 2
  }

  @doc """
  Returns the ISA version this build emits and can run.
  """
  @spec isa_version() :: pos_integer()
  def isa_version, do: @isa_version

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
    case Map.fetch(@opcode_isa, opcode) do
      {:ok, version} ->
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
