# UndefinedVariableError Position Implementation Plan

## Overview

`Predicator.Errors.UndefinedVariableError` is the one runtime error type whose
`:position` is always `nil` on the default (`on_unbound: :undefined`) path.
`px-e3g.4` gave the three runtime errors an optional `:position` populated at
the evaluator's single choke point in `step/1`, but two of the three
`UndefinedVariableError` construction sites live in `Predicator.evaluate/3`,
*after* the run, where the instruction pointer no longer exists.

This plan records a source location alongside each unbound load at the moment
the `["load", name]` instruction executes - where the instruction pointer and
the positions table are both in scope - and threads it into the two after-the-run
construction sites. Beads issue: `px-1e1` (labels `area:evaluator`, `area:api`).

## Current State Analysis

### The three construction sites

1. **`Evaluator.execute_instruction/2`, the `["load", name]` clause**
   (`lib/predicator/evaluator.ex:347-359`) under `on_unbound: :error`. It
   returns `{:error, UndefinedVariableError.new(variable_name)}` from inside
   `execute_instruction/2`, so it flows through `step/1`
   (`lib/predicator/evaluator.ex:277-292`) →
   `advance_instruction_pointer/1` (passes errors through untouched) →
   `attach_position/2` → `attach_error_position/2`
   (`lib/predicator/evaluator.ex:306-309`), which reads
   `Map.get(positions, ip)` off the **pre-step** evaluator. That ip is still the
   load's own index, so this site already carries the variable's own location.
   **This site is correct today and this plan must not change it.**

2. **`Predicator.undefined_result/1`** (`lib/predicator.ex:245-251`). Fires when
   the whole program evaluates to `:undefined`; builds the error from the head
   of `Evaluator.unbound_loads/1`. No position.

3. **`Predicator.unbound_or_type_mismatch/2`** (`lib/predicator.ex:266-276`).
   The `px-8um.7` rewrite: a `TypeMismatchError` whose `got` mentions
   `:undefined` and whose run recorded an unbound load becomes an
   `UndefinedVariableError`, again from the head of `unbound_loads/1`. No
   position.

### The recording point

`record_unbound_load/3` (`lib/predicator/evaluator.ex:1218-1226`) is called from
the `load` clause *before* `advance_instruction_pointer/1` runs, so
`evaluator.instruction_pointer` is still the load's own index and
`evaluator.positions` is the table. Everything needed is already in scope; only
the name is being kept.

It dedups by name (`variable_name not in evaluator.unbound_loads`) and prepends,
so the list is reverse execution order and `unbound_loads/1`
(`lib/predicator/evaluator.ex:150-151`) reverses it.

### The positions table is polymorphic

