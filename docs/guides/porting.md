# Porting Predicator

This guide is for someone implementing predicator's instruction set in another
runtime - a sibling to the Ruby and JavaScript implementations, or a new one.
Two artifacts bind you: [`docs/isa.md`](../isa.md) at the version you claim to
support, and the conformance corpus at the tiers you claim to pass. Those are
the only two things a sibling implementer has to read, and you are correct or
incorrect only against the version you declare, never against whatever this
repo shipped last week
([ADR-0003](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0003-the-elixir-implementation-leads-the-isa.md)).

The corpus lives in a git checkout of this repository, not in the hex
package - `mix.exs`'s package definition excludes `conformance/` deliberately,
because nothing an application does at runtime touches it. Work from a clone,
not a dependency.

## Pick the ISA version you are implementing

ISA versions are integers - v1, v2, v3 - independent of this library's
semver. A version's opcode set is the half-open interval
`[introduced, removed_in)`, and that set is fixed once minted: retiring an
opcode at a later version does not change what an earlier version was. That
means **declaring v1 or v2 claims `and`/`or`**, even though v3 retired them -
those two opcodes are still part of v1's and v2's whole set
(`docs/isa.md` section 1).

A sibling running behind the current ISA version is an expected, documented
state, not a defect
([ADR-0003](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0003-the-elixir-implementation-leads-the-isa.md)). See
[`docs/isa.md`](../isa.md) section 7 for the version-history table - which
opcodes each version introduced or retired, and which library release shipped
it.

## What the version obliges you to implement

Once you've picked a version, [`docs/isa.md`](../isa.md) section 4 is the
opcode table: implement every row in your version's set, per-opcode semantics
and error paths included (section 5).

A handful of execution-model rules live outside that table and are easy to
miss (`docs/isa.md` section 2):

- **Opcodes validate, they do not coerce.** There is no general truthiness
  rule; a boolean-expecting opcode handed a non-boolean is a
  `TypeMismatchError`.
- **"Falsy" at a jump means exactly `false` or `:undefined`**, and nothing
  else; "true" means exactly `true`.
- **Jumps are relative and forward-only.** The operand is a positive offset
  from the jump instruction's own index. There is no backward jump and no
  absolute jump in the ISA.
- **`:undefined` is a first-class value**, not an absence. Some opcodes
  propagate it, some reject it, and jumps treat it as falsy - section 5 says
  which, opcode by opcode.
- **A malformed operand is an unknown instruction, not a bad-operand error.**
  An out-of-range or wrong-typed operand - `["make_list", -1]`,
  `["compare", "FOO"]` - falls through to the catch-all clause and returns an
  `EvaluationError` with reason `"unknown_instruction"`.
- **Error types are normative; error messages are not.** Three error types
  exist - `EvaluationError`, `TypeMismatchError`, `UndefinedVariableError` -
  and a conforming implementation's own error for a given failure must map to
  one of these three. Word the message however reads naturally in your own
  idiom.

