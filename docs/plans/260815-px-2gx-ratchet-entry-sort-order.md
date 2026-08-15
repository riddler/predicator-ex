# RATCHET.md rule 2 entry sort order Implementation Plan

## Overview

`conformance/RATCHET.md`'s "Grouping and ordering" section states the three sort
clauses that rule 2 depends on and names in its own heading - `surface`
ascending, then `tier` ascending, then `case_id` ascending, all by codepoint
(`conformance/RATCHET.md:61-84`, with rule 2 itself at `:86-127`). Nothing in
the suite enforces them. This plan adds one binding test that does, runs its sabotage
verification, and records the pass. Bead: px-2gx.

The finding is px-wy8's, recorded as a deliberate out-of-scope follow-on in
`docs/research/260814-px-wy8-registry-entry-uniqueness.md:202-219`. px-wy8 has
landed (bead closed; its uniqueness `describe` block is at
`test/predicator/conformance/ratchet_registry_test.exs:82-105` in this
checkout), so the ordering dependency the bead names is satisfied.

No `lib/` change, no corpus regeneration, no schema change, no ISA movement,
and no change to `conformance/examples/registry.example.json` itself.

## Current State Analysis

- **The gap is real and was verified in this checkout.** The rule 2 test
  (`test/predicator/conformance/ratchet_registry_test.exs:125-138`) byte-
  compares the file against `reencode/1`
  (`test/predicator/conformance/ratchet_registry_test.exs:185-202`).
  `reencode/1` maps over `entries` in **parse order** - `Enum.map(list,
  &ConformanceJSON.encode_canonical/1)` at line 193 - and never sorts. Shuffling
  two entry lines therefore re-encodes to the shuffled bytes and the test stays
  green. The test's name and the moduledoc both claim to bind "the file is
  exactly the canonical encoding"; they bind the *encoding*, not the *ordering*.
- **The other five tests are green under a reorder, by construction.** Schema
  validation (`:33`) has no ordering keyword; rule 1 (`:43`) iterates entries
  independently; rule 3 uniqueness (`:82`) uses `Enum.frequencies_by/2`; the pin
  (`:107`) reads two scalars; R5 (`:140`) builds a `MapSet`. A reorder is
  invisible to every one of them.
- **The example is currently sorted.** Verified mechanically over the shipped
  file: 68 entries, the `{surface, tier, case_id}` key list equals its own sort,
  and `claims` is sorted by surface. The new assertion is green on the tree as
  it stands - it is a guard against future drift, not a fix for present drift.
- **The example exercises two of the three clauses and only two.** All 68
  entries are `tier: 1`, and two surfaces are present (`compiler`, 5 entries;
  `evaluator`, 63). The surface clause and the `case_id` clause are exercisable
  by reordering lines; the tier clause is not, because a one-tier list cannot be
  reordered on tier. See "What We're NOT Doing".
- **The file is already in `gate.sabotage.test_roots`** - `.claude/wurk.json`,
  sixth of eleven paths, verified in this checkout. No manifest edit is needed,
  and CLAUDE.md's binding-test obligation applies in full to the new assertion.
- **The moduledoc's test count is already stale.** `test/predicator/conformance/
  ratchet_registry_test.exs:3` says "five tests"; there are six after px-wy8.
  This plan takes it to the true post-change count rather than leaving a second
  wrong number behind.

## Desired End State

`test/predicator/conformance/ratchet_registry_test.exs` carries a seventh test,
in its own `describe` block, asserting that `example["entries"]` is sorted
ascending on `{surface, tier, case_id}` per RATCHET.md rule 2, with an
anti-vacuity guard and a failure message naming the first out-of-order pair. The
test carries a one-line `# sabotage: ... -> red` note. The sabotage pass - two
reorder mutations plus a re-run of px-wy8's duplicate mutation - is recorded as
a dated addendum in `docs/research/260808-px-9ab-sabotage-notes.md`.

Verify with: `mix test test/predicator/conformance/ratchet_registry_test.exs`
reports 7 tests, 0 failures; `git status --porcelain` shows changes only to the
test file and the sabotage-notes document; full `mix quality` is green.

### Key Discoveries:

- `test/predicator/conformance/ratchet_registry_test.exs:193` - `reencode/1`
  preserves parse order. This single line is why rule 2's sort clauses are
  unbound, and it is also what keeps px-wy8's sabotage isolation true.
