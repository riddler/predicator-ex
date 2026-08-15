# Misplaced string literal raises CaseClauseError - Implementation Plan

## Overview

`Predicator.compile/1` and friends raise instead of returning an error value
when a string literal appears in a position the parser rejects. The cause is a
token-shape assumption baked into sixteen error and fallback clauses in
`lib/predicator/parser.ex`: they bind a five-element token tuple, and the
`:string` token is the one token that is not five elements. This plan removes
the assumption once - by routing every one of those sites through arity-blind
token accessors and a single error constructor - rather than patching sixteen
sites, and adds a sweep test that drives a misplaced string literal through
every one of them. Bead: px-yoq.

## Current State Analysis

**The reproduction, verified in this worktree at HEAD (f5c3696):**

```
$ mix run -e 'IO.inspect(Predicator.compile("score \"a\""))'
** (CaseClauseError) no case clause matching: {:string, 1, 7, 3, "a", :double, {1, 10}}
    (predicator 7.0.0) lib/predicator/parser.ex:373: Predicator.Parser.parse/2
    (predicator 7.0.0) lib/predicator.ex:733: Predicator.compile/1
```

`Predicator.compile("next \"a\"")` fails too, with a `MatchError` rather than a
`CaseClauseError`, because its site is a destructuring bind rather than a case
clause (`parser.ex:2043`).

**The token shape.** `Lexer.token/0` (`lib/predicator/lexer.ex:38-51`) is a
union of `{type, line, column, length, value}` with one exception:

```elixir
| {:string, pos_integer(), pos_integer(), pos_integer(), binary(), :double | :single,
   {pos_integer(), pos_integer()}}
```

The `:string` token is **seven** elements, not the six the bead's description
records - `bdca2c2` ("Gives the string token its own span end position", px-8he)
added the trailing `end_position` after the bead was written. Both extra slots
are load-bearing: `quote_type` is consumed by `parse_object_key/1`
(`parser.ex:1837`) to preserve `'a'` vs `"a"` for `StringVisitor` round-trips,
and `end_position` exists because a string is the only token that can contain a
raw newline, so `{line, col + length}` is wrong for it
(`parser.ex:1533-1544`).

**The defective sites.** Sixteen clauses bind the five-element shape and are
therefore unreachable for a `:string` token, at current line numbers:

Each row's "reached by" column was **verified at HEAD** by running the source
and reading the `CaseClauseError`'s stack frame, not guessed:

| Line | Function | Message | Reached by |
|---|---|---|---|
| 377 | `parse/2` | Unexpected token ... after expression | `compile(~s\|score "a"\|)` |
| 477 | `finish_program/4` | Unexpected token ... after statement | `compile_program(~s\|x = 1 "a"\|)` |
| 661 | `parse_block/1` | Expected `{` to open a block | `compile_program(~s\|if true "a" { x = 1 }\|)` |
| 703 | `finish_block/4` | Expected `}` to close the block | `compile_program(~s\|if true { x = 1 "a" }\|)` |
| 1283 | `parse_postfix_operations/2` | Expected `]` | `compile(~s\|a[0 "a"]\|)` |
| 1316 | `parse_postfix_operations/2` | Expected property name after `.` | `compile(~s\|a."b"\|)` |
| 1345 | `parse_postfix_operations/2` | Expected a type name after `::` | `compile(~s\|a::"b"\|)` |
| 1450 | `parse_primary_token/2` (`:lparen`) | Expected `)` | `compile(~s\|(1 "a")\|)` |
| 1492 | `parse_primary_token/2` (catch-all) | Expected number, string, ... | **no string can reach it** - see below |
| 1714 | `parse_list/2` | Expected `]` in list | `compile(~s\|[1, 2 "a"]\|)` |
| 1775 | `parse_object/2` | Expected `}` in object | `compile(~s\|{"a": 1 "b"}\|)` |
| 1862 | `parse_object_key/1` | Expected identifier or string for object key | **no string can reach it** - see below |
| 1901 | `parse_function_call/3` | Expected `)` (after arguments) | `compile(~s\|f(1 "a")\|)` |
| 1914 | `parse_function_call/3` | Expected `(` after function name | `Parser.parse/2` on a hand-built token list - see below |
| 2015 | `parse_duration_with_direction/2` | Expected `now` after `from` | `compile(~s\|3d from "a"\|)` |
| 2043 | `parse_relative_date_expression/3` | Expected duration after `next`/`last` | `compile(~s\|next "a"\|)` - `MatchError`, not `CaseClauseError` |

