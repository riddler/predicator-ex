---
date: 2026-08-13
planner: Claude
git_commit: 19b10f579d905fb51de59750c0ac1768860631ae
branch: px-o9v-null-vs-undefined
repository: predicator-ex
beads_issue: px-o9v
topic: "Distinguishing a semantic null from the :undefined sentinel in Predicator.Context"
tags: [plan, context, evaluator, docs, conformance]
status: ready
---

# Null vs Undefined in Context Implementation Plan

## Overview

Make a value that is *present and null* survive the context boundary
distinguishably from a value that is *unbound*. Today `Context.new/2` and
`bind/3` rewrite `nil` to the `:undefined` sentinel
(`lib/predicator/context.ex:327`), so the two are the same value and
`_event.data.foo === undefined` answers `true` for a JSON field that was
present and explicitly `null` - the wrong-answer-quietly bug px-o9v was raised
from.

This plan implements **only the value half**: null becomes a value the context
can carry, the evaluator can operate on, and the corpus can pin. There is no
new reserved word, no grammar change, no new opcode, and no ISA version move.
The literal half (a `null` keyword in the grammar) stays deferred to the next
breaking bump, per the bead.

Bead: px-o9v.

## Current State Analysis

The research document
(`docs/research/260813-px-o9v-null-vs-undefined-in-context.md`) is the
foundation; this section records only what the plan turns on, plus what was
verified by running code against this checkout during planning.

**The collapse is one clause.** `normalize_value(nil), do: Undefined.value()`
at `lib/predicator/context.ex:327`, reached from exactly two public entry
points: `new/2` (`lib/predicator/context.ex:126`, whole-map deep) and `bind/3`
(`lib/predicator/context.ex:236`, value only).

**The collapse is already not universal.** Six paths carry a raw `nil` into
evaluation today without meeting `normalize_value/1`:
`Predicator.Evaluator.evaluate/3` on a bare map
(`lib/predicator/evaluator.ex:321-334`), `Predicator.evaluator/2`
(`lib/predicator.ex:959-965`), `Context.assign/3`
(`lib/predicator/context.ex:304-311`), `Predicator.context_assign/4`
(`lib/predicator.ex:1140-1148`), custom function return values
(`lib/predicator/evaluator.ex:1284-1310`), and the `host` slot. So `nil`
already reaches the evaluator; what it does not have is defined semantics.

**What a raw `nil` does today, measured.** Running each case against this
checkout through `Evaluator.evaluate/3` on a bare map:

| Expression | Today |
|---|---|
| `nil === :undefined` | `false` |
| `nil == :undefined` | `:undefined` |
| `nil === nil` | `true` |
| `nil == nil` | `:undefined` |
| `nil + 1` | **raises `FunctionClauseError`** |
| `not nil` | **raises `FunctionClauseError`** |
| `nil` at a jump | **raises `FunctionClauseError`** |
| `nil in [1]` | `false` |
| `nil in [nil]` | `false` |
| `nil::string` | `:undefined` |
| `nil.foo` | `:undefined` |

Three of those raise. The cause is `get_value_type/1`
(`lib/predicator/evaluator.ex:1111-1124`), which has clauses for integer,
float, boolean, binary, list, `Date`, `DateTime`, `:undefined`, and map - and
none for `nil`. A `nil` reaching `not`, arithmetic, `unary_minus`,
`unary_bang`, or any of the three jumps falls into the error-reporting path,
calls `get_value_type(nil)`, and crashes. **This is a live ADR-0004 violation**
(errors are values, never raised at a leaf) reachable today through the six
bypass paths, independent of anything px-o9v changes.

**The four comparison answers already come out right with no new code.** The
first four rows above are exactly the matrix this plan wants, produced by the
existing clauses: `compare_values(_left, :undefined, operator)` when non-strict
(`lib/predicator/evaluator.ex:752-754`) catches `null == undefined`; the raw
`===`/`!==` clauses (`757-758`) catch both strict rows; and `types_match/2`
does not admit `nil`, so `null == null` falls to the catch-all at
`lib/predicator/evaluator.ex:790` and yields `:undefined`.

**Types.** `Types.value()` (`lib/predicator/types.ex:53-62`) does **not**
include `nil`, so a `nil` in an input map is already outside the declared input
type - the normalization is what makes the spec honest today.

**The corpus already speaks JSON null.** `conformance/README.md:99-101` opens
its tagged-value section with "JSON's own type system - string, number,
boolean, `null`, array, object - covers most of predicator's value domain
directly. Four things do not fit". Null is JSON-native; it needs no fifth
`$type` tag, only two codec clauses. Today `to_json(nil)` returns
`{:error, {:unencodable, nil}}` (`lib/predicator/conformance/values.ex:96`)
and `from_json(nil)` returns `{:error, {:undecodable, nil}}` (`:153`).

**What goes red when the collapse stops.** Exactly seven, swept exhaustively by
the research: `test/predicator/context_test.exs:142, 154, 290, 349`;
`test/predicator/integration/on_unbound_test.exs:128`; and the doctests at
`lib/predicator/context.ex:109` and `:231`. Updating them is Phase 2's work,
not a surprise.

**One prose landmine.** `docs/reference/language.md` (in "The honest boundary")
tells a reader to bind a variable as declared-but-undefined with
`Predicator.Context.new(%{"x" => nil})`, "which normalizes to `:undefined`".
That instruction becomes false in Phase 2 and must be rewritten to bind
`Predicator.Undefined.value()` explicitly (which `normalize_value/1`'s scalar
catch-all passes through unchanged, verified). It is prose, not a doctest, so
no test catches it - Phase 3 owns it.

## Desired End State

Null is Elixir `nil`, and it is a value in predicator's value domain. The
organizing sentence, which every decision below is derived from:

> **Null is a value; undefined is an absence.**

After this plan:

1. `Context.new/2` and `bind/3` store `nil` as `nil`. A host can put a null in
   a context and read it back: `Context.new(%{"x" => nil}).data == %{"x" => nil}`,
   `Context.bound?(ctx, "x") == true`, and `Predicator.evaluate("x === undefined", ctx)`
   answers `{:ok, false}` where it answered `{:ok, true}` before. That is
   acceptance criterion (a).
2. The four-way comparison matrix is fixed and documented (below). That is
   acceptance criterion (b).
3. No reserved word, no grammar change, no new opcode, no ISA version move.
   That is acceptance criterion (c).
4. No expression can raise out of the evaluator on a `nil` operand; every one
   of the three crash sites returns a `TypeMismatchError` value reporting type
   `:null` (ADR-0004).
5. `docs/isa.md` §2, §3, and the affected §5 entries state null's rules;
   `docs/reference/language.md` teaches them; `docs/architecture.md` and
   `CHANGELOG.md` record them.
6. The conformance corpus carries null cases, and the codec round-trips `nil`
   as a bare JSON `null`.

### The decisions this plan settles

The parent task named six open decisions. Each is settled here, with its
reasoning, so no implementer re-litigates them.

#### D1. Representation: null is Elixir `nil`

