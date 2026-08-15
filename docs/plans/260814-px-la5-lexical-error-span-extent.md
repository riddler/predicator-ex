# Lexical error span extent Implementation Plan

## Overview

Beads issue: `px-la5` ("Widens lexical error spans to the literal extent").

px-dmt gave every lexical error a span and, by its open question 3, made every
one of them one character wide. That is the right answer for two of the three
error families the lexer emits and the wrong answer for the third: a malformed
or unterminated date/datetime literal is a whole-literal failure reported with
a caret on its opening `#`.

This plan widens exactly that family. `take_date/5`'s two error returns grow to
carry the end position they already know, the `?#` call site builds the span
from the opening `#` to that end, and the Lexer moduledoc states the per-family
rule so the remaining one-character spans read as deliberate rather than as
leftovers.

**This work does not move the ISA.** No opcode is added, removed, or altered;
no instruction encoding changes; `conformance/` is untouched and
`mix corpus.generate` produces no diff. Per this project's `/wurk:plan`
extension, the `## ISA Impact` section is therefore omitted.

## Current State Analysis

**The lexer's error term already carries a span.** `@type result`
(`lib/predicator/lexer.ex:107-109`) is
`{:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}`,
and `tokenize/1`'s `@doc` (`lib/predicator/lexer.ex:132-133`) documents that the
span's start always equals `{line, column}`. `Predicator.Types.span/0`
(`lib/predicator/types.ex:129-140`) is `{start_position, end_exclusive_position}`,
LSP-style: on one line, `end_column - start_column` is the length.

**All six lexical error sites emit a one-character span today.**

| Site | Error | Family |
|---|---|---|
| `lexer.ex:353` | `Unexpected character '&'` | single character |
| `lexer.ex:363` | `Unexpected character '\|'` | single character |
| `lexer.ex:451` | `Unexpected character '<c>'` (catch-all) | single character |
| `lexer.ex:421-422` | unterminated double-quoted string | opening quote |
| `lexer.ex:433-434` | unterminated single-quoted string | opening quote |
| `lexer.ex:445-446` | any `take_date/5` failure | **whole literal** |

Each builds `{{line, col}, {line, col + 1}}` literally.

**`lexer.ex:445-446` is one call site for three distinct messages.** The `?#` branch
(`lib/predicator/lexer.ex:438-447`) calls `take_date(rest, "", 1, line, col + 1)`
and pattern-matches `{:error, message}`. Three messages reach it:

- `"Unterminated date literal"` - `take_date([], _acc, _count, _line, _col)`
  (`lib/predicator/lexer.ex:670`), i.e. input ran out before a closing `#`.
- `"Invalid date format: <content>"` and `"Invalid datetime format: <content>"` -
  `parse_date_content/1` (`lib/predicator/lexer.ex:690-705`), reached from
  `take_date([?# | rest], acc, count, line, col)`
  (`lib/predicator/lexer.ex:672-680`) once the closing `#` has been seen.

**The end position is in scope at both error points and is discarded.**
`take_date/5` threads `line` and `col` exactly the way `take_string/6` does, and
`take_date([?\n | rest], ...)` (`lib/predicator/lexer.ex:682-684`) increments the line
and resets the column, so a multi-line date literal tracks correctly. At the
unterminated clause the running `{line, col}` *is* the exclusive end of the
consumed text; at the `parse_date_content` failure the closing `#` sits at
`{line, col}`, so `{line, col + 1}` is the exclusive end. Both are already bound
and both are currently discarded as `_line`/`_col` or dropped on the
`{:error, message}` return.

**`take_string/6` has the same shape and deliberately keeps its narrow span.**
Its `@spec` (`lib/predicator/lexer.ex:618-627`) returns `{:error, binary()}` from
one clause (`lib/predicator/lexer.ex:628-631`). An unterminated string runs to
end of source by definition, so widening it would underline the rest of the
program; the caret on the opening quote is the better diagnostic. px-la5's
description says so explicitly.

