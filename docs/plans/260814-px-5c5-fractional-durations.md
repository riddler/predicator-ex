# Fractional duration values Implementation Plan

## Overview

Beads issue: `px-5c5` ("Accepts fractional values in durations", mirrors
`st-rsl`).

Duration values are integer-only at both entry points today: `"1.5s"` is
`:error` from `Predicator.Duration.parse/1` (and therefore `:undefined` from
`"1.5s"::duration`), and the source literal `1.5s` lexes as a `:float` token
followed by an `:identifier`, which the parser never assembles into a
duration. This plan accepts a decimal fraction on a duration component at
both surfaces and normalizes it downward at parse time, so every duration map
field and every `["duration", units]` operand stays an integer.

The design is already settled. Every question this bead posed is decided in
`docs/research/260814-px-5c5-fractional-durations-decisions.md`, which is
grounded in the codebase survey
`docs/research/260814-px-5c5-fractional-durations.md`. This plan implements
those decisions and does not reopen them; where a step below looks like a
judgment call, the decision record is the authority and is cited by number.

The headline decisions, restated so a reader of this plan alone is not
misled:

1. **No ISA version bump.** ISA stays v6; the `::duration` bullet in
   `docs/isa.md` §5 is rewritten as a refinement, §7 gains no row, and
   `Predicator.isa_version/0` does not move (Decision 1).
2. **Sub-millisecond remainders are rejected**, computed in integer
   arithmetic on decimal digits, never binary floats (Decision 2).
3. **Fractions are allowed on all eight units**, `mo` and `y` included under
   the existing 30-day/365-day approximations; the remainder decomposes
   greedily through `d`, `h`, `m`, `s`, `ms` only (Decision 3).
4. **`.5s` is rejected at both entry points**; `"s"` and `"1.s"` stay errors
   (Decision 4).
5. **`to_string(parse("1.5s")) == "1s500ms"`** is accepted and documented
   (Decision 5).
6. **Expansion must not emit duplicate units.** A literal whose expansion
   collides with another component in the same literal (`1.5s200ms`) is a
   spanned compile error; integer-only literals keep today's lowering
   byte-for-byte; expansion lives in one shared `Duration` helper; the AST
   keeps its `{integer, unit}` pair shape (Decision 6).

## Current State Analysis

Integer-only is enforced in four independent places at three layers
(research doc, "Summary"):

1. **The lexer** never looks for a unit suffix after a decimal number. The
   digit branch of `tokenize_chars/4` forks on `is_integer(number)`
   (`lib/predicator/lexer.ex:231` vs `:251`); only the integer arm calls
   `try_parse_duration_after_number/2`, and the float arm's comment says
   "Float - no duration units supported" (`lib/predicator/lexer.ex:252`).
2. **`Duration.parse/1`** gates on
   `~r/\A(?:[0-9]+(?:mo|ms|y|w|d|h|m|s))+\z/` and converts each capture with
   `String.to_integer/1` (`lib/predicator/duration.ex:312-352`).
3. **`Duration.from_units/1`** gates each value on a full-string
   `Integer.parse/1` (`lib/predicator/duration.ex:72-85`).
4. **The `duration` opcode** guards each operand pair with
   `is_integer(value) and is_binary(unit)`
   (`lib/predicator/evaluator.ex:1825`).

Sites 3 and 4 are downstream of construction and are **not touched by this
plan** - normalizing downward at parse time is precisely what keeps them
still, which is what keeps the instruction set still.

Other facts the implementation depends on:

- `take_number/1` (`lib/predicator/lexer.ex:479-516`) consumes at most one
  decimal point and only when a digit follows (`:489-499`), so `1.s` already
  cannot produce a fraction; `finalize_number/4` (`:505-516`) discards the
  digit string, returning only the parsed number.
- A leading `.` never enters the number scanner: the digit branch is keyed on
  `c >= ?0 and c <= ?9` (`lib/predicator/lexer.ex:227`). `.5s` is therefore
  rejected by construction, matching Decision 4 with no new code.
- `try_parse_duration_after_number/2` (`lib/predicator/lexer.ex:737-752`)
  ignores its `number` argument entirely and works only on the remaining
  charlist, so the float arm can call it unchanged.
- `tokenize_number_duration_sequence/8` (`lib/predicator/lexer.ex:819-858`)
  hardcodes `{:integer, line, col, number_consumed, number}` as the leading
  token; it must be generalized to accept a caller-built leading token.
- `duration_unit?/1` (`lib/predicator/lexer.ex:808-817`) is the closed list of
  eight suffixes; `extract_duration_unit/1` (`:779-806`) is the `mo`/`m` and
  `ms`/`s` disambiguation, tried two-character-first in both the mid-sequence
  and end-of-run cases.
- Durations have **no lexer-level failure mode** today
  (`try_parse_duration_after_number/2` returns `{:ok, ...}` or
  `:not_duration`), so `3x` re-lexes as an integer plus an identifier. The
  nearest per-family span precedent is the date literal's whole-literal rule
  (`lib/predicator/lexer.ex:465-467`, commits `ceb9af7`/`4faf42f`).
- `parse_duration_sequence/3` (`lib/predicator/parser.ex:1980-2002`) loops the
  alternating `:integer`/`:duration_unit` run and finalizes
  `{:duration, Enum.reverse(units), duration_loc(state, position)}`. No
  validation happens there today.
- `token_end/1`'s generic clause (`lib/predicator/parser.ex:1546`) is
  `{_type, line, col, len, _value}`, so any new 5-element token gets correct
  span arithmetic for free.
- `Duration.parse/1` **accumulates** repeated units
  (`lib/predicator/duration.ex:344-347`) while the `duration` opcode
  **overwrites** them (`lib/predicator/evaluator.ex:1828`, specified at
  `docs/isa.md:575`, pinned by `conformance/cases/durations.json`). This gap
  is what makes Decision 6a's collision rule necessary.
- `lib/predicator/cast.ex:112-117` implements `::duration` by calling
  `Duration.parse/1`, mapping `:error` to `:undefined`. Widening `parse/1`
  widens the cast with no new plumbing (ADR-0011: casting is total).
- The corpus explicitly "does not cover surface syntax ... and it does not
  cover parse or lexer errors" (`docs/isa.md:847-852`). The two new
  **literal** errors therefore cannot be corpus cases; they are pinned by the
  unit suite. The `::duration` behavior is evaluator-visible and is exported
  through the corpus.
