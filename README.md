# Predicator

[![CI](https://github.com/riddler/predicator-ex/actions/workflows/ci.yml/badge.svg)](https://github.com/riddler/predicator-ex/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/riddler/predicator-ex/branch/main/graph/badge.svg)](https://codecov.io/gh/riddler/predicator-ex)
[![Hex.pm Version](https://img.shields.io/hexpm/v/predicator.svg)](https://hex.pm/packages/predicator)
[![Hex Downloads](https://img.shields.io/hexpm/dt/predicator.svg)](https://hex.pm/packages/predicator)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/predicator/)

Predicator is a secure, non-evaluative condition engine for end-user boolean
predicates. A user-authored expression like `score > 85 AND active` compiles
to a flat instruction list run by a small stack VM - there is no `eval`, no
`Code.eval_string`, and no dynamic code execution anywhere in the pipeline, so
untrusted input can never become code.

The language covers comparisons, arithmetic, logical operators, dates and
durations, lists and objects, [nested data access](docs/guides/nested-data-access.md),
and both [builtin and custom functions](docs/reference/language.md).

## Installation

Add `predicator` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:predicator, "~> 3.7"}
  ]
end
```

## Quick Start

```elixir
iex> Predicator.evaluate!("score > 85 AND active", %{"score" => 92, "active" => true})
true

iex> {:ok, instructions} = Predicator.compile("score > threshold")
iex> Predicator.evaluate!(instructions, %{"score" => 95, "threshold" => 80})
true

iex> Predicator.evaluate("score > 85", %{"score" => 92})
{:ok, true}
```

## Documentation

- [Language reference](docs/reference/language.md) - operators, builtin
  functions, data types, and error shapes
- [Nested data access](docs/guides/nested-data-access.md) - dot and bracket
  notation over deep contexts
- [Custom functions](docs/guides/custom-functions.md) - extending the function
  set per evaluation
- [Location expressions](docs/guides/location-expressions.md) - SCXML
  assignment targets and writing into a context
- [Architecture and language reference](docs/architecture.md) - the grammar
  with precedence, the compilation pipeline, and the component map
- [Architecture decision records](docs/adr/README.md) - the reasoning behind
  the design

## Migrating from `=`

Using `=` for equality still works but is deprecated: parsing one now emits a
warning, and **Predicator 4.0 makes expression-position `=` a parse error** -
`=` is reserved for assignment in the forthcoming statement grammar. Migrate to
`==` before upgrading, or silence the warning with
`config :predicator, deprecation_warnings: false`. See
[ADR-0002](docs/adr/0002-the-equals-grammar-break.md) for the reasoning.

## Cross-Language Siblings

Predicator has sibling implementations in Ruby and JavaScript, in the
[riddler/predicator](https://github.com/riddler/predicator) monorepo. The
instruction list, not the expression string, is the interchange format
between them; the divergences (including the `=` break above) are described
in [docs/architecture.md](docs/architecture.md).

## Development

See `CLAUDE.md` for the contributor workflow and
[docs/architecture.md](docs/architecture.md) for the quality-check commands.

## License

MIT - see [LICENSE](LICENSE).
