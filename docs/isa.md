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
  library's semver. ISA v2 landed across 3.7.0 and 3.8.0.
- An opcode's semantics never change under its own name. A change to what an
  opcode does is a new name at a new version. This is what makes "scan the
  opcode names in a list" a sound answer to "what version does this list
  require".
- Adding an operand form or widening an accepted type is a new version but
  not a new name.
- An additive version - new opcodes only, every existing instruction list
  still valid - ships in a minor release. Retiring an opcode invalidates
  stored artifacts and takes a major release plus an upgrade path.
- A sibling behind the current version is an expected, documented state.
  Each sibling publishes the version it supports in its own repository; this
  document maintains no support matrix.

Current version: **ISA v2**.

## 2. Execution model

The rules that govern every opcode, stated once here rather than repeated in
each row.

- A program is a flat list of instructions. An instruction is a JSON array
  whose first element is the opcode name and whose remaining elements are
  operands (`lib/predicator/types.ex:137`). Nothing else is in the wire
  format - source positions and spans travel in an Elixir-side side table
  that is never serialized (`lib/predicator/types.ex:107-112`).
- Execution is sequential from index 0. The program halts when the
  instruction pointer reaches or passes the end of the list, so a forward
  jump past the last instruction is a normal halt, not an error.
- The result is the top of the stack at halt. An empty stack at halt is an
  `EvaluationError` with reason `"empty_stack"`; it is the one error that
  belongs to no instruction and therefore carries no source position.
- **Opcodes validate, they do not coerce.** There is no general truthiness
  rule; a boolean-expecting opcode handed a non-boolean is a
  `TypeMismatchError`.
- **What "falsy" means at a jump**: `false` or `:undefined`, and nothing
  else. "True" means exactly `true`. This is ECMAScript-aligned,
  deliberately not symmetric-Kleene (ADR-0001).
- **Jumps are relative and forward-only.** The operand is a positive integer
  offset from the jump instruction's own index; the target instruction index
  is `jump_index + offset`. There is no backward jump and no absolute jump
  in the ISA.
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

One row per opcode the evaluator accepts, including opcodes the compiler no
longer emits. Columns: **Opcode**, **Operands**, **Pops**, **Pushes**,
**ISA**, **Tier**, **Emitted by compiler**.

Error semantics are not a table column: several opcodes have three or four
distinct error paths, more than a cell can carry cleanly. See the per-opcode
subsections below the table.

Every opcode is **ISA v1** except `jump_if_falsy_or_pop`,
`jump_if_true_or_pop`, and `make_list`, which are **v2** (ADR-0001).

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
| 6 | statements | (none yet - reserved for `store`) |

Tiers are defined by opcode, not by value. A date comparison
(`[["lit", Date], ["lit", Date], ["compare", "GT"]]`) is tier 1 by opcode,
even though it needs `Date` support and chronological comparison. Value-level
requirements (dates, datetimes, durations) are carried by `px-35i.4`'s
feature tags, not by tiers.

### Opcodes

| Opcode | Operands | Pops | Pushes | ISA | Tier | Emitted by compiler |
|---|---|---|---|---|---|---|
| `lit` | value | 0 | 1 | v1 | 1 | yes |
| `load` | name (string) | 0 | 1 | v1 | 1 | yes |
| `access` | property (string) | 1 | 1 | v1 | 3 | yes |
| `compare` | operator (string) | 2 | 1 | v1 | 1 | yes |
| `and` | - | 2 | 1 | v1 | 1 | no |
| `or` | - | 2 | 1 | v1 | 1 | no |
| `not` | - | 1 | 1 | v1 | 1 | yes |
| `in` | - | 2 | 1 | v1 | 3 | yes |
| `contains` | - | 2 | 1 | v1 | 3 | yes |
| `add` | - | 2 | 1 | v1 | 2 | yes |
| `subtract` | - | 2 | 1 | v1 | 2 | yes |
| `multiply` | - | 2 | 1 | v1 | 2 | yes |
| `divide` | - | 2 | 1 | v1 | 2 | yes |
| `modulo` | - | 2 | 1 | v1 | 2 | yes |
| `unary_minus` | - | 1 | 1 | v1 | 1 | yes |
| `unary_bang` | - | 1 | 1 | v1 | 1 | yes |
| `bracket_access` | - | 2 | 1 | v1 | 3 | yes |
| `call` | name (string), arg_count (int >= 0) | arg_count | 1 | v1 | 5 | yes |
| `object_new` | - | 0 | 1 | v1 | 4 | yes |
| `object_set` | key (string) | 2 | 1 | v1 | 4 | yes |
| `make_list` | count (int >= 0) | count | 1 | v2 | 3 | yes |
| `jump_if_falsy_or_pop` | offset (int > 0) | 0 or 1 | 0 | v2 | 1 | yes |
| `jump_if_true_or_pop` | offset (int > 0) | 0 or 1 | 0 | v2 | 1 | yes |
| `duration` | units (list of `[int, string]`) | 0 | 1 | v1 | 4 | yes |
| `relative_date` | direction (string) | 1 | 1 | v1 | 4 | yes |

