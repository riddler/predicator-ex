# Protected context roots Implementation Plan

## Overview

Add an opt-in `:protected_roots` evaluation option so a host can name context
roots a program may not write. A `store` whose root segment is protected
returns an `EvaluationError` (reason `"protected_root"`, operation `:store`)
carrying the root as structured data instead of performing the write, and the
run halts there with the ordinary partial context. Absent the option nothing
changes. Bead: px-1xy (mirrors st-i9d).

## Current State Analysis

**The write path.** `store` is the only opcode that writes the context
(`docs/isa.md` §5). `Predicator.Evaluator.execute_store/2`
(`lib/predicator/evaluator.ex:1491`) pops the value and `n` segments, reverses
the segments into root-first path order, runs `validate_store_segments/1`
(`lib/predicator/evaluator.ex:1541`, segments must be binary or integer), and
then hands off to `do_store/4` (`lib/predicator/evaluator.ex:1515`), which
calls `Predicator.ContextLocation.put/3`. There is no seam between the
validated path and the write, which is exactly the gap the bead describes: a
host cannot refuse a write from outside, and a diff after the fact is both late
(later statements in the same program already read the value) and incomplete (a
write-then-restore is invisible).

**How an evaluation option is plumbed today.** `:loop_budget` is the exact
precedent and the pattern this plan copies:

- a struct field with a literal default (`lib/predicator/evaluator.ex:86`) and
  a `@type t` entry (`lib/predicator/evaluator.ex:47`);
- a public reader/validator, `Evaluator.loop_budget_from_opts/1`
  (`lib/predicator/evaluator.ex:250`), which raises `ArgumentError` on a
  malformed value - host-API misuse is not a predicate-derived failure
  (ADR-0004), the same line `Predicator.Context.new/2` draws for a bad
  `:on_unbound`;
- two struct-build sites read it: `Predicator.Evaluator.evaluate/3`
  (`lib/predicator/evaluator.ex:324-333`, expression mode over a raw
  instruction list) and `Predicator.build_evaluator/3`
  (`lib/predicator.ex:236-247`), which is what **both** `evaluate/3` and the
  whole `execute` family funnel through (`lib/predicator.ex:251`,
  `lib/predicator.ex:555`);
- it is documented in `Predicator.Evaluator.evaluate/3`'s option list
  (`lib/predicator/evaluator.ex:301-305`) and in `docs/isa.md` §2 as an
  implementation-local option (`docs/isa.md:102-110`).

`Predicator.execute/3` (`lib/predicator.ex:409-415`) delegates to
`execute_value/3` (`lib/predicator.ex:473-505`), which reaches
`execute_instructions/3` (`lib/predicator.ex:554`) and therefore
`build_evaluator/3`. So a single new read in `build_evaluator/3` covers
`execute/3`, `execute_value/3`, and `evaluate/3`'s `%Context{}`/map paths at
once - the plumbing the bead says already exists.

**The error family.** Five structs in `lib/predicator/errors/`.
`EvaluationError` (`lib/predicator/errors/evaluation_error.ex`) carries
`message`, `reason`, `operation`, `position`, `span` and has **no field for
structured, error-specific data**, so an `EvaluationError` naming a root today
would only name it inside `message` - which is precisely the string matching
the bead rules out. `LocationError` already models the answer: a `details` map
(`lib/predicator/errors/location_error.ex:58-64`), read by `do_store/4` for
`:path_index`.

**Error positioning.** `execute_store/2` reports failures through `located/3`
(`lib/predicator/evaluator.ex:1595`), which joins a 0-based path index with the
run's `segment_positions` table so the caret lands on the failing segment
rather than the store instruction (px-ids). A protected-root refusal blames
path index `0`, the root.

**Partial context.** `execute_instructions/3`'s error arm already returns
`{:error, error, %{context | data: final.context}}` (`lib/predicator.ex:561`),
so every write made before the refusal survives with no change here. This is
the SCXML 4.9 shape the bead wants, and it is already correct.

