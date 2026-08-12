# Canonical Datetime Form in the Tagged-Value Encoding Implementation Plan

## Overview

Pin the fractional-seconds field of the conformance corpus's tagged `datetime`
encoding to the same canonical form `datetime::string` already carries -
**omitted entirely when the sub-second component is zero, exactly six digits
when it is not** - by canonicalizing the `DateTime` precision field on **both**
encode and decode in `Predicator.Conformance.Values`, restating the codec's
round-trip property accordingly, documenting the form in
`conformance/README.md`, and adding one conformance case that exercises the
six-digit half in the exported artifact. Bead: `px-qq6`.

The decision is settled and is not reopened here. It is recorded in
[`docs/research/260811-px-qq6-tagged-datetime-precision.md`](../research/260811-px-qq6-tagged-datetime-precision.md),
including the argument for canonicalizing on both directions rather than encode
only, the restated property, and the reasoning that **the ISA does not move and
`docs/isa.md` gets no edit at all**. This plan executes it. The form it adopts
comes from px-7t8
([`docs/research/260810-px-7t8-datetime-string-fractional-seconds.md`](../research/260810-px-7t8-datetime-string-fractional-seconds.md)),
which has already landed for the `cast` opcode.

## Current State Analysis

**The encoding is a function of an Elixir struct field, not of the instant.**
`lib/predicator/conformance/values.ex:70-72` encodes a `DateTime` with
`DateTime.to_iso8601/1`, which prints exactly as many fractional digits as the
struct's `microsecond` precision field says. Measured on this branch:

```text
#2026-08-09T10:30:00.500Z#::datetime  -> {"$type":"datetime","value":"2026-08-09T10:30:00.500Z"}
#2026-08-09T10:30:00Z#::datetime      -> {"$type":"datetime","value":"2026-08-09T10:30:00Z"}
"2026-08-09T10:30:00Z"::datetime      -> {"$type":"datetime","value":"2026-08-09T10:30:00.000000Z"}
```

The first is the load-bearing measurement: three fractional digits, a count no
Ruby `Time#iso8601(n)` can trim to and no `Date`-backed JavaScript sibling can
distinguish from any other. The second and third are the *same instant*
encoding two ways depending on which Elixir code path produced the value - the
literal path carries the lexer's precision, the string-parse path goes through
`Cast.normalize_to_utc/1` (`lib/predicator/cast.ex:165-168`), which forces
precision 6.

**The form the `cast` opcode already uses is the target.** px-7t8 landed
`canonicalize_microsecond/1` at `lib/predicator/cast.ex:174-179` - two clauses,
`{0, _} -> {0, 0}` and `{us, _} -> {us, 6}` - and pinned the resulting form
normatively in `docs/isa.md` section 5. It is private to `Cast`.

**The round-trip property is real and holds exactly today.**
`to_json/1`'s `@doc` (`values.ex:93`) promises `from_json(to_json(v)) ==
{:ok, v}`, and `test/predicator/conformance/values_test.exs:34-44` asserts it
over `@round_trip_values` (`:11-32`). `from_json/1` parses with
`DateTime.from_iso8601/1`, which sets the precision field from the digits it
read, so encode-then-decode is currently exact for every precision. What this
change weakens is a property that genuinely holds, not a documented aspiration.

**Nothing currently on disk moves.** Every tagged `datetime` value in
`conformance/corpus/tier-*.json` is zero-fraction (verified: the eight distinct
tagged datetimes across tiers 1, 2, 4, and 7 all end `:00Z`; the only fraction
anywhere in the corpus is `"2026-08-09T10:30:00.500000Z"` in tier 7, which is a
plain **string** result of `datetime::string`, not a tagged value). So the
Phase 1 code change regenerates byte-identically.

**The corpus has shipped.** It went out in 4.0.0 (`CHANGELOG.md`, the 4.0.0
section), not under `## [Unreleased]`, so a sibling may already be reading these
files. The chosen form changes nothing a sibling has seen.

**The generator compares authored expectations on the encoded JSON.**
`lib/predicator/conformance/generator.ex:408-414` compares `authored ==
computed` after encoding, and
`test/predicator/conformance/corpus_freshness_test.exs` byte-compares the
checked-in corpus against a fresh in-memory generation. Both consequences
matter for phasing: an authored case and the regenerated corpus must land in
the same commit, and the freshness test is a free automated check that Phase 1
really is a corpus no-op.

