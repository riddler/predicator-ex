# Duration Unit Order Fix Implementation Plan

## Overview

Fix `parse_duration_sequence/3` so duration units come back in source order.
`Predicator.parse("3d8h")` currently returns
`{:duration, [{8, "h"}, {3, "d"}], {1, 1}}` - the units are reversed relative
to the source text. Beads issue: px-bxz.

## Current State Analysis

The parser accumulates duration units in source order and then reverses them a
second time:

- `lib/predicator/parser.ex:1390` appends each new unit with
  `units ++ [{number, unit}]`, so the accumulator is already in source order.
- `lib/predicator/parser.ex:1395` and `lib/predicator/parser.ex:1401` both
  build the node with `{:duration, Enum.reverse(units), position}`, reversing
  the already-ordered list.

Downstream consequences of the reversed order:

- **Runtime semantics are unaffected.** `Duration.from_units/1`
  (`lib/predicator/duration.ex:62-85`) and the evaluator's `["duration", units]`
  instruction (`lib/predicator/evaluator.ex:441`) sum units into a duration
  map, which is order-insensitive.
- **StringVisitor round-tripping is broken.** `do_visit({:duration, ...})`
  (`lib/predicator/visitors/string_visitor.ex:244-247`) joins units in list
  order, so `"1d8h"` decompiles to `"8h1d"` today.
- **Several tests pin the buggy order** and must flip when it is fixed:
  - `test/predicator/parser_test.exs:1376,1384,1393,1400,1406,1492` - parser
    assertions written against reversed output.
  - `test/predicator/parser_positions_test.exs:159` - asserted as-is per the
    bead note, explicitly expected to flip with this fix.
  - `test/predicator/date_arithmetic_string_visitor_test.exs:22-27` - uses
    `assert_decompiled_matches("1d8h", "8h1d")` with a comment documenting the
    reversed order.
  - `test/predicator/visitors/instructions_visitor_positions_test.exs:61-68` -
    sorts the units to dodge the ordering bug, with a comment referencing
    px-bxz.
- **Hand-built ASTs already use source order.** The duration tests in
  `test/predicator/evaluator_test.exs` and
  `test/predicator/visitors/instructions_visitor_test.exs` construct unit
  lists like `[{1, "d"}, {8, "h"}]` directly - they are untouched by this fix
  and become consistent with real parser output.

### Cross-language check (the bead's open question)

The bead asked whether the Ruby and JavaScript siblings depend on the reversed
order (ADR-0001). Verified against the local checkout at
`~/repos/github/predicator/impl`:

- The Ruby implementation's duration is an older, single-unit feature: one
  `DURATION` token compiled straight to `["lit", seconds]`
  (`impl/rb/lib/predicator/visitors/instructions.rb:125-128`). It never emits
  or consumes the `["duration", units]` instruction.
- The TypeScript implementation has no duration support at all.

The multi-unit `["duration", units]` instruction exists only in this
implementation, and unit order inside it is not semantically observable (units
are summed). No sibling changes are needed.

## Desired End State

`Predicator.parse("3d8h")` returns `{:ok, {:duration, [{3, "d"}, {8, "h"}], {1, 1}}}`
and every multi-unit duration round-trips through `StringVisitor` unchanged:
`"1d8h"` decompiles to `"1d8h"`.

Verify with:

```elixir
Predicator.parse("3d8h")
# => {:ok, {:duration, [{3, "d"}, {8, "h"}], {1, 1}}}

{:ok, ast} = Predicator.parse("1d8h30m")
Predicator.decompile(ast)
# => "1d8h30m"
```

### Key Discoveries:
- The double reversal: append-order accumulation at
  `lib/predicator/parser.ex:1390`, reversal at `:1395` and `:1401`.
- `StringVisitor` renders units in list order
  (`lib/predicator/visitors/string_visitor.ex:244-247`), so the fix restores
  true round-tripping with no visitor change.
- Evaluation sums units (`lib/predicator/duration.ex:70-85`), so no runtime
  behavior changes.
