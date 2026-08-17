# Uniform duration key set Implementation Plan

## Overview

Beads issue: `px-69c` ("Evaluated duration key set varies by expression";
mirrors `sui-cw0` in statifier-ui and `st-4epq` in statifier-ex, neither of
which implements the fix). Labels: `area:evaluator`, `area:conformance`,
`area:docs`.

`Predicator.Evaluator`'s `duration` opcode seeds a seven-key accumulator that
omits `:milliseconds` and then fills units with `Map.put/3`, so an evaluated
duration has eight keys when the expression mentions a `ms`-family unit and
seven when it does not. Every other duration producer in the library -
`Duration.new/1`, `Duration.parse/1`, `Duration.from_units/1`, and the
`Date`-`Date` / `DateTime`-`DateTime` subtraction clauses in the evaluator
itself - produces eight, and `Types.duration()` declares eight as required.
This plan makes the `duration` opcode agree with them, then corrects the
several documents that wrote the seven-key accumulator down as the normative
value shape.

## Current State Analysis

**The defect, one line.** `lib/predicator/evaluator.ex:1822`:

```elixir
initial_duration = %{years: 0, months: 0, weeks: 0, days: 0, hours: 0, minutes: 0, seconds: 0}
```

`convert_units_to_duration_map/1` then folds the operand's unit pairs in with
`Map.put(acc, unit_atom, value)` (`evaluator.ex:1828`). `Map.put/3` inserts
when the key is absent, so `:milliseconds` materializes only when the operand
actually names a `ms`-family unit:

```
Predicator.evaluate("3d")       #=> 7 keys, no :milliseconds
Predicator.evaluate("500ms")    #=> 8 keys
Predicator.evaluate("2h30m10s") #=> 7 keys
```

**It is the only seven-key producer in the tree.** A sweep of every duration
construction site:

| Site | Shape | Note |
|---|---|---|
| `lib/predicator/duration.ex:36-47` (`new/1`) | 8 keys | the declared builder |
| `lib/predicator/duration.ex:63-68` (`from_units/1`) | 8 keys | starts from `new()` |
| `lib/predicator/duration.ex:462-472` (`parse/1`) | 8 keys | starts from `new()` |
| `lib/predicator/evaluator.ex:1098` (`Date` - `Date`) | 8 keys | `Duration.new(days: …)` |
| `lib/predicator/evaluator.ex:1105` (`DateTime` - `DateTime`) | 8 keys | `Duration.new(seconds: …)` |
| `lib/predicator/evaluator.ex:1822` (`duration` opcode) | **7 or 8** | the defect |

**`Types.duration()` disagrees with itself, in prose.**
`lib/predicator/types.ex:27-36` declares all eight keys as required in the
`@type`, but the `@typedoc` immediately above it (`types.ex:10-26`) lists only
seven units and never mentions `milliseconds`. Both halves of that file need a
pass, not just the runtime.

**`Duration.add_unit/3` is not reachable from the defect.** `duration.ex:105`
does `duration.milliseconds + value`, which raises `KeyError` on a seven-key
map. Both of its callers - `build_duration_from_units/2` (`duration.ex:72-85`)
and `parse/1`'s `reduce_component/4` (`duration.ex:474-486`) - seed their
accumulator from `new()`, so `add_unit/3` never sees fewer than eight keys
today. The evaluator does **not** call it; it does its own `Map.put/3` fold.
This is a latent hazard that the fix removes by construction, not a live bug,
and it needs no defensive change of its own.

**The corpus does not pin the defect, and the fix produces no corpus data
diff.** This is the load-bearing discovery and it contradicts the obvious
reading of `conformance/cases/durations.json`. The tagged-value codec
normalizes on the way out
(`lib/predicator/conformance/values.ex:181-189`):

```elixir
base = Map.new(@duration_keys, &{Atom.to_string(&1), Map.fetch!(duration, &1)})

case Map.get(duration, :milliseconds, 0) do
  0 -> base
  milliseconds -> Map.put(base, "milliseconds", milliseconds)
end
```

`@duration_keys` is the seven required units (`values.ex:39`), and
`milliseconds` is read with `Map.get/3` defaulting to `0` and **emitted only
when non-zero**. A duration carrying `milliseconds: 0` and a duration carrying
no `:milliseconds` key at all therefore encode to byte-identical JSON. The
generator's `check_expected/2` (`generator.ex:390-405`) dispatches to
`check_expected_result/2` (`:409-423`), which compares authored JSON against
computed JSON - both already through that encoder - so no
authored `expected` block changes either. `mix corpus.generate` after the
evaluator fix must produce an unchanged `conformance/corpus/*.json` and
`conformance/manifest.json` - and that is a verifiable prediction, not an
assumption.

The proof this is already true in the tree: `arithmetic.json`'s
`Date - Date` and `DateTime - DateTime` cases (`arithmetic.json:131-142`,
`150-161`) and `casts.json`'s `"2w3d"::duration` case (`casts.json:180-191`)
all run through `Duration.new/1` or `Duration.parse/1` today, producing eight
keys, and all three are exported as seven-key JSON.

