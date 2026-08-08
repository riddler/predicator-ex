# object_set Non-Map Error Specification Implementation Plan

## Overview

`["object_set", key]` executed against a non-map target crashes with a
`FunctionClauseError` instead of returning an error value. This plan makes that
branch return a well-formed `{:error, %EvaluationError{}}`, and - because the
acceptance criteria were deliberately widened on 2026-08-07 from a bug fix to a
spec change - promotes the behavior from "unspecified" to normative in
`docs/isa.md` section 5, removes the matching carve-out from the conformance
corpus, and adds a corpus case covering it.

Beads issue: **px-pp7** (`area:evaluator`, `area:docs`, `area:conformance`,
`release:4.0.0`).

## Current State Analysis

### The defect

`lib/predicator/evaluator.ex` `execute_object_set/2` has three clauses:

```elixir
defp execute_object_set(%__MODULE__{stack: [value, object | rest]} = evaluator, key)
     when is_map(object) do
  updated_object = Map.put(object, key, value)
  {:ok, %{evaluator | stack: [updated_object | rest]}}
end

defp execute_object_set(%__MODULE__{stack: [_value, _non_object | _rest]} = _evaluator, _key) do
  {:error, "Cannot set property on non-object value"}
end

defp execute_object_set(%__MODULE__{stack: stack} = _evaluator, _key) when length(stack) < 2 do
  {:error, EvaluationError.insufficient_operands(:object_set, length(stack), 2)}
end
```

The middle clause returns a **bare binary** in the error tuple. Every error path
in this evaluator returns an error *struct*, and
`advance_instruction_pointer/1` (`lib/predicator/evaluator.ex:530-535`) is
guarded on exactly that:

```elixir
defp advance_instruction_pointer({:ok, %__MODULE__{} = evaluator}) do ... end

defp advance_instruction_pointer({:error, error_struct}) when is_struct(error_struct),
  do: {:error, error_struct}
```

`{:error, "Cannot set property on non-object value"}` matches neither clause, so
the VM raises rather than returning a value. Reproduced in this worktree:

```
$ mix run -e 'IO.inspect(try do Predicator.Evaluator.evaluate([["lit", 5], ["lit", 1], ["object_set", "k"]], %{}) rescue e -> {:raised, e.__struct__} end)'
{:raised, FunctionClauseError}
```

