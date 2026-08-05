# Slim README Implementation Plan

## Overview

The README is 660 lines and is simultaneously a tutorial, a language reference,
an architecture doc, and a contributor guide. This plan cuts it to a slim entry
point - what Predicator is, the security property that motivates it, install,
one short quick start, then links - and relocates everything deeper into
`docs/` as reference pages and how-to guides, wired into ex_doc so the links
resolve on hexdocs as well as GitHub.

Beads issue: `px-tt6` (`area:docs`; this plan also touches `mix.exs`, so it
effectively carries `area:build` too - see "Area labels" below).

## Current State Analysis

### What exists

`README.md` (660 lines) currently holds:

| Lines | Section | Nature |
|---|---|---|
| 1-9 | Title, badges, one-paragraph description | orientation |
| 11-27 | Features - 16 emoji-decorated bullets | orientation |
| 29-39 | Installation | tutorial |
| 41-186 | Quick Start - 145 lines, ~40 examples | tutorial bloated into reference |
| 188-276 | Nested Data Access + Key Features | how-to |
| 278-352 | Supported Operations - arithmetic, comparison, logical, membership, function tables | reference |
| 305-310 | `=` deprecation callout | reference/migration |
| 354-366 | Data Types | reference |
| 368-411 | Architecture, Grammar, Core Components | duplicates `docs/architecture.md` |
| 413-423 | Error Handling | reference |
| 425-498 | Advanced Usage - custom functions, function format, string formatting options | how-to + reference |
| 500-600 | SCXML Location Expressions, assignability, path format, assignment | how-to |
| 602-631 | Cross-Language Siblings + the `=` divergence | duplicates `docs/architecture.md` |
| 633-656 | Development - setup and quality commands | duplicates `CLAUDE.md` and `docs/architecture.md` |
| 658-660 | Documentation pointer | orientation |

`docs/architecture.md` (617 lines) already carries the grammar with precedence
(`docs/architecture.md:20-49`), the component map
(`docs/architecture.md:51-74`), the pipeline diagram
(`docs/architecture.md:12-18`), the cross-language siblings section including
the `=` divergence (`docs/architecture.md:76-110`), and the quality-command
list (`docs/architecture.md:112-145`). Every architecture-flavored README
section is a **subset** of what is already there - `architecture.md`'s grammar
even annotates `=` as deprecated where the README's does not. Nothing has to
be moved into `architecture.md` before deleting from the README.

`docs/adr/` holds ADR-0001 and ADR-0002 with a `docs/adr/README.md` index.
`docs/plans/` holds five prior plans. There is no `docs/reference/` or
`docs/guides/` yet.

### Constraints discovered

**README examples are not verified by anything.** `grep -rn "README" test/ lib/`
returns nothing - no doctest, no extraction harness. Running the current
examples against the code shows several are already wrong:

| README | Claims | Actually returns |
|---|---|---|
| `README.md:141-142` | `{:error, "Expected number, ... at line 1, column 10"}` | `{:error, %Predicator.Errors.ParseError{message: "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found '>'", line: 1, column: 10}}` |
| `README.md:418-419` | `{:error, "Unexpected character '>' at line 1, column 8"}` | `%ParseError{}` with the "Expected number, ..." message, column 8 |
| `README.md:421-422` | `{:error, "... at line 1, column 1"}` | `%ParseError{}`, column **10** |
| `README.md:457-458` | `{:error, "Division by zero"}` | `{:error, %Predicator.Errors.EvaluationError{message: "Division by zero", reason: "Division by zero", operation: :function_call}}` |
| `README.md:66-67` | `evaluate!("due_at < 2w from now", %{"due_at" => Date.add(Date.utc_today(), 10)})` -> `true` | `:undefined` |
| `README.md:523-524` | `%LocationError{type: :undefined_variable, message: ...}` | same plus `details: %{variable: "missing_var"}` |

Errors became structs; the README still documents the string era. The
`2w from now` line is a comparison against a bare `Date` that yields
`:undefined`. This is the acceptance criterion "all code examples that survive
still run" failing today, and it is why this plan makes example verification
automatic rather than a manual read-through.

**The builtin function tables are stale.** `README.md:329-352` lists
`len/upper/lower/trim`, `abs/max/min`, `year/month/day`.
`docs/architecture.md:334-338` additionally lists `starts_with/2`,
`ends_with/2`, `substring/2..3`, and `index_of/2` (added by `px-8um`'s sibling
work, see `CHANGELOG.md` `Unreleased`). The relocated reference page must be
the complete catalog, not a copy of the stale one.

