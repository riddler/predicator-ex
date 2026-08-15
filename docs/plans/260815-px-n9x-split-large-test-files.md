# Splitting the six oversized test files Implementation Plan

## Overview

Six test files have grown past 1100 lines each and are not broken up by
behavior. This plan splits each one along its existing `describe` boundaries
into sibling files of roughly 200-500 lines, moving whole describe blocks
verbatim, so that the suite's test names, test bodies, and test count are
byte-for-byte unchanged and only the file layout moves.

Beads issue: `px-n9x`

This is pure file surgery. No `lib/` code changes, no ISA move, no corpus
regeneration.

## Current State Analysis

### The six files, as they stand today

Line counts have drifted upward since the bead was written; these are current.

| File | Lines | Tests | Doctests | Describes |
|---|---|---|---|---|
| `test/predicator_test.exs` | 2224 | 208 | 58 | 30 |
| `test/predicator/parser_test.exs` | 2366 | 233 | 9 | 27 |
| `test/predicator/evaluator_test.exs` | 1738 | 171 | 13 | 25 |
| `test/predicator/visitors/string_visitor_test.exs` | 1409 | 157 | 12 | 22 |
| `test/predicator/lexer_test.exs` | 1339 | 116 | 5 | 19 |
| `test/predicator/visitors/instructions_visitor_test.exs` | 1174 | 94 | 9 | 17 |

Whole-suite baseline, captured on this branch before any change:

```text
446 doctests, 2785 tests, 0 failures
```

### Key Discoveries

- **The repo already splits test files this way, flat, as siblings.**
  `test/predicator/parser_edge_cases_test.exs`,
  `parser_positions_test.exs`, `parser_spans_test.exs`,
  `parser_format_token_coverage_test.exs`, `lexer_edge_cases_test.exs`,
  `evaluator_positions_test.exs`, and
  `test/predicator/visitors/instructions_visitor_positions_test.exs` are all
  `<thing>_<topic>_test.exs` files next to the file they came from, with module
  names `Predicator.<Thing><Topic>Test`
  (`test/predicator/parser_edge_cases_test.exs:1`,
  `test/predicator/visitors/instructions_visitor_positions_test.exs:1`).
  Subdirectories exist too (`test/predicator/evaluator/`,
  `test/predicator/conformance/`) but the flat sibling is the pattern for
  splitting *one module's* tests by topic.
- **Each of the six files carries exactly one `doctest` line**
  (`test/predicator_test.exs:6`, `parser_test.exs:6`, `evaluator_test.exs:19`,
  `string_visitor_test.exs:6`, `lexer_test.exs:6`,
  `instructions_visitor_test.exs:6`). Doctests are counted separately by
  ExUnit, and duplicating a `doctest` line would inflate the count. Every
  original file therefore survives as the residual file and keeps its own
  `doctest` line.
- **Cross-describe private helpers exist and constrain the grouping.**
  `defp` inside a `describe` block is still module-level in Elixir, so two
  describes can share one:
  - `test/predicator/visitors/string_visitor_test.exs:983`
    (`assert_program_round_trip/1`) is defined inside the "program and
    assignment round-trip" describe and used by the "while round-trip"
    describe at line 991+.
  - `test/predicator/visitors/instructions_visitor_test.exs:988`
    (`visit_program/1`) is defined inside the "if/else lowering" describe and
    used by "while lowering" at line 1102+.
  - `string_visitor_test.exs:1389` and `:1399` (`assert_tree_fixpoint/1`,
    `assert_string_fixpoint/1`) are module-level and used only by the
    ":minimal adds parens" and "if/block rendering" describes.
  Each of these pairs is kept in one output file so the helper stays local.
- **`parse_positionless/1` is the one helper that genuinely spans groups.**
  It is defined identically in `test/predicator_test.exs:2213` and
  `test/predicator/parser_test.exs:2348`, and its call sites are spread across
  most describes in both files. Four further identical copies already exist in
  files this bead does not touch - `test/predicator/parser_edge_cases_test.exs:480`,
  `test/predicator/strict_equality_test.exs:251`,
  `test/predicator/object_parser_test.exs:188`, and
  `test/predicator/functions/qualified_functions_test.exs:366` - so credo
  currently tolerates six copies. Those four stay where they are: converting
  them is out of scope for this bead. What matters here is that the split would
  otherwise raise the count from six to about fifteen, which is why the two
  in-scope definitions are centralized rather than copied further.
  `parse_program_positionless/1` (`parser_test.exs:2360`) is used only inside
  the `parse_program/2` describes.
- **`test_helper.exs` is this repo's documented home for shared test support.**
  `Predicator.SpanSlicing` and `Predicator.ASTShape` live there, and
  `Predicator.Conformance.SchemaValidator`'s moduledoc states the reason
  explicitly: a `test/support/` directory would need an `elixirc_paths` change
  in `mix.exs`, which `mix.exs` does not have today. That would drag
  `area:build` into this bead, which it is not labeled with.
