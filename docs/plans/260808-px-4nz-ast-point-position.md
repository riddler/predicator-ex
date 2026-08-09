# Property and Bracket Access Point Positions Implementation Plan

## Overview

Move the point position of `{:property_access, object, property, pos}` off the
`.` token and onto the property-name token, and the point position of
`{:bracket_access, object, key, pos}` off the `[` token and onto the start of
the key expression. Span-mode annotations do not change. Beads issue: px-4nz
(discovered from px-ids).

This closes the one-column gap px-ids measured and recorded: a store failure on
`a.b` in `a = {"b": 1}; a.b.c = 2` lands at column 16 (the `.`) rather than the
bead's ideal 17 (`b` itself), because the segment table blames the
`property_access` node and that node's point position is the accessor rather
than the thing being accessed.

## Current State Analysis

### Where the positions are built

Both nodes are constructed in `parse_postfix_operations/2`,
`lib/predicator/parser.ex:945-1002`:

- `lib/predicator/parser.ex:950-959` - bracket access. The `:lbracket` token's
  `{line, col}` is passed as `loc/3`'s point argument; the span closure is
  `{node_start(expr), token_end(close)}`.
- `lib/predicator/parser.ex:977-988` - property access. The `:dot` token's
  `{dot_line, dot_col}` is the point argument; the span closure is
  `{node_start(expr), token_end(name_token)}`.

`loc/3` (`lib/predicator/parser.ex:1146-1149`) selects between the two:

```elixir
defp loc(%{spans?: false}, point, _span_fun), do: point
defp loc(%{spans?: true}, _point, span_fun), do: span_fun.()
```

The point argument is an ordinary eager argument; only the span is lazy. The
helpers that matter are `token_start/1` (`parser.ex:1155-1157`), `token_end/1`
(`parser.ex:1161-1162`), and `node_start/1` (`parser.ex:1187-1188`), whose own
comment says it is *"Only correct in span mode, where a child's trailing slot is
its span."*

### Who consumes these positions

- `lib/predicator/visitors/instructions_visitor.ex:185-189` annotates the
  emitted `["access", property]` instruction with the `property_access` node's
  trailing slot; `:217-225` annotates `["bracket_access"]` with the
  `bracket_access` node's slot. Neither inspects *what* the position names -
  they forward it into the `positions` table.
- `location_segments/2` (`instructions_visitor.ex:390-397`) annotates a dotted
  segment's `["lit", property]` instruction with the `property_access` node's
  own position; a bracket segment's instructions come from
  `visit_annotated(key, opts)` and the `bracket_access` node's own position is
  discarded (`_position`).
- `location_segment_annotations/1` (`instructions_visitor.ex:411-419`) is the
  per-segment table px-ids added. A dotted segment's annotation is the
  `property_access` node's own annotation; a **bracket** segment's annotation is
  `node_annotation(key)` - the key expression's own slot, explicitly *not* the
  `bracket_access` node's. The comment at `:399-410` states the dependence:
  *"the `property_access` node for a dotted segment (its point position is the
  `.` ...)"*.
- `lib/predicator/context_location.ex` reads no positions at all - every clause
  binds the trailing slot as `_position` (`:220`, `:225`, `:234`, `:250-299`,
  `:312-356`).
- `lib/predicator/errors/**` carries `:position`/`:span` fields but never fills
  them from an AST node directly. `Predicator.Errors.put_position/2`
  (`lib/predicator/errors.ex:41-56`) is the single generic setter.
- `lib/predicator/evaluator.ex:358-375` (`attach_position/2`) stamps
  `Map.get(positions, ip)` onto an error; `:1456-1470` (`located/3` and
  `segment_annotation/2`) stamps the per-segment annotation for a store
  failure.

So the change is confined to the parser: every consumer reads the trailing slot
structurally and none needs a code change. What the consumers *do* need is
comment and doctest updates where they assert the old column.

### Measured blast radius

The change was applied experimentally to `parse_postfix_operations/2`, the full
suite run, and then reverted. Result: **14 failures across 7 files**, out of
367 doctests + 2071 tests. `mix credo --strict`, `mix format --check-formatted`,
and `mix dialyzer` were all clean under the patch.

