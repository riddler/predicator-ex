# ISA Reference

This document is the specification of predicator's instruction set: the flat
list of opcodes a compiled expression becomes and a stack VM runs. It is the
artifact a sibling implementation (Ruby, JavaScript) implements against, and
the one the conformance corpus is generated from.

It is not a syntax reference. For the expression grammar, operators, and
builtin functions, see [Language Reference](reference/language.md). This
document covers the instruction layer beneath that syntax - what an
expression compiles to and how it runs, not how it is written.

Per [ADR-0003](adr/0003-the-elixir-implementation-leads-the-isa.md), the
Elixir implementation (this repository) is the reference implementation of
the ISA. It moves when this library needs it to; sibling parity is a
downstream obligation, not an upstream constraint.

## 1. Versioning

The versioning scheme is settled by ADR-0003; this section records it rather
than re-arguing it.

- ISA versions are integers - v1, v2, v3 - with no correspondence to this
  library's semver. All three ISA v2 opcodes shipped in 3.7.0; 3.8.0 then
  refined v2 semantics without adding an opcode (it made every arithmetic and
  legacy logical opcode report an unbound root rather than a type mismatch).
  ISA v3 both retired `and`/`or` and introduced `store`/`pop`, the two
  opcodes the statement layer needed, shipping in 4.0.0.
- An opcode's semantics never change under its own name. A change to what an
  opcode does is a new name at a new version. This is what makes "scan the
  opcode names in a list" a sound answer to "what version does this list
  require".
- Adding an operand form or widening an accepted type is a new version but
  not a new name.
- An additive version - new opcodes only, every existing instruction list
  still valid - ships in a minor release.
- **Retirement mints the next ISA integer**, in addition to taking a major
  library release and an upgrade path. The integer moves because a build that
  no longer runs an opcode must be distinguishable from one that does -
  without it, the version stamp reports a list runnable that the build will
  refuse.
- **A version's opcode set is a half-open interval.** Each opcode is
  introduced at one version and, if ever retired, removed at another;
  version *v*'s set is every opcode with `introduced <= v < removed_in`. A
  version's set is fixed once minted - retiring at v3 does not change what v2
  was - so a sibling declaring v2 claims v2's whole set, retired opcodes
  included.
- The check a consumer performs is membership in
  `Predicator.Instructions.opcode_set/1` for this build's version, not a bare
  comparison against `required_isa/1`'s result: `required_isa/1` still names
  the version an instruction list needs, and `retired_in/1` names the version
  that removed an opcode, and together they are what lets a refusal name a
  version rather than say "unknown opcode".
- A sibling behind the current version is an expected, documented state.
  Each sibling publishes the version it supports in its own repository; this
  document maintains no support matrix.

Current version: **ISA v6**.

At runtime, `Predicator.isa_version/0` returns this build's version as an
integer, and `Predicator.Instructions.required_isa/1` returns the minimum
version a given instruction list needs.

## 2. Execution model

The rules that govern every opcode, stated once here rather than repeated in
each row.

- A program is a flat list of instructions. An instruction is a JSON array
  whose first element is the opcode name and whose remaining elements are
  operands (`t:Predicator.Types.instruction/0`). Nothing else is in the wire
  format - source positions and spans travel in an Elixir-side side table
  that is never serialized (`t:Predicator.Types.position_table/0`,
  `t:Predicator.Types.span_table/0`).
- Execution is sequential from index 0. The program halts when the
  instruction pointer reaches or passes the end of the list, so a forward
  jump past the last instruction is a normal halt, not an error.
- **In expression mode, the result is the top of the stack at halt.** An empty
  stack at halt is an `EvaluationError` with reason `"empty_stack"`; it is the
  one error that belongs to no instruction and therefore carries no source
  position. A deeper stack is not an error: the top is the result and anything
  beneath it is discarded. This rule, `empty_stack` included, is expression
  mode's alone - see "Two execution modes" below.
- **Opcodes validate, they do not coerce.** There is no general truthiness
  rule; a boolean-expecting opcode handed a non-boolean is a
  `TypeMismatchError`.
- **What "falsy" means at a jump**: `false` or `:undefined`, and nothing
  else. "True" means exactly `true`. This is ECMAScript-aligned,
  deliberately not symmetric-Kleene (ADR-0001).
- **Jumps are relative; the operand is always a positive integer.** `jump`,
  `jump_if_falsy_or_pop`, and `jump_if_true_or_pop` target `index + offset`;
  `jump_backward` (ISA v6) targets `index - offset`. There is no absolute
  jump in the ISA.
- **Execution of a list containing `jump_backward` must be bounded.** An
  implementation charges a per-execution budget on each back edge taken and,
  on exhaustion, stops with an `EvaluationError` whose reason is
  `"loop_budget_exceeded"`. The budget's default value and the option that
  configures it are implementation-local, as `on_unbound` is - only the
  bound's *existence* and the exhaustion reason are normative. The derived
  guarantee: between consecutive back edges the instruction pointer strictly
  increases, so total work is at most `(budget + 1) * length(program)`
  instructions.
