# Exact Failing Segment Position for a Store Error Implementation Plan

## Overview

px-tbv.11 moved a store failure's caret off the assignment's `=` and onto the
**lhs root** segment. That is right for `a.b = 2` (the failure is at `a`) and
approximate for every deeper chain: `a = {"b": 1}; a.b.c = 2` fails at `a.b`
but reports the position of `a`.

This plan implements research options **B + C** together, which is what makes
the exact failing segment reportable:

- **Half A (option C)** - produce the failing segment's index `i` in the
  root-first path, at every site that can know it: `Enum.find_index/2` in
  `validate_store_segments/1`, and a path index threaded out of
  `ContextLocation`'s five raise sites and through `wrap_location_error/1`,
  which today discards `details`.
- **Half B (option B)** - a per-store segment position table,
  `%{store_instruction_index => [segment_annotation]}`, built at compile time
  and carried on a **new** field of `%Evaluator{}` and of `%Compiled{}`
  (additive per ADR-0009 - a new field, never a reshaping of `positions`),
  degrading to no entry on the bare-instruction-list path exactly as
  `positions` does.

Beads issue: **px-ids** (`area:api`, `area:evaluator`, `area:visitors`; this
plan also touches `docs/` and `CHANGELOG.md`, so the label set must be widened
with `area:docs` before merge - see Phase 4).

Built on `docs/research/260808-px-tbv.11-store-failure-position.md` (the AS-IS
map and the A-E option table) and on
`docs/plans/260808-px-tbv.11-store-failure-position.md` (the predecessor that
landed option A). Neither is restated here. Where the research describes the
tree *before* px-tbv.11 landed, this plan works from the tree as it is now, on
`9e8c20f`.

## Current State Analysis

### What px-tbv.11 already landed on this branch

`lib/predicator/visitors/instructions_visitor.ex:285-308` now reads:

```elixir
defp visit_annotated({:assignment, lhs, rhs, position}, opts) do
  [{_root_instruction, root_annotation} | _rest] = segments = location_segments(lhs, opts)
  depth = location_depth(lhs)

  segments ++
    visit_annotated(rhs, opts) ++
    [{["store", depth], store_annotation(position, root_annotation)}]
end

defp store_annotation({{_sl, _sc}, {_el, _ec}} = span, _root_annotation), do: span
defp store_annotation(_position, root_annotation), do: root_annotation
```

So the `["store", n]` table entry is the lhs root's point position, or the
assignment node's span under `spans: true`. `TypeMismatchError.unary/5` exists
and `validate_store_segments/1` (`lib/predicator/evaluator.ex:1367-1382`) uses
it with `"a string or an integer"`. `docs/isa.md` section 5's `store` bullet
carries the message clause.

### Verified behaviour on the current tree

Compiled tables, read with `Compiler.to_instructions_with_positions/2`:

```text
a = {"b": 1}; a.b.c = 2      point                      span
  5: ["lit", "a"]   {1, 15}    {{1, 15}, {1, 16}}
  6: ["lit", "b"]   {1, 16}    {{1, 15}, {1, 18}}
  7: ["lit", "c"]   {1, 18}    {{1, 15}, {1, 20}}
  9: ["store", 3]   {1, 15}    {{1, 15}, {1, 24}}

a[true] = 1
  0: ["lit", "a"]     {1, 1}   {{1, 1}, {1, 2}}
  1: ["lit", true]    {1, 3}   {{1, 3}, {1, 7}}
  3: ["store", 2]     {1, 1}   {{1, 1}, {1, 12}}

xs = [1,2]; xs[0-1] = 9
  3: ["lit", "xs"]   {1, 13}   {{1, 13}, {1, 15}}
  4..6: 0, 1, subtract        subtract at {1, 17} / {{1, 16}, {1, 19}}
  8: ["store", 2]    {1, 13}   {{1, 13}, {1, 24}}
```

Three facts from this drive the design.

**Fact 1 - a segment's own annotation already exists and is reachable
structurally.** The lhs chain nodes each carry an annotation slot; the walk
`location_segments/2` uses is the same walk a per-segment annotation list needs
(`instructions_visitor.ex:337-347`).

**Fact 2 - point annotations name the accessor token, not the property name.**
`docs/reference/ast.md:122-124` documents it: a `property_access` node's point
position is the `.`, a `bracket_access` node's is the opening bracket. So for
`a = {"b": 1}; a.b.c = 2` the best point position this plan can produce for the
failing segment `a.b` is **column 16** (the `.`), not the column 17 the bead
calls "ideal". Moving the `property_access` point position onto the property
name is an AST-wide change with its own blast radius and is explicitly out of
scope (see "What We're NOT Doing"). The plan therefore buys one column on that
case, not two, and says so rather than promising 17.

**Fact 3 - span annotations for a chain are cumulative from the root.**
`docs/reference/ast.md:153-154`: a `property_access` span runs from the *target
expression start* to the property-name token end. So segment 1 of `a.b.c` spans
`{{1, 15}, {1, 18}}` - it underlines `a.b`, and its **start is still the chain
root**. This is what makes the span-narrowing decision cheap and safe: narrowing
changes the underline and never the caret.

### What is missing

Research findings 3-6, still true verbatim on this tree:

- `["store", n]`'s `n` is chain **depth** (`location_depth/1`,
  `instructions_visitor.ex:349-360`), so segment index -> instruction index is
  not recoverable from the instruction list.
- `LocationError` records a rendered path string, the segment value, and (for
  `invalid_index`) an unrelated *list* index - never the segment's index in the
  path (`lib/predicator/errors/location_error.ex:140-176`).
- `wrap_location_error/1` (`evaluator.ex:1393-1409`) drops `details` wholesale.
- `validate_store_segments/1` uses `Enum.find/2`, which yields the value, not
  the index.
- `attach_error_position/2` (`evaluator.ex:354-357`) overwrites unconditionally
  via `Errors.put_position/2` (`errors.ex:41-56`), so a position chosen inside
  `execute_store/2` would be clobbered.
- `advance_instruction_pointer/1`'s error clause is guarded
  `when is_struct(error_struct)` (`evaluator.ex:574-575`), so any non-struct
  error value returned by an opcode would raise `FunctionClauseError` today.

## Desired End State

`Predicator.execute/2,3` blames the **exact failing path segment** when one is
identified, and falls back to the store instruction's own entry (the lhs root,
px-tbv.11's answer) when none is.

Point mode:

