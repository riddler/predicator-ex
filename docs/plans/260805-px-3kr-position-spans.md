# Source Spans Implementation Plan

## Overview

Widen source locations from a point to a span: `Predicator.Parser.parse/2`
gains `spans: true`, and under it every AST node's existing trailing metadata
slot carries `{{start_line, start_col}, {end_line, end_col}}` instead of
`{line, column}`. The span flows unchanged through the compiler's side table
onto runtime errors, which gain an optional `:span` alongside `:position`. Point
positions remain the default and `Predicator.Types.position/0` is untouched.

A point position tells an editor where to put a caret. A span tells it what to
underline, which is what a diagnostic wants: for `a * true` the useful highlight
is the whole expression, not column 3.

Beads issue: px-3kr (`area:api`, `area:lexer-parser`). Follows px-e3g.4, which
shipped point positions, and px-00z, which unified `ParseError`'s line/column
with the position tuple so there is one location representation to widen rather
than two.

## Current State Analysis

**The metadata slot already exists and is opaque to everything downstream.**
px-e3g.4 gave every AST node a trailing `{line, column}` (`Parser.ast/0`,
`lib/predicator/parser.ex:107-124`, plus `object_key/0` at
`lib/predicator/parser.ex:176`). No consumer inspects that value's structure:

- `InstructionsVisitor` pairs it with each emitted instruction and never reads
  it (`lib/predicator/visitors/instructions_visitor.ex:124-245`).
- `Compiler.to_instructions_with_positions/2` maps instruction index to whatever
  the node carried (`lib/predicator/compiler.ex:78-80`).
- `StringVisitor` matches the slot and discards it.
- The evaluator does one `Map.get(positions, ip)` at
  `lib/predicator/evaluator.ex:305` and hands the result to
  `Errors.put_position/2` (`lib/predicator/errors.ex:31-38`), which writes it
  into a struct field without looking at it.

So a span can travel the whole pipeline with no clause changes outside the
parser. This is what makes the change small.

**The lexer already carries the length, and it is the full source extent.**
Tokens are `{type, line, column, length, value}`
(`lib/predicator/lexer.ex:35-40`; `:string` is a 6-tuple with a trailing quote
type, `lib/predicator/lexer.ex:44`). Verified against the real lexer:

| Source | Token | Note |
|---|---|---|
| `score` | `{:identifier, 1, 1, 5, "score"}` | plain extent |
| `"John"` | `{:string, 1, 8, 6, "John", :double}` | length **includes both quotes** |
| `#2024-01-15#` | `{:date, 1, 5, 12, ~D[2024-01-15]}` | length **includes both `#` fences** |
| `and` | `{:and_op, 1, 63, 3, "and"}` | keyword extent |
| `3d8h` | four tokens: `3`,`d`,`8`,`h`, each length 1 | duration is a token sequence |

A leaf's end column is therefore `column + length`, with no lexer change at all.
The `length` element is currently discarded at every parser construction site,
exactly as line and column were before px-e3g.4.

**Closing delimiters are all in hand at the construction site.** An interior
node's span is its first descendant's start to its last descendant's end, except
for the delimited forms, where the last character belongs to a closing token that
is not a descendant. Every one of those is matched at the site that builds the
node:

- `parse_list/2` matches `:rbracket` before building `{:list, ...}`
  (`lib/predicator/parser.ex:1163, 1171`)
- `parse_object/2` matches `:rbrace` (`lib/predicator/parser.ex:1220, 1228`)
- `parse_function_call/3` matches `:rparen`
  (`lib/predicator/parser.ex:1339, 1347`)
- `parse_postfix_operations/2` matches `:rbracket` for bracket access and the
  property-name token for property access (`lib/predicator/parser.ex:918-961`)
- `parse_duration_with_direction/2` matches `:ago_op` and `:now_op`
  (`lib/predicator/parser.ex:1442, 1450`)

**One node needs threading the parser does not do today.** `duration` is built
in `parse_duration_sequence/3` (`lib/predicator/parser.ex:1427, 1433`), which has
consumed its last `:duration_unit` token and kept no reference to it. Both
terminating branches leave the parser state positioned immediately after that
unit, so a `previous_token/1` helper recovers it; no signature changes.

**Four construction sites already receive a position as a parameter** because
their defining token is consumed by the caller: `parse_list/2`,
`parse_object/2`, `parse_function_call/3`, `parse_relative_date_expression/3`,
and `parse_duration_sequence*/3`. That parameter is exactly the span's start, so
it needs no widening.

**Parenthesized expressions build no node.** `parse_primary_token/2` for
`:lparen` returns the inner expression unchanged
(`lib/predicator/parser.ex:1037-1056`), so parentheses are invisible to the AST
and cannot be included in any node's span without inventing a node.

**Error structs.** `EvaluationError` (`lib/predicator/errors/evaluation_error.ex:32`),
`TypeMismatchError` (`.../type_mismatch_error.ex:38`), and
`UndefinedVariableError` (`.../undefined_variable_error.ex:28`) each carry
`:position` typed `Predicator.Types.position() | nil`. `ParseError` is a
parse-time error with its own `line`/`column` and is out of scope, as is
`LocationError`.

**`location` is an overloaded word in this codebase** - `ContextLocation`,
`LocationError`, `Types.location_path/0`, `Types.location_result/0` - so the new
names deliberately avoid it. The union type for the metadata slot is the
existing `t:Predicator.Parser.position/0`, widened in place with a typedoc that
says what it now admits.

### Key Discoveries

- Metadata slot type to widen: `lib/predicator/parser.ex:126-130`
- AST arms and `object_key/0`: `lib/predicator/parser.ex:107-124, 176`
- Token shape, including the 6-tuple string token: `lib/predicator/lexer.ex:35-44`
- Span-agnostic normalizers: `strip_positions/1`
  (`lib/predicator/parser.ex:289-381`) and `ensure_positions/1`
  (`lib/predicator/parser.ex:399-503`) treat the slot as opaque; the only
  structural check on it is the `when is_tuple(pos) or is_nil(pos)` guard on the
  legacy object-key clauses (`lib/predicator/parser.ex:378, 500`), which a span
  satisfies
