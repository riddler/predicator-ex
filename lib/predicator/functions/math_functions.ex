defmodule Predicator.Functions.MathFunctions do
  @moduledoc """
  Mathematical functions for Predicator expressions.

  Provides SCXML-compatible Math functions for numerical computations.

  ## Available Functions

  - `Math.pow(base, exponent)` - Raises base to the power of exponent
  - `Math.sqrt(value)` - Returns the square root of a number
  - `Math.abs(value)` - Returns the absolute value
  - `Math.floor(value)` - Rounds down to the nearest integer
  - `Math.ceil(value)` - Rounds up to the nearest integer
  - `Math.round(value)` - Rounds to the nearest integer
  - `Math.min(a, b)` - Returns the smaller of two numbers
  - `Math.max(a, b)` - Returns the larger of two numbers
  - `Math.random()` - Returns a random float between 0 and 1

  ## Examples

      iex> {:ok, result} = Predicator.evaluate("Math.pow(2, 3)",
      ...>   %{}, functions: Predicator.Functions.MathFunctions.all_functions())
      iex> result
      8.0

      iex> {:ok, result} = Predicator.evaluate("Math.sqrt(16)",
      ...>   %{}, functions: Predicator.Functions.MathFunctions.all_functions())
      iex> result
      4.0
  """

  @spec all_functions() :: %{binary() => {non_neg_integer(), function()}}
  def all_functions do
    %{
      "Math.pow" => {2, &call_pow/2},
      "Math.sqrt" => {1, &call_sqrt/2},
      "Math.abs" => {1, &call_abs/2},
      "Math.floor" => {1, &call_floor/2},
      "Math.ceil" => {1, &call_ceil/2},
      "Math.round" => {1, &call_round/2},
      "Math.min" => {2, &call_min/2},
      "Math.max" => {2, &call_max/2},
      "Math.random" => {0, &call_random/2}
    }
  end

  defp call_pow([base, exponent], _context) when is_number(base) and is_number(exponent) do
    {:ok, :math.pow(base, exponent)}
  end

  defp call_pow([_base, _exponent], _context) do
    {:error, "Math.pow expects two numeric arguments"}
  end

  defp call_sqrt([value], _context) when is_number(value) and value >= 0 do
    {:ok, :math.sqrt(value)}
  end

  defp call_sqrt([value], _context) when is_number(value) do
    {:error, "Math.sqrt expects a non-negative number"}
  end

  defp call_sqrt([_value], _context) do
    {:error, "Math.sqrt expects a numeric argument"}
  end

  defp call_abs([value], _context) when is_number(value) do
    {:ok, abs(value)}
  end

  defp call_abs([_value], _context) do
    {:error, "Math.abs expects a numeric argument"}
  end

  defp call_floor([value], _context) when is_number(value) do
    {:ok, Float.floor(value * 1.0) |> trunc()}
  end

  defp call_floor([_value], _context) do
    {:error, "Math.floor expects a numeric argument"}
  end

  defp call_ceil([value], _context) when is_number(value) do
    {:ok, Float.ceil(value * 1.0) |> trunc()}
  end

  defp call_ceil([_value], _context) do
    {:error, "Math.ceil expects a numeric argument"}
  end

  defp call_round([value], _context) when is_number(value) do
    {:ok, round(value)}
  end

  defp call_round([_value], _context) do
    {:error, "Math.round expects a numeric argument"}
  end

  defp call_min([a, b], _context) when is_number(a) and is_number(b) do
    {:ok, min(a, b)}
  end

  defp call_min([_a, _b], _context) do
    {:error, "Math.min expects two numeric arguments"}
  end

  defp call_max([a, b], _context) when is_number(a) and is_number(b) do
    {:ok, max(a, b)}
  end

  defp call_max([_a, _b], _context) do
    {:error, "Math.max expects two numeric arguments"}
  end

  defp call_random([], _context) do
    {:ok, :rand.uniform()}
  end
end
