# Predicator conformance corpus

A checked-in, language-neutral JSON corpus that lets a Ruby, JavaScript, or
any other sibling implementation verify its compiler and evaluator against
predicator's instruction set (the ISA, [`docs/isa.md`](../docs/isa.md))
without an Elixir toolchain. This document is the contract: read it before
writing a runner or adding a case.

Per [ADR-0003](../docs/adr/0003-the-elixir-implementation-leads-the-isa.md),
this corpus is the *executable* form of `docs/isa.md`: the spec states the
rules in prose, and every case here is one instance the Elixir reference
implementation actually produces.

## What this is not

- **Not a surface syntax test.** The corpus never checks parsing. `=` and `==`
  both compile to `["compare", "EQ"]`, so a source-level test would encode a
  divergence that does not exist at the instruction level
  (`docs/isa.md` section 6). If two expressions compile to the same
  instructions, this corpus makes no promise about which surface syntax
  produced them.
- **Not a parse-error test.** Every authored case's `source`, when present,
  compiles successfully. A source string that fails to compile is a defect in
  this corpus, not a case - `mix corpus.generate` refuses to ship one.
- **Not exhaustive.** It is curated to the mechanical coverage rule described
  below, not to a target case count. See "Known uncovered" for what is
  deliberately absent and why.

## The two surfaces

Each case exercises up to two independent things a sibling implements:

1. **The evaluator.** Run `instructions` (already-compiled, tagged-value
   encoded) against `context`, and compare the result to `expected_result`
   (on success) or `expected_error` (on failure). Every case in the corpus has
   an evaluator form.
2. **The compiler.** Parse `source` and compare the emitted instructions,
   structurally, against `instructions`. Only cases where `source` is
   non-`null` have a compiler form.

A case with `"source": null` is an **evaluator-only** case - most commonly the
legacy `["and"]`/`["or"]` opcodes ([ADR-0001](../docs/adr/0001-keep-the-stack-vm-revise-the-instruction-set.md)),
which the compiler never emits and which
[ADR-0001](../docs/adr/0001-keep-the-stack-vm-revise-the-instruction-set.md)
originally said the evaluator must still run **forever** for stored artifacts
and v1 siblings.
[ADR-0003](../docs/adr/0003-the-elixir-implementation-leads-the-isa.md)
amended that "forever" - retirement at a version boundary, with an upgrade
path, is permitted; see "Retired opcodes and their cases" below for what that
means for a case's evaluator form. The surface rule itself does not change: a
`source: null` case is **absent from the compiler surface's case set** - it
is not a case the compiler surface skips, because there is nothing here for
the compiler to do. A runner scoped to the compiler surface simply filters to
`source != null` before it starts; it never reports these ids at all, passing
or failing.

## Retired opcodes and their cases

Retirement mints a new ISA version (`docs/isa.md` section 1); a version's
opcode set is a half-open interval, `Predicator.Instructions.opcode_set/1`,
not the full opcode table. A case using an opcode retired at or below the
corpus's `isa_version` cannot be run by this build's reference evaluator -
there is no `execute_instruction/2` clause left for it (`docs/isa.md` section
4, "Retired opcodes") - so it takes a different path than every other case
here:

- It keeps its id, its tier, and its place in the tier file. Nothing removes
  it, because a sibling claiming an earlier version still needs it.
- Its `expected_result` or `expected_error` is **frozen** from the authored
  case rather than recomputed - the generator takes the authored `expected`
  verbatim instead of running `instructions` through
  `Predicator.evaluate/3`.
- It carries the `retired` feature tag, so a runner can select it out
  mechanically.
- It is necessarily `source: null`: the compiler never emits a retired
  opcode, so a retired case is always evaluator-only (see "The two surfaces"
  above).

What a runner does with a `retired`-tagged case depends on the version it
claims: a runner targeting the current version filters `retired` out along
with anything else it does not support; a runner claiming an earlier version -
one at or after the opcode's `isa` and before its `removed_in` - runs them
normally, and that is what makes the earlier-version claim verifiable at all.

This also changes what `conformance/manifest.json`'s per-tier `opcodes` array
means: it lists what that tier unlocks **at the manifest's `isa_version`**,
not every opcode that has ever belonged to the tier. A retired opcode leaves
that array once its `removed_in` version is reached, while its case(s) stay
in the tier file regardless - the array is a version-scoped opcode listing,
the file is not.