| File | Failures | What moves |
|---|---|---|
| `test/predicator/parser_positions_test.exs:158` | 1 | `a[0][1]` inner `{1,2}`→`{1,3}`, outer `{1,5}`→`{1,6}`; test name says "points at its opening bracket" |
| `test/predicator/parser_positions_test.exs:163` | 1 | `user.name` `{1,5}`→`{1,6}`; test name says "points at the dot" |
| `test/predicator/parser_spans_test.exs:265` | 1 | point-mode control test `a.b` `{1,2}`→`{1,3}`; test name says "still points a property access at its dot" |
| `test/predicator/visitors/instructions_visitor_positions_test.exs:193` | 1 | `a[0][1]` table `2 => {1,2}`→`{1,3}`, `4 => {1,5}`→`{1,6}` |
| `test/predicator/visitors/instructions_visitor_positions_test.exs:207` | 1 | `user.name` table `1 => {1,5}`→`{1,6}`; name says "points at the dot" |
| `test/predicator/visitors/instructions_visitor_positions_test.exs:267` | 1 | `user.name = 'Ada'` table `1 => {1,5}`→`{1,6}`; inline comment says "at the dot-property token" |
| `test/predicator/visitors/instructions_visitor_positions_test.exs:370` | 1 | `a.b.c = 1` table `1 => {1,2}`→`{1,3}`, `2 => {1,4}`→`{1,5}`; segment table `[{1,1},{1,2},{1,4}]`→`[{1,1},{1,3},{1,5}]` |
| `test/predicator/visitors/instructions_visitor_positions_test.exs:392` | 1 | `u.x[k+1].z = 2` segment/position tables |
| `test/predicator/execute_test.exs:139` | 1 | `{1,16}`→`{1,17}`; carries a three-line comment naming px-4nz's gap |
| `test/predicator/execute_test.exs:205` | 1 | `compile_program_with_positions("a.b = 1")` segment table `%{3 => [{1,1},{1,2}]}`→`%{3 => [{1,1},{1,3}]}` |
| `test/predicator/compiler_test.exs:266` | 1 | same `a.b = 1` segment table |
| `test/predicator/compiler_test.exs:6` (doctest) | 1 | doctest in `lib/predicator/compiler.ex:107` |
| `test/predicator/visitors/instructions_visitor_test.exs:6` (doctest) | 1 | doctest in `lib/predicator/visitors/instructions_visitor.ex:124` |
| `test/predicator/integration/statements_test.exs:50` | 1 | `{1,16}`→`{1,17}`; comment names the `.` |

Two of the fourteen are doctests, so **two `lib/` files carry the old columns in
their `@doc`**: `lib/predicator/compiler.ex:107` and
`lib/predicator/visitors/instructions_visitor.ex:124`, both showing
`to_instructions_with_segment_positions` on `"a.b = 1"` with
`%{0 => {1,1}, 1 => {1,2}, ...}` and `%{3 => [{1,1},{1,2}]}`.

Files named in the bead's suspicion list that turned out **not** to assert these
columns, verified by the run: `test/predicator/parser_test.exs`,
`test/predicator/parser_edge_cases_test.exs`, `test/predicator_test.exs`,
`test/predicator/evaluator_test.exs`,
`test/predicator/evaluator_edge_cases_test.exs`, and
`test/predicator/integration/spans_test.exs`. The last is the important one: it
confirms the span-mode surface is untouched.

### Conformance corpus

Confirmed, not re-derived: `conformance/corpus/*.json`,
`conformance/manifest.json`, and `conformance/cases/*.json` contain no `"line"`
or `"column"` keys anywhere (`grep -o '"line"\|"column"' conformance/corpus/*.json`
returns nothing). This change therefore does not move the exported
specification, no corpus regeneration is required, and no
`area:conformance` work is in scope.

### ISA

The instruction set is **not** moved by this change. Source positions are
compile-time annotations carried in a side table
(`Predicator.Compiled.positions` / `segment_positions`, ADR-0009), not opcodes
or operands. Every emitted instruction list is byte-identical before and after -
the `a.b = 1` cases above show `[["lit","a"],["lit","b"],["lit",1],["store",2]]`
unchanged with only the annotation map moving. No opcode is added, removed,
renamed, or altered; `docs/isa.md` needs no edit and no ISA version bump is
owed. This plan carries no `## ISA Impact` section for that reason.

### ADRs

