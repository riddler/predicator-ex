---
name: cleanup-worktrees
description: Land merged work - close the beads whose PRs have merged, remove their worktrees and local branches, using GitHub PR state rather than git ancestry
model: sonnet
argument-hint: ["optional: one worktree/branch name; omit to sweep all"]
---

# Cleanup Worktrees

Remove the worktrees and local branches left behind by merged work. Worktrees
are removed at merge; nothing automated that, so they accumulate until someone
notices.

## Why detection must not use git ancestry

**This repo is configured to allow rebase merging only** (CLAUDE.md, merge
policy). Rebase replays a branch's commits onto `main` as new SHAs, so **the
branch tip never becomes an ancestor of `main`**. Two consequences, and both
are traps:

1. `git branch --merged origin/main` never lists a merged feature branch. A
   cleanup built on it silently no-ops forever while looking like it works -
   the worst kind of broken, because nothing ever reports a problem.

2. `git branch -d` refuses for the same reason, so deletion needs `-D`. That
   makes the PR-state check **load-bearing for safety, not just detection**:
   `-D` on an unmerged branch discards commits with no recovery path short of
   the reflog. Never force-delete a branch without a confirmed `MERGED` state
   from `gh`.

So: ask GitHub, never git.

```bash
gh pr list --state merged --head <branch> --json number,mergedAt
gh pr view <branch> --json state,mergedAt
```

## Input

`$ARGUMENTS` = optional worktree or branch name to clean just that one. Omitted,
sweep every worktree under `../predicator-ex-worktrees/`.

## Steps

1. **Enumerate worktrees.**
   ```bash
   git worktree list --porcelain
   ```
   Parse into `(path, branch)` pairs and **drop the main checkout**
   (`/Users/johnnyt/repos/github/predicator-ex`). Removing it would take the
   repository with it.

   No worktrees is a normal outcome. Say so and stop.

2. **Per worktree, ask GitHub whether its branch merged.**
   ```bash
   gh pr list --state merged --head <branch> --json number,mergedAt,headRefOid --jq '.[0]'
   ```
   - **A merged PR** -> eligible for cleanup. Carry the PR number **and
     `headRefOid`** forward: that SHA is the branch tip GitHub actually merged,
     and step 3 needs it.
   - **No PR, or a PR that is open or closed-unmerged** -> leave everything
     alone and record why. An open PR means work in review; a closed-unmerged
     one means work someone abandoned but did not delete, which is theirs to
     decide about, not this skill's.
   - **`gh` fails or is unauthenticated** -> STOP the whole sweep. Without PR
     state there is no safe signal, and falling back to ancestry would delete
     nothing (case 1) or the wrong thing. Report the error.

3. **Refuse if the worktree is dirty.**
   ```bash
   git -C <path> status --porcelain
   ```
   Any output means uncommitted work. Report it as `dirty, skipped` and move on.
   **Never pass `--force` to `git worktree remove`** - it discards those changes.
   `git worktree remove` already refuses on a dirty tree; that refusal is a
   feature, so do not route around it.

   Also check for commits made after the push, by comparing the local tip to
   the SHA GitHub merged (`headRefOid` from step 2):
   ```bash
   git -C <path> rev-parse HEAD
   ```
   Equal means nothing was committed after the push and the worktree is safe to
   remove. Different means someone committed on top after the merge; those
   commits are on no remote and nowhere in `main`, so skip the worktree and
   report the SHAs.

   **Do not use `git log @{upstream}..HEAD` for this.** The upstream ref is
   gone precisely when this skill runs: `delete_branch_on_merge` is on, so
   GitHub deletes the remote branch at merge, `@{upstream}` does not resolve,
   and the command exits with `fatal: ambiguous argument` rather than empty
   output. Read literally, that fatal looks like unpushed commits and skips
   **every** merged worktree - the same silent no-op this skill exists to
   prevent, arriving by a different route.

   `git log origin/main..HEAD` is not a substitute either: rebase merging
   replays commits under new SHAs, so it reports commits for every merged
   branch. `headRefOid` is the only local-vs-merged comparison that holds here.

