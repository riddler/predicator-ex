# Predicator-ex extension: /wurk:research

Where to point a sub-agent outside this repo, and the ownership rules that
govern how a finding gets attributed. Adds only - see
`~/.claude/skills/wurk:research/SKILL.md` for everything this does not repeat.

Project layout, the pipeline, module families, and search keys now live in
`.claude/wurk/codebase.md`, the codebase-agent orientation file - it is
forwarded into every `wurk-codebase-*` prompt this skill spawns, so it is the
definition site rather than this file.

## Sibling-port guidance

The Ruby and JavaScript implementations live in the `riddler/predicator`
monorepo, outside this checkout. Point a sub-agent there **explicitly**, and
only when the question genuinely involves sibling behavior - it is a
comparison point, not part of this repo's own research surface.

## ADR-0003 / ADR-0010 ownership rule

The repository whose files change owns the decision. For the language, the
ISA, the compiled format, the corpus, and the release schedule that is this
repo; for how statifier consumes any of it, statifier's bead is authoritative
and this one defers.

## The ADR-0003/ADR-0001 rule

ADR-0003 *amends* ADR-0001 without superseding it. Never resurface ADR-0001's
cross-language-interchange framing as live. A decision's ISA effect is a
versioning and stored-artifact question, never a sibling-readiness one.

## Doc roots beyond `plans`/`research`

`docs/adr/`, `docs/design/`, `docs/guides/`, `docs/reference/`,
`docs/architecture.md`. The wurk docs agents glob a conventional candidate set
that does **not** include `docs/guides/` or `docs/reference/`, so naming them
here is what keeps them searched. `docs/architecture.md` carries per-feature
history with version numbers - it plus `CHANGELOG.md` is the fastest answer to
"when and why did this arrive".

## `## ISA Impact` in research documents

A research document carries its own `## ISA Impact` section when the subject
touches the instruction set.
