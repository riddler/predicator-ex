# Bracket Access Boolean Key Implementation Plan

## Overview

`access_value/2` in `lib/predicator/evaluator.ex` is not a total function. A
target that is a list, paired with a key that is not an integer, matches no
clause and raises `FunctionClauseError` from ordinary user-authored source.
This plan makes the function total, decides what a boolean key means (it stays
a valid map key - the opposite of what `docs/isa.md` currently claims), brings
`docs/isa.md` into agreement with the code, and covers both with regression
tests and two conformance cases.

Beads issue: **px-tmy** (bug, P1, `area:docs` + `area:evaluator`; this plan
adds `area:conformance` - see Phase 3).

## Current State Analysis

### The measured behavior

Probed against this worktree (`mix run` over `Predicator.evaluate/2`):

| target | key | today |
|---|---|---|
| map | `"a"` (string) | `{:ok, value}` / `{:ok, :undefined}` on a miss |
| map | `true` | `{:ok, "enabled"}` when the map has a `true` key; `{:ok, :undefined}` on a miss |
| map | `1.5` (float) | `{:error, %TypeMismatchError{expected: :string, got: :float}}` |
| map | `[1]` (list) | `{:error, %TypeMismatchError{expected: :string, got: :list}}` |
| list | `0` (integer) | `{:ok, element}`; out-of-range and negative push `:undefined` |
| list | `1.5` (float) | `{:error, %TypeMismatchError{expected: :string, got: :float}}` |
| list | `true` | **raises `FunctionClauseError`** |
| list | `"k"` (string) | **raises `FunctionClauseError`** |
| list | `:undefined` (unbound computed key) | **raises `FunctionClauseError`** |
| list | `.name` via the `access` opcode | **raises `FunctionClauseError`** |
| scalar (non-map, non-list) | anything | `{:ok, :undefined}` |

The bead reports the boolean/list crash. The probe shows the crash class is
wider: **any non-integer key against a list target crashes**, including a plain
string key, and including the `access` (dot) opcode's always-binary property.
`Predicator.evaluate("xs.name", %{"xs" => [1, 2]})` raises today.

### Why it happens

`lib/predicator/evaluator.ex:1045-1098` is seven clauses. The map clauses cover
binary, atom, and integer keys; the list clauses cover integers only; a
non-map/non-list target clause absorbs scalars; and the final clause guards on
`not is_binary(key) and not is_integer(key) and not is_atom(key)`. Nothing
covers `is_list(object)` with a binary or atom key, so those fall off the end.

Booleans are the bead's headline because `is_atom(true)` is true in Elixir:
`true` satisfies the map clause at `:1052` (so `m[true]` is a normal lookup)
and simultaneously fails the last clause's `not is_atom(key)` (so it can never
reach the `TypeMismatchError`). That is not an accident - see below.

### Key discoveries

