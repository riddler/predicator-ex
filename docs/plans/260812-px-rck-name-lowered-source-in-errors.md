# Naming the source construct in lowered-opcode errors

## Overview

A type mismatch raised by an instruction that exists only as the lowering of a
source construct currently reports the opcode's name, which the author never
typed. This plan gives `Predicator.Errors.operation_display_name/1` explicit
clauses for the four such atoms, pins the resulting message text end to end, and
records a decision on `:in`.

Beads Issue: `px-rck`

## Current State Analysis

`Predicator.Errors.operation_display_name/1`
(`lib/predicator/errors.ex:117-141`) has explicit clauses for the arithmetic,
unary, logical, and bracket-access operations and falls through to a generic
humanizer for everything else. The humanizer splits the atom on `_`,
capitalizes each word, and upcases `and`/`or`/`not`.

Two callers consume it, and both are user-facing:

- `Predicator.Errors.TypeMismatchError.unary/4,5` and `binary/4`
  (`lib/predicator/errors/type_mismatch_error.ex:80`, `:96`)
- `Predicator.Errors.EvaluationError.insufficient_operands/3`
  (`lib/predicator/errors/evaluation_error.ex:71`)

Measured on this branch (`mix run`, 2026-08-12):

| Source | `operation` | `position` | message |
|---|---|---|---|
| `if "a" { y = 1 }` | `:pop_jump_if_falsy` | `{1, 1}` | `Pop Jump If Falsy requires a boolean, got "a" (string)` |
| `while "a" { y = 1 }` | `:pop_jump_if_falsy` | `{1, 1}` | `Pop Jump If Falsy requires a boolean, got "a" (string)` |
| `"a" and true` | `:jump_if_falsy_or_pop` | `{1, 5}` | `Jump If Falsy OR Pop requires a boolean, got "a" (string)` |
| `"a" or true` | `:jump_if_true_or_pop` | `{1, 5}` | `Jump If True OR Pop requires a boolean, got "a" (string)` |
| `a[true] = 1` | `:store` | `{1, 3}` | `Store requires a string or an integer, got true (boolean)` |
| `1 in 2` | `:in` | `{1, 3}` | `In requires a list, got 2 (integer)` |

Note the humanizer's `or` rule mangles `jump_if_falsy_or_pop`'s own structural
`or` into `OR`, so the `and` case reads as though it were about `or`.

The full set of operation atoms that can reach `TypeMismatchError` is `:in`,
`:contains`, `:jump_if_falsy_or_pop`, `:jump_if_true_or_pop`, `:logical_not`,
`:pop_jump_if_falsy`, `:store`, `:unary_bang`, `:unary_minus`, plus the
arithmetic, comparison and `:bracket_access` operations that already have
clauses. Of the ones without a clause, only the four lowering opcodes name
something with no counterpart in the source language.

Existing assertions that pin the text this plan changes:

- `lib/predicator/errors/type_mismatch_error.ex:73-75` - a doctest on
  `unary/5` pinning `"Store requires a string or an integer, got true
  (boolean)"`
- `test/predicator/execute_test.exs:204` - the same string, end to end
- `test/predicator/evaluator/store_test.exs:119` - the same string, unit level
- `test/predicator/evaluator_test.exs:446` - `msg =~ "Jump If Falsy OR Pop"`
- `test/predicator/evaluator_test.exs:475` - `msg =~ "Jump If True OR Pop"`
- `test/predicator/errors_test.exs:32-61` - the `operation_display_name/1`
  describe block; none of its cases cover the four atoms

## Desired End State

No error message reaching a caller of `Predicator.evaluate/3` or
`Predicator.execute/2` names an instruction opcode with no counterpart in the
source language. After this plan:

| Source | message |
|---|---|
| `if "a" { y = 1 }` | `Condition requires a boolean, got "a" (string)` |
| `while "a" { y = 1 }` | `Condition requires a boolean, got "a" (string)` |
| `"a" and true` | `Logical AND requires a boolean, got "a" (string)` |
| `"a" or true` | `Logical OR requires a boolean, got "a" (string)` |
| `a[true] = 1` | `Assignment requires a string or an integer, got true (boolean)` |

Positions are unchanged: `{1, 1}` for the `if`/`while` cases (px-ij7), `{1, 5}`
for the short-circuit cases, `{1, 3}` for the store. Verified by tests that
assert `position` alongside `message`.

### Key Discoveries:

- The message only owes *what rule was violated*; px-ij7 already decided the
  *position* blames the statement keyword, so the caret tells the reader which
  construct they wrote (`docs/research/260812-px-ij7-if-condition-blame.md:118-121`).
  Construct-neutral wording therefore suffices for `:pop_jump_if_falsy`, and
  the `if`/`while` ambiguity is a non-issue rather than a reason to carry the
  distinction on the instruction.
- This is a change to one function. No opcode is added, removed, renamed, or
  altered, so there is no ISA move under ADR-0003 and no `## ISA Impact`
  section (`.claude/wurk/plan.md`).
- The conformance corpus is unaffected:
  `lib/predicator/conformance/generator.ex:382-383` encodes a
  `TypeMismatchError` as `%{"type" => ..., "reason" => to_string(operation)}` -
  the raw atom, never the display name. `grep -r "Store requires" conformance`
  returns nothing. No `mix corpus.generate` run and no corpus diff to explain.
- `:jump_if_falsy_or_pop` and `:jump_if_true_or_pop` are 1:1 with `and` and
  `or`, so they take the exact strings the existing `:logical_and` /
  `:logical_or` clauses use (`lib/predicator/errors.ex:126-127`). Two atoms
  mapping to one display string is already the established shape there -
  `:unary_bang` and `:logical_not` both render `"Logical NOT"`.
- `:store`'s new name also flows through
  `EvaluationError.insufficient_operands/3`, giving
  `Assignment requires 2 values on stack, got: 1` for a hand-written
  instruction list. `test/predicator/evaluator/store_test.exs:86,93` match on
  `reason`/`operation` only, so nothing breaks there.

## What We're NOT Doing

- **Not changing any position.** px-ij7 settled that a statement's jump
  instructions blame the statement keyword; this plan's tests pin that, they do
  not move it.
- **Not touching the ISA, the compiled format, or the corpus.** No opcode
  changes, so no version, no `docs/isa.md` subsection, no corpus tier, no
  migration note.
- **Not carrying an `if`/`while` discriminator on the instruction.** That was
  the alternative px-ij7 left open; neutral wording plus the existing caret
  makes it unnecessary, and it would turn a one-function change into an ISA
  operand change (ADR-0003).
- **Not renaming `:in`** (nor its twin `:contains`). Decision with reason: `in`
  and `contains` are operators the author literally types, so `"In"` and
  `"Contains"` are capitalizations of source tokens, not leaked opcode names -
  they fall outside the acceptance criterion. Renaming `:in` alone would also
  desync it from `:contains`, which is the same class of operator, for no gain.
  The rendering stays as measured: `In requires a list, got 2 (integer)`. This
  is recorded in the CHANGELOG entry in Phase 2 so the decision survives.
- **Not rewriting the generic humanizer.** Its `or`-upcasing quirk only misfires
  on atoms with a structural `or`, and after Phase 1 every such atom has an
  explicit clause. `test/predicator/errors_test.exs:57-60` pins the humanizer's
  behavior deliberately and stays as-is.
- **No `StringVisitor` round-trip criterion.** `.claude/wurk/plan.md` requires
  it for a new AST/grammar node; this plan adds none.
- **No `## Performance Considerations` section.** Adding pattern-match clauses
  ahead of an existing catch-all is not a performance-relevant change.

## Implementation Approach

Two phases, split at the seam between the library change (which must land with
every already-pinned assertion updated in the same commit, or the gate is red)
and the new end-to-end pinning plus the user-facing changelog. Each phase is
independently committable and each leaves the full gate green.

## Phase 1: Explicit display names for the lowering opcodes

### Overview

Add four clauses to `operation_display_name/1` and bring every existing
assertion that pins the old text into line, so the gate is green on this commit
alone.

### Changes Required:

#### 1. The display-name function

**File**: `lib/predicator/errors.ex`
**Changes**: add four clauses above the generic humanizer (after the
`:bracket_access` clause at line 128), and extend the `@doc` with a doctest
covering one of them.

```elixir
  # Opcodes that exist only as the lowering of a source construct render the
  # construct's name, never their own: an author who wrote `if` never typed
  # `pop_jump_if_falsy` and cannot act on it. The wording is deliberately
  # construct-neutral for :pop_jump_if_falsy, which `if` and `while` share -
  # the error's position already names the keyword (px-ij7).
  def operation_display_name(:pop_jump_if_falsy), do: "Condition"
  def operation_display_name(:jump_if_falsy_or_pop), do: "Logical AND"
  def operation_display_name(:jump_if_true_or_pop), do: "Logical OR"
  def operation_display_name(:store), do: "Assignment"
```

