# Wurk Workflow Skill Adoption Implementation Plan

## Overview

Replace this repository's 14 in-tree skills (`.claude/skills/`) and 6 in-tree
research agents (`.claude/agents/`) with the shared `wurk:*` skill set installed
globally at `~/.claude/skills/wurk:*`, driven per-project by a
`.claude/wurk.json` manifest plus a small set of `.claude/wurk/*.md` extension
files. This is phase 3 of the wurk migration (upstream bead `wu-4tq`);
statifier-ex was the first consumer, and predicator-ex is the second - the one
that proves the manifest generalizes rather than merely describing statifier in
JSON.

Beads issue: **px-ttt** (labels `area:docs`, `area:skills`).

## Current State Analysis

**What exists in this repo today**

- `.claude/skills/` - 14 skills, 4,001 lines of `SKILL.md`, the pre-extraction
  reference implementation the wurk generic skills were ported from:
  `cleanup-worktrees`, `commit`, `create-issue`, `create-plan`,
  `implement-plan`, `iterate-plan`, `merge-request`, `new-worktree`,
  `next-issue`, `next-issues`, `refresh-worktree`, `release`,
  `research-codebase`, `work`.
- `.claude/agents/` - 6 agents (991 lines): `codebase-locator`,
  `codebase-analyzer`, `codebase-pattern-finder`, `thoughts-locator`,
  `thoughts-analyzer`, `web-search-researcher`. All six are triplicated across
  the three consumer repos and now live globally as `wurk-*` (wurk plan
  item 21), with a **double rename** on the thoughts pair:
  `thoughts-locator` -> `wurk-docs-locator`, `thoughts-analyzer` ->
  `wurk-docs-analyzer`.
- `.claude/settings.json` - a single `permissions.deny` block implementing
  ADR-0008 (bead px-rfn), with a long `_comment` explaining why `deny` and not
  `ask`, and why there are no `Write()` companions. **No hooks at all** - in
  particular no `SessionStart` `bd prime --hook-json` hook, even though
  `CLAUDE.md` says "Claude Code injects `bd prime` at session start" (wurk plan
  item 6).
- `CLAUDE.md` - the authority table, the area-label algebra, and a
  "Worktrees, skills, and area labels" table that names all nine old
  user-facing skills, plus a "Research agents" section naming all six
  unprefixed agents.
- No `config/` directory in this repo (verified: `ls config` fails).
- `mise.toml` is present; `mix.exs` holds `@version "4.0.0"` at line 5; the
  README install pin `{:predicator, "~> 4.0"}` is at `README.md:26`.
- `_build/dev/` holds `dialyxir_erlang-27.3.2_elixir-1.18.3_deps-dev.plt` (and
  an older 27.2/1.18.1 pair), so the PLT glob is
  `_build/dev/dialyxir_erlang-*_elixir-*_deps-dev.plt*`.

**What the gate actually does here** (verified by a real run in this worktree
on 2026-08-10, `mix quality --report -`, exit 0, 1,983 bytes of JSON on
stdout):

| Stage | Status | `summary` |
|---|---|---|
| Format | ok | `No changes needed` |
| Compile | ok | `dev + test compiled (warnings as errors)` |
| Doctor | **skipped** | `:doctor not installed` |
| Gettext | **skipped** | `:gettext not installed` |
| Sobelow | **skipped** | `:sobelow not installed` |
| Credo | ok | `No issues` |
| Dialyzer | ok | `No warnings` |
| Dependencies | ok | `No unused dependencies` |
| Tests | ok | `2,248 of 2,248 passed, 94.9% coverage` |

The report is emitted on stdout with the human-readable progress on stderr, so
`gate.report` is usable and this repo lands at **gate-contract tier 1**. The
three skipped stages are the ones `gate.project_level_skips` must cover, and
they are **not** statifier's list: statifier has no Sobelow skip (it ships a
`.sobelow-conf`) and carries two `.po` entries and a
`disabled in .quality.exs` entry that never fire here.

**Preconditions and hazards**

- The bead's precondition ("no live worktrees") is **already met for the two
  worktrees it names** - `px-2r5.5-cast-corpus-coverage` and
  `px-2r5.6-document-type-casts` are gone. `git worktree list` shows the main
  checkout plus **this** worktree, `px-ttt-adopt-wurk-skills`, which is the
  cutover worktree itself and is expected to be live.
- This worktree's own session was seeded with the OLD skill names. That is the
  central execution hazard of this plan and is stated in full under
  "Implementation Approach".
- The bead's stated validator path is wrong: it says
  `ruby ~/.claude/skills/wurk:kit/scripts/manifest.rb check`, but the loader
  lives at `~/.claude/skills/wurk:kit/scripts/lib/manifest.rb`
  (`docs/manifest.md` "Validation" is the authority). Use the `lib/` path.

## Desired End State

- `.claude/wurk.json` exists, describes this repo exactly, and
  `ruby ~/.claude/skills/wurk:kit/scripts/lib/manifest.rb check` exits 0
  against it.
- `.claude/wurk/` holds eleven extension files - the bead's six (`plan.md`,
  `iterate.md`, `research.md`, `work.md`, `commit.md`, `release.md`) plus five
  the loss audit requires (`implement.md`, `mr.md`, `issue.md`, `branch.md`,
  `next.md`) - each of which **adds** predicator-specific content and restates
  nothing from the generic skill.
- `.claude/skills/` and `.claude/agents/` are gone.
- `.claude/settings.json` keeps the ADR-0008 deny block **verbatim** and gains
  the `SessionStart` `bd prime --hook-json` hook.
- `CLAUDE.md` and every other tracked document name `wurk:*` skills and
  `wurk-*` agents; `git grep` finds no live reference to a deleted name.
- `px-uio` is closed as superseded by wurk bead `wu-lyc`, in the same commit
  that deletes `.claude/skills/`.
- `ruby ~/.claude/skills/wurk:kit/scripts/gate.rb` reports `ok` on a clean tree
  with no `stage_skipped` block (only `stage_skipped_project_level` warnings
  for Doctor/Gettext/Sobelow).
- A new ADR (ADR-0012) records the adoption and what deliberately stays local.
- Full `mix quality` green.

### Key Discoveries

- `mix quality --report -` works here and emits the ex_quality JSON report
  (`.quality.exs:17`'s "prefer `--format json`" header comment is an older
  spelling of the same behavior, not a contradiction; ex_quality 0.13.0 is
  pinned in `mix.lock` and is the current release). Settled in the bead notes.
- `gate.rb` classifies a skip by regex-matching the stage's `summary` against
  `gate.project_level_skips` (`scripts/gate.rb:184-203`); with no report there
  are no skip records at all, so tier 1 is the mechanism the skip taxonomy
  depends on - not optional dressing.
- `tmux_window.rb:35`'s `FINISH_TEMPLATE` appends "finish with
  `/wurk:commit --auto`" to every seeded prompt, and `/wurk:branch` seeds
  `/wurk:work` as the orchestrator. Both name post-adoption skills already.