**`from_json/1` is fed hand-authored JSON, not only encoder output.**
`decode_context/1` (`generator.ex:310-320`) and `synthesize_outcome/1`
(`generator.ex:232-241`) both decode authored case JSON, so nothing stops a case
from writing `"...00.000Z"` and putting a precision-3 `DateTime` into the
evaluator's context. That is why the decision canonicalizes on decode too.

**`values_test.exs` is not currently in the sabotage-note class.**
`docs/research/260808-px-9ab-sabotage-notes.md` enumerates eight files; this is
not one of them. The direction record adds it, so this plan adds the file to
that document's "Additions to the class" section with a verified mutation.

## Desired End State

`Predicator.Conformance.Values` emits exactly two datetime shapes -
`YYYY-MM-DDTHH:MM:SSZ` and `YYYY-MM-DDTHH:MM:SS.ffffffZ` - and decodes any
ISO-8601 fraction into the canonical one of those two, so the tagged encoding
is a function of the instant alone. `conformance/README.md` states that form
normatively beside its `duration` guidance, including the
emit-canonical/accept-anything decoder rule. One conformance case pins the
six-digit half in the exported artifact. `docs/isa.md` is untouched and
`manifest.json`'s `isa_version` stays `4`.

Verified by: `mix quality` green; `mix corpus.generate` leaving a clean tree
after Phase 2; `conformance/corpus/tier-7.json` containing a tagged datetime
whose `value` ends `.500000Z`; and `grep` finding no `docs/isa.md` change in the
branch diff.

### Key Discoveries:

- `lib/predicator/conformance/values.ex:70-72` and `:122-127` are the two
  clauses that change; the helper to add is a verbatim two-clause copy of
  `lib/predicator/cast.ex:174-179`.
- `lib/predicator/cast.ex:174-179`'s `canonicalize_microsecond/1` is **private**
  and stays that way. The direction record instructs duplicating it rather than
  sharing it: `Values` is corpus tooling excluded from the Hex package, and a
  public helper linking the two would widen `area:api` for four lines.
- `test/predicator/conformance/corpus_freshness_test.exs` byte-compares the
  corpus, so any phase that changes an authored case must regenerate in the
  same commit.
- Measured: `#2026-08-09T10:30:00.500Z#::datetime` encodes as `.500Z` today and
  as `.500000Z` after Phase 1 - a real, currently-reachable non-canonical shape,
  which is what makes the Phase 2 case worth having.
- The `lit` operand in a generated corpus line is itself tagged
  (`generator.ex:256-265`), so the Phase 2 case moves both the operand and the
  `expected_result`.
- ADR-0003: the corpus is the exported specification and a corpus diff is
  explained in the commit message and the PR body.
- `docs/isa.md` section 3 delegates the tagged encoding to `px-35i.4` /
  `conformance/README.md` explicitly, which is why pinning it cannot move the
  ISA version.

## What We're NOT Doing

- **No `docs/isa.md` edit and no ISA version bump.** Settled in the direction
  record's version section: no opcode's behavior changes, section 3 delegates
  the tagged encoding to `conformance/README.md`, and no shipped byte moves.
  `Predicator.isa_version/0` stays at 4.
- **No change to `lib/predicator/cast.ex`.** px-7t8's clause is correct and this
  bead does not touch the `cast` opcode.
- **No shared/public canonicalization helper.** The four lines are duplicated
  deliberately; see Key Discoveries.
- **No change to `conformance/cases/casts.json`'s
  `casts/string-to-datetime-with-offset` note (`:155-159`).** The direction
  record leaves the chained `::date` dodge alone: its note explains that the
  case's subject is the offset requirement and that it deliberately does not
  assert a fact it does not own, and that reasoning survives this decision.
- **No `conformance/schema/*.json` `pattern` constraint on the tagged `value`
  string.** Declined in the direction record: it would have to be repeated
  everywhere a value can appear, and the generated corpus is already the
  binding.
- **No `docs/reference/language.md` change.** Its datetime sentence is about
  the `::string` cast, which does not move.
- **No tier-1 bare-literal variant of the Phase 2 case.** A case whose source is
  just `#2026-08-09T10:30:00.500Z#` would pin the same form one tier earlier and
  therefore for more runners, and it was considered. It is declined to keep the
  change to the single case the direction record specified, in the file where
  the neighbouring datetime encodings already live; the tier-7 case pins the
  form in both the `lit` operand and the result, which is sufficient. If a
  later bead wants the earlier-tier pin, adding it is additive.