- **Credo runs over `test/`** (`.credo.exs` `included:` lists `"test/"`) with
  `strict: true`, and `Credo.Check.Design.DuplicatedCode` is enabled. Copying a
  helper into eight files is a real risk; one definition plus `import` is not.
- **`Predicator.EvaluatorTest.RaisingProvider`**
  (`test/predicator/evaluator_test.exs:1`) is a second module in the same file,
  used only at line 1732 inside the "call_function/4 dispatch" describe. That
  describe stays in the residual file, so the provider module does not move.
- **None of the six files is in `gate.sabotage.test_roots`.** The list in
  `.claude/wurk.json` names eleven binding-test files and none of them is one
  of these six, so no `test_roots` update is owed by this change. That was
  checked explicitly because splitting a file named there would require adding
  the new paths in the same commit.
- **No single describe block exceeds 500 lines.** The largest is
  `evaluator_test.exs:686` ("bracket_access instructions", 307 lines), then
  `parser_test.exs:1196` (282) and `lexer_test.exs:80` (292). The "no describe
  split across files" rule and the 200-500 line target are therefore
  compatible everywhere.
- **All six files are `async: true` and none has a `setup` block**, so there is
  no shared fixture state to reason about when a describe moves.

## Desired End State

Thirty-two test files where there were six: each original file retained (with
its `doctest` line, its module name, and a residual group of describes) plus
26 new sibling files, none over ~500 lines, each holding whole describe blocks
copied verbatim.

Verified by:

- `mix test` reports **446 doctests, 2785 tests, 0 failures** - identical to the
  baseline above.
- `git diff` shows no change under `lib/`, `conformance/`, or `mix.exs`.
- Full `mix quality` is green.
- No test file among the six groups exceeds 550 lines.

## What We're NOT Doing

- **Not rewriting, renaming, merging, or deleting any test.** Describe blocks
  and their contents move byte-for-byte. If a test looks redundant or
  misplaced, it still moves as-is; that is a separate bead.
- **Not using subdirectories.** The bead's parenthetical example
  (`parser_test.exs -> parser/literals_test.exs`) is not followed: the repo's
  own established pattern for splitting a module's tests by topic is a flat
  sibling (`parser_edge_cases_test.exs`), and the acceptance criterion says
  "under the same directory". A new `test/predicator/parser/` tree would sit
  awkwardly beside five existing flat `parser_*_test.exs` files. Recorded here
  because it is a deliberate departure from the bead's illustration, not an
  oversight.
- **Not adding a `test/support/` directory.** It needs an `elixirc_paths`
  change in `mix.exs`, which would pull `area:build` into a bead not labeled
  with it. `test_helper.exs` is the repo's documented alternative.
- **Not touching `lib/`.** No production code changes, so no CHANGELOG entry
  is owed (this is not a user-facing change) and no ISA move applies - no
  opcode is added, removed, renamed, or altered, so the `## ISA Impact`
  section is omitted per `.claude/wurk/plan.md`.
- **Not regenerating the conformance corpus.** No phase can move the exported
  specification, so the ADR-0003 corpus-diff obligation does not attach.
- **Not adding a file-length Credo check.** `.credo.exs` has no
  `LargeModule`/file-length rule today and this bead does not add one; nothing
  will stop these files growing again. Filing that is a separate decision.
- **Not splitting `test_helper.exs`**, which is itself long. Out of scope.
- **Not converting the four out-of-scope `parse_positionless/1` copies** in
  `parser_edge_cases_test.exs`, `strict_equality_test.exs`,
  `object_parser_test.exs`, and `qualified_functions_test.exs` to the new
  `Predicator.ParseShape`. They are in files this bead does not open, and
  touching them would widen the diff for no gain here. A follow-up bead can
  fold them in.
- **Not shrinking the three other test files over 550 lines**
  (`context_location_test.exs` 694, `duration_test.exs` 693,
  `instructions_visitor_positions_test.exs` 574). The bead names six files and
  these are not among them.

## Implementation Approach

One phase per original file, in descending size order, with the shared helper
promotion folded into the first phase that needs it. Each phase is a pure
move: cut a contiguous run of describe blocks out of the original, paste it
into a new file with the standard preamble (`defmodule`, `use ExUnit.Case,
async: true`, the aliases those describes actually use), and leave the
original's `doctest` line and preamble intact.

**Phase ordering matters in exactly one place.** Phase 1 adds
`Predicator.ParseShape` to `test/test_helper.exs` and Phase 2 consumes it.
Phase 1 is self-contained and gate-green on its own (it both adds and uses the
module); Phase 2 must not run before it. Every other phase is independent of
every other and could be reordered freely.

### The shared-helper mechanism

`Predicator.ParseShape` is added to `test/test_helper.exs`, alongside the
existing `Predicator.SpanSlicing` and `Predicator.ASTShape`, exposing the two
helpers as public functions under **their current names**:

```elixir
defmodule Predicator.ParseShape do
  @moduledoc """
  Parses to the slot-free AST shape most parser assertions read.

  These assertions are about AST *shape*, so they drop the trailing source
  slot; positions and spans have their own suites
  (`parser_positions_test.exs`, `parser_spans_test.exs`). Lives here rather
  than in one test file because `predicator_test.exs`, `parser_test.exs`, and
  the files split out of them all read it - the same reason
  `Predicator.ASTShape` above is here.
  """

  @doc "Parses `input` (source binary or token list) to a slot-free AST."
  @spec parse_positionless(binary() | [tuple()]) :: {:ok, term()} | {:error, term()}
  def parse_positionless(input) do
    result =
      if is_binary(input),
        do: Predicator.parse(input),
        else: Predicator.Parser.parse(input)

    case result do
      {:ok, ast} -> {:ok, Predicator.ASTShape.strip(ast)}
      other -> other
    end
  end

  @doc "Parses `tokens` as a program, to a slot-free AST."
  @spec parse_program_positionless([tuple()]) :: {:ok, term()} | {:error, term()}
  def parse_program_positionless(tokens) do
    case Predicator.Parser.parse_program(tokens) do
      {:ok, program} -> {:ok, Predicator.ASTShape.strip(program)}
      other -> other
    end
  end
end
```

Each file that needs it writes `import Predicator.ParseShape` in its preamble
and **deletes its local `defp`**. Because the names are unchanged, every call
site inside every test body stays byte-identical - which is what keeps "test
cases preserved verbatim" literally true. A file must not both `import` and
define the local `defp`; that is a compile error and the gate catches it.

The `@spec` return types above are deliberately loose (`term()`) because the
AST is a bare tuple union with no exported type for the stripped shape;
`Predicator.ASTShape` in the same file takes the same approach.

### Per-file mechanics, applied identically in every phase

1. Read the original file fully; note the exact first and last line of each
   describe block being moved.
2. Create the new file with:
   - `defmodule <Module> do`
   - `use ExUnit.Case, async: true`
   - the aliases the moved describes need (copy only the ones actually
     referenced; Credo's `Design.AliasUsage` and the unused-alias warning both
     bite, and warnings are errors under the gate)
   - `import Predicator.ParseShape` where required
   - the describe blocks, pasted verbatim with their original indentation
   - any module-level `defp` or `@attr` used *only* by the moved describes
3. Delete exactly those lines from the original.
4. **No `doctest` line in any new file.**
5. `mix format` the touched files.

Note that several describes contain nested `alias` statements inside
individual tests (e.g. `test/predicator_test.exs:2188`,
`string_visitor_test.exs:338`). Those move with the test body untouched.

---

## Phase 1: `test/predicator_test.exs` (2224 -> ~5 files)

### Overview

Splits the façade suite into five topic files plus the residual, and
introduces `Predicator.ParseShape` in `test/test_helper.exs`.

### Changes Required:

#### 1. Shared helper

**File**: `test/test_helper.exs`
**Changes**: Add the `Predicator.ParseShape` module shown in "Implementation
Approach", after `Predicator.ASTShape` and before
`Predicator.Conformance.SchemaValidator`.

#### 2. New sibling files

All at `test/`, beside `predicator_test.exs`. Line numbers are describe
starts in the current `test/predicator_test.exs`.

| New file | Module | Describes moved (start lines) | ~Lines |
|---|---|---|---|
| `test/predicator_compile_test.exs` | `PredicatorCompileTest` | 157 `compile/1`, 233 `compile_with_positions/1`, 264 `parse/2 with spans`, 281 `compile_with_spans/1`, 314 `the compile arm carries a span in every mode (Phase 4)`, 371 `parse_program/2`, 587 `compile!/1`, 615 `structured compile errors (px-d71, ADR-0015)` | ~370 |
| `test/predicator_evaluate_test.exs` | `PredicatorEvaluateTest` | 8 `evaluate/3 - :loop_budget`, 42 `evaluate/2 with string expressions`, 112 `evaluate/2 with instruction lists`, 133 `evaluate!/2`, 453 `runtime error spans`, 493 `runtime error positions`, 525 `evaluate/3 with a %Predicator.Compiled{}`, 574 `evaluate/3 with a bare instruction list and :positions`, 660 `performance scenarios`, 698 `decompile/2`, 756 `edge cases`, 771 `evaluator/2 and run_evaluator/1` | ~400 |
| `test/predicator_logical_operators_test.exs` | `PredicatorLogicalOperatorsTest` | 788 `logical operators - integration tests`, 993 `plain boolean expressions`, 1092 `lowercase logical operators` | ~405 |
| `test/predicator_collections_test.exs` | `PredicatorCollectionsTest` | 1194 `list literals and membership operators`, 1355 `object literals` | ~280 |
| `test/predicator_access_test.exs` | `PredicatorAccessTest` | 1685 `nested context access`, 1958 `evaluate/2 with bracket access expressions` | ~330 |

