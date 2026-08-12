# if/block nodes return a not-supported error instead of crashing

## Overview

`{:if, ...}` and `{:block, ...}` - the AST nodes px-3so.2 taught the parser to
build - have no clause in either visitor, so `Predicator.execute/2,3` and
`Predicator.decompile/2` raise `FunctionClauseError` on any program containing
one. ADR-0004 makes errors values, so this is a recorded convention breach, not
a matter of taste. This plan adds an explicit not-supported clause to each
visitor and threads its `{:error, struct}` out to the public API, as the
interim fix px-aen names. Bead: px-aen.

## Current State Analysis

**The crash is real and reproducible today** (verified in this worktree with
`mix run`):

```
Predicator.compile_program("if a { x = 1 }")
#=> ** (FunctionClauseError) no function clause matching in
#     Predicator.Visitors.InstructionsVisitor.visit_annotated/2

{:ok, ast} = Predicator.parse_program("if a { x = 1 }")
Predicator.decompile(ast)
#=> ** (FunctionClauseError) no function clause matching in
#     Predicator.Visitors.StringVisitor.do_visit/2
```

`Predicator.evaluate/3` and `Predicator.parse/2` are **not** affected: the
expression parser rejects `if` up front with a `ParseError` naming
`parse_program/2` (verified; also documented at
`docs/reference/language.md:266-269`). Only the program-shaped entry points
reach a visitor with one of these nodes.

- **The nodes.** `{:if, condition, then_block, else_block, position}` (5-tuple)
  and `{:block, statements, position}` (3-tuple), typed at
  `lib/predicator/parser.ex:197` and `lib/predicator/parser.ex:208`. Both are
  deliberately **outside** `t:Predicator.Parser.ast/0`
  (`lib/predicator/parser.ex:157-175`): `t:statement/0` is
  `assignment() | if_statement() | ast()`, and a `block()` appears only as an
  `if`'s then/else slot.
- **InstructionsVisitor.** `visit_annotated/2`
  (`lib/predicator/visitors/instructions_visitor.ex:167-354`) is a ~20-clause
  recursive walk returning a bare `[annotated()]` list. Its `@spec` is
  `Parser.ast() | Parser.program() | Parser.assignment()` - it does not admit
  `if_statement()` or `block()`. `visit_statement/2`
  (`instructions_visitor.ex:378-385`) already takes a `Parser.statement()` and
  falls through to `visit_annotated/2` for anything that is not an assignment,
  which is the exact call that crashes.
- **StringVisitor.** `do_visit/2`
  (`lib/predicator/visitors/string_visitor.ex:117-289`) returns a bare
  `binary()`. Its `@spec` is
  `Parser.ast() | Parser.program() | Parser.statement()`, so `{:if, ...}` is
  already inside the declared input type while no clause matches it; `block()`
  is outside it.
- **Neither return shape has room for an error value**, which is the design
  problem this plan resolves (see Implementation Approach).
- **Compiler is a pass-through.** `Predicator.Compiler`
  (`lib/predicator/compiler.ex`) is four thin functions - `to_instructions/2`,
  `to_instructions_with_positions/2`,
  `to_instructions_with_segment_positions/2`, `to_string/2` - each forwarding
  to a visitor entry point and returning its value unchanged. It needs spec and
  doc changes only, no logic.
- **The public call sites that must widen** are all in `lib/predicator.ex`:
  `evaluate/3` (line 195), `execute_value/3` (line 470), `compile/1` (line
  650), `compile_program/1` (line 728), `build_compiled_result/1` (line 764,
  serving `compile_with_positions/1`, `compile_with_spans/1`, and
  `compile_program_with_positions/1`), and `decompile/2` (line 865).
- **Both natural resolvers are still open.** px-3so.3 (ISA v5 lowering:
  `jump`, `pop_jump_if_falsy`, `@isa_version` 5) and px-3so.5 (StringVisitor
  round-trip, including the `else if` printing rule) are both `open`. Neither
  can be pre-empted here.
- **Documentation already promises this behaviour.** `CHANGELOG.md`'s
  `[Unreleased]` `if`/`else` bullet and `docs/reference/language.md:272-277`
  both say `execute/2,3` and `decompile/2` "do not yet accept a program
  containing one". Today they crash rather than declining; this plan makes the
  documented sentence true.