**The ISA position - confirmed, and why this plan carries no `## ISA Impact`
section.** `.claude/wurk/plan.md` requires that section only when a change
"adds, removes, renames, or alters an opcode". This change does none: it adds
no opcode, removes none, renames none, and changes no wire format. Its
closest kin are the two options `docs/isa.md` §2 already declares
implementation-local rather than normative - `on_unbound` (`docs/isa.md:133`)
and the loop budget (`docs/isa.md:102-110`), where only the *existence* of a
bound and the exhaustion reason are normative. `:protected_roots` is the same
kind of thing: absent the option, `store`'s behavior is byte-identical, so a
sibling at ISA v6 without it still conforms. **Conclusion: the ISA version does
not move (stays 6), `docs/isa.md` §1's version table is untouched, no
migration is needed - a program compiled before this change runs identically -
and the closing report says the ISA did not move.** What `docs/isa.md` does owe
is prose: a §2 bullet placing the option outside the ISA and a sentence in §5's
`store` subsection, both added in Phase 2.

**The conformance corpus is untouched, and cannot express this.** An authored
case (`conformance/schema/case.json`) carries `source`/`instructions`,
`context`, `expected`, `tier`, and `features` - and no evaluation options at
all, which is why `on_unbound` and `loop_budget` have no corpus cases either. A
refusal is only reachable through a host option, so no case can observe it and
`mix corpus.generate` produces no diff. `test/predicator/isa_sync_test.exs` and
the corpus freshness/opcode-coverage binding tests key on the opcode list,
which does not move, so no `gate.sabotage.test_roots` entry changes.

## Desired End State

```elixir
{:error, %Predicator.Errors.EvaluationError{
   reason: "protected_root",
   operation: :store,
   details: %{root: "_event"}
 }, partial_context} =
  Predicator.execute("x = 1; _event.name = 'boom'; y = 2",
                     %{}, protected_roots: ["_event"])

partial_context.data == %{"x" => 1}
```

Verified by: the new unit and integration tests below; the doctests in
`Predicator.execute/3`'s option list; and `mix quality` green, with the option
absent from every other test in the suite still producing today's results
(the byte-identical guarantee).

### Key Discoveries:

- `execute_store/2` at `lib/predicator/evaluator.ex:1491`, with the exact seam
  between `validate_store_segments/1` returning `:ok` and `do_store/4` running.
- `Evaluator.loop_budget_from_opts/1` at `lib/predicator/evaluator.ex:250` is
  the template for an option that is read, validated, raises `ArgumentError`
  on misuse (ADR-0004), and lands on the struct.
- `Predicator.build_evaluator/3` at `lib/predicator.ex:236` is the single
  funnel for `evaluate/3` and the whole `execute` family; only it and
  `Evaluator.evaluate/3` (`lib/predicator/evaluator.ex:324`) build the struct
  from opts.
- `LocationError`'s `details` map (`lib/predicator/errors/location_error.ex:61`)
  is the in-repo precedent for structured, host-readable error data.
- `located/3` (`lib/predicator/evaluator.ex:1595`) is how a store error gets a
  per-segment position; index `0` is the root.
- ADR-0004 (errors are values) governs the refusal itself; the malformed-option
  raise is the deliberate exception the repo already makes for host-API misuse.
- `docs/isa.md:102-110` and `docs/isa.md:133` are the two "this option is not
  part of the ISA" precedents the new §2 bullet is modeled on.

## What We're NOT Doing

- **No pre-execution scan of assignment targets.** The bead rejects it: it
  fires on assignments inside branches that never run, and it still cannot make
  the write itself fail.
- **No per-path protection.** Root-segment matching only, as the bead specifies
  (`_event.name` is refused because `_event` is protected; there is no way to
  protect `_event.name` while leaving `_event.other` writable). Widening this
  later is additive.
- **No new error struct.** A fourth VM-escaping error type would contradict
  `docs/isa.md:127-130`, which fixes the normative set at `EvaluationError`,
  `TypeMismatchError`, `UndefinedVariableError`, and would ripple into the
  corpus schema. The bead's acceptance criteria names `EvaluationError`
  explicitly, so the machine-readable root rides on a `details` map instead.
  The narrower alternative - a bare `:root` field on `EvaluationError` - was
  considered and declined: `details` mirrors `LocationError`, keeps the general
  struct free of one opcode's vocabulary, and is extensible without another
  field per future reason.
- **No `%Predicator.Context{}` field.** `on_unbound` and `host` live on the
  context because they are properties of the *binding*; `:protected_roots` is a
  property of *this run's* policy, like `:loop_budget`, and lives on the
  evaluator. A host that wants it on every run passes it in every call's opts,
  the same as `:loop_budget`.
- **No change to `Predicator.evaluator/2`** (`lib/predicator.ex:1019`), which
  takes no opts at all; a caller at that level sets the struct field directly.