- `conformance/corpus/*.json` and `conformance/manifest.json` are generated by
  `mix corpus.generate` from `conformance/cases/*.json` and are never
  hand-edited; a corpus diff moves the exported specification and is explained
  in the commit message and PR body (ADR-0003).

## Desired End State

At the end of this plan:

- `Predicator.Duration.parse/1` accepts `[0-9]+(\.[0-9]+)?<unit>` components,
  expands each fraction to integer pairs, and accumulates as it does today.
  `parse("1.5s")` is 1 s 500 ms; `parse("0.5mo")` is 15 days;
  `parse("0.5ms")`, `parse(".5s")`, `parse("1.s")`, and `parse("s")` are all
  `:error`.
- `"1.5s"::duration` is a duration; `"0.5ms"::duration` is `:undefined`.
- The duration literal `1.5s` compiles to
  `["duration", [[1, "s"], [500, "ms"]]]` - the same operand shape the opcode
  already accepts. `0.5ms` and `1.5s200ms` are spanned compile errors.
- Integer-only literals compile byte-for-byte as they do today.
- `Predicator.decompile/1` of a program containing `1.5s` renders `1s500ms`,
  which re-parses to the identical AST.
- `docs/isa.md` §5's `::duration` bullet, `docs/reference/language.md`, and
  `docs/architecture.md` state the widened grammar; `docs/isa.md` §7 and
  `Predicator.isa_version/0` are unchanged.
- Four new authored conformance cases pin the widened behavior, and
  `conformance/corpus/` and `conformance/manifest.json` are regenerated.
- `CHANGELOG.md` carries one entry under `## [Unreleased]`.

**How to verify**: `mix quality` is green; `mix corpus.generate --check`
reports no drift (this is what
`test/predicator/conformance/corpus_freshness_test.exs` runs); and the manual
checks in each phase below pass in `iex -S mix`.

### Key Discoveries:

- The float arm of `tokenize_chars/4`
  (`lib/predicator/lexer.ex:251-255`) and the `:float` clause of
  `parse_primary_token/2` (`lib/predicator/parser.ex:1381-1383`) are mirror
  images of the same fork - both must move together or the token stream and
  the parser disagree.
- `finalize_number/4` (`lib/predicator/lexer.ex:505-516`) already holds the
  literal digit string in `number_string`; returning it is the whole of "the
  fraction travels as decimal digits, never as a binary float"
  (Decision 6b). No new scanning is needed.
- The remainder ladder cannot collide with the integer part's own unit: a
  remainder is by definition smaller than one source unit, so the source
  unit's ladder rung is always 0 and is omitted. Within-component collision
  is therefore impossible by construction, and Decision 6a's check only has
  to run **across** components of one literal.
- `docs/isa.md:518-523` (the `bracket_access` bullet) is the in-repo template
  for the refinement sentence Decision 1 requires.
- `docs/architecture.md:46` and `docs/reference/language.md:46` carry the same
  `duration → NUMBER UNIT+` production verbatim; they move together.
- ADR-0003 (this repo leads the ISA), ADR-0004 (errors are values),
  ADR-0005 (area labels), ADR-0011 (`cast` is total, failure is
  `:undefined`) all bound this work and none is contradicted by it.

## What We're NOT Doing

- **Not minting ISA v7.** Decision 1 settles this; §7 gains no row and
  `isa_version/0` does not move. A reader who wants the argument reads the
  decision record, not this plan.
- **Not changing `Duration.from_units/1`, the `duration` opcode, its operand
  spec, its two error reasons, `Predicator.Types.duration()`, the
  instructions visitor, or the conformance codecs.** Downward normalization
  completes before the AST, so the change stops at the parser boundary
  (Decision 6b).
- **Not accepting a leading-dot (`.5s`) or trailing-dot (`1.s`) spelling**, at
  either entry point (Decision 4). Statifier pre-normalizes its SCXML delays;
  that note belongs on `st-rsl`.
- **Not changing `Duration.to_string/1`.** It never emits a fraction
  (Decision 5).
- **Not making the literal grammar and `Duration.parse/1` agree on repeats.**
  `parse/1` keeps accumulating uniformly (`parse("1.5s200ms")` is 1 s 700 ms,
  `:ok`) while the literal `1.5s200ms` is a compile error. That divergence is
  deliberate (Decision 6c), is the same family of divergence the two surfaces
  already have on integer repeats, and gets a documented sentence rather than
  a fix.
- **Not storing the source float in the AST for source-faithful
  decompilation.** `StringVisitor` renders the expansion (`1.5s` decompiles
  to `1s500ms`); the alternative was rejected in Decision 6b.
- **Not adding a duration test to `gate.sabotage.test_roots`.** The corpus
  freshness test, already in the list, is the binding test once Phase 3 lands
  (decision record, "Documentation and conformance obligations"; research doc
  open question 7).
- **Not adding corpus cases for the two new literal errors.** `docs/isa.md`
  §8 excludes parse and lexer errors from the corpus by construction; the
  unit suite pins them.
- **Not changing `mix.exs`, `mix.lock`, or any gate config.** This bead does
  not carry `area:build` and must not acquire it - `area:build` lands alone
  (ADR-0005).

## Implementation Approach

Three phases, split along the pipeline seams the project extension names
(`.claude/wurk/plan.md`, "Phase-splitting along the pipeline's seams") and
along the bead's four area labels:

- **Phase 1** widens the string entry point and builds the shared helper both
  entry points will use (`area:evaluator`, plus the `area:docs` files whose
  statements change with it). Ending here would leave a coherent, shippable
  state: `Duration.parse/1` and `::duration` accept fractions, the literal
  does not, and every document says exactly that.
- **Phase 2** widens the literal grammar on top of that helper
  (`area:lexer-parser`, plus the grammar productions in `area:docs`).
- **Phase 3** exports the result through the corpus (`area:conformance`).

Documentation moves **with the behavior it describes**, not in a trailing
phase, so no commit ships an implementation that contradicts `docs/isa.md`.
Phase 3 is separable precisely because it adds no behavior - it only pins
behavior both earlier phases already have.

Each phase is independently committable and leaves `mix quality` green on its
own.

