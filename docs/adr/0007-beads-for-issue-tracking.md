# ADR-0007: Beads (`bd`) is the issue tracker

Status: proposed (2026-08-07)

## Context

Predicator's work is picked up one issue at a time, by agents, in parallel
worktrees, across sessions that do not share memory and machines that do not
share a filesystem. ADR-0005 records the mechanics of that: one bead, one
branch, one worktree, and a claim taken in the tracker *before* the worktree
exists, because the claim is the lock. ADR-0006 records where a human has to be
standing in that loop, and grades every action by what it takes to undo.

Both of those decisions assume something they do not themselves establish:
that there is a tracker an agent can **query and write locally, in-process,
without a network round-trip and without a human**. That assumption is load
bearing enough to be worth its own record, because if it fails, the two ADRs
above stop describing a workable system.

The reason is that the tracker here is not a to-do list a human reads in the
morning. It is the coordination surface the whole workflow hangs off:

- **`/next-issue` claims before it builds anything.** The claim is what stops a
  second agent from picking the same bead. It has to be atomic
  (`bd ready --claim`), cheap, and visible to other sessions immediately.
- **`/next-issues` computes batches by reading labels off beads.** The
  area-label algebra of ADR-0005 is a set intersection over the `area:` labels
  of candidate beads plus the ones already held by live worktrees. That is a
  query, run once per candidate pair, unattended.
- **`/work` treats a bead as its self-contained input.** Description,
  acceptance criteria, design, and notes are what a freshly seeded session in
  an empty worktree reads to know what it is doing. There is no other context;
  the session was started with nothing but an id.
- **`/implement-plan --loop` writes progress back as notes.** Each completed
  phase gets `bd note <id> "loop: Phase N complete, commit <sha>"`, and a
  refusal or a stop gets its own note. That is how a re-invocation resumes
  rather than restarts, and it means the tracker is written to dozens of times
  in the course of one bead, not once at the start and once at the end.

Write volume is the part that surprises. A single bead's life produces a
create, a claim, several notes, a status change, and often a description or
acceptance edit. Multiply by a fan-out of three or four worktrees. Any property
of the tracker that is merely inconvenient at one write per day becomes
disqualifying at that rate.

### What the alternatives cost

**GitHub Issues** is the obvious default for a public Hex library, and it fails
on four counts at once.

1. **It is network-bound and rate-limited.** Every read is an API round-trip in
   a loop that does many of them, and the loop is expected to run unattended
   while nobody is watching it fail.
2. **It lives outside the repo.** A worktree cut from `origin/main` has the
   code, the plans, and the ADRs on disk; it would not have the issues. An
   agent seeded with nothing but an id could not read its own assignment
   offline.
3. **Its data model is weak where this workflow is strong.** Typed dependency
   links, parent/child hierarchy, acceptance criteria and design as distinct
   fields, and a `ready` computation that respects blockers are all first-class
   in `bd` and all approximations in GitHub Issues - checkbox conventions and
   free-text mentions that no picker can compute over.
4. **Every write would land on a surface other people watch.** This is the
   interlock with ADR-0006 and it is the argument that actually settles the
   question. ADR-0006 places the human gate where an action stops being
   reversible, and rung 2 is "visible to other people and other machines - an
   explicit human ask, in their own words". An agent posting a status update to
   a public issue tracker is squarely rung 2. So under the criterion this repo
   already committed to, **every routine tracking write would need a human
   ask** - and a workflow that stops to ask permission before recording that
   Phase 2 finished is not a workflow, it is a captcha.

That last point is the load-bearing one, and it runs in both directions. A
local tracker makes ordinary tracking *reversible* - a wrong `bd update` is
corrected by another `bd update`, and nobody has seen either - which is exactly
why the authority table can grant `bd create`, `bd claim`, `bd update`, and
`bd note` **with no trigger at all**, while still gating `bd close` on a merge
verified against GitHub and `bd dolt push` on the git side having already
reached origin. The tracker was not exempted from ADR-0006; it was placed on
rung 1 by the same criterion that puts `bd close` on rung 2. Choosing a remote
tracker would have collapsed that distinction and put the whole tracker on
rung 2.

**TodoWrite** is session-scoped. It evaporates when the session ends, and a
bead here routinely outlives its session: an agent stops at a phase boundary, a
worktree sits overnight, a branch waits on review. A tracker that cannot
survive a `/clear` cannot be what a resumed session reads to find out where it
was.