`%Evaluator{positions:}` is typed `Types.position_table() | Types.span_table()`
(`lib/predicator/evaluator.ex:43`), so a table entry is either a
`t:Predicator.Types.position/0` `{line, col}` or a `t:Predicator.Types.span/0`
`{{sl, sc}, {el, ec}}`. `Predicator.Errors.put_position/2`
(`lib/predicator/errors.ex:41-56`) already discriminates: a span sets `:span`
**and** `:position` (the span's start); a position sets `:position`; `nil` is a
no-op; a non-struct passes through. So the recorded value must be the **raw
table entry**, handed to `put_position/2` at construction - not a pre-narrowed
`{line, col}`.

### Key Discoveries

- `Evaluator.unbound_loads/1` is public, `@spec unbound_loads(t()) ::
  [binary()]`, and carries a doctest (`lib/predicator/evaluator.ex:125-151`).
  It is exercised by `test/predicator/evaluator_test.exs:1293-1356` and
  documented in `docs/architecture.md` and `CHANGELOG.md:261`.
- Nothing outside `Evaluator` reads the `unbound_loads` struct field directly;
  the only external readers go through the accessor
  (`lib/predicator.ex:247`, `lib/predicator.ex:269`).
- `docs/architecture.md:302-319` states as settled design that sites 2 and 3
  keep `position: nil` - site 3 deliberately, because "the position on hand
  belongs to the *rejecting operator* ... not to the variable". That reasoning
  is exactly what this change removes: after this plan the location on hand
  **is** the variable's own load site, so the objection no longer applies. That
  paragraph must be rewritten, not worked around.
- `docs/architecture.md:547` already advertises `missing`, `missing == 5`,
  `not missing`, `missing + 1` as "same, now with a position" under
  `on_unbound: :error`; after this change the default policy matches for those
  four, and the row's contrast narrows.
- ADR-0001 keeps the stack VM on ISA v2. This change emits no new instruction
  and changes no instruction's shape, so there is **no cross-language impact**
  and no Cross-Language Impact section below.

## Desired End State

`Predicator.evaluate/3` with string input returns an `UndefinedVariableError`
whose `:position` names the unbound variable's own token, on every path:

```elixir
Predicator.evaluate("missing", %{})
# {:error, %UndefinedVariableError{variable: "missing", position: {1, 1}}}

Predicator.evaluate("1 + missing", %{})
# {:error, %UndefinedVariableError{variable: "missing", position: {1, 5}}}
#                                  ^ the variable, not the {1, 3} of the `+`

Predicator.evaluate("missing", %{}, on_unbound: :error)
# {:error, %UndefinedVariableError{variable: "missing", position: {1, 1}}}  (unchanged)

{:ok, instructions, spans} = Predicator.compile_with_spans("1 + missing")
Predicator.evaluate(instructions, %{}, positions: spans)
# {:error, %UndefinedVariableError{position: {1, 5}, span: {{1, 5}, {1, 12}}}}

Predicator.evaluate([["load", "missing"]], %{})
# {:error, %UndefinedVariableError{position: nil, span: nil}}  (no table, unchanged)
```

Verification: the assertions above become tests; `mix quality` is green; the
`docs/architecture.md` paragraph that documented the old behavior is rewritten;
`CHANGELOG.md` has an `## [Unreleased]` entry.

## What We're NOT Doing

- **Not changing `unbound_loads/1`'s return shape.** See "Implementation
  Approach" for the reasoning; it keeps `[binary()]`.
- **Not adding provenance.** `unbound_loads` still records *executed* loads, not
  which one produced the `:undefined` that reached the result (`px-8um.8`). The
  first recorded load is still what gets reported, and its location is the one
  recorded with it.
- **Not changing dedup semantics.** A name is recorded once, at its first
  executed unbound load, and that first occurrence's location is what sticks.
- **Not touching the `on_unbound: :error` load site.** It already reports the
  variable's own location through `step/1`. No second attachment is added there.
- **Not touching the low-level `Evaluator.evaluate/3` contract.** It returns the
  bare `TypeMismatchError` on the rewrite-eligible paths as it does today; the
  rewrite is an API-layer concern (`docs/architecture.md:324`).
- **Not giving the empty-stack error a position.** It belongs to no instruction
  and stays `nil` by construction.
- **No new instructions, no ISA change, no sibling-implementation work.**

## Implementation Approach

**Record the pair, keep the accessor, add a sibling.**

The `%Evaluator{}` field becomes a list of `{name, location}` pairs where
`location` is the raw `positions` table entry for the load's instruction index -
`nil`, a `{line, col}`, or a `{start, end}` span. Dedup keys on the name only,
so first-occurrence-wins is preserved verbatim.

`unbound_loads/1` **keeps its `[binary()]` shape** and is redefined as a
projection over the pairs. A new `unbound_loads_with_locations/1` returns the
pairs. The reasoning:

- `unbound_loads/1` is public, `@spec`'d, doctested, referenced in
  `CHANGELOG.md` and `docs/architecture.md`, and shipped in v3.8.0. Changing its
  element type from `binary()` to a 2-tuple is a silent breaking change for
  every consumer - it still returns a list, still has the same arity, and would
  fail at the *use* site rather than the call site.
- The names-only shape is genuinely the useful one for the questions most
  callers ask ("which variables were unbound?"). A location is extra
  information for error rendering, not a refinement of the same answer.
- A sibling accessor costs one function and one type. `unbound_loads/1` becomes
  a one-line projection over it, so the two cannot drift.
- The repo has an unreleased `[Unreleased]` section that already contains a
  breaking change (the Elixir 1.18 floor), so a break would be *cheap* here -
  but cheap is not free, and nothing about this bug requires one.

`Predicator.undefined_result/1` and `unbound_or_type_mismatch/2` then read the
pair, build the error with `UndefinedVariableError.new/1` as today, and pipe it
through `Predicator.Errors.put_position/2`. Because both build a **fresh**
struct, there is no double attachment: the operator's position that
`step/1` had already put on the `TypeMismatchError` is discarded along with the
struct it was on, which is the intended outcome (`px-8um.7`'s original objection
to carrying it over).

Two phases, split at the module boundary. Phase 1 is self-contained inside
`Evaluator` and leaves the gate green on its own because `unbound_loads/1`'s
shape is unchanged; Phase 2 wires the API layer, updates the tests whose
expectations move, and updates the docs.

---

## Phase 1: Record the location alongside each unbound load

### Overview

`%Evaluator{}` stores `{name, location}` pairs. `unbound_loads/1` is unchanged
observably; `unbound_loads_with_locations/1` is new. No caller outside the module
changes, so the suite stays green.

### Changes Required:

#### 1. The struct type and the new pair type

**File**: `lib/predicator/evaluator.ex`
**Changes**: Retype the `unbound_loads` field (`:45`) and add a public typedoc'd
type for the pair.

```elixir
@typedoc """
An executed load of a root that was not bound, paired with the source location
of the `["load", _]` instruction that read it.

The location is the raw `positions` table entry: `nil` when the run carried no
table or the index was uncovered, a `t:Predicator.Types.position/0` under point
positions, a `t:Predicator.Types.span/0` under spans. Hand it to
`Predicator.Errors.put_position/2`, which discriminates the three.
"""
@type unbound_load :: {binary(), Types.position() | Types.span() | nil}
```

and in `@type t`:

```elixir
unbound_loads: [unbound_load()],
```

The `defstruct` default (`:62`) stays `unbound_loads: []`.

#### 2. The recorder

**File**: `lib/predicator/evaluator.ex` (`:1216-1226`)
**Changes**: Record the pair; dedup on the name via `List.keymember?/3`. The
existing comment about the dedup check living here rather than in
`unbound_load?/3` stays. Add a sentence pinning first-occurrence-wins.

```elixir
# The dedup check stays here rather than in unbound_load?/3: the policy fires
# on the first unbound load and halts, so it never needs it.
#
# Dedup keys on the name alone, so a name loaded twice keeps the location of
# its *first* executed load - the same entry, and the same reported variable,
# the pre-px-1e1 names-only list produced.
@spec record_unbound_load(t(), binary(), Types.value()) :: t()
defp record_unbound_load(%__MODULE__{} = evaluator, variable_name, value) do
  if unbound_load?(evaluator, variable_name, value) and
       not List.keymember?(evaluator.unbound_loads, variable_name, 0) do
    entry = {variable_name, current_location(evaluator)}
    %__MODULE__{evaluator | unbound_loads: [entry | evaluator.unbound_loads]}
  else
    evaluator
  end
end

# The load's own location, read at the load. record_unbound_load/3 runs from
# inside execute_instruction/2, before advance_instruction_pointer/1, so
# instruction_pointer is still this load's index - the same index
# attach_error_position/2 reads for an error raised by this instruction.
@spec current_location(t()) :: Types.position() | Types.span() | nil
defp current_location(%__MODULE__{positions: positions, instruction_pointer: ip}) do
  Map.get(positions, ip)
end
```

#### 3. The accessors

**File**: `lib/predicator/evaluator.ex` (`:125-151`)
**Changes**: Keep `unbound_loads/1`'s docs and doctest as-is, redefine it as a
projection, and add the sibling above or below it with its own doctest.

```elixir
@spec unbound_loads(t()) :: [binary()]
def unbound_loads(%__MODULE__{} = evaluator) do
  evaluator |> unbound_loads_with_locations() |> Enum.map(&elem(&1, 0))
end

@doc """
The same loads `unbound_loads/1` reports, each paired with the source location
of the `["load", _]` instruction that read it.

The location comes from the run's `positions` table, read at the load itself, so
it names the *variable's* token - not the operator that later rejected its
`:undefined`. It is `nil` when the run carried no table (an instruction-list
caller who passed no `positions:`), a `{line, column}` under point positions, and
a span under a table from `Predicator.compile_with_spans/1`.
`Predicator.evaluate/3` uses this to position the `UndefinedVariableError` it
builds after the run.

A name loaded more than once appears once, with the location of its first
executed load.

## Examples

    iex> {:ok, instructions, positions} = Predicator.compile_with_positions("a + b")
    iex> {:ok, _result, evaluator} =
    ...>   Predicator.Evaluator.run_prepared(%Predicator.Evaluator{
    ...>     instructions: instructions,
    ...>     context: %{"a" => 1},
    ...>     positions: positions
    ...>   })
    iex> Predicator.Evaluator.unbound_loads_with_locations(evaluator)
    [{"b", {1, 5}}]
"""
@spec unbound_loads_with_locations(t()) :: [unbound_load()]
def unbound_loads_with_locations(%__MODULE__{unbound_loads: loads}), do: Enum.reverse(loads)
```

**Doctest caution**: `"a + b"` with `a` bound to `1` and `b` unbound reaches
`["add"]` with an `:undefined` operand, which is a `TypeMismatchError`, so
`run_prepared/1` returns `{:error, _, evaluator}`, not `{:ok, ...}`. Write the
doctest against a program that *completes*, or bind the error form - verify the
exact shape with `mix test` rather than assuming. A safe completing form is
`Predicator.compile_with_positions("a == 1 or b == 1")` under the short-circuit
opcodes, or simply a hand-built `[["load", "a"], ["load", "b"]]` plus a
hand-written `positions: %{1 => {1, 5}}`. Prefer the hand-built form: it keeps
the doctest independent of the compiler's layout.

#### 4. `unbound_loads/1`'s own docs

**File**: `lib/predicator/evaluator.ex` (`:125-149`)
**Changes**: Add one sentence pointing at the sibling
("`unbound_loads_with_locations/1` returns the same loads with the source
location of each"). Leave the existing doctest untouched - it is the regression
test for the non-breaking claim.

### Success Criteria:

#### Automated Verification:
- [ ] Full quality gate passes: `mix quality`
- [ ] The existing `describe "unbound_loads/1"` block in
      `test/predicator/evaluator_test.exs:1293-1356` passes **unmodified** -
      that is the proof the public shape did not move
- [ ] The `unbound_loads/1` doctest at `lib/predicator/evaluator.ex:139-148`
      passes unmodified
- [ ] New `unbound_loads_with_locations/1` doctest passes
- [ ] Coverage for `lib/predicator/evaluator.ex` stays above the 90% floor in
      `coveralls.json`

#### Manual Verification:
- [ ] In `iex -S mix`: a run over a span table records a span in the pair, and a
      run with no table records `nil` - neither crashes `put_position/2`
- [ ] Dialyzer accepts `unbound_load()` against both `position_table()` and
      `span_table()` valued `positions` fields

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run the full `mix quality` as the phase gate. In interactive
execution, pause here for manual confirmation from the human that the manual
testing was successful before proceeding to the next phase. In looped
(`--loop`) execution, this phase's Automated Verification gates advancement
automatically (via `/commit --auto`); Manual Verification items are deferred and
surfaced once at the end instead of blocking here.

---

## Phase 2: Position the two after-the-run construction sites

### Overview

`Predicator.undefined_result/1` and `unbound_or_type_mismatch/2` read the pair
and decorate the error they build. The tests that pinned `position: nil` for
these paths are updated to pin the variable's position instead, the docs that
described the old behavior are rewritten, and `CHANGELOG.md` gets an entry.

### Changes Required:

#### 1. `undefined_result/1`

**File**: `lib/predicator.ex` (`:237-251`)
**Changes**: Read the pair, decorate. Add `Errors` to the alias on `:80`
(`alias Predicator.{Compiler, Context, ContextLocation, Errors, Evaluator,
Lexer, Parser, Types}`).

```elixir
@spec undefined_result(Evaluator.t()) :: {:ok, :undefined} | {:error, struct()}
defp undefined_result(evaluator) do
  case Evaluator.unbound_loads_with_locations(evaluator) do
    [] -> {:ok, :undefined}
    [unbound_load | _rest] -> {:error, undefined_variable_error(unbound_load)}
  end
end
```

#### 2. `unbound_or_type_mismatch/2`

**File**: `lib/predicator.ex` (`:253-276`)
**Changes**: Same read, same construction. The `with` still discriminates on a
non-empty list; the bound variable is now a pair.

```elixir
@spec unbound_or_type_mismatch(struct(), Evaluator.t()) :: struct()
defp unbound_or_type_mismatch(%TypeMismatchError{got: got} = error, evaluator) do
  with true <- undefined_operand?(got),
       [unbound_load | _rest] <- Evaluator.unbound_loads_with_locations(evaluator) do
    undefined_variable_error(unbound_load)
  else
    _no_rewrite -> error
  end
end
```

Its leading comment gains a paragraph: the rewritten error is positioned at the
**variable's** load, not at the rejecting operator - the operator's position
went out with the `TypeMismatchError` this replaces, which is the right
trade because a caller's editor wants the caret on the variable.

#### 3. The shared constructor

**File**: `lib/predicator.ex`, beside the two callers
**Changes**: One private helper so both sites decorate identically.

```elixir
# The location is the raw positions-table entry the evaluator recorded at the
# load - nil, a point position, or a span. Errors.put_position/2 discriminates
# all three, setting :span as well when it is handed one, so nothing here has
# to know which mode the program was compiled in.
@spec undefined_variable_error(Evaluator.unbound_load()) :: UndefinedVariableError.t()
defp undefined_variable_error({variable_name, location}) do
  variable_name
  |> UndefinedVariableError.new()
  |> Errors.put_position(location)
end
```

#### 4. Tests whose expectations move

**File**: `test/predicator/evaluator_positions_test.exs` (`:44-63`)
**Changes**: Both tests invert. The two comments above them describe behavior
that no longer exists and must be replaced.

```elixir
# Since px-1e1 the evaluator records each unbound load's own location, so the
# UndefinedVariableError that Predicator.evaluate/3 builds after the run points
# at the variable - not at the operator that rejected its :undefined, and not
# at nothing.
test "an unbound load rejected by an operator reports the variable's position" do
  error = error_for("1 + missing")

  assert %Predicator.Errors.UndefinedVariableError{variable: "missing"} = error
  assert error.position == {1, 5}
end

test "an UndefinedVariableError from a bare load reports the load's position" do
  assert {:error, error} = Predicator.evaluate("missing", %{})

  assert error.variable == "missing"
  assert error.position == {1, 1}
end
```

Add, in the same file's uncovered-index spirit (`:174-182`), the no-table case:

```elixir
test "an instruction-list caller with no positions table keeps position: nil" do
  assert {:error, error} = Predicator.evaluate([["load", "missing"]], %{})

  assert error.variable == "missing"
  assert error.position == nil
  assert error.span == nil
end
```

**File**: `test/predicator/integration/unbound_type_mismatch_test.exs`
**Changes**: Every string-input assertion of the form
`Predicator.evaluate("...", %{}) == {:error, UndefinedVariableError.new("unbound")}`
now compares against a struct with `position: nil` and will fail. Rewrite them
to construct the expected error with its position, e.g.

```elixir
defp unbound_at(name, position) do
  {:error, Predicator.Errors.put_position(UndefinedVariableError.new(name), position)}
end

test "logical not" do
  assert Predicator.evaluate("not unbound", %{}) == unbound_at("unbound", {1, 5})
end
```

The three **instruction-list** assertions (`:22-25`, `:45-48`, `:50-53`) pass no
`positions:`, so they keep the bare `UndefinedVariableError.new(...)` comparison
and now double as no-table regression tests - note that in a comment. Keep the
`for {op, expression}` loop; it needs a per-case column, so pair each expression
with its expected position in the loop's data.

**File**: `test/predicator/integration/on_unbound_test.exs` (`:103-116`)
**Changes**: The `describe "the error's position"` block asserted the asymmetry
this bead removes. Both policies now report `{1, 5}` for `"not missing"`; rewrite
the block to assert agreement, and delete the "no instruction in scope, so it has
no position to offer" comment.

```elixir
test "points at the variable under either policy", %{
  error_context: error_context,
  default: default
} do
  assert {:error, %UndefinedVariableError{position: {1, 5}}} =
           Predicator.evaluate("not missing", error_context)

  # px-1e1: the default policy's after-the-run rewrite now uses the location
  # recorded at the load, so it agrees with the :error policy's load site.
  assert {:error, %UndefinedVariableError{position: {1, 5}}} =
           Predicator.evaluate("not missing", default)
end
```

#### 5. Tests to add

**File**: `test/predicator/integration/spans_test.exs`
**Changes**: A span-compiled default-policy case, mirroring the existing
`on_unbound: :error` one at `:144-152`:

```elixir
test "an unbound load under the default policy slices to the variable" do
  source = "1 + missing"
  {:ok, instructions, spans} = Predicator.compile_with_spans(source)

  assert {:error, %UndefinedVariableError{} = error} =
           Predicator.evaluate(instructions, %{}, positions: spans)

  assert slice(source, error.span) == "missing"
  assert error.position == {1, 5}
end
```

**File**: `test/predicator/evaluator_test.exs`, after the existing
`describe "unbound_loads/1"` block
**Changes**: A `describe "unbound_loads_with_locations/1"` block covering: a
covered index yielding the position, an uncovered index and an absent table
yielding `nil`, a span table yielding the span unchanged (**not** narrowed to
its start - the narrowing is `put_position/2`'s job), and a repeated load keeping
the *first* location.

```elixir
test "a repeated load keeps the first occurrence's location" do
  evaluator = %Evaluator{
    instructions: [["load", "a"], ["load", "a"]],
    context: %{},
    positions: %{0 => {1, 1}, 1 => {1, 9}}
  }

  {:ok, :undefined, final} = Evaluator.run_prepared(evaluator)
  assert Evaluator.unbound_loads_with_locations(final) == [{"a", {1, 1}}]
end
```

#### 6. Documentation

**File**: `docs/architecture.md` (`:302-319`)
**Changes**: Rewrite the two paragraphs. The "Two errors keep `position: nil` by
construction" paragraph becomes one error - the empty-stack error. The px-8um.7
sentence flips: the rewrite now reports the variable's own position because
`px-1e1` records it at the load, so there is no longer a wrong-token risk. The
"third construction site is the one that *does* carry a position" paragraph
loses its asymmetry framing - all three sites now position, two of them from the
recorded pair and one from `step/1` - and gains a note that the `:error` policy's
site is unchanged.

Also update the `on_unbound` comparison table at `:547`: the
`missing`, `missing == 5`, `not missing`, `missing + 1` row's "same, now with a
position" no longer distinguishes the policies, since the default now carries one
too.

Add a short entry to the per-feature history in the same spirit as the existing
`px-8um.7` / `px-8um.8` entries, naming `px-1e1` and the
`unbound_loads_with_locations/1` accessor.

**File**: `CHANGELOG.md`, under `## [Unreleased]`
**Changes**: An `### Added` bullet for the accessor and a `### Fixed` bullet for
the bug:

```markdown
### Fixed

- `Predicator.Errors.UndefinedVariableError` now carries a `:position` (and a
  `:span` under `spans: true`) on every path. The evaluator records each unbound
  load's source location alongside its name, so the error `Predicator.evaluate/3`
  builds after the run - for a bare unbound root, and for the `px-8um.7` rewrite
  of a `TypeMismatchError` that rejected an unbound root's `:undefined` - points
  at the variable's own token. It was the one runtime error type whose
  `:position` was always `nil`. An instruction-list caller who passes no
  `positions:` still sees `nil`.

### Added

- `Predicator.Evaluator.unbound_loads_with_locations/1`, returning each unbound
  load paired with the source location of the instruction that read it.
  `unbound_loads/1` is unchanged.
```

### Success Criteria:

#### Automated Verification:
- [ ] Full quality gate passes: `mix quality`
- [ ] `mix test test/predicator/integration/unbound_type_mismatch_test.exs
      test/predicator/integration/on_unbound_test.exs
      test/predicator/integration/spans_test.exs
      test/predicator/evaluator_positions_test.exs` is green
- [ ] Coverage for `lib/predicator.ex` and `lib/predicator/evaluator.ex` stays
      above the 90% floor
- [ ] No `@tag :skip` and no weakened gate config anywhere in the diff

#### Manual Verification:
- [ ] `Predicator.evaluate("1 + missing", %{})` reports `{1, 5}` - the caret
      lands on `missing`, not on the `+`
- [ ] The rewritten `docs/architecture.md` paragraphs read as a coherent account
      of three positioning sites, not as a patch over the old two-vs-one framing
- [ ] `Predicator.evaluate("missing", %{}, on_unbound: :error)` is byte-identical
      to its pre-change result - the `:error` policy path did not regress and its
      position was not attached twice

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run the full `mix quality` as the phase gate. In interactive
execution, pause here for manual confirmation from the human that the manual
testing was successful before proceeding to the next phase. In looped
(`--loop`) execution, this phase's Automated Verification gates advancement
automatically (via `/commit --auto`); Manual Verification items are deferred and
surfaced once at the end instead of blocking here.

---

## Testing Strategy

### Unit Tests:

`test/predicator/evaluator_test.exs` - `unbound_loads_with_locations/1`:

- a covered index records its `{line, column}`
- an uncovered index and an empty table both record `nil`
- a span table records the **span**, unnarrowed
- a repeated unbound load records once, keeping the first location
- a bound name records nothing (inherited from the existing dedup/binding tests)
- `unbound_loads/1` still returns `[binary()]` for every one of the above

### Integration Tests:

The five paths the bead requires, end to end through `Predicator.evaluate/3`:

1. **Bare unbound load** - `Predicator.evaluate("missing", %{})` →
   `position: {1, 1}` (`evaluator_positions_test.exs`)
2. **The type-mismatch rewrite** - `"1 + missing"`, `"not missing"`,
   `"-missing"`, `"missing * 1"` → the variable's column, never the operator's
   (`unbound_type_mismatch_test.exs`, whole file re-pinned)
3. **`on_unbound: :error`** - unchanged, still the load site's position, asserted
   against the same expression as (2) so the two policies are pinned to *agree*
   (`on_unbound_test.exs`)
4. **Span-compiled** - `compile_with_spans/1` + `positions:` → `:span` slices to
   the variable and `:position` is the span start (`spans_test.exs`)
5. **No position table** - `Predicator.evaluate([["load", "missing"]], %{})` →
   `position: nil`, `span: nil` (`evaluator_positions_test.exs`)

### Manual Testing Steps:

1. `iex -S mix`, then `Predicator.evaluate("1 + missing", %{})` - confirm
   `position: {1, 5}` and that column 5 of the source is `m`.
2. `Predicator.evaluate("missing and other_missing", %{})` - confirm the reported
   variable and position are the *first* load's, and that the short-circuit
   opcodes do not record the second.
3. `Predicator.evaluate("false and missing", %{})` - confirm `{:ok, false}`: a
   skipped load is still never recorded, so nothing new is reported.
4. Compare the `on_unbound: :error` result for `"not missing"` before and after
   the change - it must be identical.

## Performance Considerations

The recorder now builds a 2-tuple and does one `Map.get/2` on the positions table
per *first* unbound load, and dedup moves from `not in` (a linear scan over
binaries) to `List.keymember?/3` (a linear scan over tuples) - the same
complexity. The list is empty for every program whose variables are all bound,
which is the common case, so the hot path is unchanged. `unbound_loads/1` gains
one `Enum.map/2` over a list that is almost always empty.

## References

- Beads issue: `px-1e1` (`area:evaluator`, `area:api`); discovered from
  `px-e3g.4`
- `lib/predicator/evaluator.ex:277-309` - `step/1`, `attach_position/2`,
  `attach_error_position/2`
- `lib/predicator/evaluator.ex:347-359` - the `["load", _]` clause and the
  `on_unbound: :error` construction site
- `lib/predicator/evaluator.ex:125-151` - `unbound_loads/1` and its doctest
- `lib/predicator/evaluator.ex:1210-1226` - `unbound_load?/3`,
  `record_unbound_load/3`
- `lib/predicator.ex:237-284` - `undefined_result/1`,
  `unbound_or_type_mismatch/2`, `undefined_operand?/1`
- `lib/predicator/errors.ex:41-56` - `put_position/2`, the position/span
  discriminator
- `lib/predicator/errors/undefined_variable_error.ex:30-49` - the struct and
  `new/1`
- `docs/architecture.md:294-319` - runtime error positions, the paragraph this
  change rewrites; `:321-410` - source spans; `:540-552` - the `on_unbound`
  comparison table
- Prior plans: `docs/plans/260805-px-e3g.4-source-positions.md`,
  `docs/plans/260805-px-3kr-position-spans.md`,
  `docs/plans/260805-px-8um.7-unbound-type-mismatch.md`,
  `docs/plans/260804-px-8um.8-runtime-unbound-tracking.md`
- ADR-0001 (`docs/adr/0001-keep-the-stack-vm-revise-the-instruction-set.md`) -
  no ISA change here, so no cross-language work
