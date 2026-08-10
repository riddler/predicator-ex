# Predicator-ex extension: /wurk:next

Two items with no generic home. Adds only - see
`~/.claude/skills/wurk:next/SKILL.md` for everything this does not repeat.

## Watch `area:api` in particular

It covers `lib/predicator.ex` and the error structs, which is where a
surprising number of otherwise-disjoint beads eventually meet. Two beads that
both touch the public façade carry `area:api` and are correctly not
batchable, even when their other areas are disjoint.

## Fresh-clone bootstrap

On a fresh clone with no `.beads/embeddeddolt/`, `bd dolt pull` has nothing to
pull from. Run `bd bootstrap` instead. This is not predicator-specific, but
`/wurk:next` has no equivalent step anywhere, so it is lost without this note.
File this upstream against wurk as well - an extension file carrying a
generic gap is a stopgap, not the fix.
