# Registry entry uniqueness on (case_id, surface) Implementation Plan

## Overview

Make the uniqueness that `conformance/RATCHET.md` already implies explicit and
enforced: one new sentence under rule 3 stating that `entries` holds at most one
entry per `(case_id, surface)` pair, one new binding test asserting it over
`conformance/examples/registry.example.json`, its sabotage verification, and a
`CHANGELOG.md` entry. Bead: px-wy8.

The bead was filed as "five duplicated entries, delete them". The direction stage
settled that this is a **false positive** and that nothing is deleted; see
`docs/research/260814-px-wy8-registry-entry-uniqueness.md`, which is the accepted
decision record and settled input to this plan. What survives the false positive
is the second half of the bead: today a genuine duplicate would be caught by
nothing.

## Current State Analysis

- `conformance/examples/registry.example.json` carries 68 entries. Five
  `case_id`s appear twice, once with `"surface":"compiler"` and once with
  `"surface":"evaluator"`. All 68 `(case_id, surface)` pairs are distinct. The
  file is correct as it stands.
- `conformance/RATCHET.md` keys entry identity on the pair in three places -
  the "One file, not one per surface" argument, rule 1's membership check, and
  `check/3`'s `fail unless (e.case_id, e.surface) in surface_case_set(...)` at
  `conformance/RATCHET.md:251` - and rule 3 (`conformance/RATCHET.md:173-196`)
  grows the file by a set union (`step 6: New entries = existing union
  candidates`), which is idempotent. Uniqueness is therefore implied everywhere
  and stated nowhere.
- `test/predicator/conformance/ratchet_registry_test.exs` has five tests in five
  `describe` blocks: schema validation (`:33`), rule 1 (`:43`), the pin (`:82`),
  rule 2 canonical encoding (`:99`), and R5 completeness (`:113`). Each carries
  a one-line `# sabotage: ... -> red` comment directly above the `test` line.
- The file is already listed in `.claude/wurk.json`'s `gate.sabotage.test_roots`
  - **verified in this checkout**, sixth of the ten paths. No manifest edit is
  needed.
- `docs/research/260808-px-9ab-sabotage-notes.md` is where a new binding test's
  sabotage pass is recorded, in an "Additions to the class" bullet - except that
  this is not a new *file* in the class, so it is an addendum to an existing
  member rather than a class extension. See "Implementation Approach".

### Empirical verification performed during planning

The decision record's central claim was re-checked rather than assumed. A
byte-identical copy of
`{"case_id":"comparison/gt-int-true","surface":"compiler","tier":1},` was
inserted directly beneath the original in `registry.example.json` and
`mix test test/predicator/conformance/ratchet_registry_test.exs` was run:

```text
5 tests, 0 failures
```

The file was restored with `git checkout --` and the tree confirmed clean. This
establishes two things the plan depends on:

1. A genuine duplicate is invisible to the entire current suite, so the new
   assertion is not redundant with anything.
2. The sabotage **isolates**: `reencode/1`
   (`test/predicator/conformance/ratchet_registry_test.exs:156-173`) re-emits
   `entries` in parse order without sorting, so the canonical-encoding test
   re-encodes a duplicated line to itself and stays green. Exactly one test will
   go red under the mutation, which is what a sabotage note is supposed to
   demonstrate.

## Desired End State

- `conformance/RATCHET.md` rule 3 states the uniqueness invariant normatively
  and attributes it to step 6's set union.
- `test/predicator/conformance/ratchet_registry_test.exs` has a sixth `describe`
  block with one test asserting no repeated `(case_id, surface)` pair, an
  anti-vacuity guard modelled on `:47`, and a failure message naming the
  offending pairs.
- That test carries a `# sabotage:` note, and the mutation behind it has actually
  been run and reverted, with the result recorded in
  `docs/research/260808-px-9ab-sabotage-notes.md`.
- `CHANGELOG.md` carries an `## [Unreleased]` entry for the RATCHET.md change.
- `conformance/examples/registry.example.json`, `conformance/schema/registry.json`,
  the corpus, `manifest.json`'s `corpus_hash`, and `docs/isa.md` are all
  unchanged.

Verify by: full `mix quality` green; `git diff --name-only` naming exactly
`conformance/RATCHET.md`, `test/predicator/conformance/ratchet_registry_test.exs`,
`docs/research/260808-px-9ab-sabotage-notes.md`, `CHANGELOG.md`, and this plan.

### Key Discoveries:

- `conformance/RATCHET.md:251` - `check/3` already keys on the pair; the plan
  invents no identity key.