**What the corpus does pin is a false explanation.**
`conformance/cases/durations.json:40-58` carries the case id
`durations/milliseconds-key-present-only-when-used` with the note "the
milliseconds key is present only when a ms-family unit was used; every other
case in this file omits it because it is 0". After the fix the *value* always
has the key and only the *JSON encoding* omits a zero. Same for
`durations.json:19` ("hand-decode: seven keys, all present … this is the
normative shape").

**The seven-key claim is written down in six more places**, all of which the
fix falsifies:

- `docs/isa.md:199-203` - "a map with the seven keys … plus an optional
  `milliseconds` key present only when a `ms`-family unit was used", declared
  **normative**
- `conformance/README.md:129-135` and `:153-160` (the hand-decode worked
  example)
- `lib/predicator/conformance/values.ex:17-22` (moduledoc)
- `docs/guides/porting.md:65`
- `lib/predicator/types.ex:10-26` (the `@typedoc` prose)
- `conformance/cases/durations.json:19` and `:57` (case notes)

**Seven existing test assertions encode the seven-key output.** All in
`test/predicator/evaluator_dates_test.exs`, in the
`"evaluate/2 with duration instructions"` describe block: lines 133, 141, 152,
161, 174, 182, and the `999y365d` case just after 189. Each is a full-map
`assert result == expected` and each gains `milliseconds: 0`.
`test/predicator/functions/date_arithmetic_test.exs:210-232` also writes
seven-key maps, but as members of an unused `_context` binding - inert, and
out of scope.

**Nothing pattern-matches on exactly seven keys.** `lib/predicator/cast.ex:52`
and `:143` detect a duration with a seven-key map pattern; Elixir map patterns
match subsets, so an eight-key value matches unchanged.

## Desired End State

`Predicator.evaluate/1-3` returns a duration with the same eight keys for
every expression, matching `Types.duration()` and `Duration.new/1`, and every
document that described the seven-key runtime value says so instead. The
exported corpus data is unchanged; only two case `notes` strings move.

Verification:

- `mix quality` green, on each phase.
- `Predicator.evaluate("3d")` and `Predicator.evaluate("500ms")` return maps
  whose `Map.keys/1` sets are equal, and equal to
  `Map.keys(Predicator.Duration.new())`.
- `git diff --stat conformance/corpus conformance/manifest.json` after
  `mix corpus.generate` in Phase 1 is empty; in Phase 3 it shows only the two
  `notes` strings.
- In `docs/isa.md`, `conformance/README.md`,
  `lib/predicator/conformance/values.ex`, `docs/guides/porting.md`, and
  `conformance/cases/durations.json`, no sentence describes the duration
  *value* as seven-key. Some of those files will still say "seven" about the
  *JSON encoding* - `conformance/README.md` and `values.ex` legitimately do,
  because the encoding really does write seven units and omit a zero eighth -
  and that is correct, not a leftover. (Historical plans under `docs/plans/`
  keep theirs - see "What We're NOT Doing".)

### Key Discoveries:

- `lib/predicator/evaluator.ex:1822` is the sole seven-key producer; every
  other site routes through `Duration.new/1`.
- `lib/predicator/conformance/values.ex:181-189` already normalizes
  `:milliseconds` on encode, which is why the corpus data does not move.
- `lib/predicator/duration.ex:105-106` (`add_unit/3`) would `KeyError` on a
  seven-key map but is unreachable from the evaluator; all callers seed from
  `new()`.
- **`Map.put/3` must stay.** `docs/isa.md:573-574` makes "later pairs
  overwrite earlier ones naming the same unit" normative and
  `conformance/cases/durations.json:59-77`
  (`durations/later-unit-pair-overwrites-earlier`) pins it. Routing the fold
  through `Duration.add_unit/3` would turn overwrite into accumulation - a
  genuine ISA break. Only the *seed* changes.
- **Corpus case ids are stable forever once shipped**
  (`conformance/RATCHET.md:41`, and `schema/case.json`), because a sibling's
  ratchet registry keys on `(case_id, surface)`. The misleading id
  `durations/milliseconds-key-present-only-when-used` is therefore **kept**;
  only its `notes` is corrected.
- `Types.duration()`'s `@type` (8 keys) and its `@typedoc` prose (7 units)
  already disagree at `lib/predicator/types.ex:10-36`.
- ADR-0003: this repo is the ISA reference implementation and the corpus is
  the exported specification, so a corpus diff is explained in the commit
  message and the PR body.

## What We're NOT Doing

- **Not taking the bead's option 2** (declaring the seven-key form the
  contract and loosening `Types.duration()`). See "Implementation Approach".