`jump_if_falsy_or_pop` and `jump_if_true_or_pop` pop 0 or 1 values and push
0: on the taken branch they leave the value on the stack (net 0 change), and
on the fall-through branch they pop it and execution continues into the next
instruction, which pushes its own value. Neither jump itself ever pushes.

## 5. Per-opcode semantics and errors

All line references are to `lib/predicator/evaluator.ex`.

- **`lit`** (`:388`) - pushes the operand unchanged. No error path.
- **`load`** (`:393`) - string-key lookup in the context; an absent key
  pushes `:undefined` (`:1184-1190`). Atom keys are not read: the context is
  normalized to string keys before evaluation. This is the only opcode that
  reads a root variable; `access` and `bracket_access` operate on a value
  already on the stack.
- **`access`** (`:408`, `:555`) - pops the target, pushes
  `target[property]`. A missing key, or a target that is neither a map nor a
  list, pushes `:undefined` (`:1060-1094`) - never an error. An empty stack
  is `EvaluationError` insufficient operands.
- **`compare`** (`:414`, `:545`) - operand is one of `GT`, `LT`, `EQ`,
  `GTE`, `LTE`, `NE`, `STRICT_EQ`, `STRICT_NE`; any other string is an
  unknown instruction. Pops right then left (stack top is the right
  operand).
  - `:undefined` on either side under a non-strict operator (anything except
    `STRICT_EQ`/`STRICT_NE`) pushes `:undefined` (`:581-587`).
  - `STRICT_EQ`/`STRICT_NE` are resolved before any type dispatch and work
    over every value including `:undefined` (`:590-591`). A `Date` is never
    strictly equal to a `DateTime`, since strict equality is Elixir `===`
    and the two are different structs.
  - `Date`/`Date` and `DateTime`/`DateTime` compare chronologically, never
    by struct-key order; a mixed `Date`/`DateTime` pair coerces the `Date`
    to 00:00:00 UTC before comparing (`:594-610`).
  - A type-mismatched pair under a non-strict operator pushes `:undefined`
    (`:623`) - it is **not** an error.
  - Fewer than two values on the stack is `EvaluationError`.
- **`and`, `or`** (`:420`, `:425`) - **legacy: accepted but never emitted by
  the compiler.** Both operands must be booleans; anything else, including
  `:undefined`, is `TypeMismatchError` with operation `logical_and` /
  `logical_or` and expected type `boolean` (`:666-677`, `:690-701`). They do
  not short-circuit: both operands are already on the stack by the time
  either opcode runs. Kept for stored artifacts and for v1 sibling
  implementations (ADR-0001); ADR-0003 permits retiring them at a major
  version with an upgrade path (`px-tbv.9`). A v2 implementation still has to
  run them - they are not deprecated out of the evaluator, only out of code
  generation.
- **`not`** (`:430`, `:708`) - boolean required; `:undefined` or any other
  type is `TypeMismatchError` (operation `logical_not`, expected `boolean`).
- **`in`** (`:435`, `:724`) - `left in right`. Either operand `:undefined`
  pushes `:undefined`. The right operand must be a list, else
  `TypeMismatchError` (operation `in`, expected `list`). Membership uses
  type-matched equality with chronological date comparison, and `:undefined`
  is never equal to anything (`:637-652`).