- `conformance/RATCHET.md:66-74` - the ordering is already stated normatively,
  in the "Grouping and ordering" section, with the surface-outermost rationale
  at `:76-84`. **No RATCHET.md edit is owed.** This is the point on which this
  bead differs from px-wy8, which had to add a sentence because the doc did not
  state what its test asserted (`docs/research/260814-px-wy8-registry-entry-
  uniqueness.md:129-138`). Here the doc says it and the suite does not check it;
  only the suite side moves.
- `docs/research/260808-px-9ab-sabotage-notes.md:317-345` - px-wy8's addendum
  explicitly says its "exactly one test goes red" claim goes stale if this bead
  makes `reencode/1` or a companion assertion enforce order, and must be re-run
  rather than carried forward. This plan honors that literally: the re-run is a
  step, not an assumption.
- `docs/research/260808-px-9ab-sabotage-notes.md:131-156` - the stale-beam
  hazard. It applies to mutations of Elixir source only; every mutation here is
  to a JSON data file read at runtime, so no `MIX_ENV=test mix compile --force`
  is needed. The plan states this so the omission is a decision, not a lapse.
- `test/predicator/conformance/ratchet_registry_test.exs:49-51` - the
  anti-vacuity guard pattern the neighboring tests use, and the model for this
  one.
- ADR-0003 - this repo is the ISA reference implementation and the corpus is the
  exported specification. Nothing exported moves here: the assertion enforces a
  contract already published in RATCHET.md, so no sibling is newly constrained.
- ADR-0006 - the human gates. This plan writes no bead close, no push, no
  release.

## What We're NOT Doing

- **Not modifying `conformance/examples/registry.example.json`.** It is already
  correctly sorted. The plan's mutations are sabotage mutations - applied,
  observed, reverted - and the file is byte-identical at every commit.
- **Not changing `reencode/1` to sort.** Sorting inside `reencode/1` would fold
  an ordering defect into the encoding test's message ("an editor or a
  pretty-printer likely reflowed it"), which is the wrong diagnosis for a
  shuffled line, and would redden two tests for one defect. A separate
  `describe` block gives one defect one named failure - the reason px-wy8's
  research gave for splitting this bead out at all
  (`docs/research/260814-px-wy8-registry-entry-uniqueness.md:210-214`).
- **Not writing the sortedness check strictly.** A strict-ascending check would
  subsume px-wy8's uniqueness assertion, so a duplicated line would redden two
  tests and px-wy8's recorded isolation would be not merely stale but false. The
  non-strict form (`keys == Enum.sort(keys)`) leaves a duplicate adjacent pair
  sorted, so uniqueness keeps its own clean, single-test sabotage and the two
  defects stay separately named. px-wy8's research posed this exact choice as
  the follow-on's to make
  (`docs/research/260814-px-wy8-registry-entry-uniqueness.md:215-219`); this is
  the decision, and the Phase 1 re-run mutation is its evidence.
- **Not asserting `claims` is sorted by surface**, though RATCHET.md:74 states
  it. The example carries exactly one claim, so the assertion would be trivially
  true and unsabotageable: the only mutation that could redden it - adding a
  second claim - would first have to satisfy R5 completeness for that claim, a
  much larger change. A binding test that cannot be reddened by any plausible
  mutation is a finding rather than a test
  (`docs/research/260808-px-9ab-sabotage-notes.md:92-93`), and the bead's
  acceptance criteria name `entries` only. Recorded here so the omission is
  visible to whoever revisits it if the example ever gains a second claim.
- **Not exercising rule 2's tier clause.** Every entry in the example is tier 1,
  so no reordering of the file can produce a tier-order violation, and the
  clause is asserted-but-unexercised. The alternative - hand-adding a tier-2
  entry so the clause becomes sabotageable - is rejected: rule 3's first line is
  "Nothing hand-edits the registry", and a fabricated entry is a claim that no
  run observed, which is precisely the property the ratchet exists to protect.
  The assertion still enforces the clause for any future example that gains a
  second tier. The Phase 2 note records this limitation explicitly rather than
  letting a reader infer three-clause coverage from a two-clause pass.
- **No `CHANGELOG.md` entry.** Nothing user-facing changes: no public function,
  no published document, no exported artifact. RATCHET.md and the example are
  untouched, so no sibling's `corpus_hash` pin and no sibling's registry is
  affected. (px-wy8 did earn one because it edited RATCHET.md.)
