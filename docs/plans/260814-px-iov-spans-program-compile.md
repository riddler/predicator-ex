# Spans-Based Statement Program Compile Implementation Plan

## Overview

Beads issue: `px-iov`

Add `Predicator.compile_program_with_spans/1`, the program-level counterpart to
the existing `Predicator.compile_with_spans/1`, so a host can get span-quality
diagnostics for a multi-statement script body instead of the point positions
`compile_program_with_positions/1` gives it today. Bead: px-iov (mirrors
st-57w in statifier-ex).

The headline finding of this plan's research is that **the machinery already
exists and already produces correct spans for programs**. `parse_program/2`
threads `spans: true` all the way down, assignment and expression statements
carry a span covering their own extent, the compiler's position and segment
position tables carry those spans through unchanged, and `execute/3` already
puts a `:span` on a runtime error when the program was compiled that way. What
is missing is the public entry point that asks for it, plus the tests and
documentation that pin the behaviour as a guarantee rather than an accident.

## Current State Analysis

**The asymmetry the bead describes is real, and it is only at the façade.**

Expressions have three compile entry points, one of which carries spans:

| Function | `lib/predicator.ex` | Parses with |
|---|---|---|
| `compile/1` | 687 | `parse/1` |
| `compile_with_positions/1` | 711 | `parse/1` |
| `compile_with_spans/1` | 735 | `parse(spans: true)` |

Statement programs have two, neither of which does:

| Function | `lib/predicator.ex` | Parses with |
|---|---|---|
| `compile_program/1` | 758 | `parse_program/1` |
| `compile_program_with_positions/1` | 776 | `parse_program/1` |

Neither program function takes an options keyword, so a caller has no way to
ask for spans on a program through the public façade at all.

**Everything below the façade is already span-capable.** The three functions
that would have to change if it were not are all generic over which mode the
AST was parsed in:

- `Predicator.parse_program/2` already accepts `opts` and forwards them to
  `Predicator.Parser.parse_program/2` (`lib/predicator.ex:865` area;
  `lib/predicator/parser.ex:423-424`), which sets `spans?` on its state from
  `Keyword.get(opts, :spans, false)` exactly as `parse/2` does
  (`lib/predicator/parser.ex:366`). The `loc/3` dispatch at
  `lib/predicator/parser.ex:1487-1488` is shared by every node builder, so
  statement nodes get the same treatment expression nodes do.
- `Predicator.Compiler.to_instructions_with_segment_positions/2`
  (`lib/predicator/compiler.ex:121`) reads whatever is in each node's trailing
  slot and copies it into the tables. It never inspects the shape.
- `Predicator.build_compiled_result/1` (`lib/predicator.ex:788`) is already
  shared by `compile_with_positions/1`, `compile_with_spans/1`, and
  `compile_program_with_positions/1`, and its own comment says the three
  "differ only in how they parse ... never in how the parse result becomes a
  `%Compiled{}`".
- `Predicator.Types` already documents `span()`, `span_table()`, and a
  `segment_position_table()` whose values are `position() | span() | nil`
  (`lib/predicator/types.ex:129-167`), and `%Compiled{}`'s typespec is written
  against those (`lib/predicator/compiled.ex:84-90`). No type widens.

**Verified by running the pipeline** (`mix run` against this worktree, source
`"x = 1; x + 1; y.z = 2"` parsed with `spans: true`):

```
positions:
  0 => {{1, 1}, {1, 2}}    # ["lit", "x"]      the assignment target
  1 => {{1, 5}, {1, 6}}    # ["lit", 1]        the value
  2 => {{1, 1}, {1, 6}}    # ["store", 1]      <- statement 1's own extent
  3 => {{1, 8}, {1, 9}}    # ["load", "x"]
  4 => {{1, 12}, {1, 13}}  # ["lit", 1]
  5 => {{1, 8}, {1, 13}}   # ["add"]
  6 => {{1, 8}, {1, 13}}   # ["pop"]           <- statement 2's own extent
  ...
segment_positions:
  2  => [{{1, 1}, {1, 2}}]
  10 => [{{1, 15}, {1, 16}}, {{1, 15}, {1, 18}}]
```

