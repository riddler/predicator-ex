---
name: next-issue
description: Pick the next ready bead (choices by default, --auto lets an agent take the top item), claim it, stand up its worktree via /new-worktree, then triage to plan-first or implement directly
model: sonnet
argument-hint: ["optional: --auto, and/or bd ready filters (e.g. -l area:evaluator, -p 1)"]
---

# Next Issue

Pick the next unblocked, unclaimed bead, claim it so other worktrees skip it,
cut its worktree branch via `/new-worktree`, and route the work to the right
follow-up. Beads is the only tracker here (CLAUDE.md) - there is no external
issue system to promote to or reconcile against. Issue state syncs across
machines through `refs/dolt/data` on git origin (`bd dolt pull` / `bd dolt
push`); `.beads/issues.jsonl` is a passive export, never the sync channel.

## Modes

Parse `$ARGUMENTS`:

- **`--auto` present** -> **agent-auto mode**: atomically claim the top ready
  item and proceed without confirmations. For unattended agents.
- **Otherwise** -> **manual mode** (the default): always present choices and let
  the user pick. Never auto-select in manual mode, even if only one item is
  ready - show it and confirm.

Everything else in `$ARGUMENTS` maps to `bd ready`'s native filter flags
(`-p/--priority`, `-l/--label`/`--label-any`/`--exclude-label`,
`-t/--type`/`--exclude-type`, `--parent`, ...) and is passed through to
whichever call runs, so both modes scope identically. Re-verify against
`bd ready --help` if these drift.

## Steps

0. **Refresh beads (best-effort).** The Dolt DB syncs via `refs/dolt/data` on
   git origin (github.com/riddler/predicator-ex), so pull the latest issue state
   before picking - another machine or agent may have claimed or closed work:
   ```bash
   bd dolt pull 2>/dev/null || true
   ```
   Non-fatal if offline; the local DB is then the best available view. On a
   fresh clone with no `.beads/embeddeddolt/`, run `bd bootstrap` instead - it
   clones the issue history from origin and wires the Dolt remote.

0.5. **Clean up merged worktrees (best-effort).** Invoke
   **`/cleanup-worktrees`**. Picking up new work is the natural moment for it:
   the previous branch has usually landed by now, and its worktree and local
   branch are still sitting there. Detection is GitHub PR state, never git
   ancestry - the repo allows rebase merging only, so a merged branch is never
   an ancestor of `main`.

   Like the sync steps, this must never gate the pickup. If `gh` is
   unauthenticated or offline, `/cleanup-worktrees` stops on its own and reports;
   carry on picking work regardless.

1. **Pick and claim.**

   **Manual mode:**
   ```bash
   bd ready --json [FILTERS]
   ```
   Present the top few candidates (id, title, type, priority, one-line why-now
   drawn from its epic/dependencies if obvious) and let the user pick or confirm
   the top one. Then claim:
   ```bash
   bd update <id> --claim
   ```

   **Agent-auto mode** - one atomic call, no read-then-claim race:
   ```bash
   bd ready --claim --json [FILTERS]
   ```
   Non-empty -> `[0]` is the claimed bead (status already `in_progress`); read
   `.id` from it.

   **Empty (`[]`)** in either mode -> nothing ready and unclaimed. Do not
   auto-file. Report it, show `bd blocked` so it is clear what is waiting on
   what, and stop (skip every step below). In manual mode, offer to file
   something new with `bd create`.

1.5. **Publish the claim (best-effort).** The claim is the lock, but it only
   locks what other machines can see - push it right after claiming:
   ```bash
   bd dolt push 2>/dev/null || true
   ```
   Non-fatal if offline (agents in the same checkout's worktrees share the DB
   directly and see the claim regardless); it publishes on the next push.

2. **Compute the branch name** `<id>-<slug>`. Kebab-case the bead title into a
   short slug - 2-4 distinctive words, not a full transcription
   (`/new-worktree` refuses to guess one, so this skill must produce the full
   name). Manual mode: present it for confirmation.

