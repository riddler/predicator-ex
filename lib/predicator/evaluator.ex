defmodule Predicator.Evaluator do
  @moduledoc """
  Stack-based evaluator for predicator instructions.

  The evaluator executes a list of instructions using a stack machine approach.
  Instructions operate on a stack, with the most recent values at the top (head of list).

  Supported instruction types:
  - `["lit", value]` - Push literal value onto stack
  - `["load", variable_name]` - Load variable from context onto stack  
  - `["compare", operator]` - Compare top two stack values with operator
  - `["and"]` - Logical AND of top two boolean values
  - `["or"]` - Logical OR of top two boolean values
  - `["not"]` - Logical NOT of top boolean value
  - `["in"]` - Membership test (element in collection)
  - `["contains"]` - Membership test (collection contains element)
  - `["call", function_name, arg_count]` - Call function with arguments from stack
  """

  alias Predicator.Functions.Registry
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
  @spec evaluate(Types.instruction_list(), Types.context()) :: Types.internal_result()
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
  Evaluates a list of instructions with the given context, raising on errors.

  Similar to `evaluate/2` but raises an exception for error results instead
  of returning error tuples. Follows the Elixir convention of bang functions.

  ## Examples

      iex> Predicator.Evaluator.evaluate!([["lit", 42]], %{})
      42

      iex> Predicator.Evaluator.evaluate!([["load", "score"]], %{"score" => 85})
      85

      # This would raise an exception:
      # Predicator.Evaluator.evaluate!([["unknown_op"]], %{})
  """
  @spec evaluate!(Types.instruction_list(), Types.context()) :: Types.value()
  def evaluate!(instructions, context \\ %{}) when is_list(instructions) and is_map(context) do
    case evaluate(instructions, context) do
      {:error, reason} -> raise "Evaluation failed: #{reason}"
      result -> result
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
  # Literal value instruction
  defp execute_instruction(%__MODULE__{} = evaluator, ["lit", value]) do
    {:ok, push_stack(evaluator, value)}
  end

  # Load variable from context instruction
  defp execute_instruction(%__MODULE__{} = evaluator, ["load", variable_name])
       when is_binary(variable_name) do
    value = load_from_context(evaluator.context, variable_name)
    {:ok, push_stack(evaluator, value)}
  end

  # Comparison instruction
  defp execute_instruction(%__MODULE__{} = evaluator, ["compare", operator])
       when operator in ["GT", "LT", "EQ", "GTE", "LTE", "NE"] do
    execute_compare(evaluator, operator)
  end

  # Logical AND instruction
  defp execute_instruction(%__MODULE__{} = evaluator, ["and"]) do
    execute_logical_and(evaluator)
  end

  # Logical OR instruction
  defp execute_instruction(%__MODULE__{} = evaluator, ["or"]) do
    execute_logical_or(evaluator)
  end

  # Logical NOT instruction
  defp execute_instruction(%__MODULE__{} = evaluator, ["not"]) do
    execute_logical_not(evaluator)
  end

  # Membership IN instruction
  defp execute_instruction(%__MODULE__{} = evaluator, ["in"]) do
    execute_membership(evaluator, :in)
  end

  # Membership CONTAINS instruction
  defp execute_instruction(%__MODULE__{} = evaluator, ["contains"]) do
    execute_membership(evaluator, :contains)
  end

  # Function call instruction
  defp execute_instruction(%__MODULE__{} = evaluator, ["call", function_name, arg_count])
       when is_binary(function_name) and is_integer(arg_count) and arg_count >= 0 do
    execute_function_call(evaluator, function_name, arg_count)
  end

  # Unknown instruction - catch-all clause
  defp execute_instruction(%__MODULE__{}, unknown) do
    {:error, "Unknown instruction: #{inspect(unknown)}"}
  end

  @spec advance_instruction_pointer({:ok, t()} | {:error, term()}) ::
          {:ok, t()} | {:error, term()}
  defp advance_instruction_pointer({:ok, %__MODULE__{} = evaluator}) do
    {:ok, %__MODULE__{evaluator | instruction_pointer: evaluator.instruction_pointer + 1}}
  end

  defp advance_instruction_pointer({:error, reason}), do: {:error, reason}

  @spec execute_compare(t(), binary()) :: {:ok, t()} | {:error, term()}
  defp execute_compare(%__MODULE__{stack: [right | [left | rest]]} = evaluator, operator) do
    result = compare_values(left, right, operator)
    {:ok, %__MODULE__{evaluator | stack: [result | rest]}}
  end

  defp execute_compare(%__MODULE__{stack: stack}, _operator) do
    {:error, "Comparison requires two values on stack, got: #{length(stack)}"}
  end

  # Custom guard for type matching
  defguard types_match(a, b)
           when (is_integer(a) and is_integer(b)) or
                  (is_boolean(a) and is_boolean(b)) or
                  (is_binary(a) and is_binary(b)) or
                  (is_list(a) and is_list(b)) or
                  (is_struct(a, Date) and is_struct(b, Date)) or
                  (is_struct(a, DateTime) and is_struct(b, DateTime))

  @spec compare_values(Types.value(), Types.value(), binary()) :: Types.value()
  defp compare_values(:undefined, _right, _operator), do: :undefined
  defp compare_values(_left, :undefined, _operator), do: :undefined

  defp compare_values(left, right, operator) when types_match(left, right) do
    case operator do
      "GT" -> left > right
      "LT" -> left < right
      "EQ" -> left == right
      "GTE" -> left >= right
      "LTE" -> left <= right
      "NE" -> left != right
    end
  end

  defp compare_values(_left, _right, _operator), do: :undefined

  @spec values_equal?(Types.value(), Types.value()) :: boolean()
  defp values_equal?(:undefined, _value), do: false
  defp values_equal?(_value, :undefined), do: false
  defp values_equal?(left, right) when types_match(left, right), do: left == right
  defp values_equal?(_left, _right), do: false

  @spec push_stack(t(), Types.value()) :: t()
  defp push_stack(%__MODULE__{stack: stack} = evaluator, value) do
    %__MODULE__{evaluator | stack: [value | stack]}
  end

  @spec execute_logical_and(t()) :: {:ok, t()} | {:error, term()}
  defp execute_logical_and(%__MODULE__{stack: [right | [left | rest]]} = evaluator)
       when is_boolean(left) and is_boolean(right) do
    result = left and right
    {:ok, %__MODULE__{evaluator | stack: [result | rest]}}
  end

  defp execute_logical_and(%__MODULE__{stack: [right | [left | _rest]]}) do
    {:error,
     "Logical AND requires two boolean values, got: #{inspect(left)} and #{inspect(right)}"}
  end

  defp execute_logical_and(%__MODULE__{stack: stack}) do
    {:error, "Logical AND requires two values on stack, got: #{length(stack)}"}
  end

  @spec execute_logical_or(t()) :: {:ok, t()} | {:error, term()}
  defp execute_logical_or(%__MODULE__{stack: [right | [left | rest]]} = evaluator)
       when is_boolean(left) and is_boolean(right) do
    result = left or right
    {:ok, %__MODULE__{evaluator | stack: [result | rest]}}
  end

  defp execute_logical_or(%__MODULE__{stack: [right | [left | _rest]]}) do
    {:error,
     "Logical OR requires two boolean values, got: #{inspect(left)} and #{inspect(right)}"}
  end

  defp execute_logical_or(%__MODULE__{stack: stack}) do
    {:error, "Logical OR requires two values on stack, got: #{length(stack)}"}
  end

  @spec execute_logical_not(t()) :: {:ok, t()} | {:error, term()}
  defp execute_logical_not(%__MODULE__{stack: [value | rest]} = evaluator)
       when is_boolean(value) do
    result = not value
    {:ok, %__MODULE__{evaluator | stack: [result | rest]}}
  end

  defp execute_logical_not(%__MODULE__{stack: [value | _rest]}) do
    {:error, "Logical NOT requires a boolean value, got: #{inspect(value)}"}
  end

  defp execute_logical_not(%__MODULE__{stack: []}) do
    {:error, "Logical NOT requires one value on stack, got: 0"}
  end

  @spec execute_membership(t(), :in | :contains) :: {:ok, t()} | {:error, term()}
  defp execute_membership(%__MODULE__{stack: [right | [left | rest]]} = evaluator, :in) do
    # left IN right - check if left is a member of right (list)
    case {left, right} do
      {:undefined, _value} ->
        {:ok, %__MODULE__{evaluator | stack: [:undefined | rest]}}

      {_value, :undefined} ->
        {:ok, %__MODULE__{evaluator | stack: [:undefined | rest]}}

      {_value, list} when is_list(list) ->
        result = Enum.any?(list, fn item -> values_equal?(left, item) end)
        {:ok, %__MODULE__{evaluator | stack: [result | rest]}}

      {_value, non_list} ->
        {:error, "IN operator requires a list on the right side, got: #{inspect(non_list)}"}
    end
  end

  defp execute_membership(%__MODULE__{stack: [right | [left | rest]]} = evaluator, :contains) do
    # left CONTAINS right - check if left (list) contains right (value)
    case {left, right} do
      {:undefined, _value} ->
        {:ok, %__MODULE__{evaluator | stack: [:undefined | rest]}}

      {_value, :undefined} ->
        {:ok, %__MODULE__{evaluator | stack: [:undefined | rest]}}

      {list, _value} when is_list(list) ->
        result = Enum.any?(list, fn item -> values_equal?(item, right) end)
        {:ok, %__MODULE__{evaluator | stack: [result | rest]}}

      {non_list, _value} ->
        {:error, "CONTAINS operator requires a list on the left side, got: #{inspect(non_list)}"}
    end
  end

  defp execute_membership(%__MODULE__{stack: stack}, operation) do
    {:error,
     "#{String.upcase(to_string(operation))} requires two values on stack, got: #{length(stack)}"}
  end

  @spec execute_function_call(t(), binary(), non_neg_integer()) :: {:ok, t()} | {:error, term()}
  defp execute_function_call(%__MODULE__{stack: stack} = evaluator, function_name, arg_count) do
    if length(stack) >= arg_count do
      # Extract arguments from stack (they're in reverse order)
      {args, remaining_stack} = Enum.split(stack, arg_count)
      # Reverse args to get correct order (stack is LIFO)
      function_args = Enum.reverse(args)

      case Registry.call(function_name, function_args, evaluator.context) do
        {:ok, result} ->
          {:ok, %__MODULE__{evaluator | stack: [result | remaining_stack]}}

        {:error, message} ->
          {:error, message}
      end
    else
      {:error,
       "Function #{function_name}() expects #{arg_count} arguments, but only #{length(stack)} values on stack"}
    end
  end

  @spec load_from_context(Types.context(), binary()) :: Types.value()
  defp load_from_context(context, variable_name)
       when is_map(context) and is_binary(variable_name) do
    # Check if this is a dotted path (nested access)
    if String.contains?(variable_name, ".") do
      load_nested_value(context, String.split(variable_name, "."))
    else
      # Try string key first, then atom key
      case Map.get(context, variable_name) do
        nil ->
          # Try as atom key if string key doesn't exist
          atom_key = String.to_existing_atom(variable_name)
          Map.get(context, atom_key, :undefined)

        value ->
          value
      end
    end
  rescue
    ArgumentError ->
      # String.to_existing_atom failed, variable doesn't exist
      :undefined
  end

  # Helper function to traverse nested data structures using dot notation
  @spec load_nested_value(map() | Types.value(), [binary()]) :: Types.value()
  defp load_nested_value(_value, []), do: :undefined
  defp load_nested_value(value, [_key | _rest]) when not is_map(value), do: :undefined

  defp load_nested_value(value, [key]) when is_map(value) do
    # Final key, return the value
    case Map.get(value, key) do
      nil ->
        # Try as atom key if string key doesn't exist
        try do
          atom_key = String.to_existing_atom(key)
          Map.get(value, atom_key, :undefined)
        rescue
          ArgumentError ->
            :undefined
        end

      result ->
        result
    end
  end

  defp load_nested_value(value, [key | rest_keys]) when is_map(value) do
    # Get the next nested value and continue traversing
    next_value =
      case Map.get(value, key) do
        nil ->
          # Try as atom key if string key doesn't exist
          try do
            atom_key = String.to_existing_atom(key)
            Map.get(value, atom_key)
          rescue
            ArgumentError ->
              nil
          end

        result ->
          result
      end

    case next_value do
      nil -> :undefined
      nested_value -> load_nested_value(nested_value, rest_keys)
    end
  end
end