That is precisely the acceptance criterion "a span table covering each
statement's own extent", satisfied by the existing compiler with no visitor
change: the instruction that terminates a statement (`store` for an
assignment, `pop` for a bare expression statement) already carries the
statement node's span.

**The end-to-end path works too.** Compiling `"x = 1; missing + 1"` with
spans and running `Predicator.execute/3` returns

```elixir
%Predicator.Errors.UndefinedVariableError{
  variable: "missing", position: {1, 8}, span: {{1, 8}, {1, 15}}
}
```

against `span: nil` on the same program compiled with point positions.
`Errors.put_position/2` (`lib/predicator/errors.ex:41-56`) already
discriminates point from span by tuple shape rather than by a flag, setting
`:span` and `:position` together when it is handed a span. The evaluator
passes whatever it finds in the tables straight through
(`lib/predicator/evaluator.ex:439-456`, `1602-1610`), so nothing between the
compiler and the error struct has to know which mode a program was compiled
in.

**The error arm.** `build_compiled_result/1`'s error clause
(`lib/predicator.ex:795`) formats the parser's `{:error, message, line,
column}` 4-tuple into `"#{message} at line #{line}, column #{column}"`. That
is what statifier re-parses. Two facts bound what can be done about it here:

1. The structure is not actually lost - it is one call away.
   `Predicator.parse_program(source, spans: true)` returns the raw
   `{:error, message, line, column}` tuple, publicly, today.
2. A parse error **cannot** carry a span today even in span mode. Verified:
   `parse_program("x =", spans: true)` returns `{:error, "...", 1, 4}`, a
   point. Spans are node metadata produced by `loc/3` as a node is built, and
   a parse error is precisely the case where no node was built. Making the
   error arm span-bearing is new lexer/parser work (a failing token's extent),
   not a façade change.

## Desired End State

`Predicator.compile_program_with_spans/1` exists, is documented alongside the
other program compile functions, and returns `{:ok, %Compiled{}} | {:error,
binary()}` - the same shape `compile_with_spans/1` returns - where
`compiled.positions` and `compiled.segment_positions` hold `t:span/0` values
and `compiled.instructions` is byte-identical to `compile_program/1`'s output
for the same source. The existing four compile entry points are untouched.

Verify by:

- `mix quality` green, including the new doctests and unit tests.
- `Predicator.compile_program_with_spans("x = 1; x + 1")` returning a
  `%Compiled{}` whose `positions[2]` and `positions[6]` slice out of the
  source exactly `"x = 1"` and `"x + 1"`.
- `Predicator.execute/3` on that struct putting a `:span` on an error, and
  `compile_program_with_positions/1` on the same source still putting only a
  `:position`.

### Key Discoveries:

- `build_compiled_result/1` (`lib/predicator.ex:788`) is already mode-agnostic
  and already shared by three callers; the new function is a fourth caller,
  not a new code path.
- `Parser.parse_program/2` already accepts and threads `:spans`
  (`lib/predicator/parser.ex:423-424`); nothing in the parser needs to change.
- Statement extent comes free: the terminating `store`/`pop` instruction
  already carries the statement node's own span (verified above).
- `if` statements behave correctly too: for `"if a { x = 1 } else { y = 2 }"`,
  `pop_jump_if_falsy` and `jump` carry the whole if-statement's span
  `{{1, 1}, {1, 30}}` while the nested assignment's `store` carries
  `{{1, 8}, {1, 13}}`. Nesting does not flatten the extent.
- The `{:program, statements, loc}` node's **own** span never reaches the
  tables: `InstructionsVisitor.visit_annotated/2` discards it with `_position`
  and flat-maps over the statements
  (`lib/predicator/visitors/instructions_visitor.ex:393-395`). Every table
  entry therefore comes from a statement's or a segment's own slot. This is
  the correct behaviour for this bead - the acceptance criterion asks for
  statement extents, not a whole-program extent - but it means a caller
  wanting the program's overall extent must take it from
  `parse_program(source, spans: true)`, not from `compiled.positions`. Say so
  in the Phase 1 `@doc` rather than leaving it to be discovered.
- `store_annotation/2`
  (`lib/predicator/visitors/instructions_visitor.ex:419-424`) is the one place
  in the compiler that matches on span shape at all, and it does so to decide
  whether to blame the assignment's own extent or the target's - which is
  exactly why an assignment's `store` already carries the statement extent.
- `Types.segment_position_table()` (`lib/predicator/types.ex:159-167`) already
  admits spans, so `segment_positions` needs no widening. ADR-0009 governs
  this envelope: `segment_positions` was added as a new field precisely so the
  meaning of `positions` never has to change per mode.
- ADR-0009 also settles that the position table rides on `%Compiled{}` rather
  than a third tuple element, which is why this is a one-line function body.
- A parse error carries a point, never a span, even in span mode - see
  "Current State Analysis". This is the fact that decides the bead's design
  question.

## What We're NOT Doing

- **Not changing the error arm to a struct in this bead.** The bead asks
  whether the error arm should carry a span or structure; the answer here is
  no, deferred, for three reasons recorded so the decision is not relitigated:
  (a) the acceptance criterion demands the shape match `compile_with_spans/1`,
  and a structured error on the program arm alone would create exactly the
  asymmetry this bead exists to remove; (b) restructuring all five compile
  entry points is a breaking change to a documented public return type and
  needs a major version and its own bead, not a side effect of an additive
  one - the v7.0.0 `Math.pow` return-type change is the precedent for how this
  repo treats such a change; (c) a parse error has no node and therefore no
  span, so "carry a span" is not implementable at the façade at all. Phase 3
  documents the supported structured route (`parse_program/2`'s 4-tuple) and
  files the follow-on bead.

  ADR-0004 is worth naming here rather than leaving for someone to find. It
  establishes errors-as-values and observes that the *evaluation* surface has
  been `{:ok, value} | {:error, struct}` since the error structs landed. That
  is directional support for the follow-on bead, not an argument that this
  bead must do it: `evaluate/3` and `execute/3` already return structs and are
  unaffected here, and the compile arm's binary predates the struct family
  across all five entry points. Nothing in this plan makes that arm harder to
  change later - the new function shares `build_compiled_result/1`, so the
  follow-on edits one clause and reaches all four `%Compiled{}` callers at
  once.
- **Not adding an `opts` keyword to `compile_program/1` or
  `compile_program_with_positions/1`.** The expression family expresses mode
  by function name, not by option, and the bead's acceptance criterion asks
  for uniform treatment. A `spans: true` option on `compile_program/1` would
  also have to answer what it means for a function that returns a bare
  instruction list (nothing - the instruction list is identical either way).
- **Not touching the lexer, parser, compiler, or any visitor.** All the span
  behaviour this bead needs already exists there and was verified by running
  it. A change to any of them would be evidence the design went wrong.
- **No `## ISA Impact` section.** Per `.claude/wurk/plan.md`, that section is
  included only when an opcode is added, removed, renamed, or altered. Nothing
  here touches an opcode; the emitted instruction list is byte-identical to
  `compile_program/1`'s, and the ISA version does not move.
