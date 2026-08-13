# What the ISA says to a consumer that stores instruction lists as plain JSON

Bead: px-a2w (split out of px-ocp planning,
`260812-px-ocp-undefined-literal.md`)
Date: 2026-08-13
Decision: **option (a), with option (c)'s content stated as its scope limit
and option (b) rejected.** `docs/isa.md` section 3 gains a subsection that
names the four operand types plain JSON cannot round-trip, says the ISA
defines no envelope and that choosing one is the consumer's call, and points
at the corpus tagged-value encoding as the one to reach for. **No ISA version
bump** - nothing is added to the value domain, no opcode changes, no operand
form widens. **No code changes**, in `lib/` or in tests.

This is a documentation call, not an architectural one: the decision it hangs
off - that the wire format stays a plain JSON array and that the corpus is
the ISA's executable form - is already
[ADR-0003](../adr/0003-the-elixir-implementation-leads-the-isa.md), and the
"persist the instructions, not the struct" advice is already
[ADR-0009](../adr/0009-the-compiled-envelope-carries-the-position-table.md)
and `Predicator.Compiled`'s moduledoc. `docs/adr/README.md`'s third corollary
sends a call this narrow to `docs/research/`, named after the bead. The one
option that *would* have been ADR-shaped, (b), is the one being rejected, and
declining to grow a public API is not itself a new architectural decision -
it is the existing ones holding.

## The question

`docs/isa.md` section 2 says the wire format is a flat list of JSON arrays and
"nothing else is in the wire format". Section 3 says the value domain includes
`Date`, `DateTime`, duration, and `:undefined`. Section 3 then hands the
question of how those cross a language boundary to the conformance corpus and
says nothing more.

That leaves a real reader unanswered. A consumer holding
`Predicator.compile/1`'s output and writing it to a database column as plain
JSON has a document telling it the artifact is a plain JSON array and a value
domain four of whose members do not survive the trip. Nothing tells it that,
and nothing tells it what to do instead.

## Ground truth: what actually happens, and how quietly

Elixir's native `JSON` encodes every one of the four without complaint. Run
against this build:

```
JSON.encode!(["lit", :undefined])                    -> ["lit","undefined"]
JSON.encode!(["lit", ~D[2026-08-06]])                -> ["lit","2026-08-06"]
JSON.encode!(["lit", ~U[2026-08-06T12:00:00Z]])      -> ["lit","2026-08-06T12:00:00Z"]
JSON.encode!(["lit", %{years: 0, days: 3, ...}])     -> ["lit",{"years":0,"days":3,...}]
```

Each output is a *valid* instruction. Each decodes to a different value than
the one that was stored: three strings and a map, all four of them values the
ISA's domain already contains, so nothing downstream has any way to notice.
The program keeps running; it runs a different program. `["lit", :undefined]`
becomes `["lit", "undefined"]`, and the boundness test `x === undefined` that
px-ocp's literal compiles to becomes a string comparison that is always
`false`.

The important property is the asymmetry: **encoding succeeds, decoding is
lossy, and no step in between errors.** This is not a case a consumer
discovers from a stack trace.

## Ground truth: nothing in this repo is affected

- `lib/` contains no serializer and no deserializer for instruction lists.
  `Predicator.Compiled` deliberately carries none
  (`lib/predicator/compiled.ex`, "What to store"), and no module under
  `lib/predicator/` outside `lib/predicator/conformance/` encodes or decodes
  a value to JSON.