- **No retrofit of sabotage notes onto the other eight binding-test files.**
  That is px-suw's scope; this plan adds one entry for one new test.

## Implementation Approach

Two phases, split at the seam where the corpus moves.

Phase 1 is the whole behavioral change - codec, tests, `conformance/README.md`,
moduledoc and `@doc`s, `CHANGELOG.md`, sabotage note - and is **provably a
corpus no-op**, because every tagged datetime on disk is already zero-fraction.
The freshness test is what proves it, at no extra cost. Phase 2 adds the one
conformance case and regenerates, which is the only thing in this bead that
moves `corpus_hash`.

They are split rather than combined for one concrete reason: the commit-message
and PR-body obligation ADR-0003 puts on a corpus diff is very different in the
two cases. Phase 1's explanation is "the encoding changed and deliberately
nothing on disk moved, here is why"; Phase 2's is "here is the one line that
moved and what it now pins". Folding them together produces a single commit
whose corpus diff understates what changed. Each phase is independently
committable and independently green - Phase 1's codec change stands complete
without the case, and Phase 2's case is inert without the codec change, which
is why Phase 2 comes second rather than the reverse.

They are not split further. Splitting the codec change from its tests, or the
`README` sentence from the behavior it describes, would leave an intermediate
gate red or an intermediate commit documenting a form the code does not emit.

## Phase 1: Canonicalize on encode and decode

### Overview

Make the tagged datetime encoding a function of the instant alone, restate the
round-trip property, document the form, and prove that nothing on disk moves.

### Changes Required:

#### 1. The codec

**File**: `lib/predicator/conformance/values.ex`
**Changes**: canonicalize the precision field in the `to_json/1` `%DateTime{}`
clause and in the `from_json/1` `"datetime"` clause, via a new private
two-clause helper duplicated from `Cast`.

```elixir
def to_json(%DateTime{} = datetime) do
  value = datetime |> canonicalize_microsecond() |> DateTime.to_iso8601()
  {:ok, %{"$type" => "datetime", "value" => value}}
end

def from_json(%{"$type" => "datetime", "value" => value}) when is_binary(value) do
  case DateTime.from_iso8601(value) do
    {:ok, datetime, _utc_offset} -> {:ok, canonicalize_microsecond(datetime)}
    {:error, reason} -> {:error, {:invalid_datetime, reason}}
  end
end

# The tagged datetime encoding carries the same canonical fractional-seconds
# form as datetime::string (docs/isa.md section 5, px-7t8): the fraction
# omitted entirely when the sub-second component is zero, exactly six digits
# when it is not. Elixir's precision field has no representation in the
# encoding, so canonicalizing on both directions is what makes the encoding a
# function of the instant rather than of whichever code path produced the
# struct. Deliberately duplicated from Cast's private clause rather than
# shared - see docs/research/260811-px-qq6-tagged-datetime-precision.md.
@spec canonicalize_microsecond(DateTime.t()) :: DateTime.t()
defp canonicalize_microsecond(%DateTime{microsecond: {0, _precision}} = datetime),
  do: %{datetime | microsecond: {0, 0}}

defp canonicalize_microsecond(%DateTime{microsecond: {microseconds, _precision}} = datetime),
  do: %{datetime | microsecond: {microseconds, 6}}
```

#### 2. The documented property

**File**: `lib/predicator/conformance/values.ex`
**Changes**: the moduledoc's `datetime` example line gains the form; `to_json/1`'s
`@doc` states it; `from_json/1`'s `@doc` replaces the verbatim round-trip
sentence with the restated one. The form worth stating is the one with no
exceptions:

> The inverse of `to_json/1` up to canonicalization: `to_json(from_json(to_json(v)))
> == to_json(v)` for every value `to_json/1` accepts, and `from_json(to_json(v))
> == {:ok, v}` for every value except a `DateTime` whose precision field
> disagrees with its own sub-second component, which comes back canonicalized.

`to_json/1`'s `@doc` has a `date` example (`values.ex:51-52`) and no `datetime`
one at all. Add **both** emitted shapes there, beside the `date` example - a
zero-fraction `~U[2026-08-06T12:00:00Z]` and a six-digit
`~U[2026-08-06T12:00:00.5Z]` -> `"2026-08-06T12:00:00.500000Z"` - so
`doctest Predicator.Conformance.Values` exercises the form and the moduledoc's
claim cannot drift from the code.

#### 3. The tests

