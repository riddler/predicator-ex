defmodule Predicator.Errors.EvaluationError do
  @moduledoc """
  Error struct for general evaluation errors in Predicator evaluation.

  This error occurs for runtime evaluation problems like division by zero,
  function call errors, or insufficient operands.

  ## Fields

  - `message` - Human-readable error description
  - `reason` - Structured reason code for the error
  - `operation` - The operation that failed (optional)

  ## Examples

      %Predicator.Errors.EvaluationError{
        message: "Division by zero",
        reason: "division_by_zero",
        operation: :divide
      }

      %Predicator.Errors.EvaluationError{
        message: "Function len() expects 1 arguments, got 0",
        reason: "insufficient_arguments",
        operation: :function_call
      }
  """

  @enforce_keys [:message, :reason]
  defstruct [:message, :reason, :operation]

  @type t :: %__MODULE__{
          message: binary(),
          reason: binary(),
          operation: atom() | nil
        }

  @doc """
  Creates an evaluation error.
  """
  @spec new(binary(), binary(), atom() | nil) :: t()
  def new(message, reason, operation \\ nil) do
    %__MODULE__{
      message: message,
      reason: reason,
      operation: operation
    }
  end

  @doc """
  Creates an evaluation error for insufficient operands.
  """
  @spec insufficient_operands(atom(), integer(), integer()) :: t()
  def insufficient_operands(operation, got, expected) do
    expected_word =
      case expected do
        1 -> "1 value"
        2 -> "2 values"
        n -> "#{n} values"
      end

    %__MODULE__{
      message:
        "#{Predicator.Errors.operation_display_name(operation)} requires #{expected_word} on stack, got: #{got}",
      reason: "insufficient_operands",
      operation: operation
    }
  end
end
