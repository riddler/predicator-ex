# The fractional-seconds form of the corpus's tagged `datetime` encoding

Bead: px-qq6 (discovered from px-7t8)
Date: 2026-08-11
Decision: **the tagged encoding adopts the same canonical form
`datetime::string` carries** - the fraction omitted entirely when the
sub-second component is zero, exactly six digits when it is not - and
`Predicator.Conformance.Values` canonicalizes on **both** encode and decode.
The round-trip property is **deliberately restated**: `from_json(to_json(v))`
returns the *canonical* value, which is `v` itself for every value the
encoding can express. **No ISA version bump**, and no `docs/isa.md` change at
all.

This is the second half of px-7t8, deliberately deferred there
(`260810-px-7t8-datetime-string-fractional-seconds.md`, "Deliberately out of
scope" and "Open questions"). It is one clause of one private codec plus the
sentence in `conformance/README.md` that documents it, and the decision it
hangs off - that the corpus is the ISA's executable form and this repo leads
it - is already [ADR-0003](../adr/0003-the-elixir-implementation-leads-the-isa.md).
`docs/adr/README.md`'s third corollary sends a call this narrow to
`docs/research/`, named after the bead that prompted it, and px-7t8 - the
strictly larger decision, which moved a normative sentence of `docs/isa.md`
section 5 - went here on the same reasoning. An ADR would add a file and a
maintenance obligation for a rule that explains itself once stated.

## The question

`lib/predicator/conformance/values.ex:71` encodes a `DateTime` with
`DateTime.to_iso8601/1`, so the fractional-seconds field of the emitted string
is whatever the Elixir struct's `microsecond` precision field happens to be.
That is the same underspecification px-7t8 settled for `datetime::string`, in
an artifact that crosses a language boundary: `conformance/corpus/*.json` is
read by Ruby and JavaScript siblings that have no such field.

It could not simply adopt px-7t8's form, because `to_json/1`'s `@doc`
(`values.ex:93`) promises `from_json(to_json(v)) == {:ok, v}` for every value
`to_json/1` accepts, and `test/predicator/conformance/values_test.exs:34`
asserts it over an enumerated list. Elixir's precision field has no
representation in the tagged encoding, so once the encoding drops a zero
fraction, `~U[...00.000000Z]` and `~U[...00Z]` encode identically and one of
them cannot come back structurally equal.

px-7t8 named two exits: canonicalize on decode as well and restate the
property, or leave the encoding precision-driven and document that it is *not*
the `datetime::string` form.

## Ground truth: what the codec emits today

Measured against this branch (`mix run`, the codec and the evaluator as they
stand):

```text
~U[2026-08-09 10:30:00Z]            -> "2026-08-09T10:30:00Z"
~U[2026-08-09 10:30:00.000000Z]     -> "2026-08-09T10:30:00.000000Z"
~U[2026-08-09 10:30:00.5Z]          -> "2026-08-09T10:30:00.5Z"
~U[2026-08-09 10:30:00.500000Z]     -> "2026-08-09T10:30:00.500000Z"
```

Four spellings, three of them reachable from one instant. The second and third
are the interesting ones: `.000000` is a fraction that is not there, and `.5`
is a one-digit fraction that neither a JavaScript `Date` (always three) nor
Ruby's `Time#iso8601(n)` (a fixed `n`, no trimming) can produce - exactly the
variable-digit-count hazard px-7t8 pinned six digits to remove.

The decisive measurement is that the *same instant* already encodes two ways
depending on which Elixir code path produced it:

```text
#2026-08-09T10:30:00Z#::datetime      -> {"$type":"datetime","value":"2026-08-09T10:30:00Z"}
"2026-08-09T10:30:00Z"::datetime      -> {"$type":"datetime","value":"2026-08-09T10:30:00.000000Z"}
"2026-08-09"::date::datetime          -> {"$type":"datetime","value":"2026-08-09T00:00:00Z"}
#2026-08-09T10:30:00.5Z#              -> {"$type":"datetime","value":"2026-08-09T10:30:00.5Z"}
```

The literal path carries the lexer's precision; the string-parse path goes
through `Cast.normalize_to_utc/1`, which forces precision 6 to stay
tz-database-free (`lib/predicator/cast.ex:165`). Nothing about the *value*
differs - `DateTime.compare/2` says `:eq` - and yet the exported bytes differ.

This is not hypothetical, and it has already cost the corpus a case.
`lib/predicator/conformance/generator.ex:410` compares an authored
`expected.result` against the computed one with `==` **on the encoded JSON**,
so an author who writes the obvious `{"$type":"datetime","value":"2026-08-09T10:30:00Z"}`
for `"2026-08-09T10:30:00Z"::datetime` gets a generation failure, and the only
way to satisfy the generator is to write the six zeros an Elixir struct field
put there. `conformance/cases/casts.json:155` is the scar: the
`string::datetime` case is chained on to `::date` specifically so it never has
to assert a datetime value.

## Ground truth: the round trip is exact today, for every precision

`from_json/1` parses with `DateTime.from_iso8601/1`, which sets the precision
field from the digits it read. Encode prints the precision, decode reads it
back, so the property holds exactly for all four spellings above - measured,
all four round-trip `true`. Whatever is chosen here, the property being
weakened is a real one that holds today, not a documented aspiration.

## Ground truth: nothing on disk moves

Every `datetime` value in the generated corpus today is zero-fraction. The
eight distinct encodings across `conformance/corpus/tier-{1,2,4,7}.json`:

```text
2024-01-15T00:00:00Z  2024-01-15T01:00:00Z  2024-01-15T08:00:00Z
2024-01-15T10:00:00Z  2024-01-15T11:00:00Z  2024-01-15T12:00:00Z
2026-08-09T00:00:00Z  2026-08-09T10:30:00Z
```

Zero of them carry a fraction, and the same is true of every authored
`conformance/cases/*.json` expectation and of `conformance/README.md:107`'s
documented example. So canonicalizing is byte-identical on the artifact as it
stands: no corpus expectation moves, and `manifest.json`'s `corpus_hash` does
not change unless a new case is added.

That matters more here than it did for px-7t8, because this artifact **has
shipped**. The corpus went out in 4.0.0 (`CHANGELOG.md:219`), not under
`## [Unreleased]`, so a sibling may already be running against these files.
The chosen form changes nothing a sibling has seen; it pins a field none of
them has yet had occasion to exercise.

## Weighing the exits

**Exit 2 - leave the encoding precision-driven and document that.** Rejected.
It is the cheapest change (a paragraph, no code), and it is the only one that
keeps the round-trip property verbatim, which is a genuine attraction: the
property is the codec's whole contract and weakening it is not free. But it
asks `conformance/README.md` to write down that the `value` string of a
cross-language artifact is a function of an Elixir struct field, and then to
tell a Ruby or JavaScript sibling to reproduce it. It cannot: neither host has
a precision field, and no sibling can predict from the *instant* whether this
corpus will say `10:30:00Z` or `10:30:00.000000Z` - it depends on which
predicator-ex code path produced the value, which is not part of any
specification. The result is a documented non-specification. It also leaves
the generator's `==` comparison as an authoring trap in perpetuity, and leaves
`casts.json:155`'s dodge permanent. And it forces two datetime string formats
on every sibling: the `::string` cast's canonical one and the encoding's
Elixir-shaped one, for the same value type.

The corpus is an exported specification (ADR-0003); a field of it that only
one host language can express is precisely the cost this repo is not supposed
to export.

**A third option - canonicalize on encode only.** Considered, and it is nearly
sufficient. If encode emits only the two canonical shapes, then decode already
returns a canonical value for every string encode produces (`...Z` parses to
precision `{0, 0}`; six digits parse to precision 6), so `from_json(to_json(v))`
already lands in the canonical domain without touching `from_json/1`. It is
rejected as incomplete rather than wrong: `from_json/1` is also fed
*hand-authored* JSON - `decode_context/1` at `generator.ex:315` and
`synthesize_outcome/1` at `:233` - where nothing stops a case from writing
`"...00.000Z"`. Decoding that to a precision-3 `DateTime` puts a non-canonical
value into the evaluator's context and back out through the encoder, which is
how the two-encodings-per-instant problem gets back in through the authoring
door. Canonicalizing on decode makes the codec's value domain closed under
both directions and costs the same two-clause helper.

**Exit 1 is chosen**: canonicalize on encode and on decode, and restate the
property. It makes the encoding a function of the instant alone, with exactly
two shapes; it matches every byte already on disk; it makes the obvious
authored expectation the correct one; and it leaves a sibling with one
datetime format to implement rather than two. The precedent is in the codec
already: the `duration` tag omits `milliseconds` when it is zero rather than
exporting predicator's own always-present key, and `conformance/README.md`
tells decoders to default the absent key to `0`. Normalizing a host-shaped
detail out of the encoding is what this codec does; datetime is the one place
it did not.

## The restated property, and what the test does

`canonical/1` is the identity on every value in the encoding's image, and on
`DateTime` it sets the precision field to `{0, 0}` when the microsecond
component is zero and to `{us, 6}` when it is not. The property becomes:

> `from_json(to_json(v)) == {:ok, canonical(v)}` for every value `to_json/1`
> accepts, and `canonical(v) == v` for every value except a `DateTime` whose
> precision field disagrees with its own sub-second component. Equivalently,
> and this is the form worth stating in the `@doc` because it has no
> exceptions: `to_json(from_json(to_json(v))) == to_json(v)` - the encoding is
> canonical, and encoding is stable under a round trip.

`test/predicator/conformance/values_test.exs` changes in three places, none of
them a deletion:

1. `@round_trip_values` (line 11) keeps `~U[2026-08-06T12:00:00Z]`, which is
   already canonical, and **gains** `~U[2026-08-06T12:00:00.500000Z]` so the
   six-digit shape is covered by the exact-equality test too. The existing
   `describe` block and its assertion are unchanged; its title gains "for
   every canonical value".
2. A **new** test asserts the canonicalization, as a table of non-canonical
   input to canonical output:
   `~U[...12:00:00.000000Z] -> ~U[...12:00:00Z]` and
   `~U[...12:00:00.5Z] -> ~U[...12:00:00.500000Z]`, checking both that
   `DateTime.compare/2` is `:eq` and that the precision field is the canonical
   one. This is the test that would go red if the helper were dropped, so it
   is the one that actually binds the decision.
3. A new decode test: `from_json(%{"$type" => "datetime", "value" => "...00.000Z"})`
   yields precision `{0, 0}`, and `"...00.5Z"` yields `{500_000, 6}` - the
   hand-authored path exit 1 exists to close.

The "to_json/1 - tagged encoding shape" `DateTime` test (line 56) is unchanged
and gains a sibling asserting the six-digit shape.

## Relationship to `datetime::string`: the same form, deliberately

`docs/isa.md` section 5's normative bullet and this encoding now describe the
same lexical form, and that is the point rather than a coincidence. They are
different layers - section 5 governs a *string value* the `cast` opcode
produces, and this governs the `value` field of a tagged object in a corpus
file - so nothing forced them to agree, and exit 2 was the option in which
they did not.

They are made to agree because a sibling implementor writes one datetime
formatter and one datetime parser either way, and because the alternative
requires explaining, in a document a sibling reads to *implement* predicator,
that predicator has two ISO-8601 datetime forms distinguished only by which
file they appear in. Six digits when non-zero and none when zero is reachable
in one line in all three host languages - Ruby's `iso8601` and `iso8601(6)`,
JavaScript's `toISOString()` with a stripped `.000` or a padded three digits,
Elixir's precision field - which px-7t8 established and this inherits without
re-arguing.

One asymmetry is worth writing down in `conformance/README.md`, because it is
the same shape as the `milliseconds` guidance already there: **emit only the
two canonical shapes, but accept any ISO-8601 fraction on decode.** A decoder
that rejects `...00.000Z` is wrong; the encoding never produces it, but a
hand-authored case may contain it, and the instant is unambiguous.

## Version: the ISA does not move, and section 5 is not touched

**ISA stays v4. `docs/isa.md` gets no edit at all - not section 5, not section
7 - and `Predicator.isa_version/0` does not move.** The reasoning parallels
px-7t8's but is strictly stronger at the first step, so it is worth reasoning
rather than copying:

1. Section 1's "an opcode's semantics never change under its own name" bites
   on *specified* behavior of an *opcode*. This changes neither. No opcode's
   inputs, outputs, or error behavior differ; `cast` produces exactly the
   `DateTime` it produced before, and only the corpus's serialization of it
   changes shape. px-7t8 had to argue that an unspecified field of a specified
   cast was not a semantic change; here there is no cast in the picture.
2. Section 3 hands this question away explicitly: "How these values cross a
   language boundary in the conformance corpus's tagged-value JSON encoding is
   `px-35i.4`'s concern, not restated here." The tagged encoding is documented
   in `conformance/README.md`, and section 8 names that document the ISA's
   executable form rather than part of the ISA's prose. Pinning a field of a
   document the ISA delegates to cannot move the ISA's version without
   inverting that delegation.
3. Section 7 records the general allowance in any case - "A version's
   semantics can also be refined in a later release without a new opcode and
   without a new ISA version" - and, as a backstop, no shipped byte changes:
   every datetime already in the corpus is zero-fraction and encodes
   identically before and after.

The corollary is that `manifest.json`'s `isa_version` stays `4`, and
`corpus_hash` moves only if the implementation adds a case (see the open
question).

## Consequences for the implementation

**Yes, the Elixir implementation changes**, in one module. Files a follow-on
should expect to touch:

- `lib/predicator/conformance/values.ex` - the behavioral change, in three
  spots: the `to_json/1` `%DateTime{}` clause (line 70) canonicalizes the
  precision field before `DateTime.to_iso8601/1`; the `from_json/1`
  `"datetime"` clause (line 122) canonicalizes what `DateTime.from_iso8601/1`
  returns; and a private two-clause `canonicalize_microsecond/1` identical to
  `lib/predicator/cast.ex:174`'s. **Duplicate it rather than share it** -
  `Cast`'s copy is private, the codec is corpus tooling that `mix.exs` excludes
  from the package, and a public helper linking them would widen the public
  façade (`area:api`) for four lines. The moduledoc's datetime example (line
  11) and `to_json/1`'s and `from_json/1`'s `@doc`s carry the stated form and
  the restated property.
