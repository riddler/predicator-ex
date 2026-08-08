# ADR-0009: The compiled envelope carries the position table

Status: accepted (2026-08-08)

## Context

`Predicator.compile/1` returns `{:ok, instructions}`. Its two position-mode
siblings return a three-element tuple: `compile_with_positions/1` gives
`{:ok, instructions, position_table}` and `compile_with_spans/1` gives
`{:ok, instructions, span_table}`. The table is a plain map from a 0-based
instruction index to the source location of the AST node that emitted that
instruction, and `Predicator.evaluate/3` takes it back as the `:positions`
option to put `:position` and `:span` on runtime errors.

ADR-0001 chose that shape and said why:

> The instruction format itself is unchanged, so interchange and stored
> artifacts are unaffected; the side table is an Elixir-side companion value.

Two things about that sentence have moved. The first is its motive: the
companion-value shape was defensive, protecting an interchange guarantee that
ADR-0003 has since demoted from a constraint to a goal. The second is that the
sentence is about the *instruction format*, and it stays true under every option
below - nothing here proposes putting a position into an instruction. So
ADR-0001 does not decide this; it only rules out the one design nobody is
proposing.

ADR-0003 removed the other reason an envelope might have been wanted. The ISA
version is computable from a bare instruction list, because an opcode's
semantics never change under its own name, so `Instructions.required_isa/1` is a
sound answer and no envelope is needed to carry a version. That leaves this
decision to be made on span merits alone.

**The cost of the companion-value shape is entirely on consumers, and it is a
silent one.** A three-element tuple makes the instruction list and its table two
values that a caller has to keep together by hand, across whatever boundary the
caller stores or passes them over. Nothing forces the pairing and nothing
detects its loss. A caller that keeps the instructions and drops the table gets
a working evaluation with `position: nil` on every runtime error - not a crash,
not a warning, just diagnostics that quietly stopped saying where. That is the
failure mode the position work exists to prevent, and the shape of the return
value is what invites it. The `:positions` option compounds it: re-attaching the
table is a keyword the caller must remember to pass, and forgetting it looks
exactly like never having compiled with positions in the first place.

**The countervailing cost is API churn.** `compile/1` returning a bare list is a
genuinely good API and is not in question. But an envelope is a breaking change
to both position-mode functions, and the two are not equally expensive:

- `compile_with_spans/1` has **never shipped**. It is under `## [Unreleased]` in
  `CHANGELOG.md`, targeting 4.0. Changing its shape costs no released consumer
  anything.
- `compile_with_positions/1` shipped in 3.7.0 (2026-08-05), so changing it is a
  real break against a released function - a one-line fix at each call site, in
  a release that is already taking the `=` grammar break (ADR-0002).

The known-consumer picture is the same one ADR-0002 surveyed: statifier is the
only known consumer outside this repo's suite, and it holds expressions as
`{:compiled, instructions, source}`, built once and evaluated many times. That
shape is itself an ad-hoc envelope, hand-rolled by a consumer because the
library did not offer one.

## Decision

**A compiled program with source locations is one value, not two.
`Predicator.compile_with_positions/1` and `Predicator.compile_with_spans/1`
return `{:ok, %Predicator.Compiled{}}`, and `Predicator.evaluate/3` accepts that
struct directly, threading its table without the caller re-attaching it.
`Predicator.compile/1` and `Predicator.compile!/1` are untouched and keep
returning a bare instruction list.**

Five parts:

- **The envelope has two fields: `instructions` and `positions`.** `positions`
  holds a `t:Predicator.Types.position_table/0` or a
  `t:Predicator.Types.span_table/0`, whichever mode compiled it. One field, not
  two, because that is already how the rest of the pipeline treats them:
  `evaluate/3`'s `:positions` option accepts either, `Evaluator` reads either
  without knowing which, and `Errors.put_position/2` discriminates a `nil`, a
  point, and a span at the point of use. A second field would introduce a
  distinction at the top of the pipeline that nothing below it makes.

- **The envelope does not carry the ISA version.** ADR-0003 makes the version
  computable from the instruction list, and `Instructions.required_isa/1` is the
  single authoritative answer. A stored field would be a cached copy of a derived
  fact, and a cached copy can be wrong - an envelope round-tripped through a
  consumer's own storage, or built from a list the consumer edited, would carry a
  version claim that no longer describes its instructions. Convenience is not
  worth a field that can lie about the one thing the version stamp exists to make
  trustworthy. A caller who wants the version calls `required_isa/1` on
  `compiled.instructions`.

- **The envelope is an in-memory Elixir value and is not a wire format.** What a
  consumer serializes and stores is `compiled.instructions` - a bare JSON array,
  exactly as before, with no version and no positions in it. Spans are offsets
  into a source string; they are meaningless to a reader that does not also hold
  that string, and putting them on the wire would be the thing ADR-0001 kept out
  of the instruction format, arriving by a side door. The envelope's job is to
  survive the trip from `compile` to `evaluate` inside one Elixir process tree,
  which is the trip on which the table is currently being dropped.

- **`compile/1` stays a bare list, deliberately.** The envelope is not a
  general-purpose wrapper being introduced for uniformity's sake; it exists
  because there is a *second* value that has to travel with the first. Where
  there is no second value there is no envelope, and `compile/1` remains the
  short path that returns the thing you serialize.

- **Both position-mode functions change together.** Leaving
  `compile_with_positions/1` on a three-element tuple while
  `compile_with_spans/1` returns a struct would make two functions that are
  documented as siblings, tested as siblings, and consumed through the same
  `:positions` option disagree about their return shape, for no reason other than
  which of them happened to ship first. 4.0 is the release where that costs one
  line per call site; every later release charges more for the same fix.

