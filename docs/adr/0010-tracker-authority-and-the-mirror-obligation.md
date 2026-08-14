# ADR-0010: Tracker authority follows the artifact, and mirrors pull

Status: accepted (2026-08-14) - drafted proposed 2026-08-08; accepted once
statifier-ex adopted the same rule in its ADR-0025

## Context

Three repositories share one language and have three different answers to the
question "where is the work recorded".

| Repository | Tracker | Role |
|---|---|---|
| `riddler/predicator-ex` | `bd`, `px-` prefix | the reference implementation (ADR-0003) |
| `riddler/statifier-ex` | `bd`, `st-` prefix | a downstream consumer, and the source of the upstream seams |
| `riddler/predicator` | none | the Ruby and JavaScript siblings (`impl/rb`, `impl/ts`) |

ADR-0007 settled that this repo's work lives in `bd` and named the cost it
accepted: the tracker is invisible from outside, and it deliberately carries
`upstream` beads whose execution happens somewhere else. What ADR-0007 did not
settle is what happens when the same piece of work is recorded in two of these
places at once, or in a place with no tracker at all. That gap has been filled
by imitation, and the imitation has drifted.

### What the convention actually is

The practice in use is a `mirrors: <id>` line as the first line of a bead's
description, on both halves of a pair, plus dated reconciliation notes written
by hand. `px-tbv` says `mirrors: st2-bfq`; `st-bfq` says `mirrors: px-tbv`.
It works. `st-bfq`'s 2026-08-06 note is an accurate reading of `px-tbv` as it
stood that day, down to which children had landed and which the consumer was
actually blocked on, and `st-t3f`'s notes carry the error semantics that came
back the other way.

But nothing anywhere says who wrote those notes, who owed them, or what would
have been wrong if they had never been written. Two failures follow from that,
and both are already visible.

**The ids rot.** statifier renamed its prefix from `st2-` to `st-`. Every
mirrored body written before the rename still says `st2-`, in both repos.
`st-t3f`'s own note has to apologize for it inline - "(The note above says
st2-2pj; the prefix is now st-.)" - which is a tracker telling its reader that
its own cross-references do not resolve. In this repo the surviving cases are
`px-tbv`, `px-tbv.2`, and `px-tbv.5`, plus a long tail in closed beads.

**Reconciliation has no owner and no trigger.** A note is a read of another
repo's tracker at a moment in time. It is correct when written and decays
silently afterwards. Because nothing distinguishes "this note is old" from
"this note is wrong", a reader has no way to know whether the note in front of
them can be acted on, and a writer has no way to know whether they are late.

### The monorepo is the sharper problem

`px-35i.6` and `px-35i.7` are the beads that carry the cross-language claim at
the centre of ADR-0003 - ISA v2 in the Ruby and JavaScript siblings - and they
are the two beads with no mechanism at all behind them. Both say the same
thing: "Coordination is GitHub issues on riddler/predicator, which has no bd
tracker - opening them needs a human." There is no id to mirror, so the
convention above does not apply, and the bead's only handle on the work is a
sentence of prose.

### What `bd` actually supports

The bead that prompted this ADR guessed that `--external-ref` exists "for
exactly this". It does exist, and it is narrower than the guess. Verified
against the `bd` in use on 2026-08-08:

- `--external-ref <string>` is accepted by both `bd create` and `bd update`.
  The value is free text; the help text's examples are `gh-9`, `jira-ABC`, and
  a Linear URL. Nothing validates or parses it.
- `bd show` renders it as an `External:` line in the header block, and
  `bd show --json` exposes it as `external_ref`.
- It is **single-valued**. One bead, one external ref.
- It is **not searchable and not filterable**. `bd list --json` does not
  include the field at all, `bd list` has no flag for it, and `bd search` does
  not index it - a search for the exact stored value returns nothing.

That last point is what decides how the field can be used. `external_ref` is a
handle a reader follows once they already have the bead. It is not an index,
and it cannot answer "which beads point at this issue". The `mirrors:` line in
the description, by contrast, is reachable with `bd search --desc-contains`,
and it can name more than one id - `px-8um` mirrors both `st-u41` and `st-dxp`.
The two mechanisms are not substitutes, and neither one replaces the other.

## Decision

Three rules, one per question.

### 1. Authority follows the artifact the decision changes

**A decision is owned by the repository that owns the artifact it changes, and
the bead in that repository is the authoritative record of it.** Where two
trackers disagree about a shared decision, the one on the owning side is
correct by construction and the other is stale.

For the language, the grammar, the instruction set, the compiled format, the
conformance corpus, and predicator's own release schedule, that repository is
this one. ADR-0003 already says so in substance - the ISA moves when this
library needs it to, and sibling parity is a downstream obligation rather than
an upstream constraint - and `docs/isa.md` restates it as the authority claim
for the spec. This ADR does not re-derive that; it extends it from the ISA to
the *tracker*, which is the part ADR-0003 left implicit.

