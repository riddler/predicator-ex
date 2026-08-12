# Adopts gate.sabotage over the binding tests - Implementation Plan

## Overview

Turn on the kit's sabotage scan for this repo by declaring `gate.sabotage`
inside the existing `gate` object of `.claude/wurk.json`, scoped by an
allowlist of the binding-test files rather than by the whole suite, and write
down the scoping trap that allowlist carries so a future session adding a
binding test knows to extend it. Bead: px-lxs.

## Current State Analysis

`.claude/wurk.json:29-43` declares `gate` with `full`, `loop`, `report`,
`build_paths`, `also_gated_paths`, `moving_files`, `project_level_skips`, and
`not_applicable_skips`. There is no `sabotage` key, so
`Manifest#sabotage?` (`~/.claude/skills/wurk:kit/scripts/lib/manifest.rb:304`)
returns false, `gate.rb` shells out no diff for the scan, and every run
reports `data.sabotage.enabled: false` with the reason "no gate.sabotage
section in the manifest; the scan is off" (`gate.rb:313-318`).

The discipline the scan would enforce already exists in prose. `CLAUDE.md:314-317`
(last Conventions bullet) says binding tests carry a sabotage note and
ordinary tests need none, pointing at
`docs/research/260808-px-9ab-sabotage-notes.md` for the enumerated list and
the reasoning. px-suw has since landed the notes themselves: `grep -rln
"# sabotage:" test/` returns exactly ten files today, and they are exactly the
ten the research document enumerates (its original seven at lines 49-52, plus
the three "Additions to the class" entries at lines 164-289).

The field was deliberately left off eight days ago.
`docs/plans/260812-px-hhu-wurk-config-catchup.md:436` is the decision row, and
its stated reason is a factual claim about the kit: "narrowing the scan to the
binding-test set would need `test_roots` granularity the field does not have."
That claim is false, and wurk wu-4r7 settled it as a documentation gap. The
kit hands `test_roots` verbatim to `git diff` as a pathspec
(`gate.rb:173-177`), and `Manifest#validate_sabotage`
(`manifest.rb:535-566`) accepts "directory prefixes, exact file paths, or
globs; no leading ':'". Exact file paths work today with no kit change.

### Key Discoveries:

- **The bead's JSON snippet is over-escaped and would not work as pasted.**
  Its `"test_pattern": "\\\\btest\\\\s+\""` decodes to the regex source
  `\\btest\\s+"`, which is a literal backslash followed by `btest`; verified
  by running `Regexp.new` on it against `  test "foo" do`, which does not
  match. The correct JSON is `"\\btest\\s+\""`, decoding to `\btest\s+"`,
  which matches `test "..."` and matches neither `describe "..."` nor
  `latest_test "..."`. The extra layer is shell escaping that leaked into the
  bead text.
- **The pattern is compiled, not fuzzy-matched.** `manifest.rb:312-315` does
  `Regexp.new(source)` on the raw string, and `validate_sabotage`
  (`manifest.rb:551-560`) rejects a non-String, an empty string, or a source
  `Regexp.new` raises on. So a bad pattern is a lint error, not a silently
  dead scan.
- **The section is present-or-absent, never half-present.**
  `manifest.rb:533-549`: `test_roots` must be a non-empty array of non-empty
  strings with no leading `:`, and `test_pattern` must be present alongside
  it. `exempt_prefixes` is genuinely optional (`manifest.rb:562-565`).
- **The probe is cheap, which is not obvious.** `gate.rb:313-318` populates
  `data.sabotage` *before* the gate-applicability carve-out returns at
  `gate.rb:335-346`. A branch touching only `.claude/` and `docs/` is not
  gate-applicable (`gate.build_paths` is `lib/`, `test/`, `mix.exs`,
  `mix.lock`), so `ruby .../gate.rb` on this branch reports
  `data.sabotage.enabled` without running `mix quality` at all.
- **The scan reads `main...HEAD`, so uncommitted work is invisible to it**
  (`gate.rb:174`). Any hand-verification probe has to be a real commit on the
  branch, then reset.
- **The scan is a report, never a gate** (`REFERENCE.md:287-299`). It never
  flips `ok`. Its findings surface as `sabotage_note_missing` warnings
  (`gate.rb:319-325`), and a present note is not evidence the mutation was
  actually run - that judgment stays with `/wurk:commit`'s Step 0.
