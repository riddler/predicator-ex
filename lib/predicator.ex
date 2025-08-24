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

  ## Architecture

  Predicator uses a stack-based evaluation model:
  1. Instructions are processed sequentially
  2. Each instruction manipulates a stack
  3. The final result is the top value on the stack when execution completes
  """

  alias Predicator.{Compiler, Evaluator, Lexer, Parser, Types}
  alias Predicator.Errors.{ParseError, UndefinedVariableError}

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

      # Error handling
      iex> {:error, error} = Predicator.evaluate("score + 'hello'", %{"score" => 5})
      iex> error.message
      "Arithmetic add requires integers, got 5 (integer) and \\\"hello\\\" (string)"
      iex> error.expected
      :integer
  """
  @spec evaluate(
          binary() | Types.instruction_list(),
          Types.context(),
          keyword()
        ) :: {:ok, Types.value()} | {:error, struct()}
  def evaluate(input, context \\ %{}, opts \\ [])

  def evaluate(expression, context, opts) when is_binary(expression) and is_map(context) do
    case Lexer.tokenize(expression) do
      {:ok, tokens} ->
        case Parser.parse(tokens) do
          {:ok, ast} ->
            instructions = Compiler.to_instructions(ast)
            evaluate_instructions(instructions, context, opts)

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
  defp evaluate_instructions(instructions, context, opts) do
    case Evaluator.evaluate(instructions, context, opts) do
      {:error, error_struct} when is_struct(error_struct) ->
        {:error, error_struct}

      :undefined ->
        # Check if this was an undefined variable access
        case check_for_undefined_variables(instructions, context) do
          {:error, error_struct} -> {:error, error_struct}
          {:ok, :undefined} -> {:ok, :undefined}
        end

      result ->
        {:ok, result}
    end
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

  # Helper to detect undefined variable access
  defp check_for_undefined_variables([["load", variable_name]], context)
       when is_binary(variable_name) do
    if Map.has_key?(context, variable_name) or
         variable_has_atom_key?(context, variable_name) do
      # Variable exists but has :undefined value
      {:ok, :undefined}
    else
      {:error, UndefinedVariableError.new(variable_name)}
    end
  end

  defp check_for_undefined_variables(_instructions, _context) do
    # Complex expression resulted in :undefined
    {:ok, :undefined}
  end

  # Helper to safely check for atom key without raising exceptions
  defp variable_has_atom_key?(context, variable_name) do
    atom_key = String.to_atom(variable_name)
    Map.has_key?(context, atom_key)
  rescue
    ArgumentError -> false
    SystemLimitError -> false
  end

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
      {:error, "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found end of input at line 1, column 8"}
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
  Parses an expression string into an Abstract Syntax Tree.

  ## Examples

      iex> Predicator.parse("score > 85")
      {:ok, {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}}
  """
  @spec parse(binary()) :: {:ok, Parser.ast()} | {:error, binary(), pos_integer(), pos_integer()}
  def parse(expression) when is_binary(expression) do
    case Lexer.tokenize(expression) do
      {:ok, tokens} -> Parser.parse(tokens)
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

      iex> ast = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      iex> Predicator.decompile(ast)
      "score > 85"

      iex> ast = {:literal, 42}
      iex> Predicator.decompile(ast)
      "42"

      iex> ast = {:comparison, :eq, {:identifier, "active"}, {:literal, true}}
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
end
