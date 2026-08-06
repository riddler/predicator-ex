---
name: implement-plan
description: Implement technical plans from docs/plans with verification
model: sonnet
argument-hint: ["path to plan file", "--loop", "--from-phase N"]
---

# Implement Plan

You are tasked with implementing an approved technical plan from `docs/plans/`.
These plans contain phases with specific changes and success criteria.

Implementation runs on the Sonnet tier (this skill's frontmatter); planning runs
on Opus via `/create-plan` and `/iterate-plan`.

For an unattended, phase-by-phase run with no human confirmation between
phases, pass `--loop` - see `## Looped Execution Mode` below. Everything else
in this document describes the default, interactive mode.

## Before You Start: Claim the Issue and Pick a Worktree

- The plan references a beads issue ID. Claim it before touching code:

  ```bash
  bd update <id> --claim
  ```

- **When working in parallel with other agents**, do the work in a git worktree
  under `../predicator-ex-worktrees/` named `<beads-id>-<slug>`:

  ```bash
  /new-worktree <beads-id>-<slug>
  ```

  One issue = one branch = one worktree. `/new-worktree` also warms `deps/`,
  `_build/` and the dialyzer PLT, which is the difference between a first
  `mix quality` that takes seconds and one that rebuilds the PLT from scratch.
  Run the same quality gates inside the worktree (`mix quality --profile loop`
  while iterating, full `mix quality` before the branch is committed or
  pushed). Use `bd note` for progress other agents might need.

- Working solo directly in the repo is fine; the claim still happens first, and
  the work still lands on a feature branch, never on `main`.

## Looped Execution Mode

**Trigger**: `/implement-plan <path> --loop` or
`/implement-plan <path> --loop --from-phase N`.

**Preconditions**: the beads issue is claimed (same as above); the tree is
clean (`git status --porcelain` is empty) before the loop starts. If it isn't,
stop and report rather than looping over an already-dirty tree.

**Per-phase procedure**, repeated for each phase from the first with an
unchecked Automated Verification box (or from `--from-phase N`) through the
last phase in the plan:

1. Identify the phase's full text (heading through its Success Criteria) from
   the plan file.
2. Dispatch one `Agent` call (`subagent_type: general-purpose`,
   `run_in_background: false`) with a **fully self-contained prompt**: the
   plan file path, the phase number and its complete text, the beads issue
   id, and explicit instructions to:
   - read the plan and the beads issue itself (it has no memory of this
     conversation),
   - implement only this phase, following the plan's intent and this
     project's conventions (`@doc`/`@spec` on public functions, errors as
     `{:ok, _} | {:error, _}` values, no `eval`),
   - keep `mix quality --profile loop` green while iterating,
   - check off this phase's Automated Verification boxes in the plan file
     (Edit) once satisfied - never check off Manual Verification boxes,
   - append any Manual Verification items from this phase, verbatim, to a
     running `## Deferred Manual Verification` section at the bottom of the
     plan file (create it on first use) instead of blocking on them,
   - **not** commit, **not** run the full `mix quality` as a final gate (the
     orchestrator does both), **not** close the beads issue,
   - **implement this phase itself**: this loop is already the per-phase
     orchestrator, so do not delegate the phase to a further subagent and do
     not invoke `/implement-plan` (or `/work`) itself - either one would
     re-dispatch phases a level down, outside this orchestrator's
     `/commit --auto` advancement gate, and past the spawn depth this design
     intends. A narrowly-scoped sub-task for debugging or exploring
     unfamiliar territory (per `## If You Get Stuck` below) is still fine -
     the rule is against delegating the phase itself, not against every use
     of a subagent,
   - end by reporting what changed and whether it believes the phase is
     complete.

   (`general-purpose` stays the agent type here rather than a narrower one:
   the "use sub-agents sparingly" allowance below means the phase subagent
   still legitimately needs the Agent tool for a targeted debugging or
   exploration sub-task, and no project-defined agent type under
   `.claude/agents/` combines Edit/Write/Bash with a trimmed-down Agent/Skill
   set. The prompt instruction above is the fix, not a tool restriction.)
3. The orchestrator - not the subagent - runs `/commit --auto`. This is the
   automated advancement gate: full `mix quality`, the unrelated-changes check,
   and the branch/issue checks all run for real, independent of the subagent's
   self-report.
   - **Refused** (red gate, narrowed gate, unrelated changes, no issue
     detected): stop the loop immediately - no retry.
     **Uncheck this phase's Automated Verification boxes in the plan file**
     (Edit) if the subagent checked any before the gate ran - the resume scan
     below keys off those boxes, and a refusal means this phase's work never
     actually landed, whatever the subagent's own checklist says. Leave every
     other file exactly as the subagent left it - the refusal is diagnostic
     information for the human or the next resume, not something to clean up.
     Run `bd note <id> "loop stopped at Phase N: <refusal reason>"`. Report
     the refusal reason and which phase it happened in, then end the turn.
   - **Committed**: run `bd note <id> "loop: Phase N complete, commit <sha>"` -
     this is the state handoff a later invocation (or a human) reads to see
     what happened in a session that no longer exists. Advance to the next
     phase.
4. After the last phase commits successfully, print the accumulated
   `## Deferred Manual Verification` section (if non-empty) as the final
   report, the same way non-loop mode reports Manual Verification items -
   just batched instead of per-phase. Do not remove the section from the
   plan file; a human confirming it later can check items off the same way
   non-loop mode does today.