- **No conformance-corpus change.** The corpus pins evaluation semantics, not
  façade API surface, and no instruction, value, or function behaviour moves.
  No phase runs `mix corpus.generate`, and no corpus diff should appear; one
  appearing means something unintended changed and the phase should stop.
- **No `StringVisitor` work.** The extension's round-trip criterion is about
  new AST or grammar nodes; this plan adds none.

## Implementation Approach

Three phases, each independently committable and each green under the full
`mix quality` gate on its own.

Phase 1 adds the function and the unit tests that prove it behaves like its
expression sibling. Phase 2 adds the integration coverage that turns
"statement extent" from an observed behaviour into a pinned guarantee, by
slicing spans back out of the source and by running a spans-compiled program
to an error. Phase 3 discharges the bead's design question in prose and files
the follow-on bead.

The split is deliberate rather than mechanical: Phase 1 is the smallest thing
that satisfies the acceptance criterion and could ship alone; Phase 2 is what
makes the guarantee survive a future refactor of the compiler; Phase 3 is
documentation and tracker work that touches no Elixir code and therefore
cannot break Phase 1 or 2.

---

## Phase 1: `compile_program_with_spans/1`

### Overview

Add the public function, its `@doc` and `@spec`, its doctest, unit tests
beside the existing program compile tests, and the changelog entry.