- `conformance/RATCHET.md:188-196` - rule 3 steps 4 and 6 are set-valued, which
  is why a compliant sibling writer cannot produce a duplicate and why this is a
  clarification of the exported contract rather than a new constraint on it.
- `test/predicator/conformance/ratchet_registry_test.exs:47` - the anti-vacuity
  guard to model (`assert entries != []` with a message saying the test below
  would otherwise pass vacuously).
- `test/predicator/conformance/ratchet_registry_test.exs:156-173` - `reencode/1`
  preserves parse order; this is the mechanism that makes the sabotage isolate.
- `.claude/wurk.json` `gate.sabotage.test_roots` - already lists the test file.
- ADR-0003 - this repo is the ISA reference implementation and owns the exported
  specification; siblings adopt on a boundary of their own choosing, so no
  outward notification is owed for a clarification that cannot invalidate an
  existing compliant registry.
- `docs/research/260814-px-wy8-registry-entry-uniqueness.md` - the accepted
  decision record. Its conclusions are settled input, not open items.

## What We're NOT Doing

- **Not deleting anything from `registry.example.json`.** The five reported
  duplicates are one case on two surfaces. A deletion would drop a verified
  claim, and dropping an evaluator half would fail the R5 completeness test.
- **Not adding `uniqueItems` to `conformance/schema/registry.json`.** Whole-object
  identity is a weaker key than the pair (it would admit two entries agreeing on
  `(case_id, surface)` and disagreeing on `tier`), and the test-side
  `SchemaValidator` in `test/test_helper.exs` implements no such keyword, so it
  would be decorative. Settled by the decision record; not re-litigated here.
- **Not moving the ISA.** No opcode is added, removed, renamed, or altered, so
  there is no version bump, no `docs/isa.md` entry, no `mix corpus.generate`, and
  no `corpus_hash` change. This is stated explicitly so it reaches the commit
  message and the PR body. The `## ISA Impact` section is omitted for exactly
  this reason, per `.claude/wurk/plan.md`.
- **Not adding a new numbered R-check to RATCHET.md.** A hand-edited duplicate is
  the same class of defect rule 3 already exists for.
- **Not binding rule 2's sort order.** `reencode/1` asserts canonical *encoding*,
  not canonical *ordering*; RATCHET.md rule 2's three sort clauses are asserted
  by nothing today. That is a real gap and it gets its own bead
  (`area:conformance`), because it is a second binding test with its own sabotage
  and its own RATCHET.md reading, and because a strict-ascending sortedness check
  would subsume this uniqueness assertion - which is the argument for landing
  uniqueness first with a clean sabotage. Filing that bead is a task in Phase 1;
  the work is out of scope.
- **Not writing a `registry.example.json` generator, nor correcting the test
  moduledoc's "is generated from" claim.** See "Open questions carried forward".
- **Not notifying siblings.** ADR-0003 governs; the clarification cannot
  invalidate a registry written per rule 3. If that call is ever revisited, the
  mirrored-bead protocol in `CLAUDE.md` is the mechanism, not an ad-hoc note.
- **Not running a typography pass.** `conformance/RATCHET.md` and `CHANGELOG.md`
  are hyphen-only ASCII (verified: zero em dashes in RATCHET.md); the new prose
  matches, and no surrounding text is reflowed or converted.

## Implementation Approach

This is a **one-phase change**, deliberately. The four edits are not
independently committable in any meaningful sense:

- The test without the RATCHET.md sentence is a binding test in
  `gate.sabotage.test_roots` asserting a rule the normative document does not
  state - precisely the hazard px-9ab's sabotage-note argument exists to prevent,
  in the opposite direction (this repo enforcing something larger than what the
  sibling reads).
- The RATCHET.md sentence without the test is a normative claim bound by nothing,
  in a file whose whole purpose is to be enforced.
- The sabotage note and its recorded pass are part of the test's own definition
  of done under `CLAUDE.md`'s Conventions, not a follow-up.
- The CHANGELOG entry describes the RATCHET.md change and lands with it.

Splitting these would produce intermediate commits that are green but incoherent,
which is worse than one well-formed phase. Per `/wurk:plan`'s own sizing rule, a
single phase is the correct answer for work this size.

The sabotage note is an **addendum to an existing class member**, not a class
extension: `test/predicator/conformance/ratchet_registry_test.exs` has been in
the binding class since px-9ab and in `gate.sabotage.test_roots` since px-lxs.
The "`test_roots` is a second copy of this document's class list" rule in
`docs/research/260808-px-9ab-sabotage-notes.md` therefore does not fire - there
is no new file to add to either list. The bullet added to that document records
a fresh sabotage pass on an already-listed file, and says so.

