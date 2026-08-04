---
name: next-issues
description: Pick up to n ready beads whose area labels are pairwise disjoint, claim them all, and stand up a worktree and tmux window for each via /new-worktree - the batch form of /next-issue, for fanning out to several parallel worktrees in one pass
model: sonnet
argument-hint: ["optional: n (default 3, max 4), --auto, and/or bd ready filters (e.g. -l area:evaluator, -p 1)"]
---

# Next Issues

Fan out. Pick several ready beads that are safe to work on at the same time,
claim all of them, and give each its own branch, worktree and tmux window.

`/next-issue` is the one-at-a-time form of this: pick, claim, one worktree, one
follow-up route. Running it three times gets three worktrees, but nothing checks
that those three beads can coexist - that judgment lands on whoever is watching,
once per run. This skill makes the collision check the mechanism: two beads are
batchable iff their `area:` label sets are disjoint (CLAUDE.md, area labels), so
a batch is a set intersection rather than an opinion.

This skill **composes**, it does not fork. Selection is the only thing it adds;
everything downstream is `/new-worktree`, exactly as `/next-issue` uses it.

## Input

Parse `$ARGUMENTS`:

- **A bare integer** -> `n`, the ceiling on batch size. Default `3`.
  **Refuse `n > 4`**: say so, and say why - beyond four the merge queue is the
  constraint, not the picking, and every extra worktree is another branch that
  has to rebase past the ones that land first. Offer to run with 4.
- **`--auto` present** -> **agent-auto mode**: select and claim without
  confirmation. For unattended agents.
- **Otherwise** -> **manual mode** (the default): present the batch, and what was
  skipped and why, and confirm before claiming.

Everything else maps to `bd ready`'s native filter flags (`-p/--priority`,
`-l/--label`/`--label-any`/`--exclude-label`, `-t/--type`/`--exclude-type`,
`--parent`, ...) and is passed straight through. Re-verify against
`bd ready --help` if these drift.

`n` is a **ceiling, not a target.** Returning two when three were asked for is
the right outcome when the third collides. The report must say so explicitly - a
silently short batch reads as "there was no more work", which is a different and
much more alarming fact.

## Steps

0. **Refresh beads (best-effort).**
   ```bash
   bd dolt pull 2>/dev/null || true
   ```
   Non-fatal if offline; the local DB is then the best available view. On a fresh
   clone with no `.beads/embeddeddolt/`, run `bd bootstrap` instead.

0.5. **Clean up merged worktrees (best-effort).** Invoke
   **`/cleanup-worktrees`**. This matters more here than in `/next-issue`: about
   to stand up three or four worktrees is exactly the wrong moment to be carrying
   three or four dead ones. Never let it gate the pickup - if `gh` is
   unauthenticated or offline it stops on its own and reports; carry on.

1. **List candidates.**
   ```bash
   bd ready --json [FILTERS]
   ```
   Results come back priority-sorted already. **Empty (`[]`)** -> nothing ready
   and unclaimed. Do not auto-file. Report it, show `bd blocked` so it is clear
   what is waiting on what, and stop. In manual mode, offer to file something new
   with `bd create`.

2. **Select greedily, highest priority first.** Walk the list in order,
   maintaining the batch and the union of its area labels. For each bead:

   | Test | Outcome |
   |---|---|
   | `issue_type == "epic"` | **skip** - "epic; work its children" |
   | no `area:` label and no `upstream` label | **skip** - "no area label; blast radius undecided" |
   | `area:build` and the batch is non-empty | **skip** - "area:build lands alone" |
   | `area:build` and the batch is empty | **take it, and stop** - the batch is this bead |
   | its areas intersect the batch's union | **skip** - name the overlapping area(s) and the bead already holding them |
   | otherwise | **take it**; union in its areas |

   Stop at `n` beads or at the end of the list, whichever comes first.

   Greedy by priority, **not optimal**. A picker that solves for the largest
   disjoint batch will sometimes prefer three P3s to one P1, which is the wrong
   trade every time. Take the highest-priority ready bead, then keep adding the
   next-highest that does not collide.

   Two rules that are not obvious from the table:

   - **An unlabeled bead is a bead nobody has decided the blast radius of.**
     Skipping it is not a failure of this skill; it is the label being missing.
     Say which beads were skipped for this so they can be labeled and re-run.
     The one exception is `upstream` beads, which change no files in this repo by
     definition and so collide with nothing (CLAUDE.md) - they need no area label
     and are always batchable.
   - **Do not batch across a dependency edge.** `bd ready` already serializes
     `blocks`/`depends-on`, but a parent epic and its child can both be ready.
     That is what the epic row is for.

   Watch `area:api` in particular. It covers `lib/predicator.ex` and the error
   structs, which is where a surprising number of otherwise-disjoint beads
   eventually meet: two features in different subsystems that each need to widen
   the public façade both carry it, and they are correctly not batchable.

