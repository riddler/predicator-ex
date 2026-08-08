# Porting and Embedding Guides Implementation Plan

## Overview

Predicator documents application developers well and its other two audiences
not at all. This plan adds the two missing how-to guides:

- `docs/guides/porting.md` for a sibling implementer writing predicator in
  another runtime, and
- `docs/guides/embedding.md` for a consumer that compiles once, stores the
  instruction list, and runs it later (statifier's position).

Both are registered as ExDoc extras in the Guides group and linked from the
README. Both are **assembly of material that already exists and is settled** -
`docs/isa.md`, `conformance/README.md`, `conformance/RATCHET.md`,
`Predicator.Instructions`, `Predicator.Compiled`, ADR-0003 and ADR-0009. No
new decision, no new behavior, no ISA movement.

Beads issue: **px-ycj**. Label: `area:docs` (see "Area labels and the
`area:build` flag" below - the change also touches `mix.exs` and one test
file).

Both dependencies are closed and merged: **px-35i.5** (PR #107, the
`%Predicator.Compiled{}` envelope, ADR-0009) and **px-35i.8** (PR #95,
`conformance/RATCHET.md`). This plan is written against what landed, not
against the bead description's forecast of it.

## Current State Analysis

### What exists that these guides assemble

**Specification and reference (already written, must not be duplicated):**

- `docs/isa.md` - §1 versioning (the half-open opcode-set interval, retirement
  minting the next integer, the `opcode_set/1` membership check superseding a
  bare `<=`), §2 execution model, §3 value types with the normative duration
  shape, §4 the opcode table with ISA and Tier columns plus the "Retired
  opcodes" subsection, §5 per-opcode semantics and errors, §6 "Not in the ISA",
  §7 version history (v1 up to 3.6.x, v2 in 3.7.0, v3 retiring `and`/`or` in
  4.0.0), §8 the conformance corpus pointer.
- `conformance/README.md` - the runner contract: the two surfaces
  (`conformance/README.md:29-55`), retired opcodes and their frozen cases,
  the `$type` tagged-value table, "error type and reason are normative;
  message is not", tiers being cumulative, "never skip", and how to add a case
  with no Elixir toolchain.
- `conformance/RATCHET.md` - the registry format: fields, `(case_id, surface)`
  matching, the sorted one-line-per-entry encoding, rule 1 (unmatched entry
  fails), rule 3 (verify-then-add), the reference-runner pseudocode, and the
  R1-R5 check step including what `claims` means.
- `conformance/manifest.json` - `corpus_hash`, `isa_version: 3`, and per-tier
  `{name, file, case_count, opcodes}`. The `opcodes` array is **version-scoped**
  (`conformance/README.md:85-90`): at `isa_version: 3` tier 1's array no longer
  lists `and`/`or`, while `docs/isa.md` §4's tier table still does, because a
  retired opcode keeps its tier membership. Neither is stale; a guide that
  restates either list would be.
- `conformance/examples/registry.example.json` - a real registry in the
  normative encoding.
- `docs/reference/language.md` - operators, builtins, "Error Shapes".
- `docs/architecture.md:89-153` - the Cross-Language Siblings section, which
  already carries the dated sibling-version snapshot and the `=` grammar-break
  divergence. Both guides link to it rather than restating it.

**Code the embedding guide walks through:**

- `Predicator.compile/1` (`lib/predicator.ex:395-405`) returns
  `{:ok, instruction_list}` - the bare, portable artifact.
- `Predicator.compile_with_positions/1` (`lib/predicator.ex:426-436`) and
  `Predicator.compile_with_spans/1` (`lib/predicator.ex:457-467`) return
  `{:ok, %Predicator.Compiled{instructions:, positions:}}`.
- `Predicator.Compiled` (`lib/predicator/compiled.ex:1-101`) - its moduledoc's
  "What to store" section is the source of truth for the storage advice,
  including the no-integrity-check hazard: a table from one source attached to
  another source's instructions yields a confidently wrong position rather than
  an error (`lib/predicator/compiled.ex:24-32`).
- `Predicator.isa_version/0` (`lib/predicator.ex:354-369`, delegating to
  `Predicator.Instructions.isa_version/0`) returns `3`.
- `Predicator.Instructions.required_isa/1`
  (`lib/predicator/instructions.ex:246-297`) - flat opcode scan, `{:ok, 1}` for
  an empty list, `unknown_opcode` and `malformed_instruction` error reasons.
- `Predicator.Instructions.in_isa?/2` and `opcode_set/1`
  (`lib/predicator/instructions.ex:146-210`) - **the caveat the guide must
  carry**: once any opcode is retired, a bare
  `required_isa(list) <= isa_version()` comparison is insufficient, because a
  retired opcode still reports the version that *introduced* it. The correct
  check is membership in `opcode_set(isa_version())`.
- `Predicator.Instructions.retired_in/1`
  (`lib/predicator/instructions.ex:212-244`) - names the retiring version so a
  refusal can say which.
- `Predicator.Instructions.upgrade/1`
  (`lib/predicator/instructions.ex:325-404`) - identity guarantee, three
  documented semantic divergences, and the "upgraded list requires ISA v2, so
  upgrade in step with the artifact's other consumers" warning.
- `Predicator.Instructions.tier/1` (`lib/predicator/instructions.ex:110-144`).
- The evaluator's `retired_opcode` refusal
  (`lib/predicator/evaluator.ex:512-528`).

**Registration and linking mechanics:**

- `mix.exs:95-115` - `docs()`'s `extras:` list (currently three guides, at
  `mix.exs:99-101`) and `groups_for_extras:` where `Guides: ~r{docs/guides/}`.