3.5. **Quiesce the session running in the worktree.** `/new-worktree` opens a
   tmux window per worktree with a Claude session seeded on the bead. Removing
   the directory out from under a live session yanks the tree away mid-turn and
   leaves an orphaned window sitting in a path that no longer exists.

   **Do this after the dirty and SHA checks, not before.** A worktree that is
   about to be skipped should keep its session; shutting one down and then
   deciding not to clean up is pure loss. The residual race - the session
   dirties the tree between step 3 and the removal - costs nothing, because
   `git worktree remove` refuses on a dirty tree anyway. That refusal is the
   backstop, so it stays a reported error rather than lost work.

   **Find the window from the worktree, and require both signals to agree.**
   ```bash
   tmux list-panes -a -F '#{window_id} #{window_name} #{pane_current_path}' \
     | awk -v n='<name>' -v p='<path>' '$2 == n && $3 == p { print $1 }'
   ```
   `/new-worktree` sets the window name to the worktree directory name and
   opens it with `-c <worktree path>`, so a real match agrees on both. Matching
   on name alone would close a window a human renamed onto something else;
   matching on path alone would close a stray shell someone happened to `cd`
   there. Requiring both is what keeps an unrelated window safe.

   - **No match** -> no window for this worktree. Nothing to quiesce, nothing
     to close, not an error. Continue to step 4.
   - **More than one match** -> ambiguous. Skip the quiesce and the window
     close, report it, and do not remove the worktree either - two windows
     claiming one worktree is a state a human should look at.

   Everything below targets `$win`, the captured window id. **Check it is
   non-empty before every command that uses it.** An empty `-t ""` does not
   error - tmux resolves it to the *current* window, so a stray `kill-window`
   lands on whatever the user is sitting in.

   **Is a session even running?**
   ```bash
   tmux list-panes -t "$win" -F '#{pane_current_command}'
   ```
   A bare shell (`fish`, `zsh`, `bash`, `sh`) means no session to quiesce -
   skip to the window close in step 4, no error. **Do not test this by
   grepping for `claude`.** The CLI is installed as a version-named binary
   (`~/.local/share/claude/versions/<version>`), so `pane_current_command`
   reads the version number, not `claude`, and a `claude` grep reports "no
   session" for every live one - the silent no-op this skill exists to avoid,
   arriving by a third route.

   **Idle check.** Capture the pane and require *both* conditions:
   ```bash
   tmux capture-pane -p -t "$win"
   ```
   1. **No turn in flight.** A running turn renders a spinner line carrying an
      elapsed timer: `. Cooking... (45s . 2.5k tokens)`. Match the timer
      (`\([0-9]+s`) or `esc to interrupt` - **never the verb**, which is
      randomized per frame (`Cooking...`, `Forging...`, and many others).
   2. **The input box is empty - of real text.**
      ```bash
      tmux capture-pane -e -p -t "$win" | grep '❯' | tail -1
      ```
      Use **`-e`**, not plain `-p`. Claude Code renders a greyed-out suggested
      next prompt in an otherwise-empty input box, and in plain `-p` output
      that placeholder text lands right after the marker indistinguishable
      from something the user actually typed - a session with nothing typed
      reads as "busy" and the whole worktree gets skipped for no reason. `-e`
      keeps the ANSI styling, and the placeholder is always wrapped in a
      dim/faint SGR sequence (`ESC [ 2 m ... ESC [ 0 m`) that real typed input
      never carries. Captured raw, an idle session showing a suggestion looks
      like:
      ```
      ❯ [2mbd link px-meo --depends-on px-qw9[0m
      ```
      (`[2m` / `[0m` above stand for the literal `ESC [ 2 m` / `ESC [ 0 m`
      bytes.) An empty box with no suggestion at all captures as plain
      `❯ [39m` - nothing but a color-reset code after the marker.

      Take the **last** `❯` line - the transcript echoes every user message
      with the same marker, so an earlier one says nothing about the current
      state. Classify what follows the last `❯ `:
      - **Nothing, or only SGR codes** (`ESC [ 3 9 m`, `ESC [ 0 m`, ...) with
        no visible characters -> empty, idle.
      - **Visible text wholly wrapped in dim SGR**, nothing visible outside
        that span -> Claude's suggested-prompt placeholder, idle.
      - **Anything else with visible text** -> stop. Either:
        - a half-typed draft (`❯ half a draft`) - a human's unsent text, and
          losing it is the same class of loss as a dirty tree, or
        - a dialog awaiting an answer, which renders as ` ❯ 1. Yes` (a tool
          permission prompt, a trust-this-folder prompt) - real, non-dim text,
          same as a draft.
        Genuinely typed text is not styled dim - only the suggestion
        placeholder is - so this distinction does not depend on the glyph
        stream alone the way a plain-`-p` check does.

      The dialog case is why this check is not optional at all, dim-stripping
      aside. **No spinner is drawn while a dialog is up**, so condition 1 alone
      reads a session blocked mid-tool-call as idle and shuts it down.

   Sample twice, ~3s apart, and require idle both times. One capture can land
   in the gap between a turn ending and the next tool call starting.

   **Busy -> skip the whole worktree.** Report it as `session busy, skipped`
   and leave the worktree, the branch and the window alone. This is the same
   stance as the dirty-tree skip: report, do not force.

   **Idle -> shut it down cleanly.**
   ```bash
   tmux send-keys -t "$win" C-u
   tmux send-keys -t "$win" '/exit' Enter
   ```
   `C-u` clears the input line first so `/exit` cannot be appended to leftover
   text. Then poll until the pane is back at a shell, up to 15s:
   ```bash
   tmux list-panes -t "$win" -F '#{pane_current_command}'
   ```
   Observed round trip is ~2s. `/exit` is a clean quit: the session flushes its
   state and any pending bead writes on the way out.

   **If it has not exited after 15s, skip the worktree and report it.** Never
   `kill-pane`, never `kill-window` on a live session, never SIGKILL. A session
   that will not take `/exit` is one that is doing something, and the whole
   point of this step is to not be the thing that interrupts it.