- **`contains`** (`:440`, `:742`) - `left contains right`. Mirror of `in`;
  the **left** operand must be the list, and the type mismatch is reported
  against the left operand's type.
- **`add`** (`:445`, `:773`, `:859-920`) - number+number is numeric
  addition; string+string, string+number, and number+string concatenate
  (numbers are stringified); list+list concatenates; `Date`/`DateTime` +
  duration and duration + `Date`/`DateTime` do date arithmetic. Anything
  else, including any `:undefined` operand, is `TypeMismatchError`
  (operation `add`, expected `number_or_string`).
- **`subtract`** (`:449`, `:786`, `:930-989`) - number-number is numeric
  subtraction; `Date`-`Date` yields a duration in days; `DateTime`-`DateTime`
  a duration in seconds; a mixed `Date`/`DateTime` pair coerces the `Date`
  to UTC midnight first; `Date`/`DateTime` - duration does date arithmetic.
  Else `TypeMismatchError` (operation `subtract`, expected
  `number_or_date`). Note the asymmetry with `add`: subtraction does not
  concatenate strings or lists.
- **`multiply`** (`:799`) - numbers only, else `TypeMismatchError`
  (expected `number`).
- **`divide`** (`:805-826`) - **the zero check runs before the type
  check**, so a right operand of integer `0` or float `0.0` is
  `EvaluationError` `"division_by_zero"` regardless of the left operand's
  type. Two integers use truncating integer division; any float operand
  uses float division. Otherwise `TypeMismatchError` (expected `number`).
- **`modulo`** (`:829-837`) - same zero-first ordering as `divide`,
  `EvaluationError` `"modulo_by_zero"`. **Integers only** - a float operand
  is `TypeMismatchError` (expected `number`), which is the one place
  `modulo` diverges from the other four arithmetic opcodes.
- **`unary_minus`** (`:466`, `:1016`) - number required, else
  `TypeMismatchError` (expected `number`).
- **`unary_bang`** (`:470`, `:1022`) - boolean required, else
  `TypeMismatchError` (expected `boolean`). Semantically identical to
  `not`; the two differ only in which surface operator produced them and in
  the operation name carried on the error.
- **`bracket_access`** (`:475`, `:1044`) - pops the key (stack top) then the
  target. A map accepts a string, atom, or integer key; a list accepts a
  non-negative integer index. A missing key, an out-of-range index, a
  negative index, or a target that is neither map nor list all push
  `:undefined` (`:1060-1094`). A key of any other type is
  `TypeMismatchError` (operation `bracket_access`, expected `string`, the
  message naming string/integer/atom as the accepted key types)
  (`:1096-1113`). Fewer than two values on the stack is `EvaluationError`.
- **`call`** (`:480`, `:1116`) - pops `arg_count` values; the deepest
  (pushed first) is the first argument. Fewer than `arg_count` values on the
  stack is `EvaluationError` `"insufficient_arguments"`. An unknown function
  name, an arity mismatch, a function returning `{:error, message}`, or a
  function that raises are all `EvaluationError` with operation
  `function_call` (`:1127-1170`). **The builtin function set is not part of
  the ISA table** - see [Language Reference](reference/language.md). A
  sibling implements `call` plus whatever functions it chooses to provide;
  the conformance corpus's `functions` tier is where that set is pinned.
- **`object_new`** (`:486`, `:1289`) - pushes an empty map. No error path.
- **`object_set`** (`:491`, `:1295`) - pops the value (stack top) and the
  object beneath it, pushes the object with `key` set to that value. Fewer
  than two values on the stack is `EvaluationError`. **The non-map case is
  unspecified behavior**: the Elixir evaluator does not return a well-formed
  error there today - it crashes rather than returning `{:error, _}` - which
  is a known defect tracked separately, not part of this specification. The
  compiler only ever emits `object_set` immediately after `object_new`, so
  the non-map case is reachable only from a hand-built instruction list; a
  sibling should treat it as undefined behavior rather than replicate the
  exact failure mode.