---

## Phase 1: Assert and document (case_id, surface) uniqueness

### Overview

Add the normative sentence, the binding test, the recorded sabotage pass, and the
changelog entry, as one commit.

### Changes Required:

#### 1. The normative sentence

**File**: `conformance/RATCHET.md`
**Changes**: In the "Rule 3: grown only by verify-then-add" section
(`:173-196`), after the numbered step list, add one short paragraph. Match the
file's existing voice and its ASCII-hyphen typography; do not reflow neighboring
paragraphs.

```text
It follows that `entries` contains at most one entry per `(case_id, surface)`
pair: step 6 is a set union, and a union cannot produce a second copy of a pair
it already holds. A registry carrying the same pair twice was not written by this
step, and a checker is entitled to reject it.
```

#### 2. The binding test

**File**: `test/predicator/conformance/ratchet_registry_test.exs`
**Changes**: Add a sixth `describe` block. Place it after the rule 1 block
(`:41-78`), which is the other pair-keyed test, or after the R5 block; either
reads fine, and no existing test moves. Follow the file's conventions exactly:
one `# sabotage:` line directly above `test`, `read_example/0` for the fixture,
an anti-vacuity guard modelled on `:47`, and a failure message that names the
offending pairs rather than only asserting a count.

```elixir
describe "RATCHET.md rule 3: entries are unique on (case_id, surface)" do
  # sabotage: registry.example.json duplicates the comparison/gt-int-true compiler entry line -> red
  test "no (case_id, surface) pair appears in entries more than once" do
    entries = read_example()["entries"]

    assert entries != [],
           "conformance/examples/registry.example.json has no entries - " <>
             "the test below would pass vacuously"

    duplicates =
      entries
      |> Enum.frequencies_by(&{&1["case_id"], &1["surface"]})
      |> Enum.filter(fn {_pair, count} -> count > 1 end)
      |> Enum.map(fn {pair, _count} -> pair end)
      |> Enum.sort()

    assert duplicates == [],
           "the registry carries repeated (case_id, surface) pairs: " <>
             inspect(duplicates) <>
             " - RATCHET.md rule 3 grows entries by a set union, so a repeated " <>
             "pair means the file was hand-edited or written by a step that is " <>
             "not verify-then-add"
  end
end
```

**The moduledoc's own count moves with it.** `:3-5` currently reads "four
tests, each mirroring one of the spec's rules, plus the R5 completeness check";
after this phase there are five rule-mirroring tests plus R5. Correct that
sentence in the same edit. This is the same drift the RATCHET.md sentence
exists to close, one level down, and nothing gates the accuracy of moduledoc
prose - so it is caught now or not at all.

Note the shape of the guard: `case_id` alone is **not** the key, and a reviewer
who reads only the test name should not be able to mistake it for one. The five
`case_id`s that appear twice in the shipped file are legitimate and this test
must stay green on them - if it does not, the key was written wrong.

#### 3. The recorded sabotage pass

**File**: `docs/research/260808-px-9ab-sabotage-notes.md`
**Changes**: Add a dated bullet to "Additions to the class", matching the shape
of the existing `px-ir1` / `px-qq6` / `px-kbe` / `px-3so.4` entries: what was
added, why it is in the binding class, the mutation run, what went red, and the
confirmation that it was reverted. State plainly that the file count does **not**
move (still ten) because the file was already a class member and already in
`test_roots`, and that the isolation to a single test depends on `reencode/1` not
sorting - so if the sortedness follow-on ever lands, this pass is re-run rather
than carried over.

The mutation: insert a byte-identical copy of
`{"case_id":"comparison/gt-int-true","surface":"compiler","tier":1},` directly
beneath the original in `conformance/examples/registry.example.json`, run the
suite, confirm exactly the new test goes red naming the pair, revert with
`git checkout -- conformance/examples/registry.example.json`, confirm green and
`git status --porcelain` clean.

#### 4. The changelog entry

**File**: `CHANGELOG.md`
**Changes**: One entry under `## [Unreleased]`, in a `### Changed` subsection
(add the subsection if `## [Unreleased]` does not yet carry one; today it has
only `### Added`).

**The call, and the argument.** This **does** get a CHANGELOG entry. The test is
not user-facing and would not earn one on its own, but `conformance/RATCHET.md`
is an exported specification that sibling implementations read and write against
(ADR-0003), and its normative content is exactly the kind of thing a sibling
author needs to know changed. The counter-argument - that the sentence only
states what rule 3's set union already implied, so nothing actually changed for
anyone - is real but does not win: RATCHET.md's own arrival was announced in
`CHANGELOG.md` (`:503`), which sets the precedent that its normative content is
release-visible, and "we now enforce this and you should too" is information a
sibling cannot get from a diff it does not receive. `### Changed` rather than
`### Added` because the document exists and its content moved; no migration note,
because no compliant registry becomes invalid.

