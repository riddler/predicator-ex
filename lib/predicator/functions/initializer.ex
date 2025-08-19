defmodule Predicator.Functions.Initializer do
  @moduledoc """
  A Task that initializes the function registry during application startup.

  This task starts the function registry and registers all system functions,
  then exits. It's designed for one-time initialization during app startup.
  """

  use Task

  alias Predicator.Functions.{Registry, SystemFunctions}

  @doc """
  Starts the registry initializer task.

  This is typically called by the application supervisor during startup.
  """
  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(_opts \\ []) do
    Task.start_link(__MODULE__, :run, [])
  end

  @doc """
  Runs the initialization process.

  Starts the function registry and registers all system functions.
  """
  @spec run() :: :ok
  def run do
    # Start the function registry
    Registry.start_registry()

    # Register all system functions
    SystemFunctions.register_all()

    :ok
  end
end
