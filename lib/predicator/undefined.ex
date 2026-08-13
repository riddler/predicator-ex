defmodule Predicator.Undefined do
  @moduledoc """
  The `:undefined` sentinel: predicator's representation of an unbound or
  missing value.

  The atom stays the runtime representation - it is pervasive in tests and
  the Ruby/JavaScript siblings, JSON-adjacent, and cheap. A struct sentinel
  would break instruction interchange and every existing embedding for
  aesthetic gain (the instruction list is the cross-language interchange
  format, `ADR-0001`). This module owns it publicly instead: one place that
  names the atom, checks for it, and normalizes it against `nil` at a
  JSON-shaped boundary.
  """

  alias Predicator.Types

  @doc """
  The `:undefined` sentinel value.

  ## Examples

      iex> Predicator.Undefined.value()
      :undefined
  """
  @spec value() :: :undefined
  def value, do: :undefined

  @doc """
  Checks whether `value` is the `:undefined` sentinel.

  ## Examples

      iex> Predicator.Undefined.undefined?(:undefined)
      true

      iex> Predicator.Undefined.undefined?(nil)
      false

      iex> Predicator.Undefined.undefined?(42)
      false
  """
  @spec undefined?(Types.value() | nil) :: boolean()
  def undefined?(:undefined), do: true
  def undefined?(_value), do: false

  @doc """
  Converts the `:undefined` sentinel to `nil`; any other value passes
  through unchanged.

  For embedding at a boundary that speaks `nil` rather than `:undefined`
  (JSON output, a host application's own representation of "missing"). This
  is an edge helper for a boundary that does not distinguish null from
  undefined - `Predicator.Context` itself keeps them apart.

  ## Examples

      iex> Predicator.Undefined.to_nil(:undefined)
      nil

      iex> Predicator.Undefined.to_nil(42)
      42
  """
  @spec to_nil(Types.value()) :: Types.value() | nil
  def to_nil(:undefined), do: nil
  def to_nil(value), do: value

  @doc """
  Converts `nil` to the `:undefined` sentinel; any other value passes
  through unchanged. The inverse of `to_nil/1`.

  For normalizing an incoming `nil` (JSON `null`, a host application's own
  "missing") to predicator's sentinel at the edge. This is an edge helper
  for a boundary that does not distinguish null from undefined -
  `Predicator.Context.new/2` no longer calls it: a `nil` in a context is now
  the null value.

  ## Examples

      iex> Predicator.Undefined.from_nil(nil)
      :undefined

      iex> Predicator.Undefined.from_nil(42)
      42
  """
  @spec from_nil(Types.value() | nil) :: Types.value()
  def from_nil(nil), do: :undefined
  def from_nil(value), do: value
end
