# Quality gate configuration for Predicator.
#
# Two ways to run:
#
#   mix quality                 - full gate: format, compile, credo --strict,
#                                 dialyzer, dependency audit, docs, doc links,
#                                 full suite with coverage. Required green
#                                 before every commit.
#
#   mix quality --profile loop  - inner loop while implementing: skips dialyzer
#                                 and coverage, runs only the tests covering
#                                 changed code. Use between edits, never as the
#                                 final check.
#
# Thresholds are deliberately not here. Coverage's 90% minimum lives in
# coveralls.json and the credo checks live in .credo.exs, so each has one home.
#
# Agents: prefer `--format json` when you want to route on which stage failed.

[
  format: [
    check: true
  ],

  compile: [
    warnings_as_errors: true
  ],

  credo: [
    strict: true
  ],

  # The two docs stages make this gate the pre-publish check for the package's
  # docs. Docs runs `mix docs` and fails on any ExDoc warning. Doc links fails
  # on the link rules ExDoc accepts silently: a README relative link to a file
  # not in the package files, a relative link in a Markdown extra to a file
  # that is not itself an extra (moduledoc links are the Docs stage's), two
  # extras sharing a basename, a silent rewrite to a different extra. Both are
  # opt-in in ex_quality; `:auto` runs them when :ex_doc is installed.
  docs: [
    enabled: :auto
  ],

  doc_links: [
    enabled: :auto
  ],

  profiles: [
    loop: [
      stages: [:format, :compile, :credo, :test],
      # base_ref is explicit: ExQuality's default-branch detection resolves to
      # origin/master here, which is not a ref, and the scope then falls back
      # to the whole suite.
      test: [scope: :changed, coverage: false, base_ref: "origin/main"]
    ]
  ]
]