```text
Predicator.execute("a = 1; a.b = 2; d = 3", %{})
  -> position: {1, 8}    # unchanged: segment 0 IS the lhs root here
Predicator.execute(~s(a = {"b": 1}; a.b.c = 2), %{})
  -> position: {1, 16}   # was {1, 15}; the failing segment is `.b`
Predicator.execute("a[true] = 1", %{"a" => %{}})
  -> position: {1, 3}    # was {1, 1}; the bad segment is the key `true`
Predicator.execute("xs = [1,2]; xs[0-1] = 9", %{})
  -> position: {1, 17}   # was {1, 13}; the failing segment is the key `0-1`
```

Span mode narrows to the same segment (decision D1 below):

```text
Predicator.execute("a = 1; a.b = 2; d = 3", %{}, spans: true)
  -> position: {1, 8}, span: {{1, 8}, {1, 9}}     # was span {{1, 8}, {1, 15}}
```

The caret is unchanged in span mode in every case, because a chain node's span
starts at the chain root (Fact 3); only the underline narrows.

Degradation, unchanged in kind from `positions`:

- A bare instruction list with no `segment_positions:` option -> no segment
  entry -> the store instruction's own `positions` entry is used -> identical to
  px-tbv.11's behaviour.
- A hand-built list with a `positions` table but no segment table -> same.
- No table at all -> `position: nil`, as today.

Every emitted instruction list is **byte-identical**. Error struct types,
`reason`, `expected`, `got`, `operation`, and the
`{:ok, Context.t()} | {:error, struct(), Context.t()}` contract are unchanged.

### Key Discoveries

