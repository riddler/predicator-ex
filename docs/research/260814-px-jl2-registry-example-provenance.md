# Is registry.example.json generated or hand-maintained?

Bead: px-jl2 (filed from px-wy8's open question; see
`docs/research/260814-px-wy8-registry-entry-uniqueness.md`)
Date: 2026-08-14
Decision: **hand-maintained. No generator is written, and none should be - a
faithful one would be the ratchet runner this repo deliberately does not ship,
and an unfaithful one would be the "regenerate" anti-pattern RATCHET.md rule 3
exists to forbid. The moduledoc of
`test/predicator/conformance/ratchet_registry_test.exs`, three of its failure
messages, and `conformance/schema/registry.json`'s `description` are corrected
to say so; the binding tests already in that file are the mechanism that keeps
the hand-maintained example honest.** No corpus regeneration, no `corpus_hash`
movement, no schema constraint change, no ISA movement.

This is a conformance-apparatus call, not an architectural one: it changes no
instruction, no grammar, and no normative rule in `conformance/RATCHET.md`.
Per `docs/adr/README.md`'s third corollary it goes to `docs/research/`, named
after the bead. No ADR was written.

## The question, as filed

The provenance of `conformance/examples/registry.example.json` is described
two ways, and neither is true of the tree:

- `ratchet_registry_test.exs`'s moduledoc says the example "is generated from
  this checkout's own `conformance/corpus/tier-1.json`, not hand-typed (see
  the file's own comments in RATCHET.md for why)".
- px-wy8's description, `docs/plans/260807-px-tbv.9-retire-legacy-and-or-opcodes.md:165`
  ("`registry.example.json` has **no generator task**; it is hand-maintained"),
  and `docs/plans/260813-px-24y-null-literal-grammar.md:124` all say it is
  hand-maintained.