## Phase 1: The shared expansion helper and `Duration.parse/1`

### Overview

Add one public helper to `Predicator.Duration` that performs Decision 2's
integer-arithmetic exactness test and Decision 3's greedy decomposition, then
widen `parse/1` to use it. `::duration` widens for free through
`lib/predicator/cast.ex:112-117`. Update the three documents whose statements
change as a result.

### Changes Required:

#### 1. The expansion helper

**File**: `lib/predicator/duration.ex`
**Changes**: Add two module attributes and one public function, above
`parse/1`. `@doc` and `@spec` are mandatory (project conventions); errors are
values, never raised (ADR-0004).

```elixir
# The exact integer millisecond multiplier for each unit - the same table
# to_milliseconds/1 sums with. mo and y use this project's documented 30-day
# and 365-day approximations.
@unit_milliseconds %{
  "ms" => 1,
  "s" => 1_000,
  "m" => 60_000,
  "h" => 3_600_000,
  "d" => 86_400_000,
  "w" => 604_800_000,
  "mo" => 2_592_000_000,
  "y" => 31_536_000_000
}

# A fraction's remainder decomposes largest-first through these units only -
# never back into w, mo, or y. See docs/research/260814-px-5c5-...-decisions.md
# Decision 3: this keeps 0.5y as 182d12h rather than 26w12h, and re-introducing
# an approximate unit into a remainder would be circular.
@remainder_ladder [
  {"d", 86_400_000},
  {"h", 3_600_000},
  {"m", 60_000},
  {"s", 1_000},
  {"ms", 1}
]

@spec expand_fraction(non_neg_integer(), binary(), binary()) ::
        {:ok, [{non_neg_integer(), binary()}]}
        | {:error, :subunit_remainder}
        | {:error, :unknown_unit}
def expand_fraction(integer_part, fraction_digits, unit) do
  # 1. Map.fetch(@unit_milliseconds, unit) -> {:error, :unknown_unit} on miss.
  # 2. k = byte_size(fraction_digits); f = String.to_integer(fraction_digits);
  #    total = f * multiplier; denominator = 10 ** k.
  #    Integer arithmetic throughout - no String.to_float/1 anywhere on this
  #    path (Decision 2: 0.7 * 1000 is not reliably 700.0).
  # 3. rem(total, denominator) != 0 -> {:error, :subunit_remainder}.
  # 4. remainder_ms = div(total, denominator).
  # 5. pairs = (if integer_part > 0, do: [{integer_part, unit}], else: []) ++
  #            greedy decomposition of remainder_ms over @remainder_ladder,
  #            omitting zero components.
  # 6. If pairs == [], return [{0, unit}] - so "0.0s" expands to 0s rather
  #    than to nothing, which keeps the AST's unit list non-empty and keeps
  #    StringVisitor's rendering round-trippable.
end
```

Worked expectations, exhaustive over the decision record's table:

| Call | Result |
|---|---|
| `expand_fraction(1, "5", "s")` | `{:ok, [{1, "s"}, {500, "ms"}]}` |
| `expand_fraction(1, "5", "m")` | `{:ok, [{1, "m"}, {30, "s"}]}` |
| `expand_fraction(1, "5", "h")` | `{:ok, [{1, "h"}, {30, "m"}]}` |
| `expand_fraction(1, "5", "d")` | `{:ok, [{1, "d"}, {12, "h"}]}` |
| `expand_fraction(0, "5", "w")` | `{:ok, [{3, "d"}, {12, "h"}]}` |
| `expand_fraction(0, "5", "mo")` | `{:ok, [{15, "d"}]}` |
| `expand_fraction(1, "5", "y")` | `{:ok, [{1, "y"}, {182, "d"}, {12, "h"}]}` |
| `expand_fraction(1, "0", "s")` | `{:ok, [{1, "s"}]}` |
| `expand_fraction(0, "0", "s")` | `{:ok, [{0, "s"}]}` |
| `expand_fraction(1, "0", "ms")` | `{:ok, [{1, "ms"}]}` |
| `expand_fraction(0, "5", "ms")` | `{:error, :subunit_remainder}` |
| `expand_fraction(1, "0005", "s")` | `{:error, :subunit_remainder}` |
| `expand_fraction(1, "5", "x")` | `{:error, :unknown_unit}` |

Note `expand_fraction(0, "25", "s")` is `{:ok, [{250, "ms"}]}` and
`expand_fraction(0, "1", "s")` is `{:ok, [{100, "ms"}]}` - the three valid
sub-second cases the decision record names by hand.

#### 2. `Duration.parse/1`

**File**: `lib/predicator/duration.ex:312-352`
**Changes**: Widen both regexes to admit an optional fraction group and route
fractional components through the helper. The reduce becomes a
`reduce_while/3` so a `{:error, _}` from the helper collapses the whole parse
to `:error`. Repeated units still accumulate through `add_unit/3`, expansions
included (Decision 6c).

```elixir
@whole_string_regex ~r/\A(?:[0-9]+(?:\.[0-9]+)?(?:mo|ms|y|w|d|h|m|s))+\z/
@unit_pair_regex ~r/([0-9]+)(?:\.([0-9]+))?(mo|ms|y|w|d|h|m|s)/
```

The fraction group is not trailing, so `Regex.scan/3` with
`capture: :all_but_first` yields `""` for it when absent - that empty string
is the integer-component branch. Each scanned triple becomes:

```elixir
# ["1", "", "d"]   -> add_unit(acc, "d", 1)
# ["1", "5", "s"]  -> expand_fraction(1, "5", "s") |> each pair through add_unit/3
# any {:error, _}  -> halt, parse/1 returns :error
```

Update the `@doc`: values are "non-negative integers, optionally with a
decimal fraction"; a fraction must be an exact whole number of milliseconds
or the whole string is `:error`; the expansion targets `d/h/m/s/ms`; `mo` and
`y` fractions commit the documented 30/365 approximations at parse time (so
`parse("0.5mo")` yields `days: 15` and no `months`); there is no bare
fraction and no trailing dot. Add doctests for `parse("1.5s")`,
`parse("0.5mo")`, and `parse("0.5ms") == :error`.

#### 3. The ISA statement