**Test coverage of these messages is thin and mostly span-agnostic**, which is
what px-dmt intended:

- `test/predicator/lexer_test.exs:874` - `"score > #"`, span bound as `_span`
- `test/predicator/lexer_test.exs:946, 951, 956, 957` - invalid date, invalid
  datetime, `"#2024-01-15"`, `"score > #"`; all `_span`
- `test/predicator/lexer_test.exs:891` - the one asserted literal span,
  `{{1, 1}, {1, 2}}`, on an unterminated double-quoted string (unchanged by
  this work)
- `test/predicator/lexer_edge_cases_test.exs:7-27` - unterminated date, invalid
  date, invalid datetime; all `_span`

No test in the tree asserts a date-literal span value, so nothing needs
rewriting to make room; the phases below add assertions rather than change them.

**Nothing downstream needs to change.** The parser passes lexer errors through
unchanged (`lib/predicator/parser.ex:251`, `317`), `%ParseError{}` is built one
layer up in `lib/predicator.ex`, and none of them inspect a span's width.

## Desired End State

`Predicator.Lexer.tokenize/1` reports a date/datetime literal failure with a
span covering the whole literal, from its opening `#` through the closing `#`
(or through end of input when there is none), while the unexpected-character
sites and the unterminated-string opening-quote span stay one character wide.
The rule is stated in the Lexer moduledoc, and `take_date/5`'s `@spec` reflects
its widened error return.

Verifiable end state:

```elixir
Predicator.Lexer.tokenize("#invalid-date#")
#=> {:error, "Invalid date format: invalid-date", 1, 1, {{1, 1}, {1, 15}}}

Predicator.Lexer.tokenize("#2024-01-15")
#=> {:error, "Unterminated date literal", 1, 1, {{1, 1}, {1, 12}}}

Predicator.Lexer.tokenize("score > #")
#=> {:error, "Unterminated date literal", 1, 9, {{1, 9}, {1, 10}}}

Predicator.Lexer.tokenize("\"oops")
#=> {:error, "Unterminated double-quoted string literal", 1, 1, {{1, 1}, {1, 2}}}

Predicator.Lexer.tokenize("@")
#=> {:error, "Unexpected character '@'", 1, 1, {{1, 1}, {1, 2}}}
```

### Key Discoveries:

- The date end position is already computed and thrown away -
  `lib/predicator/lexer.ex:670` binds it as `_line`/`_col`, and
  `lib/predicator/lexer.ex:672` has the closing `#` position in scope
  (`file:line` refs above). No new traversal or lookahead is needed.
- `take_date/5` already tracks newlines (`lib/predicator/lexer.ex:682-684`), so a
  date literal broken across lines gets a correct multi-line span for free.
  This is the same fix px-8he made for string tokens, arriving here by
  construction.
- Span end is **exclusive** (`lib/predicator/types.ex:129-133`). The closing `#`
  is at `{line, col}`, so the end is `{line, col + 1}`; the unterminated case's
  running `{line, col}` is *already* exclusive and must not be incremented.
  Getting these two off by one is the one real hazard in this change.
- ADR-0015 bounds the design: this arm of the work does not get a lexer
  redesign. Widening one private helper's error return is inside that bound;
  restructuring the `take_*` family into a shared result struct is not.
- ADR-0003 governs ISA movement, and this change makes none.
- The one existing literal-span assertion,
  `test/predicator/lexer_test.exs:891`, covers the string family and acts as the
  regression guard that this change did not widen the wrong family.

## What We're NOT Doing

- **Not widening the unterminated-string span.** The caret stays on the opening
  quote. px-la5 asks for this by name; an unterminated string extends to end of
  source, and underlining the remainder of the program is worse than pointing at
  where the literal began.