- **The class is ten files, not two.** All ten exist on disk and all ten
  already carry notes. See "Implementation Approach" for how this plan handles
  the divergence from the bead's two-path snippet.
- ADR-0005 governs the area labels this bead carries (`area:docs`,
  `area:skills`); ADR-0012 places wurk configuration in `.claude/wurk.json`
  and the `.claude/wurk/*.md` extensions. Nothing here moves the ISA, so no
  `## ISA Impact` section (`.claude/wurk/plan.md`).

## Desired End State

`.claude/wurk.json` declares `gate.sabotage` with an allowlist naming every
binding-test file in this repo's enumerated class plus this repo's ExUnit
`test_pattern`, `ruby ~/.claude/skills/wurk:kit/scripts/lib/manifest.rb check`
reports `data.valid: true` with an empty `errors` array, `gate.rb` reports
`data.sabotage.enabled: true` with a `null` reason, a diff adding an
undocumented test inside a listed file produces a `sabotage_note_missing`
warning, a diff adding an ordinary test anywhere else produces none, and the
scoping trap the allowlist carries is written into both `CLAUDE.md`'s
Conventions bullet and the px-9ab research document.

Verification is the four acceptance criteria on the bead, split across the two
phases below.

## What We're NOT Doing

- **Not declaring `exempt_prefixes`.** An allowlist of exact file paths
  already excludes everything else; an exempt list would be dead configuration
  whose only effect is to make a reader think something is being carved out.
- **Not moving to a naming-convention glob.** The bead defers this judgment
  call and the deferral survives: the ten files have no shared naming
  convention (`isa_sync_test.exs`, `values_test.exs`,
  `visitor_clause_coverage_test.exs`, `docs_adr_links_test.exs`), and the
  glob that would catch them all - `test/**/*_test.exs` - is the whole suite,
  which is the broad form px-9ab explicitly rejected. Exact paths stay the
  honest shape. Revisit only if a naming convention is deliberately adopted.
- **Not editing `docs/plans/260812-px-hhu-wurk-config-catchup.md:436`.** A
  landed plan is a dated record of what was decided and why, not a live
  document; rewriting its reasoning after the fact destroys the evidence that
  the reversal happened. The reversal is recorded in the px-9ab research
  document instead, which is the live one.
- **Not retrofitting or re-running any sabotage note.** All ten binding files
  already carry notes (px-suw, px-ir1, px-qq6, px-kbe, px-3so.4). This bead
  turns on a scan; it re-verifies no mutation.
- **Not touching `.quality.exs`, `.credo.exs`, `coveralls.json`, `mix.exs`, or
  any Elixir file.** This bead carries no `area:build` label and must not
  acquire one - `area:build` is exclusive under ADR-0005 and would serialize
  the queue behind it.
- **Not adding a `CHANGELOG.md` entry.** The changelog records user-facing
  changes to the library; agent-tooling configuration is not one, and px-hhu
  set that precedent for `.claude/wurk.json` edits.
- **Not adding an ADR.** px-9ab already settled that this is workflow
  governance rather than architecture, and stated that no ADR was written for
  it; enabling the scan changes no part of that decision.

## Implementation Approach

Two phases along the two area labels: the manifest edit (`area:skills`) and
the prose that records the trap (`area:docs`). Each is independently
committable, and neither can leave a gate red - no Elixir file changes, so
`gate_applicable?` is false for both and CLAUDE.md's own rule applies ("a
change touching no Elixir code has no gate to run and may commit on review of
the diff alone"). The manifest edit goes first because Phase 2's prose records
the outcome of Phase 1's hand-verification.

### The one deviation from the bead, and why

The bead's snippet lists two `test_roots` entries. **This plan lists ten** -
the full enumerated class from `docs/research/260808-px-9ab-sabotage-notes.md`,
which is a strict superset containing both of the bead's two, so acceptance
criterion 1 is satisfied rather than dodged.

The bead's premise is that this repo has two binding tests. That was true when
px-9ab first named the class boundary in the abstract, and it is not true of
the tree: the research document enumerates seven files at lines 49-52 and adds
three more at lines 164, 199, and 237, and `grep -rln "# sabotage:" test/`
returns exactly those ten today. The bead's own aside - "whether to keep the
two exact paths or move to a naming-convention glob once this repo has more
than two binding tests" - reads as written before that count was checked.

