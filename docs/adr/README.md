# Architecture Decision Records

| # | Decision | Status |
|---|---|---|
| [0001](0001-keep-the-stack-vm-revise-the-instruction-set.md) | Keep the stack VM; revise the instruction set (ISA v2) | accepted |
| [0002](0002-the-equals-grammar-break.md) | The `=` grammar break (4.0) | accepted |
| [0003](0003-the-elixir-implementation-leads-the-isa.md) | The Elixir implementation leads the ISA | accepted |
| [0004](0004-no-eval-errors-are-values.md) | No eval, ever; errors are values | accepted |
| [0005](0005-worktree-parallelism-and-the-area-label-algebra.md) | Worktree-per-bead parallelism, with area labels as a decidable batching algebra | accepted |
| [0006](0006-irreversibility-places-the-human-gates.md) | The human gate belongs where an action stops being reversible; `mix hex.publish` has no trigger at all | accepted |
| [0007](0007-beads-for-issue-tracking.md) | All work is tracked in `bd` (beads) - not GitHub Issues, not TodoWrite, not markdown TODO lists | accepted |
| [0008](0008-the-quality-gate-and-its-non-editable-config.md) | `mix quality` is the one aggregated gate, and its config is not agent-editable | accepted |
| [0009](0009-the-compiled-envelope-carries-the-position-table.md) | The compiled envelope carries the position table; `compile/1` stays a bare list | accepted |
| [0010](0010-tracker-authority-and-the-mirror-obligation.md) | Tracker authority follows the artifact; mirrors pull, and monorepo work is held by an `external-ref` | proposed |

New ADRs: next number, same three-section format (Context, Decision,
Consequences). An ADR is amended by a new ADR that supersedes it, not by
rewriting history; superseded decisions stay visible as the path taken. An ADR
whose *decision* still holds but whose *consequences* have moved is amended in
place by a later ADR that says so at the top and names the sentences it
replaces - ADR-0003 does this to ADR-0001 - and the amended ADR stays accepted.

**When a decision earns an ADR.** The test is whether someone will later ask
"why is it like this" and find that the rule alone does not answer. A rule that
explains itself needs no ADR, and writing one anyway adds a file and a
maintenance obligation for nothing. The zero-runtime-dependencies policy was
weighed on that test and declined: `px-tbv.6` and `README.md` already carry both
the fact and the reason for it.

Three corollaries, settled by `px-4lz`:

- **Reasoning that overlaps a sibling repo's ADR still gets its own record
  here.** Answering by cross-repo citation was considered as a general policy
  and rejected - a reader of this repo should not need a checkout of another
  one to learn why this one is built the way it is. ADR-0007 and ADR-0008
  overlap statifier's governance ADRs and are written out in full regardless,
  crediting the prior art in a sentence.
- **A decision that is a corollary of another belongs inside it**, as a
  consequence rather than beside it at its own number. Errors-are-values is
  part of ADR-0004 on those grounds instead of an ADR of its own.
- **A call too narrow for its own ADR goes to `docs/research/`**, named after
  the bead that prompted it. The `area:conformance` label argument
  (`260807-px-phw-conformance-area-label.md`) is the model.

**Status.** An ADR is `proposed` while it is drafted and `accepted` once the
maintainer confirms it records the decision as actually made. An agent may
draft; only the maintainer accepts, because an ADR reconstructed from a
surviving rule is a guess carrying a document's authority. ADR-0004 through
ADR-0008 were drafted proposed under `px-4lz` and accepted on review.

ADR-0001 opens a 3.6-4.0 arc designed around statifier's six upstream seams.
The remaining decisions from that design - the Context struct, typed undefined,
and the statement layer - get their ADRs as their releases are taken up, not in
advance.
