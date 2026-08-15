# Counts newlines inside string literals Implementation Plan

## Overview

Beads issue: `px-8he`

Make the lexer advance its line counter and reset its column for a raw newline
consumed inside a string or date literal, and give the string token an explicit
end position so `token_end/1` stops computing `{line, col + len}` for a token
that spans lines. Type bug, `area:lexer-parser`.

Follows px-dmt (`docs/plans/260814-px-dmt-parse-error-spans.md`), which gave
lexer and parser errors a span and promised the end-of-input failure "the true
end of the source" - a guarantee that today holds only for sources with no
multi-line string literal. Found while verifying px-dmt's deferred manual
verification item. Pre-existing, not caused by px-dmt: reproduced identically
at c970a21.

## Current State Analysis

`Predicator.Lexer.tokenize/1` (lib/predicator/lexer.ex:166) converts the source
to a charlist and walks it with `tokenize_chars/4`
(lib/predicator/lexer.ex:173), threading `line` and `col` as plain arguments.
The top-level scanner handles a newline correctly - `?\n -> tokenize_chars(rest,
line + 1, 1, tokens)` at lib/predicator/lexer.ex:192-193 - but the two literal
scanners do not:

- `take_string/4` (lib/predicator/lexer.ex:610-642) tracks only a flat
  character `count`. A raw `?\n` inside the literal falls through the catch-all
  clause at lib/predicator/lexer.ex:640 and is counted as an ordinary
  character. The caller at lib/predicator/lexer.ex:407-411 then does
  `tokenize_chars(remaining, line, col + consumed + 1, ...)` - `line` passed
  through unchanged, `col` advanced by the whole literal's character count.
- `take_date/3` (lib/predicator/lexer.ex:644-661) has the identical shape and
  the identical caller treatment at lib/predicator/lexer.ex:431-435.

Confirmed by running the source in this worktree:

```
Predicator.Lexer.tokenize("\"ab\ncd\" > 5")
{:ok, [
  {:string, 1, 1, 7, "ab\ncd", :double},
  {:gt, 1, 9, 1, ">"},        # is at {2, 5}
  {:integer, 1, 11, 1, 5},    # is at {2, 7}
  {:eof, 1, 12, 0, nil}       # is at {2, 8}
]}
```

Note: the bead's REPRODUCE block annotates these as `{2, 6}`, `{2, 8}` and
`{2, 9}`. Those annotations are off by one. The bead's own control case -
`tokenize("x\n> 5")` puts `>` at `{2, 1}` - establishes that the first
character after a newline is column 1, so on line 2 (`cd" > 5`) the `>` is at
column 5. The bead's span claim for the literal, "it really ends at `{2, 4}`",
is correct. This plan uses the computed values throughout.

On the parser side, `token_end/1` (lib/predicator/parser.ex:1532-1534) has two
clauses, one per token arity, and both return `{line, col + len}`:

```elixir
defp token_end({_type, line, col, len, _value}), do: {line, col + len}
defp token_end({_type, line, col, len, _value, _quote_type}), do: {line, col + len}
```

That is only correct for a token containing no newline. `token_end/1` feeds
`token_span/1` (lib/predicator/parser.ex:1555), which feeds `leaf_loc/2`,
`delimited_loc/3`, `duration_loc/2`, `end_of_input_error/2`
(lib/predicator/parser.ex:1571-1582) and every token-bearing `{:error, ...}`
construction, so a wrong end position reaches AST spans, `compile_with_spans/1`
output, and `ParseError` spans alike.

The parser is given only a token list - `@spec parse([Lexer.token()],
keyword())` at lib/predicator/parser.ex:366 - never the source text, so the end
position cannot be reconstructed at parse time. It has to come from the lexer.

### Key Discoveries:

- **A raw newline in the source is not the same as a `\n` escape.**
  `take_string/4`'s escape clause (lib/predicator/lexer.ex:625-638) decodes
  `\n` into a real newline in the token's *value* while consuming two *source*
  characters. `tokenize(~S|"a\nb" > 5|)` correctly leaves every token on line 1.
  Any fix must count source newlines, never newlines in the value - a
  `String.contains?(value, "\n")` test would be wrong. Existing tests at
  test/predicator/lexer_test.exs:414 and :480 already pin the escape case.
- **The string token is the only token that can span lines.** Number and
  identifier scanners exclude `\n` by character class
  (lib/predicator/lexer.ex:448-500). A date literal containing a raw newline
  always fails `parse_date_content/1` (lib/predicator/lexer.ex:663-679):
  `tokenize("#2024-01-\n01# > 5")` returns `{:error, "Invalid date format:
  2024-01-\n01", 1, 1, {{1,1},{1,2}}}`, so a multi-line date token can never be
  constructed. That invariant is what lets the 5-tuple `token_end/1` clause
  keep `{line, col + len}`, and this plan pins it with a test rather than
  leaving it implicit.