- **`:undefined` is a first-class value**, not an absence. Some opcodes
  propagate it (`compare` under a non-strict operator, `in`, `contains`),
  some reject it (`not`, the arithmetic five, `unary_minus`, `unary_bang`,
  legacy `and`/`or`), and the jumps treat it as falsy. Each opcode's
  subsection below says which.
- **A malformed operand is an unknown instruction, not a bad operand.**
  Every opcode's clause is guarded on its operand's shape, so an
  out-of-range or wrong-typed operand falls through to the catch-all clause
  and returns an `EvaluationError` with reason `"unknown_instruction"`.
  Examples: `["make_list", -1]`, `["jump_if_falsy_or_pop", 0]`,
  `["compare", "FOO"]`, `["load", 5]`.
- **Error types are normative; error messages are not.** A sibling wording a
  message in its own idiom conforms. Three error types exist:
  `EvaluationError`, `TypeMismatchError`, `UndefinedVariableError`
  (`lib/predicator/errors/`).
- **Insufficient operands is `EvaluationError`, not `TypeMismatchError`**, at
  every opcode that checks stack depth before checking types.
- The Elixir-side `on_unbound` policy (`:undefined` versus `:error` on a
  `load` of an absent root) is an *evaluation option*, not part of the ISA:
  it changes what a `load` of an absent root does but adds no opcode and no
  wire-format change. See `docs/architecture.md` for that option; it is not
  respecified here.

### Two execution modes

A program is a flat instruction list with no header, so nothing in the wire
format says whether it is an expression or a statement program. **The mode is
carried by the entry point, not by the artifact.** In this implementation
`Predicator.evaluate/2,3` is expression mode and `Predicator.execute/2` - the
4.0 statement layer, §6 - is statement mode; a sibling exposes the same two
calls under whatever names it likes. The instruction set is identical in both:
no opcode is restricted to one mode, and no opcode means anything different in
the other. Only what "result" means differs.

- **Expression mode** - the result is the top of the stack at halt, and an
  empty stack at halt is `empty_stack`, as above.
- **Statement mode** - the result is **the context at halt**, not a stack
  value. The stack is scratch space between statement boundaries: a
  well-formed statement program ends each statement with a `store` or a `pop`
  and therefore halts with an **empty stack by design**. That is a normal
  halt. `empty_stack` is an expression-mode rule and is never raised in
  statement mode. A non-empty stack at halt is likewise not an error in
  statement mode; the residue is discarded, exactly as expression mode
  discards everything beneath the top.

A statement program that halts on an error has no result. Whether the
partially applied context from the statements that completed before the error
is kept or discarded is a property of the host API, not of the VM; the VM
specifies only that execution stops at the failing instruction.

A host may additionally surface the value of the program's last expression
statement alongside the context. That is a host-API convenience, not an ISA
guarantee - the statement boundary's `pop` discards it as far as the VM is
concerned. `Predicator.execute_value/2` is this implementation's answer: it
obtains the value by having the machine retain what `pop` discarded rather
than by compiling the program differently, so the compiled artifact is
identical either way.

Statement mode was specified here, ahead of the opcodes that reach it, so the
statement layer arrived as two opcodes plus an entry point rather than as a
change to this specification. `Predicator.execute/2` is that entry point.

## 3. Value types

The value domain the opcodes operate over: integer, float, string, boolean,
list, map (object), `Date`, `DateTime`, duration, and `:undefined`.

A duration's shape is normative, because `["duration", units]` produces one
and `add`/`subtract` consume it: a map with the seven keys `years`,
`months`, `weeks`, `days`, `hours`, `minutes`, `seconds`, all present and
defaulting to `0`, plus an optional `milliseconds` key present only when a
`ms`-family unit was used.

How these values cross a language boundary in the conformance corpus's
tagged-value JSON encoding is `px-35i.4`'s concern, not restated here.

## 4. The opcode table

One row per opcode the ISA has ever contained, including opcodes the
compiler no longer emits and opcodes a later version retired. A retired
opcode keeps its row so the version scan stays total. Columns: **Opcode**,
**Operands**, **Pops**, **Pushes**, **ISA**, **Tier**, **Emitted by
compiler**, **Removed in**.

Error semantics are not a table column: several opcodes have three or four
distinct error paths, more than a cell can carry cleanly. See the per-opcode
subsections below the table.

Every opcode is **ISA v1** except `jump_if_falsy_or_pop`,
`jump_if_true_or_pop`, and `make_list`, which are **v2** (ADR-0001),
`store` and `pop`, which are **v3**, `cast`, which is **v4** (ADR-0011),
`jump` and `pop_jump_if_falsy`, which are **v5** (ADR-0013), and
`jump_backward`, which is **v6** (ADR-0013).

### Tiers

Tiers group opcodes for the conformance corpus (`px-35i.4`); a lower tier is
a smaller, more foundational surface. Tier is a function of opcode only - a
row's tier does not depend on the value types the expression happens to use
(see the note after the table).

