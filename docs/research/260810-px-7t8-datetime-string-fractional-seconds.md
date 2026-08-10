# The canonical fractional-seconds form of `datetime::string`

Bead: px-7t8 (discovered from px-2r5.3)
Date: 2026-08-10
Decision: **omit the fraction entirely when the sub-second value is zero;
emit exactly six digits when it is not.** `datetime::string` is
`YYYY-MM-DDTHH:MM:SSZ` or `YYYY-MM-DDTHH:MM:SS.ffffffZ`, in UTC, and no other
form. **No ISA version bump** - this pins a field §5 never specified, so it
is a v4 clarification, not a v5.

This is one field of one cell of one opcode's conversion matrix. It is not
ADR-shaped: the decision it hangs off - `::` is a `cast` opcode, failure is `:undefined` - is
already
[ADR-0011](../adr/0011-casts-are-an-opcode.md), and `docs/adr/README.md`'s
third corollary sends a call this narrow to `docs/research/` named after the
bead that prompted it. The matrix's own working specification is
`260809-px-2r5.1-cast-conversion-matrix.md`; this document is the missing
sentence in its `datetime::string` row.

## The question

`docs/isa.md` §5 says of `date`/`datetime` under **String formats
(`::string`)**: "ISO 8601; datetimes in UTC with `Z`". That does not determine
the fractional-seconds field, and the three implementations' host defaults
diverge on it:

| Language | Call | Default output |
|---|---|---|
| Elixir (ours) | `DateTime.to_iso8601/1` | `"2026-08-09T12:00:00.000000Z"` (the struct's precision field, forced to 6 by our own normalization) |
| JavaScript | `Date#toISOString()` | `"2026-08-09T12:00:00.000Z"` (always 3) |
| Ruby | `Time#iso8601` | `"2026-08-09T12:00:00Z"` (none unless a digit count is asked for) |

All three satisfy the sentence as written, so all three could claim ISA v4
while producing three different strings for one cast. Nothing is locked in
yet: tier 7 has no `datetime::string` case, and `cast`/ISA v4 are still under
`## [Unreleased]` in `CHANGELOG.md` (`mix.exs` is at 4.0.0), so v4 has never
shipped to a sibling.

## Ground truth: what this repo emits today

`lib/predicator/cast.ex` normalizes to UTC through
`DateTime.from_unix!(DateTime.to_unix(dt, :microsecond), :microsecond)`, which
sets the struct's precision field to 6 unconditionally, and then calls
`DateTime.to_iso8601/1`, which prints exactly that many digits. Measured:

```text
#2026-08-09T10:30:00Z#::string                    -> "2026-08-09T10:30:00.000000Z"
"2026-08-09T10:30:00Z"::datetime::string          -> "2026-08-09T10:30:00.000000Z"
"2026-08-09T10:30:00.5Z"::datetime::string        -> "2026-08-09T10:30:00.500000Z"
#2026-08-09#::datetime::string                    -> "2026-08-09T00:00:00.000000Z"
"2026-08-09T10:30:00.123456789Z"::datetime        -> ~U[2026-08-09 10:30:00.123456Z]
```

Two facts fall out of that. First, six zero digits appear that were never in
the input, in every ordinary case. Second, the repo already contradicts
itself: the corpus's tagged encoding for a datetime value goes through
`Predicator.Conformance.Values.to_json/1`, which calls `DateTime.to_iso8601/1`
on the value's *own* precision, so a datetime that reached the corpus from a
literal or from the `date::datetime` bridge encodes with **no** fraction. Both
existing corpus expectations show it -
`conformance/cases/casts.json:30` and `:72` expect
`"2026-08-09T00:00:00Z"` and `"2026-08-09T10:30:00Z"` - and so does
`conformance/README.md:107`'s example. So the exported artifact already leans
toward "no fraction", while the `::string` cast leans toward six digits.

`conformance/cases/casts.json:156` records the consequence: the
`string::datetime` case was deliberately chained on to `::date` so it would
not have to assert a datetime value whose fractional form was still open.

## Ground truth: sub-second precision is representable

It is, which rules out the tempting simplification. The lexer's datetime
literal goes through `DateTime.from_iso8601/1` (`lib/predicator/lexer.ex:655`),
so `#2026-08-09T10:30:00.5Z#` is a legal literal and evaluates to
`~U[2026-08-09 10:30:00.5Z]`; §5's `::datetime` parse is the same function.
Elixir's `DateTime` tops out at microseconds, and digits past the sixth are
truncated, not rejected - `.123456789` parses to `.123456`.

So the language can hold a sub-second instant, and any policy that formats
seconds-only silently discards data a user put in.

## Weighing the three candidates

**Seconds precision always (no fraction ever)** is the cheapest in all three
languages - Ruby's default, one `.replace` in JavaScript, one precision field
in Elixir - and it is rejected on fidelity. Sub-second instants exist in this
language, so this policy makes `"…:00.5Z"::datetime::string` emit
`"…:00Z"`, discarding the half second in a cast whose entire job is to render
the value it was given. §5's neighbouring rules point the other way: `float`'s
format is *shortest round trip*, and `duration`'s is specified precisely so
that `d::string::duration` round-trips. Losing information is not the house
style of this subsection.

**A fixed digit count always** is what we do today at six, and it is rejected
on noise and on the artifact it would force. It appends digits that were never
in the input in the overwhelmingly common case, it obliges a JavaScript
sibling to pad `toISOString()`'s three digits on every single value, and -
decisively - it would require changing the two corpus expectations quoted
above and `conformance/README.md`'s example, i.e. moving the exported
specification to accommodate an Elixir struct field that no sibling has.

**No fraction when zero** is chosen, with the digit count pinned at six when
the fraction is present. Taking the two halves separately:

- *Omit when zero.* Cheap everywhere: Elixir sets the precision field to `0`,
  Ruby's `iso8601` already does it, JavaScript strips a literal `.000`, and
  `Temporal.Instant#toString()` does it by default. It matches every datetime
  string the corpus already contains, so no existing expectation moves. And it
  makes `"2026-08-09T10:00:00Z"::datetime::string` the identity on the string,
  which is the behavior a reader of §5's sentence would predict.
- *Six digits when non-zero, not the minimal number.* A variable digit count
  is a fresh cross-language hazard of exactly the kind §5 already warns about
  for `float`: Elixir would print `.5` from its precision field, a JavaScript
  `Date` can only ever produce `.500`, and Ruby's `iso8601(n)` takes a fixed
  `n` and cannot trim. Pinning six removes the disagreement - Elixir's `.5`
  becomes `.500000`, JavaScript pads `.500` to `.500000`, Ruby asks for
  `iso8601(6)` - and six is the right constant because six is the precision
  the ISA's own `::datetime` parse accepts and truncates at.

The result is a form that is a function of the instant alone, with exactly two
shapes and no per-value digit negotiation, reachable in one line in each of
the three host languages. Under ADR-0003 this repo leads, so this is stated
normatively in §5 rather than left as a warning; the `float::string` hazard
was mitigated by pinning portable *corpus values* only because
shortest-round-trip notation genuinely cannot be pinned in prose, which is not
the case here.

## The normative sentence §5 should carry

Replacing the current `date`, `datetime` bullet under **String formats
(`::string`)**:

> - `date` - ISO 8601 calendar date (`2026-08-09`).
> - `datetime` - ISO 8601 in UTC with `Z`, and the fractional-seconds field is
>   **normative**: omitted entirely when the sub-second component is zero
>   (`2026-08-09T12:00:00Z`), and exactly six digits when it is not
>   (`2026-08-09T12:00:00.500000Z`). Never any other digit count, and never a
>   zero fraction spelled out. Sub-second precision is microseconds - the
>   `::datetime` parse truncates digits past the sixth - so the field is
>   stated in terms of the instant, not in terms of any host type's precision
>   or scale field.

Worth saying alongside it, because it is the same class of fact as the
`duration` bullet's round-trip note: `dt::string::datetime` preserves the
instant, and `s::datetime::string` is a **canonicalization**, not a string
identity - `"…:00.5Z"` comes back as `"…:00.500000Z"`, and a seventh input
digit is gone. `duration` is already documented this way.

## Version: this is a v4 clarification, not v5

**ISA stays v4. No row is added to §7, and `Predicator.isa_version/0` does not
move.** Three reasons, in increasing order of strength:

1. §1's rule that "an opcode's semantics never change under its own name" bites
   on a change to *specified* behavior. This field was never specified, so no
   conforming implementation could have depended on it and none is being
   broken. The precedent is in §5 itself: the `bracket_access` bullet says in
   so many words that it, "not the ISA version, changed to state the above
   precisely" for a case that "was previously unspecified here" and that the
   reference implementation got wrong - and cites §1 for why that is not a
   bump.
2. §7 records the same allowance generally: "A version's semantics can also be
   refined in a later release without a new opcode and without a new ISA
   version - 3.8.0 did exactly that to v2."
3. v4 has not shipped. `cast` is under `## [Unreleased]`; §7 promises it in
   4.1.0, which does not exist yet. There is no released artifact and no
   sibling claim to be compatible with, so the question of a compatibility
   version does not arise. The right framing is that v4 ships already pinned.

## Consequences for the implementation

**Yes, the Elixir implementation changes** - the chosen form is not
`DateTime.to_iso8601/1`'s default under our normalization. The change is
local: in `lib/predicator/cast.ex`, the `%DateTime{} -> "string"` clause
(around line 130) keeps `normalize_to_utc/1` and then canonicalizes the
precision field before formatting - `{0, _}` becomes `{0, 0}`, and any
non-zero microsecond value becomes `{us, 6}`. `normalize_to_utc/1` itself is
unchanged; forcing precision 6 there is what makes it tz-database-free and it
still feeds the `string::datetime` parse, which is not this bead's surface.

Files the follow-on implementation should expect to touch:

- `lib/predicator/cast.ex` - the one behavioral change.
- `docs/isa.md` §5 - the normative bullet above. §7 gets nothing.
- `test/predicator/cast_test.exs` (and the evaluator's cast tests) - both
  shapes, plus the truncation-at-six case.
- `conformance/cases/casts.json` - the pinning case(s) the acceptance criteria
  require. Two: a zero-fraction `datetime::string` and a non-zero one. **Pin a
  sub-second value expressible in milliseconds** (`.500000`, not `.123456`), so
  a JavaScript sibling backed by `Date` rather than `Temporal` can construct
  the input at all - the same portability discipline §5 already applies to
  `float::string`'s pinned values.
- `conformance/corpus/tier-*.json` and `conformance/manifest.json` -
  regenerated by `mix corpus.generate`, never hand-edited, and the corpus diff
  gets explained in the commit message and PR body (ADR-0003).
- `CHANGELOG.md` - folded into the existing cast entry under `## [Unreleased]`
  rather than added as a separate line; the cast operator has not shipped, so
  there is no user-visible change to announce, only a specification that is
  now precise.
- `docs/reference/language.md`, if it restates the cast formats.

## Deliberately out of scope

Three other call sites of `DateTime.to_iso8601/1` exist, and the decision is
scoped to the `cast` opcode:

- `lib/predicator/parser.ex:1287` - formats a datetime token inside a parse
  error message. Human-facing prose, not an exported value. Untouched.
- `lib/predicator/visitors/string_visitor.ex:161` - `decompile` renders a
  `#…#` literal. §6 puts surface syntax outside both the ISA and the corpus,
  and the round trip through the lexer holds under either form, so there is
  nothing to fix. Untouched, and no follow-on needed.
- `lib/predicator/conformance/values.ex:71` - the corpus's tagged
  `{"$type": "datetime"}` encoding, documented by example at
  `conformance/README.md:107`. This one **does** have the same
  underspecification, and it should end up with the same canonical form, but it
  is not a free rename: see the open question below. A separate bead, labeled
  `area:conformance` + `area:docs`, not this one.

## Open questions

**The tagged datetime encoding cannot simply adopt this form as-is.**
`Values.to_json/1`'s `@doc` promises `from_json(to_json(v)) == {:ok, v}` for
every accepted value, and `test/predicator/conformance/values_test.exs:34`
asserts it. Elixir's `DateTime` carries a precision field that the tagged
encoding does not represent, so once the encoding drops a zero fraction,
`~U[…00.000000Z]` and `~U[…00Z]` encode identically and structural
round-tripping is broken for one of them. The two exits are to canonicalize
on decode (and restate the inverse property as holding up to the encoded
precision) or to leave the encoding precision-driven and document *that*.
Choosing between them is a real design call about the harness's value domain,
not a formatting detail, which is why it is deferred to its own bead rather
than settled here. Nothing in the decision above depends on the outcome: the
cases this bead pins expect a **string** result, so `to_json/1`'s datetime
clause is not on their path.
