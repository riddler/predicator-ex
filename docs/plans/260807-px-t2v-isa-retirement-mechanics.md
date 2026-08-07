# ISA Opcode Retirement Mechanics Implementation Plan

## Overview

`docs/isa.md`'s entire retirement policy is one sentence (§1, `:33-35`), and
px-tbv.9 is about to execute the first retirement against it. This plan settles
the three mechanics that sentence leaves open - whether retirement mints a new
ISA version, what marker keeps a retired opcode answerable by `required_isa/1`,
and what the conformance corpus does with cases the reference evaluator can no
longer run - writes them into `docs/isa.md`, and makes each of them checkable in
the suite.

Beads issue: **px-t2v** (`area:conformance`, `area:docs`; this plan adds
`area:evaluator`). Blocks **px-tbv.9**, which retires `and`/`or`.

This plan does **not** retire `and`/`or`. It lands the mechanism with no opcode
carrying a marker, so px-tbv.9 becomes a data change (add `removed_in: 3`, drop
two evaluator clauses, regenerate) rather than a mechanism change.

Research: `docs/research/260807-px-t2v-px-z5m-isa-retirement-and-pop.md`.
Governing ADR: **ADR-0003** (this plan writes no ADR; ADR-0003 already governs
how the instruction set moves).

## Current State Analysis

### The one-sentence policy

`docs/isa.md:33-35`:

> An additive version - new opcodes only, every existing instruction list still
> valid - ships in a minor release. Retiring an opcode invalidates stored
> artifacts and takes a major release plus an upgrade path.

ADR-0003 says the same at `:92-97` and `:113-121` and is equally silent on the
ISA integer. Nothing anywhere says what a version's opcode set means once that
set can shrink.

### The opcode table has no status field

`lib/predicator/instructions.ex:34-60` - `@opcodes` is a 25-entry map whose
values are exactly `%{isa: integer, tier: integer}`. There is no `removed_in`,
no `since`, no `status`. `opcodes/0`'s `@spec` (`:77`) hard-codes that two-key
shape.

`required_isa/1` (`:158-167`) and `tier/1` (`:100-114`) both answer from
`Map.fetch/2` on that map and both construct `unknown_opcode` on a miss. So
deleting the `and`/`or` rows is exactly the failure px-t2v names: a stored
pre-3.7 artifact stops being refused "with a message naming the version it
needs" (ADR-0003 `:113-121`) and starts being refused with `unknown_opcode`.

### Four (really five) independent mechanisms constrain the marker's shape

1. **Two `@opcode_count 25` assertions** (`test/predicator/isa_sync_test.exs:27`,
   asserted at `:41-43` against `docs/isa.md`'s table rows and at `:121-124`
   against `execute_instruction/2` clause heads). They are independent surfaces
   bound to one literal; a retirement that keeps doc rows but drops evaluator
   clauses makes them disagree.
2. **The per-row round-trip** (`:45-57`): every opcode with a row in §4 must
   answer `{:ok, version}` from `required_isa/1` **and** `{:ok, tier}` from
   `tier/1`. A doc row with no map entry fails; a map entry answering an error
   tuple fails.
3. **The tier-names set equality** (`:77-104`): each tier row's opcode list must
   equal *exactly* the set the map assigns that tier. Not a subset.
4. **The row regex's column rules** (`:144`): column 1 is a bare backticked
   `[a-z_]+`, column 5 is exactly `v\d+`, column 6 is exactly `\d+`, and the
   regex stops after column 6's closing pipe - anything past it is invisible.
5. **(Not named in the research doc, and it bites.)** `isa_sync_test.exs:60-65`
   asserts `isa_version/0` equals the max version in the §4 table, reading
   column 5 only.
   A retirement that mints v3 without introducing a v3 opcode puts no `v3`
   anywhere in column 5, so `@isa_version 3` fails this assertion. Whatever
   marker is chosen must therefore also be *readable as a version* by this
   assertion.

Plus, on the corpus side: `opcode_coverage_test.exs:27-39` requires a case for
every key of `opcodes/0` and `:51-58` binds `@excluded_opcodes` to
`conformance/README.md` by set equality.

### The corpus cannot generate a case the evaluator cannot run

`Generator.evaluate_case/2` (`lib/predicator/conformance/generator.ex:222-231`)
runs the **real** `Predicator.evaluate/3`, and `check_expected/2` (`:271-288`)
fails the case when the authored `expected` disagrees. The five authored legacy
cases in `conformance/cases/legacy.json` are completed that way. Remove the
evaluator's `and`/`or` clauses and all five flip to `unknown_instruction`, fail
`check_expected/2`, and `mix corpus.generate` writes nothing.

`compute_tier/1` (`:326-347`) fails *earlier* still if the opcode also leaves the
map - `Instructions.tier/1` returns an error and there is no fallback tier.

There is **no per-ISA-version corpus snapshot**: one `conformance/corpus/`, one
`manifest.json` with one `isa_version`, one `corpus_hash`
(`lib/mix/tasks/corpus.generate.ex:139-143`), one pinned
`registry.example.json`.

## Desired End State

`docs/isa.md` states, and the suite enforces, that:

1. **Retiring an opcode mints the next ISA integer.** A version's opcode set is
   the half-open interval `[introduced, removed_in)`, so a version's set is
   fixed forever once minted and shrinkage happens only at the new version.
2. **A retired opcode keeps its row** in `@opcodes`, in §4's table, and in the
   tier-names table, gaining an optional `removed_in:` key and an eighth doc
   column. It loses exactly one thing: its `execute_instruction/2` clause.
   `required_isa/1` and `tier/1` keep answering for it.