Line 1492 is the broadest: it is the primary-expression fallback, so the
majority of malformed sources land there.

**Three of the sixteen are not reachable by a string literal from source**,
which the sweep design in Phase 2 accounts for rather than papering over:

- `:1492` - a string in primary position is a valid string literal, so
  `1 AND "a"` compiles. Unreachable by a string even through `Parser.parse/2`
  with a hand-built token list, because the `:string` head at `:1393` matches
  first.
- `:1862` - `parse_object_key/1`'s dedicated `:string` clause at `:1837`
  matches first; `{"a": 1}` is a legal object. Also unreachable by a hand-built
  list, for the same reason.
- `:1914` ("Expected `(` after function name") - unreachable from **source** at
  all, whatever the token: `lexer.ex:545-553` and `:243-253` only emit
  `:function_name` / `:qualified_function_name` when a `(` follows, so `len "a"`
  lexes `len` as an identifier. It *is* reachable through the public
  `Parser.parse/2` (`parser.ex:366`), which takes a token list, and a
  hand-built list of `[{:function_name, ...}, {:string, ...}, eof]` raises
  today - verified.

All three are still rewritten. A site whose pattern is wrong about the token
shape is wrong whether or not today's grammar lets a string arrive there, and
a grammar change could let one arrive tomorrow.

Three nearby sites bind the same shape and are **not** defective, and the plan
leaves the first two alone:

- `parser.ex:1301` and `parser.ex:1484` are guarded
  (`when type in [:identifier, :last_op, ...]`, `when kw in [:if_kw, ...]`), so
  no `:string` token can reach either head. Their five-element pattern is a
  correct statement about the token types they accept.
- `parser.ex:1837` is `parse_object_key/1`'s success path, which already has a
  dedicated seven-element `:string` clause immediately above its generic one.
  That is precisely the ad-hoc per-site patch this plan is declining to repeat
  fifteen more times; it stays as it is because it genuinely needs
  `quote_type`.

**The existing arity-blind helpers.** `token_start/1` (`parser.ex:1529-1531`)
and `token_end/1` (`parser.ex:1541-1544`) already solve this problem for
position and span, each with a `:string` clause plus a generic one, and
`token_span/1` (`:1566`) is built from them. Everything the sixteen sites need
beyond those is the token's **type** (element 0) and **value** (element 4) -
both at the same index in either arity.

**How the sites are shaped today.** Every one of them is the same four lines:

```elixir
{type, line, col, _len, value} = token ->
  {:error, "Expected ']' but found #{format_token(type, value)}", line, col,
   token_span(token)}
```

and in the enclosing `case`, a `nil ->` clause sits **below** it, delegating to
`end_of_input_error/2`. The same holds for `parse_primary_token/2`, where
`nil` is a separate function head (`:1501`) below the catch-all head (`:1492`).

**Why it matters.** CLAUDE.md's conventions require errors to be values, never
raised at a leaf. `statifier-ex` embeds `%Predicator.Errors.ParseError{}`
directly (`lib/statifier/compiler/error.ex`) with no rescue, so this surfaces
there as a crash on an ordinary user typo. No statifier-side mirror bead is
known; none is invented here.

## Desired End State

Every parse path returns `{:error, %Predicator.Errors.ParseError{}}` for a
misplaced string literal, and no site in `parser.ex` decides an error's shape
by pattern-matching a token's arity. Verified by:

- `Predicator.compile("score \"a\"")`, `compile_program/1`, and the other
  reproductions in the bead all returning error tuples.
- A sweep test in `test/predicator/parser_string_token_arity_test.exs` with one
  entry per site: a misplaced string literal asserting a `%ParseError{}` value
  for the thirteen sites a string reaches from source, a hand-built token list
  through `Parser.parse/2` for the one that is source-unreachable, and an
  ordinary-arity token asserting the unchanged message for the two a string
  cannot reach by any route (see Phase 2).
- `grep -n '{type, line, col, _len, value}' lib/predicator/parser.ex` returning
  nothing.
- Full `mix quality` green.

### Key Discoveries:

- The `:string` token is seven elements, not six: `lexer.ex:51` and
  `lexer.ex:418,430`. The bead predates `bdca2c2` and says six.