**File**: `docs/isa.md`, §5, the `::duration` bullet at `:691-692`
**Changes**: Replace "the language's own duration-literal grammar, a sequence
of integer-unit pairs (`"1d2h30m"`)" with a normative statement of the widened
grammar - number-unit pairs where the number is
`[0-9]+(\.[0-9]+)?` (no bare fraction, no trailing dot); a fractional
component must convert to an exact whole number of milliseconds or the whole
string is `:undefined`; the expansion is the integer part on its own unit plus
a remainder decomposed largest-first through `d`, `h`, `m`, `s`, `ms` only;
fractions are permitted on every unit, `mo` and `y` using this document's
30-day and 365-day approximations; repeated units accumulate, expansions
included. Add the refinement sentence Decision 1 requires, modelled verbatim
in form on the `bracket_access` bullet at `docs/isa.md:518-523`: this bullet,
not the ISA version, changed - see §1's versioning rules for why. **§7 gains
no row and `Predicator.isa_version/0` does not move.**

#### 4. The language reference

**File**: `docs/reference/language.md`
**Changes**: In the `::duration` cast bullet (`:194`) and in the
"Duration parsing is a canonicalizer, not `to_string`'s inverse" section
(`:212-225`): state the fractional spelling, the exactness rule with
`"0.5ms"` as the worked rejection, the `mo`/`y` approximation commitment, and
the `to_string` consequence from Decision 5 (`"1.5s"::duration::string` is
`"1s500ms"`; the guaranteed direction remains
`some_duration::string::duration`). Note explicitly that a bare fraction is
`:undefined` here just as it already is for `::float` (`:185-186`).

#### 5. The changelog

**File**: `CHANGELOG.md`, under `## [Unreleased]` / `### Added`
**Changes**: One entry describing the widened duration grammar at both
surfaces, the exactness rule, the downward normalization, the
`to_string`/round-trip consequence, and that this is additive (both spellings
are errors today) and moves no ISA version. Written once here, covering the
whole bead, so Phases 2 and 3 do not each append a fragment.

#### 6. Tests

**File**: `test/predicator/duration_test.exs`
**Changes**: A new `describe "expand_fraction/3"` block covering every row of
the table above, including both error atoms. In the existing `parse/1`
blocks: add the accepting cases (`"1.5s"`, `"0.5s"`, `"0.25s"`, `"0.1s"`,
`"1.0s"`, `"0.0s"`, `"1.5m"`, `"1.5h"`, `"1.5d"`, `"0.5w"`, `"0.5mo"`,
`"1.5y"`, `"1.0ms"`), the mixed case `"1.5s200ms"` == 1 s 700 ms (Decision 6c,
with a comment naming the divergence from the literal grammar), and the
rejections. **Replace** the existing `test "rejects a float value"` at
`:553-555` (`Duration.parse("1.5d") == :error`) with a positive assertion in
the accepting block, and add rejections for `".5s"`, `"1.s"`, `"s"`,
`"0.5ms"`, `"1.0005s"`, `"1..5s"`, and `"1.5"` - none of which the suite
exercises today.

**File**: `test/predicator/cast_test.exs`
**Changes**: In the `::duration` block (`:260-308`), add `"1.5s"::duration`
yielding 1 s 500 ms, `"0.5ms"::duration` yielding `:undefined`, and
`"1.5s"::duration::string` yielding `"1s500ms"`. Follow the px-7t8 pattern at
`:144-176` - cite the ISA section in a comment.

### Success Criteria:

#### Automated Verification:
- [x] `mix quality` is green (format, compile, `credo --strict`, dialyzer,
      deps audit, suite with coverage).
- [x] Coverage for `lib/predicator/duration.ex` stays above the 90% minimum
      in `coveralls.json`; every branch of `expand_fraction/3`, both error
      atoms included, is covered.
- [x] The new `@doc` doctests on `parse/1` pass (they run as part of the
      suite).
- [x] `git diff --stat` touches no file outside `lib/predicator/duration.ex`,
      `test/predicator/duration_test.exs`, `test/predicator/cast_test.exs`,
      `docs/isa.md`, `docs/reference/language.md`, and `CHANGELOG.md` - in
      particular no `mix.exs`/`mix.lock` (`area:build` is exclusive,
      ADR-0005) and no `conformance/`.
- [x] `grep -n 'isa_version' lib/predicator.ex` and `docs/isa.md`'s §1
      version line still read 6, and `docs/isa.md` §7 has no new row.
- [x] `test/predicator/isa_sync_test.exs` still passes (it binds
      `docs/isa.md`'s opcode tables to `lib/predicator/instructions.ex`;
      neither moves here).

#### Manual Verification:
- [ ] In `iex -S mix`: `Predicator.Duration.parse("1.5s")`,
      `parse("0.5mo")`, `parse("1.5y")` return exactly the maps the
      decision record's table predicts.
- [ ] `Predicator.evaluate("\"1.5s\"::duration", %{})` returns the duration
      and `Predicator.evaluate("\"0.5ms\"::duration", %{})` returns
      `:undefined`.
- [ ] Read the rewritten `docs/isa.md` §5 bullet against
      `lib/predicator/duration.ex` and confirm the prose describes what the
      code does, including the `mo`/`y` approximation commitment.
- [ ] Confirm by eye that no float ever carries a fraction on the new path -
      `String.to_float/1` appears nowhere in `duration.ex`.
- [ ] No regressions in `::duration` behavior for integer strings.

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run full `mix quality` as the phase gate. In interactive
execution, pause here for the human to confirm the manual testing before
moving to the next phase. In looped (`--loop`) execution, this phase's
Automated Verification gates advancement automatically (via
`/wurk:commit --auto`), and Manual Verification items are deferred and
surfaced once at the end instead of blocking here.

---

## Phase 2: Fractional duration literals in the lexer and parser

### Overview

Give the lexer's float arm the same duration lookahead the integer arm has,
carry the fraction to the parser as decimal digits, and expand it in
`parse_duration_sequence/3` through Phase 1's helper. Add the two new
spanned compile errors (inexact fraction, unit collision). The AST, the
instructions visitor, the evaluator, and `StringVisitor` are all unchanged -
they receive already-expanded integer pairs.

### Changes Required:

#### 1. `take_number/1` returns the digit string

**File**: `lib/predicator/lexer.ex:479-516`
**Changes**: `finalize_number/4` already builds `number_string`; return it.

