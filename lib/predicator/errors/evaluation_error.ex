defmodule Predicator.Errors.EvaluationError do
  @moduledoc """
  Error struct for general evaluation errors in Predicator evaluation.

  This error occurs for runtime evaluation problems like division by zero,
  function call errors, or insufficient operands.

  ## Fields

  - `message` - Human-readable error description
  - `reason` - Structured reason code for the error
  - `operation` - The operation that failed (optional)
  - `position` - `{line, column}` of the source token that produced the failing
    instruction, when a position table was available (optional)
  - `span` - the source text the failing instruction's AST node covers, when the
    program was compiled with spans (optional). `position` names the token to
    blame; `span` is what to underline.
  - `details` - structured, error-specific data (optional, default `nil`), the
    same shape `Predicator.Errors.LocationError` already uses. It lets a host
    read machine-readable data off an error without parsing `message`, which is
    non-normative.

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
  defstruct [:message, :reason, :operation, :position, :span, :details]

  @type t :: %__MODULE__{
          message: binary(),
          reason: binary(),
          operation: atom() | nil,
          position: Predicator.Types.position() | nil,
          span: Predicator.Types.span() | nil,
          details: map() | nil
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

  @doc """
  Creates an evaluation error for a `store` refused by the `:protected_roots`
  evaluation option.

  `details.root` carries the offending root as data, so a host maps this onto
  its own error vocabulary without matching on `message` (messages are
  non-normative, `docs/isa.md` §2).
  """
  @spec protected_root(binary()) :: t()
  def protected_root(root) do
    %__MODULE__{
      message: "Cannot assign to protected context root '#{root}'",
      reason: "protected_root",
      operation: :store,
      details: %{root: root}
    }
  end
end
