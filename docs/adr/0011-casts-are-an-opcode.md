# ADR-0011: Casts compile to a `cast` opcode; `::` is postfix and failure is `:undefined`

Status: accepted (2026-08-09)

Decision record for `px-2r5.1`, the design gate on the `px-2r5` epic
(PostgreSQL-style `::` type casts). It settles the compiled form, the
grammar slot, the type vocabulary, the failure rules, and whether casts also
exist as functions. The full conversion matrix and per-cell parse/format
rules live in
[`docs/research/260809-px-2r5.1-cast-conversion-matrix.md`](../research/260809-px-2r5.1-cast-conversion-matrix.md);
this ADR carries the rules that generate that matrix, not its cells.

## Context

`expr::type` converts a value to a named type at evaluation time -
`"42"::integer` is `42`. It is the first construct whose result type is
named in the source text, and the language today has no conversion path at
all: no conversion functions exist, and the evaluator deliberately never
coerces ("opcodes validate, they do not coerce" - `docs/isa.md` §2). A
predicate over dirty data - a `"42"` stored where an integer belongs -
currently has no recourse.

The shaping question is the compiled form: a new `cast` opcode (which mints
ISA v4 and owes ADR-0003's paperwork), or lowering to the existing `call`
opcode against builtin conversion functions (no ISA change). Lowering looks
cheaper until the function layer's actual properties are laid against what a
cast needs; three of them are disqualifying:

- **The function set is host-overridable by construction** -
  `opts[:functions]` merges last and silently shadows builtins by name. A
  host registering a function named `integer` would redefine what every
  stored `x::integer` artifact means.
- **The function set is explicitly outside the ISA** (`docs/isa.md` §5,
  §6). Cast semantics need to be normative - the same matrix in every
  sibling, pinned by the corpus at the instruction level - which lowering
  can only achieve by promoting specific function names into the spec: an
  opcode with extra steps and a worse wire format.
- **`call`'s failure model is wrong for casts.** Every `call` failure is a
  hard `EvaluationError`; casts need the soft semantics below, and carving a
  cast-specific exception into `call` would change its semantics under its
  own name, which ADR-0003 forbids.

What lowering was protecting - not touching the ISA - stopped being worth
protecting when ADR-0003 landed: an additive version is a minor release and
a page of paperwork.

## Decision

- **`expr::type` compiles to a new `cast` opcode**: operand is the type name
  as a string, pops 1, pushes 1, never touches the context. It mints
  **ISA v4** in a new corpus tier 7 (`casts`), following v3's precedent that
  a version's new opcodes get their own tier. Additive, so a minor release
  and no migration note. The AST node is `{:cast, expr, type_name, position}`,
  printed by the StringVisitor at postfix precedence. A `cast` whose operand
  is not one of the seven names below falls under the standing
  malformed-operand rule (`unknown_instruction`).

- **`::` is postfix, tighter than unary minus, chainable.** The lexer gains
  a `::` token (no collision: the only `:` today is in object literals,
  where two colons are never adjacent), and the grammar's postfix production
  becomes `primary ( "[" expression "]" | "." IDENTIFIER | "::" TYPE_NAME )*`.
  Postfix already binds tighter than unary minus, so `-1::integer` is
  `-(1::integer)` with no extra work, matching PostgreSQL. Chained casts
  parse left-to-right out of the same loop and are load-bearing for
  composition: the matrix keeps each edge minimal, and
  `"2026-08-09"::date::datetime` is the supported spelling of "date-shaped
  string to datetime".

- **The vocabulary is the seven scalar ISA type names** (`docs/isa.md` §3):
  `integer`, `float`, `string`, `boolean`, `date`, `datetime`, `duration` -
  not `list` or `map`, whose construction the language already serves. The
  names are contextual identifiers, not keywords, and stay valid as variable
  names everywhere else. **An unknown name after `::` is a parse error**: the
  type name is static text the author wrote, so it fails at authoring time,
  and a compiled artifact can never contain an invalid cast.

- **Failure is soft, by two rules that generate the whole matrix:**
  1. `:undefined::type` is `:undefined` for every target - the sparse-data
     rule `compare`, `in`, and `contains` already follow.
  2. Cast is total over values: a conversion that cannot produce a value of
     the target type pushes `:undefined`, never an error. The author's half
     of a cast - the type name - already failed at parse time; what remains
     at evaluation time is the data's half, and data problems go soft here,
     as at a `compare` mismatch or an `access` miss. `x::integer > 5` on a
     row holding `"abc"` is `:undefined`, falsy at a jump, and the run
     continues. `cast`'s only error paths are the VM-level ones every opcode
     has (insufficient operands, malformed operand).

- **No bare conversion functions.** `::` is the only surface. The registry's
  flat names collide with user variables, two spellings would make the
  StringVisitor's output a choice instead of a fact, and the function layer
  is host-shadowable - the property that disqualified it as the compiled
  form would return as an alias.

## Consequences

- **ISA v4 exists once this ships**: `docs/isa.md` gains the `cast` row, a
  §5 subsection carrying the conversion matrix as normative semantics, and a
  v4 history line; `Predicator.Instructions` gains
  `"cast" => %{isa: 4, tier: 7}` and `@isa_version` moves to 4. The matrix
  is ISA-normative, not function-layer-optional: a sibling claiming v4
  implements exactly it, and the corpus (`px-2r5.5`) exercises it.
- The epic's children are unblocked with their shapes fixed: `px-2r5.2`
  lexes/parses with the parse-time vocabulary check, `px-2r5.3` adds the
  opcode end to end, `px-2r5.4` teaches the StringVisitor the node,
  `px-2r5.6` documents the surface syntax.
- A minor release carries it; no stored artifact changes meaning.
- `docs/isa.md` §2's "no coercion" line stays true with a clarifying clause
  (`px-2r5.6`): opcodes do not coerce *implicitly*; `cast` is the author
  asking. The soft-failure precedent is bounded to `cast` and is not a
  license to soften any validating opcode.
- Rejecting call-lowering does not close the door on future functions that
  construct typed values (a richer `Date.parse`, say); it closes the door on
  `::` *meaning* a function call.
