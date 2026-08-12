# Which token a bad `if` condition blames

Bead: px-ij7 (discovered from px-3so.3's deferred manual verification)
Date: 2026-08-12
Decision: **the current behavior is confirmed - a statement's jump
instructions blame the statement keyword - and `docs/reference/ast.md` says so
as a rule, not just as a fact about `if`.**

This is an interpretation of a rule `docs/reference/ast.md` already states, not
a new architectural commitment. It changes no opcode, no grammar, and no
compiled artifact, so it does not move the ISA and it is not ADR-shaped:
ADR-0013 settles the lowering and says nothing about annotation, and the blame
rule's authority already lives in `docs/reference/ast.md`. No ADR was written,
per `docs/adr/README.md`'s third corollary ("a call too narrow for its own ADR
goes to `docs/research/`"), with `260807-px-phw-conformance-area-label.md` as
the model.

## The question

px-3so.3 annotated both instructions it emits for an `if` - the
`pop_jump_if_falsy` and, in the `else` form, the unconditional `jump` - with
the `{:if, ...}` node's own position. px-3so.4 did the same for `while`'s
`pop_jump_if_falsy` and `jump_backward`. The consequence is visible in the
error a non-boolean condition produces:

```elixir
Predicator.execute(~s|if "a" { y = 1 }|, %{})
# {:error, %TypeMismatchError{operation: :pop_jump_if_falsy, expected: :boolean,
#                             got: :string, position: {1, 1}}, ctx}
```

`{1, 1}` is the `if` keyword. The offending value is the string literal at
column 4. The bead frames exactly two answers: move the blame to the condition
and mint a second documented exception alongside `store_annotation/2`, or
confirm the keyword and write the rule down so the next reader does not
re-open it.

## Ground truth: what the language already does

Measured on this branch, `mix run`:

| Source | `operation` | `position` | Token at that column |
|---|---|---|---|
| `if "a" { y = 1 }` | `:pop_jump_if_falsy` | `{1, 1}` | `if` |
| `while "a" { y = 1 }` | `:pop_jump_if_falsy` | `{1, 1}` | `while` |
| `"a" and true` | `:jump_if_falsy_or_pop` | `{1, 5}` | `and` |
| `1 * true` | `:multiply` | `{1, 3}` | `*` |

The third row is the one that decides this. `"a" and true` fails for the same
reason `if "a"` does - a construct that requires a boolean was handed a string -
and it already blames the operator, at column 5, rather than the string at
column 1. `logical_and`'s short-circuit jump carries the `and`'s position for
precisely the reason `if`'s carries the `if`'s. Moving `if` alone would make
the statement form and the expression form disagree about the same failure,
and the obvious next question - "then why doesn't `1 * true` blame `true`?" -
has no good answer.

`docs/reference/ast.md`'s "Which token a node blames" section already states
the general rule: a non-leaf node points at the token that *names the
operation*, "so an error names the thing that failed rather than the start of
the subexpression it failed on - `a * true` reports column 3, not column 1."
The `if` keyword is that token. The condition is an operand, and predicator
blames operators, not operands.

## Why `store_annotation/2` is not a precedent for widening

px-tbv.11 moved `["store", n]`'s annotation off the assignment node's `=` and
onto the lhs root, and its reasoning reads superficially like the argument for
blaming a condition: the `=` "names the operator that noticed the write rather
than the location being written". The distinguishing feature is a type rule.

`*` carries one (numbers). `and` carries one (booleans). `if` and `while` carry
one (a boolean condition). `=` carries none - an assignment accepts any rhs, so
when a store fails the `=` has nothing to say about it and the only token that
does is the location being written. That is a single, closed exception rather
than the first of a series, and it is the unifying principle worth writing
down: **blame the token that carries the type rule that was violated.** Under
that principle the current behavior is not an exception at all, and no second
one is needed.

Two further costs of the alternative are worth recording. First, the exception
would not stop at `if`: `while` has the identical shape today, and every future
statement form with a condition would inherit it, so the "one documented
exception" would immediately be three or more. Second, `store_annotation/2` is
a point-mode-only exception - it deliberately leaves spans alone, because the
assignment's span already starts at the lhs root. An `if` exception has no such
escape: the `if` node's span starts at the `if` token (see ast.md's span
table), so honoring the exception under `spans: true` would mean narrowing the
underline from the statement to the condition, and declining to would mean
point mode and span mode naming different tokens for reasons unrelated to the
one place ast.md already sanctions that (the `property_access` caret/underline
split). Either branch costs more documentation than the error-quality gain
buys.

## What the reader complaint actually is

The blame position is defensible; the message is weaker than it should be:

```text
Pop Jump If Falsy requires a boolean, got "a" (string)
```

`Pop Jump If Falsy` is an opcode name leaking into a user-facing string. A
reader who wrote `if` never typed it and cannot act on it. Nothing about
position fixes that, and nothing about that fixes position - they are
independent, and this bead only settles the first.

**Open question, recorded rather than answered:** should a
`pop_jump_if_falsy` type mismatch name the source construct (`if`, `while`)
instead of the opcode - "`if` requires a boolean condition, got "a" (string)" -
and if so, does the evaluator have enough to tell `if` from `while` at that
point, or does the distinction have to be carried on the instruction? Worth its
own bead if a maintainer wants it; it is an error-message change with no
position, ISA, or compiled-artifact consequence. Nobody is available to answer
it here, and it does not block this decision.

## What this decides, in one sentence

A statement's jump instructions carry the statement node's own annotation - the
`if` or `while` keyword - and that is the general rule for any future statement
form, not a special case for the two that exist.

## What follows

- `docs/reference/ast.md`: the two per-construct sentences that already state
  the fact ("Both the `pop_jump_if_falsy` and the `jump` carry the `if` node's
  own position, not the condition's", and its `while` twin) stay; the "Which
  token a node blames" section gains the rule and the `store` contrast, so the
  next reader finds a reason rather than an observation.
- A test pins the position for `if "a" { y = 1 }`.
- No change to `lib/predicator/visitors/instructions_visitor.ex`.