```elixir
# was: {number, remaining, count}
# now: {number, number_string, remaining, count}
```

There is exactly one `take_number/1` call site in `tokenize_chars/4`
(`:228`); its destructure updates to the new 4-tuple, and both the integer
and float branches downstream of it share that single binding. The integer
arm ignores the new element. This is the whole of "the fraction
travels as decimal digits, not as a parsed float" (Decision 6b);
`String.to_float/1` output never reaches the expansion.

#### 2. The float arm gains duration lookahead

**File**: `lib/predicator/lexer.ex:251-255`
**Changes**: Replace the unconditional `:float` token with the same
`try_parse_duration_after_number/2` dispatch the integer arm uses. That
function ignores its `number` argument (`:739`), so it needs no change.

```elixir
else
  # A decimal number followed by a duration unit is a fractional duration
  # component; the fraction travels as its literal digits, never as the
  # binary float. A decimal number followed by anything else is an ordinary
  # float, exactly as before - `1.5x` still lexes as :float then :identifier.
  case try_parse_duration_after_number(number, remaining) do
    {:ok, duration_units, new_remaining, total_consumed} ->
      [integer_digits, fraction_digits] = String.split(number_string, ".")
      leading = {:fractional_number, line, col, consumed,
                 {String.to_integer(integer_digits), fraction_digits}}
      tokenize_number_duration_sequence(leading, duration_units, new_remaining,
                                        line, col, consumed, total_consumed, tokens)

    :not_duration ->
      token = {:float, line, col, consumed, number}
      tokenize_chars(remaining, line, col + consumed, [token | tokens])
  end
end
```

Note this is safe against existing programs: a decimal number immediately
followed by a duration-unit letter is a parse error today (two adjacent
primaries), so no currently-valid program changes meaning. Record that
observation in a comment.

#### 3. `tokenize_number_duration_sequence/8` takes the leading token

**File**: `lib/predicator/lexer.ex:819-858`
**Changes**: The first parameter becomes the already-built leading token
instead of a bare `number`; the body's `number_token = {:integer, ...}` line
is deleted and the `@spec` updated. The integer arm at `:232-244` builds
`{:integer, line, col, consumed, number}` and passes it. The unit-token
emission loop, its column arithmetic, and the `duration_unit?/1` guard are
untouched. Also declare `:fractional_number` in the module's `token_type`
typespec beside `:integer` and `:duration_unit`.

#### 4. The parser accepts a fractional component

**File**: `lib/predicator/parser.ex`
**Changes**:

- Rename `parse_duration_sequence_from_integer/3` to
  `parse_duration_sequence_from_number/3` and let its first argument be
  either an integer or `{:frac, integer_part, fraction_digits}`. Its
  `:not_duration` return is unchanged.
- Add a `parse_primary_token/2` clause for
  `{:fractional_number, line, col, _len, {int, frac}}`, mirroring the
  `:integer` clause at `:1363-1378` and calling
  `parse_duration_sequence_from_number({:frac, int, frac}, next_state,
  {line, col})`. The lexer emits `:fractional_number` **only** when a
  duration unit follows, so `:not_duration` cannot occur on this path; make
  that a documented invariant and, on the `:not_duration` branch, return
  `unexpected_token_error/2` naming the missing unit rather than
  reconstructing a float. (This keeps the function total per ADR-0004 - no
  raise at a leaf - at the cost of a branch no source reaches. If the
  coverage gate flags it, the fallback is to make the clause a hard match on
  the following `:duration_unit` token with a comment citing the lexer
  invariant, the same way `duration_loc/2` at `:1555-1561` already documents
  and relies on a lexer/parser invariant.)
- Extend `parse_duration_sequence/3` (`:1980-2002`) to also accept a
  `:fractional_number` token mid-sequence (`1h1.5m`), with the same
  structure as its existing `:integer` branch.
- Accumulate components as `{value_or_frac, unit, component_span}` rather
  than `{integer, unit}`, so the two new errors can be spanned per component.
  The component span runs from the number token's start to
  `token_end/1` of its unit token.

#### 5. Expansion and the collision check at finalization

**File**: `lib/predicator/parser.ex`, the two finalization branches of
`parse_duration_sequence/3`
**Changes**: Before building the AST node, run one new private function over
the accumulated components:

1. If **no** component is fractional, emit `{integer, unit}` pairs exactly as
   today and skip step 2 entirely. This is what keeps integer-only literals
   byte-for-byte identical, including their pinned last-wins overwrite
   behavior (Decision 6b, and `conformance/cases/durations.json`'s
   `later-unit-pair-overwrites-earlier` case must not move).
2. Otherwise expand each fractional component through
   `Duration.expand_fraction/3`. On `{:error, :subunit_remainder}`, return
   a parse error spanning **that component**, following the date-literal
   per-family precedent (`lib/predicator/lexer.ex:465-467`): a component that
   fails exactness is wrong as a whole. Message shape:
   `"Duration fraction is not a whole number of milliseconds: 0.5ms"`.
3. Concatenate the expanded pairs in source order and check that no unit is
   named twice. On a collision, return a parse error spanning **the whole
   literal** (start of the first component to the end of the last), message
   shape:
   `"Duration literal names the 'ms' unit twice after expanding a fraction"`.
   `1.5s200ms`, `1.5s1s`, and `1.5s0.5s` are all errors.
4. Build the standard `{:duration, pairs, duration_loc(state, position)}`
   node.

The AST type at `lib/predicator/parser.ex:178` is unchanged.

#### 6. The documented grammar

**Files**: `docs/architecture.md:46` and `docs/reference/language.md:46`
**Changes**: Both copies of the production move together:

```
duration     → DURATION_NUMBER UNIT+
DURATION_NUMBER → NUMBER ( "." NUMBER )?
```

Add a sentence beside each noting that a fractional component expands at
parse time, that an inexact fraction and a post-expansion unit collision are
compile errors, and that the fractional form does **not** change operator
precedence - the precedence table in `docs/architecture.md` is untouched.

**File**: `docs/reference/language.md`, the canonicalizer section
**Changes**: Add the Decision 6c divergence sentence - the literal
`1.5s200ms` is a compile error while `"1.5s200ms"::duration` is 1 s 700 ms,
because the string API is documented as a lenient canonicalizer and the
literal grammar's repeats are pinned last-wins. Also record that decompiling
a program containing `1.5s` prints `1s500ms`.