- **No `.claude/wurk.json` edit.** The file is already in
  `gate.sabotage.test_roots`; the class list gains no new file, so neither copy
  of it moves and CLAUDE.md's "the two lists move together" rule has nothing to
  do here.
- **No generator for `registry.example.json`.** px-wy8's research left an open
  question about the file's provenance being described two ways
  (`docs/research/260814-px-wy8-registry-entry-uniqueness.md:222-234`). It is
  out of scope here and stays a separate question; this plan does not touch the
  moduledoc sentence that raises it.

## Implementation Approach

One assertion, one sabotage pass, one note - split into two commits because the
note can only be written truthfully after the pass has been run, and because the
repo already commits verification records separately (`0631deb "Records the
px-5c5 manual verification"`).

The assertion compares the entries' sort key list against `Enum.sort/1` of
itself. Elixir's term ordering compares binaries byte-wise, which is codepoint
order for the ASCII case ids and surfaces in play, and compares same-size tuples
element-wise - so a single `Enum.sort/1` on `{surface, tier, case_id}` tuples is
exactly RATCHET.md's three clauses in order, with no hand-rolled comparator to
get wrong. The failure message locates the first adjacent inversion, so a
shuffled file names the two lines rather than dumping 68.

Both phases are independently committable and leave a green full gate. Phase 1
touches only Elixir test source; Phase 2 touches only a research document.

## Phase 1: Bind rule 2's sort order

### Overview

Add the seventh `describe`/`test` to the ratchet registry binding test, with its
anti-vacuity guards and its `# sabotage:` note, refresh the stale moduledoc test
count, and run the sabotage mutations before committing.

### Changes Required:

#### 1. The binding test

**File**: `test/predicator/conformance/ratchet_registry_test.exs`

**Changes**: Add one `describe` block containing one test. Place it directly
after the existing rule 2 canonical-encoding block (which ends at line 138) so
the two rule 2 halves - encoding and ordering - read together. Follow the file's
existing shape: `read_example()`, an anti-vacuity guard, then the property.

```elixir
describe "RATCHET.md rule 2: entries are sorted by (surface, tier, case_id)" do
  # sabotage: registry.example.json swaps two adjacent evaluator entry lines -> red
  test "the entries array is in ascending (surface, tier, case_id) order" do
    entries = read_example()["entries"]

    assert entries != [],
           "conformance/examples/registry.example.json has no entries - " <>
             "the test below would pass vacuously"

    keys = Enum.map(entries, &{&1["surface"], &1["tier"], &1["case_id"]})

    assert keys |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() > 1,
           "the registry's entries all carry one surface - the first of " <>
             "RATCHET.md rule 2's three sort clauses would be unexercised " <>
             "by the assertion below"

    inversion =
      keys
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.find(fn [a, b] -> a > b end)

    assert inversion == nil,
           "conformance/examples/registry.example.json's entries are not in " <>
             "the order RATCHET.md rule 2 specifies (surface ascending, then " <>
             "tier ascending, then case_id ascending): " <>
             inspect(inversion) <>
             " is out of order - restore the sort rather than reformatting; " <>
             "the canonical-encoding test above re-encodes entries in parse " <>
             "order and cannot see this"
  end
end
```

Notes for the implementer, all deliberate:

- The comparison is **non-strict** (`a > b`, not `a >= b`). See "What We're NOT
  Doing" for why. Do not tighten it.
- The second guard is the one this test needs beyond the neighbors' non-empty
  check: with a single surface present, the outermost clause would be
  structurally untestable and the assertion would silently narrow to a
  `case_id` sort. The message says so.
- `Enum.sort/1` is not called; the adjacent-inversion scan gives the same verdict
  and a message that names the offending pair. If the implementer prefers
  `assert keys == Enum.sort(keys)`, the verdict is identical but the message is
  a 68-element diff - keep the scan.
- The `# sabotage:` note must name the mutation that was actually run, in the
  file's existing one-line form.

#### 2. The moduledoc count

**File**: `test/predicator/conformance/ratchet_registry_test.exs` (line 3)

**Changes**: The moduledoc says "five tests"; there are six before this change
and seven after. Update the sentence to the true count and mention that rule 2
is now bound by two tests - encoding and ordering. Take the number from the
actual run output rather than from this plan.

#### 3. The sabotage pass (run before committing; nothing is committed from it)