- **No normalization of root names** (no atom coercion, no downcasing).
  `Context.new/2` already normalizes data keys to strings and store segments
  are binaries, so exact binary equality is the whole comparison.
- **No corpus case, no ISA version bump, no `## ISA Impact` section** - see the
  ISA position above.
- **No change to the partial-context contract.** The error arm already returns
  everything written before the failing statement; this plan adds tests
  asserting it for the new error and touches no code there.

## Implementation Approach

Two phases, split at the code/documentation seam rather than along the
pipeline - the pipeline seams (`lexer -> parser -> compiler -> evaluator`) are
not crossed here at all, because nothing about the grammar or the emitted
instructions changes.

Phase 1 is one commit because its parts are not independently gate-verifiable:
an `EvaluationError` field with no producer, or an option that lands on the
struct with nothing reading it, would leave dead code that the coverage
threshold in `coveralls.json` (>90%) and Credo would both have an opinion
about, and neither half is observable on its own. Phase 2 is separable: it
changes documentation and the changelog only, and its doctests gate it.

## Phase 1: The refusal

### Overview

`EvaluationError` gains an optional `details` map; the evaluator gains a
`protected_roots` field, a validating reader, and the refusal check inside
`execute_store/2`; both struct-build sites read the option.

### Changes Required:

#### 1. Structured error data

**File**: `lib/predicator/errors/evaluation_error.ex`
**Changes**: Add an optional `details` field (default `nil`), document it as
host-facing structured data that saves a caller from parsing `message`, and add
a constructor for the protected-root case. `new/3`'s existing signature and
behavior are unchanged, so every existing call site keeps working and every
existing error keeps `details: nil`.

```elixir
defstruct [:message, :reason, :operation, :position, :span, :details]

@type t :: %__MODULE__{
        ...,
        details: map() | nil
      }

@doc """
Creates an evaluation error for a `store` refused by the `:protected_roots`
evaluation option.

`details.root` carries the offending root as data, so a host maps this onto
its own error vocabulary without matching on `message` (messages are
non-normative, `docs/isa.md` §2).
"""
@spec protected_root(binary()) :: t()
def protected_root(root) do
  %__MODULE__{
    message: "Cannot assign to protected context root '#{root}'",
    reason: "protected_root",
    operation: :store,
    details: %{root: root}
  }
end
```

#### 2. The option on the evaluator

**File**: `lib/predicator/evaluator.ex`
**Changes**: Add `protected_roots: []` to `defstruct` (a literal default, next
to `loop_budget`), add `protected_roots: [binary()]` to `@type t`, and add the
public reader beside `loop_budget_from_opts/1`.

```elixir
@doc """
Reads and validates the `:protected_roots` evaluation option.

A list of root names (binaries) a `store` may not write. Default `[]` - the
empty list is the "option absent" case and costs one `Enum.member?/2` against
an empty list per store.

Raises `ArgumentError` for anything that is not a list of binaries - host-API
misuse, not a predicate-derived failure (ADR-0004), the same line
`loop_budget_from_opts/1` and `Predicator.Context.new/2` draw.
"""
@spec protected_roots_from_opts(keyword()) :: [binary()]
def protected_roots_from_opts(opts) do
  case Keyword.get(opts, :protected_roots, []) do
    roots when is_list(roots) ->
      if Enum.all?(roots, &is_binary/1) do
        roots
      else
        raise ArgumentError,
              "protected_roots must be a list of strings, got: #{inspect(roots)}"
      end

    other ->
      raise ArgumentError,
            "protected_roots must be a list of strings, got: #{inspect(other)}"
  end
end
```

Also extend `Predicator.Evaluator.evaluate/3`'s `opts` documentation (the list
at `lib/predicator/evaluator.ex:270-305`) with a `:protected_roots` entry, and
read it in the struct it builds (`lib/predicator/evaluator.ex:324-333`):

```elixir
protected_roots: protected_roots_from_opts(opts)
```

#### 3. The refusal itself

**File**: `lib/predicator/evaluator.ex` (`execute_store/2`, ~line 1491)
**Changes**: Between a `:ok` from `validate_store_segments/1` and `do_store/4`,
refuse a protected root. Segment-type validation stays **first**, so the error
precedence is deterministic and unchanged for every non-protected program: a
path whose root is not even a string is still a `TypeMismatchError`. The
refusal blames path index `0` through `located/3`, so it picks up the root
segment's own position when the run carries a segment table.

