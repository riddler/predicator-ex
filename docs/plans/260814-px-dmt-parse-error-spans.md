# Parse-error spans Implementation Plan

## Overview

Beads issue: `px-dmt`

Give a parse or lex failure the extent of the text that failed, not just a
point. `Predicator.Errors.ParseError` gains an optional `:span`, the parser and
lexer error term widens from a 4-tuple to a 5-tuple carrying that span, the
end-of-input clauses stop reporting a hardcoded `{1, 1}`, and all six compile
entry points return a span-bearing `ParseError` in every mode.

This is the span half of ADR-0015, which structured the compile error arm and
deliberately left spans out. ADR-0015's section "Parse-error spans: what would
have to happen first" numbers the work 1-4; the four phases below are those
four steps, in that order.

## Current State Analysis

**The extent data is already in the pipeline and is thrown away.** The lexer's
token type is `{type, line, column, length, value}`
(`lib/predicator/lexer.ex:38`), with a 6-element variant for `:string` tokens
carrying the quote style (`lib/predicator/lexer.ex:44`). Every token knows its
own length, so the failing token's extent is in scope at the moment the parser
reports the failure - and the error term, `{:error, message, line, column}`, has
room only for a point.

**That 4-tuple is the shape of every error clause in both modules.**
`Predicator.Parser`'s `@type result` and `@type program_result`
(`lib/predicator/parser.ex:315`, `249-250`) and `Predicator.Lexer`'s `@type
result` (`lib/predicator/lexer.ex:99`) all declare it. `parser.ex` has roughly
23 construction sites with a failing token in scope, 14 end-of-input
construction sites, and about 100 further mentions that are `@spec` lines and
pass-through clauses of the form `{:error, message, line, col} -> {:error,
message, line, col}`. `lexer.ex` has 6 construction sites
(`lib/predicator/lexer.ex:342`, `352`, `411`, `423`, `435`, `440`).

**Neither module knows anything about error structs.** `parser.ex` aliases only
`Predicator.Cast` and `Predicator.Lexer` (`lib/predicator/parser.ex:108-109`);
`lexer.ex` has no aliases at all. `%ParseError{}` is constructed exactly one
layer up, in `lib/predicator.ex` (lines 201, 205, 565, 891, 909) and in
`lib/predicator/context_location.ex` (lines 150, 154).

**`ParseError` has no `:span` field.** `lib/predicator/errors/parse_error.ex:24-30`:
`@enforce_keys [:message, :position]`, `defstruct [:message, :position]`, and a
single constructor `new/3`. `Predicator.Errors.put_position/2`
(`lib/predicator/errors.ex:44-50`) already discriminates a span-bearing struct
from a point-only one with `Map.has_key?(error, :span)`, so adding the field
changes what that function does when it is handed a `ParseError` and a span.

**End of input already has a real position most of the time, and the hardcoded
`{1, 1}` sites are the defensive ones.** The lexer always appends
`{:eof, line, col, 0, nil}` as the last token (`lib/predicator/lexer.ex:172`),
with the true end-of-source line and column and a length of `0`. So
`peek_token/1` returns that sentinel rather than `nil`, the
`{type, line, col, _len, value}` clause matches it, `format_token(:eof, _)`
renders `"end of input"` (`lib/predicator/parser.ex:1621`), and the reported
position is correct - which is why `Predicator.compile("score >")` already
reports `{1, 8}` (`lib/predicator.ex:711-713`). The fourteen `nil ->` clauses
that hardcode `1, 1` are reached only when `position` has walked past the
sentinel or when a hand-built token list lacks one. They are wrong regardless,
and the parser already carries the whole token list for the life of the parse
(`lib/predicator/parser.ex:323-327`; `peek_token/1` indexes, it does not pop),
so the sentinel is always recoverable from `state.tokens`.

**The baseline is green.** `mix quality` on this worktree at plan time: format
clean, compile clean with warnings-as-errors, credo clean, dialyzer clean, and
2,652 of 2,652 tests passing at 94.9% coverage. Every phase gate below is a
delta against that, and the 94.9% figure is the headroom the 90% floor in
`coveralls.json` leaves for the new branches this work adds.

**A release is already open for this break.** `mix.exs:5` says `7.0.0`, and
`CHANGELOG.md`'s `## [Unreleased]` already carries the ADR-0015 compile-arm
break slated for 8.0.0. ADR-0015's consequence "the 8.0 release should carry any
other queued façade break with it" applies directly: this bead rides that same
unreleased major rather than asking for 9.0.

## Desired End State

- `%Predicator.Errors.ParseError{}` has four constructible shapes' worth of
  behaviour from two constructors: `new/3` (point only, `:span` `nil`) and
  `new/4` (point plus span). `:span` is outside `@enforce_keys` and defaults to
  `nil`, so every existing construction site keeps compiling.
- `Predicator.Parser.parse/2`, `Predicator.Parser.parse_program/2`,
  `Predicator.Lexer.tokenize/1`, `Predicator.parse/2`, and
  `Predicator.parse_program/2` return `{:error, message, line, column, span}`,
  with the invariant `span == {{line, column}, {end_line, end_column}}` - the
  point is always the span's start, so a caller that reads only the first four
  elements positionally reads exactly what it read before.
