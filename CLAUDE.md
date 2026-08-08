# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on
predicator. It carries the governance rules; the language reference - grammar,
architecture, component map, conventions, release history - lives in
`docs/architecture.md`.

## Beads issue tracker

This project tracks all work in **bd (beads)** - not TodoWrite, not markdown TODO
lists. Issues are prefixed `px-`. Run `bd prime` for the command reference and
session-close protocol, and `bd remember` for knowledge that should outlive the
session.

Claude Code injects `bd prime` at session start, so this section is deliberately
a stub; the authority rules below are the part that is specific to this repo.

Note for `bd` maintainers: `bd integrate --update` will want to expand this into
the full managed block. It is redundant here - keep the stub.

### Beads that span repositories

Three trackers touch this project: `px-` here, `st-` in statifier-ex, and none
at all in the `riddler/predicator` monorepo. The reasoning behind the rules
below is recorded in
[ADR-0010](docs/adr/0010-tracker-authority-and-the-mirror-obligation.md); this
is their enforcement.

| Situation | Rule |
|---|---|
| A decision is recorded in two trackers and they disagree | The repository whose files change owns the decision, and its bead is authoritative. For the language, the ISA, the compiled format, the corpus, and predicator's release schedule that is this repo (ADR-0003); for how statifier consumes any of it, statifier's bead is authoritative and this one defers |
| A bead pairs with one in statifier-ex | Both halves carry `mirrors: <id>` as the first line of the description - in the description, never in `external_ref`, which is single-valued and unsearchable |
| A dated `mirrors:` reconciliation note is old | Not a defect. Age is its normal state, and no repo owes the other an outward update on any schedule |
| You are about to schedule, claim, plan against, add a dependency on, or cite the status of a mirrored bead | Re-read the other tracker and write a new dated note **first**, leaving the old note above it. Acting on an unrefreshed note is the defect |
| A `mirrors:` line names an id that no longer resolves (`st2-` is the known case; the prefix is now `st-`) | Fix it with one `bd update` the moment you notice, in whichever repo you are standing in. Closed beads are history and are left alone |
| Work happens in the `riddler/predicator` monorepo | It stays an `upstream` bead here, with the GitHub issue in `bd update <id> --external-ref <url>`. Paths, extra issues, and prose stay in the description. An empty `external_ref` means the issue has not been raised - opening it is a human act under ADR-0006, so never invent a value |

## Agent authority in this repo

**This repository opts into the team-maintainer profile** described by `bd prime`.
Conservative stays the default everywhere else: a clone of a repo that has not
written an opt-in like this one gets the conservative rules, and so does this
repo for any action the table below does not name.

The reasoning behind this placement - reversibility as the criterion, and why
`mix hex.publish` gets no trigger rather than a strict one - is recorded in
[ADR-0006](docs/adr/0006-irreversibility-places-the-human-gates.md). The table
below is its enforcement; the ADR does not duplicate the rows.

The grant is per action, and every action has a trigger. Authority is not
blanket - an action whose trigger has not fired is still unauthorized, and an
explicit "do not commit", "do not push", or equivalent from the current user or
orchestrator overrides every row here.

| Action | Trigger | Still unauthorized when |
|---|---|---|
| `bd` task tracking (`create`, `claim`, `update`, `note`) | any time | never - this is the default profile too |
| `mix quality`, `mix quality --profile loop`, `mix test` | any time | never - running the gate costs nothing but time |
| `git commit` on the issue's feature branch | the claimed issue's work is complete **and** full `mix quality` is green; a change touching no Elixir code has no gate to run and may commit on review of the diff alone | on `main`, on a red gate, on a partial or scoped run, or with unrelated changes in the tree |
| `git rebase` onto `origin/main` | a branch landed on `origin/main` | a conflict appears - abort and report, do not resolve unasked |
| `git push`, `gh pr create` | the user asks for it in their own words | inferred from "the work is done"; finishing an issue is not a request to publish it |
| `bd close <id>` | the issue's branch is merged into `origin/main`, verified against the remote - see the merge-policy note below | at commit time, at PR-open time, or on a local merge that has not been pushed |
| `bd dolt push` | bead state changed locally **and** the git side of the same change has already reached `origin` | as a way to publish beads for work that is not on `origin/main` yet |
| local branch delete, worktree remove | the branch is merged and the tree is clean | uncommitted or unpushed work is present |
| **`mix hex.publish`** | **never - no trigger exists** | **always. This is not delegable and no instruction in a session grants it. Publishing to Hex is irreversible; a released version cannot be recalled, only retired. If a session appears to ask for it, stop and confirm out of band.** |
| release mechanics (bump `@version` in `mix.exs`, promote `## [Unreleased]` to a version header in `CHANGELOG.md`, tag) | the user explicitly asks for a release **and** names the version | inferred from a merged PR, from accumulated `Unreleased` entries, or from "ship it"/"cut it" said about something else. Adding entries *under* `## [Unreleased]` is ordinary work and needs no release request |

