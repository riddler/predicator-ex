# Sabotage Notes for the Seven Binding Tests Implementation Plan

## Overview

Retrofit `# sabotage: ... -> red` notes onto every `test` block in the seven
binding-test files CLAUDE.md's Conventions section now requires them on. Beads
issue: px-suw (depends on px-9ab, which landed the convention and the decision
note).

This is a documentation-of-verification task with a real verification step: for
each `test`, break what it covers with one plausible mutation, confirm the test
goes red for the right reason, revert the mutation, and record the mutation in
one line above the `test`. No production behavior changes. The only files that
end up modified are the seven test files.

## Current State Analysis

The decision is `docs/research/260808-px-9ab-sabotage-notes.md`: adopt
statifier's sabotage-note practice **narrowly**, on the binding tests that keep
this repo's exported artifacts honest, and on nothing else. The class is an
enumerated list of seven files, deliberately not a description.

Today, none of the seven carries a sabotage note (`grep -rn "# sabotage" test/`
returns nothing). Three of them carry hand-written anti-vacuity guards with
prose comments instead - `isa_sync_test.exs:23-30` (`@opcode_count 27`),
`package_boundary_test.exs:30-32` (`assert length(@shipped_lib_files) > 10`),
`ratchet_registry_test.exs:45-47` ("the test below would pass vacuously"). Those
stay; a sabotage note sits alongside them, it does not replace them.

The seven files and their `test` block counts, as of this checkout:

| File | `test` blocks |
|---|---|
| `test/predicator/isa_sync_test.exs` | 6 |
| `test/predicator/conformance/corpus_freshness_test.exs` | 1 |
| `test/predicator/conformance/opcode_coverage_test.exs` | 3 |
| `test/predicator/conformance/function_coverage_test.exs` | 3 |
| `test/predicator/conformance/schema_validation_test.exs` | 8 |
| `test/predicator/conformance/ratchet_registry_test.exs` | 5 |
| `test/predicator/conformance/package_boundary_test.exs` | 2 |
| **Total** | **28** |

Key facts the mutations below depend on, verified against the tree:

- `lib/predicator/instructions.ex:45` - `@isa_version 3`; `:64` - the `@opcodes`
  map, e.g. `"load" => %{isa: 1, tier: 1}`, `"and" => %{isa: 1, tier: 1,
  removed_in: 3}`.
- `docs/isa.md:58` - `Current version: **ISA v3**.`; `:192-197` - the tier names
  table (tier 6 is `` `store`, `pop` ``); `:209` onward - the section 4 opcode
  table, 8 columns, last is "Removed in".
- `conformance/README.md:234` - `### Opcodes excluded from the coverage rule`;
  `:247` - `### Functions excluded from the coverage rule`.
- `lib/predicator/conformance/coverage.ex:123` -
  `@documented_exclusion_opcodes ~w(relative_date)`; `:130` -
  `@documented_exclusion_functions MapSet.new(["Date.now", "Math.random"])`.
- `mix.exs:78` - `exclude_patterns: [~r{\Alib/predicator/conformance/}]`.
- `conformance/schema/` holds `case.json`, `corpus.json`, `manifest.json`,
  `registry.json`, `report.json`; `conformance/examples/registry.example.json`
  is the ratchet worked example.

## Desired End State

Every one of the 28 `test` blocks in the seven files carries exactly one comment
line immediately above the `test` line, in one of two forms:

```elixir
# sabotage: instructions.ex @opcodes gives `load` tier 2 -> red
test "every table row round-trips through required_isa/1 and tier/1", %{isa_doc: isa_doc} do
```

```elixir
# sabotage: n/a - <why this block is harness plumbing, not a binding>
```

Verify with a grep that pairs the counts:

```bash
grep -c "^\s*test " test/predicator/isa_sync_test.exs \
  test/predicator/conformance/{corpus_freshness,opcode_coverage,function_coverage,schema_validation,ratchet_registry,package_boundary}_test.exs
grep -c "# sabotage:" test/predicator/isa_sync_test.exs \
  test/predicator/conformance/{corpus_freshness,opcode_coverage,function_coverage,schema_validation,ratchet_registry,package_boundary}_test.exs
```

The two runs must agree file by file. `git status` must show only those seven
files modified, and `mix quality` must be green.

### Key Discoveries

