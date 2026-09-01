# ADR-0016: Predicator emits no telemetry; the event contract is reserved, not shipped

Status: accepted (2026-09-01, campaign-025; unqualified direction-agent verdict)

## Context

px-zv5 asks the question its sibling repos were each asked after statifier's
OpenTelemetry design landed (statifier-ex ADR-0062 and its `docs/opentelemetry.md`,
the st-cmq.2 note): does predicator emit its own `:telemetry` events for the
compile and evaluate paths, or does it stay silent because the caller already
observes the same work? The bead is explicit that silence is a legitimate
answer and that the defect would be leaving it unrecorded - a reader who finds
no events and no reason cannot tell a decision from an omission.

**Predicator emits nothing today, and holds no dependency that would let it.**
`telemetry` matches nothing under `lib/`, `test/`, or `mix.exs`; the dependency
list is seven dev-and-test entries and nothing else. So this is not a question
about removing a surface. It is a question about opening one.

**"No runtime dependencies" is a published property of this library, not an
incidental fact about it.** `README.md` states it in the installation section,
and `docs/adr/README.md` records that the policy was weighed for an ADR of its
own and declined only because the README already carried both the fact and the
reason. `:telemetry` is a runtime dependency: it is an application that has to
be started, and an emitting library cannot mark it `optional: true` and be done
- optional still puts it in the Hex dependency table a consumer reads, and it
buys that with a `Code.ensure_loaded?` guard at every emission site plus a
with-and-without matrix in the gate. That cost was already weighed once in this
family, against exactly this shape: statifier's `docs/opentelemetry.md` rejects
the in-library optional-module pattern as "the minority pattern" for the same
test-matrix and doc-surface reasons. The argument transfers, and lands harder
here, because predicator's dependency count is currently zero rather than
merely small.

**The work is already inside a span.** Every predicator call statifier makes -
`Statifier.Compiler.Expressions`, `Statifier.Evaluator`, `Statifier.EventData` -
runs inside an open `[:statifier, :session, :macrostep, :start]` /
`[..., :stop]` pair, and the bridge records everything that fires between those
two as a span event on the macrostep span. That design explicitly rejected
microstep-granular child spans as too chatty, and an expression evaluation is
finer-grained than a microstep: a selection round evaluates a guard per
candidate transition, and a macrostep runs many rounds. A predicator-level
event would be the chattiest thing in the family's telemetry stream, added
beneath the granularity the family already decided was too fine.

**Predicator does not hold the identity that would make such an event useful.**
The library knows an instruction list, an ISA version, and a span table mapping
instruction index to source location within one expression (ADR-0009). It does
not know a session id, a state id, a transition index, or a `cond_location` -
those are the caller's, held by the Machine under statifier-ex
`docs/observability.md`'s Constraint 3 ("the Machine retains locations and
identities"), and the bridge keys its span
correlation on `session_id`, which no predicator event could carry. An emitted
`[:predicator, :evaluate, :stop]` would therefore arrive at a handler as a
duration with nothing to attach it to, and making it attachable means the
bridge growing per-process bookkeeping it deliberately does not have.

**The metadata predicator would naturally reach for is the hazard, not the
payoff.** The obvious fields are the expression source and the evaluation
context: the first is chart vocabulary authored by whoever wrote the statechart,
and the second is host data - the same datamodel values the family's PII seam
exists to keep out of places that have no redaction discipline. statifier's own
design fixes the constraint that nothing puts unbounded datamodel values into
attributes by default. Predicator can honor that constraint, but only by
declining to emit the two fields that would have been the reason to emit at all,
which leaves a duration with no subject.

**The counterargument is real and is taken seriously here.** Guard evaluation
genuinely is a blind spot in the family's observability: `Statifier.Telemetry`'s
own moduledoc records that `cond_location` is never resolved because no effect
in the vocabulary is emitted from guard evaluation. Somebody watching a
statechart make a decision cannot currently see the condition that made it. But
that gap is on the side of the seam that has the identities, and closing it from
here would close it worse - a `[:predicator, :evaluate, ...]` event says a
duration elapsed, where the thing an operator wants is *which* transition's
guard evaluated to what, which only statifier can say. The fix belongs to
statifier's event contract under ADR-0040's amendment discipline, and this ADR
records it as the follow-up rather than absorbing it.