- **Not renaming** the corpus case
  `durations/milliseconds-key-present-only-when-used`, despite the id now
  describing an encoding rule rather than a value rule. `RATCHET.md:41` makes
  shipped ids a durable key for sibling ratchet registries, and a rename is
  exactly the "corpus drift under a pinned version" failure `RATCHET.md:148`
  describes. The note is corrected; the id is not.
- **Not changing the tagged-value encoding** in
  `lib/predicator/conformance/values.ex`. Omitting a zero `milliseconds` from
  the JSON stays; it is a corpus-apparatus compaction rule, it is decoded
  symmetrically (`values.ex:191-196` defaults the key back to `0`), and
  changing it would move every duration-bearing case in the corpus for no
  gain. Only its moduledoc's *explanation* of why the key is sometimes absent
  changes.
- **Not adding a defensive guard or an eight-key assertion to
  `Duration.add_unit/3`.** The seven-key input it would guard against ceases
  to exist in this change, and errors-as-values conventions do not want a new
  error path for an unreachable state. The finding is recorded in this plan
  and in Phase 1's comment instead.
- **Not adding the new tests to `gate.sabotage.test_roots`** in
  `.claude/wurk.json`, and therefore not carrying sabotage notes on them. The
  binding-test class is the enumerable set of tests that keep an *exported
  artifact* honest, where a vacuous pass ships a wrong specification to a
  sibling (`docs/research/260808-px-9ab-sabotage-notes.md:46-52`). A test
  asserting the evaluator's runtime key set against `Duration.new/1` binds two
  in-repo call sites to each other, not an exported artifact - it is an
  ordinary regression test. Editing `.claude/**` would also pull in
  `area:skills`, which this bead does not carry.
- **Not correcting the historical plan documents** that state the seven-key
  shape (`docs/plans/260807-px-35i.4-conformance-corpus.md:388`, `:764`,
  `docs/plans/260806-px-35i.2-isa-reference.md:231`,
  `docs/plans/260809-px-2r5.3-cast-compile-eval.md:124`, `:289`). A dated plan
  is a record of what was decided then; rewriting it to match a later decision
  destroys the record.
- **Not cutting a release.** The CHANGELOG entry lands under
  `## [Unreleased]`; bumping `@version` and promoting the section is release
  work with its own trigger.
- **Not touching `test/predicator/functions/date_arithmetic_test.exs`**'s
  seven-key maps - they sit in an unused `_context` binding and assert
  nothing.

## Implementation Approach

**The choice: option 1 - seed the accumulator with all eight units, by routing
the seed through `Duration.new/1`.** Three things decide it. First,
`Types.duration()` already declares eight required keys and four of the five
other duration producers already emit eight, so option 1 makes one outlier
agree with the library rather than making the library agree with one outlier;
option 2 would mean loosening a `@type` and re-documenting an optional-unit
contract to canonize an accident of `Map.put/3`. Second, the ISA already
treats a missing `milliseconds` as zero - `conformance/README.md:133-135`
tells decoders to "default a missing `milliseconds` to `0` rather than
treating its absence as an error" - so the two shapes already denote the same
value, and the one that is uniform is strictly easier to consume. Third, the
cost is asymmetric and measurable: option 1 is one line of `lib/` plus seven
test assertions plus prose, with **zero exported-corpus data movement**
(established above), while option 2 would widen a public type to an
optional-key map, which is both a larger breaking change for Elixir consumers
and a harder thing for a sibling to reimplement faithfully.

Using `Duration.new()` for the seed rather than writing an eight-key literal
is deliberate: it makes `Duration.new/1` the single definition of the key set,
so the two can no longer drift, which is what the bead's third acceptance
criterion is asking for.

**Phase split.** Three phases along the reversibility seam rather than along
subsystems, because the behavior change is one line and the interesting risk
is in what it invalidates:

1. the behavior change and its tests, in `lib/` and `test/`, with the
   CHANGELOG entry that makes it user-visible;
2. the normative prose in `docs/` and the `@typedoc`, which is where a sibling
   reads the value shape;
3. the conformance subtree's prose plus `mix corpus.generate`, isolated so the
   ADR-0003 corpus-diff explanation is one commit with one thing in it.

Each phase leaves the tree green on its own. Phase 1 is green because the
corpus does not move; Phases 2 and 3 are documentation and would be green with
or without Phase 1, but are ordered after it so the tree never claims a shape
the runtime does not produce.

## ISA Impact

1. **Version** - **no ISA version moves.** No opcode is added, removed, or
   renamed, and no operand form changes: `["duration", units]` accepts exactly
   the same operands and `required_isa/1`'s opcode-name scan cannot express a
   value-shape edit in the first place (`docs/isa.md:33-42`). The harder
   question is whether this "changes an opcode's semantics under its own
   name", which `docs/isa.md:31-33` forbids. It does not, on the ISA's own
   terms: §3's shape already declares an absent `milliseconds` to mean zero
   (`conformance/README.md:133-135`), so both shapes denote the same value,
   and the observable export a sibling implements against - the tagged-value
   JSON in `conformance/corpus/*.json` - is **byte-identical before and
   after**. Nothing a conforming sibling must do changes. What changes is the
   in-process Elixir representation, which is a library concern, not an ISA
   one.