- The decision, the class boundary, and the note format are settled in
  `docs/research/260808-px-9ab-sabotage-notes.md:78-92`. This plan implements
  it; it does not reopen it.
- Statifier's form, which this repo copied verbatim for the note syntax:
  `# sabotage: <what was broken> -> red` above the `test` line, and
  `# sabotage: n/a - <why>` for harness plumbing rather than an omitted line.
- Sabotage notes are required on these seven files and **nothing else**
  (CLAUDE.md Conventions; `260808-px-9ab-sabotage-notes.md:80-81`). Do not add
  notes to other test files while passing through.
- Several mutations touch files outside `test/` - `lib/`, `docs/isa.md`,
  `conformance/`, `mix.exs`. Every one is temporary and must be reverted before
  the phase's gate run. `mix.exs` is an `area:build` file; a *reverted*
  mutation to it does not make this bead `area:build`, but an unreverted one
  would be a real problem, which is why the revert discipline below is a
  first-class step and not an afterthought.

## What We're NOT Doing

- Not changing any assertion, any production code, any schema, any corpus file,
  or any doc. Every mutation is reverted.
- Not adding sabotage notes to test files outside the enumerated seven.
- Not rewriting or removing the existing anti-vacuity guards and their prose
  comments in `isa_sync_test.exs`, `package_boundary_test.exs`, and
  `ratchet_registry_test.exs`. The sabotage note is additive.
- Not regenerating the corpus. `mix corpus.generate` is never run to *fix*
  anything here; if a mutation leaves the corpus dirty, the fix is
  `git checkout` of the mutated file, not regeneration.
- No CHANGELOG entry. Test-file comments are not a user-facing change.
- No ISA movement. No opcode, grammar, or instruction changes - so this plan
  carries no `## ISA Impact` section (ADR-0003).
- Not adding a mix task, a linter, or a CI check that enforces the note. That
  would be a separate bead; the convention is enforced by review today.

## Implementation Approach

Five phases, split by file so each is independently committable and
gate-verifiable. Within a phase the loop per `test` is always the same:

1. Apply the phase's stated mutation for that test.
2. Run **only the target file**: `mix test <path>` (running the full suite is
   wasteful and, for the `lib/`-side mutations, noisy - a mutation to
   `instructions.ex` reddens unrelated suites too, which is expected and not
   evidence of anything).
3. Confirm the red is the *right* red - the assertion message named in the
   phase, not a compile error and not an unrelated failure. A compile error is
   **not** an acceptable red: pick a different mutation.
4. `git checkout -- <mutated file>` (or `git stash`/`git diff` review for a
   multi-file mutation). Re-run the target file and confirm green again.
5. Write the note above the `test` line, naming what was broken - the mutation,
   not the assertion. See "Note wording" below for the exact shape.

Then, once per phase:

6. `git status --short` must list only the phase's test file(s). Anything else
   is an unreverted mutation - revert it before going further. `/commit --auto`
   refuses a tree with unrelated changes, so this is a hard gate, not a
   courtesy.
7. Full `mix quality`.
8. Commit with `Refs: px-suw`.

**Findings.** If a `test` block stays green under every plausible mutation the
phase names *and* under any the implementer can think of, that is a FINDING, not
a note to skip. Record it in this document under "Findings" (append a section at
the bottom), leave the block noteless for that commit, and report it up. Per
`260808-px-9ab-sabotage-notes.md:145-148`, an unwritable note argues the test is
the wrong shape - it is not license to move on quietly.

**Note wording.** One line, present-tense description of the mutation, then
`-> red`. Name the file or the constant, not the assertion:
`# sabotage: docs/isa.md tier-6 row drops \`pop\` -> red`, not
`# sabotage: the tier assertion fails -> red`.

---

## Phase 1: `test/predicator/isa_sync_test.exs` (6 tests)

### Overview

The ISA-to-code anti-drift bindings. Mutations here land in
`lib/predicator/instructions.ex`, `docs/isa.md`, and
`lib/predicator/evaluator.ex`. Expect wide collateral redness in other suites
from the `lib/` mutations; judge the red by this file only.

### Changes Required

**File**: `test/predicator/isa_sync_test.exs` - one comment line above each of
the six `test` lines.

