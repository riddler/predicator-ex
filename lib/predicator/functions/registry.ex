defmodule Predicator.Functions.Registry do
  @moduledoc """
  Function registry for custom predicator functions.

  This module provides a simple way to register custom functions using anonymous functions.

  ## Function Registration

      # Register anonymous functions
      Predicator.FunctionRegistry.register_function("double", 1, fn [n], _context ->
        {:ok, n * 2}
      end)

      # Register with arity validation
      Predicator.FunctionRegistry.register_function("add", 2, fn [a, b], _context ->
        {:ok, a + b}
      end)

  ## Function Contract

  All custom functions must:
  - Accept two parameters: `[arg1, arg2, ...]` and `context`
  - Return `{:ok, result}` on success or `{:error, message}` on failure
  - The context is always available but can be ignored if not needed

  ## Usage in Expressions

      # Using registered functions in predicator expressions
      Predicator.evaluate("double(value)", %{"value" => 5})
      # => {:ok, 10}

      Predicator.evaluate("add(x, y) > 10", %{"x" => 5, "y" => 7})
      # => {:ok, true}
  """

  alias Predicator.Types

  @type function_impl :: ([Types.value()], Types.context() ->
                            {:ok, Types.value()} | {:error, binary()})
  @type function_info :: %{
          name: binary(),
          arity: non_neg_integer(),
          impl: function_impl()
        }

  # Global registry state
  @registry_name :predicator_function_registry

  @doc """
  Starts the function registry.

  This is typically called automatically when the application starts.
  """
  @spec start_registry :: :ok
  def start_registry do
    case :ets.whereis(@registry_name) do
      :undefined ->
        try do
          :ets.new(@registry_name, [:set, :public, :named_table])
          :ok
        rescue
          ArgumentError ->
            # Another process created the table between our check and creation
            # This is fine, just return :ok
            :ok
        end
      _table_exists ->
        :ok
    end
  end

  @doc """
  Registers a single function with name, arity, and implementation.

  ## Parameters

  - `name` - Function name as it appears in expressions
  - `arity` - Number of arguments the function expects
  - `impl` - Function implementation that takes `(args, context)` and returns `{:ok, result}` or `{:error, message}`

  ## Examples

      # Simple function
      FunctionRegistry.register_function("double", 1, fn [n], _context ->
        {:ok, n * 2}
      end)

      # Function that uses context
      FunctionRegistry.register_function("current_user", 0, fn [], context ->
        {:ok, Map.get(context, "current_user", "anonymous")}
      end)
  """
  @spec register_function(binary(), non_neg_integer(), function_impl()) :: :ok
  def register_function(name, arity, impl)
      when is_binary(name) and is_integer(arity) and arity >= 0 do
    ensure_registry_exists()

    function_info = %{
      name: name,
      arity: arity,
      impl: impl
    }

    :ets.insert(@registry_name, {name, function_info})
    :ok
  end

  @doc """
  Calls a registered custom function.

  ## Parameters

  - `name` - Function name
  - `args` - List of argument values
  - `context` - Evaluation context

  ## Returns

  - `{:ok, result}` - Function executed successfully
  - `{:error, message}` - Function call error
  """
  @spec call(binary(), [Types.value()], Types.context()) ::
          {:ok, Types.value()} | {:error, binary()}
  def call(name, args, context) when is_binary(name) and is_list(args) and is_map(context) do
    ensure_registry_exists()

    case :ets.lookup(@registry_name, name) do
      [{_name, %{arity: arity, impl: impl}}] ->
        if length(args) == arity do
          try do
            impl.(args, context)
          rescue
            error ->
              {:error, "Function #{name}() failed: #{Exception.message(error)}"}
          end
        else
          {:error, "Function #{name}() expects #{arity} arguments, got #{length(args)}"}
        end

      [] ->
        {:error, "Unknown function: #{name}"}
    end
  end

  @doc """
  Lists all registered custom functions.

  Returns a list of function information maps containing name, arity, and implementation.
  """
  @spec list_functions() :: [function_info()]
  def list_functions do
    ensure_registry_exists()

    :ets.tab2list(@registry_name)
    |> Enum.map(fn {_key, function_info} -> function_info end)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Checks if a function is registered.

  ## Examples

      iex> FunctionRegistry.function_registered?("my_func")
      true

      iex> FunctionRegistry.function_registered?("unknown")
      false
  """
  @spec function_registered?(binary()) :: boolean()
  def function_registered?(name) when is_binary(name) do
    ensure_registry_exists()
    :ets.member(@registry_name, name)
  end

  @doc """
  Clears all registered functions.

  This is primarily useful for testing.
  """
  @spec clear_registry() :: :ok
  def clear_registry do
    ensure_registry_exists()
    :ets.delete_all_objects(@registry_name)
    :ok
  end

  # Ensure the ETS table exists
  defp ensure_registry_exists do
    case :ets.whereis(@registry_name) do
      :undefined -> start_registry()
      _table_exists -> :ok
    end
  end
end