The rule is deliberately not "predicator always wins". Authority is per
artifact, so it can point the other way in the same pair of beads. How
statifier consumes a predicator feature - the SCXML mapping, which corpus tests
join the ratchet, when statifier bumps its `~>` pin - is statifier's artifact
and statifier's bead is authoritative for it, even when the pair exists because
of a change made here. `st-t3f` is the model: the error semantics of
`execute/2` are predicator's call and were settled in `px-h66`, while what the
converter does with the third tuple element is statifier's call and is settled
in `st-t3f`.

A requirement discovered on the consuming side is not thereby owned by it. It
is raised as a bead here, decided here, and mirrored back - which is what
`px-h66` was.

### 2. Mirrors pull; nobody pushes

**A `mirrors:` note is a dated snapshot, and being stale is its normal state.
The obligation to refresh it belongs to the side about to act on it, at the
moment it acts.**

Concretely:

- Both halves of a pair carry `mirrors: <id>` as the first line of the
  description. This ratifies the existing convention rather than replacing it,
  and it stays in the description - not in `external_ref` - because it must be
  multi-valued and findable with `bd search --desc-contains`, and
  `external_ref` is neither.
- A reconciliation note is dated and says what it read:
  `2026-08-06 upstream status: ...`. `st-bfq`'s is the model.
- **Age alone is never a defect.** A note written three weeks ago and never
  touched is doing exactly what it was written to do. Reporting it as rot, or
  sweeping the trackers to refresh notes nobody is using, is work for nothing.
- **A note becomes a defect the moment someone acts on it without refreshing
  it** - schedules the bead, claims it, plans against it, adds or drops a
  dependency on it, or cites its status anywhere. Refresh first, then act. The
  refresh is a read of the other tracker and a new dated note; the old note is
  left above it as history, in the same way an ADR is amended rather than
  rewritten.
- **The authority side owes the mirror nothing on a schedule.** It does not
  chase, notify, or reconcile outward when its bead moves.

The asymmetry is the whole point and it is not politeness. The two databases
are local, embedded, and offline (ADR-0007), synchronized through git remotes
on two independent schedules. A push obligation across them is unenforceable:
nothing can detect that it was not performed, so it would be violated silently
and constantly, and a rule that is silently violated is worse than no rule
because it makes the notes look more trustworthy than they are. A pull
obligation is checkable by exactly the agent that is about to rely on it, at
the one moment the answer matters, and it is enforceable because that agent has
both repos' trackers available to it.

**Ids are the exception, and they are a defect immediately.** A `mirrors:` line
naming an id that does not resolve is not stale, it is broken: it makes the
pull-at-use obligation unperformable, since there is nothing to go and read.
Whoever notices it fixes it, in whichever repo they are standing in, with one
`bd update`. This is ADR-0006 rung 1 work - a local, reversible tracking write
authorized at any time - so noticing and fixing are the same act.

Closed beads are out of scope. A closed bead is history, its `mirrors:` line
will never be pulled on, and rewriting it edits the record of what was
believed at the time.

### 3. Monorepo work is held by a bead here plus an `external-ref`

The Ruby and JavaScript siblings have no tracker, so there is no id to mirror
and rule 2 does not reach them. **Work in `riddler/predicator` is recorded as
an `upstream` bead in this repo, and its handle on the monorepo is the GitHub
issue, carried in `bd`'s `external_ref` field.**

- The bead stays here. ADR-0007 already settled that: an `upstream` bead is
  this project's record of what it is waiting on, and moving it to the repo
  doing the work puts the answer to "why has this not shipped" somewhere the
  asker does not have. The monorepo has no `bd` to move it to in any case.
- `bd update <id> --external-ref <url>` carries the GitHub issue once it
  exists. `bd show` surfaces it as `External:`, which is the whole job -
  a reader who has the bead can reach the issue in one step.
- **`external_ref` is a handle, not an index, and the bead's description still
  carries the prose.** Because the field is single-valued and unsearchable, it
  gets the one primary issue; anything more - additional issues, the paths in
  `impl/rb` and `impl/ts`, which conformance surface leads - stays in the
  description and notes where `bd search --desc-contains` can find it, as it
  already does in `px-35i.6` and `px-35i.7`.
- **An empty `external_ref` is meaningful, not missing.** Opening the GitHub
  issue is visible to other people and other machines, which is ADR-0006's
  rung 2: it takes an explicit human ask and no agent may do it. So a bead may
  legitimately sit with the field empty for a long time, and empty is the
  accurate statement that the issue has not been raised yet - not a gap to be
  filled in with a plausible-looking value.
- No further mechanism is built. GitHub Issues on the monorepo are an intake
  and coordination surface, exactly as ADR-0007 describes them for this repo:
  the issue is where the conversation with the sibling implementer happens, and
  the bead here is the record.

### This decision does not move the instruction set

**No ISA change. The ISA version stays at v3.** No opcode is added, removed,
renamed, or given different semantics; no grammar, compiler output, or stored
artifact is touched. Per ADR-0003 an ISA change owes a version, a `docs/isa.md`
entry, a corpus tier assignment, and a migration note where stored artifacts
are affected, and none of that is owed here.