**File**: `test/predicator/conformance/values_test.exs`
**Changes**: three additions and one title change, no deletions.

- `@round_trip_values` (`:11`) keeps `~U[2026-08-06T12:00:00Z]` and **gains**
  `~U[2026-08-06T12:00:00.500000Z]`; the `describe` title (`:34`) becomes
  "round-trip: from_json(to_json(v)) == {:ok, v}, for every canonical value".
  The assertion body is unchanged.
- A new `describe` block for canonicalization, as a table of non-canonical input
  to canonical output: `~U[...12:00:00.000000Z]` encodes as `"...12:00:00Z"` and
  round-trips to a `{0, 0}` precision field; `~U[...12:00:00.5Z]` encodes as
  `"...12:00:00.500000Z"` and round-trips to `{500_000, 6}`. Each asserts both
  `DateTime.compare/2 == :eq` (the instant is preserved) and the exact precision
  field (the canonicalization happened). This is the test that binds the
  decision, so it carries a sabotage note.
- A new decode test on the hand-authored path:
  `from_json(%{"$type" => "datetime", "value" => "...00.000Z"})` yields
  precision `{0, 0}`, and `"...00.5Z"` yields `{500_000, 6}`.
- The existing "to_json/1 - tagged encoding shape" `DateTime` test (`:56`) is
  unchanged and gains a sibling asserting the six-digit shape.

#### 4. The exported documentation

**File**: `conformance/README.md`
**Changes**: in "The tagged-value encoding", the `DateTime` table row keeps its
example, and a normative paragraph goes beside the duration paragraph it
parallels: the fraction is omitted entirely when the sub-second component is
zero and is exactly six digits when it is not, never any other count and never a
zero fraction spelled out; this is the same form `docs/isa.md` section 5 gives
`datetime::string`, deliberately, so a sibling writes one datetime formatter
rather than two; and **a decoder emits only those two shapes but accepts any
ISO-8601 fraction**, because a hand-authored case may contain one and the
instant is unambiguous.

#### 5. The sabotage note

**File**: `docs/research/260808-px-9ab-sabotage-notes.md`
**Changes**: an "Additions to the class" entry dated 2026-08-11 (`px-qq6`) adding
`test/predicator/conformance/values_test.exs`, with the reason (the tagged
encoding is an exported cross-language artifact in the same sense as the corpus)
and the verified mutation. Two mutations, each naming exactly which
tests it must redden:

1. Drop the `canonicalize_microsecond/1` call from `to_json/1` (leave the helper
   and the `from_json/1` call in place). Must redden the canonicalization
   `describe`'s **encode** assertions (the `.000000Z` and `.5` rows) and the new
   six-digit sibling of the "tagged encoding shape" `DateTime` test.
2. Drop it from `from_json/1` instead. Must redden **both** decode-touching
   tests: the canonicalization `describe`'s precision-field assertions on the
   round trip **and** the separate hand-authored decode test. If either stays
   green, the tests do not cover the direction they claim to, and that is a
   finding rather than a note to write around.

Record the actual failure text for each, matching the entry style already in
that document.

#### 6. The changelog

**File**: `CHANGELOG.md`
**Changes**: one bullet of its own under `## [Unreleased]` - not folded into the
cast entry - because the corpus and its encoding shipped in 4.0.0, so this is a
specification a sibling may already be reading being made precise.

### Success Criteria:

#### Automated Verification:

- [x] Full `mix quality` passes, including doctests for the new `@doc` examples.
- [x] `mix corpus.generate` leaves the working tree clean:
      `git diff --quiet conformance/` succeeds, i.e. `corpus_hash` and every
      tier file are byte-identical. This is the phase's central claim.
- [x] `test/predicator/conformance/corpus_freshness_test.exs` passes without
      regeneration, which is the same claim checked from the other direction.
- [x] `Predicator.Conformance.Values` coverage stays above the 90% minimum in
      `coveralls.json` (both helper clauses are exercised).
- [x] `git diff --stat docs/isa.md` is empty.

#### Manual Verification:

- [ ] The sabotage mutations were actually run and confirmed red for the right
      reason, and the recorded failure text is the real one.
- [ ] `conformance/README.md`'s new paragraph reads correctly to someone
      implementing a sibling from that document alone - in particular the
      asymmetry between emitting and accepting.
- [ ] The restated `@doc` property is accurate: check by hand that
      `to_json(from_json(to_json(v))) == to_json(v)` is stated without
      exceptions and the structural form's one exception is named.
