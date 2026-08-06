defmodule Predicator.MixProject do
  use Mix.Project

  @app :predicator
  @version "3.8.0"
  @description "A secure, non-evaling condition (boolean predicate) engine for end users"
  @source_url "https://github.com/riddler/predicator-ex"
  @deps [
    # Development and testing
    {:castore, "~> 1.0", only: [:dev, :test]},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:ex_doc, "~> 0.40", only: :dev, runtime: false},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:excoveralls, "~> 0.18", only: :test},
    {:ex_quality, "~> 0.13", only: :dev, runtime: false}
  ]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: @deps,
      docs: docs(),
      description: @description,
      package: package(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
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
      # Deliberately excludes docs/ - hexdocs is built from docs()'s extras:
      # paths read off the publisher's disk, not from this tarball, so the
      # markdown sources only bloat what mix deps.get downloads.
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
      main: "readme",
      # These paths are read off disk at publish time and need no entry in
      # package()'s files: list - the docs tarball hexdocs hosts is built by
      # mix docs, separately from the package tarball mix deps.get fetches.
      extras: [
        "README.md",
        "docs/reference/language.md",
        "docs/guides/nested-data-access.md",
        "docs/guides/custom-functions.md",
        "docs/guides/location-expressions.md",
        "docs/architecture.md",
        {"docs/adr/README.md",
         [title: "Architecture Decision Records", filename: "architecture-decision-records"]},
        "docs/adr/0001-keep-the-stack-vm-revise-the-instruction-set.md",
        "docs/adr/0002-the-equals-grammar-break.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Reference: ~r{docs/reference/},
        Guides: ~r{docs/guides/},
        Architecture: ~r{docs/(architecture|adr/)}
      ]
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