#### 7. Tests

**File**: `test/predicator/parser_test.exs` (duration block, `:1686-1815`)
**Changes**: `1.5s` -> `{:duration, [{1, "s"}, {500, "ms"}], _}`; `0.5mo` ->
`[{15, "d"}]`; `1.5y` -> `[{1, "y"}, {182, "d"}, {12, "h"}]`; `1h1.5m` ->
`[{1, "h"}, {1, "m"}, {30, "s"}]`; `1.0s` -> `[{1, "s"}]`; `0.0s` ->
`[{0, "s"}]`. Error cases: `0.5ms`, `1.0005s`, `1.5s200ms`, `1.5s1s`. Confirm
`1.5x` still lexes as float-then-identifier and produces today's error, and
that `.5s` is unchanged.

**File**: `test/predicator/lexer_test.exs`
**Changes**: This file has **no duration-literal token tests** today. Add a
`describe` block asserting the exact token stream for `3d8h` (the existing
integer path, as a regression anchor) and for `1.5s` (the new
`:fractional_number` token carrying `{1, "5"}`, then `{:duration_unit, ...,
"s"}`), plus `1.5` alone still lexing as `:float` and `1.5x` as `:float` then
`:identifier`.

**File**: `test/predicator/parser_spans_test.exs` (`:219-247`)
**Changes**: `assert_span("1.5s", "1.5s")`, `assert_span("1h1.5m", "1h1.5m")`,
and assertions that the inexact-fraction error's span covers `0.5ms` within a
larger expression and that the collision error's span covers the whole
`1.5s200ms` literal.

**File**: `test/predicator/integration/` (a new or existing duration file)
**Changes**: End-to-end `Predicator.evaluate/3`: `1.5s ago` and
`1.5s from now` relative-date forms still work; `Predicator.compile("1.5s")`
yields `[["duration", [[1, "s"], [500, "ms"]]]]`; and
`Predicator.compile("3d8h")` is byte-identical to its pre-change output.

**File**: `test/predicator/date_arithmetic_string_visitor_test.exs` (or the
nearest round-trip file)
**Changes**: `Predicator.decompile/1` of the `1.5s` AST renders `"1s500ms"`,
and re-parsing that string yields the identical AST. This is the project
extension's always-required round-trip criterion, stated for a grammar form
that adds no AST node.

### Success Criteria:

#### Automated Verification:
- [x] `mix quality` is green.
- [x] Coverage for `lib/predicator/lexer.ex` and `lib/predicator/parser.ex`
      stays above the 90% minimum in `coveralls.json`.
- [x] `Predicator.compile("3d8h")` and the whole existing duration test
      corpus are unchanged - the suite proves this, since every existing
      duration assertion is left untouched.
- [x] The round-trip test asserts `decompile(parse("1.5s")) == "1s500ms"` and
      that re-parsing it gives the identical AST.
- [x] No new Credo suppression is added; the existing lexer/parser complexity
      suppressions are not widened without an explanatory comment.
- [x] `git diff --stat` touches nothing under `conformance/` and no
      `area:build` file.

#### Manual Verification:
- [ ] In `iex -S mix`: `Predicator.compile("1.5s")` prints
      `[["duration", [[1, "s"], [500, "ms"]]]]`.
- [ ] `Predicator.compile("0.5ms")` and `Predicator.compile("1.5s200ms")`
      return errors whose messages read clearly to a user who did not write
      this plan, and whose carets land where the plan says (the component,
      and the whole literal, respectively).
- [ ] `Predicator.compile("1.5x")` fails the same way it does on `main` -
      the fractional path did not capture a non-unit suffix.
- [ ] `Predicator.evaluate("1.5s ago < now()", %{})` behaves sensibly.
- [ ] No regressions in relative-date forms (`ago`, `from now`, `next`,
      `last`) with fractional durations.

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run full `mix quality` as the phase gate. In interactive
execution, pause here for the human to confirm the manual testing before
moving to the next phase. In looped (`--loop`) execution, this phase's
Automated Verification gates advancement automatically (via
`/wurk:commit --auto`), and Manual Verification items are deferred and
surfaced once at the end instead of blocking here.

---

## Phase 3: Export the refinement through the conformance corpus

### Overview

Because Decision 1 mints no ISA version, the conformance corpus **is** the
export mechanism for the refined `::duration` semantics. Add authored cases
and regenerate. No library code changes in this phase.

### Changes Required:

#### 1. Authored duration cases

**File**: `conformance/cases/durations.json`
**Changes**: Append two cases, in the existing shape (see the eight cases at
`:3-107`; `notes` is where the reasoning goes):

- `durations/fractional-literal-expands` - source `1.5s`, expected duration
  with `seconds: 1` and `milliseconds: 500`. Note: the fraction expands at
  parse time to integer unit pairs, so the `duration` opcode's operand shape
  is unchanged; this case is what pins the expansion for a sibling.
- `durations/fractional-month-uses-approximation` - source `0.5mo`, expected
  duration with `days: 15` and no `milliseconds` key (it is 0, and this file's
  convention omits it). Note: a fractional `mo` commits this project's
  documented 30-day approximation at parse time, which is why the exported
  value has no `months` component.

#### 2. Authored cast cases

**File**: `conformance/cases/casts.json`
**Changes**: Append two cases beside the existing duration casts (`:90-108`):

- `casts/string-to-duration-fractional` - source `"1.5s"::duration`, expected
  duration with `seconds: 1`, `milliseconds: 500`. Note: this is the export
  mechanism for the §5 refinement - no ISA version was minted (see
  `docs/research/260814-px-5c5-fractional-durations-decisions.md`), so the
  corpus is where a sibling learns the widened grammar.
- `casts/string-to-duration-subunit-remainder-is-undefined` - source
  `"0.5ms"::duration`, expected `{ "$type": "undefined" }`. Note: pins the
  exactness rule; half a millisecond is below the value domain's floor, and
  by ADR-0011 an unparseable string is `:undefined`, never an error.

The two new **literal** errors get no corpus case: `docs/isa.md:847-852`
excludes parse and lexer errors from the corpus by construction. Say so in
the PR body so the omission reads as deliberate.

#### 3. Regenerate

