# Predicator-ex extension: /wurk:plan

Success criteria this project always wants, its optional sections, and its
domain patterns. Adds only - see `~/.claude/skills/wurk:plan/SKILL.md` for
everything this does not repeat.

## The `## ISA Impact` section

Include this section only when the change adds, removes, renames, or alters an
opcode; omit it entirely otherwise. Per ADR-0003 the Elixir implementation
leads the ISA, so it answers three mechanical questions rather than asking
what the siblings need:

1. **Version** - does this bump the current ISA version (`docs/isa.md`,
   section 1)? Additive (new opcodes only) ships in a minor release; retiring
   an opcode takes a major release. An opcode's semantics never change under
   its own name - a different answer from an existing form is a new name.
2. **Stamp** - what the change owes `docs/isa.md`: an opcode subsection, the
   version it enters at, and a conformance-corpus tier.
3. **Migration** - can an instruction list compiled before this change still
   run and produce the same answer? If not, name the upgrade path.

A sibling behind the current ISA version is expected and documented, never a
blocker (ADR-0003). `docs/isa.md` is the authority for any ISA question.

`wurk:plan` treats extension-declared sections as mandatory as its own nine,
so declaring `## ISA Impact` here is what re-arms it.

## Always-required automated criteria

- New code stays above the 90% coverage minimum in `coveralls.json`.
- A new AST/grammar node round-trips through `StringVisitor` without losing
  information.

## Optional section this project's plans carry

`## Performance Considerations` - include only when it applies.

## Phase-splitting along the pipeline's seams

Lexer, parser, compiler/instructions, evaluator, visitors. A grammar change
that `StringVisitor` cannot render back is an incomplete change, never a
follow-up phase.

## The precedence rule

Check the grammar and precedence table in `docs/architecture.md` before
proposing new syntax. Precedence is a whole-language decision, not a local
one, and the table is the specification.

## Corpus criteria

When a phase can move the exported specification, its criteria name
`mix corpus.generate` and the ADR-0003 obligation to explain a corpus diff in
the commit message and PR body.

## Required reading

`docs/adr/`, ADR-0001 (the 3.6-4.0 arc; the stack VM stays), ADR-0003 (this
repo is the ISA reference implementation), `docs/architecture.md`.

## Testing-strategy shape

- Unit tests: `test/predicator/**`, pattern-matching style; cover precedence,
  type mismatches, error positions - the edge cases that actually bite.
- `### Integration Tests` subsection: end-to-end `Predicator.evaluate/3` cases
  in `test/predicator/integration/`.

## Common patterns

- **New syntax**: lexer -> parser precedence -> the precedence table in
  `docs/architecture.md` -> `InstructionsVisitor` + `StringVisitor` ->
  evaluator -> ISA move if an opcode changed.
- **New function**: `lib/predicator/functions/`, arity and type checks as
  `{:ok, _} | {:error, _}` values, and cover the error paths - they are the
  coverage gap the gate finds.

## Code conventions a plan must respect

`@doc`/`@spec` on every public function, errors as values never raised at a
leaf, no `eval` or dynamic code execution anywhere.
