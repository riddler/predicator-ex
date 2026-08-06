# ADR-0003: The Elixir implementation leads the ISA

Status: accepted (2026-08-06)

Amends the consequences of [ADR-0001](0001-keep-the-stack-vm-revise-the-instruction-set.md).
It does not supersede it: ADR-0001's decision stands unchanged.

## Context

ADR-0001 settled the execution model and, in the same breath, gave sibling
parity a standing it cannot support. Two sentences do the damage. The decision
section says:

> Cross-language interchange is affirmed as a real goal, not a legacy
> obligation.

and the last consequence says:

> The tree-walker option is closed for as long as interchange is a goal.

Read together they make the Ruby and JavaScript implementations load-bearing
for decisions taken in this repo. The second sentence is the clearer error: it
makes the execution model conditional on interchange, when the reason the
tree-walker is closed has nothing to do with siblings. statifier holds
expressions as `{:compiled, instructions, source}`, built at machine-build time
and evaluated many times afterwards. It needs a serializable compiled form.
That requirement survives with no siblings at all, and it is the reason the
stack VM stays.

The first sentence is subtler. Interchange *is* a real goal - nothing here
retreats from it. What ADR-0001 left implicit, and what the workflow built on
top of it then made explicit in about twenty places, is that an instruction-set
change is "not a local decision" and that the siblings "have to match". That
inverts the actual dependency. The siblings are downstream consumers of a
format this library defines; treating them as an upstream constraint means the
Elixir implementation cannot take a change its own consumers need until two
other codebases, on other schedules, are ready.

The cost of that framing is already visible. Parity has been partial since
before ADR-0001 - objects, durations, and strict equality all postdate the
siblings - and ADR-0001 added four more opcodes they do not implement. So the
constraint is not actually being honored; it is being apologized for. `README.md`'s
"Cross-Language Siblings" section and `docs/architecture.md`'s equivalent both
read as an account of how far behind the siblings have fallen, which is the
tone a repo adopts when it believes it has failed an obligation.

What was really being protected was never sibling parity. It was **stored
artifacts**: a compiled instruction list, written to a database months ago, must
not start producing different answers because this library moved. ADR-0001
conflated the two and paid for the conflation with a blanket promise never to
invalidate anything - `["and"]` and `["or"]` stay accepted forever, source
positions were deliberately kept out of the instruction format, and every
feature section in `docs/architecture.md` carries an "ISA-neutral, siblings need
nothing" note.

The thing that separates the two concerns is versioning. Without a version
stamp, "we changed the ISA" and "your stored artifact silently runs wrong" are
the same event, so the only safe policy is to change nothing. With one, they are
different events: an artifact or a consumer that has not caught up **detects and
refuses** rather than mis-running. Once refusal is possible, freezing the format
stops being the mechanism that provides safety, and the ISA is free to move.

## Decision

**The Elixir implementation is the reference implementation of predicator's
instruction set. The ISA moves when this library needs it to.** Sibling parity
is a downstream obligation, not an upstream constraint, and it is not a gate on
any change made here.

Six parts:

- **The ISA is versioned.** There is a current ISA version this build emits and
  can run, and an instruction list can be asked what version it requires -
  `Predicator.isa_version/0` and `Predicator.Instructions.required_isa/1`
  (`px-35i.3`). A consumer or sibling handed a list it is too old to run learns
  that up front, from a value, instead of failing partway through a run in
  whatever way its dispatch happens to fail. `docs/isa.md` (`px-35i.2`) is the
  specification each version names, and the conformance corpus (`px-35i.4`) is
  the executable form of it.

- **An opcode's semantics never change under its own name.** A change to what an
  opcode *does* is a new opcode name at a new ISA version, never a redefinition
  of the existing one. This is the rule that makes the version computable: a scan
  of the opcode names in an instruction list is a *sound* answer to "what version
  does this list require", not a best-effort one, because there is no case where
  the same names mean something different than they used to. Adding an operand
  form or widening an accepted type is a new version but not a new name; changing
  the answer an existing form produces is a new name.

- **ISA versions are integers, independent of the library's version.** v1, v2,
  v3, with no correspondence to semver here - ISA v2 has been landing across
  3.7.0 and 3.8.0, and a sibling declaring support for v2 should not have to know
  which Elixir release shipped it. What the library's own version does owe is the
  cost of the change: an **additive** ISA version, new opcodes only and every
  existing instruction list still valid, is a minor release, while **retiring** an
  opcode is what invalidates stored artifacts and takes a major release plus the
  upgrade path below.

- **Siblings adopt on a version boundary.** The Ruby and JavaScript
  implementations declare an ISA version they support and conform to it. They do
  not track this repo continuously and are not expected to. **A sibling behind
  the current ISA version is an expected, documented state - not a defect, not a
  bug report, and not a release blocker here.** The version each sibling
  supports is a fact to be published by that sibling, in its own repository, and
  not a gap to be apologized for here. This repo publishes two things and does
  not maintain a support matrix: the spec at each version, and the corpus that
  makes a sibling's claim verifiable by running it. `docs/architecture.md` names
  each sibling's declared version as a dated snapshot pointing at the sibling as
  the authority; a table maintained here would be the parity-deficit framing
  growing back in a new shape, and would go stale in a way this repo cannot
  detect.