2. **Stamp** - `docs/isa.md` §3 (lines 199-203) is amended: the duration shape
   becomes eight keys, `years` through `milliseconds`, all present and
   defaulting to `0`, with a sentence delegating the corpus's zero-omitting
   JSON compaction to `conformance/README.md` (which is already where §3
   delegates the tagged encoding). No opcode subsection, no version row, no
   new conformance tier.
3. **Migration** - none. Every instruction list compiled before this change
   still runs and produces the same value; a `["duration", …]` result gains a
   key whose absence already meant `0`. A sibling behind the current ISA
   version is unaffected, since no version moved (ADR-0003).

For the Elixir library the change is nonetheless breaking at the API surface:
a consumer pattern-matching on `map_size(duration) == 7`, comparing against a
seven-key literal, or enumerating `Map.keys/1` sees a different value. That is
recorded in the CHANGELOG as a breaking change under `## [Unreleased]`, which
signals a major bump (9.0.0) whenever a release is next cut. Cutting it is not
in this plan's scope.

## Phase 1: Uniform key set from the `duration` opcode

### Overview

Change the accumulator seed, update the seven assertions the old shape, add
the two key-set regression tests the bead asks for, and record the behavior
change in the CHANGELOG. This phase is the whole functional change.

### Changes Required:

#### 1. The evaluator's duration accumulator

**File**: `lib/predicator/evaluator.ex` (in
`convert_units_to_duration_map/1`, currently line 1822)
**Changes**: seed from `Duration.new/1` so the key set has one definition
site. `Map.put/3` in the fold body is unchanged - see the comment.

```elixir
defp convert_units_to_duration_map(units) do
  # Seed from Duration.new/1 rather than a literal so the eight-key set has a
  # single definition site (px-69c: the old seven-key literal omitted
  # :milliseconds, and Map.put/3 below inserted it only when the operand
  # named a ms-family unit, so the key set varied by expression).
  #
  # The fold stays Map.put/3, deliberately: docs/isa.md's `duration` opcode
  # specifies that later pairs *overwrite* earlier ones naming the same unit.
  # Duration.add_unit/3 accumulates instead, so it is the wrong tool here
  # despite taking the same unit strings.
  initial_duration = Duration.new()

  Enum.reduce_while(units, {:ok, initial_duration}, fn
    ...unchanged...
  end)
end
```

Confirm `Predicator.Duration` is already aliased in `evaluator.ex` - it is,
`Duration.new/1` is called at lines 1098 and 1105.

#### 2. Existing assertions of the seven-key output

**File**: `test/predicator/evaluator_dates_test.exs`
**Changes**: add `milliseconds: 0` to the seven full-map `expected` literals
in the `"evaluate/2 with duration instructions"` describe block (lines 133,
141, 152, 161, 174, 182, and the `999y365d` case following 189). No test names
change; these are mechanical.

#### 3. The key-set regression tests

**File**: `test/predicator/evaluator_dates_test.exs`, a new describe block
appended after the existing duration block
**Changes**: two tests satisfying the bead's third acceptance criterion,
deriving the expected key set from `Duration.new/1` rather than hardcoding it,
so the two producers cannot drift apart again.

```elixir
describe "duration key set (px-69c)" do
  test "a non-ms expression yields the same keys as Duration.new/1" do
    assert {:ok, duration} = Predicator.evaluate("3d")
    assert Map.keys(duration) |> Enum.sort() ==
             Predicator.Duration.new() |> Map.keys() |> Enum.sort()
    assert duration.milliseconds == 0
  end

  test "an ms-bearing expression yields the same keys as a non-ms one" do
    assert {:ok, with_ms} = Predicator.evaluate("1s500ms")
    assert {:ok, without_ms} = Predicator.evaluate("2h30m10s")

    assert Map.keys(with_ms) |> Enum.sort() == Map.keys(without_ms) |> Enum.sort()
    assert with_ms.milliseconds == 500
    assert without_ms.milliseconds == 0
  end
end
```

The `{:ok, _}` match is correct: `Predicator.evaluate/3`'s spec is
`{:ok, Types.value()} | {:error, struct()}` (`lib/predicator.ex:178-183`).

#### 4. The changelog entry

**File**: `CHANGELOG.md`
**Changes**: an `[Unreleased]` heading does not currently exist (the file
opens straight into the `[8.0.0] - 2026-08-15` heading). Add a level-two
`[Unreleased]` heading above it, with a level-three `Changed` subsection
holding this entry (headings elided from the block below so this plan's own
structure stays parseable):

