---
name: merge-request
description: Run the full gate, push the worktree branch, open a PR against main, and record it on the bead
model: sonnet
argument-hint: ["optional: beads issue ID; omit to detect from the commits' Refs: trailers"]
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

`$ARGUMENTS` = optional beads issue ID. Omitted, the beads come from the `Refs:`
trailers on the branch's own commits, falling back to the branch prefix
(step 2).

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

2. **Resolve the beads.** From `$ARGUMENTS` if given. Otherwise read the
   trailers the branch's own commits carry - the same anchored match
   `/cleanup-worktrees` closes on, so the PR body and the eventual closes agree:
   ```bash
   git log origin/main..HEAD --pretty=%B \
     | grep -E '^Refs:' \
     | grep -oE 'px-[a-z0-9]+(\.[0-9]+)?' | sort -u
   ```
   Fall back to the branch prefix only when that finds nothing (a branch whose
   commits predate the `Refs:` convention). The prefix is a creation-time label
   and names at most one bead, so a branch carrying several would otherwise
   reach the PR body naming only the first.

   Validate each with `bd show <id>`. STOP if none resolves. A PR that cannot be
   traced to a bead is work nobody can find later, and the `bd note` in step 8
   has nowhere to go.

3. **Fetch and rebase onto `origin/main`.** The gate in step 4 only means
   something if it attests to the tree that will actually merge, not to branch
   + stale main. Rebase has to happen here, before the gate - rebasing between
   the confirmation in step 6 and the push in step 7 would invalidate the very
   attestation the gate exists to produce.
   ```bash
   git fetch origin
   ```
   Check whether there is anything to replay before touching the build:
   ```bash
   git rev-list --count HEAD..origin/main
   ```
   Zero means `origin/main` has not moved since the branch was cut - nothing to
   rebase and no reason to invalidate warm build caches. Say so and go straight
   to step 4.

   Otherwise, rebase:
   ```bash
   git rebase origin/main
   ```
   **On conflict: abort and report, do not resolve unasked** - CLAUDE.md's
   authority table is explicit that a conflict during this rebase is still
   unauthorized. Capture the conflicting files before aborting, the same order
   `/refresh-worktree` step 3d uses, since the abort clears the conflict state
   a report assembled afterward would otherwise have nothing left to name:
   ```bash
   git diff --name-only --diff-filter=U   # capture, then
   git rebase --abort                     # abort
   ```
   Report the conflicting files and stop. Do not fall through to the gate or
   the push with the branch left un-rebased - an aborted rebase ends this run.

   If the rebase moved `mix.lock`, repair the build before step 4 runs, the
   same way `/refresh-worktree` step 3e does: `mix deps.get`, then clone the
   dialyzer PLT from the main checkout if it has already been rebuilt for the
   new dep set, or note that the next full gate run will rebuild it. Reuse that
   logic rather than reimplementing it here, and do not re-clone `deps/` or
   `_build/` wholesale - a live worktree has its own incremental state and a
   wholesale clone forces a full recompile. A lockfile that did not move is the
   common case and needs none of this.

   Record what moved, for step 6's confirmation: the pre-rebase tip, the
   `origin/main` commit rebased onto, and whether any commits were replayed.

   **On the no-op case:** even when there is nothing to replay, step 4's gate
   still runs. The fast path above skips the rebase and the build repair, not
   the gate - it is the expensive parts that are wasted on an unmoved main, not
   the cheap one. The gate attests to *this* tree, and the simplest way to know
   the tree has not drifted since `/commit` last ran it is to ask again rather
   than track how long ago it was green and whether anything else touched the
   tree since. That bookkeeping would cost more reasoning than the redundant
   gate run costs seconds. One code path - the gate always runs at step 4 -
   beats two.

4. **Run the full gate.**
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
   `lib/`, `test/`, `src/`, or `conformance/`, and neither `mix.exs` nor
   `mix.lock`, there is no gate to run. `conformance/` is in that list because a
   conformance-only diff touches no Elixir file, so the unamended carve-out
   would skip `test/predicator/conformance/corpus_freshness_test.exs` - this
   narrows an existing skip, it is not a new gate step. Skip it and say so in
   the PR body and the final report, so a skipped gate is never mistaken for a
   green one.

