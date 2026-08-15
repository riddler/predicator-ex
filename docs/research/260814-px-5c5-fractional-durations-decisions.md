---
date: 2026-08-14T22:30:00-0600
researcher: Claude
git_commit: 4faf42f5c396bb62805ea28281dc7297f1098f54
branch: px-5c5-fractional-durations
repository: predicator-ex
beads_issue: px-5c5
topic: "Design decisions for fractional duration values"
tags: [research, decisions, duration, lexer-parser, evaluator, isa]
status: complete
last_updated: 2026-08-14
last_updated_by: Claude
---

# Decisions: fractional duration values (px-5c5)

This is the decision record for px-5c5 (mirrors st-rsl). The codebase survey
it decides against is
[260814-px-5c5-fractional-durations.md](260814-px-5c5-fractional-durations.md);
read that first for where integer-only is enforced today and what the tests
pin. This document settles the six open design questions so the plan and
implementation need no further judgment calls.

Why this is a research note and not an ADR: `docs/adr/README.md`'s own test
("a call too narrow for its own ADR goes to `docs/research/`") and the direct
precedent - px-7t8's "v4 clarification, not v5" call, the same class of
question, lives in
[260810-px-7t8-datetime-string-fractional-seconds.md](260810-px-7t8-datetime-string-fractional-seconds.md).
The ISA versioning rules themselves are not moving; this applies them.

## Decision 1: No new ISA version. This is a v6 refinement, not v7.

**ISA stays v6. §7 gains no row, `Predicator.isa_version/0` does not move.**
The `::duration` bullet in `docs/isa.md` §5 (the cast opcode's string
formats, currently "a sequence of integer-unit pairs") is rewritten to state
the widened grammar precisely, with a `bracket_access`-style sentence noting
that this bullet, not the ISA version, changed.

Reasoning, in increasing order of strength:

1. **§1's widening rule scopes itself out.** "Adding an operand form or
   widening an accepted type is a new version" is immediately qualified:
   "This rule speaks to operand forms carried *in the instruction list*."
   Nothing in the wire format moves here. `"1.5s"::duration` compiles to
   `[["lit", "1.5s"], ["cast", "duration"]]` before and after; `lit`'s
   operand was always a string and `cast`'s operand is still the type name.
   A duration *literal* `1.5s` lowers to more integer pairs
   (`["duration", [[1, "s"], [500, "ms"]]]`), an operand shape the `duration`
   opcode already accepts. No operand form widens.
2. **A v7 could not do a version's job.** §1's whole design makes "scan the
   opcode names in a list" the sound answer to "what version does this list
   require", and `Predicator.Instructions.required_isa/1` reads only opcode
   heads. A version minted for a change no opcode-name scan can express would
   stamp the same instruction lists v4-compatible while meaning something
   different - the exact defect §1 cites (px-o9v's null widening at the
   host/context boundary) as grounds for not minting.
3. **The refinement precedent covers changes to specified behavior, not just
   unspecified gaps.** §7: "A version's semantics can also be refined in a
   later release without a new opcode and without a new ISA version - 3.8.0
   did exactly that to v2." 3.8.0 changed what v2 opcodes *did* (unbound-root
   reporting replaced type-mismatch errors) under existing names with no
   bump. That answers the disanalogy the research doc flagged against the
   px-7t8 route (there the field was genuinely unspecified; here
   "integer-unit pairs" is written down): the repo's precedent is not limited
   to filling gaps.
4. **ADR-0011 built `cast` to absorb exactly this.** Casting is total;
   failure is `:undefined`, never an error. A string moving from the
   unparseable set to the parseable set converts a specified `:undefined`
   into a value - a monotone widening in the direction the operator's failure
   mode was designed for. No expression that produced a value before produces
   a different value or an error after.

**Rejected alternative**: mint v7 under a broad reading of "widening an
accepted type". Rejected because of the scoping sentence (point 1) and
because the resulting version stamp would be undetectable by the membership
check §1 mandates (point 2). The refinement still gets exported to siblings -
through §5's normative text and through conformance corpus cases (see
"Documentation and conformance obligations" below), the same channel px-7t8
used.

## Decision 2: Sub-millisecond remainders are rejected, not rounded or truncated.

**A fractional value is valid iff its total is an exact integer number of
milliseconds.** `"0.5ms"` is invalid (half a millisecond). `"1.0005s"` is
invalid (1000.5 ms). `"0.5s"`, `"0.25s"`, `"0.1s"` (500, 250, 100 ms) are
valid. `"1.0s"` is valid (exactly 1 s; the zero remainder emits nothing).