No ADR under `docs/adr/` speaks to which token a node blames (`grep -rl "point
position\|property_access" docs/adr/` returns nothing). ADR-0009 governs the
*carrier* of the position table, which this change does not touch. The
convention's only normative statement is `docs/reference/ast.md`'s "Which token
a node blames" table, which is prose this plan updates rather than an ADR that
needs superseding.

## Desired End State

`Predicator.parse/2` and `parse_program/2`, in default (point) mode, give:

```elixir
Predicator.parse("user.name")
#=> {:ok, {:property_access, {:identifier, "user", {1, 1}}, "name", {1, 6}}}

Predicator.parse("a[0][1]")
#=> {:ok, {:bracket_access,
#          {:bracket_access, {:identifier, "a", {1, 1}}, {:literal, 0, {1, 3}}, {1, 3}},
#          {:literal, 1, {1, 6}}, {1, 6}}}
```

and the px-ids worst case reaches its ideal column, verified under the
experimental patch:

```elixir
Predicator.execute(~s(a = {"b": 1}; a.b.c = 2))
#=> {:error, %EvaluationError{reason: "not_a_container", position: {1, 17}}, ctx}
```

Under `spans: true` nothing changes: `Predicator.parse("a.b", spans: true)`
still gives `{{1, 1}, {1, 4}}`, and `a[x + 1]` still gives `{{1, 1}, {1, 9}}`.

Verification: `mix quality` green; `test/predicator/integration/spans_test.exs`
passes without edits (which is the proof span mode did not move); the two
`{1, 17}` assertions in `execute_test.exs` and `integration/statements_test.exs`
pass.

### Key Discoveries

- `loc/3`'s point argument is eager (`lib/predicator/parser.ex:1146-1149`), and
  `node_start/1` is documented as span-mode-only (`parser.ex:1187`). This
  decides design question 1 below on technical grounds, not taste.
- `location_segment_annotations/1` already blames the *key expression* for a
  bracket segment (`instructions_visitor.ex:418-419`), deliberately bypassing
  the `bracket_access` node's own position. That clause must stay as it is.
- The change is parser-local: no consumer branches on which token a position
  names, only comments and doctests do.
- The suite already contains explicit "this plan does not reach column 17"
  comments (`execute_test.exs:140-142`,
  `integration/statements_test.exs:51-53`) planted by px-ids. They are the
  breadcrumbs this bead exists to remove.

## What We're NOT Doing

- **Not changing span-mode annotations.** `bracket_access` keeps
  `node_start(expr)..token_end(close)`; `property_access` keeps
  `node_start(expr)..token_end(name_token)`. No concrete reason to narrow them
  was found: `integration/spans_test.exs` passes untouched under the change,
  and px-ids's D1 already settled that a chain node's span starting at the
  chain root is the intended shape.
- **Not changing `location_segment_annotations/1`'s bracket clause.** It uses
  `node_annotation(key)` and will keep doing so - see decision D1c.
- **Not touching the conformance corpus** (no positions in it) or `docs/isa.md`
  (no opcode moves).
- **Not changing any other node's point position.** `list`, `object`,
  `function_call`, `assignment`, and the operator nodes keep theirs.
- **Not renaming or restructuring the `positions` / `segment_positions`
  tables**, their fields, or any public function.
- **Not cutting a release.** Version bump and changelog promotion are separate,
  human-requested work (CLAUDE.md authority table).

## Implementation Approach

Two phases, split on the `area:` seam the bead already carries: one behavioral
phase (`area:lexer-parser`, `area:visitors`) and one documentation phase
(`area:docs`).

The behavioral phase cannot be subdivided. Changing the parser turns 14 tests
red at once, including two doctests that live in `lib/`, so parser edit +
test updates + `lib/` doctest updates must land as one commit for the gate to be
green at a phase boundary. The documentation phase is genuinely separable: it
edits prose only and turns nothing red on its own.

### Design decisions

**D1. What "the key start" is for `bracket_access` in point mode.**

Decision: the `{line, column}` of the **first token of the key expression** -
the token immediately following `[` - obtained with
`token_start(peek_token(bracket_state))`. Not `node_start(key_expr)`.

Justification:

a. `node_start/1` is not available here. `loc/3`'s point argument is evaluated
   eagerly in *both* modes (`parser.ex:1146-1149`), and in point mode a child
   node's trailing slot holds a `{line, column}`, so `node_start/1`'s
   `elem(pos, 0)` would return an integer line number rather than a position.
   `parser.ex:1187`'s own comment says the helper is "only correct in span
   mode". This is a correctness constraint, not a preference.

