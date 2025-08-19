defmodule Predicator.Types do
  @moduledoc """
  Core type definitions for the Predicator library.

  This module defines all the fundamental types used throughout the
  Predicator system for instructions, evaluation contexts, and results.
  """

  @typedoc """
  A single value that can be used in predicates.

  Values can be:
  - `boolean()` - true/false values
  - `integer()` - numeric values  
  - `binary()` - string values
  - `list()` - lists of values
  - `:undefined` - represents undefined/null values
  """
  @type value :: boolean() | integer() | binary() | list() | :undefined

  @typedoc """
  The evaluation context containing variable bindings.

  Context maps variable names (strings or atoms) to their values.
  Both string and atom keys are supported for flexibility.

  ## Examples

      %{"score" => 85, "name" => "Alice"}
      %{score: 85, name: "Alice"} 
  """
  @type context :: %{required(binary() | atom()) => value()}

  @typedoc """
  A single instruction in the stack machine.

  Instructions are lists where the first element is the operation name
  and remaining elements are arguments.

  Currently supported instructions:
  - `["lit", value()]` - Push literal value onto stack  
  - `["load", binary()]` - Load variable from context onto stack
  - `["compare", binary()]` - Compare top two stack values with operator
  - `["and"]` - Logical AND of top two boolean values
  - `["or"]` - Logical OR of top two boolean values  
  - `["not"]` - Logical NOT of top boolean value

  ## Examples

      ["lit", 42]           # Push literal 42 onto stack
      ["load", "score"]     # Load variable 'score' from context
      ["compare", "GT"]     # Pop two values, compare with >, push result
      ["and"]               # Pop two boolean values, push AND result
      ["or"]                # Pop two boolean values, push OR result
      ["not"]               # Pop one boolean value, push NOT result
  """
  @type instruction :: [binary() | value()]

  @typedoc """
  A list of instructions that form a complete program.

  Instructions are executed in order by the stack machine.
  """
  @type instruction_list :: [instruction()]

  @typedoc """
  The result of evaluating a predicate.

  Returns:
  - `boolean()` - the final evaluation result
  - `{:error, term()}` - evaluation error with details
  """
  @type result :: boolean() | {:error, term()}

  @typedoc """
  The internal state of the stack machine evaluator.

  Contains:
  - `instructions` - list of instructions to execute
  - `instruction_pointer` - current position in instruction list
  - `stack` - evaluation stack (top element is head of list)
  - `context` - variable bindings
  - `halted` - whether execution has stopped
  """
  @type evaluator_state :: %{
          instructions: instruction_list(),
          instruction_pointer: non_neg_integer(),
          stack: [value()],
          context: context(),
          halted: boolean()
        }

  @doc """
  Checks if a value is undefined.

  ## Examples

      iex> Predicator.Types.undefined?(:undefined)
      true

      iex> Predicator.Types.undefined?(42)
      false
  """
  @spec undefined?(value()) :: boolean()
  def undefined?(value), do: value == :undefined

  @doc """
  Checks if two values have matching types for operations.

  Two values have matching types if they are both:
  - integers
  - booleans  
  - binaries (strings)
  - lists

  ## Examples

      iex> Predicator.Types.types_match?(1, 2)
      true

      iex> Predicator.Types.types_match?("hello", "world")
      true

      iex> Predicator.Types.types_match?(1, "hello")
      false
  """
  @spec types_match?(value(), value()) :: boolean()
  def types_match?(a, b) when is_integer(a) and is_integer(b), do: true
  def types_match?(a, b) when is_boolean(a) and is_boolean(b), do: true
  def types_match?(a, b) when is_binary(a) and is_binary(b), do: true
  def types_match?(a, b) when is_list(a) and is_list(b), do: true
  def types_match?(_a, _b), do: false
end