- Side table producer: `lib/predicator/visitors/instructions_visitor.ex:96-108`
- Error decoration choke point: `lib/predicator/evaluator.ex:284-306`
- `Errors.put_position/2`: `lib/predicator/errors.ex:31-38`
- Public façade: `Predicator.evaluate/3` string path
  (`lib/predicator.ex:151-166`), `compile_with_positions/1`
  (`lib/predicator.ex:336-345`), `parse/1` (`lib/predicator.ex:360-365`)
- `positions:` option plumbing: `lib/predicator.ex:178`,
  `lib/predicator/evaluator.ex:197`
- Existing docs to extend: `docs/architecture.md:215-322` ("Source Positions
  (v3.7.0)"), including the defining-token table at `docs/architecture.md:255-264`
- ADR-0001 keeps the stack VM on ISA v2; the instruction list is the
  cross-language interchange format, and this change does not touch it

### Decisions taken during planning

**1. Spans reuse the existing metadata slot, opt-in per parse.**
`Parser.parse(tokens, spans: true)` puts a span where a point position would
otherwise go. Chosen over adding a second trailing element to every node, which
would repeat px-e3g.4's blast radius - 17 node arms, every visitor clause, and
~500 test assertions - for a value most callers do not want. The bead's
instruction not to widen `Types.position/0` in place is honoured: `position/0`
still means a point, `span/0` is new, and no existing default output changes.

```elixir
# default, unchanged
{:arithmetic, :multiply, {:identifier, "a", {1, 1}}, {:literal, true, {1, 5}}, {1, 3}}

# spans: true
{:arithmetic, :multiply,
  {:identifier, "a", {{1, 1}, {1, 2}}},
  {:literal, true, {{1, 5}, {1, 9}}},
  {{1, 1}, {1, 9}}}
```

The cost, stated plainly: the slot is polymorphic, so a consumer pattern
matching on a node has to know which mode it asked for. That is acceptable
because the mode is a parse-time choice the caller made explicitly, and because
every intermediate stage treats the slot as opaque.

**2. A span is `{start_position, end_position}` with an exclusive end.** The end
points one past the last character, so on a single line `end_col - start_col` is
the length, and a zero-width range is representable. This matches LSP ranges,
which is what an editor consuming this will want. `score` at column 1 spans
`{{1, 1}, {1, 6}}`.

**3. Spans compose from children, not from a generic descendant fold.** Each
construction site states its own rule, because "first descendant's start to last
descendant's end" is wrong for prefix operators (the operator is not a
descendant) and for every delimited form (the closing token is not a
descendant). The full table is in Phase 1.

**4. A parenthesized expression's span excludes its parentheses.** `(a + b)`
gives the `arithmetic` node the span of `a + b`. Parentheses build no node
(decision inherited from the grammar, `lib/predicator/parser.ex:1037`), so
including them would mean attributing another node's characters to this one.
Documented rather than worked around.

**5. Point positions do not move.** A node's position stays the *defining*
token's - the operator for a binary op, the `.` for property access - exactly as
`docs/architecture.md:250-266` documents. A span and a position answer different
questions, and `position: {1, 3}` with `span: {{1,1},{1,9}}` for `a * true` is
the correct pair: blame the `*`, underline the whole thing.

**6. Runtime errors gain `:span`, and `:position` gets the span's start.**
`Errors.put_position/2` grows one clause: handed a span, it sets `:span` to the
span and `:position` to the span's start. A caret-only consumer therefore keeps
working under `spans: true` instead of seeing `position: nil`, and a consumer
that wants underlining reads `:span`. The alternative - a single `:position`
field typed `position() | span()` - makes every existing consumer's pattern
match ambiguous, so it is rejected.

**7. `spans: true` is a no-op for instruction-list input.** `evaluate/3` with a
pre-compiled instruction list has no source to span; such a caller passes
`positions: span_table` from `compile_with_spans/1` instead. Documented on the
option.

**8. Only the two-arity form is added to the public façade.** `Parser.parse/1`,
`Predicator.parse/1`, `Predicator.compile_with_positions/1` and
`Predicator.evaluate/3` all keep their current behaviour byte for byte. The span
path is reached by `spans: true` or by the new
`Predicator.compile_with_spans/1`.

## Desired End State

- `Predicator.parse("a * true", spans: true)` returns
  `{:ok, {:arithmetic, :multiply, {:identifier, "a", {{1,1},{1,2}}}, {:literal, true, {{1,5},{1,9}}}, {{1,1},{1,9}}}}`.
- `Predicator.parse("a * true")` returns exactly what it returns today.
- `Predicator.compile_with_spans("score > 85")` returns
  `{:ok, [["load", "score"], ["lit", 85], ["compare", "GT"]], %{0 => {{1,1},{1,6}}, 1 => {{1,9},{1,11}}, 2 => {{1,1},{1,11}}}}` -
  the instruction list byte-identical to `Predicator.compile/1`'s.
- `Predicator.evaluate("a * true", %{"a" => 1}, spans: true)` returns a
  `TypeMismatchError` with `span: {{1,1},{1,9}}` and `position: {1,1}`.
- `Predicator.evaluate("a * true", %{"a" => 1})` returns the same error with
  `position: {1,3}` and `span: nil`, unchanged from 3.8.
- For every node of every expression in the test corpus, slicing the source
  string by the node's span yields the text a human would underline for that
  node.
- `Parser.strip_positions/1` and `Parser.ensure_positions/1` behave identically
  on a spanned tree as on a positioned one.

Verify by: full `mix quality` green; the source-slicing integration test in
Phase 3; and `Predicator.compile/1` output compared against
`elem(compile_with_spans/1, 1)` over the corpus.

