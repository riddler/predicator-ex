defmodule Predicator.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Predicator.Functions.{Registry, SystemFunctions}

  @impl Application
  def start(_type, _args) do
    # Initialize the function registry and register system functions immediately
    Registry.start_registry()
    SystemFunctions.register_all()

    # Start supervisor with empty children list since initialization is done
    children = []

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Predicator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
