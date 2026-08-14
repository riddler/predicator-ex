# Are the registry.example.json "duplicates" real, and does the suite need a uniqueness assertion?

Bead: px-wy8 (filed while verifying px-24y's corpus diff)
Date: 2026-08-14
Decision: **the reported duplicates are a false positive - nothing is deleted
from `conformance/examples/registry.example.json`. The test file gains one new
assertion, keyed on `(case_id, surface)`, and `conformance/RATCHET.md` gains one
sentence making the uniqueness it already implies normative.** No corpus
regeneration, no `corpus_hash` change, no schema change, no ISA movement.

This is a conformance-apparatus call, not an architectural one. The identity
key it turns on - `(case_id, surface)` - is already RATCHET.md rule 1's key and
is not being invented here, and the sabotage-note obligation the new assertion
incurs is already CLAUDE.md's rule, adopted by px-9ab. Nothing here is
ADR-shaped, so this goes to `docs/research/` per `docs/adr/README.md`'s third
corollary. No ADR was written.

## The question, as filed

px-wy8 reports that `conformance/examples/registry.example.json` carries five
duplicated entries - `comparison/eq-string-true`, `comparison/gt-int-boundary`,
`comparison/gt-int-false`, `comparison/gt-int-true`, and
`comparison/gte-int-boundary-true`, each appearing twice - and asks whether the
fix is (a) deleting them, or (b) also tightening
`test/predicator/conformance/ratchet_registry_test.exs` so the file cannot drift
this way again.

The bead's reproduce script groups the entries by `case_id` alone.

## Ground truth: the five pairs are one case on two surfaces

Grouping the same 68 entries on the pair instead:

```text
total entries:              68
duplicate on case_id:        5   each surfaces=["compiler", "evaluator"]
duplicate on (case_id, surface): 0
```

Each of the five case ids appears exactly once with `"surface":"compiler"` and
exactly once with `"surface":"evaluator"`. The two entries in each pair are not
byte-identical - they differ in the `surface` field, which is the field the
reproduce script projects away.

RATCHET.md is unambiguous that this is the intended shape, in three places:

- "**One file, not one per surface.** Rule 1 below matches an entry against the
  corpus on the pair `(case_id, surface)`" - the section heading argument for
  why both surfaces share one file.
- Rule 1 itself: "A registry entry whose `(case_id, surface)` pair is not a
  member of that surface's case set in the pinned corpus FAILS the run", and its
  third bullet: "Matching on the pair rather than the id is what makes this
  detectable at all - and it is the reason the registry cannot be a flat list of
  ids."
- The `check/3` pseudocode: `fail unless (e.case_id, e.surface) in
  surface_case_set(corpus, e.surface)`.

The worked example in RATCHET.md's "literal shape" block makes the same point
concretely: it lists `comparison/eq-string-true` twice, once per surface, as the
demonstration of the format.

The count arithmetic in the bead is consistent with this reading rather than
against it. The example claims `{"surface":"evaluator","tier":1}` and carries a
partial compiler block; the "59 unique / 64 total" and "63 unique / 68 total"
figures are the compiler block's five entries showing up a second time under
their own surface, which is what the file is supposed to look like.

**Answer to question 1: nothing is deleted.** The file is correct as it stands,
and a deletion would take it red - dropping either half of a pair drops a real,
verified claim, and dropping the evaluator half specifically fails the R5
completeness test.

## What a *true* duplicate would do today, and to what

The interesting half of the bead survives the false positive. If the file did
carry a genuine duplicate - the same `(case_id, surface)` line twice - which
test names it?

Walking the four existing tests:

| Test | Behavior on a duplicated entry line |
|---|---|
| schema validation | green. `schema/registry.json` states no `uniqueItems`, and the test-side `SchemaValidator` in `test/test_helper.exs` implements no `uniqueItems` keyword at all. |
| rule 1 (membership + tier) | green. It iterates entries and checks each one independently; a duplicate is simply checked twice and passes twice. |
| the pin | green. It reads only `corpus_hash` and `isa_version`. |
| rule 2 (canonical encoding) | **green.** See below - this is the one worth stating carefully. |
| R5 completeness | green. It builds a `MapSet` of evaluator case ids; a `MapSet` absorbs the duplicate silently. This is exactly the mechanism the bead identified. |

The rule 2 test deserves the detail because the intuition runs the other way.
`reencode/1` re-emits `entries` in **the order it parsed them**; it does not
sort. So the byte-compare is a check that the file is canonically *encoded*, not
that it is canonically *ordered*, and a duplicated line re-encodes to itself.
Verified empirically: a re-implementation of `reencode/1` reproduces the shipped
file byte-for-byte, and reproduces it byte-for-byte again after a duplicate
entry line is inserted.

So the answer to "is a true duplicate detectable in principle?" is that today it
is not detectable even in principle by the encoding test - the sort clauses of
rule 2 are not enforced by anything. Detectability and a failing test that names
the problem are different things, and here the repo has neither.

## The decision on the assertion

**Answer to question 2: yes, and the key is `(case_id, surface)`.**

The choice among the three framings the bead offers is (i) with a documentation
correction folded in, not (ii) and not a bare (iii).

It is not (ii) - over-constraining a sibling - because a sibling registry that
follows RATCHET.md **cannot** contain a duplicate. Rule 3's verify-then-add step
is written in set language throughout: step 4 builds "Candidate set =
`{(id, surface) : result == "pass"}`", and step 6 writes "New entries = existing
union candidates". A set union is idempotent; running it twice cannot produce a
second copy of a pair. A duplicate is therefore not a legal-but-unusual sibling
registry that this repo would be newly rejecting. It is only producible by the
hand edit rule 3's first line already forbids - "**Nothing hand-edits the
registry.**" - or by a writer that ignored rule 3, which is a bug in that writer.

Nor does the key admit a second candidate. `(case_id, surface)` is what rule 1
matches on, what R5's membership test is written against, and what rule 2's sort
key determines (the sort is surface, then tier, then case_id; tier is a function
of case_id under the tier check, so the sort key and the identity key carry the
same information). Keying on `case_id` alone is precisely the bead's error.
Keying on the whole entry object - which is what a `uniqueItems` in the schema
would mean - is weaker: it would let a pair of entries that agree on
`(case_id, surface)` but disagree on `tier` through, which is a duplicate by the
identity key even though the tier check would independently fail at least one of
them.

The reason this is not simply (i) is that RATCHET.md never says the word. The
uniqueness is implied by set-valued rule 3 and by rule 1's key, and the implication
is solid, but a test in `gate.sabotage.test_roots` is a binding test: it exports
what it asserts to siblings as normative. px-9ab's whole argument for sabotage
notes was that a test which is the source of an exported specification must not
be able to ship a wrong one silently. A binding test asserting a rule the
normative document does not state is that same hazard in a different direction -
the sibling reads RATCHET.md, this repo's suite enforces something slightly
larger. One sentence closes the gap.

### What lands

1. `conformance/RATCHET.md`, in the "Rule 3: grown only by verify-then-add"
   section, gains a sentence stating that `entries` contains at most one entry
   per `(case_id, surface)` pair, and noting that step 6's set union is what
   guarantees it. Placing it under rule 3 rather than rule 1 or rule 2 is
   deliberate: uniqueness is a property of how the file is *grown*, and rule 3 is
   already where the growth semantics live. The check step's list may reference it
   in passing; it needs no new numbered R-check, because a hand-edited duplicate
   is the same class of defect R3 exists for.
2. `test/predicator/conformance/ratchet_registry_test.exs` gains one `describe`
   block with one test asserting that `example["entries"]` has no repeated
   `{case_id, surface}` pair, with a failure message naming the offending pairs.
   The file is already in `.claude/wurk.json`'s `gate.sabotage.test_roots`, so
   the list needs no edit, and no other manifest change is required.
3. The new test carries the anti-vacuity guard the neighboring tests carry
   (`ratchet_registry_test.exs:47` is the model): assert the entry list is
   non-empty before asserting a property over it, so an emptied `entries` array
   cannot make the uniqueness check pass by having nothing to check.
4. `conformance/schema/registry.json` gains **nothing**. `uniqueItems` is the
   wrong key as argued above, the test-side validator does not implement the
   keyword so it would be decorative here, and the schema already declares in its
   own `entries` description that ordering and encoding rules are things "this
   schema cannot express". Uniqueness belongs with them.
5. `registry.example.json` is not touched, and neither is the corpus. Since the
   file does not change, `corpus_hash` does not move and no sibling's pin is
   affected. The RATCHET.md sentence is a clarification of the exported contract
   rather than a new constraint on it, so it needs a CHANGELOG entry under
   `## [Unreleased]` but no migration note.

## The sabotage edit, and why it isolates

**Answer to question 3.** The sabotage is: duplicate one existing entry line in
`registry.example.json` - `{"case_id":"comparison/gt-int-true","surface":"compiler","tier":1}`
is the natural pick - by inserting a byte-identical copy directly beneath it, run
the suite, confirm red, revert.

The bead's stated wrinkle is that this may also turn the encoding test red, so
the sabotage would not isolate the new assertion. **It does not, and the reason
is the `reencode/1` behavior established above.** `reencode/1` preserves parse
order, so a file with two adjacent identical lines re-encodes to itself and R3
stays green. This was checked against the real file rather than reasoned about
in the abstract: re-encoding the shipped file byte-matches it, and re-encoding
the same file with the duplicate line inserted byte-matches the modified file.
The other three tests are green by construction, per the table above - per-entry
iteration, two scalar fields, and a `MapSet`.

So the sabotage isolates exactly one test, which is the property a sabotage note
is supposed to demonstrate, and the note above the new test reads:

```text
# sabotage: registry.example.json duplicates the comparison/gt-int-true compiler entry line -> red
```

The isolation is a fact about the current suite, not a design constraint the
assertion has to be bent around. It is worth recording that it depends on
`reencode/1` not sorting: if the follow-on below adds a sortedness check with a
strict comparison, this same sabotage would take *two* tests red, and the
sabotage verification for the uniqueness test would need re-running against
whatever the suite looks like then. That is a consequence for the follow-on to
carry, not a reason to change anything here.

## Follow-on: rule 2's sort order is bound by no test

Falling out of the analysis, and deliberately **out of scope for px-wy8**: the
rule 2 test's moduledoc and name both claim to bind "the file is exactly the
canonical encoding", but `reencode/1` re-emits entries in parse order. Rule 2's
three sort clauses - surface, then tier, then case_id, all ascending by
codepoint - are asserted by nothing. Shuffling `registry.example.json`'s entry
lines into a wrong order leaves the entire suite green.

This wants its own bead (`area:conformance`), because it is a second binding
test with its own sabotage verification and its own RATCHET.md reading, and
folding it into px-wy8 would mean two assertions whose sabotages interact - a
duplicate line and an out-of-order line are different defects that should produce
different named failures. Note also that a *strict*-ascending sortedness check
would subsume the uniqueness assertion for identical entries, which is an
argument for landing uniqueness first, with its own clean sabotage, and then
deciding whether the sortedness check is written strictly or non-strictly with
the uniqueness test already in place.

## Open questions

- **The example's provenance is described two ways and there is no generator.**
  `ratchet_registry_test.exs`'s moduledoc says the example "is generated from
  this checkout's own `conformance/corpus/tier-1.json`, not hand-typed"; px-wy8's
  description says the file "is hand-maintained rather than generated". No
  generator exists: nothing in `lib/`, no `mix corpus.*` task, and no other test
  writes `registry.example.json` - the only non-documentation reference to the
  path in the tree is the test that reads it. "Generated" appears to describe how
  the file was originally derived, not a step anyone can re-run. This does not
  change any decision above (it is, if anything, the reason a uniqueness
  assertion is worth having at all), but somebody should decide whether to write
  the generator or to correct the moduledoc. Not filed as a bead here; flagged for
  the implementer to raise.
- **Whether the RATCHET.md sentence needs siblings told.** ADR-0003 has siblings
  adopting on a boundary of their own choosing, and this clarification cannot
  invalidate an existing sibling registry that followed rule 3. No outward
  notification is assumed to be owed. If the implementer disagrees, the mirrored
  bead protocol in CLAUDE.md is the mechanism, not an ad-hoc note.
