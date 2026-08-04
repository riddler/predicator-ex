# Quality gate configuration for Predicator.
#
# Two ways to run:
#
#   mix quality                 - full gate: format, compile, credo --strict,
#                                 dialyzer, dependency audit, full suite with
#                                 coverage. Required green before every commit.
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
  compile: [
    warnings_as_errors: true
  ],

  credo: [
    strict: true
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