**Command**: `mix corpus.generate`
**Changes**: `conformance/corpus/*.json` and `conformance/manifest.json` are
rewritten by the task and are **never hand-edited**. The generator checks each
authored assertion against the real compiler and evaluator and fails loudly on
disagreement, so a green generate is itself a verification that the expected
values above are right. `manifest.json`'s `corpus_hash` moves; `isa_version`
stays 6.

#### 4. Commit and PR narration

Per ADR-0003, a corpus diff moves the exported specification, so the commit
message and the PR body explain it: four cases added, the `::duration`
refinement they export, no ISA version bump and why (Decision 1), and the
`corpus_hash` change that invalidates sibling ratchet pins
(`conformance/RATCHET.md`) - which is expected and blocks nothing here
(ADR-0003).

### Success Criteria:

#### Automated Verification:
- [x] `mix corpus.generate` completes with no assertion disagreement.
- [x] `mix corpus.generate --check` reports no drift.
- [x] `test/predicator/conformance/corpus_freshness_test.exs` passes - the
      binding test that ties `conformance/corpus/` to
      `conformance/cases/`, and the reason no new
      `gate.sabotage.test_roots` entry is needed.
- [x] `test/predicator/conformance/schema_validation_test.exs` passes (the
      new cases satisfy `conformance/schema/case.json`, including the id
      pattern).
- [x] `test/predicator/conformance/opcode_coverage_test.exs` and
      `function_coverage_test.exs` still pass.
- [x] `mix quality` is green.
- [x] `git diff --stat conformance/` shows changes to
      `conformance/cases/durations.json`, `conformance/cases/casts.json`, the
      generated `conformance/corpus/` files, and `conformance/manifest.json` -
      and nothing else.
- [x] `conformance/manifest.json`'s `isa_version` still reads 6.

#### Manual Verification:
- [ ] Read the generated corpus diff and confirm every changed line is
      attributable to one of the four new cases or to the `corpus_hash`
      recomputation - no unrelated case moved.
- [ ] Confirm the four cases' `notes` fields would tell a Ruby or TypeScript
      porter what to implement without reading this repo's source.
- [ ] Confirm the `durations/later-unit-pair-overwrites-earlier` case is
      byte-identical to its previous form (Decision 6b's "integer-only
      literals are untouched").

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run full `mix quality` as the phase gate. In interactive
execution, pause here for the human to confirm the manual testing. In looped
(`--loop`) execution, this phase's Automated Verification gates advancement
automatically (via `/wurk:commit --auto`), and Manual Verification items are
deferred and surfaced once at the end.

---

## ISA Impact

1. **Version** - **no bump. ISA stays v6.** No opcode is added, removed, or
   renamed. The `duration` opcode's operand is still
   `units (list of [int, string])` (`docs/isa.md:326`) and its two error
   reasons (`docs/isa.md:576-577`) are unchanged, because a fractional source
   literal lowers to *more integer pairs*, not to a float operand. The one
   ISA-visible change is what the `cast` opcode does with a fractional string
   under `::duration`: `"1.5s"::duration` was `:undefined` and becomes a
   duration. Decision 1 settles this as a **v6 refinement** on four grounds -
   §1's widening rule scopes itself to "operand forms carried in the
   instruction list" and nothing in the wire format moves; a version minted
   here would be undetectable by the opcode-name scan §1 mandates and that
   `Predicator.Instructions.required_isa/1` implements; §7's own precedent
   ("3.8.0 did exactly that to v2") covers refining *specified* behavior, not
   only filling gaps; and ADR-0011 built `cast` to be total, so moving a
   string from the unparseable set to the parseable set is the monotone
   widening its `:undefined` failure mode was designed for. No expression
   that produced a value before produces a different value or an error after.
2. **Stamp** - `docs/isa.md` §5's `::duration` bullet is rewritten to state
   the widened grammar normatively, carrying a `bracket_access`-style
   sentence (`docs/isa.md:518-523`) that this bullet, not the ISA version,
   changed. `docs/isa.md` §7 gains **no** row. No opcode subsection is added
   and no conformance tier is assigned; the new corpus cases inherit tier 4
   from the `duration` opcode by construction, and the `durations` feature tag
   is derived automatically (`lib/predicator/conformance/features.ex:52`).
   `Predicator.isa_version/0` does not move.
3. **Migration** - **none needed.** Every instruction list compiled before
   this change still runs and produces the same answer: integer-only literals
   lower byte-for-byte identically (Phase 2, change 5, step 1), and the only
   behavior that moves is a `cast` on a string that previously produced
   `:undefined`. A stored compiled artifact is unaffected. Siblings
   (`impl/rb`, `impl/ts`) pick this up on their own schedule; their ratchet
   registries repin against the new `corpus_hash` when they do, which is the
   expected state under ADR-0003 and blocks nothing here.

## Testing Strategy

### Unit Tests:

- `test/predicator/duration_test.exs` - `expand_fraction/3` exhaustively over
  the decision record's table, both error atoms included; `parse/1` over every
  accepted fractional spelling, the mixed accumulate case `"1.5s200ms"`, and
  the rejections (`".5s"`, `"1.s"`, `"s"`, `"0.5ms"`, `"1.0005s"`, `"1..5s"`,
  `"1.5"`). The existing `test "rejects a float value"` (`:553-555`) is
  replaced by its positive counterpart.
- `test/predicator/cast_test.exs` - `"1.5s"::duration`,
  `"0.5ms"::duration` -> `:undefined`, and `"1.5s"::duration::string` ->
  `"1s500ms"`, with the ISA section cited in a comment (the px-7t8 pattern at
  `:144-176`).
- `test/predicator/lexer_test.exs` - the token stream for `3d8h` (regression
  anchor), `1.5s`, `1.5` alone, and `1.5x`.
- `test/predicator/parser_test.exs` - the AST for each fractional literal in
  the decision record's table, plus the two error forms.
- `test/predicator/parser_spans_test.exs` - spans for `1.5s` and `1h1.5m`,
  and the two error spans (component-wide, literal-wide).
- Edge cases that actually bite: `0.0s` (must not yield an empty unit list),
  `1.0ms` (valid) versus `1.5ms` (rejected), `0.5w` (crosses into `d`+`h`),
  `1.5y` (crosses three ladder rungs), `1.5s200ms` (collision as a literal,
  accumulate as a string), and `1.5x` (must not become a duration).

### Integration Tests:

- `test/predicator/integration/` - end-to-end `Predicator.evaluate/3` for a
  fractional duration in a comparison, in `ago`/`from now` relative-date
  forms, and through date arithmetic; plus `Predicator.compile("3d8h")`
  asserted byte-identical to its pre-change instruction list.

### Round-trip:

- `decompile/1` of the `1.5s` AST renders `"1s500ms"`, and re-parsing that
  string yields the identical AST. This is the project extension's
  always-required "new grammar node round-trips through `StringVisitor`
  without losing information" criterion, adapted: the grammar form adds no AST
  node, so the information that must survive is the *expanded* value, and it
  does.

### Manual Testing Steps:

1. `iex -S mix`, then `Predicator.Duration.parse("1.5s")`, `parse("0.5mo")`,
   `parse("1.5y")`, `parse("0.5ms")` - compare against the decision record's
   normalization table.
2. `Predicator.compile("1.5s")` - confirm
   `[["duration", [[1, "s"], [500, "ms"]]]]`.
3. `Predicator.compile("0.5ms")` and `Predicator.compile("1.5s200ms")` -
   read the error messages as a user would, and check the caret positions.
4. `Predicator.compile("1.5x")` - confirm it fails exactly as on `main`.
5. `Predicator.evaluate("\"1.5s\"::duration::string", %{})` - confirm
   `"1s500ms"`.
6. Read the regenerated corpus diff line by line against the four authored
   cases.

## Performance Considerations

Negligible and worth stating only to close the question. The lexer's float arm
gains one `try_parse_duration_after_number/2` call per decimal literal, which
is a regex probe against the immediately-following characters and returns
`:not_duration` in one `cond` miss for every non-duration float - the same
cost the integer arm already pays on every integer literal. The expansion
itself is at most five integer divisions per fractional component, at parse
time, never at evaluation time. Nothing in the hot evaluation path changes.

## References

- Bead: `px-5c5` (mirrors `st-rsl`)
- Decision record (authoritative for every design question):
  `docs/research/260814-px-5c5-fractional-durations-decisions.md`
- Codebase survey: `docs/research/260814-px-5c5-fractional-durations.md`
- Closest precedent for a fractional-value policy call and its test shape:
  `docs/research/260810-px-7t8-datetime-string-fractional-seconds.md`
- Last structural change to the duration parse path:
  `docs/plans/260805-px-bxz-duration-unit-order.md`
- The per-family lexer span rule this plan's errors follow:
  `docs/plans/260814-px-la5-lexical-error-span-extent.md`,
  `lib/predicator/lexer.ex:465-467`
- ADRs: `docs/adr/0003-*` (this repo leads the ISA),
  `docs/adr/0004-*` (errors are values), `docs/adr/0005-*` (area labels;
  this bead carries `area:evaluator`, `area:lexer-parser`, `area:docs`,
  `area:conformance` and must not acquire `area:build`),
  `docs/adr/0010-*` (the `st-rsl` mirror obligation),
  `docs/adr/0011-*` (`cast` is total; failure is `:undefined`)
- ISA: `docs/isa.md` §1 (versioning), §5 (`cast` string formats and the
  `bracket_access` refinement template at `:518-523`), §8 (the corpus does
  not cover parse or lexer errors)

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] In `iex -S mix`: `Predicator.Duration.parse("1.5s")`,
      `parse("0.5mo")`, `parse("1.5y")` return exactly the maps the
      decision record's table predicts.