- `test/predicator/conformance/values_test.exs` - the three changes above.
  This is a binding test for an exported artifact in the sense of
  `CLAUDE.md`'s convention, so the new canonicalization test earns a sabotage
  check and a line in `docs/research/260808-px-9ab-sabotage-notes.md`, which
  does not currently list this file.
- `conformance/README.md` - the "The tagged-value encoding" section: the
  `DateTime` table row keeps its example, and a sentence states the fractional
  form normatively, notes that it is the same form as `docs/isa.md` section
  5's `datetime::string`, and gives the emit-canonical/accept-anything decoder
  rule. Place it beside the duration paragraph, which it parallels.
- `conformance/corpus/tier-*.json` and `conformance/manifest.json` -
  regenerated by `mix corpus.generate`, never hand-edited. **Measured: no
  datetime currently on disk carries a fraction, so if no case is added the
  regeneration is a no-op and `corpus_hash` does not move.** Say so explicitly
  in the commit message and PR body, since ADR-0003 obliges a corpus diff to
  be explained and "there is deliberately no diff" is the explanation here.
- `CHANGELOG.md` - one bullet under `## [Unreleased]`, its own rather than
  folded into the cast entry. Unlike px-7t8's change, the corpus and its
  encoding shipped in 4.0.0, so this is a specification a sibling may already
  be reading being made precise, which is worth a line of its own.