| Tier | Name | Opcodes it unlocks |
|---|---|---|
| 1 | core | `lit`, `load`, `compare`, `not`, `unary_bang`, `unary_minus`, `jump_if_falsy_or_pop`, `jump_if_true_or_pop`, `and`, `or` |
| 2 | arithmetic | `add`, `subtract`, `multiply`, `divide`, `modulo` |
| 3 | access | `in`, `contains`, `access`, `bracket_access`, `make_list` |
| 4 | rich types | `object_new`, `object_set`, `duration`, `relative_date` |
| 5 | functions | `call` |
| 6 | statements | `store`, `pop` |
| 7 | casts | `cast` |
| 8 | control flow | `jump`, `pop_jump_if_falsy` |
| 9 | loops | `jump_backward` |

Tiers are defined by opcode, not by value. A date comparison
(`[["lit", Date], ["lit", Date], ["compare", "GT"]]`) is tier 1 by opcode,
even though it needs `Date` support and chronological comparison. Value-level
requirements (dates, datetimes, durations) are carried by `px-35i.4`'s
feature tags, not by tiers.

### Opcodes

| Opcode | Operands | Pops | Pushes | ISA | Tier | Emitted by compiler | Removed in |
|---|---|---|---|---|---|---|---|
| `lit` | value | 0 | 1 | v1 | 1 | yes | - |
| `load` | name (string) | 0 | 1 | v1 | 1 | yes | - |
| `access` | property (string) | 1 | 1 | v1 | 3 | yes | - |
| `compare` | operator (string) | 2 | 1 | v1 | 1 | yes | - |
| `and` | - | 2 | 1 | v1 | 1 | no | v3 |
| `or` | - | 2 | 1 | v1 | 1 | no | v3 |
| `not` | - | 1 | 1 | v1 | 1 | yes | - |
| `in` | - | 2 | 1 | v1 | 3 | yes | - |
| `contains` | - | 2 | 1 | v1 | 3 | yes | - |
| `add` | - | 2 | 1 | v1 | 2 | yes | - |
| `subtract` | - | 2 | 1 | v1 | 2 | yes | - |
| `multiply` | - | 2 | 1 | v1 | 2 | yes | - |
| `divide` | - | 2 | 1 | v1 | 2 | yes | - |
| `modulo` | - | 2 | 1 | v1 | 2 | yes | - |
| `unary_minus` | - | 1 | 1 | v1 | 1 | yes | - |
| `unary_bang` | - | 1 | 1 | v1 | 1 | yes | - |
| `bracket_access` | - | 2 | 1 | v1 | 3 | yes | - |
| `call` | name (string), arg_count (int >= 0) | arg_count | 1 | v1 | 5 | yes | - |
| `object_new` | - | 0 | 1 | v1 | 4 | yes | - |
| `object_set` | key (string) | 2 | 1 | v1 | 4 | yes | - |
| `make_list` | count (int >= 0) | count | 1 | v2 | 3 | yes | - |
| `jump_if_falsy_or_pop` | offset (int > 0) | 0 or 1 | 0 | v2 | 1 | yes | - |
| `jump_if_true_or_pop` | offset (int > 0) | 0 or 1 | 0 | v2 | 1 | yes | - |
| `duration` | units (list of `[int, string]`) | 0 | 1 | v1 | 4 | yes | - |
| `relative_date` | direction (string) | 1 | 1 | v1 | 4 | yes | - |
| `store` | n (int >= 0) | n + 1 | 0 | v3 | 6 | yes | - |
| `pop` | - | 1 | 0 | v3 | 6 | yes | - |
| `cast` | type name (string) | 1 | 1 | v4 | 7 | yes | - |
| `jump` | offset (int > 0) | 0 | 0 | v5 | 8 | yes | - |
| `pop_jump_if_falsy` | offset (int > 0) | 1 | 0 | v5 | 8 | yes | - |
| `jump_backward` | offset (int > 0) | 0 | 0 | v6 | 9 | yes | - |

`jump_if_falsy_or_pop` and `jump_if_true_or_pop` pop 0 or 1 values and push
0: on the taken branch they leave the value on the stack (net 0 change), and
on the fall-through branch they pop it and execution continues into the next
instruction, which pushes its own value. Neither jump itself ever pushes.

### Retired opcodes

An opcode's **Removed in** cell holds `-` for a live opcode or `vN` for one
retired at ISA v*N*. That marker is the ISA version that removed the opcode,
not a library version (§1). A retired opcode keeps its row in this table, its
entry in `Predicator.Instructions`'s opcode map, and its membership in the
tier-names table above; it loses exactly one thing, its
`execute_instruction/2` clause in the evaluator. `required_isa/1` and
`tier/1` keep answering for it with a version rather than falling back to
`unknown_opcode`. The conformance corpus keeps a retired opcode's cases too,
with frozen expectations rather than ones the evaluator recomputes - see §8
and [`conformance/README.md`](../conformance/README.md). Retiring an opcode
still requires an upgrade path (ADR-0003).

## 5. Per-opcode semantics and errors

Each opcode names the private functions in `lib/predicator/evaluator.ex` that
implement it: the `execute_instruction/2` clause matching its name, plus the
helper it delegates to. Function names rather than line numbers, so a
reference survives an edit above it.