**hexdocs link resolution needs `mix.exs`.** `mix.exs:70-78` lists
`extras: ["README.md", "LICENSE", "CHANGELOG.md"]`, and `mix.exs:53` ships only
`~w(lib/predicator* mix.exs README.md LICENSE CHANGELOG.md)` in the package.
ex_doc rewrites a relative `.md` link only when the target is itself an extra;
anything else is emitted verbatim and 404s on hexdocs. The existing
`README.md:630` link to `docs/adr/0001-...md` is already broken there. So the
acceptance criterion "links are relative and resolve on both GitHub and
hexdocs" is unreachable without editing `mix.exs`.

**Toolchain.** `mise.toml` pins Elixir 1.18.3; CI runs a 1.17/1.18 matrix.
`mix.exs:26` declares `elixir: "~> 1.11"`, which is the *supported consumer*
range, not the range the suite is run under.
`ExUnit.DocTest.doctest_file/1` landed in Elixir 1.15, so it is available
everywhere the suite actually runs, but the test module guards on it so a
consumer on 1.11-1.14 running `mix test` does not hit a compile error.

**Emoji.** 16 in the Features list (`README.md:13-27`), plus the checkmark and
cross in `README.md:529`/`README.md:535`, plus one in
`docs/architecture.md:155`. The bead scopes emoji removal to the README; the
`architecture.md` one is out of scope.

### Key Discoveries

- `docs/architecture.md:20-49` is a strict superset of `README.md:378-398`,
  including the `=` deprecation annotation the README's grammar lacks -
  deleting the README's grammar loses nothing
- `docs/architecture.md:76-110` is a strict superset of `README.md:602-631`
- `docs/architecture.md:112-145` is a strict superset of `README.md:633-656`,
  and `CLAUDE.md` is the authority on the workflow those commands belong to
- Errors are `%Predicator.Errors.*{}` structs; the README documents strings
- `mix.exs:70-78` and `mix.exs:53` both need the new pages
- ADR-0001 bounds the 3.6-4.0 arc; ADR-0002 owns the `=` break. The README
  cites, it does not re-argue (`CLAUDE.md`, "What this project is")

## Desired End State

- `README.md` is under 200 lines (target ~120) and reads: badges, what
  Predicator is and the security property that motivates it, install, a short
  quick start, a plain-prose capability list, a documentation map, a short `=`
  migration note, a Development pointer, license.
- A **Hex downloads badge** sits with the existing four badges.
- `docs/reference/language.md` holds the complete language reference: operator
  tables, the full builtin function catalog, data types, the `=` deprecation,
  decompile formatting options, and the error shapes.
- `docs/guides/nested-data-access.md`, `docs/guides/custom-functions.md`, and
  `docs/guides/location-expressions.md` hold the three how-to bodies.
- Every code example in the README and in all four new pages is executed by
  `test/docs_examples_test.exs` on every `mix test` run; a stale example is a
  red gate.
- `mix.exs` lists all four pages plus `docs/architecture.md` and the two ADRs
  in `extras:`, groups them for the hexdocs sidebar, and ships `docs` in
  `package files:`.
- No emoji remain in the README.

### How to verify

`wc -l README.md` is under 200. `mix quality` is green, which now includes the
doc-example doctests. `mix docs` builds and the generated sidebar shows the new
groups. Every link in the README resolves - manually on GitHub, and in the
locally generated `doc/` output for hexdocs.

## What We're NOT Doing

- **Not rewriting `docs/architecture.md`.** It is already the superset; this
  plan deletes duplicates from the README rather than reconciling two copies.
  Its one emoji (`docs/architecture.md:155`) and its stale coverage/test-count
  stats are out of scope.
- **Not restructuring `docs/adr/`** beyond adding the two ADRs to `extras:`.
- **Not writing a tutorial.** The bead asks for "a minimal tutorial slice" in
  the README, not a `docs/tutorials/` quadrant. That is a future bead.
- **Not touching the library's behavior.** Where an example is wrong, the
  example is corrected to match the code; the code is not changed to match the
  example. The `2w from now` case in particular gets a corrected example, not a
  fix to duration comparison.
- **Not changing the instruction set**, the grammar, or any public API.
- **Not adding a docs landing page** (`docs/README.md`). The README's
  documentation map plus the ex_doc sidebar cover navigation.
