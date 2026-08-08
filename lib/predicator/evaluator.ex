defmodule Predicator.Evaluator do
  @moduledoc """
  Stack-based evaluator for predicator instructions.

  The evaluator executes a list of instructions using a stack machine approach.
  Instructions operate on a stack, with the most recent values at the top (head of list).

  The instruction set - every opcode this module accepts, its operands, stack
  effect, and error semantics - is specified in
  [`docs/isa.md`](../../docs/isa.md), not here. `and` and `or` were retired at
  ISA v3: a stored pre-3.7 artifact containing either is refused with a
  message naming the removing version and pointing at
  `Predicator.Instructions.upgrade/1`, though the ISA table (`docs/isa.md` §4)
  keeps their rows.
  """

  alias Predicator.Functions.{DateFunctions, JSONFunctions, MathFunctions, SystemFunctions}
  alias Predicator.{ContextLocation, Duration, Instructions, Types, Undefined}

  alias Predicator.Errors.{
    EvaluationError,
    LocationError,
    TypeMismatchError,
    UndefinedVariableError
  }

  @typedoc "Internal evaluator state"
  @type t :: %__MODULE__{
          instructions: Types.instruction_list() | tuple(),
          instruction_pointer: non_neg_integer(),
          stack: [Types.value()],
          context: Types.context(),
          functions: %{binary() => {function_arity(), function()}},
          positions: Types.position_table() | Types.span_table(),
          segment_positions: Types.segment_position_table(),
          halted: boolean(),
          unbound_loads: [unbound_load()],
          on_unbound: Predicator.Context.on_unbound(),
          size: non_neg_integer() | nil
        }

  @typedoc "A function's accepted argument count(s): a fixed arity, or a set of arities for optional/variadic-style args"
  @type function_arity :: non_neg_integer() | [non_neg_integer()]

  @typedoc """
  An executed load of a root that was not bound, paired with the source location
  of the `["load", _]` instruction that read it.

  The location is the raw `positions` table entry: `nil` when the run carried no
  table or the index was uncovered, a `t:Predicator.Types.position/0` under point
  positions, a `t:Predicator.Types.span/0` under spans. Hand it to
  `Predicator.Errors.put_position/2`, which discriminates the three.
  """
  @type unbound_load :: {binary(), Types.position() | Types.span() | nil}

  defstruct [
    :instructions,
    :size,
    instruction_pointer: 0,
    stack: [],
    context: %{},
    functions: %{},
    positions: %{},
    segment_positions: %{},
    halted: false,
    unbound_loads: [],
    on_unbound: :undefined
  ]

  @doc """
  Merges the builtin function maps with `opts[:functions]`.

  Builtins are `SystemFunctions`, `DateFunctions`, `JSONFunctions`, and
  `MathFunctions`, in that order; `opts[:functions]` is merged last, so
  custom functions can shadow a builtin of the same name.
  """
  @spec merge_functions(keyword()) :: %{binary() => {function_arity(), function()}}
  def merge_functions(opts \\ []) do
    SystemFunctions.all_functions()
    |> Map.merge(DateFunctions.all_functions())
    |> Map.merge(JSONFunctions.all_functions())
    |> Map.merge(MathFunctions.all_functions())
    |> Map.merge(Keyword.get(opts, :functions, %{}))
  end

  @doc """
  Runs an already-built evaluator to completion, returning its result **and**
  its final state - on the error path too.

  Same as `evaluate_prepared/1` except that the caller keeps the state the run
  produced - `unbound_loads/1` in particular, which `Predicator.evaluate/3`
  reads to name the variable behind an `:undefined` result *and* behind a
  `TypeMismatchError` that rejected an `:undefined` operand (`px-8um.7`).
  """
  @spec run_prepared(t()) :: {:ok, Types.value(), t()} | {:error, struct(), t()}
  def run_prepared(%__MODULE__{} = evaluator) do
    case run_state(evaluator) do
      {:ok, %__MODULE__{stack: [result | _rest]} = final} ->
        {:ok, result, final}

      {:ok, %__MODULE__{stack: []} = final} ->
        {:error,
         EvaluationError.new(
           "Evaluation completed with empty stack",
           "empty_stack",
           :evaluate
         ), final}

      {:error, error_struct, final} when is_struct(error_struct) ->
        {:error, error_struct, final}
    end
  end

  @doc """
  Runs an already-built evaluator to completion and extracts its result.

  Unlike `evaluate/3`, this does no function merging - `evaluator.functions`
  is used as given. This is what `evaluate/3` uses internally, and what
  `Predicator.Context`-based evaluation uses to skip the per-call merge.
  """
  @spec evaluate_prepared(t()) :: Types.internal_result()
  def evaluate_prepared(%__MODULE__{} = evaluator) do
    case run_prepared(evaluator) do
      {:ok, result, _final} -> result
      {:error, error_struct, _final} -> {:error, error_struct}
    end
  end

  @doc """
  The root variables this run loaded and did not find bound, in execution
  order, without repeats.

  This is what the run *actually read*, not what the program contains: a load
  inside a branch `jump_if_falsy_or_pop`/`jump_if_true_or_pop` skipped never
  executes and never appears here. `Predicator.evaluate/3` uses it to name the
  variable behind an `:undefined` result.

  It records executed loads, not provenance - a run that executes two unbound
  loads lists both, even if only the second one's `:undefined` reached the
  result. Deciding that would require tracking which stack value descends from
  which load.

  `unbound_loads_with_locations/1` returns the same loads with the source
  location of each.

  ## Examples

      iex> instructions = [["load", "a"], ["load", "b"]]
      iex> {:ok, _result, evaluator} =
      ...>   Predicator.Evaluator.run_prepared(%Predicator.Evaluator{
      ...>     instructions: instructions,
      ...>     context: %{"a" => 1}
      ...>   })
      iex> Predicator.Evaluator.unbound_loads(evaluator)
      ["b"]
  """
  @spec unbound_loads(t()) :: [binary()]
  def unbound_loads(%__MODULE__{} = evaluator) do
    evaluator |> unbound_loads_with_locations() |> Enum.map(&elem(&1, 0))
  end

  @doc """
  The same loads `unbound_loads/1` reports, each paired with the source location
  of the `["load", _]` instruction that read it.

  The location comes from the run's `positions` table, read at the load itself, so
  it names the *variable's* token - not the operator that later rejected its
  `:undefined`. It is `nil` when the run carried no table (an instruction-list
  caller who passed no `positions:`), a `{line, column}` under point positions, and
  a span under a table from `compiled.positions`, where `compiled` is the
  `t:Predicator.Compiled.t/0` `Predicator.compile_with_spans/1` returned.
  `Predicator.evaluate/3` uses this to position the `UndefinedVariableError` it
  builds after the run.

  A name loaded more than once appears once, with the location of its first
  executed load.

  ## Examples

      iex> instructions = [["load", "a"], ["load", "b"]]
      iex> {:ok, _result, evaluator} =
      ...>   Predicator.Evaluator.run_prepared(%Predicator.Evaluator{
      ...>     instructions: instructions,
      ...>     context: %{},
      ...>     positions: %{1 => {1, 5}}
      ...>   })
      iex> Predicator.Evaluator.unbound_loads_with_locations(evaluator)
      [{"a", nil}, {"b", {1, 5}}]
  """
  @spec unbound_loads_with_locations(t()) :: [unbound_load()]
  def unbound_loads_with_locations(%__MODULE__{unbound_loads: loads}), do: Enum.reverse(loads)

  @doc """
  Evaluates a list of instructions with the given context and options.

  Returns the top value on the stack when evaluation completes,
  or an error if something goes wrong.

  ## Parameters

  - `instructions` - List of instructions to execute
  - `context` - Context map with variable bindings (default: `%{}`)
  - `opts` - Options keyword list:
    - `:functions` - Map of custom functions `%{name => {arity, function}}`
    - `:positions` - Side table mapping a 0-based instruction index to the
      `{line, column}` of the AST node that emitted it, as produced by
      `Predicator.Compiler.to_instructions_with_positions/2` and carried in a
      `t:Predicator.Compiled.t/0`'s `positions` field. Runtime errors raised by
      an instruction with a table entry carry it as `:position`. A span table
      from `compiled.positions`, where `compiled` is what
      `Predicator.compile_with_spans/1` returned, works here too: such an
      error carries the span as `:span` and the span's start as `:position`.
    - `:segment_positions` - the per-store segment-position side table from
      `compiled.segment_positions`, as produced by
      `Predicator.Compiler.to_instructions_with_segment_positions/2`. Read only
      by `store`, to blame the exact failing location segment rather than the
      store instruction's own `positions` entry (the lhs root). A run carrying
      no table - or none for the failing store - positions a store failure
      exactly as `:positions` alone would; passing this option changes no
      other opcode's behavior.
    - `:on_unbound` - `:undefined` (default) or `:error`. Under `:error`, a
      `["load", name]` whose `name` is not present in `context` returns
      `{:error, %Predicator.Errors.UndefinedVariableError{}}` instead of
      pushing `:undefined`. Unlike `Predicator.Context.new/2`, this option is
      not validated here: any value other than `:error` behaves as
      `:undefined`.

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
    evaluate_prepared(%__MODULE__{
      instructions: instructions,
      context: context,
      functions: merge_functions(opts),
      positions: Keyword.get(opts, :positions, %{}),
      segment_positions: Keyword.get(opts, :segment_positions, %{}),
      on_unbound: Keyword.get(opts, :on_unbound, :undefined)
    })
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
  def run(%__MODULE__{} = evaluator) do
    case run_state(evaluator) do
      {:ok, _final} = ok -> ok
      {:error, error_struct, _final} -> {:error, error_struct}
    end
  end

  @doc """
  Runs an already-built evaluator to halt, returning the final state on both
  paths.

  This is statement mode's entry point (`docs/isa.md` section 2): unlike
  `run_prepared/1` it applies no expression-mode result rule, so an empty
  stack at halt is a normal halt rather than `empty_stack`. On error the state
  returned is the pre-step one, holding every write the statements before the
  failing instruction performed - a `["load", _]` instruction never errors,
  so the pre-step state holds every unbound load recorded before the failing
  instruction too, which is all of them.
  """
  @spec run_state(t()) :: {:ok, t()} | {:error, struct(), t()}
  def run_state(%__MODULE__{halted: true} = evaluator), do: {:ok, evaluator}

  def run_state(%__MODULE__{} = evaluator) do
    case step(evaluator) do
      {:ok, new_evaluator} -> run_state(new_evaluator)
      {:error, error_struct} when is_struct(error_struct) -> {:error, error_struct, evaluator}
    end
  end

  @doc """
  Executes a single instruction step.

  Returns the updated evaluator state or an error.
  """
  @spec step(t()) :: {:ok, t()} | {:error, term()}
  def step(%__MODULE__{instructions: instructions} = evaluator) when is_list(instructions) do
    step(%__MODULE__{
      evaluator
      | instructions: :erlang.list_to_tuple(instructions),
        size: length(instructions)
    })
  end

  def step(%__MODULE__{} = evaluator) do
    if finished?(evaluator) do
      {:ok, halt(evaluator)}
    else
      case fetch_current_instruction(evaluator) do
        {:ok, instruction} ->
          evaluator
          |> execute_instruction(instruction)
          |> advance_instruction_pointer()
          |> attach_position(evaluator)

        {:error, reason} ->
          {:error, attach_error_position(reason, evaluator)}
      end
    end
  end

  # Private functions

  # `before` is the pre-step state, whose instruction_pointer is still the
  # failing instruction's index; advance_instruction_pointer/1 passes errors
  # through untouched, so either state would do, but the pre-step one says why.
  @spec attach_position({:ok, t()} | {:error, term()}, t()) :: {:ok, t()} | {:error, term()}
  defp attach_position({:ok, _evaluator} = ok, _before), do: ok

  # `located/3`'s tagged tuple: `store` has already resolved the exact segment
  # location itself, so it is stamped directly rather than looked up again by
  # instruction pointer. Constructed only by `located/3`, destructured only
  # here - it never escapes `step/1`.
  defp attach_position({:error, {:located, reason, location}}, _before),
    do: {:error, Predicator.Errors.put_position(reason, location)}

  defp attach_position({:error, reason}, %__MODULE__{} = before) do
    {:error, attach_error_position(reason, before)}
  end

  @spec attach_error_position(term(), t()) :: term()
  defp attach_error_position(reason, %__MODULE__{positions: positions, instruction_pointer: ip}) do
    Predicator.Errors.put_position(reason, Map.get(positions, ip))
  end

  @spec finished?(t()) :: boolean()
  defp finished?(%__MODULE__{instruction_pointer: ip, size: size}) do
    ip >= size
  end

  @spec halt(t()) :: t()
  defp halt(%__MODULE__{} = evaluator) do
    %__MODULE__{evaluator | halted: true}
  end

  @spec fetch_current_instruction(t()) :: {:ok, Types.instruction()} | {:error, term()}
  defp fetch_current_instruction(%__MODULE__{
         instruction_pointer: ip,
         instructions: instructions,
         size: size
       })
       when ip >= 0 and ip < size do
    {:ok, :erlang.element(ip + 1, instructions)}
  end

  defp fetch_current_instruction(%__MODULE__{instruction_pointer: ip}) do
    {:error,
     EvaluationError.new(
       "Invalid instruction pointer: #{ip}",
       "invalid_instruction_pointer",
       :evaluate
     )}
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

    if evaluator.on_unbound == :error and unbound_load?(evaluator, variable_name, value) do
      {:error, UndefinedVariableError.new(variable_name)}
    else
      {:ok,
       evaluator
       |> record_unbound_load(variable_name, value)
       |> push_stack(value)}
    end
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

  # List construction instruction
  defp execute_instruction(%__MODULE__{} = evaluator, ["make_list", count])
       when is_integer(count) and count >= 0 do
    execute_make_list(evaluator, count)
  end

  # Short-circuit AND: jump (leaving the value) if falsy, else pop and fall through
  defp execute_instruction(%__MODULE__{} = evaluator, ["jump_if_falsy_or_pop", offset])
       when is_integer(offset) and offset > 0 do
    execute_jump_if_falsy_or_pop(evaluator, offset)
  end

  # Short-circuit OR: jump (leaving the value) if true, else pop and fall through
  defp execute_instruction(%__MODULE__{} = evaluator, ["jump_if_true_or_pop", offset])
       when is_integer(offset) and offset > 0 do
    execute_jump_if_true_or_pop(evaluator, offset)
  end

  # Duration instruction
  defp execute_instruction(%__MODULE__{} = evaluator, ["duration", units]) when is_list(units) do
    execute_duration(evaluator, units)
  end

  # Relative date instruction
  defp execute_instruction(%__MODULE__{} = evaluator, ["relative_date", direction])
       when is_binary(direction) do
    execute_relative_date(evaluator, direction)
  end

  # Store instruction: writes a value at a location path into the context
  defp execute_instruction(%__MODULE__{} = evaluator, ["store", n])
       when is_integer(n) and n >= 0 do
    execute_store(evaluator, n)
  end

  # Statement-boundary instruction: discards the stack top, pushes nothing
  defp execute_instruction(%__MODULE__{} = evaluator, ["pop"]) do
    execute_pop(evaluator)
  end

  # A retired opcode has no clause of its own (docs/isa.md section 4, "Retired
  # opcodes") and lands here. It is not an *unknown* instruction - the ISA
  # still has its row - so it gets the refusal ADR-0003 promises: a message
  # naming the ISA version that removed it and the upgrade path. The lookup
  # costs nothing on the happy path, because this clause is reached only after
  # an instruction has already failed to match.
  defp execute_instruction(%__MODULE__{}, [opcode | _operands] = unknown)
       when is_binary(opcode) do
    case Instructions.retired_in(opcode) do
      {:ok, version} when is_integer(version) -> retired_opcode_error(opcode, version)
      _live_or_unknown -> unknown_instruction_error(unknown)
    end
  end

  # Unknown instruction - catch-all clause
  defp execute_instruction(%__MODULE__{}, unknown) do
    unknown_instruction_error(unknown)
  end

  @spec retired_opcode_error(String.t(), pos_integer()) :: {:error, EvaluationError.t()}
  defp retired_opcode_error(opcode, version) do
    {:error,
     EvaluationError.new(
       "Instruction #{inspect([opcode])} was retired at ISA v#{version}. " <>
         "Run Predicator.Instructions.upgrade/1 over this instruction list to migrate it.",
       "retired_opcode",
       :evaluate
     )}
  end

  @spec unknown_instruction_error(Types.instruction()) :: {:error, EvaluationError.t()}
  defp unknown_instruction_error(unknown) do
    {:error,
     EvaluationError.new(
       "Unknown instruction: #{inspect(unknown)}",
       "unknown_instruction",
       :evaluate
     )}
  end

  @spec advance_instruction_pointer({:ok, t()} | {:error, struct() | {:located, term(), term()}}) ::
          {:ok, t()} | {:error, struct() | {:located, term(), term()}}
  defp advance_instruction_pointer({:ok, %__MODULE__{} = evaluator}) do
    {:ok, %__MODULE__{evaluator | instruction_pointer: evaluator.instruction_pointer + 1}}
  end

  defp advance_instruction_pointer({:error, error_struct}) when is_struct(error_struct),
    do: {:error, error_struct}

  # Pass `located/3`'s tagged tuple through unchanged: it is not a struct, so
  # the guarded clause above would not match it and this would otherwise raise
  # `FunctionClauseError`. `attach_position/2` destructures it next.
  defp advance_instruction_pointer({:error, {:located, _reason, _location}} = error), do: error

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
    # access never errors (docs/isa.md section 5); access_value/3 with
    # :access always returns {:ok, _}.
    {:ok, value} = access_value(object, property, :access)
    {:ok, %__MODULE__{evaluator | stack: [value | rest]}}
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
       do: Undefined.value()

  defp compare_values(_left, :undefined, operator)
       when operator not in ["STRICT_EQ", "STRICT_NE"],
       do: Undefined.value()

  # Strict equality works on all types, including :undefined
  defp compare_values(left, right, "STRICT_EQ"), do: left === right
  defp compare_values(left, right, "STRICT_NE"), do: left !== right

  # Date/DateTime compare chronologically, not by Erlang term/struct-key order
  defp compare_values(%Date{} = left, %Date{} = right, operator) do
    compare_chronological(Date.compare(left, right), operator)
  end

  defp compare_values(%DateTime{} = left, %DateTime{} = right, operator) do
    compare_chronological(DateTime.compare(left, right), operator)
  end

  # Mixed Date/DateTime coerces the Date to midnight UTC, matching the
  # coercion apply_subtraction/2 already performs for the same pair
  defp compare_values(%Date{} = left, %DateTime{} = right, operator) do
    compare_chronological(DateTime.compare(date_to_datetime(left), right), operator)
  end

  defp compare_values(%DateTime{} = left, %Date{} = right, operator) do
    compare_chronological(DateTime.compare(left, date_to_datetime(right)), operator)
  end

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

  defp compare_values(_left, _right, _operator), do: Undefined.value()

  @spec compare_chronological(:lt | :eq | :gt, binary()) :: boolean()
  defp compare_chronological(comparison, operator) do
    case operator do
      "GT" -> comparison == :gt
      "LT" -> comparison == :lt
      "EQ" -> comparison == :eq
      "GTE" -> comparison in [:gt, :eq]
      "LTE" -> comparison in [:lt, :eq]
      "NE" -> comparison != :eq
    end
  end

  @spec values_equal?(Types.value(), Types.value()) :: boolean()
  defp values_equal?(:undefined, _value), do: false
  defp values_equal?(_value, :undefined), do: false
  defp values_equal?(%Date{} = left, %Date{} = right), do: Date.compare(left, right) == :eq

  defp values_equal?(%DateTime{} = left, %DateTime{} = right),
    do: DateTime.compare(left, right) == :eq

  defp values_equal?(%Date{} = left, %DateTime{} = right),
    do: DateTime.compare(date_to_datetime(left), right) == :eq

  defp values_equal?(%DateTime{} = left, %Date{} = right),
    do: DateTime.compare(left, date_to_datetime(right)) == :eq

  defp values_equal?(left, right) when types_match(left, right), do: left == right
  defp values_equal?(_left, _right), do: false

  @spec push_stack(t(), Types.value()) :: t()
  defp push_stack(%__MODULE__{stack: stack} = evaluator, value) do
    %__MODULE__{evaluator | stack: [value | stack]}
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
        {:ok, %__MODULE__{evaluator | stack: [Undefined.value() | rest]}}

      {_value, :undefined} ->
        {:ok, %__MODULE__{evaluator | stack: [Undefined.value() | rest]}}

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
        {:ok, %__MODULE__{evaluator | stack: [Undefined.value() | rest]}}

      {_value, :undefined} ->
        {:ok, %__MODULE__{evaluator | stack: [Undefined.value() | rest]}}

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

  # Subtraction with date arithmetic support
  defp execute_arithmetic(%__MODULE__{stack: [right | [left | rest]]} = evaluator, :subtract) do
    result = apply_subtraction(left, right)

    case result do
      {:ok, value} ->
        {:ok, %__MODULE__{evaluator | stack: [value | rest]}}

      {:error, _error} = error_result ->
        error_result
    end
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

  defp apply_addition(left, right) when is_list(left) and is_list(right) do
    {:ok, left ++ right}
  end

  # Date + Duration = Date/DateTime
  defp apply_addition(%Date{} = date, duration) when is_map(duration) do
    if duration_map?(duration) do
      {:ok, Duration.add_to_date(date, duration)}
    else
      apply_addition_fallback(date, duration)
    end
  end

  defp apply_addition(%DateTime{} = datetime, duration) when is_map(duration) do
    if duration_map?(duration) do
      {:ok, Duration.add_to_datetime(datetime, duration)}
    else
      apply_addition_fallback(datetime, duration)
    end
  end

  # Duration + Date = Date/DateTime (commutative)
  defp apply_addition(duration, %Date{} = date) when is_map(duration) do
    apply_addition(date, duration)
  end

  defp apply_addition(duration, %DateTime{} = datetime) when is_map(duration) do
    apply_addition(datetime, duration)
  end

  defp apply_addition(left, right) do
    apply_addition_fallback(left, right)
  end

  defp apply_addition_fallback(left, right) do
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

  @spec date_to_datetime(Date.t()) :: DateTime.t()
  defp date_to_datetime(%Date{} = date) do
    {:ok, datetime} = DateTime.new(date, ~T[00:00:00], "Etc/UTC")
    datetime
  end

  # Subtraction operations with date arithmetic
  @spec apply_subtraction(Types.value(), Types.value()) :: {:ok, Types.value()} | {:error, term()}
  defp apply_subtraction(left, right) when is_number(left) and is_number(right) do
    {:ok, left - right}
  end

  # Date - Date = Duration (difference in days as a duration)
  defp apply_subtraction(%Date{} = left_date, %Date{} = right_date) do
    days_diff = Date.diff(left_date, right_date)
    duration = Duration.new(days: days_diff)
    {:ok, duration}
  end

  # DateTime - DateTime = Duration (difference in seconds as a duration)
  defp apply_subtraction(%DateTime{} = left_datetime, %DateTime{} = right_datetime) do
    seconds_diff = DateTime.diff(left_datetime, right_datetime, :second)
    duration = Duration.new(seconds: seconds_diff)
    {:ok, duration}
  end

  # Mixed Date/DateTime subtraction (convert Date to start of day UTC)
  defp apply_subtraction(%Date{} = date, %DateTime{} = datetime) do
    apply_subtraction(date_to_datetime(date), datetime)
  end

  defp apply_subtraction(%DateTime{} = datetime, %Date{} = date) do
    apply_subtraction(datetime, date_to_datetime(date))
  end

  # Date - Duration = Date/DateTime
  defp apply_subtraction(%Date{} = date, duration) when is_map(duration) do
    if duration_map?(duration) do
      {:ok, Duration.subtract_from_date(date, duration)}
    else
      apply_subtraction_fallback(date, duration)
    end
  end

  defp apply_subtraction(%DateTime{} = datetime, duration) when is_map(duration) do
    if duration_map?(duration) do
      {:ok, Duration.subtract_from_datetime(datetime, duration)}
    else
      apply_subtraction_fallback(datetime, duration)
    end
  end

  defp apply_subtraction(left, right) do
    apply_subtraction_fallback(left, right)
  end

  defp apply_subtraction_fallback(left, right) do
    left_type = get_value_type(left)
    right_type = get_value_type(right)

    {:error,
     TypeMismatchError.binary(
       :subtract,
       :number_or_date,
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

  defp get_value_type(:undefined), do: Undefined.value()

  defp get_value_type(value) when is_map(value) do
    # Check if it's a duration map (has required duration keys)
    if duration_map?(value), do: :duration, else: :map
  end

  # Helper to check if a map is a duration (only called with maps)
  defp duration_map?(value) do
    Map.has_key?(value, :years) and Map.has_key?(value, :months) and
      Map.has_key?(value, :weeks) and Map.has_key?(value, :days) and
      Map.has_key?(value, :hours) and Map.has_key?(value, :minutes) and
      Map.has_key?(value, :seconds)
  end

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
    case access_value(object, key, :bracket_access) do
      {:ok, value} ->
        {:ok, %__MODULE__{evaluator | stack: [value | rest]}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_bracket_access(%__MODULE__{stack: stack}) when length(stack) < 2 do
    {:error, EvaluationError.insufficient_operands(:bracket_access, length(stack), 2)}
  end

  # Access a value from an object or array using a key or index.
  @spec access_value(Types.value(), Types.value(), :access | :bracket_access) ::
          {:ok, Types.value()} | {:error, TypeMismatchError.t()}
  # A map takes a string, an integer, or an atom key. `true`, `false`, and
  # `:undefined` are atoms in Elixir and are accepted deliberately: Context
  # normalization leaves boolean map keys unstringified precisely so this
  # lookup works (lib/predicator/context.ex, px-8um.2). A miss is :undefined,
  # not an error.
  defp access_value(object, key, _operation)
       when is_map(object) and (is_binary(key) or is_integer(key) or is_atom(key)) do
    {:ok, Map.get(object, key, Undefined.value())}
  end

  defp access_value(array, index, _operation)
       when is_list(array) and is_integer(index) and index >= 0 do
    if index < length(array), do: {:ok, Enum.at(array, index)}, else: {:ok, Undefined.value()}
  end

  # Negative indices do not count from the end; they miss.
  defp access_value(array, index, _operation) when is_list(array) and is_integer(index) do
    {:ok, Undefined.value()}
  end

  # A target that is neither map nor list has nothing to index, whatever the key.
  defp access_value(object, _key, _operation) when not is_map(object) and not is_list(object) do
    {:ok, Undefined.value()}
  end

  # Everything left is a map or list target whose key it cannot index.
  # `access` never errors (docs/isa.md section 5); `bracket_access` does.
  defp access_value(_object, _key, :access), do: {:ok, Undefined.value()}

  defp access_value(object, key, :bracket_access) do
    {:error, bracket_key_error(object, key)}
  end

  # Builds the TypeMismatchError for a bracket_access key that cannot index
  # its target. Target-aware, because "requires a string, integer, or atom
  # key" is a nonsense message to hand a caller who indexed a list.
  @spec bracket_key_error(Types.value(), Types.value()) :: TypeMismatchError.t()
  defp bracket_key_error(target, key) when is_list(target) do
    key_type = get_value_type(key)
    operation_name = Predicator.Errors.operation_display_name(:bracket_access)
    key_text = Predicator.Errors.type_name_with_value(key_type, key)

    %TypeMismatchError{
      message: "#{operation_name} on a list requires an integer index, got #{key_text}",
      expected: :integer,
      got: key_type,
      values: key,
      operation: :bracket_access
    }
  end

  defp bracket_key_error(_target, key) do
    key_type = get_value_type(key)
    operation_name = Predicator.Errors.operation_display_name(:bracket_access)
    key_text = Predicator.Errors.type_name_with_value(key_type, key)

    %TypeMismatchError{
      message: "#{operation_name} requires a string, integer, or atom key, got #{key_text}",
      # Primary expected type
      expected: :string,
      got: key_type,
      values: key,
      operation: :bracket_access
    }
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
          %{binary() => {function_arity(), function()}},
          binary(),
          [Types.value()],
          Types.context()
        ) ::
          {:ok, Types.value()} | {:error, binary()}
  defp call_function(functions, function_name, args, context) do
    case Map.get(functions, function_name) do
      {arity, function} ->
        if arity_matches?(arity, length(args)) do
          try do
            function.(args, context)
          rescue
            error ->
              {:error, "Function #{function_name}() raised: #{inspect(error)}"}
          end
        else
          {:error,
           "Function #{function_name}() expects #{describe_arity(arity)} arguments, got #{length(args)}"}
        end

      nil ->
        {:error, "Unknown function: #{function_name}"}
    end
  end

  @spec arity_matches?(function_arity(), non_neg_integer()) :: boolean()
  defp arity_matches?(arity, count) when is_integer(arity), do: arity == count
  defp arity_matches?(arities, count) when is_list(arities), do: count in arities

  @spec describe_arity(function_arity()) :: binary()
  defp describe_arity(arity) when is_integer(arity), do: to_string(arity)

  defp describe_arity(arities) when is_list(arities) do
    Enum.map_join(arities, " or ", &to_string/1)
  end

  @spec load_from_context(Types.context(), binary()) :: Types.value()
  defp load_from_context(context, variable_name)
       when is_map(context) and is_binary(variable_name) do
    # String-key lookup only. Atom keys never reach here: Context.new/2 and
    # bind/3 normalize them away at the edge (px-8um.2), so a missing string
    # key means the variable is genuinely unbound.
    Map.get(context, variable_name, Undefined.value())
  end

  @doc """
  Resolves `name` to the key it is bound under in `data`, or `:unbound`.

  A root variable may be stored under a string key or the equivalent atom key;
  this answers which. `Predicator.Context.bound?/2` and the evaluator's own
  unbound-load recording both go through here, so they cannot drift apart from
  each other.

  Note this asks about *presence*, not value: a name bound to `:undefined` (or
  to `nil`) resolves to `{:ok, key}`, because it is bound.

  > #### Atom keys resolve here but no longer load {: .info}
  >
  > This is deliberately *wider* than what a `load` instruction reads. Since
  > `px-8um.2`, `load` does a plain string-key lookup: `Predicator.Context.new/2`
  > and `bind/3` normalize atom keys away at the edge, so no `Context`-routed
  > data can still carry one. The atom branch below survives only for a caller
  > who bypasses that edge - `Predicator.Evaluator.evaluate/3` or
  > `Predicator.evaluator/2` handed a hand-built atom-keyed map.
  >
  > For that caller the two answers are asymmetric: `%{score: 85}` *loads* as
  > `:undefined` (no string key) while resolving as `{:ok, :score}` (present),
  > so the load is not recorded in `unbound_loads`. Bound-but-undefined is a
  > state this API already models, and treating a present atom key as unbound
  > bookkeeping would be the worse answer. Nothing reachable through
  > `Predicator.evaluate/3` can observe the asymmetry.

  ## Examples

      iex> Predicator.Evaluator.resolve_key(%{"score" => 85}, "score")
      {:ok, "score"}

      iex> Predicator.Evaluator.resolve_key(%{score: 85}, "score")
      {:ok, :score}

      iex> Predicator.Evaluator.resolve_key(%{"score" => 85}, "missing")
      :unbound
  """
  @spec resolve_key(Types.context(), binary()) :: {:ok, binary() | atom()} | :unbound
  def resolve_key(data, name) when is_map(data) and is_binary(name) do
    if Map.has_key?(data, name), do: {:ok, name}, else: resolve_atom_key(data, name)
  end

  @spec resolve_atom_key(Types.context(), binary()) :: {:ok, atom()} | :unbound
  defp resolve_atom_key(data, name) do
    atom_key = String.to_existing_atom(name)
    if Map.has_key?(data, atom_key), do: {:ok, atom_key}, else: :unbound
  rescue
    ArgumentError -> :unbound
  end

  # The one question both halves of the unbound-load hook ask: did this load
  # read a root that is not present in the context at all? Its two callers are
  # the recorder below and the `on_unbound: :error` policy in the `load`
  # clause - the same event, decided differently.
  #
  # Presence, not value, is the question: `%{"x" => nil}` and
  # `%{"x" => :undefined}` both load as :undefined but are bound, so neither is
  # recorded and neither trips the policy. Context.bound?/2 must keep agreeing
  # with what gets recorded here - which is why both go through resolve_key/2.
  # That agreement is between these two, not with load_from_context/2:
  # resolve_key/2 still finds an atom key that a load no longer reads, which is
  # visible only to a caller who bypassed Context.new/2 - see resolve_key/2's
  # docs.
  @spec unbound_load?(t(), binary(), Types.value()) :: boolean()
  defp unbound_load?(%__MODULE__{} = evaluator, variable_name, value) do
    Undefined.undefined?(value) and
      resolve_key(evaluator.context, variable_name) == :unbound
  end

  # The dedup check stays here rather than in unbound_load?/3: the policy fires
  # on the first unbound load and halts, so it never needs it.
  #
  # Dedup keys on the name alone, so a name loaded twice keeps the location of
  # its *first* executed load - the same entry, and the same reported variable,
  # the pre-px-1e1 names-only list produced.
  @spec record_unbound_load(t(), binary(), Types.value()) :: t()
  defp record_unbound_load(%__MODULE__{} = evaluator, variable_name, value) do
    if unbound_load?(evaluator, variable_name, value) and
         not List.keymember?(evaluator.unbound_loads, variable_name, 0) do
      entry = {variable_name, current_location(evaluator)}
      %__MODULE__{evaluator | unbound_loads: [entry | evaluator.unbound_loads]}
    else
      evaluator
    end
  end

  # The load's own location, read at the load. record_unbound_load/3 runs from
  # inside execute_instruction/2, before advance_instruction_pointer/1, so
  # instruction_pointer is still this load's index - the same index
  # attach_error_position/2 reads for an error raised by this instruction.
  @spec current_location(t()) :: Types.position() | Types.span() | nil
  defp current_location(%__MODULE__{positions: positions, instruction_pointer: ip}) do
    Map.get(positions, ip)
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

  defp execute_object_set(%__MODULE__{stack: [_value, non_object | _rest]}, _key) do
    {:error,
     EvaluationError.new(
       "Object set requires a map on the stack, got: #{inspect(non_object)}",
       "invalid_stack_value",
       :object_set
     )}
  end

  defp execute_object_set(%__MODULE__{stack: stack} = _evaluator, _key) when length(stack) < 2 do
    {:error, EvaluationError.insufficient_operands(:object_set, length(stack), 2)}
  end

  @spec execute_make_list(__MODULE__.t(), non_neg_integer()) ::
          {:ok, __MODULE__.t()} | {:error, term()}
  defp execute_make_list(%__MODULE__{stack: stack} = evaluator, count) do
    {popped, rest} = Enum.split(stack, count)

    if length(popped) == count do
      # The stack holds elements in reverse source order, deepest first.
      {:ok, %{evaluator | stack: [Enum.reverse(popped) | rest]}}
    else
      {:error, EvaluationError.insufficient_operands(:make_list, length(popped), count)}
    end
  end

  # `store` pops the value (stack top), then `n` location segments beneath
  # it, reverses the segments back into root-first path order (they were
  # pushed root-to-leaf, so the stack holds them deepest-first - the same
  # convention `execute_make_list/2` uses), and writes `path -> value` into
  # the context via `Predicator.ContextLocation.put/3`, the shared write
  # algorithm (docs/isa.md §5). Pushes nothing: this is the only opcode that
  # writes the context.
  @spec execute_store(__MODULE__.t(), non_neg_integer()) ::
          {:ok, __MODULE__.t()} | {:error, term()}
  defp execute_store(%__MODULE__{stack: stack} = evaluator, n) do
    {taken, rest} = Enum.split(stack, n + 1)

    if length(taken) == n + 1 do
      [value | reversed_segments] = taken
      path = Enum.reverse(reversed_segments)

      case validate_store_segments(path) do
        :ok ->
          do_store(evaluator, path, value, rest)

        {:error, error, index} ->
          located(evaluator, error, index)
      end
    else
      # No segment is identified (D2): the stack was short, so there is no
      # path to point into. This keeps the store instruction's own `positions`
      # entry, exactly as before px-ids.
      located(evaluator, EvaluationError.insufficient_operands(:store, length(taken), n + 1), nil)
    end
  end

  @spec do_store(__MODULE__.t(), ContextLocation.location_path(), Types.value(), [Types.value()]) ::
          {:ok, __MODULE__.t()} | {:error, term()}
  defp do_store(%__MODULE__{} = evaluator, path, value, rest) do
    case ContextLocation.put(evaluator.context, path, value) do
      {:ok, new_context} ->
        {:ok, %__MODULE__{evaluator | context: new_context, stack: rest}}

      {:error, %LocationError{details: details} = location_error} ->
        located(evaluator, wrap_location_error(location_error), Map.get(details, :path_index))
    end
  end

  # A location segment must be a binary or an integer, the mirror of
  # `bracket_access`'s key rule (docs/isa.md §5) - a boolean, a float, or
  # `:undefined` (an unbound computed bracket key) is a `TypeMismatchError`
  # rather than reaching `ContextLocation.put/3` with an out-of-domain path.
  # The expected-type text is passed explicitly (`unary/5`) rather than derived
  # from `expected`: `expected` is the normative field a consumer matches on and
  # stays `:string`, but an integer segment is equally valid (it indexes a
  # list), so the message names both instead of claiming `store` requires a
  # string alone.
  #
  # `Enum.find_index/2` rather than `Enum.find/2`: the index is the failing
  # segment's position in the root-first path, which `execute_store/2` hands to
  # `located/3` to look the segment's own annotation up in the run's segment
  # table.
  @spec validate_store_segments([term()]) ::
          :ok | {:error, TypeMismatchError.t(), non_neg_integer()}
  defp validate_store_segments(segments) do
    case Enum.find_index(segments, fn segment ->
           not (is_binary(segment) or is_integer(segment))
         end) do
      nil ->
        :ok

      index ->
        bad_segment = Enum.at(segments, index)

        {:error,
         TypeMismatchError.unary(
           :store,
           :string,
           get_value_type(bad_segment),
           bad_segment,
           "a string or an integer"
         ), index}
    end
  end

  # `put/3`'s `LocationError` carries no `:position`/`:span` (Q4,
  # `docs/isa.md` §5), so it is wrapped in an `EvaluationError` here - the
  # only place a `LocationError` can escape into the VM - which does carry
  # both and gets them stamped by `attach_position/2` like any other
  # evaluator error. The `LocationError`'s message is carried through
  # verbatim (messages are non-normative); its `type` becomes the normative
  # `reason`. `details` is no longer discarded wholesale: `do_store/4` reads
  # `:path_index` off it before calling this function, and the rest of
  # `details` is still dropped here, as it always was.
  @spec wrap_location_error(LocationError.t()) :: EvaluationError.t()
  defp wrap_location_error(%LocationError{type: :not_assignable, message: message}) do
    EvaluationError.new(message, "not_assignable", :store)
  end

  defp wrap_location_error(%LocationError{type: :not_a_container, message: message}) do
    EvaluationError.new(message, "not_a_container", :store)
  end

  defp wrap_location_error(%LocationError{type: :invalid_index, message: message}) do
    EvaluationError.new(message, "invalid_index", :store)
  end

  # The store is the one opcode that knows *which part of its own source
  # expression* failed: a path index, from `validate_store_segments/1` or from
  # the `LocationError`'s details. `positions` is keyed by instruction, so it
  # cannot express that; `segment_positions` can, and this is where the two are
  # joined. Returning `{:located, error, location}` rather than stamping here is
  # deliberate - `attach_position/2` is the single point that stamps a position
  # on an evaluator error (`Errors.put_position/2` overwrites unconditionally,
  # `errors.ex:41-56`), so a position set here would be clobbered by the store
  # instruction's own table entry. The tuple is constructed in this function and
  # destructured in `attach_position/2`, and never escapes `step/1`.
  @spec located(t(), term(), non_neg_integer() | nil) :: {:error, term()}
  defp located(%__MODULE__{} = evaluator, error, index) do
    case segment_annotation(evaluator, index) do
      nil -> {:error, error}
      annotation -> {:error, {:located, error, annotation}}
    end
  end

  @spec segment_annotation(t(), non_neg_integer() | nil) ::
          Types.position() | Types.span() | nil
  defp segment_annotation(%__MODULE__{} = evaluator, index) when is_integer(index) do
    evaluator.segment_positions
    |> Map.get(evaluator.instruction_pointer, [])
    |> Enum.at(index)
  end

  defp segment_annotation(_evaluator, _index), do: nil

  # `pop` is the statement-boundary opcode: it discards the stack top and
  # pushes nothing, so the next statement starts from a clean stack
  # (docs/isa.md §5).
  @spec execute_pop(__MODULE__.t()) :: {:ok, __MODULE__.t()} | {:error, term()}
  defp execute_pop(%__MODULE__{stack: [_value | rest]} = evaluator) do
    {:ok, %__MODULE__{evaluator | stack: rest}}
  end

  defp execute_pop(%__MODULE__{stack: []}) do
    {:error, EvaluationError.insufficient_operands(:pop, 0, 1)}
  end

  @spec execute_jump_if_falsy_or_pop(__MODULE__.t(), pos_integer()) ::
          {:ok, __MODULE__.t()} | {:error, term()}
  defp execute_jump_if_falsy_or_pop(%__MODULE__{stack: [top | _rest]} = evaluator, offset)
       when top == false or top == :undefined do
    {:ok, jump_to(evaluator, offset)}
  end

  defp execute_jump_if_falsy_or_pop(%__MODULE__{stack: [true | rest]} = evaluator, _offset) do
    {:ok, %{evaluator | stack: rest}}
  end

  defp execute_jump_if_falsy_or_pop(%__MODULE__{stack: [top | _rest]}, _offset) do
    got_type = get_value_type(top)
    {:error, TypeMismatchError.unary(:jump_if_falsy_or_pop, :boolean, got_type, top)}
  end

  defp execute_jump_if_falsy_or_pop(%__MODULE__{stack: []}, _offset) do
    {:error, EvaluationError.insufficient_operands(:jump_if_falsy_or_pop, 0, 1)}
  end

  @spec execute_jump_if_true_or_pop(__MODULE__.t(), pos_integer()) ::
          {:ok, __MODULE__.t()} | {:error, term()}
  defp execute_jump_if_true_or_pop(%__MODULE__{stack: [true | _rest]} = evaluator, offset) do
    {:ok, jump_to(evaluator, offset)}
  end

  defp execute_jump_if_true_or_pop(%__MODULE__{stack: [top | rest]} = evaluator, _offset)
       when top == false or top == :undefined do
    {:ok, %{evaluator | stack: rest}}
  end

  defp execute_jump_if_true_or_pop(%__MODULE__{stack: [top | _rest]}, _offset) do
    got_type = get_value_type(top)
    {:error, TypeMismatchError.unary(:jump_if_true_or_pop, :boolean, got_type, top)}
  end

  defp execute_jump_if_true_or_pop(%__MODULE__{stack: []}, _offset) do
    {:error, EvaluationError.insufficient_operands(:jump_if_true_or_pop, 0, 1)}
  end

  # Sets instruction_pointer so that the unconditional +1 in
  # advance_instruction_pointer/1 lands exactly on current_ip + offset.
  @spec jump_to(__MODULE__.t(), pos_integer()) :: __MODULE__.t()
  defp jump_to(%__MODULE__{instruction_pointer: ip} = evaluator, offset) do
    %{evaluator | instruction_pointer: ip + offset - 1}
  end

  @spec execute_duration(__MODULE__.t(), [[integer() | binary()]]) ::
          {:ok, __MODULE__.t()} | {:error, term()}
  defp execute_duration(%__MODULE__{} = evaluator, units) when is_list(units) do
    case convert_units_to_duration_map(units) do
      {:ok, duration_map} ->
        {:ok, push_stack(evaluator, duration_map)}

      {:error, error_struct} ->
        {:error, error_struct}
    end
  end

  # Helper function to convert units list to duration map
  @spec convert_units_to_duration_map([[integer() | binary()]]) ::
          {:ok, Types.duration()} | {:error, struct()}
  defp convert_units_to_duration_map(units) do
    initial_duration = %{years: 0, months: 0, weeks: 0, days: 0, hours: 0, minutes: 0, seconds: 0}

    Enum.reduce_while(units, {:ok, initial_duration}, fn
      [value, unit], {:ok, acc} when is_integer(value) and is_binary(unit) ->
        case unit_string_to_atom(unit) do
          {:ok, unit_atom} ->
            {:cont, {:ok, Map.put(acc, unit_atom, value)}}

          {:error, _reason} ->
            {:halt,
             {:error,
              EvaluationError.new(
                "Invalid duration unit: #{unit}",
                "invalid_duration_unit",
                :evaluate
              )}}
        end

      invalid_unit, _acc ->
        {:halt,
         {:error,
          EvaluationError.new(
            "Invalid duration unit format: #{inspect(invalid_unit)}",
            "invalid_duration_format",
            :evaluate
          )}}
    end)
  end

  @spec execute_relative_date(__MODULE__.t(), binary()) ::
          {:ok, __MODULE__.t()} | {:error, term()}
  defp execute_relative_date(%__MODULE__{stack: [duration | rest]} = evaluator, direction)
       when is_map(duration) and is_binary(direction) do
    case calculate_relative_date(duration, direction) do
      {:ok, target_datetime} ->
        {:ok, %{evaluator | stack: [target_datetime | rest]}}

      {:error, error_struct} ->
        {:error, error_struct}
    end
  end

  defp execute_relative_date(%__MODULE__{stack: [non_duration | _rest]}, _direction) do
    {:error,
     EvaluationError.new(
       "Relative date operation requires a duration on the stack, got: #{inspect(non_duration)}",
       "invalid_stack_value",
       :evaluate
     )}
  end

  defp execute_relative_date(%__MODULE__{stack: []}, _direction) do
    {:error, EvaluationError.insufficient_operands(:relative_date, 0, 1)}
  end

  # Helper function to calculate relative date
  @spec calculate_relative_date(Types.duration(), binary()) ::
          {:ok, DateTime.t()} | {:error, struct()}
  defp calculate_relative_date(duration, direction) do
    now = DateTime.utc_now()

    case direction do
      "ago" ->
        {:ok, subtract_duration(now, duration)}

      "future" ->
        {:ok, add_duration(now, duration)}

      "next" ->
        {:ok, add_duration(now, duration)}

      "last" ->
        {:ok, subtract_duration(now, duration)}

      _unknown_direction ->
        {:error,
         EvaluationError.new(
           "Unknown relative date direction: #{direction}",
           "invalid_direction",
           :evaluate
         )}
    end
  end

  # Helper functions for duration operations

  @spec unit_string_to_atom(binary()) :: {:ok, atom()} | {:error, :invalid_unit}
  defp unit_string_to_atom("y"), do: {:ok, :years}
  defp unit_string_to_atom("year"), do: {:ok, :years}
  defp unit_string_to_atom("years"), do: {:ok, :years}
  defp unit_string_to_atom("mo"), do: {:ok, :months}
  defp unit_string_to_atom("month"), do: {:ok, :months}
  defp unit_string_to_atom("months"), do: {:ok, :months}
  defp unit_string_to_atom("w"), do: {:ok, :weeks}
  defp unit_string_to_atom("week"), do: {:ok, :weeks}
  defp unit_string_to_atom("weeks"), do: {:ok, :weeks}
  defp unit_string_to_atom("d"), do: {:ok, :days}
  defp unit_string_to_atom("day"), do: {:ok, :days}
  defp unit_string_to_atom("days"), do: {:ok, :days}
  defp unit_string_to_atom("h"), do: {:ok, :hours}
  defp unit_string_to_atom("hour"), do: {:ok, :hours}
  defp unit_string_to_atom("hours"), do: {:ok, :hours}
  defp unit_string_to_atom("m"), do: {:ok, :minutes}
  defp unit_string_to_atom("min"), do: {:ok, :minutes}
  defp unit_string_to_atom("minute"), do: {:ok, :minutes}
  defp unit_string_to_atom("minutes"), do: {:ok, :minutes}
  defp unit_string_to_atom("s"), do: {:ok, :seconds}
  defp unit_string_to_atom("sec"), do: {:ok, :seconds}
  defp unit_string_to_atom("second"), do: {:ok, :seconds}
  defp unit_string_to_atom("seconds"), do: {:ok, :seconds}
  defp unit_string_to_atom("ms"), do: {:ok, :milliseconds}
  defp unit_string_to_atom("millisecond"), do: {:ok, :milliseconds}
  defp unit_string_to_atom("milliseconds"), do: {:ok, :milliseconds}
  defp unit_string_to_atom(_unknown_unit), do: {:error, :invalid_unit}

  @spec add_duration(DateTime.t(), Types.duration()) :: DateTime.t()
  defp add_duration(datetime, %{milliseconds: ms} = duration) when ms > 0 do
    total_ms = Predicator.Duration.to_milliseconds(duration)
    DateTime.add(datetime, total_ms, :millisecond)
  end

  defp add_duration(datetime, duration) do
    total_seconds = Predicator.Duration.to_seconds(duration)
    DateTime.add(datetime, total_seconds, :second)
  end

  @spec subtract_duration(DateTime.t(), Types.duration()) :: DateTime.t()
  defp subtract_duration(datetime, %{milliseconds: ms} = duration) when ms > 0 do
    total_ms = Predicator.Duration.to_milliseconds(duration)
    DateTime.add(datetime, -total_ms, :millisecond)
  end

  defp subtract_duration(datetime, duration) do
    total_seconds = Predicator.Duration.to_seconds(duration)
    DateTime.add(datetime, -total_seconds, :second)
  end
end