**Residual `test/predicator_test.exs`** keeps its preamble, `doctest
Predicator`, and 1475 `date literals and comparisons`, 1786 `single quoted
strings`, 1833 `custom functions` (~385 lines). Its local
`defp parse_positionless/1` (line 2213) is **deleted** and replaced by
`import Predicator.ParseShape`.

The `@infinite_loop` module attribute at line 12 sits inside the
`evaluate/3 - :loop_budget` describe, so it moves with that describe into
`predicator_evaluate_test.exs`.

Files needing `import Predicator.ParseShape`: the residual,
`predicator_logical_operators_test.exs` (call sites at 932, 935, 938, 1161,
1164, 1167), `predicator_collections_test.exs` (1285, 1288, 1291, 1406, 1414),
`predicator_access_test.exs` (2206). `predicator_compile_test.exs` and
`predicator_evaluate_test.exs` do not use it - do not import it there.

### Success Criteria:

#### Automated Verification:
- [x] `mix test test/predicator_test.exs test/predicator_compile_test.exs test/predicator_evaluate_test.exs test/predicator_logical_operators_test.exs test/predicator_collections_test.exs test/predicator_access_test.exs`
      reports exactly **58 doctests, 208 tests, 0 failures**
- [x] `mix test` reports **446 doctests, 2785 tests, 0 failures**
- [x] Full `mix quality` is green (format, compile with warnings-as-errors,
      `credo --strict` over `test/` included, dialyzer, coverage)
- [x] Coverage stays at or above the 90% minimum in `coveralls.json` - no
      `lib/` line loses its only exercising test
- [x] `git diff --stat` shows no file under `lib/`, `conformance/`, or
      `mix.exs` changed
- [x] `wc -l` on each of the six files above is under 550

#### Manual Verification:
- [ ] Spot-check three moved describes against `git show HEAD:test/predicator_test.exs`
      and confirm the block is byte-identical, indentation included
- [ ] Each new file's alias list is exactly what its tests reference - no
      alias copied "just in case"
- [ ] No new file contains a `doctest` line
- [ ] Grouping reads sensibly to a human opening the directory

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

## Phase 2: `test/predicator/parser_test.exs` (2366 -> ~8 files)

### Overview

The largest split: seven new sibling files plus the residual. **Depends on
Phase 1**, which introduces `Predicator.ParseShape`.

### Changes Required:

#### 1. New sibling files

All at `test/predicator/`. Line numbers are describe starts in the current
`parser_test.exs`. Note the existing files `parser_edge_cases_test.exs`,
`parser_positions_test.exs`, `parser_spans_test.exs`,
`parser_format_token_coverage_test.exs`, and
`parser_string_token_arity_test.exs` already occupy those names - none of the
names below collides with them.

| New file | Module | Describes moved (start lines) | ~Lines |
|---|---|---|---|
| `parser_errors_test.exs` | `Predicator.ParserErrorsTest` | 253 `parse/1 - error cases`, 345 `parse/1 - integration with lexer errors`, 364 `parse/1 - additional error coverage`, 1022 `parse/1 - advanced error cases` | ~325 |
| `parser_error_spans_test.exs` | `Predicator.ParserErrorSpansTest` | 1098 `parse/1 - edge cases for format_token`, 2154 `parse/1 - error spans`, 2199 `parse/1 - end of input reports the end of the source`, 2240 `failures after a multi-line string literal`, 2306 `guard: the deliberate px-tbv.2 gaps` | ~216 |
| `parser_operators_test.exs` | `Predicator.ParserOperatorsTest` | 98 `parse/1 - comparison expressions`, 204 `parse/1 - parenthesized comparisons`, 502 `logical operators`, 1146 `parse/1 - operator precedence edge cases` | ~400 |
| `parser_bracket_access_test.exs` | `Predicator.ParserBracketAccessTest` | 964 `parse/1 - complex nested expressions`, 1196 `parse/1 - bracket access expressions` | ~340 |
| `parser_type_casts_test.exs` | `Predicator.ParserTypeCastsTest` | 1478 `type casts` | ~208 |
| `parser_durations_test.exs` | `Predicator.ParserDurationsTest` | 751 `date and datetime parsing`, 1686 `parse/1 - duration expressions`, 1817 `parse/1 - fractional duration literals (px-5c5)` | ~268 |
| `parser_program_test.exs` | `Predicator.ParserProgramTest` | 1916 `parse_program/2`, 2121 `parse_program/2 - positions and spans`, 2284 `Predicator.parse_program/2 - the façade` | ~260 |

**Residual `parser_test.exs`** keeps its preamble, `doctest Predicator.Parser`,
and 8 `parse/1 - primary expressions`, 169 `parse/1 - undefined as an
operand`, 234 `parse/1 - complex expressions`, 789 `additional edge cases for
coverage`, 872 `parse/1 - function call expressions` (~320 lines).

#### 2. Helper promotion