- **Not moving `CHANGELOG.md` or `LICENSE`**, and not promoting `Unreleased`.

## Implementation Approach

Extract first, wire second, cut last. Each phase leaves the tree green and
committable on its own:

1. **Phase 1** writes the four new pages and the harness that executes their
   examples. The README still holds its duplicate copy at this point, which is
   harmless and keeps the phase independently green.
2. **Phase 2** wires the pages into ex_doc and the hex package, so that when
   the README starts linking at them in Phase 3 the links already resolve.
3. **Phase 3** cuts the README down to the links, adds the downloads badge,
   removes the emoji, extends the harness over the README, and records the
   change in `CHANGELOG.md`.

The ordering matters for one reason: Phase 3's README links must point at files
that exist and are reachable, so Phases 1 and 2 come first. Within Phase 1 the
harness is written alongside the pages rather than after, so the stale examples
surface at the moment they are relocated.

### Area labels

`px-tt6` carries `area:docs`. Phase 2 edits `mix.exs`, which is `area:build`,
and `CLAUDE.md` makes `area:build` exclusive - **this branch batches with
nothing and lands on `main` alone**. That is a deliberate widening agreed when
this plan was written, because the "links resolve on hexdocs" acceptance
criterion cannot be met without it. Add the label to the bead:

```bash
bd update px-tt6 --labels area:docs,area:build
```

## Phase 1: Extract the reference and guides into `docs/`

### Overview

Create `docs/reference/language.md` and three guides under `docs/guides/`,
carrying across every piece of README content that is not orientation or quick
start, and stand up the harness that executes their examples. Correct every
stale example the harness catches.

### Changes Required

#### 1. Language reference

**File**: `docs/reference/language.md` (new)
**Changes**: The complete language reference. Sources, in order:

| Section | From |
|---|---|
| Data types | `README.md:354-366` |
| Arithmetic operators | `README.md:280-289` |
| Comparison operators | `README.md:291-303` |
| The `=` deprecation callout | `README.md:305-310` |
| Logical operators | `README.md:312-318` |
| Membership operators | `README.md:320-325` |
| Builtin functions | `README.md:327-352`, **corrected against** `docs/architecture.md:334-338` |
| Decompiling and formatting options | `README.md:482-498` |
| Error shapes | `README.md:413-423`, **rewritten for structs** |

Open with a one-line pointer to `../architecture.md` for the grammar with
precedence rather than restating the EBNF - the grammar is architecture, and
duplicating it is the mistake this bead is undoing.

The builtin catalog is four tables (string, numeric, date, plus the string
functions the README omits). The string table must include:

| Function | Description | Example |
|----------|-------------|---------|
| `len(string)` | String length | `len(name) > 3` |
| `upper(string)` | Convert to uppercase | `upper(role) == 'ADMIN'` |
| `lower(string)` | Convert to lowercase | `lower(name) == 'alice'` |
| `trim(string)` | Remove surrounding whitespace | `len(trim(input)) > 0` |
| `starts_with(string, prefix)` | Prefix test | `starts_with(email, 'admin')` |
| `ends_with(string, suffix)` | Suffix test | `ends_with(file, '.csv')` |
| `substring(string, start[, len])` | Substring by offset | `substring(code, 0, 3) == 'ABC'` |
| `index_of(string, sub)` | Index of substring | `index_of(path, '/') == 0` |

Verify each signature and each example against
`lib/predicator/functions/` before writing the table - the harness will catch
a wrong example, but only if the example is present.

The error section replaces the string-era text. Errors are structs:

```elixir
iex> {:error, err} = Predicator.evaluate("score >> 85", %{})
iex> {err.__struct__, err.line, err.column}
{Predicator.Errors.ParseError, 1, 8}
```

Bind-and-project like this rather than inlining a full struct literal: it
survives a new field being added to the struct, which an inline
`%ParseError{...}` literal does not.

#### 2. Nested data access guide

**File**: `docs/guides/nested-data-access.md` (new)
**Changes**: `README.md:188-276` moved across - dot notation, bracket notation,
array indexing, mixed styles, atom keys, `:undefined` on a missing path, plus
the "Key Features" bullets folded into prose. The `context = %{...}` setup map
has to become a doctest-visible binding:

```elixir
iex> context = %{"user" => %{"name" => %{"first" => "John"}}, "items" => ["apple"]}
iex> Predicator.evaluate("user.name.first == 'John'", context)
{:ok, true}
```