- **Boolean map keys are a deliberately preserved feature, not a fall-through.**
  `lib/predicator/context.ex:214-223` splits atom keys out for stringification
  with `is_atom(key) and not is_boolean(key)`, and the comment above it
  (px-8um.2) says in as many words: "`true`/`false` are atoms in Elixir but are
  boolean *data* keys here ... `config[true]` compiles to a literal atom key
  lookup (`access_value/2`'s `is_atom(key)` clause), so stringifying a
  `true`/`false` map key would silently break that lookup."
- **A shipped test pins it.** `test/predicator_test.exs:1958-1967`,
  "evaluates bracket access with boolean keys", asserts
  `Predicator.evaluate("config[true]", context) == {:ok, "enabled"}` against
  `%{"config" => %{true => "enabled", false => "disabled"}}`.
- **The parser and lexer support it on purpose.** `test/predicator/parser_test.exs:1210-1218`
  covers `config[true]` and `settings[false]` as bracket keys.
- **So `docs/isa.md:365-372` is the side that is wrong**, not the code, on the
  boolean question. Its bullet says a key that is not a string, atom, or
  integer is a `TypeMismatchError`; in a language-neutral spec a reader has no
  reason to read "atom" as including `true`.
- **The `access` bullet already forbids erroring.** `docs/isa.md:269-272`:
  "A missing key, or a target that is neither a map nor a list, pushes
  `:undefined` - **never an error**." The `access` opcode's crash on a list
  target is therefore unambiguously a defect against text that already exists,
  and its fix is `:undefined`, not an error.
- **`store` already validates path segments the way this plan wants keys
  validated** (`lib/predicator/evaluator.ex:1349-1362`), rejecting a boolean or
  `:undefined` segment with a `TypeMismatchError`. Its test at
  `test/predicator/evaluator/store_test.exs:99` is even titled "a boolean
  segment is rejected the way bracket_access rejects a boolean key" - which is
  currently false of a map target. That title needs a wording fix (Phase 1);
  the assertion itself is correct and stays.
- **The corpus covers `bracket_access` already** (`conformance/cases/access.json`
  has `access/bracket-key-wrong-type` for `user[1.5]`, plus
  `errors/insufficient-operands-bracket-access`), so the mechanical
  per-opcode coverage rule in `conformance/README.md` is already satisfied and
  does not *force* new cases. New cases are still warranted: this change mints
  a normative error shape siblings must implement.
- **`docs/isa.md` names the helper by arity** at `:269` and `:365`
  (`access_value/2`). Changing the arity means editing both.
- `CHANGELOG.md` has an `## [Unreleased]` section (line 8) with `### Added`
  populated for the 4.0.0 statement work. No `### Fixed` subsection exists yet.
- `mix.exs` is at `@version "3.8.0"`; the unreleased section is the 4.0.0
  major. Nothing here has shipped under a version number yet.

## Desired End State

`access_value/3` is total. No input from any source string or any well-formed
instruction list can raise out of it. Specifically:

| target | key | after |
|---|---|---|
| map | string / integer / atom, **`true`/`false`/`:undefined` included** | lookup; `:undefined` on a miss (unchanged) |
| map | float, list, map, date, duration | `TypeMismatchError`, `expected: :string` (unchanged) |
| list | non-negative integer in range | element (unchanged) |
| list | out-of-range or negative integer | `:undefined` (unchanged) |
| list | anything not an integer | `TypeMismatchError`, `expected: :integer`, `operation: :bracket_access` (**was a crash, except floats/lists which were the `:string` shape**) |
| non-map, non-list | anything | `:undefined` (unchanged) |
| any, via the `access` opcode | anything unmatched | `:undefined`, never an error (**was a crash for a list target**) |

`docs/isa.md`'s `bracket_access` and `access` bullets state all of the above,
including the boolean/atom distinction spelled out for a non-Elixir reader.

Verify with: `mix quality` green; the new tests in Phase 1; and by hand,
`Predicator.evaluate("xs[flag]", %{"xs" => ["a"], "flag" => true})` returning
an `{:error, %TypeMismatchError{}}` tuple rather than raising.

## The three decisions this plan makes

### 1. A boolean key stays a valid map key; the doc is amended

**Chosen: amend `docs/isa.md`, keep the code's map behavior.**

The bead offers both directions. Making a boolean key a `TypeMismatchError`
would (a) delete a shipped, tested feature (`test/predicator_test.exs:1958`),
(b) contradict a deliberate decision recorded in code by px-8um.2
(`lib/predicator/context.ex:214-219`), which went out of its way to keep
boolean map keys unstringified *specifically so this lookup works*, and (c)
break a real use - a map keyed by `true`/`false` is an ordinary lookup table,
and `config[status['active']]` is the natural way to read it (that exact
expression is in the test).

Nothing argues the other way except one sentence in `docs/isa.md` written
after the fact by px-35i.2, which was documenting the code and got the Elixir
`is_atom/1` subtlety wrong. Erratum in the spec, not a regression in the code.

**Consequence for `m[true]` returning `{:ok, :undefined}`** (the bead's second
observation): that is correct and stays. It is a *miss*, identical to
`m['nope']` on a map with no `"nope"` key - not a type rejection that leaked.
The bead reads it as a discrepancy because it was compared against the float
case; under this resolution a boolean is an accepted key type and a float is
not, so the two are not meant to agree. The float case is unchanged.

This resolution deliberately makes `bracket_access` **more permissive than
`store`**, which rejects a boolean path segment. That asymmetry is intended and
should not be "fixed" later: reading `config[true]` is a lookup in data the
caller supplied, while `config[true] = 1` would have to *create* a boolean-keyed
path in a context, which `ContextLocation` does not model. Reading a shape you
cannot write is normal.

### 2. This does not move the ISA version. It stays v3.

Assessed against `docs/isa.md` section 1's rules explicitly:

- *"An opcode's semantics never change under its own name."* This rule governs
  **specified** behavior. The behavior changing here is a `FunctionClauseError`
  escaping the evaluator - which the spec never described, could not have
  described, and which no conforming sibling could have implemented. A crash
  has no semantics to preserve. Every input that produced a value or an error
  tuple before still produces the same value or the same error type after.
- The one *error-shape* change on a previously non-crashing path is
  `xs[1.5]` (list target, float key): still a `TypeMismatchError` with
  `operation: :bracket_access`, but `expected` moves `:string -> :integer` and
  the message names an integer index. The corpus's normative fields for an
  error are **type and reason only** (`conformance/README.md`, "Error type and
  reason are normative; message is not"), and both are unchanged. `expected` is
  an Elixir-side struct field, not part of the wire contract.
- *"Adding an operand form or widening an accepted type is a new version but
  not a new name."* No operand form is added and no accepted type is widened -
  the accepted map key types are exactly what the code already accepted.
- Nothing is retired, so the retirement rule (which would mint an integer) does
  not apply.

**Conclusion: ISA v3, unchanged. No bump, no new opcode, no migration path
needed** - no previously valid instruction list changes meaning. ADR-0003
governs; the ISA is spec-first and this is a code-does-not-match-spec fix in
one direction (the list crash) plus a spec-does-not-match-code correction in
the other (booleans). `Predicator.isa_version/0` and
`test/predicator/isa_sync_test.exs` need no change; that test binds section 4's
opcode table and section 1's current-version line, neither of which moves.

### 3. `docs/isa.md` needs the boolean/atom distinction spelled out

Yes, and it is the main doc change. "Atom key accepted" plus "boolean key
rejected" would be a self-contradiction in Elixir and meaningless in Ruby or
JavaScript, which have no atoms at all. The amended bullet states the accepted
set positively and in language-neutral terms, and says what a sibling without
atoms should do (treat the atom clause as vacuous; implement string, integer,
and boolean keys).

## What We're NOT Doing

- **Not** making a boolean key a `TypeMismatchError` (decision 1).
- **Not** changing `store`'s segment validation, which correctly rejects
  boolean and `:undefined` segments; only the comment in its test title moves.
- **Not** changing map behavior at all - not the `:undefined` key case
  (`m[nope]` under `on_unbound: :undefined` still misses to `:undefined`), not
  the float/list rejection, not the missing-key `:undefined`.
- **Not** adding negative-index-from-the-end semantics, or any other new list
  indexing behavior.
- **Not** bumping the ISA version or touching `Predicator.Instructions`.
- **Not** promoting `## [Unreleased]` to a version header - that is release
  work under CLAUDE.md's authority table and needs a human request.
- **Not** auditing the rest of the evaluator for other non-total private
  functions. If Phase 1 makes one obvious, file a follow-on bead; do not widen
  this branch.

## Implementation Approach

Three phases, each independently green and independently committable:

1. **Evaluator + tests** (`area:evaluator`) - make `access_value/3` total,
   operation-aware, and regression-tested. This is the whole bug fix; the
   remaining phases are the spec and the sibling contract catching up.
2. **Docs** (`area:docs`) - `docs/isa.md`'s two bullets, `CHANGELOG.md`.
3. **Conformance** (`area:conformance`) - two authored cases plus a corpus
   regeneration, so the amended rule is executable for siblings.

Phase 1 stands alone because a doc-only or corpus-only commit would describe
behavior the code did not have yet. Phases 2 and 3 could be one commit; they
are split because they carry different area labels and Phase 3 is the one that
can be dropped if a `area:conformance` branch is already live (see its
Overview).

## Phase 1: Make `access_value` total and operation-aware

### Overview

Restructure `access_value/2` into `access_value/3`, threading the calling
opcode so `access` can honor its "never an error" contract while
`bracket_access` returns a typed error. Add regression tests.

### Changes Required:

#### 1. The accessor

**File**: `lib/predicator/evaluator.ex` (`:588-596`, `:1029-1098`)

**Changes**: Both call sites pass the operation. `execute_access/2` calls
`access_value(object, property, :access)`; `execute_bracket_access/1` calls
`access_value(object, key, :bracket_access)`. The clause list becomes total,
with the final clause carrying no guard at all - that is the property being
bought, and a guard on the last clause would silently give it back.

```elixir
@spec access_value(Types.value(), Types.value(), :access | :bracket_access) ::
        {:ok, Types.value()} | {:error, TypeMismatchError.t()}
# A map takes a string, an integer, or an atom key. `true`, `false`, and
# `:undefined` are atoms in Elixir and are accepted deliberately: Context
# normalization leaves boolean map keys unstringified precisely so this
# lookup works (lib/predicator/context.ex, px-8um.2). A miss is :undefined,
# not an error.
defp access_value(object, key, _operation)
     when is_map(object) and (is_binary(key) or is_integer(key) or is_atom(key)) do
  {:ok, Map.get(object, key, Undefined.value())}
end

defp access_value(array, index, _operation)
     when is_list(array) and is_integer(index) and index >= 0 do
  if index < length(array), do: {:ok, Enum.at(array, index)}, else: {:ok, Undefined.value()}
end

# Negative indices do not count from the end; they miss.
defp access_value(array, index, _operation) when is_list(array) and is_integer(index) do
  {:ok, Undefined.value()}
end

# A target that is neither map nor list has nothing to index, whatever the key.
defp access_value(object, _key, _operation) when not is_map(object) and not is_list(object) do
  {:ok, Undefined.value()}
end

# Everything left is a map or list target whose key it cannot index.
# `access` never errors (docs/isa.md section 5); `bracket_access` does.
defp access_value(_object, _key, :access), do: {:ok, Undefined.value()}

defp access_value(object, key, :bracket_access) do
  {:error, bracket_key_error(object, key)}
end
```

The error builder replaces the inline struct at `:1088-1097` and is
target-aware, because "Bracket access requires a string, integer, or atom key,
got \"k\" (string)" is a nonsense sentence to hand a user who wrote `xs['k']`:

```elixir
@spec bracket_key_error(Types.value(), Types.value()) :: TypeMismatchError.t()
defp bracket_key_error(target, key) when is_list(target) do
  # message: "#{op_name} on a list requires an integer index, got #{key_text}"
  # expected: :integer, got: get_value_type(key), operation: :bracket_access
end

defp bracket_key_error(_target, key) do
  # the existing message and :string expectation, unchanged
end
```

Note the clause ordering: the non-map/non-list clause must stay **above** the
catch-alls so a scalar target keeps returning `:undefined` regardless of key
type (`5[1.5]` is `{:ok, :undefined}` today and stays so).

#### 2. Regression tests

**File**: `test/predicator/evaluator_test.exs` (new describe block beside the
existing `evaluate/2 with bracket_access instructions` at `:674`)

Per the bead's acceptance criteria, boolean keys are covered from **both**
surfaces:

- from source: `Predicator.evaluate("xs[flag]", %{"xs" => ["a"], "flag" => true})`
  returns `{:error, %TypeMismatchError{operation: :bracket_access, expected: :integer, got: :boolean}}`
- from source: `Predicator.evaluate("m[flag]", %{"m" => %{"a" => 1}, "flag" => true})`
  returns `{:ok, :undefined}` (a miss)
- from source: `Predicator.evaluate("config[true]", %{"config" => %{true => "on"}})`
  returns `{:ok, "on"}` - the feature decision 1 protects, asserted here as
  well as at `test/predicator_test.exs:1958` so the intent is local to the fix
- hand-built: `[["lit", ["a"]], ["lit", true], ["bracket_access"]]` errors
- hand-built: `[["lit", %{"a" => 1}], ["lit", true], ["bracket_access"]]` is
  `{:ok, :undefined}`
- hand-built: `[["lit", %{true => "on"}], ["lit", true], ["bracket_access"]]`
  is `{:ok, "on"}`

Plus the wider crash class the probe found, which is the same defect:

- `[["lit", ["a"]], ["lit", "k"], ["bracket_access"]]` - string key, list
  target - errors with `expected: :integer`
- `[["lit", ["a"]], ["lit", :undefined], ["bracket_access"]]` - errors
- `Predicator.evaluate("xs.name", %{"xs" => [1, 2]})` is `{:ok, :undefined}`,
  per `docs/isa.md:271`'s "never an error" (the `access` opcode)
- `[["lit", ["a"]], ["lit", 1.5], ["bracket_access"]]` still errors, now with
  `expected: :integer` - the one deliberate error-shape change, pinned so it
  is a decision and not a drift

**File**: `test/predicator/evaluator/store_test.exs:99`

Retitle the test: `bracket_access` rejects a boolean key against a *list*, and
accepts one against a map, so "the way bracket_access rejects a boolean key" is
no longer true as written. The assertion is unchanged. Suggested:
`"a boolean segment is rejected: a path segment must be a string or an
integer"`.

**File**: `docs/isa.md:269`, `:365` - the `access_value/2` arity references
become `access_value/3` in the same commit as the arity change, since
they are code references rather than prose.

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality`
- [x] The pre-existing `test/predicator_test.exs:1958` boolean-key test passes
      untouched
- [x] Coverage stays above the 90% floor in `coveralls.json`; every new
      `access_value/3` clause has a test that reaches it

#### Manual Verification:
- [ ] `Predicator.evaluate("xs[flag]", %{"xs" => ["a"], "flag" => true})`
      returns an error tuple in `iex` and does not raise - the bead's exact
      reproduction
- [ ] The message for `xs['k']` reads sensibly (names an integer index, does
      not tell the user a string key is required while rejecting their string)

---

## Phase 2: Bring `docs/isa.md` and `CHANGELOG.md` into agreement

### Overview

Rewrite the `bracket_access` bullet so the accepted key set is stated
positively and unambiguously for a reader with no atoms, add the list-target
rule to it, extend the `access` bullet with the list case, and record the fix.

### Changes Required:

#### 1. `docs/isa.md:365-372`, the `bracket_access` bullet

**Changes**: state the rule target-first, and make the boolean case explicit in
both directions. Substance to convey (wording is the implementer's, house style
of the file - it uses hyphens, not em dashes - is preserved):

- Pops the key (stack top) then the target (unchanged).
- **Against a map**: a string, an integer, or a boolean key indexes it; in
  Elixir, `is_atom/1` is true of `true`, `false`, and `:undefined`, so the
  clause is written as "atom" there and a sibling without atoms implements
  string, integer, and boolean. A key of any other type - float, list, map,
  date, duration - is `TypeMismatchError` (`expected: string`). A missing key
  pushes `:undefined`.
- **Boolean keys are data, not a type error.** A map may legitimately be keyed
  by `true`/`false` (`config[true]`); the reference implementation's context
  normalization preserves boolean keys for exactly this reason. `m[true]`
  against a map with no `true` key is an ordinary miss and pushes `:undefined`.
  This is a **correction**: before this change the bullet said a key that is
  not string/atom/integer is a `TypeMismatchError` and left a reader to guess
  which side of that line `true` fell on. It has always been an accepted map
  key in the reference implementation.
- **Against a list**: only a non-negative integer indexes. Out-of-range and
  negative push `:undefined`. **Any non-integer key - string, boolean,
  `:undefined`, float - is `TypeMismatchError`** (`expected: integer`).
- Against a target that is neither map nor list: `:undefined`, whatever the key.
- Fewer than two values on the stack is `EvaluationError` (unchanged).
- A note that this bullet, not the ISA version, changed: the list-with-a-non-
  integer-key case was previously unspecified and the reference implementation
  crashed on it, which is why the correction mints no version (section 1).

#### 2. `docs/isa.md:269-272`, the `access` bullet

**Changes**: add that a **list** target with a property (the compiler only ever
emits a binary property) also pushes `:undefined` - the bullet's existing "never
an error" promise now holds for every target shape, which it did not before.

#### 3. `CHANGELOG.md`

**Changes**: add a `### Fixed` subsection under `## [Unreleased]` (line 8),
after `### Added`. It records: bracket access on a list with a non-integer key
returned an error value instead of raising `FunctionClauseError`; the same
crash via `.property` on a list now pushes `:undefined`; `docs/isa.md`'s
`bracket_access` bullet corrected to say boolean map keys are accepted (they
always were); no ISA version change and no instruction list changes meaning.

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality`
- [x] `mix test test/predicator/isa_sync_test.exs` passes - the bullets edited
      here are prose, but that test parses `docs/isa.md`

#### Manual Verification:
- [ ] The bullet is readable by someone implementing in JavaScript: it never
      requires knowing what an Elixir atom is to determine the behavior
- [ ] No em dashes introduced; file house style matched

---

## Phase 3: Conformance cases for the corrected rule

### Overview

`conformance/README.md` calls the corpus "the executable form of `docs/isa.md`",
and this change mints a rule a sibling must implement (list + non-integer key)
and corrects one it might have implemented wrongly (boolean map key). Two
authored cases pin both.

**Label note**: the bead carries `area:docs` and `area:evaluator`; this phase
touches `conformance/**`, so run `bd update px-tmy --labels ...` to add
`area:conformance` before committing it. That is CLAUDE.md's documented
response to a branch touching an area it was not labeled with. `area:build` is
**not** triggered - no `mix.exs`, `coveralls.json`, or gate config moves - so
this stays batchable. If an `area:conformance` branch is already live and would
collide, drop this phase, file it as a follow-on bead, and land Phases 1-2;
nothing in them depends on it.

### Changes Required:

#### 1. `conformance/cases/access.json`

Two authored cases, ids stable forever once shipped:

- `access/bracket-list-non-integer-key` - `source: "items[flag]"` with
  `context: {"items": [1,2,3], "flag": true}`, expecting
  `{"error": {"type": "TypeMismatchError", "reason": "bracket_access"}}`, with
  a `notes` field citing `docs/isa.md`: a list accepts only a non-negative
  integer index, and every other key type is a type mismatch rather than a miss.
- `access/bracket-map-boolean-key` - `source: "config[true]"` with
  `context: {"config": {"true": ...}}` **will not work** - JSON object keys are
  strings, and the tagged-value encoding
  (`conformance/README.md`, "The tagged-value encoding") has no boolean-keyed
  map form. Author this one as the *miss* instead:
  `source: "config[true]"` with `context: {"config": {"a": 1}}` expecting
  `{"result": {"$type": "undefined"}}`, with `notes` recording that a boolean
  key against a map is an accepted key type whose miss pushes `:undefined`, not
  a `TypeMismatchError`. The boolean-key *hit* stays an Elixir-side test
  (Phase 1); it is not encodable in this corpus, and the notes should say so
  rather than leave a gap unexplained.

#### 2. Regenerate

`mix corpus.generate` recomputes `conformance/corpus/tier-3.json` and
`conformance/manifest.json` (case counts and `corpus_hash`). Generation fails
loudly if an authored `expected` disagrees with the real pipeline, which is
itself the check that Phase 1 landed the intended behavior.

### Success Criteria:

#### Automated Verification:
- [x] `mix corpus.generate` succeeds without reporting a disagreement
- [x] Full quality gate passes: `mix quality` (includes the corpus tests under
      `test/predicator/conformance/`)
- [x] `conformance/manifest.json`'s tier-3 `case_count` moved from 23 to 25 and
      `corpus_hash` changed
- [x] `conformance/manifest.json`'s `isa_version` is still `3`

#### Manual Verification:
- [ ] The two new cases validate against `conformance/schema/case.json`
- [ ] `bd update px-tmy` has added `area:conformance`

---

## Testing Strategy

### Unit Tests

`test/predicator/evaluator_test.exs` - the matrix in Phase 1, one assertion per
`access_value/3` clause, each in both surfaces the bead asks for (source and
hand-built instruction list). The hand-built form matters independently: it is
the only way to reach a target/key pair the compiler cannot produce (a raw
`:undefined` key, a map literal target).

### Integration Tests

None new. `Predicator.evaluate/2` from source *is* the integration path here,
and it is covered above. The existing `test/predicator_test.exs` bracket-access
describes must stay green untouched - that is the regression signal for
decision 1.

### Manual Testing Steps

1. `Predicator.evaluate("xs[flag]", %{"xs" => ["a"], "flag" => true})` - the
   bead's reproduction; expect `{:error, %TypeMismatchError{}}`.
2. `Predicator.evaluate("xs.name", %{"xs" => [1, 2]})` - expect
   `{:ok, :undefined}`.
3. `Predicator.evaluate("config[status['active']]", %{"config" => %{true => "enabled"}, "status" => %{"active" => true}})`
   - expect `{:ok, "enabled"}`; the feature that must survive.
4. Read the `xs['k']` error message aloud and confirm it is not self-
   contradictory.

## ISA Impact

1. **Version** - **no change; ISA stays v3.** Full reasoning in "The three
   decisions", item 2. In short: the only behavior that changes on a
   previously-working path is an Elixir struct field (`expected`) and a message,
   neither of which is normative; everything else changes a crash into a value.
   Section 1's "an opcode's semantics never change under its own name" governs
   specified behavior, and a `FunctionClauseError` was never specified.
2. **Stamp** - no new opcode subsection and no tier change. `bracket_access`
   stays tier 3, `access` stays tier 3, both keep their `introduced` version.
   What the change owes `docs/isa.md` is corrected prose in the two existing
   bullets (Phase 2) and two corpus cases (Phase 3).
3. **Migration** - none. No instruction list compiled before this change runs
   differently after it, except lists that previously crashed the evaluator.
   There is nothing to rewrite and no upgrade path to publish. Siblings adopt
   the corrected bullet whenever they next sync; a sibling that implemented the
   old bullet literally (rejecting boolean map keys) is behind, which
   ADR-0003 already treats as an expected state.

## Open Questions

One, recorded rather than blocking, with a default already chosen:

- **Should a list target with an `:undefined` key error, or propagate
  `:undefined`?** This plan errors, on two grounds: `store` already rejects an
  `:undefined` path segment with a `TypeMismatchError`
  (`test/predicator/evaluator/store_test.exs:106`), and a list index that came
  from an unbound variable is a mistake worth reporting rather than silently
  missing. The counter-argument is `docs/isa.md` section 2's note that some
  opcodes propagate `:undefined`, and that a map target treats an `:undefined`
  key as an ordinary miss - so the two targets diverge. Erring is the
  conservative choice given that the alternative (propagation) can always be
  relaxed to later without breaking anyone, while tightening an error later
  would be the breaking direction. If a human disagrees, the change is one
  clause and one test.

## References

- Beads issue: `px-tmy`; discovered from `px-tbv.2`
- `lib/predicator/evaluator.ex:588-596` (`execute_access/2`),
  `:1029-1041` (`execute_bracket_access/1`), `:1044-1098` (`access_value/2`),
  `:1349-1362` (`validate_store_segments/1`, the precedent)
- `lib/predicator/context.ex:214-223` - px-8um.2's deliberate preservation of
  boolean map keys, and the comment naming `access_value/2` as the reason
- `test/predicator_test.exs:1958-1967` - the shipped boolean-key test
- `test/predicator/parser_test.exs:1210-1218` - boolean bracket keys parse
- `test/predicator/evaluator/store_test.exs:99-111` - the test whose title
  needs correcting
- `docs/isa.md:18-62` (section 1, versioning), `:269-272` (`access`),
  `:365-372` (`bracket_access`)
- `conformance/README.md` - "Error type and reason are normative; message is
  not"; "How to add a case"; the per-opcode coverage rule
- `conformance/cases/access.json:46-54` - `access/bracket-key-wrong-type`
- `docs/adr/0003-the-elixir-implementation-leads-the-isa.md` - governs the
  versioning conclusion
- `CLAUDE.md` - area labels, quality gate, errors-as-values rule

## Deferred Manual Verification

### Phase 1

- [x] `Predicator.evaluate("xs[flag]", %{"xs" => ["a"], "flag" => true})`
      returns an error tuple in `iex` and does not raise - the bead's exact
      reproduction. Verified: returns `{:error, %TypeMismatchError{expected:
      :integer, got: :boolean, operation: :bracket_access, position: {1, 3}}}`.
- [x] The message for `xs['k']` reads sensibly (names an integer index, does
      not tell the user a string key is required while rejecting their string).
      Verified: `"Bracket access on a list requires an integer index, got \"k\"
      (string)"`, and the struct's `expected: :integer` agrees with the prose.

### Phase 2

- [x] The bullet is readable by someone implementing in JavaScript: it never
      requires knowing what an Elixir atom is to determine the behavior. The
      normative sentences are all type-name-based and the `is_atom/1`
      parenthetical translates itself for a sibling without atoms. One gap
      found and closed while checking this off: the map bullet's normative
      sentence named string, integer, and boolean but omitted `:undefined`,
      which the parenthetical implied and the code accepts (`m[o.missing]` is
      `{:ok, :undefined}`, an ordinary miss). A sibling reading only the
      normative sentence could have made it a type error and diverged, so the
      bullet now names `:undefined` outright and contrasts it with the list
      case.
- [x] No em dashes introduced; file house style matched. Verified by grepping
      the added lines of `docs/isa.md` and `CHANGELOG.md` for em and en
      dashes: zero hits.

### Phase 3

- [x] The two new cases validate against `conformance/schema/case.json`.
      Verified by test rather than by eye:
      `test/predicator/conformance/schema_validation_test.exs:56` walks every
      case in `conformance/cases/*.json` against the schema. The conformance
      and mix-task suites run 154 tests, 29 doctests, 0 failures. Both cases
      are in `conformance/corpus/tier-3.json` (case_count 25) and
      `manifest.json` still reads `"isa_version": 3`, so the no-bump
      conclusion holds in the generated artifact and not only in this plan.
- [x] `bd update px-tmy` has added `area:conformance`. Verified:
      `LABELS: area:conformance, area:docs, area:evaluator`.