Doctest to add under the existing examples (`lib/predicator/errors.ex:108-115`):

```elixir
      iex> Predicator.Errors.operation_display_name(:pop_jump_if_falsy)
      "Condition"
```

#### 2. The `unary/5` doctest

**File**: `lib/predicator/errors/type_mismatch_error.ex`
**Changes**: line 75's expected value becomes
`{:string, "Assignment requires a string or an integer, got true (boolean)"}`.

#### 3. Existing assertions on the old text

**File**: `test/predicator/evaluator/store_test.exs`
**Changes**: line 119's expected string becomes
`"Assignment requires a string or an integer, got true (boolean)"`.

**File**: `test/predicator/execute_test.exs`
**Changes**: line 204's `message:` becomes
`"Assignment requires a string or an integer, got true (boolean)"`. The
`position: {1, 3}` assertion in the same match stays untouched.

**File**: `test/predicator/evaluator_test.exs`
**Changes**: line 446 becomes `assert msg =~ "Logical AND"` and line 475
becomes `assert msg =~ "Logical OR"`.

#### 4. Unit coverage for the new clauses

**File**: `test/predicator/errors_test.exs`
**Changes**: add a test to the `operation_display_name/1` describe block:

```elixir
    test "formats lowering opcodes as the source construct they came from" do
      assert Predicator.Errors.operation_display_name(:pop_jump_if_falsy) == "Condition"
      assert Predicator.Errors.operation_display_name(:jump_if_falsy_or_pop) == "Logical AND"
      assert Predicator.Errors.operation_display_name(:jump_if_true_or_pop) == "Logical OR"
      assert Predicator.Errors.operation_display_name(:store) == "Assignment"
    end
```

### Success Criteria:

#### Automated Verification:
- [x] `mix quality` is green (format, compile, credo --strict, dialyzer, deps
      audit, suite with coverage)
- [x] `grep -rn "Pop Jump If Falsy\|Jump If Falsy OR Pop\|Jump If True OR Pop" lib test`
      returns no hits (`docs/` may still contain the historical strings and is
      not searched)
- [x] `mix test test/predicator/errors_test.exs` passes - it carries
      `doctest Predicator.Errors`, so it is where the new
      `:pop_jump_if_falsy` doctest runs
- [x] `lib/predicator/errors.ex` stays above the 90% component minimum in
      `coveralls.json`

#### Manual Verification:
- [ ] `mix run` on the six sources in the Current State table shows the Desired
      End State messages, with `:in` unchanged
- [ ] The `and` case no longer reads as though it were about `or`
- [ ] No regression in the arithmetic, unary, or bracket-access messages

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically, and Manual Verification items are deferred and
surfaced once at the end.

---

## Phase 2: End-to-end pinning and the changelog entry

### Overview

Pin the five acceptance-criteria messages at the `Predicator.execute/2` level,
alongside their positions, and record the user-facing change.

### Changes Required:

#### 1. Integration tests for the lowered-construct messages

**File**: `test/predicator/integration/statements_test.exs` (existing
end-to-end statement suite; `if_statement_execution_test.exs`,
`while_execution_test.exs`, and `short_circuit_test.exs` are the alternatives -
one new describe block in `statements_test.exs` keeps the five cases together
so a future reader sees them as one rule)
**Changes**: add a describe block asserting message and position together.

```elixir
  describe "type-mismatch messages name the source construct, not the opcode" do
    test "if blames the keyword and names the condition rule" do
      assert {:error,
              %Predicator.Errors.TypeMismatchError{
                operation: :pop_jump_if_falsy,
                position: {1, 1},
                message: "Condition requires a boolean, got \"a\" (string)"
              }, _ctx} = Predicator.execute(~s|if "a" { y = 1 }|, %{})
    end

    # ... the while, and, or, and store cases in the same shape:
    #   while "a" { y = 1 }  -> :pop_jump_if_falsy, {1, 1}, "Condition requires ..."
    #   "a" and true         -> :jump_if_falsy_or_pop, {1, 5}, "Logical AND requires ..."
    #   "a" or true          -> :jump_if_true_or_pop, {1, 5}, "Logical OR requires ..."
    #   a[true] = 1          -> :store, {1, 3}, "Assignment requires a string or an integer, ..."
  end
```