One `iex>` chain per example block; `doctest_file/1` treats a blank line as the
end of a block, so a block that needs the context must rebind it.

#### 3. Custom functions guide

**File**: `docs/guides/custom-functions.md` (new)
**Changes**: `README.md:425-480` - the `functions:` option, the
`%{name => {arity, fun}}` format, overriding builtins. Two corrections:

- The `divide(10, 0)` example returns an `%EvaluationError{}`, not a bare
  string. Rewrite as a bind-and-project.
- Note that `arity` may be a list of integers for optional arguments
  (`docs/architecture.md:340-342`), which the README's "Function Format"
  section omits.

#### 4. Location expressions guide

**File**: `docs/guides/location-expressions.md` (new)
**Changes**: `README.md:500-600` - `context_location/3`, assignable vs
non-assignable targets, the location path format, and the `context_assign/4` /
`ContextLocation.put/3` assignment semantics. Replace the `✅`/`❌` headings
(`README.md:529`, `README.md:535`) with plain "Valid assignment targets" /
"Invalid assignment targets". The `LocationError` examples project the `type`
field rather than inlining a partial struct literal.

#### 5. Doc example harness

**File**: `test/docs_examples_test.exs` (new)
**Changes**: Execute every example in the new pages.

```elixir
defmodule Predicator.DocsExamplesTest do
  @moduledoc """
  Executes the code examples in the published documentation.

  The docs are the library's front door; a stale example there is worse than
  no example. `doctest_file/1` requires Elixir 1.15+, which every version the
  CI matrix runs satisfies - the guard exists only so that `mix test` on the
  older end of `mix.exs`'s declared `~> 1.11` support range still compiles.
  """
  use ExUnit.Case, async: true

  if Version.match?(System.version(), ">= 1.15.0") do
    doctest_file("docs/reference/language.md")
    doctest_file("docs/guides/nested-data-access.md")
    doctest_file("docs/guides/custom-functions.md")
    doctest_file("docs/guides/location-expressions.md")
  end
end
```

Confirm the exact `doctest_file/1` arity and options against the installed
Elixir before finalizing. Non-`iex>` fenced blocks (the `mix.exs` snippet, the
location-path illustration) are ignored by the doctest parser, so illustrative
blocks stay illustrative.

### Success Criteria

#### Automated Verification

- [x] Full quality gate passes: `mix quality`
- [x] `test/docs_examples_test.exs` runs a non-zero number of doctests -
      confirm with `mix test test/docs_examples_test.exs` and read the count,
      since a file whose examples all failed to parse passes vacuously
- [x] Coverage stays above the 90% minimum in `coveralls.json`
- [x] `docs/reference/language.md`, `docs/guides/nested-data-access.md`,
      `docs/guides/custom-functions.md`, and
      `docs/guides/location-expressions.md` all exist

#### Manual Verification

- [x] Every README section listed in the table above has a destination; nothing
      was dropped in transit
- [x] The builtin function catalog covers all four string functions the README
      omitted, with signatures matching `lib/predicator/functions/`
- [x] The reference page defers to `../architecture.md` for the grammar rather
      than restating the EBNF
- [x] No emoji in any new page

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run the full `mix quality` as the phase gate. In interactive
execution, pause here for manual confirmation before proceeding. In looped
(`--loop`) execution, this phase's Automated Verification gates advancement
automatically (via `/commit --auto`); Manual Verification items are deferred
and surfaced once at the end.

---

## Phase 2: Wire the docs into ex_doc and the hex package

### Overview

Make the new pages reachable on hexdocs so the README's relative links resolve
there, and ship them in the released package.

### Changes Required

#### 1. ex_doc extras and grouping

**File**: `mix.exs`
**Changes**: Extend `docs/0` (`mix.exs:70-78`).

```elixir
defp docs do
  [
    name: "Predicator",
    source_ref: "v#{@version}",
    canonical: "https://hexdocs.pm/predicator",
    source_url: @source_url,
    main: "readme",
    extras: [
      "README.md",
      "docs/reference/language.md",
      "docs/guides/nested-data-access.md",
      "docs/guides/custom-functions.md",
      "docs/guides/location-expressions.md",
      "docs/architecture.md",
      "docs/adr/README.md",
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
```

