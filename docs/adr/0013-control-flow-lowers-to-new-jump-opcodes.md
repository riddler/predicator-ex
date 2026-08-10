# ADR-0013: Control flow lowers to new jump opcodes; `if` is ISA v5, `while` is ISA v6 with a loop budget

Status: accepted (2026-08-10)

Decision record for `px-3so.1`, the design gate on the `px-3so` epic
(statement-level `if`/`else` and `while`). It settles the opcode question,
the grammar and scope shape, the termination bound, and the shipping split.
ADR-0001 deferred statement-level control flow as a scope choice; this ADR
is that choice coming due.

## Context

The 4.0 statement layer exists: `parse_program/2` parses semicolon-separated
statement sequences, `store`/`pop` (ISA v3) delimit statements, and
`Predicator.execute/2,3` runs a program in statement mode where the result
is the context at halt (`docs/isa.md` §2). Control flow is the piece
ADR-0001 deliberately left out, on the note that "the VM has jumps once
this lands" - the epic reads that as a likely zero-new-opcode change over
"jump, jump_if_false and the *_or_pop variants".

That premise does not survive contact with the opcode table. The ISA
contains exactly two jumps, `jump_if_falsy_or_pop` and
`jump_if_true_or_pop`, and three properties disqualify them as a complete
lowering target:

- **There is no unconditional jump.** `if cond { A } else { B }` needs one:
  after `A` runs, execution must skip `B` unconditionally. No conditional
  jump can express that without leaving a synthetic value on the stack for
  the jump to test.
- **The `_or_pop` jumps preserve the tested value on the taken branch.**
  That is their whole design - they exist so `a AND b` can leave `a` as the
  expression's result (ADR-0001). A statement's condition is not a result:
  lowering `if` through them strands the condition value on the stack on
  the taken branch, and mopping it up takes a pop-trampoline (jump to a
  `pop` parked after the block) that needs - again - an unconditional jump
  to skip.
- **Every jump is relative and forward-only** (`docs/isa.md` §2 and §6,
  stated as a deliberate exclusion). `while` needs a back edge. This is not
  an oversight to patch quietly: forward-only jumps are why every program
  the VM can run today halts in at most `length(program)` steps, and a back
  edge is precisely the construct that forfeits that guarantee.

So the real question is not whether to mint opcodes but which ones, at what
version, and what the back edge costs. ADR-0003 makes the paperwork cheap -
an additive ISA version is a minor release, an isa.md entry, and no
migration note - and ADR-0011 already declined to contort an existing
opcode's semantics to avoid a version.

## Decision

- **Three new opcodes across two ISA versions; the epic's zero-new-opcode
  hypothesis is refuted.** All three are relative jumps with a positive
  integer offset operand, in the existing Python-bytecode style:

  - **`jump`** (ISA v5) - unconditional, target `index + offset`. Pops 0,
    pushes 0. No error path beyond the standing malformed-operand rule.
  - **`pop_jump_if_falsy`** (ISA v5) - pops the stack top **always**; jumps
    to `index + offset` when the popped value is falsy (`false` or
    `:undefined`, the standing rule), falls through when it is exactly
    `true`, and any other value is a `TypeMismatchError` (expected
    `boolean`). An empty stack is `EvaluationError` insufficient operands.
    The name is deliberate: `jump_if_falsy_or_pop` pops only on
    fall-through and preserves the value on the taken branch;
    `pop_jump_if_falsy` consumes it unconditionally, which is what a
    condition in statement position wants. (CPython draws the same
    distinction as `JUMP_IF_FALSE_OR_POP` versus `POP_JUMP_IF_FALSE`.)
  - **`jump_backward`** (ISA v6) - unconditional, target `index - offset`;
    the one back edge in the ISA, and the only opcode that charges the loop
    budget below. A target before index 0 falls under the malformed-operand
    rule. Keeping the back edge a distinct name rather than widening
    `jump` to negative offsets preserves two properties: "scan the opcode
    names" stays a sound version check (§1), and *absence of
    `jump_backward` is a termination proof* - any list without it still
    halts in at most `length(program)` steps, exactly as every list does
    today.

  Following v3's and v4's precedent that a version's opcodes get their own
  tier, `jump`/`pop_jump_if_falsy` are corpus tier 8 (control flow) and
  `jump_backward` is tier 9 (loops).

  The lowerings, with each block's statements already stack-neutral because
  the statement layer ends every statement with a `store` or a `pop`:

      if c { A }              c; pop_jump_if_falsy +(lenA+1); A

      if c { A } else { B }   c; pop_jump_if_falsy +(lenA+2); A;
                              jump +(lenB+1); B

      if c1 { A }             c1; pop_jump_if_falsy over (A, jump); A;
      else if c2 { B }        jump to end;
      else { C }              c2; pop_jump_if_falsy over (B, jump); B;
                              jump to end; C

      while c { A }           c; pop_jump_if_falsy +(lenA+2); A;
                              jump_backward back to c's first instruction

- **Braces group statements; the flat Context is the only scope.** A block
  introduces no bindings, no shadowing, and no frame: `x = 1` inside a
  taken branch is the same `store` it is at top level, visible after the
  block and in `execute/2`'s result. This is forced, not merely chosen:
  statement mode's entire output is the context at halt, so a write that
  vanished with its block would be a write to nowhere; the language has no
  declaration form to hang a scope on (`=` is assignment, ADR-0002); and a
  block scope would need scope opcodes in the wire format that no consumer
  has asked for. Statifier's datamodel is flat for the same reason.

