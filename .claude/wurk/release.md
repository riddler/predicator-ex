# Predicator-ex extension: /wurk:release

Hex recipe detail beyond the manifest fields, and the release trigger. Adds
only - see `~/.claude/skills/wurk:release/SKILL.md` for everything this does
not repeat.

## Where the fields live

- `@version` is the `@version "X.Y.Z"` module attribute in `mix.exs`. Resolve
  the line when you read this: `grep -n '@version "' mix.exs`.
- The README pin is the `{:predicator, "~> X.Y"}` snippet in the `def deps`
  example under `## Installation`. Resolve it the same way:
  `grep -n 'predicator, "~>' README.md`. It moves only on a major/minor bump -
  a patch release leaves it alone, so the two carriers agree on major and
  minor and say nothing about patch.
- The unreleased entries are the fragment files in `changelog.d/` (one per
  issue; `changelog.d/README.md` is the rationale, not a fragment). A release
  assembles them into a dated version section at the top of `CHANGELOG.md` and
  deletes the fragments. `CHANGELOG.md` has no `## [Unreleased]` section to
  promote, and none is ever created.

## The README pin's exact form

`{:predicator, "~> X.Y"}` - patch dropped, so the edit is unambiguous.
`release.readme_pin: true` in the manifest only says a pin exists; this is
where its exact shape lives.

**This file carries no version string and no line number, on purpose.** Both
rot on their own: a line number is wrong as soon as a line is inserted above
it, and a pinned version is wrong at the next minor. The sentence that used to
sit above named the pin by a version several majors old and by a README line
that had since moved down, and neither had been true for a long time when
`px-jci` found them - the same rotting-reference class `sb-0id2` and `sui-040`
fixed in the sibling recipes. The greps above resolve both carriers at read
time, so nothing here needs editing at a release and a release commit does not
touch this file.

If the two carriers ever disagree on major or minor, the pin edit goes straight
to the current major/minor in one move rather than stepping one release at a
time. That is the recipe repairing drift, not a mistake to correct back.

## `mix hex.publish` is the release workflow's, never a session's

An agent or a session never runs `mix hex.publish`; the release workflow
publishes on the tag push; a failed workflow is re-run from its Actions page,
never worked round by a local publish (CLAUDE.md's authority table; ADR-0018).
The tag is a separate step with its own owner - see the release trigger below.

## The release trigger

A release bead the operator has named (in the campaign plan or their own
words) - the family norm, not a grant a campaign consent has to name
(CLAUDE.md's Release preps paragraph); or the user asking for a release in
their own words. Where the operator does not name a version, it is this recipe's
SemVer call from the accumulated `changelog.d/` fragments. Never inferred
from a merged PR, from accumulated fragments on their own, or from "ship
it"/"cut it" said about something else. Once the prep is merged to
`origin/main`, the conductor or the session that owns the release bead tags
that merged commit with the new version and pushes the tag (CLAUDE.md's
Release preps paragraph). The release workflow publishes on that tag push,
the docs with the package, and no agent or session runs `mix hex.publish` -
see CLAUDE.md's authority table, which this section must not outrun.