4. **Remove, in this order.** Order matters: the branch cannot be deleted while
   a worktree has it checked out, and the window cannot be closed until the
   session inside it is gone.
   ```bash
   git worktree remove <path>
   git worktree prune
   git branch -D <branch>
   ```
   `-D` is correct here and only here - step 2 confirmed the merge, so the
   commits are on `main` under different SHAs.

   Then close the window step 3.5 identified, if there was one:
   ```bash
   tmux list-panes -t "$win" -F '#{pane_current_command}'   # all bare shells?
   tmux kill-window -t "$win"
   ```
   Two preconditions, both cheap and both load-bearing: `$win` is non-empty
   (see the empty-target trap above), and **every** pane in the window is a
   bare shell. A window the user split to run something else still has that
   something else in it, and `kill-window` takes the whole window, not the pane
   this skill cares about. Any pane running a non-shell command -> leave the
   window open and report `window kept, other panes busy`. The worktree is
   still removed; a leftover window is untidy, not destructive.

4.5. **Close the beads that just landed.** A closed bead is a claim about
   `main`, not about a green branch. Closing at commit or PR-open time makes
   `bd ready` offer downstream work against code that is not on `main` yet, and
   `refs/dolt/data` propagates that wrong state to other machines within
   minutes. The merge is the moment that claim becomes true, so it is the
   moment to close - which is exactly the trigger CLAUDE.md's authority table
   names for `bd close`.

   **Which beads: read the `Refs:` trailers, not the branch name.** Every commit
   carries `Refs: px-xxx` on its own line at the end (`/commit` Step 2), so the
   merged PR's commits say exactly which beads landed:
   ```bash
   gh pr view <number> --json commits --jq '.commits[].messageBody' \
     | grep -E '^Refs:' \
     | grep -oE 'px-[a-z0-9]+(\.[0-9]+)?' | sort -u
   ```
   The branch name carries only one ID, so keying on it silently drops every
   other bead a multi-commit branch closed. Trailers scale to a branch carrying
   several beads; branch names do not.

   **The `^Refs:` anchor is required, not tidiness.** Commit bodies routinely
   name other beads in prose - citing a design note, crediting a discovery,
   explaining a deviation - and an unanchored match closes every one of them.

   **A merged PR whose commits carry no `Refs:` line closes nothing - report
   that, do not pass over it.** It means either work that skipped `/commit`, or
   trailers forgotten on a grouped branch. Both leave beads open that a human
   expected closed, and silence here is indistinguishable from success.

   For each ID found:
   ```bash
   bd show <id>          # confirm it exists and is not already closed
   bd close <id> --reason="Merged to origin/main via PR #<number>"
   ```
   Already-closed is a no-op, not an error - say so and move on. An ID that
   does not resolve is worth reporting rather than swallowing: it usually means
   a typo'd trailer, and the bead it meant to close is still open.

   **Close before removing the worktree** (step 4 already ran) but **do not let
   a `bd` failure block cleanup**, and never close a bead for a branch whose
   merge step 2 did not confirm.