Three shapes were available (the research's open question 5): a second atom
sentinel (`:null`), a struct, or raw `nil`.

**Chosen: raw `nil`.** Reasoning:

- **It collapses a state instead of adding one.** Six paths already carry raw
  `nil` into evaluation with no defined semantics. A `:null` atom would leave
  them alone and create a *third* state - `nil`, `:null`, `:undefined` - with
  the raw-`nil` path still undefined and still crashing. `nil` gives every one
  of those six paths a defined meaning retroactively, which is why the research's
  open question 1 caveat ("two different things a change here would have to
  reconcile") dissolves rather than needing reconciliation.
- **It is JSON-native, which is the actual use case.** Statifier's pressure is a
  JSON event payload (W3C SCXML B.2.1). `Jason.decode!/1` produces `nil` for
  JSON `null`. With this representation the consumer does nothing at all: the
  decoded payload is already correct. `Jason.encode!(["lit", nil])` produces
  `["lit",null]` and round-trips cleanly (verified) - unlike `:undefined`,
  which encodes as the string `"undefined"`, the ambiguity px-a2w exists for.
  Null is the one member of the non-JSON-native set that is not actually
  non-JSON-native.
- **A struct is foreclosed by existing reasoning.** `lib/predicator/undefined.ex`'s
  moduledoc already rejects a struct sentinel for `:undefined`: it "would break
  instruction interchange and every existing embedding for aesthetic gain",
  citing ADR-0001. The same argument applies unchanged.

**Cost, accepted:** `Types.value()` widens by `| nil`, which the other two
options would not have required. That is the honest consequence of choosing the
representation the boundary already produces, and it makes the declared input
type match what `Context.new/2` will now accept.

#### D2. The comparison matrix

The bead's premise that "Predicator has one equality operator" is wrong -
there are two, `==` (non-strict) and `===` (strict), so the choice is four-way.

| Comparison | Answer | Mechanism |
|---|---|---|
| `null === undefined` | `false` | existing `===` clause, `lib/predicator/evaluator.ex:757` |
| `null == undefined` | `:undefined` | existing non-strict clause, `:752-754` |
| `null === null` | `true` | existing `===` clause, `:757` |
| `null == null` | `:undefined` | existing catch-all, `:790` |

**No new `compare_values/3` clause is written.** All four answers are what the
current code already produces (measured, table in Current State Analysis).
That is not a coincidence to be exploited - it is the reason to adopt them:

- `null === undefined` **must** be `false`, or acceptance criterion (a) is
  unmet. It is also ECMAScript's answer, and `===` is already documented in
  `docs/reference/language.md` as predicator's boundness test.
- `null == undefined` is `:undefined` by exact symmetry with
  `undefined == undefined`, which is `:undefined` today. Predicator's `==` is
  **not** ECMAScript's coercing `==`; it is a typed comparison whose type
  mismatch answers `:undefined` (isa.md §5, `compare`). So ECMAScript's
  `null == undefined === true` does not transfer, and importing it would be a
  transcription error, not an alignment.
- `null === null` is `true`, mirroring `undefined === undefined`.
- `null == null` is `:undefined`, mirroring `undefined == undefined`. Null has
  no ordering and no `==` peer.

The rule to document in one sentence: **`==` and the ordering operators are
typed comparisons, and null has no type peer, so every non-strict comparison
involving null yields `:undefined`; `===` is the operator that answers a
boolean about null, exactly as it is for `undefined`.**

*The alternative considered and rejected:* making `null == null` answer `true`
by giving null itself as its type peer. It requires a new clause, and it forces
an answer for `null > null` and `null >= null`, which are nonsense. The
symmetry with `:undefined` is worth more than the small ergonomic gain, and the
ergonomic gain is unreachable anyway until the literal half ships (see D2a).

#### D2a. Membership is the one place null behaves as a value, not an absence

`values_equal?/2` (`lib/predicator/evaluator.ex:804-819`) backs `in` and
`contains`. Today `null in [null]` is `false` (measured), because the catch-all
at `:819` returns `false` for anything `types_match/2` rejects.

**Chosen: add `values_equal?(nil, nil), do: true`** and nothing else. `null in
[null]` becomes `true`; `null in [1]` stays `false`.

**Do not add `:undefined`-style propagation clauses to `execute_membership/2`.**
`:undefined` propagates there (`lib/predicator/evaluator.ex:846-850, 864-868`)
because it is an absence and membership of an absence is unanswerable. Null is
present, so membership of it is answerable, and the answer is identity. This is
the one asymmetry with `:undefined` in the whole plan, and it is the organizing
sentence doing its job.

*Note the resulting surface tension, deliberately accepted and documented:*
`null == null` is `:undefined` while `null in [null]` is `true`. `==` and `in`
already disagree about `:undefined` in the opposite direction
(`undefined in [undefined]` propagates `:undefined`, while `values_equal?` would
say `false`), so the two operators were never one predicate. Stating it in
`docs/isa.md` §5 is the fix, not making them agree.

#### D3. What the six bypass paths do with `nil` after this change

**Nothing changes in any of the six, and that is the point.** They keep passing
`nil` through verbatim; what changes is that `nil` now has semantics when it
arrives. Specifically:

- `Evaluator.evaluate/3` on a bare map and `Predicator.evaluator/2`: unchanged,
  now well-defined. `test/predicator/evaluator_test.exs:1523` ("bound to nil is
  bound too") keeps passing and stops documenting a boundary - it documents the
  ordinary case.
- `Context.assign/3` and `Predicator.context_assign/4`: unchanged. The
  undocumented asymmetry the research flagged (open question 3) - `assign/3`
  storing raw `nil` where `bind/3` stored `:undefined` - **is resolved by
  removing the normalization, not by adding one.** After Phase 2 both store
  `nil`. Phase 2 adds the test that was missing and Phase 3 adds the `@doc`
  sentence.
- Custom function returns: unchanged. A provider that returns `{:ok, nil}` now
  pushes a null rather than a value with no semantics.
- `host`: unchanged, and its documented exemption
  (`lib/predicator/context.ex:22-29`) becomes narrower in scope - it now exempts
  atom keys only, since `nil` values are no longer normalized anywhere. Phase 3
  edits that paragraph.

`ContextLocation.vivify/3` (`lib/predicator/context_location.ex:382-389`), which
treats `nil` and `:undefined` alike as "absent" for auto-vivification, is
**deliberately left unchanged**: writing through a null intermediate vivifies it,
same as through an undefined one. Changing it would be a breaking change to
`store`/`assign` for no consumer's benefit, and "you cannot index into a null" is
not a rule predicator enforces anywhere else (`null.foo` is `:undefined`, not an
error). Phase 3 documents it in `docs/isa.md` §5's `store` entry.

#### D4. Truthiness, and the other opcodes

**Null is falsy at a jump**, joining `false` and `:undefined`. Implemented by
widening the three guards at `lib/predicator/evaluator.ex:1642, 1666, 1685` from
`when top == false or top == :undefined` to add `or is_nil(top)`.

Reasoning: ADR-0001 fixes the falsy rule as ECMAScript-aligned and `docs/isa.md`
§2 records it as such; ECMAScript makes `null` falsy. The alternative -
`TypeMismatchError`, which is what happens today by accident, via a crash - makes
`nullable_flag AND other` blow up on exactly the sparse data the sentinel design
exists to keep usable. And it changes no answer any conforming instruction list
produces today, because a conforming list could not put a null on the stack
before this change (see ISA Impact).

Everything else follows the `:undefined` precedent unchanged:

| Opcode family | Null's behavior | New code? |
|---|---|---|
| the three jumps | falsy | 3 guard edits |
| `not` / `unary_bang` / `unary_minus` | `TypeMismatchError`, got `:null` | none, once `get_value_type/1` has a `nil` clause |
| the five arithmetic opcodes | `TypeMismatchError`, got `:null` | same |
| `compare` | see D2 | none |
| `in` / `contains` | see D2a | one `values_equal?/2` clause |
| `access` / `bracket_access` on a null target | `:undefined` | none (`lib/predicator/evaluator.ex:1201-1203` already) |
| `cast` | `:undefined` for every target | none - `Cast`'s rule 2 total-failure catch-all (`lib/predicator/cast.ex:158`) already covers it |
| `store` | vivifies through a null intermediate | none (D3) |
| `lit` | cannot carry a null - no literal exists | none |

`cast` deserves its reasoning stated: `null::string` is `:undefined`, **not**
`"null"`. `Cast`'s rule 1 (`lib/predicator/cast.ex:40`) propagates `:undefined`
specifically; rule 2 says a conversion that cannot produce a value of the target
type yields `:undefined`. Null cannot produce a string of the target type any
more than a list can. A cast is an explicit request for a typed value, and
losing the null/undefined distinction across one is correct.

The trace-back rewrite (`lib/predicator.ex:587-632`) is **not** extended to
null: `undefined_operand?/1` keys on `:undefined` only, and a null operand came
from bound data, never from an unbound root, so there is no variable to name.
No change.

#### D5. The conformance corpus: in this bead, in its own phase

**Chosen: yes, Phase 4, paying the `corpus_hash` rotation once.**

(§3's *text* widens to name null; §1's *version* rule does not fire, because
it is scoped to operand forms carried in the instruction list rather than to a
value only a host-supplied context can produce - see ISA Impact below. The two
statements are consistent, and the plan means both.)

The cost, stated plainly: adding an authored case regenerates
`conformance/manifest.json`'s `corpus_hash`, which invalidates **every existing
sibling ratchet pin** until each is re-verified (`conformance/RATCHET.md:129-171,
260-267`). That is a real cost imposed on the Ruby and JavaScript siblings.

Why pay it now anyway:

- This plan **widens `docs/isa.md` §3's value domain**. Under ADR-0003 this repo
  is the reference implementation and §3 is exported specification. A widened
  value domain that no corpus case exercises is a specification claim nothing
  enforces - precisely what `corpus_freshness_test` and `opcode_coverage_test`
  exist to prevent. Shipping the claim without the pin is the worse outcome.
- ADR-0003 documents a sibling behind the current corpus as an expected state,
  never a blocker. An invalidated pin is a re-verification, not a break.
- Deferring it to the literal half's breaking bump would bundle a value-domain
  change into a release that also changes the grammar, making the sibling diff
  harder to reason about, not easier.

**No fifth `$type` tag.** Null is JSON-native (`conformance/README.md:99-101`
already names `null` among the types JSON covers directly), so the encoding is a
bare JSON `null` and the codec change is two clauses replacing two catch-all
rejections.

**This adds `area:conformance` and `area:docs` to a bead labeled
`area:context, area:evaluator`.** Per ADR-0005 the label is a prediction and a
branch that touches an unlabeled area is worth noticing rather than silently
accepting - so Phase 0 of the work is `bd update px-o9v --labels` adding both.
Neither is `area:build`, so batching is unaffected.

#### D6. Where the documentation lands

- **`docs/isa.md`** - §2 (the falsy bullet at line 87 and the "first-class
  value" bullet at 103), §3 (the value domain at line 168), §1 (one clarifying
  sentence, see ISA Impact), and the §5 entries that state a rule for
  `:undefined`: `lit` (284-287), `compare` (299-321), `not` (347-349),
  `in`/`contains` (350-357), arithmetic (358-390), `access`/`bracket_access`
  (391-414), the jumps (448-466, 617-621), `store` (483-500), `cast` (512-545).

  `lit` is in that list for a reason that is easy to miss. Its entry reads "The
  operand may be any value in §3's value domain, `:undefined` included", so the
  moment §3 admits null, `lit`'s stated operand domain silently admits it too -
  which would contradict this plan's own ISA-neutrality argument by widening a
  named opcode's accepted type. The fix is one sentence, not an exclusion: a
  null operand is legal under the widened §3 domain, but no source spelling
  exists (unlike `:undefined`, whose literal shipped in 5.0.0), so the compiler
  never emits `["lit", nil]` and no stored artifact can contain one.
- **`docs/reference/language.md`** - the deep-normalization paragraph (551-557,
  which currently states the `nil` rule this plan removes), a new "Null and
  undefined" subsection under "Undefined and Sparse Data", and the "honest
  boundary" prose fix identified in Current State Analysis.
- **`docs/architecture.md`** - the `Predicator.Undefined` component-map entry
  (line 124) gains null's representation alongside it.
- **`CHANGELOG.md`** under `## [Unreleased]` - `### Changed` for the context
  normalization, `### Added` for null's semantics and the codec, `### Fixed` for
  the `get_value_type/1` crash.
- **`@doc`s** - `Context.new/2`, `Context.bind/3`, `Context.assign/3`, the
  `host` section, `Undefined.from_nil/1`, `Types.value()`.

`Undefined.from_nil/1` and `to_nil/1` **stay, unchanged in behavior** - they are
public API and this release is additive. Their `@doc`s gain a sentence saying
they are edge helpers for a boundary that does *not* distinguish null from
undefined, and that `Context.new/2` no longer uses `from_nil/1`. The research's
open question 4 (two definition sites for one rule) is resolved by one of the
two sites disappearing.

### Key Discoveries

- `lib/predicator/context.ex:327` - the single clause the whole bead turns on.
- `lib/predicator/evaluator.ex:1111-1124` - `get_value_type/1` has no `nil`
  clause; three call sites crash on one today. Live ADR-0004 violation.
- `lib/predicator/evaluator.ex:748-758, 790` - the four comparison answers fall
  out of existing clauses with no new code.
- `lib/predicator/evaluator.ex:1642, 1666, 1685` - the three falsy guards, the
  only behavioral widening in the plan.
- `lib/predicator/cast.ex:158` - rule 2's catch-all already handles null.
- `conformance/README.md:99-101` - the corpus already names JSON `null` as
  natively covered; no `$type` tag needed.
- `lib/predicator/undefined.ex:2-13` - the moduledoc that forecloses a struct
  representation, citing ADR-0001.
- `docs/isa.md:415` - precedent for "this bullet, not the ISA version, changed".
- ADR-0001 (ECMAScript-aligned falsiness), ADR-0003 (this repo leads the ISA),
  ADR-0004 (errors are values, never raised at a leaf), ADR-0005 (area labels as
  file-collision prediction), ADR-0011 (cast totality).

## What We're NOT Doing

- **The literal half.** No `null` keyword in the lexer, parser, reserved-word
  list, or `StringVisitor`. It is another reserved word in the class of
  `if`/`else`/`while`/`undefined` and obliges a corpus sweep at a breaking bump;
  5.0.0 shipped 2026-08-12. A follow-up bead should be filed for it - see
  Residual Notes.
- **No new opcode, no ISA version move, no grammar change.** See ISA Impact.
- **No new `$type` tag in the corpus codec.** Null is JSON-native; a bare JSON
  `null` is the encoding.
- **Not touching `ContextLocation.vivify/3`.** A write through a null
  intermediate keeps auto-vivifying (D3).
- **Not extending the trace-back rewrite** in `lib/predicator.ex:587-632` to
  null operands (D4).
- **Not removing or changing `Undefined.from_nil/1` / `to_nil/1`.** Public API,
  additive release (D6).
- **Not making `null == null` answer `true`** (D2), and not adding `:undefined`
  -style propagation to `in`/`contains` for null (D2a).
- **Not writing an ADR.** The decision is arguably ADR-shaped - "null is a
  value, undefined is an absence" is a language-semantics call with cross-repo
  consequences, comparable to ADR-0002 or ADR-0011. It is **not** written here
  because (a) `docs/isa.md` is named by CLAUDE.md as "the authority for any ISA
  question" and Phase 3 records the decision there normatively, and (b)
  `.claude/wurk/work.md` forbids a `proposed`-status ADR, and an `accepted` ADR
  is a human's call, not a plan's. If a human wants one it would be **ADR-0015**,
  it must be `accepted`, and it must be registered in `docs/adr/README.md`'s
  index (`test/docs_adr_links_test.exs` binds that index).
- **Not resolving px-a2w.** px-a2w's set of non-JSON-native operand types does
  not gain null, because null is JSON-native - `Jason.encode!(["lit", nil])` is
  `["lit",null]` and decodes back to `nil` (verified). Phase 3 adds one sentence
  to px-a2w's bead recording that, and nothing more.
- **Not refreshing the `mirrors:`/statifier note.** No scheduling, claiming, or
  status-citing of st-7ft happens in this plan, so CLAUDE.md's refresh
  obligation is not triggered. The implementer must refresh it before citing
  st-7ft's status.

## Implementation Approach

Four phases, ordered so each is independently green under full `mix quality` and
independently committable.

The ordering constraint that fixes the sequence: **Phase 1 must precede
Phase 2.** Phase 1 gives `nil` defined semantics in the evaluator; Phase 2 lets
a `nil` reach it from a `Context`. Landing Phase 2 first would ship a crash on
`Context.new(%{"flag" => nil})` followed by any predicate with an `AND`. Phase 1
alone is purely additive - it turns three crashes into error values and defines
behavior on a path that was already reachable - so nothing goes red in it.

Phases 3 and 4 are documentation and exported specification. They follow the
behavior rather than leading it so that every doctest and corpus case they add
asserts against shipped behavior.

Before Phase 1: `bd update px-o9v` to add `area:docs` and `area:conformance`
(D5). This is bead hygiene, not a commit.

## ISA Impact

Included because the change alters the behavior of three opcodes
(`jump_if_falsy_or_pop`, `jump_if_true_or_pop`, `pop_jump_if_falsy`) and widens
§3's value domain.

### 1. Version

**The ISA stays at v6. No version moves.**

The rule that pulls the other way is `docs/isa.md` §1's "Adding an operand form
or widening an accepted type is a new version but not a new name." It does not
govern here, and Phase 3 adds a clarifying sentence to §1 saying why, so the
next reader does not re-litigate it:

- §1's own stated rationale for the version integer is that it makes "scan the
  opcode names in a list" a sound answer to "what version does this list
  require". This change adds no opcode name and changes no *operand* form, so no
  name-scan can detect it. A v7 that `Instructions.required_isa/1` cannot
  express would make the integer lie, which is the reductio.
- The widening is at the **host/context boundary**, not in the instruction list.
  Before this change no *conforming* instruction list could place a null on the
  stack: §3's value domain excluded it and no opcode produced one. Null enters
  only through a host-supplied context, which §3 governs and §1's versioning rule
  does not.
- `docs/isa.md` §6 is the precedent for a value-shape change that attaches to no
  opcode name and moves no version (the `undefined` literal), and `docs/isa.md`
  line 415 is the precedent for "this bullet, not the ISA version, changed".

Library semver: **minor**, with a prominent `### Changed` entry. The behavior
that changes for a host - `Context.new(%{"x" => nil})` no longer yielding
`:undefined` - changes an input that was **already outside the declared input
type**: `Types.value()` (`lib/predicator/types.ex:53-62`) does not include
`nil`. Making a previously-undeclared input meaningful is a widening of accepted
input, not a change to documented behavior, and it is precisely what the bead
scopes as additive.

### 2. Stamp

No opcode subsection is added. What `docs/isa.md` owes, all in Phase 3:

- §1: one sentence scoping the "widening an accepted type" rule to operand forms
  in the instruction list.
- §2: null added to the falsy bullet (line 87) and to the first-class-value
  bullet (line 103).
- §3: null added to the value domain (line 168), with a sentence distinguishing
  it from `:undefined` - a value versus an absence.
- §5: a rule for null in every entry that states one for `:undefined` (the list
  is in D6).
- Conformance tier: the new cases go in **tier 1**, which is where `core`'s
  existing `undefined` cases live - null needs no opcode beyond `load`,
  `access`, `compare`, and the jumps, all of which are tier 1.

### 3. Migration

**Every instruction list compiled before this change runs and produces the same
answer.** No stored compiled artifact is affected, because no such artifact can
contain a null: `lit` has no null operand form (no literal exists), and the only
other way a null reaches the stack is a host-supplied context, which is not part
of the artifact. No upgrade path is required.

---

## Phase 1: Null is a value the evaluator understands

### Overview

Give `nil` defined semantics inside the evaluator, without changing what
`Context` does. Purely additive: three crash sites become error values, the
jumps gain a falsy case, membership gains identity, and `Types.value()` widens.
Nothing that passes today changes answer.

### Changes Required:

#### 1. The value type

**File**: `lib/predicator/types.ex`
**Changes**: add `nil` to `value()` and to the typedoc's bullet list, naming it
as distinct from `:undefined`.

```elixir
  @type value ::
          boolean()
          | integer()
          | float()
          | binary()
          | list()
          | Date.t()
          | DateTime.t()
          | duration()
          | :undefined
          | nil
```

The typedoc gains, alongside the existing `:undefined` bullet:

```
  - `nil` - the null value: present, but with no content. Distinct from
    `:undefined`, which is an absence. `nil === :undefined` is `false`.
```

#### 2. Type reporting - the ADR-0004 fix

**File**: `lib/predicator/evaluator.ex`
**Changes**: add a `nil` clause to `get_value_type/1`, before the `is_map/1`
clause (it cannot match `nil`, but keeping the atom clauses together beside
`:undefined` at line 1119 is the readable placement).

```elixir
  defp get_value_type(nil), do: :null
```

This is what turns `not null`, `null + 1`, `-null`, and a null at a jump from a
raised `FunctionClauseError` into a `TypeMismatchError` value.

#### 3. Falsiness at the three jumps

**File**: `lib/predicator/evaluator.ex`
**Changes**: widen the guards at `:1642-1643`, `:1666-1667`, and `:1686-1687`
(the last is `execute_pop_jump_if_falsy/2`'s falsy clause, two lines below its
`@spec`).

```elixir
  defp execute_jump_if_falsy_or_pop(%__MODULE__{stack: [top | _rest]} = evaluator, offset)
       when top == false or top == :undefined or is_nil(top) do
```

Same edit in `execute_jump_if_true_or_pop/2`'s falsy clause and
`execute_pop_jump_if_falsy/2`'s falsy clause. The comment above
`execute_pop_jump_if_falsy/2` and any nearby comment naming the falsy set gets
null added.

#### 4. Membership identity

**File**: `lib/predicator/evaluator.ex`
**Changes**: one clause in `values_equal?/2`, placed after the two `:undefined`
clauses (`:805-806`) and before the `Date` clauses, with a comment stating why
null differs from `:undefined` here.

```elixir
  # Null is a value, not an absence: membership of it is answerable, and the
  # answer is identity. `:undefined` above is the opposite case (px-o9v).
  defp values_equal?(nil, nil), do: true
```

`execute_membership/2` is **not** touched.

#### 5. Tests

**File**: `test/predicator/evaluator_test.exs`
**Changes**: a `describe "null as a value (px-o9v)"` block driving
`Evaluator.evaluate/3` with a bare map (the bypass path that already exists), one
test per row of D4's table plus D2's four comparisons. Every one of the three
former crash sites gets an explicit assertion that the result is a
`TypeMismatchError` with `got: :null`, not a raise.

### Success Criteria:

#### Automated Verification:
- [x] Full `mix quality` passes (format, compile, credo --strict, dialyzer, deps
      audit, suite with coverage).
- [x] Coverage stays above the 90% minimum in `coveralls.json` for
      `Predicator.Evaluator` and `Predicator.Types`.
- [x] `mix test test/predicator/evaluator_test.exs` covers all four D2 rows, all
      three former crash sites (asserting an error *value*, not a raise), the
      three jump opcodes' falsy path, and `null in [null]` / `null in [1]`.
- [x] No existing test changes. `git diff --stat` on `test/` shows additions
      only, and `test/predicator/evaluator_test.exs:1523`,
      `test/predicator/context_location_test.exs:424`,
      `test/predicator/undefined_test.exs`, and `test/predicator/types_test.exs`
      are untouched and green.
- [x] `test/predicator/context_test.exs` is untouched and fully green - Phase 1
      changes no `Context` behavior.

#### Manual Verification:
- [ ] `Predicator.Evaluator.evaluate([["load","x"],["not"]], %{"x" => nil})`
      returns a `TypeMismatchError` naming `:null`, not a crash.
- [ ] A short-circuit over a null reads correctly:
      `Predicator.Evaluator.evaluate/3` on `"flag AND other"`-shaped
      instructions with `%{"flag" => nil}` short-circuits rather than erroring.
- [ ] No regressions in `:undefined`'s own behavior anywhere in the suite.

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution, pause here for
the manual confirmation. Under `--loop`, the automated criteria gate advancement
and the manual items are deferred to the end.

**A note on `is_nil/1` vs `== nil`**: the existing guards spell the test
`top == false or top == :undefined`. Use `is_nil(top)` for the new disjunct
rather than `top == nil` - credo prefers it and it reads unambiguously.

---

## Phase 2: Context stops collapsing null into undefined

### Overview

Remove the one clause, update the seven assertions that bind it, and add the
tests that pin the new distinguishability. This is the phase that satisfies
acceptance criterion (a).

### Changes Required:

#### 1. The normalization

**File**: `lib/predicator/context.ex`
**Changes**: delete `normalize_value(nil), do: Undefined.value()` (`:327`). The
scalar catch-all at `:337` then carries `nil` through unchanged, along with
`:undefined` itself, which a host may still bind explicitly.

Update the comment block at `:321-325` - it currently opens "Deeply converts
`nil` to `Undefined.value()` and, for plain maps, atom keys to string keys". The
function is now atom-key normalization only.

Remove the now-unused `Undefined` alias from `lib/predicator/context.ex:43` if
nothing else in the module references it (check before deleting - the gate will
catch an unused alias either way).

#### 2. The `@doc`s and their doctests

**File**: `lib/predicator/context.ex`
**Changes**:

- `new/2`'s doc (`:96-102`): "atom keys become string keys ... and `nil` values
  become the `:undefined` sentinel" becomes atom keys only, plus a sentence
  saying `nil` is preserved as the null value and pointing at
  `docs/reference/language.md`.
- The doctest at `:109-110` becomes:

  ```elixir
      iex> Predicator.Context.new(%{user: %{name: nil}}).data
      %{"user" => %{"name" => nil}}
  ```

- `bind/3`'s doc (`:217-222`) and its doctest at `:231-232`: the same two edits.
- `assign/3`'s doc (`:281-303`): add a sentence that `value` is stored verbatim,
  the same as `bind/3` stores a scalar - the asymmetry the research flagged is
  gone.
- The `host` section (`:22-29`): narrow "atom keys and `nil` values inside a
  `host` term are never touched" to atom keys, since `nil` values are no longer
  touched anywhere.
- Add one doctest to `new/2` demonstrating the acceptance criterion directly:

  ```elixir
      iex> context = Predicator.Context.new(%{"x" => nil})
      iex> {Predicator.Context.bound?(context, "x"), Predicator.evaluate("x === undefined", context)}
      {true, {:ok, false}}
  ```

#### 3. `Undefined`'s doc note

**File**: `lib/predicator/undefined.ex`
**Changes**: `from_nil/1` (`:65-79`) and `to_nil/1` (`:46-60`) gain a sentence
each: these are edge helpers for a boundary that does **not** distinguish null
from undefined, and `Context.new/2` no longer calls `from_nil/1` - a `nil` in a
context is now the null value. Behavior and specs unchanged.

#### 4. The seven red assertions

**File**: `test/predicator/context_test.exs`
**Changes**: four tests, updated to assert `nil` rather than `:undefined` and
renamed to say what they now guard:

- `:142` `"deeply converts nil to :undefined in nested maps"` becomes a test that
  atom keys convert deeply **and** `nil` survives:
  `%{"user" => %{"name" => nil}}` (`:145`).
- `:154` - `%{"items" => [%{"label" => "a"}, %{"label" => nil}]}` (`:157`).
- `:290` - `%{"user" => %{"role" => nil}}` (`:294`).
- `:349` - the title `"true for a string key bound to nil, eagerly normalized to
  :undefined"` becomes `"true for a string key bound to nil, which stays null"`;
  `:354` asserts `%{"x" => nil}`. `:355` (`bound?/2`) and `:356`
  (`evaluate("x > 5") == {:ok, :undefined}`) both keep their current
  expectations - `nil` vs `5` still hits `compare_values/3`'s catch-all.

**File**: `test/predicator/integration/on_unbound_test.exs`
**Changes**: `:128`'s test - `"x === undefined with x bound to nil is true under
either policy - Context normalizes nil"` - is the assertion this bead exists to
invert. It becomes `"x === undefined with x bound to nil is false under either
policy - null is not undefined"`, asserting `{:ok, false}` under both policies
and, under `:error`, that no `UndefinedVariableError` fires because the key is
present.

#### 5. New tests pinning the distinguishability

**File**: `test/predicator/context_test.exs`
**Changes**: a `describe "null is not undefined (px-o9v)"` block:

- `Context.new(%{"x" => nil}).data == %{"x" => nil}`
- `Context.bind(ctx, "x", nil).data == %{"x" => nil}`
- `{:ok, ctx} = Context.assign(ctx, "user.name", nil)` stores `nil`, and
  `Context.bind(ctx, "user", %{"name" => nil})` stores the same - the asymmetry
  is gone (the test the research noted did not exist).
- a host can still bind an explicit `:undefined`:
  `Context.new(%{"x" => :undefined}).data == %{"x" => :undefined}`
- `Context.new(%{"x" => nil})` and `Context.new(%{})` are distinguishable:
  `bound?/2` is `true` and `false` respectively, and
  `Predicator.evaluate("x === undefined", ...)` is `{:ok, false}` vs an
  `UndefinedVariableError`.
- a nested null: `Predicator.evaluate("user.name === undefined", Context.new(%{"user" => %{"name" => nil}}))`
  is `{:ok, false}`, while the same predicate against `%{"user" => %{}}` is
  `{:ok, true}`. This is the statifier event-payload case in miniature.

### Success Criteria:

#### Automated Verification:
- [x] Full `mix quality` passes.
- [x] Coverage stays above the 90% minimum for `Predicator.Context`.
- [x] `grep -n 'normalize_value(nil)' lib/` returns nothing.
- [x] All seven previously-red assertions are updated and green; the whole
      `test/predicator/context_test.exs` and
      `test/predicator/integration/on_unbound_test.exs` suites pass.
- [x] `test/predicator/undefined_test.exs` and `test/predicator/types_test.exs`
      are untouched and green - `from_nil/1`'s behavior did not change.
- [x] `mix test test/docs_examples_test.exs` passes (it executes
      `docs/reference/language.md`'s Elixir blocks; none puts a `nil` in a
      context today, so this should stay green through Phase 2 and is the guard
      that proves it).

#### Manual Verification:
- [ ] `Predicator.evaluate("x === undefined", Predicator.Context.new(%{"x" => nil}))`
      returns `{:ok, false}`, and the same predicate against `Context.new(%{})`
      returns an `UndefinedVariableError`. This is acceptance criterion (a),
      confirmed by hand.
- [ ] A decoded JSON payload works end to end without host-side conversion:
      `Jason.decode!(~s({"foo": null, "bar": 1}))` bound with `bind/3`, then
      `_event.data.foo === undefined`-shaped access, answers `false`.
- [ ] No regression in `on_unbound: :error` for a genuinely absent root.

**Implementation Note**: Use the loop gate between edits, full `mix quality` as
the phase gate. Interactive execution pauses here; `--loop` defers the manual
items.

---

## Phase 3: Documentation - the ISA, the language reference, the changelog

### Overview

Record the decisions normatively. This phase carries acceptance criterion (b):
the comparison semantics between null and undefined are decided and documented
under `docs/`.

### Changes Required:

#### 1. `docs/isa.md`

**File**: `docs/isa.md`
**Changes**:

- **§1** - one sentence after the "Adding an operand form or widening an
  accepted type is a new version but not a new name" bullet, scoping it: the
  rule speaks to operand forms carried *in the instruction list*; widening the
  §3 value domain with a value only a host-supplied context can produce moves no
  version, because no opcode-name scan can express it (see §6's precedent).
- **§2, line 87** - the falsy bullet becomes: `false`, `null`, or `:undefined`,
  and nothing else. Keep the ADR-0001 citation.
- **§2, line 103** - the first-class-value bullet gains null, with the
  distinguishing sentence: `:undefined` is an absence, `null` is a value that is
  present and empty; the opcodes treat them alike at a jump and differently
  under `===` and membership.
- **§3, line 168** - null joins the value domain, with a sentence on its
  relationship to `:undefined` and a note that it has no source spelling: it
  enters only through a host-supplied context, a `load`, an `access`, or a
  function return, never through `lit`.
- **§5** - a rule for null in each entry that states one for `:undefined`:
  `lit` (284-287, a null operand is legal under the widened §3 domain but has
  no source spelling, so the compiler never emits one - see D6 for why omitting
  this entry would undercut the ISA Impact argument),
  `compare` (299-321, D2's four rows), `not` (347-349, rejected, got `:null`),
  `in`/`contains` (350-357, identity via `values_equal?/2`, **not**
  propagation - state the contrast with `:undefined` explicitly), arithmetic
  (358-390, rejected), `access`/`bracket_access` (391-414, a null target pushes
  `:undefined`), the jumps (448-466, 617-621, falsy), `store` (483-500, a null
  interior slot auto-vivifies, same as `:undefined`), `cast` (512-545, null casts
  to `:undefined` for every target by rule 2, **not** by rule 1 - state that it
  is total failure, not propagation, and add a `null` row to the matrix at 545).

#### 2. `docs/reference/language.md`

**File**: `docs/reference/language.md`
**Changes**:

- Lines 551-557 - the deep-normalization paragraph. `nil` no longer becomes
  `:undefined`; atom-key normalization is unchanged.
- A new `### Null and undefined` subsection inside "Undefined and Sparse Data",
  carrying: the one-sentence rule (a value versus an absence), D2's four-row
  table, D2a's membership note, falsiness, the cast answer, and the honest
  statement that **there is no way to write a null in predicate text today** -
  a null enters only from the host, and `x === undefined` answering `false` is
  how a predicate observes one. Any Elixir example block in this subsection is
  executed by `test/docs_examples_test.exs`, so every one must be a real,
  passing expression.
- The "honest boundary" prose that currently instructs a reader to use
  `Predicator.Context.new(%{"x" => nil})` "which normalizes to `:undefined`" -
  rewrite to bind `Predicator.Undefined.value()` explicitly, which
  `normalize_value/1`'s scalar catch-all preserves.
- Line 14's literal list and the reserved-words section (394-405) are **not**
  touched: `null` is not a keyword.

#### 3. `docs/architecture.md`

**File**: `docs/architecture.md`
**Changes**: the `Predicator.Undefined` component-map entry (line 124) gains a
clause naming `nil` as the null value and pointing at `docs/isa.md` §3 for the
distinction. No new component.

#### 4. `CHANGELOG.md`

**File**: `CHANGELOG.md`
**Changes**: under `## [Unreleased]`, matching the `[5.0.0]` entry's voice:

- `### Changed` - `Context.new/2` and `bind/3` no longer rewrite `nil` to
  `:undefined`. State the observable consequence
  (`x === undefined` on a nil-bound variable flips from `true` to `false`), the
  reason it is not a breaking bump (`Types.value()` never declared `nil` as an
  input), and the migration for a host that wanted the old behavior: bind
  `Predicator.Undefined.value()` explicitly.
- `### Added` - null as a value in the ISA value domain: falsy at a jump,
  rejected by `not` and arithmetic, `:undefined` under every non-strict
  comparison, identity under `===` and membership. **The ISA version does not
  move** - use the `[5.0.0]` entry's phrasing.
- `### Fixed` - a `nil` operand reaching `not`, `unary_minus`, `unary_bang`, the
  arithmetic opcodes, or a jump raised `FunctionClauseError` instead of
  returning a `TypeMismatchError` value (ADR-0004).

#### 5. The px-a2w note

**Changes**: `bd update px-a2w` (or `bd note`) recording that null is JSON-native
and therefore does *not* join px-a2w's set of non-JSON-native operand types -
`Jason.encode!(["lit", nil])` is `["lit",null]` and round-trips. One note; px-a2w
is not otherwise touched.

### Success Criteria:

#### Automated Verification:
- [x] Full `mix quality` passes.
- [x] `mix test test/docs_examples_test.exs` passes - every Elixir block added to
      `docs/reference/language.md` executes and produces the documented result.
- [x] `mix test test/predicator/isa_sync_test.exs` passes - `docs/isa.md` still
      agrees with `lib/predicator/instructions.ex`. No opcode was added, so this
      should be unmoved; a failure means §5 was edited in a way that changed the
      opcode table.
- [x] `mix test test/docs_adr_links_test.exs` passes - every ADR link added in
      prose resolves.
- [x] `grep -n 'normalizes to `:undefined`' docs/reference/language.md` returns
      nothing.
- [x] `## [Unreleased]` in `CHANGELOG.md` is non-empty and carries `### Changed`,
      `### Added`, and `### Fixed`.

#### Manual Verification:
- [ ] Read `docs/isa.md` §5 end to end: every entry that names `:undefined` also
      names null, and no entry states a rule the evaluator does not implement.
      Cross-check against D4's table.
- [ ] The new language-reference subsection is usable by someone who has never
      read this plan: it answers "how do I put a null in a context", "how does a
      predicate tell null from undefined", and "why can't I write `null`".
- [ ] The `### Changed` changelog entry is honest about the flipped answer and
      states the migration.

**Implementation Note**: Loop gate between edits, full `mix quality` as the phase
gate. This phase changes no Elixir behavior, but it does add doctests via
`docs_examples_test.exs`, so the gate is meaningful.

---

## Phase 4: The conformance corpus

### Overview

Pin null in the exported specification. Two codec clauses, a round-trip entry,
two contract-document rows, authored cases, and one `corpus_hash` rotation.

### Changes Required:

#### 1. The codec

**File**: `lib/predicator/conformance/values.ex`
**Changes**: replace two catch-all rejections with two identity clauses. Place
each before the existing `is_binary or is_number or is_boolean` clause.

```elixir
  # Null is JSON-native: it encodes as a bare JSON null, with no $type tag.
  # `:undefined` above needs a tag because JSON has no absence; null does not
  # (px-o9v).
  def to_json(nil), do: {:ok, nil}
```

```elixir
  def from_json(nil), do: {:ok, nil}
```

Update the moduledoc (`:1-27`): it currently says §3's value domain "also
includes `Date`, `DateTime`, duration, and `:undefined`, none of which JSON can
represent directly". Null is the value that *is* directly representable, so it
belongs in the "means itself" sentence, called out explicitly because a reader
would otherwise assume a fifth tag.

Confirm `encode_plain_map/1`/`decode_plain_map/1` and the list encoders route a
`nil` member through `to_json/1`/`from_json/1` and therefore need no change -
they do, since they recurse; the gate's round-trip test proves it.

#### 2. The round-trip property

**File**: `test/predicator/conformance/values_test.exs`
**Changes**: add to `@round_trip_values` (`:11-33`):

```elixir
    nil,
    [1, nil, 3],
    %{"present" => nil, "absent" => :undefined},
```

The third entry is the one that matters: it proves the codec keeps null and
undefined distinct through a full JSON round trip inside a map, which is the
statifier payload shape.

Update the comment at `:7-9` ("Every ISA value type ... and `:undefined`") to
name null.

#### 3. The contract documents

**File**: `conformance/README.md`
**Changes**: the tagged-value section (`:98-145`) opens "Four things do not fit"
- unchanged, since null still does not need a tag. Add a sentence immediately
after the table stating that a bare JSON `null` decodes to predicator's null
value and is **not** the same as `{"$type": "undefined"}`, with a pointer to
`docs/isa.md` §3. This is the sentence a sibling implementer needs and the one
place they would otherwise guess.

**File**: `conformance/RATCHET.md`
**Changes**: the reference-runner decode note (`:227-228`) currently reads
"`$type` of `date`, `datetime`, `duration`, `undefined`; everything else decodes
as itself". Add the explicit carve-out: a JSON `null` decodes as itself, to the
null value, and a runner that maps it to its undefined must not.

#### 4. Authored cases

**File**: `conformance/cases/core.json` (beside the existing
`core/literal-undefined` family at `:73-92`)
**Changes**: add tier-1 cases, each evaluator-only where no source spelling
exists (`"source": null`, the existing convention at
`conformance/schema/case.json:13-16`):

- `core/null-strict-eq-undefined` - context `{"x": null}`, `x === undefined`,
  expected `false`. **The acceptance-criterion case.**
- `core/null-strict-eq-null` - expected `true`.
- `core/null-eq-undefined-propagates` - expected `{"$type": "undefined"}`.
- `core/null-eq-null-propagates` - expected `{"$type": "undefined"}`.
- `core/null-is-falsy-at-jump` - a short-circuit over a null.
- `core/null-rejected-by-not` - expected error `type: type_mismatch`.
- `core/null-in-list-identity` - `null in [null]`, expected `true`.
- `core/null-cast-is-undefined` - `null::string`, expected
  `{"$type": "undefined"}`.
- `access/null-member-is-not-missing` (in `conformance/cases/access.json`) -
  context `{"user": {"name": null}}`, `user.name === undefined` expected
  `false`, paired against the existing missing-key case. This is the statifier
  bug, pinned.

Then `mix corpus.generate`.

**Never hand-edit `conformance/corpus/*.json` or `conformance/manifest.json`** -
they are generated (CLAUDE.md).

#### 5. The commit and PR body

Per ADR-0003 and `.claude/wurk/plan.md`'s corpus criteria, the corpus diff moves
the exported specification, so the commit message and the PR body must state:
what the cases pin, that `corpus_hash` rotated, and that every sibling ratchet
pin needs re-verification against the new hash. Point at
`conformance/RATCHET.md:129-171`.

### Success Criteria:

#### Automated Verification:
- [ ] Full `mix quality` passes.
- [ ] `mix corpus.generate` produces no diff on a second run (idempotent), and
      `mix test test/predicator/conformance/corpus_freshness_test.exs` passes -
      the checked-in corpus byte-matches a regeneration.
- [ ] `mix test test/predicator/conformance/schema_validation_test.exs` passes -
      every new authored case and the regenerated corpus and manifest validate.
- [ ] `mix test test/predicator/conformance/values_test.exs` passes, including
      the round-trip property over the three new entries.
- [ ] `mix test test/predicator/conformance/opcode_coverage_test.exs` and
      `ratchet_registry_test.exs` and `package_boundary_test.exs` pass.
- [ ] `git diff conformance/manifest.json` shows `corpus_hash` changed - the
      expected, explained rotation, not a surprise.
- [ ] Coverage stays above the 90% minimum for
      `Predicator.Conformance.Values`.

#### Manual Verification:
- [ ] Hand-decode `core/null-strict-eq-undefined` out of the generated
      `conformance/corpus/tier-1.json` and confirm a sibling implementer reading
      only `conformance/README.md` would decode the bare `null` correctly and
      not conflate it with `{"$type": "undefined"}`.
- [ ] The commit message and PR body explain the corpus diff and the
      `corpus_hash` rotation (ADR-0003).
- [ ] `conformance/RATCHET.md`'s carve-out sentence is unambiguous read cold.

**Implementation Note**: Loop gate between edits, full `mix quality` as the phase
gate. This phase's sabotage-note obligation is already satisfied: every test it
touches (`values_test.exs`, `corpus_freshness_test.exs`,
`schema_validation_test.exs`) is already listed in `gate.sabotage.test_roots` in
`.claude/wurk.json`, and this phase adds no test file. No `test_roots` edit is
needed - confirm that before committing.

---

## Testing Strategy

### Unit Tests

- **`test/predicator/evaluator_test.exs`** (Phase 1) - null's behavior under
  every opcode family, driven through `Evaluator.evaluate/3` on a bare map. The
  edge cases that actually bite: the three former crash sites (assert an error
  *value*, with `got: :null`); the four-row comparison matrix; `null in [null]`
  versus `null in [1]`; a null at each of the three jump opcodes; `null::string`;
  `null.foo`. Existing `:undefined` tests are the control - none may change.
- **`test/predicator/context_test.exs`** (Phase 2) - the four updated
  assertions plus the new `describe "null is not undefined (px-o9v)"` block:
  `new/2`, `bind/3`, and `assign/3` all storing `nil`; an explicitly bound
  `:undefined` still surviving; and null-bound versus absent being
  distinguishable by both `bound?/2` and `x === undefined`.
- **`test/predicator/conformance/values_test.exs`** (Phase 4) - the round-trip
  property extended over `nil`, a list containing one, and a map holding both a
  null and an `:undefined`.
- **Coverage** - every new clause is reachable from a test: `get_value_type(nil)`
  via any rejecting opcode, `values_equal?(nil, nil)` via `in`, each of the three
  widened jump guards via its own opcode, and both codec clauses via the
  round-trip list.

### Integration Tests

- **`test/predicator/integration/on_unbound_test.exs`** (Phase 2) - the inverted
  `:128` test under both `on_unbound` policies, plus a case confirming a
  genuinely absent root still errors under `:error` while a null-bound one does
  not. End-to-end through `Predicator.evaluate/3`, per this project's integration
  convention.
- A new end-to-end case in the same file for the statifier shape: a nested null
  inside a bound map, reached by dot access, answering `false` to
  `=== undefined` where a missing key answers `true`.

### Manual Testing Steps

1. In `iex -S mix`, confirm the acceptance criterion directly:
   `ctx = Predicator.Context.new(%{"x" => nil})`, then `ctx.data`,
   `Predicator.Context.bound?(ctx, "x")`, and
   `Predicator.evaluate("x === undefined", ctx)` - expect `%{"x" => nil}`,
   `true`, `{:ok, false}`.
2. Compare against absence: `Predicator.evaluate("x === undefined", Predicator.Context.new(%{}))`
   - expect an `UndefinedVariableError`, and `{:ok, true}` under a policy that
   permits it. Confirm the two are distinguishable at the API surface.
3. Decode a JSON payload with `Jason.decode!(~s({"foo": null, "bar": 1}))`, bind
   it, and evaluate `data.foo === undefined` and `data.baz === undefined` -
   expect `{:ok, false}` and `{:ok, true}`. This is the statifier bug and its
   control, side by side.
4. Confirm no raise: evaluate `not x`, `x + 1`, and `-x` against `%{"x" => nil}`
   through `Predicator.Evaluator.evaluate/3` - each returns a `TypeMismatchError`
   value naming `:null`.
5. Read the generated `conformance/corpus/tier-1.json` for one null case and
   confirm the bare JSON `null` is present and untagged.

## Residual Notes

These are recorded here rather than left as open questions, because each has a
decision attached and only the follow-up action is outstanding.

1. **A follow-up bead for the literal half is warranted, and this plan does not
   file it.** The value half leaves a real gap: a predicate author cannot write
   `null`, so the only in-predicate observation of a null is
   `x === undefined` answering `false` - an indirect and unobvious idiom.
   Whoever implements this should file a `px-` bead for the literal half, blocked
   on the next breaking bump, carrying `area:lexer-parser`, `area:visitors`,
   `area:docs`, `area:conformance`, and referencing this plan's D2 as the settled
   comparison semantics it must not re-decide. It is named here rather than filed
   here because filing it is `/wurk:issue`'s job and it is not this bead's work.
2. **st-7ft (statifier) is not refreshed by this plan.** CLAUDE.md's
   `mirrors:` obligation fires on scheduling, claiming, planning against, or
   citing the status of a mirrored bead. This plan does none of those - it
   implements predicator's own decision, which ADR-0010 makes this repo's to own.
   The implementer must re-read st-7ft and write a dated note **before** citing
   its status anywhere.
3. **The area labels on px-o9v are wrong for the branch this plan produces.**
   It carries `area:context, area:evaluator`; Phases 3 and 4 add `area:docs` and
   `area:conformance`. Per ADR-0005 the label is a prediction worth correcting
   when the prediction misses. Fix it with `bd update` before Phase 1.
4. **ADR-0015 is a human's call.** See "What We're NOT Doing" for what one would
   owe if a human decides the "null is a value, undefined is an absence" rule
   deserves its own ADR. This plan records the decision in `docs/isa.md` instead,
   which CLAUDE.md names as the authority for ISA questions.

## References

- Source document: `docs/research/260813-px-o9v-null-vs-undefined-in-context.md`
- Bead: `px-o9v`
- Related ADRs: `docs/adr/0001-keep-the-stack-vm-revise-the-instruction-set.md`
  (ECMAScript-aligned falsiness; the instruction list as interchange format),
  `docs/adr/0003-the-elixir-implementation-leads-the-isa.md` (this repo leads the
  ISA; the corpus is exported specification),
  `docs/adr/0004-no-eval-errors-are-values.md` (the `get_value_type/1` fix),
  `docs/adr/0005-worktree-parallelism-and-the-area-label-algebra.md` (the label
  correction), `docs/adr/0010-tracker-authority-and-the-mirror-obligation.md`
  (st-7ft), `docs/adr/0011-casts-are-an-opcode.md` (cast totality)
- Specification: `docs/isa.md` §1 (line 58, ISA v6), §2 (84-107), §3 (166-180),
  §5, §6 (678-681)
- Language reference: `docs/reference/language.md:14, 394-405, 551-557, 563-601,
  634-645, 710-780`
- The collapse: `lib/predicator/context.ex:327`, `:126`, `:236`
- The evaluator seams: `lib/predicator/evaluator.ex:748-758, 790, 804-819,
  1111-1124, 1642, 1666, 1685`
- The codec: `lib/predicator/conformance/values.ex:71, 96, 123, 153`
- The corpus contract: `conformance/README.md:98-145`,
  `conformance/RATCHET.md:129-171, 227-228, 260-267`
- Prior plans: `docs/plans/260805-px-8um.2-context-key-normalization.md` (the
  normalization this plan partly removes),
  `docs/plans/260812-px-ocp-undefined-literal.md` (the ISA-neutrality precedent)

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] `Predicator.Evaluator.evaluate([["load","x"],["not"]], %{"x" => nil})`
      returns a `TypeMismatchError` naming `:null`, not a crash.
- [ ] A short-circuit over a null reads correctly:
      `Predicator.Evaluator.evaluate/3` on `"flag AND other"`-shaped
      instructions with `%{"flag" => nil}` short-circuits rather than erroring.
- [ ] No regressions in `:undefined`'s own behavior anywhere in the suite.

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution, pause here for
the manual confirmation. Under `--loop`, the automated criteria gate advancement
and the manual items are deferred to the end.

**A note on `is_nil/1` vs `== nil`**: the existing guards spell the test
`top == false or top == :undefined`. Use `is_nil(top)` for the new disjunct
rather than `top == nil` - credo prefers it and it reads unambiguously.

---

### Phase 2

- [ ] `Predicator.evaluate("x === undefined", Predicator.Context.new(%{"x" => nil}))`
      returns `{:ok, false}`, and the same predicate against `Context.new(%{})`
      returns an `UndefinedVariableError`. This is acceptance criterion (a),
      confirmed by hand.
- [ ] A decoded JSON payload works end to end without host-side conversion:
      `Jason.decode!(~s({"foo": null, "bar": 1}))` bound with `bind/3`, then
      `_event.data.foo === undefined`-shaped access, answers `false`.
- [ ] No regression in `on_unbound: :error` for a genuinely absent root.

**Implementation Note**: Use the loop gate between edits, full `mix quality` as
the phase gate. Interactive execution pauses here; `--loop` defers the manual
items.

---

### Phase 3

- [ ] Read `docs/isa.md` §5 end to end: every entry that names `:undefined` also
      names null, and no entry states a rule the evaluator does not implement.
      Cross-check against D4's table.
- [ ] The new language-reference subsection is usable by someone who has never
      read this plan: it answers "how do I put a null in a context", "how does a
      predicate tell null from undefined", and "why can't I write `null`".
- [ ] The `### Changed` changelog entry is honest about the flipped answer and
      states the migration.

**Implementation Note**: Loop gate between edits, full `mix quality` as the phase
gate. This phase changes no Elixir behavior, but it does add doctests via
`docs_examples_test.exs`, so the gate is meaningful.

---