- [ ] The commit message and PR body say explicitly that the corpus was
      regenerated and deliberately did not move, and why (ADR-0003 obliges a
      corpus diff to be explained, and "there is no diff" is this phase's
      explanation).

**Implementation Note**: Use `mix quality --profile loop` between edits and the
full gate as the phase gate. In interactive execution, pause here for the human
to confirm the manual testing before moving to the next phase. In looped
(`--loop`) execution, this phase's Automated Verification gates advancement
automatically (via `/wurk:commit --auto`), and Manual Verification items are
deferred and surfaced once at the end instead of blocking here.

---

## Phase 2: Pin the six-digit shape in the corpus

### Overview

Add the one conformance case that makes the non-zero half of the form part of
the exported specification rather than only of the Elixir suite, and regenerate.

### Changes Required:

#### 1. The authored case

**File**: `conformance/cases/casts.json`
**Changes**: one case, placed beside `casts/datetime-to-datetime-identity`
(`:70-74`), which it mirrors.

```json
{
  "id": "casts/datetime-identity-non-zero-fraction-encodes-six-digits",
  "source": "#2026-08-09T10:30:00.500Z#::datetime",
  "expected": {
    "result": { "$type": "datetime", "value": "2026-08-09T10:30:00.500000Z" }
  },
  "notes": "the tagged datetime encoding carries the same canonical fractional-seconds form as datetime::string: omitted entirely when the sub-second component is zero and exactly six digits when it is not (conformance/README.md, px-qq6). The literal's own three digits are not what is exported - a variable digit count is the cross-language hazard the form exists to remove, since a Date-backed JavaScript sibling can only produce three and Ruby's iso8601(n) cannot trim. The pinned value is expressible in milliseconds deliberately, so such a sibling can construct the input at all. Every other datetime in the corpus is zero-fraction, so without this case the six-digit half of the form is pinned only by the reference implementation's own suite"
}
```

The value is millisecond-expressible for the same portability reason px-7t8
applied. The result is asserted as a **tagged datetime**, not chained onto
`::date` or `::string` - asserting the encoding is the entire point of the case.

#### 2. The regenerated corpus

**Files**: `conformance/corpus/tier-7.json`, `conformance/manifest.json`
**Changes**: produced by `mix corpus.generate`, never hand-edited. Expect
tier 7's `case_count` to go 56 -> 57 and `corpus_hash` to change. The new line
carries the canonical form in **two** places - the `lit` operand and
`expected_result` - because instruction operands are tagged too.

### Success Criteria:

#### Automated Verification:

- [x] Full `mix quality` passes, including the schema-validation and
      corpus-freshness binding tests.
- [x] `mix corpus.generate` is a fixpoint: running it twice leaves the tree
      clean the second time.
- [x] `grep '10:30:00\.500000Z' conformance/corpus/tier-7.json` finds the new
      case's tagged `value`, and the same line's `lit` operand carries it too.
- [x] `conformance/manifest.json`'s `isa_version` is still `4`, and its tier-7
      `case_count` is 57.
- [x] `git diff --stat docs/isa.md` is still empty.

#### Manual Verification:

- [ ] The generator accepted the authored `expected` without a mismatch error,
      confirming the authored form is what the real pipeline computes rather
      than something the author guessed.
- [ ] The corpus diff is exactly one added line plus the manifest's hash and
      count - nothing else moved.
- [ ] The commit message and PR body explain the corpus diff and what it pins
      (ADR-0003), and say that `corpus_hash` moved for an added case rather than
      for a changed expectation, so no sibling's existing expectation is
      invalidated.
- [ ] The case reads as pinning the *encoding*, not the `cast` opcode, to
      someone who finds it in `casts.json`.

**Implementation Note**: Use `mix quality --profile loop` between edits and the
full gate as the phase gate. In interactive execution, pause here for the human
to confirm the manual testing. In looped (`--loop`) execution, this phase's
Automated Verification gates advancement automatically, and Manual Verification
items are deferred and surfaced once at the end.

If the corpus diff turns out to be unwanted - the direction record records this
as the cheap fallback - dropping this phase entirely leaves every consequence of
Phase 1 intact, at the cost of leaving the six-digit half pinned only by the
Elixir suite.

---

## Testing Strategy

### Unit Tests:

- `test/predicator/conformance/values_test.exs` - the four changes in Phase 1.
  The canonicalization table is the load-bearing one: it covers both helper
  clauses in both directions, and it is the test the sabotage note is written
  against.