- **`lit`** - pushes the operand unchanged. No error path.
- **`load`** (`load_from_context/2`) - string-key lookup in the context; an
  absent key pushes `:undefined`. Atom keys are not read: the context is
  normalized to string keys before evaluation. This is the only opcode that
  reads a root variable; `access` and `bracket_access` operate on a value
  already on the stack.
- **`access`** (`execute_access/2`, `access_value/3`) - pops the target,
  pushes `target[property]`. A missing key, a property against a list (the
  compiler only ever emits a binary property, which a list never accepts as
  an index), or a target that is neither a map nor a list, all push
  `:undefined` - never an error. An empty stack is `EvaluationError`
  insufficient operands.
- **`compare`** (`execute_compare/2`, `compare_values/3`) - operand is one of
  `GT`, `LT`, `EQ`, `GTE`, `LTE`, `NE`, `STRICT_EQ`, `STRICT_NE`; any other
  string is an unknown instruction. Pops right then left (stack top is the
  right operand).
  - `:undefined` on either side under a non-strict operator (anything except
    `STRICT_EQ`/`STRICT_NE`) pushes `:undefined`.
  - `STRICT_EQ`/`STRICT_NE` are resolved before any type dispatch and work
    over every value including `:undefined`. A `Date` is never strictly equal
    to a `DateTime`, since strict equality is Elixir `===` and the two are
    different structs.
  - `Date`/`Date` and `DateTime`/`DateTime` compare chronologically, never
    by struct-key order; a mixed `Date`/`DateTime` pair coerces the `Date`
    to 00:00:00 UTC before comparing.
  - **Every other pair must be type-matched**, where "matched" means both
    numbers, both booleans, both strings, both lists, or both plain maps
    (`types_match/2`). Integer and float are the same type for this purpose,
    so `1 < 2.0` compares and `1 == 1.0` is `true` - while `STRICT_EQ` on
    that same pair is `false`, because strict equality does not bridge
    integer and float. This is the one place the two equality families
    disagree on numbers, and it is worth a conformance case.
  - **A type-mismatched pair under a non-strict operator pushes
    `:undefined`** - it is **not** an error. `1 > "a"` is `:undefined`, and
    so is `true == 1`.
  - Ordering on a matched pair, by type:
    - **numbers** - numeric order.
    - **strings** - lexicographic by Unicode codepoint, comparing the UTF-8
      bytes. Not a locale collation: no case folding, no accent folding.
    - **booleans** - `false < true`.
    - **lists** - element-wise, comparing the first position where the two
      differ; a proper prefix sorts before the longer list.
    - **maps** - the Elixir reference implementation orders these by Erlang
      term order (size first, then sorted keys, then values). **A sibling
      should treat ordering comparisons between two maps as unspecified**
      rather than reproduce that rule; the conformance corpus does not
      exercise them. `EQ`/`NE`/`STRICT_EQ`/`STRICT_NE` on two maps are
      well-defined and portable - only `GT`/`LT`/`GTE`/`LTE` are not.
  - Fewer than two values on the stack is `EvaluationError`.
- **`and`, `or`** - **retired at ISA v3; never emitted by the compiler.**
  Both operands must be booleans; anything else, including `:undefined`, is
  `TypeMismatchError` with operation `logical_and` / `logical_or` and
  expected type `boolean`. They do not short-circuit: both operands are
  already on the stack by the time either opcode runs. This is the semantics
  a v1 or v2 implementation still has to provide - a sibling declaring either
  version claims `and`/`or` under the interval rule (§1). This build has no
  `execute_instruction/2` clause for them: evaluating a list containing
  either is refused with reason `"retired_opcode"`, naming ISA v3 and
  pointing at `Predicator.Instructions.upgrade/1`, which is the migration
  ADR-0003 requires (`px-tbv.9`).
- **`not`** (`execute_logical_not/1`) - boolean required; `:undefined` or any
  other type is `TypeMismatchError` (operation `logical_not`, expected
  `boolean`).
- **`in`** (`execute_membership/2`) - `left in right`. Either operand
  `:undefined` pushes `:undefined`. The right operand must be a list, else
  `TypeMismatchError` (operation `in`, expected `list`). Membership uses
  type-matched equality with chronological date comparison
  (`values_equal?/2`), and `:undefined` is never equal to anything.
- **`contains`** (`execute_membership/2`) - `left contains right`. Mirror of
  `in`; the **left** operand must be the list, and the type mismatch is
  reported against the left operand's type.
- **`add`** (`execute_arithmetic/2`) - number+number is numeric
  addition; string+string, string+number, and number+string concatenate
  (numbers are stringified); list+list concatenates; `Date`/`DateTime` +
  duration and duration + `Date`/`DateTime` do date arithmetic. Anything
  else, including any `:undefined` operand, is `TypeMismatchError`
  (operation `add`, expected `number_or_string`).
- **`subtract`** (`execute_arithmetic/2`) - number-number is numeric
  subtraction; `Date`-`Date` yields a duration in days; `DateTime`-`DateTime`
  a duration in seconds; a mixed `Date`/`DateTime` pair coerces the `Date`
  to UTC midnight first; `Date`/`DateTime` - duration does date arithmetic.
  Else `TypeMismatchError` (operation `subtract`, expected
  `number_or_date`). Note the asymmetry with `add`: subtraction does not
  concatenate strings or lists.
