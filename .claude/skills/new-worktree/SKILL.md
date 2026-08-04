---
name: new-worktree
description: Create a per-issue worktree under ../predicator-ex-worktrees/ with a new branch off main, warm it (deps, _build, dialyzer PLT) so the first quality run is fast, and open a tmux window there with a Claude session seeded on the bead
model: sonnet
argument-hint: ["branch/worktree name, e.g. px-abc-object-notation"]
---

# New Worktree

Stand up a fresh worktree for one beads issue: one issue, one branch, one
worktree under `../predicator-ex-worktrees/`, named `<beads-id>-<slug>`. Then
warm the worktree's build caches by cloning `deps/`, `_build/` and `priv/plts/`
from this checkout - that carries the compiled beams and the dialyxir PLT, so
the first `mix quality` there recompiles only the delta instead of rebuilding
the world.

The beads issue should already be claimed (`bd update <id> --claim`) before the
worktree exists - the claim is the lock, the worktree is just the workspace.
`/next-issue` handles claim + naming and then invokes this skill; `/next-issues`
does the same for a batch of beads, once per bead.

## Input

`$ARGUMENTS` = the branch name, optionally followed by `--` and the command to
seed the new session with.

**Branch name** (or ask) is also the worktree folder name: `<beads-id>-<slug>`,
e.g. `px-abc-object-notation`. Keep the slug to 2-4 distinctive kebab-case
words from the issue title, not a full transcription. If given only a bead id,
ask for the slug - it matters and should not be guessed.

**Seed command** (optional) is what the tmux session in step 5 runs, e.g.:

```
/new-worktree px-abc-object-notation -- /create-plan px-abc
```

This is how `/next-issue` hands its triage decision (plan / implement) to the
session that will act on it. Without it the decision is lost and the new
session re-derives it from scratch, usually differently. Omitted - someone
invoking this skill directly - falls back to a generic seed that tells the
session to read the bead and decide for itself.

## Steps

1. **Guard.** From the main checkout (`/Users/johnnyt/repos/github/predicator-ex`):
   - `git branch --list <name>` - if the branch already exists, STOP and report.
     Offer a different name or let the user delete the old one. Never force.
   - `ls ../predicator-ex-worktrees/<name>` - same rule if the folder exists.
   - `git fetch origin` so the branch is cut from the latest `origin/main`
     (github.com/riddler/predicator-ex), not a stale local copy. If the fetch
     fails (offline) or `origin/main` does not exist, fall back to local `main`
     and say so in the report.

2. **Create the worktree + branch.**
   ```bash
   mkdir -p ../predicator-ex-worktrees
   git worktree add ../predicator-ex-worktrees/<name> -b <name> --no-track origin/main
   ```
   (`--no-track` keeps the new branch push-safe; drop to `main` only in the
   offline/fallback case above.)

3. **Warm the caches.** Clone `deps/`, `_build/` and `priv/plts/` from this
   checkout into the worktree. On APFS `cp -Rc` uses copy-on-write clonefiles,
   so this is nearly instant and costs almost no disk:
   ```bash
   cp -Rfc deps _build ../predicator-ex-worktrees/<name>/ 2>/dev/null \
     || cp -Rf deps _build ../predicator-ex-worktrees/<name>/
   mkdir -p ../predicator-ex-worktrees/<name>/priv/plts
   cp -fc priv/plts/dialyzer.plt* ../predicator-ex-worktrees/<name>/priv/plts/ 2>/dev/null \
     || cp -f priv/plts/dialyzer.plt* ../predicator-ex-worktrees/<name>/priv/plts/ 2>/dev/null || true
   ```
   This carries:
   - compiled dep and app beams (incremental recompile only for changed files)
   - the dialyzer PLT, which `mix.exs` pins to `priv/plts/dialyzer.plt`.
     Dialyxir keys the PLT on OTP/Elixir versions and the dep set via the
     adjacent `.hash`, so a cloned PLT is picked up as-is and full
     `mix quality` skips the multi-minute PLT build.

   If `priv/plts/` here is empty (fresh clone), note it and suggest running
   `mix dialyzer --plt` once - in either checkout, then re-clone or let the
   worktree build it.

   Note the `-f`: `cp` is often aliased to `-i`, which hangs an agent forever on
   a prompt it cannot see (CLAUDE.md, non-interactive shell commands).

4. **Verify the worktree is green.** In the worktree:
   ```bash
   cd ../predicator-ex-worktrees/<name>
   mix deps.get        # no-op unless mix.lock changed since the clone
   mix quality --profile loop
   ```
   A warm worktree should pass this in seconds. Never truncate the output.