## What We're NOT Doing

- **Not changing the instruction format.** No new opcode, no extra element on
  any instruction. The span table is an Elixir-side companion value exactly as
  the position table is. No Ruby or JavaScript work follows from this bead.
- **Not widening `Types.position/0`.** It stays a point. `Types.span/0` is added
  alongside it, per the bead.
- **Not making spans the default.** `parse/1` and every existing entry point
  keep emitting point positions.
- **Not adding a second metadata element** to any node (decision 1).
- **Not adding spans to `ParseError`.** A parse error has no node, and px-00z
  already settled its representation. A span for the offending token is a
  separate change if it is ever wanted.
- **Not adding spans to `LocationError`**, which is a resolution-time error.
- **Not extending a span over parentheses** (decision 4).
- **Not surfacing spans in rendered error messages.** `:span` is structured data
  for callers; every `message` string is unchanged, so no message assertion
  moves.
- **Not adding an accessor for the metadata slot.** Callers pattern match the
  trailing element, as they do for positions today.
- **Not changing `StringVisitor`, `ContextLocation`, or the evaluator's logic.**
  Their patterns already treat the slot as opaque; only typespecs and docs move.

## Implementation Approach

Phase 1 is the whole functional change and is confined to the parser and
`Types`: the span mode, the per-node span rules, and their tests. Nothing
downstream needs to know, because the metadata slot is opaque - which means
Phase 1 leaves a full `mix quality` green with spans reachable and tested
through `Parser.parse/2` alone.

Phase 2 makes spans reachable from the public façade and lets them land on
errors. It is confined to `lib/predicator.ex`, `lib/predicator/errors.ex`, the
three error structs, and typespec/doc widening in `Compiler`,
`InstructionsVisitor`, and `Evaluator`.

Phase 3 is documentation plus the end-to-end proof that every span names the
right characters.

Splitting Phase 1 finer would leave an intermediate gate red - half the
construction sites spanning and half not means `a + b` reports a span whose end
came from a point position - so the parser's sites move as one unit. Phase 2 and
Phase 3 are each independently green because Phase 1 already made spans
producible.

---

## Phase 1: Spans in the parser

### Overview

`Types.span/0` and `Types.span_table/0` are added, and `Parser.parse/2` learns
`spans: true`: the parser threads a mode flag in its state and, at each of the
~35 construction sites, emits either the defining token's point position
(default) or the node's span.

### Changes Required:

#### 1. Span types

**File**: `lib/predicator/types.ex`
**Changes**: Add `span/0` and `span_table/0` immediately after `position/0` and
`position_table/0` (`lib/predicator/types.ex:145-157`). `position/0` and
`position_table/0` are untouched.

```elixir
@typedoc """
A source span: the start and end of the source text an AST node covers.

The end is **exclusive** - it names the position one past the last character -
so on a single line `end_column - start_column` is the span's length, matching
LSP ranges. The identifier `score` at line 1 column 1 spans
`{{1, 1}, {1, 6}}`.

A span composes two `t:position/0` values; a point position and a span answer
different questions, and both are available. See
`Predicator.Parser.parse/2`'s `:spans` option.
"""
@type span :: {start :: position(), end_exclusive :: position()}

@typedoc """
Maps a 0-based instruction index to the span of the AST node that emitted it.

The span-mode counterpart of `t:position_table/0`, produced by
`Predicator.Compiler.to_instructions_with_positions/2` from an AST parsed with
`spans: true`. Like the position table it is never part of the instruction list,
so interchange and stored compiled artifacts are unaffected.
"""
@type span_table :: %{non_neg_integer() => span()}
```

#### 2. Widened metadata slot type

**File**: `lib/predicator/parser.ex`
**Changes**: `t:position/0` (`lib/predicator/parser.ex:126-130`) is the type of
the trailing slot, and it widens to admit a span. Every `ast/0` arm and
`object_key/0` keep referring to it, so no arm changes.

```elixir
@typedoc """
A node's trailing source metadata.

A `t:Predicator.Types.position/0` by default - the `{line, column}` of the
token that defines the node - or a `t:Predicator.Types.span/0` when the AST was
parsed with `spans: true`, or `nil` when the node was not produced by the
parser. One parse produces one kind throughout; the two are never mixed in a
single tree.
"""
@type position :: Predicator.Types.position() | Predicator.Types.span() | nil
```

The moduledoc gains a `## Source spans` subsection under the existing
`## Source positions` section (`lib/predicator/parser.ex:41-49`) showing the
`a * true` example from Desired End State and stating the exclusive-end rule and
the parenthesis exclusion.

#### 3. Parse option and mode threading

**File**: `lib/predicator/parser.ex`
**Changes**: `parse/1` becomes `parse/2` with a default, and the mode lands in
the parser state map, which is already threaded through every internal function
(`lib/predicator/parser.ex:218-221, 253`).

```elixir
@typedoc """
Internal parser state for tracking position and tokens.

`spans?` records whether the caller asked for spans; it selects what `loc/3`
puts in each node's trailing slot.
"""
@type parser_state :: %{
        tokens: [Lexer.token()],
        position: non_neg_integer(),
        spans?: boolean()
      }

@doc """
Parses a list of tokens into an Abstract Syntax Tree.

## Parameters

- `tokens` - List of tokens from the lexer
- `opts` - Options:
  - `:spans` - when `true`, each node's trailing slot carries a
    `t:Predicator.Types.span/0` covering the source text the node
    spans, instead of the `{line, column}` of the token that defines it.
    Defaults to `false`.

## Examples

    iex> {:ok, tokens} = Predicator.Lexer.tokenize("a * true")
    iex> Predicator.Parser.parse(tokens, spans: true)
    {:ok, {:arithmetic, :multiply, {:identifier, "a", {{1, 1}, {1, 2}}}, {:literal, true, {{1, 5}, {1, 9}}}, {{1, 1}, {1, 9}}}}
"""
@spec parse([Lexer.token()], keyword()) :: result()
def parse(tokens, opts \\ []) when is_list(tokens) do
  warn_deprecated_equals(tokens)

  state = %{tokens: tokens, position: 0, spans?: Keyword.get(opts, :spans, false) == true}
  # ... unchanged from here
end
```

