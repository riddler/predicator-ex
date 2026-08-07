# The sibling conformance ratchet

The registry format each implementation - `impl/rb`, `impl/ts`, and any future
port - uses to record which corpus cases it passes, on which surface, against
which corpus version. This document is the contract those registries are
written against; it does not ship a registry itself. See
[`conformance/README.md`](README.md) for the corpus this registry references,
and [`docs/isa.md`](../docs/isa.md) for the instruction set the corpus is the
executable form of.

## The registry file

One file per implementation, covering **both surfaces**. Not mandated at a
particular path, but the recommended location is `conformance/registry.json`
inside the sibling's own repository - so `impl/rb/conformance/registry.json`
and `impl/ts/conformance/registry.json`.

**One file, not one per surface.** Rule 1 below matches an entry against the
corpus on the pair `(case_id, surface)`, and a single `corpus_hash` pin has to
apply to whatever the file claims. Two files invite the two surfaces to pin
different `corpus_hash` values - a compiler registry verified against one
corpus revision and an evaluator registry verified against another - which is
exactly the incoherence the pin exists to prevent.

## Fields

Top level, all required:

| Field | Type | Meaning |
|---|---|---|
| `claims` | array | Zero or more `{surface, tier}` objects, at most one per surface. "Every case in tiers 1..N on this surface has an entry." May be empty. |
| `corpus_hash` | string, `^sha256:[0-9a-f]{64}$` | The `manifest.json` `corpus_hash` every entry was verified against. The pin. |
| `entries` | array | The ratchet itself: one `{case_id, surface, tier}` per verified pass. |
| `implementation` | string | Self-identifying name, e.g. `"predicator-rb"`. Diagnostic only - a registry pasted into an issue here says what it is. |
| `isa_version` | integer >= 1 | The manifest's `isa_version` at pin time. |

Entry object, all required:

| Field | Type | Meaning |
|---|---|---|
| `case_id` | string, the corpus id pattern | The corpus case. Ids are stable forever once shipped (`schema/case.json`), which is what makes them a durable key. |
| `surface` | `"evaluator"` \| `"compiler"` | The same enum as `schema/report.json`. |
| `tier` | integer >= 1 | The case's tier, copied from the corpus. Redundant on purpose - see below. |

**Why `tier` is on the entry even though the corpus already knows it.** It
makes the file readable and the ordering self-evident without joining against
the corpus, and - more usefully - it is a second, free consistency check: if a
case's tier moves in a future corpus, the entry's stale `tier` disagrees and
the run fails, naming the case. A field that can only ever be redundant or
wrong is a field that catches drift.

**Why the pin is both `corpus_hash` and `isa_version`.** `corpus_hash` is the
load-bearing one: it is exact identity, and it subsumes `isa_version` (a
corpus regenerated at a new ISA version necessarily hashes differently).
`isa_version` is carried anyway so a human reading the registry, or a
sibling's README quoting one field of it, learns which ISA the claim is
against without fetching the manifest. That asymmetry is deliberate: nothing
should key a rule on `isa_version` that `corpus_hash` already enforces more
tightly.

## Grouping and ordering

The grouping is produced by the ordering, not by nesting - there is no
per-tier object or per-tier array, because nested structure is exactly what a
pretty-printer reflows and what makes a one-line change into a whole-file
diff.

`entries` is sorted by:

1. `surface`, ascending by codepoint - so `"compiler"` before `"evaluator"`
2. then `tier`, ascending
3. then `case_id`, ascending by codepoint

`claims` is sorted by `surface`, ascending by codepoint.

**Why surface is the outermost key.** The two surfaces are independent
capabilities climbed on independent schedules - an evaluator can be
conformant to tier 5 while the compiler is still at tier 1. Surface-first
makes the file two contiguous blocks - "here is what my evaluator passes,
here is what my compiler passes" - each internally grouped by tier, so
ratcheting in a whole tier on one surface is a single contiguous insertion.
Tier-first ordering was considered and rejected: it interleaves the two
independent climbs, so a surface's progress is never visible as a block and a
tier's worth of new entries scatters through the file.

## Encoding

Normative, and binding on the **writer** only - a reader just parses JSON:

