# Date vs DateTime Comparison Coercion Implementation Plan

## Overview

Comparing a Date against a DateTime silently yields `:undefined` instead of a
boolean. Since relative dates (`2w from now`, `3d ago`, `next 1mo`, `last 1y`)
always evaluate to a DateTime, any context value held as a Date fails to
compare against one - the documented example
`Predicator.evaluate("due_at < 2w from now", %{"due_at" => Date.add(Date.utc_today(), 10)})`
returns `{:ok, :undefined}` where it documents `true`.

**Decision (recorded per the acceptance criteria)**: mixed Date/DateTime
comparison **coerces** the Date to a DateTime at `00:00:00` UTC, matching the
coercion `apply_subtraction/2` already performs for the same pair. Equality
and membership (`==`, `!=`, `in`, `contains`) coerce the same way. Strict
equality (`===`, `!==`) stays type-strict. Rationale: arithmetic already
coerces this exact pair, so refusing to order it is an inconsistency inside
one module; and the silent `:undefined` gives rule authors no signal that
anything is wrong.

Beads issue: px-2ka

## Current State Analysis

- `compare_values/3` handles Date/Date chronologically at
  `lib/predicator/evaluator.ex:520` and DateTime/DateTime at `:524` (both
  landed with px-ddc), but the mixed pair falls through to the catch-all at
  `:539` and returns `Undefined.value()`.
- The `types_match/2` guard (`lib/predicator/evaluator.ex:496-503`)
  deliberately admits only same-type Date/Date and DateTime/DateTime pairs.
- `values_equal?/2` (`lib/predicator/evaluator.ex:553-562`) has the same gap:
  the mixed pair falls to the final clause and returns `false`. It backs `in`
  and `contains` membership at `:644` and `:662`, so
  `~D[2024-01-15] in [~U[2024-01-15 00:00:00Z]]` is silently `false`.
- `apply_subtraction/2` already coerces the mixed pair via
  `DateTime.new(date, ~T[00:00:00], "Etc/UTC")` at
  `lib/predicator/evaluator.ex:853-860` - the precedent this plan extends to
  ordering and equality.
- The documented example lives at `docs/architecture.md:382` (the README was
  slimmed to an entry point by px-tt6 and no longer carries it).
- `docs/architecture.md` has no section describing comparison semantics for
  temporal types; the decision has nowhere to live yet.
- px-ddc (dependency) is closed and its fix is on `main`; this branch is cut
  from a `main` that contains it.

## Desired End State

- `Predicator.evaluate("due_at < 2w from now", %{"due_at" => Date.add(Date.utc_today(), 10)})`
  returns `{:ok, true}`, and the equivalent holds for `3d ago`, `next 1mo`,
  and `last 1y` predicates with Date context values.
- Mixed Date/DateTime ordering works in both operand orders.
- `==`/`!=` and `in`/`contains` treat a Date as equal to a DateTime at
  exactly `00:00:00` UTC of that day, and unequal otherwise.
- `===`/`!==` remain type-strict: a Date is never strictly equal to a
  DateTime.
- `docs/architecture.md` records the coercion decision and why.
- Verify with `mix quality` (full gate) and the manual iex checks below.

### Key Discoveries:
- Coercion precedent: `lib/predicator/evaluator.ex:853-860`
  (`DateTime.new(date, ~T[00:00:00], "Etc/UTC")`).
- Chronological compare pattern to extend: `lib/predicator/evaluator.ex:519-526`
  delegating to `compare_chronological/2` at `:541-551`.
- Membership goes through `values_equal?/2`, not `compare_values/3`
  (`lib/predicator/evaluator.ex:644,662`), so both functions need clauses.
- `STRICT_EQ`/`STRICT_NE` are handled before any type dispatch at
  `lib/predicator/evaluator.ex:516-517` via `===`/`!==` and need no change.

## What We're NOT Doing

- No change to the instruction set - no new instructions, no ISA bump, no
  cross-language interchange impact (ADR-0001 untouched).
- No change to strict equality semantics (`===`/`!==` stay type-strict).
- No timezone configurability - the coercion is fixed at UTC midnight,
  exactly as `apply_subtraction/2` already hardcodes it. Making the anchor
  configurable would be a new feature, not this bug fix.