- **`{:string, line, col, len, value, quote_type}` is the sole 6-element token**
  (lib/predicator/lexer.ex:44); all 47 other variants are 5-tuples. In
  `parser.ex` it is destructured at exactly five sites:
  lib/predicator/parser.ex:1393, :1528, :1534, :1823, :1849. Nothing outside
  `lexer.ex` and `parser.ex` in `lib/` pattern-matches a raw token tuple -
  `predicator.ex`, `context_location.ex` and the visitors only see the
  `{:error, message, line, col, span}` result tuple.
- **`Predicator.SpanSlicing.slice/2` already exists**
  (test/test_helper.exs:1-25), splits on `"\n"` and sums line lengths, so it is
  already multi-line correct. The span-slicing assertions this bead asks for
  need no new helper.
- **Test blast radius of widening the string token is 24 literals** in three
  files - test/predicator/lexer_test.exs (17),
  test/predicator/lexer_edge_cases_test.exs (4) and
  test/predicator/parser_test.exs (3) - plus one doctest at
  lib/predicator/lexer.ex:149 and one destructuring test at
  test/predicator/parser_test.exs:2067-2078. Widening every token variant
  instead would touch roughly 630 token-tuple literals across five files, which
  is what makes the narrow choice the proportionate one.
- ADR-0009 (the compiled envelope carries the position table) and ADR-0015
  (compile errors are structured values) bound this work; neither is
  contradicted - the shapes are unchanged, only the values in them get correct.
  ADR-0003 governs ISA moves; this change makes none.

## Desired End State

`Predicator.Lexer.tokenize/1` reports the line and column a token actually
occupies, for every token, including tokens that follow a multi-line string
literal, and `Predicator.Parser` derives an AST span whose end is the literal's
true end. Verified by:

- `tokenize("\"ab\ncd\" > 5")` returns `{:gt, 2, 5, 1, ">"}`, `{:integer, 2, 7,
  1, 5}` and `{:eof, 2, 8, 0, nil}`, with the string token still starting at
  `{1, 1}` with `len` 7.
- The `:string_literal` node's span is `{{1, 1}, {2, 4}}`, and
  `Predicator.SpanSlicing.slice(source, span) == "\"ab\ncd\""` - the assertion
  slices the span back out of the source rather than hardcoding coordinates.
- `Predicator.parse("\"ab\ncd\" > ")` reports its end-of-input failure at the
  true end of the source rather than `{1, 11}`.
- Every source containing no raw newline inside a literal produces
  byte-identical tokens, spans and error tuples to today. This is the
  regression bar for the whole change.

## What We're NOT Doing

- **Not widening all 48 token variants to carry an end position.** It would
  touch every construction site in `tokenize_chars/4`, all 47 `@type token`
  variants and roughly 630 token-tuple literals across five test files, for a
  property only the string token can ever exercise. The narrow change is the
  proportionate one, and px-4nz
  (`docs/plans/260808-px-4nz-ast-point-position.md`) is the precedent for a
  surgical position fix. The cost of the narrow choice is that the invariant
  "no 5-tuple token contains a raw newline" becomes load-bearing; Phase 1 pins
  it with a test so it cannot silently break.
- **Not giving the date/datetime token an end position.** A 6-element date
  token would reintroduce arity ambiguity in `token_end/1`, and no multi-line
  date token can be constructed today. `take_date/3` still gets correct
  line/column threading so the *scanner* is right; only the token shape stays
  5-element.
- **Not moving the lexer's unterminated-literal error off the opening
  delimiter.** `take_string/4` and `take_date/3` return a bare `{:error,
  message}` with no position, and the caller anchors the span at the opening
  quote or `#` (lib/predicator/lexer.ex:413-414, :425-426, :437-438). Blaming
  the actual point of failure is a separate improvement and a separate bead.
- **Not unifying the two scanners' `\r` handling.** See Open Questions.
- **No ISA move.** No opcode is added, removed, renamed or altered, so per
  `.claude/wurk/plan.md` this plan carries no `## ISA Impact` section.
  `conformance/` must come back clean from `mix corpus.generate`, and each
  phase asserts that.
- **Not writing a `docs/design/` note.** px-l5s
  (`docs/design/260806-px-l5s-parenthesized-span-extent.md`) recorded a
  judgment call about what a span *should* cover. This bead is a defect: the
  span semantics are unchanged, the producer was wrong. The plan document is
  the record.

## Implementation Approach

Two independent defects share one bead, and they separate cleanly along the
lexer/parser seam that `.claude/wurk/plan.md` names:

1. **The scanner's position advance.** `take_string` and `take_date` thread
   `line` and `col` instead of relying on the caller's flat character
   arithmetic, and return the position just past the closing delimiter.
   `tokenize_chars/4` resumes from that position. This alone fixes every token
   after a multi-line literal, the `:eof` token, and therefore every parse
   error position and span derived from either.

2. **The token's end position.** The string token grows a seventh element
   holding its exclusive end position, and `token_end/1` reads it for a
   `:string` token instead of computing it. This fixes the literal's own AST
   span.

Phase 1 is committable and gate-green on its own: it changes no tuple shape, so
the parser is untouched. After Phase 1 the multi-line literal's own span is
still `{{1,1},{1,8}}` - no worse than today, just not yet fixed - which is why
Phase 2 exists. Phase 2 must land the lexer's tuple widening and the parser's
five destructuring sites in one commit, because either half alone leaves the
gate red. Phase 3 adds the error-path coverage and the reference doc touch-up;
it changes no `lib/` behavior.

The `\n` clause added to each scanner goes *after* the escape clause and
*before* the catch-all, so `\\` + `n` is still consumed as a two-character
escape and never mistaken for a source newline.

## Phase 1: Lexer advances line and column inside literal scanners

### Overview

Thread `line` and `col` through `take_string` and `take_date`, add a raw-newline
clause to each, and have `tokenize_chars/4` resume from the returned end
position. No token tuple shape changes; no parser change.

### Changes Required:

#### 1. The string scanner

**File**: `lib/predicator/lexer.ex`
**Changes**: `take_string/4` becomes `take_string/6`, taking the position of the
first content character and returning the position one past the closing quote.
A `?\n` clause increments `line` and resets `col` to 1, mirroring
lib/predicator/lexer.ex:192-193.

```elixir
@spec take_string(charlist(), binary(), pos_integer(), :double | :single,
                  pos_integer(), pos_integer()) ::
        {:ok, binary(), charlist(), pos_integer(), pos_integer(), pos_integer()}
        | {:error, binary()}
defp take_string([], _acc, _count, quote_type, _line, _col) do
  quote_name = if quote_type == :double, do: "double", else: "single"
  {:error, "Unterminated #{quote_name}-quoted string literal"}
end

defp take_string([?" | rest], acc, count, :double, line, col),
  do: {:ok, acc, rest, count, line, col + 1}

defp take_string([?' | rest], acc, count, :single, line, col),
  do: {:ok, acc, rest, count, line, col + 1}

# A two-character escape never contains a source newline, even when it
# decodes to one: `\n` is backslash-then-n in the source.
defp take_string([?\\ | [escaped | rest]], acc, count, quote_type, line, col) do
  char = # ...unchanged mapping...
  take_string(rest, acc <> char, count + 2, quote_type, line, col + 2)
end

defp take_string([?\n | rest], acc, count, quote_type, line, _col) do
  take_string(rest, acc <> "\n", count + 1, quote_type, line + 1, 1)
end

defp take_string([c | rest], acc, count, quote_type, line, col) do
  take_string(rest, acc <> <<c>>, count + 1, quote_type, line, col + 1)
end
```

#### 2. The date scanner

**File**: `lib/predicator/lexer.ex`
**Changes**: `take_date/3` becomes `take_date/5` with the same treatment. Its
success arm is unreachable with an embedded newline today (see Key
Discoveries), but threading removes the hidden dependency on ISO 8601 rejecting
newlines, and the `?\n` clause itself is reached on the error path.

```elixir
@spec take_date(charlist(), binary(), pos_integer(), pos_integer(), pos_integer()) ::
        {:ok, Date.t() | DateTime.t(), charlist(), pos_integer(),
         :date | :datetime, pos_integer(), pos_integer()}
        | {:error, binary()}
defp take_date([], _acc, _count, _line, _col), do: {:error, "Unterminated date literal"}

defp take_date([?# | rest], acc, count, line, col) do
  case parse_date_content(acc) do
    {:ok, date_value, token_type} -> {:ok, date_value, rest, count, token_type, line, col + 1}
    {:error, message} -> {:error, message}
  end
end

defp take_date([?\n | rest], acc, count, line, _col),
  do: take_date(rest, acc <> "\n", count + 1, line + 1, 1)

defp take_date([c | rest], acc, count, line, col),
  do: take_date(rest, acc <> <<c>>, count + 1, line, col + 1)
```

#### 3. The three call sites

**File**: `lib/predicator/lexer.ex` (lines 405-439)
**Changes**: pass the content-start position in, resume from the returned end
position. Error arms are unchanged.