```elixir
case validate_store_segments(path) do
  :ok ->
    store_or_refuse(evaluator, path, value, rest)

  {:error, error, index} ->
    located(evaluator, error, index)
end

# The one place a host's write policy can stop a write: `store` is the only
# opcode that writes the context (docs/isa.md section 5), so refusing here
# refuses everywhere. Protection is per-root, not per-path - the root segment
# is the whole comparison - and the check runs after segment validation so a
# malformed path still reports its type error first. Index 0 is the root, which
# is the segment `located/3` points the caret at.
@spec store_or_refuse(t(), ContextLocation.location_path(), Types.value(), [Types.value()]) ::
        {:ok, t()} | {:error, term()}
defp store_or_refuse(%__MODULE__{protected_roots: roots} = evaluator, [root | _rest_path] = path, value, rest)
     when is_binary(root) do
  if root in roots do
    located(evaluator, EvaluationError.protected_root(root), 0)
  else
    do_store(evaluator, path, value, rest)
  end
end

defp store_or_refuse(evaluator, path, value, rest) do
  do_store(evaluator, path, value, rest)
end
```

The fallback clause covers the two paths with no protectable root: the empty
path (only reachable from a hand-built `["store", 0]`, which `do_store/4`
already answers with `not_assignable`) and an integer root segment. Both keep
today's behavior exactly.

#### 4. The option on the host façade

**File**: `lib/predicator.ex` (`build_evaluator/3`, ~line 236)
**Changes**: one line, which is what makes the option work for `execute/3`,
`execute_value/3`, and `evaluate/3` alike.

```elixir
protected_roots: Evaluator.protected_roots_from_opts(opts),
```

#### 5. Tests

**File**: `test/predicator/evaluator/store_test.exs`
**Changes**: a `describe "store: protected roots"` block, driving
`%Evaluator{}` directly the way the file's existing blocks do:

- a protected root refuses: `{:error, %EvaluationError{reason:
  "protected_root", operation: :store, details: %{root: "_event"}}}`, and the
  run's context is unchanged;
- a nested write under a protected root (`_event.name = ...`) refuses on the
  root;
- an unprotected root with a non-empty list still writes;
- a protected list matching nothing behaves exactly as `[]`;
- the check is exact and case-sensitive: `"_Event"` protected does not refuse
  `_event`;
- a hand-built `["store", 0]` (empty path) with a non-empty protected list is
  still `not_assignable`, not `protected_root`;
- an integer root segment is unaffected;
- segment-type validation wins: a boolean segment is still a
  `TypeMismatchError` even when the list is non-empty.

**File**: `test/predicator/evaluator/store_test.exs` (position coverage) or
`test/predicator/evaluator_positions_test.exs`, whichever the existing
store-position assertions live nearest - a refusal compiled with
`compile_program_with_positions/1` carries the root segment's position.

**File**: `test/predicator/errors/` - a new `evaluation_error_test.exs` (the
directory has one file per error struct and no `evaluation_error_test.exs`
yet), covering `protected_root/1`'s fields and `new/3` leaving `details` nil.

**File**: `test/predicator/integration/protected_roots_test.exs` (new), the
end-to-end half:

- `Predicator.execute/3` with `protected_roots:` refuses mid-program and the
  returned context carries every earlier write and none of the later ones;
- **later statements do not observe the write**: `_event = 1; z = _event` never
  reaches the second statement, and the refusal is on the first;
- a write-then-restore program (`_event = 1; _event = original`) still errors -
  the case the post-hoc diff misses;
- `execute_value/3` returns the same three-tuple error arm as `execute/3`;
- absent the option, the same programs succeed exactly as today;
- `ArgumentError` for `protected_roots: "_event"` and for
  `protected_roots: [:_event]`.

### Success Criteria:

#### Automated Verification:

- [ ] Full quality gate passes: `mix quality`
- [ ] New code stays above the 90% coverage minimum in `coveralls.json`,
      including both `ArgumentError` branches of `protected_roots_from_opts/1`
      and both clauses of `store_or_refuse/4`
- [ ] `mix corpus.generate` produces no diff (`git status` clean under
      `conformance/`) - the corpus cannot express an evaluation option
- [ ] The whole existing suite passes unchanged, and no test outside the new
      files is edited - the mechanical form of "byte-identical when the option
      is absent". Decided by `git diff --name-only origin/main -- test/`,
      whose output must contain only the files this phase creates

#### Manual Verification:

