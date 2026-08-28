# Predicator-ex extension: /wurk:implement

This file is passed **by path** to `--loop` phase subagents that have no
other context, so it is written to need no external read to follow. See
`~/.claude/skills/wurk:implement/SKILL.md` for everything this does not
repeat.

## Pipeline completeness

Predicator's pipeline is source -> tokens -> AST -> instructions -> stack VM.
A syntax change that compiles to nothing, or an instruction nothing emits, is
half-finished. **A grammar change is not done until `StringVisitor` round-trips
it.** An opcode change moves the ISA (ADR-0003) and carries its version, its
`docs/isa.md` entry, and any migration note into the commit message and PR
body.

## The corpus discipline

When `test/predicator/conformance/corpus_freshness_test.exs` is red, the fix
is `mix corpus.generate` plus reading the resulting diff. Generated files
under `conformance/corpus/` and `conformance/manifest.json` are never
hand-edited - editing one to force the test green is a live failure mode, the
single most consequential mistake this file warns against.

## Errors are values

Never raise at a leaf, never rescue-to-default. No `eval`, no
`Code.eval_string`, no dynamic dispatch on user input.

## Credo suppressions are deliberate

Complexity suppressions in the lexer and parser are intentional and
documented in place. They are not a licence to add more elsewhere.

## Never weaken the gate

No lowered coverage threshold, no `enabled: false`, no `--skip-*` on the final
check, no `@tag :skip`. Report a genuinely wrong finding and let a human
decide. `mix quality.verify` (ex_quality's attestation, wired as
`gate.attest`) catches a *narrowed* run, but nothing catches a *weakened*
gate, and this repo has no `gate.guard_ledger` - so restate it here
explicitly. CLAUDE.md and the ADR-0008 deny rules are the only other place
this is said.

## Cover the error paths

The uncovered lines the gate finds are almost always the `{:error, _}`
branches. Write tests for them, not just the happy path.

## The span-slot contract

A hand-built AST node with a `nil` span renders identically to one carrying a
real span - `StringVisitor` and friends never require span data to produce
correct output. This is what makes parse -> visit -> parse round-tripping a
valid test strategy without also constructing spans by hand.

## Edge-case test naming

A test file exercising the edge cases of a feature (precedence surprises,
boundary values, malformed input) is named `*_edge_cases_test.exs`, not
folded into the feature's main test file.

## Two debugging moves

- Parse or precedence surprise: read the precedence table in
  `docs/architecture.md` - it is the specification.
- Evaluation surprise: print the compiled instruction list; the VM's behavior
  follows directly from it.

## Doctests are executed tests

`test/docs_examples_test.exs` executes the examples embedded in `docs/`, so a
documentation edit can turn the suite red. Treat a `docs/` change as code.

## Conventions a fresh subagent has not read

`@doc`/`@spec` on public functions, errors as `{:ok, _} | {:error, _}` values,
no `eval` or dynamic code execution, work lands on a feature branch and never
on `main`.