3. **A retired case stays in the live corpus with a frozen expectation.** The
   generator stops running it through the evaluator, uses its authored
   `expected` as data, and tags it `retired`. `corpus_hash`, case ids, the
   ratchet pin, and the exclusion list are all untouched by the mechanism.

Verification: `mix quality` green, and specifically -

- `mix corpus.generate --check` reports no drift (the mechanism is a no-op today
  because no opcode carries a marker);
- `conformance/manifest.json`, `conformance/corpus/*.json`, and
  `conformance/examples/registry.example.json` are **byte-identical** to their
  pre-plan contents, so `corpus_hash` has not moved;
- the new `Instructions` functions have doctests covering both the live and the
  retired branch, using synthetic table entries for the retired branch;
- `Generator.generate/2`'s retired path is exercised by unit tests that inject a
  synthetic retired-opcode set, so no real retirement is needed to cover it.

### Key Discoveries

- `required_isa(list) <= isa_version()` is **necessary but not sufficient** once
  retirement exists: a retired `and` still reports `isa: 1`, so `1 <= 3` passes
  while the v3 build cannot run it. Membership in the version's opcode set is
  the sound check, and it subsumes both conditions.
  (`lib/predicator/instructions.ex:158-167`.)
- §7 already defines v1 as "the full opcode set the Elixir evaluator accepted
  before ADR-0001" (`docs/isa.md:392-395`) - a version's set anchored to a
  historical evaluator, not the live table. The interval rule generalizes that
  existing sentence rather than contradicting it.
- A **new column 8** is the one place a marker can live in the §4 table without
  touching the existing regex (`isa_sync_test.exs:144` stops after column 6).
- `tier_row_opcodes/1` (`isa_sync_test.exs:174-183`) returns `[]` for any tier
  cell **starting with `(`** - see "Mechanical trap" below.
- The manifest's per-tier `opcodes` arrays are derived from
  `Instructions.opcodes/0` (`generator.ex:419-441`), so they move the moment the
  map does, independently of which cases exist.
- `Features.outcome_tags/1` has a `{:error, _other}` catch-all
  (`features.ex:145`), so a synthesized outcome for a frozen case produces the
  same `errors` tag the real error struct produces. Frozen cases therefore keep
  their feature tags byte-stable.

### Mechanical trap (research doc item 7, restated as a constraint)

**The tier-6 cell must keep its leading `(`.** `docs/isa.md:137` reads
`| 6 | statements | (none yet - reserved for `store`) |`, and it contributes
zero opcodes to the tier-names equality *solely because the cell starts with a
paren*. Any rewording that drops the leading `(` makes `store` a required entry
in `@opcodes`, which contradicts `test/predicator/instructions_test.exs:102-108`
("store is currently an unknown opcode") and adds an uncoverable opcode to
`opcode_coverage_test.exs`. **No phase in this plan edits that row.** px-z5m,
which does edit it, inherits the same constraint.

## What We're NOT Doing

- **Not retiring `and`/`or`.** No opcode gains a `removed_in:` value here. That
  is px-tbv.9: evaluator clauses, `upgrade/1`, CHANGELOG breaking-change entry.
- **Not bumping `@isa_version`.** It stays 2. v3 is minted by px-tbv.9, which is
  the release that actually removes something.
- **Not writing an ADR.** ADR-0003 governs; this plan cites it.
- **Not touching px-z5m's surface.** No edits to §2 (halt / `empty_stack`), §6
  (reserved names), or the tier-names table. §4's tier table is read but not
  written.
- **Not adding a frozen per-version corpus tree.** See decision (c).
- **Not changing `required_isa/1`'s return shape.** It keeps returning
  `{:ok, minimum_introducing_version}`; three doctests and the isa_sync
  round-trip depend on it.
- **Not adding `store` or `pop` to anything.**

## Implementation Approach

### Decision (a): retirement mints a new ISA version, and a version's opcode set is an interval

**Chosen.** Retiring an opcode mints the next ISA integer, *in addition to*
taking a major library release and an upgrade path. Each opcode carries a
half-open interval `[isa, removed_in)`; ISA version *V*'s opcode set is every
opcode whose interval contains *V*. A version's set is therefore immutable once
minted - retiring at v3 does not change what v2 was - and "a sibling claiming v2"
claims exactly v2's set, `and`/`or` included, forever.

Rationale: without a new integer, a v2 build that no longer runs `and` is
indistinguishable from one that does, and the stamp check `required_isa(list) <=
isa_version()` returns *pass* for a list the build will refuse - the precise
silent-mis-run failure ADR-0003's version stamp exists to eliminate
(`adr/0003:113-121`). The interval also preserves §1's soundness argument that
"scan the opcode names in a list" answers the version question, because every
name still maps to an interval.

Rejected: *retirement is a library-major event only, no integer moves.* It keeps
§7's history table simpler, but leaves siblings with no way to name the
distinction and leaves the stamp unsound in exactly the case it was built for.

Consequence recorded in the plan: the runnability check a consumer or sibling
performs is **membership in `opcode_set(isa_version())`**, not the `<=`
comparison alone. `required_isa/1` remains the function that produces the number
for the refusal message; `retired_in/1` produces the other half of it.

### Decision (b): `removed_in:` as an optional map key plus an eighth doc column

**Chosen shape.**

- `@opcodes` values gain an **optional** `:removed_in` key, present only on
  retired opcodes: `"and" => %{isa: 1, tier: 1, removed_in: 3}`.
- `opcodes/0`'s `@spec` **widens** to
  `%{optional(String.t()) => %{:isa => pos_integer(), :tier => pos_integer(), optional(:removed_in) => pos_integer()}}`.
  Yes, the two-key value shape must widen - it is a spec change as well as a
  data change.