- [ ] In `iex -S mix`, an SCXML-shaped program
      (`protected_roots: ["_event", "_sessionid", "_name", "_ioprocessors"]`)
      refuses each of the four roots and writes an ordinary one
- [ ] In `iex`, `{:error, e, _ctx} = Predicator.execute("_event = 1", %{},
      protected_roots: ["_event"])` and then `e.details.root` returns
      `"_event"` without reading `e.message` at all
- [ ] The reported position points at the assignment's root token: compile
      `"_event.name = 1"` with `Predicator.compile_program_with_positions/1`,
      run it with `protected_roots: ["_event"]`, and expect the error's
      `position` to be `{1, 1}` (the `_event` token), not the `= 1` operator
- [ ] Three no-option control programs behave exactly as before:
      `Predicator.execute("if x > 1 { y = 2 } else { y = 3 }", %{"x" => 5})`
      gives `%{"x" => 5, "y" => 2}`; `Predicator.execute("i = 0; while i < 3 { i = i + 1 }",
      %{})` gives `%{"i" => 3}`; and
      `Predicator.execute("x = len('abc')", %{})` gives `%{"x" => 3}`

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run full `mix quality` as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the
next phase. In looped (`--loop`) execution, this phase's Automated Verification
gates advancement automatically (via `/wurk:commit --auto`), and Manual
Verification items are deferred and surfaced once at the end instead of
blocking here.

---

## Phase 2: Documentation and changelog

### Overview

Document the option where a host reads about it (`execute/3`, `execute_value/3`),
where a sibling implementer reads about `store` (`docs/isa.md`), where the
component map lives (`docs/architecture.md`), and in `CHANGELOG.md` under
`## [Unreleased]`.

### Changes Required:

#### 1. The execute family's option list

**File**: `lib/predicator.ex`
**Changes**: `execute/3`'s "Parameters" section (`lib/predicator.ex:357-372`)
lists the options it accepts by name; add `:protected_roots` to that list with
a short description and a pointer to `Predicator.Evaluator.evaluate/3`'s fuller
entry. Add a "Protected context roots" paragraph explaining the refusal, the
per-root granularity, and that the error arm's partial context is unchanged.
Add a doctest:

```elixir
    iex> {:error, %Predicator.Errors.EvaluationError{reason: "protected_root"} = error, ctx} =
    ...>   Predicator.execute("x = 1; _event = 2", %{}, protected_roots: ["_event"])
    iex> {error.details.root, ctx.data}
    {"_event", %{"x" => 1}}
```

`execute_value/3`'s "Parameters" section says "Same as `execute/3`", so it
needs a one-line pointer only, plus a doctest asserting its error arm is the
same three-tuple.

#### 2. The ISA

**File**: `docs/isa.md`
**Changes**: two edits, both prose, no version change and no table change.

- §2, next to the `on_unbound` bullet (`docs/isa.md:133-137`): a bullet saying
  a host may name context roots a `store` refuses to write, that this is an
  *evaluation option* and not part of the ISA - it adds no opcode and no
  wire-format change - that a run with no such option behaves exactly as
  specified, and that the refusal is an `EvaluationError` with reason
  `"protected_root"`. Model the wording on the loop-budget bullet
  (`docs/isa.md:102-110`), which likewise makes only a reason token normative.
- §5, at the end of the `store` subsection (`docs/isa.md:578-599`), after the
  `not_assignable`/`not_a_container`/`invalid_index` sentence: a sentence
  saying a host that supplied a protected-root list gets `EvaluationError`
  `"protected_root"` when the path's root segment is in it, checked after
  segment-type validation and before the write, so no partial write occurs -
  and that this is host policy, not an ISA rule (pointer back to §2).

#### 3. The component map

**File**: `docs/architecture.md`
**Changes**: extend the one-line **Evaluator** entry in "Core Components"
(`docs/architecture.md:92`) with a clause naming `:protected_roots` as a
per-run write policy the evaluator carries, and say explicitly that it is an
evaluator option rather than a `%Context{}` field like `on_unbound`
(`docs/architecture.md:105`, which is left unchanged) - a run policy, not a
property of the binding.

#### 4. The changelog

**File**: `CHANGELOG.md`
**Changes**: an entry under the existing `## [Unreleased]` / `### Added`,
following the file's existing bolded-lead style: what the option is, the error
shape including `details.root`, that the partial context is unchanged, and that
it is additive - absent the option, behavior is identical, so this is a minor
release, not a breaking one.

