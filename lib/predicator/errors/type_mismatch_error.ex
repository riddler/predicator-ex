defmodule Predicator.Errors.TypeMismatchError do
  @moduledoc """
  Error struct for type mismatch errors in Predicator evaluation.

  This error occurs when an operation receives values of incorrect types,
  such as trying to perform arithmetic on strings or logical operations on integers.

  ## Fields

  - `message` - Human-readable error description
  - `expected` - The type that was expected (e.g., `:integer`, `:boolean`)
  - `got` - The actual type(s) received (single type or tuple for binary operations)
  - `values` - The actual value(s) that caused the error (optional, for debugging)
  - `operation` - The operation that failed (e.g., `:add`, `:logical_and`)
  - `position` - `{line, column}` of the source token that produced the failing
    instruction, when a position table was available (optional)
  - `span` - the source text the failing instruction's AST node covers, when the
    program was compiled with spans (optional). `position` names the token to
    blame; `span` is what to underline.

  ## Examples

      %Predicator.Errors.TypeMismatchError{
        message: "Arithmetic add requires integers, got \"hello\" (string) and 5 (integer)",
        expected: :integer,
        got: {:string, :integer},
        values: {"hello", 5},
        operation: :add
      }

      %Predicator.Errors.TypeMismatchError{
        message: "Unary minus requires an integer, got \"text\" (string)",
        expected: :integer,
        got: :string,
        values: "text",
        operation: :unary_minus
      }
  """

  @enforce_keys [:message, :expected, :got, :operation]
  defstruct [:message, :expected, :got, :values, :operation, :position, :span]

  @type t :: %__MODULE__{
          message: binary(),
          expected: atom(),
          got: atom() | {atom(), atom()},
          values: term(),
          operation: atom(),
          position: Predicator.Types.position() | nil,
          span: Predicator.Types.span() | nil
        }

  @doc """
  Creates a type mismatch error for unary operations.
  """
  @spec unary(atom(), atom(), atom(), any()) :: t()
  def unary(operation, expected, got, value) do
    expected_text = Predicator.Errors.expected_type_name(expected)
    got_text = Predicator.Errors.type_name_with_value(got, value)
    operation_name = Predicator.Errors.operation_display_name(operation)

    %__MODULE__{
      message: "#{operation_name} requires #{expected_text}, got #{got_text}",
      expected: expected,
      got: got,
      values: value,
      operation: operation
    }
  end

  @doc """
  Creates a type mismatch error for binary operations.
  """
  @spec binary(atom(), atom(), {atom(), atom()}, {any(), any()}) :: t()
  def binary(operation, expected, {got1, got2}, {value1, value2}) do
    operation_name = Predicator.Errors.operation_display_name(operation)
    expected_text = Predicator.Errors.expected_type_name(expected)
    got1_text = Predicator.Errors.type_name_with_value(got1, value1)
    got2_text = Predicator.Errors.type_name_with_value(got2, value2)

    expected_plural =
      case expected_text do
        "an " <> rest -> rest <> "s"
        "a " <> rest -> rest <> "s"
        text -> text <> "s"
      end

    %__MODULE__{
      message: "#{operation_name} requires #{expected_plural}, got #{got1_text} and #{got2_text}",
      expected: expected,
      got: {got1, got2},
      values: {value1, value2},
      operation: operation
    }
  end
end
