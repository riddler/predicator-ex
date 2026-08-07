# Does the conformance tree earn its own area label?

Bead: px-phw (discovered from px-35i.4)
Date: 2026-08-07
Decision: **yes - `area:conformance` is added to CLAUDE.md's vocabulary.**

This is workflow governance, not architecture. It changes no instruction, no
opcode, and no grammar, so it **does not move the ISA** and it is not
ADR-shaped: every existing ADR is about the language or the architecture, and
the authority for area labels already lives in CLAUDE.md. No ADR was written.

## The question

px-35i.4 created the conformance tree and was labeled `area:build` +
`area:evaluator`, with `area:docs` added at merge time because the branch also
moved `docs/`, `README.md`, and `CHANGELOG.md`. `area:build` is exclusive, so
every follow-on that touches corpus tooling batches with nothing. Either the
conformance tree genuinely is build surface, or the vocabulary is missing a row.

## Ground truth: the paths

The apparatus occupies exactly these paths, and no others:

```
conformance/README.md
conformance/manifest.json
conformance/cases/*.json            12 authored case files
conformance/corpus/tier-{1..5}.json generated output
conformance/schema/{case,corpus,manifest,report}.json
lib/predicator/conformance/{coverage,features,generator,json,values}.ex
lib/mix/tasks/corpus.{generate,coverage}.ex
test/predicator/conformance/*.exs   10 files
test/mix/tasks/corpus_{generate,coverage}_test.exs
```

References from outside the subtree:

- `mix.exs` - the `package/0` `files:` list and `exclude_patterns:`, plus a long
  comment explaining the three-way exclusion. **One edit, already made.**
- `.quality.exs`, `coveralls.json`, `.credo.exs`, `.github/**` - **zero
  references.** Grepped for both `conformance` and `corpus`; nothing.
- `mix.lock` - untouched. The corpus tooling added no dependency.

The tree's own tests run as ordinary ExUnit tests and are picked up by the
default `test/` path, which is why the gate config needed no entry.

Adjacent but deliberately *not* covered: `docs/isa.md`,
`lib/predicator/instructions.ex`, and `test/predicator/isa_sync_test.exs`. The
corpus generator reads the opcode/tier table those define, but they are ISA
surface and stay `area:docs` / `area:evaluator`.

## Ground truth: the blast radius of real conformance work

The argument for `area:build` is that conformance work forces edits to the
shared build files on an ongoing basis. The commits say otherwise. The two
follow-on beads created by px-35i.4's own verification pass, both labeled
`area:build`, touched between them:

- px-q1f (`4a967a6`, filters function noise from `corpus.coverage`) -
  `CHANGELOG.md`, `conformance/README.md`, `lib/mix/tasks/corpus.coverage.ex`,
  `lib/predicator/conformance/coverage.ex`, two test files.
- px-1ka (`2931666`, covers every builtin in the corpus) -
  `conformance/cases/functions.json`, `conformance/corpus/tier-5.json`,
  `conformance/manifest.json`, one test file.

**Neither touched a single file in the `area:build` row.** They held the
exclusive label, and therefore the whole batch queue, for a blast radius that
was entirely inside `conformance/**` plus `CHANGELOG.md`.

The `mix.exs` edits on the px-35i.4 branch (`ac59b3e`, `4afe61e`, `b5a86b0`)
were all about keeping the apparatus *out* of the Hex package. That is a
one-time boundary decision, guarded from then on by
`test/predicator/conformance/package_boundary_test.exs`. Standing the tree up
cost a build edit; living with it does not.

The two open beads that will touch this area next confirm the shape:

- px-9ab (teaches the workflow the corpus) - `.claude/**` and CLAUDE.md only.
- px-35i.8 (specifies the sibling ratchet) - a docs spec plus a reference runner
  that is explicitly *not* Elixir. No ratchet mechanics land in this repo.

## The decision

`area:conformance` covers the subtree listed above. It is an ordinary,
non-exclusive label: two beads are batchable iff their area sets are disjoint,
and a conformance bead now batches freely against lexer/parser, evaluator, and
functions work.

The relationship to `area:build` is the plain file-collision rule with no
special case. A conformance bead that also edits `mix.exs`, `coveralls.json`,
`mix.lock`, or anything else in the `area:build` row carries **both** labels,
and `area:build`'s exclusivity re-triggers in full: that bead lands alone. This
is the right answer for the same reason `area:api` is the right answer for a
bead that adds a function and exposes it - it does touch both. The hazard
`area:build` guards is a moved `mix.lock` or gate config poisoning every
parallel worktree's warmed `_build`, and that hazard is a property of the file,
not of the subject. Widening `area:conformance` to swallow such a bead would
smuggle exactly that change into a batch.

## Naming

px-9ab's acceptance criteria say `area:corpus`; px-phw's description says
`area:conformance`. Settled here as **`area:conformance`**, matching the
directory name and the `Predicator.Conformance` module namespace, and because
the label covers more than the generated corpus files - it also covers the
schemas, the authored cases, the generator, and the mix tasks. px-9ab has been
noted to that effect; its remaining acceptance criteria are unaffected.

## What was changed

- `CLAUDE.md` - the `area:conformance` row in the area table, plus prose stating
  why it exists and how it interacts with `area:build`.
- `.claude/skills/create-issue/SKILL.md` - the label enumeration and the
  "come up constantly" list. `next-issues` needed no edit: it special-cases only
  `area:build` and otherwise defers to CLAUDE.md's vocabulary.

## Relabeling

- px-9ab, px-35i.8 - open, but neither's predicted blast radius is inside the
  conformance subtree (docs and skills for the first, a docs spec for the
  second). Left as labeled; a note records the naming decision.
- px-q1f, px-1ka - closed and merged via PR #90. Relabeled to
  `area:conformance` anyway, for record accuracy: they are the evidence for this
  decision, and leaving them tagged `area:build` would make the record
  contradict the reasoning.
- px-phw itself - its own edit stays inside `CLAUDE.md` and `.claude/`, so
  `area:docs` (plus `area:skills`) is correct. It is not a conformance bead; it
  is a bead *about* the conformance label.