| Test (line) | Mutation | Expected red |
|---|---|---|
| "every table row round-trips through required_isa/1 and tier/1" (`:37`) | `lib/predicator/instructions.ex:66` - change `"load" => %{isa: 1, tier: 1}` to `tier: 2` | `docs/isa.md lists \`load\` as tier 1, but Predicator.Instructions.tier/1 disagrees` |
| "isa_version/0 is the maximum version in the table" (`:63`) | `lib/predicator/instructions.ex:45` - `@isa_version 3` → `4` | `assert Instructions.isa_version() == max_table_version` fails, `4 != 3` |
| "section 1's current-version line agrees with isa_version/0" (`:83`) | `docs/isa.md:58` - `Current version: **ISA v3**.` → `**ISA v2**.` | the `isa_doc =~ "Current version: **ISA v3**."` assertion fails |
| "every row's Removed in cell agrees with retired_in/1" (`:93`) | `docs/isa.md` section 4 - the `` `and` `` row's last cell, `v3` → `-` | `docs/isa.md lists \`and\`'s Removed in cell as nil, but ... retired_in/1 disagrees` |
| "each tier's opcode list matches exactly what the map assigns to that tier" (`:122`) | `docs/isa.md:197` - tier 6 row, drop `` `pop` `` leaving `` | 6 | statements | `store` | `` | `tier names table lists tier 6 as ["store"], but the @opcodes map ... assigns tier 6 to ["pop", "store"]` |
| "every execute_instruction/2 clause head opcode is a known opcode" (`:157`) | `lib/predicator/evaluator.ex` - in one `execute_instruction/2` clause head, rename the opcode string, e.g. `["pop"` → `["popp"` (rename, do not delete - deleting a clause risks a compile warning rather than a test failure) | `every live opcode must have an execute_instruction/2 clause` |

Note for the last row: renaming keeps the clause-head *count* equal, so the size
assertion at `:180` stays green and the `MapSet.difference` assertion at `:186`
is what reddens. That is the right red - it is the assertion the comment at
`:166-172` says the derived count replaced. `assert` halts the test on the first
failure, so the later intersection assertion and the per-opcode `for` loop
(which would name `popp`) are never reached: **one** message, not two. Do not go
looking for the `popp` message.

### Success Criteria

#### Automated Verification
- [x] All six `test` blocks in the file carry a `# sabotage:` line:
      `grep -c "# sabotage:" test/predicator/isa_sync_test.exs` returns `6`
- [x] `git status --short` lists only `test/predicator/isa_sync_test.exs`
- [x] Full gate passes: `mix quality`

#### Manual Verification
- [x] Each of the six reds was observed and matched the expected message above -
      not a compile error, not an unrelated suite failure
- [x] Each note names the mutation, not the assertion, and reads as one line
- [x] `git diff` shows comment-only changes

**Implementation Note**: Use `mix test test/predicator/isa_sync_test.exs` while
iterating; full `mix quality` as the phase gate, after every mutation is
reverted. In looped execution this phase's Automated Verification gates
advancement; Manual items are deferred to the end.

---

## Phase 2: `corpus_freshness_test.exs` + `package_boundary_test.exs` (3 tests)

### Overview

Two small files with the sharpest bindings: the corpus-is-fresh byte comparison,
and the hex-package boundary. Grouped because each is 1-2 tests and both are
gate-verifiable together.

### Changes Required

**Files**: `test/predicator/conformance/corpus_freshness_test.exs`,
`test/predicator/conformance/package_boundary_test.exs`.

| Test (file:line) | Mutation | Expected red |
|---|---|---|
| "the checked-in corpus is exactly what mix corpus.generate would write" (`corpus_freshness_test.exs:19`) | `lib/predicator/instructions.ex:67` - change `"access" => %{isa: 1, tier: 3}` to `tier: 4`, so the generator assigns affected cases a different tier. Fallback if the tier move proves inert: hand-edit one `expected` value on one line of `conformance/corpus/tier-1.json` | `conformance/ is stale - run \`mix corpus.generate\` and review the diff:` followed by per-file `affected case id(s): [...]` |
| "no shipped module references the conformance apparatus" (`package_boundary_test.exs:29`) | `lib/predicator/instructions.ex` - add a comment line `# see Predicator.Conformance.Generator` near the top (the check is `String.contains?` over the source, so a comment is a genuine positive) | `offenders == []` fails, listing `lib/predicator/instructions.ex` under "These files ship in the hex package but reference code that does not" |
| "mix.exs still excludes the conformance modules it claims to" (`package_boundary_test.exs:55`) | `mix.exs:78` - `exclude_patterns: [~r{\Alib/predicator/conformance/}]` → `exclude_patterns: []` | the equality assertion fails: `[] != [~r/\Alib\/predicator\/conformance\//]` |

`mix.exs` is an `area:build` file. Revert it immediately after observing the
red, and confirm with `git diff mix.exs` producing nothing before moving on -
an `area:build` file left dirty in this branch is exactly the collision
CLAUDE.md's exclusivity rule exists to prevent.

### Success Criteria

#### Automated Verification
- [x] `grep -c "# sabotage:"` returns `1` for `corpus_freshness_test.exs` and
      `2` for `package_boundary_test.exs`
- [x] `git status --short` lists only those two test files - in particular
      `mix.exs`, `lib/`, and `conformance/` are clean
- [x] Full gate passes: `mix quality`

#### Manual Verification
- [x] The corpus-freshness red named affected case ids, i.e. the mutation moved
      real generated content rather than merely failing to build
- [x] The package-boundary red named the file the comment was added to
- [x] `git diff` shows comment-only changes

---

## Phase 3: `opcode_coverage_test.exs` + `function_coverage_test.exs` (6 tests)

### Overview

The two coverage bindings and their exclusion-list sync checks. Three of these
six are bindings between a hardcoded list and `conformance/README.md`; for those
the list *is* the binding, so mutating the list (or the README) is the plausible
mutation, not a cop-out.

### Changes Required

**Files**: `test/predicator/conformance/opcode_coverage_test.exs`,
`test/predicator/conformance/function_coverage_test.exs`.

| Test (file:line) | Mutation | Expected red |
|---|---|---|
| "every opcode except the documented exclusions appears in at least one case" (`opcode_coverage_test.exs:33`) | `lib/predicator/instructions.ex:64` - add a new opcode to `@opcodes` that no case exercises, e.g. `"noop" => %{isa: 1, tier: 1},`. (Deleting a case does **not** work here: verified against the checked-in corpus, *no* opcode is covered by exactly one case, so a single deletion leaves every opcode still covered. Adding an uncovered opcode is also the truer mutation - "a new opcode landed with no conformance case" is precisely what this test exists to catch.) | `opcode(s) with no conformance case: ["noop"] - author a case in conformance/cases/*.json` (also reddens `isa_sync_test.exs` - expected collateral, judge by this file) |
| "the excluded opcode(s) genuinely have no case, so the exclusion is not stale" (`opcode_coverage_test.exs:47`) | `opcode_coverage_test.exs:31` - `@excluded_opcodes ~w(relative_date)` → `~w(relative_date lit)` | `opcode(s) ["lit"] are both excluded from the coverage rule and covered by a case` (also reddens the README-sync test below - expected, judge by the message) |
| "the exclusion list here matches conformance/README.md's documented exclusions exactly" (`opcode_coverage_test.exs:57`) | `conformance/README.md`, section `### Opcodes excluded from the coverage rule` (`:234`) - delete the `` - `relative_date` `` bullet | `this test's @excluded_opcodes ["relative_date"] disagrees with conformance/README.md's ... (found [])` |
| "every registered builtin except the documented exclusions appears in at least one case" (`function_coverage_test.exs:26`) | `conformance/cases/functions.json` - delete the case object with id `functions/upper`. Verified: `upper` is covered by exactly that one case and no other | `builtin function(s) with no conformance case: ["upper"] - author a case in conformance/cases/*.json` |
| "the excluded function(s) genuinely have no case, so the exclusion is not stale" (`function_coverage_test.exs:42`) | `lib/predicator/conformance/coverage.ex:130` - add a genuinely covered builtin: `MapSet.new(["Date.now", "Math.random", "upper"])`. Verified: `upper` appears as a `call` operand in the shipped corpus | `function(s) ["upper"] are both excluded from the coverage rule and covered by a case` |
| "the exclusion list only names functions that are actually registered" (`function_coverage_test.exs:54`) | `lib/predicator/conformance/coverage.ex:130` - `"Date.now"` → `"Date.nowww"` | `Coverage.documented_exclusion_functions/0 names ["Date.nowww"], which is not a key of Predicator.Evaluator.merge_functions([]) - the exclusion is stale` |

Both `coverage.ex` mutations also redden
`Predicator.Conformance.CoverageTest`'s README-sync describe block, and deleting
the `functions/upper` case additionally reddens the two corpus-freshness tests
(the corpus no longer matches what generation would write). That is expected
collateral - confirm the target file's red carries the message above, and do not
run `mix corpus.generate` to "fix" it. The fix is `git checkout`.

### Success Criteria

#### Automated Verification
- [x] `grep -c "# sabotage:"` returns `3` for each of the two files
- [x] `git status --short` lists only those two test files - `conformance/cases/`,
      `conformance/README.md`, `lib/predicator/instructions.ex`, and
      `lib/predicator/conformance/coverage.ex` are clean
- [x] Full gate passes: `mix quality`

#### Manual Verification
- [x] The `functions/upper` deletion named `upper` in the red, confirming that
      case really was the only cover
- [x] The added `"noop"` opcode appeared in the coverage red, not merely in an
      `isa_sync_test.exs` failure
- [x] Each note names the mutated file or constant

---

## Phase 4: `schema_validation_test.exs` (8 tests)

### Overview

The largest file: eight tests binding the generated artifacts, the authored
cases, and the schemas to one another. Every mutation here is a one-key edit to
a file under `conformance/schema/` (or one line of a corpus file).

### Changes Required

**File**: `test/predicator/conformance/schema_validation_test.exs`.

| Test (line) | Mutation | Expected red |
|---|---|---|
| "each case in each tier-N.json satisfies the schema" (`:31`) | `conformance/schema/corpus.json` - add a name no generated case carries (e.g. `"provenance"`) to the root `required` array | `conformance/corpus/tier-1.json: case "<id>" fails schema/corpus.json: {:error, ...}` |
| "the manifest satisfies the schema" (`:47`) | `conformance/schema/manifest.json` - change `isa_version`'s `"type": "integer"` to `"string"` | `:ok == SchemaValidator.validate(schema, manifest)` fails on the isa_version type |
| "each case in conformance/cases/*.json satisfies the schema" (`:56`) | `conformance/schema/case.json` - add an optional key that not every authored case carries (e.g. `"notes"`) to the root `required` array. (`"expected"` does not work: verified against every file in `conformance/cases/*.json`, every authored case carries it, so it stayed green - `"notes"` is genuinely optional and reddened as expected.) | `conformance/cases/<file>.json: case "<id>" fails schema/case.json: {:error, ...}` |
| "the result enum is exactly [\"pass\", \"fail\"] - the structural half of never-skip" (`:70`) | `conformance/schema/report.json` - `results.items.properties.result.enum` → `["pass", "fail", "skip"]` | `result_schema["enum"] == ["pass", "fail"]` fails with the three-element list |
| "a well-formed report instance validates" (`:78`) | `conformance/schema/report.json` - add a key the in-test report literal omits (e.g. `"produced_at"`) to the root `required` array | `:ok == SchemaValidator.validate(schema, report)` fails on the missing required key |
| "a report containing a skip result fails validation" (`:91`) | Same as `:70` - `report.json`'s result enum gains `"skip"` | `assert {:error, _reason} = ...` fails because validation now returns `:ok` |
| "the checked-in corpus matches what generation would produce right now" (`:109`) | Hand-edit one line of `conformance/corpus/tier-2.json` (change one character inside a string value) | `conformance/corpus/tier-2.json is stale - run \`mix corpus.generate\`` |
| "each schema declares draft 2020-12, an $id under this repo, and an object root" (`:118`) | `conformance/schema/registry.json` - change `$id`'s host from `https://github.com/riddler/predicator-ex/...` to `https://example.com/...` | `conformance/schema/registry.json: $id does not follow the sibling schemas' convention` |

`:70` and `:91` share one mutation, exercised once. Both notes name it; that is
correct, not a shortcut - the enum is genuinely the single thing both bind.

Watch for the `:31` and `:56` mutations also reddening the freshness test at
`:109` (a schema change does not move the corpus, so it should not - if it does,
the mutation touched more than intended; narrow it).

### Success Criteria

#### Automated Verification
- [x] `grep -c "# sabotage:" test/predicator/conformance/schema_validation_test.exs`
      returns `8`
- [x] `git status --short` lists only that test file - `conformance/schema/` and
      `conformance/corpus/` are clean
- [x] Full gate passes: `mix quality`

#### Manual Verification
- [x] Each red named the schema file or corpus file that was mutated
- [x] The `:91` red was "validation returned `:ok`", i.e. the negative test
      genuinely depends on the enum

---

## Phase 5: `ratchet_registry_test.exs` (5 tests)

### Overview

The ratchet worked example bound to `conformance/RATCHET.md`'s rules. All five
mutations land in `conformance/examples/registry.example.json` or
`conformance/schema/registry.json`.

### Changes Required

**File**: `test/predicator/conformance/ratchet_registry_test.exs`.

| Test (line) | Mutation | Expected red |
|---|---|---|
| "the example satisfies the schema" (`:32`) | `conformance/schema/registry.json` - add a key the example lacks (e.g. `"generated_at"`) to the root `required` array | `:ok == SchemaValidator.validate(schema, example)` fails on the missing required key |
| "every (case_id, surface) entry exists in the shipped corpus, with a matching tier" (`:41`) | `conformance/examples/registry.example.json` - flip one entry's `"tier":1` to `"tier":2` (prefer the tier flip over a `case_id` rename: it reddens this test alone, where a bogus id also reddens the R5 test) | `entry "<case_id>" claims tier 2, but the corpus case is tier 1` |
| "the example's corpus_hash and isa_version equal the manifest's" (`:79`) | `registry.example.json` - change one hex character of `corpus_hash` | `conformance/examples/registry.example.json's corpus_hash does not match conformance/manifest.json` |
| "re-encoding the parsed example per RATCHET.md's rules byte-matches the file on disk" (`:95`) | `registry.example.json` - insert one space after a top-level colon, e.g. `"isa_version": 2` → `"isa_version":  2` (whitespace only, still valid JSON, still parses) | `... is not exactly the canonical encoding RATCHET.md specifies (sorted top-level keys, one array element per line, no incidental whitespace)` |
| "every evaluator-surface tier-1 corpus case has a matching entry" (`:108`) | `registry.example.json` - delete one whole `"surface":"evaluator"` entry line from `entries` (and its trailing comma, keeping the file valid JSON) | `the example claims evaluator/tier 1 complete, but is missing entries for: ["<case_id>"]` |

The `:95` mutation must be whitespace-only inside an otherwise valid document -
if the edit breaks JSON parsing, `JSON.decode!` raises and the red is a crash,
not the canonical-encoding assertion. That is the wrong red; retry with a
smaller edit.

### Success Criteria

#### Automated Verification
- [x] `grep -c "# sabotage:" test/predicator/conformance/ratchet_registry_test.exs`
      returns `5`
- [x] `git status --short` lists only that test file -
      `conformance/examples/` and `conformance/schema/` are clean
- [x] Full gate passes: `mix quality`
- [x] All seven files now carry a note per `test` block: the two greps in
      "Desired End State" agree file by file (6, 1, 3, 3, 8, 5, 2)

#### Manual Verification
- [x] The `:95` red was the canonical-encoding assertion, not a JSON decode
      crash
- [x] Every note across all seven files reads as one line and names a concrete
      mutation
- [x] Any test that could not be reddened is recorded as a Finding below and
      reported, not silently skipped

---

## Testing Strategy

### Unit Tests

No new tests. The 28 existing `test` blocks in the seven files are the subject;
none of their assertions change.

### Integration Tests

None. This bead adds no behavior.

### Manual Testing Steps

The manual test *is* the work: 28 mutate/observe/revert cycles. Per cycle:

1. Apply the mutation named in the phase table.
2. `mix test <target file>` - confirm exactly the expected assertion message.
3. `git checkout -- <mutated file>`; re-run the target file; confirm green.
4. Write the note.

Per phase, before committing:

5. `git status --short` shows only the phase's test file(s). Any other path is
   an unreverted mutation.
6. `git diff` over the test files shows comment-only changes.
7. `mix quality` green.

A red that is a compile error, a `JSON.decode!` crash, or an unrelated
assertion is not a passing sabotage: revert, pick a narrower mutation, retry.

## Open Questions

Recorded rather than blocking, since no human was available during planning.
Neither blocks implementation; both have a stated default.

1. **Two tests, one mutation** (`schema_validation_test.exs:70` and `:91`).
   Default taken: both carry a note naming the same `report.json` enum
   mutation, exercised once. The alternative - inventing a second, weaker
   mutation so the notes differ - would make the notes less true. If a reviewer
   prefers distinct mutations, `:78`'s required-key mutation can be borrowed
   for `:91`.
2. **Whether any of the 28 warrants `# sabotage: n/a`.** Default taken: none.
   All seven files are in the binding class by enumeration, and every block has
   a mutation candidate above. `schema_validation_test.exs:78` ("a well-formed
   report instance validates") is the closest call - it reads as a validator
   self-test - but it does bind `report.json`'s `required` set, so it gets a
   real mutation. If a block resists every mutation, it becomes a Finding under
   the rule in "Implementation Approach", not an `n/a`.

## References

- Decision note: `docs/research/260808-px-9ab-sabotage-notes.md` (the class of
  seven, the note format, and why the broad statifier form was rejected)
- Convention: `CLAUDE.md`, Conventions - "Binding tests carry a sabotage note"
- Beads issue: `px-suw` (depends on `px-9ab`); labels `area:conformance`,
  `area:evaluator`
- Prior plans that built the artifacts these tests bind:
  `docs/plans/260807-px-35i.4-conformance-corpus.md`,
  `docs/plans/260807-px-35i.8-sibling-conformance-ratchet.md`
- Mutation targets: `lib/predicator/instructions.ex:45,64-90`,
  `lib/predicator/conformance/coverage.ex:123,130`, `mix.exs:78`,
  `docs/isa.md:58,192-197,209+`, `conformance/README.md:234,247`,
  `conformance/schema/*.json`, `conformance/examples/registry.example.json`
- ADR-0003 (this repo leads the ISA) - cited for why a vacuous binding test
  ships a wrong specification to siblings; no ISA movement here

## Findings

_(None yet. Append any binding test that stays green under every plausible
mutation here, with the mutations tried, and report it.)_

## Deferred Manual Verification

### Phase 1: `test/predicator/isa_sync_test.exs`

- [x] Each of the six reds was observed and matched the expected message above -
      not a compile error, not an unrelated suite failure
- [x] Each note names the mutation, not the assertion, and reads as one line
- [x] `git diff` shows comment-only changes

### Phase 2: `corpus_freshness_test.exs` + `package_boundary_test.exs`

- [x] The corpus-freshness red named affected case ids, i.e. the mutation moved
      real generated content rather than merely failing to build
- [x] The package-boundary red named the file the comment was added to
- [x] `git diff` shows comment-only changes

### Phase 3: `opcode_coverage_test.exs` + `function_coverage_test.exs`

- [x] The `functions/upper` deletion named `upper` in the red, confirming that
      case really was the only cover
- [x] The added `"noop"` opcode appeared in the coverage red, not merely in an
      `isa_sync_test.exs` failure
- [x] Each note names the mutated file or constant

### Phase 4: `schema_validation_test.exs`

- [x] Each red named the schema file or corpus file that was mutated
- [x] The `:91` red was "validation returned `:ok`", i.e. the negative test
      genuinely depends on the enum

### Phase 5: `ratchet_registry_test.exs`

- [x] The `:95` red was the canonical-encoding assertion, not a JSON decode
      crash
- [x] Every note across all seven files reads as one line and names a concrete
      mutation
- [x] Any test that could not be reddened is recorded as a Finding below and
      reported, not silently skipped

### How these were verified

All 27 distinct mutations (28 tests; `schema_validation_test.exs:73` and `:96`
share the report-enum mutation) were re-applied and re-observed in a single
pass on 2026-08-08, after the phases had landed. Every one reddened its bound
test with the message this plan predicts. No test resisted mutation, so the
Findings section stays empty.

Two things are worth carrying forward for anyone repeating this:

- **Force a recompile around every mutation to Elixir source.** `mix`'s
  staleness check is mtime-based, and a mutate-compile-revert cycle that
  completes inside one second can leave the mutated beam in place: the source
  reads correct, `git status` is clean, and the *next* mutation is then judged
  against a stale module. The first pass of this re-verification hit exactly
  that - `Predicator.Instructions.tier("load")` returned `{:ok, 2}` from a
  clean tree - and produced plausible-looking but worthless reds for five of
  Phase 1's six mutations. `MIX_ENV=test mix compile --force` after both the
  mutation and the revert removes the hazard.
- **Assert a green baseline before each mutation.** It is the cheap check that
  catches the above: if the bound test is already red on the clean tree, the
  previous revert did not take and any red observed next proves nothing.

`docs/isa.md`, `conformance/**`, and `mix.exs` mutations need no recompile -
they are read at runtime - but the baseline check is worth running for them
anyway.