- The conformance corpus is unaffected, because it already solved this. Its
  tagged-value encoding (`conformance/README.md`, "The tagged-value
  encoding"; `lib/predicator/conformance/values.ex`) carries exactly these
  four as `{"$type": ...}` objects, and the README already states that the
  encoding applies "inside `instructions` itself - a `lit` instruction
  pushing a `Date` carries a tagged operand, not a raw one, because JSON has
  no way to distinguish `"2026-08-06"` the date from `"2026-08-06"` the
  string without it".

So the gap is not a defect anywhere in the tree. It is a missing sentence in
the specification, and the sentence's whole job is to stop a consumer from
rediscovering the corpus's problem the hard way.

## Ground truth: this predates `:undefined` by four ISA versions

`Date`, `DateTime`, and duration have been in the value domain since v1.
px-ocp added a *spelling* for an operand `lit` already admitted, and
`docs/isa.md` section 6 already records that the ISA does not move for it. So
`:undefined` neither creates this gap nor worsens it - it made a
four-year-old rough edge visible during planning, which is why px-ocp filed
it out rather than widening into it.

That matters for how the note is written: it is a statement about the value
domain, belonging in section 3 beside the domain itself, not a note attached
to `lit` or to the `undefined` literal.

## Weighing the exits

**(b) Promote the tagged-value encoding into a supported serialization API.**
Rejected, on four counts.

1. It contradicts `mix.exs`. `Predicator.Conformance` is excluded from the
   published package three separate ways (`files:`,
   `exclude_patterns:`, and the corpus tree's absence), with a long comment
   giving the reason: nothing an application does at runtime touches it, and
   the audience that does works from a git checkout. A test guards the
   invariant that nothing under `lib/` outside those directories references
   the namespace. Making the codec public means undoing all of that, and
   `area:build` is exclusive, so it is not a change that rides along with
   anything.
2. It creates a second wire format the ISA would then owe a version to.
   Today the tagged encoding is corpus apparatus: it can be revised by
   regenerating the corpus, as px-qq6 did to the `datetime` fraction on
   2026-08-11. As a public API it becomes a stored-artifact format under
   ADR-0003's stored-artifact guarantee, so the next px-qq6 stops being a
   regeneration and becomes a migration. That is a large, permanent
   obligation bought for a problem that is one sentence of guidance.
3. It is the wrong layer. ADR-0003 is explicit that "the wire format stays a
   plain JSON array". An envelope wrapping predicator values is a *container*
   concern, and the consumers who have one - statifier holds expressions as
   `{:compiled, instructions, source}` - already have a container of their
   own choosing to put it in.
4. Nobody has asked for it. The bead was filed from planning, not from a
   report. Standing up an API on a hypothetical is what the ADR index's "a
   rule that explains itself needs no ADR" test warns against, in code form.

**(c) Declare it entirely a consumer concern and say so.** Rejected as a
*complete* answer, kept as half of one. The envelope genuinely is the
consumer's - the ISA cannot pick one, because a consumer storing to Postgres
`jsonb`, to a column of source text, or to an Erlang term binary needs three
different answers, and only the first has the problem at all. But "your
problem" alone leaves the reader exactly where they started, having now been
told there is a hazard and nothing about it. A specification that knows the
four members of its own value domain that break, and knows a worked encoding
for them sitting in the same repository, and says only "not our concern", is
withholding rather than scoping.

**(a) A section 3 note.** Chosen. It costs one subsection, it changes no
code, it moves no version, and it says the true thing: here are the four,
here is why it is silent, the envelope is yours, and here is one that already
works if you want it. Option (c)'s content survives inside it as the scope
limit - the ISA defines no envelope and is not going to - rather than as the
whole answer.

## What the note says, and what it deliberately does not

It says four things:

1. Which types are affected - `Date`, `DateTime`, duration, `:undefined` -
   and what each collides with on decode (three with a string, one with a
   plain map).
2. That the failure is silent in both directions: the encode succeeds and the
   decode yields a valid instruction.
3. That the ISA defines no envelope, and that whether to use one is the
   consumer's decision.
4. Two things that work: the corpus's tagged-value encoding, pointed at
   rather than restated, and persisting the *source* and recompiling on load,
   which sidesteps the question and is already `Predicator.Compiled`'s advice
   for getting positions back.

It does **not** make the tagged encoding normative for consumers. The corpus
README stays the specification of that encoding for the corpus, exactly as it
is today; the ISA recommends it, which is a different verb. If a consumer
adopts it, it inherits the corpus's own caveat - a genuine predicator map
containing a literal `"$type"` key is ambiguous with the tag namespace, which
is why `Values.to_json/1` rejects one rather than emitting a tag.

It also does not touch section 2's wire-format sentence. "Nothing else is in
the wire format" remains exactly true: an envelope is something a consumer
wraps *around* the wire format, not something added to it.

## Version: the ISA does not move

No opcode is added, removed, renamed, or given different semantics. No
operand form is added and no accepted type is widened - the four types were
already in section 3's domain, which is the whole reason the gap is old. The
opcode table and the version-history table are untouched, so
`test/predicator/isa_sync_test.exs` has nothing to react to.
`conformance/manifest.json` is not regenerated and its `isa_version` stays
`6`. Under section 1's rules this is not a version-bumping change of any
kind; it is prose about a domain that already existed.

## What was changed

- `docs/isa.md` - section 3 gains the subsection "Crossing a plain-JSON
  boundary"; section 6 gains a bullet naming a serialization envelope as
  something the ISA does not define, pointing back at it.
- `conformance/README.md` - one sentence at the end of the tagged-value
  encoding section noting that `docs/isa.md` section 3 now recommends the
  encoding to consumers too, and that this does not make it normative outside
  the corpus.
- `CHANGELOG.md` - an entry under `## [Unreleased]` / `### Documentation`.
- This document.

Nothing under `lib/` or `test/`.

## Open questions, recorded rather than blocked

- **Should a future release ship a supported serialization API after all?**
  Not decided here beyond "not now, and not by promoting the corpus codec".
  If a consumer reports the loss in the wild, the shape worth weighing first
  is a small public codec that is *not* the corpus's - so the corpus can keep
  being regenerated freely - and that would be ADR-shaped, since it would
  create a second versioned artifact under ADR-0003's stored-artifact
  guarantee. No bead filed: filing one would put a hypothetical in the queue,
  and this paragraph is the record.
- **Should the siblings' porting guidance repeat the note?**
  `docs/guides/porting.md` was deliberately left alone - px-ocp declined to
  touch it on the grounds that porting guidance is about the ISA and
  `on_unbound`. A sibling implementer reads `docs/isa.md` by definition
  (ADR-0003 names it and the corpus as the only two artifacts they must
  read), so the note reaches them where they already are.