- [ ] `Predicator.evaluate("\"1.5s\"::duration", %{})` returns the duration
      and `Predicator.evaluate("\"0.5ms\"::duration", %{})` returns
      `:undefined`.
- [ ] Read the rewritten `docs/isa.md` §5 bullet against
      `lib/predicator/duration.ex` and confirm the prose describes what the
      code does, including the `mo`/`y` approximation commitment.
- [ ] Confirm by eye that no float ever carries a fraction on the new path -
      `String.to_float/1` appears nowhere in `duration.ex`.
- [ ] No regressions in `::duration` behavior for integer strings.

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run full `mix quality` as the phase gate. In interactive
execution, pause here for the human to confirm the manual testing before
moving to the next phase. In looped (`--loop`) execution, this phase's
Automated Verification gates advancement automatically (via
`/wurk:commit --auto`), and Manual Verification items are deferred and
surfaced once at the end instead of blocking here.

---

### Phase 2

- [ ] In `iex -S mix`: `Predicator.compile("1.5s")` prints
      `[["duration", [[1, "s"], [500, "ms"]]]]`.
- [ ] `Predicator.compile("0.5ms")` and `Predicator.compile("1.5s200ms")`
      return errors whose messages read clearly to a user who did not write
      this plan, and whose carets land where the plan says (the component,
      and the whole literal, respectively).
- [ ] `Predicator.compile("1.5x")` fails the same way it does on `main` -
      the fractional path did not capture a non-unit suffix.
- [ ] `Predicator.evaluate("1.5s ago < now()", %{})` behaves sensibly.
- [ ] No regressions in relative-date forms (`ago`, `from now`, `next`,
      `last`) with fractional durations.

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run full `mix quality` as the phase gate. In interactive
execution, pause here for the human to confirm the manual testing before
moving to the next phase. In looped (`--loop`) execution, this phase's
Automated Verification gates advancement automatically (via
`/wurk:commit --auto`), and Manual Verification items are deferred and
surfaced once at the end instead of blocking here.

---

### Phase 3

- [ ] Read the generated corpus diff and confirm every changed line is
      attributable to one of the four new cases or to the `corpus_hash`
      recomputation - no unrelated case moved.
- [ ] Confirm the four cases' `notes` fields would tell a Ruby or TypeScript
      porter what to implement without reading this repo's source.
- [ ] Confirm the `durations/later-unit-pair-overwrites-earlier` case is
      byte-identical to its previous form (Decision 6b's "integer-only
      literals are untouched").

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run full `mix quality` as the phase gate. In interactive
execution, pause here for the human to confirm the manual testing. In looped
(`--loop`) execution, this phase's Automated Verification gates advancement
automatically (via `/wurk:commit --auto`), and Manual Verification items are
deferred and surfaced once at the end.

---
