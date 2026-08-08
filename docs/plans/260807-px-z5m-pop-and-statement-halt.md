# Reserving `pop` and the Statement-Program Halt Contract Implementation Plan

## Overview

`docs/isa.md` reserves one opcode name for the 4.0 statement layer, `store`, and
specifies exactly one execution contract: "the result is the top of the stack at
halt; an empty stack at halt is `empty_stack`". px-tbv.2 needs a second reserved
name (`pop`, the statement boundary) and a second execution contract (a
statement program halts with an empty stack **by design** and its result is a
context, not a stack value). Neither exists in the spec today.

This plan writes both into `docs/isa.md` and adds the one test that keeps the
reservation honest. Beads issue: **px-z5m** (`area:docs`; this plan adds
`area:evaluator` for the test file). It blocks **px-tbv.1** and **px-tbv.2**.

No opcode is added, removed, or altered. `@isa_version` stays **2**. This is
specification-only work: it makes px-tbv.2 a data change (two opcodes, one
entry point) rather than a spec change discovered mid-implementation.

Research: `docs/research/260807-px-t2v-px-z5m-isa-retirement-and-pop.md`
(areas 5 and 6; this plan decides its Open Questions 5, 6, and 7).
Sibling plan landed on the same file: `docs/plans/260807-px-t2v-isa-retirement-mechanics.md`.
Governing ADRs: **ADR-0001** (the statement layer and `["store", n]`),
**ADR-0003** (how the ISA moves).

## Current State Analysis

### `pop` does not exist anywhere

`grep -rn '"pop"'` over `lib/`, `test/`, `docs/`, and `conformance/` returns
nothing. The token appears only as the `_or_pop` suffix on
`jump_if_falsy_or_pop` / `jump_if_true_or_pop`, which are live ISA v2 opcodes
that pop *conditionally as part of a jump* - a different thing entirely, and a
name collision worth calling out in the spec so a sibling implementer does not
read `pop` as a shorthand for either.

### `store`'s reservation is a three-part pattern

`store` is reserved in exactly three places, and this is the pattern `pop`
should be measured against:

1. `docs/isa.md` §6 ("Not in the ISA"), one bullet: "specified by ADR-0001 for
   the 4.0 statement layer, not implemented and not accepted by any current
   evaluator clause. Reserved name, tier 6."
2. `docs/isa.md` §4's tier table, the tier-6 row:
   `| 6 | statements | (none yet - reserved for \`store\`) |`
3. `test/predicator/instructions_test.exs:186-192`, a test asserting `store` is
   *currently unknown*, with the comment "px-tbv.2 adds it, at which point this
   expectation flips intentionally rather than by accident."

Note what reservation deliberately does **not** include: no `@opcodes` entry, no
§4 opcode-table row, no evaluator clause, no corpus case. A reserved name is
prose plus a guard.

### The tier-6 cell's leading paren is load-bearing

`test/predicator/isa_sync_test.exs:274-283`, `tier_row_opcodes/1`:

```elixir
defp tier_row_opcodes(opcodes_cell) do
  if String.starts_with?(opcodes_cell, "(") do
    []
  else
    ...scan every backtick span...
  end
end
```

The tier-names test (`:122-149`) asserts each tier row's opcode list equals
**exactly** the set `@opcodes` assigns that tier. Tier 6's cell contributes zero
opcodes solely because it begins with `(`. A cell that named `store` and `pop`
without that leading paren would require both in `@opcodes`, which would
contradict `instructions_test.exs:189-192` and fail `opcode_coverage_test.exs`
(every key of `opcodes/0` needs a corpus case). This is Open Question 7, and it
is mechanical, not editorial: **whatever the tier-6 cell becomes must still
start with `(`.**

### Section 2 states one execution contract, unconditionally

`docs/isa.md` §2, currently:

> - The result is the top of the stack at halt. An empty stack at halt is an
>   `EvaluationError` with reason `"empty_stack"`; it is the one error that
>   belongs to no instruction and therefore carries no source position.

