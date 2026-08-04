---
name: merge-request
description: Run the full gate, push the worktree branch, open a PR against main, and record it on the bead
model: sonnet
argument-hint: ["optional: beads issue ID; omit to detect from the branch name"]
---

# Merge Request

Take a finished worktree branch from local commits to an open pull request.

This is where the confirmation removed from `/commit --auto` went. A commit on a
per-issue branch is private and undone with `git reset --soft HEAD~1`; a push
and a PR are visible to other people and other machines, enter review queues,
and send notifications. CLAUDE.md's authority table puts the human gate here for
exactly that reason - push and `gh pr create` fire only when the user asks in
their own words - so this skill confirms before pushing even when everything
else it checks is green.

The bead is **not** closed here. It stays `in_progress` until the branch merges
into `origin/main`. A PR is a request, not an outcome.

## Input

`$ARGUMENTS` = optional beads issue ID. Omitted, it comes from the branch name,
which `/new-worktree` shapes as `<beads-id>-<slug>`.

## Steps

1. **Establish where you are.**
   ```bash
   git branch --show-current
   git status --porcelain
   ```
   STOP if the branch is `main` - this skill operates on per-issue worktree
   branches only, and this repo takes no direct commits to `main`. STOP if the
   tree is dirty: an uncommitted change is either part of this work and belongs
   in a commit, or is unrelated and belongs somewhere else. Do not stage it here.

   Confirm there is something to push:
   ```bash
   git log origin/main..HEAD --oneline
   ```
   Empty means nothing to open a PR for. Say so and stop.

2. **Resolve the bead.** From `$ARGUMENTS` or the branch prefix, then validate:
   ```bash
   bd show <id>
   ```
   STOP if it does not resolve. A PR that cannot be traced to a bead is work
   nobody can find later, and the `bd note` in step 7 has nowhere to go.

3. **Run the full gate.**
   ```bash
   mix quality
   ```
   Never truncate the output. **Refuse on red** - report the failing stages with
   their `file:line` findings and stop. Do not push a branch whose gate is red
   in the hope that CI disagrees.

   A narrowed run does not count: `--quick`, `--profile loop`, `--skip-*`, and
   `--test-scope changed` all skip checks a reviewer will assume ran. Only a
   full `mix quality` clears this step, and it is never made green by weakening
   the gate - no lowered coverage threshold, no disabled check, no `@tag :skip`.

   **Carve-out**, matching `/commit` Step 0: if the diff touches nothing under
   `lib/`, `test/`, or `src/`, and neither `mix.exs` nor `mix.lock`, there is no
   gate to run. Skip it and say so in the PR body and the final report, so a
   skipped gate is never mistaken for a green one.

4. **Check for a changelog entry.** Only when the diff changes observable
   behavior - the public API under `lib/`, or what a predicate source string
   does:
   ```bash
   git diff origin/main...HEAD --name-only
   git diff origin/main...HEAD -- CHANGELOG.md
   ```
   This repo edits `CHANGELOG.md` directly: user-facing changes get a bullet
   under `## [Unreleased]` (CLAUDE.md, conventions). There is no `changelog.d/`
   fragment directory here, so do not look for one.

   Most changes need no entry - tests, docs, ADRs, plans, internal refactors,
   and agent tooling are all exempt. The test to apply: could someone who only
   calls `Predicator.evaluate/3`, or only writes predicates, tell the
   difference?

   If it does need one and `CHANGELOG.md` is untouched on this branch, **ask the
   user** what it should say. Do not invent it: a changelog entry is a promise
   to users about observable behavior, and guessing at one produces a release
   note describing something the code may not do.

   Never promote `## [Unreleased]` to a version header here. That is release
   work and needs the user to ask for a release and name the version.

5. **Confirm before pushing.** Show the user what is about to become public:

   ```
   Ready to open a PR for px-xxx - "<issue title>"

   Branch:    px-xxx-slug -> main
   Commits:   3
   Gate:      full mix quality green   (or: docs only, no gate applicable)
   Changelog: CHANGELOG.md [Unreleased] updated   (or: not needed - internal tooling)

   <proposed PR title>

   Push and open the PR?
   ```

   Wait for an answer. This is the one confirmation this skill does not skip,
   and there is no `--auto` for it.

6. **Push, then open the PR.**
   ```bash
   git push -u origin <branch>
   ```
   If the branch was rebased after a previous push (`/refresh-worktree` rewrites
   commits), the remote counterpart has diverged and the push needs
   `--force-with-lease` - never a bare `--force`, which discards commits pushed
   from elsewhere without telling you:
   ```bash
   git push --force-with-lease
   ```

   Then:
   ```bash
   gh pr create --base main --title "<title>" --body "<body>"
   ```

   PR title matches the commit style: present tense, s-form, under 50
   characters. The body carries what a reviewer needs and the commits do not:

   - **Why** - the problem, in the bead's terms
   - **What** - the shape of the change, not a file list; the diff has that
   - **Notes** - anything surprising, deliberately deferred, or worth a second
     opinion, plus which gate ran. If the change touches the instruction set,
     say so explicitly: it is the cross-language interchange format shared with
     the Ruby and JavaScript implementations (ADR-0001), so it is not a local
     decision.
   - The bead reference: `Closes px-xxx` (and the epic, if it has one)

   No AI attribution in the title or the body, same rule as commit messages
   (CLAUDE.md, and the override in `/commit`).

7. **Sync beads, then record the PR.**
   ```bash
   bd dolt push
   bd note <id> "PR: <url>"
   ```
   `bd dolt push` is not optional and not a nicety. Issue state travels over
   `refs/dolt/data` on the same remote as the code; a PR whose bead was never
   pushed is invisible to every other machine, so a reviewer pulling the branch
   sees work with no issue behind it. The git side has just reached `origin`,
   which is exactly the trigger CLAUDE.md's authority table names for this.

   Leave the bead `in_progress`. Do not close it.

8. **Report.**
   ```
   PR opened: <url>
   Branch:    px-xxx-slug -> main (3 commits)
   Gate:      full mix quality green
   Bead:      px-xxx in_progress, PR URL recorded, dolt pushed
   Next:      merge is a human decision; the bead closes on merge, not here
   ```

## Guidelines

- **The repo allows rebase merging only.** Do not offer or perform a squash
  merge, and do not restructure the branch's commits on the assumption they will
  be squashed. Rebase replays each commit onto `main` with its message intact,
  which is why `/commit --auto` producing several commits on a branch is fine
  and needs no cleanup pass. It also means the branch tip never becomes an
  ancestor of `main`, so merge detection anywhere downstream must use `gh` PR
  state rather than git ancestry.
- **Never close the bead here.** `bd close` fires on merge into `origin/main`,
  verified against the remote. Closing at PR-open time asserts to every other
  machine that the work landed when it has not.
- **Confirmation is not a formality.** If the user declines, the branch stays
  local and nothing is lost. That asymmetry is the whole argument for putting
  the gate at this step rather than at commit.
- **One bead per branch is the default, not a law.** Several small beads that
  touch the same files belong on one branch as separate commits; splitting them
  across parallel worktrees manufactures exactly the rebase conflicts the area
  labels exist to avoid. Group them when they are the same work, split them
  when they are not.

  This is safe because `/cleanup-worktrees` closes beads from the `Refs:`
  trailers in the merged PR's commits, not from the branch name, so every bead a
  branch carries gets closed. Keep one bead per **commit** so those trailers stay
  unambiguous, and name every bead the PR closes in its body.
- After the merge, the survivors need `/refresh-worktree`, and this branch's
  worktree and beads are handled by `/cleanup-worktrees`.
