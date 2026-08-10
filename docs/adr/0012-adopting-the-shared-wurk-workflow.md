# ADR-0012: Adopting the shared `wurk` workflow

Status: accepted (2026-08-10)

## Context

This repo's development loop - file a bead, stand up a worktree, research,
plan, implement, commit, open a PR, clean up - was implemented three times: in
this repo's `.claude/skills/` and `.claude/agents/`, in statifier-ex's, and
(more loosely) in the `riddler/predicator` monorepo's own conventions. The
triplication was not cosmetic. `predicator-ex` and `statifier-ex` share one
maintainer and nearly identical workflow shapes - worktree-per-bead, an area-
label batching algebra, a rebase-merge policy, the same reversibility ladder -
and every rule captured in one repo's skill had to be remembered and re-applied
by hand in the other's. A fix to the worktree-warming step, or a clarification
to the commit-message format, landed in one tree and had to be separately
noticed, ported, and re-verified in the other. Nothing enforced that they
stayed in sync, and nothing would have noticed if they had not.

`wurk` extracts the shape both repos already had into a shared skill set,
installed once, globally, at `~/.claude/skills/wurk:*`, and driven per-project
by a `.claude/wurk.json` manifest plus optional `.claude/wurk/*.md` extension
files. statifier-ex adopted it first and recorded the move in its own
ADR-0016 (with the judged-surface follow-up in ADR-0017). This repo is the
second consumer, and the harder proof: predicator-ex's gate has no
`mix gate.verify` attestation, uses a different PLT location, and edits
`CHANGELOG.md` directly instead of statifier's changelog-fragment workflow, so
adopting it here is what actually shows the manifest generalizes rather than
merely re-describing statifier in JSON. The mechanical work - writing the
manifest, writing the extension files, deleting the old skills and agents, and
the sweep this ADR's own commit finishes - is tracked in `px-ttt` (upstream:
wurk `wu-4tq`).

Three of this repo's own ADRs are directly implicated by the move, and would
otherwise silently drift out of sync with what the tree actually does:

- **ADR-0005** (worktree parallelism and the area-label algebra). The
  batching computation it describes moved from `/new-worktree` and
  `/next-issues` to `/wurk:branch` and `/wurk:next`, with the label vocabulary
  itself now also declared in `.claude/wurk.json`'s `beads.areas` alongside
  `CLAUDE.md`'s table.
- **ADR-0006** (irreversibility places the human gates). The reversibility
  ladder and its triggers are unchanged, but they are now enforced by skills
  this repo does not own the source of.
- **ADR-0008** (the quality gate and its non-editable config). The gate
  itself - `mix quality`, `.quality.exs`, `.credo.exs`, `coveralls.json` - is
  untouched. What changed is who runs it: `wurk:commit` and `wurk:implement`
  invoke it the same way the retired `/commit` and `/implement-plan` did, and
  the `permissions.deny` block that protects the three gate-config files is
  the one piece of enforcement this ADR keeps entirely local (see Decision).

None of the three needs its decision revisited, and this ADR does not
re-argue any of them - it cites them, records that the machinery they
describe now lives partly outside this tree, and points a future reader
"where did the skill that used to be here go" at this document instead of
leaving them to discover the answer from a missing directory.

## Decision

**This repo consumes the `wurk:*` skills globally rather than maintaining its
own copies, and configures their generic behavior through
`.claude/wurk.json` and `.claude/wurk/*.md`.** `.claude/skills/` (14 skills)
and `.claude/agents/` (6 agents) are deleted; the equivalent behavior is
`~/.claude/skills/wurk:*` and the globally installed `wurk-*` research
agents (`wurk-codebase-locator`, `wurk-codebase-analyzer`,
`wurk-codebase-pattern-finder`, `wurk-docs-locator`, `wurk-docs-analyzer`,
`wurk-web-search-researcher`).