This is the one open violation of the errors-are-values thesis in `CLAUDE.md`
("errors are values, returned as `{:ok, result} | {:error, ...}` tuples, never
raised at a leaf").

### Reachability

The compiler always emits `["object_new"]` immediately before `["object_set", k]`
(`lib/predicator/visitors/instructions_visitor.ex`; see `test/predicator_test.exs:1114`),
so the target on the stack is always a map for compiled source. The branch is
reachable **only from a hand-built instruction list** - which, per the bead's
2026-08-07 note, is exactly what sibling implementers produce.

### What currently documents it as unspecified

Three places carve this out, and all three must move together:

1. `docs/isa.md` section 5, the `object_set` bullet (around line 380): "**The
   non-map case is unspecified behavior** ... a known defect tracked separately,
   not part of this specification ... a sibling should treat it as undefined
   behavior rather than replicate the exact failure mode."
2. `conformance/README.md`'s "Also out of scope" section (around line 266): the
   `object_set`-on-a-non-map bullet.
3. `test/predicator/conformance/opcode_coverage_test.exs:28-31`, a comment
   pointing at (2) and explaining why that section is deliberately not parsed by
   the test.

Note that (2) sits in "**Also out of scope**", which is explicitly *not* the
"Opcodes excluded from the coverage rule" section - the latter is parsed and
bound by `opcode_coverage_test.exs`'s third assertion, and contains only
`relative_date`. Removing the `object_set` bullet therefore touches no parsed
list and breaks no binding test; only the explanatory comment at (3) needs
updating.

### Existing test coverage

`test/predicator/evaluator_edge_cases_test.exs:77-81` is named "handles object
operations with non-object stack top" but its instruction list is
`[["lit", "not_an_object"], ["object_set", "key"]]` - only **one** value on the
stack, so it lands on the `insufficient_operands` clause, not the non-map
clause. The crashing branch has no test today.

### The precedent for the error shape

`relative_date` is the exact structural analogue - an opcode that pops a value
it needs to be a map, from a hand-built list, and finds something else
(`lib/predicator/evaluator.ex:1410-1417`):

```elixir
defp execute_relative_date(%__MODULE__{stack: [non_duration | _rest]}, _direction) do
  {:error,
   EvaluationError.new(
     "Relative date operation requires a duration on the stack, got: #{inspect(non_duration)}",
     "invalid_stack_value",
     :evaluate
   )}
end
```

`docs/isa.md` section 5 already states this normatively: "a non-map on top of the
stack is `EvaluationError` `\"invalid_stack_value\"`". That is the vocabulary
this repo already uses for "wrong-typed value found on the stack", and
`invalid_stack_value` is the reason token to reuse.

### Constraints

- `CLAUDE.md`: full `mix quality` green before any commit; coverage >90%; the
  gate is not to be weakened.
- ADR-0003: this repo is the reference implementation of the ISA; a change to the
  instruction set owes a version answer, an `docs/isa.md` entry, and a migration
  note if a stored artifact is affected. See **ISA Impact** below.
- `conformance/README.md`: `type` and `reason` in a corpus case are normative;
  the human-readable message never is.
- The corpus is generated, not hand-written: `mix corpus.generate` rebuilds
  `conformance/corpus/tier-*.json` and `conformance/manifest.json` from
  `conformance/cases/*.json`, and `corpus_freshness_test.exs` byte-compares the
  checked-in files against a regeneration.
- **A parallel worktree (px-bay) is editing `CHANGELOG.md` under `## [Unreleased]`
  right now.** See Phase 4 for the conflict-avoidance rule.

## Desired End State

1. `Predicator.Evaluator.evaluate([["lit", 5], ["lit", 1], ["object_set", "k"]], %{})`
   returns `{:error, %Predicator.Errors.EvaluationError{reason: "invalid_stack_value",
   operation: :object_set}}` instead of raising, and carries a source position
   when a position table was supplied.
2. `docs/isa.md` section 5's `object_set` bullet reads as a normative error row
   in the same shape as its neighbors (`relative_date`, `duration`, `divide`),
   with no "unspecified behavior" caveat and no reference to a tracked defect.
3. `conformance/cases/errors.json` carries a case for the non-map target;
   `conformance/corpus/tier-4.json` and `conformance/manifest.json` are
   regenerated (tier-4 `case_count` 14 -> 15, `corpus_hash` moves,
   `isa_version` stays `2`); `conformance/README.md`'s "Also out of scope"
   `object_set` bullet is gone.
4. `CHANGELOG.md` has exactly one new bullet under `## [Unreleased]`.
5. Full `mix quality` is green.

### Key Discoveries

- `lib/predicator/evaluator.ex:530-535` - `advance_instruction_pointer/1`'s
  `is_struct` guard is what turns the bare binary into a `FunctionClauseError`.
- `lib/predicator/evaluator.ex:1285-1288` - the offending clause.
- `lib/predicator/evaluator.ex:1410-1417` - the `relative_date` precedent to copy.
- `docs/isa.md:428` - the normative sentence for `relative_date`'s
  `invalid_stack_value`, the model for the new `object_set` sentence.
- `conformance/cases/errors.json` - the errors group; cases carry only
  `id`, `instructions` (or `source`), `expected`, and optionally `notes`.
- `test/predicator/conformance/opcode_coverage_test.exs:28-31` - the comment that
  must be updated when `conformance/README.md`'s carve-out goes.
- `docs/isa.md` section 1 - the versioning rules that decide the ISA question.

## What We're NOT Doing

- **No ISA version bump.** See ISA Impact; the reasoning is recorded there.
- **No release mechanics.** No `@version` bump in `mix.exs`, no promotion of
  `## [Unreleased]` to a version header, no tag. Per `CLAUDE.md` those require an
  explicit request naming a version. The `release:4.0.0` label says *when this
  ships*, not that this branch cuts the release.
- Not changing `object_set`'s success path, its operand shape, its pops/pushes,
  or its tier.
- Not touching `relative_date`'s error, `divide`'s, or any other opcode's - the
  only reason token in play is the one being reused.
- Not adding a `TypeMismatchError` variant for `object_set` (see the decision
  note in Phase 1).
- Not refreshing any sibling's ratchet registry. `corpus_hash` moving is
  ordinary "corpus drift under a pinned version" per `conformance/RATCHET.md`;
  each sibling re-pins on its own schedule.
- Not fixing the misleading name of the existing
  `evaluator_edge_cases_test.exs` "non-object stack top" test beyond what Phase 1
  needs (a new, correctly-shaped test is added beside it).
- Not editing any other part of `CHANGELOG.md` (px-bay conflict avoidance).

## Implementation Approach

Four phases, each independently gate-verifiable, in dependency order: the
evaluator change first (it is what the spec then describes), the spec second,
the corpus third (its generated expectation is computed by the evaluator from
Phase 1, so it cannot precede it), the changelog last and alone so the
conflict-prone file is touched in one small commit.

Phases 2-4 are documentation-only and could be one commit; they are kept
separate because they map onto three different `area:` labels and three
different review concerns.

## Phase 1: Return a well-formed error from `object_set`

### Overview

Replace the bare-binary error with an `EvaluationError` matching the
`relative_date` precedent, and cover the branch with tests.

### Changes Required:

#### 1. The evaluator clause

**File**: `lib/predicator/evaluator.ex` (the middle `execute_object_set/2` clause,
around line 1285)

**Changes**: return an `EvaluationError` struct instead of a binary. Keep the
clause's position in the clause order - the `is_map(object)` success clause still
comes first, and the `length(stack) < 2` clause still comes last, so stack-depth
checking and type checking keep their current relationship.

```elixir
defp execute_object_set(%__MODULE__{stack: [_value, non_object | _rest]}, _key) do
  {:error,
   EvaluationError.new(
     "Object set requires a map on the stack, got: #{inspect(non_object)}",
     "invalid_stack_value",
     :object_set
   )}
end
```

Three deliberate choices, recorded so review does not have to re-derive them:

- **`EvaluationError`, not `TypeMismatchError`.** The acceptance criteria name
  `EvaluationError` explicitly, and `relative_date` - the one existing opcode
  with the identical shape of failure (popped a value that had to be a map, got
  something else, only reachable from a hand-built list) - already reports
  `EvaluationError`/`invalid_stack_value`. `docs/isa.md` section 2's "a
  boolean-expecting opcode handed a non-boolean is a `TypeMismatchError`" is
  about opcodes performing a typed *operation* on a surface-reachable operand;
  this is a structural precondition on a stack slot the compiler always
  populates. Matching `relative_date` keeps the reason vocabulary small, which is
  what siblings reproduce.
- **Reason `"invalid_stack_value"`**, reused verbatim rather than minting a new
  token, for the same reason.
- **Operation `:object_set`**, not `relative_date`'s `:evaluate`. The other
  `object_set` clause already reports `operation: :object_set` via
  `EvaluationError.insufficient_operands/3`, so the two error paths of one opcode
  agree. `Predicator.Errors.operation_display_name/1` has no explicit clause for
  `:object_set` and falls through to its generic humanizer
  (`lib/predicator/errors.ex:130`), which is fine - it is only used by
  `insufficient_operands/3`, and the message here is written literally.

The clause's `= _evaluator` binding is dropped since the evaluator is unused, and
`non_object` is bound so the message can name the offending value.

#### 2. Tests

**File**: `test/predicator/evaluator_edge_cases_test.exs`

**Changes**: add a test beside the existing "handles object operations with
non-object stack top" that puts **two** values on the stack so the non-map clause
is actually reached, and asserts the struct rather than `match?({:error, _}, ...)`:

```elixir
test "object_set on a non-map target returns an EvaluationError, not a crash" do
  instructions = [["lit", 5], ["lit", 1], ["object_set", "key"]]

  assert {:error, %EvaluationError{reason: "invalid_stack_value", operation: :object_set}} =
           Evaluator.evaluate(instructions, %{})
end
```

Add a second test asserting the *insufficient operands* path still reports
`"insufficient_operands"` (the existing one-value case), so the clause ordering
is pinned and a future edit cannot silently reroute a short stack into the new
branch.

Add a third test confirming the error flows through
`advance_instruction_pointer/1` normally - i.e. that a position is attached when
a position table is supplied, the way every other struct error is:

```elixir
test "object_set's non-map error carries a source position when one is available"
```

Build the position table by hand (the compiler cannot produce this instruction
list); assert `:position` is non-`nil`. If attaching a position turns out to
require a code change rather than falling out of the existing
`attach_error_position/2` path, that is a finding to report, not a reason to
weaken the assertion - the whole point of the fix is that this error path is now
ordinary.

### Success Criteria:

#### Automated Verification:
- [x] `mix quality --profile loop` green while iterating
- [x] Full gate passes: `mix quality` (a pre-existing test,
      `test/predicator/conformance/generator_test.exs`'s "evaluation that
      raises is a generator error, not a crash" case, assumed
      `object_set` on a non-map still crashed; updated to use
      `[["lit", :foo], ["unary_minus"]]` instead, which still genuinely
      raises `FunctionClauseError` via `get_value_type/1` having no atom
      clause - see finding recorded below)
- [x] Coverage for `lib/predicator/evaluator.ex` stays above the 90% floor in
      `coveralls.json` (91.1%)
- [x] No `TypeMismatchError` appears anywhere in the diff (the shape decision
      above held)

#### Manual Verification:
- [ ] `mix run -e 'IO.inspect(Predicator.Evaluator.evaluate([["lit", 5], ["lit", 1], ["object_set", "k"]], %{}))'`
      prints an `{:error, %EvaluationError{}}` tuple and does not raise
- [ ] The message reads naturally next to `relative_date`'s
      ("Relative date operation requires a duration on the stack, got: ...")
- [ ] A compiled object literal (`Predicator.evaluate("{a: 1}.a", %{})`) is
      unaffected

**Implementation Note**: Use `mix quality --profile loop` between edits; run the
full `mix quality` as the phase gate. Under `--loop` execution the Manual
Verification items are deferred and surfaced at the end.

---

## Phase 2: Make the behavior normative in `docs/isa.md`

### Overview

Rewrite section 5's `object_set` bullet as a normative error row in the shape its
neighbors use.

### Changes Required:

#### 1. Section 5, the `object_set` bullet

**File**: `docs/isa.md` (around line 380)

**Changes**: delete the "unspecified behavior" sentence, the "known defect
tracked separately" clause, and the "a sibling should treat it as undefined
behavior" instruction. Replace with a normative statement modeled on
`relative_date`'s. Target shape:

> - **`object_set`** (`execute_object_set/2`) - pops the value (stack top) and
>   the object beneath it, pushes the object with `key` set to that value. Fewer
>   than two values on the stack is `EvaluationError` insufficient operands. A
>   non-map beneath the value is `EvaluationError` `"invalid_stack_value"`,
>   checked after the stack-depth check. The compiler only ever emits
>   `object_set` immediately after `object_new`, so the non-map case is
>   reachable only from a hand-built instruction list - but it is specified, not
>   undefined: a sibling implements it to claim tier 4.

Keep the existing sentence about the compiler always emitting `object_new`
first - it is still true and still useful context for an implementer. What goes
is only the claim that the case is unspecified.

**House style**: `docs/isa.md` uses hyphens, not em dashes. Match it.

#### 2. Nothing else in `docs/isa.md`

The section 4 opcode table row for `object_set` is unchanged - error semantics are
explicitly not a table column ("Error semantics are not a table column", section
4 preamble). Section 1's "Current version: **ISA v2**" is unchanged. Section 7's
version-history table is unchanged. See ISA Impact for why.

### Success Criteria:

#### Automated Verification:
- [ ] Full gate passes: `mix quality` (`isa_sync_test.exs` and the doc tests
      still pass)
- [ ] `grep -n "unspecified" docs/isa.md` no longer returns an `object_set` hit

#### Manual Verification:
- [ ] The rewritten bullet reads as a peer of the `relative_date` and `duration`
      bullets, not as a changelog entry
- [ ] No remaining sentence in `docs/isa.md` tells a sibling that any
      `object_set` shape is undefined

---

## Phase 3: Remove the corpus carve-out and add the case

### Overview

Author one case in the errors group, regenerate the corpus, and delete the
`conformance/README.md` carve-out plus the test comment that points at it.

### Changes Required:

#### 1. The authored case

**File**: `conformance/cases/errors.json`

**Changes**: append one case. `instructions`-only (there is no source that
compiles to this shape), matching the `errors/unary-bang-type-mismatch` and
`errors/insufficient-operands-bracket-access` style:

```json
{
  "id": "errors/object-set-non-map-target",
  "instructions": [["lit", 5], ["lit", 1], ["object_set", "key"]],
  "expected": {
    "error": { "type": "EvaluationError", "reason": "invalid_stack_value" }
  },
  "notes": "docs/isa.md section 5: object_set's target must be a map. Reachable only from a hand-built instruction list - the compiler always emits object_new immediately before object_set - but specified, not undefined. Shares the invalid_stack_value reason with relative_date's non-duration case."
}
```

The `id` is stable forever once shipped (`conformance/README.md`), so it is worth
getting right the first time: `errors/object-set-non-map-target`.

Do **not** hand-write `tier` or `features`; the generator computes them
(`Predicator.Conformance.Generator`, `Predicator.Conformance.Features` -
`"object_set" => ~w(objects)`, `lib/predicator/conformance/features.ex:51`). The
case lands in tier 4 because `object_set` is a tier-4 opcode.

#### 2. Regenerate

**Command**: `mix corpus.generate`

**Expected diff**: `conformance/corpus/tier-4.json` gains one line;
`conformance/manifest.json`'s tier-4 `case_count` goes 14 -> 15 and `corpus_hash`
changes. `isa_version` stays `2`. If generation fails naming this case, the
authored `expected` disagrees with what Phase 1 actually produces - fix the case
or the code, do not force the generator.

#### 3. Delete the carve-out

**File**: `conformance/README.md` (the "Also out of scope" section, around line
266)

**Changes**: delete the `object_set`-on-a-non-map bullet entirely. Leave the
section's remaining content - the ordering-comparison-between-maps paragraph and
the `on_unbound` note - intact. If the bullet was the section's only list item,
check whether the surrounding prose still reads correctly and adjust the lead-in
sentence minimally; do not delete the section, which the map-ordering paragraph
still needs.

Do **not** touch the "Opcodes excluded from the coverage rule" section - it is
parsed and bound by `opcode_coverage_test.exs` and contains only `relative_date`,
which is unaffected.

#### 4. Update the stale comment

**File**: `test/predicator/conformance/opcode_coverage_test.exs:28-31`

**Changes**: the comment currently reads

```elixir
# docs/isa.md section 5 / plan Open Question #2. object_set on a non-map
# is a separate, non-opcode exclusion (object_set itself is covered via its
# normal post-object_new form) - see conformance/README.md's "Also out of
# scope" section, which is deliberately not parsed by this test.
@excluded_opcodes ~w(relative_date)
```

Drop the `object_set` sentences; keep the `relative_date` justification. The
`@excluded_opcodes` value itself does **not** change - `object_set` was never in
it.

### Success Criteria:

#### Automated Verification:
- [ ] `mix corpus.generate` succeeds and writes a diff to
      `conformance/corpus/tier-4.json` and `conformance/manifest.json`
- [ ] Full gate passes: `mix quality` - in particular
      `corpus_freshness_test.exs` (checked-in corpus byte-matches a
      regeneration), `opcode_coverage_test.exs` (all three assertions), and
      `generator_test.exs`
- [ ] `mix corpus.generate --check` exits zero
- [ ] `conformance/manifest.json` shows `"isa_version":2` unchanged and tier-4
      `case_count` 15

#### Manual Verification:
- [ ] The generated tier-4 line's `expected_error` reads
      `{"type":"EvaluationError","reason":"invalid_stack_value"}` - i.e. the
      generator agreed with the authored assertion rather than overwriting a
      different one
- [ ] `conformance/README.md`'s "Also out of scope" section still reads as
      coherent prose after the deletion
- [ ] No sibling-facing document still describes this shape as uncovered

---

## Phase 4: Changelog

### Overview

One bullet, one file, deliberately minimal - a parallel worktree (px-bay) is
editing the same section.

### Changes Required:

#### 1. The entry

**File**: `CHANGELOG.md`

**Changes**: add **exactly one bullet**, appended as the **last bullet of the
existing `### Changed` subsection under `## [Unreleased]`** - that is,
immediately before the `### Removed` header. Change nothing else in the file: no
reflowing, no reordering, no touching other subsections.

Rationale for the placement, which is a conflict-avoidance decision rather than a
taxonomy one: px-bay is an `area:docs` bead rewriting
`docs/reference/language.md` (undefined/sparse-data semantics, plus a wrong
division row), so its changelog bullet will most plausibly land under
`### Documentation` or `### Fixed`. `### Changed` is the least contended
subsection, and it already carries the precedent entry for a spec move
("`docs/isa.md` now specifies opcode retirement mechanics ..."), which this is the
sibling of. Appending at the end of a subsection rather than the top also keeps
the conflict hunk away from a section header, which is what makes a three-way
merge trivial.

Draft text (hyphens, matching the file's house style):

```markdown
- `object_set` on a non-map target is now specified behavior. The evaluator
  returns `%Predicator.Errors.EvaluationError{}` with reason
  `"invalid_stack_value"` and operation `:object_set` instead of raising a
  `FunctionClauseError`, matching how `relative_date` reports a non-duration on
  the stack. `docs/isa.md` section 5 states it normatively rather than calling
  it unspecified, and the conformance corpus covers it in the errors group - so
  a sibling implementation must now produce this error to claim tier 4. The
  shape is reachable only from a hand-built instruction list; the compiler
  always emits `object_new` immediately before `object_set`, so nothing
  compiled from source changes.
```

### Success Criteria:

#### Automated Verification:
- [ ] Full gate passes: `mix quality`
- [ ] `git diff --stat CHANGELOG.md` shows insertions only, and only in one hunk

#### Manual Verification:
- [ ] `git diff CHANGELOG.md` shows a single added hunk with no incidental
      whitespace or reflow changes anywhere else in the file
- [ ] The bullet tells a sibling implementer what they now owe, which is the
      point of the entry

---

## Testing Strategy

### Unit Tests:
- `test/predicator/evaluator_edge_cases_test.exs` - the non-map branch returns
  `EvaluationError`/`invalid_stack_value`/`:object_set`; the short-stack branch
  still returns `insufficient_operands` (clause ordering pinned); the error
  carries a position when a position table is supplied.
- Assert on the struct's fields, not `match?({:error, _}, ...)`. The existing
  neighbouring test uses the loose form and is exactly why the defect survived:
  a crash and an error are indistinguishable to a test that never runs the
  clause it names.

### Integration Tests:
- The conformance corpus case is the integration test for the cross-language
  contract: `errors/object-set-non-map-target` in tier 4, generated by running
  the real evaluator, byte-pinned by `corpus_freshness_test.exs`.
- No new `test/predicator/integration/` case is needed - the shape is
  unreachable from source, so there is no `Predicator.evaluate/3` string form of
  it.

### Manual Testing Steps:
1. `mix run -e 'IO.inspect(Predicator.Evaluator.evaluate([["lit", 5], ["lit", 1], ["object_set", "k"]], %{}))'`
   - returns an error tuple, does not raise.
2. `mix run -e 'IO.inspect(Predicator.evaluate("{name: \"x\"}.name", %{}))'` -
   the ordinary compiled path is unaffected.
3. Read the rewritten `docs/isa.md` bullet beside `relative_date`'s and confirm
   they read as peers.
4. `git diff CHANGELOG.md` - one hunk, insertions only.

## ISA Impact

**Version: no bump. This lands at ISA v2 and `docs/isa.md` section 1's "Current
version: **ISA v2**" is unchanged.**

The reasoning, against section 1's own rules:

- **No opcode is added and none is retired.** Section 1 mints an integer for
  exactly two events: a new opcode (additive, minor release) and a retirement
  (major release plus upgrade path). Neither happens here.
  `Predicator.Instructions.opcode_set/1` and `required_isa/1` return exactly what
  they returned before, which is the property that makes "scan the opcode names"
  a sound version answer.
- **"An opcode's semantics never change under its own name"** governs a changed
  *answer* for a program that previously had a defined one. No such program
  exists here: the previous behavior was a crash, and `docs/isa.md` said in
  writing that it was unspecified. Specifying a previously-unspecified case
  changes no conforming program's result, so nothing needs a new name.
- **There is direct precedent.** Section 1 records that "3.8.0 then refined v2
  semantics without adding an opcode (it made every arithmetic and legacy
  logical opcode report an unbound root rather than a type mismatch)". That was a
  broader error-reporting refinement across many opcodes and it did not mint v3.
  This change is strictly narrower.
- **"Adding an operand form or widening an accepted type is a new version"** does
  not apply: `object_set`'s operand shape is unchanged and no accepted type is
  widened. If anything the specification *narrows* what is legal input, and it
  narrows it to a case that already failed.

**Stamp**: `docs/isa.md` section 5's `object_set` bullet gains a normative error
sentence (Phase 2). No new opcode subsection, no tier change - `object_set` stays
tier 4. The conformance corpus gains one tier-4 case in the errors group.

**Migration**: none. Any instruction list compiled before this change still runs
and still produces the same answer - the compiler never emits the affected shape.
The only artifact that moves is `conformance/manifest.json`'s `corpus_hash`,
which is ordinary "corpus drift under a pinned version" per
`conformance/RATCHET.md`; a sibling re-pins on its own schedule, and no registry
entry becomes invalid because no existing case's expectation changed.

**Sibling consequence, recorded deliberately** (the bead's 2026-08-07 note
accepts this cost): a sibling claiming tier 4 must now produce
`EvaluationError`/`invalid_stack_value` for a non-map `object_set` target, where
today the behavior was free. That is a conformance-ratchet obligation carried by
`corpus_hash`, not by the ISA integer. A sibling behind the current corpus is an
expected, documented state (ADR-0003).

**Release**: the bead carries `release:4.0.0`, which says *when this ships*, not
that this branch cuts a release. Per `CLAUDE.md`, bumping `@version` in `mix.exs`
and promoting `## [Unreleased]` are release mechanics requiring an explicit
request naming a version, and are out of scope here.

## Open Questions

Recorded rather than blocking, since no human was available during planning. None
of these prevents implementation; each has a stated default that the plan takes.

1. **`EvaluationError` vs `TypeMismatchError`.** The acceptance criteria name
   `EvaluationError` and `relative_date` is the precedent, so the plan takes
   `EvaluationError`/`invalid_stack_value`. But `docs/isa.md` section 2 states
   "Opcodes validate, they do not coerce ... a boolean-expecting opcode handed a
   non-boolean is a `TypeMismatchError`", which a reader could apply here.
   **Default taken:** `EvaluationError`, reason `invalid_stack_value`, on the
   `relative_date` precedent and the explicit AC wording. If a reviewer prefers
   `TypeMismatchError`, the change is one function call in Phase 1, one sentence
   in Phase 2, and one token in the Phase 3 case.
2. **Changelog subsection.** The plan places the bullet at the end of
   `### Changed`, reasoning that px-bay (a `docs/reference/language.md` bead)
   will land in `### Documentation` or `### Fixed`. If px-bay has already pushed
   by the time this phase runs, re-check its actual hunk and pick the
   least-contended subsection then; the requirement is one self-contained bullet,
   not this specific subsection.
3. **Position attachment.** Phase 1 assumes the new struct error picks up a
   source position through the existing `attach_error_position/2` path with no
   code change, since it is now an ordinary struct error. Not verified during
   planning. If it does not, report it - do not weaken the test.

## References

- Beads issue: `px-pp7` (AC widened 2026-08-07 from bug fix to spec change)
- `lib/predicator/evaluator.ex:530-535` - `advance_instruction_pointer/1`
- `lib/predicator/evaluator.ex:1285-1288` - the offending `execute_object_set/2`
  clause
- `lib/predicator/evaluator.ex:1410-1417` - `execute_relative_date/2`, the
  precedent
- `lib/predicator/errors/evaluation_error.ex` - `new/3` and
  `insufficient_operands/3`
- `docs/isa.md` section 1 (versioning), section 2 (execution model, error
  types), section 4 (opcode table), section 5 (`object_set`, `relative_date`)
- `conformance/README.md` - "Error type and reason are normative", "Also out of
  scope", "How to add a case"
- `conformance/RATCHET.md` - corpus drift under a pinned version
- `conformance/cases/errors.json` - the errors group
- `test/predicator/conformance/opcode_coverage_test.exs:28-31` - the stale
  comment
- `test/predicator/evaluator_edge_cases_test.exs:77-81` - the existing,
  mis-shaped test
- ADR-0003 (`docs/adr/0003-the-elixir-implementation-leads-the-isa.md`) - this
  repo leads the ISA; sibling parity is downstream
- ADR-0001 (`docs/adr/0001-keep-the-stack-vm-revise-the-instruction-set.md`) -
  the 3.6-4.0 arc
- Prior plan: `docs/plans/260806-px-35i.2-isa-reference.md` (Open Question 1 is
  where this defect was first recorded)
- Prior plan: `docs/plans/260807-px-35i.4-conformance-corpus.md`

## Deferred Manual Verification

### Phase 1

- [ ] `mix run -e 'IO.inspect(Predicator.Evaluator.evaluate([["lit", 5], ["lit", 1], ["object_set", "k"]], %{}))'`
      prints an `{:error, %EvaluationError{}}` tuple and does not raise
- [ ] The message reads naturally next to `relative_date`'s
      ("Relative date operation requires a duration on the stack, got: ...")
- [ ] A compiled object literal (`Predicator.evaluate("{a: 1}.a", %{})`) is
      unaffected
