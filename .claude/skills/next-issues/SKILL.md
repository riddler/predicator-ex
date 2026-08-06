---
name: next-issues
description: Pick up to n ready beads whose area labels are pairwise disjoint, claim them all, and stand up a worktree and tmux window for each via /new-worktree - the batch form of /next-issue, for fanning out to several parallel worktrees in one pass
model: sonnet
argument-hint: ["optional: n (default 3, max 4), --auto, one or more bead IDs, and/or bd ready filters (e.g. -l area:evaluator, -p 1)"]
---

# Next Issues

Fan out. Pick several ready beads that are safe to work on at the same time,
claim all of them, and give each its own branch, worktree and tmux window.

`/next-issue` is the one-at-a-time form of this: pick, claim, one worktree, one
seeded session. Running it three times gets three worktrees, but nothing checks
that those three beads can coexist - that judgment lands on whoever is watching,
once per run. This skill makes the collision check the mechanism: two beads are
batchable iff their `area:` label sets are disjoint (CLAUDE.md, area labels), so
a batch is a set intersection rather than an opinion.

In manual mode this skill **presents choices, it does not decide for you.**
Every candidate's constraints go on screen - including collisions with beads
already in a live worktree elsewhere - before anything is claimed, and the
greedy pick is offered as the *recommended* option among the legal ones, not
as the outcome. A user who understands a collision's risk can still take it,
deliberately, through the override path; an unattended agent (`--auto`) never
can.

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
- **One or more bead IDs** (tokens matching the `px-` id shape) ->
  **explicit-selection mode**: "consider exactly these", not a `bd ready`
  filter. Validate each with `bd show <id>`; an unknown id is reported, not
  silently dropped. Explicit selection skips the `bd ready` listing as the
  candidate source but still checks readiness - a blocked or already-claimed
  bead is a constraint to surface in the picker, not to silently obey or
  silently drop. `n` defaults to the count of listed ids in this mode (still
  capped at 4; refuse and offer to run with 4 if more than four ids are
  given). Mixing bead IDs with `bd ready` filter flags is refused as
  ambiguous - the user gets one input form per invocation.
- **Otherwise** -> **manual mode** (the default): present the candidates,
  their constraints, and the legal batch options; let the user pick before
  claiming anything.

Everything else maps to `bd ready`'s native filter flags (`-p/--priority`,
`-l/--label`/`--label-any`/`--exclude-label`, `-t/--type`/`--exclude-type`,
`--parent`, ...) and is passed straight through. Re-verify against
`bd ready --help` if these drift.

