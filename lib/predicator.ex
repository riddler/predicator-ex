defmodule Predicator do
  @moduledoc """
  A secure, non-evaluative condition engine for processing end-user boolean predicates.

  Predicator transforms string conditions into executable instructions that can be
  safely evaluated without direct code execution. It uses a stack-based virtual machine
  to process instructions and supports flexible context-based condition checking.

  ## Basic Usage

  The simplest way to use Predicator is with the `evaluate/2` function:

      iex> instructions = [["lit", 42]]
      iex> Predicator.evaluate(instructions)
      {:ok, 42}

      iex> instructions = [["load", "score"]]
      iex> context = %{"score" => 85}
      iex> Predicator.evaluate(instructions, context)
      {:ok, 85}

  ## Instruction Format

  Instructions are lists where:
  - First element is the operation name (string)
  - Remaining elements are operation arguments

  Currently supported instructions:
  - `["lit", value]` - Push a literal value onto the stack
  - `["load", variable_name]` - Load a variable from context onto the stack
  - `["compare", operator]` - Compare top two stack values (GT, LT, EQ, GTE, LTE, NE)

  ## Context

  The context is a map containing variable bindings. Both string and atom keys
  are supported for flexibility:

      %{"score" => 85, "name" => "Alice"}
      %{score: 85, name: "Alice"}

  A bare map is merged with the builtin functions on every `evaluate/3` call -
  fine for one-off evaluation, wasteful when the same bindings are evaluated
  against repeatedly. `Predicator.Context.new/2` builds that merge once into a
  `%Predicator.Context{}`, which `evaluate/3` also accepts directly:

      iex> context = Predicator.Context.new(%{"score" => 85})
      iex> Predicator.evaluate("score > 80", context)
      {:ok, true}
      iex> context = Predicator.Context.bind(context, "score", 90)
      iex> Predicator.evaluate("score > 80", context)
      {:ok, true}

  A context also carries the unbound-variable policy. By default a load of an
  unbound root pushes the `:undefined` sentinel, which three-valued logic can
  absorb into a defined result; under `on_unbound: :error` the load fails
  instead, naming the variable:

      iex> context = Predicator.Context.new(%{}, on_unbound: :error)
      iex> {:error, error} = Predicator.evaluate("missing OR true", context)
      iex> error.variable
      "missing"

  The same option works on a bare map, which `evaluate/3` routes through
  `Predicator.Context.new/2`:

      iex> Predicator.evaluate("missing OR true", %{})
      {:ok, true}
      iex> {:error, error} = Predicator.evaluate("missing OR true", %{}, on_unbound: :error)
      iex> error.variable
      "missing"

  ## Architecture

  Predicator uses a stack-based evaluation model:
  1. Instructions are processed sequentially
  2. Each instruction manipulates a stack
  3. The final result is the top value on the stack when execution completes
  """

  alias Predicator.{
    Compiler,
    Context,
    ContextLocation,
    Errors,
    Evaluator,
    Instructions,
    Lexer,
    Parser,
    Types
  }

  alias Predicator.Errors.{ParseError, TypeMismatchError, UndefinedVariableError}

  @doc """
  Evaluates a predicate expression or instruction list.

  This is the main entry point for Predicator evaluation. It accepts either:
  - A string expression (e.g., "score > 85") which gets compiled automatically
  - A pre-compiled instruction list for maximum performance

  ## Parameters

  - `input` - String expression or instruction list to evaluate
  - `context` - Optional context map with variable bindings (default: `%{}`)
  - `opts` - Optional keyword list of options:
    - `:functions` - Map of custom functions to make available during evaluation
    - `:positions` - Source-position side table from
      `compile_with_positions/1`, or a source-span table from
      `compile_with_spans/1`, used to populate `:position` (and `:span`) on
      runtime errors. String input threads its own table automatically; an
      instruction-list caller who omits this sees `position: nil`.
    - `:spans` - when `true`, string input compiles with spans instead of point
      positions, so runtime errors carry `:span` and `:position` names the
      span's start. Ignored for instruction-list input, which has no source;
      such a caller passes `positions:` from `compile_with_spans/1` instead.

  ## Returns

  - `{:ok, result}` on successful evaluation
  - `{:error, error_struct}` if parsing or execution fails

  ## Error Types

  - `Predicator.Errors.TypeMismatchError` - Type mismatch in operation
  - `Predicator.Errors.UndefinedVariableError` - Variable not found in context
  - `Predicator.Errors.EvaluationError` - General evaluation error (division by zero, etc.)
  - `Predicator.Errors.ParseError` - Expression parsing error

  ## Examples

      # Simple expressions
      iex> Predicator.evaluate("true")
      {:ok, true}

      iex> Predicator.evaluate("2 + 3")
      {:ok, 5}

      # With context
      iex> Predicator.evaluate("score > 85", %{"score" => 90})
      {:ok, true}

      # With custom functions
      iex> custom_functions = %{"double" => {1, fn [n], _context -> {:ok, n * 2} end}}
      iex> Predicator.evaluate("double(21)", %{}, functions: custom_functions)
      {:ok, 42}

      # Pre-compiled instruction lists
      iex> Predicator.evaluate([["lit", 42]])
      {:ok, 42}

      # Type coercion with + operator (string concatenation)
      iex> Predicator.evaluate("score + 'hello'", %{"score" => 5})
      {:ok, "5hello"}

      # Error handling for incompatible types
      iex> {:error, error} = Predicator.evaluate("score * true", %{"score" => 5})
      iex> String.contains?(error.message, "multiply requires")
      true
  """
  @spec evaluate(
          binary() | Types.instruction_list(),
          Types.context() | Context.t(),
          keyword()
        ) :: {:ok, Types.value()} | {:error, struct()}
  def evaluate(input, context \\ %{}, opts \\ [])

  def evaluate(expression, context, opts) when is_binary(expression) and is_map(context) do
    case Lexer.tokenize(expression) do
      {:ok, tokens} ->
        case Parser.parse(tokens, opts) do
          {:ok, ast} ->
            {instructions, positions} = Compiler.to_instructions_with_positions(ast)
            evaluate_instructions(instructions, context, Keyword.put(opts, :positions, positions))

          {:error, message, line, column} ->
            {:error, ParseError.new(message, line, column)}
        end

      {:error, message, line, column} ->
        {:error, ParseError.new(message, line, column)}
    end
  end

  def evaluate(instructions, context, opts) when is_list(instructions) and is_map(context) do
    evaluate_instructions(instructions, context, opts)
  end

  # Helper function to evaluate instructions and convert errors to new format
  defp evaluate_instructions(instructions, %Context{} = context, opts) do
    evaluator = %Evaluator{
      instructions: instructions,
      context: context.data,
      functions: context.functions,
      positions: Keyword.get(opts, :positions, %{}),
      on_unbound: context.on_unbound
    }

    case Evaluator.run_prepared(evaluator) do
      {:error, error_struct, final_evaluator} when is_struct(error_struct) ->
        {:error, unbound_or_type_mismatch(error_struct, final_evaluator)}

      {:ok, :undefined, final_evaluator} ->
        undefined_result(final_evaluator)

      {:ok, result, _final_evaluator} ->
        {:ok, result}
    end
  end

  defp evaluate_instructions(instructions, context, opts) when is_map(context) do
    evaluate_instructions(instructions, Context.new(context, opts), opts)
  end

  @doc """
  Evaluates a predicate expression or instruction list, raising on errors.

  Similar to `evaluate/3` but raises an exception for error results instead
  of returning error tuples. Follows the Elixir convention of bang functions.

  ## Examples

      iex> Predicator.evaluate!("score > 85", %{"score" => 90})
      true

      iex> Predicator.evaluate!([["lit", 42]])
      42

      # With custom functions
      iex> custom_functions = %{"double" => {1, fn [n], _context -> {:ok, n * 2} end}}
      iex> Predicator.evaluate!("double(21)", %{}, functions: custom_functions)
      42

      # This would raise an exception:
      # Predicator.evaluate!("score >", %{})
  """
  @spec evaluate!(
          binary() | Types.instruction_list(),
          Types.context(),
          keyword()
        ) :: Types.value()
  def evaluate!(input, context \\ %{}, opts \\ []) do
    case evaluate(input, context, opts) do
      {:ok, result} -> result
      {:error, error_struct} -> raise "Evaluation failed: #{error_struct.message}"
    end
  end

  # An :undefined result is ambiguous on its own: it's either a genuinely
  # unbound root variable or a value that legitimately evaluates to
  # :undefined (a missing nested path, an out-of-bounds index, a type
  # mismatch). The evaluator records the unbound loads it actually executed,
  # so ask it rather than scanning the program - a load the short-circuit
  # jumps skipped is present in the instruction list but was never read, and
  # naming it would report a variable the author was entitled to leave
  # unbound (px-8um.8).
  @spec undefined_result(Evaluator.t()) :: {:ok, :undefined} | {:error, struct()}
  defp undefined_result(evaluator) do
    case Evaluator.unbound_loads_with_locations(evaluator) do
      [] -> {:ok, :undefined}
      [unbound_load | _rest] -> {:error, undefined_variable_error(unbound_load)}
    end
  end

  # An opcode that *rejects* an :undefined operand - not, unary_minus,
  # unary_bang, the five arithmetic opcodes, the legacy ["and"]/["or"] - errors
  # before evaluation ever produces an :undefined result, so undefined_result/1
  # never sees it and the caller gets a TypeMismatchError naming no variable at
  # all. When that operand came from a root the run loaded and did not find
  # bound, report the variable instead: the same answer "unbound > 5" already
  # gives, for the same cause (px-8um.7).
  #
  # Gated on both halves. A TypeMismatchError with no :undefined operand is an
  # ordinary type error ("name" * 5) and passes through; an :undefined operand
  # with no unbound load came from bound data (%{"b" => :undefined}) or a
  # missing nested path (user.nope), which is a genuine type mismatch on data
  # the caller supplied, and also passes through.
  #
  # The rewritten error is positioned at the variable's own load, not at the
  # rejecting operator: the operator's position went out with the
  # TypeMismatchError this replaces, along with the struct it was on. That is
  # the right trade - a caller's editor wants the caret on the variable, not
  # on the `+` or `not` that merely noticed it was undefined (px-1e1).
  @spec unbound_or_type_mismatch(struct(), Evaluator.t()) :: struct()
  defp unbound_or_type_mismatch(%TypeMismatchError{got: got} = error, evaluator) do
    with true <- undefined_operand?(got),
         [unbound_load | _rest] <- Evaluator.unbound_loads_with_locations(evaluator) do
      undefined_variable_error(unbound_load)
    else
      _no_rewrite -> error
    end
  end

  defp unbound_or_type_mismatch(error, _evaluator), do: error

  # `got` is a single type for a unary operation and a {left, right} tuple for
  # a binary one; either position may be the rejected :undefined operand.
  @spec undefined_operand?(term()) :: boolean()
  defp undefined_operand?(:undefined), do: true
  defp undefined_operand?({:undefined, _right}), do: true
  defp undefined_operand?({_left, :undefined}), do: true
  defp undefined_operand?(_got), do: false

  # The location is the raw positions-table entry the evaluator recorded at the
  # load - nil, a point position, or a span. Errors.put_position/2 discriminates
  # all three, setting :span as well when it is handed one, so nothing here has
  # to know which mode the program was compiled in.
  @spec undefined_variable_error(Evaluator.unbound_load()) :: UndefinedVariableError.t()
  defp undefined_variable_error({variable_name, location}) do
    variable_name
    |> UndefinedVariableError.new()
    |> Errors.put_position(location)
  end

  @doc """
  Returns the ISA version this build emits and can run.

  ISA versions are integers, independent of this library's semantic version
  (ADR-0003). Compare it against `Predicator.Instructions.required_isa/1`
  before running a stored instruction list, so a version mismatch is caught
  up front instead of failing partway through evaluation. See
  [`docs/isa.md`](../docs/isa.md) for the full versioning scheme.

  ## Examples

      iex> Predicator.isa_version()
      2
  """
  @spec isa_version() :: pos_integer()
  defdelegate isa_version(), to: Instructions

  @doc """
  Compiles a string expression to instruction list.

  This function allows you to pre-compile expressions for maximum performance
  when evaluating the same expression multiple times with different contexts.

  ## Parameters

  - `expression` - String expression to compile

  ## Returns

  - `{:ok, instructions}` - Successfully compiled instructions
  - `{:error, message}` - Parse error with details

  ## Examples

      iex> {:ok, instructions} = Predicator.compile("score > 85")
      iex> instructions
      [["load", "score"], ["lit", 85], ["compare", "GT"]]

      iex> Predicator.compile("score >")
      {:error, "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input at line 1, column 8"}
  """
  @spec compile(binary()) :: {:ok, Types.instruction_list()} | {:error, binary()}
  def compile(expression) when is_binary(expression) do
    case parse(expression) do
      {:ok, ast} ->
        instructions = Compiler.to_instructions(ast)
        {:ok, instructions}

      {:error, message, line, column} ->
        {:error, "#{message} at line #{line}, column #{column}"}
    end
  end

  @doc """
  Compiles a string expression to an instruction list plus a source-position
  side table.

  The instruction list is identical to `compile/1`'s; the table maps each
  instruction's 0-based index to the `{line, column}` of the AST node that
  emitted it. Pass it to `evaluate/3` as `positions:` to get positions on
  runtime errors from a pre-compiled program.

  ## Examples

      iex> {:ok, instructions, positions} = Predicator.compile_with_positions("score > 85")
      iex> instructions
      [["load", "score"], ["lit", 85], ["compare", "GT"]]
      iex> positions
      %{0 => {1, 1}, 1 => {1, 9}, 2 => {1, 7}}
  """
  @spec compile_with_positions(binary()) ::
          {:ok, Types.instruction_list(), Types.position_table()} | {:error, binary()}
  def compile_with_positions(expression) when is_binary(expression) do
    case parse(expression) do
      {:ok, ast} ->
        {instructions, positions} = Compiler.to_instructions_with_positions(ast)
        {:ok, instructions, positions}

      {:error, message, line, column} ->
        {:error, "#{message} at line #{line}, column #{column}"}
    end
  end

  @doc """
  Compiles a string expression to an instruction list plus a source-span side
  table.

  The instruction list is identical to `compile/1`'s; the table maps each
  instruction's 0-based index to the `t:Predicator.Types.span/0` of the AST node
  that emitted it. Pass it to `evaluate/3` as `positions:` to get spans on
  runtime errors from a pre-compiled program.

  ## Examples

      iex> {:ok, instructions, spans} = Predicator.compile_with_spans("score > 85")
      iex> instructions
      [["load", "score"], ["lit", 85], ["compare", "GT"]]
      iex> spans
      %{0 => {{1, 1}, {1, 6}}, 1 => {{1, 9}, {1, 11}}, 2 => {{1, 1}, {1, 11}}}
  """
  @spec compile_with_spans(binary()) ::
          {:ok, Types.instruction_list(), Types.span_table()} | {:error, binary()}
  def compile_with_spans(expression) when is_binary(expression) do
    case parse(expression, spans: true) do
      {:ok, ast} ->
        {instructions, spans} = Compiler.to_instructions_with_positions(ast)
        {:ok, instructions, spans}

      {:error, message, line, column} ->
        {:error, "#{message} at line #{line}, column #{column}"}
    end
  end

  @doc """
  Parses an expression string into an Abstract Syntax Tree.

  Every node carries a trailing `{line, column}` source position. Pass
  `spans: true` for a `t:Predicator.Types.span/0` in that slot instead - the
  source text the node covers, which is what a diagnostic underlines.

  ## Examples

      iex> Predicator.parse("score > 85")
      {:ok, {:comparison, :gt, {:identifier, "score", {1, 1}}, {:literal, 85, {1, 9}}, {1, 7}}}

      iex> Predicator.parse("score > 85", spans: true)
      {:ok, {:comparison, :gt, {:identifier, "score", {{1, 1}, {1, 6}}}, {:literal, 85, {{1, 9}, {1, 11}}}, {{1, 1}, {1, 11}}}}
  """
  @spec parse(binary(), keyword()) ::
          {:ok, Parser.ast()} | {:error, binary(), pos_integer(), pos_integer()}
  def parse(expression, opts \\ []) when is_binary(expression) do
    case Lexer.tokenize(expression) do
      {:ok, tokens} -> Parser.parse(tokens, opts)
      {:error, message, line, column} -> {:error, message, line, column}
    end
  end

  @doc """
  Converts an AST back to a string representation.

  This function takes an Abstract Syntax Tree and generates a readable string
  representation. This is useful for debugging, displaying expressions to users,
  and documentation purposes.

  ## Parameters

  - `ast` - The Abstract Syntax Tree to convert
  - `opts` - Optional formatting options:
    - `:parentheses` - `:minimal` (default) | `:explicit` | `:none`
    - `:spacing` - `:normal` (default) | `:compact` | `:verbose`

  ## Returns

  String representation of the AST

  ## Examples

      iex> ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      iex> Predicator.decompile(ast)
      "score > 85"

      iex> ast = {:literal, 42, nil}
      iex> Predicator.decompile(ast)
      "42"

      iex> ast = {:comparison, :eq, {:identifier, "active", nil}, {:literal, true, nil}, nil}
      iex> Predicator.decompile(ast, parentheses: :explicit, spacing: :verbose)
      "(active  =  true)"
  """
  @spec decompile(Parser.ast(), keyword()) :: binary()
  def decompile(ast, opts \\ []) do
    Compiler.to_string(ast, opts)
  end

  @doc """
  Compiles a string expression to instruction list, raising on errors.

  Similar to `compile/1` but raises an exception for parse errors.

  ## Examples

      iex> Predicator.compile!("score > 85")
      [["load", "score"], ["lit", 85], ["compare", "GT"]]
  """
  @spec compile!(binary()) :: Types.instruction_list()
  def compile!(expression) when is_binary(expression) do
    case compile(expression) do
      {:ok, instructions} -> instructions
      {:error, reason} -> raise "Compilation failed: #{reason}"
    end
  end

  @doc """
  Creates a new evaluator state for low-level instruction processing.

  This function is useful when you need fine-grained control over the
  evaluation process or want to inspect the evaluator state.

  ## Parameters

  - `instructions` - List of instructions to prepare for execution
  - `context` - Optional context map with variable bindings (default: `%{}`)

  ## Returns

  An `%Predicator.Evaluator{}` struct ready for execution.

  ## Examples

      iex> evaluator = Predicator.evaluator([["lit", 42]])
      iex> evaluator.instructions
      [["lit", 42]]

      iex> evaluator = Predicator.evaluator([["load", "x"]], %{"x" => 10})
      iex> evaluator.context
      %{"x" => 10}
  """
  @spec evaluator(Types.instruction_list(), Types.context()) :: Evaluator.t()
  def evaluator(instructions, context \\ %{}) when is_list(instructions) and is_map(context) do
    %Evaluator{
      instructions: instructions,
      context: context
    }
  end

  @doc """
  Runs an evaluator until completion.

  This provides direct access to the low-level evaluator API for cases
  where you need more control than the `execute/2` function provides.

  ## Parameters

  - `evaluator` - An `%Predicator.Evaluator{}` struct

  ## Returns

  - `{:ok, final_evaluator_state}` on success
  - `{:error, reason}` on failure

  ## Examples

      iex> evaluator = Predicator.evaluator([["lit", 42]])
      iex> {:ok, final_state} = Predicator.run_evaluator(evaluator)
      iex> final_state.stack
      [42]
  """
  @spec run_evaluator(Evaluator.t()) :: {:ok, Evaluator.t()} | {:error, term()}
  def run_evaluator(%Evaluator{} = evaluator) do
    Evaluator.run(evaluator)
  end

  @doc """
  Resolves a location path for assignment operations in SCXML datamodel expressions.

  Takes an expression string and returns a location path that can be used for
  assignment operations. Validates that the expression represents an assignable
  location (l-value) rather than a computed value.

  This function is specifically designed for SCXML `<assign location="...">` operations
  where the location attribute must specify where to assign a value in the datamodel.

  ## Location Path Format

  Location paths are returned as lists of keys/indices that represent the path
  to a specific location in the context data structure:

  - `["user"]` - top-level variable `user`
  - `["user", "name"]` - property access `user.name`
  - `["items", 0]` - array access `items[0]`
  - `["user", "profile", "settings", "theme"]` - nested `user.profile.settings.theme`

  ## Assignable vs Non-Assignable

  **Assignable (valid locations):**
  - Simple identifiers: `user`
  - Property access: `user.name`, `obj.prop`
  - Bracket access: `items[0]`, `obj["key"]`
  - Mixed notation: `user.items[0].name`

  **Non-Assignable (invalid locations):**
  - Literals: `42`, `"string"`, `true`
  - Function calls: `len(items)`, `upper(name)`
  - Arithmetic expressions: `user.age + 1`
  - Any computed values

  ## Parameters

  - `expression` - The location expression string to resolve
  - `context` - The evaluation context (used for resolving variable keys)
  - `opts` - Options (currently unused, reserved for future extensions)

  ## Examples

      # Simple identifier
      iex> Predicator.context_location("user", %{"user" => %{"name" => "John"}})
      {:ok, ["user"]}

      # Property access
      iex> Predicator.context_location("user.name", %{"user" => %{"name" => "John"}})
      {:ok, ["user", "name"]}

      # Bracket access with literal key
      iex> Predicator.context_location("items[0]", %{"items" => [1, 2, 3]})
      {:ok, ["items", 0]}

      # Bracket access with string key
      iex> Predicator.context_location("user['profile']", %{"user" => %{"profile" => %{}}})
      {:ok, ["user", "profile"]}

      # Mixed notation
      iex> Predicator.context_location("data.users[0]['name']", %{"data" => %{"users" => [%{"name" => "Alice"}]}})
      {:ok, ["data", "users", 0, "name"]}

      # Variable as bracket key
      iex> Predicator.context_location("items[index]", %{"items" => [1, 2, 3], "index" => 1})
      {:ok, ["items", 1]}

      # Error: cannot assign to literal
      iex> {:error, %Predicator.Errors.LocationError{type: :not_assignable}} =
      ...>   Predicator.context_location("42", %{})

      # Error: cannot assign to function call
      iex> {:error, %Predicator.Errors.LocationError{type: :not_assignable}} =
      ...>   Predicator.context_location("len(items)", %{"items" => [1, 2, 3]})

      # Error: cannot assign to computed expression
      iex> {:error, %Predicator.Errors.LocationError{type: :not_assignable}} =
      ...>   Predicator.context_location("user.age + 1", %{"user" => %{"age" => 30}})

  ## SCXML Usage Example

      # In an SCXML state machine
      location_expr = "user.profile.settings['theme']"

      case Predicator.context_location(location_expr, datamodel_context) do
        {:ok, path} ->
          # Use path for assignment: ["user", "profile", "settings", "theme"]
          update_datamodel_at_path(datamodel, path, new_value)

        {:error, %Predicator.Errors.LocationError{} = error} ->
          # Handle invalid assignment target
          {:error, "Invalid assignment location: \#{error.message}"}
      end

  """
  @spec context_location(binary(), Types.context(), keyword()) ::
          {:ok, ContextLocation.location_path()} | {:error, struct()}
  def context_location(expression, context \\ %{}, _opts \\ [])
      when is_binary(expression) and is_map(context) do
    ContextLocation.resolve_expression(expression, context)
  end

  @doc """
  Assigns `value` at the location `expression` names within `context`.

  Resolves the location expression the same way `context_location/3` does, then
  writes through `Predicator.ContextLocation.put/3`, creating any missing
  intermediate maps and lists. See `Predicator.ContextLocation.put/3` for the
  full auto-vivification and collision rules.

  The expression is resolved against the *pre-assignment* context, which matches
  SCXML: a variable bracket key such as `items[index]` reads `index` as it stands
  before the write.

  > #### Argument order {: .info}
  >
  > `context` comes first because this function *transforms* a context and
  > returns a new one, which makes it pipeline-friendly, whereas
  > `context_location/3` merely inspects one.

  ## Parameters

  - `context` - The context map to write into
  - `expression` - The location expression naming where to write
  - `value` - The value to write
  - `opts` - Reserved for future options

  ## Returns

  - `{:ok, context}` - The updated context
  - `{:error, %Predicator.Errors.LocationError{}}` - The expression is not an
    assignable location, or the write collided with existing data
  - `{:error, %Predicator.Errors.ParseError{}}` - The expression did not parse

  ## Examples

      iex> Predicator.context_assign(%{}, "user.profile.name", "Ada")
      {:ok, %{"user" => %{"profile" => %{"name" => "Ada"}}}}

      iex> Predicator.context_assign(%{"items" => [1, 2, 3]}, "items[1]", "x")
      {:ok, %{"items" => [1, "x", 3]}}

      iex> {:error, error} = Predicator.context_assign(%{}, "len(items)", 1)
      iex> error.type
      :not_assignable

  """
  @spec context_assign(Types.context(), binary(), term(), keyword()) ::
          {:ok, Types.context()} | {:error, struct()}
  def context_assign(context, expression, value, opts \\ [])
      when is_map(context) and is_binary(expression) do
    case context_location(expression, context, opts) do
      {:ok, path} -> ContextLocation.put(context, path, value)
      {:error, _error} = error -> error
    end
  end
end
