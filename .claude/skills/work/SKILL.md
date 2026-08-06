---
name: work
description: Single entry point for working a bead - creates or reads it, sizes the job, then drives research / plan / implement as model-tiered subagents. Never implements directly.
model: opus
argument-hint: ["a beads issue ID, or free text describing the work", "optional: --auto"]
---

# Work

The single entry point for working a bead. Take a bead id (or free text that
becomes one), size the job **with the codebase in reach**, then drive the
research -> plan -> implement sequence as model-tiered subagents.

This skill orchestrates. It never implements the bead itself.

`model: opus` in the frontmatter is what makes "the orchestrator is always Opus"
hold even when `/work` is typed into an already-running Sonnet session: a
skill's `model:` governs the turn it is active for, independent of the session's
own model.

## Input

Parse `$ARGUMENTS`:

- **A token matching the `px-` id shape** (`px-abc`, `px-8um.3`) -> **bead
  mode**: that is the bead to work.
- **`--auto` present** -> **unattended mode**: no checkpoint pauses, no
  questions. This is what `/new-worktree` seeds. Without it, `/work` pauses at
  each artifact boundary for review.
- **Anything else** -> **intake mode**: the free text is the work description
  and a bead must be created from it before anything else happens.

    /work px-abc                                   # bead mode, interactive
    /work px-abc --auto                            # bead mode, unattended
    /work "add a len() function for strings"       # intake mode

## Step 0: Locate self

Everything downstream branches on this, because CLAUDE.md forbids committing on
`main`:

```bash
if [ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ]; then
  echo main-checkout
else
  echo worktree
fi
```

In the main checkout both resolve to `.git`; in a linked worktree `--git-dir` is
`.git/worktrees/<name>` while `--git-common-dir` is the shared `.git`. This is
more robust than comparing `git rev-parse --show-toplevel` against a hardcoded
path - it survives the checkout being moved or cloned elsewhere.

- **main checkout** -> do intake (step 1) if needed, claim the bead, compute the
  branch name `<id>-<slug>` (2-4 distinctive kebab-case words from the title,
  not a full transcription), then invoke
  **`/new-worktree <id>-<slug> -- /work <id> --auto`** and **stop**. Do not work
  the bead here. The seeded session's `/work` runs step 0 again, takes the
  worktree branch, and does the work - so the recursion terminates at depth one.
- **worktree** -> continue to step 1.

## Step 1: Get a claimed bead

**Bead mode.** `bd show <id>` - description, acceptance, dependencies, notes.
This is the input to sizing, so it happens before anything is spawned. If the
bead is not already `in_progress`, claim it:

```bash
bd update <id> --claim
```

The claim is the lock (CLAUDE.md, worktrees). An epic is not workable: report
it, point at its children, and stop.

**Intake mode.** Compose with **`/create-issue`** rather than duplicating it.
The bead **must** carry, before it is claimed:

- a description,
- acceptance criteria (`bd create ... --acceptance "..."`),
- at least one `area:` label from CLAUDE.md's vocabulary.

The area label is not optional and is not something to backfill later: an
unlabeled bead is exactly what `/next-issues` skips as "blast radius undecided",
so a bead this skill creates and then leaves unlabeled is a bead the batch
picker will refuse to touch. Intake owes the label at creation.

Then claim and publish:

```bash
bd update <id> --claim
bd dolt push 2>/dev/null || true
```

The push is best-effort and never gates the claim - agents in this checkout's
worktrees share the DB directly and see the claim regardless.

## Step 2: Size the job

Buckets are **entry points into one sequence**, not terminal choices. Picking
"plan-only" does not mean planning is the whole job; it means the sequence
starts at the plan stage and runs through implementation from there.

| Bucket | Enters at | Stages, in order | When |
|---|---|---|---|
| **Code-heavy** | research | `research-codebase` -> `create-plan` -> `implement-plan --loop` | Touches the lexer/parser/compiler/evaluator chain across more than one stage; blast radius unclear; the existing grammar, precedence table, or instruction handling must be mapped before planning. |
| **Plan-only** | plan | `create-plan` -> `implement-plan --loop` | Well understood but multi-step or cross-cutting enough to deserve a plan in `docs/plans/`. Anything crossing more than one `area:` label starts here at the latest. |
| **Just-do-it** | implement | one implementation subagent, no artifacts | Bounded doc / chore / config / single-module change, low blast radius. |
| **Direction** | direction | direction stage (Step 3) -> resumes into the sequence below | ADR-shaped work: architecture decisions, grammar or instruction-set questions, review of plans or of finished phases. |