### What this decision does and does not change about the instruction set

**This decision does not move the ISA. The ISA version stays at 3.** No opcode is
added, removed, renamed, or given different semantics; no instruction gains an
element; the wire format stays a plain JSON array of instructions. An instruction
list compiled before this decision runs identically after it, and a stored
artifact needs no migration - `compiled.instructions` is byte-identical to what
`compile/1` emits for the same source, which is an invariant the suite already
asserts.

**The Ruby and JavaScript siblings owe nothing.** Per ADR-0003 the obligation a
change creates is measured in ISA versions, `docs/isa.md` entries, and corpus
tiers; this change produces none of those. A sibling that conformed to ISA v3
before this ADR conforms to ISA v3 after it. `Predicator.Compiled` is an Elixir
struct with no cross-language counterpart, and a sibling that wants the same
ergonomics may invent its own shape or not at all.

The migration this ADR does create is an **Elixir API migration**, which is a
different and much smaller thing than a stored-artifact migration. It is written
out below.

## Consequences

- **Migration for `compile_with_positions/1` callers (4.0, breaking).**
  `{:ok, instructions, positions} = Predicator.compile_with_positions(src)`
  becomes `{:ok, compiled} = Predicator.compile_with_positions(src)`, with
  `compiled.instructions` and `compiled.positions` holding what the second and
  third tuple elements held. A caller that then evaluated with
  `Predicator.evaluate(instructions, ctx, positions: positions)` can drop the
  option entirely and call `Predicator.evaluate(compiled, ctx)`. The
  `:positions` option itself is **not** removed: it remains the way an
  instruction-list caller who reconstructed a table from elsewhere attaches it.
- **Migration for `compile_with_spans/1` callers: none in practice.** The
  function is unreleased, so its shape change lands before any released consumer
  can have depended on it. It is listed in the changelog under Added, in its new
  shape, rather than under Changed.
- **`compile/1` and `compile!/1` are unchanged**, and so is everything that
  consumes their output. A caller who never asked for positions sees nothing
  different, which is the majority of the surface.
- **The `## [Unreleased]` CHANGELOG entry reads, under Changed:**
  "`Predicator.compile_with_positions/1` now returns
  `{:ok, %Predicator.Compiled{}}` instead of
  `{:ok, instructions, position_table}`. The envelope carries the instruction
  list and its source-location table as one value, so the table cannot be
  silently dropped between compilation and evaluation;
  `Predicator.evaluate/3` accepts a `%Predicator.Compiled{}` directly and
  threads the table itself. Read `compiled.instructions` and
  `compiled.positions` for the old tuple elements; `evaluate/3`'s `:positions`
  option still works for a bare instruction list. `Predicator.compile/1` and
  `Predicator.compile!/1` are unchanged and still return a bare instruction
  list, which remains what a consumer serializes and stores. No instruction
  changed and the ISA stays at version 3, so stored artifacts need no
  migration." The unreleased `Predicator.compile_with_spans/1` entry under
  Added is rewritten in the new shape rather than given a Changed entry of its
  own.
- **Storage advice becomes explicit and has to stay that way.** `README.md` and
  `docs/architecture.md` gain the sentence that a consumer persists
  `compiled.instructions`, not the struct. Without it the envelope invites
  exactly the mistake it was built to prevent, in mirror image: a consumer that
  serializes the whole struct writes source offsets into a stored artifact where
  they will outlive the source they index into.
- **The silent-loss failure mode does not disappear, it moves and shrinks.** A
  consumer who deliberately unwraps the envelope, stores the bare list, and
  evaluates that later still gets `position: nil`, and correctly so - the source
  is gone. What the envelope removes is losing the table *by accident, while
  still holding everything needed to keep it*.
- **`Predicator.Compiled` becomes a public struct and therefore a compatibility
  surface**, subject to the same `@doc`/`@spec` and versioning obligations as
  the rest of the façade. Adding a field later is additive; changing the meaning
  of `positions` is not.
- **Later entry points inherit the shape rather than reinventing it.**
  `Predicator.execute/2` (`px-tbv.2`) and any future compile-a-program path
  should return or accept the envelope rather than growing a fourth tuple
  element, which is a decision this ADR pre-empts rather than one those beads
  re-argue.
- Reverting to a companion value means superseding this ADR, not adding a
  tuple-returning function beside it.

### Open questions left to the implementation

Recorded rather than settled; none of them block the implementation.

- **Should the envelope also carry `source`?** statifier's own
  `{:compiled, instructions, source}` keeps it, and a span is only renderable as
  an underline by a holder of the string it indexes into - so an envelope with
  spans and without source is not quite self-sufficient. It is excluded here
  because it changes the value's size class and its privacy profile (the source
  is user-authored text, which a caller may not want retained), and because no
  current call site needs it. If a consumer turns up that does, it is an
  additive field.
- **Does `Predicator.Compiled` want a public constructor** (`new/2`) for a
  consumer who stored a bare list and wants to re-attach a table it kept
  separately? Probably yes, and it is cheap, but nothing in this repo needs it
  yet and a struct literal is available in the meantime.
- **Should `evaluate/3` reject a `%Compiled{}` combined with an explicit
  `positions:` option**, or let the option win? Rejecting is the safer reading of
  ADR-0004 (errors are values, and a contradictory call is a caller bug worth
  naming); letting it win is the more permissive one. Left to the implementation
  bead, which should pick one and document it.