3. **Present the batch (manual mode).** Show both halves - what was picked, and
   what was skipped and why. "Why did it only take two" is the question this
   skill will be asked most often, and the answer has to be on screen before
   anyone asks. Confirm, then continue.

   In agent-auto mode, print the same two lists and proceed without confirming.

4. **Compute a branch name per bead**: `<id>-<slug>`, the slug 2-4 distinctive
   kebab-case words from the title, not a full transcription. `/new-worktree`
   refuses to guess one, so this skill produces the full name. Manual mode:
   confirm the names alongside the batch in step 3.

5. **Claim every bead - all of them, before any worktree exists.**
   ```bash
   bd update <id> --claim   # once per bead in the batch
   ```
   The claim is the lock, and the ordering here is deliberate: claimed-with-no-
   worktree is a cheap, recoverable state (`bd update <id> --status open`), while
   a worktree for an unclaimed bead is another agent's collision waiting to
   happen. If a claim fails - someone else got there between step 1 and now -
   drop that bead from the batch, keep the rest, and say so.

5.5. **Publish the claims (best-effort), once for the batch.**
   ```bash
   bd dolt push 2>/dev/null || true
   ```
   Non-fatal if offline; agents in this checkout's worktrees share the DB
   directly and see the claims regardless.

6. **Triage each bead, then stand up its worktree.** For each bead in the batch,
   `bd show <id>`, pick exactly one bucket using the triage table in
   `/next-issue` (plan-first / just-do-it), then invoke:

   **`/new-worktree <id>-<slug> -- <seed command>`**

   which cuts the branch off `origin/main`, warms `deps/`, `_build/` and the
   PLT, verifies the loop profile is green, and opens a tmux window running a
   Claude session seeded on that command. Just-do-it omits the `--` and takes
   `/new-worktree`'s generic seed.

   Pass the bucket's command through for the same reason `/next-issue` does: the
   triage decision is made here, with the bead in hand, and the session that acts
   on it is a different process with none of that context.

   Worktrees are created **one at a time, in batch order.** Each one clones
   `deps/` and `_build/` from this checkout and then runs a quality gate; running
   several at once contends on the same caches for no gain. If one fails, report
   it, leave its bead claimed, and continue with the rest - a failed worktree is
   not a reason to abandon the ones that worked.

7. **Report the batch.** One row per bead:

   | Bead | Branch | Worktree | tmux window | Bucket |
   |---|---|---|---|---|
   | `px-abc` | `px-abc-object-notation` | `../predicator-ex-worktrees/px-abc-object-notation` | `px-abc-object-notation` (`@42`) | `/create-plan px-abc` |

   Then, always and separately:

   - **what was skipped and why**, bead by bead - including "asked for 4, took 2"
     stated as such
   - any bead left **claimed without a worktree**, with the release command
   - the quality result from each `/new-worktree`
   - a reminder that each issue is worked **inside its own worktree**, in its own
     tmux window - not here

8. **Hand off - do not do any of the work here.** Each seeded session owns its
   issue from this point. This session picked and dispatched; that is the whole
   job.

## Guidelines

- **Claim the whole batch before creating any worktree.** Not per-bead
  claim-then-worktree - that leaves worktrees for beads whose claim later fails.
- Sync steps (0, 0.5, 5.5) are best-effort and must never gate a claim. Offline
  is not a reason to abort a pickup.
- **Areas are about file collision, not subject matter** (CLAUDE.md). Two beads
  both "about durations" touching disjoint files are batchable; two beads in
  different subsystems that both edit `mix.exs` are not.
- **An `area:` label is a prediction, written before the work exists.** A batch
  built on a wrong label produces the rebase conflict the labels exist to
  prevent. When `/refresh-worktree` hits one, that is feedback about this skill's
  input, not just a chore.
- `n > 4` is refused, not silently clamped. Someone asking for 8 has a wrong
  model of where the constraint is, and clamping hides that.
- Discovered work found while triaging is filed with `bd q` and linked
  `discovered-from`, not chased now.
- Compose with `/next-issue`'s triage table, `/new-worktree` and
  `/cleanup-worktrees` rather than duplicating their logic. The only thing that
  lives here is selection.
- Re-verify exact `bd` flags against `bd ready --help` if this drifts -
  `bd ready --json` and `bd update --claim` are confirmed current as of the bd
  version in use (2026-08).