- **The repo already has this exact escape mechanism, checked in.**
  `Predicator.Duration.add_unit/3` (`lib/predicator/duration.ex:109`) throws
  from a leaf clause and `build_duration_from_units/2`
  (`duration.ex:76-80`) catches it and returns `{:error, message}`. The
  no-raise half of ADR-0004 is about what the **host observes**; an internal
  throw converted to a value before the boundary satisfies it, as ADR-0004's
  own consequences accept for `resolve_atom_key/2`'s rescue and
  `call_function/4`'s rescue.

### Key Discoveries:

- The shallowest unsupported node in any parser-produced tree is always a
  direct element of the top-level `{:program, ...}` statement list - a `block`
  only occurs inside an `if`, and an `if` only occurs as a statement. A
  **hand-built** AST can bury one deeper (`{:logical_not, {:if, ...}, nil}`),
  which is precisely the sibling-implementer case ADR-0004's px-pp7 consequence
  calls out. This is why a shallow pre-pass is rejected below.
- `Predicator.Errors.put_position/2` (`lib/predicator/errors.ex:44-56`)
  discriminates `nil`, a point position, and a span, and no-ops on a struct
  without the field - so the not-supported error can carry the `if` keyword's
  own annotation with no mode-specific code.
- `Predicator.Errors.EvaluationError` (`lib/predicator/errors/evaluation_error.ex`)
  carries `message`, `reason`, `operation`, `position`, `span` and has
  `@enforce_keys [:message, :reason]`. `reason` is the structured discriminator
  the family already uses (`"division_by_zero"`, `"not_a_container"`,
  `"insufficient_operands"`).
- Dialyzer will reject a `visit_annotated({:if, ...}, _opts)` clause against
  the current `@spec`, because `if_statement()` is not in that input union. The
  widening has to reach `Predicator.Visitor`'s `@callback visit/2` as well:
  an `@impl` `@spec` whose argument type is narrower than the callback's is a
  dialyzer `callback_spec_arg_type_mismatch`. `.quality.exs` also sets
  `compile: [warnings_as_errors: true]`, so nothing may be left warning.
- `CHANGELOG.md`'s `if`/`else` entry is under `[Unreleased]`, so this is a
  refinement of an unreleased bullet rather than a new user-facing change -
  except for `decompile/2`'s widened return type, which touches a shipped
  function and is called out separately.
- The precedent for a missing visitor clause in this repo is px-7k2 (closed),
  which fixed it by **adding the real clause**. That option is not available
  here: the real clause is px-3so.3's and px-3so.5's work, and px-3so.3 mints
  ISA v5.

## Desired End State

Every public entry point that can be handed an `{:if, ...}` or `{:block, ...}`
node returns a value describing the refusal, and no path raises
`FunctionClauseError`:

| Entry point | Result |
|---|---|
| `Predicator.execute/2,3` | `{:error, %EvaluationError{reason: "unsupported_node"}, context}` |
| `Predicator.execute_value/3` | same three-tuple |
| `Predicator.decompile/2` | `{:error, %EvaluationError{reason: "unsupported_node"}}` |
| `Predicator.compile_program/1`, `compile/1` | `{:error, binary()}` |
| `Predicator.compile_program_with_positions/1` and siblings | `{:error, binary()}` |
| `Predicator.evaluate/3` | `{:error, %EvaluationError{}}` (unreachable in practice - `parse/2` rejects `if` first - but typed and handled) |
| `Predicator.Compiler.*`, `InstructionsVisitor.visit*`, `StringVisitor.visit` | `{:error, %EvaluationError{}}` |

Verified by: `mix quality` green, plus the new tests named in each phase, plus
the manual `iex` reproductions from Current State Analysis returning tuples.

## What We're NOT Doing

- **Not lowering `if`/`else` to instructions.** That is px-3so.3: two new
  opcodes, ISA v5, `docs/isa.md` rows, corpus tier 8. This plan adds no opcode,
  bumps no ISA version, and regenerates no corpus - which is why this document
  carries no `## ISA Impact` section (`.claude/wurk/plan.md` requires that
  section only for an opcode change).