The store case duplicates `test/predicator/execute_test.exs:204` by design -
that test is about which segment is blamed, this one is about the construct
name - so both stay.

#### 2. Changelog

**File**: `CHANGELOG.md`
**Changes**: an entry under `## [Unreleased]`, in the existing Keep a Changelog
shape, under `### Changed`:

```markdown
- Type-mismatch errors raised by an instruction that only exists as the
  lowering of a source construct now name the construct rather than the
  opcode. `if "a" { y = 1 }` and `while "a" { y = 1 }` report `Condition
  requires a boolean, got "a" (string)` instead of `Pop Jump If Falsy
  requires ...`; `"a" and true` and `"a" or true` report `Logical AND` and
  `Logical OR`, matching their non-short-circuit twins; a failing store
  reports `Assignment requires a string or an integer, got true (boolean)`
  instead of `Store requires ...`. Error positions, the instruction set, and
  the conformance corpus are unchanged. `in` and `contains` keep their
  existing `In` / `Contains` rendering deliberately - both are operators the
  author types, so neither leaks an opcode name.
```

### Success Criteria:

#### Automated Verification:
- [x] `mix quality` is green
- [x] `mix test test/predicator/integration/statements_test.exs` passes with the
      five new cases
- [x] `CHANGELOG.md` contains the new entry under `## [Unreleased]`
- [x] `git diff --name-only` for the branch touches no file under
      `conformance/` (no corpus move to explain under ADR-0003)

#### Manual Verification:
- [ ] The changelog entry reads correctly to someone who did not write the
      change, and states the `:in` decision
- [ ] Sabotaging one new assertion (e.g. reverting the `:store` clause) turns
      the new tests red, confirming they bind what they claim to

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. Same interactive/looped handling as
Phase 1.

---

## Testing Strategy

### Unit Tests:
- `test/predicator/errors_test.exs` - the four new clauses of
  `operation_display_name/1`, asserted directly; the existing humanizer cases
  stay to prove the fallthrough still works for atoms with no clause.
- `test/predicator/evaluator_test.exs` - the two short-circuit type-mismatch
  tests, retargeted at the new text.
- `test/predicator/evaluator/store_test.exs` - the store message, exact match.
- Doctests in `lib/predicator/errors.ex` and
  `lib/predicator/errors/type_mismatch_error.ex`.

### Integration Tests:
- `test/predicator/integration/statements_test.exs` - the five acceptance cases
  through `Predicator.execute/2`, each asserting `operation`, `position`, and
  `message` in one pattern match so a position regression cannot hide behind a
  passing message assertion.

### Manual Testing Steps:
1. `mix run` a script evaluating `if "a" { y = 1 }`, `while "a" { y = 1 }`,
   `"a" and true`, `"a" or true`, `a[true] = 1`, and `1 in 2`; confirm the
   first five match the Desired End State table and the sixth is unchanged.
2. Confirm each error's `position` matches the Current State table - the values
   must not have moved.
3. Evaluate `1 * true` and `-"a"` to confirm the untouched operations still
   render `Arithmetic multiply` and `Unary minus`.

## References

- Source document: `docs/research/260812-px-ij7-if-condition-blame.md`
- Related ADRs: `docs/adr/0003-the-elixir-implementation-leads-the-isa.md` (why
  this is not an ISA move), `docs/adr/0004-no-eval-errors-are-values.md`,
  `docs/adr/0013-control-flow-lowers-to-new-jump-opcodes.md` (the if/while
  lowering)
- Similar implementation: `lib/predicator/errors.ex:118-128` (the existing
  explicit clauses), `docs/plans/260808-px-tbv.11-store-failure-position.md`
  (the last change to a `store` message, including its changelog shape)
- Bead: `px-rck`

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] `mix run` on the six sources in the Current State table shows the Desired
      End State messages, with `:in` unchanged
- [ ] The `and` case no longer reads as though it were about `or`
- [ ] No regression in the arithmetic, unary, or bracket-access messages

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically, and Manual Verification items are deferred and
surfaced once at the end.

---

### Phase 2

- [ ] The changelog entry reads correctly to someone who did not write the
      change, and states the `:in` decision
- [ ] Sabotaging one new assertion (e.g. reverting the `:store` clause) turns
      the new tests red, confirming they bind what they claim to

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. Same interactive/looped handling as
Phase 1.

---