### Changes Required:

#### 1. The façade

**File**: `lib/predicator.ex`
**Changes**: Add `compile_program_with_spans/1` immediately after
`compile_program_with_positions/1` (which ends at line 778), so the program
family reads in the same order as the expression family. Body mirrors
`compile_with_spans/1` at line 735.

```elixir
@doc """
Compiles a statement-sequence string to a `t:Predicator.Compiled.t/0` - the
instruction list plus a source-span side table, as one value.

The program-shaped echo of `compile_with_spans/1`. `compiled.instructions` is
identical to `compile_program/1`'s output; `compiled.positions` maps each
instruction's 0-based index to the `t:Predicator.Types.span/0` of the AST node
that emitted it, and `compiled.segment_positions` holds spans too. The
instruction that terminates a statement - `store` for an assignment, `pop` for
a bare expression statement - carries that statement's own source extent, so a
host can underline the failing statement inside a multi-statement body rather
than the whole program.

Pass the struct straight to `execute/3`, which threads the table itself; an
error it returns then carries `:span` as well as `:position`.

Store `compiled.instructions`, not the struct - see `Predicator.Compiled`.

  ## Examples

    iex> {:ok, compiled} = Predicator.compile_program_with_spans("x = 1")
    iex> compiled.instructions
    [["lit", "x"], ["lit", 1], ["store", 1]]
    iex> compiled.positions
    %{0 => {{1, 1}, {1, 2}}, 1 => {{1, 5}, {1, 6}}, 2 => {{1, 1}, {1, 6}}}
"""
@spec compile_program_with_spans(binary()) :: {:ok, Compiled.t()} | {:error, binary()}
def compile_program_with_spans(source) when is_binary(source) do
  source |> parse_program(spans: true) |> build_compiled_result()
end
```

Two notes on transcribing the block above. The `## Examples` line is indented
here only so this plan's own section structure parses; in the real `@doc` it
sits flush left, exactly as in `compile_with_spans/1`. And the doctest values
were taken from a real run of the pipeline in this worktree, but re-verify
them with `mix test` rather than trusting the transcription.

#### 2. The shared helper's comment

**File**: `lib/predicator.ex` (lines 780-783)
**Changes**: `build_compiled_result/1`'s comment enumerates its callers by
name. Add the new one so the list stays true:

```elixir
# Shared by compile_with_positions/1, compile_with_spans/1,
# compile_program_with_positions/1, and compile_program_with_spans/1: each
# differs only in how it parses (an expression vs a program, point positions
# vs spans), never in how the parse result becomes a %Compiled{} or a binary
# error.
```

#### 3. Unit tests

**File**: `test/predicator/execute_test.exs`
**Changes**: Rename the existing describe block at line 247 from
`"compile_program/1 and compile_program_with_positions/1"` to
`"compile_program/1, compile_program_with_positions/1, and
compile_program_with_spans/1"` and add tests modelled on the
`compile_with_spans/1` block at `test/predicator_test.exs:278-308`:

- returns a `%Compiled{}` with the same instruction list `compile_program/1`
  returns, for a multi-statement source and for one containing an `if`
