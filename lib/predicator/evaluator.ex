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
  - `["add"]` - Add top two integer values
  - `["subtract"]` - Subtract top two integer values
  - `["multiply"]` - Multiply top two integer values
  - `["divide"]` - Divide top two integer values (integer division)
  - `["modulo"]` - Modulo operation on top two integer values
  - `["unary_minus"]` - Negate top integer value
  - `["unary_bang"]` - Logical NOT of top boolean value
  - `["bracket_access"]` - Pop key and object, push object[key] result
  - `["call", function_name, arg_count]` - Call function with arguments from stack
  """

  alias Predicator.Functions.{JSONFunctions, MathFunctions, SystemFunctions}
  alias Predicator.Types
  alias Predicator.Errors.{EvaluationError, TypeMismatchError}

  @typedoc "Internal evaluator state"
  @type t :: %__MODULE__{
          instructions: Types.instruction_list(),
          instruction_pointer: non_neg_integer(),
          stack: [Types.value()],
          context: Types.context(),
          functions: %{binary() => {non_neg_integer(), function()}},
          halted: boolean()
        }

  defstruct [
    :instructions,
    instruction_pointer: 0,
    stack: [],
    context: %{},
    functions: %{},
    halted: false
  ]

  @doc """
  Evaluates a list of instructions with the given context and options.

  Returns the top value on the stack when evaluation completes,
  or an error if something goes wrong.

  ## Parameters

  - `instructions` - List of instructions to execute
  - `context` - Context map with variable bindings (default: `%{}`)
  - `opts` - Options keyword list:
    - `:functions` - Map of custom functions `%{name => {arity, function}}`

  ## Examples

      iex> Predicator.Evaluator.evaluate([["lit", 42]], %{})
      42

      iex> Predicator.Evaluator.evaluate([["load", "score"]], %{"score" => 85})
      85

      # With custom functions
      iex> custom_functions = %{"double" => {1, fn [n], _context -> {:ok, n * 2} end}}
      iex> instructions = [["lit", 21], ["call", "double", 1]]
      iex> Predicator.Evaluator.evaluate(instructions, %{}, functions: custom_functions)
      42
  """
  @spec evaluate(Types.instruction_list(), Types.context(), keyword()) :: Types.internal_result()
  def evaluate(instructions, context \\ %{}, opts \\ [])
      when is_list(instructions) and is_map(context) do
    # Merge custom functions with system functions
    merged_functions =
      SystemFunctions.all_functions()
      |> Map.merge(JSONFunctions.all_functions())
      |> Map.merge(MathFunctions.all_functions())
      |> Map.merge(Keyword.get(opts, :functions, %{}))

    evaluator = %__MODULE__{
      instructions: instructions,
      context: context,
      functions: merged_functions
    }

    case run(evaluator) do
      {:ok, %__MODULE__{stack: [result | _rest]}} ->
        result

      {:ok, %__MODULE__{stack: []}} ->
        {:error,
         EvaluationError.new(
           "Evaluation completed with empty stack",
           "empty_stack",
           :evaluate
         )}

      {:error, error_struct} when is_struct(error_struct) ->
        {:error, error_struct}
    end
  end

  @doc """
  Evaluates a list of instructions with the given context and options, raising on errors.

  Similar to `evaluate/3` but raises an exception for error results instead
  of returning error tuples. Follows the Elixir convention of bang functions.

  ## Examples

      iex> Predicator.Evaluator.evaluate!([["lit", 42]], %{})
      42

      iex> Predicator.Evaluator.evaluate!([["load", "score"]], %{"score" => 85})
      85

      # With custom functions
      iex> custom_functions = %{"double" => {1, fn [n], _context -> {:ok, n * 2} end}}
      iex> instructions = [["lit", 21], ["call", "double", 1]]
      iex> Predicator.Evaluator.evaluate!(instructions, %{}, functions: custom_functions)
      42
  """
  @spec evaluate!(Types.instruction_list(), Types.context(), keyword()) :: Types.value()
  def evaluate!(instructions, context \\ %{}, opts \\ [])
      when is_list(instructions) and is_map(context) do
    case evaluate(instructions, context, opts) do
      {:error, %{message: message}} ->
        raise "Evaluation failed: #{message}"

      result ->
        result
    end
  end

  @doc """
  Runs the evaluator until it halts or encounters an error.

  Returns `{:ok, final_state}` on success or `{:error, reason}` on failure.
  """
  @spec run(t()) :: {:ok, t()} | {:error, struct()}
  def run(%__MODULE__{halted: true} = evaluator), do: {:ok, evaluator}

  def run(%__MODULE__{} = evaluator) do
    case step(evaluator) do
      {:ok, new_evaluator} -> run(new_evaluator)
      {:error, error_struct} when is_struct(error_struct) -> {:error, error_struct}
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
      nil ->
        {:error,
         EvaluationError.new(
           "Invalid instruction pointer: #{ip}",
           "invalid_instruction_pointer",
           :evaluate
         )}

      instruction ->
        {:ok, instruction}
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

  # Property access instruction
  defp execute_instruction(%__MODULE__{} = evaluator, ["access", property])
       when is_binary(property) do
    execute_access(evaluator, property)
  end

  # Comparison instruction
  defp execute_instruction(%__MODULE__{} = evaluator, ["compare", operator])
       when operator in ["GT", "LT", "EQ", "GTE", "LTE", "NE", "STRICT_EQ", "STRICT_NE"] do
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

  # Arithmetic instructions
  defp execute_instruction(%__MODULE__{} = evaluator, ["add"]) do
    execute_arithmetic(evaluator, :add)
  end

  defp execute_instruction(%__MODULE__{} = evaluator, ["subtract"]) do
    execute_arithmetic(evaluator, :subtract)
  end

  defp execute_instruction(%__MODULE__{} = evaluator, ["multiply"]) do
    execute_arithmetic(evaluator, :multiply)
  end

  defp execute_instruction(%__MODULE__{} = evaluator, ["divide"]) do
    execute_arithmetic(evaluator, :divide)
  end

  defp execute_instruction(%__MODULE__{} = evaluator, ["modulo"]) do
    execute_arithmetic(evaluator, :modulo)
  end

  # Unary instructions
  defp execute_instruction(%__MODULE__{} = evaluator, ["unary_minus"]) do
    execute_unary(evaluator, :minus)
  end

  defp execute_instruction(%__MODULE__{} = evaluator, ["unary_bang"]) do
    execute_unary(evaluator, :bang)
  end

  # Bracket access instruction
  defp execute_instruction(%__MODULE__{} = evaluator, ["bracket_access"]) do
    execute_bracket_access(evaluator)
  end

  # Function call instruction
  defp execute_instruction(%__MODULE__{} = evaluator, ["call", function_name, arg_count])
       when is_binary(function_name) and is_integer(arg_count) and arg_count >= 0 do
    execute_function_call(evaluator, function_name, arg_count)
  end

  # Object creation instruction
  defp execute_instruction(%__MODULE__{} = evaluator, ["object_new"]) do
    execute_object_new(evaluator)
  end

  # Object property set instruction
  defp execute_instruction(%__MODULE__{} = evaluator, ["object_set", key])
       when is_binary(key) do
    execute_object_set(evaluator, key)
  end

  # Unknown instruction - catch-all clause
  defp execute_instruction(%__MODULE__{}, unknown) do
    {:error,
     EvaluationError.new(
       "Unknown instruction: #{inspect(unknown)}",
       "unknown_instruction",
       :evaluate
     )}
  end

  @spec advance_instruction_pointer({:ok, t()} | {:error, struct()}) ::
          {:ok, t()} | {:error, struct()}
  defp advance_instruction_pointer({:ok, %__MODULE__{} = evaluator}) do
    {:ok, %__MODULE__{evaluator | instruction_pointer: evaluator.instruction_pointer + 1}}
  end

  defp advance_instruction_pointer({:error, error_struct}) when is_struct(error_struct),
    do: {:error, error_struct}

  @spec execute_compare(t(), binary()) :: {:ok, t()} | {:error, term()}
  defp execute_compare(%__MODULE__{stack: [right | [left | rest]]} = evaluator, operator) do
    result = compare_values(left, right, operator)
    {:ok, %__MODULE__{evaluator | stack: [result | rest]}}
  end

  defp execute_compare(%__MODULE__{stack: stack}, _operator) do
    {:error, EvaluationError.insufficient_operands(:comparison, length(stack), 2)}
  end

  # Execute property access: pop object from stack, access property, push result
  defp execute_access(%__MODULE__{stack: [object | rest]} = evaluator, property) do
    case access_value(object, property) do
      {:ok, value} ->
        {:ok, %__MODULE__{evaluator | stack: [value | rest]}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_access(%__MODULE__{stack: stack}, _property) do
    {:error, EvaluationError.insufficient_operands(:access, length(stack), 1)}
  end

  # Custom guard for type matching
  defguard types_match(a, b)
           when (is_number(a) and is_number(b)) or
                  (is_boolean(a) and is_boolean(b)) or
                  (is_binary(a) and is_binary(b)) or
                  (is_list(a) and is_list(b)) or
                  (is_struct(a, Date) and is_struct(b, Date)) or
                  (is_struct(a, DateTime) and is_struct(b, DateTime)) or
                  (is_map(a) and is_map(b) and not is_struct(a) and not is_struct(b))

  @spec compare_values(Types.value(), Types.value(), binary()) :: Types.value()
  # Handle undefined values for non-strict operators
  defp compare_values(:undefined, _right, operator)
       when operator not in ["STRICT_EQ", "STRICT_NE"],
       do: :undefined

  defp compare_values(_left, :undefined, operator)
       when operator not in ["STRICT_EQ", "STRICT_NE"],
       do: :undefined

  # Strict equality works on all types, including :undefined
  defp compare_values(left, right, "STRICT_EQ"), do: left === right
  defp compare_values(left, right, "STRICT_NE"), do: left !== right

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
    left_type = get_value_type(left)
    right_type = get_value_type(right)

    {:error,
     TypeMismatchError.binary(
       :logical_and,
       :boolean,
       {left_type, right_type},
       {left, right}
     )}
  end

  defp execute_logical_and(%__MODULE__{stack: stack}) do
    {:error, EvaluationError.insufficient_operands(:logical_and, length(stack), 2)}
  end

  @spec execute_logical_or(t()) :: {:ok, t()} | {:error, term()}
  defp execute_logical_or(%__MODULE__{stack: [right | [left | rest]]} = evaluator)
       when is_boolean(left) and is_boolean(right) do
    result = left or right
    {:ok, %__MODULE__{evaluator | stack: [result | rest]}}
  end

  defp execute_logical_or(%__MODULE__{stack: [right | [left | _rest]]}) do
    left_type = get_value_type(left)
    right_type = get_value_type(right)

    {:error,
     TypeMismatchError.binary(
       :logical_or,
       :boolean,
       {left_type, right_type},
       {left, right}
     )}
  end

  defp execute_logical_or(%__MODULE__{stack: stack}) do
    {:error, EvaluationError.insufficient_operands(:logical_or, length(stack), 2)}
  end

  @spec execute_logical_not(t()) :: {:ok, t()} | {:error, term()}
  defp execute_logical_not(%__MODULE__{stack: [value | rest]} = evaluator)
       when is_boolean(value) do
    result = not value
    {:ok, %__MODULE__{evaluator | stack: [result | rest]}}
  end

  defp execute_logical_not(%__MODULE__{stack: [value | _rest]}) do
    got_type = get_value_type(value)
    {:error, TypeMismatchError.unary(:logical_not, :boolean, got_type, value)}
  end

  defp execute_logical_not(%__MODULE__{stack: []}) do
    {:error, EvaluationError.insufficient_operands(:logical_not, 0, 1)}
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
        {:error, TypeMismatchError.unary(:in, :list, get_value_type(non_list), non_list)}
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
        {:error,
         TypeMismatchError.unary(
           :contains,
           :list,
           get_value_type(non_list),
           non_list
         )}
    end
  end

  defp execute_membership(%__MODULE__{stack: stack}, operation) do
    {:error, EvaluationError.insufficient_operands(operation, length(stack), 2)}
  end

  @spec execute_arithmetic(t(), :add | :subtract | :multiply | :divide | :modulo) ::
          {:ok, t()} | {:error, term()}
  # Addition with type coercion
  defp execute_arithmetic(%__MODULE__{stack: [right | [left | rest]]} = evaluator, :add) do
    result = apply_addition(left, right)

    case result do
      {:ok, value} ->
        {:ok, %__MODULE__{evaluator | stack: [value | rest]}}

      {:error, _error} = error_result ->
        error_result
    end
  end

  # Subtraction - numeric only
  defp execute_arithmetic(%__MODULE__{stack: [right | [left | rest]]} = evaluator, :subtract)
       when is_number(left) and is_number(right) do
    {:ok, %__MODULE__{evaluator | stack: [left - right | rest]}}
  end

  # Multiplication - numeric only
  defp execute_arithmetic(%__MODULE__{stack: [right | [left | rest]]} = evaluator, :multiply)
       when is_number(left) and is_number(right) do
    {:ok, %__MODULE__{evaluator | stack: [left * right | rest]}}
  end

  # Division by zero check for integers
  defp execute_arithmetic(%__MODULE__{stack: [0 | [_left | _rest]]}, :divide) do
    {:error, EvaluationError.new("Division by zero", "division_by_zero", :divide)}
  end

  # Division by zero check for floats
  defp execute_arithmetic(%__MODULE__{stack: [right | [_left | _rest]]}, :divide)
       when is_float(right) and right == 0.0 do
    {:error, EvaluationError.new("Division by zero", "division_by_zero", :divide)}
  end

  # Division - numeric only
  defp execute_arithmetic(%__MODULE__{stack: [right | [left | rest]]} = evaluator, :divide)
       when is_number(left) and is_number(right) do
    result =
      if is_integer(left) and is_integer(right) do
        div(left, right)
      else
        left / right
      end

    {:ok, %__MODULE__{evaluator | stack: [result | rest]}}
  end

  # Modulo by zero check
  defp execute_arithmetic(%__MODULE__{stack: [0 | [_left | _rest]]}, :modulo) do
    {:error, EvaluationError.new("Modulo by zero", "modulo_by_zero", :modulo)}
  end

  # Modulo - integers only (rem doesn't work well with floats)
  defp execute_arithmetic(%__MODULE__{stack: [right | [left | rest]]} = evaluator, :modulo)
       when is_integer(left) and is_integer(right) do
    {:ok, %__MODULE__{evaluator | stack: [rem(left, right) | rest]}}
  end

  # Type mismatch for non-addition operations
  defp execute_arithmetic(%__MODULE__{stack: [right | [left | _rest]]}, operation)
       when operation != :add do
    left_type = get_value_type(left)
    right_type = get_value_type(right)

    {:error,
     TypeMismatchError.binary(
       operation,
       :number,
       {left_type, right_type},
       {left, right}
     )}
  end

  defp execute_arithmetic(%__MODULE__{stack: stack}, operation) do
    {:error, EvaluationError.insufficient_operands(operation, length(stack), 2)}
  end

  # Helper function for addition with type coercion
  defp apply_addition(left, right) when is_number(left) and is_number(right) do
    {:ok, left + right}
  end

  defp apply_addition(left, right) when is_binary(left) and is_binary(right) do
    {:ok, left <> right}
  end

  defp apply_addition(left, right) when is_binary(left) and is_number(right) do
    {:ok, left <> to_string(right)}
  end

  defp apply_addition(left, right) when is_number(left) and is_binary(right) do
    {:ok, to_string(left) <> right}
  end

  defp apply_addition(left, right) do
    left_type = get_value_type(left)
    right_type = get_value_type(right)

    {:error,
     TypeMismatchError.binary(
       :add,
       :number_or_string,
       {left_type, right_type},
       {left, right}
     )}
  end

  # Helper function to get the type of a value for error reporting
  defp get_value_type(value) when is_integer(value), do: :integer
  defp get_value_type(value) when is_float(value), do: :float
  defp get_value_type(value) when is_boolean(value), do: :boolean
  defp get_value_type(value) when is_binary(value), do: :string
  defp get_value_type(value) when is_list(value), do: :list
  defp get_value_type(%Date{}), do: :date
  defp get_value_type(%DateTime{}), do: :datetime
  defp get_value_type(:undefined), do: :undefined
  defp get_value_type(_other), do: :unknown

  @spec execute_unary(t(), :minus | :bang) :: {:ok, t()} | {:error, term()}
  defp execute_unary(%__MODULE__{stack: [value | rest]} = evaluator, :minus)
       when is_number(value) do
    result = -value
    {:ok, %__MODULE__{evaluator | stack: [result | rest]}}
  end

  defp execute_unary(%__MODULE__{stack: [value | rest]} = evaluator, :bang)
       when is_boolean(value) do
    result = not value
    {:ok, %__MODULE__{evaluator | stack: [result | rest]}}
  end

  defp execute_unary(%__MODULE__{stack: [value | _rest]}, :minus) do
    got_type = get_value_type(value)
    {:error, TypeMismatchError.unary(:unary_minus, :number, got_type, value)}
  end

  defp execute_unary(%__MODULE__{stack: [value | _rest]}, :bang) do
    got_type = get_value_type(value)
    {:error, TypeMismatchError.unary(:unary_bang, :boolean, got_type, value)}
  end

  defp execute_unary(%__MODULE__{stack: []}, operation) do
    {:error, EvaluationError.insufficient_operands(:"unary_#{operation}", 0, 1)}
  end

  # Bracket access operations - access object[key] or array[index]
  @spec execute_bracket_access(t()) :: {:ok, t()} | {:error, term()}
  defp execute_bracket_access(%__MODULE__{stack: [key, object | rest]} = evaluator) do
    case access_value(object, key) do
      {:ok, value} ->
        {:ok, %__MODULE__{evaluator | stack: [value | rest]}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_bracket_access(%__MODULE__{stack: stack}) when length(stack) < 2 do
    {:error, EvaluationError.insufficient_operands(:bracket_access, length(stack), 2)}
  end

  # Access a value from an object or array using a key or index
  @spec access_value(Types.value(), Types.value()) :: {:ok, Types.value()} | {:error, term()}
  defp access_value(object, key) when is_map(object) and is_binary(key) do
    # Map access with string key
    case Map.get(object, key) do
      nil ->
        # Try as atom key if string key doesn't exist
        try do
          atom_key = String.to_existing_atom(key)
          {:ok, Map.get(object, atom_key, :undefined)}
        rescue
          ArgumentError ->
            {:ok, :undefined}
        end

      value ->
        {:ok, value}
    end
  end

  defp access_value(object, key) when is_map(object) and is_atom(key) do
    # Map access with atom key
    {:ok, Map.get(object, key, :undefined)}
  end

  defp access_value(object, key) when is_map(object) and is_integer(key) do
    # Map access with integer key (maps can have integer keys too)
    {:ok, Map.get(object, key, :undefined)}
  end

  defp access_value(array, index) when is_list(array) and is_integer(index) and index >= 0 do
    # Array access with integer index
    if index < length(array) do
      {:ok, Enum.at(array, index)}
    else
      {:ok, :undefined}
    end
  end

  defp access_value(array, index) when is_list(array) and is_integer(index) and index < 0 do
    # Negative index not supported, return undefined
    {:ok, :undefined}
  end

  defp access_value(object, _key) when not is_map(object) and not is_list(object) do
    # Can't access properties of non-object/non-array values
    {:ok, :undefined}
  end

  defp access_value(_object, key)
       when not is_binary(key) and not is_integer(key) and not is_atom(key) do
    # Invalid key type - create a custom error message for bracket access key types
    key_type = get_value_type(key)
    operation_name = Predicator.Errors.operation_display_name(:bracket_access)
    key_text = Predicator.Errors.type_name_with_value(key_type, key)

    error_struct = %TypeMismatchError{
      message: "#{operation_name} requires a string, integer, or atom key, got #{key_text}",
      # Primary expected type
      expected: :string,
      got: key_type,
      values: key,
      operation: :bracket_access
    }

    {:error, error_struct}
  end

  @spec execute_function_call(t(), binary(), non_neg_integer()) :: {:ok, t()} | {:error, term()}
  defp execute_function_call(
         %__MODULE__{stack: stack, functions: functions} = evaluator,
         function_name,
         arg_count
       ) do
    if length(stack) >= arg_count do
      # Extract arguments from stack (they're in reverse order)
      {args, remaining_stack} = Enum.split(stack, arg_count)
      # Reverse args to get correct order (stack is LIFO)
      function_args = Enum.reverse(args)

      case call_function(functions, function_name, function_args, evaluator.context) do
        {:ok, result} ->
          {:ok, %__MODULE__{evaluator | stack: [result | remaining_stack]}}

        {:error, message} ->
          {:error, EvaluationError.new(message, message, :function_call)}
      end
    else
      {:error,
       EvaluationError.new(
         "Function #{function_name}() expects #{arg_count} arguments, but only #{length(stack)} values on stack",
         "insufficient_arguments",
         :function_call
       )}
    end
  end

  # Call a function from the functions map
  @spec call_function(
          %{binary() => {non_neg_integer(), function()}},
          binary(),
          [Types.value()],
          Types.context()
        ) ::
          {:ok, Types.value()} | {:error, binary()}
  defp call_function(functions, function_name, args, context) do
    case Map.get(functions, function_name) do
      {arity, function} ->
        if length(args) == arity do
          try do
            function.(args, context)
          rescue
            error ->
              {:error, "Function #{function_name}() raised: #{inspect(error)}"}
          end
        else
          {:error, "Function #{function_name}() expects #{arity} arguments, got #{length(args)}"}
        end

      nil ->
        {:error, "Unknown function: #{function_name}"}
    end
  end

  @spec load_from_context(Types.context(), binary()) :: Types.value()
  defp load_from_context(context, variable_name)
       when is_map(context) and is_binary(variable_name) do
    # Try string key first, then atom key
    case Map.get(context, variable_name) do
      nil ->
        # Try as atom key if string key doesn't exist
        try do
          atom_key = String.to_existing_atom(variable_name)
          Map.get(context, atom_key, :undefined)
        rescue
          ArgumentError ->
            # String.to_existing_atom failed, variable doesn't exist
            :undefined
        end

      value ->
        value
    end
  end

  @spec execute_object_new(__MODULE__.t()) :: {:ok, __MODULE__.t()}
  defp execute_object_new(%__MODULE__{stack: stack} = evaluator) do
    new_object = %{}
    {:ok, %{evaluator | stack: [new_object | stack]}}
  end

  @spec execute_object_set(__MODULE__.t(), binary()) :: {:ok, __MODULE__.t()} | {:error, term()}
  defp execute_object_set(%__MODULE__{stack: [value, object | rest]} = evaluator, key)
       when is_map(object) do
    updated_object = Map.put(object, key, value)
    {:ok, %{evaluator | stack: [updated_object | rest]}}
  end

  defp execute_object_set(%__MODULE__{stack: [_value, _non_object | _rest]} = _evaluator, _key) do
    {:error, "Cannot set property on non-object value"}
  end

  defp execute_object_set(%__MODULE__{stack: stack} = _evaluator, _key) when length(stack) < 2 do
    {:error, EvaluationError.insufficient_operands(:object_set, length(stack), 2)}
  end
end