- No change to Date/Date or DateTime/DateTime comparison (px-ddc's territory).
- No coercion of date-like strings - only actual `%Date{}`/`%DateTime{}`
  structs participate.
- No new ADR - the decision is recorded in `docs/architecture.md` and on the
  bead; it is a module-consistency fix, not a new architectural direction.

## Implementation Approach

Extend the chronological-comparison clauses in `compare_values/3` and the
equality clauses in `values_equal?/2` with the two mixed-pair orderings,
coercing through a small private helper that `apply_subtraction/2`'s clauses
can also share. The `types_match/2` guard is left untouched: the mixed pair is
handled by explicit struct-pattern clauses above the guard clause, exactly how
the same-type Date/DateTime clauses already work, so the guard keeps meaning
"same type" for every other caller.

Single phase: the evaluator change, its tests, and the docs/decision record
are one committable unit. Splitting docs out would leave the first commit
failing the bead's acceptance criteria.

## Phase 1: Mixed Date/DateTime coercion in the evaluator

### Overview
Add coercing clauses for ordering, equality, and membership; share the
Date-to-DateTime coercion helper with subtraction; record the decision in the
architecture doc and CHANGELOG.

### Changes Required:

#### 1. Evaluator: coercion helper and comparison clauses
**File**: `lib/predicator/evaluator.ex`
**Changes**:

Add a private helper (near the other date helpers, before
`apply_subtraction/2`):

```elixir
@spec date_to_datetime(Date.t()) :: DateTime.t()
defp date_to_datetime(%Date{} = date) do
  {:ok, datetime} = DateTime.new(date, ~T[00:00:00], "Etc/UTC")
  datetime
end
```

Add mixed-pair clauses to `compare_values/3`, directly after the
DateTime/DateTime clause at `:524-526`:

```elixir
# Mixed Date/DateTime: coerce the Date to midnight UTC, matching
# apply_subtraction/2's coercion for the same pair
defp compare_values(%Date{} = left, %DateTime{} = right, operator) do
  compare_chronological(DateTime.compare(date_to_datetime(left), right), operator)
end

defp compare_values(%DateTime{} = left, %Date{} = right, operator) do
  compare_chronological(DateTime.compare(left, date_to_datetime(right)), operator)
end
```

Add mixed-pair clauses to `values_equal?/2`, after the DateTime/DateTime
clause at `:558-559`:

```elixir
defp values_equal?(%Date{} = left, %DateTime{} = right),
  do: DateTime.compare(date_to_datetime(left), right) == :eq

defp values_equal?(%DateTime{} = left, %Date{} = right),
  do: DateTime.compare(left, date_to_datetime(right)) == :eq
```

Rewrite the two mixed `apply_subtraction/2` clauses at `:853-860` to use the
shared helper:

```elixir
defp apply_subtraction(%Date{} = date, %DateTime{} = datetime) do
  apply_subtraction(date_to_datetime(date), datetime)
end

defp apply_subtraction(%DateTime{} = datetime, %Date{} = date) do
  apply_subtraction(datetime, date_to_datetime(date))
end
```

Note the mixed `compare_values/3` clauses must sit above the
`types_match/2`-guarded clause and the catch-all; the mixed `values_equal?/2`
clauses must sit above its `types_match/2` clause and final `false` clause.

#### 2. Tests
**File**: `test/predicator/evaluator_test.exs` (comparison unit coverage,
alongside the existing Date/DateTime comparison tests from px-ddc)
**Changes**: add a describe block for mixed Date/DateTime comparison:

- Ordering, both operand orders: a Date before/after a DateTime yields the
  correct boolean for `<`, `>`, `<=`, `>=` (pattern-matched through compiled
  instruction runs, matching the file's existing style).
- Equality boundary: `~D[2024-01-15]` vs `~U[2024-01-15 00:00:00Z]` is `EQ`
  true; vs `~U[2024-01-15 00:00:01Z]` is `EQ` false / `NE` true.
- Strict equality unchanged: `~D[2024-01-15] === ~U[2024-01-15 00:00:00Z]`
  is `false`, `!==` is `true`.
- Membership: a Date is `in` a list containing the midnight-UTC DateTime of
  the same day; `contains` mirror case.

**File**: `test/predicator/integration/full_pipeline_test.exs` (or the
integration file the existing relative-date tests live in - confirm at
implementation time and co-locate)
**Changes**: end-to-end `Predicator.evaluate/2` cases:

- The documented example: `"due_at < 2w from now"` with
  `%{"due_at" => Date.add(Date.utc_today(), 10)}` returns `{:ok, true}`.
- `"created_at > 3d ago"` with a Date 1 day ago returns `{:ok, true}`.
- `"due_at < next 1mo"` and `"start_on > last 1y"` with Date values return
  booleans, both directions exercised.
- A false case, e.g. `"due_at < 2w from now"` with a Date 30 days out
  returning `{:ok, false}`, so the tests prove real comparison rather than
  truthiness.

#### 3. Documentation and decision record
**File**: `docs/architecture.md`
**Changes**: add a short "Temporal comparison semantics" note in the
evaluator/conventions area (near the material the v3.4.0 history at `:370-386`
references): Date/Date and DateTime/DateTime compare chronologically; a mixed
pair coerces the Date to `00:00:00` UTC, matching date subtraction's coercion;
strict equality never crosses the type boundary. State the why in one
sentence (consistency with arithmetic, and silent `:undefined` gives authors
no signal).

**File**: `CHANGELOG.md`
**Changes**: entry under `## [Unreleased]` / `### Fixed`: comparing a Date
against a DateTime (including all relative-date results) now coerces the Date
to midnight UTC and returns a boolean instead of silently evaluating to
`:undefined`.

**Bead**: `bd note px-2ka` recording the decision (coerce, midnight UTC,
matching subtraction; equality and membership included; strict equality
excluded) and why.

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes (format, compile, credo --strict, dialyzer,
      deps audit, full suite with coverage): `mix quality`
- [x] New clauses are covered - coverage stays above the 90% minimum in
      `coveralls.json`
- [x] The new integration test asserting
      `evaluate("due_at < 2w from now", %{"due_at" => Date.add(Date.utc_today(), 10)}) == {:ok, true}`
      passes

#### Manual Verification:
- [x] In iex: the four relative-date forms (`2w from now`, `3d ago`,
      `next 1mo`, `last 1y`) each return a boolean against a Date context
      value
- [x] In iex: `evaluate("d == #2024-01-15T00:00:00Z#", %{"d" => ~D[2024-01-15]})`
      is `{:ok, true}` and the `===` form is `{:ok, false}`
- [x] The `docs/architecture.md` note reads correctly next to the v3.4.0
      example it fixes

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run the full `mix quality` as the phase gate. When the work is
complete, finish with `/commit --auto` - it writes the `Refs:` trailer and
refuses if the tree carries changes unrelated to px-2ka. Do not run
`git commit` directly.

---

## Testing Strategy

### Unit Tests:
- Mixed-pair ordering clauses, both operand orders, all four ordering
  operators (`test/predicator/evaluator_test.exs`).
- Equality boundary at exactly midnight UTC vs one second after.
- Strict equality regression: mixed pair is never `===`-equal.
- Membership (`in`/`contains`) with mixed pairs in both element/list roles.

### Integration Tests:
- End-to-end `Predicator.evaluate/2` for all four relative-date forms with
  Date context values, including at least one `{:ok, false}` case.

### Manual Testing Steps:
1. `iex -S mix`, run the bead's reproducing call and confirm `{:ok, true}`.
2. Run the same predicate with a Date 30 days out and confirm `{:ok, false}`.
3. Spot-check `==` vs `===` on a Date against its midnight-UTC DateTime.

## Performance Considerations

`DateTime.new/3` with `"Etc/UTC"` is allocation-cheap and timezone-database
free; one extra struct per mixed comparison is negligible and identical to
what subtraction already pays.

## References

- Beads issue: `px-2ka` (decision and acceptance criteria)
- Coercion precedent: `lib/predicator/evaluator.ex:853-860`
- Chronological compare (px-ddc): `lib/predicator/evaluator.ex:519-526`
- Equality/membership path: `lib/predicator/evaluator.ex:553-562,644,662`
- Documented example this fixes: `docs/architecture.md:382`
- Related closed issue: `px-ddc` (same-type ordering fix this builds on)
- ADR-0001: instruction set is the cross-language format - unchanged here
