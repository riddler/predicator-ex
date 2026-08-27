defmodule Predicator.Types do
  @moduledoc """
  Core type definitions for the Predicator library.

  This module defines all the fundamental types used throughout the
  Predicator system for instructions, evaluation contexts, and results.
  """

  @typedoc """
  A duration representing a time span.

  Duration is represented as a map with fields for different time units. All
  eight keys are always present; an unspecified unit is `0`.
  - `years` - number of years (default: 0)
  - `months` - number of months (default: 0)
  - `weeks` - number of weeks (default: 0)
  - `days` - number of days (default: 0)
  - `hours` - number of hours (default: 0)
  - `minutes` - number of minutes (default: 0)
  - `seconds` - number of seconds (default: 0)
  - `milliseconds` - number of milliseconds (default: 0)

  ## Examples

  3 days 8 hours. Every unit the expression did not name is present and `0`,
  so the map is always this wide:

      %{years: 0, months: 0, weeks: 0, days: 3,
        hours: 8, minutes: 0, seconds: 0, milliseconds: 0}

  Build one with `Predicator.Duration.new/1` rather than writing the literal,
  which fills the units you omit:

      Predicator.Duration.new(weeks: 2)
      Predicator.Duration.new(minutes: 30)
  """
  @type duration :: %{
          years: non_neg_integer(),
          months: non_neg_integer(),
          weeks: non_neg_integer(),
          days: non_neg_integer(),
          hours: non_neg_integer(),
          minutes: non_neg_integer(),
          seconds: non_neg_integer(),
          milliseconds: non_neg_integer()
        }

  @typedoc """
  A single value that can be used in predicates.

  Values can be:
  - `boolean()` - true/false values
  - `integer()` - integer numeric values
  - `float()` - floating-point numeric values
  - `binary()` - string values
  - `list()` - lists of values
  - `Date.t()` - date values
  - `DateTime.t()` - datetime values
  - `duration()` - duration values for time spans
  - `:undefined` - represents an absence: an unbound variable or a value that
    could not be produced; see `Predicator.Undefined` for the canonical
    definition of the sentinel
  - `nil` - the null value: present, but with no content. Distinct from
    `:undefined`, which is an absence. `nil === :undefined` is `false`.
  """
  @type value ::
          boolean()
          | integer()
          | float()
          | binary()
          | list()
          | Date.t()
          | DateTime.t()
          | duration()
          | :undefined
          | nil

  @typedoc """
  The evaluation context containing variable bindings.

  Context maps variable names (strings or atoms) to their values.
  Both string and atom keys are supported for flexibility.

  ## Examples

      %{"limit" => 85, "name" => "Alice"}
      %{limit: 85, name: "Alice"}
  """
  @type context :: %{required(binary() | atom()) => value()}

  @typedoc """
  A single instruction in the stack machine.

  Instructions are lists where the first element is the operation name
  and remaining elements are arguments. The full opcode set - every
  instruction the evaluator accepts, its operands, stack effect, and error
  semantics - is specified in [`docs/isa.md`](../../docs/isa.md).

  No instruction carries a source position. Positions travel in a separate
  `t:position_table/0`, produced alongside the instruction list by
  `Predicator.Compiler.to_instructions_with_positions/2` and available as
  `compiled.positions` on the `t:Predicator.Compiled.t/0` that
  `Predicator.compile_with_positions/1` returns, so the instruction format
  stays exactly what the Ruby and JavaScript siblings interchange (ADR-0001).
  That side table holds `t:span/0` values instead when the AST was parsed with
  `spans: true`; the instruction format is unaffected either way.

  ## Examples

      ["lit", 42]           # Push literal 42 onto stack
      ["load", "limit"]     # Load variable 'limit' from context
      ["compare", "GT"]     # Pop two values, compare with >, push result
  """
  @type instruction :: [binary() | value()]

  @typedoc """
  A list of instructions that form a complete program.

  Instructions are executed in order by the stack machine.
  """
  @type instruction_list :: [instruction()]

  @typedoc """
  A source position: 1-based line and column of the token that defines an AST
  node.
  """
  @type position :: {line :: pos_integer(), column :: pos_integer()}

  @typedoc """
  Maps a 0-based instruction index to the source position of the AST node that
  emitted it. Produced by `Predicator.Compiler.to_instructions_with_positions/2`
  and carried as `compiled.positions` on the `t:Predicator.Compiled.t/0` that
  `Predicator.compile_with_positions/1` returns; never part of the instruction
  list itself, so interchange and stored compiled artifacts are unaffected.
  """
  @type position_table :: %{non_neg_integer() => position()}

  @typedoc """
  A source span: the start and end of the source text an AST node covers.

  The end is **exclusive** - it names the position one past the last character -
  so on a single line `end_column - start_column` is the span's length, matching
  LSP ranges. The identifier `limit` at line 1 column 1 spans
  `{{1, 1}, {1, 6}}`.

  A span composes two `t:position/0` values; a point position and a span answer
  different questions, and both are available. See
  `Predicator.Parser.parse/2`'s `:spans` option.
  """
  @type span :: {start :: position(), end_exclusive :: position()}

  @typedoc """
  Maps a 0-based instruction index to the span of the AST node that emitted it.

  The span-mode counterpart of `t:position_table/0`, produced by
  `Predicator.Compiler.to_instructions_with_positions/2` from an AST parsed with
  `spans: true`, and carried as `compiled.positions` on the
  `t:Predicator.Compiled.t/0` that `Predicator.compile_with_spans/1` returns.
  Like the position table it is never part of the instruction list, so
  interchange and stored compiled artifacts are unaffected.
  """
  @type span_table :: %{non_neg_integer() => span()}

  @typedoc """
  Maps a `["store", n]` instruction's 0-based index to one source annotation
  per location segment in the assignment's lhs chain, root-first.

  A segment's annotation is `nil` when the node that produced it carried none;
  otherwise it is a `t:position/0` or a `t:span/0`, matching whichever mode
  `t:position_table/0` or `t:span_table/0` is in for the same compile. Produced
  by `Predicator.Compiler.to_instructions_with_segment_positions/2` and carried
  as `compiled.segment_positions` on the `t:Predicator.Compiled.t/0` that
  returns it. Like `position_table/0` this is never part of the instruction
  list, so interchange and stored compiled artifacts are unaffected.
  """
  @type segment_position_table :: %{
          non_neg_integer() => [position() | span() | nil]
        }

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

  Delegates to `Predicator.Undefined.undefined?/1` - see that module for the
  canonical definition of the `:undefined` sentinel.

  ## Examples

      iex> Predicator.Types.undefined?(:undefined)
      true

      iex> Predicator.Types.undefined?(42)
      false
  """
  @spec undefined?(value()) :: boolean()
  def undefined?(value), do: Predicator.Undefined.undefined?(value)

  @doc """
  Checks if two values have matching types for operations.

  Two values have matching types if they are both:
  - integers
  - booleans
  - binaries (strings)
  - lists
  - maps (objects)
  - dates
  - datetimes

  ## Examples

      iex> Predicator.Types.types_match?(1, 2)
      true

      iex> Predicator.Types.types_match?("hello", "world")
      true

      iex> Predicator.Types.types_match?(%{a: 1}, %{b: 2})
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

  def types_match?(a, b) when is_map(a) and is_map(b) and not is_struct(a) and not is_struct(b),
    do: true

  def types_match?(_a, _b), do: false
end