- **`make_list`** (`:497`, `:1311`) - pops `count` values and pushes them as
  a list **in source order**: the stack holds them reversed, deepest first,
  and this opcode reverses them back (`:1316`). Fewer than `count` values on
  the stack is `EvaluationError`. `count` of `0` pushes `[]`. The compiler
  only emits this opcode for a list with at least one non-literal element;
  an all-literal list compiles to a single `["lit", [...]]` instead, which
  is why v1 siblings can still run most list expressions.
- **`jump_if_falsy_or_pop`** (`:503`, `:1324`) - if the stack top is `false`
  or `:undefined`, jump to `index + offset`, **leaving the value on the
  stack** as the result of the expression; if it is exactly `true`, pop it
  and fall through to the next instruction; any other value is
  `TypeMismatchError` (expected `boolean`). An empty stack is
  `EvaluationError`. Worked example, `a AND b`:
  `[["load","a"],["jump_if_falsy_or_pop",2],["load","b"]]` - if `a` is falsy,
  the jump lands past `["load","b"]` and `a`'s value is the result; if `a`
  is `true`, it is popped and `b`'s value becomes the result.
- **`jump_if_true_or_pop`** (`:509`, `:1344`) - mirror of
  `jump_if_falsy_or_pop`: jump on exactly `true`, leaving the value on the
  stack; pop and fall through on `false` or `:undefined`; anything else is
  `TypeMismatchError`. Worked example, `a OR b`:
  `[["load","a"],["jump_if_true_or_pop",2],["load","b"]]`. State the
  ECMAScript alignment explicitly: `undefined AND x` short-circuits to
  `:undefined` without evaluating `x`, while `undefined OR x` falls through
  and takes `x`'s value.
- **`duration`** (`:515`, `:1371`) - pushes a duration map built from the
  operand's unit pairs. Accepted unit strings, all of them:
  `y`/`year`/`years`, `mo`/`month`/`months`, `w`/`week`/`weeks`,
  `d`/`day`/`days`, `h`/`hour`/`hours`, `m`/`min`/`minute`/`minutes`,
  `s`/`sec`/`second`/`seconds`, `ms`/`millisecond`/`milliseconds`. Later
  pairs overwrite earlier ones naming the same unit. An unrecognized unit
  string is `EvaluationError` `"invalid_duration_unit"`; a pair that is not
  `[integer, string]` is `EvaluationError` `"invalid_duration_format"`.
- **`relative_date`** (`:520`, `:1416`) - pops a duration map, pushes a
  `DateTime`. `"ago"` and `"last"` subtract the duration from the current
  time; `"future"` and `"next"` add it. Any other direction string is
  `EvaluationError` `"invalid_direction"`; a non-map on top of the stack is
  `EvaluationError` `"invalid_stack_value"`; an empty stack is
  `EvaluationError` insufficient operands. **The result depends on the
  current time** - it reads the system clock at evaluation time - so a
  conformance case exercising it cannot pin an exact expected value.

## 6. Not in the ISA

What a reader might expect to find here and will not:

- `["store", n]` - specified by ADR-0001 for the 4.0 statement layer, not
  implemented and not accepted by any current evaluator clause. Reserved
  name, tier 6.
- Source positions and spans - these travel in an Elixir-side side table,
  never serialized as part of the instruction list. See
  `docs/architecture.md`'s Source Positions and Source Spans sections.
- Surface syntax, including the `=` grammar break
  ([ADR-0002](adr/0002-the-equals-grammar-break.md)). Both `=` and `==`
  compile to `["compare", "EQ"]`, so no instruction-level divergence exists
  between them: a parse-time deprecation warning is the entire difference,
  and it is outside the conformance corpus's scope.
- The builtin function set - see
  [Language Reference](reference/language.md).
- Backward jumps and absolute jumps. Every jump in the ISA is relative and
  forward-only.

## 7. Version history

| ISA | Opcodes introduced | Shipped in |
|---|---|---|
| v1 | everything not listed below | up to 3.6.x |
| v2 | `jump_if_falsy_or_pop`, `jump_if_true_or_pop`, `make_list` | 3.7.0 |

ISA v1 is defined as the full opcode set the Elixir evaluator accepted
before ADR-0001. A sibling declaring v1 support is claiming that whole set;
where a sibling falls short of it, the sibling publishes that fact in its
own repository. No support matrix is maintained here (ADR-0003).
