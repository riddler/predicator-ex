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

## Agent authority in this repo

**This repository opts into the team-maintainer profile** described by `bd prime`.
Conservative stays the default everywhere else: a clone of a repo that has not
written an opt-in like this one gets the conservative rules, and so does this
repo for any action the table below does not name.

The grant is per action, and every action has a trigger. Authority is not
blanket - an action whose trigger has not fired is still unauthorized, and an
explicit "do not commit", "do not push", or equivalent from the current user or
orchestrator overrides every row here.

| Action | Trigger | Still unauthorized when |
|---|---|---|
| `bd` task tracking (`create`, `claim`, `update`, `note`) | any time | never - this is the default profile too |
| `mix quality`, `mix quality.check`, `mix test` | any time | never - running the gate costs nothing but time |
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

## What this project is

Predicator is a secure, non-evaluative condition engine: user-authored boolean
predicates compile to a flat instruction list run by a stack VM, with no
`eval` and no dynamic code execution anywhere in the pipeline.

Read before making design decisions:

- `docs/architecture.md` - grammar with precedence, the component map,
  per-feature history, conventions, and troubleshooting. The detailed reference
  for this codebase.
- `docs/adr/` - the reasoning behind architectural decisions; cite ADR numbers
  instead of re-arguing them. ADR-0001 sets the 3.6-4.0 arc.

Predicator has sibling implementations in Ruby and JavaScript. The instruction
set is the cross-language interchange format, so changes to it are not local to
this repo (ADR-0001).

## Build & Test

```bash
mix quality                # full gate: format, credo --strict, coverage, dialyzer
mix quality.check          # same checks, without fixing formatting
mix test                   # run the suite
mix test --watch           # watch mode
mix test.coverage          # coverage report
mix test.coverage.html     # HTML coverage report
```

Full `mix quality` must be green before any commit. Coverage target is >90% for
every component. The gate is a hand-rolled `mix` task today; migrating it to
ex_quality is tracked as `px-t54`.

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
