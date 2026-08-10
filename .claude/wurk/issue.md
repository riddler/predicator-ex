# Predicator-ex extension: /wurk:issue

The manifest carries the `area:` labels only as a name list; the per-label
path mapping and its disambiguation live here. Adds only - see
`~/.claude/skills/wurk:issue/SKILL.md` for everything this does not repeat.

## The `area:` label -> path mapping

| Label | Covers |
|---|---|
| `area:lexer-parser` | `lib/predicator/lexer.ex`, `parser.ex`, `types.ex`, and their tests |
| `area:evaluator` | `lib/predicator/compiler.ex`, `evaluator.ex`, `duration.ex`, and their tests |
| `area:context` | `lib/predicator/context_location.ex` and the future Context struct |
| `area:functions` | `lib/predicator/functions/**` |
| `area:visitors` | `lib/predicator/visitor.ex`, `lib/predicator/visitors/**` |
| `area:api` | `lib/predicator.ex`, `lib/predicator/errors.ex`, `lib/predicator/errors/**` |
| `area:conformance` | `conformance/**`, `lib/predicator/conformance/**`, `lib/mix/tasks/corpus.*.ex`, their tests |
| `area:skills` | `.claude/**` |
| `area:docs` | `docs/**`, `CLAUDE.md`, `README.md`, `CHANGELOG.md` |
| `area:build` | `mix.exs`, `mix.lock`, `.quality.exs`, `.credo.exs`, `coveralls.json`, `mise.toml`, `.gitignore`, `.github/**` |

## `area:conformance` vs `area:build`

`area:conformance` is deliberately *not* `area:build`, even though it covers
mix tasks - regenerating or extending the corpus touches none of `area:build`'s
files. A bead that *also* edits `mix.exs`, `coveralls.json`, or another
`area:build` file carries **both** labels and lands alone; that is the
file-collision rule doing its job, not a penalty for touching conformance.
This was mis-labeled once already and serialized the queue
(`docs/research/260807-px-phw-conformance-area-label.md`).

## `area:api` is the cross-cutting surface

A bead that adds a function *and* exposes it on `lib/predicator.ex` carries
both `area:functions` (or whichever subsystem) and `area:api` - it does touch
both.

## ISA changes are not automatically `upstream`

A change to the instruction set is real work in this repo (ADR-0003), not an
`upstream` bead. File the sibling-side adoption as its own `upstream` bead if
it needs tracking, and never make it a dependency of the Elixir work.

## Dependency links and epics

Follow the real build order - lexer before parser, parser before compiler.
Epics mirror ADR-0001's release arcs.