**Markdown TODO lists** fail on identity and concurrency. A line in a file has
no stable id to cite from a commit message, no typed state, and no dependency
graph, so `bd ready` has no analogue. Worse, the file lives in the repo - which
means every parallel worktree has its own copy on its own branch, and two
agents claiming work would each be editing their private copy of the list. The
claims would not be visible to each other until merge, which is exactly too
late for a lock. A shared coordination surface cannot be a branch-local file.

### The `px-` id is the durable reference

Ids are cited far outside the tracker. They appear in commit `Refs:` trailers,
in ADR prose (ADR-0003 cites `px-35i.*` and `px-tbv.*` throughout), in
`docs/architecture.md`, and in the filenames of every document under
`docs/plans/` and `docs/research/` (`260807-px-phw-conformance-area-label.md`).
That cross-referencing is what turns the tracker from a queue into project
history: given a line of code, `git blame` gives a commit, the commit gives a
`px-` id, and the id gives the bead, its plan, its research, and the ADR that
governed it. It works only because the ids are stable and locally resolvable.

### The multi-audience problem

Predicator is not a private repo. It is a published Hex package, it is the
reference implementation of an instruction set that Ruby and JavaScript
siblings adopt on their own schedule (ADR-0003), and it has at least one
downstream consumer in statifier. So its tracker has more than one audience,
and it carries work whose *execution* happens somewhere else entirely -
`CLAUDE.md` defines an `upstream` bead class precisely for that: beads that
change no file in this repo because the work lands in a sibling or a consumer.

Keeping those beads here is deliberate. They are this project's record of what
it is waiting on, and the alternative - tracking predicator's dependencies in
the repos that happen to be doing the work - means the answer to "why has this
not shipped" lives in a repo the asker does not have. But the cost is real and
should be stated plainly rather than discovered: **an external contributor
arriving through GitHub cannot see any of this.**

### Prior art

statifier's ADR-0007 reached the same conclusion in that repo, and this
decision is downstream of it in the ordinary sense that the practice arrived
here from there. This ADR is not a citation to it. Predicator carries its own
record even where the reasoning overlaps, and everything above is argued in
predicator's terms and is readable without that repo.

## Decision

**All work in this repo is tracked in `bd` (beads). Not GitHub Issues, not
TodoWrite, not markdown TODO lists.** Issues are prefixed `px-`, and the `px-`
id is the durable reference used in commit `Refs:` trailers, in ADR and
architecture prose, and in plan and research filenames.

Four properties are what the decision is actually buying, and a replacement
tracker would have to supply all four:

1. **Local and in-process.** Queries and writes are a subprocess call against
   an embedded database in the repo's own `.beads/`, with no network in the
   path. A worktree with no connectivity can still read its bead and record
   progress.
2. **Structured enough to compute over.** Typed issues, priorities, labels,
   parent/child hierarchy, and typed dependency links, so that `bd ready` and
   the area-label algebra of ADR-0005 are computations rather than readings.
3. **Durable across sessions, worktrees, and machines.** The record outlives
   any one session's context and any one worktree's lifetime.
4. **Reversible for routine writes.** Ordinary tracking is corrected by another
   write and nobody outside has seen it, which is what places it on ADR-0006's
   rung 1.

**Dolt is the sync mechanism.** Bead state is versioned in an embedded Dolt
database and shared through the git remote (`bd dolt pull` / `bd dolt push`),
which is what makes the record durable across machines rather than merely
across sessions on one machine. Publishing is a distinct act from recording,
and it inherits ADR-0006's placement: `bd dolt push` is gated on **the git side
of the same change having already reached `origin`**. The failure that gate
prevents is directional - a published tracker claiming work, or claiming
completion, that no one can find any code for. The reverse skew, commits on
`origin` whose bead state has not been pushed yet, is self-correcting on the
next push and is why `/next-issue` treats its post-claim `bd dolt push` as
best-effort rather than as a precondition.

**`CLAUDE.md` is the enforcement, and it is deliberately a stub.** Its "Beads
issue tracker" section states the rule and defers the command reference and the
session-close protocol to `bd prime`, which the harness injects at session
start. That is on purpose: the command surface belongs to the tool and changes
with it, and a copy of it in `CLAUDE.md` would be a second source of truth that
drifts. This ADR is the reasoning; `CLAUDE.md` is the rule; `bd prime` is the
reference.

**GitHub Issues, if used at all, are an intake surface and not the record.** An
issue filed by an outside contributor is a report to be triaged into a bead; it
is not itself the tracked work, and no skill in `.claude/skills/` reads it.