### Success Criteria:

#### Automated Verification:

- [ ] Full quality gate passes: `mix quality` (the new doctests in
      `execute/3` and `execute_value/3` run as part of the suite)
- [ ] `test/docs_adr_links_test.exs` passes - any ADR reference added to the
      docs resolves
- [ ] `test/predicator/isa_sync_test.exs` passes unchanged: `docs/isa.md`'s
      opcode inventory still matches `lib/predicator/instructions.ex`, which is
      the mechanical confirmation that the prose edits moved no opcode
- [ ] `CHANGELOG.md` has the entry under `## [Unreleased]` and no new version
      header

#### Manual Verification:

- [ ] `mix docs` (or the rendered `@doc`) reads correctly: the option appears
      in `execute/3`'s list and the doctest output matches
- [ ] `docs/isa.md` §2's new bullet reads as a peer of the `on_unbound` and
      loop-budget bullets, and a sibling implementer would not conclude the ISA
      version moved
- [ ] The changelog entry is accurate about the release class (minor, additive)

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run full `mix quality` as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the
next phase. In looped (`--loop`) execution, this phase's Automated Verification
gates advancement automatically (via `/wurk:commit --auto`), and Manual
Verification items are deferred and surfaced once at the end instead of
blocking here.

---

## Testing Strategy

### Unit Tests:

- `test/predicator/evaluator/store_test.exs` - the refusal at the opcode, in
  the file that already asserts `store` against `docs/isa.md` §5: refusal,
  nested path refusing on the root, non-matching list, exact/case-sensitive
  matching, empty-path and integer-root fallbacks, and the precedence of
  segment-type validation over the refusal.
- `test/predicator/errors/evaluation_error_test.exs` (new) -
  `protected_root/1`'s message, reason, operation, and `details`, and `new/3`
  leaving `details` nil so no existing error shape changed.
- Option validation - `protected_roots_from_opts/1` accepting `[]`, a list of
  binaries, and raising `ArgumentError` for a non-list and for a list with a
  non-binary member. Both raise branches are needed for coverage.
- Edge cases that actually bite: a protected root that is also *bound* in the
  incoming context (protection is about writes, not reads - `load` is
  untouched); a program that only reads a protected root, which must succeed;
  and a store inside an `if`/`while` body, which must refuse only when the
  branch actually executes.

### Integration Tests:

- `test/predicator/integration/protected_roots_test.exs` (new), end-to-end
  through `Predicator.execute/3` and `execute_value/3`, mirroring
  `test/predicator/integration/on_unbound_test.exs`'s shape as the nearest
  option-driven precedent: the partial context on the error arm, later
  statements not observing the refused write, the write-then-restore program
  that the post-hoc diff cannot catch, and the absent-option control cases.

### Manual Testing Steps:

1. `iex -S mix`, then
   `Predicator.execute("_event = 1", %{}, protected_roots: ["_event"])` -
   expect the `protected_root` error and an empty partial context.
2. `Predicator.execute("a = 1; _event.x = 2; b = 3", %{}, protected_roots:
   ["_event"])` - expect `%{"a" => 1}` in the returned context, no `b`.
3. Re-run both without the option - expect success and the full context.
4. `Predicator.execute("x = _event", %{"_event" => 5}, protected_roots:
   ["_event"])` - reading a protected root still works.
5. `Predicator.execute("x = 1", %{}, protected_roots: "_event")` - expect
   `ArgumentError`.

## References

- Bead: `px-1xy` (mirrors `st-i9d`; downstream ask from statifier-ex st-af3.17,
  its ADR-0026, W3C SCXML 5.10 and 4.9)
- Related ADRs: `docs/adr/0003-the-elixir-implementation-leads-the-isa.md`
  (the ISA moves only for opcode changes; this is not one),
  `docs/adr/0004-no-eval-errors-are-values.md` (the refusal is a value; the
  malformed-option raise is the host-API-misuse exception),
  `docs/adr/0009-the-compiled-envelope-carries-the-position-table.md`
  (why the refusal is positioned through the segment table)
- Similar implementation: the `:loop_budget` option -
  `lib/predicator/evaluator.ex:250`, `lib/predicator/evaluator.ex:301`,
  `lib/predicator.ex:245`, `docs/isa.md:102`
- Specification: `docs/isa.md` §2 (execution model, options that are not the
  ISA) and §5 (`store`)
- Structured error data precedent:
  `lib/predicator/errors/location_error.ex:58-64`