- `README.md:63-78` - the Documentation bullet list, one `- [Title](path) -
  description` line per document; `README.md:90-105` - Cross-Language Siblings.
- `test/docs_examples_test.exs:14-17` - every existing guide is executed with
  `doctest_file/1`, so an `iex>` block in a guide is a test.
- `CHANGELOG.md:8` - `## [Unreleased]` with an `### Added` subsection already
  open.

### What is missing

Nothing joins these into a path. A sibling implementer has to discover on
their own that the corpus offers two *independent* conformance surfaces and
that the evaluator surface needs no parser - the single most useful fact about
porting this language, currently recorded only in a bead note. An embedder has
to assemble the store/check/refuse lifecycle from two function docs and an ADR.

### Constraints

- **Diátaxis: these are how-to guides.** Task-oriented, goal-framed, written
  for a competent reader. Action, not teaching; branch where a real decision
  exists ("if you target v2, ..."); point at `docs/isa.md`,
  `docs/reference/language.md`, and `conformance/RATCHET.md` for exhaustive
  detail instead of inlining it. No opcode table, no field-by-field registry
  schema, no re-argued ADR reasoning in either file.
- **House style, judged per file and its neighbors.** The three existing guides
  in `docs/guides/` use plain hyphens and no em dashes, `##` section headings
  under a single `#` title, fenced `elixir` blocks with `iex>` prompts, and
  short tables where a field-by-field enumeration is genuinely needed. Match
  that exactly.
- **Every claim traces to a file in this repo.** No writing from memory. The
  facts these guides state are already written down in the files listed above;
  the work is selection and sequencing.
- **ADR-0003 forbids a support matrix here.** Neither guide states what the
  Ruby or JavaScript sibling currently supports; `docs/architecture.md` carries
  the dated snapshot and each sibling's own repository is the authority.

## Desired End State

`docs/guides/porting.md` and `docs/guides/embedding.md` exist, are listed in
`mix.exs`'s `extras:` (landing in the Guides group), are linked from
`README.md`'s Documentation list, and have an entry under
`## [Unreleased]` / `### Added` in `CHANGELOG.md`.

`porting.md` names both conformance surfaces, says to lead with the evaluator
and why (no parser needed; every case has an evaluator form), shows how to run
the cumulative tiers, and says what "conformant at tier N" does and does not
claim. `embedding.md` walks the `required_isa/1` versus `isa_version/0` check
end to end, including the retired-opcode caveat and the refuse/upgrade
branches, and says what a major ISA version does to a stored artifact.

Verification: `mix quality` is green, `mix docs` builds with no new warnings
and both guides appear under Guides in the generated sidebar, and every `iex>`
block in `embedding.md` passes as a doctest.

### Key discoveries

- **The evaluator surface is the entry point for a port.** Every corpus case
  has an evaluator form; only `source != null` cases have a compiler form
  (`conformance/README.md:29-55`). Tier 1 is self-contained and complete on its
  own (`conformance/README.md:174-179`), so a port can be green with no lexer
  and no parser written.
- **Tiers are cumulative and are a property of opcodes, not values**
  (`conformance/README.md:165-186`, `docs/isa.md:183-203`).
- **`claims` is what turns a registry into a green/red signal** (R5,
  `conformance/RATCHET.md:243-287`), and an empty `claims` array is a valid,
  passing registry - the ADR-0003-aligned "here is what I pass, I am not
  asserting a tier yet".
