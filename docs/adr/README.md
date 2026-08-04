# Architecture Decision Records

| # | Decision | Status |
|---|---|---|
| [0001](0001-keep-the-stack-vm-revise-the-instruction-set.md) | Keep the stack VM; revise the instruction set (ISA v2) | accepted |
| [0002](0002-the-equals-grammar-break.md) | The `=` grammar break (4.0) | accepted |

New ADRs: next number, same three-section format (Context, Decision,
Consequences). An ADR is amended by a new ADR that supersedes it, not by
rewriting history; superseded decisions stay visible as the path taken.

ADR-0001 opens a 3.6-4.0 arc designed around statifier's six upstream seams.
The remaining decisions from that design - the Context struct, typed undefined,
and the statement layer - get their ADRs as their releases are taken up, not in
advance.