The section is prefaced "The rules that govern **every** opcode". There is no
mode qualifier anywhere in it and no notion of a program that is not an
expression. The evaluator implements the rule in one place,
`lib/predicator/evaluator.ex:86-102` (`run_prepared/1`), with no mode parameter -
and its success clause matches `[result | _rest]`, so a *deeper* stack already
returns its top and silently discards the rest. Only the empty case errors.

The corpus's characterization of that error today
(`conformance/cases/errors.json`, `errors/empty-stack-at-halt`) is "only
reachable via an empty hand-built instruction list" - a sentence a statement
program halting empty by design directly contradicts.

### A program is a flat list with no header

§2's first bullet: "A program is a flat list of instructions... **Nothing else is
in the wire format**." So no field in a serialized program can say "this is a
statement program". This is Open Question 5, and the wire format forecloses
every answer except one.

### What px-tbv.2 and px-h66 have already settled downstream

- px-tbv.2 AC: "A statement boundary compiles to `["pop"]`, discarding
  expression-statement values", and `Predicator.execute(program_or_source, ctx)`
  returns `{:ok, %Context{}} | {:error, e, %Context{}}`.
- px-h66 (per px-z5m's 2026-08-07 note): W3C SCXML 1.0 §4.9 requires
  stop-on-error but **not** rollback, and IRP test 156 observationally pins
  non-rollback. Hence the widened three-element error return: the partial
  context is handed back and commit-or-discard is the **caller's** policy.
  `docs/design/260807-px-h66-scxml-error-semantics.md` is not present in this
  worktree (px-h66 is being worked elsewhere); the note in `bd show px-z5m`
  carries the reasoning and the proposed wording, which is sufficient.

### Nothing in the suite parses §2 or §6

`isa_sync_test.exs` reads three things out of `docs/isa.md`: §4's opcode table
(two regexes), §4's tier-names table, and the literal line
`Current version: **ISA v2**.`. §2's and §6's prose are unparsed. So the halt
contract's wording is free-form; only the tier-6 cell has a mechanical
constraint.

## Desired End State

`docs/isa.md` states, and the suite guards where it can, that:

1. **`pop` is a reserved tier-6 name beside `store`** - §6 bullet, tier-6 cell,
   and a unit test asserting it is currently an unknown opcode, exactly
   mirroring `store`'s three-part treatment.
2. **The ISA has two execution modes, and the mode is carried by the entry
   point, not by the artifact.** Expression mode's result is the stack top at
   halt; statement mode's result is the context at halt. The instruction set is
   identical in both; no opcode is mode-restricted.
3. **`empty_stack` is an expression-mode rule.** A statement program halts with
   an empty stack by design and that is a normal halt.
4. **A statement program that halts on an error has no result**, and
   commit-or-discard of the partial context is a host-API property the VM stays
   out of.

Verification: `mix quality` green - specifically `isa_sync_test.exs` still
parses all 25 opcode rows and finds tier 6 empty, `instructions_test.exs` has a
`pop` case beside the `store` one, and `mix corpus.generate --check` reports no
drift (nothing this plan touches feeds the generator).

### Key Discoveries

- `test/predicator/isa_sync_test.exs:274-283` - the leading-paren rule that
  bounds the tier-6 cell's wording.
- `test/predicator/instructions_test.exs:186-192` - the `store` guard this plan
  mirrors, comment shape included.
- `lib/predicator/evaluator.ex:86-102` - the single `empty_stack` construction,
  and the `[result | _rest]` clause showing extra stack depth is already
  tolerated.
- `docs/isa.md` §2 bullet 1 - the wire format has no header, which is what makes
  "the entry point carries the mode" the only available answer.
- ADR-0003 - reserving a name is not an ISA version change; only adding the
  opcode is, and that is px-tbv.2's additive change.

## What We're NOT Doing

- **Not adding `store` or `pop` to `@opcodes`**, to §4's opcode table, to the
  evaluator, or to the corpus. Reservation is prose plus a guard; px-tbv.2 does
  the addition. `@opcode_count` stays 25.
- **Not bumping the ISA version.** `@isa_version` stays 2 and the
  `Current version: **ISA v2**.` line is untouched.
- **Not implementing `Predicator.execute/2`**, the statement grammar, or the
  parser. Those are px-tbv.1 and px-tbv.2.
- **Not renumbering sections**, and **not re-editing §1, §4's opcode table, or
  §7** - px-t2v just landed there and its edits are settled.
- **Not touching `lib/predicator/evaluator.ex`.** Statement mode is unreachable
  until the two opcodes and the entry point exist, so there is nothing to
  implement behind the spec today.
- **Not adding a corpus case or tier-6 manifest entry.** Tier 6 stays absent
  from the manifest until an opcode lands in it
  (`lib/predicator/conformance/generator.ex:39-42` already anticipates this).
- **Not writing an ADR.** ADR-0001 already specifies the statement layer and
  ADR-0003 already governs how the ISA moves; this is spec drafting under both.
- **Not correcting the corpus note on `errors/empty-stack-at-halt`** ("only
  reachable via an empty hand-built instruction list"). It stays true for
  expression mode, which is the only mode any evaluator implements today;
  revisiting it is px-tbv.2's business and moving it would move `corpus_hash`.

## Implementation Approach

Two phases, split at the gate boundary.

Phase 1 is the whole substantive change - three `docs/isa.md` edits and one
test - and it is one phase rather than three because the tier-6 cell edit and
the `pop` reservation are a single fact stated twice, and because the doc edit
is only *verified* by running the suite that parses the doc. Splitting them
would leave an intermediate gate that proves nothing.

Phase 2 is CHANGELOG plus `bd` bookkeeping, including the bead's final
acceptance clause, which is a `bd show` verification rather than a file edit.

The decisions this plan settles are recorded inline in Phase 1 so the
implementer applies wording, not judgment.

## Phase 1: Reserve `pop` and specify the statement halt contract

### Overview

Three edits to `docs/isa.md` (§4's tier table cell, §2's execution model, §6's
"Not in the ISA" list) and one new test in
`test/predicator/instructions_test.exs`.

### Decisions this phase encodes

**(a) How `pop` is reserved.** Symmetrically with `store`, in all three places:
the §6 bullet, the tier-6 cell, and the "is currently an unknown opcode" test.
**The mirror test is included.** Rationale: that test is the only *executable*
half of the reservation - the other two are prose - and its stated purpose is to
make the flip at px-tbv.2 deliberate rather than accidental. `pop` needs that
guard for exactly the same reason `store` does; a reservation with prose but no
guard is weaker than the one beside it for no reason. Rejected alternative:
prose only, on the grounds that one guard for the whole tier-6 reservation
suffices. Rejected because the two names will be added by the same bead but are
independent map entries, and a test naming only `store` would go green with
`pop` half-added.

**(b) What carries the statement mode: the entry point.** A program is a flat
instruction list with no header (§2 bullet 1), so the artifact cannot carry the
distinction and this plan does not add a header to make it. `Predicator.evaluate/2,3`
is expression mode; the future `Predicator.execute/2` is statement mode. The
spec says this in those words rather than leaving it inferable. Rejected
alternatives: (i) a program header or a leading marker instruction - it would
change the wire format for every existing artifact and break "nothing else is in
the wire format", a far larger change than the problem warrants; (ii) inferring
the mode from the instructions (a program containing `store`/`pop` is a
statement program) - it is unsound in both directions, since a single-expression
statement program contains neither, and a hand-built expression list could
contain a `pop`. The entry point is the only place the distinction can live
without cost.

**(c) The px-h66 error/halt sentence: taken verbatim.** The proposed wording in
px-z5m's note is adopted unchanged, placed immediately after the statement-mode
"result" definition. Rationale: it is already precisely scoped to what SCXML
4.9 plus IRP test 156 actually establish (stop-on-error, no rollback), and it
draws the VM/host line exactly where px-tbv.2's `{:error, e, %Context{}}` return
puts it. Rewording it risks drifting from the citation that justifies it, and
this plan verified none of that reasoning independently - the design doc is not
in this worktree. Verbatim is the honest choice. One editorial addition is made
*around* it, not to it: a sentence saying a host may additionally surface the
last expression statement's value as a convenience, which is not an ISA
guarantee. That is needed because px-tbv.2's AC mentions it and the ISA must be
explicit that it is not promising it.

**Also decided (Open Question 7 fallout):** the tier-6 cell becomes
`(none yet - reserved for \`store\` and \`pop\`)` - still leading with `(`, so
it still contributes zero opcodes to the tier-names equality check.

### Changes Required:

#### 1. The tier-6 cell

**File**: `docs/isa.md`, §4's tier table (the `| 6 | statements | ... |` row)
**Changes**: name both reserved opcodes, keeping the leading `(`.

```markdown
| 6 | statements | (none yet - reserved for `store` and `pop`) |
```

**Hard constraint**: the cell must still start with `(`. If it does not,
`tier_row_opcodes/1` (`test/predicator/isa_sync_test.exs:274-283`) scans the
backtick spans, demands `store` and `pop` in `@opcodes` at tier 6, and both the
tier-names test and `opcode_coverage_test.exs` go red. No other cell in the
table changes, and §4's *opcode* table is not touched at all.

#### 2. Section 2's result bullet, scoped to expression mode

**File**: `docs/isa.md`, §2 Execution model
**Changes**: replace the existing result bullet with a mode-scoped one. Keep it
in place in the bullet list - do not move it.

```markdown
- **In expression mode, the result is the top of the stack at halt.** An empty
  stack at halt is an `EvaluationError` with reason `"empty_stack"`; it is the
  one error that belongs to no instruction and therefore carries no source
  position. A deeper stack is not an error: the top is the result and anything
  beneath it is discarded. This rule, `empty_stack` included, is expression
  mode's alone - see "Two execution modes" below.
```

#### 3. Section 2 gains a "Two execution modes" subsection

**File**: `docs/isa.md`, §2, appended after the existing bullet list
**Changes**: a new `###` subsection. `###` under a numbered `##` is established
house style here (§4 already carries `### Tiers`, `### Opcodes`, `### Retired
opcodes`), so this adds no numbered section and renumbers nothing.

```markdown
### Two execution modes

A program is a flat instruction list with no header, so nothing in the wire
format says whether it is an expression or a statement program. **The mode is
carried by the entry point, not by the artifact.** In this implementation
`Predicator.evaluate/2,3` is expression mode and `Predicator.execute/2` - the
4.0 statement layer, §6 - is statement mode; a sibling exposes the same two
calls under whatever names it likes. The instruction set is identical in both:
no opcode is restricted to one mode, and no opcode means anything different in
the other. Only what "result" means differs.

- **Expression mode** - the result is the top of the stack at halt, and an
  empty stack at halt is `empty_stack`, as above.
- **Statement mode** - the result is **the context at halt**, not a stack
  value. The stack is scratch space between statement boundaries: a
  well-formed statement program ends each statement with a `store` or a `pop`
  and therefore halts with an **empty stack by design**. That is a normal
  halt. `empty_stack` is an expression-mode rule and is never raised in
  statement mode. A non-empty stack at halt is likewise not an error in
  statement mode; the residue is discarded, exactly as expression mode
  discards everything beneath the top.

A statement program that halts on an error has no result. Whether the
partially applied context from the statements that completed before the error
is kept or discarded is a property of the host API, not of the VM; the VM
specifies only that execution stops at the failing instruction.

A host may additionally surface the value of the program's last expression
statement alongside the context. That is a host-API convenience, not an ISA
guarantee - the statement boundary's `pop` discards it as far as the VM is
concerned.

Statement mode is specified here, ahead of the opcodes that reach it, so the
statement layer arrives as two opcodes plus an entry point rather than as a
change to this specification. Until `store` and `pop` exist (§6), no evaluator
has a statement entry point and no program is a statement program.
```

#### 4. Section 6 reserves `pop` and names statement mode as absent

**File**: `docs/isa.md`, §6 "Not in the ISA"
**Changes**: leave the `store` bullet exactly as it is; add two bullets
immediately after it.

```markdown
- `["pop"]` - the statement-boundary opcode of the same 4.0 statement layer:
  it discards an expression statement's value so the next statement begins
  from a clean stack. Not implemented and not accepted by any current
  evaluator clause. Reserved name, tier 6, beside `store`. It is **not**
  related to `jump_if_falsy_or_pop` / `jump_if_true_or_pop`, which are live
  ISA v2 opcodes that pop conditionally as part of a jump; the shared word in
  their names is the only thing the three have in common.
- A statement entry point. §2's "Two execution modes" specifies statement
  mode's halt contract, but no current evaluator exposes one, so every program
  any implementation runs today is an expression program.
```

#### 5. The `pop` reservation guard

**File**: `test/predicator/instructions_test.exs`
**Changes**: add a test immediately after "store is currently an unknown
opcode" (`:186-192`), in the same `describe` block, mirroring its comment shape.

```elixir
# "pop" is the statement-boundary opcode reserved beside "store"
# (docs/isa.md section 6) and is not in the map yet - px-tbv.2 adds it,
# at which point this expectation flips intentionally rather than by
# accident.
test "pop is currently an unknown opcode" do
  assert {:error, %EvaluationError{reason: "unknown_opcode"}} =
           Instructions.required_isa([["pop"]])
end
```

`["pop"]` takes no operand, so the instruction is a one-element list -
`required_isa/1` reads only the head and never the operands
(`lib/predicator/instructions.ex:293-306`), so this is the right shape and
matches the eventual emitted instruction.

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality`
- [x] `mix test test/predicator/isa_sync_test.exs` - all 25 §4 rows still parse,
      `isa_version/0` still equals the table maximum, and the tier-names
      equality still finds tier 6 empty
- [x] `mix test test/predicator/instructions_test.exs` - the new `pop` case
      passes alongside the `store` one
- [x] `mix corpus.generate --check` reports no drift, and
      `git diff --stat conformance/` is empty - `corpus_hash` has not moved
- [x] `git diff docs/isa.md` touches only §2, §4's tier-6 row, and §6 - no hunk
      lands in §1, §4's opcode table, or §7
- [x] Coverage stays above the 90% floor in `coveralls.json` (the change adds a
      test and no production code)

#### Manual Verification:
- [ ] The tier-6 cell still begins with `(` - read the literal line
- [ ] §2 reads coherently top to bottom: a reader arriving at the mode-scoped
      result bullet finds "Two execution modes" where the cross-reference sends
      them
- [ ] A sibling implementer reading §2 and §6 cold can answer "what does my
      `execute` return, and what happens on an error partway through" without
      opening a bead
- [ ] Section numbering is unchanged: §1 through §8, same titles

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate.

---

## Phase 2: Changelog and bead bookkeeping

### Overview

The user-facing record of the spec change, plus the `bd` steps the acceptance
criteria ask for. No Elixir moves in this phase, so there is no new gate beyond
Phase 1's green (CLAUDE.md's authority table: a change touching no Elixir code
commits on review of the diff).

### Changes Required:

#### 1. CHANGELOG

**File**: `CHANGELOG.md`, under `## [Unreleased]` → `### Documentation`
**Changes**: one entry. `### Documentation` is the right subsection rather than
`### Added` or `### Changed`: no public function, opcode, or behavior moved -
the only code change is a test.

The entry should say, from a consumer's point of view: `docs/isa.md` now
reserves `["pop"]` beside `["store"]` as a tier-6 name for the 4.0 statement
layer, and specifies that the ISA has two execution modes distinguished by the
entry point rather than by anything in the instruction list - expression mode
(`Predicator.evaluate/2,3`), whose result is the stack top at halt, and
statement mode (the future `Predicator.execute/2`), whose result is the context
at halt and which halts with an empty stack by design. `empty_stack` is
documented as an expression-mode rule. A statement program that halts on an
error has no result, and whether the partial context is kept is the host's
policy, not the VM's. **No instruction-set behavior changed** and the ISA
version stays v2 - neither reserved opcode is implemented.

Per CLAUDE.md, adding entries under `## [Unreleased]` is ordinary work and is
**not** a release request.

#### 2. Bead bookkeeping

**File**: none - `bd` only.
**Changes**:

- `bd update px-z5m --labels area:docs,area:evaluator`. The bead carries
  `area:docs` today, but this plan edits
  `test/predicator/instructions_test.exs`, which CLAUDE.md assigns to
  `area:evaluator`. The label is a prediction and this one was short by one
  file; correcting it at merge time is what the CLAUDE.md note asks for.
- `bd note px-tbv.2` recording the three decisions so its implementer does not
  re-derive them: (i) `pop` is reserved in §6 and the tier-6 cell and has a
  "currently unknown" guard in `instructions_test.exs` that flips when the
  opcode is added - both guards must flip together; (ii) the statement mode is
  carried by the **entry point**, `Predicator.execute/2`, not by anything in
  the instruction list, so `execute/2` must not sniff the program for
  `store`/`pop`; (iii) `empty_stack` is now spec'd as expression-mode-only, so
  `execute/2` must not route through a path that raises it, and the last
  expression statement's value is a host convenience the ISA does not promise.
  Also note that adding either opcode moves the tier-6 cell out of its
  leading-paren form and therefore requires both names in `@opcodes` at tier 6
  in the same change, plus corpus cases (or a documented coverage exclusion)
  for each.
- `bd note px-tbv.1` pointing at §2's "Two execution modes" as the contract its
  new entry point is being written against.
- **The bead's final acceptance clause**, "px-tbv.1 and px-tbv.2 blocked on this
  bead", is a **`bd` verification step, not a file edit**: run
  `bd show px-tbv.1` and `bd show px-tbv.2` and confirm each lists
  `→ px-z5m` under `DEPENDS ON`. Both do today (and px-z5m's own `BLOCKS`
  section lists both), so this is a confirmation, not an edit. If either edge is
  missing, restore it with `bd dep add`.
- Close-out follows CLAUDE.md's authority table: `bd close px-z5m` only once the
  branch is merged into `origin/main`, verified against the remote via
  `gh pr view`.

### Success Criteria:

#### Automated Verification:
- [x] `mix quality` still green (unchanged from Phase 1; no Elixir moved)
- [x] `bd show px-z5m` lists `area:evaluator` among its labels
- [x] `bd show px-tbv.1` shows `→ px-z5m` under `DEPENDS ON`
- [x] `bd show px-tbv.2` shows `→ px-z5m` under `DEPENDS ON`

#### Manual Verification:
- [ ] The CHANGELOG entry is written for a consumer of the library, not as a
      summary of this plan
- [ ] px-tbv.2's note is specific enough that its implementer flips both
      reservation guards and does not re-open the mode question

---

## Testing Strategy

### Unit Tests

- `test/predicator/instructions_test.exs` - one new case, "pop is currently an
  unknown opcode", asserting `required_isa([["pop"]])` returns
  `{:error, %EvaluationError{reason: "unknown_opcode"}}`. The mirror of the
  existing `store` case, and the executable half of the reservation.

### Integration Tests

None. No public API changes and no evaluator behavior changes, so there is
nothing to exercise end to end.

### Documentation-Binding Tests (existing, must stay green)

These are the tests that make a `docs/isa.md` edit checkable, and all of them
are pre-existing - this plan adds none:

- `test/predicator/isa_sync_test.exs` - §4's 25 opcode rows round-trip through
  `required_isa/1` and `tier/1`; the "Removed in" column agrees with
  `retired_in/1`; each tier row's opcode list equals `@opcodes`'s assignment for
  that tier (tier 6 must resolve to `[]`); `isa_version/0` equals the table
  maximum; the literal `Current version: **ISA v2**.` is present.
- `test/predicator/conformance/opcode_coverage_test.exs` - every key of
  `opcodes/0` has a case. Guards against a reserved name being smuggled into the
  map.
- `test/predicator/conformance/corpus_freshness_test.exs` and
  `mix corpus.generate --check` - byte identity of the corpus, which proves this
  plan moved nothing downstream.

### Manual Testing Steps

1. Read the tier-6 row literally and confirm the cell's first character is `(`.
2. Read §2 end to end and confirm the cross-reference from the result bullet
   lands on "Two execution modes".
3. Read §6 and confirm the `store` bullet is byte-unchanged and the two new
   bullets follow it.
4. `git diff docs/isa.md` and confirm no hunk falls inside §1, §4's opcode
   table, or §7.

## ISA Impact

Included for completeness because the bead touches `docs/isa.md`; the answer to
all three of ADR-0003's questions is "nothing is owed".

1. **Version** - no bump. No opcode is added, removed, renamed, or altered.
   Reserving a name is not an ISA change: `store` has been reserved since
   px-35i.2 with no version movement, and `pop` gets the same treatment.
   `@isa_version` stays **2** and §1's `Current version: **ISA v2**.` line is
   untouched. Scoping `empty_stack` to expression mode is not a semantics change
   under an existing name either - no evaluator has a statement entry point, so
   no program's behavior changes.
2. **Stamp** - no opcode subsection, no §4 table row, no corpus tier assignment.
   Tier 6 remains empty in `conformance/manifest.json` (it never appears, since
   the manifest lists tiers that have opcodes). px-tbv.2 owes all three when it
   adds `store` and `pop` at their entry version.
3. **Migration** - none. Every instruction list valid before this change is
   valid after it and produces the same answer, because the only mode any
   implementation exposes today is the expression mode whose rules are unchanged.

## References

- Beads issue: **px-z5m**; blocks **px-tbv.1**, **px-tbv.2**
- Research: `docs/research/260807-px-t2v-px-z5m-isa-retirement-and-pop.md`
  (areas 5 and 6; Open Questions 5, 6, 7 decided here)
- Sibling plan on the same file:
  `docs/plans/260807-px-t2v-isa-retirement-mechanics.md`
- ADRs: `docs/adr/0001-keep-the-stack-vm-revise-the-instruction-set.md` (the
  statement layer and `["store", n]`),
  `docs/adr/0003-the-elixir-implementation-leads-the-isa.md` (how the ISA moves)
- px-h66's proposed wording and its SCXML 1.0 §4.9 / IRP test 156 reasoning:
  `bd show px-z5m` NOTES. Its design doc,
  `docs/design/260807-px-h66-scxml-error-semantics.md`, is not present in this
  worktree.
- `docs/isa.md` §2 (execution model), §4's tier table, §6 (Not in the ISA)
- `test/predicator/isa_sync_test.exs:274-283` - the leading-paren rule
- `test/predicator/isa_sync_test.exs:122-149` - the tier-names set equality
- `test/predicator/instructions_test.exs:186-192` - the `store` guard this plan
  mirrors
- `lib/predicator/instructions.ex:56-82` - `@opcodes`, which neither reserved
  name enters
- `lib/predicator/instructions.ex:293-306` - `opcode_version/2`, why
  `[["pop"]]` is the right test shape
- `lib/predicator/evaluator.ex:86-102` - `run_prepared/1`, the sole
  `empty_stack` construction
- `lib/predicator/conformance/generator.ex:39-42` - tier 6 named but absent from
  the manifest until an opcode lands in it

## Deferred Manual Verification

- [x] The tier-6 cell still begins with `(` - read the literal line
- [x] §2 reads coherently top to bottom: a reader arriving at the mode-scoped
      result bullet finds "Two execution modes" where the cross-reference sends
      them
- [x] A sibling implementer reading §2 and §6 cold can answer "what does my
      `execute` return, and what happens on an error partway through" without
      opening a bead
- [x] Section numbering is unchanged: §1 through §8, same titles

Phase 2:

- [x] The CHANGELOG entry is written for a consumer of the library, not as a
      summary of this plan
- [x] px-tbv.2's note is specific enough that its implementer flips both
      reservation guards and does not re-open the mode question