- `positions` values are spans (2-tuples of 2-tuples), not point positions
- `segment_positions` carries spans for a nested target: for `"a.b = 1"`,
  `%{3 => [{{1, 1}, {1, 2}}, {{1, 1}, {1, 4}}]}` - the identifier's span then
  the property access's - contrasting the point-mode
  `%{3 => [{1, 1}, {1, 3}]}` already asserted at line 270. That span-mode
  value is transcribed from a run against `"y.z = 2"` and shifted to column 1;
  re-verify it with `mix test` rather than trusting the arithmetic, the same
  way the doctest values above are re-verified
- the error arm equals `compile_program/1`'s for the same bad source, matching
  the parity assertion at `test/predicator_test.exs:307`
- the emitted instruction list is byte-identical to
  `compile_program_with_positions/1`'s for the same source - spans change only
  the side table

#### 4. Changelog

**File**: `CHANGELOG.md`
**Changes**: There is no `## [Unreleased]` section (7.0.0 was released the
same day). Add one above `## [7.0.0]` with an `### Added` entry describing
`compile_program_with_spans/1`, that it completes the program family's
symmetry with the expression family, that the instruction list is unchanged,
and that it is purely additive.

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes (`mix quality`), including `credo --strict`,
      dialyzer against the new `@spec`, and the new doctest
- [x] Coverage stays above the 90% minimum in `coveralls.json` - the gate
      fails the run if it does not