#### 4. The selector and the span helpers

**File**: `lib/predicator/parser.ex`
**Changes**: One selector plus five small helpers, added near `peek_token/1`
(`lib/predicator/parser.ex:1092-1100`).

```elixir
# Selects a node's trailing metadata. The span is computed lazily so that
# position mode - the default - pays nothing for it, and so that the span
# closure may assume what is only true in span mode: that every child node's
# trailing slot already holds a span.
@spec loc(parser_state(), Types.position(), (-> Types.span())) ::
        Types.position() | Types.span()
defp loc(%{spans?: false}, point, _span_fun), do: point
defp loc(%{spans?: true}, _point, span_fun), do: span_fun.()

@spec previous_token(parser_state()) :: Lexer.token() | nil
defp previous_token(%{tokens: tokens, position: pos}), do: Enum.at(tokens, pos - 1)

@spec token_start(Lexer.token()) :: Types.position()
defp token_start({_type, line, col, _len, _value}), do: {line, col}
defp token_start({_type, line, col, _len, _value, _quote_type}), do: {line, col}

# Exclusive: one past the token's last character. The lexer's length is the full
# source extent, quotes and date fences included.
@spec token_end(Lexer.token()) :: Types.position()
defp token_end({_type, line, col, len, _value}), do: {line, col + len}
defp token_end({_type, line, col, len, _value, _quote_type}), do: {line, col + len}

@spec token_span(Lexer.token()) :: Types.span()
defp token_span(token), do: {token_start(token), token_end(token)}

# Only correct in span mode, where a child's trailing slot is its span.
@spec node_start(ast()) :: Types.position()
defp node_start(node), do: node |> elem(tuple_size(node) - 1) |> elem(0)

@spec node_end(ast()) :: Types.position()
defp node_end(node), do: node |> elem(tuple_size(node) - 1) |> elem(1)
```

#### 5. Construction sites

**File**: `lib/predicator/parser.ex`
**Changes**: Each site wraps its current position expression in `loc/3`. The
defining-token position argument is exactly what the site passes today, so the
default path is unchanged by construction.

```elixir
# Before - lib/predicator/parser.ex:815-826
defp parse_multiplication_rest_token(left, state, {:multiply, line, col, _len, _value}) do
  mul_state = advance(state)

  case parse_unary(mul_state) do
    {:ok, right, final_state} ->
      ast = {:arithmetic, :multiply, left, right, {line, col}}

# After
defp parse_multiplication_rest_token(left, state, {:multiply, line, col, _len, _value}) do
  mul_state = advance(state)

  case parse_unary(mul_state) do
    {:ok, right, final_state} ->
      location = loc(state, {line, col}, fn -> {node_start(left), node_end(right)} end)
      ast = {:arithmetic, :multiply, left, right, location}
```

```elixir
# Before - lib/predicator/parser.ex:1022-1024
defp parse_primary_token(state, {:identifier, line, col, _len, value}) do
  {:ok, {:identifier, value, {line, col}}, advance(state)}
end

# After
defp parse_primary_token(state, {:identifier, _line, _col, _len, _value} = token) do
  location = loc(state, token_start(token), fn -> token_span(token) end)
  {:ok, {:identifier, elem(token, 4), location}, advance(state)}
end
```

Span rule per node, with the sites that build it:

| Node | Span start | Span end | Sites (`parser.ex`) |
|---|---|---|---|
| `literal` (integer, float, boolean, date, datetime) | own token | own token end | 992, 998, 1008, 1013, 1018 |
| `string_literal` | own token (opening quote) | own token end (past closing quote) | 1003 |
| `identifier` | own token | own token end | 1023 |
| `object_key` | own token (opening quote if quoted) | own token end | 1310, 1313 |
| `comparison`, `membership` | left operand start | right operand end | 709, 724 |
| `arithmetic` | left operand start | right operand end | 767, 781, 820, 833, 849 |
| `logical_and`, `logical_or` | left operand start | right operand end | 619, 632, 567, 580 |
| `unary`, `logical_not` | operator token | operand end | 875, 889, 660 |
| `list` | `[` token | `]` token end | 1164, 1172 |
| `object` | `{` token | `}` token end | 1221, 1229 |
| `function_call` | name token | `)` token end | 1340, 1348 |
| `bracket_access` | target expression start | `]` token end | 926 |
| `property_access` | target expression start | property-name token end | 950 |
| `duration` | first number token | last `duration_unit` token end | 1427, 1433 |
| `relative_date` (`ago`) | duration start | `ago` token end | 1443 |
| `relative_date` (`from now`) | duration start | `now` token end | 1451 |
| `relative_date` (`next`, `last`) | direction keyword token | duration end | 1476 |

Notes on the four sites that need more than a local wrap:

- **`duration`** (`parse_duration_sequence/3`, `lib/predicator/parser.ex:1414-1436`):
  both terminating branches leave the state positioned immediately after the
  last `:duration_unit`, so the end is `token_end(previous_token(state))`. The
  start is the `position` parameter the caller already threads. Assert this
  explicitly in tests for `3d`, `3d8h`, and the `3d 8h` spacing variant.
- **`relative_date` with `from now`** (`lib/predicator/parser.ex:1445-1451`):
  the position stays the `from` token (unchanged, decision 5) while the span
  ends at the `now` token, which is matched at `lib/predicator/parser.ex:1450`.
- **`bracket_access` and `property_access`**
  (`parse_postfix_operations/2`, `lib/predicator/parser.ex:914-967`): the start
  is `node_start(expr)` from the expression being indexed, so `a[0][1]` gives
  the outer node a span starting at `a` and ending past the second `]`.
