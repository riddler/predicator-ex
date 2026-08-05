defmodule Predicator.Errors do
  @moduledoc """
  Common utilities for error formatting across all Predicator error modules.

  This module provides shared functions for formatting error messages,
  type names, and operation names consistently across all error types.
  """

  alias Predicator.Types

  @doc """
  Attaches a source position to an error struct that has a `:position` field.

  Returns the error unchanged when `position` is `nil` or when the value has no
  `:position` field, so it is safe to call on any error value - including the
  bare-string errors some evaluator paths return internally.

  ## Examples

      iex> error = Predicator.Errors.EvaluationError.new("boom", "boom")
      iex> Predicator.Errors.put_position(error, {1, 3}).position
      {1, 3}

      iex> error = Predicator.Errors.EvaluationError.new("boom", "boom")
      iex> Predicator.Errors.put_position(error, nil).position
      nil

      iex> Predicator.Errors.put_position("boom", {1, 3})
      "boom"
  """
  @spec put_position(term(), Types.position() | nil) :: term()
  def put_position(error, nil), do: error

  def put_position(%_struct{} = error, position) do
    if Map.has_key?(error, :position), do: %{error | position: position}, else: error
  end

  def put_position(error, _position), do: error

  @doc """
  Formats an expected type name for error messages with proper articles.

  ## Examples

      iex> Predicator.Errors.expected_type_name(:integer)
      "an integer"

      iex> Predicator.Errors.expected_type_name(:boolean)
      "a boolean"

      iex> Predicator.Errors.expected_type_name(:custom_type)
      "a custom_type"
  """
  @spec expected_type_name(atom()) :: String.t()
  def expected_type_name(:integer), do: "an integer"
  def expected_type_name(type), do: "a #{type}"

  @doc """
  Formats a type name with its value for error messages.

  ## Examples

      iex> Predicator.Errors.type_name_with_value(:string, "hello")
      "\\"hello\\" (string)"

      iex> Predicator.Errors.type_name_with_value(:integer, 42)
      "42 (integer)"

      iex> Predicator.Errors.type_name_with_value(:undefined, :undefined)
      ":undefined (undefined)"
  """
  @spec type_name_with_value(atom(), any()) :: String.t()
  def type_name_with_value(type, value) do
    type_name = "#{type}"

    value_repr =
      case type do
        :string -> "\"#{value}\""
        _other_type -> "#{inspect(value)}"
      end

    "#{value_repr} (#{type_name})"
  end

  @doc """
  Formats an operation name for user-friendly error messages.

  ## Examples

      iex> Predicator.Errors.operation_display_name(:add)
      "Arithmetic add"

      iex> Predicator.Errors.operation_display_name(:logical_and)
      "Logical AND"

      iex> Predicator.Errors.operation_display_name(:unary_bang)
      "Logical NOT"
  """
  @spec operation_display_name(atom()) :: String.t()
  def operation_display_name(:add), do: "Arithmetic add"
  def operation_display_name(:subtract), do: "Arithmetic subtract"
  def operation_display_name(:multiply), do: "Arithmetic multiply"
  def operation_display_name(:divide), do: "Arithmetic divide"
  def operation_display_name(:modulo), do: "Arithmetic modulo"
  def operation_display_name(:unary_minus), do: "Unary minus"
  def operation_display_name(:unary_bang), do: "Logical NOT"
  def operation_display_name(:logical_not), do: "Logical NOT"
  def operation_display_name(:logical_and), do: "Logical AND"
  def operation_display_name(:logical_or), do: "Logical OR"
  def operation_display_name(:bracket_access), do: "Bracket access"

  def operation_display_name(op) do
    op
    |> to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", fn
      "and" -> "AND"
      "or" -> "OR"
      "not" -> "NOT"
      word -> String.capitalize(word)
    end)
  end
end