- **`multiply`** (`execute_arithmetic/2`) - numbers only, else
  `TypeMismatchError` (expected `number`).
- **`divide`** (`execute_arithmetic/2`) - **the zero check runs before the
  type check**, so a right operand of integer `0` or float `0.0` is
  `EvaluationError` `"division_by_zero"` regardless of the left operand's
  type. Two integers use truncating integer division; any float operand
  uses float division. Otherwise `TypeMismatchError` (expected `number`).
- **`modulo`** (`execute_arithmetic/2`) - **integers only**, which is the one
  place `modulo` diverges from the other four arithmetic opcodes: a float
  operand is `TypeMismatchError` (expected `number`). A right operand of
  integer `0` is checked before the type check, as in `divide`, and is
  `EvaluationError` `"modulo_by_zero"`. There is **no float-zero clause** -
  unlike `divide`, a right operand of `0.0` is a `TypeMismatchError`, not
  `"modulo_by_zero"`.
- **`unary_minus`** (`execute_unary/2`) - number required, else
  `TypeMismatchError` (expected `number`).
- **`unary_bang`** (`execute_unary/2`) - boolean required, else
  `TypeMismatchError` (expected `boolean`). Semantically identical to
  `not`; the two differ only in which surface operator produced them and in
  the operation name carried on the error.
- **`bracket_access`** (`execute_bracket_access/1`, `access_value/3`) - pops
  the key (stack top), then the target.
  - **Against a map**: a string, an integer, a boolean, or `:undefined`
    indexes it. (The reference implementation writes this as one Elixir clause
    on `is_atom/1`, which is also true of `true`, `false`, and `:undefined`; a
    sibling with no atom type implements the clause as string, integer,
    boolean, and its own undefined value.) A key of any other type - float,
    list, map, date, duration - is `TypeMismatchError` (operation
    `bracket_access`, expected `string`). A missing key pushes `:undefined`,
    and an `:undefined` key is an ordinary miss on any map that does not carry
    one, not a type error - unlike the list case below.
  - **Boolean keys are data, not a type error.** A map may legitimately be
    keyed by `true`/`false` (`config[true]`); the reference implementation's
    context normalization preserves boolean keys for exactly this reason.
    `m[true]` against a map with no `true` key is an ordinary miss and pushes
    `:undefined`, the same as any other missing key - it is not a type
    rejection that leaked through.
  - **Against a list**: only a non-negative integer indexes; out-of-range and
    negative indices push `:undefined`. Any non-integer key - string, boolean,
    `:undefined`, float - is `TypeMismatchError` (operation `bracket_access`,
    expected `integer`).
  - Against a target that is neither map nor list: `:undefined`, whatever the
    key.
  - Fewer than two values on the stack is `EvaluationError`.
  - This bullet, not the ISA version, changed to state the above precisely:
    the list-with-a-non-integer-key case was previously unspecified here and
    the reference implementation crashed on it rather than returning an error
    value, and the boolean-map-key line corrects an earlier erratum in this
    document rather than describing a behavior change - see §1's versioning
    rules for why neither warrants a version bump.
- **`call`** (`execute_function_call/3`, `call_function/4`) - pops
  `arg_count` values; the deepest (pushed first) is the first argument. Fewer
  than `arg_count` values on the stack is `EvaluationError`
  `"insufficient_arguments"`. An unknown function name, an arity mismatch, a
  function returning `{:error, message}`, or a function that raises are all
  `EvaluationError` with operation
  `function_call`. **The builtin function set is not part of
  the ISA table** - see [Language Reference](reference/language.md). A
  sibling implements `call` plus whatever functions it chooses to provide;
  the conformance corpus's `functions` tier is where that set is pinned.
- **`object_new`** (`execute_object_new/1`) - pushes an empty map. No error
  path.
- **`object_set`** (`execute_object_set/2`) - pops the value (stack top) and
  the object beneath it, pushes the object with `key` set to that value. Fewer
  than two values on the stack is `EvaluationError` insufficient operands. A
  non-map beneath the value is `EvaluationError` `"invalid_stack_value"`,
  checked after the stack-depth check. The compiler only ever emits
  `object_set` immediately after `object_new`, so the non-map case is
  reachable only from a hand-built instruction list - but it is specified, not
  undefined: a sibling implements it to claim tier 4.
- **`make_list`** (`execute_make_list/2`) - pops `count` values and pushes
  them as a list **in source order**: the stack holds them reversed, deepest
  first, and this opcode reverses them back. Fewer than `count` values on
  the stack is `EvaluationError`. `count` of `0` pushes `[]`. The compiler
  only emits this opcode for a list with at least one non-literal element;
  an all-literal list compiles to a single `["lit", [...]]` instead, which
  is why v1 siblings can still run most list expressions.