This is a version boundary, not an exclusion: it changes *when* an opcode is
required, not whether it is ever required. "Opcodes excluded from the
coverage rule" below is a distinct, narrower mechanism - a permanent
exclusion for opcodes no case can ever pin an expected value for - and is not
where a retired opcode goes.

## The tagged-value encoding

JSON's own type system - string, number, boolean, `null`, array, object -
covers most of predicator's value domain directly. Four things do not fit,
and are carried as a JSON object with a `$type` key:

| Predicator value | JSON encoding |
|---|---|
| `Date` | `{"$type": "date", "value": "2026-08-06"}` (ISO 8601 date) |
| `DateTime` | `{"$type": "datetime", "value": "2026-08-06T12:00:00Z"}` (ISO 8601, UTC) |
| duration | `{"$type": "duration", "value": {"years":0,"months":0,"weeks":0,"days":3,"hours":0,"minutes":0,"seconds":0}}` |
| `:undefined` | `{"$type": "undefined"}` |

Everything else - integer, float, string, boolean, list, plain object -
decodes to itself; a plain JSON object with no `$type` key is a predicator
map.

**The duration shape is normative** ([`docs/isa.md` section 3](../docs/isa.md)):
all seven keys - `years`, `months`, `weeks`, `days`, `hours`, `minutes`,
`seconds` - are always present, defaulting to `0`. An eighth key,
`milliseconds`, is present **only** when a `ms`-family unit produced a
non-zero value; its absence means zero, the same as an absent value for any
of the other seven. A decoder should default a missing `milliseconds` to `0`
rather than treating its absence as an error.

This encoding applies everywhere a predicator value appears in a case:
`context`, `expected_result`, and inside `instructions` itself - a `lit`
instruction pushing a `Date` carries a tagged operand, not a raw one, because
JSON has no way to distinguish `"2026-08-06"` the date from `"2026-08-06"` the
string without it.

**How to hand-decode a duration case.** Take
`conformance/corpus/tier-4.json`'s `durations/milliseconds-key-present-only-when-used`
case: `instructions` is `[["duration",[[500,"ms"]]]]`, and `expected_result`
is `{"$type":"duration","value":{"years":0,"months":0,"weeks":0,"days":0,"hours":0,"minutes":0,"seconds":0,"milliseconds":500}}`.
Read the `$type` key first - `"duration"` - then read `value` as the seven-plus-one
key map: every unit here is `0` except `milliseconds: 500`. No parser, no
unit-string table, no ambiguity - the map is the whole answer.

## Error type and reason are normative; message is not

`expected_error` carries exactly two fields:

```json
{"type": "TypeMismatchError", "reason": "add"}
```

- **`type`** is one of predicator's three error struct names -
  `EvaluationError`, `TypeMismatchError`, `UndefinedVariableError`
  (`docs/isa.md` section 2) - and is normative: a conforming implementation's
  own error type for the same failure must map to the same one of these three
  categories.
- **`reason`** is a structured token - `"division_by_zero"`,
  `"unbound_variable"`, the failing opcode's operation name - and is
  **also normative**. `docs/isa.md` section 5 enumerates these reasons as part
  of the spec, so a sibling reproduces the token, in its own idiom (a symbol,
  an error code, a constant), rather than inventing its own vocabulary.
- **The human-readable message is never carried** in this corpus. Word it
  however reads naturally in the runner's own language; nothing here checks
  it.

If a sibling's runtime genuinely cannot produce a matching `reason` token for
some case, that is worth raising as an issue against this repository rather
than silently diverging - the token is meant to be reachable from any
reasonable implementation of the documented behavior.

## Tiers

Cases are grouped into files by tier, `conformance/corpus/tier-N.json`, one
JSON object per line. Tier is a property of the **opcodes** a case's
`instructions` use, not of the case's value types - a date comparison is tier
1 (`compare`) even though it needs `Date` support (`docs/isa.md` section 4).
`conformance/manifest.json` lists, for each tier, the opcodes it *unlocks* and
its case count.

**Running tier N means running every file for tiers 1 through N**, not tier N
in isolation - an implementation that supports only `core` (tier 1) runs only
`tier-1.json` and stops there for a green result. An implementation claiming
tier 3 (`access`) runs `tier-1.json`, `tier-2.json`, and `tier-3.json`. Tier 1
alone is a complete, self-contained target: nothing in it requires an opcode
outside `lit`, `load`, `compare`, `not`, `unary_bang`, `unary_minus`,
`jump_if_falsy_or_pop`, `jump_if_true_or_pop`, `and`, `or`.

