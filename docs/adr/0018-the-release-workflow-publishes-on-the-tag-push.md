# ADR-0018: The release workflow publishes on the tag push

Status: accepted (2026-10-10, predicator 9.4.3; proposed 2026-10-04)

Supersedes the publish sentences of
[ADR-0006](0006-irreversibility-places-the-human-gates.md), and only those. It
is the successor ADR-0006 itself names: its Consequences bullet **"New actions
get placed, not debated."** ends "changing the *criterion* - gating by blast
radius after all, or granting `mix hex.publish` a trigger - supersedes this
one." ADR-0006's criterion - the human gate belongs where an action stops
being reversible - and its first three rungs stand, and no line of ADR-0006 is
edited. The sentences this ADR replaces:

- The Decision's fourth rung: "**4. Irreversible to everyone, forever - no
  trigger exists at all.** `mix hex.publish`. Not gated, not delegable, and no
  instruction in a session grants it."
- The Decision's section "Why `mix hex.publish` has no trigger, rather than a
  strict one", in its conclusions: "No correction path means no error budget.
  No error budget means there is no trigger good enough", and "The
  consequence is that publishing is **not delegable**". Its account of why an
  in-session instruction to publish is evidence that something is wrong
  stands, and is why the publish still never runs in a session.
- The same section's "A published Hex version has no correction path. It
  cannot be recalled, only **retired**", in so far as it denies the window
  Hex leaves: a new version can be reverted or replaced within one hour (the
  Decision below). Its account of what retirement leaves behind stands.