5. **Publish the closes.**
   ```bash
   bd dolt push
   ```
   A close nobody else can see does not do the job: other machines keep offering
   the same work until the close reaches `refs/dolt/data`. The git side is
   already on `origin` by definition here - the PR merged - so this is exactly
   the trigger CLAUDE.md's authority table names.

   Skip it when nothing was closed. Non-fatal if offline; report that the closes
   are local and will publish on the next push.

6. **Prune remote-tracking refs once**, after the loop:
   ```bash
   git fetch --prune
   ```
   Remote branches are usually already gone: `delete_branch_on_merge` is on, so
   GitHub deletes them at merge. Cleanup here is purely local, which is the
   whole reason it needs automating - nothing else was ever going to do it.

7. **Report** one line per worktree, naming the beads closed and what happened
   to the session and window:

   | Worktree | Result |
   |---|---|
   | `px-abc-object-notation` | merged in PR #48, closed px-abc, session exited, removed, branch deleted, window closed |
   | `px-def-context-struct` | merged in PR #50, closed px-def + px-ghi, no window, removed |
   | `px-jkl-duration-parsing` | open PR #51, kept |
   | `px-mno-string-visitor` | no PR, kept |
   | `px-pqr-area-labels` | dirty, skipped |
   | `px-stu-json-functions` | merged in PR #53, **session busy, skipped** |
   | `px-vwx-error-shapes` | merged in PR #52, **no `Refs:` trailer, no bead closed** |

   **A busy session is a skip worth naming, not a footnote.** It is the one
   outcome where re-running the sweep later finishes the job on its own, and
   the user needs to know there is a job left to finish.

   **Nothing to clean is a success, and must say so explicitly** - "no merged
   worktrees found, 3 live worktrees kept, no beads closed" rather than silence.
   A silent sweep is indistinguishable from the ancestry bug this skill exists
   to avoid.

## Guidelines

- **PR state or nothing.** If `gh` cannot answer, stop. Do not substitute
  `git branch --merged`, `git merge-base --is-ancestor`, or a commit-message
  comparison; under rebase merging none of them are sound.
- **Never `--force` a worktree removal, never `-D` an unmerged branch.** Both
  destroy work that exists nowhere else. Every skip is reported so a human can
  deal with it.
- **Never kill a Claude session, only ask it to exit.** `/exit` and a timeout,
  never a signal. A session that will not exit is busy by definition, and the
  same "report, do not force" rule that governs a dirty tree governs it.
- **tmux is convenience, never a gate.** No tmux, no server, no window, a
  window with no session in it - all of them are normal and none of them are
  errors. `/new-worktree` treats the window as optional on the way up; this
  skill treats it as optional on the way down. The worktree and the bead are
  the work; the window is a place to sit.
- Pairs with `/refresh-worktree`: same moment, opposite direction. That one
  rebases the survivors onto the new `origin/main`; this one removes the
  worktree of the branch that just landed. Run this first - refreshing a
  worktree that is about to be deleted is wasted work.
- **Never close a bead the merge check did not confirm.** Bead closing and
  worktree removal share one detection step on purpose: they answer the same
  question, "did this branch land", and answering it two ways is how they drift.
- **A branch may carry several beads.** Trailer-driven closing is what makes
  that safe, so grouping related beads onto one branch is a real option rather
  than something the tooling punishes. See the note in `/merge-request`.
- Safe to re-run: worktrees with no merged PR are kept, already-closed beads
  are a no-op, and a clean sweep changes nothing.