Two page titles collide by filename - `docs/adr/README.md` and the root
`README.md` both render as "README". Give the ADR index an explicit title via
the `{path, title: "..."}` extras form, and check whether the guide and
reference pages need one too rather than inheriting their first heading.

#### 2. Package files

**File**: `mix.exs`
**Changes**: Add `docs` to the file list at `mix.exs:53`.

```elixir
files: ~w(lib/predicator* docs mix.exs README.md LICENSE CHANGELOG.md)
```

`docs/plans/` ships along with this, which is acceptable - it is small, it is
already public on GitHub, and excluding it would mean enumerating
subdirectories that then drift as new ones are added.

### Success Criteria

#### Automated Verification

- [x] Full quality gate passes: `mix quality`
- [x] `mix docs` builds with no warnings about missing or unresolved extras
- [x] `mix hex.build` succeeds and `mix hex.build --unpack` (into a scratch
      directory) shows the `docs/` tree present in the package contents

#### Manual Verification

- [x] The generated `doc/index.html` sidebar shows Reference, Guides, and
      Architecture groups with the expected pages under each
- [x] The ADR index page has a distinct title from the root README page
- [x] A relative link between two extras (e.g. reference -> architecture)
      resolves in the generated output, not just on GitHub

**Implementation Note**: `mix hex.build` is a local packaging check and is
safe. **`mix hex.publish` is never run** - `CLAUDE.md`'s authority table gives
it no trigger.

---

## Phase 3: Rewrite the README as a slim entry point

### Overview

Cut the README to orientation plus a minimal tutorial slice, add the Hex
downloads badge, remove the emoji, link out to everything relocated in Phase 1,
and put the README's own examples under the harness.

### Changes Required

#### 1. The README

**File**: `README.md`
**Changes**: Full rewrite. Target shape, ~120 lines:

**Badges** - the existing four plus total Hex downloads:

```markdown
[![CI](https://github.com/riddler/predicator-ex/actions/workflows/ci.yml/badge.svg)](https://github.com/riddler/predicator-ex/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/riddler/predicator-ex/branch/main/graph/badge.svg)](https://codecov.io/gh/riddler/predicator-ex)
[![Hex.pm Version](https://img.shields.io/hexpm/v/predicator.svg)](https://hex.pm/packages/predicator)
[![Hex Downloads](https://img.shields.io/hexpm/dt/predicator.svg)](https://hex.pm/packages/predicator)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/predicator/)
```

`hexpm/dt` is the all-time download total. Load the badge URL once in a browser
before committing - shields renders "invalid" rather than erroring if the
package path is wrong.

**What it is and why** - two short paragraphs replacing `README.md:8-9` and the
16-bullet emoji list. Lead with the security property: user-authored predicates
compile to a flat instruction list run by a stack VM, with no `eval` and no
dynamic code execution anywhere in the pipeline. Then a plain-prose sentence or
two on what the language covers (comparisons, arithmetic, logic, dates and
durations, lists and objects, nested access, builtin and custom functions), each
phrase linking into the reference rather than expanding into a bullet.

**Installation** - keep `README.md:29-39` verbatim.

**Quick start** - roughly 10 lines, doctest-clean, covering only: a comparison,
a logical expression, `compile/1` + reuse, and `evaluate/2`'s `{:ok, _}` shape.
Everything else moves to the reference.

**Documentation** - the map, the section that does the actual handing off:

```markdown
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
```

**Migrating from `=`** - three or four lines: `=` as equality is deprecated and
becomes a parse error in 4.0, use `==`, silence with
`config :predicator, deprecation_warnings: false`, link to
[ADR-0002](docs/adr/0002-the-equals-grammar-break.md). Keep this in the README
rather than only in the reference: it is a migration users must not miss.