```markdown
- **A duration produced by the `duration` opcode now always carries all eight
  unit keys, `milliseconds` included.** Previously the evaluator seeded a
  seven-key accumulator and inserted `milliseconds` only when the expression
  named a `ms`-family unit, so `Predicator.evaluate("3d")` returned seven keys
  while `Predicator.evaluate("500ms")` returned eight - a key set that varied
  with the expression and did not satisfy `t:Predicator.Types.duration/0`,
  which has always declared all eight as required. Every other duration
  producer (`Duration.new/1`, `parse/1`, `from_units/1`, and `Date`/`DateTime`
  subtraction) already returned eight; the opcode now matches them. **This is
  a breaking change** for a consumer that pattern-matches on the seven-key
  shape, compares against a seven-key literal, or enumerates `Map.keys/1`; a
  consumer reading units with `Map.get/3` is unaffected, and the numeric value
  of every duration is unchanged, since an absent `milliseconds` always meant
  `0`. No ISA version moves and no compiled instruction list changes meaning -
  the conformance corpus's exported bytes are identical, because its JSON
  encoding already omitted a zero `milliseconds`.
```

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality`
- [x] The two new tests in `test/predicator/evaluator_dates_test.exs` pass:
      `mix test test/predicator/evaluator_dates_test.exs`
- [x] `mix corpus.generate` leaves `conformance/corpus/` and
      `conformance/manifest.json` byte-identical:
      `git diff --exit-code conformance/corpus conformance/manifest.json`
      exits 0. This is the phase's central prediction; if it exits non-zero,
      stop and re-read `lib/predicator/conformance/values.ex:181-189` before
      committing anything
- [x] Coverage stays above the `coveralls.json` minimum for
      `lib/predicator/evaluator.ex` (no new branches are introduced, so this
      should be unchanged or up)
- [x] `grep -rn "years: 0" test/ | grep -v milliseconds` returns only
      `test/predicator/functions/date_arithmetic_test.exs` (the inert
      `_context` maps, deliberately left alone)

#### Manual Verification:
- [ ] In `iex -S mix`, `Predicator.evaluate("3d")`,
      `Predicator.evaluate("500ms")`, `Predicator.evaluate("1s500ms")`, and
      `Predicator.evaluate("2h30m10s")` all show eight keys with the same names
- [ ] `Predicator.evaluate("#2026-01-20# - #2026-01-15#")` (the `Date`-`Date`
      path, which was already eight-key) still returns `days: 5` and reads
      identically to the opcode-produced values
- [ ] A relative-date expression (`3d ago`) still evaluates to a `DateTime`,
      confirming `execute_relative_date/2` is unaffected by the extra key
- [ ] No regressions in duration-to-string round-tripping:
      `"2w3d"::duration::string` is still `"2w3d"`

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

**One-time non-vacuity check, performed once during implementation and not a
standing gate condition**: after writing the two new tests, revert the seed at
`evaluator.ex:1822` to the old seven-key literal, run
`mix test test/predicator/evaluator_dates_test.exs`, confirm both new tests go
red, then restore the fix. This is the sabotage technique, applied here as an
authoring discipline rather than as a recorded sabotage note - the tests are
not in the binding-test class (see "What We're NOT Doing"), so nothing is
written to `.claude/wurk.json` and nothing re-runs it later. Do it before the
phase's final `mix quality`.

---

## Phase 2: Correct the normative shape in `docs/` and the `@typedoc`

### Overview

`docs/isa.md` §3 is the authority a sibling reads for the duration value
shape, and it currently specifies the bug. Fix it, the porting guide that
repeats it, and the `Types.duration()` `@typedoc` prose that omits
`milliseconds` entirely. No `lib/` behavior changes.

### Changes Required:

#### 1. The ISA's normative duration shape

**File**: `docs/isa.md`, §3 "Value types", lines 199-203
**Changes**: replace the seven-plus-optional wording with the uniform
eight-key shape, and delegate the corpus's compaction rather than restating
it. Keep the existing sentence structure and the file's em-dash house style.

```markdown
A duration's shape is normative, because `["duration", units]` produces one
and `add`/`subtract` consume it: a map with the eight keys `years`, `months`,
`weeks`, `days`, `hours`, `minutes`, `seconds`, `milliseconds`, all present
and defaulting to `0`. The key set does not vary with the units an expression
named. The conformance corpus's tagged-value JSON omits a `milliseconds` of
`0` as a compaction, which `conformance/README.md` specifies and which does
not narrow this shape - an absent key decodes to `0`.
```

Leave the `duration` opcode subsection at `docs/isa.md:570-577` untouched: its
unit-string table and its overwrite rule are unchanged, and adding a shape
sentence there would duplicate §3.

Check `docs/isa.md:220` (the plain-JSON table row
`` duration | `{"years":0,"days":3,...}` ``) - the ellipsis makes it
shape-agnostic, so it needs no edit; confirm rather than assume.

#### 2. The porting guide

**File**: `docs/guides/porting.md`, line 65
**Changes**: same correction, in that document's voice. Read the surrounding
paragraph first; it is addressed to a sibling implementer and may need the
compaction caveat too.

#### 3. The `Types.duration()` typedoc

**File**: `lib/predicator/types.ex`, `@typedoc` at lines 10-26
**Changes**: add the missing `milliseconds` bullet to the unit list and state
that all eight keys are always present. The `@type` at lines 27-36 is already
correct and does not change.

```elixir
@typedoc """
A duration representing a time span.

Duration is represented as a map with fields for different time units. All
eight keys are always present; an unspecified unit is `0`.
- `years` - number of years (default: 0)
...
- `seconds` - number of seconds (default: 0)
- `milliseconds` - number of milliseconds (default: 0)
...
"""
```

While in this docstring, note that its `## Examples` block writes
`%Duration{days: 3, hours: 8}` - struct syntax for what is a plain map. Fix
the notation to `%{days: 3, hours: 8}` in passing; it is the same docstring
and leaving a misleading example beside a corrected list is worse than a
one-line drive-by.

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality` (this includes
      `test/predicator/isa_sync_test.exs` and `test/docs_adr_links_test.exs`,
      both of which read `docs/isa.md`)
- [x] `mix corpus.generate` still leaves `conformance/corpus` and
      `conformance/manifest.json` byte-identical (`git diff --exit-code`) -
      this phase touches no case file
- [x] `grep -n "seven key\|seven-key" docs/isa.md docs/guides/porting.md`
      returns nothing
- [x] `grep -n "milliseconds" lib/predicator/types.ex` shows the key in both
      the `@typedoc` and the `@type`

#### Manual Verification:
- [ ] `mix docs` renders `Predicator.Types` with the eight-unit list and no
      struct-syntax example
- [ ] Read `docs/isa.md` §3 end to end and confirm the new sentence does not
      contradict the delegation to `conformance/README.md` that follows it two
      paragraphs later
- [ ] Read `docs/guides/porting.md` around the edit and confirm a sibling
      implementer following it would build the eight-key map

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

## Phase 3: Correct the conformance subtree's prose and regenerate

### Overview

The conformance tree explains the zero-omitting JSON as a mirror of the
evaluator's behavior. After Phase 1 that explanation is false: the omission is
a compaction rule of the codec alone. Correct the three prose sites and the
two authored case notes, then regenerate. This is the only phase that moves
the exported corpus, and the diff is two `notes` strings.

### Changes Required:

#### 1. The codec's moduledoc

**File**: `lib/predicator/conformance/values.ex`, moduledoc lines 17-22
**Changes**: reframe from "the value sometimes lacks the key" to "the codec
omits a zero".

```elixir
  A `duration` tag's `value` carries the normative eight-key map from
  `docs/isa.md` section 3 - `years`, `months`, `weeks`, `days`, `hours`,
  `minutes`, `seconds`, `milliseconds`, all always present in the value
  itself. The JSON compacts it: `milliseconds` is emitted only when non-zero,
  and `from_json/1` restores it as `0` when absent, so the two forms decode
  identically. The other seven units are always written out.