Every mutation below edits `conformance/examples/registry.example.json`, which
is read at runtime, so the stale-beam hazard
(`docs/research/260808-px-9ab-sabotage-notes.md:131-156`) does not apply and no
forced recompile is needed. Confirm a green baseline before each mutation,
revert with `git checkout -- conformance/examples/registry.example.json`, and
confirm green again after each. Record the exact failure text of each red - it
is Phase 2's content.

**Persist that text across the phase boundary before committing Phase 1.**
Phase 2 may be executed by a different agent invocation with none of this
phase's transcript, and its criterion is that the text is quoted rather than
reconstructed - so the observed output has to live somewhere durable, not in a
session. Write it to the bead as the last step of this phase:

```bash
bd note px-2gx "px-2gx sabotage pass, <date>: <verbatim mix test output
for each of the three mutations - test counts and failure messages>"
```

`bd note` is authorized at any time by CLAUDE.md's authority table, and the
bead is the loop's own state channel, which is what this is. Phase 2 reads the
note and turns it into prose. If the note is missing when Phase 2 starts, the
correct recovery is to re-run all three mutations from Phase 1 step 3 - never
to reconstruct plausible text from this plan's "Expect:" lines, which are
predictions and not observations.

1. **case_id clause.** Swap two adjacent evaluator entry lines, e.g.
   `comparison/lt-int-true` and `comparison/lt-list-elementwise` (lines 20-21).
   Expect: exactly the new test red, naming the inverted pair. Expect the
   canonical-encoding test to stay **green** - parse order is preserved through
   `reencode/1`, so the swapped bytes re-encode to themselves.
2. **surface clause.** Move one `"surface":"compiler"` entry line (e.g.
   `comparison/gt-int-true`, line 10) to the end of the entries array, after the
   last evaluator line. Expect: exactly the new test red, naming the
   `evaluator`/`compiler` inversion. Rule 1, rule 3, the pin, R5, and the
   encoding test all stay green.
3. **px-wy8 re-run, required by that bead's note.** Insert a byte-identical copy
   of `{"case_id":"comparison/gt-int-true","surface":"compiler","tier":1},`
   directly beneath the original. Expect: **exactly one** test red - the rule 3
   uniqueness test - and the new sort test **green**, because a duplicated
   adjacent pair is still non-strictly ascending. This is the evidence that the
   non-strict choice preserved px-wy8's recorded isolation. If this mutation
   reddens two tests, the comparison was written strictly; fix it and re-run.

If any mutation's observed result differs from the expectation above, that is a
finding to record in Phase 2 verbatim - do not adjust the expectation to match.

### Success Criteria:

#### Automated Verification:

- [x] `mix test test/predicator/conformance/ratchet_registry_test.exs` reports
      7 tests, 0 failures
- [x] Full quality gate is green: `mix quality`
- [x] `git status --porcelain` names exactly one changed file,
      `test/predicator/conformance/ratchet_registry_test.exs` - in particular
      `conformance/examples/registry.example.json`, `conformance/corpus/*.json`,
      and `conformance/manifest.json` are unchanged, confirming no sabotage
      mutation survived and no exported artifact moved (ADR-0003)
- [x] `ruby ~/.claude/skills/wurk:kit/scripts/gate.rb --profile loop` reports
      `sabotage.missing: []` - the new `test "..."` in a `test_roots` file
      carries its `# sabotage:` note
- [x] `mix corpus.generate` is **not** run and is not needed: no phase changes
      `conformance/cases/**`, so the corpus and `corpus_hash` cannot move. The
      `git status` criterion above is what proves it
