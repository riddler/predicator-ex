# Architecture Decision Records

| # | Decision | Status |
|---|---|---|
| [0001](0001-keep-the-stack-vm-revise-the-instruction-set.md) | Keep the stack VM; revise the instruction set (ISA v2) | accepted |
| [0002](0002-the-equals-grammar-break.md) | The `=` grammar break (4.0) | accepted |
| [0003](0003-the-elixir-implementation-leads-the-isa.md) | The Elixir implementation leads the ISA | accepted |
| [0004](0004-no-eval-errors-are-values.md) | No eval, ever; errors are values | proposed |
| [0005](0005-worktree-parallelism-and-the-area-label-algebra.md) | Worktree-per-bead parallelism, with area labels as a decidable batching algebra | proposed |
| [0006](0006-irreversibility-places-the-human-gates.md) | The human gate belongs where an action stops being reversible; `mix hex.publish` has no trigger at all | proposed |
| [0007](0007-beads-for-issue-tracking.md) | All work is tracked in `bd` (beads) - not GitHub Issues, not TodoWrite, not markdown TODO lists | proposed |
| [0008](0008-the-quality-gate-and-its-non-editable-config.md) | `mix quality` is the one aggregated gate, and its config is not agent-editable | proposed |

New ADRs: next number, same three-section format (Context, Decision,
Consequences). An ADR is amended by a new ADR that supersedes it, not by
rewriting history; superseded decisions stay visible as the path taken. An ADR
whose *decision* still holds but whose *consequences* have moved is amended in
place by a later ADR that says so at the top and names the sentences it
replaces - ADR-0003 does this to ADR-0001 - and the amended ADR stays accepted.

ADR-0001 opens a 3.6-4.0 arc designed around statifier's six upstream seams.
The remaining decisions from that design - the Context struct, typed undefined,
and the statement layer - get their ADRs as their releases are taken up, not in
advance.