- **Not teaching StringVisitor to render `if`/`else`.** That is px-3so.5,
  including ADR-0013's `else if` printing rule and the
  parse -> print -> parse fixpoint property. `.claude/wurk/plan.md`'s standing
  "a new AST node round-trips through StringVisitor" criterion is not owed
  here: this bead adds no node (px-3so.2 added them) and the round-trip is
  px-3so.5's acceptance criterion by name.
- **Not adding a catch-all clause to either visitor.** A catch-all would
  convert a genuine internal dispatch bug - a typo in a node shape, a new node
  wired to the parser and forgotten in a visitor - into a user-visible error
  value, hiding the defect. Two named clauses for the two named nodes keep
  every other missing clause loud, and px-3so.3 / px-3so.5 delete exactly the
  clause each of them supersedes.
- **Not introducing a new public error struct.** See the open questions below.
- **Not adding a `while` clause.** `while` is a reserved word that does not
  parse (`test/predicator/if_statement_test.exs:199`), so no `{:while, ...}`
  node exists to guard against.
- **Not changing `Predicator.evaluate/3`'s observable behaviour.** Its error
  arm for these nodes is unreachable while `parse/2` rejects `if`; it is
  handled only because the widened `Compiler` return type makes the current
  hard destructuring a latent `MatchError`.
- **Not touching `docs/architecture.md` or `docs/isa.md`.**

## Implementation Approach

### The design problem

`visit_annotated/2` returns a bare `[annotated()]` and `do_visit/2` returns a
bare `binary()`. Neither has a slot for an error value, and both are deeply
recursive, so there is no obvious place for a `{:error, ...}` to originate.
Four mechanisms were considered:

1. **Thread `{:ok, _} | {:error, _}` through the recursion.** Rewrites ~20
   clauses in `InstructionsVisitor` and ~25 in `StringVisitor` into `with`
   chains, and makes the short-circuit offset arithmetic
   (`length(right_instructions) + 1`, `instructions_visitor.ex:243`) awkward.
   It is also churn px-3so.3 and px-3so.5 would immediately have to work
   around, on a fix that is by construction temporary. **Rejected on blast
   radius.**
2. **A pre-pass that validates the AST before compiling or rendering.** Purest
   against ADR-0004 - no throw anywhere - and cheap for parser-produced trees,
   since the shallowest bad node is always a top-level statement. But to be
   sound against a **hand-built** AST it has to re-walk every node shape,
   duplicating the visitor's whole clause table into a second list that can
   drift from it. A hand-built artifact is exactly the case ADR-0004's px-pp7
   consequence says the rule must cover. **Rejected on soundness.**
3. **Raise a bespoke exception and rescue at the boundary.** Equivalent in
   effect to (4) but adds an exception module for a temporary fix, and a
   `rescue` invites being widened later to catch `FunctionClauseError`, which
   would swallow real bugs. **Rejected as strictly worse than (4).**
4. **Throw a tagged tuple from the not-supported clause; catch it at each
   visitor's public entry point and return `{:error, struct}`.** *Chosen.* It
   fires if and only if the visitor genuinely has no clause for that node, at
   any depth and from any caller. It leaves every recursive clause and both
   internal return types untouched, so the union appears only at the four
   public entry points where it belongs. The catch pattern is one specific tag,
   so anything else still crashes loudly. And it is the shape already checked
   into this repo at `lib/predicator/duration.ex:76-109`.

ADR-0004 is satisfied because the throw never crosses a public boundary: the
observable contract at every entry point is a value. That is the same line
ADR-0004 already draws for `resolve_atom_key/2`'s internal rescue and for
`call_function/4` converting a raising host function.

### The shape

Each visitor gets its own private helper - the two are not shared, because the
message differs per visitor and because keeping them independent is what lets
the two phases land separately, and each is deleted whole by its resolver:

```elixir
# In each visitor, next to its other private helpers
@spec unsupported_node(binary(), Types.position() | Types.span() | nil) :: no_return()
defp unsupported_node(construct, annotation) do
  error =
    EvaluationError.new(
      "'#{construct}' does not compile to instructions yet - lowering control " <>
        "flow needs the ISA v5 jump opcodes (ADR-0013)",
      "unsupported_node"
    )

  throw({:unsupported_node, Errors.put_position(error, annotation)})
end
```