- The failing segment's path index is derivable at all five `ContextLocation`
  raise sites (research section 5's table), and `do_put/4`'s `trail` is absolute
  within the full path because the interior clause recurses with
  `trail ++ [segment]` (`context_location.ex:369-375`).
- `LocationError.details` is a free-form map that already differs per
  constructor, so the path index rides there. **No new struct field** - which
  answers research Q7 without paying its cost on a struct shared with
  `ContextLocation.resolve/2` and `Context.assign/3`.
- `execute_store/2` runs while `instruction_pointer` is still the store's index
  (`step/1` advances afterwards, `evaluator.ex:330-334`), so the store can look
  its own segment list up by ip with no extra plumbing.
- `test/predicator/evaluator/store_test.exs:139-168` hand-builds
  `positions = %{3 => {5, 9}}` and no segment table, so it takes the fallback
  path and **stays green untouched**. That is the designed-in proof that the
  degradation works.
- The conformance corpus asserts no positions
  (`conformance/cases/statements.json:63-80,96-108`), so `corpus_hash` does not
  move and no regeneration is needed.

## What We're NOT Doing

- **Not** moving `property_access`'s or `bracket_access`'s point position off
  the accessor token onto the property name / key. That is an AST-wide change
  documented at `docs/reference/ast.md:122-124`, would move a large number of
  existing position assertions, and is the only thing standing between this
  plan's column 16 and the bead's "ideal" 17. If it is ever wanted it is its own
  bead (recorded in "Open Questions" and filed in Phase 4).
- **Not** adding a field to `LocationError`. The path index rides in `details`.
- **Not** changing `Errors.put_position/2`'s unconditional overwrite, and **not**
  adding set-if-absent semantics to `attach_error_position/2` (research Q4). The
  store hands its chosen location to the same single stamping point instead.
- **Not** reshaping `Compiled.positions` or changing its meaning (ADR-0009
  forbids it); the segment table is a **new** field.
- **Not** introducing a stack-effect model (research option D / Q8).
- **Not** putting positions into the instruction list (research option E) - the
  one option that would move the ISA, foreclosed by `docs/isa.md` section 6.
- **Not** changing `expected: :string`, any `reason`, any error struct type, or
  the `{:error, error, context}` shape.
- **Not** touching `bracket_access`'s own message defect (px-tmy).
- **Not** regenerating the conformance corpus or editing `docs/isa.md` sections
  4 or 7.

## Implementation Approach

Four phases, each independently gate-verifiable and committable:

1. **Half A** in `LocationError` and `ContextLocation` alone - the path index
   becomes a recorded fact. Nothing consumes it yet, so the phase is a pure
   additive change with its own unit tests.
2. **Half B's carrier** - the compile-time segment table, threaded from the
   visitor through `Compiler`, `Compiled`, `Predicator`, and onto `%Evaluator{}`.
   Still unconsumed, so no behaviour moves and the phase is verifiable on the
   table's shape alone.
3. **The join** - `execute_store/2` resolves segment index + segment table into
   a location and hands it to the stamping point. This is the only phase where
   observable behaviour changes, and every changed assertion lands with it.
4. **Docs, changelog, labels, follow-ups.**

### The mechanism, end to end

**Compile time.** A new private walk in the instructions visitor produces one
annotation per *segment* (not per instruction), root-first:

```elixir
# One annotation per location segment, root-first - the segment-level echo of
# `location_segments/2`, whose list a computed bracket key inflates (`a[k+1]`
# is one segment in several instructions). Its length is `location_depth/1`
# by construction, which is what makes `["store", n]`'s operand an index bound
# for this list.
#
# A segment's annotation is the annotation of the node that produced its
# *value*: the identifier for the root, the `property_access` node for a dotted
# segment (its point position is the `.`, its span runs from the chain root -
# docs/reference/ast.md), and the *key expression* for a bracket segment, since
# the key is what a bad or out-of-range segment value came from.
@spec location_segment_annotations(Parser.ast()) ::
        [Types.position() | Types.span() | nil]
defp location_segment_annotations({:identifier, _name, annotation}), do: [annotation]

defp location_segment_annotations({:property_access, object, _property, annotation}),
  do: location_segment_annotations(object) ++ [annotation]

defp location_segment_annotations({:bracket_access, object, key, _annotation}),
  do: location_segment_annotations(object) ++ [node_annotation(key)]
```

`node_annotation/1` is the existing `statement_position/1`
(`instructions_visitor.ex:329-330`, `elem(node, tuple_size(node) - 1)`) renamed;
it is now used from two places and "statement" no longer describes it. Rename
it and update its one existing call site in `visit_statement/2`.

The store's annotated tuple gains a third element carrying that list:

```elixir
defp visit_annotated({:assignment, lhs, rhs, position}, opts) do
  [{_root_instruction, root_annotation} | _rest] = segments = location_segments(lhs, opts)

  segments ++
    visit_annotated(rhs, opts) ++
    [
      {["store", location_depth(lhs)], store_annotation(position, root_annotation),
       location_segment_annotations(lhs)}
    ]
end
```

`@type annotated` widens to a two-or-three-element tuple. Every consumer of the
annotated list already goes through two functions in this module
(`visit/2:71-77` and `visit_with_positions/2:96-110`), both of which change from
destructuring `{instruction, position}` to `elem/2`, so the widening is
contained to this file.

**The tables.** One private helper builds both from a single walk of the
annotated list, so the two tables cannot disagree about an index:

```elixir
@spec tables([annotated()]) ::
        {[[binary() | term()]], Types.position_table() | Types.span_table(),
         Types.segment_position_table()}
```

`visit_with_positions/2` keeps its exact current return shape by dropping the
third element - **no existing signature changes**. A new
`visit_with_segment_positions/2` returns all three.

**Threading.** `Compiler.to_instructions_with_segment_positions/2` wraps the new
visitor function. `%Compiled{}` gains `segment_positions: %{}` and `new/3`.
`build_compiled_result/1` populates it, so `compile_with_positions/1`,
`compile_with_spans/1`, and `compile_program_with_positions/1` all carry it (an
expression compiles no store, so it is `%{}` there - uniform, not special-cased).
`Predicator.execute/3` and `Predicator.evaluate/3` thread it on the `%Compiled{}`
clause and the source clause, and accept a `:segment_positions` option on the
bare-list clause. `%Evaluator{}` gains `segment_positions: %{}`.

**Run time.** `execute_store/2` already holds the evaluator, so it resolves the
location itself and hands it to the one place that stamps positions:

```elixir
# The store is the one opcode that knows *which part of its own source
# expression* failed: a path index, from `validate_store_segments/1` or from
# the `LocationError`'s details. `positions` is keyed by instruction, so it
# cannot express that; `segment_positions` can, and this is where the two are
# joined. Returning `{:located, error, location}` rather than stamping here is
# deliberate - `attach_position/2` is the single point that stamps a position
# on an evaluator error (`Errors.put_position/2` overwrites unconditionally,
# `errors.ex:41-56`), so a position set here would be clobbered by the store
# instruction's own table entry. The tuple is constructed in this function and
# destructured in `attach_position/2`, and never escapes `step/1`.
@spec located(t(), term(), non_neg_integer() | nil) :: {:error, term()}
defp located(%__MODULE__{} = evaluator, error, index) do
  case segment_annotation(evaluator, index) do
    nil -> {:error, error}
    annotation -> {:error, {:located, error, annotation}}
  end
end

@spec segment_annotation(t(), non_neg_integer() | nil) ::
        Types.position() | Types.span() | nil
defp segment_annotation(%__MODULE__{} = evaluator, index) when is_integer(index) do
  evaluator.segment_positions
  |> Map.get(evaluator.instruction_pointer, [])
  |> Enum.at(index)
end

defp segment_annotation(_evaluator, _index), do: nil
```

`attach_position/2` gains one clause, and `advance_instruction_pointer/1` gains
one pass-through clause (its existing error clause is guarded
`when is_struct(...)`):

```elixir
defp attach_position({:error, {:located, reason, location}}, _before),
  do: {:error, Predicator.Errors.put_position(reason, location)}
```

Falling back to `{:error, error}` whenever there is no annotation is what makes
every degradation path (no table, hand-built list, out-of-range index, `nil`
entry) collapse to exactly px-tbv.11's behaviour with no extra branches.

### Decisions

**D1 - does span mode narrow to match point mode? YES.** The bead names this as
the open question px-tbv.11 declined; this plan decides it.

Reasoning, in the order that settles it:

1. **The caret does not move.** A chain node's span starts at the chain root
   (`docs/reference/ast.md:153-154`, verified above:
   `a.b` in `a.b.c` spans `{{1, 15}, {1, 18}}`). `Errors.put_position/2` derives
   `position` from the span start, so narrowing changes `span` and leaves
   `position` exactly where px-tbv.11 put it. The risk that made px-tbv.11
   decline - moving a caret nobody asked to move - does not exist here.
2. **The underline gets strictly more informative.** `a = {"b": 1}; a.b.c = 2`
   underlines `a.b`, the prefix that actually failed, instead of the whole
   statement `a.b.c = 2`. For the bracket cases it underlines `true` and `0-1`,
   the exact sub-expressions that produced the bad segment values.
3. **Declining would re-open the inconsistency px-tbv.11 closed.** If only point
   mode narrowed, the two modes would once again disagree about which token a
   store failure names - the precise defect px-tbv.11's plan called a "mode
   inconsistency" and fixed. A design whose two modes agree by construction is
   the one that does not need a third bead.
4. **It costs nothing.** The segment table's entries are whatever the AST
   carries: point positions under point mode, spans under `spans: true`. Both
   modes take the same code path, and there is no mode-discriminating clause to
   write (unlike px-tbv.11's `store_annotation/2`, which needed one precisely
   because it was choosing a *different* node's annotation).

The one assertion this moves is `test/predicator/execute_test.exs:128-131`, and
Phase 3 changes it deliberately with the old and new spans both written down.

**D2 - what about errors that identify no segment?** `not_assignable` (empty
path, `["store", 0]`) and `insufficient_operands` (a short stack) name no
segment. They pass `nil` as the index, `segment_annotation/2`'s catch-all
clause returns `nil`, and they keep the store instruction's own entry -
px-tbv.11's answer, unchanged. Both are reachable only from a hand-built
instruction list.

**D3 - `expected`/`got`/`reason` and the `%Compiled{}` shape.** Untouched and
additive respectively, per ADR-0009's rule that a new field is additive and a
reshaping of `positions` is not.

## Phase 1: Record the failing segment's path index

### Overview

Half A. `LocationError` learns to carry a path index in `details`, and
`ContextLocation`'s five raise sites supply it. Nothing consumes it yet.

### Changes Required

#### 1. `LocationError` constructors

**File**: `lib/predicator/errors/location_error.ex`
**Changes**: `not_a_container/3` becomes `not_a_container/4` and
`invalid_index/2` becomes `invalid_index/3`, each taking an optional trailing
`path_index` defaulting to `nil` and putting it in `details` under
`:path_index`. Default arguments keep both call shapes valid, so
`test/predicator/errors/location_error_test.exs` stays green untouched.

```elixir
@doc """
Creates a LocationError for assignment through a non-container value.

Used when a location path traverses a value that is neither a map nor a list,
so intermediate structure cannot be created without destroying existing data.

`path_index` is the failing segment's 0-based index in the root-first location
path, or `nil` when the caller cannot identify one. `Predicator.Evaluator`'s
`store` path joins it with the run's segment-position table to point a store
failure at the segment that failed rather than at the location's root (px-ids).
It is deliberately a `details` key rather than a struct field: this struct is
shared with `Predicator.ContextLocation.resolve/2` and
`Predicator.Context.assign/3`, which have no path to index.
"""
@spec not_a_container(binary(), term(), term(), non_neg_integer() | nil) :: t()
def not_a_container(location, segment, value, path_index \\ nil) do
```

Note in the `invalid_index/3` doc that `:index` (the list index) and
`:path_index` (the segment's index in the path) are unrelated integers - the
research called that collision out explicitly.

#### 2. `ContextLocation`'s five raise sites

**File**: `lib/predicator/context_location.ex`
**Changes**: supply the index at each site. `do_put/4`'s interior clause
recurses with `trail ++ [segment]` (`:369-375`), so a trail length is an
absolute index into the full path.

| Site | Line | Index expression |
|---|---|---|
| `vivify(scalar, _next, trail)` | `:391-393` | `length(trail) - 1` (the trail **includes** the failing segment) |
| `fetch_in(list, index, trail)` negative index | `:404-406` | `length(trail)` |
| `fetch_in(list, key, trail)` non-integer key | `:408-410` | `length(trail)` |
| `set_in(list, index, _v, trail)` negative index | `:422-424` | `length(trail)` |
| `set_in(list, key, _v, trail)` non-integer key | `:426-428` | `length(trail)` |

Add one comment above `do_put/4`'s trail doc noting that the trail is absolute
and therefore doubles as the failing segment's path index.

#### 3. Tests

**File**: `test/predicator/context_location_test.exs`
**Changes**: add a describe pinning `details.path_index` for each of the five
sites, e.g.

```elixir
test "a scalar in the interior records its own path index" do
  assert {:error, %LocationError{type: :not_a_container, details: details}} =
           ContextLocation.put(%{"a" => %{"b" => 1}}, ["a", "b", "c"], 2)

  assert details.path_index == 1
end

test "a negative list index records the segment's path index" do
  assert {:error, %LocationError{type: :invalid_index, details: details}} =
           ContextLocation.put(%{"xs" => [1, 2]}, ["xs", -1], 9)

  assert details.index == -1
  assert details.path_index == 1
end
```

**File**: `test/predicator/errors/location_error_test.exs`
**Changes**: add two tests that the arity-3/arity-2 forms still default
`path_index` to `nil`, so the delegation cannot drift.

### Success Criteria

#### Automated Verification

- [ ] Full quality gate passes: `mix quality`
- [ ] `mix test test/predicator/context_location_test.exs
      test/predicator/errors/location_error_test.exs` is green
- [ ] Every pre-existing test in both files passes **unmodified** - the change
      is additive by default argument
- [ ] All five raise sites are covered by a `path_index` assertion; coverage
      stays above the 90% minimum in `coveralls.json`

#### Manual Verification

- [ ] `ContextLocation.put(%{"a" => %{"b" => 1}}, ["a", "b", "c"], 2)` reports
      `details.path_index == 1` and its `message` is unchanged
- [ ] No error message string anywhere in the suite changed wording

**Implementation Note**: use `mix quality --profile loop` between edits; full
`mix quality` is the phase gate.

---

## Phase 2: Build and thread the segment-position table

### Overview

Half B's carrier. The visitor emits a per-store segment annotation list, a new
table is derived from it, and it is threaded to `%Evaluator{}`. Nothing reads it
yet, so no behaviour moves - which is exactly what makes this phase's gate
meaningful on the table's shape alone.

### Changes Required

#### 1. The type

**File**: `lib/predicator/types.ex`
**Changes**: add `segment_position_table/0` next to `position_table/0` and
`span_table/0` (`:114-148`), with a typedoc in the same voice: keyed by the
`["store", n]` instruction's 0-based index, valued by one annotation per
location segment in root-first order, `nil` for a segment whose node carried no
annotation; never part of the instruction list, so interchange and stored
compiled artifacts are unaffected.

```elixir
@type segment_position_table :: %{
        non_neg_integer() => [position() | span() | nil]
      }
```

#### 2. The instructions visitor

**File**: `lib/predicator/visitors/instructions_visitor.ex`
**Changes**:

- widen `@type annotated` to admit a three-element store tuple, documenting that
  the third element exists only on `["store", n]`;
- rename `statement_position/1` to `node_annotation/1` and update its call site
  in `visit_statement/2`;
- add `location_segment_annotations/1` (body in "Implementation Approach"), with
  a comment recording the length invariant against `location_depth/1` and the
  per-segment annotation rule;
- extend the `{:assignment, ...}` clause to emit the third element;
- change `visit/2` and `visit_with_positions/2` to read via `elem/2`, and
  factor the shared index walk into a private `tables/1`;
- add `visit_with_segment_positions/2` returning
  `{instructions, positions, segment_positions}` with a `@doc`, a `@spec`, and a
  doctest.

Suggested doctest, verified against the current tree:

```elixir
iex> {:ok, program} = Predicator.parse_program("a.b = 1", spans: false)
iex> Predicator.Visitors.InstructionsVisitor.visit_with_segment_positions(program)
{[["lit", "a"], ["lit", "b"], ["lit", 1], ["store", 2]],
 %{0 => {1, 1}, 1 => {1, 2}, 2 => {1, 7}, 3 => {1, 1}},
 %{3 => [{1, 1}, {1, 2}]}}
```

Confirm the exact tuple by running it before committing the doctest; the
positions half is verified above (`a.b.c = 2` gives `{1,1}`, `{1,2}`, `{1,4}`),
the segment half follows from the same annotations.

#### 3. The compiler

**File**: `lib/predicator/compiler.ex`
**Changes**: add `to_instructions_with_segment_positions/2` beside
`to_instructions_with_positions/2` (`:88-92`), delegating to the new visitor
function, with a `@doc` saying what the third table is and that the instruction
list is still identical to `to_instructions/2`'s. **Do not change
`to_instructions_with_positions/2`'s return shape** - it is public API and
several call sites and doctests pin the two-tuple.

#### 4. The compiled envelope

**File**: `lib/predicator/compiled.ex`
**Changes**: add `segment_positions: %{}` to the struct, the `@type t`, and the
typedoc; add `new/3` (a third defaulted argument on the existing head). Extend
the "What to store" moduledoc paragraph: the new field is a second Elixir-side
derived table with the same storage advice as `positions` - persist the source,
recompile on load. Cite ADR-0009's additive-field rule in the typedoc.

#### 5. The evaluator's carrier

**File**: `lib/predicator/evaluator.ex`
**Changes**: add `segment_positions: %{}` to `defstruct` (`:55-66`) and to
`@type t` (`:28-39`); accept `:segment_positions` in `evaluate/3`'s opts
(`:232-241`) and document it in the option list next to `:positions`
(`:202-211`), stating that it is only read by `store` and that a run without it
positions a store failure exactly as `positions` alone would.

#### 6. The façade

**File**: `lib/predicator.ex`
**Changes**:

- `build_compiled_result/1` (`:631-634`) uses
  `to_instructions_with_segment_positions/2` and `Compiled.new/3`;
- `execute/3`'s `%Compiled{}` clause (`:345-353`) and source clause
  (`:355-370`) put `:segment_positions` into opts alongside `:positions`;
- `evaluate/3`'s two matching clauses (`:168-192`) do the same, for uniformity -
  an expression compiles no store, so the table is `%{}` there;
- `execute_instructions/3` (`:386-402`) and `evaluate_instructions/2,3` copy it
  onto `%Evaluator{}`;
- `reject_positions_option!/1,2` (`:233-247`) rejects `:segment_positions`
  alongside a `%Compiled{}` too. **Keep the existing message verbatim for the
  `:positions` case** so `test/predicator/execute_test.exs:26-31` stays green;
  add an analogous message for the new key.
- extend the `:positions` bullets in `execute/3`'s and `evaluate/3`'s `@doc`
  option lists to mention the companion table.

#### 7. Tests

**File**: `test/predicator/visitors/instructions_visitor_positions_test.exs`
**Changes**: add a `visit_with_segment_positions/2` describe. The existing
`instructions ==` and `positions ==` assertions in the statements describe
(`:258-352`) must stay **unchanged** - that is the in-suite proof that neither
the instruction list nor the existing table moved. New tests:

| Source | Expected `segment_positions` |
|---|---|
| `x = 1` | `%{2 => [{1, 1}]}` |
| `a.b.c = 1` | `%{4 => [{1, 1}, {1, 2}, {1, 4}]}` |
| `a[true] = 1` | `%{3 => [{1, 1}, {1, 3}]}` |
| `u.x[k+1].z = 2` | `%{7 => [{1, 1}, {1, 2}, {1, 6}, {1, 9}]}` - length 4 for six segment instructions, the computed-key case |
| `a.b = 1` with `spans: true` | segment spans, not points |
| `x = 1; y + 1` | only the store index is keyed; the `pop` contributes nothing |

Add one test asserting `length(segment_positions[i]) == n` for the
`["store", n]` at index `i` on the computed-key source - the invariant that
makes `n` a valid index bound.

**File**: `test/predicator/compiler_test.exs`
**Changes**: one test that
`to_instructions_with_segment_positions/2` returns the same instructions as
`to_instructions/2` for the same AST, plus the third table.

**File**: `test/predicator/compiled_test.exs` (or wherever `Compiled` is
covered - check `test/predicator/` before creating a file)
**Changes**: `new/2` defaults `segment_positions` to `%{}`; `new/3` sets it.

**File**: `test/predicator/execute_test.exs`
**Changes**: extend the `compile_program_with_positions/1` describe (`:155-170`)
with an assertion that the returned `%Compiled{}` carries a non-empty
`segment_positions` for `"a.b = 1"`, and add a test that passing
`segment_positions:` alongside a `%Compiled{}` raises `ArgumentError` (mirroring
`:26-31`).

### Success Criteria

#### Automated Verification

- [ ] Full quality gate passes: `mix quality`
- [ ] Every `instructions ==` and existing `positions ==` assertion in
      `instructions_visitor_positions_test.exs` passes **unmodified**
- [ ] The whole suite passes with no behavioural test edited - this phase adds a
      carrier and changes no error
- [ ] The new doctests on `visit_with_segment_positions/2` and
      `to_instructions_with_segment_positions/2` pass
- [ ] Dialyzer is clean on the widened `annotated` type
- [ ] Coverage above 90% for `instructions_visitor.ex`, `compiler.ex`,
      `compiled.ex`

#### Manual Verification

- [ ] `Predicator.compile_program_with_positions("a.b.c = 1")` returns a
      `%Compiled{}` whose `segment_positions` is `%{4 => [{1,1},{1,2},{1,4}]}`
      and whose `instructions` and `positions` are identical to what the same
      call returned before this phase
- [ ] `Predicator.compile_program("a.b.c = 1")` is byte-identical to before

---

## Phase 3: Point a store failure at the failing segment

### Overview

The join. `execute_store/2` resolves a path index plus the segment table into a
location and hands it to `attach_position/2`. This is the only phase where
observable behaviour changes.

### Changes Required

#### 1. `validate_store_segments/1`

**File**: `lib/predicator/evaluator.ex` (`:1367-1382`)
**Changes**: `Enum.find/2` becomes `Enum.find_index/2`, and the function returns
the index alongside the error so `execute_store/2` can locate it. The `expected`
atom, `got`, `values`, `operation`, and the message are unchanged.

```elixir
@spec validate_store_segments([term()]) ::
        :ok | {:error, TypeMismatchError.t(), non_neg_integer()}
defp validate_store_segments(segments) do
  case Enum.find_index(segments, fn segment ->
         not (is_binary(segment) or is_integer(segment))
       end) do
    nil ->
      :ok

    index ->
      bad_segment = Enum.at(segments, index)

      {:error,
       TypeMismatchError.unary(
         :store,
         :string,
         get_value_type(bad_segment),
         bad_segment,
         "a string or an integer"
       ), index}
  end
end
```

Extend the existing comment: the index is the segment's position in the
root-first path, which the run's segment table turns into a source location.

#### 2. `execute_store/2`, `do_store/4`, `wrap_location_error/1`

**File**: `lib/predicator/evaluator.ex` (`:1329-1409`)
**Changes**:

- `execute_store/2`'s `validate_store_segments/1` branch becomes
  `{:error, error, index} -> located(evaluator, error, index)`;
- its `insufficient_operands` branch passes `nil` as the index (D2);
- `do_store/4`'s error branch reads the index off the `LocationError` and calls
  `located/3`:

```elixir
{:error, %LocationError{details: details} = location_error} ->
  located(evaluator, wrap_location_error(location_error), Map.get(details, :path_index))
```

- `wrap_location_error/1` is otherwise unchanged: it still keeps the message
  verbatim and maps `type` to `reason`. Update its comment to record that
  `details` is no longer discarded wholesale - `:path_index` is read at the call
  site, and the rest still is.
- add `located/3` and `segment_annotation/2` (bodies in "Implementation
  Approach").

#### 3. The stamping funnel

**File**: `lib/predicator/evaluator.ex`
**Changes**: add one clause to `attach_position/2` (`:348-352`) and one
pass-through clause to `advance_instruction_pointer/1` (`:570-575`), whose
existing error clause is guarded `when is_struct(error_struct)` and would
otherwise raise on the tagged tuple. Widen
`advance_instruction_pointer/1`'s `@spec` if it has one. Comment the invariant:
`{:located, error, location}` is constructed only by `located/3` and
destructured only by `attach_position/2`, so it never escapes `step/1`.

#### 4. Evaluator tests

**File**: `test/predicator/evaluator/store_test.exs`
**Changes**:

- The existing describe at `:139-168` **stays green untouched**: both its tests
  hand-build a `positions` table with no segment table, so they take the
  fallback path. Extend its describe title or add a comment noting that it now
  also pins the *degradation* - a run with no segment table positions a store
  error exactly as before px-ids.
- Add a describe for the refined path, hand-built so it needs no compiler:

```elixir
describe "store: a run carrying a segment table blames the failing segment" do
  test "not_a_container reads the failing segment's own annotation" do
    instructions = [["lit", "a"], ["lit", "b"], ["lit", "c"], ["lit", 2], ["store", 3]]

    assert {:error, %EvaluationError{reason: "not_a_container", position: {9, 4}}} =
             Evaluator.run(%Evaluator{
               instructions: instructions,
               context: %{"a" => %{"b" => 1}},
               positions: %{4 => {9, 1}},
               segment_positions: %{4 => [{9, 1}, {9, 4}, {9, 7}]}
             })
  end

  test "a bad segment type reads the bad segment's own annotation" do
    instructions = [["lit", "a"], ["lit", true], ["lit", 1], ["store", 2]]

    assert {:error, %TypeMismatchError{position: {9, 4}}} =
             Evaluator.run(%Evaluator{
               instructions: instructions,
               context: %{},
               positions: %{3 => {9, 1}},
               segment_positions: %{3 => [{9, 1}, {9, 4}]}
             })
  end

  test "insufficient_operands keeps the store instruction's own entry" do
    # No segment is identified, so the segment table is not consulted (D2).
  end

  test "a segment table with a nil entry falls back to the instruction's entry" do
  end

  test "a segment table whose list is shorter than the index falls back" do
  end
end
```

The last three are the degradation coverage that keeps `located/3`'s `nil`
branch and `segment_annotation/2`'s catch-all out of the uncovered-branch report.

#### 5. End-to-end tests

**File**: `test/predicator/execute_test.exs`
**Changes**: three existing assertions move and two are added. Write the old
value in a comment beside each new one.

| Test | Line | Was | Becomes |
|---|---|---|---|
| "a store failure blames the lhs root, not the `=`" | `:117-121` | `{1, 8}` | `{1, 8}` - **unchanged**; segment 0 is the lhs root here. Retitle to "blames the failing segment" |
| "an invalid list index blames the lhs root" | `:123-126` | `{1, 13}` | `{1, 17}` - the key expression `0-1`. Retitle |
| span-mode test | `:128-131` | `span: {{1, 8}, {1, 15}}` | `span: {{1, 8}, {1, 9}}`, `position: {1, 8}` unchanged - **decision D1** |
| `TypeMismatchError` for `a[true] = 1` | `:133-140` | `position: {1, 1}` | `position: {1, 3}` - the key `true` |
| **new** - a deep chain blames the interior segment | - | - | `Predicator.execute(~s(a = {"b": 1}; a.b.c = 2), %{})` -> `{1, 16}`, with a comment that `a` is at 15 and the `.` before `b` at 16 (`docs/reference/ast.md:122-124`) |
| **new** - a bare instruction list degrades | - | - | `Predicator.execute([["lit","a"],["lit","b"],["lit",2],["store",2]], %{"a" => 1})` positions as `positions` alone dictates |

**File**: `test/predicator/integration/statements_test.exs`
**Changes**: `:42-48` asserts only `reason` and the partial context and stays
green untouched - a useful signal that the contract half held. Add one
assertion there for the interior-segment position, so the behaviour is pinned at
the integration layer and not only in `execute_test.exs`.

**File**: `conformance/cases/statements.json`
**Changes**: **none.** Neither store-error case (`:63-80`, `:96-108`) asserts a
position or a message, so `corpus_hash` does not move and no regeneration runs.
Confirm with the gate rather than by assertion.

### Success Criteria

#### Automated Verification

- [ ] Full quality gate passes: `mix quality`
- [ ] `test/predicator/evaluator/store_test.exs:139-168` passes with **no edit
      to its instructions, tables, or assertions** - if it fails, the fallback
      path is broken and the design's degradation claim is wrong
- [ ] `mix test test/predicator/conformance` (or the corpus task the gate runs)
      is green with no corpus regeneration and no `corpus_hash` change
- [ ] `mix test test/predicator/isa_sync_test.exs` is green with no edit to that
      file
- [ ] Every `instructions ==` assertion across the suite is unchanged
- [ ] Coverage above 90% for `evaluator.ex`; `located/3`'s `nil` branch and
      `segment_annotation/2`'s catch-all are both exercised

#### Manual Verification

- [ ] In `iex -S mix`, each line of "Desired End State" reproduces exactly,
      including `{1, 16}` (not `{1, 17}`) for
      `~s(a = {"b": 1}; a.b.c = 2)` - the documented precision limit
- [ ] `Predicator.execute("a = 1; a.b = 2; d = 3", %{}, spans: true)` reports
      `position: {1, 8}` with `span: {{1, 8}, {1, 9}}`, and a human agrees the
      narrower underline is an improvement (decision D1)
- [ ] Every error `message` string is unchanged from before the branch

---

## Phase 4: Docs, changelog, labels, follow-ups

### Overview

The user-facing record and the governance tidy-up. Touches `docs/` and
`CHANGELOG.md` only.

### Changes Required

#### 1. `CHANGELOG.md`

**Changes**: extend the `### Fixed` subsection under `## [Unreleased]` that
px-tbv.11 added, rather than opening a new one:

```markdown
- **A store failure blames the exact failing location segment.** Building on
  the fix above, the compiler now emits a per-store side table mapping each
  `["store", n]` instruction's index to one source annotation per location
  segment, and the evaluator joins it with the failing segment's path index.
  `Predicator.execute(~s(a = {"b": 1}; a.b.c = 2), %{})` reports
  `position: {1, 16}` - the `.b` that held a scalar - instead of `{1, 15}`, the
  location's root; `Predicator.execute("a[true] = 1", %{"a" => %{}})` reports
  `{1, 3}`, the offending key, instead of `{1, 1}`. Under `spans: true` the
  underline narrows to the failing segment (`a.b`) instead of covering the whole
  statement; the caret is unchanged, because a chain node's span already started
  at the chain root. `Predicator.Compiled` gains a `segment_positions` field and
  `Predicator.Compiled.new/3`, `Predicator.Compiler` gains
  `to_instructions_with_segment_positions/2`, and
  `Predicator.Evaluator.evaluate/3` accepts a `:segment_positions` option - all
  additive. A run without the table (a bare instruction list, a stored program)
  positions a store failure exactly as it did before, at the location's root.
  Every emitted instruction list is byte-identical; no ISA version, error type,
  reason, `expected`, or `{:error, error, context}` shape moves.
```

#### 2. `docs/reference/ast.md`

**Changes**: extend the `InstructionsVisitor` paragraph px-tbv.11 edited
(`:94-104`) with the segment table: alongside the position table, compiling an
assignment produces one annotation per location segment, keyed by the store
instruction's index; a segment's annotation is the node that produced its value
(the identifier for the root, the `property_access` node for a dotted segment,
the key expression for a bracket segment); the list's length is the chain depth,
which is `["store", n]`'s operand, so `n` bounds the index. Note explicitly that
because a `property_access` node's point position is the `.` (`:122-124`), a
dotted segment's point position names the accessor rather than the property
name, and that its span starts at the chain root (`:153-154`), which is why
narrowing the span moves the underline and not the caret.

#### 3. `docs/isa.md`

**Changes**: **none.** Section 6 (`:463-467`) puts source positions outside the
ISA, sections 4 and 7 are untouched, and `isa_sync_test.exs` parses none of
section 5's prose. Confirm by running the gate, not by editing.

#### 4. Bead labels and notes

**Changes**:

- `bd update px-ids` to add **`area:docs`** - this plan edits
  `docs/reference/ast.md` and `CHANGELOG.md`, and CLAUDE.md requires the label
  be widened *before* merge rather than noticed at merge time. The existing
  `area:api`, `area:evaluator`, `area:visitors` all stay and are all correct
  (`lib/predicator.ex` + `lib/predicator/compiled.ex` + the error structs,
  `lib/predicator/evaluator.ex` + `lib/predicator/context_location.ex`, and
  `lib/predicator/visitors/instructions_visitor.ex` respectively).
- `bd note` recording decision **D1** (span mode narrows, caret unchanged) and
  the measured precision limit (column 16, not the bead's estimated 17, because
  `property_access`'s point position is the `.`), so the next reader does not
  re-derive either.

#### 5. The one follow-up

**Changes**: file a bead (`/create-issue`, or `/wurk:issue`) for moving a
`property_access` node's **point** position off the `.` and onto the property
name, and a `bracket_access` node's off the `[`. It carries
`area:lexer-parser`, `area:docs`, and probably `area:visitors`; it is the only
remaining gap between this plan's column 16 and the bead's ideal 17, it is
AST-wide rather than store-specific, and `docs/reference/ast.md:122-124`
documents the current choice deliberately - so it needs its own justification
and its own blast-radius assessment. Low priority. Do **not** block Phases 1-3
on it.

### Success Criteria

#### Automated Verification

- [ ] `mix quality` still green (this is the pre-commit run for the branch)
- [ ] `git diff --stat` for this phase touches only `CHANGELOG.md` and
      `docs/reference/ast.md`

#### Manual Verification

- [ ] The changelog entry names the old and new positions concretely and states
      the degradation behaviour
- [ ] `bd show px-ids` lists `area:api`, `area:docs`, `area:evaluator`,
      `area:visitors`
- [ ] The follow-up bead exists and names the AST point-position change

---

## Testing Strategy

### Unit Tests

- `test/predicator/context_location_test.exs` - `details.path_index` at all five
  raise sites (Phase 1). These are the only tests that prove Half A, and they
  need no compiler and no evaluator.
- `test/predicator/errors/location_error_test.exs` - the defaulted `nil`
  path index, so the additive change cannot drift.
- `test/predicator/visitors/instructions_visitor_positions_test.exs` - the
  compile-time half: the segment table's shape for a simple chain, a deep chain,
  a bracket key, a *computed* bracket key (the case where instruction count and
  depth diverge), and span mode. The unchanged `instructions ==` and
  `positions ==` assertions are the in-suite proof that neither the instruction
  list nor the existing table moved.
- `test/predicator/compiler_test.exs`, `Compiled`'s tests - the carrier's
  plumbing and defaults.
- `test/predicator/evaluator/store_test.exs` - the runtime half, hand-built so
  it exercises the evaluator without the compiler: the refined path for
  `not_a_container` and for a bad segment type, and **three degradation cases**
  (no segment table, a `nil` entry, an index past the list's end) which are also
  the branch coverage for `located/3` and `segment_annotation/2`.

### Integration Tests

- `test/predicator/execute_test.exs` - exact columns on **multi-statement**
  sources, so a regression cannot hide behind a column-1 lhs root: the deep
  chain at `{1, 16}`, the bracket key at `{1, 3}`, the invalid index at
  `{1, 17}`, the narrowed span, and the bare-instruction-list degradation.
- `test/predicator/integration/statements_test.exs` - one interior-segment
  position assertion added; the existing `reason`/partial-context assertions
  stay green untouched.

### Manual Testing Steps

1. `iex -S mix`, then each line of "Desired End State"; compare against the
   "Current State Analysis" table captured on this branch's parent.
2. Confirm `Predicator.compile_program("a.b.c = 1")` is byte-identical to what
   `main` emits - the instruction-list invariance claim.
3. Run a store failure under `spans: true` and confirm the caret is where
   px-tbv.11 left it and only the underline narrowed.

## Performance Considerations

The segment table is built by one extra structural walk of the lhs chain per
assignment at compile time, proportional to chain depth - the same order as
`location_depth/1`, which already walks it. At run time the refinement is one
`Map.get/3` plus one `Enum.at/2` on a list whose length is the chain depth, and
only on the error path. Neither the success path nor any non-store opcode gains
work. `%Compiled{}` and `%Evaluator{}` each carry one more map, empty for every
program containing no assignment.

## ISA Impact

**None. This change does not move the ISA version.**

1. **Version** - unchanged. `store` stays ISA v3, tier 6. No opcode is added,
   removed, renamed, or given different semantics, and no operand form changes:
   `["store", n]`'s `n` is still the chain depth. The instruction list emitted
   for every program is **byte-identical** before and after - only two
   Elixir-side side tables carry more, and `docs/isa.md` section 6 (`:463-467`)
   states that source positions and spans are never part of the instruction list.
   The unchanged `instructions ==` assertions in
   `instructions_visitor_positions_test.exs` are the mechanical check, and
   Phases 2 and 3 both call it out in their success criteria. This confirms the
   research's answer (options A-D are not ISA changes; only option E, which this
   plan rejects, would be) still holds for the design landed here.
2. **Stamp** - nothing owed. `docs/isa.md` gains no edit at all: section 4's
   opcode table, the tier table, and section 7's history are untouched, so
   `test/predicator/isa_sync_test.exs`'s four regexes and `@opcode_count` are
   unaffected. The `position`/`span` fields are non-normative by that document's
   own taxonomy; the normative fields (`type`, `reason`, `expected`,
   `operation`) do not move.
3. **Migration** - none. Any instruction list compiled before this change runs
   unchanged and produces the same answer, and positions a store failure exactly
   as it did before (a bare list carries no segment table, so the fallback path
   is taken by construction). No stored artifact is affected. The conformance
   corpus is untouched - neither store-error case asserts a position or a
   message - so `corpus_hash` does not move.

Sibling implementations (Ruby, JavaScript) owe nothing here: there is no ISA
delta to adopt (ADR-0003).

## Open Questions

None blocking. The two questions this plan was asked to settle are settled -
decision **D1** (span mode narrows; the caret does not move) and decision **D2**
(segment-less errors keep the store instruction's own entry) - and both are
enforced by named assertions in Phase 3.

One question is recorded as **deliberately out of scope rather than
unresolved**, and is filed as a follow-up bead in Phase 4:

- **Should a `property_access` node's point position name the property rather
  than the `.`, and a `bracket_access` node's the key rather than the `[`?**
  `docs/reference/ast.md:122-124` documents the current choice deliberately, and
  it is the whole of the remaining gap between this plan's column 16 and the
  bead's estimated ideal of 17 for `a = {"b": 1}; a.b.c = 2`. Changing it is an
  AST-wide change touching the parser and a large number of existing position
  assertions, it affects every node type's blame token and not just `store`, and
  it would be wrong to fold into a P3 store bead. It is not needed for any
  acceptance criterion here.

## References

- Beads issue: `px-ids` (discovered from `px-tbv.11`)
- Source research: `docs/research/260808-px-tbv.11-store-failure-position.md` -
  the eleven findings, the A-E option table, and the "no ISA change for A-D"
  finding this plan re-verifies
- Predecessor plan: `docs/plans/260808-px-tbv.11-store-failure-position.md` -
  option A, which this plan builds on rather than replaces; its Q1-Q8
  resolutions are the baseline, and Q1, Q3, Q5, Q7 are revisited here because
  B+C is now in scope
- Prior research: `docs/research/260808-px-tbv.2-store-opcode-execute.md` - the
  pre-implementation map of the store opcode
- `docs/adr/0003-the-elixir-implementation-leads-the-isa.md:90-97,191-195` -
  what an ISA change owes, and why this is not one
- `docs/adr/0009-the-compiled-envelope-carries-the-position-table.md:93-100,171-197` -
  the table is not a wire format; **adding a field to `%Compiled{}` is additive,
  changing `positions`'s meaning is not** - the rule that makes
  `segment_positions` a new field
- `docs/adr/0001-keep-the-stack-vm-revise-the-instruction-set.md:83-84` -
  `["store", n]`'s operand as chain depth
- `lib/predicator/visitors/instructions_visitor.ex:96-110,285-308,329-330,337-360` -
  `visit_with_positions/2`, the assignment clause and `store_annotation/2` as
  px-tbv.11 left them, `statement_position/1` (to be renamed), `location_segments/2`,
  and `location_depth/1`
- `lib/predicator/compiler.ex:88-92` - `to_instructions_with_positions/2`, whose
  return shape does **not** change
- `lib/predicator/compiled.ex:56-100` - the envelope's typedoc, struct, and
  `new/2`
- `lib/predicator/evaluator.ex:28-66,325-357,388,570-575,1329-1409` - the struct
  and type, `step/1`'s position pipeline, `execute_instruction/2`'s spec,
  `advance_instruction_pointer/1`'s `is_struct` guard, `execute_store/2`,
  `do_store/4`, `validate_store_segments/1`, `wrap_location_error/1`
- `lib/predicator/context_location.ex:364-428` - `do_put/4`'s trail and the five
  raise sites
- `lib/predicator/errors/location_error.ex:49-64,140-176` - the struct (no
  position field, free-form `details`) and the two constructors that gain a
  path index
- `lib/predicator/errors.ex:41-56` - `put_position/2`'s span/point
  discrimination and unconditional overwrite
- `lib/predicator.ex:168-192,233-247,338-402,631-634` - `evaluate/3`,
  `reject_positions_option!/1,2`, `execute/3`, `execute_instructions/3`, and
  `build_compiled_result/1`
- `lib/predicator/types.ex:109-148` - `position_table/0` and `span_table/0`, the
  models for the new typedoc
- `docs/reference/ast.md:85-104,122-124,153-154` - the statement-node shape, the
  `InstructionsVisitor` paragraph Phase 4 extends, the **point** blame table (the
  `.` and the `[`), and the **span** extent table (chain-root start)
- `docs/isa.md:435-451,463-467` - the `store` bullet (unedited here) and
  positions being outside the ISA
- `test/predicator/evaluator/store_test.exs:98-168` - the normative-field
  assertions and the table-lookup describe that stays green as the degradation
  guard
- `test/predicator/execute_test.exs:26-31,109-140,155-170` - the
  `ArgumentError` guard, the four position assertions Phase 3 revisits, and the
  `compile_program_with_positions/1` shape tests Phase 2 extends
- `test/predicator/integration/statements_test.exs:42-48` - the end-to-end
  `not_a_container` test
- `test/predicator/visitors/instructions_visitor_positions_test.exs:258-352` -
  the store-position tests whose `instructions ==` and `positions ==`
  assertions must not move
- `conformance/cases/statements.json:63-80,96-108` - the two store-error cases,
  neither asserting a position or a message
- Related bead: **px-tmy** (`bracket_access` does not obey its own isa.md
  bullet) - different region of `evaluator.ex`, unaffected by this change