- `wurk:kit/REFERENCE.md:325-370` documents both recommended consumer settings
  blocks - the `bd prime` hook (which this repo lacks) and the gate-config deny
  rules (which this repo already has, and which the kit now recommends to
  everyone on the strength of this repo's version).
- `docs/manifest.md:232-250`: `beads.areas.always_batchable` and
  `gate.attest`/`gate.guard_ledger` are optional; absent means off, and absent
  `project_level_skips` means every skipped stage blocks.
- The generic `/wurk:commit` takes `--auto` as its first argument-hint
  (`wurk:commit/SKILL.md:5`), and `/wurk:implement --loop` uses
  `/wurk:commit --auto` as the per-phase advancement gate
  (`wurk:implement/SKILL.md:128-163`).

## What We're NOT Doing

- **No alias shims.** Typing `/commit`, `/work`, `/next-issue` in this repo
  will stop working. Settled upstream as wurk plan item 14; retrain to
  `/wurk:*`.
- **Not porting `settings.local.json`.** Its ~190 accumulated allow entries are
  organic accretion, not workflow dependencies (item 20). Running
  `/fewer-permission-prompts` after adoption is a reasonable follow-up and is
  out of scope here.
- **Not adopting `beads.areas.always_batchable: ["upstream"]`.** Settled in the
  bead notes: the field makes a bead *pickable*, and `/wurk:next` would then
  stand up a full warmed Elixir worktree for work happening in a different
  repository. Revisit after wurk `wu-lyc` lands.
- **Not declaring `gate.attest`** (`mix gate.verify` does not exist here - that
  is statifier's ADR-0011) **or `gate.guard_ledger`** (no
  `docs/quality-gate-changes.md` here; ADR-0008's deny rules are this repo's
  equivalent protection).
- **Not declaring `gate.sabotage`.** This repo's sabotage discipline is a
  narrow enumerated list of binding tests
  (`docs/research/260808-px-9ab-sabotage-notes.md`), not statifier's
  every-new-test protocol; the kit's scan would flag every ordinary test.
  Deliberately off - see the loss audit in Phase 5.
- **Not fixing the wider claim race.** `/wurk:next` keeps the select-then-claim
  window with a `bd_claim_failed` fallback rather than this repo's old atomic
  `bd ready --claim --json`. A knowing one-race-window regression, owed
  upstream as wurk `wu-z6n`, not a bug to fix here.
- **Not changing any Elixir source, the ISA, the corpus, or the gate config.**
- **No push, no PR, no `mix hex.publish`.**

## Implementation Approach

Phase order is fixed by the bead's DESIGN section and is not negotiable:

1. **Manifest first**, because `lib/manifest.rb check` is the mechanical
   validator everything after it leans on.
2. **Extensions second**, because they are written *from* the 14 old skills,
   which phase 3 deletes. Writing them afterwards means reconstructing from git
   history.
3. **Deletion third**, with the settings reconciliation and the `px-uio` close
   in the same commit.
4. **Docs last**, because the cross-reference sweep can only be verified once
   the old names are actually gone.

Phase 5 (end-to-end verification and the loss audit) follows, and adds nothing
to that ordering - it verifies the result.

### CRITICAL: the commit skill changes hands at Phase 3

**Phase 3 deletes `.claude/skills/`, which contains this repo's own `/commit`
and `/implement-plan` skills.** The implementation loop uses `/commit --auto`
as its per-phase advancement gate, so the gate itself disappears mid-plan.
This is the single most likely way for this plan to fail confusingly, so it is
stated here rather than in a footnote:

| Phase | Commit with |
|---|---|
| Phase 1 (manifest) | **local `/commit --auto`** |
| Phase 2 (extensions) | **local `/commit --auto`** |
| **Phase 3 (deletion + settings)** | **global `/wurk:commit --auto`** |
| Phase 4 (docs) | **global `/wurk:commit --auto`** |
| Phase 5 (verification) | **global `/wurk:commit --auto`** (only if it edits anything) |

Both spellings are verified real: the local skill is
`.claude/skills/commit/SKILL.md`, and the global one is
`~/.claude/skills/wurk:commit/SKILL.md`, whose frontmatter declares
`name: wurk:commit` and `argument-hint: ["--auto", "optional: bead ID"]`. The
argument form is identical; only the skill name changes.

Two consequences a human or an orchestrator must plan around:

- **Do not run this plan under `/implement-plan --loop`.** That loop invokes
  the local `/commit --auto` for every phase and will lose its advancement gate
  the moment Phase 3 lands. Run the phases interactively, or run Phases 1-2
  under `/implement-plan --loop` and Phases 3-5 under `/wurk:implement --loop`
  with `--from-phase 3`. The second option is the intended path and is the
  reason each phase below is independently committable.
- **This worktree's own tmux session was seeded with the old names.** Its
  finishing clause says `/commit --auto`. After Phase 3 lands, that clause is
  dead in this session. Nothing needs repairing - just use `/wurk:commit`
  from that point on. Every *future* seeded session gets the correct clause
  from `tmux_window.rb` automatically.

### The gate is mostly not applicable here

Every phase of this plan touches only `.claude/**`, `docs/**`, and `CLAUDE.md`.
None of those is in `gate.build_paths` or `gate.also_gated_paths`, so
`gate.rb` will report the carve-out (`applicable: false`) and the phase commits
on review of the diff alone - which the repo's authority table explicitly
allows ("a change touching no Elixir code has no gate to run and may commit on
review of the diff alone"). Each phase below says so in its own Automated
Verification list rather than pretending a gate ran. A full `mix quality` is
still run once, at Phase 5, to satisfy the bead's "Full `mix quality` green"
acceptance criterion against the finished tree.

---

## Phase 1: The manifest

### Overview

Write `.claude/wurk.json` with this repo's real values, deriving the two gate
values the bead requires be derived rather than copied.

`area:skills`.

### Changes Required

#### 1. Derive `gate.report` from a real run (do this first)

**Command**:

```bash
mix quality --report - > /tmp/px-ttt-gate.json
echo "exit=$?"
ruby -rjson -e 'j=JSON.parse(File.read("/tmp/px-ttt-gate.json")); \
  puts j["status"]; j["stages"].each { |s| puts "#{s["name"]}\t#{s["status"]}\t#{s["summary"]}" }'
```

This must print a parseable JSON status and one line per stage. If it does not
emit a report, `gate.report` is **omitted** (the bead is explicit: a report
command that emits nothing is worse than none) and this plan's tier-1
assumptions - including `gate.project_level_skips` - are void, which is a
stop-and-report condition, not something to work around.

Baseline recorded 2026-08-10: exit 0, report emitted, `status: "ok"`, nine
stages, three skipped.

#### 2. Derive `gate.project_level_skips` from that same run

Take the `summary` string of every stage whose `status` is `skipped` and anchor
it as a regex. From the recorded run that is exactly three:

```json
"project_level_skips": [
  "^:doctor not installed$",
  "^:gettext not installed$",
  "^:sobelow not installed$"
]
```

Anchored and literal on purpose. A *new* skip - Dialyzer skipping because the
PLT is missing, Tests skipping because compilation half-failed - must still
block, because it means the gate could not measure something. Do not copy
statifier's list: it lacks Sobelow and carries `.po` and
`disabled in .quality.exs` entries that never fire in this repo.

#### 3. Write `.claude/wurk.json`

**File**: `.claude/wurk.json` (new)

```json
{
  "wurk": 1,

  "beads": {
    "prefix": "px",
    "topology": "beads",
    "areas": {
      "labels": [
        "area:lexer-parser",
        "area:evaluator",
        "area:context",
        "area:functions",
        "area:visitors",
        "area:api",
        "area:conformance",
        "area:skills",
        "area:docs",
        "area:build"
      ],
      "lands_alone": ["area:build"]
    }
  },

  "forge": { "kind": "github", "labels": {} },

  "gate": {
    "full": ["mix", "quality"],
    "loop": ["mix", "quality", "--profile", "loop"],
    "report": ["mix", "quality", "--report", "-"],
    "build_paths": ["lib/", "test/", "mix.exs", "mix.lock"],
    "also_gated_paths": ["conformance/"],
    "moving_files": [".quality.exs", ".credo.exs", "coveralls.json"],
    "project_level_skips": [
      "^:doctor not installed$",
      "^:gettext not installed$",
      "^:sobelow not installed$"
    ]
  },

  "parallelism": {
    "model": "worktree-per-issue",
    "worktrees_dir": "../predicator-ex-worktrees",
    "trust": ["mise", "trust", "{path}"],
    "warm_clone": ["deps", "_build", "priv/plts"],
    "warm_globs": ["priv/plts/dialyzer.plt*"],
    "warm": [["mix", "deps.get"]],
    "repair_when": "mix.lock",
    "repair": [["mix", "deps.get"]],
    "post_branch": []
  },

  "tmux": { "session": "predicator-ex", "model": "opus" },

  "artifacts": {
    "plans": "docs/plans",
    "research": "docs/research",
    "filename": "YYMMDD-[id-]kebab"
  },

  "commits": {
    "style": "s-form",
    "subject_under": 50,
    "body_line_max": 72,
    "total_lines_max": 40,
    "trailer": { "key": "Refs" }
  },

  "changelog": { "mode": "keep-a-changelog" },

  "release": {
    "kind": "hex",
    "version_file": "mix.exs",
    "readme_pin": true,
    "changelog": "CHANGELOG.md"
  }
}
```

Deliberate divergences from statifier's manifest, each with its reason:

| Field | Value here | Why not statifier's |
|---|---|---|
| `gate.build_paths` | no `config/` | this repo has no `config/` directory (nor `src/`) |
| `gate.also_gated_paths` | `["conformance/"]` | statifier's is empty. `test/predicator/conformance/corpus_freshness_test.exs` measures the corpus tree, so a corpus-only diff must **not** get the commit carve-out. Missing this is the exact failure `docs/manifest.md:171-186` warns about |
| `parallelism.warm_globs` | `priv/plts/dialyzer.plt*` | statifier's dialyxir PLT lives under `_build/dev/`; **this repo pins it** to `priv/plts/dialyzer.plt` (`mix.exs:41`), and `priv/plts/` is gitignored (`.gitignore:23`). `warm_clone` gains `priv/plts` for the same reason |
| `gate.attest` | omitted | no `mix gate.verify` here (statifier ADR-0011) |
| `gate.guard_ledger` | omitted | no `docs/quality-gate-changes.md`; ADR-0008's deny rules are the protection |
| `gate.moving_files` | `.quality.exs`, `.credo.exs`, `coveralls.json` | **this repo is the reference**: `coveralls.json` belongs and statifier's refresh had dropped it. Do not flatten toward statifier |
| `gate.sabotage` | omitted | see "What We're NOT Doing" |
| `beads.areas.always_batchable` | **omitted** | settled in the bead notes |
| `models.direction` | omitted | the default is `opus`, which is this repo's value; statifier's `fable` is the divergence the field exists for (item 10) |
| `changelog.mode` | `keep-a-changelog`, no `dir` | this repo edits `CHANGELOG.md`'s `## [Unreleased]` directly; **first non-fragment consumer** |
| `release` | a hex recipe | statifier's is `null`; **first non-null recipe** |

#### 4. Validate

```bash
ruby ~/.claude/skills/wurk:kit/scripts/lib/manifest.rb check
```

Note the `lib/` path - the bead's copy of this command omits it and will not
resolve. Unknown-key warnings do not fail the check; a missing required key
does.

### Success Criteria

#### Automated Verification

- [x] `mix quality --report -` emits a parseable JSON report and exits 0
- [x] Every `skipped` stage's `summary` in that report is matched by an entry
      in `gate.project_level_skips`, and no `ok` stage's summary is
- [x] `ruby ~/.claude/skills/wurk:kit/scripts/lib/manifest.rb check` exits 0
- [x] `ruby ~/.claude/skills/wurk:kit/scripts/gate.rb` reports `ok` with no
      `stage_skipped` block (three `stage_skipped_project_level` warnings are
      expected and correct)
- [x] `git diff --stat` touches only `.claude/wurk.json` - no Elixir code, so
      the gate carve-out applies and the diff review is the bar

#### Manual Verification

- [ ] `beads.areas.labels` matches CLAUDE.md's area-label table exactly, all
      ten, in the same spelling
- [ ] `always_batchable` is absent from the file, not present-and-empty
- [ ] `warm_globs` matches an actual file: `ls priv/plts/dialyzer.plt*`
- [ ] `conformance/` is in `also_gated_paths`, so a corpus-only diff is not
      carved out of the gate

**Implementation Note**: commit this phase with the **local `/commit --auto`**
- `.claude/skills/commit/` still exists at this point.

---

## Phase 2: The extension files

### Overview

Write the `.claude/wurk/*.md` files that carry everything predicator-only out
of the 14 skills and into the extension layer. Extensions **add**; they
never restate the generic skill and never override it. If a generic skill needs
different behavior, the manifest schema is missing a field - that is an
upstream wurk change to `lib/manifest.rb` + `docs/manifest.md` in one commit,
not a forked skill.

Statifier's six files are the shape to copy: 20-98 lines each, short and
specific.

**The bead names six files. This plan writes eleven.** A pre-flight inventory
of all 14 old skills and all 6 old agents against the wurk generic skills found
substantial predicator-only content in five more places: `/wurk:implement`,
`/wurk:mr`, `/wurk:issue`, `/wurk:branch` and `/wurk:next`. The bead's final
acceptance criterion is that anything in the old skills landing in neither wurk
nor an extension file is "named as deliberately dropped, or is a bug" - and
none of the five bodies of content below is droppable, so writing only the six
would guarantee five findings in Phase 5's audit. The six are required; the
five are what the audit would otherwise force back in.

`area:skills`.

### Changes Required

#### 1. `.claude/wurk/plan.md`

Sourced from `.claude/skills/create-plan/SKILL.md`. Content:

- The **`## ISA Impact` section** this repo's plans require, reproduced with
  its three mechanical questions (version / stamp / migration) from
  `create-plan/SKILL.md:374-393`, and the rule that it is omitted entirely when
  no opcode changes.
- ADR-0003: the Elixir implementation leads the ISA; a sibling behind the
  current version is expected, not a blocker.
- `docs/isa.md` is the authority for any ISA question.
- Optional sections this repo's plans carry: `## Performance Considerations`.
- Phase-splitting along this pipeline's seams: lexer, parser,
  compiler/instructions, evaluator, visitors - and that a grammar change
  `StringVisitor` cannot render back is an incomplete change.
- The precedence rule: check `docs/architecture.md`'s grammar and precedence
  table before proposing syntax; precedence is a whole-language decision.
- Corpus criteria: when a phase can move the exported specification,
  `mix corpus.generate` and the ADR-0003 obligation to explain a corpus diff.
- Required reading for a plan: `docs/adr/`, ADR-0001 (the 3.6-4.0 arc; the
  stack VM stays), ADR-0003 (this repo is the ISA reference implementation),
  `docs/architecture.md`.
- The always-wanted success criteria: coverage stays above the 90% minimum in
  `coveralls.json`; a new node type round-trips through `StringVisitor`.
- The testing-strategy shape this repo's plans use: `test/predicator/**` in
  pattern-matching style, an **Integration Tests** subsection naming
  `Predicator.evaluate/3` and `test/predicator/integration/`, and the edge
  cases that actually bite (precedence, type mismatches, error positions).
- Common patterns: new syntax (lexer -> parser precedence -> the precedence
  table in `docs/architecture.md` -> `InstructionsVisitor` + `StringVisitor` ->
  evaluator -> ISA move) and new functions (`lib/predicator/functions/`, arity
  and type checks as `{:ok, _} | {:error, _}` values, cover the error paths -
  they are the coverage gap the gate finds).
- Code conventions a plan must respect: `@doc`/`@spec` on public functions,
  errors as values never raised at a leaf, no `eval` or dynamic execution.

`wurk:plan` treats extension-declared sections as being as mandatory as its own
nine, so declaring `## ISA Impact` here is what re-arms it.

#### 2. `.claude/wurk/iterate.md`

Sourced from `.claude/skills/iterate-plan/SKILL.md`. Deliberately thin -
`/wurk:iterate` already reads `.claude/wurk/plan.md`, so this file must not
duplicate it. Content: preserve an `## ISA Impact` section when a phase
carrying one is split or re-cut; a re-cut phase that silently loses its ISA
stamp is a regression in the plan.

#### 3. `.claude/wurk/research.md`

Sourced from `.claude/skills/research-codebase/SKILL.md`. Content:

- The pipeline vocabulary: source -> lexer -> parser -> AST -> compiler /
  `InstructionsVisitor` -> flat instruction list -> stack VM evaluator, plus
  the visitor round-trip path.
- The tree map: `lib/predicator/{lexer,parser,types,compiler,evaluator,
  duration,context_location,visitor}.ex`, `lib/predicator/functions/**`,
  `lib/predicator/visitors/**`, `conformance/**`.
- **Sibling-port guidance**: the Ruby and JavaScript implementations in the
  `riddler/predicator` monorepo. Point a sub-agent there explicitly and only
  when the question genuinely involves sibling behavior.
- **ADR-0003 and ADR-0010's ownership rule**: the repository whose files change
  owns the decision. For the language, the ISA, the compiled format, the
  corpus, and release schedule that is this repo; for how statifier consumes
  any of it, statifier's bead is authoritative.
- Good search keys: opcode names (`lit`, `load`, `compare`, `object_new`,
  `jump_if_false`), `docs/isa.md` section numbers, AST node tags, "corpus",
  "conformance", "instruction", "visitor", "precedence", "short-circuit",
  "duration", "span", "on_unbound".
- **The doc roots beyond `plans`/`research`**: `docs/adr/`, `docs/design/`,
  `docs/guides/`, `docs/reference/`, `docs/architecture.md`. The wurk docs
  agents glob a conventional candidate set that does **not** include
  `docs/guides/` or `docs/reference/`, so naming them here is what keeps them
  searched.
- `docs/architecture.md` carries per-feature history with version numbers, and
  it plus `CHANGELOG.md` is the fastest answer to "when and why did this
  arrive".
- **The ADR-0003/ADR-0001 rule** (highest-value item in this file): ADR-0003
  *amends* ADR-0001 without superseding it. Never resurface ADR-0001's
  cross-language-interchange framing as live. A decision's ISA effect is a
  versioning and stored-artifact question, never a sibling-readiness one.
- A research document in this repo carries its own `## ISA Impact` section when
  the subject touches the instruction set.

#### 4. `.claude/wurk/work.md`

Sourced from `.claude/skills/work/SKILL.md`. Content: **the ISA sizing rule** -
a bead that adds, removes, renames, or alters an opcode is never a
just-do-it-sized job. It moves the exported specification (ADR-0003) and owes a
version, a `docs/isa.md` entry, a conformance-corpus tier, and a migration note,
so it goes plan-first at minimum - with the carve-out that touching instruction
*handling* without altering an opcode does not bump. Also:

- Sizing triggers phrased in this pipeline's terms: anything crossing more than
  one `area:` label starts at plan-first at the latest.
- The Direction bucket's reading list (`docs/adr/`, `docs/architecture.md`,
  `docs/reference/language.md`) and this repo's **ADR authoring rules**: next
  free number, **register it in `docs/adr/README.md`'s index**, and **no
  `proposed` status** - narrower calls go to `docs/research/` instead. Neither
  the index step nor the no-`proposed` rule has any generic equivalent.
- The closing report states whether the work moved the ISA and to what version,
  so it reaches the commit message and the PR body.

#### 5. `.claude/wurk/commit.md`

Sourced from `.claude/skills/commit/SKILL.md`. Content:

- **ISA-bump analysis**: before committing, ask whether the diff touches
  `lib/predicator/instructions.ex`, `docs/isa.md`, or the corpus. If it moves
  the instruction set, the commit owes the version, the `docs/isa.md` entry,
  and a corpus explanation in the message body (ADR-0003).
- **A corpus diff gets explained** in the commit message and the PR body -
  `conformance/corpus/*.json` and `conformance/manifest.json` are generated,
  never hand-edited; the authored source is `conformance/cases/*.json`.
- **An explicit warning against the changelog-fragment workflow**: this repo is
  `changelog.mode: keep-a-changelog`. Add entries **directly** under
  `## [Unreleased]` in `CHANGELOG.md`. There is no `changelog.d/`, and
  statifier's fragment instructions must never be applied here. Promoting
  `## [Unreleased]` to a version header is release work under CLAUDE.md's
  authority table, not commit work (wurk plan item 17 - this is the repo where
  that confusion would land).
- The binding-test sabotage note convention: the enumerated tests that bind an
  exported artifact to its source carry a sabotage note; ordinary tests do not
  (`docs/research/260808-px-9ab-sabotage-notes.md`). State the narrow scope
  explicitly so nobody imports statifier's every-new-test protocol.
- Diff-classification vocabulary for the commit body: tokens, AST nodes,
  instructions/opcodes, visitors, corpus tiers.
- **The stale-corpus recovery**, which is a live failure mode: when
  `corpus_freshness_test.exs` is red the fix is always `mix corpus.generate`
  plus reading the diff - **never** an edit to `conformance/corpus/` or
  `conformance/manifest.json` to go green. A surprising diff is a finding.
- The definition of "user-facing" here: predicator is a published Hex package,
  so a user is anyone calling `Predicator.evaluate/3` or writing predicate
  source. A new operator, function, or instruction qualifies.
- No version-bump ritual on a feature branch: `@version` in `mix.exs` moves
  only for a named release.

#### 6. `.claude/wurk/release.md`

Sourced from `.claude/skills/release/SKILL.md`. Content:

- Hex recipe detail beyond the manifest fields: `@version` is `mix.exs:5`; the
  README pin is the `{:predicator, "~> 4.0"}` snippet at `README.md:26` and
  moves only on a major/minor bump; `## [Unreleased]` in `CHANGELOG.md` is
  promoted to a dated version header.
- **`mix hex.publish` has no trigger, ever.** It is not delegable and no
  instruction in a session grants it (CLAUDE.md's authority table; ADR-0006).
  Tag and push stay separately human-gated.
- The release trigger: the user explicitly asks **and** names the version.
  Never inferred from a merged PR, accumulated `Unreleased` entries, or
  "ship it".
- The README pin's exact form - `{:predicator, "~> X.Y"}`, patch dropped - so
  the edit is unambiguous. `release.readme_pin: true` only says a pin exists.

#### 7. `.claude/wurk/implement.md`

Sourced from `.claude/skills/implement-plan/SKILL.md`. **This file is passed by
path to `--loop` phase subagents that have no other context**, so it must need
no external read to follow. Content:

- **The pipeline-completeness rules**: source -> tokens -> AST -> instructions
  -> stack VM. A syntax change that compiles to nothing, or an instruction
  nothing emits, is half-finished. **A grammar change is not done until
  `StringVisitor` round-trips it.** An opcode change moves the ISA (ADR-0003)
  and carries its version, `docs/isa.md` entry, and migration note into the
  commit message and PR body.
- **The corpus discipline**: when `corpus_freshness_test.exs` is red the fix is
  `mix corpus.generate` plus reading the diff; generated files are never
  hand-edited. This is the single most consequential item in the file - an
  agent editing `conformance/corpus/*.json` to go green is a live failure mode.
- Errors are values: never raise at a leaf, never rescue-to-default. No `eval`,
  `Code.eval_string`, or dynamic dispatch on user input.
- The Credo note: complexity suppressions in the lexer and parser are
  deliberate and are not a licence to add more.
- **Never weaken the gate**: no lowered coverage threshold, no
  `enabled: false`, no `--skip-*` on the final check, no `@tag :skip`. Report
  and let a human decide. Restated here because this repo has no
  `gate.attest`/`gate.guard_ledger`, so wurk's substitute mechanism never
  fires - CLAUDE.md and the ADR-0008 deny rules are the only other statement.
- Cover the error paths: the uncovered lines the gate finds are almost always
  the `{:error, _}` branches.
- **The two debugging moves** (the generic skill has an explicit hole for
  exactly this): for a parse or precedence surprise, read the precedence table
  in `docs/architecture.md` - the table is the specification; for an evaluation
  surprise, print the compiled instruction list.
- `test/docs_examples_test.exs` executes the examples in `docs/`, so a
  documentation edit can turn the suite red. Doctests are executed tests.
- The conventions clause a fresh subagent will not otherwise have read:
  `@doc`/`@spec`, `{:ok, _} | {:error, _}`, no `eval`, work lands on a feature
  branch and never on `main`.

#### 8. `.claude/wurk/mr.md`

Sourced from `.claude/skills/merge-request/SKILL.md`. Content:

- The PR body states an ISA move: the version it lands at, its `docs/isa.md`
  entry, any migration note (ADR-0003). A sibling that has not adopted is not a
  blocker.
- The **Corpus section** of the PR body: name the cause and the case ids. The
  corpus is the exported specification; the suite proves freshness, never
  wantedness.
- **This repo is rebase-merge-only**, asserted as fact. The generic skill
  states the rule conditionally ("where the project merges by rebase") and no
  manifest field carries the setting, so the assertion has to live here.
  CLAUDE.md's merge-policy section is the reference.
- The public-surface test for whether a changelog entry is owed.

#### 9. `.claude/wurk/issue.md`

Sourced from `.claude/skills/create-issue/SKILL.md`. The manifest carries the
area labels only as a **name list**; the per-label path mapping and its
disambiguation have no generic home. Content:

- The `area:` label -> path mapping from CLAUDE.md, in full.
- **The `area:conformance` vs `area:build` disambiguation**: `area:conformance`
  covers `conformance/**`, `lib/predicator/conformance/**`,
  `lib/mix/tasks/corpus.*.ex` and is deliberately *not* `area:build`; a
  conformance bead that also edits `mix.exs` carries **both** and then lands
  alone. This was mis-labeled once already and serialized the queue
  (`docs/research/260807-px-phw-conformance-area-label.md`).
- `area:api` is the cross-cutting surface (`lib/predicator.ex` + the error
  structs); a bead that adds a function *and* exposes it carries both labels.
- A change to the instruction set is **not** automatically `upstream`: the
  Elixir side is real work here (ADR-0003). Sibling adoption is its own
  `upstream` bead and is **never a dependency** of the Elixir work.
- Dependency links follow the real build order (lexer before parser, parser
  before compiler); epics mirror ADR-0001's release arcs.

#### 10. `.claude/wurk/branch.md`

Sourced from `.claude/skills/new-worktree/SKILL.md`. Content:

- Why the PLT clone works and matters: `mix.exs:41` pins the PLT to
  `priv/plts/dialyzer.plt`; dialyxir keys it on OTP/Elixir versions and the dep
  set via the adjacent `.hash`, so a cloned PLT is picked up as-is and full
  `mix quality` skips a multi-minute build.
- **The recovery command when `priv/plts/` is empty**: `mix dialyzer --plt`,
  once, in either checkout. The generic skill emits a `warm_cache_missing`
  warning and says to suggest rebuilding it **without naming the command** - so
  the command is lost unless this file carries it.
- `deps/`, `_build/` and `priv/plts/` are gitignored, so the clones never
  appear in `git status`; `mise.toml` pins OTP and Elixir, so a PLT rebuild
  should be rare.

#### 11. `.claude/wurk/next.md`

Sourced from `.claude/skills/next-issues/SKILL.md`. Two items:

- The batching heuristic: **watch `area:api` in particular** - it covers
  `lib/predicator.ex` and the error structs, which is where a surprising number
  of otherwise-disjoint beads eventually meet.
- `bd bootstrap` on a fresh clone with no `.beads/embeddeddolt/`. Not
  predicator-specific, but `/wurk:next` has no equivalent anywhere, so it is
  otherwise lost. **File this upstream against wurk as well** - an extension
  file carrying a generic gap is a stopgap, not the fix.

### Success Criteria

#### Automated Verification

- [x] All eleven files exist under `.claude/wurk/` and are non-empty:
      `plan`, `iterate`, `research`, `work`, `commit`, `release`, `implement`,
      `mr`, `issue`, `branch`, `next`
- [x] Each filename matches a real generic skill: for each `f` in
      `.claude/wurk/*.md`, `~/.claude/skills/wurk:$(basename $f .md)` exists -
      an extension whose skill does not exist is never read
- [x] `grep -c '' .claude/wurk/*.md` shows each file under ~110 lines - the
      statifier band (20-98) is the target; a long file is a sign it is
      restating the generic skill
- [x] No extension file contains the string "override" applied to generic
      behavior, and none instructs the reader to ignore a generic step
- [x] `git diff --stat` touches only `.claude/wurk/` - gate carve-out applies

#### Manual Verification

- [ ] Each file names the generic skill it extends and says "adds only"
- [ ] `commit.md`'s changelog section cannot be misread as endorsing fragments
- [ ] `iterate.md` does not duplicate `plan.md`
- [ ] `implement.md` is self-contained - a phase subagent handed only its path
      can follow it with no other read
- [ ] `commit.md` and `implement.md` do not contradict each other on the corpus
      discipline (one states the commit-time refusal, the other the protocol)
- [ ] Reading each extension alongside its generic skill, no instruction
      contradicts the generic one

**Implementation Note**: commit this phase with the **local `/commit --auto`** -
`.claude/skills/commit/` still exists. This is the **last** phase for which
that is true.

---

## Phase 3: Delete the old surface, reconcile settings, close px-uio

### Overview

Delete the 14 skills and 6 agents, add the missing `bd prime` hook while
keeping the ADR-0008 deny block verbatim, and close `px-uio` as superseded - all
in one commit.

`area:skills`.

**From this phase onward, commit with the global `/wurk:commit --auto`.** The
local `/commit` skill is one of the files this phase deletes.

### Changes Required

#### 1. Delete the in-tree skill and agent surface

```bash
git rm -r .claude/skills .claude/agents
```

Both trees are recoverable from git history; wurk plan "Risks and rollback"
makes reverting the adoption commit the rollback path.

#### 2. Reconcile `.claude/settings.json`

**File**: `.claude/settings.json`

**Keep verbatim**: the entire `_comment` string and the three
`permissions.deny` entries. Not one character changes. This repo is **ahead**
of statifier here - statifier has no deny rules at all, and
`wurk:kit/REFERENCE.md:344-370` now recommends this exact pattern to every
consumer on the strength of it. Do not flatten toward statifier's
hooks-only file.

**Add** the SessionStart hook (wurk plan item 6; the block is
`REFERENCE.md:331-336`, identical to statifier's `settings.json`):

```json
"hooks": {
  "SessionStart": [
    { "matcher": "", "hooks": [{ "type": "command", "command": "bd prime --hook-json" }] }
  ]
}
```

This repo has never had it, even though `CLAUDE.md` says the injection happens.

**Do not touch `settings.local.json`.**

#### 3. Close px-uio as superseded

```bash
bd note px-uio "Superseded by wurk bead wu-lyc. Its acceptance criteria name \
/work, /next-issue and /next-issues, all deleted by px-ttt; both of its asks \
(no-workspace exit for upstream beads, type:decision -> Direction bucket) were \
verified unmet in wurk on 2026-08-10 and refiled there as wu-lyc."
bd close px-uio
```

**Authorization**: CLAUDE.md's authority table normally gates `bd close` on a
verified merge into `origin/main`. **px-ttt explicitly overrides that for
px-uio**, and the authorization is the bead's own notes section
("ACTION FOR THIS BEAD: close px-uio as superseded by wu-lyc, in the same
commit that deletes `.claude/skills/`"), reinforced by the acceptance criterion
of the same name. The override is narrow: it covers `px-uio` only, and no other
bead's close is unblocked by this plan. The reason it cannot wait for the merge
is that px-uio's acceptance criteria name three skills this commit deletes -
leaving it open past this commit means leaving a bead pointing at files that do
not exist.

#### 4. Prose that names a deleted agent, in this same commit

Item 21: the unprefixed agent names stop resolving the moment the local copies
go, so any prose still naming them must be updated here, not in Phase 4. Grep
for **both** forms of the double rename:

```bash
git grep -n 'thoughts-locator\|thoughts-analyzer\|codebase-locator\|codebase-analyzer\|codebase-pattern-finder\|web-search-researcher'
git grep -n '\bdocs-locator\|\bdocs-analyzer'
```

Rename to `wurk-docs-locator`, `wurk-docs-analyzer`, `wurk-codebase-locator`,
`wurk-codebase-analyzer`, `wurk-codebase-pattern-finder`,
`wurk-web-search-researcher`. CLAUDE.md's "Research agents" section is the
known hit; take any others the grep finds. (CLAUDE.md's skill *table* is
Phase 4's job; the agent names are this phase's because they break here.)

### Success Criteria

#### Automated Verification

- [x] `.claude/skills` and `.claude/agents` do not exist
- [x] `ruby ~/.claude/skills/wurk:kit/scripts/lib/manifest.rb check` still
      exits 0 (the manifest is untouched but must still resolve with the
      skills gone)
- [x] `git diff HEAD -- .claude/settings.json` shows the `_comment` and the
      three `deny` entries **unchanged**, and only a `hooks` key added
- [x] `python3 -c 'import json;json.load(open(".claude/settings.json"))'` (or
      `ruby -rjson -e 'JSON.parse(File.read(".claude/settings.json"))'`) parses
- [x] `bd show px-uio` reports status closed with the superseding note
- [x] `git grep -n 'thoughts-locator\|thoughts-analyzer'` returns nothing
      outside `docs/plans/` history
- [x] `git diff --stat` touches no Elixir code - gate carve-out applies

#### Manual Verification

- [ ] A fresh session in this repo shows primed bead context (the hook fires)
- [ ] The deny rules still fire: an attempted `Edit(.quality.exs)` is refused

**Implementation Note**: commit with **`/wurk:commit --auto`**. The deletion,
the settings change, the px-uio close, and the agent-name prose fixes are all
**one commit** - the bead's acceptance criterion requires px-uio's close to
ride with the skill deletion.

---

## Phase 4: Documentation and the adoption ADR

### Overview

Rewrite every document that names an old skill, and record the adoption in an
ADR.

`area:docs`.

### Changes Required

#### 1. `CLAUDE.md` - the "Worktrees, skills, and area labels" table

Rewrite the nine-row skill table to the wurk names. The collapse to note:
`/next-issue` and `/next-issues` become a **single `/wurk:next`** with `n`
defaulting to 1.

| Old | New |
|---|---|
| `/create-issue` | `/wurk:issue` |
| `/next-issue`, `/next-issues` | `/wurk:next` |
| `/new-worktree` | `/wurk:branch` |
| `/work` | `/wurk:work` |
| `/research-codebase` | `/wurk:research` |
| `/create-plan` | `/wurk:plan` |
| `/iterate-plan` | `/wurk:iterate` |
| `/implement-plan` | `/wurk:implement` |
| `/commit` | `/wurk:commit` |
| `/merge-request` | `/wurk:mr` |
| `/release` | `/wurk:release` |
| `/cleanup-worktrees` | `/wurk:cleanup` |
| `/refresh-worktree` | `/wurk:refresh` |

Also update the surrounding prose: "The skills in `.claude/skills/` automate the
loop" becomes a statement that the skills are installed globally under `wurk:`
and configured by `.claude/wurk.json` plus `.claude/wurk/*.md`. Keep the
worktree-path and claim-is-the-lock sentences, and keep the "sizing happens in
the worktree" paragraph - `/wurk:work` preserves that behavior.

#### 2. `CLAUDE.md` - the research-agents section

Already renamed in Phase 3 (the names break there). This phase adjusts the
surrounding sentence: the agents no longer live in `.claude/agents/`; wurk
ships them globally, and this repo's `.claude/agents/` is now empty and
available for genuinely predicator-only agents (an ISA-drift checker is the
documented example).

#### 3. Sweep everything else

```bash
git grep -n '/commit\b\|/work\b\|/next-issue\|/next-issues\|/new-worktree\|/create-plan\|/iterate-plan\|/implement-plan\|/research-codebase\|/merge-request\|/cleanup-worktrees\|/refresh-worktree\|/create-issue\|/release\b' \
  -- CLAUDE.md README.md docs/
```

Known hits from a pre-flight sweep: `CLAUDE.md`, and
`docs/adr/0005`, `0006`, `0007`, `0008`, `0010`. **ADR prose is history and is
mostly left alone** - an accepted ADR records what was decided at the time. The
rule for this sweep: an ADR sentence *describing what was true when the ADR was
written* stays; a sentence *instructing a reader to run a command today* is
updated, or gets a one-line "superseded by ADR-0012" pointer. Plans and
research documents under `docs/plans/` and `docs/research/` are dated records
and are **not** rewritten.

#### 4. Write ADR-0012

**File**: `docs/adr/0012-adopting-the-shared-wurk-workflow.md` (new)

**Decision: yes, this repo writes an adoption ADR.** The reasoning:

- This repo has an active ADR practice (eleven accepted ADRs) and CLAUDE.md's
  standing instruction is to "cite ADR numbers instead of re-arguing them". The
  question "why are this repo's workflow skills not in this repo?" will
  recur - a reader of ADR-0005 or ADR-0008 lands on machinery that has moved
  out of the tree with nothing explaining where it went.
- Three existing ADRs are directly implicated and would otherwise silently
  drift: **ADR-0005** (the worktree/area-label algebra, whose enforcement moved
  from `/new-worktree` and `/next-issues` to `/wurk:branch` and `/wurk:next`
  plus `beads.areas` in the manifest), **ADR-0006** (irreversibility places the
  human gates, whose triggers are now enforced by skills this repo does not
  own), and **ADR-0008** (the non-editable gate config, whose deny rules are
  the one part deliberately staying local).
- statifier-ex wrote ADR-0016 for the same move; a second consumer with no
  record makes the pair harder to reason about later.
- It is the cheapest place to record **what stays local**, which is the part a
  future reader most needs: the ADR-0008 deny block, the `.claude/wurk/`
  extension surface, and the manifest itself.

Content, kept short: context (the three-repo triplication, the extraction),
decision (consume `wurk:*` globally; configure by manifest + extensions), what
stays local (deny rules, extensions, manifest, CLAUDE.md's authority table -
wurk defers to it and never widens it), consequences (old slash names stop
resolving with no shims; a behavior change needs a manifest field upstream, not
a forked skill; the one knowing regression is the wider claim race, owed as
wurk `wu-z6n`), and status accepted, dated 2026-08-10. Add it to
`docs/adr/README.md`.

#### 5. `CHANGELOG.md`

No entry. This is developer tooling with no user-facing surface; CLAUDE.md
scopes `## [Unreleased]` entries to user-facing changes.

### Success Criteria

#### Automated Verification

- [x] `git grep -n` for each of the 14 deleted skill names returns nothing
      outside `docs/plans/`, `docs/research/`, and deliberate ADR prose
- [x] `git grep -n` for each of the 6 unprefixed agent names returns nothing
      outside those same directories
- [x] `docs/adr/0012-adopting-the-shared-wurk-workflow.md` exists and is listed
      in `docs/adr/README.md`
- [x] `git diff --stat` touches only `CLAUDE.md` and `docs/` - gate carve-out
      applies

#### Manual Verification

- [ ] The rewritten CLAUDE.md skill table reads correctly to someone who has
      never seen the old one - no orphan references to a `/next-issues` batch
      form that no longer exists as a separate skill
- [ ] ADR-0012 does not re-argue ADR-0005, ADR-0006, or ADR-0008; it cites them
- [ ] Every ADR sentence left naming an old skill is genuinely historical

**Implementation Note**: commit with **`/wurk:commit --auto`**.

---

## Phase 5: End-to-end verification and the loss audit

### Overview

Prove the adopted workflow actually runs, and prove nothing predicator-only was
dropped on the floor. This phase edits files only if it finds a gap.

`area:skills`, `area:docs`.

### Changes Required

#### 1. Full gate on the finished tree

```bash
mix quality
```

The bead's acceptance criteria require a full green, and this is the one place
in the plan where a full run is meaningful (no Elixir changed, but the criterion
is about the tree, not the diff).

```bash
ruby ~/.claude/skills/wurk:kit/scripts/gate.rb
```

Must come back `ok` on a clean tree with no `stage_skipped` block.

#### 2. The loss audit - method, not a hand-wave

The 14 old skills are the pre-extraction reference implementation. Anything in
them that ends up in neither a wurk generic skill nor an extension file is
either **deliberately dropped and named as such**, or a bug.

Method, executable and reviewable:

1. Recover the deleted tree into a scratch directory so it can be read without
   reverting anything:

   ```bash
   # the commit that deleted them; its parent still has the tree
   DEL=$(git log --format=%H --diff-filter=D -1 -- .claude/skills)
   mkdir -p /tmp/px-ttt-old
   git archive "$DEL^" .claude/skills .claude/agents | tar -x -C /tmp/px-ttt-old
   ls /tmp/px-ttt-old/.claude/skills   # expect 14 directories
   ```

2. For each of the 14 skills, walk its sections and classify every substantive
   instruction into exactly one of four buckets:

   | Bucket | Meaning |
   |---|---|
   | **covered** | the generic `wurk:*` skill says the same thing |
   | **manifest** | it became a `.claude/wurk.json` field |
   | **extension** | it is in one of the six `.claude/wurk/*.md` files |
   | **dropped** | it is in none of the above |

3. Every **dropped** item must be named in the closing report with a reason.
   Expected drops, pre-identified, so a reviewer can tell the known from the
   surprising:

   - the atomic `bd ready --claim --json` claim (`next-issue`) - knowingly
     regressed to `/wurk:next`'s select-then-claim window with a
     `bd_claim_failed` fallback; owed upstream as wurk `wu-z6n`
   - `/next-issues` as a distinct skill - collapsed into `/wurk:next` with `n`
   - any `## Model routing` prose citing this repo's own docs - model routing
     is generic policy and lives in the wurk skills; the one divergence
     (`models.direction`) is a manifest field and this repo takes the default
   - alias/muscle-memory affordances - deliberately none (item 14)
   - every worked output example written in predicator paths (object literal /
     `object_new` / ISA v2 commit examples, the plan and research examples, the
     agent output examples) - the generic files use placeholders. **Four
     carve-outs are facts wearing an example's clothing** and are re-homed into
     extension files rather than dropped: the span-slot contract (a hand-built
     AST with a `nil` span renders identically) plus parse -> visit -> parse
     round-tripping, doctests-are-executed-tests
     (`test/docs_examples_test.exs`), integration-vs-unit assertion style, and
     the `*_edge_cases_test.exs` naming convention
   - hardcoded machine paths (`/Users/johnnyt/repos/github/predicator-ex`) and
     the literal remote URL - both derived at runtime by the kit scripts
   - rationale prose now internal to kit scripts: the fish equals-expansion
     quoting note, the dialyxir cache-key reasoning, the `cp -f` aliasing note
     (which CLAUDE.md still carries)
   - release-history asides (the "two most recent hand-cut releases" note, the
     `d9ff35c` editorial-pass reference, the `git log --grep '^Releases '`
     precedent check)
   - CLAUDE.md cross-references - CLAUDE.md still exists and still says it

   An item that is dropped and **not** on this list is a finding: either add it
   to an extension file (this repo's job) or file it upstream against wurk
   (a generic gap). Say which, per item.

   **Behavior divergences to record as decisions, not losses.** Each is a real
   change in what the workflow does; the audit names them rather than letting a
   reader discover them:

   - `/merge-request` waited for an explicit human answer before pushing and
     deliberately had no `--auto`. `/wurk:mr` relocates that gate to skill
     invocation and proceeds. Compatible with CLAUDE.md's authority table
     (typing `/wurk:mr` *is* the ask) but strictly less conservative.
   - `/next-issues` defaulted to n=3; `/wurk:next` defaults to n=1.
   - `/implement-plan` told the session to commit; `/wurk:implement` leaves
     commit, push and merge to the user unless instructed.
   - The belt-and-braces `mix format` re-run before staging has no
     `/wurk:commit` equivalent (the gate's Format stage covers it).
   - "Never weaken the gate" is not restated in the generic commit or mr
     skills. It survives in CLAUDE.md, wurk's `docs/gate-contract.md`, the
     ADR-0008 deny rules, and - by this plan - `.claude/wurk/implement.md`.
   - **New capability, not a loss**: `wurk-gate-reader` absorbs full gate
     output, `wurk-plan-critic` reviews plans adversarially, `plan_state.rb`
     structurally refuses manual-checkbox ticks, and `commit_message.rb`
     mechanically enforces the no-attribution rule.

   **Highest-risk items if an extension file is missing.** Check these by name
   before declaring the audit clean: the ADR-0003-amends-ADR-0001 rule; the
   corpus-regeneration discipline; the `StringVisitor` round-trip completeness
   rule; the ISA versioning triad; the `area:conformance`/`area:build`
   disambiguation; the `docs/adr/README.md` index step; the no-`proposed`
   status rule; and `bd bootstrap`.

4. Record the audit's outcome in a `bd note` on px-ttt, so the finding survives
   the session:

   ```bash
   bd note px-ttt "loss audit: <n> items classified; dropped: <list>; findings: <list>"
   ```

#### 3. Drive one bead end to end

From the **main checkout**, not this worktree:

```
/wurk:next          # picks and claims one ready bead, stands up its worktree
                    # via /wurk:branch, seeds a session with /wurk:work
/wurk:work <id>     # in the new worktree: sizes, then drives the stage
/wurk:commit        # or --auto
/wurk:mr            # STOP BEFORE PUSH
```

`/wurk:mr` rebases, runs the full gate, then pushes and opens the request.
**Stop before the push step.** The user has not asked for a push, and
CLAUDE.md's authority table makes "the work is done" not a request to publish
it. Report the branch state and stop.

#### 4. Confirm a seeded worktree window opens and its session runs

What can be checked mechanically, and belongs in Automated Verification:

```bash
tmux list-windows -t predicator-ex
tmux capture-pane -p -t predicator-ex:<window> | head -40
```

The capture must show the seeded prompt naming `/wurk:work <id>` and the
appended finishing clause naming **`/wurk:commit --auto`** (from
`tmux_window.rb:35`'s `FINISH_TEMPLATE`) - not `/commit --auto`. A seeded
prompt still naming the old skill is exactly the silent breakage wurk plan
item 4 warns about.

What cannot be checked unattended, and goes to **Deferred Manual
Verification**: that the Claude session inside that window is genuinely live
and responsive, that it accepted the seed and started working, and that the
end-to-end drive above reached `/wurk:mr` cleanly. Those need a human at the
terminal.

### Success Criteria

#### Automated Verification

- [ ] Full `mix quality` is green on the finished tree
- [ ] `ruby ~/.claude/skills/wurk:kit/scripts/gate.rb` reports `ok`, no
      `stage_skipped` block
- [ ] `ruby ~/.claude/skills/wurk:kit/scripts/lib/manifest.rb check` exits 0
- [ ] `git status` is clean
- [ ] The loss audit is complete: every old-skill instruction is classified,
      and the dropped list is written to a `bd note` on px-ttt
- [ ] `tmux list-windows -t predicator-ex` shows the new bead's window
- [ ] `tmux capture-pane` of that window shows a seed naming `/wurk:work` and a
      finishing clause naming `/wurk:commit --auto`

#### Manual Verification

- [ ] A human attaches to the seeded tmux window and confirms the Claude
      session is live, primed with bead context, and acting on the seed
- [ ] The end-to-end drive reaches `/wurk:mr`'s pre-push state with a green
      gate, and stops there
- [ ] The loss audit's dropped list contains no surprises - every entry is
      either on the pre-identified list or has a filed follow-up
- [ ] A second, unrelated `/wurk:next` pickup behaves sanely for a bead with no
      area label (the expected `unlabeled` verdict, skipped by name)

**Implementation Note**: commit with **`/wurk:commit --auto`**, and only if
this phase produced file edits. A verification-only phase with a clean tree has
nothing to commit and should say so rather than manufacturing a commit.

---

## Testing Strategy

This change adds no Elixir code, so it has no unit or integration tests. Its
verification is structural and behavioral:

### Structural checks

- `lib/manifest.rb check` - the schema validator, run in Phases 1, 3 and 5.
- `gate.rb` - proves the manifest's gate section describes the real gate:
  the skip taxonomy resolves, the carve-out predicate answers correctly for a
  docs-only diff, and `moving_files` is honored.
- `git grep` sweeps for the 14 skill names and the 6 agent names, in both the
  `thoughts-` and bare `docs-` spellings.
- JSON parse of `.claude/settings.json` after the hook is added.

### Behavioral checks

- One bead driven `/wurk:next` -> `/wurk:branch` -> `/wurk:work` ->
  `/wurk:commit` -> `/wurk:mr` (stopping before push).
- A seeded tmux window inspected with `tmux capture-pane` for the correct seed
  and finishing clause.

### Manual testing steps

1. Open a fresh session in the main checkout; confirm bead context is primed
   (the new SessionStart hook).
2. Attempt an edit to `.quality.exs`; confirm it is denied cleanly, not
   prompted (ADR-0008).
3. Run `/wurk:next`; attach to the created tmux window; confirm the session is
   live and working the seeded bead.
4. In that worktree, run `/wurk:commit` and confirm the message carries a
   `Refs:` trailer, no attribution, and a body under the manifest's limits.
5. Run `/wurk:mr` and stop before push; confirm the rebase and full gate ran.

## Open Questions

The `/create-plan` skill asks for no unresolved questions in a final plan. Each
question below is therefore **decided**, with the assumption stated. They are
recorded rather than dropped because this plan was authored unattended and a
human may want to revisit one.

1. **Does this repo want an adoption ADR?** *(Left open by the bead and by the
   wurk plan, phase 3 step 4.)* **Decided: yes - ADR-0012, written in Phase 4.**
   Reasoning is in Phase 4 step 4. Assumption: eleven accepted ADRs and
   CLAUDE.md's cite-don't-re-argue rule make an unexplained absence of the
   workflow machinery worse than a short ADR.

2. **The bead's validator command path is wrong.** It gives
   `~/.claude/skills/wurk:kit/scripts/manifest.rb check`; the file is at
   `scripts/lib/manifest.rb` (`docs/manifest.md:266`). **Decided: use the
   `lib/` path.** Assumption: the doc and the filesystem agree, so the bead has
   a typo. No upstream change is needed.

3. **Should `gate.project_level_skips` also carry statifier's
   `disabled in \.quality\.exs` entry, defensively?** **Decided: no.** The bead
   requires derivation from a real run, and no stage is disabled in this repo's
   `.quality.exs`. Assumption: if a stage is disabled later, the resulting
   block is correct behavior - it forces a deliberate manifest edit rather than
   silently accepting a narrower gate.

4. **Does `.claude/agents/` come back for predicator-only agents?**
   **Decided: not in this bead.** The directory is deleted empty; the wurk
   architecture document names an ISA-drift checker as the pattern for when one
   is wanted. Assumption: no such agent exists today, so creating a placeholder
   would be speculative.

5. **The bead names six extension files; a pre-flight inventory found content
   requiring eleven.** **Decided: write all eleven** (Phase 2). Assumption: the
   bead's final acceptance criterion - anything in neither wurk nor an
   extension file is a bug unless named as a deliberate drop - is the
   controlling instruction, and the five extra files are exactly the content
   that criterion would otherwise flag. The bead's six remain mandatory; the
   five are additive and each is justified in place. A reviewer who disagrees
   can drop any of the five and record its content as a deliberate loss
   instead - that is the only other consistent answer.

6. **Two manifest values in the bead's own field list are wrong for this
   repo.** The bead says `gate.build_paths` should include `config/` (there is
   no `config/` here) and implies statifier's `_build/dev/dialyxir_*` PLT glob;
   this repo pins the PLT to `priv/plts/dialyzer.plt` (`mix.exs:41`).
   **Decided: follow the repo, not the bead** - the bead itself says to check
   `config/` first, and `warm_globs` is defined as matching this repo's actual
   `_build` path, which resolves to `priv/plts/`. Also added:
   `also_gated_paths: ["conformance/"]`, which the bead left as "[] unless
   something outside build_paths is gate-relevant" -
   `corpus_freshness_test.exs` is exactly that.

7. **Can the end-to-end drive be completed unattended?** **Decided: partially.**
   The mechanical half (window exists, seed text correct, gate green,
   pre-push state reached) is automated in Phase 5; anything requiring a human
   to look at a live tmux session is in Deferred Manual Verification.
   Assumption: an agent capturing a pane can prove the seed is right but cannot
   prove the session is responsive.

## ISA Impact

**None.** This work changes no opcode, adds none, removes none, and renames
none. `docs/isa.md`, `lib/predicator/instructions.ex`, and
`conformance/corpus/**` are untouched, no ISA version moves, and no compiled
instruction list is affected. Per ADR-0003 there is nothing for the Ruby or
JavaScript siblings to adopt from this change. This section is stated
explicitly rather than omitted because the bead's own extension files are
*about* the ISA sections, and a reader could reasonably wonder.

## References

- Beads issue: **px-ttt** (`bd show px-ttt`) - description, design, and the
  2026-08-10 decisions in its notes section, which are binding
- Superseded bead: **px-uio**, closed in Phase 3 in favor of wurk `wu-lyc`
- Upstream: wurk bead `wu-4tq` (this phase), `wu-lyc` (upstream/decision bead
  handling), `wu-z6n` (atomic claim)
- `~/repos/github/wurk/docs/plan.md:222-360` - the numbered coupling-point
  inventory (items 4, 5, 6, 9, 14, 17, 20, 21 are live here);
  `:1126-1155` - "Phase 3: predicator-ex adoption"
- `~/repos/github/wurk/docs/manifest.md` - the schema;
  `~/.claude/skills/wurk:kit/scripts/lib/manifest.rb` is the authority where
  they differ
- `~/repos/github/wurk/docs/architecture.md:24-88` - the four-layer split and
  the extensions-add-never-override rule
- `~/repos/github/wurk/docs/gate-contract.md` - the tiers; this repo lands at
  tier 1
- `~/repos/github/wurk/skills/wurk:kit/REFERENCE.md:325-370` - the recommended
  consumer settings blocks
- `~/repos/github/statifier-ex/.claude/` - the worked example: `wurk.json`,
  `wurk/*.md`, `settings.json`
- `~/.claude/skills/wurk:commit/SKILL.md:1-60` - `name: wurk:commit`,
  `--auto` argument form, and the auto-mode refusal conditions
- `~/.claude/skills/wurk:implement/SKILL.md:128-163` - `/wurk:commit --auto` as
  the loop's advancement gate
- `~/.claude/skills/wurk:kit/scripts/tmux_window.rb:35` - the finishing-clause
  template
- This repo: `CLAUDE.md` (authority table, area labels, skill table),
  `.claude/settings.json` (ADR-0008 deny block), `.quality.exs`,
  `mix.exs:5`, `README.md:26`
- ADRs: `docs/adr/0003` (this repo leads the ISA), `0005` (worktree
  parallelism and the area-label algebra), `0006` (irreversibility places the
  human gates), `0008` (the quality gate and its non-editable config), `0010`
  (tracker authority and the mirror obligation); new `0012` in Phase 4
- `docs/research/260808-px-9ab-sabotage-notes.md` - the narrow binding-test
  sabotage convention that must not be confused with statifier's protocol

## Deferred Manual Verification

Phase 1: `beads.areas.labels` matches CLAUDE.md's area-label table exactly, all
ten, in the same spelling
Phase 1: `always_batchable` is absent from the file, not present-and-empty
Phase 1: `warm_globs` matches an actual file: `ls priv/plts/dialyzer.plt*`
Phase 1: `conformance/` is in `also_gated_paths`, so a corpus-only diff is not
carved out of the gate

Phase 2: Each file names the generic skill it extends and says "adds only"
Phase 2: `commit.md`'s changelog section cannot be misread as endorsing
fragments
Phase 2: `iterate.md` does not duplicate `plan.md`
Phase 2: `implement.md` is self-contained - a phase subagent handed only its
path can follow it with no other read
Phase 2: `commit.md` and `implement.md` do not contradict each other on the
corpus discipline (one states the commit-time refusal, the other the
protocol)
Phase 2: Reading each extension alongside its generic skill, no instruction
contradicts the generic one

Phase 3: A fresh session in this repo shows primed bead context (the hook
fires)
Phase 3: The deny rules still fire: an attempted `Edit(.quality.exs)` is
refused

Phase 4: The rewritten CLAUDE.md skill table reads correctly to someone who
has never seen the old one - no orphan references to a `/next-issues` batch
form that no longer exists as a separate skill
Phase 4: ADR-0012 does not re-argue ADR-0005, ADR-0006, or ADR-0008; it cites
them
Phase 4: Every ADR sentence left naming an old skill is genuinely historical