```elixir
?" ->
  case take_string(rest, "", 1, :double, line, col + 1) do
    {:ok, content, remaining, consumed, end_line, end_col} ->
      token = {:string, line, col, consumed + 1, content, :double}
      tokenize_chars(remaining, end_line, end_col, [token | tokens])

    {:error, message} ->
      {:error, message, line, col, {{line, col}, {line, col + 1}}}
  end
```

The `?'` branch is identical with `:single`; the `?#` branch is the same shape
with `{token_type, line, col, consumed + 1, date_value}` and the two extra
return elements. `len` remains `consumed + 1`, the source character count -
unchanged in meaning, and still what every existing test asserts.

#### 4. Tests

**File**: `test/predicator/lexer_test.exs`
**Changes**: a new `describe "raw newlines inside literals"` block.

- `"\"ab\ncd\" > 5"` yields `{:string, 1, 1, 7, "ab\ncd", :double}`,
  `{:gt, 2, 5, 1, ">"}`, `{:integer, 2, 7, 1, 5}`, `{:eof, 2, 8, 0, nil}`.
- the same source single-quoted yields the same positions with `:single`.
- `~S|"a\nb" > 5|` (escape, not a source newline) leaves every token on line 1
  - the regression pin for the escape/raw distinction.
- `"\"ab\r\ncd\" > 5"` - CRLF - puts `>` on line 2.
- two multi-line literals in sequence accumulate correctly:
  `"\"ab\ncd\" \"ef\ngh\" x"` puts `x` on line 3.
- a bare newline outside a literal is unaffected: `tokenize("x\n> 5")` still
  puts `>` at `{2, 1}`.
- `tokenize("#2024-01-\n01# > 5")` is a lex error. This pins the invariant that
  Phase 2's 5-tuple `token_end/1` clause depends on; if a future change ever
  makes a multi-line date literal valid, this test goes red and says so.

#### 5. Changelog

**File**: `CHANGELOG.md`
**Changes**: a `### Fixed` bullet under `## [Unreleased]` stating that the
lexer now advances its line counter for a raw newline inside a string or date
literal, so every token after a multi-line literal - and every parse error
position derived from one - reports the line and column it actually occupies.
Phase 2 extends this bullet.

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality`
- [x] The new `describe` block in `test/predicator/lexer_test.exs` passes,
      including the escaped-`\n` regression pin and the multi-line-date-is-an-
      error pin
- [x] Every pre-existing test in `test/predicator/lexer_test.exs`,
      `lexer_edge_cases_test.exs`, `parser_test.exs`, `parser_spans_test.exs`
      and `parser_positions_test.exs` passes unmodified - no source in the
      suite that lacks a raw newline inside a literal may change behavior
- [x] Coverage stays above the 90% minimum in `coveralls.json`, with the new
      `?\n` clauses in both scanners covered
- [x] `mix corpus.generate` leaves the tree clean:
      `git diff --exit-code conformance/` - the exported specification does not
      move (ADR-0003)
- [x] `CHANGELOG.md` has a `### Fixed` bullet under `## [Unreleased]`

#### Manual Verification:
- [x] `Predicator.Lexer.tokenize/1` on a hand-written three-line source with a
      literal spanning lines 1-2 and an operator on line 3 reports positions
      that match the source read by eye
- [x] `Predicator.evaluate/3` on a predicate containing a multi-line string
      returns the same result as before the change - positions moved, semantics
      did not
- [x] No regression in `StringVisitor` round-tripping a multi-line string
      literal back to source

**Implementation Note**: Use `mix quality --profile loop` between edits; run
`mix quality` as the phase gate. In interactive execution, pause here for the
human to confirm the manual testing before moving to the next phase. In looped
(`--loop`) execution, this phase's Automated Verification gates advancement
automatically (via `/wurk:commit --auto`), and Manual Verification items are
deferred and surfaced once at the end instead of blocking here.

---

## Phase 2: The string token carries its end position

### Overview

Widen the `:string` token from six elements to seven by appending its exclusive
end position, and make `token_end/1` read that element instead of computing
`{line, col + len}`. The lexer and parser halves must land together: either
alone leaves the gate red.

### Changes Required:

#### 1. The token type

**File**: `lib/predicator/lexer.ex` (typedoc at :35-39, variant at :44)
**Changes**:

```elixir
@typedoc """
A lexical token with position information.

Format: `{type, line, column, length, value}`, except `:string`, which is
`{:string, line, column, length, value, quote_type, end_position}`.

`length` is the token's source character count. `end_position` is the
exclusive end - one past the closing quote - and is `{line, column + length}`
for every literal on a single line. The two disagree only when the literal
contains a raw newline, which is why the string token stores it rather than
letting a consumer compute it.
"""
```