- **The bare `<=` version comparison is a trap post-retirement**
  (`lib/predicator/instructions.ex:146-210`, `docs/isa.md:48-53`). This is the
  single most load-bearing correction `embedding.md` carries.
- **Positions are a derived fact with no integrity check**
  (`lib/predicator/compiled.ex:24-32`) - store the source and recompile, never
  the table.
- **The corpus is not in the hex package** (`mix.exs:54-83`): the audience for
  `porting.md` works from a git checkout. Say so once, early.

## What We're NOT Doing

- **No `lib/` changes.** No new function, no changed behavior, no ISA movement.
  The ISA stays at v3 and this plan has no `## ISA Impact` section.
- **No new ADR.** Both dependencies already produced theirs (ADR-0003,
  ADR-0009).
- **No reference material.** Neither guide reproduces the opcode table, the
  tier-to-opcode listing, the registry field schema, or the `$type` table. They
  link to `docs/isa.md`, `conformance/manifest.json`, `conformance/RATCHET.md`,
  and `conformance/README.md`.
- **No sibling support matrix** (ADR-0003), and no edits to
  `docs/architecture.md`'s Cross-Language Siblings section.
- **No writing a real runner.** `conformance/RATCHET.md` already ships the
  reference-runner pseudocode; `porting.md` points at it.
- **No widening of `mix.exs` beyond the two `extras:` entries.** ADR-0009 and
  the later ADRs are absent from `extras:` - a pre-existing gap that px-35i.5
  deliberately left to a separate `area:build` bead. Do not fix it here.
- **No third guide, no guides landing page, no restructuring of
  `docs/guides/`.** Diátaxis's workflow rule: structure is a consequence of
  incremental improvement, not a precondition.
- **No changes to `conformance/**`.** Any discrepancy noticed while writing is
  reported, not fixed here.

## Implementation Approach

One guide per phase, each phase complete in itself - the file, its `extras:`
entry, and its README link - so each is independently green and independently
committable. A third phase carries the CHANGELOG entry and the whole-change
verification (`mix docs`, sidebar, link check).

`porting.md` goes first: it is the larger assembly job and touches no Elixir
API, so it cannot be blocked by anything. `embedding.md` follows and is the
phase that introduces doctests.

Write each guide by opening the source files listed under "Sources" for that
phase and quoting the facts from them. If a sentence cannot be traced to one of
those files, cut it.

### Area labels and the `area:build` flag

The bead is labeled `area:docs`, which covers `docs/**`, `README.md`, and
`CHANGELOG.md`. Two files fall outside it:

- **`mix.exs` is an `area:build` file, and `area:build` is exclusive.** This
  change touches exactly two lines of it (the `extras:` entries) and moves no
  dependency, no `mix.lock`, and no gate config, so it does not carry the
  hazard the exclusivity rule exists to prevent. Per CLAUDE.md, a branch
  touching an area it was not labeled with is **worth noticing at merge time**:
  flag it in the PR body rather than silently relabeling the bead.
- **`test/docs_examples_test.exs`** gains one `doctest_file/1` line in Phase 2
  (see Open Questions). It belongs to no `area:` row; flag it the same way.

## Phase 1: `docs/guides/porting.md`

### Overview

The path a sibling implementer follows: pick a version, learn what it obliges,
verify the evaluator surface, then the compiler surface, then record and defend
the claim.

### Sources (read before writing, quote from these only)

`docs/isa.md` (§1, §2, §3, §4 including "Retired opcodes", §6, §7, §8),
`conformance/README.md` (whole file), `conformance/RATCHET.md` (whole file),
`conformance/manifest.json`, `conformance/examples/registry.example.json`,
`conformance/schema/report.json`, `docs/adr/0003-...md`,
`docs/architecture.md:89-153`, `mix.exs:54-83` (the package exclusion).

### Changes Required

#### 1. The guide

**File**: `docs/guides/porting.md` (new)
**Shape**: `# Porting Predicator`, then `##` sections in this order. Target
roughly 150-220 lines - comparable to `location-expressions.md`.