- **`jump_if_falsy_or_pop`** (`execute_jump_if_falsy_or_pop/2`,
  `jump_to/2`) - if the stack top is `false` or `:undefined`, jump to
  `index + offset`, **leaving the value on the
  stack** as the result of the expression; if it is exactly `true`, pop it
  and fall through to the next instruction; any other value is
  `TypeMismatchError` (expected `boolean`). An empty stack is
  `EvaluationError`. Worked example, `a AND b`:
  `[["load","a"],["jump_if_falsy_or_pop",2],["load","b"]]` - if `a` is falsy,
  the jump lands past `["load","b"]` and `a`'s value is the result; if `a`
  is `true`, it is popped and `b`'s value becomes the result.
- **`jump_if_true_or_pop`** (`execute_jump_if_true_or_pop/2`, `jump_to/2`) -
  mirror of
  `jump_if_falsy_or_pop`: jump on exactly `true`, leaving the value on the
  stack; pop and fall through on `false` or `:undefined`; anything else is
  `TypeMismatchError`. Worked example, `a OR b`:
  `[["load","a"],["jump_if_true_or_pop",2],["load","b"]]`. State the
  ECMAScript alignment explicitly: `undefined AND x` short-circuits to
  `:undefined` without evaluating `x`, while `undefined OR x` falls through
  and takes `x`'s value.
- **`duration`** (`execute_duration/2`) - pushes a duration map built from the
  operand's unit pairs. Accepted unit strings, all of them:
  `y`/`year`/`years`, `mo`/`month`/`months`, `w`/`week`/`weeks`,
  `d`/`day`/`days`, `h`/`hour`/`hours`, `m`/`min`/`minute`/`minutes`,
  `s`/`sec`/`second`/`seconds`, `ms`/`millisecond`/`milliseconds`. Later
  pairs overwrite earlier ones naming the same unit. An unrecognized unit
  string is `EvaluationError` `"invalid_duration_unit"`; a pair that is not
  `[integer, string]` is `EvaluationError` `"invalid_duration_format"`.
- **`relative_date`** (`execute_relative_date/2`) - pops a duration map,
  pushes a `DateTime`. `"ago"` and `"last"` subtract the duration from the
  current time; `"future"` and `"next"` add it. Any other direction string is
  `EvaluationError` `"invalid_direction"`; a non-map on top of the stack is
  `EvaluationError` `"invalid_stack_value"`; an empty stack is
  `EvaluationError` insufficient operands. **The result depends on the
  current time** - it reads the system clock at evaluation time - so a
  conformance case exercising it cannot pin an exact expected value.
- **`store`** (`execute_store/2`) - pops the value from the stack top, then
  `n` location segments beneath it, and reverses those `n` into root-first
  path order: the compiler pushes segments root-to-leaf followed by the
  value, so the stack holds the segments deepest-first, exactly as
  `make_list` does. Writes `path -> value` into the evaluator's context via
  the same write algorithm `Predicator.ContextLocation.put/3` implements: a
  missing or `:undefined` interior slot is auto-vivified as a list when the
  next segment is an integer and a map otherwise, an integer past a list's
  end pads with `:undefined`, and the leaf is always overwritten. **Pushes
  nothing.** Fewer than `n + 1` values on the stack is `EvaluationError`
  insufficient operands. A segment that is neither a string nor an integer
  is `TypeMismatchError` (operation `store`, expected `string`, the message
  naming string and integer as the accepted segment types), the mirror of
  `bracket_access`'s key rule. A write that cannot be performed is
  `EvaluationError` with reason `not_assignable` (empty path, only reachable
  from a hand-built `["store", 0]`), `not_a_container` (an interior segment
  holds a scalar), or `invalid_index` (a negative list index). This is the
  only opcode that writes the context.
- **`pop`** (`execute_pop/1`) - discards the stack top and pushes nothing.
  The statement-boundary opcode: the compiler emits it after every
  expression statement so the next statement starts from a clean stack. An
  empty stack is `EvaluationError` insufficient operands. It is unrelated to
  `jump_if_falsy_or_pop`/`jump_if_true_or_pop`, which pop conditionally as
  part of a jump. Non-normative: this implementation additionally retains the
  discarded value in the evaluator's own state, which is how
  `Predicator.execute_value/2` reports the last expression statement's value;
  the stack effect, the error, and everything else a conforming
  implementation must reproduce are unchanged, and a sibling need not retain
  anything.