The throw tag `:unsupported_node` is distinct from `Duration`'s `{:error, msg}`
throw, which is caught inside `Duration` and never escapes it.

### Spec widening

`Predicator.Parser` gains one public type so the widening is a single name
rather than a four-way union repeated at eight sites:

```elixir
@typedoc """
Anything a visitor accepts: a whole program, any single statement, or the
block an if statement holds. Wider than `t:ast/0`, which is the expression
layer only.
"""
@type visitable :: program() | statement() | block()
```

(`statement()` already unions `assignment()`, `if_statement()`, and `ast()`,
so `visitable()` covers every previous spelling.)

### Decisions taken without a human (open questions)

This plan was produced in an unattended run. Three points would normally be put
to the maintainer; each is recorded here with the default taken.

1. **Error struct: reuse `EvaluationError` or add
   `Predicator.Errors.UnsupportedNodeError`?** *Assumption taken: reuse
   `EvaluationError` with `reason: "unsupported_node"`.* A new struct would
   join the public error family documented in `lib/predicator.ex`'s "Error
   Types" list and in ADR-0004's consequences, and would then be deleted two
   beads later when px-3so.3 and px-3so.5 land - churn on a public surface for
   a temporary condition. `reason` is exactly the discriminator this family
   uses for sub-cases. The stretch is that "evaluation" names a compile-stage
   failure; that is accepted as the smaller cost. If the maintainer prefers a
   distinct struct, only `unsupported_node/2` and the tests change.
2. **Widening `decompile/2` from `binary()` to
   `binary() | {:error, struct()}`.** *Assumption taken: widen, as px-aen's
   acceptance criteria states in so many words.* No previously-working call
   changes behaviour - every AST that returned a binary still does - but a
   caller with a `binary()`-typed variable will see a new dialyzer union. This
   is the only shipped-surface change in the plan and is called out in the
   changelog entry.
3. **Area labels.** px-aen carries `area:evaluator` and `area:visitors`. The
   changelog amendment (and the one-line `docs/reference/language.md`
   clarification in Phase 2) put it in `area:docs` as well. *Assumption taken:
   make the edits and add `area:docs` to the bead* - per CLAUDE.md a branch
   touching an unlabelled area is "worth noticing at merge time", and
   `CHANGELOG.md` is unavoidable here regardless. `area:docs` is not exclusive,
   so no batching consequence follows.

---

## Phase 1: InstructionsVisitor declines if/block; execute/3 returns a value

### Overview

The primary half of the acceptance criteria: `Predicator.execute/2,3` and
every other program-compiling entry point return a value instead of crashing.
This phase also lands the shared type work (`Parser.visitable`, the `Visitor`
callback widening) that Phase 2 builds on.

### Changes Required:

#### 1. The visitable type

**File**: `lib/predicator/parser.ex`
**Changes**: Add the `@typedoc` + `@type visitable :: program() | statement() | block()`
shown in Implementation Approach, placed after the `statement()` typedoc
(around line 213).

#### 2. The visitor behaviour and both of its implementations

**Files**: `lib/predicator/visitor.ex`, and one `@spec` line in
`lib/predicator/visitors/string_visitor.ex`
**Changes**: Widen the `@callback visit/2` argument (line 52) and
`accept/3`'s `@spec` (line 65) from `Parser.ast() | Parser.program()` to
`Parser.visitable()`. Both must move together, or `accept/3` calling a
widened impl mismatches.

**Both `@impl` implementations must move in the same commit.** Widening the
callback makes *every* narrower impl spec a dialyzer
`callback_spec_arg_type_mismatch`, and `StringVisitor` is one -
`lib/predicator/visitors/string_visitor.ex:61,111-112` declares
`@behaviour Predicator.Visitor`, marks `visit/2` `@impl`, and specs its input
as `Parser.ast() | Parser.program()`. So this phase also edits that one `@spec`
line to `Parser.visitable()` input, and **nothing else in that file** - the
clauses, the helper, the `catch`, and the widened *return* type are Phase 2's.
Widening an input spec ahead of the behaviour is honest: a wider input type
promises nothing about success, only about what the function may legally be
handed.

#### 3. InstructionsVisitor