```

The `@duration_keys` module attribute at `values.ex:39` and the
`encode_duration/1` / `decode_duration/1` bodies do **not** change - see "What
We're NOT Doing".

#### 2. The conformance README

**File**: `conformance/README.md`
**Changes**: two sites.

- Lines 129-135, "**The duration shape is normative**": say all eight keys are
  present in the value and that the encoding omits a zero `milliseconds` as a
  compaction. Keep the existing "a decoder should default a missing
  `milliseconds` to `0`" sentence - it is still exactly right, and it is now
  the reason the corpus bytes did not move.
- Lines 153-160, "**How to hand-decode a duration case**": the worked example
  still uses the
  `durations/milliseconds-key-present-only-when-used` case (its id is
  unchanged), but the surrounding sentence "read `value` as the seven-plus-one
  key map" and the closing gloss need rewording to the compaction framing. Add
  one clause noting the id is historical and kept because shipped ids are
  stable (`RATCHET.md:41`), so a reader is not misled by it.

#### 3. The authored case notes

**File**: `conformance/cases/durations.json`
**Changes**: two `notes` strings, no ids, no expected values.

- Line 19: replace "hand-decode: seven keys, all present, defaulting to 0 -
  this is the normative shape docs/isa.md:100-106 and Open Question #1 in the
  plan settle on" with a note stating that the value has eight keys and the
  JSON omits a zero `milliseconds` per `conformance/README.md`. Drop the stale
  `docs/isa.md:100-106` line reference (§3 has moved to ~line 199) in favour of
  a section reference, which cannot rot.
- Line 57: replace "the milliseconds key is present only when a ms-family unit
  was used; every other case in this file omits it because it is 0" with
  something like "a ms-family unit gives a non-zero `milliseconds`, which is
  the only condition under which the tagged encoding writes the key out; the
  duration value itself always carries all eight units (px-69c). The case id
  predates that fix and is kept because shipped corpus ids are stable
  (`conformance/RATCHET.md`)."

#### 4. Regenerate

**File**: `conformance/corpus/*.json`, `conformance/manifest.json` (generated)
**Changes**: run `mix corpus.generate`. Expect exactly two changed `notes`
strings in `conformance/corpus/tier-4.json` (both `durations/*` cases) plus
whatever hash/count fields in `conformance/manifest.json` those two strings
feed. Nothing else may move; if an `expected_result` changes, stop - it means
Phase 1's prediction was wrong and the codec is not normalizing as read.

Per ADR-0003 the corpus is the exported specification, so the commit message
and the PR body state what moved and why: two case notes corrected to describe
the codec's compaction rather than the evaluator's old behavior; no expected
value, no case id, and no instruction list changed.

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality` (which runs
      `test/predicator/conformance/corpus_freshness_test.exs`, the binding
      test that fails if the corpus was hand-edited or left stale, plus
      `schema_validation_test.exs` and `ratchet_registry_test.exs`)
- [x] `mix corpus.generate` is idempotent: running it twice leaves
      `git diff --exit-code conformance/corpus conformance/manifest.json` at 0
      on the second run
- [x] The corpus diff touches only `notes` fields:
      `git diff conformance/corpus` shows no change to any
      `expected_result`, `expected_error`, `instructions`, `id`, `tier`, or
      `features` value
- [x] `test/predicator/conformance/values_test.exs` is unchanged by this
      phase: `git diff --exit-code test/predicator/conformance/values_test.exs`
      exits 0. Its "seven-key map" test name (`:70`) describes the *JSON* it
      asserts, which is still seven keys, and its input is built with
      `Duration.new/1`, which already returned eight - the test is correct as
      it stands

#### Manual Verification:
- [ ] Read the regenerated `conformance/corpus/tier-4.json` entry for
      `durations/milliseconds-key-present-only-when-used` and confirm its
      `expected_result` is byte-identical to the pre-change one
- [ ] Read `conformance/README.md`'s hand-decode walkthrough as a sibling
      implementer would and confirm it now produces an eight-key value
- [ ] Confirm the commit message and PR body carry the ADR-0003 corpus-diff
      explanation
- [ ] `grep -rn "seven key\|seven-key" conformance/README.md
      lib/predicator/conformance/values.ex conformance/cases/durations.json`
      and read each remaining hit: every one must be describing the JSON
      encoding, none the value shape

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before finishing. In looped
(`--loop`) execution, this phase's Automated Verification gates advancement
automatically (via `/wurk:commit --auto`), and Manual Verification items are
deferred and surfaced once at the end instead of blocking here.

---

## Testing Strategy

### Unit Tests:

- `test/predicator/evaluator_dates_test.exs` - the seven existing full-map
  assertions gain `milliseconds: 0`; two new tests assert the key set itself.
  The new tests derive the expected key set from
  `Predicator.Duration.new()` rather than a literal, which is what makes them
  a drift guard rather than a second hardcoded copy of the same list.
- Edge cases worth covering in the new block, beyond the bead's two:
  - `"1s500ms"` (ms present and non-zero) and `"2h30m10s"` (ms absent from the
    source) produce equal key sets - this is the exact pair the bead names.
  - A zero-valued ms unit: `["duration", [[0, "ms"]]]` via
    `Evaluator.evaluate/1` produces `milliseconds: 0` and eight keys, and
    encodes to seven-key JSON. Worth one assertion, because it is the case
    where the value shape and the JSON shape visibly diverge.
  - The overwrite rule survives: `["duration", [[1, "h"], [2, "h"]]]` still
    yields `hours: 2`, not `3`. The existing corpus case pins it, but a unit
    test next to the changed line is what catches a future refactor that
    reaches for `add_unit/3`.
- `test/predicator/duration_test.exs` and
  `test/predicator/parser_durations_test.exs` need no changes - both already
  exercise eight-key producers.
- `test/predicator/conformance/values_test.exs` needs no changes: its two
  duration tests (`:70`, `:88`) build their inputs with `Duration.new/1`,
  which already returned eight keys, and assert on the JSON, which does not
  move.

### Integration Tests:

`test/predicator/integration/` gains nothing. The bead's acceptance criteria
are about `Predicator.evaluate/1-2`'s return value, and the two new tests
already call the public `Predicator.evaluate/1` rather than
`Evaluator.evaluate/1` - that is the end-to-end path, exercised at the point
where the assertion is legible. Adding a second copy in
`integration/` would duplicate it without covering another seam.

### Manual Testing Steps:

1. `iex -S mix`, then evaluate `"3d"`, `"500ms"`, `"1s500ms"`, `"2h30m10s"`
   and confirm all four print eight keys with identical names.
2. Evaluate `"3d" |> Predicator.evaluate() |> Predicator.Duration.to_string()`
   and confirm `"3d"` - the extra zero key must not appear in the rendered
   string.
3. Evaluate `"#2026-01-20# - #2026-01-15#"` and `"3d ago"` to confirm the
   `Date`-arithmetic and `relative_date` consumers of a duration are
   unaffected.
4. `mix corpus.generate && git diff --stat conformance/` after Phase 1 (expect
   empty) and after Phase 3 (expect two `notes` strings plus the manifest).
5. Read `docs/isa.md` §3, `docs/guides/porting.md`, and
   `conformance/README.md`'s duration sections as a sibling implementer and
   confirm they describe one shape between them.

## References

- Bead: `px-69c` (mirrors `sui-cw0` in statifier-ui, `st-4epq` in
  statifier-ex)
- The defect: `lib/predicator/evaluator.ex:1822` and the `Map.put/3` fold at
  `:1828`
- The declared shape: `lib/predicator/types.ex:27-36` (`@type`) and `:10-26`
  (`@typedoc`, out of date)
- The reference builder: `lib/predicator/duration.ex:35-47` (`new/1`); the
  `KeyError` hazard at `:105-106` (`add_unit/3`), unreachable today
- The normalizing codec: `lib/predicator/conformance/values.ex:181-189`
  (`encode_duration/1`) and `:191-196` (`decode_duration/1`)
- The generator's authored-vs-computed comparison:
  `lib/predicator/conformance/generator.ex:390-405` and `:409-423`
- Normative prose to correct: `docs/isa.md:199-203`,
  `conformance/README.md:129-135` and `:153-160`,
  `docs/guides/porting.md:65`, `conformance/cases/durations.json:19` and
  `:57`
- Corpus id stability: `conformance/RATCHET.md:41` and `:148-153`
- Sabotage-note class definition:
  `docs/research/260808-px-9ab-sabotage-notes.md:46-52`
- Related ADRs: `docs/adr/0003-the-elixir-implementation-leads-the-isa.md`
  (the corpus is the exported specification; the ISA moves when this repo
  needs it to), `docs/adr/0006-irreversibility-places-the-human-gates.md`
  (why the release is not in scope)
- Prior plans that state the superseded shape, left as historical record:
  `docs/plans/260807-px-35i.4-conformance-corpus.md:388`,
  `docs/plans/260806-px-35i.2-isa-reference.md:231`,
  `docs/plans/260809-px-2r5.3-cast-compile-eval.md:289`

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] In `iex -S mix`, `Predicator.evaluate("3d")`,
      `Predicator.evaluate("500ms")`, `Predicator.evaluate("1s500ms")`, and
      `Predicator.evaluate("2h30m10s")` all show eight keys with the same names
- [ ] `Predicator.evaluate("#2026-01-20# - #2026-01-15#")` (the `Date`-`Date`
      path, which was already eight-key) still returns `days: 5` and reads
      identically to the opcode-produced values
- [ ] A relative-date expression (`3d ago`) still evaluates to a `DateTime`,
      confirming `execute_relative_date/2` is unaffected by the extra key
- [ ] No regressions in duration-to-string round-tripping:
      `"2w3d"::duration::string` is still `"2w3d"`

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

**One-time non-vacuity check, performed once during implementation and not a
standing gate condition**: after writing the two new tests, revert the seed at
`evaluator.ex:1822` to the old seven-key literal, run
`mix test test/predicator/evaluator_dates_test.exs`, confirm both new tests go
red, then restore the fix. This is the sabotage technique, applied here as an
authoring discipline rather than as a recorded sabotage note - the tests are
not in the binding-test class (see "What We're NOT Doing"), so nothing is
written to `.claude/wurk.json` and nothing re-runs it later. Do it before the
phase's final `mix quality`.

---

### Phase 2

- [ ] `mix docs` renders `Predicator.Types` with the eight-unit list and no
      struct-syntax example
- [ ] Read `docs/isa.md` §3 end to end and confirm the new sentence does not
      contradict the delegation to `conformance/README.md` that follows it two
      paragraphs later
- [ ] Read `docs/guides/porting.md` around the edit and confirm a sibling
      implementer following it would build the eight-key map

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

### Phase 3

- [ ] Read the regenerated `conformance/corpus/tier-4.json` entry for
      `durations/milliseconds-key-present-only-when-used` and confirm its
      `expected_result` is byte-identical to the pre-change one
- [ ] Read `conformance/README.md`'s hand-decode walkthrough as a sibling
      implementer would and confirm it now produces an eight-key value
- [ ] Confirm the commit message and PR body carry the ADR-0003 corpus-diff
      explanation
- [ ] `grep -rn "seven key\|seven-key" conformance/README.md
      lib/predicator/conformance/values.ex conformance/cases/durations.json`
      and read each remaining hit: every one must be describing the JSON
      encoding, none the value shape

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before finishing. In looped
(`--loop`) execution, this phase's Automated Verification gates advancement
automatically (via `/wurk:commit --auto`), and Manual Verification items are
deferred and surfaced once at the end instead of blocking here.

---