and

```elixir
| {:string, pos_integer(), pos_integer(), pos_integer(), binary(),
   :double | :single, {pos_integer(), pos_integer()}}
```

#### 2. Token construction and the doctest

**File**: `lib/predicator/lexer.ex` (:410, :422, and the doctest at :149)
**Changes**: append `{end_line, end_col}`, the value Phase 1 already computed
and currently only uses to resume the scan.

```elixir
token = {:string, line, col, consumed + 1, content, :double, {end_line, end_col}}
```

The doctest at lib/predicator/lexer.ex:149 becomes
`{:string, 1, 9, 6, "John", :double, {1, 15}}`.

#### 3. The parser's position helpers

**File**: `lib/predicator/parser.ex` (:1526-1534)
**Changes**: replace both 6-tuple clauses. Match the 7-tuple on its `:string`
tag rather than on arity, and put it first, so the dispatch reads as the
special case it is.

```elixir
@spec token_start(Lexer.token()) :: Predicator.Types.position()
defp token_start({:string, line, col, _len, _value, _quote_type, _end}), do: {line, col}
defp token_start({_type, line, col, _len, _value}), do: {line, col}

# Exclusive: one past the token's last character. A `:string` token carries
# its own end, because it is the only token that can contain a raw newline -
# every other scanner's character class excludes one, and a date literal
# containing one fails ISO 8601 parsing before a token is built (pinned by
# "a date literal containing a newline is a lex error" in lexer_test.exs).
# For those, the lexer's length is the full source extent, quotes and date
# fences included, and `col + len` is exact.
@spec token_end(Lexer.token()) :: Predicator.Types.position()
defp token_end({:string, _line, _col, _len, _value, _quote_type, end_position}),
  do: end_position

defp token_end({_type, line, col, len, _value}), do: {line, col + len}
```

#### 4. The parser's three remaining string destructurings

**File**: `lib/predicator/parser.ex`
**Changes**: add a trailing `_end_position` at :1393 (`parse_primary_token/2`),
:1823 (the `:string` error clause in `parse_object_entry/1`) and :1849
(`parse_object_key/1`). Behavior is unchanged at all three.

#### 5. Existing test literals

**Files**: exactly 24 literals in three files -
`test/predicator/lexer_test.exs` (17: :360, :362, :374, :383, :392, :403, :414,
:430, :439, :448, :459, :469, :480, :674, :1056, :1066, :1076),
`test/predicator/lexer_edge_cases_test.exs` (4: :143, :152, :161, :170),
`test/predicator/parser_test.exs` (3: :526, :530, :811). Verified by
`grep -rEn '\{:string,\s*[0-9]+,\s*[0-9]+,\s*[0-9]+,' test`; no other test file
carries one.
**Changes**: append the seventh element to each `{:string, ...}` literal. For
every one of these the source is single-line, so the value is
`{line, col + len}` - which is the point: none of these assertions changes
meaning.

**File**: `test/predicator/parser_test.exs` (:2067-2078)
**Changes**: the test named "a `:string` token's span is derived from the
6-element token shape ..." is renamed for the 7-element shape, its `match?`
and destructuring gain the extra element, and its
`assert stop == {expected_line, expected_col + len}` is replaced by a
span-slicing assertion so it pins the contract rather than the arithmetic.

#### 6. New span tests

**File**: `test/predicator/parser_spans_test.exs`
**Changes**: a `describe "spans across a multi-line string literal"` block
using `Predicator.SpanSlicing.slice/2` (test/test_helper.exs:11) - no
hardcoded line numbers in the assertions.

- for `source = "\"ab\ncd\" > 5"`, the `:string_literal` node's span slices
  back to `"\"ab\ncd\""`.
- the enclosing `:comparison` node's span slices back to the whole `source`.
- the same for the single-quoted source.
- `Predicator.compile_with_spans(source)` returns a `positions` map whose every
  span slices back to non-empty source text, and whose `lit` instruction's span
  slices back to the literal including its quotes.
- `Predicator.compile_program_with_spans/1` on a two-statement program whose
  first statement contains a multi-line literal: the second statement's span
  slices back to the second statement.
- the escaped-`\n` source `~S|"a\nb" > 5|` slices back correctly too - the
  regression pin at the span layer.

#### 7. Changelog