- UTF-8, LF line endings, exactly one trailing newline.
- Top-level keys in codepoint order: `claims`, `corpus_hash`, `entries`,
  `implementation`, `isa_version`.
- **No indentation anywhere.** Matching `conformance/corpus/tier-N.json`,
  which is already written this way.
- Each element of `claims` and of `entries` occupies **exactly one line**,
  encoded as canonical JSON: object keys in codepoint order, no whitespace
  after `:` or `,`.
- The array brackets and the top-level scalars occupy their own lines.

The literal shape:

```json
{
"claims": [
{"surface":"compiler","tier":1},
{"surface":"evaluator","tier":3}
],
"corpus_hash": "sha256:9b3a6b0709f9346294d8466c4cf9c60f5d7437df665dd6f4bcca4474b45d85ae",
"entries": [
{"case_id":"comparison/eq-string-true","surface":"compiler","tier":1},
{"case_id":"comparison/gt-int-boundary","surface":"compiler","tier":1},
{"case_id":"legacy/and-true-true","surface":"evaluator","tier":1},
{"case_id":"comparison/eq-string-true","surface":"evaluator","tier":1}
],
"implementation": "predicator-rb",
"isa_version": 2
}
```

This is ordinary, valid JSON that any stdlib parser reads. What the rules buy
is that **ratcheting one case in on one surface is a one-line insertion
diff**, and that two implementers ratcheting concurrently produce diffs that
merge instead of conflicting on a reflowed array.

This sounds fussy and is not: a pretty-printer that reflows the array turns
every ratchet commit into an unreviewable blob - and an unreviewable ratchet
commit is a ratchet nobody reviews, which is the same as not having one.

## Rule 1: an unmatched entry fails the run

**A registry entry whose `(case_id, surface)` pair is not a member of that
surface's case set in the pinned corpus FAILS the run.** Never dropped, never
warned about, never silently skipped.

The surface case sets, restated from [`conformance/README.md`](README.md) so
this rule is self-contained:

- **evaluator**: every case in the corpus.
- **compiler**: every case with `source != null`. A `source: null` case is
  *absent from* this set, not skipped by it.

Three distinct things this catches, all worth writing down:

1. **The statifier reason** (ADR-0006): dropping an unmatched entry silently
   shrinks the ratchet, which is the one thing a ratchet exists to prevent. A
   ratchet that quietly forgets what it used to pass is a ratchet with no
   teeth.
2. **Corpus drift under a pinned version**: a case renamed or removed
   upstream surfaces here, as a failure naming the id, rather than as a slow
   leak.
3. **A surface claim with no surface**: a `compiler` entry for a
   `source: null` case claims a capability that does not exist. Matching on
   the pair rather than the id is what makes this detectable at all - and it
   is the reason the registry cannot be a flat list of ids.

**The tier check is a sibling of rule 1**: an entry whose `tier` disagrees
with the pinned corpus's tier for that case FAILS, same handling, same
reasoning.

## Rule 3: grown only by verify-then-add

**Nothing hand-edits the registry.** The only input to the writing step is a
runner report; there is no "add case X" command that takes an id. The
property that makes the file trustworthy is exactly that: every line in it
was produced by a run that observed a pass.

The step (naming is the sibling's; the semantics are not):

1. Read `conformance/manifest.json`; take `corpus_hash` and `isa_version`.
2. Run the runner for each surface being ratcheted, at the tier being
   attempted, producing report(s) conforming to
   [`conformance/schema/report.json`](schema/report.json).
3. Abort if any report's `corpus_hash` differs from the manifest's - the
   report describes a different corpus than the one on disk.
4. Candidate set = `{(id, surface) : result == "pass"}` over all reports.
5. **Refuse to write** if any *existing* registry entry is absent from the
   candidate set. That is a regression, and the step exits non-zero naming
   every such pair. The step never removes an entry - this is the ratchet's
   teeth, and the reason "verify-then-add" is not "regenerate".
6. New entries = existing union candidates. Write with the encoding above,
   `corpus_hash` and `isa_version` from the manifest, `claims` as the caller
   asserts (and see the completeness check the reference runner section
   defines, which will refuse a claim the entries do not support).