1. **Opening paragraph, no heading.** Who this is for (someone implementing
   predicator's instruction set in another runtime), the two artifacts that
   bind them (`docs/isa.md` at the version they claim, and the corpus at the
   tiers they claim - ADR-0003's phrasing), and the practical note that the
   corpus lives in a git checkout, not the hex package (`mix.exs:54-83`).

2. **`## Pick the ISA version you are implementing`** - versions are integers
   independent of the library's semver; a version's opcode set is the half-open
   interval `[introduced, removed_in)` and is fixed once minted, so **declaring
   v1 or v2 claims `and`/`or` even though v3 retired them** (`docs/isa.md`
   §1, §7). A sibling behind the current version is an expected, documented
   state, not a defect (ADR-0003) - one sentence, linked, not re-argued. Link
   `docs/isa.md` §7's version-history table rather than restating it.

3. **`## What the version obliges you to implement`** - the opcode rows in that
   version's set (`docs/isa.md` §4), plus the execution-model rules that are
   easy to miss because they live outside the table (`docs/isa.md` §2): opcodes
   validate and never coerce; "falsy" at a jump is exactly `false` or
   undefined; jumps are relative and forward-only; undefined is a first-class
   value; a malformed operand is `unknown_instruction`, not a bad-operand
   error; the three error **types** are normative and messages are not. Add the
   normative duration shape (`docs/isa.md` §3) and the corresponding
   `reason`-token rule from `conformance/README.md:139-162`. Close with a short
   "not required of you" list pointing at `docs/isa.md` §6: surface syntax,
   parse errors, the builtin function set, backward jumps.

4. **`## Start with the evaluator surface`** - the load-bearing section. State
   the two surfaces and the asymmetry between them
   (`conformance/README.md:29-55`): the evaluator surface takes `instructions`
   plus `context` and compares against `expected_result`/`expected_error`, and
   **every case has one**; the compiler surface takes `source` and compares the
   emitted list structurally, and only `source != null` cases have one. Then
   the recommendation and its reason: implement the evaluator first, because it
   needs no lexer and no parser, and tier 1 alone is a complete, green,
   honest result. Note that a `source: null` case is *absent from* the compiler
   surface's case set, not skipped by it.

5. **`## Run tier 1`** - the mechanics. Read `conformance/manifest.json`; tiers
   are **cumulative** (running tier N means tiers 1..N); decode values through
   the `$type` table; compare `expected_error` on `type` and `reason` only,
   never the message; emit a report matching `conformance/schema/report.json`.
   State never-skip at the point it bites: an unimplemented feature is
   `{"result": "fail", "reason": "<feature> not implemented"}`, never an absent
   entry. Point at `conformance/RATCHET.md`'s reference-runner pseudocode
   rather than reproducing it. **Do not restate any tier's opcode list** - the
   manifest's per-tier `opcodes` array is version-scoped and is the live
   answer.

6. **`## Add the compiler surface`** - filter to `source != null`; compare
   structurally against `instructions`; the corpus never checks surface syntax,
   so `=` versus `==` is invisible here (`conformance/README.md:14-28`,
   `docs/isa.md` §6). Note that the two surfaces climb on independent
   schedules - an evaluator at tier 5 with a compiler at tier 1 is a coherent
   state (`conformance/RATCHET.md:76-85`).

7. **`## Record what you pass`** - one registry file per implementation
   covering both surfaces, living in the sibling's own repo; grown only by
   verify-then-add, never hand-edited; pinned to `corpus_hash` plus
   `isa_version`; entries keyed on `(case_id, surface, tier)`; an unmatched
   entry fails the run. Point at `conformance/RATCHET.md` for the normative
   field list and encoding and at `conformance/examples/registry.example.json`
   for a real one. Do not reproduce the field tables.

8. **`## What "conformant at tier N" claims`** - the closing section the bead
   asks for. A claim is per surface, per tier, against one pinned corpus
   revision: R5 says every case in tiers 1..N on that surface has an entry, R4
   says every recorded pass still passes today. Then the boundaries: entries
   above the claimed tier are legal and still ratchet-checked; an empty
   `claims` array is a valid passing registry; and the claim says nothing about
   surface syntax, parse errors, the builtin function set beyond the tier-5
   cases, ordering comparisons between two maps, clock- and RNG-dependent
   opcodes and functions, or the `on_unbound` evaluation option
   (`conformance/README.md:232-269`).

**Typography and links**: plain hyphens, no em dashes, matching the neighbors.
Relative links for targets that are ExDoc extras (`../isa.md`,
`../reference/language.md`, `../architecture.md`,
`../adr/0003-the-elixir-implementation-leads-the-isa.md`); absolute
`https://github.com/riddler/predicator-ex/blob/main/...` links for targets that
are not (`conformance/README.md`, `conformance/RATCHET.md`,
`conformance/manifest.json`, `conformance/examples/registry.example.json`) -
see Open Questions.

**No `iex>` blocks in this guide.** Its examples are language-neutral JSON and
pseudocode in ```json / ```text fences, which is what its audience runs.

#### 2. ExDoc registration

**File**: `mix.exs`
**Change**: append to the `extras:` list, after
`"docs/guides/location-expressions.md"` (`mix.exs:101`):

```elixir
"docs/guides/embedding.md",
"docs/guides/porting.md",
```

Phase 1 adds only the `porting.md` line; Phase 2 adds `embedding.md` above it.
`groups_for_extras:`'s `Guides: ~r{docs/guides/}` already matches, so no change
there.

#### 3. README link

**File**: `README.md`
**Change**: add a bullet to the Documentation list (`README.md:63-78`), after
the Location expressions entry, in the existing `- [Title](path) -
description` form:

```markdown
- [Porting Predicator](docs/guides/porting.md) - implementing the instruction
  set in another language and verifying it against the conformance corpus
```

Also add one sentence to Cross-Language Siblings (`README.md:90-105`) pointing
a would-be implementer at the guide. Do not restructure that section.

### Success Criteria

#### Automated Verification:
- [x] `docs/guides/porting.md` exists and is non-empty
- [x] `mix.exs`'s `extras:` contains `"docs/guides/porting.md"`
- [x] `README.md` contains `docs/guides/porting.md`
- [x] Every relative link target in the new file resolves on disk:
      `grep -o '](\.\./[^)]*)' docs/guides/porting.md` and check each path
- [x] Full gate passes: `mix quality`
- [x] `mix docs` completes with no new warnings

#### Manual Verification:
- [ ] The guide reads as a how-to: goal-framed sections, imperative steps, no
      paragraph that re-argues ADR-0003 or reproduces the opcode table
- [ ] Both surfaces are named, and the evaluator-first recommendation states
      *why* (no parser needed; tier 1 is complete on its own)
- [ ] No tier's opcode list, and no sibling support matrix, is restated in the
      guide
- [ ] Typography matches the neighboring guides (hyphens, no em dashes)
- [ ] `doc/index.html` from `mix docs` shows the guide under Guides

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In looped execution the Automated
Verification gates advancement and the Manual items are deferred to the end.

---

## Phase 2: `docs/guides/embedding.md`

### Overview

The compile-once/store/check/run lifecycle, ending at what a major ISA version
does to something already in a database.

### Sources (read before writing, quote from these only)

`lib/predicator/compiled.ex` (whole file), `lib/predicator.ex:354-467`,
`lib/predicator/instructions.ex` (whole file), `lib/predicator/evaluator.ex`
around `retired_opcode_error/2` (`:512-528`), `docs/isa.md` §1 and §4's
"Retired opcodes", `docs/adr/0009-...md`, `docs/adr/0003-...md`,
`docs/reference/language.md`'s "Error Shapes", `README.md:51-61`.

### Changes Required

#### 1. The guide

**File**: `docs/guides/embedding.md` (new)
**Shape**: `# Embedding Compiled Programs`, then:

1. **Opening paragraph, no heading.** Who this is for: a host that compiles a
   predicate once, persists the result, and evaluates it many times later,
   possibly under a different build of this library. Name the payoff in one
   sentence: a stored artifact is never silently mis-run (ADR-0003).

2. **`## Choose a compile function`** - `compile/1` returns the bare
   instruction list, which is the portable artifact; `compile!/1` is its
   raising form; `compile_with_positions/1` and `compile_with_spans/1` return
   `{:ok, %Predicator.Compiled{}}` carrying the instructions and a
   source-location table as one value, which `evaluate/3` accepts directly so
   the table cannot be dropped between compile and evaluate (ADR-0009). One
   short `iex>` example per branch; `compiled.instructions` is byte-identical
   to `compile/1`'s output for the same source.

3. **`## Store the instruction list, not the struct`** - the struct is an
   in-memory value, never a wire format; `positions` holds offsets into a
   source string and is meaningless without it. A program loaded back as a bare
   list evaluates fine and reports `position: nil`, which is *correct*. To get
   positions back after a round trip, persist the **source** and recompile on
   load - recompiling is deterministic. Carry the hazard verbatim in substance:
   nothing checks that a table came from the instructions it is attached to, so
   a persisted table can yield a confidently wrong position, which is worse
   than an honest `nil` (`lib/predicator/compiled.ex:24-32`).

4. **`## Check the ISA version before you run a stored program`** - the end-to-
   end walk the acceptance criteria name:
   - `Predicator.Instructions.required_isa/1` gives the minimum version a list
     needs (flat opcode scan; `{:ok, 1}` for an empty list); `Predicator.
     isa_version/0` gives what this build emits and runs.
   - **The caveat, stated as a caveat and not a footnote**: a bare
     `required_isa(list) <= isa_version()` comparison is not sufficient once
     any opcode has been retired, because a retired opcode still reports the
     version that *introduced* it. The check to perform is membership of every
     opcode in `Predicator.Instructions.opcode_set(Predicator.isa_version())`
     (`docs/isa.md:48-53`, `lib/predicator/instructions.ex:146-210`). Show that
     check as a short `iex>`-able snippet over an instruction list.
   - **What to do when it fails**, as branches: `required_isa/1`'s own error
     values (`unknown_opcode`, `malformed_instruction`) mean the artifact is
     not something this build understands - refuse; an opcode outside
     `opcode_set/1` with a `retired_in/1` answer means the artifact predates a
     retirement - run `Predicator.Instructions.upgrade/1`, which has an
     identity guarantee so it may be called unconditionally over every stored
     artifact; anything else - refuse rather than mis-run (ADR-0003).
   - Note the evaluator's own backstop: running a list containing `and`/`or` on
     this build is refused with reason `"retired_opcode"`, naming ISA v3 and
     pointing at `upgrade/1` (`lib/predicator/evaluator.ex:512-528`). The
     up-front check exists so the refusal happens before a partial run, not
     because the backstop is missing.

5. **`## What a major ISA version does to a stored artifact`** - retirement
   mints the next ISA integer, takes a major library release, and requires an
   upgrade path (`docs/isa.md` §1, ADR-0003). A stored list is therefore never
   stranded and never silently mis-run: it either still runs, or is refused
   with a message naming the version, or is rewritten by `upgrade/1`. Then the
   two consequences an embedder actually has to plan for: `upgrade/1` is not
   answer-preserving against the legacy opcodes and documents exactly three
   divergences (short-circuiting, undefined operands, a non-boolean right
   operand) - link its `@doc` rather than restating all three in full; and the
   upgraded list requires ISA v2, so an artifact shared with another
   implementation must be upgraded in step with its consumers, not ahead of
   them (`lib/predicator/instructions.ex:368-375`).

6. **`## Runtime errors and positions`** - short closing section: what an error
   carries depends on whether the evaluation had a table, pointing at
   `docs/reference/language.md`'s "Error Shapes". Keep it to a few lines; this
   is a pointer, not a second guide.

**`iex>` blocks**: every example must be a genuine, deterministic doctest -
they will be executed (see registration below). Keep them small and prefer
literal instruction lists over multi-step pipelines. A doctest asserting
`Predicator.isa_version()` is `3` is acceptable and desirable: it fails loudly
when the ISA moves.

**Typography and links**: same rules as Phase 1. ADR-0009 is **not** an ExDoc
extra, so link it by absolute GitHub URL.

#### 2. ExDoc registration

**File**: `mix.exs`
**Change**: add `"docs/guides/embedding.md"` to `extras:`, immediately before
the `porting.md` entry added in Phase 1 (embedders before implementers, both
after the three application-developer guides).

#### 3. README link

**File**: `README.md`
**Change**: add the Documentation bullet, placed before the Porting bullet:

```markdown
- [Embedding compiled programs](docs/guides/embedding.md) - storing an
  instruction list and checking its ISA version before running it
```

The existing "Persist `compiled.instructions`, not the struct" paragraph
(`README.md:56-61`) stays; add a trailing pointer to the guide rather than
moving or duplicating that text.

#### 4. Doctest registration

**File**: `test/docs_examples_test.exs`
**Change**: add `doctest_file("docs/guides/embedding.md")` inside the existing
version guard, after the three guide entries. `porting.md` is **not** added -
it has no `iex>` blocks.

### Success Criteria

#### Automated Verification:
- [x] `docs/guides/embedding.md` exists and is non-empty
- [x] `mix.exs`'s `extras:` contains both new guide paths
- [x] `README.md` links both new guides
- [x] Full gate passes: `mix quality` - which executes the new guide's
      doctests through `Predicator.DocsExamplesTest`
- [x] `mix test test/docs_examples_test.exs` passes on its own
- [x] `mix docs` completes with no new warnings

#### Manual Verification:
- [ ] The `required_isa/1` versus `isa_version/0` walk is end to end: get the
      requirement, perform the membership check, and act on each failure branch
- [ ] The bare-`<=` caveat is present and reads as a correction, not a footnote
- [ ] The storage advice matches `Predicator.Compiled`'s moduledoc in substance,
      including the no-integrity-check hazard
- [ ] No section drifts into reference (no opcode table, no full restatement of
      `upgrade/1`'s three divergences) or explanation (no re-argued ADR-0009)
- [ ] Typography matches the neighboring guides

---

## Phase 3: CHANGELOG and whole-change verification

### Overview

Record the user-facing addition and verify the two guides as a set.

### Changes Required

#### 1. CHANGELOG

**File**: `CHANGELOG.md`
**Change**: one entry under the existing `## [Unreleased]` / `### Added`,
matching the surrounding entries' bolded-lead style:

```markdown
- **Two new guides.** [Porting Predicator](docs/guides/porting.md) is the path
  a sibling implementation follows ... and
  [Embedding compiled programs](docs/guides/embedding.md) covers the
  compile-once/store/check lifecycle ... Both are published as hexdocs extras.
```

Place it in the Added list; do not promote or restructure the section
(promoting `## [Unreleased]` is release work and is not authorized here).

#### 2. Verification pass

No file changes. Run `mix docs`, open `doc/index.html`, and confirm both guides
appear under Guides in the expected order; walk the links in both new files.

### Success Criteria

#### Automated Verification:
- [x] `CHANGELOG.md` names both new guide paths under `## [Unreleased]`
- [x] Full gate passes: `mix quality`
- [x] `mix docs` completes with no new warnings
- [x] No file under `lib/` differs from `origin/main`:
      `git diff --stat origin/main -- lib/` is empty

#### Manual Verification:
- [ ] Both guides appear under Guides in the generated sidebar, ordered
      nested-data-access, custom-functions, location-expressions, embedding,
      porting
- [ ] Every link in both guides resolves - relative ones inside the generated
      docs, absolute GitHub ones in a browser
- [ ] The PR body flags the `mix.exs` and `test/docs_examples_test.exs` edits as
      touching areas outside the bead's `area:docs` label

---

## Testing Strategy

### Unit Tests

None added. This change adds no code.

### Integration Tests

`embedding.md`'s `iex>` blocks become executable doctests via
`test/docs_examples_test.exs`, which is the repo's existing mechanism for
keeping published examples from going stale. That is the only new test surface.

### Manual Testing Steps

1. `mix docs` and open `doc/index.html`; confirm the Guides group contains five
   entries in the intended order.
2. Read `porting.md` as an implementer: can you get to a green tier-1 evaluator
   result and a valid registry without opening a bead or an Elixir file?
3. Read `embedding.md` as an embedder: can you write the load-time version
   check from the guide alone, including the retired-opcode branch?
4. Diff-read both files for typography drift against `custom-functions.md`.

## Open Questions (decided)

No human was available while this plan was written, so each question below was
decided rather than asked. Each records the choice and its reasoning; revisit
only if a reviewer disagrees.

1. **Do the new guides get executable doctests, given that would touch
   `test/`?** *Decided: yes for `embedding.md`, no for `porting.md`.* Every
   existing guide is registered in `test/docs_examples_test.exs`, whose
   moduledoc states the principle - "a stale example there is worse than no
   example". An `embedding.md` full of unexecuted Elixir would break that
   convention on the one guide whose examples are most version-sensitive. The
   cost is one line in a test file, flagged at merge time.
   `porting.md`'s examples are JSON and pseudocode, so there is nothing to
   register.

2. **How should the guides link to files that are not ExDoc extras?**
   *Decided: relative links for extras, absolute `github.com/.../blob/main/`
   URLs for non-extras* (`conformance/**`, ADR-0009). A relative link to
   `conformance/README.md` from an extra renders as a dead link on hexdocs, and
   `porting.md`'s entire subject lives in `conformance/`. Adding those files to
   `extras:` would exceed the scope the bead allows for `mix.exs`, so absolute
   URLs are the remaining correct option. `README.md`'s existing relative link
   to `conformance/README.md` has the same defect; it is out of scope and is
   left alone.

3. **Title style: goal-shaped ("How to port ...") or noun-phrase?** *Decided:
   noun-phrase `#` titles - "Porting Predicator", "Embedding Compiled
   Programs" - matching the three neighbors, with goal-shaped `##` section
   headings inside.* House style wins over the Diátaxis titling preference at
   the page level; the task orientation is carried by the sections, which is
   where a reader scanning for their goal actually looks.

4. **Does `porting.md` restate what each tier contains?** *Decided: no.*
   `conformance/manifest.json`'s per-tier `opcodes` array is version-scoped and
   `docs/isa.md` §4's tier table is not, and both are correct for what they
   are. A third copy in a guide would be the one that goes stale. The guide
   tells the reader to read the manifest.

5. **Should `docs/architecture.md`'s Cross-Language Siblings section link the
   new porting guide?** *Decided: no - README only.* The bead asks for README
   links; `architecture.md` was rewritten recently (px-7jd.4, fb8ec3a) and
   adding a cross-link there widens the diff for no acceptance-criteria gain.
   Worth a follow-up bead if a reader misses it.

6. **Guide order in `extras:`?** *Decided: embedding before porting, both after
   the three existing guides.* Rough audience size and proximity to the
   existing guides: an embedder is still a user of this library, an implementer
   is not.

## References

- Beads issue: `px-ycj` (deps `px-35i.5` PR #107, `px-35i.8` PR #95, both
  merged)
- `docs/isa.md` - §1 versioning, §2 execution model, §3 value types, §4 opcode
  table and retired opcodes, §6 not in the ISA, §7 version history, §8 corpus
- `conformance/README.md` - the runner contract: two surfaces (`:29-55`),
  retired cases (`:57-96`), tagged values (`:98-136`), error normativity
  (`:138-162`), tiers (`:164-186`), never skip (`:188-203`), known uncovered
  (`:232-269`)
- `conformance/RATCHET.md` - registry fields (`:25-59`), ordering (`:62-85`),
  encoding rule 2 (`:86-127`), rule 1 (`:129-171`), verify-then-add
  (`:173-196`), reference runner (`:198-237`), check step R1-R5 (`:239-287`)
- `conformance/manifest.json`, `conformance/examples/registry.example.json`,
  `conformance/schema/report.json`
- `docs/adr/0003-the-elixir-implementation-leads-the-isa.md` - the six-part
  decision, especially stored-artifact compatibility (`:113-121`)
- `docs/adr/0009-the-compiled-envelope-carries-the-position-table.md`
- `lib/predicator/compiled.ex:1-101` - "What to store"
- `lib/predicator/instructions.ex:110-404` - `tier/1`, `in_isa?/2`,
  `opcode_set/1`, `retired_in/1`, `required_isa/1`, `upgrade/1`
- `lib/predicator.ex:354-467` - `isa_version/0`, `compile/1`,
  `compile_with_positions/1`, `compile_with_spans/1`
- `lib/predicator/evaluator.ex:512-528` - the `retired_opcode` refusal
- `mix.exs:54-83` (package exclusions), `:95-115` (`extras:`,
  `groups_for_extras:`)
- `README.md:51-105`, `CHANGELOG.md:8`, `test/docs_examples_test.exs:12-18`
- Existing guides for house style: `docs/guides/custom-functions.md`,
  `docs/guides/location-expressions.md`, `docs/guides/nested-data-access.md`

## Deferred Manual Verification

### Phase 1

- [ ] The guide reads as a how-to: goal-framed sections, imperative steps, no
      paragraph that re-argues ADR-0003 or reproduces the opcode table
- [ ] Both surfaces are named, and the evaluator-first recommendation states
      *why* (no parser needed; tier 1 is complete on its own)
- [ ] No tier's opcode list, and no sibling support matrix, is restated in the
      guide
- [ ] Typography matches the neighboring guides (hyphens, no em dashes)
- [ ] `doc/index.html` from `mix docs` shows the guide under Guides

### Phase 2

- [ ] The `required_isa/1` versus `isa_version/0` walk is end to end: get the
      requirement, perform the membership check, and act on each failure branch
- [ ] The bare-`<=` caveat is present and reads as a correction, not a footnote
- [ ] The storage advice matches `Predicator.Compiled`'s moduledoc in substance,
      including the no-integrity-check hazard
- [ ] No section drifts into reference (no opcode table, no full restatement of
      `upgrade/1`'s three divergences) or explanation (no re-argued ADR-0009)
- [ ] Typography matches the neighboring guides

### Phase 3

- [ ] Both guides appear under Guides in the generated sidebar, ordered
      nested-data-access, custom-functions, location-expressions, embedding,
      porting
- [ ] Every link in both guides resolves - relative ones inside the generated
      docs, absolute GitHub ones in a browser
- [ ] The PR body flags the `mix.exs` and `test/docs_examples_test.exs` edits as
      touching areas outside the bead's `area:docs` label
