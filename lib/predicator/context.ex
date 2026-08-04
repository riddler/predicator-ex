defmodule Predicator.Context do
  @moduledoc """
  A bound evaluation context: data, functions, and the unbound-variable policy.

  Build one with `new/2`, evaluate `Predicator.evaluate/3` against it many
  times, and rebind cheaply with `bind/3` between evaluations - the builtin
  function maps merge once, at construction, not on every evaluate call.

  ## Examples

      iex> context = Predicator.Context.new(%{"score" => 85})
      iex> Predicator.evaluate("score > 80", context)
      {:ok, true}

      iex> context = Predicator.Context.new(%{})
      iex> context = Predicator.Context.bind(context, "score", 90)
      iex> Predicator.evaluate("score", context)
      {:ok, 90}
  """

  alias Predicator.{ContextLocation, Evaluator, Types}

  @typedoc "Policy for a load of an unbound root variable. See `px-8um.3`."
  @type on_unbound :: :undefined | :error

  @typedoc "A bound evaluation context."
  @type t :: %__MODULE__{
          data: Types.context(),
          functions: %{binary() => {non_neg_integer(), function()}},
          on_unbound: on_unbound()
        }

  defstruct data: %{}, functions: %{}, on_unbound: :undefined

  @doc """
  Builds a context, merging the builtin function maps once.

  ## Parameters

  - `data` - the bound-variable map (default `%{}`)
  - `opts` - `:functions` (custom functions merged over the builtins,
    same as `Predicator.evaluate/3`'s `:functions` option) and `:on_unbound`
    (`:undefined` (default) | `:error` - stored for `px-8um.3`; this
    struct does not yet act on it)

  ## Examples

      iex> Predicator.Context.new(%{"x" => 1}).data
      %{"x" => 1}

      iex> Predicator.Context.new().on_unbound
      :undefined
  """
  @spec new(Types.context(), keyword()) :: t()
  def new(data \\ %{}, opts \\ []) when is_map(data) do
    %__MODULE__{
      data: data,
      functions: Evaluator.merge_functions(opts),
      on_unbound: validate_on_unbound!(Keyword.get(opts, :on_unbound, :undefined))
    }
  end

  @spec validate_on_unbound!(term()) :: on_unbound()
  defp validate_on_unbound!(policy) when policy in [:undefined, :error], do: policy

  defp validate_on_unbound!(other) do
    raise ArgumentError,
          "on_unbound must be :undefined or :error, got: #{inspect(other)}"
  end

  @doc """
  Binds `name` to `value` in `data`. O(1): a single `Map.put/3`.

  `functions` and `on_unbound` are carried over unchanged.

  ## Examples

      iex> context = Predicator.Context.new(%{"a" => 1})
      iex> Predicator.Context.bind(context, "b", 2).data
      %{"a" => 1, "b" => 2}
  """
  @spec bind(t(), binary(), Types.value()) :: t()
  def bind(%__MODULE__{data: data} = context, name, value) when is_binary(name) do
    %{context | data: Map.put(data, name, value)}
  end

  @doc """
  Assigns `value` at `path_or_expression`, returning the rebound context.

  `path_or_expression` is either a location expression string (resolved
  against the context's current `data`, then written) or an
  already-resolved `t:Predicator.ContextLocation.location_path/0`. Writes
  through `Predicator.ContextLocation.put/3` - the same auto-vivifying write
  algorithm as `Predicator.context_assign/4` and the future `store` opcode
  (`px-tbv.2`).

  ## Examples

      iex> context = Predicator.Context.new(%{})
      iex> {:ok, context} = Predicator.Context.assign(context, "user.name", "Ada")
      iex> context.data
      %{"user" => %{"name" => "Ada"}}

      iex> context = Predicator.Context.new(%{"items" => [1, 2, 3]})
      iex> {:ok, context} = Predicator.Context.assign(context, ["items", 1], "x")
      iex> context.data
      %{"items" => [1, "x", 3]}
  """
  @spec assign(t(), binary() | ContextLocation.location_path(), Types.value()) ::
          {:ok, t()} | {:error, struct()}
  def assign(%__MODULE__{data: data} = context, path_or_expression, value) do
    with {:ok, path} <- resolve_path(data, path_or_expression),
         {:ok, new_data} <- ContextLocation.put(data, path, value) do
      {:ok, %{context | data: new_data}}
    end
  end

  @spec resolve_path(Types.context(), binary() | ContextLocation.location_path()) ::
          ContextLocation.location_result() | {:error, struct()}
  defp resolve_path(_data, path) when is_list(path), do: {:ok, path}

  defp resolve_path(data, expression) when is_binary(expression) do
    ContextLocation.resolve_expression(expression, data)
  end
end