Per surface:

- duration literal `0.5ms` - **compile-time error** (see Decision 6a for the
  error shape and span);
- `Duration.parse("0.5ms")` - `:error`;
- `"0.5ms"::duration` - `:undefined` (cast maps `parse/1`'s `:error`, per
  ADR-0011; no new plumbing).

Reasoning: the value domain bottoms out at milliseconds
(`Types.duration()`'s smallest field), and px-7t8's fidelity principle -
"losing information is not the house style of this subsection", argued there
by citing duration's own round-trip guarantee - cuts against silently
discarding a sub-ms remainder. Rejection is also the smaller, extendable
claim: an error that later becomes a value is an additive change, while a
rounded value that later changes rounding is a breaking one.

**Rejected alternative**: round (or truncate), as `::datetime` does to a
seventh fractional-seconds digit. Rejected because the datetime truncation
pins an *unspecified boundary* at the host type's precision, whereas here the
fraction is the feature itself and the caller wrote a value the domain cannot
hold. CSS2-style consumers that want rounding can round before calling; a
parser that rounds cannot be un-rounded by any caller.

**Exactness is computed in integer arithmetic, never floats.** For a
component `<int>.<frac><unit>` with `k` fraction digits, let `F` be the
fraction digits read as an integer and `M` the unit's millisecond multiplier
(the same table `to_milliseconds/1` uses). The component is valid iff
`rem(F * M, 10^k) == 0`, and its remainder is `div(F * M, 10^k)`
milliseconds. Binary floats must not appear anywhere in this computation
(`0.7 * 1000` is not reliably `700.0`), which is why the fraction travels as
decimal digits, not as a parsed float - see Decision 6b.

## Decision 3: Fractions are allowed on all eight units, under the one exactness rule.

**No unit-class restriction.** `"0.5mo"` and `"0.5y"` are valid; so are
fractional `w` and `d`. The only gate is Decision 2's integer-millisecond
test, which every unit can pass because every unit already has an exact
integer millisecond multiplier in `to_milliseconds/1` - `mo` and `y` via the
documented 30-day and 365-day approximations.

Reasoning:

- Nothing in the codebase programmatically distinguishes "exact" from
  "approximate" units; that distinction lives only in `@doc` prose. A
  restriction would introduce it - a new error class, a units table in two
  grammars and three documents - solely to forbid something whose semantics
  the approximations already fix.
- One uniform rule is easier to state normatively in §5 and easier for a
  sibling to port than a unit-class carve-out.
- Every arithmetic consumer (`to_seconds/1`, `to_milliseconds/1`,
  `add_to_date/2`, `subtract_from_date/2`) already applies the 30/365
  approximations, so expanding `0.5mo` to `15d` at parse time produces
  results identical to any post-hoc application.

Consequence to document: expanding a fractional `mo`/`y` **commits the
documented approximation at parse time** - `parse("0.5mo")` yields a map with
`days: 15` and no `months` key. Acceptable here because no consumer performs
calendar-aware month arithmetic; the approximation is the semantics.

**Rejected alternative**: restrict fractions to units with exact conversions
(`w` and below), the bead's "smaller claim". Rejected for the machinery cost
above and because no consumer pushes for it - SCXML's delay grammar
(`ms|s|m|h|d`) does not contain `mo`/`y` at all, so the restriction would
protect nobody.

**Normalization shape.** For a component `<int>.<frac><unit>`: the integer
part stays on the source unit; the remainder (Decision 2's
`div(F * M, 10^k)` milliseconds) decomposes greedily, largest-first, through
**`d`, `h`, `m`, `s`, `ms` only** - never back into `w`, `mo`, or `y`.
Examples, exhaustively:

| Source | Normalized |
|---|---|
| `1.5s` | `1s` + `500ms` |
| `1.5m` | `1m` + `30s` |
| `1.5h` | `1h` + `30m` |
| `1.5d` | `1d` + `12h` |
| `0.5w` | `3d` + `12h` |
| `0.5mo` | `15d` |
| `1.5y` | `1y` + `182d` + `12h` |
| `1.0s` | `1s` (zero remainder emits nothing) |
| `0.0s` | the zero duration (`0d` is already legal) |

Excluding `w` from the ladder keeps `0.5y` as `182d12h` rather than the
unreadable `26w12h`, and excluding `mo`/`y` is forced anyway (a remainder is
always smaller than its source unit, and re-introducing approximate units
into a remainder would be circular).

## Decision 4: The leading-dot spelling `.5s` is rejected - at both entry points.

**`Duration.parse(".5s")` is `:error`, and `.5s` is not a duration literal**
(the lexer does not gain a leading-dot number form). The rule at both
surfaces: a fraction requires digits on both sides of the dot. Likewise
unchanged at both surfaces: a bare unit (`"s"`) stays an error, and a
trailing dot (`"1.s"`) stays an error - the widened `parse/1` pattern is
`[0-9]+(\.[0-9]+)?<unit>`, and the lexer's number scanner already consumes
`.` only when a digit follows.

Reasoning: the language has a documented position on exactly this shape on
the nearest analogous surface - `".5"::float` is `:undefined`, "no bare
fraction" (`docs/reference/language.md`). Accepting `.5s` in `parse/1` while
the lexer rejects it would fork the two grammars, which the ISA and
`language.md` currently describe as one; accepting it in the lexer would
open a leading-dot number form the language has deliberately never had. The
two entry points were considered separately, as the bead asks, and land in
the same place for the same reason.

Consequence for the mirror (st-rsl): SCXML's schema pattern
`\d*(\.\d+)?(ms|s|m|h|d)` permits `.5s`, so statifier pre-normalizes
(prepends `0` to a leading-dot delay) before calling `parse/1` - the option
the bead itself names. That note belongs on st-rsl's side of the mirror.

## Decision 5: The `to_string/1` round-trip consequence is accepted and documented.

`to_string(parse("1.5s"))` is `"1s500ms"`, and `"1.5s"::duration::string` is
`"1s500ms"`. **Accepted as documented behavior; `to_string/1` itself does not
change and never emits a fraction.**

This costs nothing that existed: the property the tests and `language.md`
actually guarantee is `parse(to_string(d)) == {:ok, d}` (map -> string ->
map), which downward normalization preserves because parse output is always
an integer map. The other direction, `to_string(parse(s)) == s`, was never
true - `"30m3d"` is the standing counter-example - and `language.md` already
frames `::duration` as "a canonicalizer over any equivalent spelling, not an
inverse of `::string`'s duration formatting". A fractional spelling is one
more equivalent spelling; the fractional examples join that paragraph.

## Decision 6: Pipeline invariants - duplicate units, error surfaces, and where expansion lives

### 6a. The lowering must not introduce duplicate units; a collision is a compile-time error

The research doc's observation: `Duration.parse/1` **accumulates** repeated
units while the `duration` opcode **overwrites** them (specified in
`docs/isa.md` §5, pinned by `conformance/cases/durations.json`). A fractional
expansion that emitted a unit also named elsewhere in the literal would fall
into that gap - `1.5s200ms` naively lowered to
`[[1,"s"],[500,"ms"],[200,"ms"]]` would evaluate to 1s200ms, silently
discarding the fraction's 500 ms.

**Decided:**

- **The chosen normalization must not emit two pairs naming the same unit
  from one literal.** Within a single component's expansion this holds by
  construction (greedy visits each ladder unit at most once, and the integer
  part's unit is above the ladder cut).
- **A duration literal containing any fractional component must, after
  expansion, name each unit at most once across the whole literal; a
  collision is a compile-time error** (`1.5s200ms`, `1.5s1s`, `1.5s0.5s` are
  all errors). Rejecting is Decision 2's fidelity principle again: neither
  overwrite (drops the fraction's remainder) nor accumulate (contradicts the
  literal grammar's pinned last-wins rule) can be chosen without a silent
  surprise.
- **Literals with no fractional component are untouched.** `1s2s` keeps
  today's lowering (`[[1,"s"],[2,"s"]]`) and the opcode's pinned overwrite
  behavior; no existing corpus case moves.
- **`Duration.parse/1` keeps its accumulate rule uniformly**, expansions
  included: `parse("1.5s200ms")` is 1 s 700 ms, `:ok`. The string API is
  documented as a lenient canonicalizer and stays one; the resulting
  literal-vs-parse divergence on mixed spellings is the same family of
  divergence the two surfaces already have on repeats, and it gets a
  sentence in `language.md`'s canonicalizer section.

Error surface for the two new literal errors (failed exactness, unit
collision): a **deliberate, spanned compile error** with a message naming
the problem - not a silent re-lex into `:float` + `:identifier` that
surfaces as a generic unexpected-token error. The span follows the
date-literal per-family precedent (`lib/predicator/lexer.ex:465-467`, the
two commits preceding this branch): a fractional component that fails
exactness is wrong as a whole, so the span covers that number-unit
component; a collision spans the whole literal. A fraction followed by a
*non-unit* (`1.5x`) keeps today's path: float token, then identifier,
exactly as `3x` re-lexes today.

### 6b. Expansion lives in `Predicator.Duration`, is computed from decimal digits, and completes before the AST

- **One shared helper in `Predicator.Duration`** (e.g. a
  `expand_fraction(int_part, frac_digits, unit)` returning
  `{:ok, [{integer, unit_string}]} | {:error, :subunit_remainder}`) performs
  Decision 2's integer-arithmetic test and Decision 3's greedy
  decomposition. Both `Duration.parse/1` and the compile pipeline call it,
  so the two grammars cannot drift on the exactness rule - answering the
  research doc's open question 5 (today they are two unrelated
  implementations of one grammar; the *scanners* stay separate, the
  *fraction semantics* become shared).
- **No binary float ever carries the fraction.** The fraction travels as its
  decimal digit string from the scanner to the helper. `String.to_float/1`
  output must not feed the expansion (Decision 2's arithmetic note).
- **The AST keeps its existing `{:duration, [{integer(), binary()}], pos}`
  shape**, receiving already-expanded pairs. Consequently `types.ex`, the
  instructions visitor, the evaluator's `is_integer/1` guard, the `duration`
  opcode's operand spec, and the conformance codecs are all untouched - the
  change stops at the parser boundary. The recommended token mechanism (the
  plan may adjust the mechanism, not the invariants): the lexer's float arm
  gains the same duration lookahead the integer arm has and, when a unit
  follows, emits a fractional-number token carrying
  `{int_part, frac_digits}` plus the usual `:duration_unit` tokens;
  `parse_duration_sequence/3` accepts it, calls the helper, enforces 6a, and
  builds the standard AST. A bare `1.5` with no unit still lexes as `:float`
  unchanged.
- Consequence, accepted: **`StringVisitor` renders the expansion** -
  decompiling a program containing `1.5s` prints `1s500ms`. This is the
  canonicalizer stance `language.md` already takes for duration strings,
  now visible one layer up. The rejected alternative - storing the float in
  the AST for source-faithful rendering - was rejected because it either
  puts a float where every downstream consumer holds an integer invariant
  or forces dual expansion sites, and because binary-float fidelity is
  illusory anyway (`0.1` is not `0.1`).

## Documentation and conformance obligations (the checklist Decision 1 implies)

- `docs/isa.md` §5, the `::duration` string-format bullet: the widened
  grammar stated normatively - number-unit pairs where the value may carry a
  decimal fraction; the fraction must expand exactly (an inexact fraction
  parses to nothing, so the cast is `:undefined`); expansion targets
  `d/h/m/s/ms`; `mo`/`y` fractions use the documented approximations. Plus
  the refinement sentence per Decision 1. §7: nothing.
- `docs/architecture.md` and `docs/reference/language.md`: the
  `duration → NUMBER UNIT+` production gains the fractional alternative in
  both copies; `language.md`'s canonicalizer section gains the fractional
  examples, the collision rule (6a), and the literal-vs-`parse/1` divergence
  sentence. The `::duration` cast bullet points at the same grammar.
- `conformance/cases/durations.json`: at least one fractional-literal case
  (pinning the expansion through the corpus, e.g. `1.5s` and a `0.5mo`).
  `conformance/cases/casts.json`: `"1.5s"::duration` (the refined cast
  semantics - since no version is minted, **these cases are the export
  mechanism**), and `"0.5ms"::duration` -> `:undefined` (pins Decision 2).
  Corpus regenerated by `mix corpus.generate`; the diff explained in commit
  and PR body (ADR-0003). The corpus freshness test is then the binding test
  - no new `test_roots` entry needed (research doc, open question 7).
- `CHANGELOG.md`: one entry under `## [Unreleased]`; additive, any 8.x
  minor, does not ride 8.0.
- Bead labels: the decisions add `docs/**` and `conformance/**` to the
  predicted blast radius, so px-5c5 now carries `area:docs` and
  `area:conformance` alongside `area:evaluator` and `area:lexer-parser`
  (ADR-0005 - the label is a prediction, updated when the prediction
  changes).

## Open questions

None. All six questions the direction stage was handed are settled above.
The one deliberately deferred item is mechanism-level: the exact token shape
carrying `{int_part, frac_digits}` from lexer to parser (6b names a
recommended shape; the plan may substitute an equivalent one so long as the
invariants - no floats, integer AST pairs, spanned errors - hold).