**Feature tags** (`features`, e.g. `comparison`, `strict_equality`,
`durations`, `legacy_logical`) are a finer, cross-tier cut - useful for a
runner that wants to report what it lacks in those terms, or that has taken an
advanced feature early. They are informational, not a second grouping a
runner is required to honor.

## Never skip

A runner reports every case in the tiers (and, for the compiler surface, the
`source`-bearing cases) it claims to run as either `"pass"` or `"fail"` -
never anything else. `conformance/schema/report.json`'s per-case `result`
field is an enum of exactly `["pass", "fail"]`; there is no third value to
emit, so a report containing one fails schema validation in any language,
before a human even reads it.

The reason is blunt: a skipped case reads as a pass in every summary anyone
actually looks at (a percentage, a checkmark, a green CI badge), silently
inflating a claim of conformance. If a runner has not implemented some
feature yet, the honest report is `"fail"` with a `reason` naming the gap -
`"duration parsing not implemented"` is a legitimate, useful `reason` string.
This is affordable precisely because of tiers: an implementation that only
supports tier 1 does not need to skip its way through tiers 2-5's cases -
it runs `tier-1.json` alone, which is a complete, green, honest result.

## Recording what you pass

This document is the runner contract: what a sibling's runner reads and how it
compares. What a runner's output feeds into is a separate document -
[`conformance/RATCHET.md`](RATCHET.md) specifies the registry format a sibling
uses to record which cases it passes, on which surface, against which corpus
version, and grow that record only by verify-then-add.

## How to add a case, without any Elixir

1. Edit (or create) a file in `conformance/cases/*.json` - a JSON array of
   authored cases. See `conformance/schema/case.json` for the field-by-field
   shape: `id` (required, stable forever once shipped), `source` **or**
   `instructions` (exactly one), `context`, `expected`, and optionally `tier`
   and `features` as assertions the real pipeline must agree with.
2. Validate the file against `conformance/schema/case.json` with any JSON
   Schema (draft 2020-12) tool in any language.
3. Open a pull request. You do not run `mix corpus.generate` yourself if you
   have no Elixir toolchain - a maintainer or CI regenerates
   `conformance/corpus/*.json` and `conformance/manifest.json` from your
   authored file and commits the result in the same PR. If your authored
   `expected` disagrees with what the real compiler and evaluator compute,
   generation fails loudly, naming your case and both values, rather than
   silently overwriting your assertion - that disagreement is either a bug in
   predicator or a misreading of `docs/isa.md`, and either way it gets sorted
   out in review, not silently.

## Known uncovered

### Opcodes excluded from the coverage rule

`test/predicator/conformance/opcode_coverage_test.exs` asserts that every
opcode in `Predicator.Instructions.opcodes/0` appears in at least one case,
**except** the opcode named below - and a test binds that exclusion list to
this exact section, so removing the exclusion in one place without the other
fails the suite.

- `relative_date` - its result depends on the system clock at evaluation time
  (`docs/isa.md` section 5: it calls `DateTime.utc_now/0`), so no case can pin
  an expected value. A clock-injection seam would make this coverable and is
  its own future issue if wanted.

### Functions excluded from the coverage rule

`mix corpus.coverage`'s tier-5 section marks these builtins as documented
exclusions - an inline note, not a bare `corpus: 0` row - for the same reason
`relative_date` above is excluded: no case can pin an expected value.
`Predicator.Conformance.Coverage.documented_exclusion_functions/0` is the one
place this list is declared in code; a test binds it to this exact section,
the same way `opcode_coverage_test.exs` binds `relative_date` to the section
above.

- `Date.now` - depends on the system clock, same root cause as
  `relative_date` (`docs/isa.md` section 5).
- `Math.random` - depends on the RNG (`docs/isa.md` section 5).

### Also out of scope

These are not opcode-coverage exclusions - the opcodes involved are covered
in their ordinary form - but specific shapes this corpus does not exercise,
structurally rather than as an exclusion list: ordering
comparisons (`GT`/`LT`/`GTE`/`LTE`, not `EQ`/`NE`/`STRICT_EQ`/`STRICT_NE`)
between two plain maps (`docs/isa.md` section 5 - the Elixir reference orders
these by an internal term order a sibling should not try to reproduce), and
the `on_unbound` evaluation option (`docs/isa.md` section 2 - not part of the
ISA; every case in this corpus runs under the default option).