**Anything that changes the instruction set is at least Direction or
Plan-only, never just-do-it.** The instruction set is the cross-language
interchange format shared with the Ruby and JavaScript implementations
(ADR-0001), so a change to it is not a local decision and does not belong in
an unreviewed one-shot.

**Direction still goes through the worktree-per-bead path, deliberately.** An
ADR is a `docs/` change and often precedes the code it governs, so a warmed
Elixir worktree is wasted setup for it - but wasted is not harmful, and the
alternative is a second pickup path that only Direction beads use, forking the
flow this skill exists to keep singular (see "Sizing happens here" below). One
path that occasionally warms a build it does not need is cheaper than two paths
to keep in sync, so Direction enters at Step 0 like every other bucket and pays
the same worktree cost.

**Sizing happens here, with the codebase in reach.** That is the whole reason it
lives in this skill rather than in `/next-issue`: read the files the bead names
before choosing a bucket. A description-only guess at blast radius is what this
step exists to replace.

When genuinely uncertain between two buckets, pick the heavier one
(research > plan > just-do-it). Skipped diligence costs more than an unnecessary
research pass.

**Skip stages already satisfied.** Before spawning anything, check for work that
already exists:

- a `docs/research/` doc naming this bead,
- a `docs/plans/` plan naming this bead,
- `bd show <id>`'s notes - `/implement-plan --loop` writes
  `loop: Phase N complete, commit <sha>` after each phase, and
  `loop stopped at Phase N: <reason>` when it refuses.

Enter the sequence at the first unsatisfied stage. This is the seam that makes
`/work <id>` re-invocable: after a stopped loop, re-running it resumes rather
than restarting.

**Report the bucket and a one-line rationale** before spawning. Without
`--auto`, let the user override it first.

## Step 3: Stage contract

| Stage | Skill | Agent type | `model` |
|---|---|---|---|
| Research | `/research-codebase <id>` | `general-purpose` | `opus` |
| Plan | `/create-plan <id>` | `general-purpose` | `opus` |
| Direction | *(no stage skill - prompt below)* | `general-purpose` | `opus` |
| Implement | `/implement-plan <path> --loop` | `general-purpose` | `sonnet` |

Every spawn obeys these invariants:

- **The `model` column mirrors each skill's `model:` frontmatter; it does not
  override it.** A skill's frontmatter wins for the turn it is active, so the
  Agent-call override governs only the subagent's turns *before* the skill
  fires - the `bd show`, the file reads. Keeping the two equal is the point: if
  they ever diverge, the frontmatter is what actually runs and this table is
  wrong. **Direction is the one row with nothing to mirror** - none of the
  existing skills fit what it produces (a decision, not a plan or an
  implementation), so its prompt is composed directly in the Agent call instead
  of dispatched through the Skill tool.
- **`run_in_background: false`.** Each stage feeds the next; there is nothing to
  do while one runs.
- **The prompt must be fully self-contained**: the bead id, the artifact path
  when there is one, and an explicit instruction to read the bead itself. The
  subagent has no memory of this conversation. This is the same rule
  `/implement-plan`'s loop already states at its step 2.
- **No human is available.** Tell the subagent so, and tell it what to do
  instead: record open questions *in the artifact it produces* and return them
  in its report; never block on a question. `/create-plan` and
  `/research-codebase` are interactive by design, and this instruction is what
  makes them terminate instead of stalling on a clarifying question nobody will
  answer.
- **Return the artifact path** in the report, so `/work` can pass it to the next
  stage.