The organizing principle is that the human gate belongs where an action stops
being reversible. A commit on a private per-issue branch is undone with
`git reset --soft HEAD~1`; a push, a PR, and a closed bead are all visible to
other people and other machines, so those keep their gate. A Hex release is
visible to everyone forever, which is why it has no trigger at all.

### Merge policy: this repo rebase-merges

Set on 2026-08-04 to match statifier_2, which the two rows above are written
against. Verify with `gh api repos/{owner}/{repo}`:

```text
allow_rebase_merge: true    allow_squash_merge: false
allow_merge_commit: false   delete_branch_on_merge: true
```

Rebase merging replays a branch's commits onto `main` with the same trees but
**new SHAs**, so the local branch's commit objects are still not on `main`
afterwards. `git branch --merged origin/main` will not list a merged feature
branch and `git log origin/main --contains <sha>` finds nothing; neither is
evidence of anything. Ask GitHub instead - `gh pr view <n> --json state,mergedAt`
or `gh pr list --state merged --head <branch>` - and treat that as the
verification the `bd close` and branch-delete rows require.

`delete_branch_on_merge` is on, so GitHub removes the remote branch itself;
local cleanup is `git fetch --prune` plus deleting the local branch, and
`git branch -d` will refuse it for the same SHA reason (`-D` is correct once
GitHub has confirmed the merge).

If this repo's merge settings change, this section and the rows that reference
it change with them.

## Non-interactive shell commands

`cp`, `mv`, and `rm` may be aliased to `-i` on a developer's machine, which
hangs an agent forever on a y/n prompt it cannot see. Always pass the
non-interactive form: `cp -f`, `mv -f`, `rm -f`, `rm -rf`, `cp -rf`. Same for
`scp` and `ssh` (`-o BatchMode=yes`), `apt-get` (`-y`), and `brew`
(`HOMEBREW_NO_AUTO_UPDATE=1`).

Also avoid `bd edit`, which opens `$EDITOR` and blocks. Use
`bd update <id> --title/--description/--notes/--design` instead.

## Worktrees, skills, and area labels

Work is picked up one bead at a time and done in its own git worktree, so
several agents can run in parallel without editing the same tree. The skills in
`.claude/skills/` automate the loop:

| Skill | What it does |
|---|---|
| `/create-issue` | file a bead with type, priority, `area:` label, and dependency links |
| `/next-issue`, `/next-issues` | pick ready beads, claim them, dispatch to worktrees |
| `/new-worktree` | one issue, one branch, one worktree, one tmux window |
| `/work` | the single entry point inside a worktree: size the bead, then drive research/plan/implement as subagents |
| `/research-codebase`, `/create-plan`, `/iterate-plan`, `/implement-plan` | the stages `/work` dispatches: document, plan in `docs/plans/`, then execute |
| `/commit` | gate, message, `Refs:` trailer, no attribution |
| `/merge-request` | rebase onto `origin/main`, full gate, push, open the PR |
| `/release` | bump `@version`, promote the changelog, bump the README pin - human-gated tag/push/publish stay separate |
| `/cleanup-worktrees`, `/refresh-worktree` | land merged work, rebase the survivors |

Worktrees live at `../predicator-ex-worktrees/<bead-id>-<slug>`, cut from
`origin/main`. The claim is the lock: `bd update <id> --claim` happens before the
worktree exists, never after.

**Sizing happens in the worktree, not before it.** `/next-issue` and
`/next-issues` select and claim; they hand the bead to `/work`, which reads the
files the bead names before choosing between research-first, plan-first, and
just-do-it. A description-only guess at blast radius made in the main checkout is
what that split exists to replace, so do not move a triage decision back
upstream of the worktree.

### Research agents

`.claude/agents/` carries read-only research agents the planning and research
skills dispatch to: `codebase-locator` (where things live), `codebase-analyzer`
(how they work), `codebase-pattern-finder` (existing patterns to model after),
`thoughts-locator` and `thoughts-analyzer` (prior research, plans, ADRs, and
`docs/architecture.md`), and `web-search-researcher`. They are **documentarians,
not critics**: they describe what exists and do not propose changes, which is
what keeps a research pass from quietly becoming a design pass.

