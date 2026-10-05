# Predicator

[![CI](https://github.com/riddler/predicator-ex/actions/workflows/ci.yml/badge.svg)](https://github.com/riddler/predicator-ex/actions/workflows/ci.yml)
[![Hex.pm Version](https://img.shields.io/hexpm/v/predicator.svg)](https://hex.pm/packages/predicator)
[![Hex Downloads](https://img.shields.io/hexpm/dt/predicator.svg)](https://hex.pm/packages/predicator)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/predicator/)
[![codecov](https://codecov.io/gh/riddler/predicator-ex/branch/main/graph/badge.svg)](https://codecov.io/gh/riddler/predicator-ex)
[![License](https://img.shields.io/hexpm/l/predicator.svg)](https://github.com/riddler/predicator-ex/blob/main/LICENSE)

A small, safe predicate language for Elixir: parse a rule a person wrote, such
as `renewals < 3 AND NOT on_hold`, and evaluate it against a context of data.
A rule compiles to a flat list of instructions that a small stack machine
runs, so the text never becomes code. Short programs - assignments, `if`/`else`
and `while` - run the same way and write their results into the context.

## Why a predicate language of its own

Without one, an application that lets its users or its configuration decide
when something may happen has two poor choices. It can write every condition
in code, so each new rule waits for a release; or it can evaluate the text a
person typed, so a typo or a hostile string runs inside the application. With
Predicator the rule is data: it is parsed by a grammar of comparisons, logic,
arithmetic, membership, dates, lists and function calls, compiled to
instructions that are plain terms you can store, and evaluated with no `eval`
anywhere in the path. A rule that names a value the data does not carry comes
back as an error value rather than a crash, and the same compiled rule runs as
often as you like.

## Installation

Add `predicator` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:predicator, "~> 9.4"}
  ]
end
```

## Basic usage

A library loan: a copy of a book lent to a patron, due on a date, renewed,
returned or lost. The library lets staff write the renewal rule as text.
Compile it once, evaluate it against each loan, and read a missing value as an
error rather than a crash; a short program records the renewal itself.

```elixir
iex> {:ok, may_renew} = Predicator.compile("status == 'on_loan' AND renewals < 3 AND NOT on_hold")
iex> Predicator.evaluate(may_renew, %{"status" => "on_loan", "renewals" => 1, "on_hold" => false})
{:ok, true}
iex> Predicator.evaluate(may_renew, %{"status" => "on_loan", "renewals" => 3, "on_hold" => false})
{:ok, false}
iex> {:error, error} = Predicator.evaluate(may_renew, %{"status" => "on_loan"})
iex> error.variable
"renewals"
iex> {:ok, context} = Predicator.execute("if renewals < 3 { renewals = renewals + 1; due_in_days = 21 }", %{"renewals" => 1})
iex> context.data
%{"due_in_days" => 21, "renewals" => 2}
```

`may_renew` is a plain list of instructions, so it can sit in ETS, in a
process's state or in a database column until the next loan comes back.

## Documentation

- Learn
  - [Basic usage](#basic-usage): a renewal rule compiled once and evaluated against loans.
- Do
  - [Add custom functions](docs/guides/custom-functions.md): give rules a function of your own, and the host state it reads.
  - [Embed compiled programs](docs/guides/embedding.md): store a compiled rule, check its instruction-set version, and evaluate it later.
  - [Port Predicator to another language](docs/guides/porting.md): implement the instruction set and verify it against the conformance corpus.
- Look up
  - [Language reference](docs/reference/language.md): operators, builtin functions, data types, statements, and error shapes.
  - [Running a program from Elixir](docs/reference/language.md#running-a-program-from-elixir): `execute/3`, `execute_value/3`, and the roots a program may not overwrite.
  - [The vocabulary for an editor](docs/reference/language.md#the-vocabulary-for-an-editor): every operator, keyword and function name, for a completion list.
  - [Nested data access](docs/guides/nested-data-access.md): dot and bracket notation over deep contexts.
  - [Location expressions](docs/guides/location-expressions.md): the targets an assignment may write, and how they resolve.
  - [The simple subset](docs/guides/simple-subset.md): a rule as field, operator and value rows, for a form-based editor.
  - [AST reference](https://github.com/riddler/predicator-ex/blob/main/docs/reference/ast.md): the tree `Predicator.parse/2` returns, node by node.
  - [ISA reference](docs/isa.md): the instruction set's opcodes, stack effects, error semantics and versions.
  - [API reference](https://hexdocs.pm/predicator/api-reference.html): every public module and function.
  - [The changelog](CHANGELOG.md): what changed in each version.
- Understand
  - [Architecture](docs/architecture.md): the compilation pipeline, the component map, and the design decisions behind them.
  - [Cross-language siblings](docs/architecture.md#cross-language-siblings): how implementations in other languages adopt each instruction-set version.
  - [Why `=` is assignment, never equality](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0002-the-equals-grammar-break.md): the grammar break and what it left untouched.
  - [Why this implementation leads the instruction set](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0003-the-elixir-implementation-leads-the-isa.md): the versioned contract the siblings follow.
  - [The decision records](https://github.com/riddler/predicator-ex/blob/main/docs/adr/README.md): the reasoning behind the rest of the design.

## Compatibility

Predicator needs Elixir 1.18 or later (`elixir: "~> 1.18"` in `mix.exs`) and
has no runtime dependencies.

A compiled rule carries the version of the instruction set it was compiled
for, which moves separately from the package version. Check that version
before evaluating a rule stored under an earlier release, and the rule either
still runs or is refused with a message naming why, never silently mis-run;
[Embed compiled programs](docs/guides/embedding.md#check-the-isa-version-before-you-run-a-stored-program)
shows the check. Every change a caller can observe is recorded in the
[changelog](CHANGELOG.md).

## Contributing

[docs/contributing.md](https://github.com/riddler/predicator-ex/blob/main/docs/contributing.md)
has the quality-check commands and the checklists for adding operators and
data types.

## License

MIT - see [LICENSE](https://github.com/riddler/predicator-ex/blob/main/LICENSE).
