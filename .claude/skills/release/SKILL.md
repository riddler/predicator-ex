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