3. **Read the bead.** `bd show <id>` - description, acceptance, dependencies,
   notes. This is the input to the triage decision in step 4, so it has to
   happen before the worktree is stood up, not after.

4. **Triage.** Judge what the issue needs from what is already in hand (type,
   description, priority, which module it touches), then pick exactly one
   bucket.

   | Bucket | Seed command | When |
   |---|---|---|
   | **Plan-first** | `/create-plan <id>` | Touches the lexer/parser/compiler chain, changes the instruction set, or is otherwise multi-step or cross-cutting enough to deserve a plan in `docs/plans/`. Anything crossing more than one `area:` label starts here. Runs on Opus per its frontmatter. |
   | **Just-do-it** | *(no seed command - omit `--`)* | Bounded doc / chore / config / single-module change with low blast radius. Skip the plan and start implementing immediately, keeping `mix quality --profile loop` green. |

   Just-do-it has no skill to invoke, so it omits the `--` and lets
   `/new-worktree` use its generic seed ("Work bead `<id>` ... start with
   `bd show`"). That is the one bucket where the seeded session legitimately
   reads the bead and starts working, because that is the whole instruction.

   There is deliberately no separate research bucket here. Predicator is small
   enough that a plan-first session can do its own reading; a change to the
   instruction set is the case where that reading is genuinely expensive,
   because it is cross-language interchange (ADR-0001) and the Ruby and
   JavaScript siblings are part of the blast radius. Say so in the rationale
   when it applies, so the seeded session knows to look outward.

   - When genuinely uncertain between the two, pick plan-first - skipped
     diligence costs more than an unnecessary plan.
   - **Manual mode:** state the chosen bucket and a one-line rationale, and let
     the user override before the worktree is created.
   - **Agent-auto mode:** announce bucket + rationale, then proceed.

5. **Stand up the worktree, seeded with the routing.** Invoke
   **`/new-worktree <id>-<slug> -- <seed command>`** - it cuts the branch off
   `origin/main`, creates `../predicator-ex-worktrees/<id>-<slug>`, warms
   `deps/`, `_build/`, and the dialyzer PLT, verifies the loop profile is green,
   and opens a tmux window running a Claude session on the seed command.

   **Pass the bucket's command through.** The triage decision was made here,
   with the bead in hand; the session that acts on it is a different process
   with none of that context. Dropping the command means it re-derives the
   bucket from scratch, usually differently, and the diligence this step just
   paid for is spent twice.

6. **Hand off - do not do the work here.** The seeded session in the tmux
   window owns the issue from this point. Doing it in this session as well is
   two sessions editing one worktree.

   **Report**: the chosen bead, that it was claimed, the branch and worktree
   created, the quality-check result from `/new-worktree`, the bucket and its
   one-line rationale, and the tmux window to jump to.

## Guidelines

- Claim before worktree, always - the claim is the lock. Never create the
  worktree for an unclaimed bead.
- Sync and cleanup steps (0, 0.5 and 1.5) are best-effort and must never gate
  the claim: if `bd dolt pull`/`push` is slow, errors, or the machine is
  offline, proceed - they retry on the next run. Never abort pickup on a sync
  failure.
- Manual mode confirms the pick and the branch name before anything mutates the
  repo; the claim itself is cheap to reverse (`bd update <id> --status open`).
- Discovered work found while triaging is filed with `bd q` and linked
  `discovered-from`, not chased now.
- Compose with `/new-worktree` rather than duplicating its logic.
- **This skill dispatches, it does not implement.** Triage happens here because
  the bead is in hand; the work happens in the seeded session because that is
  where the worktree is. Splitting it the other way - deciding there, working
  here - is how one issue gets worked twice.
- Re-verify exact `bd` flags against `bd ready --help` if this drifts -
  `bd ready --claim --json` and `bd update --claim` are confirmed current as of
  the bd version in use (2026-08).