No generator exists. `mix corpus.generate` writes only
`conformance/corpus/tier-*.json` and `conformance/manifest.json`
(`lib/mix/tasks/corpus.generate.ex`); nothing in `lib/`, no mix task, and no
test writes the example - the only non-documentation reference to the path is
the test that reads it. The moduledoc's parenthetical points at comments that
do not exist: RATCHET.md never discusses the example's provenance at all
(JSON carries no comments, and RATCHET.md's prose never mentions the file).

The bead asks: write the generator the moduledoc claims, or correct the prose
and lean on the binding tests?

## Why not a generator

Three reasons, in descending order of weight. The first is a matter of
principle, not cost.

**1. A faithful generator is the ratchet runner this repo refuses to ship.**
RATCHET.md rule 3 is explicit that a registry is grown only by
verify-then-add: "The only input to the writing step is a runner report;
there is no 'add case X' command that takes an id", and step 5's refusal to
drop an entry is "the reason 'verify-then-add' is not 'regenerate'". A
generator that derives the example from `tier-1.json` is precisely a
regeneration step - it would produce the worked example of the contract by
the one process the contract forbids. The alternative - a generator that
actually runs the evaluator and compiler over the corpus and writes from the
report - is RATCHET.md's runner plus writer, and the moduledoc's own closing
paragraph records the standing decision against that: "This repo ships no
ratchet runner (`lib/` gains no module here)". px-35i.8 put the runner in
language-neutral pseudocode for siblings to implement, deliberately not in
Elixir; a generator would quietly reverse that.

**2. The example's shape is didactic, and no function of the corpus produces
it.** The file claims `{"surface":"evaluator","tier":1}` only, yet carries
five compiler entries - a sibling mid-climb, recording compiler passes above
what it claims, which is exactly the "entries above the claimed tier are
legal" property RATCHET.md spells out. Which five, and why only five, is a
pedagogical choice. A generator would need that choice as input, and a
hand-maintained input file driving a generator is the same hand maintenance
with an extra moving part.

**3. Practice has already settled the question.** Every corpus-moving branch
since the file was created - px-3so.3, px-3so.4, px-ocp, px-24y among them -
has its plan instruct "hand-update `registry.example.json`'s `corpus_hash`
and `isa_version`" (and its entries, when tier 1 grew), and the file is
correct today. The cost of hand maintenance is a few lines per corpus change,
paid under test; the cost of a generator is a new module, a new task, its
tests, and a standing contradiction with rule 3.

"Generated from tier-1.json" in the moduledoc appears to describe how the
file's entry list was originally *derived* when px-35i.8 authored it, not a
step anyone can re-run. The distinction stopped mattering the moment the
prose claimed a re-runnable step that does not exist.

## The mechanism: binding tests, not provenance

What actually keeps the file honest is the suite in
`ratchet_registry_test.exs`, all of it already in
`.claude/wurk.json`'s `gate.sabotage.test_roots` with sabotage notes per
px-9ab. Every drift class the bead could worry about has a test that goes red
naming it:

| Drift | Named by |
|---|---|
| entry not in the corpus, wrong tier, compiler entry for a `source: null` case | rule 1 test |
| stale `corpus_hash` / `isa_version` after `mix corpus.generate` | the pin test (against `conformance/manifest.json`) |
| tier-1 evaluator case added to the corpus but not the example | R5 completeness test |
| duplicated `(case_id, surface)` line | rule 3 uniqueness test (px-wy8) |
| reindent, reflow, incidental whitespace | rule 2 canonical-encoding byte-compare |
| example no longer satisfies the schema | schema validation test |

That table is the reason "hand-maintained" is not a euphemism for
"unverified": the suite is R1, R2 (rule 1 + tier), R3 (encoding), and R5 of
RATCHET.md's own check step, applied to the one registry this repo has. The
one property bound by nothing is rule 2's sort order - already recorded as a
follow-on in px-wy8's research document, out of scope here, and unchanged by
this decision.

## What changes, exactly

Two files change; both changes are prose only. No test logic, no assertion,
no sabotage note, and no entry in `gate.sabotage.test_roots` moves, so no
sabotage re-verification is owed.

### 1. `test/predicator/conformance/ratchet_registry_test.exs`

**The moduledoc's second paragraph** (currently lines 8-14) is replaced with:

> `conformance/examples/registry.example.json` is hand-maintained: no
> generator exists, and none should - a faithful writer would be RATCHET.md's
> verify-then-add step, which is the ratchet runner this repo deliberately
> does not ship, and a regenerate-from-corpus script is the regeneration
> rule 3 exists to forbid. These tests are what keep the hand-maintained
> example honest: a `mix corpus.generate` that changes the corpus, a bad hand
> edit, a duplicated line, or a reindent all turn this suite red, naming the
> problem, rather than letting the worked example quietly drift from the spec
> it demonstrates.

(The "see the file's own comments in RATCHET.md" parenthetical is dropped
entirely - it points at nothing.)

**Three failure messages that instruct the impossible** ("regenerate") are
reworded to instruct the actual remedy:

- The pin test's `corpus_hash` message (currently ends "regenerate
  `#{@example_path}` against the new corpus") becomes: "the corpus
  regenerated and the example was not: hand-update `#{@example_path}`'s
  `corpus_hash` (and its entries, if tier 1 changed) to match the new
  manifest".
- The pin test's `isa_version` message (currently "regenerate
  `#{@example_path}` against the current manifest") becomes: "hand-update
  `#{@example_path}`'s `isa_version` to match the current manifest".
- The rule 2 test's message (currently ends "a hand edit or a pretty-printer
  likely touched it; regenerate it instead of editing it directly") becomes:
  "an editor or a pretty-printer likely reflowed it; restore the encoding
  RATCHET.md rule 2 specifies rather than reformatting".

Message text is not asserted by anything, so these are free; the sabotage
notes above each test describe the mutation and the red, not the wording, and
stay as they are.

### 2. `conformance/schema/registry.json`

The top-level `description` (line 5) currently says
"conformance/examples/registry.example.json is a worked example generated
from this checkout's own corpus". The clause becomes:
"conformance/examples/registry.example.json is a hand-maintained worked
example, kept correct against this checkout's own corpus by
test/predicator/conformance/ratchet_registry_test.exs". The rest of the
sentence and the file are untouched.

**In scope, deliberately.** The schema is a checked-in, hand-authored
exported artifact that siblings consume, so the ADR-0003 weighing was done
rather than skipped: this edit changes an English `description`, not a
constraint - no keyword, no `required` list, no pattern moves - so no
sibling registry that validated before validates differently after, nothing
about the stored corpus moves (`corpus_hash` covers `conformance/corpus/`,
not the schema files), and no ISA version or migration note is owed. What an
exported-artifact diff does owe, by the same convention as a corpus diff, is
an explanation in the commit message and PR body, and a line under
`## [Unreleased]` - see below. Leaving the schema's false claim in place
while fixing the moduledoc would move the drift, not close it: the schema is
the copy of this claim a sibling actually reads.

### 3. `CHANGELOG.md`

One line under `## [Unreleased]`, documentation section, noting that the
registry example's provenance prose (test moduledoc and
`schema/registry.json` description) now matches reality: the file is
hand-maintained and test-enforced. Same treatment px-wy8 gave its RATCHET.md
clarification sentence.

### Explicitly not changed

- `conformance/examples/registry.example.json` itself - correct as it stands;
  `corpus_hash` does not move, no sibling pin is affected.
- `conformance/RATCHET.md` - it never claimed the example was generated, and
  rule 3's "nothing hand-edits the registry" governs a sibling's real
  registry grown by verify-then-add, not this repo's didactic example. Adding
  a carve-out sentence for the example was considered and declined: the
  document ships to siblings as the contract for *their* files, and the
  example's provenance is this repo's internal affair, documented where the
  enforcement lives (the test file).
- `conformance/README.md`, `docs/guides/porting.md`, and CHANGELOG history
  (the 553-area release entry) - none of them claims the file is generated;
  porting.md's "a real one to model your own after" stays accurate.
- `docs/plans/*` and `docs/research/*` - historical records; the two plans
  that already say "hand-maintained" were right.

## Sibling notification

None owed. Per ADR-0003 siblings adopt on a boundary of their own choosing
and are bound only by `docs/isa.md` and the corpus; a prose correction in a
schema `description` binds nobody and invalidates nothing. Same conclusion
px-wy8 reached for its RATCHET.md sentence, for the same reason.

## Open questions

- None blocking. The one adjacent gap - rule 2's sort order is bound by no
  test - was identified in px-wy8's research document as its own follow-on
  bead (`area:conformance`) and is unaffected by this decision; whoever files
  it should note that the pin-test message wording above assumes
  hand-updating remains the remedy.