- `docs/isa.md` - **nothing**, per the version section above.
- `docs/reference/language.md` - **nothing**. Its datetime sentence (line 195)
  is about the `::string` cast, which does not change.
- `conformance/schema/*.json` - **nothing**. The schemas do not constrain the
  tagged `value` string at all. A `pattern` binding the two shapes was
  considered and declined: it would have to be repeated everywhere a value can
  appear (`context`, `expected_result`, `instructions` operands), and the
  corpus's own generated content is already the binding.

## Open question, recorded rather than blocked

**Whether this bead's implementation should also add a conformance case
pinning a fractional datetime *value*, and whether `casts.json:155`'s chained
dodge should be undone.**

For adding one: the corpus contains no datetime with a non-zero fraction, so
the six-digit half of the form is currently pinned only by the Elixir test
suite, and a sibling could pass every case while formatting `.5` as `.500`.
`#2026-08-09T10:30:00.500Z#::datetime` asserting
`{"$type":"datetime","value":"2026-08-09T10:30:00.500000Z"}` would pin it, and
the millisecond-expressible value keeps a `Date`-backed JavaScript sibling able
to construct it - the portability discipline px-7t8 already applied.

Against: it moves `corpus_hash`, which turns a zero-diff change into a corpus
diff, and the case belongs as much to px-7t8's tier-7 cast coverage as to this
bead.

The best-supported call, made here because no human is available: **add the
one case**, accepting the `corpus_hash` move, because a cross-language form
that no cross-language artifact exercises is not actually pinned - which is the
whole argument this document rests on. **Leave `casts.json:155` alone**: its
note explains that its subject is the offset requirement and that it
deliberately does not assert a fact it does not own, and that reasoning
survives this decision unchanged. If the implementing session disagrees about
the added case, dropping it costs only the corpus diff and leaves every other
consequence above intact.
