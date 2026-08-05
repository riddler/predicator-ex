# Release Mechanics Skill Implementation Plan

## Overview

Build a `/release` skill that automates the mechanical part of cutting a
Predicator release: bump `@version` in `mix.exs`, promote `CHANGELOG.md`'s
`## [Unreleased]` to a dated version header, and bump the README install
snippet's version pin. It stops there - `git tag`, `git push`, `gh pr create`,
`mix hex.publish`, and `bd close` stay explicit human-gated steps per
`CLAUDE.md`'s authority table, which lists no trigger for `mix hex.publish` at
all. Beads issue: px-7p9.

## Current State Analysis

The 3.7.0 release (`d9ff35c`) was cut by hand this morning and touched exactly
three files:

```
CHANGELOG.md | 89 +++++++++++++++++++++++++++++-------------------------------
README.md    |  2 +-
mix.exs      |  2 +-
```

- `mix.exs:5` - `@version "3.6.0"` -> `"3.7.0"`.
- `README.md:26` - `{:predicator, "~> 3.6"}` -> `{:predicator, "~> 3.7"}`. The
  pin is `~> MAJOR.MINOR`, not the full patch version.
- `CHANGELOG.md` - `## [Unreleased]` became `## [3.7.0] - 2026-08-05`, and the
  session also reordered/consolidated entries under that heading (leading
  with short-circuit AND/OR, merging duplicate `Changed`/`Fixed` sections left
  by separate feature PRs) and framed the ISA v2 additions for the Ruby/JS
  siblings per ADR-0001. No empty `## [Unreleased]` stub was left behind - the
  next commit to touch the changelog (`2184ab7`) re-adds that heading itself,
  which matches `/commit`'s Step 1.6 convention.

Its commit title, `Releases v3.7.0`, matches every prior release commit
(`git log --all --oneline --grep '^Releases '`): `v3.6.0`, `v3.5.0`, `v3.4.0`,
back to `v1.0.0`. `bd show px-7p9` records that this session's own release
commit needed a title amend - the skill exists partly to stop that recurring.

Per CLAUDE.md's authority table, "release mechanics (bump `@version` in
`mix.exs`, promote `## [Unreleased]` to a version header in `CHANGELOG.md`,
tag) - the user explicitly asks for a release **and** names the version" -
and separately, `mix hex.publish` has no trigger at all and is never
delegable. The row groups tagging in with the mechanical edits, but "tag" is
also visible/irreversible the moment it's pushed, and neither `git tag` nor
`git push` nor `gh pr create` has a trigger that fires from running this
skill alone; those still need the user's own words, same as any other push
(the generic `git push`/`gh pr create` row).

No skill in `.claude/skills/` currently does release work. `/commit` and
`/merge-request` are the closest shape: frontmatter with `name`,
`description`, `model: sonnet`, `argument-hint`; a numbered `## Steps`/
`## Process` section; explicit STOP conditions; a final report naming what was
and wasn't done. `/merge-request` in particular models "do the mechanical work,
then confirm before the irreversible step" - except here there's no
confirmable irreversible step inside the skill's scope at all, since tagging
and pushing are out of scope entirely.

`CLAUDE.md`'s "Everything lands on a feature branch and merges to `main` by
PR. There are no direct commits to `main`." applies uniformly; nothing carves
out release commits, even though the last two release commits
(`33eb02c`, `d9ff35c`) landed on `main` with no PR number, unlike earlier ones
(`bf49224 ... (#41)`). That's the hand-cut process this issue exists to
replace, not a convention to encode into the skill.

### Key Discoveries

- `d9ff35c` (`git show d9ff35c`) is the exact template for the mechanical
  diff shape and the commit body's phrasing style.
- `/commit`'s Step 0 carve-out ("a change touching no Elixir code has no gate
  to run") explicitly excludes `mix.exs` from the no-gate case - so a release
  commit, which always touches `mix.exs`, always runs the full `mix quality`
  gate, never the docs-only skip.
- `bd show px-7p9`'s acceptance criteria are exhaustive and unambiguous: bump
  version, promote header, bump README pin, commit titled `Releases vX.X.X`,
  stop short of tag/push/`hex.publish`/`bd close`, and require the same
  explicit human ask + named version that release mechanics already require -
  invoking the skill is not itself that ask unless it carries the version.
