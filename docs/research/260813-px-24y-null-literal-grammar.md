---
date: 2026-08-13T17:09:36-0600
researcher: Claude
git_commit: f2ac226152775c4a4b8cfc13f57194139957535b
branch: px-24y-null-literal-grammar
repository: predicator-ex
beads_issue: px-24y
topic: "Adding a null literal to the predicator grammar: how reserved words work today and the blast radius of reserving one more"
tags: [research, codebase, lexer-parser, evaluator, docs, conformance, isa]
status: complete
last_updated: 2026-08-13
last_updated_by: Claude
---

# Research: Adding a null literal to the grammar (px-24y)

**Date**: 2026-08-13T17:09:36-0600
**Git Commit**: f2ac226152775c4a4b8cfc13f57194139957535b
**Branch**: px-24y-null-literal-grammar
**Bead**: px-24y (depends on px-o9v, closed)

## Research Question

px-24y is the deferred **literal half** of px-o9v. px-o9v gave null a value,
semantics at every opcode, and corpus coverage; it deliberately gave null no
source spelling, because a `null` keyword is another reserved word and that is a
breaking change. This document maps the codebase as it stands today: how
reserved words are handled, how a literal reaches the compiled `lit` operand
form, what the full blast radius of reserving one more word is, how conformance
cases are authored and generated, what `docs/isa.md` §§1/3/6 already say, which
doctests pin the current identifier behavior, and how this project has taken
breaking and reserved-word changes before.

It documents what exists. It does not design the change.

## Summary

**The mechanical change is small and has an exact, recent template.** Reserving
`undefined` in 5.0.0 (px-ocp) touched four production clauses - one in the
lexer, two in the parser, one in the `StringVisitor` - and nothing else in
`lib/`. The compiler, the instructions visitor, and the evaluator need no change
at all, because every literal collapses to one AST tag (`{:literal, value,
pos}`) that lowers through a single generic clause to `["lit", value]`, and the
evaluator's `lit` clause matches the opcode name only and never inspects the
operand.

**The blast radius of reserving `null` is remarkably narrow - narrower than
px-o9v's bead text implies.** An exhaustive sweep found **zero** uses of `null`
as a predicate identifier in `lib/`, `test/`, `conformance/cases/`,
`conformance/corpus/`, or `README.md`. Every one of px-o9v's own corpus null
cases sources its null from `context` (`{"x": null}`) with `x`/`y` identifiers,
so **the corpus needs no sweep at all** - only additive cases. The entire live
breakage is **four doctest lines in one file**, plus prose in three files that
becomes false.