**Timings are obtainable today without an emitter.** `compile/1` and
`evaluate/3` are pure functions over values, with no process, no I/O, and no
supervision tree - a caller that wants the duration wraps the call in
`:telemetry.span/3` at its own call site, where it also has the identity to
put in the metadata. In-repo measurement is already covered: `benchee` is a dev
dependency for exactly this.

## Decision

**Predicator emits no `:telemetry` events, from the compile path or the
evaluate path, and takes no `:telemetry` dependency - not required, not
optional. The family's observability surface for expression work is the
caller's: statifier's `[:statifier, :session, ...]` contract (statifier-ex
ADR-0040) and the `opentelemetry_statifier` bridge over it (statifier-ex
ADR-0062).**

The decision is a no with a shape attached. Reversing it should be a decision
about *whether* to emit, not a re-derivation of what the events would be called,
so the contract a future emission would take is reserved here in four clauses.
Nothing below is implemented; all of it is what an implementation would be held
to.

1. **Span shape, two spans, no more.** `:telemetry.span/3`'s convention, giving
   `[:predicator, :compile, :start | :stop | :exception]` and
   `[:predicator, :evaluate, :start | :stop | :exception]`. Predicator has two
   phases, not a hierarchy; there is no third segment and no per-instruction or
   per-opcode event at any granularity.

2. **Measurements are the span convention and nothing else.** `system_time` on
   the start half; `duration` and `monotonic_time` on the stop half. No
   predicator-specific measurement: an instruction count is derivable from the
   compiled value the caller is already holding, and a measurement that
   duplicates a value the handler can read is a field to keep in sync for
   nothing.

3. **Metadata is bounded, and the unbounded fields are named as excluded.**
   Permitted: `instruction_count` (integer), `isa_version` (integer), `result`
   (`:ok | :error`), and `error_type` (the `Predicator.Errors` struct module on
   the error arm), plus `telemetry_metadata` - an opaque map the caller supplies
   through the options and predicator copies through without inspecting, which
   is how caller identity reaches the event. **The expression source, the
   context keys, the context values, and rendered error messages are never
   metadata**, on the datamodel-values constraint above; a caller that wants its
   expression identified passes an identifier of its own choosing in
   `telemetry_metadata`.

4. **Emission is opt-in per call, never a global switch.** Predicator's
   documented usage is compile-once-evaluate-many inside a hot loop
   (`docs/guides/embedding.md`), so an application-env flag puts an unbounded
   emission rate one config line away from a host that never asked for it. The
   opt-in rides the options the call already takes.

This ADR is superseded, not amended, if predicator ever emits: a decision to
open the surface is a new ADR that says so, per `docs/adr/README.md`'s
amendment discipline, and this one stays visible as the path taken.

## Consequences

- **Nothing under `lib/` changes.** The deliverable is the record. What this
  buys is that the next reader who greps for `telemetry`, finds nothing, and
  asks whether it was ever considered gets an answer with reasons instead of a
  gap - which is the whole of what px-zv5 asked for.

- **The zero-runtime-dependencies property keeps a second, specific defence.**
  The README states it; this ADR is the first time a concrete candidate
  dependency was named, weighed, and declined, so the property is now a decision
  under pressure rather than a fact that has never been tested.

- **Guard-evaluation blindness stays statifier's to close.** Whether
  `[:statifier, :session, ...]` grows an event carrying the guard's
  `cond_location`, its transition identity, and its boolean result is a
  statifier-ex decision under ADR-0040's amendment discipline, and that repo
  holds every field such an event needs. It is recorded here as the follow-up
  this ADR declines, not as work predicator owes.

- **A host that wants predicator timings today wraps the call**, and gets a
  better event than predicator could have emitted, because the wrapping site
  knows what the expression is for:

  ```elixir
  :telemetry.span([:my_app, :predicate], %{rule_id: rule.id}, fn ->
    {Predicator.evaluate(compiled, context), %{rule_id: rule.id}}
  end)
  ```

- **Reversal is cheap and additive.** Adding events is a minor release, not a
  major one: no existing return value or option changes shape, and the reserved
  contract above means the reversal conversation is about the dependency, which
  is the part that was actually hard.

- **No outward mirror note is owed.** px-zv5 carries `mirrors: st-cmq.2`, and
  st-cmq.2 is closed - merged to statifier-ex `main` via its PR #206, verified
  2026-09-01. Under ADR-0010 a closed bead is history and is left alone, so the
  reconciliation for this pair is recorded on the px- half only.