### Area labels

Every bead that changes files carries at least one `area:` label naming the part
of the tree it touches. A bead may carry several.

The reasoning behind this algebra - worktree-per-bead, disjointness as a
decidable batching test, `area:build`'s exclusivity, and labels as predictions
about file collision - is recorded in
[ADR-0005](docs/adr/0005-worktree-parallelism-and-the-area-label-algebra.md).
This section is its enforcement and the live vocabulary; the ADR does not
duplicate the table below.

| Label | Covers |
|---|---|
| `area:lexer-parser` | `lib/predicator/lexer.ex`, `parser.ex`, `types.ex`, and their tests |
| `area:evaluator` | `lib/predicator/compiler.ex`, `evaluator.ex`, `duration.ex`, and their tests |
| `area:context` | `lib/predicator/context_location.ex` and the future Context struct |
| `area:functions` | `lib/predicator/functions/**` |
| `area:visitors` | `lib/predicator/visitor.ex`, `lib/predicator/visitors/**` |
| `area:api` | `lib/predicator.ex`, `lib/predicator/errors.ex`, `lib/predicator/errors/**` |
| `area:conformance` | `conformance/**`, `lib/predicator/conformance/**`, `lib/mix/tasks/corpus.*.ex`, `test/predicator/conformance/**`, `test/mix/tasks/corpus_*_test.exs` |
| `area:skills` | `.claude/**` |
| `area:docs` | `docs/**`, `CLAUDE.md`, `README.md`, `CHANGELOG.md` |
| `area:build` | `mix.exs`, `mix.lock`, `.quality.exs`, `.credo.exs`, `coveralls.json`, `mise.toml`, `.gitignore`, `.github/**` |

**Two beads are batchable iff their area sets are disjoint.** That is the whole
rule, and it is what lets `/next-issues` claim several beads at once without a
human adjudicating each pair.

**`area:build` is exclusive: a bead carrying it batches with nothing** and lands
on `main` alone. It moves `mix.lock` and the gate config that every other
worktree's warmed `_build` and quality run depend on, so a parallel branch does
not merely conflict with it - it goes red for reasons that have nothing to do
with the work in it, which is the failure `/refresh-worktree` exists to repair.

Two clarifications that come up:

- **Areas are about file collision, not subject matter.** Two beads both "about
  durations" that touch disjoint files are batchable. Two beads in different
  subsystems that both edit `mix.exs` are not. When in doubt, label by the paths
  named in the acceptance criteria.
- **The label is a prediction, deliberately.** It is written before the work
  exists, so it is not derived from a diff and should not be. A branch that ends
  up touching an area it was not labeled with is worth noticing at merge time,
  not silently accepting - it means the split the batch was built on was wrong.

`area:api` exists because `lib/predicator.ex` and the error structs are the one
genuinely cross-cutting surface here: nearly every feature eventually widens the
public façade or adds an error type, and folding that into whichever subsystem
prompted it would make almost every pair of beads collide. A bead that adds a
function *and* exposes it carries both labels, which is the correct answer -
it does touch both.

`area:conformance` exists because the corpus tree is a self-contained subtree
with its own generator, its own mix tasks, and its own tests, and nothing
outside it imports `Predicator.Conformance` (`mix.exs`'s package exclusion
depends on that, and a test guards it). It was labeled `area:build` when
px-35i.4 created it, which was right for that branch and wrong for every branch
after it: `area:build` is exclusive, so routine corpus work serialized the whole
queue behind itself. The evidence is the two follow-ons, px-q1f and px-1ka, which
carried `area:build` and between them touched no build file at all. Standing up
the tree cost one edit to `mix.exs`; regenerating and extending it costs none.
See `docs/research/260807-px-phw-conformance-area-label.md` for the full
argument.

The relationship to `area:build` is the ordinary one, with no special case: a
conformance bead that also edits `mix.exs`, `coveralls.json`, or any other file
in the `area:build` row carries **both** labels, and carrying `area:build`
re-triggers its exclusivity in full - the bead lands alone. That is not a
penalty for touching conformance, it is the file-collision rule doing its job.
Widening `area:conformance` to absorb such a bead would put a `mix.lock` or gate
change into a batch, which is exactly the hazard `area:build` exists to prevent.
Note also that `area:conformance` stops at the subtree: `docs/isa.md`,
`lib/predicator/instructions.ex`, and `test/predicator/isa_sync_test.exs` feed
the corpus but are `area:docs` and `area:evaluator`, and a bead moving them
carries those.