- `token_start/1` and `token_end/1` (`parser.ex:1529-1544`) are already the
  arity-blind accessor pattern this plan extends; the fix is consistency with
  code that is already there, not a new idea.
- `parse_object_key/1` (`parser.ex:1830-1840`) shows what the per-site patch
  costs: a duplicated clause per site, each of which must be revisited if the
  token grows an eighth element.
- The clause-ordering hazard: a bare `token ->` catch-all also matches `nil`,
  so each `nil ->` clause must move **above** it or the compiler emits an
  unreachable-clause warning, which the gate treats as a failure
  (`--warnings-as-errors` via `mix quality`).
- `parser.ex:2043` is a destructuring bind, not a case clause. It raises
  `MatchError`, and it is also unguarded against `nil`; converting it to a
  `case` fixes both.
- `format_token/2` (`parser.ex:1638-1690`) enumerates every token type,
  including `:eof`, with no catch-all clause. Routing all sixteen sites through
  it therefore adds no new way to raise at a leaf - it is the same function
  they already called - but it does mean a future token type owes it a clause,
  which is pre-existing and unchanged by this plan.
- The message-building capture form the plan uses, `&"... #{&1}"`, is valid
  Elixir and was checked in this worktree with
  `elixir -e 'f = &"x #{&1}"; IO.puts(f.("y"))'`.
- ADR-0004 ("No eval; errors are values") is the decision this bug violates:
  a leaf that raises is exactly what it rules out. The fix restores it rather
  than arguing it.
- ADR-0003: this repo is the ISA reference implementation. Nothing here moves
  the ISA - no opcode, instruction, or corpus change - so no `## ISA Impact`
  section applies.
- ADR-0015 ("Compile errors are structured values") fixes the return shape the
  callers already expect: `%Predicator.Errors.ParseError{}`, which
  `Predicator.compile/1` builds from the parser's five-element error tuple.
  Nothing in this plan changes that tuple's shape.

## What We're NOT Doing

- **Not normalizing the `:string` token to five elements.** This was the bead's
  second candidate: fold `quote_type` into the value. It is rejected on three
  grounds. First, it no longer reaches five elements - `end_position` landed in
  `bdca2c2` and is required for a multi-line string's span (px-8he), so
  normalization would produce a six-element token and leave the arity split
  exactly where it is. Second, `Lexer.token/0` is public and documented at
  `lexer.ex:38`, and its `@doc` example at `lexer.ex:157` is a doctest, so the
  change would break any consumer that matches lexer output - a wider blast
  radius than the bug. Third, folding the quote type into the value would make
  the value no longer the string's value, which `format_token(:string, value)`
  and `parse_object_key/1` both rely on. The accessor approach fixes the same
  sixteen sites with no public-surface change.
- **Not adding a source-scanning binding test** that greps `parser.ex` for
  five-element token patterns. Such a test would have to be registered in
  `gate.sabotage.test_roots` in `.claude/wurk.json` (CLAUDE.md), which widens
  this bead from `area:lexer-parser` into `area:skills` for a guard the
  behavioral sweep already provides - the sweep goes red on a seventeenth
  defective site the same way, and does it by observing behavior rather than
  by reading source. If a future token grows an eighth element, the sweep is
  the thing that catches it.
- **Not touching the two guarded five-element patterns** at `parser.ex:1301`
  and `:1484`, nor `parse_object_key/1`'s success clause at `:1837`. They are
  correct as written; rewriting them would be churn in a bug fix.
- **Not changing any error message text.** Byte-identical messages for
  non-string tokens is a property the existing suite already asserts, and
  keeping them identical is what makes the diff reviewable.
