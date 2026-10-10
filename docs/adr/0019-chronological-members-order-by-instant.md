# ADR-0019: Chronological members of lists and maps order by instant

Status: proposed (2026-10-10)

## Context

`docs/isa.md` section 5 states two rules for the `compare` opcode that meet
inside a container. `Date`/`Date` and `DateTime`/`DateTime` pairs "compare
chronologically, never by struct-key order", and two lists order
"element-wise, comparing the first position where the two differ". Two maps,
in this implementation, order by Erlang term order (size, then sorted keys,
then values), and the same section tells a sibling to treat map ordering as
unspecified.

Before this record, the reference evaluator applied the chronological rule to
a top-level pair only. Its chronological clauses in `compare_values/3`
(`lib/predicator/evaluator.ex`) match a bare `Date` or `DateTime` on each
side; two lists or two maps fell to the type-matched clause, which applied
Elixir's term operators to the whole containers. Term order reads a `Date`
struct's fields in key order - `day` before `month` and `year` - so
`[#2026-01-02#] < [#2025-12-31#]` answered `true` while
`#2026-01-02# < #2025-12-31#` answered `false`. `DateTime` members had the
same fault, and so did object literals holding either.

The TypeScript sibling found the divergence while matching the reference and
declared it rather than reproduce it. The fix was ruled by the operator,
2026-10-06. Its reach and this record's route were decided by the conductor
under a standing consent, 2026-10-10: same-kind pairs only, and a new record,
because no earlier record states the comparison rule.

## Decision

**Under `GT`, `LT`, `GTE` and `LTE`, two lists, or two plain maps, compare
their members by the same rule the opcode applies at the top level for
chronological values: two `Date` members, or two `DateTime` members, order by
instant, at any depth. A member pair at the same instant is level, and the
next member decides.** Every other member pair keeps its term order. The
ordering is `order_members/2` in `lib/predicator/evaluator.ex`; the clause
that routes container ordering to it is the container clause of
`compare_values/3`.

Per member pair, under the four ordering operators:

| Member pair | Orders by | Changed by this record |
|---|---|---|
| `Date` and `Date` | instant (`Date.compare/2`) | yes, where term order disagreed |
| `DateTime` and `DateTime` | instant (`DateTime.compare/2`) | yes, where term order disagreed |
| `Date` and `DateTime` (mixed) | term order (a `Date` sorts first) | no - not decided here |
| two lists, or two plain maps | this rule, one level down | yes, through their members |
| any other pair | term order | no |

For maps, term order is kept where it decides without the values: maps of
different sizes, or of the same size with different keys, answer exactly as
before. Two maps with the same keys compare their values in key order, by
the rule above.

**What this record does not change.**

- **Equality.** `EQ` and `NE` on two lists or two maps stay structural (`==`),
  and `in` and `contains` keep their answers. Two `DateTime` members written
  to different precision are therefore level for ordering - both `<=` and `>=`
  hold - while `==` on the two containers answers `false`. That disagreement
  is a separate question about container equality and is left as it is.
- **The mixed pair.** A `Date` member against a `DateTime` member is not
  decided by this record. The top level coerces the `Date` to midnight UTC;
  whether a member pair should do the same is left open, and it keeps the
  term-order answer it had. The conformance corpus does not exercise it.
- **Top-level answers.** Every pair compared outside a container answers as
  before.
- **Map ordering for siblings.** `docs/isa.md` still calls map ordering
  unspecified for a sibling, and the corpus still does not exercise it; the
  map arm is pinned by unit tests here.

**The ISA version does not move.** `docs/isa.md` section 1 says an opcode's
semantics never change under its own name. The rule `compare` is specified
by - chronological dates, element-wise lists - is unchanged at ISA v6; the
reference evaluator departed from it inside containers, and this record
brings the evaluator into line with the stated rule. No opcode, operand form
or accepted type changes, and every instruction list keeps its required
version. The lists bullet in `docs/isa.md` section 5 gains sentences that
state the member rule outright, in the shape the `bracket_access` bullet
used when it corrected its own wording without a version move.

## Consequences

- **A changed answer, released as a patch.** A host that orders two lists or
  two maps holding dates or datetimes can see a different boolean. The
  changelog fragment names it under Changed.
- **The corpus moves.** New `dates/` cases pin date and datetime members
  inside lists, including a level pair that steps to the next member; they are
  generated through `mix corpus.generate`, so the manifest's `corpus_hash`
  moves and each sibling re-vendors at the next tag.
- **Ordering and equality can disagree on one shape.** Containers whose
  `DateTime` members name the same instant in different forms are level under
  `<=`/`>=` and unequal under `==`, as stated above. A later record that makes
  container equality chronological would close it.
- **The mixed member pair stays open.** Deciding it - most likely by the
  top-level coercion - changes more answers and is a decision of its own.
