# Wurk Config Catch-Up Implementation Plan

## Overview

Catch this repo's wurk configuration up to the kit's current feature set:
reclassify the three skipped gate stages between `gate.project_level_skips`
and a new `gate.not_applicable_skips`, author the `.claude/wurk/codebase.md`
orientation file that wurk ADR-0011 added, and make an explicit, recorded
decision for every remaining manifest field the kit's schema offers. Bead:
px-hhu.

This plan changes no Elixir code. Every edit lands under `.claude/`, plus this
document under `docs/plans/`.

## Current State Analysis

### The manifest today

`.claude/wurk.json` (35 lines of schema-bearing JSON) declares `beads`,
`forge`, `gate`, `parallelism`, `tmux`, `artifacts`, `commits`, `changelog`,
and `release`. It does **not** declare `repo`, `models`, `judge`, `rebase`,
`gate.attest`, `gate.guard_ledger`, `gate.sabotage`,
`gate.not_applicable_skips`, or `beads.areas.always_batchable`.

Its whole skip taxonomy is three anchored exact-match patterns in
`gate.project_level_skips`:

```json
"project_level_skips": [
  "^:doctor not installed$",
  "^:gettext not installed$",
  "^:sobelow not installed$"
]
```

### What the gate actually reports

A full `ruby ~/.claude/skills/wurk:kit/scripts/gate.rb` run on this branch's
clean tree (2026-08-12) returned `ok: true`, tier 1, `attested: false`, 2,478
tests, 94.8% coverage, Credo and Dialyzer clean, and exactly three skipped
stages:

| Stage | `summary` | classification today |
|---|---|---|
| Doctor | `:doctor not installed` | `project_level` |
| Gettext | `:gettext not installed` | `project_level` |
| Sobelow | `:sobelow not installed` | `project_level` |

There are no other skips, and no `no .po files` summary of the kind
statifier-ex sees. The three anchored patterns cover the observed set exactly,
so a reclassification is a move between two lists and not a widening of what
is matched.

Each of the three currently emits a `stage_skipped_project_level` warning
saying the stage is "a standing project gap ... say so when reporting", which
is why every `/wurk:mr` request body this repo produces recites all three.

### The orientation gap

`.claude/wurk/` holds ten per-skill extension files (`branch`, `commit`,
`implement`, `issue`, `iterate`, `mr`, `next`, `plan`, `release`, `research`,
`work`) and no `codebase.md`. Wurk ADR-0011 (accepted 2026-08-12) added that
file as an agent-family extension: `/wurk:research`, `/wurk:plan`, and
`/wurk:iterate` forward it verbatim into every `wurk-codebase-*` prompt, and
the analyzer and pattern-finder read it themselves when invoked standalone.
Absent the file, each agent re-derives the layout from `CLAUDE.md` plus a
directory listing on every invocation.

Some of the material that belongs there already exists, in the wrong file.
`.claude/wurk/research.md` carries three orientation-shaped sections - "The
pipeline vocabulary", "The tree map", and "Good search keys" - which are read
by `/wurk:research` only. `/wurk:plan` and `/wurk:iterate` never see them, and
neither does any codebase agent, because a skill extension is not forwarded
into subagent prompts. ADR-0011 point 6 names exactly this reroute.

### Key discoveries

- Kit classifier: `gate.rb:211` `classify_skip/3` checks
  `not_applicable_skips` **first**, then `project_level_skips`. The patterns
  compile through `Manifest#not_applicable_skip_re` and
  `#project_level_skip_re` (`lib/manifest.rb:289,297`). Because this repo's
  existing patterns are anchored exact matches, a stage moved between lists
  must be **removed** from the old list - shadowing does not apply here, and
  leaving a duplicate would be a silent no-op that the next reader has to
  re-derive.
- Reporting rule: wurk `docs/manifest.md` "gate.project_level_skips and
  gate.not_applicable_skips" - a `not_applicable` match still warns
  (`stage_skipped_not_applicable`), still never counts as a pass, and is
  explicitly **not required** in commit reports or request bodies.
- The choosing test, from the same section: *is this a stage the project would
  run if someone did the work?*
- Carve-out hazard: `lib/gate_paths.rb` `gate_applicable?` unions
  `gate.build_paths` (`lib/`, `test/`, `mix.exs`, `mix.lock`) and
  `gate.also_gated_paths` (`conformance/`). A branch whose changed paths are
  all under `.claude/` and `docs/` matches neither, so `gate.rb` reports
  `applicable: false` and never runs `mix quality` - and therefore emits no
  `skipped_stages` at all. **The reclassification cannot be observed
  end-to-end from this branch.** Verification uses the loader's own compiled
  regexes instead (see Phase 1), with the end-to-end confirmation deferred to
  the first post-merge branch that touches `lib/`.