- [x] `git status --porcelain conformance/` is empty - no corpus movement
- [x] `grep -c "compile_program_with_spans" lib/predicator.ex` is at least 3
      (`@spec`, `def`, and the shared helper's comment)
- [x] `git diff -U0 lib/predicator.ex | grep '^-' | grep -v '^---'` shows
      exactly one removed line - the old `build_compiled_result/1` comment
      line being rewritten. Any other removal means an existing entry point
      was touched, which the additive claim forbids

#### Manual Verification:
- [ ] `Predicator.compile_program_with_spans("x = 1; x + 1")` in `iex -S mix`
      returns spans whose slices out of the source read `"x = 1"` and
      `"x + 1"`
- [ ] Read the new `@doc` beside `compile_with_spans/1`'s at line 715-734 and
      confirm it follows the same four-paragraph order: what it returns, what
      `positions` holds, what to pass it to, and the "store the instructions,
      not the struct" warning. A missing or reordered paragraph is the defect
      to catch, not the prose style

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run full `mix quality` as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the
next phase. In looped (`--loop`) execution, this phase's Automated
Verification gates advancement automatically (via `/wurk:commit --auto`), and
Manual Verification items are deferred and surfaced once at the end instead of
blocking here.

---

## Phase 2: Pin the statement-extent guarantee end to end

### Overview

Phase 1's tests assert values; this phase asserts the *property* - that every
span slices back out of the source text it claims to cover, and that a
spans-compiled program produces span-bearing runtime errors. This is what
keeps a future compiler or visitor refactor from silently degrading program
spans, and it is the behaviour statifier's ADR-0014 constraint actually
depends on.

### Changes Required:

#### 1. Program spans in the integration suite

**File**: `test/predicator/integration/spans_test.exs`
**Changes**: The file already carries an expression `@corpus` and a "source
cross-check" describe block that slices every node's span out of the source
(line 35 onward). Add a parallel `@program_corpus` and a describe block for
programs. Sources to include, chosen to cover each statement shape:

```elixir
@program_corpus [
  "x = 1",
  "x = 1; x + 1",
  "a.b = 1",
  "a[0] = 1",
  "x = 1; y = x + 1; y > 1",
  "if a { x = 1 }",
  "if a { x = 1 } else { y = 2 }",
  "x = 1;\ny = 2"
]
```

New tests:

- **instruction-list identity**: for every program in the corpus,
  `compile_program_with_spans/1`'s instructions equal `compile_program/1`'s.
  This is the program echo of the assertion at line 98.
- **every span slices**: for every program, every value in `positions` and
  every value in `segment_positions` is a well-formed span whose start is not
  after its end, and slicing the source between the two offsets yields text
  that is a substring of the source. Reuse whatever slicing helper the
  expression cross-check already uses rather than writing a second one.
- **statement extent**: for `"x = 1; x + 1"`, the span on the `store` and the
  span on the `pop` slice to exactly `"x = 1"` and `"x + 1"` respectively.
  Assert the sliced strings, not the tuples - a tuple assertion tests
  arithmetic, a slice assertion tests the claim.
- **nesting does not flatten**: for `"if a { x = 1 } else { y = 2 }"`, the
  `pop_jump_if_falsy`'s span slices to the whole if-statement while the inner
  `store`'s span slices to `"x = 1"`.
- **multi-line**: for `"x = 1;\ny = 2"`, the second statement's span starts on
  line 2, confirming the slicing helper handles line offsets.

#### 2. Runtime error spans for programs

**File**: `test/predicator/evaluator_positions_test.exs`
**Changes**: The file already proves this for expressions with
`compile_with_spans/1` at lines 153 and 190. Add the program echo: compile
`"x = 1; missing + 1"` with `compile_program_with_spans/1`, run
`Predicator.execute/3` with an empty context, and assert the returned
`UndefinedVariableError` carries `span: {{1, 8}, {1, 15}}` alongside
`position: {1, 8}`; then assert the same program compiled with
`compile_program_with_positions/1` yields `span: nil`. The pair is the point:
it shows the span is a consequence of the compile mode, not of the error.

### Success Criteria:

#### Automated Verification:
- [ ] Full quality gate passes (`mix quality`)
- [ ] `mix test test/predicator/integration/spans_test.exs` and
      `mix test test/predicator/evaluator_positions_test.exs` both pass
- [ ] Coverage stays above the 90% minimum in `coveralls.json`
- [ ] `git status` shows no diff under `conformance/` and no diff under `lib/`
      - this phase is tests only

#### Manual Verification:
- [ ] Sabotage check: temporarily change the new function to parse without
      `spans: true`, confirm the new tests go red, then revert. This is not a
      binding test under `gate.sabotage.test_roots` and needs no note in
      `docs/research/260808-px-9ab-sabotage-notes.md`, but the check is what
      makes the phase worth its own commit
- [ ] Confirm no new assertion was written by copying a tuple out of a run of
      the new code: every cross-check compares a **sliced substring** against
      a string literal typed by hand. A test asserting `{{1, 8}, {1, 13}}`
      instead of `"x + 1"` proves only that the code equals itself

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run full `mix quality` as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the
next phase. In looped (`--loop`) execution, this phase's Automated
Verification gates advancement automatically (via `/wurk:commit --auto`), and
Manual Verification items are deferred and surfaced once at the end instead of
blocking here.

---

## Phase 3: The error arm - document the decision, file the follow-on

### Overview

Discharge the design question the bead raises. The decision is made in this
plan ("What We're NOT Doing"); this phase writes it where a caller will find
it and opens the bead that would change it.

### Changes Required:

#### 1. Name the structured route in the docs

**File**: `lib/predicator.ex`
**Changes**: Add a short paragraph to the `@doc` of `compile_program/1`,
`compile_program_with_positions/1`, and `compile_program_with_spans/1` saying
that the error arm is a formatted binary for uniformity with the expression
family, and that a caller wanting the line and column as data should call
`parse_program/2` directly, which returns `{:error, message, line, column}` -
no message re-parsing required. Add the mirror note to `compile/1`,
`compile_with_positions/1`, and `compile_with_spans/1` only if it can be done
without restating the same paragraph six times; a single sentence pointing at
`parse_program/2` on the three program functions is sufficient and is what the
bead asked about.

Also state the limitation plainly in the `compile_program_with_spans/1` doc:
spans describe AST nodes, so a parse error carries a point position and never
a span, in span mode as much as in point mode.

#### 2. Note the guarantee in the architecture doc

**File**: `docs/architecture.md`
**Changes**: The `### Core Components` list (line 87 onward) describes the
Compiler at line 91 but nothing in the document enumerates the façade's
compile entry points - `grep -n "compile_program" docs/architecture.md`
returns nothing today. Add a `### Compile entry points` subsection after that
list, listing the five compile functions in two families
(expression, program) with the three modes (bare list, point positions,
spans), and stating the statement-extent guarantee Phase 2 pins. Keep it to a
table plus two sentences; the detailed contract lives in the `@doc`s and
should not be duplicated.

#### 3. File the follow-on bead

**Command**: `bd create` (tracker work, authorized at any time by the
authority table in `CLAUDE.md`)
**Changes**: File a bead for the structured error arm, carrying:

- title along the lines of "Decides whether compile errors become structured
  values"
- `area:api` (and `area:lexer-parser` if the span-bearing parse error is kept
  in scope)
- the scope: all five compile entry points move together or none do; a
  span-bearing parse error needs a failing token's extent from the parser,
  which is new work in `lib/predicator/parser.ex`, not a façade change; the
  return-type change is breaking and needs a major version
- the reason it is separate: recorded in this plan and in px-iov's PR
- a `mirrors:` line for statifier's st-57w if statifier files its half; if it
  has not, say so rather than inventing an id, per `CLAUDE.md`'s rule that an
  unresolvable `mirrors:` id is a defect

Add a `bd note` to px-iov recording the decision and the new bead's id, so the
mirror reconciliation with st-57w has something to point at.

### Success Criteria:

#### Automated Verification:
- [ ] Full quality gate passes (`mix quality`) - the `@doc` edits are compiled
      and any doctest in them runs
- [ ] `mix test test/docs_adr_links_test.exs` passes - the architecture doc
      edit must not break a link
- [ ] `bd show <new-id>` returns the follow-on bead with an `area:` label and
      a description naming the five entry points
- [ ] `git status` shows no diff under `conformance/`

#### Manual Verification:
- [ ] A reader of `compile_program_with_spans/1`'s doc can tell, without
      reading this plan, how to get the line and column as data
- [ ] The architecture doc's new subsection is at most a table plus two
      sentences, and states no return shape, error shape, or span-table detail
      that is already in the `@doc`s - it points at them instead
- [ ] The follow-on bead is actionable on its own - someone picking it up does
      not need this plan to understand the scope

**Implementation Note**: This phase touches no Elixir logic; the gate still
runs because `@doc` content is compiled. In interactive execution, pause here
for the human to confirm the manual testing. In looped (`--loop`) execution,
this phase's Automated Verification gates advancement automatically (via
`/wurk:commit --auto`), and Manual Verification items are deferred and
surfaced once at the end instead of blocking here.