- **No opcode, instruction, or corpus change.** The ISA does not move.
- **Not widening the bead's area labels.** px-yoq carries `area:lexer-parser`,
  and Phase 2's changelog entry technically falls under `area:docs`
  (CLAUDE.md's table lists `CHANGELOG.md` there). A one-bullet `Unreleased`
  entry is the repo's standard obligation for any user-facing change rather
  than a second subsystem's worth of work, and it collides with nothing, so
  the label stays as filed. Worth noticing at merge time, per ADR-0005's rule
  that a label is a prediction; not worth serializing the queue over.

## Implementation Approach

Add two one-line accessors, `token_type/1` and `token_value/1`, that read
elements 0 and 4 with `elem/2` and so work for either arity, and one error
constructor, `unexpected_token_error/2`, that takes a token and a function
from the formatted token description to the message. Rewrite each of the
sixteen sites as a bare `token ->` clause delegating to that constructor, with
the enclosing `nil` clause moved above it. After the rewrite no site names the
token's arity at all, so the defect cannot recur at a site - only at a new one
written in the old style, which is what the sweep test is for.

Phase 1 is the fix plus the bead's named reproductions. Phase 2 is the
exhaustive sweep and the changelog entry. The order is forced: a sweep test
written first would be red, and a red gate is not committable, so the phase
that introduces the sweep must be the phase after the one that makes it pass.

## Phase 1: Arity-blind token accessors and the sixteen sites

### Overview

Introduce the accessors and the error constructor, rewrite all sixteen sites
through them, and pin the reproductions the bead names.

### Changes Required:

#### 1. Token accessors

**File**: `lib/predicator/parser.ex`, beside `token_start/1` (around `:1529`)
**Changes**: two accessors that do not care how many elements a token has.

```elixir
# A token's type and value sit at the same index in either token arity -
# `:string` carries two extra trailing slots (quote type, end position) and no
# other token does. Reading them positionally is what lets an error path accept
# any token without a clause per shape; the same reason token_start/1 and
# token_end/1 below have a :string clause instead of the call sites having one.
@spec token_type(Lexer.token()) :: atom()
defp token_type(token), do: elem(token, 0)

@spec token_value(Lexer.token()) :: term()
defp token_value(token), do: elem(token, 4)
```

#### 2. The error constructor

**File**: `lib/predicator/parser.ex`, beside `point_error/3` (around `:1571`)
**Changes**: one constructor every "found an unexpected token" site routes
through. The message is built by a function of the formatted token so that no
call site needs the type or the value itself.

```elixir
# Every "expected X but found Y" failure is this: the token's own point, the
# token's own span, and a message that names it. Taking the token whole rather
# than its destructured parts is the point - a site that never writes a tuple
# pattern cannot be wrong about how many elements a token has.
@spec unexpected_token_error(Lexer.token(), (binary() -> binary())) ::
        {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
defp unexpected_token_error(token, message_fun) do
  {line, col} = token_start(token)
  description = format_token(token_type(token), token_value(token))
  {:error, message_fun.(description), line, col, token_span(token)}
end
```

#### 3. The fifteen case-clause sites

**File**: `lib/predicator/parser.ex` at lines 377, 477, 661, 703, 1283, 1316,
1345, 1450, 1492, 1714, 1775, 1862, 1901, 1914 and 2015
**Changes**: replace the five-element bind with a bare catch-all, and move the
`nil ->` clause above it. For example, at `:1283`:

```elixir
              nil ->
                end_of_input_error(state, "Expected ']' but found end of input")

              token ->
                unexpected_token_error(token, &"Expected ']' but found #{&1}")
```

`parse_primary_token/2` (`:1492`) is the same edit at function-head level: the
`nil` head at `:1501` moves above the catch-all head, and the catch-all head
becomes `defp parse_primary_token(_state, token) do`. Its `expected` string is
unchanged.

`parse_object_key/1` (`:1862`) keeps its dedicated seven-element `:string`
clause at `:1837` untouched - that clause is on the **success** path of a
different `case` and is unrelated.

#### 4. The one destructuring-bind site

**File**: `lib/predicator/parser.ex:2043` (`parse_relative_date_expression/3`)
**Changes**: this site raises `MatchError`, not `CaseClauseError`, and has no
`nil` handling. Convert it to a `case`:

```elixir
      {:ok, _other_ast, _final_state} ->
        case peek_token(next_state) do
          nil ->
            end_of_input_error(
              next_state,
              "Expected duration after '#{direction}' but found end of input"
            )

          token ->
            unexpected_token_error(
              token,
              &"Expected duration after '#{direction}' but found #{&1}"
            )
        end
```

#### 5. Regression tests for the bead's reproductions

**File**: `test/predicator/parser_edge_cases_test.exs`
**Changes**: a `describe "a string literal in a rejected position"` block
pinning the four sources the bead names - `score "a"`, `5 "a"`, `true "a"`,
`[1, 2 "ab\ncd"]` - plus `next "a"` for the `MatchError` site, each asserting
`{:error, %Predicator.Errors.ParseError{}}` from `Predicator.compile/1` and,
for the first, from `Predicator.compile_program/1` as well. The multi-line case
also asserts the error's span end line is 2, so the `end_position` slot is
shown to survive the rewrite.

### Success Criteria:

#### Automated Verification:

- [x] Full quality gate passes: `mix quality`
- [x] `mix run -e 'IO.inspect(Predicator.compile("score \"a\""))'` prints an
      `{:error, %Predicator.Errors.ParseError{}}` tuple and does not raise
- [x] `grep -n '{type, line, col, _len, value}' lib/predicator/parser.ex`
      returns no matches
- [x] `grep -c 'unexpected_token_error(' lib/predicator/parser.ex` returns 17
      (one definition plus sixteen call sites)
- [x] Coverage for `lib/predicator/parser.ex` stays above the 90% minimum in
      `coveralls.json`
- [x] No compiler warning about an unreachable clause - every `nil` clause and
      head precedes its catch-all

#### Manual Verification:

- [ ] Error messages for **non**-string tokens are unchanged: compare
      `Predicator.compile("score )")` and `Predicator.compile("[1, 2 3]")`
      against the same calls on `origin/main`
- [ ] The reported line and column for a misplaced string point at the string's
      opening quote, not at the token before it
- [ ] No regression in `StringVisitor` round-trips for single- versus
      double-quoted object keys - `'a': 1` still renders with single quotes
- [ ] `git log -p` on the phase reads as one mechanical substitution, with no
      message text altered

**Implementation Note**: Use `mix quality --profile loop` between edits and the
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

## Phase 2: The sweep test and the changelog

### Overview

Phase 1 fixes the sites. This phase adds the test that would have caught them
as a family, so a seventeenth site written in the old style goes red rather
than hiding behind the other sixteen.

### Changes Required:

#### 1. The sweep test

**File**: `test/predicator/parser_string_token_arity_test.exs` (new)
**Changes**: a module whose `@moduledoc` states the invariant - *no parse path
raises on a misplaced string literal, whatever the token's arity* - and that
tests it two ways.

First, a per-site table. One entry per defective site, each naming the parser
function and the source that reaches it, so a reader can tell which clause a
failure came from. **The sources below were verified against HEAD before the
fix** by running each through `Predicator.compile_program/1` and confirming it
raised - a source that already returns an error value at HEAD is testing some
other clause, which is exactly how the guessed first draft of this table was
wrong. Assignment is `=`, not `:=` (ADR-0002), and a duration is `3d`, not
`3 days`:

```elixir
# {site, entry point, source} - thirteen sites a string reaches from source.
@string_sites [
  {"parse/2 (:377)", :compile, ~s|score "a"|},
  {"finish_program/4 (:477)", :compile_program, ~s|x = 1 "a"|},
  {"parse_block/1 (:661)", :compile_program, ~s|if true "a" { x = 1 }|},
  {"finish_block/4 (:703)", :compile_program, ~s|if true { x = 1 "a" }|},
  {"postfix ']' (:1283)", :compile, ~s|a[0 "a"]|},
  {"postfix property (:1316)", :compile, ~s|a."b"|},
  {"postfix cast type (:1345)", :compile, ~s|a::"b"|},
  {"primary ')' (:1450)", :compile, ~s|(1 "a")|},
  {"parse_list/2 (:1714)", :compile, ~s|[1, 2 "a"]|},
  {"parse_object/2 (:1775)", :compile, ~s|{"a": 1 "b"}|},
  {"function args ')' (:1901)", :compile, ~s|f(1 "a")|},
  {"duration direction (:2015)", :compile, ~s|3d from "a"|},
  {"relative date (:2043)", :compile, ~s|next "a"|}
]

for {site, entry, source} <- @string_sites do
  test "a misplaced string literal is an error value at #{site}" do
    assert {:error, %Predicator.Errors.ParseError{}} =
             apply(Predicator, unquote(entry), [unquote(source)])
  end
end
```

**The remaining three sites need a different entry, and the test says so
rather than faking a case.** All three were verified at HEAD:

- `parse_function_call/3` (`:1914`, "Expected `(` after function name") is
  unreachable from source at all - the lexer emits `:function_name` only when a
  `(` follows - but is reachable through the public `Parser.parse/2` with a
  hand-built token list. Its entry hands `Parser.parse/2`
  `[{:function_name, 1, 1, 3, "len"}, {:string, 1, 5, 3, "a", :double, {1, 8}},
  {:eof, 1, 8, 0, nil}]` and asserts an `{:error, message, line, col, span}`
  tuple. This is the one site where a hand-built list is the only way in, and
  it is also the strongest test of the fix: the token is a real seven-element
  string token.
- `parse_primary_token/2`'s catch-all (`:1492`) and `parse_object_key/1`'s
  generic clause (`:1862`) cannot receive a string token by any route, since
  a `:string` clause matches ahead of each. Their entries use an
  ordinary-arity token - `Predicator.compile(",")` and
  `Predicator.compile("{1: 2}")` - and assert the **existing message text
  verbatim**, so the rewrite is shown not to have altered them.

A comment in the test states all three facts, so a future reader does not
mistake the non-string entries for an oversight.

**A review finding declined, with the evidence:** the plan critic proposed
reaching `:1914` from source with `f "a"`. It does not work, and the reason is
worth recording so nobody retries it - `Predicator.compile(~s|len "a"|)` was
run at HEAD and raised in `parse/2`, not in `parse_function_call/3`, because
`handle_regular_identifier/6` (`lexer.ex:545-553`) only emits `:function_name`
when the next non-whitespace character is `(`. Without one, `len` is an
ordinary `:identifier` and the site is never entered. The hand-built token
list is not a convenience here; it is the only route.

Second, a generative sweep that does not depend on the table being complete: a
fixture list of well-formed sources - expressions, programs, lists, objects,
function calls, casts, property and bracket access, relative dates - each of
which is re-emitted with a string literal spliced in at every whitespace
boundary. Three splices are used, so the `quote_type` and `end_position` slots
are both exercised on an error path: `"zz"`, `'zz'`, and `"a\nb"`.

```elixir
@fixtures [
  ~s|score > 85|,
  ~s|[1, 2, 3]|,
  ~s|{"a": 1, "b": 2}|,
  ~s|f(1, 2)|,
  ~s|a.b[0]::string|,
  ~s|3d from now|,
  ~s|x = 1; y = 2|,
  ~s|if true { x = 1 } else { x = 2 }|
  # ... enough fixtures to clear @minimum_sources below
]
@splices [~s|"zz"|, ~s|'zz'|, ~s|"a\nb"|]
@minimum_sources 200

defp generated_sources do
  for fixture <- @fixtures,
      splice <- @splices,
      {_, i} <- Enum.with_index(String.split(fixture, " ")),
      do: fixture |> String.split(" ") |> List.insert_at(i, splice) |> Enum.join(" ")
end

test "no source with a spliced-in string literal raises" do
  sources = generated_sources()

  # Guards against a fixture list that silently shrinks to nothing - the same
  # vacuous-pass guard isa_sync_test.exs uses for @opcode_count.
  assert length(sources) >= @minimum_sources

  for source <- sources do
    result = Predicator.compile_program(source)

    assert match?({:ok, _}, result) or
             match?({:error, %Predicator.Errors.ParseError{}}, result),
           "compile_program/1 did not return a value for #{inspect(source)}: " <>
             inspect(result)
  end
end
```

A raise inside the loop fails the test with the offending source named, which
is what makes a seventeenth defective site diagnosable rather than merely red.

The generative sweep is the durable half: it is written against no line number
and no clause list, so it keeps working after the parser is refactored, and it
is what catches a site this plan's table missed.

#### 2. Changelog

**File**: `CHANGELOG.md`
**Changes**: an entry under `## [Unreleased]` -> `### Fixed`, describing the
raise-instead-of-return for a string literal in a rejected position, naming
`Predicator.compile/1` and `compile_program/1`, and noting that the fix is
behavioral only: no public type, no error message, and no instruction output
changed.

### Success Criteria:

#### Automated Verification:

- [ ] Full quality gate passes: `mix quality`
- [ ] `mix test test/predicator/parser_string_token_arity_test.exs` passes and
      reports exactly 16 tests from the per-site table - one per site, with no
      site silently dropped
- [ ] The generative sweep exercises more than 200 distinct sources - asserted
      inside the test itself, so an empty fixture list cannot pass vacuously
- [ ] `CHANGELOG.md` has a new bullet under `## [Unreleased]` / `### Fixed`

#### Manual Verification:

- [ ] Each of the sixteen sites is genuinely reached: temporarily replace one
      site's body with `raise "probe"`, run the sweep, confirm it goes red,
      and restore. Repeat across the sites, or at minimum across `parse/2`,
      `parse_primary_token/2`'s catch-all, `parse_list/2` and
      `parse_relative_date_expression/3`
- [ ] Reverting Phase 1's `parser.ex` changes (`git stash` the file) makes the
      sweep red rather than erroring in setup - the test observes the bug, it
      does not merely assert current behavior
- [ ] The changelog entry reads as a user-visible fix, not as an internal
      refactor note

**Implementation Note**: Use `mix quality --profile loop` between edits and the
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

## Testing Strategy

### Unit Tests:

- `test/predicator/parser_edge_cases_test.exs` - the bead's five named
  reproductions, pattern-matching style, asserting `%ParseError{}` values from
  both `compile/1` and `compile_program/1`.
- `test/predicator/parser_string_token_arity_test.exs` - the per-site table and
  the generative splice sweep described in Phase 2.
- `test/predicator/parser_spans_test.exs` - confirm the existing span
  assertions still pass unchanged; the rewrite routes spans through
  `token_span/1`, the same function they already used.
- Edge cases that actually bite: a string containing a raw newline in a
  rejected position (the `end_position` slot), a single-quoted string in a
  rejected position (the `quote_type` slot), a string at the very end of input
  versus followed by more tokens, and an empty string literal `""` whose value
  is falsy-looking but must still format as `string ""`.

### Integration Tests:

`test/predicator/integration/` needs no new file: the failure is a parse-time
one and `Predicator.compile/1` is the boundary the bead names. The two
integration assertions worth having live in the edge-case file above -
`Predicator.evaluate("score \"a\"", %{})` returning an error tuple rather than
raising, since that is the call a host such as statifier-ex actually makes.

### Manual Testing Steps:

1. `mix run -e 'IO.inspect(Predicator.compile("score \"a\""))'` - an
   `{:error, %Predicator.Errors.ParseError{}}` tuple, no stack trace.
2. Repeat for `5 "a"`, `true "a"`, `next "a"`, `{"a": 1 "b"}`, and
   `[1, 2 "ab\ncd"]`. Note that `{"a" "b"}` is *not* a reproduction - it
   already returns "Expected ':' after object key but found string" via the
   dedicated clause at `parser.ex:1837`.
3. `mix run -e 'IO.inspect(Predicator.compile("score > \"a\""))'` - still
   compiles; the happy path is untouched.
4. Compare a handful of non-string error messages against `origin/main` to
   confirm the text is byte-identical.
5. Probe two or three sites with a temporary `raise` to confirm the sweep
   reaches them, then restore.

## References

- Bead: `px-yoq`
- Source: `lib/predicator/parser.ex` (the sixteen sites), `lib/predicator/lexer.ex:38-51`
  (`Lexer.token/0`), `lib/predicator/lexer.ex:418,430` (string token construction)
- Existing arity-blind pattern to model after: `lib/predicator/parser.ex:1529-1566`
  (`token_start/1`, `token_end/1`, `token_span/1`)
- The per-site patch this plan declines to repeat: `lib/predicator/parser.ex:1837`
- Prior plan that introduced the seventh token element: `docs/plans/260814-px-8he-multiline-string-newlines.md`
- Prior plan that added the span argument to these error terms: `docs/plans/260814-px-dmt-parse-error-spans.md`
- Related ADRs: `docs/adr/0004-no-eval-errors-are-values.md` (the rule this bug
  breaks), `docs/adr/0015-compile-errors-are-structured-values.md` (the
  `%ParseError{}` return shape), `docs/adr/0003-the-elixir-implementation-leads-the-isa.md`
  (the ISA does not move here),
  `docs/adr/0005-worktree-parallelism-and-the-area-label-algebra.md`
  (the area-label reasoning behind declining the source-scanning guard)
- Downstream consumer with no rescue: `statifier-ex`, `lib/statifier/compiler/error.ex`

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] Error messages for **non**-string tokens are unchanged: compare
      `Predicator.compile("score )")` and `Predicator.compile("[1, 2 3]")`
      against the same calls on `origin/main`
- [ ] The reported line and column for a misplaced string point at the string's
      opening quote, not at the token before it
- [ ] No regression in `StringVisitor` round-trips for single- versus
      double-quoted object keys - `'a': 1` still renders with single quotes
- [ ] `git log -p` on the phase reads as one mechanical substitution, with no
      message text altered

**Implementation Note**: Use `mix quality --profile loop` between edits and the
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---