- [x] Coverage stays above the 90% floor in `coveralls.json` (this phase adds
      test code only and no `lib/` code, so no component's ratio can fall)
- [x] `bd show px-2gx` carries a note containing the verbatim sabotage output -
      the durable handoff Phase 2 quotes from

#### Manual Verification:

- [ ] All three sabotage mutations were actually run, each observed red or green
      as predicted, each reverted, and green re-confirmed after each - a present
      `# sabotage:` note is not evidence the mutation was run
      (`docs/research/260808-px-9ab-sabotage-notes.md:406-409`)
- [ ] Mutation 3 reddened exactly one test and left the new sort test green,
      confirming px-wy8's isolation claim survives this change
- [ ] The failure messages read as diagnoses - they name the offending pair and
      point at the fix - rather than as bare assertion dumps
- [ ] The moduledoc's test count matches the run output
- [ ] The new test's placement and phrasing match the file's five neighbors

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run the full `mix quality` as the phase gate. In interactive
execution, pause here for the human to confirm the manual testing before moving
to the next phase. In looped (`--loop`) execution, this phase's Automated
Verification gates advancement automatically (via `/wurk:commit --auto`), and
Manual Verification items are deferred and surfaced once at the end instead of
blocking here.

---

## Phase 2: Record the sabotage pass

### Overview

Write the dated addendum that CLAUDE.md's binding-test convention requires, so
the Phase 1 pass survives the session.

### Changes Required:

#### 1. The sabotage-notes addendum

**File**: `docs/research/260808-px-9ab-sabotage-notes.md`

**Source**: the sabotage note Phase 1 wrote to the bead - read it first with
`bd show px-2gx`. Quote its failure text; do not paraphrase it and do not
reconstruct it from this plan. If it is absent, re-run Phase 1 step 3's three
mutations before writing anything.

**Changes**: Add a bullet to the "Additions to the class" list, after the
`2026-08-14 (px-ty0)` entry and before the "Enforcement: gate.sabotage" section.
Model it on the `2026-08-14 (px-wy8)` addendum at lines 317-345, which is the
same shape - a new assertion inside an already-listed file, not a new file.

The bullet states, at minimum:

- **The class count does not move.** `test/predicator/conformance/
  ratchet_registry_test.exs` has been in the class since px-9ab and in
  `gate.sabotage.test_roots` since px-lxs. Eleven files, still.
- What the new assertion binds: `conformance/RATCHET.md:66-74`'s three sort
  clauses, previously asserted by nothing because `reencode/1` re-emits entries
  in parse order.
- The three mutations, each with its literal observed failure text and test
  count, in the style the px-ty0 and px-wy8 entries use.
- **That the comparison is deliberately non-strict**, and that mutation 3 is the
  evidence: px-wy8's "exactly one test goes red" isolation was **re-run under
  this change and still holds**, rather than being carried forward on the
  strength of the earlier pass. Cross-reference the px-wy8 bullet so a reader
  arriving there finds the re-verification.
- **The honest coverage limitation**: the pass exercises the surface clause and
  the `case_id` clause. The tier clause is asserted but unexercised, because
  every entry in the example is tier 1 and no reordering can violate a one-tier
  order. Name what would change that (an example carrying a second tier) so the
  next reader knows the note is a two-clause pass wearing a three-clause
  assertion, in the spirit of the px-ir1 and px-qq6 entries that record exactly
  this kind of "reads as covering a direction and does not" finding.
- Confirmation that `git status --porcelain` reported no diff for
  `conformance/examples/registry.example.json` after each revert.

House style: this file uses plain ASCII punctuation and hyphens throughout;
match it.

### Success Criteria:

#### Automated Verification:

- [x] Full quality gate is green: `mix quality`
- [x] `mix test test/docs_adr_links_test.exs` passes - the docs binding test is
      unaffected by a `docs/research/` addition, and this confirms it
- [x] `git status --porcelain` names exactly one changed file,
      `docs/research/260808-px-9ab-sabotage-notes.md`
- [x] `grep -c "px-2gx" docs/research/260808-px-9ab-sabotage-notes.md` is
      non-zero

#### Manual Verification:

- [ ] The recorded failure text is what was actually observed in Phase 1, quoted
      rather than reconstructed
- [ ] The non-strict decision and the px-wy8 re-run are both stated, and the
      px-wy8 bullet's staleness warning is answered rather than left dangling
- [ ] The tier-clause limitation is stated plainly, not glossed
- [ ] The file count claim ("eleven files, still") matches
      `.claude/wurk.json`'s `gate.sabotage.test_roots`

**Implementation Note**: This phase touches no Elixir code, so per CLAUDE.md's
authority table it has no gate of its own to run - the full `mix quality` is
still run as the phase gate and must be green, since a green gate on an
unchanged tree is the cheapest possible confirmation that nothing leaked from
Phase 1. In interactive execution, pause here for the human to confirm the
manual testing. In looped execution, Manual Verification items are deferred to
the end.

---

## Testing Strategy

### Unit Tests:

- One new test in `test/predicator/conformance/ratchet_registry_test.exs`, in
  its own `describe` block, in the file's existing pattern-matching-free,
  data-driven style (it asserts over parsed JSON, not over `lib/` behavior).
- Edge cases the assertion must handle: an empty `entries` array (caught by the
  first guard, not by a vacuous pass); a single-surface entries array (caught by
  the second guard); a duplicated adjacent pair (deliberately **not** caught -
  that is rule 3's test); an inversion anywhere in the list, including the last
  pair (the `chunk_every(2, 1, :discard)` scan covers every adjacent pair).

### Integration Tests:

None. This bead adds no language behavior, so there is no
`Predicator.evaluate/3` or `execute/2` path to exercise end-to-end and nothing
belongs in `test/predicator/integration/`. The binding test *is* the integration
here: it reads a shipped artifact off disk and checks it against a published
contract.

### Manual Testing Steps:

1. On a clean tree, run `mix test
   test/predicator/conformance/ratchet_registry_test.exs` and confirm 7 tests,
   0 failures.
2. Swap two adjacent evaluator entry lines in
   `conformance/examples/registry.example.json`; re-run; confirm exactly one
   failure, the new sort test, naming the inverted pair. Revert with `git
   checkout --` and confirm green.
3. Move a compiler entry line to the end of the array; re-run; confirm exactly
   one failure, the new sort test, naming the surface inversion. Revert; confirm
   green.
4. Duplicate the `comparison/gt-int-true` compiler entry line; re-run; confirm
   exactly one failure - the rule 3 uniqueness test - and that the sort test is
   green. Revert; confirm green.
5. Confirm `git status --porcelain` reports no diff for
   `conformance/examples/registry.example.json` after step 4.

## References

- Bead: `px-2gx` (depends on px-wy8, which is closed and landed)
- Source document: `docs/research/260814-px-wy8-registry-entry-uniqueness.md`
  (the finding, at `:202-219`)
- Sabotage-note class and practice:
  `docs/research/260808-px-9ab-sabotage-notes.md`; px-wy8's addendum and its
  staleness warning at `:317-345`; the stale-beam hazard at `:131-156`
- The contract being bound: `conformance/RATCHET.md:66-74` (ordering),
  `:86-127` (rule 2), `:252-265` (`check/3`, R3)
- The file under test:
  `test/predicator/conformance/ratchet_registry_test.exs`; `reencode/1` at
  `:185-202`; the anti-vacuity pattern at `:49-51`
- Related ADRs: `docs/adr/0003-the-elixir-implementation-leads-the-isa.md` (this
  repo leads the ISA; the corpus is the exported specification - nothing
  exported moves here),
  `docs/adr/0006-irreversibility-places-the-human-gates.md` (the gates this plan
  stops short of),
  `docs/adr/0005-worktree-parallelism-and-the-area-label-algebra.md` (the
  `area:conformance` + `area:docs` labels this bead carries; no `area:build`,
  since `.claude/wurk.json` needs no edit)
- Similar implementation: `docs/plans/260814-px-wy8-registry-entry-uniqueness.md`

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] All three sabotage mutations were actually run, each observed red or green
      as predicted, each reverted, and green re-confirmed after each - a present
      `# sabotage:` note is not evidence the mutation was run
      (`docs/research/260808-px-9ab-sabotage-notes.md:406-409`)
- [ ] Mutation 3 reddened exactly one test and left the new sort test green,
      confirming px-wy8's isolation claim survives this change
- [ ] The failure messages read as diagnoses - they name the offending pair and
      point at the fix - rather than as bare assertion dumps
- [ ] The moduledoc's test count matches the run output
- [ ] The new test's placement and phrasing match the file's five neighbors

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run the full `mix quality` as the phase gate. In interactive
execution, pause here for the human to confirm the manual testing before moving
to the next phase. In looped (`--loop`) execution, this phase's Automated
Verification gates advancement automatically (via `/wurk:commit --auto`), and
Manual Verification items are deferred and surfaced once at the end instead of
blocking here.

---

### Phase 2

- [ ] The recorded failure text is what was actually observed in Phase 1, quoted
      rather than reconstructed
- [ ] The non-strict decision and the px-wy8 re-run are both stated, and the
      px-wy8 bullet's staleness warning is answered rather than left dangling
- [ ] The tier-clause limitation is stated plainly, not glossed
- [ ] The file count claim ("eleven files, still") matches
      `.claude/wurk.json`'s `gate.sabotage.test_roots`

**Implementation Note**: This phase touches no Elixir code, so per CLAUDE.md's
authority table it has no gate of its own to run - the full `mix quality` is
still run as the phase gate and must be green, since a green gate on an
unchanged tree is the cheapest possible confirmation that nothing leaked from
Phase 1. In interactive execution, pause here for the human to confirm the
manual testing. In looped execution, Manual Verification items are deferred to
the end.

---
