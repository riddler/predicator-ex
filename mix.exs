defmodule Predicator.MixProject do
  use Mix.Project

  @app :predicator
  @version "9.0.2"
  @description "A secure, non-evaling condition (boolean predicate) engine for end users"
  @source_url "https://github.com/riddler/predicator-ex"
  @deps [
    # Development and testing
    {:castore, "~> 1.0", only: [:dev, :test]},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:ex_doc, "~> 0.40", only: :dev, runtime: false},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:excoveralls, "~> 0.18", only: :test},
    {:ex_quality, "~> 0.14", only: :dev, runtime: false},
    {:benchee, "~> 1.3", only: :dev, runtime: false}
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
      #
      # The whole conformance apparatus is excluded on the same principle:
      # nothing an application does at runtime touches it, and the audience
      # that does - sibling implementers - works from a git checkout. That is
      # three things, excluded three ways (px-35i.4):
      #
      #   conformance/                   the corpus, manifest, and schemas;
      #                                  simply absent from files:
      #   lib/mix/tasks/corpus.*.ex      the dev tasks that regenerate it;
      #                                  lib/predicator* never matched them
      #   lib/predicator/conformance/    the generator modules the tasks call;
      #                                  matched by the glob, so removed by
      #                                  exclude_patterns below
      #
      # Nothing under lib/ outside those two directories references
      # Predicator.Conformance, so dropping it cannot break a consumer's
      # compile. A test guards that invariant.
      files: ~w(lib/predicator* mix.exs README.md LICENSE CHANGELOG.md),
      exclude_patterns: [~r{\Alib/predicator/conformance/}],
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
        "docs/reference/ast.md",
        "docs/isa.md",
        "docs/guides/nested-data-access.md",
        "docs/guides/custom-functions.md",
        "docs/guides/location-expressions.md",
        "docs/guides/embedding.md",
        "docs/guides/porting.md",
        "docs/architecture.md",
        "docs/contributing.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Reference: ~r{docs/(reference/|isa\.md)},
        Guides: ~r{docs/guides/},
        Architecture: ~r{docs/architecture}
      ],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
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