Delete `defp parse_positionless/1` (line 2348) and
`defp parse_program_positionless/1` (line 2360) from `parser_test.exs`; every
file above that calls either one gets `import Predicator.ParseShape` - **and so
does the residual `parser_test.exs` itself**, whose retained describes call
`parse_positionless/1` dozens of times (lines 11-905). Deleting the local
`defp` without adding the import breaks the residual's compile. Confirm
per file with `grep -n 'parse_positionless\|parse_program_positionless'` after
the move - `parse_program_positionless/1` is used only by the
`parse_program/2` describes, so only `parser_program_test.exs` needs it, but
the single import covers both names.

The `alias Predicator.Lexer` at `parser_test.exs:4` is needed by nearly every
group (tests tokenize before parsing); copy it only where referenced.

### Success Criteria:

#### Automated Verification:
- [x] `mix test test/predicator/parser_test.exs test/predicator/parser_errors_test.exs test/predicator/parser_error_spans_test.exs test/predicator/parser_operators_test.exs test/predicator/parser_bracket_access_test.exs test/predicator/parser_type_casts_test.exs test/predicator/parser_durations_test.exs test/predicator/parser_program_test.exs`
      reports exactly **9 doctests, 233 tests, 0 failures**
- [x] `mix test` reports **446 doctests, 2785 tests, 0 failures**
- [x] Full `mix quality` is green
- [x] Coverage stays at or above the 90% minimum in `coveralls.json`
- [x] `git diff --stat` shows no file under `lib/`, `conformance/`, or
      `mix.exs` changed
- [x] No file among the eight exceeds 550 lines

#### Manual Verification:
- [ ] Three moved describes spot-checked byte-identical against
      `git show <phase-1-sha>:test/predicator/parser_test.exs`
- [ ] `parser_*_test.exs` naming reads consistently with the five
      pre-existing `parser_*_test.exs` files
- [ ] No new file contains a `doctest` line

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

## Phase 3: `test/predicator/evaluator_test.exs` (1738 -> ~5 files)

### Overview

Four new sibling files plus the residual. Independent of every other phase.

### Changes Required:

All new files at `test/predicator/`, beside the existing
`evaluator_positions_test.exs`. Line numbers are describe starts in the
current `evaluator_test.exs`.

| New file | Module | Describes moved (start lines) | ~Lines |
|---|---|---|---|
| `evaluator_bracket_access_test.exs` | `Predicator.EvaluatorBracketAccessTest` | 686 `evaluate/2 with bracket_access instructions`, 993 `access_value/3 is total (px-tmy)` | ~378 |
| `evaluator_dates_test.exs` | `Predicator.EvaluatorDatesTest` | 503 `date and datetime evaluation`, 567 `mixed date/datetime comparison`, 1064 `evaluate/2 with duration instructions`, 1145 `evaluate/2 with relative_date instructions` | ~385 |
| `evaluator_logical_test.exs` | `Predicator.EvaluatorLogicalTest` | 292 `retired and/or opcodes`, 340 `logical operators`, 426 `short-circuit jump instructions` | ~211 |
| `evaluator_unbound_test.exs` | `Predicator.EvaluatorUnboundTest` | 1390 `unbound_loads/1`, 1455 `unbound_loads_with_locations/1`, 1508 `evaluate/3 with on_unbound: :error`, 1542 `null as a value (px-o9v)` | ~258 |

**Residual `evaluator_test.exs`** keeps the
`Predicator.EvaluatorTest.RaisingProvider` module at the top of the file
(lines 1-10), its preamble, `doctest Predicator.Evaluator`, and 21 `lit`, 61
`load`, 84 `mixed instructions`, 110 `make_list`, 159 `list concatenation`,
182 `error cases`, 205 `step/1 and run/1`, 252 `evaluate!/2`, 625 `error
handling edge cases`, 1327 `cast instruction`, 1648 `:loop_budget`, 1681
`call_function/4 dispatch` (~485 lines). `RaisingProvider` stays because its
only consumer (line 1732) is in the `call_function/4` describe, which stays.

The `@infinite_loop` attribute at line 1651 is inside the `:loop_budget`
describe, which stays; it does not move.

Aliases at lines 15-17: `Predicator.Errors.{...}`, `Predicator.Evaluator`,
`Predicator.EvaluatorTest.RaisingProvider`. The `RaisingProvider` alias stays
only in the residual. Copy the error-struct alias only into files whose tests
reference those structs.

### Success Criteria:

#### Automated Verification:
- [ ] `mix test test/predicator/evaluator_test.exs test/predicator/evaluator_bracket_access_test.exs test/predicator/evaluator_dates_test.exs test/predicator/evaluator_logical_test.exs test/predicator/evaluator_unbound_test.exs`
      reports exactly **13 doctests, 171 tests, 0 failures**
- [ ] `mix test` reports **446 doctests, 2785 tests, 0 failures**
- [ ] Full `mix quality` is green
- [ ] Coverage stays at or above the 90% minimum in `coveralls.json`
- [ ] `git diff --stat` shows no file under `lib/`, `conformance/`, or
      `mix.exs` changed
- [ ] No file among the five exceeds 550 lines

