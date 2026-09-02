# Predicator-ex extension: /wurk:release

Hex recipe detail beyond the manifest fields, and the release trigger. Adds
only - see `~/.claude/skills/wurk:release/SKILL.md` for everything this does
not repeat.

## Where the fields live

- `@version` is `mix.exs:5`.
- The README pin is the `{:predicator, "~> 4.0"}` snippet at `README.md:26`,
  and moves only on a major/minor bump - a patch release leaves it alone.
- The unreleased entries are the fragment files in `changelog.d/` (one per
  issue; `changelog.d/README.md` is the rationale, not a fragment). A release
  assembles them into a dated version section at the top of `CHANGELOG.md` and
  deletes the fragments. `CHANGELOG.md` has no `## [Unreleased]` section to
  promote, and none is ever created.

## The README pin's exact form

`{:predicator, "~> X.Y"}` - patch dropped, so the edit is unambiguous.
`release.readme_pin: true` in the manifest only says a pin exists; this is
where its exact shape lives.

## `mix hex.publish` has no trigger, ever

Not delegable, and no instruction in a session grants it (CLAUDE.md's
authority table; ADR-0006). Tag and push stay separately human-gated.

## The release trigger

An operator-authorized release bead, inside a campaign carrying the
operator's explicit consent; or the user asking for a release in their own
words. Where the operator does not name a version, it is this recipe's
SemVer call from the accumulated `changelog.d/` fragments. Never inferred
from a merged PR, from accumulated fragments on their own, or from "ship
it"/"cut it" said about something else. The tag, the push and the publish
stay the operator's - see CLAUDE.md's authority table, which this section
must not outrun.