**Cross-language siblings** - three lines. Ruby and JavaScript implementations
live in the [riddler/predicator](https://github.com/riddler/predicator)
monorepo, the instruction list is the interchange format, the divergences are
in `docs/architecture.md`. Delete `README.md:602-631`'s long version.

**Development** - replace `README.md:633-656` with a pointer: `CLAUDE.md` for
the workflow rules and `docs/architecture.md` for the command reference. Do not
restate `mix quality`.

**License** - one line if not already present.

Delete outright (duplicated by `docs/architecture.md`): Architecture, Grammar,
and Core Components (`README.md:368-411`).

House style: the README is ASCII-punctuation today (plain hyphens throughout)
and stays that way. The pipeline diagram's `→` characters leave with the
Architecture section.

#### 2. Extend the harness over the README

**File**: `test/docs_examples_test.exs`
**Changes**: Add `doctest_file("README.md")` inside the existing version guard.

#### 3. Changelog

**File**: `CHANGELOG.md`
**Changes**: Under `## [Unreleased]`, a `### Changed` entry:

```markdown
- Documentation restructured: the README is now a slim entry point, with the
  language reference, nested data access, custom functions, and location
  expressions moved to `docs/reference/` and `docs/guides/` and published to
  hexdocs. All documentation examples are now executed by the test suite.
```

Add the `### Changed` heading if `Unreleased` does not have one yet.

### Success Criteria

#### Automated Verification

- [x] Full quality gate passes: `mix quality`
- [x] `wc -l README.md` reports fewer than 200 lines
- [x] `grep -nP '[^\x00-\x7F]' README.md` returns nothing - no emoji and no
      non-ASCII typography
- [x] `mix test test/docs_examples_test.exs` runs the README's doctests and
      the count went up relative to Phase 1
- [x] `mix docs` builds with no warnings

#### Manual Verification

- [x] Every link in the README resolves on GitHub (click each one on the
      pushed branch) and in the locally generated `doc/` output
- [x] The Hex downloads badge renders a number, not "invalid"
- [x] The README reads as orientation: someone who has never seen Predicator
      learns what it is, why the no-`eval` property matters, and how to get one
      expression evaluating, without scrolling past a reference table
- [x] Nothing cut from the README is unreachable - walk the Current State
      Analysis table and confirm each row's destination is linked
- [x] The `=` deprecation notice is still prominent enough to be seen by
      someone skimming

**Implementation Note**: The link check is the one criterion no automated step
covers - relative-link checking on GitHub needs a human or a link checker this
repo does not have. Walk them.

---

## Testing Strategy

### Unit Tests

No new unit tests. This bead changes no behavior; `lib/` is untouched, so the
existing suite is the regression net for "the docs describe the code
accurately" only insofar as the doctests exercise it.

### Integration Tests

`test/docs_examples_test.exs` is the whole testing story here, and it is an
integration test in the truest sense: it drives the public API exactly the way
the documentation tells a reader to. Expect it to fail on first run against the
relocated content - that is the point, and the failures listed in Current State
Analysis are the ones already known.

Two failure modes to watch for:

- **Vacuous pass.** A markdown file whose `iex>` blocks are malformed
  contributes zero doctests and the file still "passes". Read the reported test
  count after each `doctest_file` is added, not just the green.
- **Non-determinism.** Any example using `Date.utc_today/0`, `DateTime.utc_now/0`,
  or a relative date (`3d ago`, `2w from now`) is time-dependent and can pass
  today and fail next week. Rewrite those against fixed literals -
  `#2024-01-10# + 5d == #2024-01-15#` is deterministic where
  `due_at < 2w from now` is not.

### Manual Testing Steps

1. `mix docs && open doc/index.html` - check the sidebar groups, then click
   through every link in the rendered README.
2. On the pushed branch, open `README.md` on GitHub and click every link.
3. `mix hex.build --unpack /tmp/predicator-pkg` and confirm `docs/` is present
   in the unpacked tree.
4. Read the finished README end to end as a first-time visitor and check it
   answers what / why / how do I start, in that order.

## Cross-Language Impact

None. This bead changes no instruction, no grammar production, and no public
API, so nothing in ADR-0001's interchange contract moves and the Ruby and
JavaScript siblings need no corresponding change. The README's remaining note
about the `=` divergence is a pointer to a decision already recorded in
ADR-0002, not a new one.

## References

- Beads issue: `px-tt6`
- `README.md` - the 660-line current state, section map in Current State
  Analysis above
- `docs/architecture.md:20-49` (grammar), `:51-74` (components), `:76-110`
  (siblings), `:112-145` (commands), `:334-338` (full builtin catalog)
- `mix.exs:53` (package files), `mix.exs:70-78` (ex_doc config)
- `docs/adr/0001-keep-the-stack-vm-revise-the-instruction-set.md` - the
  3.6-4.0 arc and the instruction set as interchange format
- `docs/adr/0002-the-equals-grammar-break.md` - the `=` deprecation and 4.0
  parse error
- `CLAUDE.md` - agent authority table, area labels (`area:build` is exclusive),
  commit and changelog conventions
- Diataxis framing for the reference/guides split: https://diataxis.fr
