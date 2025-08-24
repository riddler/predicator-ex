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
  - `Date.t()` - date values
  - `DateTime.t()` - datetime values
  - `:undefined` - represents undefined/null values
  """
  @type value :: boolean() | integer() | binary() | list() | Date.t() | DateTime.t() | :undefined

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
  - `["in"]` - Membership test (element in collection)
  - `["contains"]` - Membership test (collection contains element)
  - `["add"]` - Pop two values, add them, push result
  - `["subtract"]` - Pop two values, subtract them, push result
  - `["multiply"]` - Pop two values, multiply them, push result
  - `["divide"]` - Pop two values, divide them, push result
  - `["modulo"]` - Pop two values, modulo operation, push result
  - `["unary_minus"]` - Pop one value, negate it, push result
  - `["unary_bang"]` - Pop one value, logical NOT it, push result
  - `["bracket_access"]` - Pop key and object, push object[key] result
  - `["call", binary(), integer()]` - Call built-in function with arguments from stack

  ## Examples

      ["lit", 42]           # Push literal 42 onto stack
      ["load", "score"]     # Load variable 'score' from context
      ["compare", "GT"]     # Pop two values, compare with >, push result
      ["and"]               # Pop two boolean values, push AND result
      ["or"]                # Pop two boolean values, push OR result
      ["not"]               # Pop one boolean value, push NOT result
      ["add"]               # Pop two values, add them, push result
      ["subtract"]          # Pop two values, subtract them, push result
      ["multiply"]          # Pop two values, multiply them, push result
      ["divide"]            # Pop two values, divide them, push result
      ["modulo"]            # Pop two values, modulo them, push result
      ["unary_minus"]       # Pop one value, negate it, push result
      ["unary_bang"]        # Pop one value, logical NOT it, push result
      ["bracket_access"]    # Pop key and object, push object[key]
      ["call", "len", 1]    # Pop 1 argument, call len function, push result
  """
  @type instruction :: [binary() | value()]

  @typedoc """
  A list of instructions that form a complete program.

  Instructions are executed in order by the stack machine.
  """
  @type instruction_list :: [instruction()]

  @typedoc """
  The result of evaluating a predicate from public API functions.

  Returns:
  - `{:ok, value()}` - successful evaluation with result value
  - `{:error, term()}` - evaluation error with details
  """
  @type result :: {:ok, value()} | {:error, term()}

  @typedoc """
  The internal result of evaluating a predicate from Evaluator functions.

  Returns:
  - `value()` - the final evaluation result value
  - `{:error, term()}` - evaluation error with details
  """
  @type internal_result :: value() | {:error, term()}

  @typedoc """
  SCXML-compatible error result for enhanced error handling.

  Returns structured error information for SCXML datamodel compatibility:
  - `{:error, :undefined_variable, %{variable: binary()}}` - Variable not found in context
  - `{:error, :type_mismatch, %{expected: atom(), got: atom()}}` - Type mismatch in operation
  - `{:error, :invalid_location, %{expression: binary()}}` - Invalid assignment target
  - `{:error, :evaluation_error, %{reason: binary()}}` - General evaluation error
  - `{:error, :parse_error, %{message: binary(), line: integer(), column: integer()}}` - Parse error
  """
  @type scxml_error ::
          {:error, :undefined_variable, %{variable: binary()}}
          | {:error, :type_mismatch, %{expected: atom(), got: atom()}}
          | {:error, :invalid_location, %{expression: binary()}}
          | {:error, :evaluation_error, %{reason: binary()}}
          | {:error, :parse_error, %{message: binary(), line: integer(), column: integer()}}

  @typedoc """
  SCXML-compatible result type for value expressions.

  Returns:
  - `{:ok, value()}` - successful evaluation with result value
  - `scxml_error()` - structured error with SCXML-compatible details
  """
  @type scxml_result :: {:ok, value()} | scxml_error()

  @typedoc """
  Location path for assignment expressions.

  Represents the path to an assignable location in nested data structures:
  - Simple property: `["user", "name"]`
  - Array index: `["items", 0, "price"]` 
  - Dynamic property: `["user", "settings", "theme"]` (for `user.settings["theme"]`)
  """
  @type location_path :: [binary() | non_neg_integer()]

  @typedoc """
  Result type for location expression evaluation.

  Returns:
  - `{:ok, location_path()}` - valid assignment path
  - `scxml_error()` - error if location is not assignable
  """
  @type location_result :: {:ok, location_path()} | scxml_error()

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
  - dates
  - datetimes

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
  def types_match?(%Date{} = _a, %Date{} = _b), do: true
  def types_match?(%DateTime{} = _a, %DateTime{} = _b), do: true
  def types_match?(_a, _b), do: false
end