#### Manual Verification:
- [ ] `RaisingProvider` is still defined exactly once, in the residual file
- [ ] Three moved describes spot-checked byte-identical against the original
- [ ] No new file contains a `doctest` line

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

## Phase 4: `test/predicator/visitors/string_visitor_test.exs` (1409 -> ~5 files)

### Overview

Four new sibling files plus the residual. This phase carries the two
cross-describe helper couplings, so its groupings are not freely
rearrangeable.

### Changes Required:

All new files at `test/predicator/visitors/`. Line numbers are describe starts
in the current `string_visitor_test.exs`.

| New file | Module | Describes moved (start lines) | ~Lines |
|---|---|---|---|
| `string_visitor_precedence_test.exs` | `Predicator.Visitors.StringVisitorPrecedenceTest` | 1148 `visit/2 - :minimal adds parens exactly when precedence requires it`, 1303 `visit/2 - if/block rendering (ADR-0013)` | ~245 |
| `string_visitor_operators_test.exs` | `Predicator.Visitors.StringVisitorOperatorsTest` | 538 `visit/2 - logical operators`, 735 `visit/2 - arithmetic operators`, 804 `visit/2 - unary operators`, 852 `visit/2 - equality operators`, 882 `visit/2 - mixed operator expressions` | ~331 |
| `string_visitor_integration_test.exs` | `Predicator.Visitors.StringVisitorIntegrationTest` | 43 `raw parser output`, 336 `visit/2 - integration with parser output`, 689 `visit/2 - integration with parser` | ~230 |
| `string_visitor_programs_test.exs` | `Predicator.Visitors.StringVisitorProgramsTest` | 915 `visit/2 - object keys`, 942 `visit/2 - program and assignment round-trip`, 991 `visit/2 - while round-trip (ADR-0013, px-3so.4 Phase 2)`, 1035 `visit/2 - cast nodes` | ~220 |

**Helper placement, which fixes these groupings:**

- The `@corpus` module attribute (lines 8-41) is used only by the `raw parser
  output` describe at line 43, so it **moves into
  `string_visitor_integration_test.exs`** and is deleted from the residual.
- `defp assert_program_round_trip/1` (line 983) lives inside the `program and
  assignment round-trip` describe and is called by the `while round-trip`
  describe. Both go to `string_visitor_programs_test.exs`; the helper moves
  with its describe, unchanged.
- `@precedence_corpus` (line 1266) and `@control_flow_corpus` (line 1304) are
  inside the two describes going to `string_visitor_precedence_test.exs`;
  module-level `defp assert_tree_fixpoint/1` (1389) and
  `defp assert_string_fixpoint/1` (1399), plus the comment above them, move to
  that file too and are deleted from the residual.

**Residual `string_visitor_test.exs`** keeps its preamble, `doctest
Predicator.Visitors.StringVisitor`, and 55 `visit/2 - literal nodes`, 169
`visit/2 - identifier nodes`, 192 `visit/2 - comparison nodes`, 257 `visit/2 -
spacing options`, 297 `visit/2 - parentheses options`, 320 `visit/2 - combined
options`, 505 `visit/2 - edge cases`, 1019 `visit/2 - :eq renders as valid 4.0
source` (~330 lines).

### Success Criteria:

#### Automated Verification:
- [ ] `mix test test/predicator/visitors/string_visitor_test.exs test/predicator/visitors/string_visitor_precedence_test.exs test/predicator/visitors/string_visitor_operators_test.exs test/predicator/visitors/string_visitor_integration_test.exs test/predicator/visitors/string_visitor_programs_test.exs`
      reports exactly **12 doctests, 157 tests, 0 failures**
- [ ] `mix test` reports **446 doctests, 2785 tests, 0 failures**
- [ ] Full `mix quality` is green
- [ ] Coverage stays at or above the 90% minimum in `coveralls.json` - the
      round-trip corpora are what cover several `StringVisitor` clauses, so a
      dropped `@corpus` shows up here and in
      `test/predicator/visitor_clause_coverage_test.exs`
- [ ] `git diff --stat` shows no file under `lib/`, `conformance/`, or
      `mix.exs` changed
- [ ] No file among the five exceeds 550 lines

#### Manual Verification:
- [ ] `@corpus`, `@precedence_corpus`, and `@control_flow_corpus` each appear
      exactly once across the five files, with the same entries as before
- [ ] `assert_tree_fixpoint/1`, `assert_string_fixpoint/1`, and
      `assert_program_round_trip/1` each appear exactly once
- [ ] No new file contains a `doctest` line

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

## Phase 5: `test/predicator/lexer_test.exs` (1339 -> ~4 files)

### Overview

Three new sibling files plus the residual. No module-level helpers or
attributes to relocate - the simplest of the six.

### Changes Required:

All new files at `test/predicator/`, beside the existing
`lexer_edge_cases_test.exs`. Line numbers are describe starts in the current
`lexer_test.exs`.