Suggested wording, in the file's house style (bold lead sentence, ASCII hyphens):

```markdown
### Changed

- **`conformance/RATCHET.md` now states registry entry uniqueness
  normatively.** Rule 3 already grew `entries` by a set union, and rule 1 already
  keyed entry identity on the `(case_id, surface)` pair, so uniqueness on that
  pair was implied throughout - it is now written down, and
  `test/predicator/conformance/ratchet_registry_test.exs` binds it. No registry
  written by rule 3's verify-then-add step can violate it, so a compliant sibling
  registry needs no change; a registry carrying a repeated pair was hand-edited.
  The corpus, `corpus_hash`, the schema, and the ISA are unaffected.
```

#### 5. The follow-on bead

**Not a file change.** File the sortedness bead described in "What We're NOT
Doing" with `/wurk:issue` (or `bd create`): type `bug` or `chore`, label
`area:conformance`, describing that RATCHET.md rule 2's three sort clauses are
asserted by nothing because `reencode/1` preserves parse order, and that
shuffling `registry.example.json`'s entry lines leaves the whole suite green.
Cross-reference px-wy8 and this plan. Do this in the same session so the finding
is not lost; the bead id does not need to appear in the commit.

### Success Criteria:

#### Automated Verification:

- [x] Full `mix quality` is green (format, compile, credo --strict, dialyzer,
      deps audit, suite with coverage).
- [x] `mix test test/predicator/conformance/ratchet_registry_test.exs` reports
      6 tests, 0 failures.
- [x] With the sabotage mutation applied, the same command reports exactly
      1 failure, and it is the new test.
- [x] After reverting the mutation, `git status --porcelain` shows no change to
      `conformance/examples/registry.example.json`.
- [x] `git diff --name-only` against `origin/main` names only
      `conformance/RATCHET.md`,
      `test/predicator/conformance/ratchet_registry_test.exs`,
      `docs/research/260808-px-9ab-sabotage-notes.md`, `CHANGELOG.md`, and
      `docs/plans/260814-px-wy8-registry-entry-uniqueness.md`. In particular
      `conformance/`'s corpus, manifest, schema, and example files are untouched.
- [x] `ruby ~/.claude/skills/wurk:kit/scripts/gate.rb --profile loop` reports no
      `sabotage_note_missing` warning for the new test (the note is present).
      Note this is a report, never a gate, and a present note is not evidence the
      mutation was run - that judgment is the manual item below.

#### Manual Verification:

- [ ] The sabotage mutation was actually run, went red for the right reason (the
      failure message names `{"comparison/gt-int-true", "compiler"}`), and was
      reverted - not merely described.
- [ ] The new test stays green on the five legitimate `case_id` collisions,
      confirming the key is the pair and not the id.
- [ ] The RATCHET.md sentence reads as part of rule 3's argument rather than as a
      bolted-on clause, and introduces no typography the file does not already
      use.
- [ ] The sabotage-notes bullet matches the shape of its neighbors and correctly
      says the class is still ten files.
- [ ] The test file's moduledoc no longer says "four tests" - its count and
      description include the new rule 3 test.
- [ ] The commit message and PR body state that this does not move the ISA: no
      version bump, no `docs/isa.md` entry, no corpus regeneration, no
      `corpus_hash` change.
- [ ] No regressions in related features - the rest of `conformance/` is
      untouched.

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run full `mix quality` as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before committing. In
looped (`--loop`) execution the Automated Verification gates advancement via
`/wurk:commit --auto`, and the Manual Verification items - the sabotage pass
above all - are surfaced once at the end. **The sabotage item is not
auto-dischargeable**: an unattended run must surface it as outstanding rather
than treat the presence of the `# sabotage:` comment as the verification.

---

## Testing Strategy

### Unit Tests:

- One new test in `test/predicator/conformance/ratchet_registry_test.exs`,
  pattern-matching the file's existing style: read the example, guard against
  vacuity, compute the offending set, assert it empty with a naming message.
- Key edge cases: the five legitimate one-id/two-surface pairs must not trip it
  (the whole point of the pair key); an empty `entries` array must fail the guard
  rather than pass the uniqueness check vacuously; a pair repeated with differing
  `tier` values must still be reported as a duplicate, which is why the frequency
  key is the pair and not the whole entry object.