b. It is what a reader means by "the key start". Measured under the
   experimental patch: `a[x + 1]` gives the node point `{1, 3}` (the `x`) while
   the key node's own point is `{1, 5}` (the `+`); `a[(1)]` gives `{1, 3}` (the
   `(`) while the key literal's own point is `{1, 4}`; `a[-1]` gives `{1, 3}`
   for both the node and the unary key. Pointing at the first written character
   of the key is stable across all four shapes; pointing at the key node's own
   defining token is not.

c. It composes with, rather than duplicates, `location_segment_annotations/1`.
   That function blames the *key expression node* for a bracket segment
   (`instructions_visitor.ex:418-419`) precisely because the key's value is what
   failed. Making the `bracket_access` node's point the key's first token leaves
   that clause meaningful and correct - the two agree for a simple key and
   differ, correctly, for a compound one (`a[(1)] = 1` should still blame the
   `1`, not the `(`). Switching that clause to the node's own position would be
   a regression, which is why it is explicitly out of scope.

d. It matches how every other point position in the parser is derived - from a
   token via `token_start/1` or a literal `{line, col}` destructured from a
   token, never from a child node.

Note the eof safety: the lexer always emits a trailing `{:eof, line, col, 0,
nil}` token (verified: `Predicator.Lexer.tokenize("a[")` returns three tokens),
so `peek_token/1` never returns `nil` mid-stream and `token_start/1` never sees
`nil`. On the `a[` error path the computed point is discarded before use.
Dialyzer was clean under the patch.

**D2. `docs/reference/ast.md` wording.**

Decision: keep the framing sentence and the table, retarget the two rows, and
rewrite the worked example. The page's rule - *"points at the token that names
the operation, so an error names the thing that failed rather than the start of
the subexpression it failed on"* (`ast.md:132-135`) - is not being repealed; it
is being applied more faithfully. For `user.name`, the thing that failed is
`name`, not the `.` that introduced it, exactly as `a * true`'s failure is the
`*` and not `a`. The edit therefore reads as a refinement of an existing rule
rather than an exception to it, and the page keeps a single rule for a new node
type to follow.

Concretely: `bracket_access` splits out of the `list`, `object` row (they keep
"the opening bracket or brace"), `property_access`'s "the `.`" becomes "the
property-name token", and `ast.md:116-124`'s "column 16 ... not column 17, `b`
itself" paragraph is rewritten to state column 17 with the contrast dropped.
The neighbouring observation that a span-mode caret still lands at the chain
root stays true and stays put - it just now differs from the point-mode caret by
two columns instead of one, which the rewritten paragraph says plainly.

**D3. Whether a CHANGELOG entry is owed.**

Decision: yes, and it takes two edits.

1. A new bullet under `## [Unreleased]` → `### Changed`, because the move is
   user-visible relative to the released 3.8.0: `Predicator.parse/2`'s output
   changes for both node types, the `positions` table's entry for `access` and
   `bracket_access` instructions moves, and any error stamped from those
   instructions moves with it.
2. An in-place correction to the existing px-ids bullet at `CHANGELOG.md:320-337`,
   which currently reads *"reports `position: {1, 16}` - the `.b` that held a
   scalar"*. That bullet is under `## [Unreleased]` and has never shipped, so
   leaving `{1, 16}` in it would publish a number the code does not produce.
   It becomes `{1, 17}` with the prose adjusted from "the `.b`" to the property
   name. The same bullet's `Predicator.execute("a[true] = 1", ...)` → `{1, 3}`
   example is **unchanged and stays** - that position comes from the key
   expression's own annotation, which this change does not move (confirmed: the
   "a bracket key segment's annotation is the key's own token position" test at
   `instructions_visitor_positions_test.exs:385` did not fail under the patch).

---

## Phase 1: Move the point positions and re-pin the suite

### Overview

Change the two construction sites in `parse_postfix_operations/2`, then update
every assertion, test name, inline comment, and doctest that pins the old
column. This is the whole behavioral change; after it, `mix quality` is green
and the px-ids case reports column 17.

### Changes Required:

#### 1. The parser

**File**: `lib/predicator/parser.ex`
**Changes**: In `parse_postfix_operations/2` (`:945-1002`), pass the key's
first token / the property-name token to `loc/3` instead of the accessor token.
Both span closures are byte-identical to what they are today.