| New file | Module | Describes moved (start lines) | ~Lines |
|---|---|---|---|
| `lexer_identifiers_test.exs` | `Predicator.LexerIdentifiersTest` | 80 `tokenize/1 - identifiers and keywords` | ~295 |
| `lexer_operators_test.exs` | `Predicator.LexerOperatorsTest` | 534 `tokenize/1 - comparison operators`, 687 `tokenize/1 - parentheses`, 758 `tokenize/1 - arithmetic operators`, 1094 `:: token` | ~265 |
| `lexer_literals_test.exs` | `Predicator.LexerLiteralsTest` | 372 `tokenize/1 - list literals`, 412 `tokenize/1 - string literals`, 468 `tokenize/1 - single quoted string literals`, 963 `date literal tokenization`, 1013 `raw newlines inside literals` | ~295 |

**Residual `lexer_test.exs`** keeps its preamble, `doctest Predicator.Lexer`,
and 8 `tokenize/1 - integers`, 37 `tokenize/1 - duration literals (px-5c5)`,
590 `tokenize/1 - semicolon`, 699 `tokenize/1 - complex expressions`, 875
`tokenize/1 - position tracking`, 907 `tokenize/1 - error cases`, 945
`tokenize/1 - edge cases`, 1173 `additional edge cases for coverage`, 1235
`function calls` (~480 lines).

The single `alias Predicator.Lexer` (line 4) is copied into all three new
files; every describe here calls `Lexer.tokenize/1`.

### Success Criteria:

#### Automated Verification:
- [ ] `mix test test/predicator/lexer_test.exs test/predicator/lexer_identifiers_test.exs test/predicator/lexer_operators_test.exs test/predicator/lexer_literals_test.exs`
      reports exactly **5 doctests, 116 tests, 0 failures**
- [ ] `mix test` reports **446 doctests, 2785 tests, 0 failures**
- [ ] Full `mix quality` is green
- [ ] Coverage stays at or above the 90% minimum in `coveralls.json`
- [ ] `git diff --stat` shows no file under `lib/`, `conformance/`, or
      `mix.exs` changed
- [ ] No file among the four exceeds 550 lines

#### Manual Verification:
- [ ] The residual is still coherent - it holds numbers, durations,
      statement structure, and error/position handling, not leftovers
- [ ] Three moved describes spot-checked byte-identical against the original
- [ ] No new file contains a `doctest` line

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

## Phase 6: `test/predicator/visitors/instructions_visitor_test.exs` (1174 -> ~4 files)

### Overview

Three new sibling files plus the residual, with one cross-describe helper
coupling to respect.

### Changes Required:

All new files at `test/predicator/visitors/`, beside the existing
`instructions_visitor_positions_test.exs`. Line numbers are describe starts in
the current `instructions_visitor_test.exs`.

| New file | Module | Describes moved (start lines) | ~Lines |
|---|---|---|---|
| `instructions_visitor_control_flow_test.exs` | `Predicator.Visitors.InstructionsVisitorControlFlowTest` | 857 `visit/2 - assignment statements`, 910 `visit/2 - programs`, 987 `visit/2 - if/else lowering (ADR-0013)`, 1102 `visit/2 - while lowering (ADR-0013, px-3so.4 Phase 2)` | ~290 |
| `instructions_visitor_operators_test.exs` | `Predicator.Visitors.InstructionsVisitorOperatorsTest` | 360 `visit/2 - arithmetic operators`, 449 `visit/2 - unary operators`, 517 `visit/2 - equality operators`, 556 `visit/2 - mixed operator expressions` | ~275 |
| `instructions_visitor_values_test.exs` | `Predicator.Visitors.InstructionsVisitorValuesTest` | 634 `visit/2 - duration nodes`, 685 `visit/2 - relative date nodes`, 771 `visit/2 - list nodes`, 958 `visit/2 - cast nodes` | ~255 |

`defp visit_program/1` (line 988) is defined inside the `if/else lowering`
describe and used by `while lowering`; both are in
`instructions_visitor_control_flow_test.exs`, so the helper moves with its
describe unchanged and needs no promotion.

**Residual `instructions_visitor_test.exs`** keeps its preamble, `doctest
Predicator.Visitors.InstructionsVisitor`, and 8 `visit/2 - literal nodes`, 31
`visit/2 - identifier nodes`, 47 `visit/2 - comparison nodes`, 137 `visit/2 -
logical nodes`, 274 `visit/2 - integration with full pipeline` (~355 lines).

### Success Criteria:

#### Automated Verification:
- [ ] `mix test test/predicator/visitors/instructions_visitor_test.exs test/predicator/visitors/instructions_visitor_control_flow_test.exs test/predicator/visitors/instructions_visitor_operators_test.exs test/predicator/visitors/instructions_visitor_values_test.exs`
      reports exactly **9 doctests, 94 tests, 0 failures**
- [ ] `mix test` reports **446 doctests, 2785 tests, 0 failures**
- [ ] Full `mix quality` is green
- [ ] Coverage stays at or above the 90% minimum in `coveralls.json`, and
      `test/predicator/visitor_clause_coverage_test.exs` still passes