**Extensions add; they never override.** `.claude/wurk/plan.md`,
`iterate.md`, `research.md`, `work.md`, `commit.md`, `release.md`,
`implement.md`, `mr.md`, `issue.md`, `branch.md`, and `next.md` each carry
content a generic skill has no way to know - the ISA-versioning triad, the
corpus-regeneration discipline, the `area:conformance`/`area:build`
disambiguation, the no-`proposed`-status ADR rule, and so on - and none of
them restates or contradicts the generic skill it extends. If a generic
skill's *behavior* needs to differ here, the fix is a manifest field added
upstream in `wurk`, never a forked copy of the skill.

**What stays local, deliberately, and why:**

- **The ADR-0008 deny rules.** `.claude/settings.json`'s `permissions.deny`
  block on `.quality.exs`, `.credo.exs`, and `coveralls.json` has no wurk
  equivalent and is not something the manifest expresses - it is a Claude
  Code permission, not a workflow parameter. It is kept verbatim, and it is
  this repo's own contribution back to the pattern: `wurk:kit`'s
  `REFERENCE.md` now recommends this exact block to every consumer on the
  strength of this repo having written it first.
- **The `.claude/wurk/*.md` extensions themselves.** They are how a shared
  skill set stays shared without becoming generic to the point of uselessness
  - project-specific knowledge lives beside the project, not forked into the
  skill.
- **`.claude/wurk.json`, the manifest.** It is this repo's own description of
  itself - its area labels, its gate commands, its commit and changelog
  conventions, its release recipe - read by every `wurk:*` skill but authored
  and owned here.
- **`CLAUDE.md`'s authority table (ADR-0006).** `wurk` defers to it and never
  widens it. A `wurk:*` skill's own auto-mode or `--loop` behavior operates
  strictly inside the rungs that table already grants; adopting `wurk`
  changes who implements a gate's enforcement, not what the gate permits.

## Consequences

- **Old slash names stop resolving, with no shims.** `/commit`, `/work`,
  `/next-issue`, `/next-issues`, `/new-worktree`, `/create-plan`,
  `/iterate-plan`, `/implement-plan`, `/research-codebase`,
  `/merge-request`, `/release`, `/cleanup-worktrees`, `/refresh-worktree`, and
  `/create-issue` are gone from this repo entirely; a session or a seeded tmux
  window that types one gets nothing. `/next-issue` and `/next-issues`
  collapse into a single `/wurk:next`, whose `n` argument defaults to 1 in
  place of the old two-skill split.
- **A behavior change is now an upstream change, not a fork.** If this
  repo needs a `wurk:*` skill to do something its generic form does not, the
  fix is a new manifest field (`lib/manifest.rb` and `docs/manifest.md` in
  `wurk`, one commit) or a new extension file - never a private copy of the
  skill diverging from the shared one. The `.claude/wurk/` files this ADR
  names are the full extent of this repo's legitimate divergence.
- **One knowing regression, owed upstream.** `/wurk:next` claims a bead with a
  select-then-claim window and a `bd_claim_failed` fallback, in place of the
  old `/next-issue`'s atomic `bd ready --claim --json`. That is a real,
  understood widening of the claim race between two agents picking work at
  the same moment, accepted rather than fixed here because the fix belongs in
  `wurk` itself, not in a per-consumer patch. It is filed there as
  `wu-z6n`.
- **This repo's ADRs describing the old skills are left as history, not
  rewritten.** ADR-0005, ADR-0006, and ADR-0008 cite `/next-issues`,
  `/new-worktree`, `/commit`, `/merge-request`, `/cleanup-worktrees`, and
  `/release` by their old names throughout - those sentences describe the
  decision as it stood on the date each ADR was accepted, and rewriting them
  to the new names would misrepresent what was actually decided then in
  exchange for a cosmetic consistency this ADR already supplies going
  forward. A reader who lands on one of those ADRs and wants the current
  command name for a skill it mentions is pointed here.
- **Reversing this ADR means going back to forked copies.** Restoring
  `.claude/skills/` and `.claude/agents/` and dropping `.claude/wurk.json`
  would supersede this decision; adding a new manifest field, extension file,
  or `wurk:*` skill does not, and is the expected shape of ongoing change.
