defmodule Predicator.Functions.MathFunctions do
  @moduledoc """
  Mathematical functions for Predicator expressions.

  Provides SCXML-compatible Math functions for numerical computations.

  ## Available Functions

  - `Math.pow(base, exponent)` - Raises base to the power of exponent; integer
    in, non-negative integer exponent, integer out
  - `Math.sqrt(value)` - Returns the square root of a number; integer in with
    an exact integer root, integer out
  - `Math.abs(value)` - Returns the absolute value
  - `Math.floor(value)` - Rounds down to the nearest integer
  - `Math.ceil(value)` - Rounds up to the nearest integer
  - `Math.round(value)` - Rounds to the nearest integer
  - `Math.min(a, b)` - Returns the smaller of two numbers
  - `Math.max(a, b)` - Returns the larger of two numbers
  - `Math.random()` - Returns a random float between 0 and 1

  ## Examples

      iex> {:ok, result} = Predicator.evaluate("Math.pow(2, 3)",
      ...>   %{}, providers: [Predicator.Functions.MathFunctions])
      iex> result
      8

      iex> {:ok, result} = Predicator.evaluate("Math.sqrt(16)",
      ...>   %{}, providers: [Predicator.Functions.MathFunctions])
      iex> result
      4
  """

  @behaviour Predicator.FunctionProvider

  alias Predicator.{Context, Types}

  @type function_result :: {:ok, Types.value()} | {:error, binary()}

  @doc """
  Returns all math functions as a `Predicator.FunctionProvider` map.
  """
  @impl Predicator.FunctionProvider
  @spec functions() :: %{
          Predicator.FunctionProvider.name() => Predicator.FunctionProvider.entry()
        }
  def functions do
    %{
      "Math.pow" => {2, :call_pow},
      "Math.sqrt" => {1, :call_sqrt},
      "Math.abs" => {1, :call_abs},
      "Math.floor" => {1, :call_floor},
      "Math.ceil" => {1, :call_ceil},
      "Math.round" => {1, :call_round},
      "Math.min" => {2, :call_min},
      "Math.max" => {2, :call_max},
      "Math.random" => {0, :call_random}
    }
  end

  @doc """
  Raises base to the power of exponent.

  Returns an integer when both arguments are integers and the exponent is
  non-negative - computed exactly, with no float rounding at large magnitudes.
  Returns a float otherwise (float argument, or negative exponent).
  """
  @spec call_pow([Types.value()], Context.t()) :: function_result()
  def call_pow([base, exponent], _context)
      when is_integer(base) and is_integer(exponent) and exponent >= 0 do
    {:ok, Integer.pow(base, exponent)}
  end

  def call_pow([base, exponent], _context) when is_number(base) and is_number(exponent) do
    {:ok, :math.pow(base, exponent)}
  end

  def call_pow([_base, _exponent], _context) do
    {:error, "Math.pow expects two numeric arguments"}
  end

  @doc """
  Returns the square root of a number.

  Returns an integer when the argument is a non-negative integer with an exact
  integer square root (`Math.sqrt(16)` is `4`). Returns a float otherwise. A
  negative argument is an error, not NaN.
  """
  @spec call_sqrt([Types.value()], Context.t()) :: function_result()
  def call_sqrt([value], _context) when is_integer(value) and value >= 0 do
    root = isqrt(value)
    if root * root == value, do: {:ok, root}, else: {:ok, :math.sqrt(value)}
  end

  def call_sqrt([value], _context) when is_number(value) and value >= 0 do
    {:ok, :math.sqrt(value)}
  end

  def call_sqrt([value], _context) when is_number(value) do
    {:error, "Math.sqrt expects a non-negative number"}
  end

  def call_sqrt([_value], _context) do
    {:error, "Math.sqrt expects a numeric argument"}
  end

  # Integer square root via Newton's method, entirely in integer arithmetic.
  # Not `trunc(:math.sqrt(n))`: that route inherits float precision, which
  # loses exactness (and raises `badarith` above ~1.8e308) for integers this
  # clause needs to handle exactly. Returns `floor(:math.sqrt(n))`.
  @spec isqrt(non_neg_integer()) :: non_neg_integer()
  defp isqrt(0), do: 0

  defp isqrt(n) when is_integer(n) and n > 0 do
    isqrt_newton(n, n)
  end

  @spec isqrt_newton(non_neg_integer(), pos_integer()) :: non_neg_integer()
  defp isqrt_newton(n, x) do
    next = div(x + div(n, x), 2)

    if next >= x, do: x, else: isqrt_newton(n, next)
  end

  @doc "Returns the absolute value of a number."
  @spec call_abs([Types.value()], Context.t()) :: function_result()
  def call_abs([value], _context) when is_number(value) do
    {:ok, abs(value)}
  end

  def call_abs([_value], _context) do
    {:error, "Math.abs expects a numeric argument"}
  end

  @doc "Rounds a number down to the nearest integer."
  @spec call_floor([Types.value()], Context.t()) :: function_result()
  def call_floor([value], _context) when is_number(value) do
    {:ok, Float.floor(value * 1.0) |> trunc()}
  end

  def call_floor([_value], _context) do
    {:error, "Math.floor expects a numeric argument"}
  end

  @doc "Rounds a number up to the nearest integer."
  @spec call_ceil([Types.value()], Context.t()) :: function_result()
  def call_ceil([value], _context) when is_number(value) do
    {:ok, Float.ceil(value * 1.0) |> trunc()}
  end

  def call_ceil([_value], _context) do
    {:error, "Math.ceil expects a numeric argument"}
  end

  @doc "Rounds a number to the nearest integer."
  @spec call_round([Types.value()], Context.t()) :: function_result()
  def call_round([value], _context) when is_number(value) do
    {:ok, round(value)}
  end

  def call_round([_value], _context) do
    {:error, "Math.round expects a numeric argument"}
  end

  @doc "Returns the smaller of two numbers."
  @spec call_min([Types.value()], Context.t()) :: function_result()
  def call_min([a, b], _context) when is_number(a) and is_number(b) do
    {:ok, min(a, b)}
  end

  def call_min([_a, _b], _context) do
    {:error, "Math.min expects two numeric arguments"}
  end

  @doc "Returns the larger of two numbers."
  @spec call_max([Types.value()], Context.t()) :: function_result()
  def call_max([a, b], _context) when is_number(a) and is_number(b) do
    {:ok, max(a, b)}
  end

  def call_max([_a, _b], _context) do
    {:error, "Math.max expects two numeric arguments"}
  end

  @doc "Returns a random float between 0 and 1."
  @spec call_random([Types.value()], Context.t()) :: function_result()
  def call_random([], _context) do
    {:ok, :rand.uniform()}
  end
end
