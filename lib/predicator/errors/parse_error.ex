defmodule Predicator.Errors.ParseError do
  @moduledoc """
  Error struct for parse errors in Predicator expressions.

  This error occurs when the input expression cannot be parsed due to syntax errors.

  ## Fields

  - `message` - Human-readable error description
  - `line` - Line number where the error occurred
  - `column` - Column number where the error occurred

  ## Examples

      %Predicator.Errors.ParseError{
        message: "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found '>' at line 1, column 10",
        line: 1,
        column: 10
      }
  """

  @enforce_keys [:message, :line, :column]
  defstruct [:message, :line, :column]

  @type t :: %__MODULE__{
          message: binary(),
          line: pos_integer(),
          column: pos_integer()
        }

  @doc """
  Creates a parse error.
  """
  @spec new(binary(), pos_integer(), pos_integer()) :: t()
  def new(message, line, column) do
    %__MODULE__{
      message: message,
      line: line,
      column: column
    }
  end
end
