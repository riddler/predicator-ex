defmodule Predicator.RegistryInitializer do
  @moduledoc """
  A GenServer that initializes the function registry during application startup.

  This worker starts the function registry and registers all built-in functions,
  ensuring they're available for use throughout the application lifecycle.
  """

  use GenServer

  alias Predicator.{BuiltInFunctions, FunctionRegistry}

  @doc """
  Starts the registry initializer.

  This is typically called by the application supervisor during startup.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl GenServer
  def init(:ok) do
    # Start the function registry
    FunctionRegistry.start_registry()

    # Register all built-in functions
    BuiltInFunctions.register_all()

    {:ok, %{}}
  end
end