Shipping the two-path form would mean the scan is blind to eight files that
are, by this repo's own written definition, in the class it exists to protect,
and blind on the day it lands. That is precisely the scoping trap the bead
asks to be written down, walked into by the same change that documents it. The
widening costs one line each, changes nothing about the narrow-form property
the bead cares about (an ordinary test outside the allowlist is still not
flagged, and the allowlist is still ten files out of an 82-file suite), and is
mechanically reversible if a reviewer disagrees.

If a reviewer prefers the literal two-path form, the edit is to delete eight
lines from Phase 1's snippet; nothing else in this plan changes.

## Phase 1: Declare `gate.sabotage` and verify the scan by hand

### Overview

Add the `sabotage` object to `.claude/wurk.json`'s `gate` section, lint the
manifest, and hand-verify both directions of the scan - that a missing note
inside a listed file is reported, and that an ordinary test outside the
allowlist is not.

### Changes Required:

#### 1. The manifest

**File**: `.claude/wurk.json`
**Changes**: Add one `"sabotage"` key inside the existing `gate` object, after
`not_applicable_skips` (last position, so the diff is an append inside the
object and reads cleanly). Note the escaping: `\\b` and `\\s` in JSON, not
`\\\\b` and `\\\\s`, and `\"` for the literal double quote.

```json
    "not_applicable_skips": [
      "^:gettext not installed$",
      "^:sobelow not installed$"
    ],

    "sabotage": {
      "test_roots": [
        "test/predicator/isa_sync_test.exs",
        "test/predicator/conformance/corpus_freshness_test.exs",
        "test/predicator/conformance/opcode_coverage_test.exs",
        "test/predicator/conformance/function_coverage_test.exs",
        "test/predicator/conformance/schema_validation_test.exs",
        "test/predicator/conformance/ratchet_registry_test.exs",
        "test/predicator/conformance/package_boundary_test.exs",
        "test/docs_adr_links_test.exs",
        "test/predicator/conformance/values_test.exs",
        "test/predicator/visitor_clause_coverage_test.exs"
      ],
      "test_pattern": "\\btest\\s+\""
    }
```

The order of `test_roots` is the order the class was established in - px-9ab's
original seven first (research document lines 49-52), then the three additions
in the order they were made (px-ir1, px-qq6, px-kbe/px-3so.4). A reader
diffing the list against the research document reads top to bottom.

#### 2. Nothing else

No other file changes in this phase. `exempt_prefixes` is deliberately absent
(see "What We're NOT Doing").

### Success Criteria:

#### Automated Verification:

- [x] `ruby ~/.claude/skills/wurk:kit/scripts/lib/manifest.rb check 2>/dev/null`
      emits `"valid":true` with `"errors":[]`. (Redirect stderr: running the
      kit's `manifest.rb` from a checkout that also has wurk on the load path
      prints harmless "already initialized constant" warnings.)
- [x] `ruby -rjson -e 'p JSON.parse(File.read(".claude/wurk.json"))["gate"]["sabotage"]["test_roots"].reject { |p| File.exist?(p) }'`
      prints `[]` - every listed path exists on disk.
- [x] `ruby -rjson -e 'src = JSON.parse(File.read(".claude/wurk.json"))["gate"]["sabotage"]["test_pattern"]; abort("no match") unless %q(  test "x" do) =~ Regexp.new(src)'`
      exits 0 - the pattern actually matches an ExUnit test declaration.
- [x] `ruby ~/.claude/skills/wurk:kit/scripts/gate.rb 2>/dev/null` reports
      `data.sabotage.enabled: true` and `data.sabotage.reason: null`. On a
      branch touching only `.claude/` and `docs/` this returns without running
      `mix quality` (`gate.rb:313-318` precedes the carve-out return at
      `gate.rb:335-346`), so it costs a `git diff`.

#### Manual Verification:

- [x] **Negative probe (the bead's stated point).** On a clean tree with the
      manifest change committed, commit a throwaway ordinary test outside the
      allowlist - e.g. `test/predicator/scratch_probe_test.exs` with a single
      `test "probe" do` and no `# sabotage:` note - then run
      `ruby ~/.claude/skills/wurk:kit/scripts/gate.rb --profile loop`. Confirm
      `data.sabotage.missing` is `[]` and no `sabotage_note_missing` warning
      appears. Then `git reset --hard HEAD~1`. (`--profile loop` because the
      throwaway touches `test/`, which makes the run gate-applicable; the gate
      command's own result is not what is being read here.)
- [x] **Positive probe (that the scan is wired at all).** Same procedure, but
      the throwaway commit adds an undocumented `test "probe" do` line inside
      `test/predicator/isa_sync_test.exs`. Confirm exactly one entry appears
      in `data.sabotage.missing`, naming that file and that line, with a
      matching `sabotage_note_missing` warning. Then `git reset --hard HEAD~1`.
      A negative probe alone cannot distinguish "correctly not flagged" from
      "scan silently doing nothing", which is why both directions are run.
- [x] `git status --porcelain` is empty after both probes, and
      `git log --oneline -1` is the manifest commit - no throwaway commit and
      no probe file survives.

**Implementation Note**: There is no Elixir change in this phase, so per
CLAUDE.md's authority table the commit is reviewed on the diff alone; run
`mix quality --profile loop` only if a probe left the tree unexpectedly dirty.
Pause here for the human to confirm the two probes before Phase 2 begins,
because Phase 2's prose quotes their output.

**This plan is interactive-only; do not run it under `/wurk:implement --loop`.**
Looped execution defers every Manual Verification item to a batched pass after
the last phase has already committed, so a Phase 2 subagent would be asked to
quote probe output that does not exist yet - and Phase 2's own manual
criterion ("describe what actually ran") is precisely the check that catches
that. The dependency is real and one-directional, so the fix is the execution
mode, not a softer criterion.

---

## Phase 2: Write down the scoping trap

### Overview

Record, in the two places a future session actually reads, that the allowlist
is exhaustive by construction: a binding test added to a file not listed in
`gate.sabotage.test_roots` is invisible to the scan, so adding one includes
adding its path in the same change. Also record the reversal of px-hhu's
"leave off" decision and the outcome of Phase 1's probes.

### Changes Required:

#### 1. The Conventions bullet

**File**: `CLAUDE.md`
**Changes**: Extend the existing last Conventions bullet (lines 314-317) with
the enforcement half. Keep it to the bullet - this file's Conventions section
is a list of one-to-four-line rules and a new section would over-weight a
configuration detail.

```markdown
- Binding tests carry a sabotage note - the enumerated tests that bind an
  exported artifact to its source are verified by breaking what they cover and
  confirming they go red. Ordinary tests need no note. The list and the
  reasoning are in `docs/research/260808-px-9ab-sabotage-notes.md`.
  `gate.sabotage.test_roots` in `.claude/wurk.json` is that same list, in
  machine-readable form, and the scan reads nothing else: **a binding test in
  a file not named there is invisible to it.** Adding a binding test therefore
  means adding its path to `test_roots` in the same change, and the scan's
  silence about a file is never evidence that file is clean.
```

#### 2. The research document

**File**: `docs/research/260808-px-9ab-sabotage-notes.md`
**Changes**: Add a new top-level section after "Additions to the class" (which
ends at line 289), recording four things: that the decision is now enforced by
`gate.sabotage`; that px-hhu's `gate.sabotage` "leave off" row is thereby
reversed and on what evidence (wu-4r7: `test_roots` is a git pathspec, so the
narrow form always worked); that `test_roots` is a second copy of the class
list and must be extended alongside the "Additions to the class" section
above it, with the trap spelled out; and the outcome of Phase 1's two probes,
dated, in the same style the "Additions to the class" entries use for their
sabotage passes.

Match this file's existing house style: hyphens, no em dashes, `**bold**` for
the load-bearing claim, backticked paths.

Head the new section with a top-level heading reading
`Enforcement: gate.sabotage, from 2026-08-12 (px-lxs)`, at the same heading
level as "Additions to the class", and carry the four items above under it,
with the probe results from Phase 1 quoted as they actually ran.

### Success Criteria:

#### Automated Verification:

- [x] `grep -n "test_roots" CLAUDE.md` and
      `grep -n "gate.sabotage" docs/research/260808-px-9ab-sabotage-notes.md`
      each return at least one line - the trap is written in both places.
- [x] `ruby -rjson -e 'roots = JSON.parse(File.read(".claude/wurk.json"))["gate"]["sabotage"]["test_roots"]; doc = File.read("docs/research/260808-px-9ab-sabotage-notes.md"); missing = roots.reject { |p| doc.include?(File.basename(p)) }; abort(missing.inspect) unless missing.empty?'`
      exits 0 - every path in `test_roots` is named somewhere in the research
      document, so the two copies of the class list agree.
- [x] `ruby ~/.claude/skills/wurk:kit/scripts/lib/manifest.rb check 2>/dev/null`
      still reports `"valid":true` (this phase touches no JSON, so it is a
      regression check).
- [x] `mix test test/docs_adr_links_test.exs` passes - `CLAUDE.md` is not in
      its scope, but the run is cheap and confirms no documentation binding
      test was disturbed.

#### Manual Verification:

- [x] Read the `CLAUDE.md` bullet cold: does it say plainly that the scan's
      silence about an unlisted file is not evidence of anything? That is the
      trap, and a reader who takes silence as coverage has been misled by the
      feature this bead turned on.
- [x] The research document's new section states the reversal of px-hhu's row
      with its evidence, so a reader who finds that row first is not left
      believing the kit cannot do this.
- [x] The recorded probe results describe what actually ran in Phase 1, not
      what was expected to run.
- [x] No regressions in related features: `.claude/wurk/*.md` extensions are
      untouched, and no `area:build` file appears in `git diff --name-only
      main...HEAD`.

**Implementation Note**: No Elixir change here either, so the commit is
reviewed on the diff alone. This is the last phase; the bead's `Refs:` trailer
is `px-lxs` on both commits.

---

## Testing Strategy

This bead adds no Elixir code, so it has no unit tests to write. The
`.claude/wurk/plan.md` extension's always-required automated criteria - 90%
coverage on new code, and an AST node round-tripping through `StringVisitor` -
describe code changes and are inapplicable here rather than omitted. There is
likewise no `### Integration Tests` subsection, no corpus criterion (nothing
regenerates `conformance/corpus/**`), and no `## ISA Impact` section (no
opcode moves).

What replaces them is the kit's own verification surface plus two hand probes:

### Configuration validation:

- `ruby ~/.claude/skills/wurk:kit/scripts/lib/manifest.rb check` is the schema
  authority (`manifest.rb:535-566` is the `gate.sabotage` validator: non-empty
  string roots, no leading `:`, a compilable `test_pattern`).
- The two one-liner Ruby checks in Phase 1 cover what the linter deliberately
  does not: that the listed paths exist on disk (a pathspec matching nothing
  is legal git, and legal manifest) and that the compiled pattern matches a
  real ExUnit declaration.

### Manual Testing Steps:

1. Commit the manifest change. Run `ruby ~/.claude/skills/wurk:kit/scripts/gate.rb`
   and read `data.sabotage`: `enabled: true`, `reason: null`, `missing: []`.
2. Commit a throwaway `test/predicator/scratch_probe_test.exs` containing one
   undocumented `test "probe" do`. Run `gate.rb --profile loop`; expect
   `missing: []` and no `sabotage_note_missing` warning. `git reset --hard
   HEAD~1`.
3. Commit an undocumented `test "probe" do` inside
   `test/predicator/isa_sync_test.exs` instead. Run `gate.rb --profile loop`;
   expect exactly one `missing` entry naming that file, and the matching
   warning. `git reset --hard HEAD~1`.
4. Confirm `git status --porcelain` is empty and the branch tip is the
   manifest commit.
5. Record steps 2 and 3 verbatim in the research document's new section during
   Phase 2.

## References

- Bead: `px-lxs`
- Source decision: `docs/research/260808-px-9ab-sabotage-notes.md` (the class
  boundary, lines 49-52 and the additions at 164, 199, 237)
- Decision being reversed: `docs/plans/260812-px-hhu-wurk-config-catchup.md:436`
- Kit contract: `~/.claude/skills/wurk:kit/REFERENCE.md:287-299`
- Kit implementation: `~/.claude/skills/wurk:kit/scripts/gate.rb:118-191`,
  `~/.claude/skills/wurk:kit/scripts/gate.rb:313-325`,
  `~/.claude/skills/wurk:kit/scripts/lib/manifest.rb:301-319`,
  `~/.claude/skills/wurk:kit/scripts/lib/manifest.rb:535-566`
- Related ADRs: `docs/adr/0005-worktree-parallelism-and-the-area-label-algebra.md`
  (the `area:docs` + `area:skills` labelling and `area:build` exclusivity),
  `docs/adr/0006-irreversibility-places-the-human-gates.md` (why these commits
  need no push), `docs/adr/0012-adopting-the-shared-wurk-workflow.md` (wurk
  adoption; configuration lives in
  `.claude/wurk.json`)
- Convention text edited: `CLAUDE.md:314-317`
