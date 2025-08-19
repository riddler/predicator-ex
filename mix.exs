defmodule Predicator.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/predicator/predicator_elixir"

  def project do
    [
      app: :predicator,
      version: @version,
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
      aliases: aliases(),
      preferred_cli_env: [
        "test.watch": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Predicator.Application, []}
    ]
  end

  defp deps do
    [
      # Development and testing
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mix_test_watch, "~> 1.2", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "A secure, non-evaluative condition engine for processing end-user boolean predicates in Elixir"
  end

  defp package do
    [
      name: :predicator,
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Predicator Team"]
    ]
  end

  defp docs do
    [
      name: "Predicator",
      source_ref: "v#{@version}",
      canonical: "https://hexdocs.pm/predicator",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        Core: [Predicator, Predicator.Types],
        Evaluation: [Predicator.Evaluator],
        Compilation: [],
        Errors: []
      ]
    ]
  end

  defp aliases do
    [
      "test.watch": ["test.watch --stale"]
    ]
  end
end