---

## Testing Strategy

### Unit Tests:

- `test/predicator/execute_test.exs` - the program compile family's behaviour:
  `%Compiled{}` shape, span-valued `positions` and `segment_positions`,
  instruction-list identity with `compile_program/1` and
  `compile_program_with_positions/1`, error-arm parity. Pattern-matching
  style, matching the surrounding block at line 247.
- `test/predicator/evaluator_positions_test.exs` - the paired assertion that a
  spans-compiled program yields `span:` on a runtime error and a
  positions-compiled one yields `span: nil`.
- Doctest on `compile_program_with_spans/1` - the smallest example that shows
  a span table, run by the suite.

Edge cases worth covering explicitly, because they are where a naive
implementation would drift: a nested assignment target (`a.b = 1`,
`a[0] = 1`) whose `segment_positions` list must hold one span per segment; a
bare expression statement, whose extent lands on `pop` rather than `store`; a
statement nested inside an `if` block, whose extent must not be the whole
if-statement; a multi-line program, where the second statement's span starts
on line 2; and a parse error, which must return the same formatted binary
`compile_program/1` returns.

### Integration Tests:

`test/predicator/integration/spans_test.exs` gains a program corpus and a
source cross-check that slices every span back out of the source, mirroring
what the file already does for expressions. This is the end-to-end statement
of the guarantee: `Predicator.compile_program_with_spans/1` ->
`Predicator.execute/3` -> a span-bearing error, over a corpus rather than a
single case.

