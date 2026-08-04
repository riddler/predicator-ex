# ADR-0001: Keep the stack VM; revise the instruction set (ISA v2)

Status: accepted (2026-08-03)

## Context

Predicator compiles an expression to a flat list of instructions and runs them
on a stack VM (`Predicator.Evaluator`). Six gaps were identified upstream by
statifier v2, which has committed to predicator as its only datamodel (statifier
ADR-0004). Three of them - persistent bound context, typed undefined, statement
sequences - touch the same code and interact, so all six were designed as one
system and reviewed on 2026-08-03 rather than patched one at a time. Statifier
tracks the upstream work as beads st2-qjs, st2-u41, st2-dxp, st2-bfq, st2-mxx,
st2-xoj, and st2-cys.

That design forced a prior question. For a single Elixir consumer, a
tree-walking evaluator over the AST would be simpler than a compiler plus a VM,
and the VM has one defect that a tree-walker would not have:

**`AND` and `OR` do not short-circuit.** The compiler emits
`left ++ right ++ [["and"]]`, so both sides always run. Verified on 3.5.0:

    false AND score > 5           -> {:error, TypeMismatchError}   (score unbound)
    user.age > 18 AND user.name = 'x'
                                  -> {:error, TypeMismatchError}   (user unbound)
    true OR (1 / 0) > 1           -> {:error, Division by zero}

Every SCXML `cond` guard written in the natural style trips this. It also
diverges from ECMAScript, from what the Ruby and JavaScript siblings' hosts
expect, and from what this library's own "graceful undefined handling"
documentation implies. In a stack VM the fix costs jump opcodes; in a
tree-walker it is free. That made the execution model the decision to settle
before building anything else on it.

Weighing against the rewrite: statifier's evaluation contract already assumes
compile-once-evaluate-many, holding expressions as `{:compiled, instructions,
source}` built at machine-build time. The instruction list is the natural
compiled artifact and is JSON-serializable, which keeps storing compiled
machines open. The instruction set is also predicator's cross-language
interchange format; parity with the Ruby and JavaScript siblings is already
partial (objects, durations, strict equality postdate them), so it is not a hard
constraint, but the format costs nothing to keep. And the alternative rewrites
roughly 1,100 LOC of evaluator and re-earns its share of 1,181 tests to arrive
at the same semantics.

## Decision

**Keep compile-to-instructions as the one execution path.** Treat the six seams
as the occasion for a deliberate instruction-set revision - ISA v2 - rather than
a reason to abandon the VM. Cross-language interchange is affirmed as a real
goal, not a legacy obligation: JavaScript-side tooling and editors are a
plausible consumer of compiled instruction lists.

ISA v2 comprises:

- **Short-circuit jumps.** `["jump_if_falsy_or_pop", offset]` and
  `["jump_if_true_or_pop", offset]`, relative and forward-only, in the style of
  Python bytecode: if the top of stack meets the condition, jump and *leave* it
  as the result; otherwise *pop* it and fall through into the right operand.
  `a AND b` compiles to `a`, `jump_if_falsy_or_pop end`, `b`; `a OR b` compiles
  to `a`, `jump_if_true_or_pop end`, `b`.

  The `:undefined` semantics are ECMAScript-aligned, not symmetric-Kleene:
  "falsy" means `false` or `:undefined`, "true" means exactly `true`. So
  `undefined AND x` short-circuits to `:undefined` without evaluating `x` (JS:
  `undefined && x` is `undefined`), while `undefined OR x` falls through and
  takes `x`'s value (JS: `undefined || x` is `x`) - which is what a guard author
  means by "either condition" and what the W3C ECMAScript tests assume. A
  symmetric propagation was rejected at review because it makes
  `missing_var OR In('a')` poison a true right side. Any other non-boolean on
  top of stack at a jump remains a `TypeMismatchError`; the opcodes validate,
  they do not perform general truthiness coercion.

  The existing `["and"]` and `["or"]` opcodes remain *accepted* by the evaluator,
  for previously compiled artifacts and for sibling implementations, but the
  Elixir compiler stops emitting them.

- **`["make_list", n]`** - pop n values, push a list. This removes the
  compiler's `raise "Non-literal list elements are not yet supported"`, the one
  place the errors-are-values convention is broken, and is required by the
  `[x + 1]` cases in the string/list seam.

- **`["store", n]`** - the assignment opcode for the statement layer, popping n
  path segments plus a value and writing through `ContextLocation.put/3`.

- **Mechanical fixes taken in the same pass.** Instructions are held as a tuple
  (`:erlang.list_to_tuple/1` at evaluator init) so fetch is O(1) rather than
  `Enum.at/2`, and `finished?` compares against a precomputed size instead of
  calling `length/1`.

- **Source positions.** AST nodes carry `{line, col}` threaded from the tokens,
  and the compiler emits a side table (`%{instruction_index => {line, col}}`)
  alongside the instruction list. The instruction format itself is unchanged, so
  interchange and stored artifacts are unaffected; the side table is an
  Elixir-side companion value. Runtime error structs gain an optional `position`
  field, populated when the evaluator is given the table.

ISA v2 ships in 3.7.0.

## Consequences

- **The short-circuit change is observable.** Expressions that returned an error
  on 3.5 evaluate successfully on 3.7+. By this library's own documentation that
  is a bugfix rather than a breaking change, but it must be called out as the
  headline changelog item for the release, because a consumer relying on the
  error is relying on the bug.
- Statement-level control flow (`if`, `while`) stays possible without redesign,
  because the VM has jumps once this lands. The statement layer in 4.0
  deliberately ships without it; that is a scope choice, not a limitation.
- The instruction list remains a flat, JSON-serializable artifact through every
  seam, including statement programs. The interchange story survives intact,
  which is the payoff of this decision.
- The Ruby and JavaScript siblings gain three opcodes to implement if they want
  parity. Until they do, an instruction list compiled here that contains jumps,
  `make_list`, or `store` will not run there - a wider gap than the existing
  partial parity, and a README note in each sibling.
- Old compiled artifacts keep running: `["and"]` and `["or"]` stay accepted.
  A stored instruction list is never invalidated by this revision.
- The tree-walker option is closed for as long as interchange is a goal.
  Reopening it means superseding this ADR, not quietly adding a second
  execution path.