- **Not widening `take_string/6`'s error return.** px-la5's "what to do" bullet
  names `lexer.ex:421-422` and `:433-434` alongside `:445-446`, but its per-family rule keeps
  the string span at one character, so an extent threaded to those two call sites
  would be bound and immediately discarded. Threading data no caller uses is
  dead weight in a `credo --strict` tree; the moduledoc rule added in Phase 2 is
  what records the decision instead. Recorded in Open Questions as OQ1.
- **Not widening the unexpected-character spans.** One character is exactly
  right: the offending character is one character.
- **Not touching the parser, compiler, evaluator, visitors, or
  `lib/predicator.ex`.** Lexer errors pass through unchanged and no consumer
  inspects a span's width.
- **Not moving the ISA.** No opcode, no instruction, no `docs/isa.md` edit, no
  `conformance/` change, no `mix corpus.generate` run.
- **Not adding a caret-rendering or diagnostic-formatting helper.** Rendering a
  span as an underline is a separate concern and no bead asks for it here.
- **Not reconciling `Invalid date format` / `Invalid datetime format` message
  text.** Only the span changes; the strings are asserted by existing tests and
  stay byte-identical.

## Implementation Approach

Two phases, split along the seam between behavior and documentation so each is
independently committable and independently gate-verifiable.

Phase 1 is the whole behavioral change and its tests: widen `take_date/5`'s two
error returns from `{:error, binary()}` to `{:error, binary(), pos_integer(),
pos_integer()}`, update the `@spec`, and build the span at the single `?#` call
site. `take_date/5` is private and has exactly one caller, so producer and
consumer must move together - splitting them would leave an intermediate commit
with a red gate, which is the sizing rule the phase structure has to respect.

Phase 2 is documentation only: the per-family rule in the Lexer moduledoc plus a
`## [Unreleased]` CHANGELOG entry. It touches no Elixir behavior, so it can land
separately without either phase depending on the other's tests.

Phase 1 alone satisfies every functional acceptance criterion; Phase 2 alone
satisfies the "state the rule" criterion. Neither is a prerequisite for the
other compiling, but Phase 2's text describes Phase 1's behavior, so the order
below is the sensible one.

## Phase 1: Widen `take_date/5`'s error return to the literal's extent

### Overview

Carry the end position out of `take_date/5` and build the whole-literal span at
the `?#` branch. Behavior changes for three messages and nothing else.

### Changes Required:

#### 1. `take_date/5` error returns

**File**: `lib/predicator/lexer.ex` (around lines 666-680)
**Changes**: Widen the `@spec`'s error arm and both error-producing clauses to
carry the exclusive end position. Note that the unterminated clause's bound
`line`/`col` are already exclusive and the `parse_date_content` failure needs
`col + 1` to move past the closing `#`.