```elixir
      {:lbracket, _line, _col, _len, _value} ->
        # Parse bracket access: expr[key]
        bracket_state = advance(state)
        key_token = peek_token(bracket_state)

        case parse_expression(bracket_state) do
          {:ok, key_expr, key_state} ->
            case peek_token(key_state) do
              {:rbracket, _line, _col, _len, _value} = close ->
                location =
                  loc(state, token_start(key_token), fn ->
                    {node_start(expr), token_end(close)}
                  end)
```

```elixir
      {:dot, _dot_line, _dot_col, _len, _value} ->
        # Parse property access: expr.property
        dot_state = advance(state)

        case peek_token(dot_state) do
          {type, _line, _col, _len, property_name} = name_token
          when type in [:identifier, :last_op, :next_op, :ago_op, :from_op, :now_op] ->
            location =
              loc(state, token_start(name_token), fn ->
                {node_start(expr), token_end(name_token)}
              end)
```

Add a short comment at each site recording *why* the point is the accessed thing
rather than the accessor, pointing at `docs/reference/ast.md`, in the style of
the existing `store_annotation/2` comment (`instructions_visitor.ex:348-357`).

The parser's own moduledoc (`parser.ex:50-57`, "Source positions") states the
general rule without naming these two nodes; it needs no edit.

#### 2. The two `lib/` doctests

**Files**: `lib/predicator/compiler.ex` (doctest at `:107`),
`lib/predicator/visitors/instructions_visitor.ex` (doctest at `:124`)
**Changes**: Both show `to_instructions_with_segment_positions` on `"a.b = 1"`.
Update `%{0 => {1, 1}, 1 => {1, 2}, 2 => {1, 7}, 3 => {1, 1}}` to
`1 => {1, 3}`, and `%{3 => [{1, 1}, {1, 2}]}` to `%{3 => [{1, 1}, {1, 3}]}`.
Instructions in both doctests are unchanged.

#### 3. The visitor's segment-annotation comment

**File**: `lib/predicator/visitors/instructions_visitor.ex:399-410`
**Changes**: The comment reads *"the `property_access` node for a dotted segment
(its point position is the `.`, its span runs from the chain root)"*. Replace
"the `.`" with "the property name". The code below it
(`:411-419`) does not change - in particular the bracket clause keeps
`node_annotation(key)` (decision D1c).

#### 4. Test updates - 14 assertions across 7 files

**File**: `test/predicator/parser_positions_test.exs`
- `:158` "bracket access points at its opening bracket, one position per link" →
  rename to name the key start; `{1, 2}`→`{1, 3}`, `{1, 5}`→`{1, 6}`.
- `:163` "property access points at the dot" → rename to name the property
  token; `{1, 5}`→`{1, 6}`.

**File**: `test/predicator/parser_spans_test.exs`
- `:265` "still points a property access at its dot" → rename; `{1, 2}`→`{1, 3}`.
  This is the point-mode control inside the spans file; its neighbours at `:257`
  and `:272` must keep passing untouched.

**File**: `test/predicator/visitors/instructions_visitor_positions_test.exs`
- `:193` `a[0][1]`: `2 => {1, 2}`→`{1, 3}`, `4 => {1, 5}`→`{1, 6}`.
- `:207` "property access points at the dot" → rename; `1 => {1, 5}`→`{1, 6}`.
- `:267` `user.name = 'Ada'`: `1 => {1, 5}`→`{1, 6}`; the inline comment "name at
  the dot-property token" is reworded.
- `:370` `a.b.c = 1`: positions `1 => {1, 2}`→`{1, 3}`, `2 => {1, 4}`→`{1, 5}`;
  segment table `%{4 => [{1,1},{1,2},{1,4}]}`→`%{4 => [{1,1},{1,3},{1,5}]}`.
- `:392` `u.x[k+1].z = 2`: positions and segment table per the new columns;
  the assertion that the segment list stays one entry per segment is the point
  of the test and must still hold.