- **`cast`** (`execute_cast/2`, `Predicator.Cast.cast/2`) - pops the stack
  top, converts it to the named type, pushes the result. The operand must be
  one of the seven scalar type names below; any other value is `unknown_instruction`,
  the standing malformed-operand rule (ADR-0011) - `cast` has no other error
  path. An empty stack is `EvaluationError` insufficient operands. This
  subsection is the **normative** conversion matrix: a sibling claiming ISA
  v4 implements exactly it.

  Two rules generate every cell:

  1. `:undefined` propagates: `cast(:undefined, _type)` is `:undefined` for
     every target.
  2. `cast` is total over values: a conversion that cannot produce a value of
     the target type pushes `:undefined`, never an error. The type name
     itself already failed at parse time if it was invalid; what remains at
     evaluation time is the data's half, and data problems go soft here, as
     at a `compare` mismatch or an `access` miss.

  The seven scalar type names are `integer`, `float`, `string`, `boolean`,
  `date`, `datetime`, `duration` (§3). `=` is identity, a word names a
  conversion, `-` is `:undefined`:

  | source \ target | integer | float | string | boolean | date | datetime | duration |
  |---|---|---|---|---|---|---|---|
  | integer | = | widen | format | - | - | - | - |
  | float | truncate | = | format | - | - | - | - |
  | string | parse | parse | = | parse | parse | parse | parse |
  | boolean | - | - | format | = | - | - | - |
  | date | - | - | format | - | = | midnight UTC | - |
  | datetime | - | - | format | - | calendar date | = | - |
  | duration | - | - | format | - | - | - | = |
  | list | - | - | - | - | - | - | - |
  | map | - | - | - | - | - | - | - |
  | `:undefined` | - | - | - | - | - | - | - |

  **Numeric conversions.**

  - `integer::float` widens to the nearest representable double, which is
    exact up to 2^53 and rounds beyond it: `(2^53+1)::float` is `2^53`.
    Siblings agree, because a 53-bit mantissa is what their host float
    types have too, but the conversion is not lossless and a round trip
    through `float` is not identity for a large integer.
  - `float::integer` truncates toward zero. PostgreSQL rounds here; this
    diverges deliberately, because truncation is what Elixir `trunc`,
    JavaScript `Math.trunc`, and Ruby `to_i` all do natively, and matching
    the siblings' host languages is worth more than matching PG's
    tie-breaking.

  **String parses.** Each parse accepts the whole string or yields
  `:undefined`; no trimming, no partial consumption, no locale forms.

  - `::integer` - an optionally-negated decimal integer (`-?[0-9]+`).
  - `::float` - an optionally-negated decimal number with an optional
    fraction (`-?[0-9]+(\.[0-9]+)?`); `"3"::float` is `3.0`. No exponent
    form, matching the language's own float literal grammar.
  - `::boolean` - exactly `"true"` or `"false"`, case-sensitive.
  - `::date` - ISO 8601 calendar date (`2026-08-09`).
  - `::datetime` - ISO 8601 datetime **with a UTC offset**, normalized to
    UTC. A date-only string is `:undefined` here; the supported spelling is
    `s::date::datetime`.
  - `::duration` - the language's own duration-literal grammar, a sequence
    of integer-unit pairs (`"1d2h30m"`).

  **String formats (`::string`).**

  - `integer` - decimal.
  - `float` - the shortest round-trip decimal. Shortest-round-trip printing
    is a known cross-language hazard, so the conformance corpus pins values
    chosen to format identically across languages.
  - `boolean` - `"true"` / `"false"`.
  - `date` - ISO 8601 calendar date (`2026-08-09`).
  - `datetime` - ISO 8601 in UTC with `Z`, and the fractional-seconds field is
    **normative**: omitted entirely when the sub-second component is zero
    (`2026-08-09T12:00:00Z`), and exactly six digits when it is not
    (`2026-08-09T12:00:00.500000Z`). Never any other digit count, and never a
    zero fraction spelled out. Sub-second precision is microseconds - the
    `::datetime` parse truncates digits past the sixth - so the field is
    stated in terms of the instant, not in terms of any host type's precision
    or scale field. `dt::string::datetime` preserves the instant, but
    `s::datetime::string` is a **canonicalization** rather than a string
    identity: `"…:00.5Z"` returns as `"…:00.500000Z"`, and a seventh digit is
    gone.
  - `duration` - the duration-literal grammar, largest unit first, zero
    components omitted, `"0s"` when all components are zero, so
    `d::string::duration` round-trips.
  - Lists and maps are `-`: serialization is `JSON.stringify`'s job, not a
    cast's.

  **The date/datetime bridge.**

  - `date::datetime` is midnight UTC - the same coercion `compare` and
    `subtract` already apply to a mixed pair.
  - `datetime::date` is the datetime's calendar date.

  **No boolean/number bridge.** `1::boolean` and `true::integer` are
  `:undefined`. The ISA has no truthiness rule (§2) and `compare` refuses to
  bridge booleans and numbers; casts do not open a side door.
- **`jump`** (`jump_to/2`) - unconditional jump to `index + offset`. Pops
  nothing, pushes nothing. No error path beyond the standing malformed-operand
  rule (a non-integer or non-positive offset falls through to
  `unknown_instruction`). Statement-level control flow's only unconditional
  jump - `if/else` uses it to skip the `else` branch once the `if` branch has
  run. Worked example, `if c { A } else { B }`:
  `c; ["pop_jump_if_falsy", lenA + 2]; A; ["jump", lenB + 1]; B` - after `A`
  runs, `jump` skips past `B` to the instruction following it.
