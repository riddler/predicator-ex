---
date: 2026-08-14T21:40:19-0600
researcher: Claude
git_commit: 4faf42f5c396bb62805ea28281dc7297f1098f54
branch: px-5c5-fractional-durations
repository: predicator-ex
beads_issue: px-5c5
topic: "Accepting fractional values in duration literals and Duration.parse/1"
tags: [research, codebase, duration, lexer-parser, evaluator]
status: complete
last_updated: 2026-08-14
last_updated_by: Claude
---

# Research: Accepting fractional values in durations

**Date**: 2026-08-14T21:40:19-0600
**Git Commit**: 4faf42f5c396bb62805ea28281dc7297f1098f54
**Branch**: px-5c5-fractional-durations
**Bead**: px-5c5 (mirrors st-rsl)

## Research Question

px-5c5 asks to accept fractional values in (a) `Predicator.Duration.parse/1`
and (b) the language's duration-literal lexing, normalizing downward so the
duration map's fields stay integers (`"1.5s"` -> 1s500ms). This document maps
what exists today: where integer-only is enforced, how many independent
enforcement sites there are, which of them are ISA-specified, what the
existing tests pin, and what precedent the repo has already set for
fractional handling.

## Summary

Integer-only durations are enforced in **four independent places**, not one,
and they sit at three different layers:

1. **The lexer** never looks for a unit suffix after a decimal number. The
   digit branch of `tokenize_chars/4` gates on `is_integer(number)`, and the
   `else` arm is commented "Float - no duration units supported"
   ([`lib/predicator/lexer.ex:226-255`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/lexer.ex#L226-L255)). `3.5d` therefore lexes as a `:float`
   token followed by an `:identifier` token, and the parser never sees a
   duration at all.
2. **`Duration.parse/1`** matches `~r/\A(?:[0-9]+(?:mo|ms|y|w|d|h|m|s))+\z/`
   and converts with `String.to_integer/1` ([`lib/predicator/duration.ex:312-352`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/duration.ex#L312-L352)).
   A decimal point cannot match, so `parse("1.5d")` is `:error`.
3. **`Duration.from_units/1`** gates each value on `Integer.parse/1` with a
   full-string match ([`lib/predicator/duration.ex:72-85`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/duration.ex#L72-L85)).
4. **The `duration` opcode** guards each operand pair with
   `is_integer(value) and is_binary(unit)`
   ([`lib/predicator/evaluator.ex:1825`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/evaluator.ex#L1825)); anything else is
   `EvaluationError` `"invalid_duration_format"`.

The bead's stated approach - normalize downward at parse time so the duration
map's fields stay integers - keeps site 4 untouched, which is what keeps the
instruction set still. The `duration` opcode's operand stays
`[[integer, string], ...]` exactly as [`docs/isa.md:326`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/isa.md#L326) specifies, because a
fractional source literal lowers to *more integer pairs*, not to a float
operand. Under §1's own rule, a new source spelling for a value the domain
already admits "moves no version, because a spelling is surface syntax (§6)
and attaches to no opcode name".

**The one part that is not surface syntax is `::duration`.** That is the
`cast` opcode, its string-parse behavior is specified normatively in
[`docs/isa.md:691-692`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/isa.md#L691-L692) as "a sequence of integer-unit pairs", and it is backed
by the very function this bead widens ([`lib/predicator/cast.ex:112-117`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/cast.ex#L112-L117) calls
`Duration.parse/1`). Widening `parse/1` changes what `"1.5s"::duration`
evaluates to - `:undefined` today, a duration afterwards - under the `cast`
opcode's own name. Whether that is a §1 "widening an accepted type" (which
mints an ISA version) or a v6 refinement of an under-specified sentence (the
px-7t8 precedent) is the single genuine ISA question this bead carries. See
**ISA Impact** below.

Downstream of construction, nothing else cares: every consumer identifies a
duration structurally by key presence and never inspects value types. The
places that would break on a float field are all *unguarded standard-library
calls* (`div/2`, `Date.add/2`, `DateTime.add/3`), which is exactly why
normalizing to integers at parse time is the shape the bead proposes.

## Detailed Findings

### `lib/predicator/duration.ex` - the module under change

**The duration map** is built by `new/1` ([`lib/predicator/duration.ex:36-47`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/duration.ex#L36-L47)),
eight atom keys defaulting to `0`. It is a plain map, not a struct - a fact
[`CHANGELOG.md:1019-1026`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/CHANGELOG.md#L1019-L1026) calls out as load-bearing for context normalization.

**`parse/1`** ([`lib/predicator/duration.ex:338-352`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/duration.ex#L338-L352)) is the bead's primary
target. Two module attributes define it:

```elixir
@whole_string_regex ~r/\A(?:[0-9]+(?:mo|ms|y|w|d|h|m|s))+\z/
@unit_pair_regex ~r/([0-9]+)(mo|ms|y|w|d|h|m|s)/
```

The whole-string regex is the anchoring gate (`\A`/`\z`, not `^`/`$` - see the
trailing-newline regression note below); the pair regex then scans and each
capture goes through `String.to_integer/1`. `mo`/`ms` precede the
single-character units in both alternations, which is how `"1mo"` is one month
rather than one minute plus a stray `o`. Repeated units **accumulate** via
`add_unit/3` (`"1d2d"` is 3 days).

**`to_milliseconds/1`** ([`lib/predicator/duration.ex:153-163`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/duration.ex#L153-L163)) and
**`to_seconds/1`** (`:127-136`) are plain sums of `Map.get(duration, k, 0) *
<integer multiplier>`. Both are `@spec`'d to return `integer()`. A float in
any field promotes the whole sum to a float and violates that spec at runtime
(Dialyzer-catchable, not runtime-checked).

**The mo/y approximations** are `1 month = 30 days` (2_592_000 s) and
`1 year = 365 days` (31_536_000 s), documented in both functions' `@doc` and
repeated in `add_to_date/2` and `subtract_from_date/2`
([`lib/predicator/duration.ex:176-192`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/duration.ex#L176-L192), `:226-242`) as `* 30` and `* 365` day
multipliers. These are the approximations the bead's design decision 2
(fractions on `mo`/`y`) would have to lean on if fractions were allowed there.

**`to_string/1`** ([`lib/predicator/duration.ex:278-310`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/duration.ex#L278-L310)) emits largest unit
first, omits zero components, and returns `"0s"` when everything is zero. It
formats each field with `"#{value}#{suffix}"` interpolation, so a float field
would render literally (`"1.5d"`) - a string `parse/1` cannot read back.

**Date/DateTime arithmetic is integer-only at the stdlib boundary**:
`add_to_date/2`/`subtract_from_date/2` call `div(additional_seconds, 86_400)`
(`:189`, `:239`) and `Date.add/2` (`:191`, `:241`); the datetime pair calls
`DateTime.add/3` (`:207`, `:212`, `:257`, `:262`). `div/2` raises on floats,
and `Date.add/2`/`DateTime.add/3` require integer offsets. None of these is
guarded - they are reached only if a float slips past the four gates above,
e.g. by calling `Duration.new/1` or `add_unit/3` directly with a float
(neither has a runtime type check; `add_unit/3`'s `@spec` claims
`non_neg_integer()`).

### `lib/predicator/lexer.ex` - the duration-literal grammar

There is **no `:duration` token**. A duration literal lexes as an alternating
run of `:integer` and `:duration_unit` tokens, and the parser reassembles it.

- `take_number/1` ([`lib/predicator/lexer.ex:479-516`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/lexer.ex#L479-L516)) is the single scanner for
  integers and floats. It consumes at most one decimal point, and only when the
  `.` is followed by another digit (`:492-497`); `finalize_number/4` (`:505-516`)
  returns a float via `String.to_float/1` when a point was seen, else an
  integer. **A leading-dot spelling like `.5s` never reaches this scanner at
  all** - the digit branch at `:227` is keyed on `c >= ?0 and c <= ?9`, so a
  leading `.` is dispatched elsewhere entirely.
- The integer/float fork is [`lib/predicator/lexer.ex:231`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/lexer.ex#L231) vs `:251`. Only the
  integer arm calls `try_parse_duration_after_number/2` (`:737-752`); the float
  arm emits a bare `:float` token with the comment "Float - no duration units
  supported" (`:252`).
- `extract_duration_unit/1` (`:779-806`) is the disambiguation point: an
  ordered `cond` trying `~r/^(ms|mo)(\d.*)/`, then `~r/^([ydhmsw])(\d.*)/`,
  then the same two against `(\D.*|$)`. Two-character units are tried before
  single-character ones in both the mid-sequence and end-of-run cases, which is
  the whole of the `m`/`mo` and `s`/`ms` disambiguation. `duration_unit?/1`
  (`:808-817`) is the closed list of eight suffixes.
- Note the `{value, unit}` pairs this path threads carry `""` for value at
  every match site (`:786`, `:791`, `:796`, `:801`) - only the unit letters are
  extracted here. The magnitudes come from the separate `:integer` tokens.
- `tokenize_number_duration_sequence/8` (`:819-858`) emits
  `{:integer, line, col, len, number}` then one
  `{:duration_unit, line, col, String.length(unit), unit}` per suffix,
  advancing the column by each unit's own length. So a `:duration_unit` is an
  ordinary 5-element token and `token_end/1` computes its end generically
  ([`lib/predicator/parser.ex:1546`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/parser.ex#L1546)) with no duration-specific clause.
- Walking `3d8h`: the first pass consumes `3`, then `d` (the unit walker stops
  at `8`, a digit no unit regex matches), and `tokenize_chars` re-enters the
  digit branch for `8h`. The alternating token stream is produced by several
  independent passes through `:227-255`.

**Error handling: durations have no lexer-level failure mode.**
`try_parse_duration_after_number/2` returns only `{:ok, ...}` or
`:not_duration` (`:737-738`); the latter re-lexes the number as a plain
integer and lets the following characters tokenize normally (so `3x` is an
integer plus an identifier). This matters for the per-family span rule the
lexer otherwise follows:

- simple tokens and unknown characters: a point at the failing character,
  `{{line, col}, {line, col + 1}}` (`:373`, `:474`);
- string literals: opening quote through wherever `take_string` stopped
  (`:441-443`);
- date literals: the comment at `:465-467` states the widened rule explicitly -
  "A malformed literal is wrong as a whole, so the span covers the whole
  literal - opening `#` through the closing `#`, or through end of input when
  there is none" (this is commit `ceb9af7`/`4faf42f`, the two commits
  immediately preceding this branch);
- **duration literals: no family convention exists**, because they never fail
  as a unit. A malformed duration surfaces later as an ordinary parser
  unexpected-token error using that token's own span.

### `lib/predicator/parser.ex` - consumption

- `parse_primary_token/2`'s `:integer` clause ([`lib/predicator/parser.ex:1362-1378`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/parser.ex#L1362-L1378))
  always tries `parse_duration_sequence_from_integer/3` first. The `:float`
  clause (`:1381-1383`) unconditionally builds a `{:literal, value, pos}` node
  with **no duration lookahead** - the parser-side mirror of the lexer's fork.
- `parse_duration_sequence/3` (`:1980-2002`) loops on the alternating
  `:integer`/`:duration_unit` run and finalizes
  `{:duration, Enum.reverse(units), duration_loc(state, position)}`. **No
  validation happens here** - not on ordering, not on repetition, not on
  magnitude.
- AST shape: `{:duration, [{integer(), binary()}], position()}`
  ([`lib/predicator/parser.ex:178`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/parser.ex#L178)).
- `duration_loc/2` (`:1555-1561`) spans from the leading integer token's start
  to `token_end(previous_token(state))`, relying on the documented invariant
  that the last `:duration_unit` has already been consumed on both terminating
  branches.
- `parse_duration_with_direction/2` (`:2007-2037`) wraps into
  `{:relative_date, duration_ast, direction, loc}` for `ago`/`from now`;
  `parse_relative_date_expression/3` (`:2042-2069`) handles the `next`/`last`
  prefix and requires a `{:duration, ...}` primary, erroring with
  "Expected duration after '<direction>'" otherwise.
- Neither the lexer nor the parser calls `Duration.from_units/1` or
  `add_unit/3`. Those run at evaluation time only.

### Downstream consumers

**[`lib/predicator/types.ex:27-36`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/types.ex#L27-L36)** declares
`@type duration :: %{years: non_neg_integer(), ... milliseconds: non_neg_integer()}`
and lists `duration()` in the `value()` union (`:64`). This is the only formal
statement that the fields are integers, and it is a Dialyzer contract, not a
runtime check. `types_match?/2` (`:294-305`) routes durations through its
generic plain-map arm and never special-cases them.

**`lib/predicator/cast.ex`** is the ISA-visible surface:

- `cast(value, "duration")` string clause (`:112-117`) calls
  `Duration.parse/1`, mapping `:error` to `:undefined`. **This is the site
  that makes this bead an ISA question.**
- The identity clause (`:50-63`) matches on the presence of the seven base keys
  only and never inspects values.
- `cast(duration, "string")` (`:141-154`) delegates to `Duration.to_string/1`.

**`lib/predicator/evaluator.ex`**:

- `["duration", units]` dispatches at `:668-670` to `execute_duration/2`
  (`:1806-1816`) and `convert_units_to_duration_map/1` (`:1819-1849`). The
  reduce clause guards `is_integer(value) and is_binary(unit)` (`:1825`);
  anything else halts with `"invalid_duration_format"` (`:1840-1848`), and an
  unrecognized unit string is `"invalid_duration_unit"` (`:1830-1838`). Note
  the initial map here has **seven** keys - `milliseconds` is added only when a
  `ms`-family unit appears - and later pairs **overwrite** earlier ones
  (`Map.put`), which is the opposite of `Duration.parse/1`'s accumulate.
- Date arithmetic (`:1041-1064`, `:1118-1133`) guards with `duration_map?/1`
  (`:1170-1175`, key presence only) and delegates to the `Duration` functions.
- Durations the evaluator *produces* are always integer-valued:
  `Date.diff/2` into `Duration.new(days: ...)` (`:1096-1100`) and
  `DateTime.diff(..., :second)` into `Duration.new(seconds: ...)` (`:1103-1107`).
- `get_value_type/1` (`:1152-1167`) reports `:duration` for any map passing the
  key-presence check.
- Comparison and equality have **no duration clause**. A duration falls into
  the generic map arm of the `types_match/2` guard (`:775-782`, `:817-826`,
  `:860`) and is compared as an Erlang term, so `1d` and `24h` are not equal.
- `add_duration/2`/`subtract_duration/2` (`:1937-1957`) branch on
  `%{milliseconds: ms} when ms > 0` and call `DateTime.add/3` with the result
  of `to_milliseconds/1` or `to_seconds/1` - an unguarded integer-only stdlib
  call.

**[`lib/predicator/visitors/string_visitor.ex:273-276`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/visitors/string_visitor.ex#L273-L276)** renders the AST's unit
list with `"#{value}#{unit}"` interpolation and joins. It sees the AST list,
never the evaluated map.

**[`lib/predicator/visitors/instructions_visitor.ex:328-333`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/visitors/instructions_visitor.ex#L328-L333)** maps
`[{value, unit}]` to `[[value, unit], ...]` and emits one
`["duration", serializable_units]` instruction. This is a plain `Enum.map`,
not `Duration.from_units/1`.

**`lib/predicator/functions/date_functions.ex`** does not consume durations at
all - the only hit is the moduledoc's prose mention at `:6`.

**Conformance modules** (`lib/predicator/conformance/values.ex:39,88-94,178-207`
and `features.ex:52,132-140`) each carry their own copy of the key-presence
`duration_map?/1` check and pass field values through untyped in both
directions. `values.ex`'s `encode_duration/1` `@spec` claims
`%{optional(binary()) => integer()}`.

### Existing tests that pin current behavior

`test/predicator/duration_test.exs` is the primary pinning file. The rejection
block (`:545-588`) is what this bead moves, and one line is exactly on point:

```elixir
test "rejects a float value" do
  assert Duration.parse("1.5d") == :error
end
```

That is [`test/predicator/duration_test.exs:553-555`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/test/predicator/duration_test.exs#L553-L555). The same block pins the
empty string, `-1d`, `1x`, `1dabc`, leading/embedded/trailing whitespace, a
bare `42`, and leading/trailing newlines. **There is no test for a leading-dot
spelling (`.5d`) or a trailing-point spelling (`1.d`)** - `"1.5d"` is the only
decimal case exercised anywhere.

Other pinning sites:

- [`test/predicator/duration_test.exs:525-543`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/test/predicator/duration_test.exs#L525-L543) - the `to_string`/`parse`
  round-trip loop over six constructed durations including
  `Duration.new(milliseconds: 500)`.
- [`test/predicator/duration_test.exs:493-523`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/test/predicator/duration_test.exs#L493-L523) - each of the eight units alone,
  the `mo`/`m`/`ms` disambiguation, and the accumulate-on-repeat cases.
- [`test/predicator/duration_test.exs:62-117`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/test/predicator/duration_test.exs#L62-L117) - `from_units/1`'s three error
  messages, including `"Invalid duration value: invalid"`.
- [`test/predicator/cast_test.exs:260-308`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/test/predicator/cast_test.exs#L260-L308) - the `::duration` surface: identity,
  `"1d2h30m"`, `"abc"`/`"1x"` to `:undefined`, the newline anchoring
  regression, and a round-trip block including the `1mo`/`1ms` pair.
- [`test/predicator/parser_test.exs:1686-1815`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/test/predicator/parser_test.exs#L1686-L1815) - the duration-literal parse
  block, including `"1d8x"` as an error and `0d` and `999y365d24h60m60s`.
- [`test/predicator/parser_spans_test.exs:219-247`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/test/predicator/parser_spans_test.exs#L219-L247) - `assert_span("3d", "3d")`,
  `"3d8h"`, `"3d 8h"`, and the four relative-date forms.
- [`test/predicator/parser_positions_test.exs:190`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/test/predicator/parser_positions_test.exs#L190) -
  `{:ok, {:duration, [{3, "d"}, {8, "h"}], {1, 1}}}`.
- [`test/predicator/evaluator_test.exs:1064-1147`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/test/predicator/evaluator_test.exs#L1064-L1147) - `["duration", [[5, "d"]]]`
  and the two error shapes.
- [`test/predicator/visitors/instructions_visitor_test.exs:636-750`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/test/predicator/visitors/instructions_visitor_test.exs#L636-L750),
  `test/predicator/functions/date_arithmetic_test.exs`,
  `test/predicator/date_arithmetic_string_visitor_test.exs` - compilation,
  end-to-end arithmetic, and round-trip rendering.
- `test/predicator/lexer_test.exs` has **no duration-literal token tests**. Its
  one `duration` hit (`:1118-1127`) asserts the seven cast type names still lex
  as plain identifiers.

**The model for fractional-value tests already exists**, from px-7t8:
[`test/predicator/cast_test.exs:144-176`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/test/predicator/cast_test.exs#L144-L176) pins both shapes of the
fractional-seconds field with the ISA section cited in a comment, and
[`test/predicator/conformance/values_test.exs:114-177`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/test/predicator/conformance/values_test.exs#L114-L177) pairs each case with an
explicit sabotage note and asserts encoding, decode round trip, and the exact
internal `.microsecond` tuple - separate `describe` blocks for the encode side
and the decode side.

### Binding tests and the sabotage machinery

`.claude/wurk.json`'s `gate.sabotage.test_roots` names ten files. **No duration
test is among them**, and `test/predicator/duration_test.exs`,
`lexer_test.exs`, `cast_test.exs`, and `parser_test.exs` are all outside the
list - the scan is blind to anything not named there.

Two entries in the list are nonetheless duration-adjacent:

- `test/predicator/visitor_clause_coverage_test.exs`. Its 2026-08-11 sabotage
  pass ([`docs/research/260808-px-9ab-sabotage-notes.md:273-283`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/research/260808-px-9ab-sabotage-notes.md#L273-L283)) used the
  `:duration` tag as its mutation target - renaming `string_visitor.ex`'s
  `{:duration, ...}` `do_visit/2` clause head to `:durationx` and confirming
  the missing-direction assertion caught it. This is a note *about* the
  coverage test, not a duration binding test.
- `test/predicator/conformance/values_test.exs`, which round-trips duration
  values (`:28-30`, `:70`) among others.

If this bead adds a case to `conformance/cases/durations.json`, the corpus
freshness test (`test/predicator/conformance/corpus_freshness_test.exs`, also
in `test_roots`) is the binding test that notices.

## ISA Impact

**Two halves, and they land on different sides of the line.**

The surface half moves nothing. [`docs/isa.md:326`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/isa.md#L326) specifies the `duration`
opcode's operand as `units (list of [int, string])`, and
[`docs/isa.md:576-577`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/isa.md#L576-L577) makes a pair that is not `[integer, string]` an
`EvaluationError` `"invalid_duration_format"`. If `1.5s` lowers to
`["duration", [[1, "s"], [500, "ms"]]]`, that operand is unchanged, the
opcode's semantics are unchanged, and §1's own rule applies: "A later source
spelling for a value that domain already admits likewise moves no version,
because a spelling is surface syntax (§6) and attaches to no opcode name."
§8 reinforces it - the corpus "does not cover surface syntax... and it does
not cover parse or lexer errors" ([`docs/isa.md:847-852`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/isa.md#L847-L852)). Current version is
**ISA v6** ([`docs/isa.md:66`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/isa.md#L66)); `duration` is a v1 opcode at tier 4
([`lib/predicator/instructions.ex:85`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/instructions.ex#L85)), and `required_isa/1` reads only the
opcode head, never the operand
([`lib/predicator/instructions.ex:292-329`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/instructions.ex#L292-L329)).

The `::duration` half is not surface syntax. [`docs/isa.md:691-692`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/isa.md#L691-L692) specifies
the string parse normatively as "the language's own duration-literal grammar,
a sequence of integer-unit pairs (`\"1d2h30m\"`)", and [`lib/predicator/cast.ex:112-117`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/cast.ex#L112-L117)
implements it by calling the exact function this bead widens. After the
change, `"1.5s"::duration` stops being `:undefined` and starts being a
duration - a change in what the `cast` opcode does, under its own name, to an
input the ISA currently describes. §1 offers two readings and the bead has to
pick one:

- **"Adding an operand form or widening an accepted type is a new version but
  not a new name"** ([`docs/isa.md:33-42`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/isa.md#L33-L42)). Read as a widening of `cast`'s
  accepted string domain, this mints ISA v7.
- **The px-7t8 refinement precedent.** §7 records that "A version's semantics
  can also be refined in a later release without a new opcode and without a
  new ISA version - 3.8.0 did exactly that to v2", and §5's `bracket_access`
  bullet says in so many words that it, "not the ISA version, changed to state
  the above precisely" for a case previously unspecified. px-7t8 took this
  route ([`docs/research/260810-px-7t8-datetime-string-fractional-seconds.md:149-168`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/research/260810-px-7t8-datetime-string-fractional-seconds.md#L149-L168)).
  The disanalogy is that the fractional-seconds field was genuinely
  *unspecified*, whereas `::duration`'s "integer-unit pairs" is written down.

Either way the `duration` opcode itself, its operand shape, its two error
reasons, and `Predicator.Instructions`' tables stay exactly as they are.

**What conformance would owe.** The `durations` feature tag is derived
automatically ([`lib/predicator/conformance/features.ex:52`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/conformance/features.ex#L52) from the opcode,
`:132-140` from a top-level duration-shaped context value), so no manual tag.
A fractional case's tier is 4 by construction. Neither
`conformance/schema/case.json` nor `Values`' codec imposes any integer
constraint on unit values, so nothing there blocks a case. The natural homes
are `conformance/cases/durations.json` (which today holds eight cases, all
integer-valued, `:3-107`) and `conformance/cases/casts.json` for the
`::duration` side (its existing duration cases are at `:90-108`, `:175-193`,
`:212-217`, `:260-265`, `:350-361`). `conformance/corpus/*.json` and
`conformance/manifest.json` are regenerated by `mix corpus.generate` and never
hand-edited, and a corpus diff moves the exported specification, so it gets
explained in the commit message and PR body (ADR-0003).

[`docs/guides/porting.md:64-72`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/guides/porting.md#L64-L72) restates the normative duration shape for
siblings, and the px-bxz plan records that Ruby's duration support is an older
single-unit `DURATION` token compiling to `["lit", seconds]` and TypeScript has
none at all - a sibling behind the current version is an expected state
(ADR-0003), not a blocker.

## Code References

- [`lib/predicator/duration.ex:312-352`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/duration.ex#L312-L352) - `parse/1` and its two regexes
- [`lib/predicator/duration.ex:72-85`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/duration.ex#L72-L85) - `from_units/1`'s `Integer.parse/1` gate
- [`lib/predicator/duration.ex:127-163`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/duration.ex#L127-L163) - `to_seconds/1`, `to_milliseconds/1`,
  and the 30-day/365-day approximations
- [`lib/predicator/duration.ex:278-310`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/duration.ex#L278-L310) - `to_string/1`
- `lib/predicator/duration.ex:189,191,207,239,241,257` - the integer-only
  `div/2`, `Date.add/2`, `DateTime.add/3` calls
- [`lib/predicator/lexer.ex:226-255`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/lexer.ex#L226-L255) - the integer/float fork
- [`lib/predicator/lexer.ex:479-516`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/lexer.ex#L479-L516) - `take_number/1`
- [`lib/predicator/lexer.ex:737-858`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/lexer.ex#L737-L858) - the duration-suffix walker and token
  emission
- [`lib/predicator/lexer.ex:465-467`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/lexer.ex#L465-L467) - the date-literal whole-literal span rule
  (the nearest per-family precedent)
- [`lib/predicator/parser.ex:1362-1383`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/parser.ex#L1362-L1383) - the `:integer` and `:float` primary
  clauses
- [`lib/predicator/parser.ex:1961-2069`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/parser.ex#L1961-L2069) - duration sequence assembly and
  direction handling
- [`lib/predicator/parser.ex:178`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/parser.ex#L178) - the `{:duration, [{integer(), binary()}], position()}` AST shape
- [`lib/predicator/types.ex:27-36`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/types.ex#L27-L36) - the `duration()` type
- [`lib/predicator/cast.ex:112-117`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/cast.ex#L112-L117) - `::duration` calls `Duration.parse/1`
- [`lib/predicator/evaluator.ex:1819-1849`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/evaluator.ex#L1819-L1849) - the `is_integer(value)` guard
- [`lib/predicator/visitors/instructions_visitor.ex:328-333`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/visitors/instructions_visitor.ex#L328-L333) - AST to
  `["duration", units]`
- [`lib/predicator/visitors/string_visitor.ex:273-276`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/visitors/string_visitor.ex#L273-L276) - duration rendering
- [`docs/isa.md:326`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/isa.md#L326) - the opcode table row
- [`docs/isa.md:576-577`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/isa.md#L576-L577) - `invalid_duration_format`
- [`docs/isa.md:691-692`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/isa.md#L691-L692) - `::duration`'s "integer-unit pairs"
- [`docs/isa.md:33-42`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/isa.md#L33-L42) - the widening-vs-spelling versioning rule
- [`docs/reference/language.md:212-225`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/reference/language.md#L212-L225) - the canonicalizer section
- [`docs/architecture.md:46`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/architecture.md#L46) and [`docs/reference/language.md:46`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/reference/language.md#L46) - the
  `duration → NUMBER UNIT+` production
- [`test/predicator/duration_test.exs:553-555`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/test/predicator/duration_test.exs#L553-L555) - `parse("1.5d") == :error`
- [`conformance/cases/durations.json:3-107`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/conformance/cases/durations.json#L3-L107) - the eight existing cases

## Architecture Documentation

The grammar production is `duration → NUMBER UNIT+`, with `NUMBER` and `FLOAT`
listed as *separate* alternatives in `primary` - so the documented grammar has
no `FLOAT UNIT+` alternative today. It appears verbatim in two places,
[`docs/architecture.md:39-47`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/architecture.md#L39-L47) and [`docs/reference/language.md:37-48`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/reference/language.md#L37-L48), and both
would move together.

[`docs/reference/language.md:212-225`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/reference/language.md#L212-L225) is the fullest prose statement of the
current contract: `::duration` accepts `<digits><unit>` pairs "with no
whitespace, no sign, and no partial consumption", does not require canonical
ordering, and accumulates on repeat, so it is "a canonicalizer over any
equivalent spelling, not an inverse of `::string`'s duration formatting".
Normalizing `1.5s` downward to `1s500ms` is the same *kind* of fact this
paragraph already documents, and the bead's `to_string/1` round-tripping
consequence belongs beside it.

Note a real difference between the two parse paths, already present:
`Duration.parse/1` **accumulates** repeated units
([`lib/predicator/duration.ex:344-347`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/duration.ex#L344-L347), pinned at `duration_test.exs:520-521`)
while the `duration` **opcode overwrites** them
([`lib/predicator/evaluator.ex:1828`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/evaluator.ex#L1828), specified at [`docs/isa.md:575`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/isa.md#L575) and pinned
by [`conformance/cases/durations.json:59-77`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/conformance/cases/durations.json#L59-L77)). Any downward normalization that
emits two pairs for one source unit (e.g. `1.5s` -> `1s` + `500ms`) touches
distinct units and so is unaffected by either rule - but a normalization that
could emit two pairs naming the *same* unit would be read differently by the
two paths.

Relevant ADRs: **ADR-0003** (this repo leads the ISA; source of §1's
versioning rules), **ADR-0011** (`::` is a `cast` opcode, failure is
`:undefined`, `duration` is one of the seven cast type names), **ADR-0004**
(errors are values), **ADR-0005** (the area-label algebra - this bead carries
`area:evaluator` and `area:lexer-parser`, and would additionally carry
`area:docs` and `area:conformance` if it moves `docs/isa.md` or the corpus).
**ADR-0010** governs the mirror with st-rsl.

## Historical Context

- `docs/research/260810-px-7t8-datetime-string-fractional-seconds.md` is the
  repo's closest precedent for a fractional-value policy call, and it decided
  three things worth carrying: (1) *fidelity beats cheapness* - the
  seconds-only option was rejected because "Losing information is not the house
  style of this subsection", citing duration's own round-trip guarantee as the
  neighbouring rule; (2) *pin one canonical form rather than a per-value
  negotiation*, because a variable digit count is a cross-language hazard; and
  (3) *an unspecified field can be pinned at the same ISA version*, with §1 and
  §7 cited for why.
- `docs/research/260811-px-qq6-tagged-datetime-precision.md:162,283` was
  written deliberately to *parallel* duration's own zero-omission convention -
  the `milliseconds` key being present only when non-zero.
- `docs/plans/260805-px-bxz-duration-unit-order.md` fixed
  `parse_duration_sequence/3` so units parse in source order; the CHANGELOG
  entry is at [`CHANGELOG.md:1180-1182`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/CHANGELOG.md#L1180-L1182). It is the last structural change to the
  duration parse path.
- [`CHANGELOG.md:1284-1291`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/CHANGELOG.md#L1284-L1291) added the `ms` unit and `to_milliseconds/1`;
  [`CHANGELOG.md:1303-1307`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/CHANGELOG.md#L1303-L1307) is the original duration/relative-date feature.
- [`docs/design/260806-px-35i.4-corpus-format-and-tooling.md:320-321`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/design/260806-px-35i.4-corpus-format-and-tooling.md#L320-L321) records
  that duration's corpus-tag representation was itself an open design point
  when the corpus was stood up.

A useful adjacent precedent for design decision 3 (the leading dot): the cast
matrix already refuses a bare fraction on the *float* side -
[`docs/reference/language.md:185-186`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/reference/language.md#L185-L186) says `"1e3"::float` is `:undefined` "and
no bare fraction (`\".5\"::float` is `:undefined`)". The language therefore
already has a documented position that a leading-dot number is not a valid
string-parse input, on the nearest analogous surface.

## Related Research

- `docs/research/260810-px-7t8-datetime-string-fractional-seconds.md`
- `docs/research/260811-px-qq6-tagged-datetime-precision.md`
- `docs/research/260809-px-2r5.1-cast-conversion-matrix.md`
- `docs/research/260808-px-9ab-sabotage-notes.md`
- `docs/plans/260805-px-bxz-duration-unit-order.md`
- `docs/design/260806-px-35i.4-corpus-format-and-tooling.md`

## Open Questions

These are recorded, not answered - the bead names the first three as design
decisions and no human was available to settle them.

> **Settled.** Every question below is decided in
> [260814-px-5c5-fractional-durations-decisions.md](260814-px-5c5-fractional-durations-decisions.md);
> read that document before planning or implementing. The list is kept as
> written for the record.

1. **Sub-millisecond remainder (`0.5ms`): reject or round?** No precedent
   binds. The nearest one cuts toward *not* silently discarding: px-7t8
   rejected the lossy option on fidelity grounds. But `::datetime` already
   truncates a seventh fractional digit rather than rejecting the string, and
   §5 documents that truncation as normative - so both readings have a
   neighbour.
2. **Fractions on `mo` and `y`.** The 30-day and 365-day approximations are
   already documented and already used by `to_seconds/1`, `to_milliseconds/1`,
   `add_to_date/2`, and `subtract_from_date/2`. Restricting fractions to `w`
   and below is the smaller claim; allowing them re-uses machinery that exists.
   Nothing in the codebase currently distinguishes "exact" from "approximate"
   units programmatically - that distinction lives only in `@doc` prose.
3. **The leading-dot spelling `.5s`.** Three facts bear on it: the lexer's
   digit branch is keyed on `?0..?9` so a leading `.` never enters the number
   scanner at all ([`lib/predicator/lexer.ex:227`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/lib/predicator/lexer.ex#L227)); `"\".5\"::float"` is already
   documented as `:undefined` ([`docs/reference/language.md:185-186`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/docs/reference/language.md#L185-L186)); and no
   test anywhere exercises `.5d`. Accepting it in `parse/1` while the lexer
   rejects it would make the two grammars diverge, which the ISA and
   `language.md` currently describe as one grammar.
4. **Does `::duration` mint ISA v7?** The single ISA question, argued both ways
   under **ISA Impact** above. It has to be settled before the plan, because it
   determines whether `docs/isa.md` §7 gains a row and whether
   `Predicator.isa_version/0` moves.
5. **Where does normalization live - the lexer, the parser, or a shared
   helper?** `Duration.parse/1` and the lexer are today two entirely separate
   implementations of the same grammar (a regex pair versus a hand-rolled
   `cond` walker), and the bead widens both. Nothing in the repo currently
   shares them.
6. **`to_string/1` round-tripping.** The bead already accepts that
   `to_string(parse("1.5s"))` is `"1s500ms"`. Worth noting that the existing
   round-trip assertions
   ([`test/predicator/duration_test.exs:525-543`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/test/predicator/duration_test.exs#L525-L543),
   [`test/predicator/cast_test.exs:286-308`](https://github.com/riddler/predicator-ex/blob/4faf42f5c396bb62805ea28281dc7297f1098f54/test/predicator/cast_test.exs#L286-L308)) start from constructed duration
   *maps*, not from source strings, so downward normalization leaves them
   green - the property they assert is `parse(to_string(d)) == {:ok, d}`, not
   `to_string(parse(s)) == s`, and the latter was never true anyway
   (`"30m3d"` is the standing counter-example in `language.md:218`).
7. **Should a duration test become a binding test?** No duration test is in
   `gate.sabotage.test_roots` today. If this bead pins the normalization in the
   corpus, the freshness test already covers it; if it pins it only in unit
   tests, the scan stays blind to those files by design.