- A failure with a token in scope reports that token's extent. A failure with no
  token reports a zero-width span at the true end of the source, and its point
  is the end of the source rather than `{1, 1}`.
- All six compile entry points return `{:error, %ParseError{span: {_, _}}}` for
  a parse or lex failure, in point mode as much as in span mode. The `spans:
  true` parse option does not gate it.
- `docs`, `@spec`s, and the `## [Unreleased]` CHANGELOG section describe the new
  shapes; the existing 8.0 entry's claim that `parse/2` and `parse_program/2`'s
  4-tuple is unchanged is corrected.
- `mix quality` is green; per-component coverage stays above the 90% floor in
  `coveralls.json`; the ISA version is still 6 and no corpus file moves.

Verify with: `mix quality`, plus the doctests and unit tests named per phase.

### Key Discoveries:

- `token_span/1` already exists and is exactly the helper this needs -
  `lib/predicator/parser.ex:1522-1523`, built from `token_start/1`
  (`:1493-1495`) and `token_end/1` (`:1499-1501`), both of which handle the
  5-element and 6-element token shapes and neither of which needs
  `parser_state`. The `:eof` token's length of `0` makes `token_span/1` return a
  zero-width span for free.
- `loc/3` (`lib/predicator/parser.ex:1485-1488`) gates on `state.spans?`. Error
  spans must **not** go through it - ADR-0015 step 4 is explicit that a parse
  error's span comes from the token stream, not from the node-metadata option.
- `Predicator.Errors.put_position/2` (`lib/predicator/errors.ex:44-50`) changes
  behaviour for `ParseError` the moment the field is added: given a span it will
  now set `:span` and `:position` instead of only `:position`. That is the
  intended effect (the ADR names it), but it is a live behaviour change that
  Phase 1 must test, not a no-op.
- `Predicator.Parser.parse/2` takes a **token list**, not a string
  (`lib/predicator/parser.ex:365`, `423`); tokenization happens in
  `lib/predicator.ex` (lines 197, 515, 930, 962). The parser therefore never
  sees the source text and cannot compute an end-of-source position from
  anything but the `:eof` token.
- ADR-0015 is the governing decision; ADR-0004 (errors are values) and ADR-0003
  (the ISA moves only on ISA changes) bound it. ADR-0004's own note that
  `docs/architecture.md` states the error contract wrongly is tracked as px-mis,
  not here.

## What We're NOT Doing

- **Not moving the ISA.** No opcode is added, removed, renamed, or given
  different semantics; no instruction gains an element. `docs/isa.md` stays at
  version 6, `conformance/**` is untouched, and no `mix corpus.generate` run is
  part of this work. The corpus pins evaluation semantics, not façade return
  shapes. The `## ISA Impact` section that `.claude/wurk/plan.md` describes is
  therefore omitted, per that file's own instruction to include it only when an
  opcode changes.
- **Not turning the parser's error term into a struct.** `Parser` and `Lexer`
  stay free of `Predicator.Errors`; `%ParseError{}` keeps being constructed one
  layer up. See Open Questions.
- **Not adding `Predicator.Errors.format/1`**, and not adding a `:stage` field
  distinguishing a lexical failure from a syntactic one. Both are ADR-0015's
  own open questions, both are additive, and neither is needed for a span.
- **Not deleting the defensive `nil ->` clauses** in `parser.ex` even though the
  lexer's `:eof` sentinel makes them near-unreachable. Phase 3 gives them a
  correct position; removing a defensive branch is a separate judgment call with
  its own coverage consequences.
- **Not editing historical records.** `docs/adr/**`, `docs/plans/**`, and
  `docs/research/**` show the 4-tuple in prose written when it was true; they are
  records of decisions taken, not live documentation. ADR-0015 is amended by
  this bead's existence, not by an edit. `docs/reference/language.md` is the
  exception and **is** edited - it is doctested by
  `test/docs_examples_test.exs:14`, so it is live and would go red otherwise.
- **Not touching `docs/architecture.md`'s "Error Handling" bullet.** It already
  states the contract wrongly for a different reason and px-mis owns it; fixing
  it here would collide with that bead.
- **Not adding a StringVisitor round-trip criterion.** `.claude/wurk/plan.md`
  requires one for a new AST or grammar node; this change adds neither, so the
  criterion has nothing to bind. The grammar and the precedence table in
  `docs/architecture.md` are untouched.
- **Not cutting the release.** Version bumping, changelog promotion, and tagging
  are release work under CLAUDE.md's authority table and need an explicit human
  request naming the version.

## Implementation Approach

Four phases, matching ADR-0015's four numbered steps and the bead's own order of
work. The ordering is not arbitrary: each phase leaves `mix quality` green on
its own, and the seam between them is chosen so that no phase has to undo
another's work.

The error term becomes a **5-tuple, `{:error, message, line, column, span}`**,
appending rather than restructuring. Three reasons: the ~100 pass-through
clauses and `@spec` lines in `parser.ex` change by one element rather than being
rewritten; the positional read of `line` and `column` survives for anyone
porting a `case` clause; and a consumer that still matches the old 4-tuple fails
to match loudly instead of silently binding the span to `column`. ADR-0015 step 2
names this shape first among its two sketched options.