5. **Open a tmux window for the worktree.** Reporting a path and leaving the
   user to `cd` there by hand is the step that makes fan-out feel expensive,
   and the step most likely to be done wrong: a session started in the main
   checkout instead of the worktree silently edits the wrong tree.

   **This step is optional and never fatal.** If `tmux` is not installed, or
   `$TMUX` is unset and no server is running, skip it with a note and go to the
   report. The worktree is the deliverable; the window is convenience. Never
   fail worktree creation because the window could not be made.

   Windows live in a single per-project session (`predicator-ex`) - one session
   per project, windows within it. Do not create a session per worktree.

   ```bash
   # ALWAYS quote a '=' target - fish and zsh expand a leading = as a command
   # path (equals-expansion), so a bare -t =predicator-ex: dies with
   # "predicator-ex: not found" before tmux ever sees it. The user's shell is
   # fish, so this is not hypothetical.
   tmux has-session -t '=predicator-ex' 2>/dev/null \
     || tmux new-session -d -s predicator-ex -c /Users/johnnyt/repos/github/predicator-ex
   ```

   **Guard on the window name** before creating anything, the same way steps 1
   and 2 refuse an existing branch or worktree directory. Two windows with the
   same name in one session is exactly the state where the wrong one gets typed
   into:
   ```bash
   tmux list-windows -t '=predicator-ex' -F '#{window_name}' | grep -Fxq '<name>'
   ```
   A hit means the window already exists - report it and skip the rest of this
   step. Do not create a second one.

   ```bash
   FINISH=" When the work is complete, finish with /commit --auto - it writes the Refs trailer and refuses if the tree carries changes unrelated to <id>. Do not run git commit directly."

   win=$(tmux new-window -d -P -F '#{window_id}' \
     -t '=predicator-ex:' \
     -n '<name>' \
     -c "/Users/johnnyt/repos/github/predicator-ex-worktrees/<name>")
   [ -n "$win" ] || { echo 'tmux window not created, skipping'; exit 0; }
   tmux send-keys -t "$win" \
     "claude --permission-mode auto '<seed>.$FINISH'" Enter
   ```

   `<seed>` is the seed command from the input when one was given - pass it
   through verbatim, including the leading slash:

   ```
   claude --permission-mode auto '/create-plan px-abc.$FINISH'
   ```

   With no seed command, fall back to:

   ```
   claude --permission-mode auto 'Work bead <id> in this worktree. Start with bd show <id>.$FINISH'
   ```

   The finishing clause is appended unconditionally, to every bucket's seed and
   to the fallback, because this step is the one place all buckets
   (`/next-issue`, `/next-issues`, and a direct `/new-worktree` invocation)
   converge - editing it here reaches every seeded session without touching
   the bucket-selection skills themselves. It specifies `/commit --auto`
   rather than bare `/commit` because the tmux session runs unattended under
   `--permission-mode auto`: `/commit`'s interactive approval step would stall
   with nobody watching the window to answer it. This does not grant commit
   authority beyond what CLAUDE.md's authority table already grants (issue
   complete and full `mix quality` green) - it only routes that authority
   through the skill that performs the Refs-trailer and unrelated-changes
   checks, instead of a bare `git commit` that skips them.

   **Check `$win` is non-empty before any command that targets it, and never
   chain a follow-up with `;`.** An empty `-t ""` does not error - tmux resolves
   it to the *current* window, so `kill-window` or `send-keys` lands on whatever
   the user is sitting in. A `;` after a failed `new-window` is enough to do it.

   `<id>` is the bead id at the front of the branch name (`px-abc` from
   `px-abc-object-notation`).

   Two details are load-bearing:

   - **Capture the window id (`-P -F '#{window_id}'`, giving `@42`) and target
     that for every follow-up command.** It is stable under
     `renumber-windows on` (which renumbers every window whenever one is
     closed) and unambiguous against a session or window whose name shares a
     prefix.
   - **`-d` on `new-window`** so creating three worktrees in a row does not yank
     focus three times. The user jumps to the one they want when they are ready.

   The fallback prompt points at `bd show` rather than restating the bead: the
   beads DB is shared across worktrees, so the new session reads it directly,
   and a restated description goes stale. The same reasoning is why a seed
   command passes only the bead id - `/create-plan px-abc`, not a paraphrase
   of what to plan.

   `--permission-mode auto` starts the seeded session in auto mode, so it makes
   routine calls without stopping to confirm each one - the point of fanning
   worktrees out is not to then babysit four sessions. It is `auto`, not
   `bypassPermissions`: the permission system still applies, and this repo's
   authority table (CLAUDE.md) still gates push, PR, and `bd close` on an
   explicit human ask.

6. **Report.** State the worktree path, the branch and what it was cut from,
   that caches were cloned (and whether the PLT came along), the quality
   result, and **the tmux window** (its name and id, or why it was skipped) so
   the user can jump to it with the prefix key. Remind that subsequent work on
   this issue happens **inside the worktree**, and the worktree is removed at
   merge (`git worktree remove ../predicator-ex-worktrees/<name>`).

## Notes

- Worktree-local and push-safe: no upstream is set, nothing is pushed.
- `deps/`, `_build/` and `priv/plts/` are gitignored; the clones never show up
  in `git status`.
- If OTP/Elixir versions differ from when the PLT was built, dialyxir rebuilds
  it automatically - the clone is a best-effort warm, never a correctness risk.
  `mise.toml` pins both, so this should be rare.
- The beads DB is shared across worktrees (Dolt-backed), so `bd` commands work
  identically from the worktree.
- `/cleanup-worktrees` takes the window down at merge: it matches the window by
  **name and path together**, asks the session inside to `/exit`, and only then
  removes the directory and closes the window. Both halves of that match come
  from this step, so renaming the window or moving the worktree afterwards
  means cleanup will not find it and will leave it open rather than guess.
- A **busy** session blocks its own worktree's cleanup and is reported, so a
  sweep run while an agent is mid-turn is safe and re-running it later finishes
  the job.
