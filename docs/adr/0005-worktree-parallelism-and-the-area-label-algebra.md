# ADR-0005: Worktree parallelism and the area-label algebra

Status: accepted (2026-08-07)

## Context

Work in this repo is done by agents, several at a time, and the constraint that
shapes everything else is that they cannot share a working tree. Two sessions
editing one checkout serialize on the filesystem: they overwrite each other's
edits, they cannot be on different branches at once, and - the expensive part -
they share one `_build`. An Elixir project's build cache is the thing that makes
a `mix quality` run take seconds instead of minutes, and it is invalidated by
whichever session compiled last. So the second agent in a shared checkout is not
merely slower than the first, it is intermittently red for reasons that have
nothing to do with its own change.

Git worktrees remove that constraint: each one is a real directory with its own
branch, its own `deps/`, its own `_build/`, and its own dialyzer PLT. What they
do not remove is the *other* collision, the one that shows up later. Two
branches cut from the same `origin/main` that both edit `lib/predicator/
parser.ex` do not conflict while they are being worked; they conflict when the
second one rebases, after both are finished and one has landed. Parallelism
bought at the filesystem is paid back at the merge queue unless something
decides, up front, which pairs of jobs are safe to run at the same time.

statifier's ADR-0010 established worktree-per-issue as the unit of parallel
work. That is the ancestor of this decision and this ADR does not re-argue it.
What predicator adds - and what this ADR exists to record - is the second half:
a **label algebra** that turns "which pairs are safe" from a judgment call into
a computation. `/next-issues` (`.claude/skills/next-issues/SKILL.md`) selects a
batch of beads to fan out to; it has to answer that question once per candidate
pair, unattended, without a human in the loop. A rule that needs judgment per
pair is not a rule a skill can execute - it collapses back into the human gate
the fan-out existed to remove.

The vocabulary of labels itself already lives in `CLAUDE.md` ("Worktrees,
skills, and area labels"), which explains the rule clearly and is the file the
skills read. What has never been recorded is *why* the rule has the shape it
has: why disjointness rather than something finer, why one label is exclusive
and the rest are not, and why the labels are allowed to be wrong.

## Decision

**Worktree-per-bead is the unit of parallel work.** One bead, one branch, one
worktree under `../predicator-ex-worktrees/<bead-id>-<slug>` cut from
`origin/main`, one tmux window with a session seeded on that bead. The `bd`
claim is the lock, and it is taken **before the worktree exists**
(`bd update <id> --claim`, then `/new-worktree`). The ordering is deliberate:
claimed-with-no-worktree is a cheap, fully recoverable state, while a worktree
for an unclaimed bead is another agent's collision already in progress. A claim
in the tracker is also a cheaper lock than a branch - it is visible to every
session without a fetch, it costs nothing to release, and it exists before any
filesystem state has been committed to.

**The area-label algebra** governs which claimed beads may run at the same
time. Every bead that changes files in this repo carries at least one `area:`
label naming the part of the tree it touches, and may carry several. Three
rules:

1. **Two beads are batchable iff their area sets are disjoint.** The whole
   point is decidability. `/next-issues` computes a batch by set intersection,
   which a program can do; any formulation that asks "would these two really
   conflict?" requires reading both beads and forming an opinion, which is a
   human gate wearing a rule's clothes. Set disjointness is coarse - it will
   sometimes refuse a pair that would in fact have been fine - and that
   coarseness is the price of being executable unattended.

2. **`area:build` is exclusive: a bead carrying it batches with nothing** and
   lands on `main` alone. It moves `mix.lock` and the gate configuration that
   every other worktree's warmed `_build` and `mix quality` run depend on. The
   failure mode this prevents is not an ordinary merge conflict, which is
   visible and attributable; it is a parallel branch going **red for reasons
   unrelated to its own work** - a dependency it never touched moved under it,
   or the gate it was passing changed shape. That failure is expensive to
   diagnose precisely because the evidence points away from the cause, and it
   is what makes exclusivity worth the serialization it costs. Every other
   label is ordinary and non-exclusive.

3. **Labels are about file collision, not subject matter, and they are
   predictions, deliberately.** Two beads both "about durations" that touch
   disjoint files are batchable; two beads in unrelated subsystems that both
   edit `mix.exs` are not. The label is written when the bead is filed, before
   the work exists, so it cannot be derived from a diff - and it is wanted at
   selection time, which is before any diff exists. The consequence is that a
   label can be wrong, and that is accepted: a branch that ends up touching an
   area it was not labeled with is a **signal that the split the batch was
   built on was wrong**, worth noticing at merge time rather than silently
   accepting.

**A wrong label on a merged bead is noted, not rewritten.** The label's only
operational job is batching, and that job is finished the moment the bead
merges; what survives afterwards is its value as *evidence* that a split was
miscalibrated. Retroactively correcting it destroys exactly that evidence, so
merge-time drift is recorded on the bead - a note saying which areas the branch
actually touched - and the label itself is left standing. This is what
`CLAUDE.md` means by drift being "worth noticing at merge time, not silently
accepting": noticing is the whole of the required response. The one exception is
a change to the **label vocabulary itself**, where the old term no longer means
what it meant when the bead was filed. Relabeling is then migrating a record,
not correcting a mistake, and the bead was never wrong under the vocabulary it
was written against.

**`CLAUDE.md` is the enforcement of this ADR, not a copy of it.** The live
vocabulary - which paths each label covers, and the `upstream` case for beads
that change no files here - lives in `CLAUDE.md`'s "Area labels" section and is
maintained there. This ADR deliberately does not reproduce that table: the
vocabulary changes as the tree grows (see `area:conformance` below), and two
copies of it would diverge. Cite ADR-0005 for the rules and the reasoning; read
`CLAUDE.md` for the current labels.

**`area:api` exists because there is exactly one genuinely cross-cutting
surface.** `lib/predicator.ex` and the error structs under
`lib/predicator/errors/` are where nearly every feature eventually arrives: a
new capability widens the public facade or adds an error type. Folding that
surface into whichever subsystem prompted the change would make almost every
pair of beads collide, since any two features could both need it. Naming it
separately means a bead that adds a function *and* exposes it carries both
labels, which is the correct answer - it does touch both - and beads that stay
inside their subsystem batch freely.

### This decision does not move the instruction set

**No ISA change. No opcode is added, removed, renamed, or given different
semantics, and no ISA version is bumped.** This is a process decision about how
work is scheduled across worktrees; it touches no grammar, no compiler output,
and no stored artifact. Per ADR-0003 an ISA change owes a version, a
`docs/isa.md` entry, and a migration note where stored artifacts are affected -
none of that is owed here.

## Consequences

- **The batching predicate is executable, and `/next-issues` executes it.**
  The skill's verdict table (epic / unlabeled / lands-alone / collides with
  live worktree / free) plus a greedy walk by priority is the algebra applied.
  It is greedy rather than optimal on purpose: a picker solving for the largest
  disjoint batch would prefer three P3s to one P1, which is the wrong trade
  every time.