**File**: `test/predicator/execute_test.exs`
- `:139` `{1, 16}`→`{1, 17}`, and delete the three-line comment at `:140-142`
  ("not column 17, the property name, which this plan explicitly does not
  reach") - it is now false. Replace it with a one-line note that column 17 is
  the property name.
- `:205` segment table `%{3 => [{1,1},{1,2}]}`→`%{3 => [{1,1},{1,3}]}`.

**File**: `test/predicator/compiler_test.exs`
- `:266` segment table `%{3 => [{1,1},{1,2}]}`→`%{3 => [{1,1},{1,3}]}`.

**File**: `test/predicator/integration/statements_test.exs`
- `:50` `{1, 16}`→`{1, 17}`; the comment at `:51-53` naming the `.` is reworded.

#### 5. One new test

**File**: `test/predicator/parser_positions_test.exs`
**Changes**: Add a case pinning the compound-key shape that D1 turns on, since
no existing test distinguishes "first token of the key" from "the key node's own
position":

```elixir
test "bracket access points at the key's first token, not the key node's own token" do
  assert {:ok, {:bracket_access, _base, {:arithmetic, :add, _l, _r, {1, 5}}, {1, 3}}} =
           Predicator.parse("a[x + 1]")

  assert {:ok, {:bracket_access, _b, {:literal, 1, {1, 4}}, {1, 3}}} =
           Predicator.parse("a[(1)]")
end
```

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality`
- [x] `mix test test/predicator/integration/spans_test.exs` passes with **zero
      edits to that file** - the evidence span mode did not move
- [x] `mix test test/predicator/parser_spans_test.exs` passes with only the
      `:265` point-mode control changed
- [x] Coverage stays above the 90% floor in `coveralls.json` (no new branches
      are introduced, so this should be a no-op)
- [x] `git grep -n "points at the dot\|opening bracket, one position"` in
      `test/` returns nothing

#### Manual Verification:
- [ ] `Predicator.decompile/2` still round-trips `user.name` and `a[x + 1]` in
      an `iex -S mix` session. This is the only item here not already pinned by
      an automated assertion: the `{1, 17}` case, the unregressed `{1, 3}` key
      blame, and both span shapes are covered by `execute_test.exs:139`,
      `instructions_visitor_positions_test.exs:385`, and
      `integration/spans_test.exs` respectively, all of which the gate runs.

**Implementation Note**: Use `mix quality --profile loop` between edits; run the
full `mix quality` as the phase gate. In interactive execution, pause here for
human confirmation of the manual items. Under `--loop`, the Automated
Verification block gates advancement and the manual items are surfaced at the
end.

---

## Phase 2: Update the documented convention

### Overview

Bring `docs/reference/ast.md` and `CHANGELOG.md` in line with the behavior
Phase 1 shipped. No Elixir code changes here; per CLAUDE.md a change touching no
Elixir code may commit on review of the diff alone, though the gate is still run
and must be green.

### Changes Required:

#### 1. The "Which token a node blames" table

**File**: `docs/reference/ast.md:137-148`
**Changes**: Split `bracket_access` out of the `list`, `object` row and retarget
`property_access`:

```markdown
| `list`, `object` | the opening bracket or brace |
| `function_call` | the name token |
| `bracket_access` | the first token of the key expression |
| `property_access` | the property-name token |
```

Extend the sentence at `:132-135` so the rule still reads as one rule: an access
node blames the thing being accessed, not the punctuation that introduces it,
which is the same principle that makes `a * true` report the `*`. Keep the
closing "A new node type follows this rule" line at `:148`.

#### 2. The store-segment worked example

**File**: `docs/reference/ast.md:116-124`
**Changes**: The paragraph currently reads *"Because a `property_access` node's
point position is the `.` ..., the segment for `.b` points at column 16 in `a =
{"b": 1}; a.b.c = 2`, the `.` before `b`, not column 17, `b` itself."* Rewrite
it to state that the segment points at column 17, `b` itself, and drop the
contrast. Keep the following sentence about the span-mode caret unchanged in
substance - it is still true that narrowing the span moves only the underline -
and note that the point-mode caret (column 17) and the span-derived caret
(column 15, the chain root) are deliberately different answers to different
questions.

#### 3. The span table

**File**: `docs/reference/ast.md:160-179`
**Changes**: None. `bracket_access` and `property_access` keep their existing
rows verbatim. Called out here so the implementer does not "helpfully" edit
them.

#### 4. CHANGELOG

**File**: `CHANGELOG.md`
**Changes**: Per decision D3, two edits under `## [Unreleased]`:

- Correct the px-ids bullet at `:320-337`: `position: {1, 16}` → `{1, 17}`, and
  "the `.b` that held a scalar" → wording naming the property name `b`. Leave
  the `a[true] = 1` → `{1, 3}` example and every other sentence in that bullet
  alone.
- Add a bullet under `### Changed` (the section already exists at `:339`):

  > **Property and bracket access blame the accessed thing, not the accessor.**
  > A `{:property_access, ...}` node's point position is now the property-name
  > token rather than the `.`, and a `{:bracket_access, ...}` node's is the
  > first token of the key expression rather than the `[`.
  > `Predicator.parse("user.name")` reports `{1, 6}` instead of `{1, 5}`; the
  > position table entry for an `["access", ...]` or `["bracket_access"]`
  > instruction moves with it, and so does any error stamped from one. Spans are
  > unchanged: `spans: true` still runs a chain node from the chain root to the
  > accessor's end. No instruction list, opcode, ISA version, error type, or
  > reason moves.

**File**: `docs/architecture.md`
**Changes**: None. It mentions neither node's point position
(`grep -n "property_access\|bracket_access\|point position" docs/architecture.md`
returns nothing). Recorded so the implementer does not go looking.

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality` (no Elixir changed; the gate is
      run to prove the tree is still green)
- [x] `git grep -n 'point position is the `\.`'` returns nothing across `docs/`
      and `lib/`
- [x] `git grep -n "column 16" docs/` returns nothing (the reference page's old
      worked example)
- [x] `git grep -n "{1, 16}" CHANGELOG.md` returns nothing - the px-ids bullet
      never spells the word "column", so this is the check that actually proves
      the CHANGELOG correction in D3 was made

#### Manual Verification:
- [ ] `docs/reference/ast.md`'s two tables still read as one coherent rule each,
      and a reader adding a new node type can tell which row to fill in
- [ ] The `## [Unreleased]` section describes exactly one behavioral change to
      access positions - the px-ids bullet and the new `### Changed` bullet do
      not contradict each other
- [ ] The reference page's `a = {"b": 1}; a.b.c = 2` example matches what
      `Predicator.execute/1` actually prints

**Implementation Note**: Same gate discipline as Phase 1.

---

## Testing Strategy

### Unit Tests

- `test/predicator/parser_positions_test.exs` - the direct pins on both node
  types' point positions, plus the new compound-key and parenthesized-key case
  that distinguishes D1's choice from the alternative.
- `test/predicator/parser_spans_test.exs` - the point-mode control at `:265`
  moves; every span assertion in the file must pass untouched, which is what
  proves the two modes stayed independent.
- `test/predicator/visitors/instructions_visitor_positions_test.exs` - the
  instruction-level position table and the per-segment table, including the
  computed-key case at `:392` whose invariant (one segment entry per segment,
  not per instruction) must survive.
- Doctests in `lib/predicator/compiler.ex` and
  `lib/predicator/visitors/instructions_visitor.ex`.

### Integration Tests

- `test/predicator/execute_test.exs:139` and
  `test/predicator/integration/statements_test.exs:50` - the px-ids case
  end-to-end, now at `{1, 17}`. These two are the acceptance criterion for the
  bead.
- `test/predicator/execute_test.exs` "a bare instruction list with no segment
  table degrades to ... `position: nil`" must still pass unchanged - the
  degradation path is orthogonal.
- `test/predicator/integration/spans_test.exs` - passes with no edits.

### Manual Testing Steps

1. `iex -S mix`, then `Predicator.execute(~s(a = {"b": 1}; a.b.c = 2))` -
   expect `position: {1, 17}`.
2. `Predicator.execute("a[true] = 1", %{"a" => %{}})` - expect `{1, 3}`,
   unchanged.
3. `Predicator.parse("a[(1)]")` - expect the node at `{1, 3}` and the key
   literal at `{1, 4}`, confirming D1's "first token" reading.
4. `Predicator.parse("a.b", spans: true)` and
   `Predicator.parse("a[x + 1]", spans: true)` - spans unchanged.
5. `Predicator.decompile(ast)` on both - round-trip intact.

## Performance Considerations

None. The bracket-access site adds one `peek_token/1` call (an `Enum.at/2` on
the token list) per bracket access at parse time, and the property-access site
swaps a destructured `{line, col}` for a `token_start/1` call on a token it
already holds. Neither allocates. The span closure in both cases is unchanged
and still lazy, so point mode - the default - pays nothing extra for spans.

## Open Questions

None block implementation. Two judgment calls that a reader might expect to find
open were resolved rather than deferred, and are recorded here so the reasoning
is not re-derived:

1. **Should `location_segment_annotations/1`'s bracket clause
   (`instructions_visitor.ex:418-419`) now be simplified to use the
   `bracket_access` node's own annotation, since the two nearly coincide?**
   No, and deliberately so. They coincide only for a single-token key. For
   `a[(1)] = 1` the node's point is the `(` while `node_annotation(key)` is the
   `1`, and the `1` is what a bad segment value came from. Simplifying would be
   a silent regression on exactly the case the clause was written for. If a
   future reader wants to revisit it, that is a new bead, not this one.

2. **Should span mode narrow to match the more precise point?** No. px-ids's
   D1 already settled that a chain node's span starts at the chain root, and
   `test/predicator/integration/spans_test.exs` passing untouched under the
   experimental patch is the evidence that point and span mode are cleanly
   separable here. The task framing put span changes out of scope "unless the
   plan finds a concrete reason"; none was found.

## References

- Beads issue: `px-4nz` (labels `area:docs`, `area:lexer-parser`,
  `area:visitors`); discovered from `px-ids`
- Predecessor plans: `docs/plans/260808-px-ids-store-segment-position.md`,
  `docs/plans/260808-px-tbv.11-store-failure-position.md`
- Prior research: `docs/research/260808-px-tbv.11-store-failure-position.md`
- Construction sites: `lib/predicator/parser.ex:950-959` (bracket),
  `lib/predicator/parser.ex:977-988` (property)
- Position machinery: `lib/predicator/parser.ex:1146-1149` (`loc/3`),
  `:1155-1162` (`token_start/1`, `token_end/1`), `:1187-1188` (`node_start/1`)
- Consumers: `lib/predicator/visitors/instructions_visitor.ex:185-189`,
  `:217-225`, `:390-397` (`location_segments/2`), `:399-419`
  (`location_segment_annotations/1`); `lib/predicator/evaluator.ex:358-375`,
  `:1456-1470`; `lib/predicator/errors.ex:41-56`
- Documented convention: `docs/reference/ast.md:116-124`, `:130-148`, `:160-179`
- ADR-0009 (`docs/adr/0009-the-compiled-envelope-carries-the-position-table.md`)
  - the carrier of the position table, unchanged by this plan
- ADR-0003 (`docs/adr/0003-the-elixir-implementation-leads-the-isa.md`) - the
  ISA is not moved; see "ISA" under Current State Analysis

## Deferred Manual Verification

Items from a phase's "Manual Verification" checklist that were not run during
automated implementation, recorded here for a human to check off later.

### Phase 1

- [x] `Predicator.decompile/2` still round-trips `user.name` and `a[x + 1]` in
      an `iex -S mix` session. This is the only item here not already pinned by
      an automated assertion: the `{1, 17}` case, the unregressed `{1, 3}` key
      blame, and both span shapes are covered by `execute_test.exs:139`,
      `instructions_visitor_positions_test.exs:385`, and
      `integration/spans_test.exs` respectively, all of which the gate runs.
      Verified live 2026-08-08: both round-trip in point and span mode. The
      only difference found, `a[(1)]` -> `a[1]`, is pre-existing
      `StringVisitor` paren-stripping, unrelated to positions.

### Phase 2

- [x] `docs/reference/ast.md`'s two tables still read as one coherent rule each,
      and a reader adding a new node type can tell which row to fill in.
      Verified live 2026-08-08 - required the prose amendment to "Which token
      a node blames" made in this commit, which states the access-node
      exception and the compound-key coincidence as part of the rule itself.
- [x] The `## [Unreleased]` section describes exactly one behavioral change to
      access positions - the px-ids bullet and the new `### Changed` bullet do
      not contradict each other. Verified live 2026-08-08: every numeric claim
      checked holds - `a = 1; a.b = 2` -> `{1, 8}`, `a[true] = 1` -> `{1, 3}`,
      `a = {"b": 1}; a.b.c = 2` -> `{1, 17}`, `parse("user.name")` -> `{1, 6}`.
- [x] The reference page's `a = {"b": 1}; a.b.c = 2` example matches what
      `Predicator.execute/1` actually prints. Verified live 2026-08-08:
      `Predicator.execute/1` returns "Cannot assign through non-container
      value at 'a.b'" at `position: {1, 17}`, matching the page.
