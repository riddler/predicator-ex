defmodule Predicator do
  @moduledoc """
  A secure, non-evaluative condition engine for processing end-user boolean predicates.

  Predicator transforms string conditions into executable instructions that can be
  safely evaluated without direct code execution. It uses a stack-based virtual machine
  to process instructions and supports flexible context-based condition checking.

  ## Basic Usage

  The simplest way to use Predicator is with the `execute/2` function:

      iex> instructions = [["lit", 42]]
      iex> Predicator.execute(instructions)
      42

      iex> instructions = [["load", "score"]]
      iex> context = %{"score" => 85}
      iex> Predicator.execute(instructions, context)
      85

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

  @doc """
  Evaluates a predicate expression or instruction list with an optional context.

  This is the main entry point for Predicator evaluation. It accepts either:
  - A string expression (e.g., "score > 85") which gets compiled automatically
  - A pre-compiled instruction list for maximum performance

  ## Parameters

  - `input` - String expression or instruction list
  - `context` - Optional context map with variable bindings (default: `%{}`)

  ## Returns

  - The evaluation result (boolean, value, or `:undefined`)
  - `{:error, reason}` if parsing or execution fails

  ## Examples

      # String expressions (compiled automatically)
      iex> Predicator.evaluate("score > 85", %{"score" => 90})
      true

      iex> Predicator.evaluate("name = \\"John\\"", %{"name" => "John"})
      true

      iex> Predicator.evaluate("age >= 18", %{"age" => 16})
      false

      # Pre-compiled instruction lists (maximum performance)
      iex> Predicator.evaluate([["load", "score"], ["lit", 85], ["compare", "GT"]], %{"score" => 90})
      true

      iex> Predicator.evaluate([["lit", 42]])
      42

      # Parse errors are returned  
      iex> Predicator.evaluate("score >", %{})
      {:error, "Expected number, string, boolean, identifier, or '(' but found end of input at line 1, column 8"}
  """
  @spec evaluate(binary() | Types.instruction_list(), Types.context()) :: Types.result()
  def evaluate(input, context \\ %{})

  def evaluate(expression, context) when is_binary(expression) and is_map(context) do
    with {:ok, tokens} <- Lexer.tokenize(expression),
         {:ok, ast} <- Parser.parse(tokens) do
      instructions = Compiler.to_instructions(ast)
      Evaluator.evaluate(instructions, context)
    else
      {:error, message, line, column} -> {:error, "#{message} at line #{line}, column #{column}"}
    end
  end

  def evaluate(instructions, context) when is_list(instructions) and is_map(context) do
    Evaluator.evaluate(instructions, context)
  end

  @doc """
  Evaluates a predicate expression or instruction list, raising on errors.

  Similar to `evaluate/2` but raises an exception for error results instead
  of returning error tuples. Follows the Elixir convention of bang functions.

  ## Examples

      iex> Predicator.evaluate!("score > 85", %{"score" => 90})
      true

      iex> Predicator.evaluate!([["lit", 42]])
      42

      # This would raise an exception:
      # Predicator.evaluate!("score >", %{})
  """
  @spec evaluate!(binary() | Types.instruction_list(), Types.context()) ::
          boolean() | Types.value()
  def evaluate!(input, context \\ %{}) do
    case evaluate(input, context) do
      {:error, reason} -> raise "Evaluation failed: #{reason}"
      result -> result
    end
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
      {:error, "Expected number, string, boolean, identifier, or '(' but found end of input at line 1, column 8"}
  """
  @spec compile(binary()) :: {:ok, Types.instruction_list()} | {:error, binary()}
  def compile(expression) when is_binary(expression) do
    with {:ok, tokens} <- Lexer.tokenize(expression),
         {:ok, ast} <- Parser.parse(tokens) do
      instructions = Compiler.to_instructions(ast)
      {:ok, instructions}
    else
      {:error, message, line, column} -> {:error, "#{message} at line #{line}, column #{column}"}
    end
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
  Executes a list of instructions with an optional context.

  This is the main entry point for evaluating predicator instructions.
  Instructions are executed in order using a stack machine, and the
  final result is returned.

  ## Parameters

  - `instructions` - List of instructions to execute
  - `context` - Optional context map with variable bindings (default: `%{}`)

  ## Returns

  - The final value from the top of the stack
  - `{:error, reason}` if execution fails

  ## Examples

      # Literal values
      iex> Predicator.execute([["lit", 42]])
      42

      iex> Predicator.execute([["lit", true]])
      true

      # Loading from context
      iex> Predicator.execute([["load", "score"]], %{"score" => 85})
      85

      # Missing variables return :undefined
      iex> Predicator.execute([["load", "missing"]], %{})
      :undefined

      # Multiple instructions (last value wins)
      iex> instructions = [["lit", 1], ["lit", 2], ["lit", 3]]
      iex> Predicator.execute(instructions)
      3

      # Comparison operations  
      iex> instructions = [["load", "score"], ["lit", 85], ["compare", "GT"]]
      iex> Predicator.execute(instructions, %{"score" => 90})
      true

      iex> instructions = [["load", "age"], ["lit", 18], ["compare", "GTE"]]
      iex> Predicator.execute(instructions, %{"age" => 16})
      false
  """
  @spec execute(Types.instruction_list(), Types.context()) :: Types.result()
  def execute(instructions, context \\ %{}) when is_list(instructions) and is_map(context) do
    Evaluator.evaluate(instructions, context)
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