The adjacency is worth naming precisely, because this ADR is *about* the
cross-repo relationship that ADR-0003 governs. ADR-0003 decides who may move
the ISA and what they owe when they do. This ADR decides where the resulting
work is written down and how the three trackers refer to each other. A sibling
that is behind on the ISA is unaffected by anything here, and `px-35i.6` and
`px-35i.7` gaining an `external_ref` changes nothing about what ISA v2 requires
of them.

## Consequences

- **`px-tbv`, `px-tbv.2`, and `px-tbv.5` are corrected from `st2-` to `st-`**
  under rule 2's id exception. Those are the live beads in this repo whose
  `mirrors:` line does not resolve. The rest of their descriptions are
  untouched.
- **The `st2-` references in closed beads are left, deliberately.** `px-hc3*`,
  `px-8um*`, `px-e3g*`, `px-tbv.1/.3/.4`, and `px-198` all carry them and all
  are closed. They will never be pulled on, and rewriting them would edit the
  record of what was true when the work was done. Anyone reading one needs to
  know only that statifier's prefix changed from `st2-` to `st-`, which this
  ADR now says in one place.
- **statifier-ex owed a reciprocal line, and now carries one.** When this ADR
  was drafted its `CLAUDE.md` said nothing about cross-repo coordination at
  all, its own `st2-` references were live, and the decision was only
  half-recorded - work in another repository, out of scope for that branch by
  ADR-0005's worktree rule. It was done there instead, under `st-c07`
  (`mirrors: px-xsk`), on 2026-08-14: statifier-ex ADR-0025 adopts rules 1 and
  2 verbatim, adopts rule 3 with a narrowing that does not reach this repo,
  and its `CLAUDE.md` carries the enforcement table pointing here. Its own
  live `st2-` ids were corrected under rule 2's id exception in the same
  change, and the ones this bullet named (`st-bfq`, `st-t3f`) had closed by
  then and were left under the closed-bead exclusion. That is what moved this
  ADR from proposed to accepted; the reciprocal read is recorded there rather
  than duplicated here.
- **The `mirrors:` line is now load-bearing, so it has to be written.** A pair
  created without one on both halves is a pair with no pull path, and rule 2
  has nothing to operate on. `/create-issue` is where that would be enforced if
  it turns out to need enforcing; this ADR does not add it, on the same grounds
  ADR-0007 declined an intake skill - a hand-off that happens a few times a
  release does not justify automation that would rot between uses.
- **"Refresh before acting" is a real cost on the consuming side.** Every
  scheduling decision that leans on a mirrored bead now begins with a read of
  the other repo's tracker. That is the price of not having a push obligation,
  and it is paid by whoever is about to benefit from the answer, which is the
  correct person to charge.
- **Nothing detects a violation of rule 2.** An agent that acts on a stale note
  without refreshing produces a plan built on last month's status, and no gate
  catches it. The mitigation is that the failure is loud when it lands -
  a dependency on a bead that closed, a claim on work already done - rather
  than silent, which is what the push version would have been.
- **A single bead cannot hold two external refs.** If sibling work ever needs
  two GitHub issues under one bead, either it splits into two beads or the
  second issue lives in the description. Splitting is usually right, since
  `px-35i.6` and `px-35i.7` are already split by implementation language.
- **Authority-follows-the-artifact has to be applied, not looked up.** There is
  no table of which repo owns which decision, and this ADR deliberately does
  not write one - it would go stale exactly as the sibling support matrix
  ADR-0003 declined would have. The question to ask is which repository's files
  change if the decision goes the other way.
- Reversing any of this - a push obligation, a mirror registry, a shared
  tracker across the three repos - means superseding this ADR rather than
  adding a mechanism beside it.

## Open questions

- ~~**Does statifier-ex adopt the same rule, or a different one?**~~ Answered
  2026-08-14, and answering it is what allowed this ADR to be accepted. The
  decision above assumed statifier adopts this rule and points here, which is
  what makes rule 2 symmetric; nothing in this repo could ask. statifier-ex
  ADR-0025 adopts it - same obligation, same direction, verified performable
  from that side rather than assumed - so this ADR is made whole rather than
  superseded. Rule 2's symmetry is no longer an assumption. If either repo
  later changes the obligation, the two records move together.
- **Should `px-35i.6` and `px-35i.7` be backfilled with an `external_ref`
  now?** They cannot be: no GitHub issue exists on `riddler/predicator` for
  either, and opening one is a human act under ADR-0006. Their empty fields are
  correct today under rule 3, and the backfill happens when the issues are
  raised.
- **Does the `mirrors:` line want a second form for the monorepo?** Rule 3
  gives monorepo work an `external_ref` and no `mirrors:` line, on the grounds
  that there is no id on the other side. If the monorepo ever grows a tracker,
  rule 2 applies to it unchanged and rule 3 becomes the special case for
  trackerless repositories generally.