**Resuming after a stop**: re-running `/implement-plan <path> --loop`
re-scans the plan for the first phase with an unchecked Automated
Verification box and continues from there, same as `## Resuming Work` below
already describes for interactive mode. Pass `--from-phase N` to force
starting at a specific phase (e.g. after a human fixes the failure by hand
and wants to skip re-dispatching a phase that's actually done but whose boxes
weren't checked).

## Getting Started

When given a plan path:

- Read the plan completely and check for any existing checkmarks (- [x])
- Read the beads issue (`bd show <id>`) and all files mentioned in the plan
- **Read files fully** - never use limit/offset parameters, you need complete
  context
- Think deeply about how the pieces fit together
- Create a todo list to track your progress
- Start implementing if you understand what needs to be done

If no plan path provided, ask for one.

## Implementation Philosophy

Plans are carefully designed, but reality can be messy. Your job is to:

- Follow the plan's intent while adapting to what you find
- Implement each phase fully before moving to the next
- Verify your work makes sense in the broader codebase context
- Update checkboxes in the plan as you complete sections
- Keep `mix quality --profile loop` green between edits; the gate's Format stage
  formats for you, so do not run `mix format` as a separate step

When things don't match the plan exactly, think about why and communicate
clearly. The plan is your guide, but your judgment matters too.

### When Implementing Pipeline Changes

If the plan touches the lexer, parser, compiler, evaluator, or visitors:

- The pipeline is source -> tokens -> AST -> instructions -> stack VM. A change
  at one stage usually needs the next one; a syntax change that compiles to
  nothing, or an instruction nothing emits, is a half-finished change.
- **A grammar change is not done until `StringVisitor` round-trips it.**
  Rendering the AST back to source is part of the public contract, not a
  nicety.
- **Instructions are the cross-language interchange format** (ADR-0001). Adding
  or changing one is a decision the Ruby and JavaScript implementations have to
  match, so it belongs in the commit message and the PR body, not just the code.
- Errors are values: return `{:ok, result} | {:error, ...}` and let the caller
  decide. Never raise at a leaf, and never rescue-to-default.
- No `eval`, no `Code.eval_string`, no dynamic dispatch on user input. That is
  the whole point of the project.
- Credo complexity warnings are suppressed in the lexer and parser with
  explanatory comments. That is not an invitation to suppress others.

If you encounter a mismatch:

- STOP and think deeply about why the plan can't be followed
- Present the issue clearly:

  ```
  Issue in Phase [N]:
  Expected: [what the plan says]
  Found: [actual situation]
  Why this matters: [explanation]

  How should I proceed?
  ```

## Verification Approach

After implementing a phase:

- Run the success criteria checks: `mix quality --profile loop` while
  iterating, then the full `mix quality` gate for the phase (this is also the
  pre-commit bar). Use `mix quality --format json` if you need to route on the
  results programmatically. Never truncate the gate's output.
- **Never weaken the gate to get it green**: no lowered coverage threshold, no
  `enabled: false`, no `--skip-*` on the final check, no `@tag :skip`. Coverage
  is >90% per component, enforced by `coveralls.json`. If a finding is
  genuinely wrong for this repo, report it and let a human decide.
- Cover the error paths, not just the happy path. In a codebase where errors are
  return values, the uncovered lines the gate finds are almost always the
  `{:error, _}` branches.
- Fix any issues before proceeding
- Update your progress in both the plan and your todos
- Check off completed items in the plan file itself using Edit
- **In interactive (non-`--loop`) mode: pause for human verification**. After
  completing all automated verification for a phase, pause and inform the
  human that the phase is ready for manual testing. Use this format:

  ```
  Phase [N] Complete - Ready for Manual Verification

  Automated verification passed:
  - [List automated checks that passed]

  Please perform the manual verification steps listed in the plan:
  - [List manual verification items from the plan]

  Let me know when manual testing is complete so I can proceed to Phase [N+1].
  ```

  In `--loop` mode, see `## Looped Execution Mode` above instead - automated
  verification gates advancement and Manual Verification items are deferred
  to a batched report at the end.

Do not check off items in the manual testing steps until confirmed by the user.

## If You Get Stuck

When something isn't working as expected:

- First, make sure you've read and understood all the relevant code
- For a parse or precedence surprise, check the grammar and precedence table in
  `docs/architecture.md` before assuming the code is wrong - the table is the
  specification
- For an evaluation surprise, print the compiled instruction list. The VM is
  small and flat; reading what it was actually asked to run is usually faster
  than reasoning about what it should have been asked to run
- Consider if the codebase has evolved since the plan was written
- Present the mismatch clearly and ask for guidance

Use sub-agents sparingly - mainly for targeted debugging or exploring
unfamiliar territory.

## Wrapping Up

- When all phases are complete and the full `mix quality` gate is green, report
  status and commit with `/commit`. **Do not close the beads issue**: `bd close`
  fires on merge into `origin/main`, verified against the remote (CLAUDE.md's
  authority table), and the bead stays `in_progress` until then.
- User-facing changes need an entry under `## [Unreleased]` in `CHANGELOG.md`;
  `/commit` checks for one.
- Capture discovered work immediately with `bd q` and link it with
  `discovered-from` rather than chasing it mid-task
- Push and PR are a separate, explicit ask. `/merge-request` is the skill for
  it, and it confirms before pushing.
- In `--loop` mode, this wrapping-up happens once, after the last phase's
  commit - not per phase. Discovered work still goes to `bd q` as it's found,
  rather than being batched to the end.

## Resuming Work

If the plan has existing checkmarks:

- Trust that completed work is done
- Pick up from the first unchecked item
- Verify previous work only if something seems off

Remember: You're implementing a solution, not just checking boxes. Keep the end
goal in mind and maintain forward momentum.