- The ISA is untouched: the `["duration", units]` instruction shape stays
  `[[value, "unit"], ...]`; only the order of entries produced from parsed
  source changes, and no sibling emits or reads that instruction (ADR-0001
  checked, see above).

## What We're NOT Doing

- No change to the `["duration", units]` instruction shape or any other part
  of the ISA.
- No changes to `Duration`, the evaluator, or either visitor - the fix is
  parser-only in `lib/`.
- No sibling (Ruby/TypeScript) work - verified unaffected.
- No grammar or precedence changes; `docs/architecture.md` stays as-is (it
  documents node shape and position anchoring, not unit order).
- Not normalizing or sorting units (e.g. canonicalizing `8h3d` to `3d8h`) -
  source order is preserved, whatever it is.

## Implementation Approach

Single phase. The lib change is two lines in one private function, the rest is
flipping tests that deliberately pinned the buggy behavior. It is one area
(`area:lexer-parser`), one gate, one commit.

For the accumulation itself, switch to the idiomatic prepend-then-reverse:
seed with `[{number, unit}]`, prepend each subsequent unit with
`[{number, unit} | units]`, and keep the single `Enum.reverse/1` at the end.
This produces source order and drops the O(n²) `++` append. (Simply deleting
the two `Enum.reverse` calls would also fix the order but keep the quadratic
append.)

## Phase 1: Fix unit order and flip the pinned tests

### Overview
Make the parser emit duration units in source order, update every test that
asserted the reversed order, and record the user-facing fix in the changelog.

### Changes Required:

#### 1. Parser
**File**: `lib/predicator/parser.ex`
**Changes**: In `parse_duration_sequence/3`, prepend new units and reverse once
when building the node.

```elixir
defp parse_duration_sequence(units, state, position) do
  case peek_token(state) do
    {:integer, _line, _col, _len, number} ->
      next_state = advance(state)

      case peek_token(next_state) do
        {:duration_unit, _line, _col, _len, unit} ->
          # Continue building duration sequence (prepend; reversed once at the end)
          parse_duration_sequence([{number, unit} | units], advance(next_state), position)

        _token ->
          duration_ast = {:duration, Enum.reverse(units), position}
          parse_duration_with_direction(duration_ast, state)
      end

    _token ->
      duration_ast = {:duration, Enum.reverse(units), position}
      parse_duration_with_direction(duration_ast, state)
  end
end
```

(`parse_duration_sequence_from_integer/3` at line 1367 already seeds with a
single-element list and needs no change.)

#### 2. Parser tests pinning reversed order
**File**: `test/predicator/parser_test.exs`
**Changes**: Flip the multi-unit assertions at lines 1376, 1384, 1393, 1400,
1406, and 1492 to source order, e.g.:

```elixir
# "1d8h30m"
assert {:ok, {:duration, [{1, "d"}, {8, "h"}, {30, "m"}]}} = result

# "2y3mo4w5d6h7m8s"
assert {:ok,
        {:duration, [{2, "y"}, {3, "mo"}, {4, "w"}, {5, "d"}, {6, "h"}, {7, "m"}, {8, "s"}]}} =
         result
```

#### 3. Position test asserted as-is per the bead
**File**: `test/predicator/parser_positions_test.exs`
**Changes**: Flip line 159 to the expected order from the bead note:

```elixir
assert {:ok, {:duration, [{3, "d"}, {8, "h"}], {1, 1}}} = Predicator.parse("3d8h")
```

#### 4. StringVisitor round-trip tests
**File**: `test/predicator/date_arithmetic_string_visitor_test.exs`
**Changes**: Replace the `assert_decompiled_matches` calls at lines 22-27 (and
their "Parser stores units in reverse order" comment) with true round-trips:

```elixir
test "complex duration literals" do
  assert_round_trip("1d8h")
  assert_round_trip("2w3d")
  assert_round_trip("1d8h30m")
end
```

If `assert_decompiled_matches/2` has no remaining callers after this, remove
the helper.

#### 5. Instructions position test sorting around the bug
**File**: `test/predicator/visitors/instructions_visitor_positions_test.exs`
**Changes**: At lines 61-68, drop the `Enum.sort` workaround and the px-bxz
comment; assert exact order:

```elixir
test "a duration takes its first number's position" do
  assert table("3d8h") == {[["duration", [[3, "d"], [8, "h"]]]], %{0 => {1, 1}}}
end
```

#### 6. Changelog
**File**: `CHANGELOG.md`
**Changes**: Add under `## [Unreleased]` (Fixed section):

```markdown
- Duration units now parse in source order: `3d8h` produces
  `[{3, "d"}, {8, "h"}]` instead of the reversed `[{8, "h"}, {3, "d"}]`, and
  multi-unit durations round-trip through the string visitor unchanged
```

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes (format, compile, credo --strict, dialyzer,
      deps audit, full suite with coverage): `mix quality`
- [x] Coverage stays above the 90% minimum in `coveralls.json` (no new code
      paths are added, so this should be unaffected)

#### Manual Verification:
- [ ] `Predicator.parse("3d8h")` returns
      `{:ok, {:duration, [{3, "d"}, {8, "h"}], {1, 1}}}` in iex
- [ ] `"1d8h30m"` round-trips through parse + decompile unchanged
- [ ] `Predicator.evaluate("created_at > 3d8h ago", %{...})` still evaluates
      correctly (order-insensitivity of evaluation confirmed end to end)

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run the full `mix quality` as the phase gate. In interactive
execution, pause here for manual confirmation from the human that the manual
testing was successful before proceeding. In looped (`--loop`) execution, this
phase's Automated Verification gates advancement automatically (via
`/commit --auto`); Manual Verification items are deferred and surfaced once at
the end instead of blocking here.

When the work is complete, finish with `/commit --auto` - it writes the
`Refs:` trailer and refuses if the tree carries changes unrelated to px-bxz.
Do not run `git commit` directly.

---

## Testing Strategy

### Unit Tests:
- Multi-unit duration parsing in source order (`parser_test.exs`): mixed
  orders like `1y2mo3w4d5h6m7s`, descending and ascending unit sizes, and the
  single-unit case (unchanged by the fix).
- Position anchoring unchanged: the duration node still takes its first
  number's position (`parser_positions_test.exs`,
  `instructions_visitor_positions_test.exs`).
- StringVisitor round-trip for multi-unit durations
  (`date_arithmetic_string_visitor_test.exs`).

### Integration Tests:
- Existing end-to-end duration evaluation in `evaluator_test.exs` (hand-built
  instructions, order-insensitive) continues to pass unmodified - that is the
  regression check that runtime behavior did not change.

### Manual Testing Steps:
1. In iex: `Predicator.parse("3d8h")` - expect
   `{:ok, {:duration, [{3, "d"}, {8, "h"}], {1, 1}}}`.
2. In iex: `{:ok, ast} = Predicator.parse("1d8h30m"); Predicator.decompile(ast)` -
   expect `"1d8h30m"`.
3. In iex: evaluate a relative-date predicate (e.g.
   `Predicator.evaluate("ts > 2h30m ago", %{"ts" => DateTime.utc_now()})`) and
   confirm it behaves as before.

## Cross-Language Impact

The ISA is untouched: the `["duration", units]` instruction keeps its shape,
and only the order of entries produced from parsed source changes. Verified
against the sibling checkout (`~/repos/github/predicator/impl`): Ruby's
duration is a single-unit feature compiled to `["lit", seconds]`
(`impl/rb/lib/predicator/visitors/instructions.rb:125-128`) and TypeScript has
no duration support, so neither emits nor consumes this instruction. No
sibling work is required (ADR-0001 check complete).

## References

- Beads issue: `px-bxz` (discovered from px-e3g.4)
- Bug site: `lib/predicator/parser.ex:1379-1404`
- Order-insensitive evaluation: `lib/predicator/duration.ex:62-85`,
  `lib/predicator/evaluator.ex:441`
- Round-trip rendering: `lib/predicator/visitors/string_visitor.ex:244-247`
- Related ADR: `docs/adr/0001-keep-the-stack-vm-revise-the-instruction-set.md`
- Ruby sibling duration:
  `~/repos/github/predicator/impl/rb/lib/predicator/visitors/instructions.rb:125-128`