- No new `lib/` code, so the 90% coverage floor in `coveralls.json` is unaffected
  in either direction; the full gate's coverage stage confirms it.

### Manual Testing Steps:

1. Insert a byte-identical copy of the `comparison/gt-int-true` compiler entry
   line into `conformance/examples/registry.example.json`.
2. Run `mix test test/predicator/conformance/ratchet_registry_test.exs`. Expect
   exactly one failure, the new test, naming
   `{"comparison/gt-int-true", "compiler"}`.
3. `git checkout -- conformance/examples/registry.example.json`; re-run; expect
   6 tests, 0 failures, and a clean `git status --porcelain`.
4. Read the amended rule 3 section of `conformance/RATCHET.md` top to bottom and
   confirm the new sentence follows from the numbered steps above it.

## Open questions carried forward

Both are inherited from the decision record's own "Open questions" section. Both
are deliberately **out of scope** for this bead - neither blocks any step above,
and each is recorded here so it survives to whoever reads this plan.

1. **`registry.example.json`'s provenance is described two ways and no generator
   exists.** The test moduledoc
   (`test/predicator/conformance/ratchet_registry_test.exs:8-10`) says the
   example "is generated from this checkout's own
   `conformance/corpus/tier-1.json`, not hand-typed"; px-wy8's description says it
   "is hand-maintained rather than generated". Nothing in `lib/`, no `mix
   corpus.*` task, and no other test writes the path - the only non-documentation
   reference to it in the tree is the test that reads it. "Generated" appears to
   describe how the file was originally derived, not a step anyone can re-run.
   This does not change any decision in this plan (if anything it is the reason a
   uniqueness assertion is worth having), but somebody should decide whether to
   write the generator or correct the moduledoc. **Not resolved here, and not
   filed as a bead by the decision record** - the implementer should raise it,
   and filing it is the low-cost option.
2. **Whether the RATCHET.md sentence needs siblings told.** The call taken above
   is no: ADR-0003 has siblings adopting on a boundary of their own choosing, and
   this clarification cannot invalidate a registry that followed rule 3. Recorded
   as an open question rather than a closed one because it is a judgment about
   another repo's expectations that this repo cannot verify alone. If it is ever
   revisited, the mechanism is the mirrored-bead protocol in `CLAUDE.md`.

## References

- Source document: `docs/research/260814-px-wy8-registry-entry-uniqueness.md`
- Sabotage-note practice: `docs/research/260808-px-9ab-sabotage-notes.md`
- Related ADRs: `docs/adr/0003-the-elixir-implementation-leads-the-isa.md` (this
  repo is the ISA reference implementation and owns the exported specification),
  `docs/adr/0005-worktree-parallelism-and-the-area-label-algebra.md` (area
  labels: this bead is `area:conformance` + `area:docs`, and touches no
  `area:build` file),
  `docs/adr/0006-irreversibility-places-the-human-gates.md` (where the human
  gates sit)
- Specification under change: `conformance/RATCHET.md:173-196` (rule 3),
  `conformance/RATCHET.md:251` (`check/3`'s pair key)
- Similar implementation: `test/predicator/conformance/ratchet_registry_test.exs:41-78`
  (the other pair-keyed test) and `:47` (the anti-vacuity guard)
- Bead: `px-wy8`

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] The sabotage mutation was actually run, went red for the right reason (the
      failure message names `{"comparison/gt-int-true", "compiler"}`), and was
      reverted - not merely described.
- [ ] The new test stays green on the five legitimate `case_id` collisions,
      confirming the key is the pair and not the id.
- [ ] The RATCHET.md sentence reads as part of rule 3's argument rather than as a
      bolted-on clause, and introduces no typography the file does not already
      use.
- [ ] The sabotage-notes bullet matches the shape of its neighbors and correctly
      says the class is still ten files.
- [ ] The test file's moduledoc no longer says "four tests" - its count and
      description include the new rule 3 test.
- [ ] The commit message and PR body state that this does not move the ISA: no
      version bump, no `docs/isa.md` entry, no corpus regeneration, no
      `corpus_hash` change.
- [ ] No regressions in related features - the rest of `conformance/` is
      untouched.

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run full `mix quality` as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before committing. In
looped (`--loop`) execution the Automated Verification gates advancement via
`/wurk:commit --auto`, and the Manual Verification items - the sabotage pass
above all - are surfaced once at the end. **The sabotage item is not
auto-dischargeable**: an unattended run must surface it as outstanding rather
than treat the presence of the `# sabotage:` comment as the verification.

---