If your version's set includes `duration`, its output shape is also
normative: a map with the eight keys `years`, `months`, `weeks`, `days`,
`hours`, `minutes`, `seconds`, `milliseconds`, always present and defaulting
to `0`; the key set does not vary with the units an expression named
(`docs/isa.md` section 3). The conformance corpus's tagged-value JSON omits a
`milliseconds` of `0` as a compaction - an absent key decodes to `0` and does
not narrow this shape. The corpus checks the failure side of duration
cases the same way it checks every other error: `expected_error`'s `type` and
`reason` fields, never the message
([`conformance/README.md`](https://github.com/riddler/predicator-ex/blob/main/conformance/README.md),
"Error type and reason are normative; message is not").

Not required of you, per [`docs/isa.md`](../isa.md) section 6: surface syntax
(including the `=`/`==` grammar break), parse errors, the builtin function
set beyond what your claimed tier exercises, and backward jumps - none of
these exist in the ISA this document specifies.

Also not required of you: how a host registers a function or passes it
runtime state. The Elixir implementation's `Predicator.FunctionProvider`
behaviour and the context's `host` slot
([ADR-0014](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0014-functions-are-provided-by-modules.md))
are host-side plumbing for *this* implementation's embedding API, not part of
the instruction set - no opcode, corpus case, or conformance claim depends on
either existing. Adopt an equivalent in your own runtime, or don't; either is
correct, and on whatever schedule you choose
([ADR-0003](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0003-the-elixir-implementation-leads-the-isa.md)).

## Start with the evaluator surface

This is the load-bearing decision in the whole guide. The corpus exercises
two independent things a sibling implements
([`conformance/README.md`](https://github.com/riddler/predicator-ex/blob/main/conformance/README.md),
"The two surfaces"):

1. **The evaluator surface.** Run `instructions` (already-compiled) against
   `context`, and compare the result to `expected_result` or `expected_error`.
   **Every case in the corpus has an evaluator form.**
2. **The compiler surface.** Parse `source` and compare the emitted
   instructions, structurally, against `instructions`. Only cases where
   `source` is non-`null` have a compiler form - a `source: null` case is
   *absent from* the compiler surface's case set, not skipped by it. A runner
   scoped to the compiler surface filters to `source != null` before it
   starts and never reports the others at all, passing or failing.

**Implement the evaluator first.** It needs no lexer and no parser - you feed
it already-compiled instructions and a context - so it is reachable before
you have written a line of surface-syntax code. Tier 1 alone is a complete,
self-contained target - see `conformance/manifest.json` for the opcodes it
unlocks at your ISA version. A tier-1-only evaluator is a complete, green,
honest result, not a partial one.

## Run tier 1

Read [`conformance/manifest.json`](https://github.com/riddler/predicator-ex/blob/main/conformance/manifest.json)
first: it names each tier's file, case count, and - at the manifest's own
`isa_version` - the opcodes that tier unlocks. **Running tier N means running
every case in tiers 1 through N**, not tier N in isolation.

The mechanics:

- Cases are one JSON object per line in `conformance/corpus/tier-N.json`.
  Decode tagged values through the `$type` table
  ([`conformance/README.md`](https://github.com/riddler/predicator-ex/blob/main/conformance/README.md),
  "The tagged-value encoding") - `date`, `datetime`, `duration`, `undefined`;
  everything else decodes as itself.
- Compare an error case on `expected_error`'s `type` and `reason` fields
  only, never the message.
- Emit a report matching
  [`conformance/schema/report.json`](https://github.com/riddler/predicator-ex/blob/main/conformance/schema/report.json):
  `isa_version`, `corpus_hash`, `tier`, `surface`, and one `{id, result,
  reason}` per case, where `result` is exactly `"pass"` or `"fail"`.

**Never skip a case.** If a feature is not implemented yet, the honest report
entry is `{"result": "fail", "reason": "<feature> not implemented"}`, never
an absent entry - `report.json`'s `result` enum has no third value, so a
skip is not representable. This is affordable because of tiers: an
implementation that only supports tier 1 does not skip its way through
tiers 2-5, it simply runs `tier-1.json` alone.

[`conformance/RATCHET.md`](https://github.com/riddler/predicator-ex/blob/main/conformance/RATCHET.md)'s
reference-runner pseudocode is the worked example of all of this end to end -
read it rather than reimplementing the mechanics from scratch. Do not look
to this guide, or to `docs/isa.md`'s tier table, for a tier's opcode list:
`conformance/manifest.json`'s per-tier `opcodes` array is version-scoped and
is the live answer.

## Add the compiler surface

Once the evaluator is green at some tier, add the compiler surface at your own
pace: filter the same corpus to `source != null`, parse `source` with your
lexer and parser, and compare the emitted instruction list structurally
against `instructions`. The corpus never checks surface syntax, so `=` versus
`==` producing the same `["compare", "EQ"]` instruction is invisible here
([`conformance/README.md`](https://github.com/riddler/predicator-ex/blob/main/conformance/README.md),
`docs/isa.md` section 6).

The two surfaces climb on independent schedules. An evaluator conformant to
tier 5 with a compiler still at tier 1 is a coherent, reportable state, not a
contradiction
([`conformance/RATCHET.md`](https://github.com/riddler/predicator-ex/blob/main/conformance/RATCHET.md)).

## Record what you pass

Keep one registry file, covering both surfaces, in your own repository -
recommended path `conformance/registry.json`. Grow it only by
verify-then-add: run your reports, and the write step adds only cases that
just passed, refusing to write at all if an existing entry regressed. Nothing
hand-edits this file.

The registry pins itself to a `corpus_hash` and an `isa_version`, and its
entries are keyed on `(case_id, surface, tier)`. An entry whose
`(case_id, surface)` pair is not a member of that surface's case set in the
pinned corpus fails the run - never dropped, never silently skipped.

[`conformance/RATCHET.md`](https://github.com/riddler/predicator-ex/blob/main/conformance/RATCHET.md)
is the normative field list, encoding, and check-step definition; do not
expect this guide to restate the field tables.
[`conformance/examples/registry.example.json`](https://github.com/riddler/predicator-ex/blob/main/conformance/examples/registry.example.json)
is a real one to model your own after.

## What "conformant at tier N" claims

A claim is per surface, per tier, against one pinned corpus revision. Two
rules make it meaningful
([`conformance/RATCHET.md`](https://github.com/riddler/predicator-ex/blob/main/conformance/RATCHET.md),
the R1-R5 check step):

- **R5, completeness**: every case in tiers 1..N on the claimed surface has a
  registry entry.
- **R4, no regression**: every recorded pass still passes today, against the
  pinned corpus.

Two boundaries worth knowing when you read or write a claim:

- **Entries above the claimed tier are legal and are still ratchet-checked.**
  Recording tier-2 passes while claiming tier 1 is normal mid-climb behavior;
  R4 protects those entries even though R5 does not require them.
- **An empty `claims` array is a valid, passing registry** - an honest "here
  is what I pass, I am not asserting a tier yet."

And a claim of "conformant at tier N" says nothing about: surface syntax,
parse errors, the builtin function set beyond the tier-5 cases the corpus
happens to pin, ordering comparisons (`GT`/`LT`/`GTE`/`LTE`) between two maps,
clock- and RNG-dependent opcodes and functions (`relative_date`, `Date.now`,
`Math.random`), or the `on_unbound` evaluation option
([`conformance/README.md`](https://github.com/riddler/predicator-ex/blob/main/conformance/README.md),
"Known uncovered").
