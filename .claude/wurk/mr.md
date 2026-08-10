# Predicator-ex extension: /wurk:mr

ISA and corpus content for the PR body, the merge policy, and the changelog
test. Adds only - see `~/.claude/skills/wurk:mr/SKILL.md` for everything this
does not repeat.

## ISA in the PR body

If the change moves the ISA, say so explicitly: the version it lands at, its
`docs/isa.md` entry, and any migration note (ADR-0003). A sibling that has not
adopted the new version is not a blocker on the PR.

## Corpus section of the PR body

If `conformance/corpus/*.json` or `conformance/manifest.json` moved, name the
cause and the affected case ids. The corpus is the exported specification
siblings verify against; `corpus_freshness_test.exs` proves the corpus is
fresh, never that the change was wanted.

## This repo is rebase-merge-only

Asserted as fact, not conditionally: do not offer or perform a squash merge,
and do not restructure the branch's commits on the assumption they will be
squashed. See CLAUDE.md's merge-policy section for the settings this
assertion is drawn from.

## Changelog entry test

A changelog entry is owed only when the diff changes something a caller of
`Predicator.evaluate/3` or a predicate author can observe. If one is needed
and missing, ask the user what it should say rather than inventing it - it is
a promise about behavior, added directly under `## [Unreleased]` in
`CHANGELOG.md` (this repo's `changelog.mode` is `keep-a-changelog`, not
fragments).
