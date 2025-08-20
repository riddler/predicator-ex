defmodule Predicator.MixProject do
  use Mix.Project

  @version "1.1.0"
  @description "A secure, non-evaling condition (boolean predicate) engine for end users"
  @source_url "https://github.com/riddler/predicator-ex"
  @deps [
    # Development and testing
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:ex_doc, "~> 0.31", only: :dev, runtime: false},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:excoveralls, "~> 0.18", only: :test}
  ]

  def project do
    [
      app: :predicator,
      version: @version,
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: @deps,
      docs: docs(),
      description: @description,
      package: package(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        "test.watch": :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        quality: :test,
        "quality.check": :test,
        "test.coverage": :test,
        "test.coverage.html": :test,
        "test.coverage.detail": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Predicator.Application, []}
    ]
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
      main: "readme"
    ]
  end

  defp aliases do
    [
      quality: ["format", "credo --strict", "coveralls", "dialyzer"],
      "quality.check": [
        "format --check-formatted",
        "credo --strict",
        "coveralls",
        "dialyzer"
      ],
      "test.coverage": ["coveralls"],
      "test.coverage.html": ["coveralls.html"],
      "test.coverage.detail": ["coveralls.detail"]
    ]
  end
end
