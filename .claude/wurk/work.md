# Predicator-ex extension: /wurk:work

The ISA sizing rule and this project's Direction reading list. Adds only - see
`~/.claude/skills/wurk:work/SKILL.md` for everything this does not repeat.

## The ISA sizing rule

A bead that adds, removes, renames, or alters an opcode is never a
just-do-it-sized job. It moves the exported specification (ADR-0003) and owes
a version, a `docs/isa.md` entry, a conformance-corpus tier, and a migration
note, so it goes plan-first at minimum. Carve-out: touching instruction
*handling* without altering an opcode does not bump the size.

## Other sizing triggers

Anything crossing more than one `area:` label starts at plan-first at the
latest.

## Direction reading list

`docs/adr/`, `docs/architecture.md`, `docs/reference/language.md`.

## ADR authoring rules for Direction work

- Use the next free ADR number.
- **Register it in `docs/adr/README.md`'s index** - no generic equivalent
  covers this step.
- **No `proposed` status.** An ADR here is `accepted` or nothing; a narrower
  call that doesn't warrant its own ADR goes to `docs/research/` instead.

## The closing report

State whether the work moved the ISA and to what version, so it reaches the
commit message and the PR body.
