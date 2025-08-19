defmodule Predicator.Evaluator do
  @moduledoc """
  Stack-based evaluator for predicator instructions.

  The evaluator executes a list of instructions using a stack machine approach.
  Instructions operate on a stack, with the most recent values at the top (head of list).
  """

  alias Predicator.Types

  @typedoc "Internal evaluator state"
  @type t :: %__MODULE__{
          instructions: Types.instruction_list(),
          instruction_pointer: non_neg_integer(),
          stack: [Types.value()],
          context: Types.context(),
          halted: boolean()
        }

  defstruct [
    :instructions,
    instruction_pointer: 0,
    stack: [],
    context: %{},
    halted: false
  ]

  @doc """
  Evaluates a list of instructions with the given context.

  Returns the top value on the stack when evaluation completes,
  or an error if something goes wrong.

  ## Examples

      iex> Predicator.Evaluator.evaluate([["lit", 42]], %{})
      42

      iex> Predicator.Evaluator.evaluate([["load", "score"]], %{"score" => 85})
      85

      iex> Predicator.Evaluator.evaluate([["load", "missing"]], %{})
      :undefined
  """
  @spec evaluate(Types.instruction_list(), Types.context()) :: Types.result()
  def evaluate(instructions, context \\ %{}) when is_list(instructions) and is_map(context) do
    evaluator = %__MODULE__{
      instructions: instructions,
      context: context
    }

    case run(evaluator) do
      {:ok, %__MODULE__{stack: [result | _rest]}} ->
        result

      {:ok, %__MODULE__{stack: []}} ->
        {:error, "Evaluation completed with empty stack"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Runs the evaluator until it halts or encounters an error.

  Returns `{:ok, final_state}` on success or `{:error, reason}` on failure.
  """
  @spec run(t()) :: {:ok, t()} | {:error, term()}
  def run(%__MODULE__{halted: true} = evaluator), do: {:ok, evaluator}

  def run(%__MODULE__{} = evaluator) do
    case step(evaluator) do
      {:ok, new_evaluator} -> run(new_evaluator)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Executes a single instruction step.

  Returns the updated evaluator state or an error.
  """
  @spec step(t()) :: {:ok, t()} | {:error, term()}
  def step(%__MODULE__{} = evaluator) do
    if finished?(evaluator) do
      {:ok, halt(evaluator)}
    else
      case fetch_current_instruction(evaluator) do
        {:ok, instruction} ->
          evaluator
          |> execute_instruction(instruction)
          |> advance_instruction_pointer()

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Private functions

  @spec finished?(t()) :: boolean()
  defp finished?(%__MODULE__{instruction_pointer: ip, instructions: instructions}) do
    ip >= length(instructions)
  end

  @spec halt(t()) :: t()
  defp halt(%__MODULE__{} = evaluator) do
    %__MODULE__{evaluator | halted: true}
  end

  @spec fetch_current_instruction(t()) :: {:ok, Types.instruction()} | {:error, term()}
  defp fetch_current_instruction(%__MODULE__{instruction_pointer: ip, instructions: instructions}) do
    case Enum.at(instructions, ip) do
      nil -> {:error, "Invalid instruction pointer: #{ip}"}
      instruction -> {:ok, instruction}
    end
  end

  @spec execute_instruction(t(), Types.instruction()) :: {:ok, t()} | {:error, term()}
  defp execute_instruction(%__MODULE__{} = evaluator, instruction) do
    case instruction do
      ["lit", value] ->
        {:ok, push_stack(evaluator, value)}

      ["load", variable_name] when is_binary(variable_name) ->
        value = load_from_context(evaluator.context, variable_name)
        {:ok, push_stack(evaluator, value)}

      unknown ->
        {:error, "Unknown instruction: #{inspect(unknown)}"}
    end
  end

  @spec advance_instruction_pointer({:ok, t()} | {:error, term()}) ::
          {:ok, t()} | {:error, term()}
  defp advance_instruction_pointer({:ok, %__MODULE__{} = evaluator}) do
    {:ok, %__MODULE__{evaluator | instruction_pointer: evaluator.instruction_pointer + 1}}
  end

  defp advance_instruction_pointer({:error, reason}), do: {:error, reason}

  @spec push_stack(t(), Types.value()) :: t()
  defp push_stack(%__MODULE__{stack: stack} = evaluator, value) do
    %__MODULE__{evaluator | stack: [value | stack]}
  end

  @spec load_from_context(Types.context(), binary()) :: Types.value()
  defp load_from_context(context, variable_name)
       when is_map(context) and is_binary(variable_name) do
    # Try string key first, then atom key
    case Map.get(context, variable_name) do
      nil ->
        # Try as atom key if string key doesn't exist
        atom_key = String.to_existing_atom(variable_name)
        Map.get(context, atom_key, :undefined)

      value ->
        value
    end
  rescue
    ArgumentError ->
      # String.to_existing_atom failed, variable doesn't exist
      :undefined
  end
end
