defmodule Predicator.MixProject do
  use Mix.Project

  @app :predicator
  @version "3.1.0"
  @description "A secure, non-evaling condition (boolean predicate) engine for end users"
  @source_url "https://github.com/riddler/predicator-ex"
  @deps [
    # Development and testing
    {:castore, "~> 1.0", only: [:dev, :test]},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:ex_doc, "~> 0.31", only: :dev, runtime: false},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:excoveralls, "~> 0.18", only: :test}
  ]

  def project do
    [
      app: @app,
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
      ],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit],
        warnings: [:unknown]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      name: @app,
      files: ~w(lib/predicator* mix.exs README.md LICENSE CHANGELOG.md),
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
      extras: ["README.md", "LICENSE", "CHANGELOG.md"],
      main: "readme"
    ]
  end

  defp aliases do
    [
      "test.coverage": ["coveralls"],
      "test.coverage.html": ["coveralls.html"],
      "test.coverage.detail": ["coveralls.detail"]
    ]
  end
end