- `upstream` is a real label here: 1 closed bead carries it, and CLAUDE.md's
  area-label section names the class explicitly ("work that changes no files
  in this repo"). `beads.areas.always_batchable` is therefore a genuine gap,
  not a hypothetical.
- This repo has a sabotage discipline, but a *narrower* one than
  `gate.sabotage` scans for: CLAUDE.md says binding tests carry a note and
  "Ordinary tests need no note", with the enumerated list in
  `docs/research/260808-px-9ab-sabotage-notes.md`. The kit's scan flags every
  new test declaration lacking a note.
- Constraint: `.claude/wurk.json` is strict JSON parsed by Ruby's stdlib
  (wurk ADR-0006). No comments. Decisions about it cannot be recorded inside
  it - this document is their record.

## Desired End State

- `.claude/wurk.json` classifies Gettext and Sobelow as `not_applicable` and
  leaves Doctor as the one genuine project-level gap; declares
  `repo.default_branch`, `models.direction`, and
  `beads.areas.always_batchable`; and still loads clean.
- `.claude/wurk/codebase.md` exists, is about one screenful, and carries this
  repo's layout, suite split, module families, terms of art, and reading
  rules. `.claude/wurk/research.md` no longer duplicates the orientation
  sections and points at it instead.
- Every field in the bead's section 3 has a decision recorded in this
  document, including the ones whose answer is "leave it off".

Verified by: `manifest.rb check` reporting `ok: true`; the classifier probe in
Phase 1 printing `not_applicable` for Gettext and Sobelow and `project_level`
for Doctor; `gate.rb` reporting `ok: true`; and the file existing with the
content Phase 2 specifies.

## What We're NOT Doing

- **Not adding `.claude/` to `gate.also_gated_paths`.** It would make the
  carve-out fire on this branch and let `gate.rb` observe the skip
  reclassification directly, but nothing in `mix quality` measures `.claude/`,
  so the gate would then claim to measure something it does not. The kit's
  `REFERENCE.md` warns against exactly this ("A consumer repo that gates its
  own `.claude/` should stop measuring the kit"). The Phase 1 probe is the
  honest substitute.
- **Not opting into `rebase.auto_resolve_paths`.** See the Phase 3 decision
  table; the candidate is named there but no evidence supports opting in yet.
- **Not declaring `gate.sabotage`, `gate.attest`, or `gate.guard_ledger`.**
  Decisions and reasons in Phase 3.
- **Not editing `CLAUDE.md`.** The manifest decisions are wurk-configuration
  detail, and ADR-0012 already delegates that to `.claude/wurk.json` plus this
  repo's extension files. Adding a pointer there would also pull `area:docs`
  onto a bead labelled `area:skills`.
- **Not touching any Elixir file, `mix.exs`, `.quality.exs`, or
  `coveralls.json`.** The `.claude/wurk/plan.md` extension's always-required
  automated criteria (90% coverage on new code, `StringVisitor` round-trip)
  and its `### Integration Tests` subsection describe code changes; this bead
  makes none, so they are inapplicable rather than omitted. No opcode moves,
  so no `## ISA Impact` section.
- **Not rewriting the other nine `.claude/wurk/*.md` extensions.** Only
  `research.md` loses content, and only the three sections ADR-0011 point 6
  names.

## Implementation Approach

Three phases, one per part of the bead, each a self-contained commit. They are
ordered by how much each depends on judgment established by the one before it:
Phase 1 is a mechanical two-line move with a scriptable probe, Phase 2 is
authoring, Phase 3 is a sweep that appends to the same manifest Phase 1
touched.

Phases 1 and 3 both edit `.claude/wurk.json`, so they are sequential rather
than parallel; keeping them separate is still right, because Phase 1's change
is behavioral (it changes what `/wurk:mr` must recite) and Phase 3's is
declarative (it pins defaults and closes one real gap), and a reviewer reading
one commit should not have to separate the two.

Because no phase touches a gated path, `ruby
~/.claude/skills/wurk:kit/scripts/gate.rb` will report `applicable: false`
with a carve-out reason from Phase 1 onward. That is the correct answer, not a
failure: `ok: true` is still the bar, and it is what `/wurk:commit` reads.

## Phase 1: Reclassify the skipped gate stages

### Overview

Move Gettext and Sobelow into a new `gate.not_applicable_skips`, leave Doctor
in `gate.project_level_skips`, so `/wurk:mr` request bodies stop reciting two
stages that can never apply to this codebase.

### The per-stage decision

Applying wurk `docs/manifest.md`'s test - *would this repo be better off if
someone did the work to make the stage run?*

| Stage | Decision | Why |
|---|---|---|
| **Doctor** | stays `project_level` | Doctor is a documentation-coverage check, and this repo has a live `@doc`/`@spec`-on-every-public-function discipline (CLAUDE.md Conventions; `docs/architecture.md`). Installing it would measure something this project already claims to do by hand. A genuine gap, and the nag is doing its job. |
| **Gettext** | moves to `not_applicable` | Translation tooling. Predicator is a compiler and stack VM library with no user-facing strings to translate; its only strings are error messages addressed to predicate authors, which are English-only by design and part of the tested API surface. No i18n is coming. |
| **Sobelow** | moves to `not_applicable` | Sobelow is a Phoenix security scanner. This repo has no Phoenix surface, no web layer, and no Plug dependency; there is nothing for it to scan. Predicator's security posture is structural (no `eval`, ADR-0004) and is enforced by the suite, not by Sobelow. |

### Changes Required:

#### 1. The manifest's gate section

**File**: `.claude/wurk.json`
**Changes**: Reduce `project_level_skips` to Doctor alone and add the sibling
list. The two Gettext/Sobelow patterns are **removed** from the old list, not
left in it - the existing patterns are anchored exact matches, so a duplicate
would be dead configuration that the precedence rule silently shadows.

```json
    "project_level_skips": [
      "^:doctor not installed$"
    ],
    "not_applicable_skips": [
      "^:gettext not installed$",
      "^:sobelow not installed$"
    ]
```

Keep the anchored exact-match shape rather than relaxing to a substring
pattern: the observed summaries are stable, and a broad pattern would classify
a future unrelated skip as permanently inapplicable without anyone deciding
that.

### Success Criteria:

#### Automated Verification:

- [x] `ruby ~/.claude/skills/wurk:kit/scripts/lib/manifest.rb check` reports
      `ok: true` with no `blocked` entries and no unknown-key warning for
      `gate.not_applicable_skips`.
- [x] The classifier probe prints `project_level` for Doctor and
      `not_applicable` for Gettext and Sobelow, using the kit's own compiled
      regexes and the same precedence order `gate.rb:211` uses:

      ```sh
      ruby -e 'require "/Users/johnnyt/repos/github/wurk/skills/wurk:kit/scripts/lib/manifest.rb"
        m = Manifest.current
        [":doctor not installed", ":gettext not installed", ":sobelow not installed"].each do |s|
          c = if m.not_applicable_skip_re && s =~ m.not_applicable_skip_re then "not_applicable"
              elsif m.project_level_skip_re && s =~ m.project_level_skip_re then "project_level"
              else "run_level" end
          puts "#{s} => #{c}"
        end'
      ```

- [x] Neither Gettext nor Sobelow still appears in `project_level_skips`:
      `ruby -rjson -e 'p JSON.parse(File.read(".claude/wurk.json"))["gate"]["project_level_skips"]'`
      prints exactly `["^:doctor not installed$"]`.
- [x] `ruby ~/.claude/skills/wurk:kit/scripts/gate.rb` reports `ok: true`
      (expected `applicable: false` with a carve-out reason, since the changed
      paths are all outside `gate.build_paths` and `gate.also_gated_paths`).

#### Manual Verification:

- [ ] On the next branch that touches `lib/` or `test/`, a full `gate.rb` run
      classifies Gettext and Sobelow as `not_applicable` with
      `stage_skipped_not_applicable` warnings, and Doctor as `project_level`.
      This is deferred by construction - the carve-out means it cannot be
      observed from this branch.
- [ ] A `/wurk:mr` request body drafted for this branch names Doctor as a
      standing gap and does **not** recite Gettext or Sobelow.
- [ ] The two moved stages read as permanently inapplicable to a reviewer, not
      merely unaddressed - the decision table above is the argument.

**Implementation Note**: Use the project's loop gate between edits while
iterating; run the full gate as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the
next phase. In looped (`--loop`) execution, this phase's Automated
Verification gates advancement automatically (via `/wurk:commit --auto`), and
Manual Verification items are deferred and surfaced once at the end instead of
blocking here.

---

## Phase 2: Author `.claude/wurk/codebase.md`

### Overview

Give the `wurk-codebase-*` agents this repo's orientation in one file, and
move the orientation-shaped sections out of `.claude/wurk/research.md` so
there is one definition site rather than two.

### Changes Required:

#### 1. The new orientation file

**File**: `.claude/wurk/codebase.md` (new)
**Changes**: Free-form markdown addressed to the codebase agents, following
the shape of wurk's own `.claude/wurk/codebase.md`. ADR-0011 point 1 asks for
about a screenful, because the file is pasted into every codebase-agent
prompt; the budget is **under 85 lines** (wurk's own is ~56, for a smaller
tree than this one). Headings and the content each must carry:

- **`# Project orientation: predicator-ex`** - one sentence on what the
  project is: a secure, non-evaluative condition engine compiling boolean
  predicates to a flat instruction list run by a stack VM, with no `eval`
  anywhere.
- **`## Layout`** - `lib/predicator.ex` (public façade);
  `lib/predicator/{lexer,parser,types,compiler,evaluator,duration,context,
  context_location,cast,compiled,instructions,undefined,visitor}.ex`;
  `lib/predicator/errors/**` (five error structs);
  `lib/predicator/functions/**` (four builtin provider modules plus
  `provider.ex`); `lib/predicator/visitors/**` (`instructions_visitor.ex`,
  `string_visitor.ex`); `lib/predicator/conformance/**` and
  `lib/mix/tasks/corpus.*.ex`; `conformance/` (`cases/` authored,
  `corpus/` and `manifest.json` generated, plus `schema/`, `examples/`,
  `RATCHET.md`).
- **`## Suites`** - one ExUnit suite under `test/`, 82 files, mirroring `lib/`:
  `test/predicator/**` unit tests, `test/predicator/integration/**` end-to-end
  `Predicator.evaluate/3` and `execute/2` cases,
  `test/predicator/conformance/**` and `test/mix/tasks/**` for the corpus
  tooling. Name `isa_sync_test.exs` and `corpus_freshness_test.exs` as the
  binding tests that tie an exported artifact to its source.
- **`## The pipeline`** - moved verbatim from `research.md`:
  `source -> lexer -> parser -> AST -> compiler / InstructionsVisitor ->
  flat instruction list -> stack VM evaluator`, plus the round-trip path
  `AST -> StringVisitor -> source`.
- **`## Module families worth mining`** - the five error structs share one
  shape; the four function-provider modules all implement the one-callback
  `Predicator.FunctionProvider` behaviour; the two visitors both implement
  `Predicator.Visitor`; any one member is the template for a new one.
- **`## Terms of art`** - opcode, instruction list, ISA, corpus, conformance,
  ratchet, visitor, provider, precedence, short-circuit, duration, span,
  `on_unbound`, sentinel/`:undefined`, statement mode vs expression mode.
- **`## Best search keys`** - moved from `research.md`: opcode names (`lit`,
  `load`, `compare`, `object_new`, `jump_if_false`, `store`, `pop`, `cast`),
  `docs/isa.md` section numbers, AST node tags.
- **`## Reading rules`** - four, each one an instruction that changes what an
  agent writes:
  1. `docs/isa.md` is the authority for any instruction-set question.
     Describe an opcode's behavior against its ISA section rather than
     inferring intent from the evaluator clause that implements it.
  2. Errors are values: `{:ok, result} | {:error, struct}`, never raised at a
     leaf (ADR-0004). Do not describe an error path as an exception path.
  3. `conformance/corpus/*.json` and `conformance/manifest.json` are
     generated by `mix corpus.generate`; the authored source is
     `conformance/cases/*.json`. Never treat a generated file as the
     definition site.
  4. Credo complexity suppressions in the lexer and parser are deliberate and
     carry explanatory comments; they are not findings.

**If the draft runs past 85 lines, compress in this order** - stated here so
the implementer is not left choosing between the content list and the line
budget:

1. Collapse `## Layout`'s per-file enumeration to directory-level lines
   (`lib/predicator/errors/**` - five error structs, one shape), keeping the
   generated-vs-authored split under `conformance/`.
2. Trim `## Terms of art` to the ten highest-yield terms; it is a grep-key
   list, not a glossary.
3. Fold `## Best search keys` into `## Terms of art` as a final line.

Do **not** compress `## Reading rules` or the generated-vs-authored fact -
those are the items that change what an agent writes, which is the whole
reason ADR-0011 exists.

Note ADR-0011 point 5, add-never-override: this file states facts and search
guidance and cannot re-role an agent. Do not write judgment rules into it.

#### 2. Deduplicate the research extension

**File**: `.claude/wurk/research.md`
**Changes**: Remove "The pipeline vocabulary", "The tree map", and "Good
search keys" - the three orientation-shaped sections ADR-0011 point 6 names -
and replace them with a single pointer line naming `.claude/wurk/codebase.md`
as the definition site. Keep everything genuinely skill-facing:
"Sibling-port guidance", "ADR-0003 / ADR-0010 ownership rule", "The
ADR-0003/ADR-0001 rule", "Doc roots beyond `plans`/`research`", and
"`## ISA Impact` in research documents".

`docs/adr/`, `docs/design/`, `docs/guides/`, and `docs/reference/` stay in
`research.md`, not `codebase.md`: ADR-0011's third open question explicitly
leaves the docs agents on their existing two-path lookup, so moving doc roots
into an agent-family file the docs agents never read would silently
un-configure them.

The alternative - leave `research.md` intact and accept the duplication - was
considered and rejected. Two definition sites drift, and the material is
currently invisible to `/wurk:plan` and `/wurk:iterate`, which is the gap
ADR-0011 exists to close.

### Success Criteria:

#### Automated Verification:

- [x] `.claude/wurk/codebase.md` exists and is under 85 lines
      (`wc -l .claude/wurk/codebase.md`).
- [x] Every `lib/` and `test/` path the file names resolves: extracting the
      backticked paths and checking each with `test -e` reports no misses.
- [x] `.claude/wurk/research.md` no longer contains the headings "The pipeline
      vocabulary", "The tree map", or "Good search keys", and does contain a
      reference to `codebase.md`
      (`grep -c 'codebase.md' .claude/wurk/research.md` is at least 1).
- [x] `ruby ~/.claude/skills/wurk:kit/scripts/gate.rb` reports `ok: true`.

#### Manual Verification:

- [ ] Spawn a `wurk-codebase-locator` on a question whose answer depends on
      orientation ("where do new opcodes get implemented and tested") with the
      file's content pasted under "Project orientation, from
      .claude/wurk/codebase.md", and confirm the answer names
      `lib/predicator/instructions.ex`, `evaluator.ex`, and `docs/isa.md`
      without a discovery detour.
- [ ] The file reads as facts and search guidance, with no judgment rule that
      would re-role an agent (ADR-0011 point 5).
- [ ] Nothing removed from `research.md` is now unreachable by the
      `/wurk:research` flow.

**Implementation Note**: Use the project's loop gate between edits while
iterating; run the full gate as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the
next phase. In looped (`--loop`) execution, this phase's Automated
Verification gates advancement automatically (via `/wurk:commit --auto`), and
Manual Verification items are deferred and surfaced once at the end instead of
blocking here.

---

## Phase 3: Decide the rest of the manifest schema

### Overview

Walk wurk `docs/manifest.md`'s "Per-repo starting values" table and the
sections below it, record a decision for every field, and apply the three that
are not already correct. Because the manifest is strict JSON and cannot carry
comments, the decision table below is the record.

### The decisions

| Field | Decision | Reasoning |
|---|---|---|
| `repo.default_branch` | **Set explicitly** to `"main"` | Currently absent, so the loader's `"main"` default applies and behavior is already correct. Setting it is one line and defends a documented failure mode: `.quality.exs` already carries an explicit `base_ref: "origin/main"` because ExQuality's default-branch detection resolved `origin/master` here and silently widened the loop scope. Six wurk behaviors read this field (commit carve-out, sabotage pathspec, plan-doc bead resolution, worktree rebase and staleness, judge base ref); pinning it means none of them can be re-derived wrongly. |
| `rebase.auto_resolve_paths` | **Leave off** (no `rebase` section) | ADR-0010 starts every consumer at `[]` and asks for a narrow allowlist only where a file conflicts repeatedly. No such evidence exists here: plan and research documents are per-bead and never collide. The one plausible future candidate is `CHANGELOG.md`, whose `## [Unreleased]` section is the file parallel branches would both append to, and it would validate cleanly (disjoint from `gate.build_paths`, `also_gated_paths`, `moving_files`, `repair_when`, and `.claude/`). Revisit only if a conflict there actually recurs; opting in on speculation is what ADR-0010's default exists to prevent. |
| `beads.areas.always_batchable` | **Set** to `["upstream"]` | A real gap, not a copy of statifier-ex. CLAUDE.md's area-label section already names `upstream` as this repo's one class of bead that changes no files here, and one closed bead carries the label. Setting it gives `select_batch.rb` the `upstream` verdict and lets `/wurk:work` take its early-exit coordination path instead of standing up a worktree with nothing in it. A bead carrying it takes no `area:` label; the two are alternatives. |
| `models.direction` | **Set explicitly** to `"opus"` | Matches the doc's table and the loader default, so behavior does not change. Setting it anyway because the field exists precisely because two consumers disagreed on it, and the doc records that neither manifest set it for a while and both silently ran on the default - a drift that cost a research document (wu-ubm) to resolve. Wurk's own manifest sets it explicitly for the same reason. |
| `gate.attest` | **Leave off** | Tier 2 needs a command that re-verifies a green run independently. This repo has no `mix gate.verify` equivalent, and inventing one is a gate change (`area:build`, exclusive, human-reviewed under ADR-0005), not a config catch-up. `attested: false` with the stated degradation message is the honest report. |
| `gate.guard_ledger` | **Leave off** | The field points at a ledger recording deliberate gate-config changes. This repo solves the same problem differently and already: ADR-0008 plus the `Edit(.quality.exs)` / `Edit(.credo.exs)` / `Edit(coveralls.json)` deny rules in `.claude/settings.json`, with a legitimate change carrying `area:build`. Adding a ledger file would be a second, unmaintained record of the same decisions. |
| `gate.sabotage` | **Leave off** | The one row where this repo's table entry ("none") needs defending, because a sabotage discipline *does* exist here - CLAUDE.md's last Conventions bullet, with the enumerated list in `docs/research/260808-px-9ab-sabotage-notes.md`. But the disciplines are not the same shape: this repo requires a note only on the enumerated tests that bind an exported artifact to its source, and states outright that "Ordinary tests need no note", while the kit's scan flags *every* new test declaration in the diff with no `# sabotage:` note above it. Enabling it against an 82-file suite would report a finding on nearly every added test - noise that trains readers to ignore the field, which is the same failure `not_applicable_skips` exists to prevent in Phase 1. `enabled: false` with a stated reason is the honest state; narrowing the scan to the binding-test set would need `test_roots` granularity the field does not have. |
| `judge` | **Leave off** | Not in the bead's list, checked for completeness. Wurk is the only repo configuring it (ADR-0008 over its own `skills/**/SKILL.md`); no downstream consumer does, and this repo has no judgment-bearing prose corpus with a matching judged text. |
| Everything else in the table (`beads.prefix`, `topology`, `forge.kind`, `gate.full`/`loop`/`report`, `parallelism.model`, `tmux.session`, `artifacts.*`, `commits.*`, `changelog.mode`, `release`) | **Already correct** | Verified line by line against the "Per-repo starting values" table's predicator-ex column; every value matches. |

### Changes Required:

#### 1. The three applied fields

**File**: `.claude/wurk.json`
**Changes**: Add a `repo` section, add `always_batchable` inside
`beads.areas`, and add a `models` section. Field order follows the schema
document's own ordering, so a reader diffing against `docs/manifest.md` reads
top to bottom.

```json
  "repo": { "default_branch": "main" },

  "beads": {
    "prefix": "px",
    "topology": "beads",
    "areas": {
      "labels": ["..."],
      "lands_alone": ["area:build"],
      "always_batchable": ["upstream"]
    }
  },

  "models": { "direction": "opus" },
```

`models` goes between `tmux` and `artifacts`, matching the schema document's
layout. No other section moves.

### Success Criteria:

#### Automated Verification:

- [x] `ruby ~/.claude/skills/wurk:kit/scripts/lib/manifest.rb check` reports
      `ok: true` with no `blocked` entries and no unknown-key warnings.
- [x] The three fields load with the intended values:

      ```sh
      ruby -rjson -e 'm = JSON.parse(File.read(".claude/wurk.json"))
        p m["repo"]["default_branch"], m["models"]["direction"],
          m["beads"]["areas"]["always_batchable"]'
      ```

      prints `"main"`, `"opus"`, `["upstream"]`.
- [x] The fields deliberately left off are absent:
      `ruby -rjson -e 'm = JSON.parse(File.read(".claude/wurk.json")); g = m["gate"]
        p m.key?("judge"), m.key?("rebase"), g.key?("attest"),
          g.key?("guard_ledger"), g.key?("sabotage")'`
      prints five `false` values.
- [x] `ruby ~/.claude/skills/wurk:kit/scripts/gate.rb` reports `ok: true`, with
      `data.sabotage.enabled` still `false` and a stated `reason`, and
      `attested: false`.
- [x] The kit's own accessor returns the new value - the field is read through
      the loader, not merely present in the file:

      ```sh
      ruby -e 'require "/Users/johnnyt/repos/github/wurk/skills/wurk:kit/scripts/lib/manifest.rb"
        p Manifest.current.area_always_batchable'
      ```

      prints `["upstream"]`. (`select_batch.rb --help` is deliberately *not*
      used here: its `--help` exits inside argument parsing, before
      `Manifest.require!` is ever reached, so it would pass whether the field
      is well-formed, malformed, or absent.)

#### Manual Verification:

- [ ] Each row of the decision table is defensible on its own terms, and the
      three "leave off" rows state a reason specific to this repo rather than
      copying statifier-ex's column.
- [ ] The `gate.sabotage` row's disagreement with wurk `docs/manifest.md`
      ("predicator-ex ... ha[s] no sabotage-discipline corpus") is understood
      as a granularity mismatch, not an oversight in either document.
- [ ] A future `upstream` bead is reported by `/wurk:next` as the `upstream`
      verdict rather than being handed a worktree.

**Implementation Note**: Use the project's loop gate between edits while
iterating; run the full gate as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the
next phase. In looped (`--loop`) execution, this phase's Automated
Verification gates advancement automatically (via `/wurk:commit --auto`), and
Manual Verification items are deferred and surfaced once at the end instead of
blocking here.

---

## Testing Strategy

### Unit Tests:

None. This bead changes no Elixir code, so there is nothing for `test/` to
cover and no new code for `coveralls.json`'s 90% minimum to measure. The
`.claude/wurk/plan.md` extension's two always-required automated criteria
(coverage on new code, `StringVisitor` round-trip for a new AST node) and its
`### Integration Tests` subsection are inapplicable for the same reason. This
is stated rather than omitted so a reviewer can tell the difference between
"not applicable" and "forgotten" - the same distinction Phase 1 is about.

The suite must still be green, and is: 2,478 tests, 94.8% coverage on the
pre-change baseline. Nothing in this plan can move either number.

### Configuration Tests:

The manifest and extension files are exercised by the kit, not by
`mix quality`, so each phase's automated criteria are the tests:
`manifest.rb check` for schema validity, the classifier probe for Phase 1's
behavior, JSON field reads for Phase 3's, and path-existence checks for Phase
2's. All are deterministic and rerunnable.

### Manual Testing Steps:

1. After Phase 1, draft (do not open) a `/wurk:mr` request body for this
   branch and confirm the gate paragraph names Doctor and omits Gettext and
   Sobelow.
2. After Phase 2, spawn a `wurk-codebase-locator` with `codebase.md`'s content
   forwarded and confirm it orients without a discovery detour.
3. After Phase 3, read the decision table against wurk `docs/manifest.md`'s
   per-repo table and confirm every row is either applied or reasoned.
4. On the first branch after this one that touches `lib/`, run
   `ruby ~/.claude/skills/wurk:kit/scripts/gate.rb` and confirm the three
   stages classify as the Phase 1 table says. This is the deferred end-to-end
   check the carve-out makes impossible here.

## References

- Bead: `px-hhu`
- This repo: `.claude/wurk.json`, `.claude/wurk/research.md`,
  `.claude/settings.json`, `CLAUDE.md`, `docs/architecture.md`
- This repo's ADRs: `docs/adr/0004-no-eval-errors-are-values.md`,
  `docs/adr/0005-worktree-parallelism-and-the-area-label-algebra.md`,
  `docs/adr/0008-the-quality-gate-and-its-non-editable-config.md`,
  `docs/adr/0012-adopting-the-shared-wurk-workflow.md`
- This repo's sabotage discipline:
  `docs/research/260808-px-9ab-sabotage-notes.md`
- Wurk schema: `~/repos/github/wurk/docs/manifest.md`, sections
  "`gate.project_level_skips` and `gate.not_applicable_skips`",
  "`gate.sabotage`", "`rebase.auto_resolve_paths`",
  "`beads.areas.always_batchable`", "Two path lists, not one", and "Per-repo
  starting values"
- Wurk ADRs:
  `~/repos/github/wurk/docs/adr/0011-codebase-orientation-extension-file.md`,
  `0010-bounded-rebase-conflict-auto-resolution.md`,
  `0008-merge-time-judge-over-generic-skill-prose.md`,
  `0006-ruby-stdlib-scripts-with-envelope-contract.md`,
  `0004-manifest-and-extension-seams.md`
- Shape example: `~/repos/github/wurk/.claude/wurk/codebase.md`
- Kit: `~/.claude/skills/wurk:kit/REFERENCE.md`,
  `scripts/gate.rb:193-215` (`skipped_from`, `classify_skip`),
  `scripts/lib/manifest.rb:285-300` (`project_level_skip_re`,
  `not_applicable_skip_re`), `scripts/lib/gate_paths.rb` (`gate_applicable?`)

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

All nine were walked with the user on 2026-08-12 and are resolved below.

### Phase 1

- [x] Verified on this branch, not deferred: the carve-out did not bite,
      because the local `main` ref is behind and the diff picked up
      `lib/`/`test/` files, so `gate.rb` reported `applicable: true` and ran.
      `skipped_stages` classifies Doctor `project_level`, Gettext and Sobelow
      `not_applicable`, with the matching `stage_skipped_*` warnings.
- [x] `wurk:mr/SKILL.md:173-176` requires only `project_level` entries in the
      request body and exempts `not_applicable`; against the classification
      above that leaves Doctor alone.
- [x] `mix.exs` carries **zero runtime dependencies** - no Phoenix, no Plug,
      no Gettext - so neither a Sobelow scan nor an i18n stage can ever apply
      here. Doctor stays a genuine gap for the same reason.

**Implementation Note**: Use the project's loop gate between edits while
iterating; run the full gate as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the
next phase. In looped (`--loop`) execution, this phase's Automated
Verification gates advancement automatically (via `/wurk:commit --auto`), and
Manual Verification items are deferred and surfaced once at the end instead of
blocking here.

---

### Phase 2

- [x] Run as specified. The locator named `instructions.ex`, `evaluator.ex`,
      `instructions_visitor.ex`, `docs/isa.md` and `isa_sync_test.exs`, and
      reported it needed no discovery pass - only confirming greps anchored on
      `jump_backward`, which the "best search keys" line handed it. It also
      surfaced two files the Layout section did not name,
      `lib/predicator/errors.ex` and `lib/predicator/instructions/upgrade.ex`;
      both were added, paid for by compressing the visitors bullet, so the
      file is still 83 lines. A sweep of every `lib/**/*.ex` against the file
      now leaves only `lib/predicator/conformance/*.ex`, which its directory
      bullet covers.
- [x] All four reading rules are descriptive constraints on how to *describe*
      this code; none asks an agent to evaluate or propose.
- [x] The removed sections all landed in `codebase.md`, which
      `wurk:research/SKILL.md:124-125` pastes verbatim into every
      `wurk-codebase-*` spawn, so the content is reachable on more paths than
      before rather than fewer.

**Implementation Note**: Use the project's loop gate between edits while
iterating; run the full gate as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the
next phase. In looped (`--loop`) execution, this phase's Automated
Verification gates advancement automatically (via `/wurk:commit --auto`), and
Manual Verification items are deferred and surfaced once at the end instead of
blocking here.

---

### Phase 3

- [x] Walked row by row with the user and accepted. Each "leave off" row cites
      something local: no `mix gate.verify` task exists (`gate.attest`),
      ADR-0008 plus the `settings.json` deny rules already cover what
      `gate.guard_ledger` guards, there is no judged-text corpus (`judge`),
      and `rebase.auto_resolve_paths` stays off per ADR-0010's default against
      speculative opt-in.
- [x] Understood as a granularity mismatch and filed against the kit as
      **wu-4r7**, "Narrows gate.sabotage to enumerated binding tests": the
      discipline exists here but covers only the enumerated binding tests,
      while the kit's scan flags every new test declaration. `gate.sabotage`
      stays off here until the kit can be scoped; the manifest row is revisited
      when wu-4r7 lands.
- [x] `Manifest.current.area_always_batchable` returns `["upstream"]`,
      `Areas.upstream?(["upstream"])` is true and `["area:skills"]` false, and
      `select_batch.rb:232` turns that into the informational `upstream`
      verdict that never enters the recommended batch.

**Implementation Note**: Use the project's loop gate between edits while
iterating; run the full gate as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the
next phase. In looped (`--loop`) execution, this phase's Automated
Verification gates advancement automatically (via `/wurk:commit --auto`), and
Manual Verification items are deferred and surfaced once at the end instead of
blocking here.

---