**Exception: `--label-any` is broken upstream as of bd 1.1.2 (filed
[beads#5358](https://github.com/gastownhall/beads/issues/5358)) - it is
silently ignored in embedded-Dolt workspaces (`bd ready`'s WHERE builder never
emits an OR-set clause for it), so passing it straight through returns the
*unfiltered* ready set with no error. `bd ready --help` still advertises it
and always will until the upstream fix lands, so do not quietly drop it from
this list on a future re-verification pass without checking whether #5358 has
closed. Until it does: translate `--label-any l1,l2,...` into the OR form
yourself - run `bd ready --json -l <label>` once per label (each single-label
`-l` call is trivially both AND and OR for one label) and union the results by
id before step 3. `-l`/`--label` (AND) is unaffected and passes through
normally.

`n` is a **ceiling, not a target.** Returning two when three were asked for is
the right outcome when the third collides. The report must say so explicitly - a
silently short batch reads as "there was no more work", which is a different and
much more alarming fact. In manual mode this is what the picker exists to
prevent: the ceiling being hit is shown as a constraint before the batch is
finalized, not discovered afterward in a report.

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

   **Run this every invocation, even if `/cleanup-worktrees` already ran earlier
   in the session.** Step 2's live-worktree survey is only sound for the window
   "since the last sweep", and a fanned-out session can land on `origin/main`
   in the minutes between an earlier cleanup and this run - "cleanup already ran
   this session" is not the same claim as "cleanup ran immediately before this
   survey". Re-running is never wasted: the cost is one `gh` call per worktree,
   against a survey that reports a collision that has already resolved.

1. **List candidates.**

   **Default and filtered forms:**
   ```bash
   bd ready --json [FILTERS]
   ```
   Results come back priority-sorted already. **Empty (`[]`)** -> nothing ready
   and unclaimed. Do not auto-file. Report it, show `bd blocked` so it is clear
   what is waiting on what, and stop. In manual mode, offer `/create-issue`.

   **Do not trust a label filter you cannot verify.** Whenever `FILTERS`
   includes any label flag (`-l`/`--label`, or the `--label-any` translation
   above), also fetch the unfiltered count (`bd ready --json | jq 'length'`)
   and compare it to the filtered count. Equal counts with a nonempty
   unfiltered set is suspicious enough to say so rather than proceed
   silently - it is exactly the symptom a `bd` flag being silently ignored
   produces (see the `--label-any` exception above). Report the mismatch,
   show both counts, and stop rather than building a candidate table from a
   set that was never actually filtered.

   **Explicit-selection mode:** `bd show <id> --json` for each listed id
   instead. An id that does not resolve is reported and dropped from the
   candidate set (not the whole run). For each that resolves, note its
   readiness (blocked / already claimed / open) - this becomes a constraint on
   the candidate table in step 3, not a reason to drop it silently.

2. **Survey live worktrees.** Enumerate other worktrees and the areas they
   already hold, so a candidate that would collide with work in progress
   elsewhere is a known constraint, not a surprise discovered by
   `/refresh-worktree` later:
   ```bash
   git worktree list --porcelain
   ```
   For each worktree other than the main checkout, parse the leading bead id
   from its directory/branch name (`<id>-<slug>`), then `bd show <id> --json`
   to collect its `area:` labels. The result is a map of area -> holding
   worktree/bead. A worktree whose name does not parse to a bead id, or whose
   bead cannot be fetched, is reported and treated as holding no areas -
   best-effort, never fatal, never blocks the survey. `upstream`-labeled beads
   hold no areas, same as in batching.

   **This survey must not simply trust that step 0.5 ran and succeeded.** For
   each live worktree found here, also check whether its branch already
   merged - the same query `/cleanup-worktrees` uses:
   ```bash
   gh pr list --state merged --head <branch> --json number,mergedAt --jq '.[0]'
   ```
   A merged result means the worktree is stale regardless of *why* it survived
   cleanup (0.5 was treated as already satisfied by an earlier run, `gh` was
   briefly down, the session inside it was busy) - treat it as holding no
   areas, same as a worktree whose bead cannot be fetched. This is what turns
   a skipped or failed 0.5 into a correct-but-untidy survey instead of a wrong
   one: without it, a merged-but-not-removed worktree suppresses a candidate
   for colliding with work that already landed on `main`.

   If `gh` itself is unavailable for this check, say so once (not once per
   worktree) and fall back to trusting the raw worktree list, the same
   best-effort stance as step 0.5. A survey degraded this way can still
   overstate held areas, so name that limitation next to any **collides with
   live worktree** verdict step 3 produces from it - a suppressed candidate
   should read as "possibly stale, `gh` was unavailable to confirm" rather
   than presented as a hard fact.

3. **Annotate every candidate with its verdict - select nothing yet.** Walk
   the candidate list (from step 1) and give each one a verdict:

   | Test | Verdict |
   |---|---|
   | `issue_type == "epic"` | **epic** - work its children |
   | no `area:` label and no `upstream` label | **unlabeled** - blast radius undecided |
   | `area:build` | **lands-alone** |
   | its areas intersect a live worktree's held areas (step 2) | **collides with live worktree** - name the area(s) and the worktree/bead holding them |
   | otherwise | **free** |

   These four are order-independent - they hold regardless of what else ends
   up in the batch. Then run the same greedy walk this skill has always run -
   highest priority first, skip epic/unlabeled/live-worktree-collision,
   `area:build` takes the batch alone, otherwise take and union in areas, skip
   on **collides in-batch** (name the overlapping area(s) and the candidate
   already holding them) - stopping at `n` beads or the end of the list. Label
   its result the **recommended batch**: an option to present, not the outcome
   to report.

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

   **Explicit-selection mode:** build the legal options around the requested
   set instead of one greedy walk - the largest legal subset of exactly the
   requested ids, plus sequencing suggestions for the rest (e.g. "px-abc alone
   now, px-def after it lands" when they collide, or "px-def after the live
   worktree holding `area:api` merges").

4. **Present the picker (manual mode).** Show the full candidate table first -
   id, title, priority, verdict - so every constraint is on screen before any
   question is asked. "Why did it only take two" is the question this skill
   will be asked most often, and the answer has to be visible before anyone
   asks it. Then offer the choice:

   - Where the **AskUserQuestion** tool is available, use it. Options:
     1. **The recommended batch** (marked as such).
     2. **Legal alternatives**, when meaningfully different from the
        recommendation - explicit-list subsets, sequencing splits.
     3. **Override**: take a bead despite a named live-worktree or in-batch
        collision. The option text names the specific risk it accepts (e.g.
        "take px-def despite area:api collision with worktree
        px-abc-object-notation").
   - Where it is not available, present the same options as a plain-text list
     and ask for a reply.

   Nothing is claimed until the user picks. Branch-name confirmation (step 5)
   folds into the same presentation.

   **Agent-auto mode:** skip the picker. Take the recommended batch, with
   **collides with live worktree** added as a hard skip alongside epic /
   unlabeled / in-batch-collision - an unattended agent cannot knowingly
   accept a risk on someone's behalf, so the override option does not exist
   here. Explicit-selection input combined with `--auto` takes the largest
   legal subset of the requested ids and reports the rest as skipped, same as
   manual mode's alternatives but without stopping to ask. Print the picked
   and skipped lists and proceed without confirming.

5. **Compute a branch name per bead**: `<id>-<slug>`, the slug 2-4 distinctive
   kebab-case words from the title, not a full transcription. `/new-worktree`
   refuses to guess one, so this skill produces the full name. Manual mode: the
   names ride along in the step 4 presentation, confirmed at the same time as
   the batch choice.

6. **Claim every bead in the chosen batch - all of them, before any worktree
   exists.**
   ```bash
   bd update <id> --claim   # once per bead in the batch
   ```
   The claim is the lock, and the ordering here is deliberate: claimed-with-no-
   worktree is a cheap, recoverable state (`bd update <id> --status open`), while
   a worktree for an unclaimed bead is another agent's collision waiting to
   happen. If a claim fails - someone else got there between step 1 and now -
   drop that bead from the batch, keep the rest, and say so.

   **If the chosen batch includes an override** (manual mode only - `--auto`
   never takes one), record it on each affected bead at claim time:
   ```bash
   bd update <id> --notes "$(date +%F): claimed over area:<x> collision with <worktree/bead> - deliberate override via /next-issues"
   ```
   (append semantics; never `bd edit`, which opens `$EDITOR` and blocks.) This
   is the record that lets `/refresh-worktree` and future selection runs see
   that the collision was accepted on purpose, not missed.

6.5. **Publish the claims (best-effort), once for the batch.**
   ```bash
   bd dolt push 2>/dev/null || true
   ```
   Non-fatal if offline; agents in this checkout's worktrees share the DB
   directly and see the claims regardless.

7. **Stand up a worktree per bead.** For each bead in the batch, invoke:

   **`/new-worktree <id>-<slug> -- /work <id> --auto`**

   which cuts the branch off `origin/main`, warms `deps/`, `_build/` and the
   PLT, verifies the loop profile is green, and opens a tmux window running a
   Claude session seeded on that command. The seed is the same for every bead:
   sizing the job needs the codebase, so `/work` does it in the worktree, not
   here.

   Worktrees are created **one at a time, in batch order.** Each one clones
   `deps/` and `_build/` from this checkout and then runs a quality gate; running
   several at once contends on the same caches for no gain. If one fails, report
   it, leave its bead claimed, and continue with the rest - a failed worktree is
   not a reason to abandon the ones that worked.

8. **Report the batch.** One row per bead:

   | Bead | Branch | Worktree | tmux window |
   |---|---|---|---|
   | `px-abc` | `px-abc-object-notation` | `../predicator-ex-worktrees/px-abc-object-notation` | `px-abc-object-notation` (`@42`) |

   Then, always and separately:

   - **what was skipped and why**, bead by bead - including "asked for 4, took 2"
     stated as such
   - **what was overridden and why**, bead by bead, when the chosen batch took
     one - the same collision named in the picker, now recorded as accepted
   - any bead left **claimed without a worktree**, with the release command
   - the quality result from each `/new-worktree`
   - a reminder that each issue is worked **inside its own worktree**, in its own
     tmux window - not here

9. **Hand off - do not do any of the work here.** Each seeded session owns its
   issue from this point. This session picked and dispatched; that is the whole
   job.

## Guidelines

- **Manual mode presents, it does not impose.** The picker in step 4 is the
  point of this skill; a run that claims before the user has seen the
  candidate table and chosen among the legal options has skipped the part
  that matters.
- **Claim the whole batch before creating any worktree.** Not per-bead
  claim-then-worktree - that leaves worktrees for beads whose claim later fails.
- Sync steps (0, 0.5, 6.5) are best-effort and must never gate a claim. Offline
  is not a reason to abort a pickup.
- **Areas are about file collision, not subject matter** (CLAUDE.md). Two beads
  both "about durations" touching disjoint files are batchable; two beads in
  different subsystems that both edit `mix.exs` are not.
- **An `area:` label is a prediction, written before the work exists.** A batch
  built on a wrong label produces the rebase conflict the labels exist to
  prevent. When `/refresh-worktree` hits one, that is feedback about this skill's
  input, not just a chore.
- **Live worktrees are part of the collision surface, not just the batch being
  formed.** A candidate whose areas are held by another worktree is a
  constraint exactly like an in-batch collision; the only difference is who
  is allowed to override it (a user, deliberately - never `--auto`).
- `n > 4` is refused, not silently clamped. Someone asking for 8 has a wrong
  model of where the constraint is, and clamping hides that. The same applies
  to more than four explicit bead ids.
- Discovered work found while picking is filed with `bd q` and linked
  `discovered-from`, not chased now.
- Compose with `/new-worktree`, `/cleanup-worktrees` and `/work` rather than
  duplicating their logic. The only thing that lives here is selection.
- Re-verify exact `bd` flags against `bd ready --help` if this drifts -
  `bd ready --json`, `bd show --json`, `bd update --claim`, `bd update --notes`
  and `git worktree list --porcelain` are confirmed current as of the bd
  version in use (2026-08).