**The two doctests px-24y must update are
[`docs/reference/language.md:929-934`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/reference/language.md#L929-L934) and [`docs/reference/language.md:940-945`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/reference/language.md#L940-L945).**
They are executed by [`test/docs_examples_test.exs:14`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/test/docs_examples_test.exs#L14) via `doctest_file/1`, and
they exist precisely as the tripwire the bead describes: one asserts
`Predicator.compile("x === null")` produces `[["load","x"],["load","null"],
["compare","STRICT_EQ"]]`, the other asserts that under `on_unbound: :error` the
phantom `null` variable raises an `UndefinedVariableError` naming `"null"`.
Both go red the moment `null` lexes as a keyword. That is by design.

**The ISA question is not a clean repeat of 5.0.0, and this is the one genuinely
new wrinkle.** px-ocp's argument for "no version move" was that `lit`'s operand
domain already admitted `:undefined`, so the compiler was only gaining a spelling
for an instruction it could already execute. §3's value domain already admits
null too (px-o9v put it there), so the same argument is available. **But
px-o9v's own clarifying sentence in §1 is scoped in a way that stops describing
null once the literal ships**: it excuses "widening §3's value domain with a
value that only a host-supplied context can produce, **and that no opcode can
place on the stack**" ([`docs/isa.md:33-38`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L33-L38)). A `null` literal makes `lit` place
null on the stack from a compiled artifact for the first time, so that sentence,
and §5's `lit` entry which says "the compiler never emits `["lit", nil]`, so no
stored artifact can contain one" ([`docs/isa.md:350-355`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L350-L355)), both become false as
written. Whether that is a version move or merely a prose correction is a live
question this research records rather than settles - see Open Questions.

**Nothing currently schedules the breaking bump px-24y is supposed to ride.**
The tracker has exactly two unfinished beads: px-24y itself and px-dnc (a
sabotage-note doc task). `mix.exs` is at `5.0.0`. There is no 6.0.0 bead, no
release bead, and no other breaking change queued to share the bump with.

## Detailed Findings

### 1. Reserved words in the lexer and parser

#### The reserved-word table is a function, not a data structure

`classify_identifier/1` ([`lib/predicator/lexer.ex:498-520`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/lexer.ex#L498-L520)) is a private
multi-clause function with one clause per reserved string and a catch-all. It is
the single decision point for keyword-vs-identifier. Full contents today:

| Source string | Token type | Value |
|---|---|---|
| `true` / `false` (`:499-500`) | `:boolean` | `true` / `false` |
| `undefined` (`:501`) | `:undefined` | `:undefined` |
| `AND`/`OR`/`NOT`/`and`/`or`/`not` (`:502-507`) | `:and_op`/`:or_op`/`:not_op` | the source string |
| `IN`/`in`/`CONTAINS`/`contains` (`:508-511`) | `:in_op`/`:contains_op` | the source string |
| `if`/`else`/`while` (`:512-514`) | `:if_kw`/`:else_kw`/`:while_kw` | the source string |
| `ago`/`from`/`now`/`next`/`last` (`:515-519`) | `:ago_op`/`:from_op`/`:now_op`/`:next_op`/`:last_op` | the source string |
| anything else (`:520`) | `:identifier` | the source string |

**`null` has no clause**, so it falls to [`lib/predicator/lexer.ex:520`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/lexer.ex#L520) and
becomes `{:identifier, "null"}`. That single line is what makes `x === null`
compile to a `load` today.

Matching is **exact-string and case-sensitive**: there is no `TRUE` clause and no
`UNDEFINED` clause, which is why `UNDEFINED`/`Undefined` stay ordinary
identifiers ([`test/predicator/lexer_test.exs:90-104`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/test/predicator/lexer_test.exs#L90-L104)). Naming convention within
the table: `_kw` marks statement keywords, `_op` marks operators, and a bare type
name (`:boolean`, `:undefined`, `:date`, `:datetime`) marks a *literal*.

A keyword is never allowed to become a function name:
`handle_regular_identifier/6` ([`lib/predicator/lexer.ex:522-555`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/lexer.ex#L522-L555)) consults
`classify_identifier/1` before deciding whether a following `(` makes a
`:function_name`, so `undefined(` is handled for free
([`lib/predicator/lexer.ex:537-547`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/lexer.ex#L537-L547), tested at
[`test/predicator/lexer_test.exs:106-116`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/test/predicator/lexer_test.exs#L106-L116)).

#### The parser folds every literal into one AST tag

`parse_primary_token/2` has adjacent clauses for the two literal keyword
families, and both produce the **same** node shape:

- boolean: [`lib/predicator/parser.ex:1365-1367`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/parser.ex#L1365-L1367) →
  `{:literal, value, leaf_loc(...)}`
- undefined: [`lib/predicator/parser.ex:1370-1372`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/parser.ex#L1370-L1372) →
  `{:literal, :undefined, leaf_loc(...)}`

There is no `:undefined_literal` AST tag. The AST type is
`{:literal, value(), position()}` ([`lib/predicator/parser.ex:159-160`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/parser.ex#L159-L160)), and the
parser-local `value()` union at [`lib/predicator/parser.ex:122-130`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/parser.ex#L122-L130) enumerates
what may sit in that slot - it currently ends in `| :undefined` and does **not**
include `nil`.

#### Four other sites enumerate keywords, each independently

This is the part that is easy to under-count. Reserving a word touches more than
the lexer table:

1. **`format_token/2`** ([`lib/predicator/parser.ex:1561-1613`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/parser.ex#L1561-L1613)) - names a token in
   an error message, one clause per token type, `:undefined` at `:1566`. **It has
   no catch-all.** px-ocp's plan calls this "the easiest thing in the change to
   miss": without a clause, `user.<kw>` and `{<kw>: 1}` raise
   `FunctionClauseError` instead of returning a `ParseError`, which is an
   ADR-0004 breach.
2. **Statement-keyword rejection** ([`lib/predicator/parser.ex:1442-1447`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/parser.ex#L1442-L1447)) -
   matches `kw in [:if_kw, :else_kw, :while_kw]` and emits "'X' is a statement
   keyword, not an expression". `undefined` has no such clause and needs none; a
   literal keyword is legal in expression position.
3. **Property access after `.`** ([`lib/predicator/parser.ex:1263-1290`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/parser.ex#L1263-L1290)) -
   whitelists token types `:identifier, :last_op, :next_op, :ago_op, :from_op,
   :now_op` at `:1270`. Any other type, including a literal keyword, errors at
   `:1284-1286`. This is why `user.undefined` is a parse error.
4. **Object keys** ([`lib/predicator/parser.ex:1768-1781`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/parser.ex#L1768-L1781)) - accepts only
   `:identifier` (bare) or `:string` (quoted). This is why `{undefined: 1}` fails
   while `{"undefined": 1}` parses.

Sites 3 and 4 are *whitelists by token type*, so they need no edit when a new
keyword arrives - the new token type simply is not on the list, and the break
falls out. That is why px-ocp's diff was four clauses and not eight.

#### Round-trip rendering

`StringVisitor` renders the undefined literal back to source with one
exact-value clause:
`defp do_visit({:literal, :undefined, _position}, _opts), do: "undefined"`
([`lib/predicator/visitors/string_visitor.ex:130`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/visitors/string_visitor.ex#L130)), sitting immediately after the
boolean clause at `:126-128`.

#### The reserved-word test suite

`test/predicator/reserved_words_test.exs` (237 lines) is the dedicated suite and
the exact template a `null` bead would follow. Its shape, per reserved word:

- one `describe` block per breakage site - variable name, bare property name,
  bare object key
- each block asserts from **all four public entry points**: `Predicator.parse/2`,
  `parse_program/2`, `evaluate/3`, `compile/1`
- one message constant per site, shared across the four assertions
- one closing test that the quoted object key still parses

The `undefined` half runs [`test/predicator/reserved_words_test.exs:159-236`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/test/predicator/reserved_words_test.exs#L159-L236); the
`if`/`else`/`while` half runs `:13-157`. The error strings are asserted
verbatim, including line/column - e.g.
`@user_undefined_message "Expected property name after '.' but found 'undefined'"`
at `:185`.

Other keyword-enumerating tests: [`test/predicator/lexer_test.exs:65-116`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/test/predicator/lexer_test.exs#L65-L116)
(tokenization plus case-sensitivity) and `test/predicator/parser_test.exs:34-56,
145-176` (AST shape).

### 2. How a literal reaches the compiled `lit` operand

The path is short and almost entirely generic:

```
source
  → lexer   classify_identifier/1        lib/predicator/lexer.ex:498-520
  → parser  parse_primary_token/2        lib/predicator/parser.ex:1365-1372
            {:literal, value, position}
  → Compiler.to_instructions/2           lib/predicator/compiler.ex:58-60
  → Visitor.accept/3                     lib/predicator/visitor.ex:65-68
  → InstructionsVisitor.visit_annotated/2
            [{["lit", value], position}]  lib/predicator/visitors/instructions_visitor.ex:174-176
  → Evaluator ["lit", value] → push      lib/predicator/evaluator.ex:489-491
```

The three load-bearing facts:

- **`lib/predicator/compiler.ex` has no literal logic at all.** It is a facade
  naming `InstructionsVisitor` and delegating.
- **The lowering clause is generic.** `visit_annotated({:literal, value,
  position}, _opts)` ([`lib/predicator/visitors/instructions_visitor.ex:174-176`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/visitors/instructions_visitor.ex#L174-L176))
  passes `value` through structurally. Numbers, booleans, dates, durations, and
  `:undefined` all use it; a null would too, with no new clause. (Note the
  all-literal list fold at
  [`lib/predicator/visitors/instructions_visitor.ex:279-286`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/visitors/instructions_visitor.ex#L279-L286), which collapses an
  all-literal list into one `["lit", list]`.)
- **The evaluator does not validate the operand.**
  `execute_instruction(evaluator, ["lit", value])`
  ([`lib/predicator/evaluator.ex:489-491`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/evaluator.ex#L489-L491)) is guardless and pushes whatever it is
  handed. No type-domain check exists anywhere on the `lit` path.

#### The visitor behaviour gives no exhaustiveness; a binding test does

`Predicator.Visitor` declares exactly one callback, `visit/2`
([`lib/predicator/visitor.ex:52`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/visitor.ex#L52)). There is no per-node callback, so `@behaviour`
compliance guarantees nothing about clause coverage. That gap is closed by
`test/predicator/visitor_clause_coverage_test.exs`, a binding test listed in
`.claude/wurk.json`'s `gate.sabotage.test_roots`. It:

- expands `Parser.visitable/0`'s union via `Code.Typespec.fetch_types/1` down to
  tuple constructors, asserting exactly **23** today
  ([`test/predicator/visitor_clause_coverage_test.exs:48`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/test/predicator/visitor_clause_coverage_test.exs#L48), `:184-225`)
- source-parses both visitor files with `Code.string_to_quoted/1` and reads the
  leading tag atom off every private dispatch clause head (`:233-263`)
- asserts the two sets are equal **in both directions** (`:111-123`, `:163-176`)

A `null` literal that reuses the existing `{:literal, value, pos}` tag adds no
constructor, so this test would not move. A new tag would move it.

#### The opcode registry ignores operands entirely

`@opcodes` in [`lib/predicator/instructions.ex:64-96`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/instructions.ex#L64-L96) maps opcode name to
`%{isa: ..., tier: ...}`; `"lit" => %{isa: 1, tier: 1}` at `:65`. The
`opcode_info` type (`:53-57`) has **no operand-domain field**. `required_isa/1`
(`:292-303`) and `opcode_version/2` (`:305-320`) match `[opcode | _operands]` and
never inspect the operand. **The value a `lit` carries has no effect on the ISA
version an instruction list reports needing.** This is exactly px-ocp's third
argument against a bump (see §6 below).

`@isa_version 6` is pinned at [`lib/predicator/instructions.ex:45`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/instructions.ex#L45), surfaced by
`Predicator.isa_version/0` ([`lib/predicator.ex:660`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator.ex#L660)), and bound to
[`docs/isa.md:62`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L62)'s prose by [`test/predicator/isa_sync_test.exs:86-88`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/test/predicator/isa_sync_test.exs#L86-L88).

#### The conformance codec already handles null

`lib/predicator/conformance/values.ex` tags exactly four types (`date`,
`datetime`, `duration`, `undefined`). px-o9v added the null clauses:

- `to_json(nil), do: {:ok, nil}` ([`lib/predicator/conformance/values.ex:77`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/conformance/values.ex#L77)),
  with the comment at `:74-76` explaining that null is JSON-native and needs no
  tag
- `from_json(nil), do: {:ok, nil}` ([`lib/predicator/conformance/values.ex:131`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/conformance/values.ex#L131))

So a `["lit", nil]` operand round-trips through plain JSON cleanly - unlike
`["lit", :undefined]`, which is one of px-a2w's four lossy types
([`docs/isa.md:205-210`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L205-L210)). **A null literal does not enlarge px-a2w's problem.**

`Predicator.Types.value/0` ([`lib/predicator/types.ex:38-66`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/types.ex#L38-L66)) already ends
`| :undefined | nil`, widened by px-o9v.

### 3. Blast radius of reserving `null`

An exhaustive sweep across `lib/`, `test/`, `docs/`, `conformance/`,
`README.md`, and `CHANGELOG.md` distinguishing `null`-as-predicate-identifier
from JSON `null` / Elixir `nil` / concept prose.

#### What actually breaks (executable)

Four doctest lines, all in one file, all executed by
[`test/docs_examples_test.exs:14`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/test/docs_examples_test.exs#L14):

| Location | Content |
|---|---|
| [`docs/reference/language.md:930`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/reference/language.md#L930) | `iex> Predicator.compile("x === null")` |
| [`docs/reference/language.md:931`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/reference/language.md#L931) | `{:ok, [["load", "x"], ["load", "null"], ["compare", "STRICT_EQ"]]}` |
| [`docs/reference/language.md:932`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/reference/language.md#L932) | `iex> Predicator.evaluate("x === null", %{"x" => nil})` |
| [`docs/reference/language.md:942`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/reference/language.md#L942) | `Predicator.evaluate("x === null", Predicator.Context.new(%{"x" => nil}, on_unbound: :error))` |
| [`docs/reference/language.md:944`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/reference/language.md#L944) | `{Predicator.Errors.UndefinedVariableError, "null"}` |

[`docs/reference/language.md:931`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/reference/language.md#L931) carries the **only** `["load", "null"]` operand
in any executable artifact in the repo. `:944` is the only assertion that `null`
resolves as an unbound *variable name*.

#### What becomes false (prose)

- [`docs/reference/language.md:922-927`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/reference/language.md#L922-L927) - "**Writing `null` anyway does not fail -
  it reads a variable.** `null` is not a reserved word, so it lexes as an
  ordinary identifier and compiles to a `load`"
- [`docs/reference/language.md:936-938`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/reference/language.md#L936-L938) - "the phantom `null` variable is then an
  `UndefinedVariableError` naming it"
- [`docs/reference/language.md:910`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/reference/language.md#L910) - "**There is currently no way to write a null
  literal in predicate text.**"
- [`docs/reference/language.md:394-405`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/reference/language.md#L394-L405) - the `### Reserved words` section, which
  lists `if`/`else`/`while`/`undefined` and does not mention `null`
- [`docs/isa.md:181-186`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L181-L186) - "`null` has no source spelling ... no grammar
  production emits a null ... never through `lit`"
- [`docs/isa.md:350-355`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L350-L355) - §5's `lit` entry: "no source spelling exists for it:
  the compiler never emits `["lit", nil]`, so no stored artifact can contain
  one"
- [`docs/isa.md:33-38`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L33-L38) - §1's px-o9v sentence, scoped to a value "that no opcode
  can place on the stack"
- [`CHANGELOG.md:20-21`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/CHANGELOG.md#L20-L21) - "There is no source spelling for null (no `null`
  keyword)"
- [`CHANGELOG.md:22-25`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/CHANGELOG.md#L22-L25) - "**The ISA version does not move**: no opcode name
  changed and no *instruction-list* operand form widened"
- [`docs/architecture.md:40`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/architecture.md#L40) - the EBNF `primary` production, which lists
  `UNDEFINED` but no `NULL`

#### What does not break - verified absent

- **No conformance case, authored or generated, has `null` in a `source`
  field.** Confirmed directly: `grep` for `"source":"...null..."` across
  `conformance/corpus/*.json` returns nothing. Every px-o9v null case uses `x`/`y`
  with `"context": {"x": null}` - e.g. [`conformance/cases/core.json:95-137`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/conformance/cases/core.json#L95-L137),
  [`conformance/cases/access.json:92-103`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/conformance/cases/access.json#L92-L103), [`conformance/cases/casts.json:22-26`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/conformance/cases/casts.json#L22-L26).
- No `["load", "null"]` anywhere in `lib/`, `test/`, or the corpus.
- No context map anywhere binds a key literally named `"null"`.
- `README.md` contains zero occurrences of `null`.
- No doctest in `lib/` uses `null` as an identifier.

Two near-misses that are **not** blast radius:
[`test/predicator/functions/qualified_functions_test.exs:313`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/test/predicator/functions/qualified_functions_test.exs#L313) uses `'null'` as a
single-quoted **string literal** inside predicate source, and `:177` feeds the
*string* `"null"` to `JSON.parse` through context. Neither is affected by a
keyword.

**Bottom line: the reserved-word sweep the bead anticipates is already clean.**
The corpus needs additive cases only, and the entire fixture churn is one docs
section.

### 4. Conformance: authoring and generation

#### Authored source

Sixteen files under `conformance/cases/*.json`, each a bare JSON array. The
schema is [`conformance/schema/case.json:1-87`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/conformance/schema/case.json#L1-L87):

| Field | Lines | Notes |
|---|---|---|
| `id` | `:8-12` | the only `required` field (`:84`); "globally unique, stable forever. Never renamed once shipped." |
| `source` | `:13-16` | string or null; exactly one of `source`/`instructions` non-null |
| `instructions` | `:17-25` | for evaluator-only cases no source compiles to |
| `context` | `:26-30` | tagged-value encoded, defaults to `{}` |
| `expected` | `:31-68` | `oneOf` `{"result": ...}` or `{"error": {type, reason}}` |
| `tier` | `:69-73` | an *assertion*, computed as `max(tier(opcode))` |
| `features` | `:74-78` | merged with the computed set |
| `notes` | `:79-82` | carried into the shipped corpus |

`additionalProperties: false` at `:85`. An author supplies only
`id`/`source`/`context`/`expected`/`notes`; the generator computes
`instructions`, `tier`, and `features`, and **fails loudly** if `expected`
disagrees with the real pipeline.

`"source": null` marks an **evaluator-only** case ([`conformance/README.md:41-55`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/conformance/README.md#L41-L55))
- a compiler-scoped runner filters `source != null` and never reports those ids.
In authored files the key is usually omitted rather than written as `null`; the
generator materializes the explicit field.

#### The model cases

The `core/literal-undefined` family ([`conformance/cases/core.json:72-93`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/conformance/cases/core.json#L72-L93)) is the
direct template - four tier-1 cases, the first carrying the note that names the
ISA reasoning:

> "the undefined literal (px-ocp): a source spelling for a lit operand the ISA's
> value domain already admitted (docs/isa.md section 3), so no ISA version moves
> - surface syntax is outside the ISA (section 6)"

px-o9v's null family ([`conformance/cases/core.json:94-137`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/conformance/cases/core.json#L94-L137)) sits immediately
after it, all context-sourced. One of its notes states the gap px-24y closes:

> "There is no null literal in the grammar, so the null comes from context rather
> than a source spelling"

#### Generation

`mix corpus.generate` (`lib/mix/tasks/corpus.generate.ex`) reads
`conformance/cases/*.json` (`:34`, `:72-100`), runs each case through the real
compiler and evaluator via `Predicator.Conformance.Generator.generate/1`, and
writes `conformance/corpus/tier-*.json` plus `conformance/manifest.json`
(`:107-131`, `:145-150`). `--check` diffs without writing (`:152-176`).

`corpus_hash` (`hash_corpus/1`, `:139-143`) is
`"sha256:" <> Base.encode16(:crypto.hash(:sha256, content), case: :lower)` over
the concatenated tier-file bytes in tier order.

`build_files/0` (`:64-70`) is public specifically so
`corpus_freshness_test.exs` can reuse it.

#### The binding tests

| Test | Enforces |
|---|---|
| `test/predicator/conformance/corpus_freshness_test.exs` | the checked-in corpus byte-matches a regeneration |
| `test/predicator/conformance/schema_validation_test.exs` | every generated case validates against `conformance/schema/corpus.json` |
| `test/predicator/conformance/opcode_coverage_test.exs` | every opcode in the current ISA set appears in some case; the exclusion list matches `conformance/README.md` |
| `test/predicator/conformance/function_coverage_test.exs` | the same for builtin functions |
| `test/predicator/conformance/values_test.exs` | the tagged-value codec round-trips every value type, `nil` included (`:9`, `:11-36`) |
| `test/predicator/conformance/ratchet_registry_test.exs` | `conformance/examples/registry.example.json` validates and satisfies RATCHET's R5 completeness |
| `test/predicator/conformance/package_boundary_test.exs` | no shipped `lib/` module outside the conformance tree references it |

All seven are in `.claude/wurk.json`'s `gate.sabotage.test_roots`.

#### The corpus cannot pin a keyword - and that split is deliberate

px-ocp's plan states it directly
([`docs/plans/260812-px-ocp-undefined-literal.md:442-453`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/plans/260812-px-ocp-undefined-literal.md#L442-L453)):

> The corpus can pin what `undefined` **compiles to** and what it **evaluates
> to** under the default policy. It cannot pin that `undefined` lexes as a
> keyword: surface syntax and parse errors are outside its scope
> ([`conformance/README.md:14-24`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/conformance/README.md#L14-L24), [`docs/isa.md:704-719`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L704-L719)), and it carries no
> `on_unbound` field ... Phase 1's ExUnit tests are where those two claims live,
> and that split is deliberate.

[`docs/isa.md:829-834`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L829-L834) restates the boundary: the corpus does not cover surface
syntax and does not cover parse or lexer errors.

#### The ratchet obligation of a `corpus_hash` rotation

`conformance/RATCHET.md` specifies a per-sibling registry pinning
`corpus_hash` (`:32`) - "The pin". Rule 1 (`:129-171`) fails a run whose entry is
not in the pinned corpus's case set; the check step's R1 (`:248-249`, `:264-271`)
treats any hash mismatch as a **hard failure**: "if the corpus moved, the claims
are unverified." Rule 3 (`:173-196`) requires verify-then-add, refusing to write
if any existing entry regressed - "There is no path through this that silently
shrinks."

**A non-obvious in-repo obligation**: `conformance/examples/registry.example.json`
is **hand-maintained**, not generated. px-ocp's plan
([`docs/plans/260812-px-ocp-undefined-literal.md:511-524`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/plans/260812-px-ocp-undefined-literal.md#L511-L524)) records that
`ratchet_registry_test.exs` goes red on both the pin (`:81`) and R5 completeness
(`:112`) without updating it, that no mix task produces it, and that the way to
regenerate it is a throwaway `mix run` script mirroring the canonical encoding
the test re-implements at `ratchet_registry_test.exs:152-172`.

[`conformance/README.md:111-113`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/conformance/README.md#L111-L113) and [`conformance/RATCHET.md:229-231`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/conformance/RATCHET.md#L229-L231) both already
carry px-o9v's carve-out telling a sibling that a bare JSON `null` decodes to
predicator's null value and never to `:undefined`.

### 5. `docs/isa.md` §§1, 3, 5, 6 as they stand

#### §1 Versioning ([`docs/isa.md:18-66`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L18-L66))

The rule that matters, at [`docs/isa.md:33-38`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L33-L38), with px-o9v's clarifying sentence
attached:

> - Adding an operand form or widening an accepted type is a new version but not
>   a new name. This rule speaks to operand forms carried *in the instruction
>   list* - widening §3's value domain with a value that only a host-supplied
>   context can produce, and that no opcode can place on the stack, moves no
>   version, because no opcode-name scan can express it (§6's `undefined`
>   literal precedent, and line 415's, are the same shape).

Also load-bearing: "An opcode's semantics never change under its own name"
(`:29-32`), which is what makes an opcode-name scan a sound version check.

Current version stated at [`docs/isa.md:62`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L62) as the exact string
`Current version: **ISA v6**.`, bound by
[`test/predicator/isa_sync_test.exs:86-88`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/test/predicator/isa_sync_test.exs#L86-L88).

#### §3 Value types ([`docs/isa.md:174-243`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L174-L243))

The domain (`:176-177`) is eleven types: integer, float, string, boolean, list,
map, `Date`, `DateTime`, duration, `null`, `:undefined`.

px-o9v added [`docs/isa.md:179-186`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L179-L186):

> `null` and `:undefined` are both first-class values and neither is the other:
> `:undefined` is an absence - no value was ever supplied - while `null` is a
> value that is present and empty. `null` has no source spelling: unlike
> `:undefined`, which as of the change that added this sentence has a literal
> keyword (§5's `lit` entry, §6), no grammar production emits a null. It enters
> the value domain only through a host-supplied context, a `load` of a bound
> null, an `access`/`bracket_access` result, or a function return - never through
> `lit`.

The "Crossing a plain-JSON boundary" subsection (`:197-243`, px-a2w) names null
among the **seven JSON-native types** that survive a round trip (`:199-200`), and
lists only `Date`, `DateTime`, duration, and `:undefined` in the lossy table
(`:205-210`).

#### §5's `lit` entry ([`docs/isa.md:350-355`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L350-L355))

> - **`lit`** - pushes the operand unchanged. No error path. The operand may be
>   any value in §3's value domain, `:undefined` included; a source spelling for
>   that operand (the `undefined` literal keyword) exists as of the change that
>   added this sentence. `null` is legal under that same widened §3 domain in
>   principle, but no source spelling exists for it: the compiler never emits
>   `["lit", nil]`, so no stored artifact can contain one (§3).

§5's `compare` entry also carries null's four-row matrix at [`docs/isa.md:392-401`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L392-L401).

#### §6 Not in the ISA ([`docs/isa.md:769-794`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L769-L794))

A flat bulleted list of four items - **not** a table, no schema. The relevant
bullet (`:778-786`) is where the `undefined` literal's precedent lives:

> - Surface syntax, including the `=` grammar break (ADR-0002). Both `=` and `==`
>   compile to `["compare", "EQ"]` ... The `undefined` literal keyword is the
>   same shape: it compiles to the existing `["lit", :undefined]`, an instruction
>   this ISA's value domain (§3) already admitted, so the new spelling attaches
>   to no opcode name and moves no version.

A new literal entry would structurally be either a third worked example appended
to this bullet or a bullet of its own - name the spelling, name the instruction
it compiles to, state the version consequence.

#### §7 Version history ([`docs/isa.md:796-812`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L796-L812))

| ISA | Introduced | Retired | Shipped in |
|---|---|---|---|
| v1 | everything else | - | up to 3.6.x |
| v2 | `jump_if_falsy_or_pop`, `jump_if_true_or_pop`, `make_list` | - | 3.7.0 |
| v3 | `store`, `pop` | `and`, `or` | 4.0.0 |
| v4 | `cast` | - | 5.0.0 |
| v5 | `jump`, `pop_jump_if_falsy` | - | 5.0.0 |
| v6 | `jump_backward` | - | 5.0.0 |

Neither the `undefined` literal nor px-o9v's null work added a row.

#### What `isa_sync_test.exs` actually binds

Only three surfaces: §1's `Current version:` line (`:86-88`), §4's opcode table
rows including the Removed-in column (`:38-62`, `:97-118`, `:216-259`), and §4's
tier-names table (`:273-291`). Plus evaluator clause heads (`:163-204`,
`:300-306`). **Edits confined to §3, §5 prose, or §6 do not trip it** - px-ocp's
plan relies on exactly that ([`docs/plans/260812-px-ocp-undefined-literal.md:185-195`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/plans/260812-px-ocp-undefined-literal.md#L185-L195)).

### 6. Precedent: how this project takes breaking and reserved-word changes

#### The `undefined` literal (5.0.0, px-ocp) - the closest template

`docs/plans/260812-px-ocp-undefined-literal.md`, three phases:

1. **Phase 1** (`:269-437`) - lexer clause + two typespecs, parser primary clause
   + `format_token/2` clause + typespec, `StringVisitor` clause. Instructions
   visitor and evaluator **explicitly unchanged**, stated so the implementer does
   not go looking (`:376-383`).
2. **Phase 2** (`:440-556`) - four tier-1 cases in `core.json`, one tier-3 case in
   `access.json`, `mix corpus.generate`, and the hand-written ratchet example.
3. **Phase 3** (`:560-665`) - architecture EBNF, four sites in
   `docs/reference/language.md`, two `docs/isa.md` prose clarifications, changelog.

Its **reserved, not contextual** reasoning (`:276-286`) is worth quoting, because
it applies verbatim to `null`:

> The two precedents in this codebase are `true`/`false` (reserved, in
> `classify_identifier/1`) and the seven cast type names (contextual, ADR-0011).
> The cast names can be contextual because `::` makes their position
> unambiguous ... `undefined` appears in ordinary primary-expression position ...
> which is not decidable and would make `x === undefined` mean different things
> depending on whether a variable named `undefined` happened to be bound.
> `undefined` is a literal, and every other literal keyword in this language is
> reserved.

Its **ISA Impact verdict** (`:143-201`) is no version move, on three independently
sufficient grounds: nothing widens; §6 excludes surface syntax; and a bump would
mint an unreachable version -

> `required_isa/1` computes a list's required version as `max` over
> `@opcodes[name].isa`. A v7 whose only content is "the compiler now emits an
> operand it could always execute" attaches to no opcode name, so no instruction
> list would ever report requiring it, and `opcode_set(7)` would equal
> `opcode_set(6)`.

It then ships a **negative obligation table** (`:170-184`) - ten sites each marked
"unchanged", introduced with "do **not** touch any of these" - and "**3.
Migration.** None."

Note that the *research* behind px-ocp
([`docs/research/260812-px-ocp-undefined-literal.md:363-422`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/research/260812-px-ocp-undefined-literal.md#L363-L422)) left the version
question deliberately open, observing that "shipping a *compiler that emits*
`["lit", :undefined]` for the first time is the operand-form widening §1 has in
mind", and enumerated the full obligation set a bump would carry. The plan
resolved it against a bump. **px-24y faces the same fork, with the added wrinkle
that px-o9v's §1 sentence was written on the assumption no opcode could place a
null on the stack.**

#### The changelog shape for a reserved word

Both 5.0.0 reservations live under `### Changed` (not Added, not Removed) and
share an identical four-part structure - *what the lexer now does; the three
breakage sites; the fix; the case-sensitivity carve-out*:

[`CHANGELOG.md:240-246`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/CHANGELOG.md#L240-L246):

> - **`undefined` is a reserved word.** The lexer now classifies it as a literal
>   keyword rather than a plain identifier, so a predicate that used it as a
>   variable name (`undefined = 3`), a bare property name (`user.undefined`), or a
>   bare object key (`{undefined: 1}`) is now a parse error. The fix is renaming
>   the variable or, for an object key, quoting it (`{"undefined": 1}`, which
>   still parses). Only the lowercase spelling is reserved - `UNDEFINED` and
>   `Undefined` stay ordinary identifiers.

[`CHANGELOG.md:231-239`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/CHANGELOG.md#L231-L239) is the `if`/`else`/`while` twin, adding the
reserve-early rationale: "All three words are reserved together even though
`while` does not gain real grammar until a later release, so the break lands once
instead of twice (ADR-0013)." [`CHANGELOG.md:150-151`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/CHANGELOG.md#L150-L151) later confirms that paid
off.

The `undefined` **literal** got its own `### Added` bullet
([`CHANGELOG.md:82-98`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/CHANGELOG.md#L82-L98)), separate from the reserved-word `### Changed` bullet. So
a literal reservation is documented as a **pair** of entries.

#### There is no `### Migration` heading and no migration guide file

Verified: `docs/guides/` holds `custom-functions.md`, `embedding.md`,
`location-expressions.md`, `nested-data-access.md`, `porting.md` - no migration
guide. Recent changelog entries embed the migration sentence in the prose of the
bullet itself. The only literal `#### Migration Guide` heading is at
[`CHANGELOG.md:1531`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/CHANGELOG.md#L1531) (1.0.0), and `**Migration Required**:` at `:1317` (3.0.0) is
the old style.

The one break that earned a durable home outside the changelog is `=`:
[`README.md:153-161`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/README.md#L153-L161) (`## Migrating from =`) and
[`docs/architecture.md:180-202`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/architecture.md#L180-L202) (`### The = grammar break (4.0)`).

#### Deprecation-first vs. straight break - the two precedents disagree

- **`=` (ADR-0002)**: a 3.8.0 deprecation warning was "the migration story and
  the entire notice period" ([`docs/adr/0002-the-equals-grammar-break.md:62-67`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/adr/0002-the-equals-grammar-break.md#L62-L67)),
  justified by a **known-consumer survey** (`:37-47`) finding statifier the only
  external consumer and already `==`-clean. 4.0.0 then made it a parse error and
  deleted the `deprecation_warnings` config ([`CHANGELOG.md:693-695`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/CHANGELOG.md#L693-L695)).
- **`if`/`else`/`while`/`undefined` (5.0.0)**: reserved outright, with **no
  warning release at all**. The px-3so.2 plan justified it by a sweep
  ([`docs/plans/260810-px-3so.2-if-else-parser.md:90-92`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/plans/260810-px-3so.2-if-else-parser.md#L90-L92)): "No existing test,
  doctest, or conformance case uses `if`, `else` or `while` as an identifier
  (grepped across `test/`, `conformance/cases/`, `docs/`), so the break costs no
  fixture churn."

**The deprecation-warning infrastructure no longer exists.** `grep -rn
"deprecat" lib/` returns nothing; it was deleted in 4.0.0. A warning-first path
for `null` would mean rebuilding it.

#### ADR-0002's transferable reasoning

ADR-0002 rejected both a position-dependent dual meaning and a per-caller grammar
config. The second rejection ([`docs/adr/0002-the-equals-grammar-break.md:29-35`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/adr/0002-the-equals-grammar-break.md#L29-L35))
is the one that generalizes: "two dialects of stored, user-authored rule strings
is a support burden forever, for a migration that is one loud parse error deep."

It also records the sibling consequence (`:78-84`): the Ruby and JavaScript
lexers do not adopt a break automatically, so a reserved word here is "a
documented, deliberate surface-syntax divergence until the siblings adopt the
same break on their own schedule" - consistent with ADR-0003.

### 7. Release state

- [`mix.exs:5`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/mix.exs#L5) - `@version "5.0.0"`, released 2026-08-12.
- [`CHANGELOG.md:8-77`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/CHANGELOG.md#L8-L77) - `## [Unreleased]` currently holds px-o9v's and px-a2w's
  entries under `### Added`, `### Documentation`, `### Changed`, `### Fixed`. All
  are non-breaking.
- Tracker state: 136 beads, **1 open** (px-dnc, a sabotage-note doc task) and **1
  in progress** (px-24y itself). No 6.0.0 bead, no release bead, no other queued
  breaking change.

Per CLAUDE.md's authority table, release mechanics require the user to ask
explicitly **and name the version**; they are never inferred from accumulated
`Unreleased` entries.

## Code References

- [`lib/predicator/lexer.ex:498-520`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/lexer.ex#L498-L520) - `classify_identifier/1`, the reserved-word table; `:520` is the catch-all that makes `null` an identifier today
- [`lib/predicator/lexer.ex:522-555`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/lexer.ex#L522-L555) - `handle_regular_identifier/6`, the function-name veto for keywords
- [`lib/predicator/parser.ex:1365-1372`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/parser.ex#L1365-L1372) - the boolean and undefined primary clauses, both producing `{:literal, value, pos}`
- [`lib/predicator/parser.ex:122-130`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/parser.ex#L122-L130) - the parser-local `value()` union, ending `| :undefined`
- [`lib/predicator/parser.ex:1561-1613`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/parser.ex#L1561-L1613) - `format_token/2`, no catch-all; `:1566` is the `:undefined` clause
- [`lib/predicator/parser.ex:1263-1290`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/parser.ex#L1263-L1290) - property-access token whitelist
- [`lib/predicator/parser.ex:1768-1781`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/parser.ex#L1768-L1781) - object-key token whitelist
- [`lib/predicator/parser.ex:1442-1447`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/parser.ex#L1442-L1447) - the statement-keyword rejection clause
- [`lib/predicator/visitors/string_visitor.ex:130`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/visitors/string_visitor.ex#L130) - the undefined round-trip clause
- [`lib/predicator/visitors/instructions_visitor.ex:174-176`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/visitors/instructions_visitor.ex#L174-L176) - the generic literal lowering to `["lit", value]`
- [`lib/predicator/compiler.ex:58-60`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/compiler.ex#L58-L60) - the facade
- [`lib/predicator/visitor.ex:52`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/visitor.ex#L52) - the single `visit/2` callback
- [`lib/predicator/evaluator.ex:489-491`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/evaluator.ex#L489-L491) - `lit` execution, guardless
- [`lib/predicator/instructions.ex:45`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/instructions.ex#L45) - `@isa_version 6`
- [`lib/predicator/instructions.ex:64-96`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/instructions.ex#L64-L96) - `@opcodes`; `"lit"` at `:65`
- [`lib/predicator/instructions.ex:292-320`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/instructions.ex#L292-L320) - `required_isa/1`, opcode-name only
- [`lib/predicator/types.ex:38-66`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/types.ex#L38-L66) - `value()`, ending `| :undefined | nil`
- [`lib/predicator/conformance/values.ex:77`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/conformance/values.ex#L77) - `to_json(nil)`
- [`lib/predicator/conformance/values.ex:131`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/predicator/conformance/values.ex#L131) - `from_json(nil)`
- [`lib/mix/tasks/corpus.generate.ex:64-70`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/mix/tasks/corpus.generate.ex#L64-L70) - `build_files/0`
- [`lib/mix/tasks/corpus.generate.ex:139-143`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/lib/mix/tasks/corpus.generate.ex#L139-L143) - `hash_corpus/1`
- [`test/predicator/reserved_words_test.exs:159-236`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/test/predicator/reserved_words_test.exs#L159-L236) - the `undefined` reservation suite, four entry points per breakage site
- [`test/predicator/lexer_test.exs:65-116`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/test/predicator/lexer_test.exs#L65-L116) - keyword tokenization and case sensitivity
- [`test/predicator/visitor_clause_coverage_test.exs:48`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/test/predicator/visitor_clause_coverage_test.exs#L48) - the 23-constructor assertion
- [`test/predicator/isa_sync_test.exs:86-88`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/test/predicator/isa_sync_test.exs#L86-L88) - binds [`docs/isa.md:62`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L62) to `@isa_version`
- [`test/docs_examples_test.exs:14`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/test/docs_examples_test.exs#L14) - `doctest_file("docs/reference/language.md")`
- [`docs/reference/language.md:929-934`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/reference/language.md#L929-L934) - **doctest 1**, the compile form
- [`docs/reference/language.md:940-945`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/reference/language.md#L940-L945) - **doctest 2**, the `on_unbound: :error` variant
- [`docs/reference/language.md:394-405`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/reference/language.md#L394-L405) - the reserved-words section
- [`docs/reference/language.md:8-27`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/reference/language.md#L8-L27) - the literals list; no `null` entry
- [`docs/isa.md:33-38`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L33-L38) - §1's operand-form rule with px-o9v's scoping sentence
- [`docs/isa.md:179-186`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L179-L186) - §3's null paragraph
- [`docs/isa.md:350-355`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L350-L355) - §5's `lit` entry
- [`docs/isa.md:392-401`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L392-L401) - §5's null comparison matrix
- [`docs/isa.md:778-786`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L778-L786) - §6's surface-syntax bullet
- [`docs/architecture.md:40`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/architecture.md#L40) - the EBNF `primary` production
- [`conformance/cases/core.json:72-93`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/conformance/cases/core.json#L72-L93) - the `core/literal-undefined` family
- [`conformance/cases/core.json:94-137`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/conformance/cases/core.json#L94-L137) - px-o9v's context-sourced null family
- [`conformance/schema/case.json:1-87`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/conformance/schema/case.json#L1-L87) - the authored case schema
- [`conformance/README.md:111-113`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/conformance/README.md#L111-L113) - the bare-JSON-null carve-out
- [`conformance/RATCHET.md:129-171`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/conformance/RATCHET.md#L129-L171) - the pin and what invalidates it
- [`CHANGELOG.md:82-98`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/CHANGELOG.md#L82-L98) - the `undefined` literal `### Added` entry
- [`CHANGELOG.md:231-246`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/CHANGELOG.md#L231-L246) - the two 5.0.0 reserved-word `### Changed` entries

## Architecture Documentation

**One AST tag for every literal.** `{:literal, value, position}` carries
numbers, booleans, dates, durations, and `:undefined`, distinguished only by the
Elixir term in the value slot. This is why the compiler and evaluator need no
change for a new literal keyword: the differentiation is entirely upstream, in
the lexer and parser. A `null` literal reusing this tag adds no visitor clause
and no `visitable/0` constructor.

**Keyword classification is a function, not data.** There is no reserved-word
list to append to; a new reserved word is a new `classify_identifier/1` clause.
The corollary is that "the reserved words" cannot be enumerated programmatically
- [`docs/reference/language.md:394-405`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/reference/language.md#L394-L405) is the human-readable list and nothing
binds it to the lexer.

**Breakage falls out of whitelists.** The property-access and object-key
positions accept an explicit set of token types. A new keyword's token type is
simply not on either list, so `user.null` and `{null: 1}` become parse errors
with no edit at those sites. Only `format_token/2` must be extended, and it must
be, because it has no catch-all and an omission is an ADR-0004 breach.

**Exhaustiveness is enforced by binding tests, not the type system.**
`Predicator.Visitor`'s single callback guarantees nothing;
`visitor_clause_coverage_test.exs` recomputes both sets at test time. Likewise
`isa_sync_test.exs` regex-binds only §1's version line and §4's tables, so §3/§5/§6
prose is unguarded and must be checked by reading.

**Version detection is opcode-name-only** (ADR-0003). `required_isa/1` never
inspects an operand. This is simultaneously px-ocp's strongest argument that a
literal moves no version, and the reason a version that *did* move for an operand
change would be unreachable by the scan [`docs/isa.md:29-32`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L29-L32) calls sound.

**Surface syntax is outside the ISA and outside the corpus** ([`docs/isa.md:769-794`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L769-L794),
`:829-834`). A keyword change can therefore be pinned by ExUnit but not by the
conformance corpus; the corpus can only pin what the literal compiles to and
evaluates to.

ADRs in scope: **ADR-0001** (ECMAScript-aligned falsiness; the instruction list as
interchange), **ADR-0002** (the `=` grammar break - the notice-period precedent),
**ADR-0003** (this repo leads the ISA; the corpus is exported specification;
siblings adopt on their own schedule), **ADR-0004** (errors are values - the
`format_token/2` obligation), **ADR-0005** (area labels as file-collision
prediction), **ADR-0011** (casts are an opcode - the contextual-keyword
counterexample), **ADR-0013** (control flow lowers to jumps; reserve-early
reasoning).

## Historical Context

- `docs/plans/260812-px-ocp-undefined-literal.md` - the three-phase plan px-24y
  should mirror. Its ISA Impact (`:143-201`), reserved-vs-contextual argument
  (`:276-286`), before/after breakage table (`:288-301`), and negative obligation
  table (`:170-184`) are all directly reusable in shape.
- [`docs/research/260812-px-ocp-undefined-literal.md:363-422`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/research/260812-px-ocp-undefined-literal.md#L363-L422) - the research that
  left the version question open and enumerated both readings. The honest record
  that this fork is genuinely arguable.
- `docs/plans/260813-px-o9v-null-vs-undefined-in-context.md` - the parent plan.
  D1-D6 settle null's semantics; "What We're NOT Doing" (`:406-441`) scopes out
  the literal half; Residual Note 1 (`:1127-1135`) is the instruction that filed
  px-24y, naming `area:lexer-parser`, `area:visitors`, `area:docs`,
  `area:conformance`.
- [`docs/plans/260810-px-3so.2-if-else-parser.md:90-92`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/plans/260810-px-3so.2-if-else-parser.md#L90-L92) - the sweep precedent:
  a reserved-word break justified by grepping `test/`, `conformance/cases/`, and
  `docs/` and finding no identifier uses. This research is that same sweep for
  `null`, and it comes out the same way.
- `docs/research/260813-px-o9v-null-vs-undefined-in-context.md` - the value-half
  research. Note `:274-275` is now stale: it says "There is no mention of `null`
  as a concept anywhere in the reference", which px-o9v's own Phase 3 fixed.
- `docs/adr/0002-the-equals-grammar-break.md` - the one grammar break that took a
  notice period, and the known-consumer survey that justified it being only one
  release.
- [`docs/plans/260808-px-7jd.4-feature-history-sort.md:3-12`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/plans/260808-px-7jd.4-feature-history-sort.md#L3-L12) - deleted
  `docs/architecture.md`'s `## Recent Additions` and `## Breaking Changes`
  sections. **CLAUDE.md's claim that `docs/architecture.md` carries "per-feature
  history" is stale**; that history now lives in `CHANGELOG.md`. The surviving
  named-subsection format is used only for the `=` break, under Cross-Language
  Siblings.

## Related Research

- `docs/research/260813-px-o9v-null-vs-undefined-in-context.md` - null's value half
- `docs/research/260812-px-ocp-undefined-literal.md` - the undefined literal
- `docs/research/260813-px-a2w-plain-json-round-trip.md` - non-JSON-native operands; null is explicitly **not** in that set
- `docs/research/260807-px-t2v-px-z5m-isa-retirement-and-pop.md` - how `docs/isa.md`'s tables are regex-bound

## ISA Impact

Recorded per `.claude/wurk/research.md`'s rule, because the subject touches the
instruction set. **This section states the question, not an answer** - resolving
it is the plan's job.

**What changes materially**: for the first time, the compiler would emit
`["lit", nil]`. Null enters the value domain today only through a host-supplied
context, a `load`, an `access`, or a function return; a literal makes it reachable
from a compiled artifact.

**The argument for no version move** (px-ocp's, transplanted): §3's value domain
already admits null, `lit`'s documented operand domain is "any value in §3's
value domain", the evaluator already executes `["lit", nil]` correctly, §6
excludes surface syntax, and a v7 attaching to no opcode name would be
unreachable by `required_isa/1`.

**The argument the other way**, which is stronger here than it was for
`undefined`: px-o9v wrote §1's clarifying sentence
([`docs/isa.md:33-38`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L33-L38)) with an explicit condition - a value "that only a
host-supplied context can produce, **and that no opcode can place on the
stack**". A `null` literal falsifies the second clause. §5's `lit` entry
([`docs/isa.md:350-355`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L350-L355)) likewise asserts "the compiler never emits `["lit",
nil]`, so no stored artifact can contain one", which becomes false. So px-24y
cannot simply cite px-o9v's sentence; it must either amend it or explain why the
amendment does not imply a version.

**What does not change either way**: no opcode is added, renamed, or retired; no
existing instruction list changes meaning or becomes invalid; §7 gains no row on
the "no move" reading; and because null is JSON-native ([`docs/isa.md:199-200`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/isa.md#L199-L200)),
a `["lit", nil]` operand round-trips through plain JSON cleanly, so px-a2w's
lossy set stays at four.

**Library semver is independent and is unambiguous**: reserving a word is a
breaking change to the grammar, so it needs a major bump regardless of what the
ISA integer does.

## Open Questions

1. **Nothing schedules the breaking bump.** px-24y's acceptance criteria require
   it to "land on a breaking bump, never forcing one", but the tracker has no
   6.0.0 bead, no release bead, and no other queued breaking change - px-24y and
   px-dnc are the only unfinished beads, and px-dnc touches docs only. Whether
   px-24y should sit until something else forces a major, or whether the null
   literal is itself sufficient reason to cut 6.0.0, is a human scheduling call
   under CLAUDE.md's release row. **No agent may infer a release from this.**
2. **Does §1's px-o9v sentence need amending, and does amending it imply a
   version move?** See ISA Impact. px-ocp's research recorded that this fork is
   genuinely arguable and its plan chose one branch; px-24y's added wrinkle is
   that the repo has since written down the *reason* no version moved in terms
   that a null literal falsifies.
3. **Deprecation warning first, or a straight break?** The two precedents
   disagree - `=` got one release of notice (ADR-0002), while
   `if`/`else`/`while`/`undefined` got none. The 5.0.0 precedent is the closer
   analogy and this sweep is as clean as px-3so.2's was, which argues for a
   straight break; but ADR-0002's known-consumer survey is a year older and the
   deprecation infrastructure was deleted in 4.0.0, so a warning-first path means
   rebuilding it. A human call.
4. **Delete or invert the two doctests?** [`docs/reference/language.md:929-934`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/reference/language.md#L929-L934)
   and `:940-945` pin behavior that ceases to exist. They could be deleted, or
   rewritten to pin the *new* behavior (a parse error where the identifier
   reading used to be), which would preserve their tripwire value for the next
   change. The bead says "updated or removed" without choosing.
5. **How much of the surrounding "Null and undefined" section survives?** Beyond
   the two doctests, [`docs/reference/language.md:902`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/reference/language.md#L902) writes `null::T` as if null
   were writable (it is not today, so the prose is already ahead of the grammar),
   and `:910-920` states there is no way to write a null. Those become correct
   and false respectively - the section needs a read-through, not a line edit.
6. **Should `NULL`/`Null` stay ordinary identifiers?** Every precedent says yes
   (`true`/`false`, `undefined`, `if`/`else`/`while` are all lowercase-only), but
   nothing in the bead states it and it should be an explicit decision rather than
   an accident of following the template.
7. **st-7ft (statifier) has not been refreshed.** px-o9v's plan Residual Note 2
   records that its `mirrors:` obligation was not triggered and that "the
   implementer must re-read st-7ft and write a dated note **before** citing its
   status anywhere". This research cites no statifier status, so the obligation is
   still untriggered - but any plan that schedules px-24y against statifier's
   needs must refresh it first, per CLAUDE.md.
8. **Does the sibling divergence need a `docs/architecture.md` entry?** The `=`
   break earned a named subsection under Cross-Language Siblings
   ([`docs/architecture.md:180-202`](https://github.com/riddler/predicator-ex/blob/f2ac226152775c4a4b8cfc13f57194139957535b/docs/architecture.md#L180-L202)) because the Ruby and JavaScript lexers stayed
   on the old rule. Reserving `null` creates the same class of divergence, but
   5.0.0's four reservations did **not** get such an entry. Which precedent
   applies is unresolved.