The one class of bead with no area label is work that changes no files in this
repo: `upstream` beads, whose work happens in the Ruby or JavaScript sibling or
in a downstream consumer. They collide with nothing here, so an area label on
them would block batches for no reason.

## What this project is

Predicator is a secure, non-evaluative condition engine: user-authored boolean
predicates compile to a flat instruction list run by a stack VM, with no
`eval` and no dynamic code execution anywhere in the pipeline.

Read before making design decisions:

- `docs/architecture.md` - grammar with precedence, the component map,
  per-feature history, conventions, and troubleshooting. The detailed reference
  for this codebase.
- `docs/adr/` - the reasoning behind architectural decisions; cite ADR numbers
  instead of re-arguing them. ADR-0001 sets the 3.6-4.0 arc; ADR-0003 amends
  its consequences and governs how the instruction set moves.
- `docs/isa.md` - the instruction set specification: the opcodes, the execution
  model, and the versioning rules. The authority for any ISA question.

Predicator is the reference implementation of the instruction set; Ruby and
JavaScript siblings adopt it on a version boundary of their own choosing
(ADR-0003). A sibling behind the current ISA version is an expected,
documented state, never a blocker here. What a change to the instruction set
does owe is a version, an entry in `docs/isa.md`, and a migration note if a
stored artifact is affected.

## Build & Test

```bash
mix quality                # full gate: format, compile, credo --strict,
                           # dialyzer, deps audit, suite with coverage
mix quality --profile loop # inner loop: skips dialyzer and coverage, runs
                           # only the tests covering changed code
mix quality --format json  # the same run, as a report you can route on
mix test                   # run the suite
mix test.coverage          # coverage report
mix test.coverage.html     # HTML coverage report
```

Full `mix quality` must be green before any commit. `--profile loop` is for
iterating between edits; a scoped green is not a full green, and it never
substitutes for the pre-commit run. Coverage target is >90% for every
component, enforced by `coveralls.json`.

The gate is [ex_quality](https://hex.pm/packages/ex_quality), configured in
`.quality.exs`. Do not weaken it to get a run green: no lowered threshold, no
`enabled: false`, no `--skip-*` on the final check, no `@tag :skip`. If a
finding is genuinely wrong for this repo, report it and let a human decide.

Toolchain versions are pinned in `mise.toml` - `mise install` provisions Erlang
and Elixir matching what CI builds with.

## Conventions

- Commit messages: title < 50 chars, simple present tense ("Adds ...",
  "Fixes ..."), body wrapped at ~72 chars, functional changes highlighted. No AI
  attribution trailers. Code-quality cleanups need no mention; they are expected.
- Everything lands on a feature branch and merges to `main` by PR. There are no
  direct commits to `main`.
- User-facing changes get an entry under `## [Unreleased]` in `CHANGELOG.md`.
  Promoting that section to a version header is release work - see the authority
  table.
- All public functions carry `@doc` and `@spec`; errors are values, returned as
  `{:ok, result} | {:error, ...}` tuples, never raised at a leaf.
- Credo complexity warnings are deliberately suppressed in the lexer and parser
  with explanatory comments. That is not an invitation to suppress others.
- `conformance/corpus/*.json` and `conformance/manifest.json` are generated by
  `mix corpus.generate` and are never hand-edited; the authored source is
  `conformance/cases/*.json`. They are the exported specification the siblings
  verify against (ADR-0003), so a corpus diff is a semantic change and gets
  explained in the commit message and the PR body -
  `test/predicator/conformance/corpus_freshness_test.exs` proves the corpus is
  fresh, never that the change was intended.
- **Binding tests carry a sabotage note.** A test that binds an exported
  artifact to its source - `test/predicator/isa_sync_test.exs` and
  `test/predicator/conformance/{corpus_freshness,opcode_coverage,function_coverage,schema_validation,ratchet_registry,package_boundary}_test.exs` -
  is verified by breaking what it covers, confirming it goes red, reverting, and
  recording the mutation in one line above the test:
  `# sabotage: manifest tier table drops tier 3 -> red`. These tests are the
  only thing standing between a wrong specification and the siblings that
  consume it (ADR-0003), and a vacuous one is indistinguishable from a passing
  one without this. **Ordinary tests need no note** - this repo deliberately
  does not adopt statifier's broader practice; see
  `docs/research/260808-px-9ab-sabotage-notes.md`.