- **`pop_jump_if_falsy`** (`execute_pop_jump_if_falsy/2`, `jump_to/2`) - pops
  the stack top **always**. If the popped value is `false` or `:undefined`,
  jump to `index + offset`; if it is exactly `true`, fall through to the next
  instruction; any other value is `TypeMismatchError` (expected `boolean`). An
  empty stack is `EvaluationError` insufficient operands.

  **Contrast with `jump_if_falsy_or_pop`**: that opcode pops only on the
  fall-through branch and *leaves the value on the stack* on the taken
  branch, because it exists to make `a AND b` yield `a` as the expression's
  result. `pop_jump_if_falsy` pops unconditionally - a statement's condition
  is never a result, so there is nothing to preserve, and leaving it behind
  would strand a value on the stack for the following statement to trip over.
  CPython draws the same distinction between `JUMP_IF_FALSE_OR_POP` and
  `POP_JUMP_IF_FALSE`, and this opcode is the latter's counterpart, not the
  former's.

  Worked example, `if c { A }` (no `else`):
  `c; ["pop_jump_if_falsy", lenA + 1]; A` - a falsy `c` jumps past `A`
  entirely; `A`'s length plus one lands on the instruction after `A`. Worked
  example, `if c { A } else { B }` (continuing the `jump` example above):
  a falsy `c` jumps over both `A` and the trailing `jump`, landing on `B`'s
  first instruction, `lenA + 2` past the `pop_jump_if_falsy` itself.
- **`jump_backward`** (`execute_jump_backward/2`, `jump_backward_to/2`) - the
  one back edge in the ISA (ISA v6, ADR-0013). Unconditional jump to
  `index - offset`. Pops nothing, pushes nothing. A non-integer offset, a
  non-positive offset, or a target before index 0 is `unknown_instruction`,
  the standing malformed-operand rule (§2).

  The opcode has its own name rather than being a negative `jump` offset
  deliberately: it keeps opcode-name scanning a sound version check, and the
  *absence* of `jump_backward` in a list remains a termination proof - a list
  without it still halts in at most `length(program)` steps, since every
  other jump is forward-only (§2).

  Every execution of a back edge charges a per-execution loop budget (§2). On
  exhaustion, the instruction returns an `EvaluationError` with reason
  `"loop_budget_exceeded"`, carrying the `jump_backward` instruction's own
  source position - the same position-attachment every other opcode's error
  gets, with no special-case plumbing.

  Worked example, `while c { A }`:
  `c; ["pop_jump_if_falsy", lenA + 2]; A; ["jump_backward", lenC + lenA + 1]`
  - the `pop_jump_if_falsy` skips past `A` *and* the trailing
  `jump_backward` once `c` goes falsy (the `+2`); the `jump_backward` at the
  end targets the condition's first instruction, `lenC` instructions before
  `A` began, so its offset counts both `lenC` and `lenA`.

## 6. Not in the ISA

What a reader might expect to find here and will not:

- Source positions and spans - these travel in an Elixir-side side table,
  never serialized as part of the instruction list. See
  `docs/reference/ast.md` for the blame-token and span tables, and
  `docs/reference/language.md`'s "Error Shapes" for how they surface on an
  error.
- Surface syntax, including the `=` grammar break
  ([ADR-0002](adr/0002-the-equals-grammar-break.md)). Both `=` and `==`
  compile to `["compare", "EQ"]`, so no instruction-level divergence exists
  between them: the difference is a parse error in expression position and an
  assignment in statement position, entirely at the parser layer, and it is
  outside the conformance corpus's scope.
- The builtin function set - see
  [Language Reference](reference/language.md).
- Absolute jumps. Every jump in the ISA is relative. Backward jumps entered
  at v6 as exactly one opcode, `jump_backward` - see §5.

## 7. Version history

| ISA | Opcodes introduced | Opcodes retired | Shipped in |
|---|---|---|---|
| v1 | everything not listed below | - | up to 3.6.x |
| v2 | `jump_if_falsy_or_pop`, `jump_if_true_or_pop`, `make_list` | - | 3.7.0 |
| v3 | `store`, `pop` | `and`, `or` | 4.0.0 |
| v4 | `cast` | - | 4.1.0 |
| v5 | `jump`, `pop_jump_if_falsy` | - | 4.1.0 |
| v6 | `jump_backward` | - | 4.1.0 |

This table records the release each opcode was *introduced* in, and, now that
an opcode has been retired, the release each was *removed* in - both ends of
the interval §1 defines. A version whose only change is a retirement still
gets a row here. A version's semantics can also be refined in a
later release without a new opcode and without a new ISA version - 3.8.0 did
exactly that to v2, as noted in §1.

ISA v1 is defined as the full opcode set the Elixir evaluator accepted
before ADR-0001. A sibling declaring v1 support is claiming that whole set;
where a sibling falls short of it, the sibling publishes that fact in its
own repository. No support matrix is maintained here (ADR-0003).

## 8. Conformance corpus

This document specifies the ISA in prose; [`conformance/README.md`](../conformance/README.md)
is its **executable form** - a checked-in, language-neutral JSON corpus a
sibling runs its compiler and evaluator against, tier by tier, without an
Elixir toolchain (`px-35i.4`, ADR-0003). Read it before implementing against
a tier or adding a case. [`conformance/RATCHET.md`](../conformance/RATCHET.md)
is the companion format a sibling uses to record and defend its conformance
claim over time (`px-35i.8`).

The corpus's scope boundary matches this document's: it does **not** cover
surface syntax (§6 - `=` and `==` compile identically, so a source-level test
would encode a divergence that does not exist) and it does **not** cover
parse or lexer errors (every authored case's `source`, when present, compiles
successfully). Coverage here means the instruction layer this document
specifies, nothing above it.