- **Live worktrees are part of the collision surface, not just the batch being
  formed.** The areas held by branches already in flight constrain a new pick
  exactly as an in-batch collision does. This is what makes the algebra hold
  across sessions rather than only within one fan-out.
- **An unlabeled bead is unschedulable, and that is the label being missing,
  not the skill failing.** `/next-issues` skips it and says so. The one
  exception is `upstream` beads, which change no files in this repo by
  definition and so collide with nothing.
- **A wrong label is falsifiable and gets corrected - `area:conformance` is the
  worked example.** The conformance tree was labeled `area:build` when px-35i.4
  created it, which was right for that branch and wrong for every branch after
  it: `area:build` is exclusive, so routine corpus work serialized the entire
  queue behind itself. The evidence is the two follow-ons, px-q1f and px-1ka,
  which carried `area:build` and between them touched **no file in the
  `area:build` row at all**. Standing the tree up cost one edit to `mix.exs`;
  living with it costs none. `area:conformance` was split out as an ordinary
  non-exclusive label, and the reasoning is recorded in
  `docs/research/260807-px-phw-conformance-area-label.md`. That correction is
  this ADR's proof that the algebra is falsifiable: the rule is coarse, so it
  will misclassify, and the response is to fix the vocabulary rather than to
  make the rule negotiable case by case. Relabeling px-q1f and px-1ka after
  they had merged is the vocabulary exception above, not a counterexample to
  it: both were correctly labeled under the vocabulary that existed when they
  were filed, and the pass migrated a record whose term had changed meaning.
- **Exclusivity does not spread by subject.** A conformance bead that also
  edits `mix.exs` or `coveralls.json` carries **both** labels, and
  `area:build`'s exclusivity re-triggers in full - that bead lands alone. The
  hazard is a property of the file, not of the topic. Widening a subject label
  to absorb such a bead would smuggle a `mix.lock` change into a batch, which
  is the exact failure `area:build` exists to prevent.
- **Adding a label is cheap; changing the rules is not.** New areas are added
  to `CLAUDE.md`'s table as the tree grows, and doing so needs no new ADR - the
  vocabulary is data. Making a second label exclusive, or replacing
  disjointness with a finer test, changes the algebra and supersedes this ADR.
- **The cost is accepted: coarse refusals and serialized build work.** Some
  batchable pairs are refused because they share a label they would not have
  actually collided in, and every `area:build` bead stops the fan-out for its
  duration. Both are the price of a selection rule that runs without a human,
  and both are visible in `/next-issues`' report rather than hidden - the skill
  is required to say what it skipped and why, because "it only took two" reads
  as "there was no more work" otherwise, which is a different and much more
  alarming fact.
- **Rebase conflicts become feedback, not just chores.** When
  `/refresh-worktree` hits a conflict between two branches that were batched as
  disjoint, that is information about the labels that produced the batch. The
  labels are predictions; a conflict is a prediction that failed, and the
  response is to fix the label or the vocabulary.
