defmodule Predicator.Errors.UndefinedVariableError do
  @moduledoc """
  Error struct for undefined variable errors in Predicator evaluation.

  This error occurs when trying to access a variable that doesn't exist in the evaluation context.

  ## Fields

  - `message` - Human-readable error description
  - `variable` - The name of the undefined variable
  - `position` - `{line, column}` of the source token that produced the failing
    instruction, when a position table was available (optional)

  ## Examples

      %Predicator.Errors.UndefinedVariableError{
        message: "Undefined variable: score",
        variable: "score"
      }

      %Predicator.Errors.UndefinedVariableError{
        message: "Undefined variable: user.profile.settings",
        variable: "user.profile.settings"
      }
  """

  @enforce_keys [:message, :variable]
  defstruct [:message, :variable, :position]

  @type t :: %__MODULE__{
          message: binary(),
          variable: binary(),
          position: Predicator.Types.position() | nil
        }

  @doc """
  Creates an undefined variable error.
  """
  @spec new(binary()) :: t()
  def new(variable) do
    %__MODULE__{
      message: "Undefined variable: #{variable}",
      variable: variable
    }
  end
end
