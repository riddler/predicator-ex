defmodule Predicator.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      # Initialize the function registry and register system functions
      Predicator.Functions.Initializer
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Predicator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