- **Stored-artifact compatibility is a separate and stronger guarantee.** A
  compiled instruction list that was valid when it was written keeps producing
  the same answer, or is refused with a message naming the version it needs. It
  is never silently mis-run. That guarantee is delivered by the version stamp
  plus an **explicit upgrade path** - a function that rewrites an old list into
  current form, run once by a consumer who has stored artifacts - rather than by
  accepting every historical opcode forever. Retiring an opcode is permitted at
  a major version when an upgrade path exists for it (`px-tbv.9` is the first
  case: `["and"]` and `["or"]`).

- **The tree-walker stays closed, for an independent reason.**
  compile-to-instructions remains the one execution path because statifier needs
  a serializable compiled artifact, not because interchange is a goal. This
  reason does not depend on the siblings existing. Reopening the tree-walker
  still means superseding ADR-0001, and this ADR does not weaken that.

### What this decision does and does not change about the instruction set

**This decision does not change the instruction set.** No opcode is added,
removed, renamed, or given different semantics here. An instruction list valid
before this ADR is valid after it, and a sibling that conformed before still
conforms.

What it changes is *governance*: who decides the ISA moves (this repo), what
gets published when it does (a version, a spec entry, a corpus tier), and what a
sibling is obliged to do about it (adopt at a boundary of its own choosing).
Adding versioning is itself a change *around* the format, not *to* it: because an
opcode's semantics never move under its own name, a bare instruction list already
carries its required version implicitly, and the wire format stays a plain JSON
array. Whether an envelope value *additionally* carries the version alongside the
span table is an API question about `compile_with_spans/1`, left to `px-35i.5`,
and it is not needed to make the version knowable.

So: nothing in this ADR binds the Ruby and JavaScript siblings. What binds them
is `docs/isa.md` at the version they claim to support, and the conformance
corpus at the tiers they claim to pass. Those are the only two artifacts a
sibling implementer has to read, and a sibling is correct or incorrect only
against the version it declares - never against whatever this repo shipped last
week.

## Consequences

- **ADR-0001's decision is untouched; two of its consequences are amended.**
  "Cross-language interchange is affirmed as a real goal" stands as a goal but
  is demoted from a constraint: it no longer authorizes blocking a change here
  on sibling readiness. "The tree-walker option is closed for as long as
  interchange is a goal" is replaced by "the tree-walker option is closed
  because a serializable compiled artifact is required" - same conclusion,
  a premise that does not evaporate if interchange ever does.
- ADR-0001's consequence that "the Ruby and JavaScript siblings gain three
  opcodes to implement if they want parity" is restated rather than repealed:
  the opcodes are ISA v2, the siblings implement them when they adopt v2
  (`px-35i.6`, `px-35i.7`), and until then they are v1 implementations, which is
  a complete and honest description of their state.
- ADR-0001's promise that "a stored instruction list is never invalidated by
  this revision" is kept, but is now discharged by the version stamp and an
  upgrade path rather than by permanent acceptance. `px-tbv.9` may retire
  `["and"]` and `["or"]` in 4.0 on that basis - the artifact half of ADR-0001's
  reason for keeping them survives and must be served by an upgrade function;
  the sibling half is retired by this ADR. Retirement is the case that takes a
  major release, per the numbering rule above, and 4.0 is one.
- **The framing in `README.md` ("Cross-Language Siblings") and
  `docs/architecture.md` is now wrong and gets rewritten.** Both describe a
  parity deficit. They should describe a versioned contract: here is the ISA
  version this library emits, here is what each sibling supports, here is where
  the spec lives. Same facts, correct standing.
- **The `.claude/` workflow encodes the repealed constraint and gets reframed**
  (`px-im6`). Roughly twenty sites across the skills, the research agents, and
  `CLAUDE.md` say some version of "an instruction change is not a local
  decision, the siblings have to match". The replacement question is mechanical,
  not deliberative: does this bump the ISA version, is it stamped, and does a
  stored artifact need a migration note.
- **Versioning is now load-bearing, so it must exist before the freedom is
  used.** This ADR is safe only in company with `px-35i.2` (the spec),
  `px-35i.3` (the stamp and the check), and `px-35i.4` (the corpus). An ISA
  change taken before those land has the pre-ADR failure mode - a stored
  artifact that mis-runs with no way to detect it - and the license this ADR
  grants should not be drawn on until they do.
- The ISA gains a real cost it did not have: every change to it now owes a
  version bump, a `docs/isa.md` entry, a corpus tier assignment, and a migration
  note if stored artifacts are affected. That is the trade. The old regime's
  cost was a veto held by two other repositories; this one's is paperwork, paid
  by the change that incurs it.
- Nothing here obliges the siblings to do anything on any schedule. A sibling
  that never adopts v2 is a v1 implementation indefinitely, and the corpus tiers
  make that a green run against a named subset rather than a wall of failures.
- Reversing this - making sibling parity a gate on Elixir-side ISA changes
  again - means superseding this ADR, not adding an exception beside it.