**File**: `lib/predicator/visitors/instructions_visitor.ex`
**Changes**:

- Add `alias Predicator.Errors` and
  `alias Predicator.Errors.EvaluationError` to the existing alias block
  (line 48).
- Widen `visit_annotated/2`'s `@spec` (lines 167-169) to `Parser.visitable()`;
  this is what makes the new clauses legal to dialyzer.
- Add the two clauses immediately before the `{:program, ...}` clause
  (line 340), so they read next to the statement-layer clauses:

```elixir
# ISA v5's jump opcodes are px-3so.3's work, so control flow has no lowering
# yet. Declining explicitly keeps the contract a value (ADR-0004) instead of
# a FunctionClauseError; px-3so.3 replaces this clause with the real one.
defp visit_annotated({:if, _condition, _then_block, _else_block, annotation}, _opts),
  do: unsupported_node("if", annotation)

defp visit_annotated({:block, _statements, annotation}, _opts),
  do: unsupported_node("block", annotation)
```

- Add the `unsupported_node/2` helper from Implementation Approach.
- Widen the three public entry points' `@spec`s to `Parser.visitable()` input
  and a `| {:error, struct()}` return, and wrap each body in the catch:

```elixir
def visit(ast_node, opts \\ []) do
  ast_node
  |> visit_annotated(opts)
  |> Enum.map(&elem(&1, 0))
catch
  {:unsupported_node, error} -> {:error, error}
end
```

  The same `catch` block goes on `visit_with_positions/2` and
  `visit_with_segment_positions/2`. Update each `@doc` to name the error
  return.

#### 4. Compiler pass-through

**File**: `lib/predicator/compiler.ex`
**Changes**: Widen the input to `Parser.visitable()` and add
`| {:error, struct()}` to the returns of `to_instructions/2`,
`to_instructions_with_positions/2`, and
`to_instructions_with_segment_positions/2`. No body changes - each already
returns its visitor's value unchanged. Add a sentence to each `@doc` naming
the error return. Existing doctests are unaffected.

#### 5. Public entry points

**File**: `lib/predicator.ex`
**Changes**: five call sites stop destructuring unconditionally.

- `evaluate/3` binary arm (line 195): `case` the
  `Compiler.to_instructions_with_positions/1` result;
  `{:error, error} -> {:error, error}`.
- `execute_value/3` binary arm (line 470): `case` the
  `Compiler.to_instructions_with_segment_positions/1` result;
  `{:error, error} -> {:error, error, normalize_context(context, opts)}` -
  the same shape the `ParseError` arm two lines below already returns, and
  the shape `execute/3`'s `drop_last_value/1` passes straight through.
- `compile/1` (line 650) and `compile_program/1` (line 728): `case` the
  `Compiler.to_instructions/1` result; `{:error, error} -> {:error, error.message}`
  to match the declared `{:error, binary()}`.
- `build_compiled_result/1` (line 764): same, so
  `compile_with_positions/1`, `compile_with_spans/1`, and
  `compile_program_with_positions/1` are all covered by one edit.

#### 6. Changelog

**File**: `CHANGELOG.md`
**Changes**: Amend the final sentence of the existing `[Unreleased]`
`if`/`else` bullet so "do not yet accept a program containing one" reads that
they **return an `{:error, ...}` tuple naming the unsupported construct**. No
new bullet - the feature is unreleased.

#### 7. Tests

**File**: `test/predicator/visitors/instructions_visitor_test.exs` (new
describe block) and `test/predicator/execute_test.exs`
**Changes**:

- `Predicator.execute("x = 1; if x > 0 { y = 2 }")` returns
  `{:error, %EvaluationError{reason: "unsupported_node"}, %Context{}}`, and
  the returned context carries the writes that completed before the
  refusal - here, nothing, since compilation fails before any statement runs
  (assert `ctx.data == %{}`).
- `Predicator.execute_value/3` returns the identical three-tuple.
- `Predicator.compile_program/1` returns `{:error, binary()}` and
  `compile_program_with_positions/1` likewise.
- The error's `position` is the `if` keyword's `{1, 8}` in the example above
  (point mode), and its `span` is set when the program is parsed with
  `spans: true`.
