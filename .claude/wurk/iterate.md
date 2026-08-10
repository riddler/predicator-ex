# Predicator-ex extension: /wurk:iterate

Deliberately thin. `/wurk:iterate` already reads `.claude/wurk/plan.md`, so
this file does not duplicate the criteria or sections stated there - see that
file for the `## ISA Impact` section, the always-required criteria, and the
domain patterns a re-cut phase must still follow.

## Preserve the `## ISA Impact` section when re-cutting phases

If a phase being split or reworked carries an `## ISA Impact` section, carry
it into the resulting phase(s) rather than dropping it. A re-cut phase that
silently loses its ISA stamp - the version, the `docs/isa.md` entry, or the
migration note - is a regression in the plan, not a simplification of it.

## ADR contradiction

`~/.claude/skills/wurk:iterate/SKILL.md` already states the generic rule -
flag, never silently edit, a change that would contradict an accepted ADR - so
it is not restated here.