- **`list`, `object`, `function_call`**: the closing token is matched at the
  site; empty forms (`[]`, `{}`, `f()`) span both delimiters because the end
  comes from the closing token rather than from a child.

#### 6. Tests

**New file**: `test/predicator/parser_spans_test.exs`
**Changes**: The assertion style is source slicing, so a test states the text it
expects underlined rather than a coordinate pair a reader has to count out:

```elixir
# Slices the source text a span covers. Exclusive end, single line.
defp slice(source, {{line, start_col}, {line, end_col}}) do
  source
  |> String.split("\n")
  |> Enum.at(line - 1)
  |> String.slice(start_col - 1, end_col - start_col)
end

test "a binary operator spans both operands" do
  source = "a * true"
  {:ok, {:arithmetic, :multiply, _left, _right, span} = ast} = parse(source)

  assert slice(source, span) == "a * true"
  assert {:arithmetic, :multiply, _op, _r, {1, 3}} = strip_to_position(source)
end
```

Coverage required, one case each: every leaf type including a single-quoted and
a double-quoted string (quotes inside the span) and a date literal (`#` fences
inside the span); every binary operator; both unary operators and `logical_not`;
empty and non-empty `list` and `object`; object keys in all three styles;
`function_call` including a qualified name, an empty argument list, and a nested
call (`len(upper(name))` - the inner call's span must not leak into the outer);
`bracket_access` chained (`a[0][1]`); `property_access` chained (`a.b.c`);
`duration` in the `3d`, `3d8h`, and `3d 8h` forms; each of the four
`relative_date` directions; a parenthesized expression (span excludes the
parens); a multi-line expression whose span crosses a line boundary; and an
expression with a repeated token (`a + a + a`) proving spans are not shared.

Two invariant tests:

- **Default unchanged**: for a corpus of expressions, `Parser.parse(tokens)`
  returns exactly what it returned before this change - asserted by comparing
  against `Parser.parse(tokens, spans: false)` and against literal expected
  ASTs for a handful of shapes.
- **Position is still the defining token**: under `spans: true` the position is
  gone, but under the default it is unmoved; the existing
  `parser_positions_test.exs` proves this and must not need editing.

**Extended**: `test/predicator/parser_normalization_test.exs` - `strip_positions/1`
and `ensure_positions/1` over a spanned tree: stripping a spanned tree yields the
same bare AST as stripping the positioned one, `ensure_positions/1` leaves a
spanned tree untouched, and a spanned object key round-trips.

### Success Criteria:

#### Automated Verification:
- [ ] Full quality gate passes: `mix quality`
- [ ] `lib/predicator/parser.ex` coverage does not regress from its current
      level, and total coverage stays above the 90% minimum in `coveralls.json`
- [ ] No file outside `lib/predicator/parser.ex`, `lib/predicator/types.ex`, and
      the two parser test files changes in this phase
- [ ] Dialyzer is clean on the widened `t:Predicator.Parser.position/0`

#### Manual Verification:
- [ ] `Predicator.Parser.parse(tokens, spans: true)` on `"a * true"` gives the
      `arithmetic` node a span covering the whole expression, and the default
      parse still gives it position `{1, 3}`
- [ ] `#2024-01-15# > x` gives the date literal a span whose slice includes both
      `#` fences, and `'a'` a span whose slice includes both quotes
- [ ] A two-line expression's top-level node spans from line 1 to line 2

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run the full `mix quality` as the phase gate. In interactive
execution, pause here for manual confirmation from the human that the manual
testing was successful before proceeding to the next phase. In looped
(`--loop`) execution, this phase's Automated Verification gates advancement
automatically (via `/commit --auto`); Manual Verification items are deferred and
surfaced once at the end instead of blocking here.

---

## Phase 2: Spans on the façade and on runtime errors

### Overview

Spans become reachable without touching the parser directly, and a runtime error
carries the span of the instruction that failed.

### Changes Required:

#### 1. Error structs

**Files**: `lib/predicator/errors/evaluation_error.ex`,
`type_mismatch_error.ex`, `undefined_variable_error.ex`
**Changes**: Each gains `:span` in `defstruct` (not in `@enforce_keys`, so it
defaults to `nil`), in `@type t`, and in its `## Fields` moduledoc beside the
existing `:position` bullet.

```elixir
@enforce_keys [:message, :reason]
defstruct [:message, :reason, :operation, :position, :span]

@type t :: %__MODULE__{
        message: binary(),
        reason: binary(),
        operation: atom() | nil,
        position: Predicator.Types.position() | nil,
        span: Predicator.Types.span() | nil
      }
```

The moduledoc bullet, identical in all three:

```text
- `span` - the source text the failing instruction's AST node covers, when the
  program was compiled with spans (optional). `position` names the token to
  blame; `span` is what to underline.
```

#### 2. `Errors.put_position/2` learns spans

**File**: `lib/predicator/errors.ex`
**Changes**: One clause ahead of the existing struct clause, matching a span by
shape, plus a widened `@spec` and two doctests. The name stays `put_position/2`:
it is still "put the source location the evaluator has on hand", and the
codebase's `location` vocabulary is already taken by `ContextLocation` and
`LocationError`.

```elixir
@doc """
Attaches a source position or span to an error struct.

Given a `t:Predicator.Types.position/0`, sets `:position`. Given a
`t:Predicator.Types.span/0`, sets `:span` to the span and `:position` to its
start, so a caller reading only `:position` keeps getting a usable caret when
the program was compiled with spans.

Returns the error unchanged when the location is `nil` or when the value has no
`:position` field, so it is safe to call on any error value - including the
bare-string errors some evaluator paths return internally.

## Examples

    iex> error = Predicator.Errors.EvaluationError.new("boom", "boom")
    iex> Predicator.Errors.put_position(error, {1, 3}).position
    {1, 3}

    iex> error = Predicator.Errors.EvaluationError.new("boom", "boom")
    iex> decorated = Predicator.Errors.put_position(error, {{1, 1}, {1, 9}})
    iex> {decorated.position, decorated.span}
    {{1, 1}, {{1, 1}, {1, 9}}}

    iex> Predicator.Errors.put_position("boom", {1, 3})
    "boom"
"""
@spec put_position(term(), Types.position() | Types.span() | nil) :: term()
def put_position(error, nil), do: error

def put_position(%_struct{} = error, {{_sl, _sc} = start, {_el, _ec}} = span) do
  if Map.has_key?(error, :span) do
    %{error | span: span, position: start}
  else
    put_position(error, start)
  end
end

def put_position(%_struct{} = error, position) do
  if Map.has_key?(error, :position), do: %{error | position: position}, else: error
end

def put_position(error, _location), do: error
```

The `Map.has_key?(error, :span)` fallback matters: a struct with `:position` but
no `:span` - none today, but `ParseError` shows the shape exists - degrades to
the caret rather than raising.

#### 3. Public façade

**File**: `lib/predicator.ex`
**Changes**:

`parse/1` becomes `parse/2`, forwarding to `Parser.parse/2`:

```elixir
@doc """
Parses an expression string into an Abstract Syntax Tree.

Every node carries a trailing `{line, column}` source position. Pass
`spans: true` for a `t:Predicator.Types.span/0` in that slot instead - the
source text the node covers, which is what a diagnostic underlines. Use
`Predicator.Parser.strip_positions/1` to recover the position-free shape
Predicator 3.6 produced.

## Examples

    iex> Predicator.parse("score > 85")
    {:ok, {:comparison, :gt, {:identifier, "score", {1, 1}}, {:literal, 85, {1, 9}}, {1, 7}}}

    iex> Predicator.parse("score > 85", spans: true)
    {:ok, {:comparison, :gt, {:identifier, "score", {{1, 1}, {1, 6}}}, {:literal, 85, {{1, 9}, {1, 11}}}, {{1, 1}, {1, 11}}}}
"""
@spec parse(binary(), keyword()) ::
        {:ok, Parser.ast()} | {:error, binary(), pos_integer(), pos_integer()}
def parse(expression, opts \\ []) when is_binary(expression) do
  case Lexer.tokenize(expression) do
    {:ok, tokens} -> Parser.parse(tokens, opts)
    {:error, message, line, column} -> {:error, message, line, column}
  end
end
```

`compile/1` and `compile_with_positions/1` call `parse/1` internally
(`lib/predicator.ex:307, 337`) and are unaffected by the new default argument.

New `compile_with_spans/1`, a sibling of `compile_with_positions/1`:

```elixir
@doc """
Compiles a string expression to an instruction list plus a source-span side
table.

The instruction list is identical to `compile/1`'s; the table maps each
instruction's 0-based index to the `t:Predicator.Types.span/0` of the AST node
that emitted it. Pass it to `evaluate/3` as `positions:` to get spans on runtime
errors from a pre-compiled program.

## Examples

    iex> {:ok, instructions, spans} = Predicator.compile_with_spans("score > 85")
    iex> instructions
    [["load", "score"], ["lit", 85], ["compare", "GT"]]
    iex> spans
    %{0 => {{1, 1}, {1, 6}}, 1 => {{1, 9}, {1, 11}}, 2 => {{1, 1}, {1, 11}}}
"""
@spec compile_with_spans(binary()) ::
        {:ok, Types.instruction_list(), Types.span_table()} | {:error, binary()}
def compile_with_spans(expression) when is_binary(expression) do
  case parse(expression, spans: true) do
    {:ok, ast} ->
      {instructions, spans} = Compiler.to_instructions_with_positions(ast)
      {:ok, instructions, spans}

    {:error, message, line, column} ->
      {:error, "#{message} at line #{line}, column #{column}"}
  end
end
```

`evaluate/3`'s string path (`lib/predicator.ex:151-166`) forwards the option to
the parser; nothing else in the path changes, because the table it builds
carries whatever the nodes carried:

```elixir
case Parser.parse(tokens, opts) do
```

and its `## Parameters` list gains:

```text
- `:spans` - when `true`, string input compiles with spans instead of point
  positions, so runtime errors carry `:span` and `:position` names the span's
  start. Ignored for instruction-list input, which has no source; such a caller
  passes `positions:` from `compile_with_spans/1` instead.
```

The `:positions` bullet (`lib/predicator.ex:96-99`) is amended to say the table
may hold either positions or spans.

#### 4. Typespec and doc widening

No logic changes; these three keep the pipeline's types honest.

**File**: `lib/predicator/visitors/instructions_visitor.ex`
**Changes**: `t:annotated/0` (`:52`) and `visit_with_positions/2`'s `@spec`
(`:94-95`) admit spans; the moduledoc's `## Source positions` section
(`:9-19`) notes that the paired value is whatever the node carried.

```elixir
@type annotated :: {[binary() | term()], Types.position() | Types.span() | nil}

@spec visit_with_positions(Parser.ast() | Parser.bare_ast(), keyword()) ::
        {[[binary() | term()]], Types.position_table() | Types.span_table()}
```

**File**: `lib/predicator/compiler.ex`
**Changes**: `to_instructions_with_positions/2`'s `@spec` (`:76-77`) and doc
(`:55-75`) admit spans, with a one-line pointer to
`Predicator.compile_with_spans/1`.

**File**: `lib/predicator/evaluator.ex`
**Changes**: the struct's `positions:` field type (`:43`) and the `:positions`
option doc (`:165-167`) admit spans. `attach_error_position/2` (`:304-306`)
needs no change - it passes the table value straight to `Errors.put_position/2`.

#### 5. Tests

**Extended**: `test/predicator/errors/position_test.exs` - `put_position/2` with
a span sets both fields on each of the three structs; with a span against a
struct that has `:position` but no `:span` it falls back to the start; with a
span against `ParseError` and against a bare string it returns them unchanged.

**Extended**: `test/predicator/evaluator_positions_test.exs` - a run seeded with
a span table decorates the failing instruction's error with both `:span` and
`:position`; a partial span table leaves both `nil` for uncovered indices; the
`on_unbound: :error` path (which builds its error at the `load`) reports the
variable's own span.

**Extended**: `test/predicator_test.exs` - `parse/2` with `spans: true`;
`compile_with_spans/1` and the invariant that its instruction list equals
`compile/1`'s; `evaluate/3` with `spans: true` on `"a * true"` reporting
`span: {{1,1},{1,9}}` and `position: {1,1}`; `evaluate/3` without the option
reporting `position: {1,3}` and `span: nil`; `evaluate/3` with an instruction
list and `spans: true` behaving exactly as without it; and
`evaluate(instructions, ctx, positions: span_table)` decorating from a
caller-supplied span table.

### Success Criteria:

#### Automated Verification:
- [ ] Full quality gate passes: `mix quality`
- [ ] `Errors` stays at 100% coverage; the three error struct modules and
      `Evaluator` do not regress; total coverage stays above the
      `coveralls.json` minimum
- [ ] Dialyzer is clean on the widened error struct types and the widened
      table unions
- [ ] Every existing assertion on `:position` still passes unedited - the
      default path is untouched

#### Manual Verification:
- [ ] `Predicator.evaluate("a * true", %{"a" => 1}, spans: true)` reports
      `span: {{1,1},{1,9}}` and `position: {1,1}`
- [ ] The same call without `spans: true` reports `position: {1,3}` and
      `span: nil`
- [ ] Every rendered `message` is byte-identical with and without the option
- [ ] A multi-line expression's runtime error reports a span whose start and end
      lines are both correct

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run the full `mix quality` as the phase gate. In interactive
execution, pause here for manual confirmation from the human that the manual
testing was successful before proceeding to the next phase. In looped
(`--loop`) execution, this phase's Automated Verification gates advancement
automatically (via `/commit --auto`); Manual Verification items are deferred and
surfaced once at the end instead of blocking here.

---

## Phase 3: Documentation and end-to-end verification

### Overview

Record the span rules where the next contributor will look for them, and prove
end to end that every span names the characters a human would underline.

### Changes Required:

#### 1. Architecture reference

**File**: `docs/architecture.md`
**Changes**: A `### Source Spans (v3.9.0, unreleased)` section after the
existing `### Source Positions (v3.7.0)` block (which ends at
`docs/architecture.md:322`), covering:

- the opt-in and the slot it reuses, with the `a * true` before/after pair
- the exclusive-end rule and why (LSP ranges)
- a **span rule table** beside the existing defining-token table
  (`docs/architecture.md:255-264`), one row per node, so a contributor adding a
  node knows both which token to blame and which characters to cover
- the parenthesis exclusion, stated as a known limit rather than left implicit
- that `position` and `span` answer different questions and both are available
  on an error, with `position` set to the span's start under `spans: true`
- that the side table is still an Elixir-side companion value, so ADR-0001's
  interchange guarantee is untouched

The two Common Tasks checklists (`docs/architecture.md:773-793`) each gain a
line: a new node type needs a span rule as well as a defining token.

#### 2. Changelog

**File**: `CHANGELOG.md`
**Changes**: Entries under `## [Unreleased]`. Promoting the section is release
work and is not part of this bead.

- Added: `Predicator.Types.span/0` and `span_table/0`; the `:spans` option on
  `Predicator.Parser.parse/2`, `Predicator.parse/2`, and `Predicator.evaluate/3`
  (string input); `Predicator.compile_with_spans/1`; `:span` on
  `EvaluationError`, `TypeMismatchError`, and `UndefinedVariableError`; span
  handling in `Predicator.Errors.put_position/2`.
- Unchanged, stated so: point positions remain the default at every entry
  point, `Predicator.Types.position/0` is untouched, no AST node gained or lost
  an element, every rendered error message is identical, and the instruction
  list produced by `compile/1` is byte-identical - so stored compiled artifacts
  and cross-language interchange are unaffected.

#### 3. Type inventory note

**File**: `lib/predicator/types.ex`
**Changes**: The instruction-inventory note added by px-e3g.4
(`lib/predicator/types.ex:107-111`) is extended by one sentence: the side table
holds spans instead of positions when the AST was parsed with `spans: true`, and
the instruction format is unaffected either way.

#### 4. End-to-end test

**New file**: `test/predicator/integration/spans_test.exs`
**Changes**: Over a corpus covering every node type:

- **Source cross-check**: walk the spanned AST, and for each node assert that
  slicing the source string by its span yields the expected text - the whole
  subexpression for interior nodes, the token including its quotes or fences for
  leaves. This is the test that would catch an off-by-one in any single rule.
- **Instruction-list identity**: `Predicator.compile/1` output equals
  `elem(Predicator.compile_with_spans/1, 1)` for every corpus expression.
- **Table completeness**: every instruction index has a span entry, and every
  entry's start is less than or equal to its end in reading order.
- **Nesting invariant**: a child's span is contained in its parent's span, for
  every parent/child pair in the corpus. This is the general statement of the
  per-node rules and catches a leak like an inner function call's end
  overrunning its caller's.
- **Runtime cross-check**: for an expression that fails at runtime, the reported
  span slices to the failing subexpression's source text.

### Success Criteria:

#### Automated Verification:
- [ ] Full quality gate passes: `mix quality`
- [ ] Overall coverage stays above the 90% minimum in `coveralls.json`
- [ ] `mix docs` builds with no *new* warnings (this repo carries a
      pre-existing baseline of `CHANGELOG.md` references to removed functions -
      compare the count before and after, do not expect zero)

#### Manual Verification:
- [ ] The span rule table in `docs/architecture.md` has a row for every arm of
      `Parser.ast/0` plus `object_key/0`
- [ ] A reader can tell from the docs alone what span a new node type should
      carry, and that parentheses are excluded by design
- [ ] The `CHANGELOG.md` entry makes clear that nothing changes for a caller who
      does not pass `spans: true`

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run the full `mix quality` as the phase gate. In interactive
execution, pause here for manual confirmation from the human that the manual
testing was successful before proceeding to the next phase. In looped
(`--loop`) execution, this phase's Automated Verification gates advancement
automatically (via `/commit --auto`); Manual Verification items are deferred and
surfaced once at the end instead of blocking here.

---

## Testing Strategy

### Unit Tests

- **Parser spans** (`test/predicator/parser_spans_test.exs`): one case per node
  type, asserted by slicing the source rather than by hand-counted coordinates.
  The cases most likely to be got wrong, each explicitly covered: quoted strings
  and `#`-fenced dates, where the lexer's length includes the delimiters;
  delimited forms, whose end comes from a closing token rather than a child;
  empty `[]`, `{}`, and `f()`, which have delimiters but no children; durations,
  whose end token the parser has already consumed; `from now`, whose span and
  position end at different tokens; nested calls and chained access, where an
  inner span must not leak outward; and a multi-line expression.
- **Default unchanged** (`test/predicator/parser_positions_test.exs`, unedited):
  its continued passing is the proof that the default path did not move.
- **Normalization** (`test/predicator/parser_normalization_test.exs`):
  `strip_positions/1` and `ensure_positions/1` over spanned trees, including a
  spanned object key.
- **Error decoration** (`test/predicator/errors/position_test.exs`):
  `put_position/2` with a span across all three structs, against a struct with
  `:position` but no `:span`, against `ParseError`, and against a bare string.
- **Evaluator** (`test/predicator/evaluator_positions_test.exs`): a span table
  decorates both fields; a partial table leaves both `nil`; the
  `on_unbound: :error` load-site error carries the variable's span.
- **Façade** (`test/predicator_test.exs`): `parse/2`, `compile_with_spans/1`,
  and the three `evaluate/3` shapes from Desired End State.

Edge cases to cover explicitly: an expression that is a single leaf (`"42"`),
where the root's span is the token's; a unary chain (`--a`, `!!a`), where each
level extends the span leftward by one; `a + a + a`, proving spans are not
shared between structurally identical nodes; and an all-literal list, whose
single `["lit", [...]]` instruction takes the whole literal's span - which is
strictly more useful than the point position it collapsed to before.

### Integration Tests

`test/predicator/integration/spans_test.exs`, per Phase 3: source cross-check,
instruction-list identity against `compile/1`, table completeness, the
child-contained-in-parent nesting invariant, and a runtime error whose span
slices to the failing subexpression.

### Manual Testing Steps

1. In `iex`, `Predicator.parse("a * true", spans: true)` and confirm the
   `arithmetic` node's span covers the whole expression while
   `Predicator.parse("a * true")` still reports position `{1, 3}`.
2. `Predicator.parse("x == '#a#'", spans: true)` and confirm the string
   literal's span includes both single quotes.
3. `Predicator.evaluate("a * true", %{"a" => 1}, spans: true)` and confirm
   `span` is `{{1,1},{1,9}}`, `position` is `{1,1}`, and `message` is identical
   to the run without the option.
4. `Predicator.compile_with_spans("a > 1 and b < 2")` and confirm every
   instruction has a span entry and the `jump_if_falsy_or_pop` spans the whole
   expression.
5. Evaluate a two-line expression that fails on line 2 and confirm the span's
   start and end lines.

## Performance Considerations

Position mode - the default - pays for one extra closure allocation per node,
because `loc/3` takes the span computation lazily and never calls it. Span mode
additionally allocates one two-tuple per node and reads two elements out of each
child. Both are on the compile path, which is not the hot path
(`Predicator.compile/1` exists precisely so callers can hoist it out of their
loop), and evaluation is untouched: the evaluator's single `Map.get/2` is on the
error path only.

If the closure allocation ever shows up in a parse benchmark, the fix is to pass
the span's pieces eagerly instead and let position mode discard them - cheaper
per node but it computes spans nobody asked for. Not worth taking pre-emptively,
and the lazy form is what keeps the "children carry spans" invariant confined to
code that only runs in span mode.

## Cross-Language Impact

None. No opcode is added and no instruction gains or loses an element. The span
table is an Elixir-side companion value of exactly the kind px-e3g.4 introduced
for positions, never serialized into the instruction list, so the cross-language
interchange format specified by ADR-0001 is unchanged, as are any compiled
artifacts consumers have already stored. The Ruby and JavaScript siblings need
no work from this bead and may adopt spans independently whenever they want
them.

## References

- Beads issue: `px-3kr`; follows `px-00z`; discovered from `px-e3g.4`
- ADR: `docs/adr/0001-keep-the-stack-vm-revise-the-instruction-set.md` - the
  instruction set is the cross-language interchange format
- Predecessor plan: `docs/plans/260805-px-e3g.4-source-positions.md` - the point
  positions this widens, and the decisions this one inherits
- Position and span docs: `docs/architecture.md:215-322`, defining-token table
  at `docs/architecture.md:255-264`
- Token shape and length: `lib/predicator/lexer.ex:35-44`
- Metadata slot type: `lib/predicator/parser.ex:126-130`
- AST arms and object keys: `lib/predicator/parser.ex:107-124, 176`
- Normalizers: `lib/predicator/parser.ex:289-381, 399-503`
- Side table producer: `lib/predicator/visitors/instructions_visitor.ex:96-108`
- Error decoration: `lib/predicator/evaluator.ex:284-306`,
  `lib/predicator/errors.ex:31-38`
- Façade: `lib/predicator.ex:151-166, 336-345, 360-365`