- The 2026-09-29 Note's two publish sentences: "The publish - `mix
  hex.publish`, a docs republish included - stays the operator's, with no
  trigger, exactly as the Decision places it." and "`mix hex.publish` is
  still the one action with no trigger."

## Context

Every release step but one is already automation's. On a release bead the
operator has named, an agent bumps `@version` and promotes the changelog; once
that prep is merged to `origin/main`, the conductor or the session that owns
the release bead tags the merged commit and pushes the tag (`CLAUDE.md`,
**Release preps**). The publish was the one step a person ran by hand, after
the tag, from their own machine.

ADR-0006 gave `mix hex.publish` no trigger because any trigger is a rule
deciding without a human, and a rule that is wrong once produces an outcome
nobody can undo. The threat it named was a session reaching for the publish:
a confused session, a stale plan, or text injected into a bead or a file.

A trigger that no session evaluates answers that threat differently. By the
time a version tag exists, every human gate before it has already passed: the
commit reached the default branch through a reviewed, merged pull request, and
the version in it is the one a release prep the operator named put there. What
is left to decide is mechanical - is this the commit, is this the version, is
the gate green - and a workflow checks that more reliably than a person
re-reading it at a terminal. Hex's own rules also leave a short correction
window that ADR-0006 did not count: a new version of an existing package can
be reverted or replaced within one hour of its publication (24 hours for a new
package; `mix help hex.publish`, "Reverting a package").

## Decision

**The release workflow publishes on the tag push, and no agent or session ever
runs `mix hex.publish`.** Moving the publish to the tag push was ruled by the
operator, 2026-10-04.

`.github/workflows/release.yml` runs on a push of a tag matching `v*.*.*` and
on nothing else: no branch push, no pull request, no manual dispatch. It
publishes to Hex (the `predicator` package) only when three things hold at the
tagged commit, each checked before any toolchain is installed or the gate is
run:

1. **The tagged commit is on the default branch.** The branch is read from the
   push event (`github.event.repository.default_branch`), never written into
   the file, and the commit must be an ancestor of that branch's head
   (`git merge-base --is-ancestor`).
2. **The tag names the version.** The tag without its leading `v` equals
   `@version` in `mix.exs` at the tagged commit.
3. **The full gate is green.** The workflow provisions the toolchain exactly as
   `ci.yml` does and runs the `gate.full` command from `.claude/wurk.json`, as
   CI runs it; a red gate publishes nothing.

A fourth check runs with the first two: when Hex already shows the version,
the run stops and reports it, so a version is never published twice and a
re-run of a run that did publish says so. Running the gate inside the
workflow rather than reading CI's result, reading the branch from the event,
reading the version from `mix.exs` at the tag, copying the toolchain from
`ci.yml`, and giving the workflow no manual dispatch were decided by the
conductor under a standing consent, 2026-10-03.

**The key.** The publish step authenticates with the `HEX_API_KEY` secret, an
organisation secret the maintainer scopes to this repository and rotates. The
workflow reads it as `${{ secrets.HEX_API_KEY }}` in that one step's
environment and nowhere else; the job's own token is read-only
(`contents: read`). No agent holds, reads, or passes on the key.

**The docs publish with the package.** `mix hex.publish --yes` builds and
publishes the docs with the package, as by default, so HexDocs carries every
version's documentation; the gate's Docs stage builds the same docs first and
fails on any ExDoc warning. Decided by the conductor under a standing consent, 2026-10-04.

**A failed publish.** The workflow never retries. A run that stops at a check
or at the gate publishes nothing, and the tag stands as the record of what was
attempted: the fix lands on the default branch and the next patch version is
tagged; a tag is never moved or pushed again. A run whose publish step failed
on a registry or network error is re-run once, by hand, from the run's page in
the Actions tab; a gate that failed is never re-run, and a second failure of
the publish step is the maintainer's. A failed workflow is never worked round
by a local publish. Decided by the conductor under a standing consent,
2026-10-04.

**A published version stands.** Hex allows a new version of an existing
package to be reverted or replaced within one hour of its publication, then
only retired, and a retired version stays resolvable to everyone who already
depends on it. No agent or session runs any `mix hex.publish` form - a
replace, a revert, or a docs-only publish included.

## Consequences

- **The authority table moves with the decision.** `CLAUDE.md`'s
  `mix hex.publish` row, the release-prep row's tag clause, the relay
  paragraph, the version-bump exception and the **Release preps** paragraph
  now say that the release workflow publishes on the tag push and that no
  agent or session runs the publish command; `.claude/wurk/release.md` says the
  same in its publish section and its release trigger.
- **The tag push is now the release.** Pushing a version tag that passes the
  three checks publishes a version nobody can take back after an hour. The
  tag's trigger, a release prep the operator named and merged to
  `origin/main`, therefore carries the weight the publish row used to carry,
  and the release-prep row stays narrow for that reason.
- **The gate runs once more per release.** The workflow runs the full gate
  itself instead of trusting a CI result on the same commit; the cost is one
  gate run per release, and it holds when CI was cancelled or never ran on
  that commit.
- **The workflow file is code that runs with a secret in scope.** Its checks
  run before the toolchain and before the key's step, no repository file or
  event field is interpolated into a `run:` script, and the coverage upload
  that `ci.yml` runs after its gate is left out, so no second secret shares
  the job with `HEX_API_KEY`.
- **This decision does not move the instruction set.** No grammar, opcode,
  compiled format or stored artifact changes, and no ISA version is bumped;
  ADR-0003's obligations are not engaged.

## Notes

### 2026-10-10: the status is now `accepted`

This record stayed proposed until the release workflow it decides had
published a version, and it has. predicator 9.4.3 is the first version
published through `.github/workflows/release.yml`: the tag `v9.4.3`, on the
commit `f423083f` that the 9.4.3 release prep
([#243](https://github.com/riddler/predicator-ex/pull/243)) merged, started
<https://github.com/riddler/predicator-ex/actions/runs/37309522889>, whose
branch, version and Hex checks, full gate and publish step all passed on its
first attempt. No later version has been published through the workflow.
The workflow itself landed in
[#239](https://github.com/riddler/predicator-ex/pull/239). Flipping this
record on its first workflow publish, with that run and its commit as the
evidence, was ruled by the operator, 2026-10-06; the evidence this Note names
and the version the Status line names were decided by the conductor under a
standing consent, 2026-10-10.

Every claim above was re-verified on 2026-10-10 against `origin/main` at
`f423083f`, which no commit has followed: the workflow's tag-only trigger,
its read-only token, its branch, version and Hex checks run before the
toolchain, the gate read from `gate.full` in `.claude/wurk.json`, the key in
the publish step alone, the docs published with the package, and the coverage
upload left out; `CLAUDE.md`'s publish row, release-prep row, relay paragraph,
version-bump exception and **Release preps** paragraph;
`.claude/wurk/release.md`'s publish section and release trigger; each
ADR-0006 sentence quoted at the top, still present and unedited; and Hex's
one-hour window for a new version of an existing package, in
`mix help hex.publish`. No claim had moved, so no sentence above is
superseded.