- `docs/architecture.md:116-120` points at `CLAUDE.md`, `## [Unreleased]`,
  itself, and the README as the places release-affecting decisions get
  recorded - none of that changes here; the skill only touches the three
  release-mechanics files.

## Desired End State

A `.claude/skills/release/SKILL.md` exists, invoked as `/release X.Y.Z`, that:

1. Refuses to run without an explicit, well-formed version argument - it does
   not infer a version from `Unreleased` content, semver bump rules, or
   anything else.
2. Refuses on `main`, on a dirty tree, on a version that isn't strictly
   greater than the current `@version`, and on an empty/missing
   `## [Unreleased]` section (nothing to release).
3. Makes exactly three mechanical edits: `mix.exs` `@version`, the README
   install snippet pin (`~> MAJOR.MINOR`), and the `CHANGELOG.md` heading
   (`## [Unreleased]` -> `## [X.Y.Z] - YYYY-MM-DD`, content untouched -
   reordering/curating entries is editorial judgment, not mechanics, and stays
   manual).
4. Runs the full `mix quality` gate (mix.exs changed, so the docs-only
   carve-out never applies) and refuses to commit on red.
5. Commits locally with title `Releases vX.Y.Z` and a body describing the
   three mechanical changes, no AI attribution, optionally a `Refs:` trailer
   if a bead/epic ID was supplied.
6. Reports explicitly that `git tag`, `git push`, `gh pr create`,
   `mix hex.publish`, and `bd close` were **not** run, and names the commands
   the user would run themselves next.

Verify by reading the finished `SKILL.md` against the checklist above, and by
walking its steps by hand against `61be076` (the commit immediately before
`d9ff35c`) with version `3.7.0` - the mechanical diffs it would produce
(`mix.exs`, README pin) should match `d9ff35c` exactly, and the CHANGELOG
heading line should match even though the curated content beneath it (which
stays manual) does not.

## What We're NOT Doing