The invariant that makes the phases compose is **`span` is always
`{{line, column}, end}`** - the tuple's point is the span's start, always. Phase
2 derives the end-of-input span as `{point, point}` from whatever point the
clause already reports, which is why Phase 3's point fix repairs those spans
automatically without a second edit to the same lines.

Phase 2 deliberately stops short of putting the span on the struct: the compile
helpers are widened to *accept* the 5-tuple and discard the span, which keeps
the gate green and leaves Phase 4 a real change to make. That mirrors ADR-0015's
own "until step 2 lands, a structured compile error carries a point position and
a `nil` span, which is a complete and honest value."

---

## Phase 1: `ParseError` gains an optional `:span`

### Overview

Purely additive. The struct grows a field and a constructor; nothing else in the
tree changes behaviour except `Errors.put_position/2`, which starts populating
that field when it is handed a span, exactly as it already does for the
evaluator's error structs.

### Changes Required:

#### 1. The struct

**File**: `lib/predicator/errors/parse_error.ex`
**Changes**: add `:span` outside `@enforce_keys`, widen `@type t`, add `new/4`,
and document the field. The moduledoc's `## Fields` list gains a `span` entry
saying it is `nil` unless the failure carried a token extent, and that
`:position` is always the span's start when both are present.

```elixir
@enforce_keys [:message, :position]
defstruct [:message, :position, span: nil]

@type t :: %__MODULE__{
        message: binary(),
        position: Predicator.Types.position(),
        span: Predicator.Types.span() | nil
      }

@spec new(binary(), pos_integer(), pos_integer()) :: t()
def new(message, line, column) do
  %__MODULE__{message: message, position: {line, column}, span: nil}
end

@spec new(binary(), pos_integer(), pos_integer(), Predicator.Types.span() | nil) :: t()
def new(message, line, column, span) do
  %__MODULE__{message: message, position: {line, column}, span: span}
end
```

#### 2. `put_position/2`'s documented behaviour

**File**: `lib/predicator/errors.ex`
**Changes**: no code change - the `Map.has_key?(error, :span)` branch at lines
44-50 already does the right thing. Add a doctest showing it on a `ParseError`,
so the new field's interaction with the existing discriminator is bound by a
test rather than by reading.

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality`
- [x] `%ParseError{}` built by `new/3` has `span: nil`; `new/4` stores the span
      and sets `:position` to the span's start-equivalent point - asserted in
      `test/predicator/errors/parse_error_test.exs` (created if absent)
- [x] `Predicator.Errors.put_position(%ParseError{}, {{1, 1}, {1, 6}})` returns a
      struct with `span: {{1, 1}, {1, 6}}` and `position: {1, 1}`
- [x] `Predicator.Errors.put_position(%ParseError{}, {1, 3})` still returns
      `position: {1, 3}` and leaves `span` untouched
- [x] Coverage for `lib/predicator/errors/` stays above the 90% floor in
      `coveralls.json`

#### Manual Verification:
- [ ] Every existing `ParseError.new/3` call site still compiles and returns a
      value whose `:span` is `nil` - confirmed by reading the five sites in
      `lib/predicator.ex` and two in `lib/predicator/context_location.ex`
- [ ] No existing test that pattern-matches a whole `%ParseError{}` literal
      breaks on the new field
- [ ] The moduledoc example is accurate about `:span` being `nil` at this point
      in the sequence

**Implementation Note**: Use `mix quality --profile loop` between edits; run the
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, the Automated Verification gates advancement and
Manual Verification items are deferred to the end.

---

## Phase 2: The parser and lexer error term carries the extent

### Overview

The wide, mechanical phase, and the one that breaks a public shape. Every error
term in `Predicator.Parser` and `Predicator.Lexer` becomes
`{:error, message, line, column, span}`, and every consumer of the 4-tuple in
`lib/` and `test/` is updated. The compile arm's *observable* behaviour does not
change in this phase: the helpers in `lib/predicator.ex` accept the 5-tuple and
drop the span on the floor.

**This phase is much larger than the other three and does not split further.**
A widened `@type result` with any consumer left on the 4-tuple is a red gate -
dialyzer on the specs, `CaseClauseError`s in the suite - so there is no smaller
unit that is independently green. Expect several `mix quality --profile loop`
iterations inside the phase rather than one edit-and-gate pass, and work in this
order, which keeps the feedback useful at every step: types and specs first,
then `parser.ex`'s construction and pass-through sites, then `lexer.ex`, then
the `lib/` consumers, then the tests, then the three doctests. The doctests go
last on purpose - while they are still red they are a free reminder that the
`lib/` side is not finished.

### Changes Required:

#### 1. The error type and the construction sites

**File**: `lib/predicator/parser.ex`
**Changes**: widen `@type result` (line 315) and `@type program_result` (lines
249-250), and every inline `{:error, binary(), pos_integer(), pos_integer()}` in
a `@spec`, to a 5-tuple ending in `Predicator.Types.span()`. Each of the ~23
construction sites with a token in scope binds the token and calls the existing
private `token_span/1` (line 1522). Each of the 14 `nil ->` end-of-input sites
emits a zero-width span at the point it already reports.

```elixir
# token in scope - bind the whole token, not just line and col
{_type, line, col, _len, value} = token ->
  {:error, "Expected ']' but found #{format_token(elem(token, 0), value)}",
   line, col, token_span(token)}