- **Never a nested `claude` CLI.** A seeded session cannot spawn one -
  `--permission-mode auto`'s classifier blocks `tmux send-keys ... 'claude'`
  (see `new-worktree/SKILL.md`'s closing note). In-process Agent subagents are
  unaffected and are the only mechanism this skill uses.

### Direction stage prompt

No skill wraps this stage, so the prompt is written out here and composed
directly into the Agent call. Tell the subagent to:

- read the bead in full (`bd show <id>`) and the files it names;
- read the existing entries under `docs/adr/` (and `docs/architecture.md`,
  `docs/reference/language.md` where relevant) to see whether the bead is
  asking for a new ADR, an amendment to one already accepted, or a narrower
  grammar or instruction-set interpretation that does not warrant its own ADR;
- write the decision as a new `docs/adr/NNNN-<slug>.md` at the next free
  number, in the same shape and with the same status heading every other ADR
  in the repo carries, and add it to `docs/adr/README.md`'s index. There is no
  `proposed` state here: a second status would need something to sweep for
  drafts that were never promoted, and an ADR nobody promoted reads as settled
  anyway. The human gate on this work is the review of the branch it lands on,
  same as any other change. A call too narrow for its own ADR goes to
  `docs/research/` instead, naming the bead;
- **say explicitly whether the decision changes the instruction set.** That is
  cross-language interchange (ADR-0001), so it binds the Ruby and JavaScript
  siblings too and has to be visible in the ADR, not inferred from it;
- return the artifact path and a one-line statement of the decision it made
  (or the open question it could not resolve, recorded in the artifact per
  the "no human is available" invariant above).

Same invariants as every other row: self-contained prompt, `run_in_background:
false`, no human available, return the artifact path, no nested `claude` CLI.

**What happens after the artifact** follows Step 2's "buckets are entry points
into one sequence" framing. Some Direction beads are done once the ADR lands -
the decision was the whole deliverable, and Step 5 reports the ADR path as the
terminal artifact. Others exist to unblock implementation the bead also asks
for; once the direction question has an answer, `/work` re-enters Step 2 and
sizes whatever is left the normal way (commonly plan-only or just-do-it, since
the hard call is already made) rather than treating Direction as a dead end.

`general-purpose` is the right agent type because its tool list is `*`: it has
both the Skill tool (to invoke the stage skill) and the Agent tool (so the
implement stage's own loop can spawn per-phase subagents).

## Step 4: Implement stage

**With a plan**: one Sonnet subagent running `/implement-plan <path> --loop`.

That loop is **already a per-phase orchestrator**: it dispatches one
`general-purpose` subagent per phase with a self-contained prompt, and it runs
`/commit --auto` *itself* after each phase as the automated advancement gate -
deliberately independent of the phase subagent's self-report. `/work` must not
re-implement either half. Do not spawn per-phase subagents here, and do not run
`/commit` per phase here.

The nesting this produces - `/work` (main) -> implement subagent (layer 1) ->
per-phase subagent (layer 2) - is within Claude Code's default three-layer spawn
depth.

On a **stopped loop**, the subagent returns the refusal reason and the phase.
Report both verbatim; do not retry and do not clean up the tree - the refusal is
diagnostic information. Re-running `/work <id>` later resumes via step 2's
artifact scan.

**Just-do-it** is the same shape without a plan: one Sonnet subagent implements
the bead and is told explicitly **not** to commit; `/work` runs `/commit --auto`
itself afterwards. This mirrors the loop's deliberate split - the gate runs
independent of the subagent's self-report, so a subagent that believes it is
done still has to pass a real gate.

## Step 5: Checkpoints and report

- **Without `--auto`**: after each stage, print the artifact path and a one-line
  summary, then pause for the user before starting the next stage.
- **With `--auto`**: chain straight through, no pauses, no questions. Report
  every artifact at the end.

Always report:

- the bucket and its one-line rationale,
- each stage that ran, the model it ran on, and the artifact it produced,
- any **Deferred Manual Verification** items the loop surfaced, and any open
  questions a stage recorded in its artifact,
- for a stopped loop: the refusal reason and the phase it stopped at,
- whether the work changed the instruction set (ADR-0001), since that has to
  reach the commit message and the eventual PR body.

## Guidelines

- **This skill orchestrates, it does not implement.** No `Edit`/`Write` to
  `lib/`, `test/`, or `docs/` content. The only things this session does itself
  are `bd` calls, the just-do-it `/commit --auto` gate, and its own report.
  Everything else is a subagent.
- **Sizing happens here, in the worktree**, because this is the session that can
  read the code. That is why it moved out of `/next-issue`, and re-adding a
  bucket decision upstream of the worktree undoes the point of this skill.
- Sync steps (`bd dolt pull`/`push`) are best-effort and never gate a claim.
  Offline is not a reason to abort.
- Discovered work found along the way is filed with `bd q` and linked
  `discovered-from`, not chased now.
- Compose with `/create-issue`, `/new-worktree`, and the three stage skills
  rather than duplicating their logic. When a stage skill's behavior needs to
  change, change it there.
- The bead stays `in_progress` when the work is done - it closes on merge, per
  CLAUDE.md's authority table. Push, PR, and `bd close` all still need an
  explicit human ask; finishing the work is not a request to publish it.
