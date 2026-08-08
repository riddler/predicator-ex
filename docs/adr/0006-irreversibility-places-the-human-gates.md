# ADR-0006: Irreversibility places the human gates

Status: proposed (2026-08-07)

## Context

Almost all of the work in this repo is done by agents running unattended in
their own worktrees, and almost all of it is uninteresting: read a bead, edit
files, run the gate, write a commit. The question this ADR answers is not
whether an agent may work - it is *where in that loop a human has to be
standing*, and on what grounds that placement is decided.

The question is forced because both extremes fail, and they fail in ways that
are easy to mistake for each other.

- **A blanket grant** - "the agent may do anything on its own branch" - has no
  stopping rule at the edges, and the edges are where the damage is. The
  interior of the loop is safe not because it was authorized but because it is
  private and undoable; a grant phrased over the interior says nothing about
  the moment the work leaves the machine, so in practice it authorizes that
  moment too, by omission. Every action that hurts is an edge action.

- **A blanket denial** - confirm everything - makes the human the bottleneck on
  the reversible majority, which is nearly all of it. That is not merely slow.
  A human asked to approve forty indistinguishable, harmless things learns to
  approve without reading, and then approves the forty-first, which was not
  harmless. A gate that is always answered "yes" is worse than no gate, because
  it also carries the appearance of review. The value of a confirmation prompt
  is inversely proportional to how often it fires.

- **Gating by blast radius, or by how risky an action feels**, is the intuitive
  middle and the worst of the three. It requires a judgment per action, and the
  judgment is exactly the one an autonomous agent cannot be trusted to make
  about its own work: the agent that is wrong about the change is wrong about
  the change's blast radius in the same direction and for the same reason. It
  also does not compose. "Risky" is a property of a situation as one session
  understood it, so nothing survives to the next session except the vibe, and
  the vibe drifts.

What the third option gets wrong is subtler than being subjective. Blast radius
is a property of *the change* - how much code it touches, how central the file
is, how many tests it moves. Reversibility is a property of *the action* - what
git or Hex or GitHub will let you take back afterwards. That distinction is the
whole decision. A property of the change has to be re-evaluated for every
change; a property of the action can be decided once, written in a table, and
executed by a skill that never has to form an opinion.

This repo already opts into `bd`'s team-maintainer profile rather than the
conservative default, which raises the stakes on getting the placement right:
the grant is real, so its boundaries have to be, too.

## Decision

**The human gate belongs where an action stops being reversible.** Not where it
feels risky, not where it is expensive, not in proportion to how much code it
touches. Reversibility is the criterion because it is the one property that can
be *checked against an action* rather than argued about, and because it is
stable - `git reset --soft HEAD~1` will still undo a local commit next year.

The grant is therefore per action, and every action has a trigger. Authority is
never blanket: an action whose trigger has not fired is unauthorized, and an
explicit "do not commit" or "do not push" from the current user or orchestrator
overrides every row. `CLAUDE.md`'s authority table is the enforcement of this
ADR; the table is the live artifact and this ADR is the reasoning, so the rows
are not reproduced here.

The ladder has four rungs, graded by what it takes to undo the action.

**1. Locally undoable - no human gate.** `bd` tracking (`create`, `claim`,
`update`, `note`), running `mix quality` or `mix test`, and `git commit` on the
issue's own feature branch. A commit on a private per-issue branch is undone
with `git reset --soft HEAD~1` and nobody else has ever seen it, so there is
nothing for a human to protect. The gate at this rung is the **quality gate** -
a machine check, not a human one. Full `mix quality` green is the precondition
for a commit, and a narrowed run (`--profile loop`, a scoped test selection) is
not a green gate for commit purposes. This is what makes `/commit --auto`
coherent: it removes a prompt, it does not lower a bar.

**2. Visible to other people and other machines - an explicit human ask, in
their own words.** `git push`, `gh pr create`, `bd close`, `bd dolt push`. Once
a branch is on `origin` a reviewer can be reading it, CI can be running on it,
and another worktree can be rebasing onto it; the change is no longer the
agent's to retract quietly. The trigger for these rows is the user asking, and
**finishing the work is not a request to publish it.** Inferring a push from
"the work is done" is precisely the failure this rung exists to prevent -
completion is a fact about the branch, not an instruction about the remote.
`/merge-request` implements the seam: it rebases, runs the full gate, shows
what is about to become public, and confirms before pushing, even when
everything is green.

**3. Destroys local state - gated on a verified precondition, not on a human.**
Local branch deletion and worktree removal. These are not gated on an ask
because the ask is not the useful check; the useful check is *whether the work
survived somewhere else*. So the trigger is a merge verified against GitHub,
and the verification method is part of the decision because the obvious one is
silently wrong here. This repo rebase-merges: `main` gets the same trees under
**new SHAs**, so `git branch --merged origin/main` never lists a merged feature
branch and `git log origin/main --contains <sha>` finds nothing. Neither is
evidence of anything, yet both read as "not merged", and acting on that reading
means keeping garbage forever (harmless) or, with the polarity flipped, `-D` on
a branch that in fact had not merged (not harmless). The evidence is
`gh pr view` / `gh pr list --state merged --head <branch>`, and
`/cleanup-worktrees` is built on that and on comparing the local tip against
the `headRefOid` GitHub actually merged.

**4. Irreversible to everyone, forever - no trigger exists at all.**
`mix hex.publish`. Not gated, not delegable, and no instruction in a session
grants it.