```elixir
  @spec take_date(charlist(), binary(), pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, Date.t() | DateTime.t(), charlist(), pos_integer(), :date | :datetime,
           pos_integer(), pos_integer()}
          | {:error, binary(), pos_integer(), pos_integer()}

  # Input ran out before a closing `#`. The running position is already the
  # exclusive end of everything consumed, so it is the span's end as-is.
  defp take_date([], _acc, _count, line, col),
    do: {:error, "Unterminated date literal", line, col}

  defp take_date([?# | rest], acc, count, line, col) do
    case parse_date_content(acc) do
      {:ok, date_value, token_type} ->
        {:ok, date_value, rest, count, token_type, line, col + 1}

      # `line, col` is the closing `#`; the exclusive end is one past it.
      {:error, message} ->
        {:error, message, line, col + 1}
    end
  end
```

`parse_date_content/1` keeps its `{:error, binary()}` shape - it sees only the
literal's content and has no position to offer.

#### 2. The `?#` call site

**File**: `lib/predicator/lexer.ex` (around lines 438-447)
**Changes**: Match the widened error and build the span from the opening `#`.

```elixir
      # Date literals
      ?# ->
        case take_date(rest, "", 1, line, col + 1) do
          {:ok, date_value, remaining, consumed, token_type, end_line, end_col} ->
            # +1 for opening #
            token = {token_type, line, col, consumed + 1, date_value}
            tokenize_chars(remaining, end_line, end_col, [token | tokens])

          # A malformed literal is wrong as a whole, so the span covers the
          # whole literal - opening `#` through the closing `#`, or through
          # end of input when there is none.
          {:error, message, end_line, end_col} ->
            {:error, message, line, col, {{line, col}, {end_line, end_col}}}
        end
```

#### 3. Span assertions for the date family

**File**: `test/predicator/lexer_test.exs`
**Changes**: Tighten the four existing date-error tests in place - keep their
names and inputs, replace only the `_span` wildcard with the concrete value -
then add the one case nothing covers today, a date literal broken across lines.

The four to tighten, all currently binding `_span`:

- `test/predicator/lexer_test.exs:873-875` - `"returns error with correct
  position"`, `Lexer.tokenize("score > #")` -> `{{1, 9}, {1, 10}}`
- `test/predicator/lexer_test.exs:945-948` - `"returns error for invalid date
  format"`, `Lexer.tokenize("#not-a-date#")` -> `{{1, 1}, {1, 13}}`
- `test/predicator/lexer_test.exs:950-953` - `"returns error for invalid
  datetime format"`, `Lexer.tokenize("#2024-01-15T25:00:00Z#")` ->
  `{{1, 1}, {1, 23}}`
- `test/predicator/lexer_test.exs:955-958` - `"returns error for unterminated
  date literal"`, two asserts: `Lexer.tokenize("#2024-01-15")` ->
  `{{1, 1}, {1, 12}}`, and `Lexer.tokenize("score > #")` -> `{{1, 9}, {1, 10}}`

So, for example:

```elixir
    test "returns error for invalid date format" do
      assert {:error, "Invalid date format: not-a-date", 1, 1, {{1, 1}, {1, 13}}} =
               Lexer.tokenize("#not-a-date#")
    end
```

And the new case, which belongs in the existing
`describe "raw newlines inside literals"` block (`test/predicator/lexer_test.exs`,
just after the date-error describe) rather than with the others, because that is
where px-8he's multi-line literal tests live:

```elixir
    test "a date literal broken across lines gets a multi-line error span" do
      assert {:error, "Invalid date format: " <> _content, 1, 1, {{1, 1}, {2, 7}}} =
               Lexer.tokenize("#2024-\n01-01#")
    end
```

The corresponding `_span` bindings in `test/predicator/lexer_edge_cases_test.exs:7-27`
stay as wildcards; that file asserts message/line/column and duplicating the span
values there would give two places to update for one behavior.

Column arithmetic to confirm while implementing rather than to trust from this
document: for `"#not-a-date#"` the closing `#` is at column 12, so the exclusive
end is 13; for `"#2024-01-15"` the input is 11 characters, so the exclusive end
is 12. Compute each expected value against the source string, and treat a
mismatch as a bug in this plan's arithmetic, not a reason to loosen the
assertion to `_span`.

#### 4. Keep the non-date families pinned

**File**: `test/predicator/lexer_test.exs`, `test/predicator/lexer_edge_cases_test.exs`
**Changes**: px-dmt already left two literal-span assertions in place, in the
same `describe` block, and they are the regression guard for "did not widen the
wrong family" - **leave both exactly as they are**:

- `test/predicator/lexer_test.exs:886-888` - `"an 'unexpected character' failure
  spans exactly one character"`, asserting `{{1, 1}, {1, 2}}` for `"@"`
- `test/predicator/lexer_test.exs:890-893` - `"an unterminated string's span
  lands the caret on the opening quote"`, asserting `{{1, 1}, {1, 2}}` for
  `~s("unterminated)`

The single-quoted string is the only member of the narrow families not pinned by
value. Add it beside them, in the same block:

```elixir
    test "an unterminated single-quoted string also keeps a one-character span" do
      assert {:error, "Unterminated single-quoted string literal", 1, 1, {{1, 1}, {1, 2}}} =
               Lexer.tokenize(~s('unterminated))
    end
```

Do not add a second one-character assertion for `"@"` or for the double-quoted
string; those would duplicate tests that already exist.

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality` (format, compile, `credo --strict`,
      dialyzer, deps audit, suite with coverage)
- [x] Dialyzer is clean - it is the check that catches a `take_date/5` clause or
      call site left at the old arity, so a green dialyzer is the real evidence
      the widening is complete
- [x] `lib/predicator/lexer.ex` coverage stays above the 90% minimum in
      `coveralls.json`
- [x] `mix test test/predicator/lexer_test.exs test/predicator/lexer_edge_cases_test.exs`
      passes, including the new span assertions
- [x] `git diff --stat` touches only `lib/predicator/lexer.ex` and the two lexer
      test files - no `conformance/`, no `docs/isa.md`
- [x] `mix corpus.generate` leaves `conformance/` clean (`git status --porcelain
      conformance/` is empty), confirming the exported specification did not move

#### Manual Verification:
- [ ] In `iex -S mix`, each `Predicator.Lexer.tokenize/1` example in "Desired End
      State" returns exactly the span shown
- [ ] The multi-line case `"#2024-\n01-01#"` reports an end on line 2, not line 1
- [ ] `Predicator.compile("#not-a-date#")` surfaces the widened span through
      `%Predicator.Errors.ParseError{}` unchanged in every other respect
- [ ] No regression in string or unexpected-character diagnostics: `"\"oops"`,
      `"'oops"`, `"@"`, `"a & b"`, and `"a | b"` all still report one character

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run full `mix quality` as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the next
phase. In looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

## Phase 2: Record the per-family span rule

### Overview

State in the Lexer moduledoc why three error families get three different span
widths, so the surviving one-character spans read as a decision rather than as
work someone forgot to finish. Documentation only; no behavior changes.

The moduledoc addition deliberately contains no `iex>` prompt, so it adds no
doctest and the suite's test count is unchanged - which is why the criteria
below carry no doctest-specific item beyond the gate itself.

### Changes Required:

#### 1. Lexer moduledoc

**File**: `lib/predicator/lexer.ex` (the `@moduledoc`, lines 5-22)
**Changes**: Add a section after the existing bullet list and before `##
Example`.

```elixir
  ## Error spans

  A lexical error returns `{:error, message, line, column, span}`, where
  `span`'s start always equals `{line, column}` and its end is exclusive. How
  wide the span is depends on the failure, and the three widths are deliberate:

  - **An unexpected character** spans one character. The offending character
    *is* one character, so there is nothing wider to underline.
  - **An unterminated string literal** spans the opening quote alone. The
    literal runs to end of source by definition, so underlining its true
    extent would underline the rest of the program; pointing at where the
    literal began is the better diagnostic.
  - **A malformed or unterminated date/datetime literal** spans the whole
    literal - the opening `#` through the closing `#`, or through end of input
    when there is none. Here the literal is wrong as a unit, and a caret on
    the opening `#` under-describes the failure.

  A date literal containing a raw newline gets a span whose end is on a later
  line, the same way a multi-line string token's `end_position` does.
```

#### 2. Changelog

**File**: `CHANGELOG.md`
**Changes**: Add an entry under the existing `## [Unreleased]` heading. It is a
diagnostic-quality change to an already-public return value, so it belongs in
`### Changed`, which `## [Unreleased]` already has (alongside `### Added` and
`### Fixed`) - append to it rather than creating a second one.

```markdown
### Changed

- **A malformed or unterminated date or datetime literal now reports a span
  covering the whole literal.** `Predicator.Lexer.tokenize/1` previously
  returned a one-character span at the literal's opening `#` for
  `Invalid date format:`, `Invalid datetime format:`, and
  `Unterminated date literal`; the span now runs from the opening `#` through
  the closing `#`, or through end of input when the literal is unterminated.
  The message text, line, and column are unchanged, as are the spans for
  unexpected characters and for unterminated string literals - those stay one
  character wide, and the Lexer moduledoc now records why.
```

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality`
- [x] `git diff --stat` shows only `lib/predicator/lexer.ex` (moduledoc) and
      `CHANGELOG.md`

#### Manual Verification:
- [ ] `mix docs` (or reading the moduledoc) renders the "Error spans" section
      correctly and its three bullets match Phase 1's actual behavior
- [ ] A reader who did not write this change can tell from the moduledoc alone
      that the one-character string span is intentional

**Implementation Note**: This phase touches no Elixir behavior, so the loop gate
is enough while drafting; run full `mix quality` before committing. In
interactive execution, pause here for confirmation. In looped execution, the
Automated Verification items gate advancement and the Manual items are deferred
to the end.

---

## Testing Strategy

### Unit Tests:

- `test/predicator/lexer_test.exs` - the date-family span values, by literal
  assertion rather than `_span`: invalid date, invalid datetime, unterminated at
  end of input, unterminated `#` at the end of a longer expression, and a date
  literal broken across lines.
- `test/predicator/lexer_test.exs` - the non-date families pinned at one
  character: the existing unterminated-double-quoted-string assertion at line
  891 (unchanged), plus new single-quoted-string and unexpected-character
  assertions. These are the tests that fail if the widening leaks.
- `test/predicator/lexer_edge_cases_test.exs:7-27` - existing message/line/column
  assertions stay as they are; they cover the parts this change must not move.
- Edge cases that actually bite here: the off-by-one between the two error
  clauses (one end is already exclusive, the other needs `+1`); a literal that
  is just `#` at end of input, where the correct widened span is still one
  character; and the multi-line literal, where the end line must advance.

### Integration Tests:

No new file under `test/predicator/integration/` is warranted - this change
alters a diagnostic's extent, not evaluation behavior, and every affected code
path is reached directly through `Predicator.Lexer.tokenize/1`. The pass-through
to `%Predicator.Errors.ParseError{}` is covered by the manual step in Phase 1
rather than by a new integration case, because no existing integration test
asserts a lexer span and adding one would duplicate the unit coverage.

### Manual Testing Steps:

1. `iex -S mix`, then `Predicator.Lexer.tokenize("#not-a-date#")` - expect
   `{{1, 1}, {1, 13}}`.
2. `Predicator.Lexer.tokenize("#2024-01-15")` - expect `{{1, 1}, {1, 12}}`,
   i.e. the end sits one past the last character of input.
3. `Predicator.Lexer.tokenize("score > #")` - expect `{{1, 9}, {1, 10}}`; a
   bare `#` is genuinely one character wide and must not be widened past it.
4. `Predicator.Lexer.tokenize("#2024-\n01-01#")` - expect an end on line 2.
5. `Predicator.Lexer.tokenize("\"oops")`, `"'oops"`, `"@"`, `"a & b"`,
   `"a | b"` - each still one character wide.
6. `Predicator.compile("#not-a-date#")` - the `%ParseError{}` carries the
   widened span and is otherwise unchanged.

## Open Questions

Every question below was resolved during planning; each is recorded with the
answer taken and the reasoning, so a reviewer can overturn one without
re-deriving it. **No question is left open for the implementer.**

- **OQ1: should `take_string/6`'s error return be widened too?** px-la5's "what
  to do" bullet names `lexer.ex:421-422` and `:433-434` (the string call
  sites) next to `:445-446` (the date one), but the same bullet's per-family rule says the
  unterminated-string span stays on the opening quote. **Decision: do not widen
  `take_string/6`.** Threading an extent to two call sites that immediately
  discard it adds an unused return element to a private helper in a
  `credo --strict` tree and buys nothing; the acceptance criteria only require
  the date family to move. The intent behind the bullet - that the inconsistency
  be legible - is served by the moduledoc rule in Phase 2. If a later bead does
  widen the string span, `take_string/6` is widened then, by that bead.
- **OQ2: is the span's end for an unterminated date literal `{line, col}` or
  `{line, col + 1}`?** **Decision: `{line, col}`.** The running position in
  `take_date([], ...)` is already one past the last consumed character, and span
  ends are exclusive (`lib/predicator/types.ex:129-133`). Incrementing it would
  underline a character that does not exist. The `parse_date_content` failure is
  the opposite case: its `{line, col}` is the closing `#` itself, so it does need
  `+ 1`. Phase 1's test values (`{{1, 1}, {1, 12}}` for an 11-character input)
  are what make the difference observable.
- **OQ3: should `parse_date_content/1` also carry a position, so the span could
  point at the offending part of the content rather than at the whole literal?**
  **Decision: no.** px-la5 asks for the literal's extent, sub-literal precision
  would mean parsing ISO-8601 ourselves instead of delegating to
  `Date.from_iso8601/1` and `DateTime.from_iso8601/1`, and ADR-0015 says this
  work does not get a lexer redesign.
- **OQ4: does this need a CHANGELOG entry at all, given the message, line, and
  column are unchanged?** **Decision: yes, under `### Changed`.** The span is
  part of a documented public return value (`lib/predicator/lexer.ex:132-133`), a
  consumer rendering a caret sees different output, and the project convention is
  that user-facing changes get an `## [Unreleased]` entry. Promoting that section
  to a version header remains release work and is out of scope.
- **OQ5: does anything in `conformance/` or `docs/isa.md` move?** **Decision:
  no, and Phase 1 verifies it rather than asserting it.** The corpus records
  instruction-level behavior and this change produces no instructions; the
  `mix corpus.generate`-leaves-`conformance/`-clean criterion is there so the
  claim is checked by a command rather than believed.

## References

- Bead: `px-la5` ("Widens lexical error spans to the literal extent")
- Depends on: `px-dmt` (parse-error spans), `px-8he` (newlines inside string
  literals) - both closed
- Source plan for the predecessor: `docs/plans/260814-px-dmt-parse-error-spans.md`
- Related plan: `docs/plans/260814-px-8he-multiline-string-newlines.md`
- Related ADRs: `docs/adr/0015-compile-errors-are-structured-values.md` (bounds
  the design: no lexer redesign), `docs/adr/0003-the-elixir-implementation-leads-the-isa.md`
  (ISA movement rules, not triggered here)
- Primary implementation site: `lib/predicator/lexer.ex:438-447` (the `?#`
  branch), `lib/predicator/lexer.ex:666-687` (`take_date/5`)
- Span type: `lib/predicator/types.ex:129-140`
- Similar prior change: `lib/predicator/lexer.ex:682-684` and the string token's
  `end_position` (`lib/predicator/lexer.ex:44-50`), from px-8he

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] In `iex -S mix`, each `Predicator.Lexer.tokenize/1` example in "Desired End
      State" returns exactly the span shown
- [ ] The multi-line case `"#2024-\n01-01#"` reports an end on line 2, not line 1
- [ ] `Predicator.compile("#not-a-date#")` surfaces the widened span through
      `%Predicator.Errors.ParseError{}` unchanged in every other respect
- [ ] No regression in string or unexpected-character diagnostics: `"\"oops"`,
      `"'oops"`, `"@"`, `"a & b"`, and `"a | b"` all still report one character

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run full `mix quality` as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the next
phase. In looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

### Phase 2

- [ ] `mix docs` (or reading the moduledoc) renders the "Error spans" section
      correctly and its three bullets match Phase 1's actual behavior
- [ ] A reader who did not write this change can tell from the moduledoc alone
      that the one-character string span is intentional

**Implementation Note**: This phase touches no Elixir behavior, so the loop gate
is enough while drafting; run full `mix quality` before committing. In
interactive execution, pause here for confirmation. In looped execution, the
Automated Verification items gate advancement and the Manual items are deferred
to the end.

---