- `docs/isa.md` §4's table gains **column 8, "Removed in"**, cell content `-` or
  `vN`. Columns 1-7 are untouched and keep their order.

How each constraining mechanism is satisfied:

| Mechanism | How it is satisfied | Does a count change? |
|---|---|---|
| `@opcode_count 25` vs the §4 table (`isa_sync_test:41-43`) | A retired opcode **keeps its row**. The doc-row count is the size of `@opcodes`, retired entries included. | **No.** Stays 25 here and stays 25 through px-tbv.9. |
| `@opcode_count 25` vs evaluator clause heads (`isa_sync_test:121-124`) | This surface *does* shrink on retirement, so the literal is replaced by a **derived** expectation: `map_size(opcodes()) - number of retired opcodes`. Two new directional assertions replace what the literal was really guarding: every live opcode has a clause, and every retired opcode has none. | **No** today (25 - 0 = 25); px-tbv.9 gets 23 with no test edit. |
| Round-trip through `required_isa/1` and `tier/1` (`isa_sync_test:45-57`) | Satisfied by construction: the map entry survives retirement, so both keep returning `{:ok, _}`. This is the whole point of the marker over deletion, and it is what discharges ADR-0003's "refused with a message naming the version it needs". | n/a |
| Tier-names set equality (`isa_sync_test:77-104`) | A retired opcode **stays in its tier cell** (`and`, `or` remain in tier 1's list) because it stays in the map. Zero edits to that table. | n/a |
| Row regex column rules (`isa_sync_test:144`) | Column 8 is past the regex's stopping point, so the existing regex is unmodified. A **second, new** regex reads columns 1 and 8 and binds the cell to `retired_in/1`. | n/a |
| Max-version assertion (`isa_sync_test:60-65`) - the fifth mechanism | Widened to take the max over column 5 **and** column 8, so a `v3` appearing only as a retirement version still moves the expected `isa_version/0`. | n/a |
| Opcode coverage (`opcode_coverage_test:27-39`) | Switched from `opcodes() |> Map.keys()` to `opcode_set(isa_version())`, so a retired opcode leaves the coverage requirement automatically. | See (c) - the exclusion list does **not** grow. |

Rejected marker shapes:

- *Annotating the opcode cell* (`` `and` (removed in 4.0) ``). Fragile: it
  survives the §4 regex by accident but is scanned as a bare opcode name by
  `tier_row_opcodes/1`, and it encodes a *library* version where the ISA integer
  belongs.
- *A `status:` enum (`:live | :retired`)*. Loses the version, which is the one
  fact the refusal message needs.
- *Deleting the row and keeping a separate `@retired_opcodes` map*. Two tables
  that can disagree, and every consumer of `opcodes/0` has to remember to
  consult both. One table with an optional key is the smaller surface.

### Decision (c): live corpus, frozen expectations for retired cases

**Chosen.** A case whose instructions use an opcode retired at or below the
build's ISA version is a **retired case**. It stays in the live corpus, at its
existing tier, with its existing id. The generator does not run it through the
evaluator; it takes the case's authored `expected` as data, and adds a `retired`
feature tag. Two rules make it well-formed:

- A retired case **must author `expected`** - generation fails naming the case
  and the opcode otherwise, because nothing can compute the value any more.
- A retired case **must be `instructions`-authored** (`source: null`) - the
  compiler cannot emit a retired opcode, so a `source` would compile to
  something else. Generation fails otherwise.

Effects on the three things the bead names:

- **`corpus_hash`** - unmoved by this plan (no opcode is retired, so no case
  takes the frozen path and every byte is regenerated identically). At px-tbv.9
  it moves only by the `retired` feature tag added to the five legacy cases;
  their `expected_result`/`expected_error`, tier, ids, and every other field are
  unchanged, and the `errors` tag survives via `outcome_tags/1`'s `{:error, _}`
  catch-all. `hash_corpus/1` covers the tier files only, so the manifest's own
  churn does not enter it (`corpus.generate.ex:116-126, 139-143`).
- **`opcode_coverage_test.exs`'s exclusion list** - **unchanged**,
  `~w(relative_date)`, and `conformance/README.md`'s bound section is untouched.
  Retirement is a version boundary, not an exclusion: the coverage rule is
  re-pointed at `opcode_set(isa_version())`, so a retired opcode drops out of the
  requirement without anybody editing a list. This is the payoff that made the
  interval rule worth choosing.
- **px-35i.8's ratchet pin** - **unchanged**. Case ids survive, so RATCHET.md
  rule 1 (`RATCHET.md:129-158`) still resolves every entry, and R5 completeness
  (`ratchet_registry_test.exs:107-130`) still finds an evaluator-surface entry
  for every tier-1 case. `registry.example.json` is byte-identical here; at
  px-tbv.9 it needs regenerating only because `corpus_hash` moves, which the
  existing pin test already catches (`:78-92`). RATCHET.md gains one paragraph
  stating that a retired case remains a member of the evaluator surface's case
  set and is absent from the compiler surface's - which is already true of every
  `source: null` case, so no rule changes.

Rejected:

- *Frozen per-version snapshot* (`conformance/corpus-v2/` with its own manifest
  and hash). It is a second artifact nothing regenerates, so nothing detects
  drift in it, and the ratchet's single `corpus_hash` pin cannot name it without
  a format change to RATCHET.md - which px-35i.8 has already shipped and which
  this bead is not chartered to reopen.
- *Dropping v1 coverage.* ADR-0003 makes "a sibling behind the current version"
  a supported, documented state (`:99-111`, `:196-198`); a corpus that cannot
  certify v1 makes that state unverifiable, which is the opposite of what the
  corpus is for.
- *A `legacy_logical`-style hand-written tag as the whole mechanism.* The tag is
  a fine selector and it is kept, but it does not solve the actual blocker:
  generation fails before tagging, because `evaluate_case/2` runs the real
  evaluator. The frozen-expectation path is what unblocks it; the tag is the
  runner-facing half.

### Why the mechanism lands with no opcode carrying a marker

Chosen deliberately. The alternative - fold the mechanism into px-tbv.9 - would
put spec, mechanism, corpus tooling, evaluator surgery, an `upgrade/1` function,
and a breaking CHANGELOG entry into one branch, and would mean the retirement
rule gets designed under the pressure of executing it. Splitting keeps px-t2v's
diff a no-op at runtime (every artifact byte-identical) and reduces px-tbv.9 to
data plus deletions.

The cost is that the retired branches have no production data exercising them.
That is paid with **injectable seams rather than dead code**: `in_isa?/2` is a
pure predicate over an explicit entry map (doctestable with synthetic entries),
and `Generator.generate/2` takes a `:retired_opcodes` option defaulting to the
real table, so unit tests exercise the frozen path, the missing-`expected`
error, and the `source`-present error at full coverage.

## Phase 1: The `removed_in` marker in `Predicator.Instructions`

### Overview

Widen the opcode table's value shape and add the three queries the interval rule
needs. No opcode gains a marker; every existing return value is unchanged.

### Changes Required:

#### 1. The opcode table and its spec

**File**: `lib/predicator/instructions.ex`
**Changes**: extend the `@opcodes` comment (`:29-33`) to document the optional
`:removed_in` key and the interval rule, citing `docs/isa.md` §1 and §4. Widen
`opcodes/0`'s `@spec` (`:77`) to the three-key form with `optional(:removed_in)`.
Add an `@type opcode_info` so the shape is named once.

```elixir
@typedoc """
One opcode's table entry: the ISA version that introduced it, its conformance
tier, and - only when it has been retired - the ISA version that removed it.
An opcode is in ISA version `v` iff `isa <= v < removed_in` (docs/isa.md §1);
an entry with no `:removed_in` key has never been retired.
"""
@type opcode_info :: %{
        :isa => pos_integer(),
        :tier => pos_integer(),
        optional(:removed_in) => pos_integer()
      }
```

#### 2. `in_isa?/2` - the interval predicate

**File**: `lib/predicator/instructions.ex`
**Changes**: new public function, pure, over an explicit entry. This is the seam
that makes the retired branch coverable today.

```elixir
@spec in_isa?(opcode_info(), pos_integer()) :: boolean()
def in_isa?(%{isa: introduced} = info, version)
    when is_integer(version) and version > 0 do
  case Map.fetch(info, :removed_in) do
    {:ok, removed_in} -> introduced <= version and version < removed_in
    :error -> introduced <= version
  end
end
```

Doctests cover: live opcode in range, live opcode below its introducing version,
retired opcode at a version before removal, retired opcode at the removing
version, retired opcode after it.

#### 3. `opcode_set/1` - what a version comprises

**File**: `lib/predicator/instructions.ex`
**Changes**: new public function returning the opcode names in a given ISA
version. This is the executable form of decision (a)'s second half and the
membership test that supersedes a bare `<=` comparison.

```elixir
@spec opcode_set(pos_integer()) :: MapSet.t(String.t())
def opcode_set(version) when is_integer(version) and version > 0 do
  for {opcode, info} <- @opcodes, in_isa?(info, version), into: MapSet.new(), do: opcode
end
```

Its `@doc` states the rule a consumer applies: a build running ISA version `v`
can run an instruction list iff every opcode in it is a member of
`opcode_set(v)`, and that `required_isa/1` alone stops being sufficient once any
opcode is retired.

#### 4. `retired_in/1` - the marker read

**File**: `lib/predicator/instructions.ex`
**Changes**: new public function mirroring `tier/1`, including its
`unknown_opcode` error with `operation: :retired_in`.

```elixir
@spec retired_in(String.t()) :: {:ok, pos_integer() | nil} | {:error, EvaluationError.t()}
```

`{:ok, nil}` means "never retired". The `@doc` names it as the source of the
second half of ADR-0003's refusal message: `required_isa/1` names the version
the list needs, `retired_in/1` names the version that removed the opcode.

#### 5. Moduledoc

**File**: `lib/predicator/instructions.ex:2-21`
**Changes**: one paragraph on retirement - a retired opcode keeps its row so
`required_isa/1` and `tier/1` keep answering with a version rather than
`unknown_opcode`; a version's opcode set is an interval and is fixed once
minted.

#### 6. Tests

**File**: `test/predicator/instructions_test.exs`
**Changes**: unit tests for `in_isa?/2` (synthetic entries, both branches),
`opcode_set/1` (`opcode_set(1)` excludes the three v2 opcodes; `opcode_set(2)`
is all 25; `opcode_set(2)` equals `Map.keys(opcodes())` today), and
`retired_in/1` (`{:ok, nil}` for every live opcode, `unknown_opcode` for a name
not in the table). Add a test asserting **no opcode currently carries
`:removed_in`**, with a comment that px-tbv.9 flips it intentionally - the
mirror of the existing "store is currently an unknown opcode" test at `:102-108`.

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality`
- [x] New doctests run and pass (`mix test --only doctest` covered by the gate)
- [x] Coverage for `Predicator.Instructions` stays above the 90% minimum in
      `coveralls.json`, with both `in_isa?/2` branches covered
- [x] `mix corpus.generate --check` reports no drift (this phase changes no
      generated bytes)

#### Manual Verification:
- [ ] In `iex`, `Instructions.opcode_set(1)` and `opcode_set(2)` differ by
      exactly `jump_if_falsy_or_pop`, `jump_if_true_or_pop`, `make_list`
- [ ] `retired_in("and")` reads as `{:ok, nil}`, not an error

**Implementation Note**: Use `mix quality --profile loop` between edits; full
`mix quality` is the phase gate.

---

## Phase 2: The spec text in `docs/isa.md` and its bindings

### Overview

Write the retirement rules into the spec and bind the new column to the map. No
section is renumbered and no existing section is reordered, which is what keeps
this diff off px-z5m's edits.

### Changes Required:

#### 1. §1 Versioning

**File**: `docs/isa.md` (the bullet list at `:23-38`)
**Changes**: replace the single retirement bullet (`:33-35`) with three, keeping
the surrounding bullets and their order intact:

- Additive version rule (unchanged wording, split out).
- **Retirement mints the next ISA integer** and takes a major library release
  plus an upgrade path. The integer moves because a build that no longer runs an
  opcode must be distinguishable from one that does; without it the version
  stamp reports a list runnable that the build will refuse.
- **A version's opcode set is a half-open interval.** Each opcode is introduced
  at one version and, if ever retired, removed at another; version *v*'s set is
  every opcode with `introduced <= v < removed_in`. A version's set is fixed
  once minted - retiring at v3 does not change what v2 was - so a sibling
  declaring v2 claims v2's whole set, retired opcodes included.
- A closing sentence on the runtime form: the check a consumer performs is
  membership in `Predicator.Instructions.opcode_set/1` for this build's version;
  `required_isa/1` still names the version a list needs, and
  `retired_in/1` names the version that removed an opcode, which together are
  what makes a refusal message name a version rather than say "unknown opcode".

`Current version: **ISA v2**.` at `:40` is untouched.

#### 2. §4 preamble and table

**File**: `docs/isa.md:112-121` and the table at `:147-173`
**Changes**:

- Amend the membership sentence. "One row per opcode the evaluator accepts" ->
  one row per opcode **the ISA has ever contained**, including opcodes the
  compiler no longer emits and opcodes a later version retired. A retired opcode
  keeps its row so the version scan stays total.
- Add **Removed in** to the column list, and add column 8 to every row with
  cell `-`.

```
| Opcode | Operands | Pops | Pushes | ISA | Tier | Emitted by compiler | Removed in |
|---|---|---|---|---|---|---|---|
| `lit` | value | 0 | 1 | v1 | 1 | yes | - |
...
| `and` | - | 2 | 1 | v1 | 1 | no | - |
```

- Add a short `### Retired opcodes` subsection after the table (before §5)
  stating: the marker is the **ISA version that removed it**, not a library
  version; a retired opcode keeps its row, its map entry, and its tier-table
  membership, and loses only its evaluator clause; the corpus keeps its cases
  with frozen expectations (forward reference to §8 and
  `conformance/README.md`); and an upgrade path is required (ADR-0003 `:113-121`).

**The tier-names table at `:130-137` is not edited.** Its tier-6 cell keeps its
leading `(` - see "Mechanical trap" above.

#### 3. §7 Version history

**File**: `docs/isa.md:381-395`
**Changes**: add an **Opcodes retired** column; existing rows get `-`. Add a
sentence: the table now records both ends of each opcode's interval, and a
version whose only change is a retirement still gets a row. Keep the existing
paragraph defining v1 as the pre-ADR-0001 set - it is the same interval rule
stated for the first version, and the new bullets in §1 generalize it.

```
| ISA | Opcodes introduced | Opcodes retired | Shipped in |
|---|---|---|---|
| v1 | everything not listed below | - | up to 3.6.x |
| v2 | `jump_if_falsy_or_pop`, `jump_if_true_or_pop`, `make_list` | - | 3.7.0 |
```

(Neither `@isa_table_row_regex` nor `@tier_table_row_regex` matches §7's rows -
column 1 is `v1`/`v2`, which is neither a backticked opcode nor bare digits - so
the added column is inert to both.)

#### 4. Bind column 8 to the map

**File**: `test/predicator/isa_sync_test.exs`
**Changes**:

- New `@isa_removed_column_regex` reading columns 1 and 8, deliberately separate
  from `@isa_table_row_regex` so the existing count and round-trip assertions
  carry no new risk:

```elixir
# Matches the same rows as @isa_table_row_regex, capturing column 1 (the
# opcode) and column 8 ("Removed in"): "-" for a live opcode, "vN" for one
# retired at ISA vN. Kept separate from @isa_table_row_regex so that regex -
# and the row count and round-trip assertions built on it - is unchanged by
# the column's arrival.
@isa_removed_column_regex ~r/^\|\s*`([a-z_]+)`\s*\|(?:[^|]*\|){6}\s*(\S+)\s*\|\s*$/m
```

- A test asserting this regex matches `@opcode_count` rows (the same vacuity
  guard the existing regex carries) and that, per row,
  `Instructions.retired_in(opcode)` agrees with the cell: `-` maps to
  `{:ok, nil}`, `vN` to `{:ok, N}`, anything else fails with a message naming
  the accepted cell forms.
- Widen the max-version assertion (`:60-65`) to take the max over the ISA column
  **and** the Removed-in column, with a comment explaining why: a retirement-only
  version appears nowhere in column 5.
- Replace the second `@opcode_count` use (`:121-124`) with a derived expectation
  and two directional assertions:

```elixir
# Retired opcodes keep their table row and lose their evaluator clause
# (docs/isa.md section 4, "Retired opcodes"), so the clause-head count is the
# live opcode count, not the table size. Deriving it means a retirement needs
# no edit here - and the two assertions below are what the literal was really
# guarding: no live opcode without a clause, no retired opcode with one.
live = Instructions.opcode_set(Instructions.isa_version())
assert MapSet.size(clause_head_opcodes) == MapSet.size(live)
assert MapSet.difference(live, clause_head_opcodes) == MapSet.new()
assert MapSet.intersection(clause_head_opcodes, retired_opcodes) == MapSet.new()
```

- Update `@opcode_count`'s comment to say it is the **table** size (retired rows
  included) and that the evaluator surface is now derived from it.

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality`
- [x] `test/predicator/isa_sync_test.exs` passes with all four bindings green
      (row count, round-trip, tier-names equality, removed-column agreement)
- [x] The removed-column regex matches 25 rows, not 0 - the vacuity guard fires
      if the column layout drifts
- [x] `mix corpus.generate --check` still reports no drift

#### Manual Verification:
- [ ] §1 reads as a rule a sibling implementer can apply without reading this
      plan: what mints a version, and what version *v* comprises
- [ ] Temporarily setting `"and" => %{isa: 1, tier: 1, removed_in: 3}` in
      `@opcodes` produces a red suite that names the *doc column* disagreement
      and the *evaluator clause still present* disagreement - then revert
- [ ] The §4 table still renders as a table in a markdown preview with 8 columns

---

## Phase 3: The corpus policy

### Overview

Teach the generator the frozen-expectation path, re-point the coverage rule at
the version's opcode set, and write the policy into `conformance/README.md` and
`conformance/RATCHET.md`. Every generated byte stays identical.

### Changes Required:

#### 1. The generator's retired-case path

**File**: `lib/predicator/conformance/generator.ex`
**Changes**: `generate/1` becomes `generate/2` with an options keyword list; the
only option is `:retired_opcodes`, a `MapSet` defaulting to the opcodes absent
from `Instructions.opcode_set(Instructions.isa_version())` but present in
`opcodes/0`. Existing callers are unaffected by the default argument.

In `generate_case/2`, after `resolve_instructions/1` and before
`evaluate_case/2`, classify the case:

```elixir
# A case using an opcode this build's ISA version has retired cannot be
# completed by the reference evaluator - there is no clause left to run it
# (docs/isa.md section 4, "Retired opcodes"). Its authored `expected` is
# frozen as data instead: the case keeps its id, its tier, and its place in
# the live corpus so a sibling claiming an earlier version still has it, and
# so the ratchet's case ids keep resolving.
```

- `retired_opcodes_used/2` returns the sorted retired opcodes in the case's
  instructions.
- If empty, the existing pipeline runs unchanged.
- If non-empty:
  - fail if the case authored `source` - "a case using retired opcode(s) X must
    author `instructions`; the compiler cannot emit a retired opcode";
  - fail if the case has no `expected` - "a case using retired opcode(s) X must
    author `expected`; the reference evaluator can no longer compute it";
  - otherwise take `expected` verbatim as `expected_result` / `expected_error`,
    synthesize the outcome for feature computation (`{:result, decoded}` via
    `Values.from_json/1` for a result, `{:error, :retired}` for an error - which
    `outcome_tags/1`'s `{:error, _other}` catch-all at `features.ex:145` maps to
    `errors`, the same tag the real struct produces), and append `"retired"` to
    the case's features.

`compute_tier/1` needs no change: the retired opcode keeps its map row, so
`Instructions.tier/1` still answers. That is the single most load-bearing
consequence of decision (b) and deserves a comment at the call site.

#### 2. The manifest

**File**: `lib/predicator/conformance/generator.ex:407-441`
**Changes**: `build_manifest/1` and `group_by_tier/1` filter the opcode table
through `Instructions.opcode_set(Instructions.isa_version())`, so each tier's
`opcodes` array lists what that tier unlocks **at this corpus's ISA version**. A
no-op today (`opcode_set(2)` is the whole table), so `manifest.json` is
byte-identical; at px-tbv.9 the retired names leave the array while their cases
remain, which is the intended reading and is documented in the README change
below.

#### 3. Coverage

**File**: `test/predicator/conformance/opcode_coverage_test.exs:30-32`
**Changes**: `expected` is built from `Instructions.opcode_set(Instructions.isa_version())`
rather than `Instructions.opcodes() |> Map.keys()`, with a comment that
retirement removes an opcode from the coverage requirement by version, not by
exclusion. `@excluded_opcodes` stays `~w(relative_date)`;
`readme_excluded_opcodes/0`'s `known_opcodes` sanity filter keeps reading the
full table (a retired name in that section should still be recognized as an
opcode). The moduledoc gains a sentence on the distinction.

#### 4. `conformance/README.md`

**File**: `conformance/README.md`
**Changes**:

- In "The two surfaces" (`:41-48`), amend the `source: null` paragraph: the
  claim that the legacy opcodes "must still run **forever**" is ADR-0001's, and
  ADR-0003 amended it - retirement at a version is permitted with an upgrade
  path. The surface rule itself does not change.
- New subsection "Retired opcodes and their cases": a case using an opcode
  retired at or below the corpus's `isa_version` keeps its id, tier, and place
  in the tier file; its expectation is **frozen** from the authored case rather
  than recomputed; it carries the `retired` feature tag; it is necessarily
  `source: null`. A runner targeting the current version filters `retired` out;
  a runner claiming an earlier version runs them, and that is what makes an
  earlier-version claim verifiable. Note explicitly that the manifest's per-tier
  `opcodes` array lists what the tier unlocks at the manifest's `isa_version`,
  so a retired opcode leaves that array while its cases stay in the file.
- **"Opcodes excluded from the coverage rule" is not edited.** Add one sentence
  to the retired-opcodes subsection saying so and why: retirement is a version
  boundary, not an exclusion, and the coverage rule reads the version's opcode
  set.

#### 5. `conformance/RATCHET.md`

**File**: `conformance/RATCHET.md` (rule 1's surface-set restatement, `:129-158`)
**Changes**: one paragraph, no rule change - a retired case remains a member of
the **evaluator** surface's case set and is absent from the **compiler**
surface's, exactly as any `source: null` case is, so rule 1, the tier check, and
R5 completeness all continue to resolve its id. A retirement moves
`corpus_hash`, which is an ordinary pin refresh (rule 1's "corpus drift under a
pinned version"), not a new failure mode.

#### 6. Tests

**File**: `test/predicator/conformance/generator_test.exs` (and a small addition
to `test/mix/tasks/corpus_generate_test.exs` if the option needs plumbing there)
**Changes**: unit tests passing `retired_opcodes: MapSet.new(["and"])` against
synthetic cases -

- a frozen result case: `expected_result` equals the authored value, tier is
  still 1, features include `retired` and `legacy_logical`;
- a frozen error case: `expected_error` equals the authored error map, features
  include `retired` and `errors`;
- a retired case with no `expected` fails, and the message names the opcode;
- a retired case authoring `source` fails, and the message names the opcode;
- a case using no retired opcode is unaffected when the option is passed;
- the default option value is empty today, so `generate/1` and
  `generate/2` with no `:retired_opcodes` agree.

**File**: `test/predicator/conformance/corpus_freshness_test.exs`
**Changes**: none needed - it already byte-compares every generated file and is
the assertion that this phase moved nothing.

### Success Criteria:

#### Automated Verification:
- [ ] Full quality gate passes: `mix quality`
- [ ] `mix corpus.generate --check` reports no drift
- [ ] `git diff --stat conformance/` shows **only** `README.md` and `RATCHET.md`
      changed - no `corpus/*.json`, no `manifest.json`, no
      `examples/registry.example.json`
- [ ] `test/predicator/conformance/ratchet_registry_test.exs` passes unchanged,
      including the `corpus_hash` pin
- [ ] `opcode_coverage_test.exs`'s three tests pass with `@excluded_opcodes`
      still `~w(relative_date)`
- [ ] Coverage for `Predicator.Conformance.Generator` stays above 90% with the
      retired path exercised

#### Manual Verification:
- [ ] Read `conformance/README.md`'s new subsection as a sibling implementer:
      it says what to do with a `retired`-tagged case at each version claim
- [ ] `RATCHET.md`'s paragraph makes clear no ratchet rule changed

---

## Phase 4: Changelog and bead bookkeeping

### Overview

The user-facing surface added by phases 1-3, and the `bd` steps the bead's
acceptance criteria ask for. No Elixir changes, so there is no gate to run
beyond the previous phase's green - this phase commits on review of the diff
(CLAUDE.md's authority table).

### Changes Required:

#### 1. CHANGELOG

**File**: `CHANGELOG.md`, under `## [Unreleased]`
**Changes**: an **Added** entry for `Predicator.Instructions.in_isa?/2`,
`opcode_set/1`, and `retired_in/1`, and the widened `opcodes/0` value shape
(`:removed_in` is optional and absent today, so no existing consumer breaks); a
**Changed** entry noting `docs/isa.md` now specifies retirement mechanics -
retirement mints an ISA version, retired opcodes keep their table rows, and the
corpus freezes their cases. No breaking change here; px-tbv.9 owns that entry.

Note per CLAUDE.md: adding entries under `## [Unreleased]` is ordinary work and
is **not** a release request.

#### 2. Bead bookkeeping

**File**: none - `bd` only.
**Changes**:

- `bd update px-t2v --labels ...` to add **`area:evaluator`**. The bead carries
  `area:conformance, area:docs` today, but this plan edits
  `lib/predicator/instructions.ex` and `test/predicator/isa_sync_test.exs`,
  which CLAUDE.md's `area:conformance` note explicitly assigns to
  `area:evaluator`. The label is a prediction and this one was short - worth
  correcting at merge time rather than silently accepting.
- `bd note px-tbv.9` recording the three settled rules and where they live:
  retirement mints ISA v3 and `@isa_version` moves with it; mark both opcodes
  with `removed_in: 3` in `@opcodes` and `v3` in `docs/isa.md` §4's "Removed in"
  column, **keeping** their rows, their tier-1 membership, and their evaluator
  clause *removal* as the only deletion; the five `legacy.json` cases stay in
  the corpus and are regenerated onto the frozen path, which moves `corpus_hash`
  and obliges a regenerated `registry.example.json`.
- Verify with `bd show px-tbv.9` that its `DEPENDS ON` edge to px-t2v is
  present - it is today - which is the bead's final acceptance clause,
  "px-tbv.9 blocked on this bead". This is a `bd` verification step, **not** a
  file edit.
- Close-out follows CLAUDE.md's authority table: `bd close px-t2v` only after
  the branch is merged into `origin/main`, verified against the remote.

### Success Criteria:

#### Automated Verification:
- [ ] `mix quality` still green (unchanged from Phase 3; no Elixir moved)
- [ ] `bd show px-t2v` lists `area:evaluator` among its labels
- [ ] `bd show px-tbv.9` shows `→ px-t2v` under `DEPENDS ON`

#### Manual Verification:
- [ ] The CHANGELOG entry describes the change from a consumer's point of view,
      not the plan's
- [ ] px-tbv.9's note is specific enough that its implementer does not have to
      re-derive any of the three decisions

---

## Testing Strategy

### Unit Tests

- `test/predicator/instructions_test.exs` - `in_isa?/2` over synthetic entries
  (both branches, both boundary conditions: `version == removed_in` is out,
  `version == removed_in - 1` is in); `opcode_set/1` at v1 and v2; `retired_in/1`
  for a live opcode, and `unknown_opcode` for an unknown name; the "no opcode is
  retired yet" guard.
- `test/predicator/conformance/generator_test.exs` - the frozen path via the
  injected `:retired_opcodes` set: result case, error case, missing `expected`,
  authored `source`, non-retired case unaffected, default option is empty.

### Integration Tests

- `test/predicator/isa_sync_test.exs` - the doc/map bindings, now four: row count
  and round-trip (unchanged), tier-names equality (unchanged), the Removed-in
  column, and the derived evaluator-clause expectation with its two directional
  assertions.
- `test/predicator/conformance/corpus_freshness_test.exs` and
  `mix corpus.generate --check` - the assertion that the whole plan is a
  generated-byte no-op.
- `test/predicator/conformance/ratchet_registry_test.exs` - unchanged and still
  green, which is the evidence px-35i.8's pin is untouched.

### Manual Testing Steps

1. Apply a throwaway `removed_in: 3` to `"and"` in `@opcodes` and run
   `mix test test/predicator/isa_sync_test.exs`. Expect red naming (i) the
   Removed-in column disagreement and (ii) an evaluator clause present for a
   retired opcode. Revert.
2. With that same throwaway marker plus `@isa_version 3` and the two `and`/`or`
   clauses commented out of the evaluator, run `mix corpus.generate --check`.
   Expect the five legacy cases to regenerate through the frozen path and the
   only diff to be the `retired` feature tag plus `corpus_hash`. Revert. This is
   the dry run of px-tbv.9 and the strongest evidence the mechanism works.
3. Read §1 and §4's new subsection top to bottom as a sibling implementer with
   no context from this plan.

## ISA Impact

1. **Version** - **no bump.** This plan adds, removes, renames, and alters no
   opcode; `@isa_version` stays 2 and `Current version: **ISA v2**.` is
   untouched. What it changes is the *rule* for how the integer moves: from here
   on, retiring an opcode mints the next integer. px-tbv.9 is the first
   application and mints v3.
2. **Stamp** - `docs/isa.md` §1 gains the retirement and interval rules, §4
   gains a "Removed in" column plus a "Retired opcodes" subsection, §7 gains an
   "Opcodes retired" column. No opcode subsection is added because no opcode is
   added. The conformance tier assignment of every opcode is unchanged.
3. **Migration** - none is owed here: every instruction list valid before this
   plan is valid after it and produces the same answer, and every generated
   corpus byte is identical. The migration this plan *specifies* is the one
   px-tbv.9 will owe: an upgrade path rewriting a pre-3.7 `["and"]`/`["or"]` list
   into jump form, refused in the meantime with a message naming both the version
   the list needs (`required_isa/1`) and the version that retired the opcode
   (`retired_in/1`).

A sibling behind the current ISA version is an expected, documented state
(ADR-0003) - and decision (c) is what keeps that state *verifiable* after a
retirement.

## References

- Beads issue: `px-t2v`; unblocks `px-tbv.9`
- Research: `docs/research/260807-px-t2v-px-z5m-isa-retirement-and-pop.md`
  (Open Questions 1-4 and 7 are the questions this plan answers)
- ADR: `docs/adr/0003-the-elixir-implementation-leads-the-isa.md:92-97`,
  `:113-121`, `:167-173`, `:191-195`; `docs/adr/0001-keep-the-stack-vm-revise-the-instruction-set.md:74-76`, `:116-118`
- Spec: `docs/isa.md:23-44` (§1), `:110-178` (§4), `:234-243` (`and`/`or`),
  `:381-395` (§7), `:397-413` (§8)
- Code: `lib/predicator/instructions.ex:27`, `:34-60`, `:77-78`, `:100-114`,
  `:158-193`; `lib/predicator/conformance/generator.ex:110-130`, `:222-231`,
  `:271-288`, `:326-347`, `:407-441`;
  `lib/predicator/conformance/features.ex:102-107`, `:139-150`;
  `lib/mix/tasks/corpus.generate.ex:52-70`, `:116-126`, `:139-143`
- Tests: `test/predicator/isa_sync_test.exs:23-27`, `:41-69`, `:77-104`,
  `:121-131`, `:135-183`; `test/predicator/instructions_test.exs:102-108`;
  `test/predicator/conformance/opcode_coverage_test.exs:25-58`;
  `test/predicator/conformance/corpus_freshness_test.exs:19-30`;
  `test/predicator/conformance/ratchet_registry_test.exs:40-130`
- Corpus: `conformance/README.md:29-48`, `:184-197`;
  `conformance/RATCHET.md:129-158`; `conformance/cases/legacy.json:1-39`;
  `conformance/manifest.json:1`; `conformance/examples/registry.example.json:46-50`
- Sibling bead sharing `docs/isa.md`: `px-z5m` (reserves `pop`, statement halt
  contract). This plan edits §1, §4's opcode table, and §7; px-z5m edits §2, §6,
  and §4's tier-names row 6. Disjoint by construction - and the tier-6 cell's
  leading `(` is a constraint on px-z5m's edit, not this one's.

## Deferred Manual Verification

- (Phase 1) In `iex`, `Instructions.opcode_set(1)` and `opcode_set(2)` differ by
  exactly `jump_if_falsy_or_pop`, `jump_if_true_or_pop`, `make_list`
- (Phase 1) `retired_in("and")` reads as `{:ok, nil}`, not an error
- (Phase 2) §1 reads as a rule a sibling implementer can apply without reading
  this plan: what mints a version, and what version *v* comprises
- (Phase 2) Temporarily setting `"and" => %{isa: 1, tier: 1, removed_in: 3}` in
  `@opcodes` produces a red suite that names the *doc column* disagreement
  and the *evaluator clause still present* disagreement - then revert
- (Phase 2) The §4 table still renders as a table in a markdown preview with 8
  columns