- A bare `{:block, [], nil}` handed to `Compiler.to_instructions/1` returns
  `{:error, ...}` rather than crashing - the hand-built-AST case.
- A **nested** `if` reached through an `else` block
  (`if a { } else if b { }`) also returns the error, proving the clause fires
  at depth rather than only at the top of the statement list.
- Negative control: an ordinary program (`"x = 1; x + 1"`) still returns
  `{:ok, ...}`, so the catch has not swallowed the happy path.

### Success Criteria:

#### Automated Verification:
- [x] `mix quality` is green - format, `compile --warnings-as-errors`, credo
      `--strict`, dialyzer, deps audit, full suite with coverage.
- [x] Dialyzer specifically reports no `callback_spec_arg_type_mismatch` and
      no unmatched-pattern warning on the two new `visit_annotated/2` clauses.
- [x] Coverage stays above `coveralls.json`'s 90% minimum, with the new
      clauses and the two `catch` blocks covered by the tests above.
- [x] `grep -rn "FunctionClauseError" test/predicator/execute_test.exs`
      returns nothing - the tests assert values, not rescued crashes.
- [x] No file under `conformance/` changes (`git status --porcelain conformance/`
      is empty) - this phase moves no opcode and no exported specification, so
      `mix corpus.generate` is not run and ADR-0003's corpus-diff obligation is
      not triggered.
- [x] `Predicator.isa_version() == 4` still holds
      (`test/predicator/isa_sync_test.exs` unchanged and green).

#### Manual Verification:
- [ ] In `iex -S mix`, the bead's first reproduction -
      `Predicator.execute("x = 1; if x > 0 { y = 2 }")` - returns a
      three-tuple, and the message reads sensibly to someone who has not read
      this plan.
- [ ] The error's `position` points at the `if` keyword, not at the enclosing
      statement or the `=`, when checked against the source by eye.
- [ ] No regression in the statement-mode integration suite's behaviour when
      exercised by hand (`test/predicator/integration/statements_test.exs`
      cases re-run in `iex`).

**Implementation Note**: Use `mix quality --profile loop` between edits and
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

## Phase 2: StringVisitor declines if/block; decompile/2 returns a value

### Overview

The second half of the acceptance criteria: `Predicator.decompile/2` on a tree
containing an `if` or a `block` returns `{:error, ...}` instead of crashing.

**Depends on Phase 1**, and not only for the `Parser.visitable` type: Phase 1
widens `Predicator.Visitor`'s `@callback visit/2`, which forces
`StringVisitor.visit/2`'s input `@spec` to move at the same time or dialyzer
goes red. Phase 1 therefore lands that one `@spec` line; this phase supplies
everything behind it. Beyond that shared seam the two phases touch disjoint
code - `StringVisitor`, `Compiler.to_string/2`, and `decompile/2` here; the
instruction path there.

### Changes Required:

#### 1. StringVisitor

**File**: `lib/predicator/visitors/string_visitor.ex`
**Changes**:

- Replace the lone `alias Predicator.Parser` (line 63) with
  `alias Predicator.{Errors, Parser, Types}` plus
  `alias Predicator.Errors.EvaluationError`. **`Types` is not currently
  aliased in this file** - `InstructionsVisitor` has it via
  `alias Predicator.{Parser, Types}` but `StringVisitor` does not, and the
  helper's `@spec` below names `Types.position()` and `Types.span()`.
- Widen `do_visit/2`'s `@spec` (line 117) to `Parser.visitable()` - this is
  what admits `block()`, which the current union omits.
- Add the two clauses immediately before the `{:program, ...}` clause
  (line 283):

```elixir
# Rendering control flow back to source is px-3so.5's work, including
# ADR-0013's else-if printing rule. Declining explicitly keeps the contract a
# value (ADR-0004) rather than a FunctionClauseError.
defp do_visit({:if, _condition, _then_block, _else_block, annotation}, _opts),
  do: unsupported_node("if", annotation)

defp do_visit({:block, _statements, annotation}, _opts),
  do: unsupported_node("block", annotation)
```

- Add the `unsupported_node/2` helper, with a message naming decompilation
  rather than instruction lowering.