**File**: `CHANGELOG.md`
**Changes**: extend the Phase 1 `### Fixed` bullet to say that the AST span of
a multi-line string literal now ends at its true end rather than
`{start_line, start_col + length}`, and that this changes span values exported
through `Predicator.compile_with_spans/1` and
`Predicator.compile_program_with_spans/1` for any source containing a
multi-line string literal - a consumer that pinned those values will see them
move. Note the lexer's `:string` token shape change in the same bullet, since
`Predicator.Lexer.token/0` is public.

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality`
- [x] Dialyzer is clean - it is the check that catches a missed `:string`
      destructuring site, since the widened `@type token` no longer admits the
      6-element form
- [x] The lexer doctest at `lib/predicator/lexer.ex:149` passes
- [x] The new `describe` block in `test/predicator/parser_spans_test.exs`
      passes, and every assertion in it is a `SpanSlicing.slice/2` comparison
      rather than a hardcoded coordinate
- [x] Coverage stays above the 90% minimum in `coveralls.json`
- [x] `mix corpus.generate` leaves the tree clean:
      `git diff --exit-code conformance/`
- [x] `CHANGELOG.md`'s `### Fixed` bullet names `compile_with_spans/1`,
      `compile_program_with_spans/1` and the `Predicator.Lexer.token/0` shape
      change

#### Manual Verification:
- [x] `Predicator.compile_with_spans("\"ab\ncd\" > 5")` returns
      `%{0 => {{1, 1}, {2, 4}}, ...}` and each span, sliced out of the source,
      reads as the construct it names
- [x] A single-line source's `compile_with_spans/1` output is unchanged from
      before the branch - compare against `git stash` or `origin/main`
- [x] `Predicator.Lexer.tokenize/1`'s moduledoc examples still read correctly
      as documentation for a reader, not just as passing doctests

**Implementation Note**: Use `mix quality --profile loop` between edits; run
`mix quality` as the phase gate. In interactive execution, pause here for the
human to confirm the manual testing before moving to the next phase. In looped
(`--loop`) execution, this phase's Automated Verification gates advancement
automatically (via `/wurk:commit --auto`), and Manual Verification items are
deferred and surfaced once at the end instead of blocking here.

---

## Phase 3: Parse-error positions and spans after a multi-line literal

### Overview

Phases 1 and 2 fix the error path as a consequence - `end_of_input_error/2`
reads the `:eof` token and `token_span/1` reads `token_end/1`, both now
correct. This phase pins that consequence with tests and records the token
shape exception in the reference documentation. No `lib/` behavior changes.

### Changes Required:

#### 1. Error-path tests

**File**: `test/predicator/parser_test.exs`
**Changes**: a `describe "failures after a multi-line string literal"` block.

- `Predicator.parse("\"ab\ncd\" > ")` returns an end-of-input failure whose
  `{line, col}` is the true end of the source, computed from the source in the
  test rather than hardcoded: `line == length(String.split(source, "\n"))` and
  `col == String.length(List.last(String.split(source, "\n"))) + 1`. This is
  px-dmt's "true end of the source" guarantee, now holding for a source with a
  multi-line literal.
- the failure's span is zero-width at that point, so
  `SpanSlicing.slice(source, span) == ""`.
- an unexpected-token failure after a multi-line literal -
  `Predicator.parse("\"ab\ncd\" > 5 extra")` - reports the offending token's
  real line and column, and `SpanSlicing.slice(source, span) == "extra"`.
- the lexical-failure arm: `Predicator.parse("\"ab\ncd\" > @")` reports the
  `@` at its real line and column.
- the span-start invariant from px-dmt - `elem(span, 0) == {line, col}` - still
  holds for all three failure kinds when a multi-line literal precedes them.

**File**: `test/predicator/integration/spans_test.exs`
**Changes**: one end-to-end case asserting that `Predicator.compile/1` and
`Predicator.compile_program_with_spans/1` return a
`%Predicator.Errors.ParseError{}` whose `:span` is the corrected one, so the
fix is visible at the public façade and not only inside `Parser`.

#### 2. Reference documentation

**File**: `docs/architecture.md`
**Changes**: extend the lexer's one-line component description (around :89) to
note that tokens are 5-element tuples except `:string`, which carries its quote
type and an explicit exclusive end position because it is the only token that
can span lines.