- **Grammar: `if expr { stmts } else { stmts }` and
  `while expr { stmts }`, statement-position only.** The `statement`
  production gains `if_statement` and `while_statement` alternatives;
  `parse/2`, the expression entry point, keeps rejecting them - `if` is a
  statement, not an expression, and there is no ternary here. Braces are
  mandatory (no braceless single-statement form), a block may be empty, a
  block's interior is an ordinary semicolon-separated statement sequence,
  and the separator after a closing `}` is optional. The condition is a
  bare expression - parentheses are ordinary grouping, never required. Its
  value follows `pop_jump_if_falsy`'s rule above: `false`/`:undefined`
  skip, `true` runs, anything else is a `TypeMismatchError` - opcodes
  validate, they do not coerce (§2).

  **`else if` chains are sugar, desugared in the parser.** `else if c2 { B }`
  parses as an `else` block whose sole statement is the nested `if`; there
  is no chain node in the AST. The StringVisitor prints an `else` branch
  containing exactly one `if` statement back as `else if`, so the natural
  spelling round-trips; either spelling parses to the same tree, so
  `parse_program |> StringVisitor |> parse_program` stays a fixpoint.

  **`if`, `else`, and `while` become reserved words**, lowercase, in the
  lexer's `classify_identifier/1` set beside `in` and `contains` - all
  three reserved in the v5 release even though `while` parses only at v6,
  so the break lands once. A predicate using one as a variable name stops
  parsing; that is a deliberate small grammar break in ADR-0002's mold,
  called out in the changelog rather than engineered around with
  contextual-keyword tricks that would make `if = 3` mean something.

- **`while` gets a fuel counter on the evaluator, charged per back edge.**
  Every program the VM runs today halts because the instruction pointer
  only moves forward; `jump_backward` forfeits that, so ISA v6 pairs the
  opcode with a bound, and the bound restores a guarantee: between
  consecutive back edges the pointer strictly increases, so total work is
  at most `(budget + 1) * length(program)` instructions.

  - **Where it lives**: a counter on the evaluator struct, decremented only
    in `jump_backward`'s clause. A program with no back edge never touches
    it - no per-instruction cost, and the v5 termination property survives
    verbatim.
  - **Default**: 10,000 back edges per execution, shared across all loops
    in the program, configurable per call through an evaluation option
    (`:loop_budget`), the `on_unbound` pattern.
  - **On exhaustion**: the taken-once-too-often `jump_backward` stops
    execution with an `EvaluationError` value, reason
    `"loop_budget_exceeded"`, carrying that instruction's source position -
    an error value per ADR-0004, never a raise.
  - **What is exported and what is local**: that execution of a list
    containing `jump_backward` **must** be bounded, and that exhaustion is
    an `EvaluationError` with reason `"loop_budget_exceeded"`, is normative
    ISA v6 - a sibling claiming v6 that can hang on a stored artifact does
    not conform, and the corpus's tier 9 includes a case that exhausts the
    bound (pinning the error type, not the count at which a default fires).
    The default value and the option surface are implementation-local, as
    `on_unbound` is (§2).

- **`if`/`else` and `while` ship separately: v5 first, v6 after.** `if` is
  mechanical - two forward jumps, no new failure mode, every v5 artifact
  still provably halting. `while` carries the halting risk, the budget
  machinery, and the normative bound. Splitting them keeps the strong
  guarantee attached to the version that actually has it, and means the
  loop release is judged on the loop questions alone. Both versions are
  additive, so each is a minor release with no migration note.

## Consequences

- **ISA v5 and v6 exist once the epic ships**: `docs/isa.md` gains three
  opcode rows, tiers 8 and 9, per-opcode subsections, and two version-history
  lines; `Predicator.Instructions` gains the three entries and
  `@isa_version` moves with each release. Per ADR-0003 each version's
  paperwork lands in the bead that implements it - v5 in `px-3so.3`, v6 in
  `px-3so.4` - not ahead of it.
- The epic is a parser+compiler epic *and* an ISA epic, against its own
  guess: siblings wanting control-flow parity implement three small
  opcodes, and a v5/v6 artifact does not run on a v4 sibling - the
  expected, documented state (ADR-0003).
- The `_or_pop` jumps keep their job. Expression-level `AND`/`OR` compile
  exactly as before; nothing about v5 revisits ADR-0001's short-circuit
  design, and no existing instruction list changes meaning.
- `Predicator.execute_value/2`'s "last expression statement's value"
  becomes dynamic: it reports the last expression statement *executed*,
  which branches and loops now choose at runtime. That is the natural
  reading of the existing pop-retention mechanism, not a change to it.
- Reserving `if`/`else`/`while` breaks predicates that used them as
  variable names - a parse error at authoring time, headline changelog
  item for the v5 release, ADR-0002's precedent.
- The termination story is now layered: no `jump_backward` means halting
  by construction; `jump_backward` means halting by budget. A consumer
  that must never block (statifier's guards) can keep loops out entirely
  by scanning for one opcode name.
- The default budget (10,000 back edges) is a guess made without
  production data. If hosts hit it on legitimate programs, moving the
  default is an implementation-local change needing no ISA motion; only
  removing the bound's existence would.
- The flat-scope choice closes block-local variables for as long as the
  statement layer's result is the context. Reopening it means a
  declaration form and scope opcodes - a new ADR superseding this one, not
  a parser tweak.