- [ ] `git diff --stat` shows no file under `lib/`, `conformance/`, or
      `mix.exs` changed
- [ ] No file among the four exceeds 550 lines
- [ ] Across the whole branch, `find test -name '*_test.exs' -exec wc -l {} + | sort -rn`
      shows no file over 550 lines except the two this bead does not touch:
      `test/predicator/context_location_test.exs` (694) and
      `test/predicator/duration_test.exs` (693), which are out of scope and
      unchanged, plus `test/predicator/visitors/instructions_visitor_positions_test.exs`
      (574), likewise unchanged

#### Manual Verification:
- [ ] `visit_program/1` is defined exactly once, in the control-flow file
- [ ] Three moved describes spot-checked byte-identical against the original
- [ ] No new file contains a `doctest` line
- [ ] Final read-through of the six directories: the file names describe what
      is in them, and a reader looking for a behavior can guess the file

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

## Testing Strategy

There are no new tests to write. The strategy is entirely about proving the
move was lossless.

### Unit Tests:

- **No test is authored, renamed, or deleted.** Every describe block, test
  name, and test body is moved verbatim.
- The count identity is the primary check, and it is checked twice per phase:
  once over the phase's own file group (which catches a describe accidentally
  dropped or duplicated *within* the group) and once over the whole suite
  (which catches a describe dropped entirely, or a `doctest` line duplicated
  into a new file).
- Baselines, captured before any change on this branch:
  whole suite **446 doctests, 2785 tests**; per file 58/208, 9/233, 13/171,
  12/157, 5/116, 9/94 for `predicator_test.exs`, `parser_test.exs`,
  `evaluator_test.exs`, `string_visitor_test.exs`, `lexer_test.exs`,
  `instructions_visitor_test.exs` respectively.
- A cheap independent cross-check, using the same pattern
  `gate.sabotage.test_pattern` uses:
  `grep -chE '\btest\s+"' <the phase's files> | paste -sd+ | bc` must equal
  the per-file baseline for that phase.

### Integration Tests:

Nothing under `test/predicator/integration/` changes. Those end-to-end
`Predicator.evaluate/3` suites are untouched by this bead and act as the
independent check that the pipeline still behaves - if a split accidentally
removed the only coverage of a `lib/` path, the coverage gate and
`test/predicator/visitor_clause_coverage_test.exs` are what report it, not a
new integration test.

The always-required "new AST node round-trips through `StringVisitor`"
criterion from `.claude/wurk/plan.md` is satisfied vacuously: no AST or
grammar node is added, removed, or altered by any phase.

### Manual Testing Steps:

1. `git diff --stat HEAD~1` after each phase and confirm the added and removed
   line counts are close to equal - a large asymmetry means content was lost
   or duplicated rather than moved.
2. For each phase, pick three moved describes at random and diff the block
   against the pre-phase version of the original file
   (`git show <sha>:<path>`); the blocks must be byte-identical.
3. `grep -rn 'doctest' test/ | wc -l` must be unchanged from the baseline
   across the whole branch.
4. Open each of the six directories and read the file names as a set: they
   should partition the module's behavior in a way a newcomer can navigate.

## References

- Bead: `px-n9x`
- Project instructions: `CLAUDE.md` (area labels, gate rules, commit
  conventions)
- Plan extension: `.claude/wurk/plan.md`
- Manifest: `.claude/wurk.json` (`gate.sabotage.test_roots` - checked, none of
  the six files is listed; `gate.full`, `gate.loop`)
- Existing split-file precedent: `test/predicator/parser_edge_cases_test.exs:1`,
  `test/predicator/parser_positions_test.exs:1`,
  `test/predicator/lexer_edge_cases_test.exs:1`,
  `test/predicator/visitors/instructions_visitor_positions_test.exs:1`
- Shared test-support precedent: `test/test_helper.exs`
  (`Predicator.SpanSlicing`, `Predicator.ASTShape`,
  `Predicator.Conformance.SchemaValidator` - whose moduledoc records why
  `test/support/` was not used)
- Sabotage-note list: `docs/research/260808-px-9ab-sabotage-notes.md`
- Related ADRs: `docs/adr/0005-worktree-parallelism-and-the-area-label-algebra.md`
  (this bead spans four areas and lands alone),
  `docs/adr/0006-irreversibility-places-the-human-gates.md` (commit authority)

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] Spot-check three moved describes against `git show HEAD:test/predicator_test.exs`
      and confirm the block is byte-identical, indentation included
- [ ] Each new file's alias list is exactly what its tests reference - no
      alias copied "just in case"
- [ ] No new file contains a `doctest` line
- [ ] Grouping reads sensibly to a human opening the directory

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

### Phase 2

- [ ] Three moved describes spot-checked byte-identical against
      `git show <phase-1-sha>:test/predicator/parser_test.exs`
- [ ] `parser_*_test.exs` naming reads consistently with the five
      pre-existing `parser_*_test.exs` files
- [ ] No new file contains a `doctest` line

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---