**File**: `docs/reference/ast.md`
**Changes**: if it documents span derivation, add a sentence that a span's end
is exclusive and is taken from the token rather than computed, so a multi-line
literal's span is correct. Skip if the file says nothing about token shapes.

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality`
- [x] The new `describe` block in `test/predicator/parser_test.exs` passes, and
      its end-of-source expectation is computed from the source string rather
      than written as a literal coordinate
- [x] The integration case asserting a span-bearing `ParseError` at the public
      façade passes
- [x] `mix docs` builds without warnings after the `docs/architecture.md` edit
- [x] Coverage stays above the 90% minimum in `coveralls.json`
- [x] `mix corpus.generate` leaves the tree clean:
      `git diff --exit-code conformance/`

#### Manual Verification:
- [x] The error message and caret position a consumer would render from the
      returned `{line, col}` land on the right character when checked by eye
      against a hand-written multi-line source
- [x] `docs/architecture.md`'s new sentence reads correctly next to its
      neighbors and uses the file's existing typography

**Implementation Note**: Use `mix quality --profile loop` between edits; run
`mix quality` as the phase gate. In interactive execution, pause here for the
human to confirm the manual testing before moving to the next phase. In looped
(`--loop`) execution, this phase's Automated Verification gates advancement
automatically (via `/wurk:commit --auto`), and Manual Verification items are
deferred and surfaced once at the end instead of blocking here.

---

## Open Questions

These were resolved by best judgment during planning because no human was
available to arbitrate. Each is recorded here with the call made and the
reasoning, so it can be revisited rather than rediscovered.

1. **`\r` inside a literal.** The top-level scanner consumes a bare `?\r`
   without advancing the column at all (lib/predicator/lexer.ex:195-196), which
   is itself a quirk. This plan does *not* mirror that inside the literal
   scanners: `\r` falls through to the catch-all and advances the column like
   any other character. That preserves the regression bar - no source without a
   raw newline in a literal changes behavior - because `\r` already counts
   toward `len` today. The cost is that the two scanners disagree about a lone
   `\r`. `\r\n` is handled correctly either way. Unifying them is a separate,
   behavior-changing decision and belongs in its own bead.

2. **Whether the date token should carry an end position too.** Decided no, on
   the grounds that no multi-line date token can be constructed and a 6-element
   date token would make `token_end/1`'s dispatch ambiguous again. The
   invariant is pinned by a Phase 1 test instead of by the type. If a future
   change makes a newline-bearing date literal valid, that test fails first and
   points here.

3. **Whether the bead's REPRODUCE column annotations should be treated as the
   specification.** Decided no - they are off by one and contradict the bead's
   own control case. The plan uses computed values throughout, and every test
   it specifies either computes its expectation from the source or slices the
   span back out of it, which is the property that makes this class of
   off-by-one impossible to bake in.

4. **Whether Phase 1 should be folded into Phase 2.** Decided no. Phase 1
   changes no tuple shape, so it is independently committable and gate-green,
   and it delivers the larger half of the user-visible fix on its own. The
   intermediate state it leaves - the literal's own span still ending at
   `{start_line, start_col + len}` while the tokens around it are correct - is
   no worse than today's, only differently incomplete.

## Testing Strategy

### Unit Tests:

- `test/predicator/lexer_test.exs` - token positions after a multi-line literal
  in both quote styles; the escaped-`\n` regression pin; CRLF; two multi-line
  literals in sequence; a bare newline outside a literal; a date literal
  containing a newline is a lex error.
- `test/predicator/parser_spans_test.exs` - the literal's own span, the
  enclosing node's span, and the `compile_with_spans/1` and
  `compile_program_with_spans/1` position tables, every assertion made by
  slicing the span back out of the source with `Predicator.SpanSlicing.slice/2`
  rather than by hardcoding coordinates.
- `test/predicator/parser_test.exs` - end-of-input, unexpected-token and
  lexical failures after a multi-line literal, with the end-of-source
  expectation computed from the source string.

The edge cases that actually bite here, and which each get a named test: the
`\n` *escape* versus a raw source newline; `\r\n`; consecutive multi-line
literals; an empty string literal (unchanged, `len` 2); a literal whose closing
quote is the last character of the source.

### Integration Tests:

- `test/predicator/integration/spans_test.exs` - one case evaluating a
  predicate containing a multi-line string literal end to end through
  `Predicator.evaluate/3`, and one
  asserting that a parse failure surfaced at the public façade carries a
  `%ParseError{}` whose `:span` is the corrected one.
- The existing `StringVisitor` round-trip suite
  (`test/predicator_test.exs:2200`) re-tokenizes regenerated source; it must
  stay green for a multi-line literal, confirming that the round-trip path is
  unaffected.

### Manual Testing Steps:

1. In `iex -S mix`, run `Predicator.Lexer.tokenize/1` on a hand-written
   three-line source with a string literal spanning lines 1-2 and an operator
   on line 3; confirm each reported position against the source read by eye.
2. Run `Predicator.compile_with_spans/1` on the same source and slice each span
   out of it; confirm each slice reads as the construct it names.
3. Run `Predicator.parse/1` on the same source truncated mid-expression;
   confirm the reported position is the last character of the source.
4. Compare `compile_with_spans/1` output for a single-line source against
   `origin/main`; confirm it is byte-identical.

## References

- Bead: `px-8he`
- Related ADRs: `docs/adr/0003-the-elixir-implementation-leads-the-isa.md`,
  `docs/adr/0004-no-eval-errors-are-values.md`,
  `docs/adr/0009-the-compiled-envelope-carries-the-position-table.md`,
  `docs/adr/0015-compile-errors-are-structured-values.md`
- Immediate predecessor: `docs/plans/260814-px-dmt-parse-error-spans.md`
- Span lineage: `docs/plans/260805-px-3kr-position-spans.md`,
  `docs/plans/260805-px-e3g.4-source-positions.md`,
  `docs/design/260806-px-l5s-parenthesized-span-extent.md`
- Similar surgical position fix: `docs/plans/260808-px-4nz-ast-point-position.md`
- Producer: `lib/predicator/lexer.ex:173` (`tokenize_chars/4`),
  `lib/predicator/lexer.ex:610` (`take_string/4`),
  `lib/predicator/lexer.ex:644` (`take_date/3`)
- Consumer: `lib/predicator/parser.ex:1526` (`token_start/1`),
  `lib/predicator/parser.ex:1532` (`token_end/1`),
  `lib/predicator/parser.ex:1555` (`token_span/1`),
  `lib/predicator/parser.ex:1571` (`end_of_input_error/2`)
- Test helper: `test/test_helper.exs:11` (`Predicator.SpanSlicing.slice/2`)
- Downstream consumer of these spans: statifier-ex ADR-0014,
  `lib/statifier/parser/location.ex`

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

**All items below were confirmed on 2026-08-14.** The "unchanged behavior"
items were checked by running the same script against a throwaway worktree at
the branch point (`dfdd94f`) and diffing the output, rather than by
inspection: single-line `compile_with_spans/1` positions, `evaluate/3`
results, and `StringVisitor` round-tripping are byte-identical to
pre-change. Two findings came out of the pass and are recorded here because
neither is visible from the diff:

- The pre-change span end for `"ab\ncd"` was `{1, 8}`, which slices the
  literal out of the source correctly even though line 1 holds only three
  characters. A column measured without counting newlines coincides with a
  flat offset, so a consumer doing byte arithmetic saw plausible values while
  a consumer trusting the line number did not - which is the statifier
  failure mode the bead predicted, and the reason a slicing assertion alone
  would not have caught this.
- The end-of-input error position after a multi-line literal now lands at the
  true end of the source, restoring px-dmt's guarantee for exactly the
  sources it did not previously hold for.

### Phase 1

- [x] `Predicator.Lexer.tokenize/1` on a hand-written three-line source with a
      literal spanning lines 1-2 and an operator on line 3 reports positions
      that match the source read by eye
- [x] `Predicator.evaluate/3` on a predicate containing a multi-line string
      returns the same result as before the change - positions moved, semantics
      did not
- [x] No regression in `StringVisitor` round-tripping a multi-line string
      literal back to source

**Implementation Note**: Use `mix quality --profile loop` between edits; run
`mix quality` as the phase gate. In interactive execution, pause here for the
human to confirm the manual testing before moving to the next phase. In looped
(`--loop`) execution, this phase's Automated Verification gates advancement
automatically (via `/wurk:commit --auto`), and Manual Verification items are
deferred and surfaced once at the end instead of blocking here.

---

### Phase 2

- [x] `Predicator.compile_with_spans("\"ab\ncd\" > 5")` returns
      `%{0 => {{1, 1}, {2, 4}}, ...}` and each span, sliced out of the source,
      reads as the construct it names
- [x] A single-line source's `compile_with_spans/1` output is unchanged from
      before the branch - compare against `git stash` or `origin/main`
- [x] `Predicator.Lexer.tokenize/1`'s moduledoc examples still read correctly
      as documentation for a reader, not just as passing doctests

**Implementation Note**: Use `mix quality --profile loop` between edits; run
`mix quality` as the phase gate. In interactive execution, pause here for the
human to confirm the manual testing before moving to the next phase. In looped
(`--loop`) execution, this phase's Automated Verification gates advancement
automatically (via `/wurk:commit --auto`), and Manual Verification items are
deferred and surfaced once at the end instead of blocking here.

---

### Phase 3

- [x] The error message and caret position a consumer would render from the
      returned `{line, col}` land on the right character when checked by eye
      against a hand-written multi-line source
- [x] `docs/architecture.md`'s new sentence reads correctly next to its
      neighbors and uses the file's existing typography

**Implementation Note**: Use `mix quality --profile loop` between edits; run
`mix quality` as the phase gate. In interactive execution, pause here for the
human to confirm the manual testing before moving to the next phase. In looped
(`--loop`) execution, this phase's Automated Verification gates advancement
automatically (via `/wurk:commit --auto`), and Manual Verification items are
deferred and surfaced once at the end instead of blocking here.

---