- Not writing a `mix` task or standalone script - a skill markdown file is the
  right shape here, matching `/commit` and `/merge-request`, and the issue's
  own design note treats a `mix` task as optional ("if the logic warrants
  compile-time checks").
- Not tagging, pushing, opening a PR, or running `mix hex.publish` - these
  have no trigger the skill can fire, per CLAUDE.md's authority table.
- Not closing the beads issue or epic - `bd close` fires on a verified merge
  into `origin/main`, which a local commit is not.
- Not reordering, curating, or rewriting `CHANGELOG.md` content - only its
  heading line changes. Framing entries (as `d9ff35c` did) is a human editorial
  pass this skill does not attempt.
- Not inferring or defaulting the version number from `Unreleased` content,
  the latest git tag, or semver bump conventions - the acceptance criteria and
  CLAUDE.md both require the explicit human-named version as input every time.
- Not adding a new empty `## [Unreleased]` stub after promotion - matching
  `d9ff35c`'s actual result; the next commit that needs one adds it, per
  `/commit` Step 1.6.
- Not updating `docs/architecture.md`'s "(Unreleased)"/"(vX.Y.Z, unreleased)"
  annotations - those are prose the authoring session writes by hand when a
  feature lands, not something a release commit derives mechanically.

## Implementation Approach

Single phase: author `.claude/skills/release/SKILL.md` modeled directly on
`/commit` and `/merge-request` (frontmatter, numbered steps, explicit STOPs,
closing report of what was and wasn't done), add its row to `CLAUDE.md`'s
skills table, and verify it by hand-tracing its steps against the real
`d9ff35c` diff. This is a docs/skills-only change (`area:skills`) with no
Elixir code touched, so it's small enough for one phase and needs no
intermediate gate beyond the final `mix quality --profile loop` sanity check
described below.

## Phase 1: Author the /release skill

### Overview

Create the skill file, wire it into the skills table, and confirm its logic
reproduces the mechanical parts of the last real release.

### Changes Required

#### 1. `.claude/skills/release/SKILL.md` (new file)

**File**: `.claude/skills/release/SKILL.md`
**Changes**: New skill, modeled on `/commit` and `/merge-request`'s shape.

```markdown
---
name: release
description: Bump version, promote the changelog, and commit release mechanics - human-gated tag/push/publish stay separate
model: sonnet
argument-hint: ["X.Y.Z - the version being released; required, no default"]
---

# Release Mechanics

Automates the mechanical part of cutting a Predicator release: bump
`@version`, promote `CHANGELOG.md`'s `## [Unreleased]` to a dated version
header, and bump the README install snippet's pin. Nothing else. CLAUDE.md's
authority table gates `git tag`, `git push`, `gh pr create`, and
`mix hex.publish` on the user's own words - this skill never runs them, and
`mix hex.publish` has no trigger at all, ever.

## Trigger

`$ARGUMENTS` must be a semver `X.Y.Z` (optionally followed by free text, e.g.
notes to ignore). If it is missing or doesn't parse:

STOP and ask the user to name the exact version being released. Do not infer
one from `## [Unreleased]` content, the latest git tag, or semver bump rules -
CLAUDE.md's release-mechanics row requires the user to explicitly ask for a
release **and** name the version; running this skill is not itself that ask
unless the version came with it.

## Steps

### Step 0: Preconditions

```bash
git branch --show-current
git status --porcelain
```

STOP if the branch is `main` - this repo takes no direct commits to `main`,
release commits included; the two most recent hand-cut releases did this and
it's the process this skill replaces, not a convention to keep. STOP if the
tree is dirty - an uncommitted change is either unrelated (doesn't belong in
a release commit) or belongs in its own commit first.

```bash
grep '@version' mix.exs
```

Parse the current version and confirm `$ARGUMENTS`'s version is strictly
greater (compare major, then minor, then patch as integers). STOP on equal or
lesser - almost always a typo or the wrong argument.

```bash
sed -n '/## \[Unreleased\]/,/^## \[/p' CHANGELOG.md
```

STOP if `## [Unreleased]` is missing, or present with no bullets under it -
there is nothing to release.

### Step 1: Make the mechanical edits

Three files, three edits, nothing else:

1. **`mix.exs`**: `@version "OLD"` -> `@version "X.Y.Z"`.
2. **`README.md`**: find the install snippet's `{:predicator, "~> OLD_MAJOR.OLD_MINOR"}`
   and bump it to `{:predicator, "~> X.Y"}` - the pin drops the patch
   component, matching every prior release (check `git show d9ff35c` if
   unsure of the exact line).
3. **`CHANGELOG.md`**: replace the `## [Unreleased]` heading line with
   `## [X.Y.Z] - YYYY-MM-DD` using today's date. Leave every line under it
   untouched - reordering, consolidating, or reframing entries is an
   editorial pass a human does separately, not something this step infers.
   Do not add a new `## [Unreleased]` stub above it.

### Step 2: Run the gate

```bash
mix quality
```

`mix.exs` changed, so `/commit`'s docs-only carve-out does not apply here -
this step always runs, never `--profile loop` or any narrowed form. STOP on
red and report the failing stage; a version bump breaking the suite is
exactly what the gate exists to catch before it's a tagged release.

### Step 3: Commit

```bash
git status --porcelain
```

Confirm only `mix.exs`, `README.md`, and `CHANGELOG.md` are changed. STOP if
anything else is dirty - do not fold unrelated changes into a release commit.

```bash
git add mix.exs README.md CHANGELOG.md
git commit -m "$(cat <<'COMMIT_MSG'
Releases vX.Y.Z

- Bumps @version to X.Y.Z and the README install snippet to ~> X.Y
- Promotes ## [Unreleased] to an X.Y.Z header, dated today
COMMIT_MSG
)"
```

Title is exactly `Releases vX.Y.Z` - the convention every prior release
commit uses (`git log --all --oneline --grep '^Releases '`). No AI
attribution lines, same rule as every other commit in this repo. If the user
named a bead or epic to reference (e.g. a release-tracking epic), add a
trailing `Refs: <id>` line; otherwise omit it - release commits aren't
required to close a specific bead.

Verify immediately:

```bash
git log -1 --pretty=format:"%B"
```

Check the title, check there's no attribution, amend with
`git commit --amend` if either is wrong rather than leaving a bad commit.

### Step 4: Report

State plainly what happened and what didn't:

```
Committed: Releases vX.Y.Z (<sha>)
Files: mix.exs, README.md, CHANGELOG.md
Gate: full mix quality green

Not done (human-gated, per CLAUDE.md):
- git tag vX.Y.Z
- git push / gh pr create
- mix hex.publish
- bd close

Next steps are yours to take explicitly.
```

## Guidelines

- **This skill never pushes, tags, or publishes.** Those rows in CLAUDE.md's
  authority table have no trigger this skill can fire on its own - not
  "finishing a release commit," not anything else. `mix hex.publish`
  specifically has no trigger at all, ever, from any session.
- **The version is always explicit input, never inferred.** If a future
  caller wants "just bump to the next minor," that's still a human decision
  to state out loud, not a default this skill computes.
- **Content curation is out of scope.** `d9ff35c`'s reordering and framing of
  changelog entries was a human editorial pass. This skill only renames the
  heading and stamps the date.
```

#### 2. `CLAUDE.md` skills table

**File**: `CLAUDE.md`
**Changes**: Add a `/release` row to the skills table in "Worktrees, skills,
and area labels", after `/merge-request` (same "land the work" grouping).

```markdown
| `/release` | bump `@version`, promote the changelog, bump the README pin - human-gated tag/push/publish stay separate |
```

### Success Criteria

#### Automated Verification

- [ ] `git diff --stat` for this change touches only
  `.claude/skills/release/SKILL.md` and `CLAUDE.md` - no `lib/`, `test/`,
  `mix.exs`, or `mix.lock` files, so per `/commit`'s Step 0 carve-out there is
  no `mix quality` gate to run for *this* commit (the gate described inside
  the new skill is for releases it performs later, not for adding the skill
  itself).
- [ ] `.claude/skills/release/SKILL.md` exists with valid YAML frontmatter
      (`name`, `description`, `model`, `argument-hint`).

#### Manual Verification

- [ ] Read the finished skill against the Desired End State checklist above -
      every refusal condition and every "not done" item is present.
- [ ] Hand-trace the skill's Step 0-1 logic against `61be076` (parent of
      `d9ff35c`) with `$ARGUMENTS = 3.7.0`: the `mix.exs` and README diffs it
      would produce match `d9ff35c`'s exactly; the CHANGELOG heading line
      matches (`## [3.7.0] - 2026-08-05`) even though the curated content
      beneath it differs, as expected.
  - [ ] Confirm the skill's version-comparison step would have caught an
      accidental `3.6.0` or `3.7.0` re-entry (equal/lesser) as a STOP.
  - [ ] Confirm the skill's empty-`Unreleased` check would STOP on the
      current tree's actual `## [Unreleased]` state whenever it has no
      bullets (it currently has one - the Hex package fix - so this is a
      logic check, not a live run).

## Testing Strategy

### Unit Tests

None - this is a markdown skill definition, not Elixir code; there's nothing
under `lib/` or `test/` for the coverage gate to measure.

### Integration Tests

None applicable in the automated sense. The manual verification above (hand-
tracing against `d9ff35c`/`61be076`) is this change's integration test: it
confirms the skill's described steps reproduce a known-correct prior release's
mechanical diff.

### Manual Testing Steps

1. Read `.claude/skills/release/SKILL.md` end to end and confirm it STOPs
   before every human-gated action named in CLAUDE.md's authority table.
2. Walk Step 0's version-comparison logic by hand for a few cases: greater
   (proceeds), equal (STOPs), lesser (STOPs), malformed (STOPs at the Trigger
   check before Step 0 is reached).
3. Confirm the skill's commit message template, run by hand against
   `3.7.0`, produces a title byte-identical to `d9ff35c`'s: `Releases v3.7.0`.

## References

- Release commit studied: `d9ff35c` ("Releases v3.7.0"), `git show d9ff35c`
- Prior commit for hand-trace: `61be076`
- Release commit title history: `git log --all --oneline --grep '^Releases '`
- Beads issue: `px-7p9` (epic-less; created directly)
- Modeled on: `.claude/skills/commit/SKILL.md`, `.claude/skills/merge-request/SKILL.md`
- Authority table: `CLAUDE.md`, "Agent authority in this repo"