- Edge cases worth having in the table: a zero fraction spelled with six digits
  (`.000000`), a zero fraction spelled with three (`.000`, decode side only,
  since encode cannot produce it), a one-digit non-zero fraction (`.5` -> six
  digits), and a fraction already at six digits (identity).
- Doctests on `to_json/1` cover the two emitted shapes, so the moduledoc's
  claim and the code cannot drift.

### Integration Tests:

None needed. This surface is corpus tooling, not the evaluator: nothing in
`test/predicator/integration/` reaches `Predicator.Conformance.Values`, and
`Predicator.evaluate/3` is unchanged. The end-to-end check that matters is the
corpus round trip through `mix corpus.generate`, which the freshness binding
test already runs on every gate.

### Manual Testing Steps:

1. In `iex -S mix`, encode `~U[2026-08-09 10:30:00.5Z]`,
   `~U[2026-08-09 10:30:00.000000Z]`, and `~U[2026-08-09 10:30:00Z]` and confirm
   exactly two distinct shapes come out.
2. Decode `%{"$type" => "datetime", "value" => "2026-08-09T10:30:00.000Z"}` and
   confirm the precision field is `{0, 0}`, i.e. the hand-authored path is
   closed.
3. Run the Phase 1 sabotage mutations, confirm red, revert.
4. After Phase 2, read `conformance/corpus/tier-7.json`'s new line as a sibling
   implementor would: the `lit` operand and the `expected_result` should agree
   on the six-digit form.

## References

- Source document: `docs/research/260811-px-qq6-tagged-datetime-precision.md`
- Upstream decision: `docs/research/260810-px-7t8-datetime-string-fractional-seconds.md`
- Its plan, for the form already landed in `Cast`:
  `docs/plans/260810-px-7t8-datetime-string-canonical-form.md`
- Sabotage-note class: `docs/research/260808-px-9ab-sabotage-notes.md`
- Related ADRs: `docs/adr/0003-the-elixir-implementation-leads-the-isa.md`
  (the corpus is the exported specification; a corpus diff is explained),
  `docs/adr/0011-casts-are-an-opcode.md` (the cast semantics the form rides on)
- Similar implementation: `lib/predicator/cast.ex:174-179`
- Bead: `px-qq6`

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] The sabotage mutations were actually run and confirmed red for the right
      reason, and the recorded failure text is the real one.
- [ ] `conformance/README.md`'s new paragraph reads correctly to someone
      implementing a sibling from that document alone - in particular the
      asymmetry between emitting and accepting.
- [ ] The restated `@doc` property is accurate: check by hand that
      `to_json(from_json(to_json(v))) == to_json(v)` is stated without
      exceptions and the structural form's one exception is named.
- [ ] The commit message and PR body say explicitly that the corpus was
      regenerated and deliberately did not move, and why (ADR-0003 obliges a
      corpus diff to be explained, and "there is no diff" is this phase's
      explanation).

**Implementation Note**: Use `mix quality --profile loop` between edits and the
full gate as the phase gate. In interactive execution, pause here for the human
to confirm the manual testing before moving to the next phase. In looped
(`--loop`) execution, this phase's Automated Verification gates advancement
automatically (via `/wurk:commit --auto`), and Manual Verification items are
deferred and surfaced once at the end instead of blocking here.

---

### Phase 2

- [ ] The generator accepted the authored `expected` without a mismatch error,
      confirming the authored form is what the real pipeline computes rather
      than something the author guessed.
- [ ] The corpus diff is exactly one added line plus the manifest's hash and
      count - nothing else moved.
- [ ] The commit message and PR body explain the corpus diff and what it pins
      (ADR-0003), and say that `corpus_hash` moved for an added case rather than
      for a changed expectation, so no sibling's existing expectation is
      invalidated.
- [ ] The case reads as pinning the *encoding*, not the `cast` opcode, to
      someone who finds it in `casts.json`.

**Implementation Note**: Use `mix quality --profile loop` between edits and the
full gate as the phase gate. In interactive execution, pause here for the human
to confirm the manual testing. In looped (`--loop`) execution, this phase's
Automated Verification gates advancement automatically, and Manual Verification
items are deferred and surfaced once at the end.

If the corpus diff turns out to be unwanted - the direction record records this
as the cheap fallback - dropping this phase entirely leaves every consequence of
Phase 1 intact, at the cost of leaving the six-digit half pinned only by the
Elixir suite.

---
