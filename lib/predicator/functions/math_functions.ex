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

  @behaviour Predicator.FunctionProvider

  alias Predicator.{Context, Types}

  @type function_result :: {:ok, Types.value()} | {:error, binary()}

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

  @doc """
  Returns all math functions as a `Predicator.FunctionProvider` map.

  Same names and arities as `all_functions/0`, naming each implementation by
  atom instead of closure.
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

  @doc "Raises base to the power of exponent."
  @spec call_pow([Types.value()], Context.t() | Types.context()) :: function_result()
  def call_pow([base, exponent], _context) when is_number(base) and is_number(exponent) do
    {:ok, :math.pow(base, exponent)}
  end

  def call_pow([_base, _exponent], _context) do
    {:error, "Math.pow expects two numeric arguments"}
  end

  @doc "Returns the square root of a number."
  @spec call_sqrt([Types.value()], Context.t() | Types.context()) :: function_result()
  def call_sqrt([value], _context) when is_number(value) and value >= 0 do
    {:ok, :math.sqrt(value)}
  end

  def call_sqrt([value], _context) when is_number(value) do
    {:error, "Math.sqrt expects a non-negative number"}
  end

  def call_sqrt([_value], _context) do
    {:error, "Math.sqrt expects a numeric argument"}
  end

  @doc "Returns the absolute value of a number."
  @spec call_abs([Types.value()], Context.t() | Types.context()) :: function_result()
  def call_abs([value], _context) when is_number(value) do
    {:ok, abs(value)}
  end

  def call_abs([_value], _context) do
    {:error, "Math.abs expects a numeric argument"}
  end

  @doc "Rounds a number down to the nearest integer."
  @spec call_floor([Types.value()], Context.t() | Types.context()) :: function_result()
  def call_floor([value], _context) when is_number(value) do
    {:ok, Float.floor(value * 1.0) |> trunc()}
  end

  def call_floor([_value], _context) do
    {:error, "Math.floor expects a numeric argument"}
  end

  @doc "Rounds a number up to the nearest integer."
  @spec call_ceil([Types.value()], Context.t() | Types.context()) :: function_result()
  def call_ceil([value], _context) when is_number(value) do
    {:ok, Float.ceil(value * 1.0) |> trunc()}
  end

  def call_ceil([_value], _context) do
    {:error, "Math.ceil expects a numeric argument"}
  end

  @doc "Rounds a number to the nearest integer."
  @spec call_round([Types.value()], Context.t() | Types.context()) :: function_result()
  def call_round([value], _context) when is_number(value) do
    {:ok, round(value)}
  end

  def call_round([_value], _context) do
    {:error, "Math.round expects a numeric argument"}
  end

  @doc "Returns the smaller of two numbers."
  @spec call_min([Types.value()], Context.t() | Types.context()) :: function_result()
  def call_min([a, b], _context) when is_number(a) and is_number(b) do
    {:ok, min(a, b)}
  end

  def call_min([_a, _b], _context) do
    {:error, "Math.min expects two numeric arguments"}
  end

  @doc "Returns the larger of two numbers."
  @spec call_max([Types.value()], Context.t() | Types.context()) :: function_result()
  def call_max([a, b], _context) when is_number(a) and is_number(b) do
    {:ok, max(a, b)}
  end

  def call_max([_a, _b], _context) do
    {:error, "Math.max expects two numeric arguments"}
  end

  @doc "Returns a random float between 0 and 1."
  @spec call_random([Types.value()], Context.t() | Types.context()) :: function_result()
  def call_random([], _context) do
    {:ok, :rand.uniform()}
  end
end