5. **Check for a changelog entry.** Only when the diff changes observable
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

6. **Confirm before pushing.** Show the user what is about to become public,
   including what step 3 found on `origin/main`:

   ```
   Ready to open a PR for px-xxx - "<issue title>"

   Branch:    px-xxx-slug -> main
   Rebased:   origin/main was already current, no commits replayed
              (or: onto <sha>, N commits replayed)
   Commits:   3
   Gate:      full mix quality green   (or: docs only, no gate applicable)
   Changelog: CHANGELOG.md [Unreleased] updated   (or: not needed - internal tooling)

   <proposed PR title>

   Push and open the PR?
   ```

   Wait for an answer. This is the one confirmation this skill does not skip,
   and there is no `--auto` for it.

7. **Push, then open the PR.**
   ```bash
   git push -u origin <branch>
   ```
   If the branch had already been pushed before step 3 ran - the common case,
   since a worktree usually gets at least one push before its PR is ready - the
   rebase in step 3 rewrote commits the remote already has, and the remote
   counterpart has diverged. Same if `/refresh-worktree` rebased it
   independently between pushes. Either way the push needs
   `--force-with-lease` - never a bare `--force`, which discards commits pushed
   from elsewhere without telling you:
   ```bash
   git push --force-with-lease
   ```
   A branch that was rebased in step 3 but never pushed before (the first push
   for this branch) needs neither flag - there is nothing on the remote yet to
   diverge from.

   Then:
   ```bash
   gh pr create --base main --title "<title>" --body "<body>"
   ```

   PR title matches the commit style: present tense, s-form, under 50
   characters. The body carries what a reviewer needs and the commits do not:

   - **Why** - the problem, in the bead's terms
   - **What** - the shape of the change, not a file list; the diff has that
   - **Notes** - anything surprising, deliberately deferred, or worth a second
     opinion, plus which gate ran. If the change moves the ISA, say so
     explicitly and name the version it lands at, plus its `docs/isa.md` entry
     and any migration note (ADR-0003). A sibling that has not adopted that
     version is not a blocker on the PR.
   - **Corpus** - if `conformance/corpus/*.json` or `conformance/manifest.json`
     moved, say why in the body, naming the cause and the case ids that moved.
     The corpus is the exported specification siblings verify against
     (ADR-0003), so a corpus diff a reviewer cannot account for from the PR body
     is the single most reviewable form of an unintended semantic change - and
     the reviewer is the only one positioned to catch it, because the suite
     confirms the corpus is *fresh*, never that the change was *wanted*.
   - The bead references: `Closes px-xxx` for **every** bead the branch's
     trailers name, one per line (and the epic, if they share one)

   No AI attribution in the title or the body, same rule as commit messages
   (CLAUDE.md, and the override in `/commit`).

8. **Sync beads, then record the PR.**
   ```bash
   bd dolt push
   bd note <id> "PR: <url>"
   ```
   Run the `bd note` once per bead step 2 resolved - a bead whose PR URL was
   never recorded is one nobody can follow from the issue to the review.

   `bd dolt push` is not optional and not a nicety. Issue state travels over
   `refs/dolt/data` on the same remote as the code; a PR whose bead was never
   pushed is invisible to every other machine, so a reviewer pulling the branch
   sees work with no issue behind it. The git side has just reached `origin`,
   which is exactly the trigger CLAUDE.md's authority table names for this.

   Leave the bead `in_progress`. Do not close it.

9. **Report.**
   ```
   PR opened: <url>
   Branch:    px-xxx-slug -> main (3 commits)
   Gate:      full mix quality green
   Bead:      px-xxx in_progress, PR URL recorded, dolt pushed
   Next:      merge is a human decision; the bead closes on merge, not here
   ```

## Guidelines

- **The generated corpus is never hand-edited.** `conformance/corpus/*.json`
  and `conformance/manifest.json` are written only by `mix corpus.generate`;
  the authored source is `conformance/cases/*.json`. See `/commit`'s
  "Important Context" for the full rule.
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