# end of input - the point is still whatever this clause reports today;
# Phase 3 corrects it, and this span follows it for free
nil ->
  {:error, "Expected ']' but found end of input", 1, 1, {{1, 1}, {1, 1}}}
```

A small private helper keeps the second form from being written fourteen times:

```elixir
# A failure with no token has no extent to borrow, so its span is a
# zero-width point. Deriving the span from the point here is what lets
# Phase 3 fix both by fixing only the point.
@spec point_error(binary(), pos_integer(), pos_integer()) ::
        {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
defp point_error(message, line, col), do: {:error, message, line, col, {{line, col}, {line, col}}}
```

Pass-through clauses become `{:error, _message, _line, _col, _span} = error -> error`
wherever the existing clause already re-tags without inspecting, and
`{:error, message, line, col, span} -> {:error, message, line, col, span}` where
the existing code spells the rebuild out. Prefer collapsing to the `= error`
form; it is the shape most of the file already uses and it removes the risk of a
mis-ordered rebuild.

**File**: `lib/predicator/lexer.ex`
**Changes**: widen `@type result` (line 99) and the `@doc` at line 122. The six
construction sites get spans by this rule: a site whose failure is a single
character (`lib/predicator/lexer.ex:342`, `352`, `440` - the "Unexpected
character" family) spans that one character, `{{line, col}, {line, col + 1}}`; a
site that re-raises a `{:error, message}` from a `take_*` helper
(`:411`, `:423`, `:435` - unterminated and malformed literals) spans the opening
delimiter character at the reported position, also one character wide. The
`take_*` helpers' own `{:error, binary()}` returns are unchanged.

#### 2. The consumers in `lib/`

**File**: `lib/predicator.ex`
**Changes**: the four tokenize/parse sites (lines 197-205, 515-526, 930-931,
962-963) match the 5-tuple. `Predicator.parse/2` and `Predicator.parse_program/2`
return it unchanged - that is the public break. `execute_value_parse_error/4`
(line 564) gains the span argument but continues to build with `ParseError.new/3`
until Phase 4. `build_compiled_result/1` (line 890) and
`build_instructions_result/1` (line 908) match `{:error, message, line, column, _span}`
and keep calling `ParseError.new/3`; their `@spec`s (lines 879-882, 897-900)
widen accordingly.

**File**: `lib/predicator/context_location.ex`
**Changes**: the two sites at lines 150 and 154 match the 5-tuple and ignore the
span for now.

#### 3. Docs on the functions whose shape changed

**Files**: `lib/predicator/parser.ex` (the `@doc` "Returns" lists at lines 344
and 406), `lib/predicator/lexer.ex:122`, and `Predicator.parse/2` /
`Predicator.parse_program/2`'s `@doc`s in `lib/predicator.ex` (the `@spec` at
`lib/predicator.ex:927-928` types the 4-tuple and widens with them)
**Changes**: describe `{:error, message, line, column, span}`, state the
invariant that `span`'s start equals `{line, column}`, and say that the span is
present in point mode as much as in span mode - it is not the `:spans` option.

Three live doctests show the 4-tuple and go red the moment the term widens.
They are the phase's early-warning system, so fix them last, not first:

- `lib/predicator/parser.ex:418-420` - `Parser.parse_program/2`'s example
- `lib/predicator.ex:957-958` - `Predicator.parse_program/2`'s example
- `docs/reference/language.md:270-273` - the statement-keyword-in-expression
  example. This file is doctested for real, via `doctest_file("docs/reference/
  language.md")` at `test/docs_examples_test.exs:14`, so it is live
  documentation and not a historical record. Its reported `1, 1` is correct
  (the `if` token starts at column 1) and stays; it gains
  `{{1, 1}, {1, 3}}`.

No other doctest in `lib/`, `README.md`, or `docs/guides/**` shows a parse or
lex error arm - the `{:error, "Division by zero"}` samples in
`docs/guides/custom-functions.md` and `docs/reference/language.md` are custom
function returns and are unaffected.

#### 4. The tests that assert the shape

**Files**: thirteen, in rough descending order of how many assertions each
carries - `test/predicator/parser_test.exs` (by far the largest),
`test/predicator/reserved_words_test.exs`,
`test/predicator/parser_edge_cases_test.exs`,
`test/predicator/lexer_test.exs`,
`test/predicator/equals_grammar_break_test.exs`,
`test/predicator/object_parser_test.exs`,
`test/predicator/if_statement_test.exs`,
`test/predicator/lexer_edge_cases_test.exs`,
`test/predicator/object_edge_cases_test.exs`,
`test/predicator_test.exs`,
`test/predicator/while_statement_test.exs`,
`test/predicator/strict_equality_test.exs`,
`test/predicator/date_arithmetic_string_visitor_test.exs`.

Deliberately no per-file counts: two different greps over these files disagree
by more than a factor of two, because a `{:error,` in a test file is as likely
to be a compiler or evaluator error as a parse one, and a number written down
here would be trusted more than it deserves. Get the real inventory at the start
of the phase with the pattern you will actually edit against, and let the
compiler and the suite name whatever the grep missed:

```bash
grep -rn '{:error, [^}]*, [0-9a-z_]\+, [0-9a-z_]\+}' test/
```

None of the matches live under `test/predicator/conformance/**`, which is what
makes the "no corpus move" claim checkable rather than asserted.
**Changes**: every assertion on a parse or lex error becomes a 5-tuple. Where an
assertion only cares about the message, prefer `{:error, message, _, _, _}` over
spelling the span out; add explicit span assertions only in the new tests
described below, so the bulk of the suite does not have to be re-edited if a
span is later refined.

New assertions to add (in `test/predicator/parser_test.exs` and
`test/predicator/lexer_test.exs`):

- a single-token failure spans exactly that token, checked against a token
  longer than one character (e.g. an identifier or a keyword), not just a
  punctuation mark
- a `:string` token failure spans correctly, exercising the 6-element token
  shape through `token_start/1` and `token_end/1`
- the invariant `elem(err, 4) |> elem(0) == {elem(err, 2), elem(err, 3)}` holds
  for a representative error from each of: an unexpected token, a lexical
  failure, and an end-of-input failure
- a lexical "Unexpected character" failure spans one character

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality` (dialyzer included - the widened
      `@spec`s are the main thing it checks here)
- [x] `grep -n '{:error, [^}]*, pos_integer(), pos_integer()}' lib/predicator/parser.ex
      lib/predicator/lexer.ex` returns nothing - no 4-tuple `@spec` survives
- [x] For a token-bearing failure, `Predicator.parse("score >>")`-style cases
      return a span whose width equals the failing token's length
- [x] The point/span-start invariant holds across the three representative
      failure classes named above
- [x] Coverage for `lib/predicator/parser.ex` and `lib/predicator/lexer.ex`
      stays above the 90% floor in `coveralls.json`
- [x] `mix test test/docs_examples_test.exs` passes - `docs/reference/
      language.md` is doctested and its parse-error example must move with the
      shape
- [x] All six compile entry points still return `{:error, %ParseError{span: nil}}` -
      the compile arm is unchanged in this phase, and a test asserting `span: nil`
      here is what makes Phase 4 a visible change

#### Manual Verification:
- [ ] No pass-through clause silently reordered `line`, `column`, and `span` -
      spot-check the collapsed `= error` rewrites in the deeply nested regions
      (`lib/predicator/parser.ex:1015-1043`, `1240-1330`, `1640-1720`)
- [ ] A multi-line string literal's failure produces a span that is wrong in the
      same way AST node spans are already wrong for it (`token_end/1` computes
      `col + len` regardless of newlines) - consistency with existing behaviour
      is the bar, not correctness that AST spans do not have
- [ ] The lexer's one-character span rule reads sensibly on an unterminated
      string: the caret lands on the opening quote

**Implementation Note**: Use `mix quality --profile loop` between edits; run the
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, the Automated Verification gates advancement and
Manual Verification items are deferred to the end.

---

## Phase 3: End of input reports the end of the source

### Overview

The correctness fix ADR-0015 says is worth landing on its own merits. The
fourteen `nil ->` clauses stop reporting `{1, 1}` and report the true end of the
source instead. Because Phase 2 derived their spans from their points, the spans
become correct zero-width end-of-source spans with no further edit to those
lines.

### Changes Required:

#### 1. An end-of-input location helper

**File**: `lib/predicator/parser.ex`
**Changes**: one private helper, used by every `nil ->` clause. The parser keeps
the full token list for the life of the parse
(`lib/predicator/parser.ex:323-327`), and the lexer always appends
`{:eof, line, col, 0, nil}` (`lib/predicator/lexer.ex:172`), so the sentinel is
always the last element.

```elixir
# A failure with no token in scope reports the end of the source, not {1, 1}.
# The lexer's :eof sentinel carries the true end position and a length of 0,
# so token_span/1 gives a zero-width span there for free. The {1, 1} fallback
# survives only for a hand-built token list with no sentinel at all, which the
# public entry points cannot produce.
@spec end_of_input_error(parser_state(), binary()) ::
        {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
defp end_of_input_error(%{tokens: tokens}, message) do
  case List.last(tokens) do
    nil -> point_error(message, 1, 1)
    token -> {line, col} = token_start(token); {:error, message, line, col, token_span(token)}
  end
end
```

Each of the fourteen sites listed in Current State Analysis
(`lib/predicator/parser.ex:658`, `698`, `1258`, `1291`, `1320`, `1420`, `1466`,
`1648`, `1706`, `1767`, `1792`, `1828`, `1841`, `1937`) becomes
`nil -> end_of_input_error(state, "...")`, with the state binding that clause
already has in scope. `point_error/3` from Phase 2 is retained as the helper's
own fallback.

Note that `List.last/1` on the token list is O(n) in the number of tokens. It
runs at most once per parse, only on the failure path, and only on the branch
the `:eof` sentinel normally prevents from being reached at all - so it is not a
hot path and needs no index.

#### 2. Tests

**File**: `test/predicator/parser_test.exs`
**Changes**: assert the true end-of-source point and zero-width span for
end-of-input failures. The natural route is the `:eof`-token clause, which is
what real input reaches: `Predicator.parse("[1,")` and friends already report a
real position through the `{type, line, col, ...}` branch - pin those. To reach
the `nil` branch, a test constructs a token list directly and calls
`Predicator.Parser.parse/2` with it, which is a public function taking a token
list.

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality`
- [x] `grep -n ', 1, 1}' lib/predicator/parser.ex` returns no error-construction
      line - the only surviving `{1, 1}` literals are `program_start_point/1`'s
      fallback (line 450) and doctest expectations
- [x] End-of-input failures on multi-line sources report the last line, not line
      1 - e.g. a source ending after a newline reports that line's end
- [x] Every end-of-input span is zero-width and its start equals the reported
      point
- [x] Coverage for `lib/predicator/parser.ex` stays above the 90% floor
- [x] Existing doctests that show an end-of-input position
      (`lib/predicator.ex:711-713`, `798-800`) still pass unchanged - those go
      through the `:eof` token and were already correct

#### Manual Verification:
- [ ] The reported end-of-source column is one past the last character, matching
      the exclusive-end convention `Predicator.Types.span/0` documents
- [ ] A source ending in trailing whitespace or a newline reports a position a
      human would call "the end", not a surprising interior point
- [ ] The `nil`-branch tests genuinely exercise the branch rather than falling
      through to the `:eof` clause - confirmed by temporarily breaking the
      helper and seeing them go red

**Implementation Note**: Use `mix quality --profile loop` between edits; run the
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, the Automated Verification gates advancement and
Manual Verification items are deferred to the end.

---

## Phase 4: The compile arm carries the span, in every mode

### Overview

The span reaches `%ParseError{}` and therefore every public function that
returns one. This is ADR-0015 step 4, including its insistence that the span is
not gated on `_with_spans`. Docs, specs, and the CHANGELOG land here.

### Changes Required:

#### 1. The construction sites

**File**: `lib/predicator.ex`
**Changes**: `build_compiled_result/1` (line 890), `build_instructions_result/1`
(line 908), the two `evaluate` paths (lines 201-205), and
`execute_value_parse_error/4` (line 564) all switch from `ParseError.new/3` to
`ParseError.new/4`, passing the span through. No mode branching: the same code
serves `compile/1` and `compile_with_spans/1` alike.

**File**: `lib/predicator/context_location.ex`
**Changes**: the two sites at lines 150 and 154 switch to `new/4` for the same
reason - a caller of `context_location/3` gets the same struct a caller of
`compile/1` does.

#### 2. Docs on the six compile entry points

**File**: `lib/predicator.ex`
**Changes**: the closing paragraph repeated in all six `@doc`s (lines 715-718,
744-747, 773-776, 802-805, 825-828, 861-864) currently points callers at
`parse/2` "for the raw 4-tuple". It becomes a 5-tuple, and gains a sentence
saying the struct now carries `:span` in every mode. The line at
`lib/predicator.ex:866-867` - "a parse error carries a point position and never a
span, in span mode as much as in point mode" - is now false and is replaced by
its inverse. Add a doctest to `compile/1` showing `error.span` alongside
`error.message` and `error.position`, and one to `compile_program/1`.

Also update `Predicator.evaluate/3`'s error list (line 144) and the
`context_assign/4` doc at line 1229, both of which name `ParseError` without
mentioning the span.

#### 3. CHANGELOG

**File**: `CHANGELOG.md`
**Changes**: two edits under `## [Unreleased]` / `### Changed`.

First, correct the existing ADR-0015 entry: its "Unchanged:" list names
"`parse/2` and `parse_program/2`'s 4-tuple" among the things this release does
not move. It does now. Strike that clause from the list rather than leaving two
entries contradicting each other.

Second, a new entry naming the migration:

```markdown
- **BREAKING: `parse/2`, `parse_program/2`, and `Predicator.Lexer.tokenize/1`
  now return `{:error, message, line, column, span}` instead of
  `{:error, message, line, column}`, and every `%Predicator.Errors.ParseError{}`
  carries the same extent in a new `:span` field.** The span is the source
  extent of the token that failed - `{{start_line, start_column},
  {end_line, end_column}}` with an exclusive end, the same
  `t:Predicator.Types.span/0` the position tables use - and its start is always
  the tuple's own `{line, column}`, so a caller reading only the first four
  elements reads exactly what it read before and a caller matching the 4-tuple
  gets a loud `CaseClauseError` rather than a silent mis-bind. A failure with no
  token to borrow an extent from reports a zero-width span at the end of the
  source; the end-of-input clauses that previously reported a hardcoded
  `{1, 1}` now report the true end of the source, which is a position-correctness
  fix in its own right. All six compile entry points carry the span in every
  mode - `compile/1` as much as `compile_with_spans/1` - because a parse error's
  extent comes from the token stream, not from the `spans: true` node-metadata
  option. `:span` is `nil` only on a `ParseError` built by a caller through
  `new/3`. The ISA version is unchanged (still 6), no instruction list moves,
  and the conformance corpus is untouched.
```

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality`
- [x] All six compile entry points return `{:error, %ParseError{span: span}}`
      with a non-nil span for a parse failure and for a lex failure - a test that
      loops over all six is the honest form of this criterion
- [x] `compile/1` and `compile_with_spans/1` return the **same** span for the
      same failing source, proving the span is not gated on the mode
- [x] `Predicator.evaluate/3`, `Predicator.execute/3`, and
      `Predicator.context_location/3` return span-bearing `ParseError`s for a
      parse failure
- [x] The Phase 2 test asserting `span: nil` on the compile arm is inverted, not
      deleted - it becomes the assertion that the span is present
- [x] Doctests pass, including the new `error.span` examples
- [x] `grep -rn 'never a span' lib/` returns nothing
- [x] `mix quality` reports no coverage regression below the 90% floor for
      `lib/predicator.ex` or `lib/predicator/errors/`
- [x] `git diff --stat` names no file under `conformance/` and no change to the
      ISA version line in `docs/isa.md`

#### Manual Verification:
- [ ] The CHANGELOG's two entries read as one coherent 8.0 story rather than as
      two independent breaks - a reader migrating should see the compile arm
      becoming a struct and that struct gaining a span as one migration
- [ ] The `@doc` paragraph repeated across the six compile functions is
      genuinely identical in all six, as it is today
- [ ] A host rendering `"#{e.message} at line #{l}, column #{c}"` still gets the
      same sentence; the span is purely additive to what it reads

**Implementation Note**: Use `mix quality --profile loop` between edits; run the
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, the Automated Verification gates advancement and
Manual Verification items are deferred to the end.

---

## Testing Strategy

### Unit Tests:

- `test/predicator/errors/parse_error_test.exs` - `new/3` leaves `:span` `nil`;
  `new/4` stores it; `put_position/2` with a span populates both `:span` and
  `:position`; with a point it populates only `:position`.
- `test/predicator/parser_test.exs` - the span of a single-token failure equals
  that token's extent, checked on a multi-character token; the 6-element
  `:string` token shape; the point/span-start invariant; end-of-input failures
  on single-line and multi-line sources; the defensive `nil` branch reached by
  passing a hand-built token list to `Predicator.Parser.parse/2`.
- `test/predicator/lexer_test.exs` - the one-character span for each
  "Unexpected character" site; the unterminated-literal span landing on the
  opening delimiter.
- `test/predicator_test.exs` - all six compile entry points return a span-bearing
  `ParseError`; `compile/1` and `compile_with_spans/1` agree on the span for the
  same source.

Edge cases that actually bite, and are therefore named rather than left to
judgment: a failure on the very first token (span starts at `{1, 1}` and is not
zero-width); a failure on the very last token; end of input on an empty source;
end of input immediately after a newline; a lexical failure at the last
character; a `:string` token failure, which is the only 6-element token shape.

### Integration Tests:

`test/predicator/integration/` gains end-to-end cases going through
`Predicator.evaluate/3` and `Predicator.execute/3` with unparseable source,
asserting the returned `%ParseError{}` carries both `:position` and `:span` and
that the two agree. These are the cases that prove the span survives the whole
façade rather than only the compile helpers - which is the acceptance criterion
"in every compile mode, not only the `_with_spans` entry points" stated as
behaviour a host can observe.

### Manual Testing Steps:

1. In `iex -S mix`, run `Predicator.compile("score > ")` and confirm the error's
   `:span` is a zero-width span at the end of the source and `:position` is its
   start.
2. Run `Predicator.compile("score >> 5")` and confirm the span covers exactly
   the `>>` token, not the whole expression and not one character.
3. Run the same two sources through `Predicator.compile_with_spans/1` and
   confirm byte-identical error values - the mode must make no difference.
4. Run `Predicator.parse_program("if x {\n  y = \n}")` and confirm the reported
   position is on line 2 or 3, never line 1.
5. Format the old sentence by hand from `:message` and `:position` and confirm
   it matches what 7.0.0 produced for the same source.

## References

- Bead: `px-dmt`
- Governing ADR: `docs/adr/0015-compile-errors-are-structured-values.md`,
  especially "Parse-error spans: what would have to happen first" (lines 120-154)
  and "What this decision does and does not change about the instruction set"
- Related ADRs: `docs/adr/0004-no-eval-errors-are-values.md` (errors are
  values), `docs/adr/0003-the-elixir-implementation-leads-the-isa.md` (what a
  change owes the ISA - here, nothing),
  `docs/adr/0009-the-compiled-envelope-carries-the-position-table.md` (spans as
  a side table, and why entry points move as a family)
- Span type and its exclusive-end convention:
  `lib/predicator/types.ex:129-152`
- The helper this reuses: `lib/predicator/parser.ex:1493-1523`
  (`token_start/1`, `token_end/1`, `token_span/1`)
- The `:eof` sentinel: `lib/predicator/lexer.ex:172`
- The immediately preceding bead's plan, whose compile-arm work this extends:
  `docs/plans/260814-px-d71-structured-compile-errors.md`
- Prior work on parse-error positions:
  `docs/plans/260805-px-tbv.7-parse-error-position.md`,
  `docs/plans/260805-px-3kr-position-spans.md`,
  `docs/plans/260808-px-4nz-ast-point-position.md`
- Project extension read for this plan: `.claude/wurk/plan.md`

## Open Questions (resolved unattended)

This plan was authored in an unattended session with no human available to
consult. Each question below would normally have been asked; the answer taken is
recorded with it so the decision is reviewable rather than invisible. None of
them is left open - the plan above is written against the chosen answer.

1. **5-tuple, or a struct at the parser boundary?** ADR-0015 step 2 sketches
   both ("a 5-tuple, or an error term carrying a span"). *Chosen: the 5-tuple.*
   It appends rather than restructures, so the ~100 pass-through clauses and
   `@spec` lines change by one element; it keeps `Parser` and `Lexer` free of
   any dependency on `Predicator.Errors`, which is how those modules are built
   today; and it keeps the positional read of `line` and `column` working. A
   struct at the parser boundary is a larger reshape that ADR-0015 did not ask
   for, and it can still be done later on its own major version.
2. **Does this bead need its own major version, or does it ride 8.0?** The bead
   description says "It needs its own major version". *Chosen: it rides the
   already-open 8.0.* `mix.exs` is at 7.0.0 and `## [Unreleased]` already holds
   ADR-0015's compile-arm break, so 8.0 is unreleased and not yet cut. ADR-0015's
   own consequence is explicit: "The 8.0 release should carry any other queued
   façade break with it - a major version is the scarce resource here, not the
   edit." Charging consumers two migrations one release apart for two halves of
   one decision is what that consequence exists to prevent. The bead's sentence
   is satisfied either way: it does need a major, and 8.0 is one.
3. **What span should a lexical error carry?** *Chosen: one character at the
   reported position* - the offending character for the "Unexpected character"
   family, the opening delimiter for an unterminated or malformed literal.
   Spanning the whole unterminated literal to the end of source would be a
   better caret in one case, but it requires widening the private `take_*`
   helpers' `{:error, binary()}` returns to carry a consumed length, which is
   the lexer redesign ADR-0015 says this work does not need. Refining it later
   is compatible: the plan deliberately keeps span assertions out of the bulk
   test edits so a refinement touches few tests.
4. **Keep or delete the defensive `nil ->` clauses?** The lexer's `:eof`
   sentinel makes them near-unreachable, and `lib/predicator/parser.ex:537-539`
   already calls them defensive. *Chosen: keep them, and give them a correct
   position.* Deleting fourteen defensive branches is a behaviour question of
   its own (a hand-built token list is a supported input to the public
   `Predicator.Parser.parse/2`), and it would be doing it for coverage reasons
   inside a bead about spans.
5. **Does Phase 2 or Phase 4 put the span on the struct?** *Chosen: Phase 4,
   with Phase 2 deliberately discarding it.* Phase 2 must widen the compile
   helpers anyway to keep the gate green; having them keep calling
   `ParseError.new/3` costs nothing, preserves the bead's four-step order, and
   leaves Phase 4 a real, testable change instead of a documentation pass. It is
   also exactly the intermediate state ADR-0015 describes as "a complete and
   honest value".
6. **Should `docs/architecture.md`'s error-handling contract be corrected here?**
   *Chosen: no.* ADR-0004 records that it is already wrong and names px-mis as
   the bead that owns it. Fixing it inside this branch would collide with that
   work and would put an `area:docs` change into a bead labeled `area:api` and
   `area:lexer-parser`.

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] Every existing `ParseError.new/3` call site still compiles and returns a
      value whose `:span` is `nil` - confirmed by reading the five sites in
      `lib/predicator.ex` and two in `lib/predicator/context_location.ex`
- [ ] No existing test that pattern-matches a whole `%ParseError{}` literal
      breaks on the new field
- [ ] The moduledoc example is accurate about `:span` being `nil` at this point
      in the sequence

**Implementation Note**: Use `mix quality --profile loop` between edits; run the
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, the Automated Verification gates advancement and
Manual Verification items are deferred to the end.

---

### Phase 2

- [ ] No pass-through clause silently reordered `line`, `column`, and `span` -
      spot-check the collapsed `= error` rewrites in the deeply nested regions
      (`lib/predicator/parser.ex:1015-1043`, `1240-1330`, `1640-1720`)
- [ ] A multi-line string literal's failure produces a span that is wrong in the
      same way AST node spans are already wrong for it (`token_end/1` computes
      `col + len` regardless of newlines) - consistency with existing behaviour
      is the bar, not correctness that AST spans do not have
- [ ] The lexer's one-character span rule reads sensibly on an unterminated
      string: the caret lands on the opening quote

**Implementation Note**: Use `mix quality --profile loop` between edits; run the
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, the Automated Verification gates advancement and
Manual Verification items are deferred to the end.

---

### Phase 3

- [ ] The reported end-of-source column is one past the last character, matching
      the exclusive-end convention `Predicator.Types.span/0` documents
- [ ] A source ending in trailing whitespace or a newline reports a position a
      human would call "the end", not a surprising interior point
- [ ] The `nil`-branch tests genuinely exercise the branch rather than falling
      through to the `:eof` clause - confirmed by temporarily breaking the
      helper and seeing them go red

**Implementation Note**: Use `mix quality --profile loop` between edits; run the
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, the Automated Verification gates advancement and
Manual Verification items are deferred to the end.

---

### Phase 4

- [ ] The CHANGELOG's two entries read as one coherent 8.0 story rather than as
      two independent breaks - a reader migrating should see the compile arm
      becoming a struct and that struct gaining a span as one migration
- [ ] The `@doc` paragraph repeated across the six compile functions is
      genuinely identical in all six, as it is today
- [ ] A host rendering `"#{e.message} at line #{l}, column #{c}"` still gets the
      same sentence; the span is purely additive to what it reads

**Implementation Note**: Use `mix quality --profile loop` between edits; run the
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, the Automated Verification gates advancement and
Manual Verification items are deferred to the end.

---