- Widen `visit/2`'s `@spec` (line 112) **return** to
  `binary() | {:error, struct()}` - its input was already widened to
  `Parser.visitable()` by Phase 1, which had to move it in lockstep with the
  `@callback` - and add the `catch` clause to its body. `precedence/1`'s existing catch-all (line 409) is unreachable for
  these nodes because the throw happens first; leave it alone.

#### 2. Compiler pass-through

**File**: `lib/predicator/compiler.ex`
**Changes**: Widen `to_string/2`'s `@spec` to `Parser.visitable()` input and
`binary() | {:error, struct()}` return, and note the error return in its
`@doc`. No body change.

#### 3. Public entry point

**File**: `lib/predicator.ex`
**Changes**: Widen `decompile/2`'s `@spec` (line 863) to
`Parser.visitable()` input and `binary() | {:error, struct()}` return, and add
a `## Returns` note plus a doctest showing the refusal:

```
    iex> {:ok, ast} = Predicator.parse_program("if a { x = 1 }")
    iex> {:error, error} = Predicator.decompile(ast)
    iex> error.reason
    "unsupported_node"
```

Body is unchanged - `Compiler.to_string/2` already returns the value.

#### 4. Changelog and language reference

**File**: `CHANGELOG.md`
**Changes**: Add one bullet under `[Unreleased]` -> `### Changed` recording
that `Predicator.decompile/2`'s return type widens to
`binary() | {:error, struct()}`. This is the one shipped-surface change in the
plan and warrants its own entry rather than riding the unreleased `if`/`else`
bullet.

**File**: `docs/reference/language.md`
**Changes**: In the `if`/`else` callout (lines 272-277), change "do not accept
a program containing one" to say they **return an error tuple** naming the
construct, so the reader who follows the doc to the crash now finds the
documented behaviour instead.

#### 5. Tests

**File**: `test/predicator/visitors/string_visitor_test.exs` (new describe
block) and `test/predicator/compiler_test.exs`
**Changes**:

- `Predicator.parse_program("if a { x = 1 }")` piped into
  `Predicator.decompile/1` returns
  `{:error, %EvaluationError{reason: "unsupported_node"}}`.
- The same for a program with an `else` block and for an `else if` chain
  (`"if a { x = 1 } else if b { x = 2 }"`), which exercises the nested case.
- A bare `{:block, [], nil}` and a bare `{:if, ..., nil}` handed directly to
  `Predicator.Compiler.to_string/1` both return `{:error, ...}` - the
  hand-built-AST case.
- The error's `position` is the `if` keyword's, matched against the parsed
  tree's annotation.
- Negative controls: `decompile/2` on an ordinary expression and on a program
  of assignments (`"a = 1; b = 2"`) still returns a binary, and the existing
  round-trip tests in this file still pass, proving the catch has not changed
  the happy path.

### Success Criteria:

#### Automated Verification:
- [x] `mix quality` is green.
- [x] The new `decompile/2` doctest passes (`mix test --only doctest` or the
      full run).
- [x] Coverage stays above the 90% minimum, with both new `do_visit/2`
      clauses and the `catch` block covered.
- [x] `git status --porcelain conformance/` is empty - no exported
      specification moves.
- [x] Every existing `test/predicator/visitors/string_visitor_test.exs` case
      passes unchanged, i.e. no existing round-trip assertion was edited to
      accommodate the union return.

#### Manual Verification:
- [ ] In `iex -S mix`, the bead's second reproduction -
      `{:ok, ast} = Predicator.parse_program("if a { x = 1 }")` then
      `Predicator.decompile(ast)` - returns `{:error, error}` and
      `error.message` reads sensibly.
- [ ] `docs/reference/language.md`'s callout, read end to end, now matches
      what the two entry points actually do.
- [ ] Both bead reproductions are re-run together after both phases have
      landed, confirming neither visitor can still be reached with a node it
      has no clause for - the confirmation px-aen's description asks whichever
      resolver lands last to perform.

**Implementation Note**: Use `mix quality --profile loop` between edits and
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

## Testing Strategy

### Unit Tests:

- `test/predicator/visitors/instructions_visitor_test.exs` - the two new
  `visit_annotated/2` clauses reached through `visit/2`,
  `visit_with_positions/2`, and `visit_with_segment_positions/2`; the position
  carried on the error in both point and span modes; a nested `if` inside an
  `else` block, proving depth; a bare `{:block, [], nil}`, proving the
  hand-built case.