### Manual Testing Steps:

1. `iex -S mix`, then
   `{:ok, c} = Predicator.compile_program_with_spans("x = 1; x + 1")` and
   confirm `c.positions[2]` and `c.positions[6]` slice to `"x = 1"` and
   `"x + 1"`.
2. Compile `"x = 1; missing + 1"` both ways and run `Predicator.execute/3`
   with `%{}`; confirm the spans compile puts `span: {{1, 8}, {1, 15}}` on the
   error and the positions compile leaves `span: nil`.
3. Compile `"if a { x = 1 } else { y = 2 }"` with spans and confirm the jump
   instructions carry the whole if-statement's extent while the inner `store`
   carries only `"x = 1"`.
4. Confirm `Predicator.compile_program("x = 1; x + 1")` and
   `Predicator.compile_program_with_positions("x = 1; x + 1")` return exactly
   what they did before the branch - the additive claim.
5. `Predicator.parse_program("x =", spans: true)` and confirm it returns the
   `{:error, message, 1, 4}` 4-tuple the Phase 3 documentation points callers
   at.

## References

- Bead: `px-iov` (mirrors `st-57w` in statifier-ex)
- Existing sibling to model on: `Predicator.compile_with_spans/1`,
  `lib/predicator.ex:735`
- The functions that gain a sibling: `lib/predicator.ex:758` and
  `lib/predicator.ex:776`
- The shared helper that needs no change: `lib/predicator.ex:788`
- Parser span threading: `lib/predicator/parser.ex:423-424`,
  `lib/predicator/parser.ex:1487-1488`
- Compiler tables: `lib/predicator/compiler.ex:121`
- Types: `lib/predicator/types.ex:129-167`
- Envelope: `lib/predicator/compiled.ex:84-90`
- Related ADRs: `docs/adr/0009-the-compiled-envelope-carries-the-position-table.md`
  (the `%Compiled{}` envelope and why `segment_positions` is a separate
  field), `docs/adr/0004-no-eval-errors-are-values.md` (errors are values;
  bears on the deferred error-arm decision),
  `docs/adr/0003-the-elixir-implementation-leads-the-isa.md` (this
  repo leads the ISA; nothing here moves it),
  `docs/adr/0006-irreversibility-places-the-human-gates.md` (push, PR, and
  release stay human-gated)
- Prior plans: `docs/plans/260805-px-3kr-position-spans.md` (introduced
  expression spans and `compile_with_spans/1`),
  `docs/plans/260808-px-tbv.2-store-opcode-execute.md` (introduced the program
  compile family), `docs/plans/260811-px-aen-visitor-unsupported-node-error.md`
  (the current `{:error, binary()}` shape across the compile façade)
- Project extension: `.claude/wurk/plan.md`

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] `Predicator.compile_program_with_spans("x = 1; x + 1")` in `iex -S mix`
      returns spans whose slices out of the source read `"x = 1"` and
      `"x + 1"`
- [ ] Read the new `@doc` beside `compile_with_spans/1`'s at line 715-734 and
      confirm it follows the same four-paragraph order: what it returns, what
      `positions` holds, what to pass it to, and the "store the instructions,
      not the struct" warning. A missing or reordered paragraph is the defect
      to catch, not the prose style

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run full `mix quality` as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the
next phase. In looped (`--loop`) execution, this phase's Automated
Verification gates advancement automatically (via `/wurk:commit --auto`), and
Manual Verification items are deferred and surfaced once at the end instead of
blocking here.

---
