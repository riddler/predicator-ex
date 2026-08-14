defmodule Predicator.Errors.ParseError do
  @moduledoc """
  Error struct for parse errors in Predicator expressions.

  This error occurs when the input expression cannot be parsed due to syntax errors.

  ## Fields

  - `message` - Human-readable error description. Never contains the
    location - that is always `:position`
  - `position` - `{line, column}` of the syntax error, typed
    `t:Predicator.Types.position/0` so generic error-reporting code can read a
    position uniformly across `ParseError`, `EvaluationError`,
    `TypeMismatchError`, and `UndefinedVariableError`

  ## Examples

      %Predicator.Errors.ParseError{
        message: "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found '>'",
        position: {1, 10}
      }
  """

  @enforce_keys [:message, :position]
  defstruct [:message, :position]

  @type t :: %__MODULE__{
          message: binary(),
          position: Predicator.Types.position()
        }

  @doc """
  Creates a parse error.

  Takes the line and column separately because that is the shape
  `Predicator.Lexer.tokenize/1` and `Predicator.Parser.parse/2` report failures
  in; the struct stores them as a single `:position` tuple.
  """
  @spec new(binary(), pos_integer(), pos_integer()) :: t()
  def new(message, line, column) do
    %__MODULE__{message: message, position: {line, column}}
  end
end