- `test/predicator/visitors/string_visitor_test.exs` - the two new
  `do_visit/2` clauses through `visit/2`; `else` and `else if` forms; bare
  nodes; the existing round-trip cases unchanged as negative controls.
- `test/predicator/compiler_test.exs` - all four `Compiler` functions return
  the error value rather than raising.
- Edge cases that actually bite here: an **empty** block (`if a { }`), which
  is a distinct parser output; an `else { }` with an empty block, which
  ADR-0013 keeps distinguishable from an absent one; and a program whose
  `if` is not the first statement, so the refusal happens after other
  statements have already compiled.

### Integration Tests:

- `test/predicator/integration/statements_test.exs` - end-to-end
  `Predicator.execute/2,3` and `Predicator.execute_value/3` on a program
  containing an `if`, asserting the `{:error, struct, context}` three-tuple
  and that `context.data` is the pre-run context (compilation fails before
  any statement executes, so no partial writes exist to preserve).
- One end-to-end case per compile-flavoured entry point -
  `compile_program/1`, `compile_program_with_positions/1` - confirming the
  `{:error, binary()}` shape rather than a struct.

### Manual Testing Steps:

1. `iex -S mix`, then `Predicator.execute("x = 1; if x > 0 { y = 2 }")` -
   expect a three-tuple whose error names `if`.
2. `{:ok, ast} = Predicator.parse_program("if a { x = 1 }")` then
   `Predicator.decompile(ast)` - expect `{:error, error}`.
3. `Predicator.evaluate("if a { x = 1 }")` - expect the pre-existing
   `ParseError`, unchanged.
4. `Predicator.execute("x = 1; y = x + 2")` and
   `Predicator.decompile(elem(Predicator.parse_program("a = 1; b = 2"), 1))` -
   expect the ordinary success values, confirming no happy-path regression.
5. Read the two new error messages as a user would: do they say what is not
   supported, and do they point at where?

## References

- Bead: `px-aen` (`area:evaluator`, `area:visitors`; `area:docs` to be added -
  see open question 3)
- Blocked-on-in-spirit beads, both still open: `px-3so.3` (ISA v5 lowering),
  `px-3so.5` (StringVisitor round-trip)
- Precedent for a missing visitor clause: `px-7k2` (closed) - fixed by adding
  the real clause, which is not available here
- Related ADRs: `docs/adr/0004-no-eval-errors-are-values.md` (the rule this
  bead enforces, and the px-pp7 consequence that makes hand-built ASTs count),
  `docs/adr/0013-control-flow-lowers-to-new-jump-opcodes.md` (what the real
  lowering will be), `docs/adr/0003-the-elixir-implementation-leads-the-isa.md`
  (why no ISA move happens here)
- Throw/catch precedent in this repo: `lib/predicator/duration.ex:76-109`
- Source document: none - planned directly from the bead
- Project extension: `.claude/wurk/plan.md`

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] In `iex -S mix`, the bead's first reproduction -
      `Predicator.execute("x = 1; if x > 0 { y = 2 }")` - returns a
      three-tuple, and the message reads sensibly to someone who has not read
      this plan.
- [ ] The error's `position` points at the `if` keyword, not at the enclosing
      statement or the `=`, when checked against the source by eye.
- [ ] No regression in the statement-mode integration suite's behaviour when
      exercised by hand (`test/predicator/integration/statements_test.exs`
      cases re-run in `iex`).

**Implementation Note**: Use `mix quality --profile loop` between edits and
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

### Phase 2

- [ ] In `iex -S mix`, the bead's second reproduction -
      `{:ok, ast} = Predicator.parse_program("if a { x = 1 }")` then
      `Predicator.decompile(ast)` - returns `{:error, error}` and
      `error.message` reads sensibly.
- [ ] `docs/reference/language.md`'s callout, read end to end, now matches
      what the two entry points actually do.
- [ ] Both bead reproductions are re-run together after both phases have
      landed, confirming neither visitor can still be reached with a node it
      has no clause for - the confirmation px-aen's description asks whichever
      resolver lands last to perform.

**Implementation Note**: Use `mix quality --profile loop` between edits and
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---