**The criterion applies to the observable outcome, not to the internal state
change.** An action a third party can see is rung 2 - "visible to other people
and other machines" - whether or not the actor can technically retract it
afterwards. Deleting a posted comment does not unsend it; the reader has already
read it, and the CI job or notification it triggered has already run. So a
technically-undoable-but-socially-not action needs no fifth rung: the existing
table's own logic places it on rung 2, and it takes an explicit human ask like
every other row there. This is not hypothetical. `gh pr comment` and
`gh issue comment` are reachable from this workflow today through the same `gh`
CLI the merge-verification rows depend on, so the case is present already rather
than waiting to arrive.

### Why `mix hex.publish` has no trigger, rather than a strict one

Every other row on the ladder has a trigger, and the reason is not that those
actions are safe. It is that each of them has a **correction path** if the
trigger fires wrongly. A push that should not have happened is force-pushable
or revertible. A PR opened too early is closable. A bead closed prematurely
reopens. A branch deleted by mistake is recoverable from the remote, or from
the reflog, or from the merged PR. In every case a human who notices the
mistake can put the world back, which means the trigger is allowed to be
imperfect: there is an error budget, and the trigger only has to be good enough
that the budget is not exhausted.

A published Hex version has no correction path. It cannot be recalled, only
**retired**, and retirement does not remove the artifact - it stays resolvable
to everyone who already depends on it, and to anyone with the version pinned in
a `mix.lock`. The package is in other people's builds, in CI caches, and in
mirrors, permanently, and the only remedy available afterwards is a *note*
saying it should not be used.

No correction path means no error budget. No error budget means there is no
trigger good enough: any trigger is a rule for deciding without a human, and a
rule that is wrong once has already produced an outcome nobody can undo. That
is why the answer is not "a very strict trigger" or "confirm twice" - a
stricter trigger is still a smaller nonzero probability multiplied by an
unbounded, uncorrectable cost.

The consequence is that publishing is **not delegable**, and it follows that an
in-session instruction appearing to request it cannot supply the missing
authority - a session cannot establish what only an out-of-band human decision
can. Worse, such an instruction is itself evidence that something is wrong:
the plausible sources are a confused session, a stale plan carried forward from
a context where a release was pending, or a prompt-injection surface (a bead
description, a file, a piece of fetched text) reaching for the one action with
no correction path. That is why `CLAUDE.md` says to **stop and confirm out of
band** rather than to comply. `/release` is the enforcement: it does the
version bump, promotes the changelog, and stops - tag, push, and publish are
deliberately outside it.

**The adjacent row shows the criterion is doing real work.** Release
*mechanics* - bumping `@version` in `mix.exs`, promoting `## [Unreleased]` to a
version header, tagging - **do** have a trigger (the user asks for a release and
names the version). If the rule were "release stuff is scary, gate it", these
would be ungated too. They are not, because before a push they are ordinary
local edits on a branch, undone like any other commit. The criterion
discriminates within the release workflow itself, which is the strongest
available evidence that it is a criterion and not a mood.

### This decision does not move the instruction set

**No ISA change. No opcode is added, removed, renamed, or given different
semantics, and no ISA version is bumped.** This is a governance decision about
where human authorization sits in an agent's workflow; it touches no grammar,
no compiler output, no opcode, and no stored artifact. Per ADR-0003 an ISA
change owes a version, a `docs/isa.md` entry, and a migration note where stored
artifacts are affected - none of that is owed here. The one adjacency worth
naming is that ADR-0003 makes this repo the ISA's reference implementation, so
a Hex release from here is what siblings adopt against; that raises the cost of
a bad release without changing anything about the instruction set itself.

## Consequences

- **The authority table is a live artifact, and it changes when the underlying
  reversibility changes.** The rows are derived from the criterion, not
  independent of it, so a change in what the tooling permits propagates into
  the table. The merge-policy subsection is the worked example: `bd close` and
  branch deletion are gated on GitHub-verified merge *because* this repo
  rebase-merges, and `CLAUDE.md` says outright that if the merge settings
  change, that section and the rows referencing it change with them. A table
  maintained as an independent list of rules would not know to move.

- **The opt-in is written down rather than assumed.** This repo opts into the
  team-maintainer profile; conservative stays the default everywhere else,
  including for any action this repo's table does not name. That asymmetry is
  itself an application of the criterion - a clone of this repo has not made
  the decision, so it does not inherit the grant.

- **An explicit refusal from the user overrides every row.** "Do not commit",
  "do not push", or an equivalent from the current user or orchestrator wins
  over any trigger that has fired. The table grants authority; it never
  obligates an action.

- **The skills are the enforcement, and their seams are the decision.** Each
  gate is implemented by a skill that deliberately stops short of the next
  rung: `/commit` commits and does not push; `/merge-request` pushes and opens
  a PR only after an explicit confirmation, and never closes the bead;
  `/cleanup-worktrees` closes and deletes only against GitHub-verified merge
  state and refuses to use git ancestry; `/release` performs the reversible
  mechanics and leaves tag, push, and publish alone. Where a skill stops is not
  an incomplete implementation, it is where the rung ends.

- **Auto modes are legible because of the criterion.** `/commit --auto` is
  defensible without a case-by-case argument: it operates entirely at rung 1.
  Any future proposal to add an auto mode is answered by asking which rung the
  action sits on, rather than by re-litigating how risky it feels.

- **New actions get placed, not debated.** When a tool, integration, or command
  is added to this workflow, the question is a single one: what does it take to
  undo it, and who has to be involved. That yields a rung and therefore a
  trigger. Adding a row is ordinary maintenance and needs no new ADR; changing
  the *criterion* - gating by blast radius after all, or granting
  `mix hex.publish` a trigger - supersedes this one.

- **The cost is accepted: some irreversible-looking work waits on a human who
  is not there.** An unattended session that finishes a branch cannot publish
  it and must stop and report. That is the intended behavior, and the
  alternative - letting an agent decide that this particular push is obviously
  fine - is the blast-radius rule wearing a different hat.