**The hand-off is a written policy, not automation.** The maintainer triages an
inbound GitHub issue into a bead with `/create-issue`; the GitHub issue stays
open as the reporter's thread and is closed when the bead's PR merges. That is
deliberately a policy rather than an intake skill: inbound volume on a
solo-maintained library does not justify one, and a skill that runs a few times
a year would rot unread between uses - it would be describing a `bd` command
surface and a triage flow that had both moved under it since the last time
anyone looked. A written rule that a human reads at the moment of use cannot go
stale in the same silent way.

### This decision does not move the instruction set

**No ISA change. No opcode is added, removed, renamed, or given different
semantics, and no ISA version is bumped.** This is a governance decision about
where the project's work record lives; it touches no grammar, no compiler
output, no opcode, and no stored artifact. Per ADR-0003 an ISA change owes a
version, a `docs/isa.md` entry, and a migration note where stored artifacts are
affected - none of that is owed here. The only adjacency is bibliographic: ISA
changes are argued in beads and cited by `px-` id from `docs/isa.md` and from
the ADRs, so the tracker is where the *reasoning* behind an ISA move is
findable. That is a property of the record, not of the instruction set.

## Consequences

- **The tracker is invisible to anyone without the tool and the database.** A
  visitor browsing this repo on GitHub sees code, ADRs, plans, and research,
  and sees no issue list at all. Someone who wants to know what is planned or
  in flight cannot find out from the public surface. This is the largest cost
  of the decision and it is accepted, not mitigated: the workflow that the
  tracker serves is the internal one, and the public artifacts of intent are
  `CHANGELOG.md`, the ADRs, and `docs/plans/`.
- **Onboarding requires installing `bd`.** A fresh clone is not enough - a new
  contributor or a new machine needs the tool, and a fresh clone with no
  `.beads/embeddeddolt/` needs `bd bootstrap` before `bd ready` says anything
  useful. Every skill in the workflow assumes the command exists.
- **External contributions arrive on a surface that is not the record.** A
  GitHub issue or PR from outside has to be triaged into a bead by someone with
  the tool, and until that happens it is not visible to `bd ready` and cannot
  be scheduled by `/next-issues`. That hand-off is manual by decision, not by
  omission, and the reporter's thread stays open on GitHub until the bead's PR
  merges so the latency is at least visible to the person who filed it.
- **The reasoning behind a change is split across three places.** Beads carry
  the immediate why and the acceptance criteria, `docs/research/` carries the
  investigation, `docs/plans/` carries the intended sequence, and ADRs carry
  the durable decision. That split is mostly a feature - each has a different
  lifetime - but it means reconstructing a decision can require all four, and
  only three of them are in the repo. When something is worth outliving its
  bead, it belongs in an ADR or in `docs/`, and the bead should say so.
- **A bead is only as good as the acceptance criteria written into it.**
  `/work` seeds a session with nothing but the bead, so a vague description
  produces a vague implementation with no human present to notice. `bd lint`
  and `bd create --validate` exist for this, and the discipline they enforce is
  a real ongoing tax on filing work, paid by whoever files it.
- **Two records now have to be kept from diverging.** Git and the bead database
  are separate stores of the same project's state. The authority table's
  ordering rules (`bd close` only on a merge verified against GitHub,
  `bd dolt push` only after the git side has reached `origin`) exist entirely
  to keep the skew in the harmless direction. That is maintenance the decision
  created.
- **Switching trackers later is a migration, not a configuration change.** The
  `px-` ids are cited from commit trailers, ADR prose, `docs/architecture.md`,
  and filenames under `docs/plans/` and `docs/research/`, none of which can be
  rewritten. A successor tracker would have to preserve the id namespace or
  accept that the historical references become dangling.
- **The four properties in the Decision are the test for any replacement.** A
  proposed alternative is evaluated against local-and-in-process, structured,
  durable, and reversible-for-routine-writes, rather than by re-arguing
  tracker preferences. Changing the tracker supersedes this ADR; adding a field,
  a label vocabulary, or a workflow on top of `bd` does not.
- **Publishing a readable subset of the tracker was considered and rejected.**
  A generated roadmap, or beads mirrored into the repo as text, would address
  the visibility cost directly - and it loses to the same drift objection that
  keeps the `bd` command reference out of `CLAUDE.md`, in a stronger form. That
  reference is written once and re-read by a human who can notice it is wrong;
  a mirror regenerates continuously against a database that changes dozens of
  times per bead, and nothing in the workflow detects that a stale copy has
  been committed. The visibility it would buy is also already partly paid for
  by `CHANGELOG.md` and by merged PR history, both public and both accurate by
  construction rather than by a job having run. Reversing this means
  superseding this ADR, not adding a mirror beside it.
