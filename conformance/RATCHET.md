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

## Rule 2: one entry per line, sorted, never reflowed

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

A retired opcode does not change this. A case using an opcode retired at or
below the corpus's `isa_version` (`docs/isa.md` section 4, "Retired
opcodes"; [`conformance/README.md`](README.md)'s "Retired opcodes and their
cases") keeps its id and stays a member of the **evaluator** surface's case
set - its `expected_result`/`expected_error` is frozen data rather than a
live evaluation, but rule 1 does not distinguish frozen from computed, only
membership - and, being `source: null`, is absent from the **compiler**
surface's, exactly as any other `source: null` case is. Rule 1, the tier
check, and R5 completeness all continue to resolve its id unchanged. A
retirement moves `corpus_hash`, which is an ordinary pin refresh under "Corpus
drift under a pinned version" above, not a new failure mode - nothing about
the ratchet rules themselves changes.

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

## The reference runner

Small by design, and doubles as the worked example of consuming the corpus:

```text
run(surface, tier_n):
  manifest = parse_json(read("conformance/manifest.json"))
  cases    = []
  for t in manifest.tiers where t.tier <= tier_n:        # tiers are CUMULATIVE
    for line in read(t.file).split("\n") where line != "":
      cases.append(parse_json(line))

  if surface == "compiler":
    cases = cases.filter(c -> c.source != null)          # absent, not skipped

  results = []
  for c in cases:
    if surface == "evaluator":
      actual = my_evaluator.run(decode(c.instructions), decode(c.context))
      results.append(compare_value(c, actual))
    else:
      actual = my_compiler.compile(c.source)
      results.append(compare_instructions(c, actual))

  return {isa_version: my_isa_version, corpus_hash: manifest.corpus_hash,
          tier: tier_n, surface: surface, results: results}
```

The pieces that do not fit in the pseudocode itself: `decode` points at
[`conformance/README.md`](README.md)'s tagged-value table (`$type` of `date`,
`datetime`, `duration`, `undefined`; everything else decodes as itself). A
bare JSON `null` is part of that "everything else": it decodes as itself, to
predicator's null value, never to `:undefined` - a reference runner that maps
a JSON `null` to its own undefined sentinel disagrees with the corpus and must
not do so.
`compare_value` checks `expected_result` structurally, or - when the case
expects an error - `expected_error`'s `type` and `reason` fields, never the
human-readable message. `compare_instructions` compares the compiler's output
structurally against `c.instructions`.

Restate never-skip at the point it bites: **an unimplemented feature produces
`{"result": "fail", "reason": "<feature> not implemented"}`, never an absent
entry.** `report.json`'s enum makes any other choice unrepresentable, but the
runner author needs to be told what to do instead, not only what not to do.

## The check step

The CI-side counterpart, which writes nothing:

```text
check(registry, manifest, corpus):
  fail unless registry.corpus_hash == manifest.corpus_hash        # R1: the pin
  for e in registry.entries:
    fail unless (e.case_id, e.surface) in surface_case_set(corpus, e.surface)
    fail unless e.tier == corpus[e.case_id].tier                  # R2: rule 1
  fail unless reencode(registry) == read_bytes(registry_path)     # R3: rule 2
  reports = {s: run(s, max_tier_for(registry, s)) for s in surfaces_present}
  for e in registry.entries:
    fail unless reports[e.surface].result_for(e.case_id) == "pass"  # R4: no regression
  for cl in registry.claims:                                        # R5: completeness
    for c in surface_case_set(corpus, cl.surface) where c.tier <= cl.tier:
      fail unless (c.id, cl.surface) in registry.entries
```

Each check earns its line in the spec:

- **R1, the pin.** A `corpus_hash` mismatch is a **hard failure**, not a
  warning and not an auto-refresh. Every entry in the file is a claim about a
  specific corpus; if the corpus moved, the claims are unverified, and a
  ratchet of unverified claims is worth nothing. The remedy is to re-run
  verify-then-add, which - because it refuses to record a failing case and
  refuses to drop an existing entry - either produces a correctly re-pinned
  file or fails loudly naming what regressed. There is no path through this
  that silently shrinks.
- **R2** is rule 1 and its tier sibling, from above.
- **R3** is what makes rule 2 *enforced* rather than aspirational: re-encode
  the parsed registry per the normative encoding rules and byte-compare. A
  hand edit, a pretty-printer, or an editor that reindents on save is caught
  here, which is the only way "nothing hand-edits this file" is a fact rather
  than a hope.
- **R4** is the ratchet: every recorded pass must still pass, today.
- **R5** is what makes `claims` mean something. Without it a registry says
  only "these pass" and never "and that is all of tier N", so it cannot be a
  green/red signal on its own. With it, a sibling's CI is one command.

Two properties, stated explicitly so nobody reads R5 as stricter than it is:

- **Entries above the claimed tier are legal and are still ratchet-checked.**
  A sibling mid-climb records tier-2 passes while claiming tier 1; R4
  protects them, R5 ignores them.
- **An empty `claims` array is a valid, passing registry.** Per ADR-0003 a
  sibling adopts on a boundary of its own choosing; a registry with entries
  and no claims is an honest "here is what I pass, I am not asserting a tier
  yet", and this rule must not turn that into a failure.
