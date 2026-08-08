# Teaching the Workflow the Conformance Corpus Implementation Plan

## Overview

Teach the ported workflow skills two facts about the conformance corpus that
px-35i.4 created and that nothing in `.claude/` currently carries: the corpus is
**generated output that is never hand-edited**, and an **unexplained corpus diff
in a review is a semantic change nobody meant to make**. Both land as things to
*explain* - a `/commit` message item and a `/merge-request` PR-body item - not
as a new gate step, because `test/predicator/conformance/corpus_freshness_test.exs`
already fails the suite on a stale corpus.

The bead also asks for an explicit decision, either way, on adopting statifier's
sabotage-note practice here, narrowly scoped to corpus-source tests. This plan
makes that decision (Phase 3) and records its reasoning and its cost.

Beads issue: px-9ab (`area:docs`, `area:skills`, `workflow`; depends on the
closed px-35i.4).

## Current State Analysis

### The first acceptance clause is already satisfied

px-9ab's first acceptance clause - "`area:corpus` added to CLAUDE.md's
vocabulary with the paths it covers, or the decision to reuse an existing label
recorded with reasoning" - was **satisfied by px-phw**, which settled the name as
`area:conformance` rather than `area:corpus` and shipped:

- the `area:conformance` row in CLAUDE.md's area table
  (`CLAUDE.md`, "Area labels"), plus the prose explaining why it exists and how
  it interacts with the exclusive `area:build`;
- the label in `.claude/skills/create-issue/SKILL.md:76-78`;
- the full argument in
  `docs/research/260807-px-phw-conformance-area-label.md`.

**This plan does not redo it and must not restate it.** Every phase below is
scoped to the remaining clauses.

### What the corpus actually is, mechanically

Verified in this checkout, because the plan's wording has to be accurate about
what "regenerated" means:

- **Authored source**: `conformance/cases/*.json` - hand-written, minimal JSON
  cases (12 files). These *are* hand-edited; that is how a case is added, and
  `conformance/README.md`'s "How to add a case, without any Elixir" documents
  the flow for a sibling implementer with no Elixir toolchain.
- **Generated output**: `conformance/corpus/tier-{1..5}.json` and
  `conformance/manifest.json`. Written only by `mix corpus.generate`
  (`lib/mix/tasks/corpus.generate.ex`), which runs every authored case through
  the real compiler and evaluator and fills in `instructions`,
  `expected_result`/`expected_error`, `tier`, and `features`.
- **The staleness gate**:
  `test/predicator/conformance/corpus_freshness_test.exs` regenerates in memory
  via the task's public `build_files/0` and byte-compares against the checked-in
  files, failing with `conformance/ is stale - run \`mix corpus.generate\` and
  review the diff:` and the affected case ids.
- **`mix corpus.generate --check`** is the same comparison as a task, writing
  nothing and exiting non-zero on drift.

So the line the skills need to draw is **authored vs generated**, not
"`conformance/**` is off limits". A skill that says "never edit anything under
`conformance/`" would contradict the contributor flow the corpus README ships.

### The hole in the existing gate carve-out

Both `/commit` (Step 0) and `/merge-request` (Step 4) carry the same carve-out:

> if the diff touches nothing under `lib/`, `test/`, or `src/`, and neither
> `mix.exs` nor `mix.lock`, there is no gate to run.

A change to `conformance/cases/*.json` plus its regenerated
`conformance/corpus/*.json` and `conformance/manifest.json` touches **none** of
those paths. The carve-out therefore fires, `mix quality` is skipped, and
`corpus_freshness_test.exs` - the one thing standing between a mis-generated
corpus and a merge - never runs. This is precisely the case the bead's premise
("the suite already fails on a stale corpus") assumes is covered, and it is not.

Closing it is **not a new gate step**: it narrows an existing skip so the gate
that already exists actually runs. Both skills must move together, since
`/merge-request` step 4 explicitly says "matching `/commit` Step 0".

### The sabotage-note question, and what px-35i.4 did to its premise

The bead's argument is: "once suite tests become the SOURCE of an exported
specification, a vacuous test ships to siblings as normative". That premise was
written before px-35i.4 chose its mechanism, and the mechanism it chose changes
the shape of the risk:

- **The ExUnit suite is not the corpus's source.** px-35i.4's plan rejected
  static extraction from the suite (~25% coverage, fragile) and runtime capture
  (unstable ids) in favour of authored JSON completed by the real pipeline. A
  vacuous ExUnit test therefore ships nowhere. `mix corpus.coverage` reads the
  suite as an authoring *checklist*, which is advisory and fails no gate.
- **An authored case cannot be vacuous in the relevant sense.** The generator
  computes the real result and **fails loudly** when an authored `expected`
  disagrees; a case with no `expected` still ships the value the real evaluator
  produced. Statifier's own testing doc reaches the same conclusion about its
  corpus and exempts it: "the corpus is sabotage-proof by construction".

What *is* exposed is a narrower and enumerable class: the **binding tests** that
keep the exported artifacts honest, where a vacuous pass ships a wrong
specification to siblings with nothing noticing. In this checkout that class is
`test/predicator/isa_sync_test.exs` plus
`test/predicator/conformance/{corpus_freshness,opcode_coverage,function_coverage,schema_validation,ratchet_registry,package_boundary}_test.exs`.

The repo is **already doing this ad hoc**, three times, each with a hand-written
comment explaining the guard:

- `test/predicator/isa_sync_test.exs:29-30` - `@opcode_count 27`, with the
  comment "vacuously - by asserting this literal count rather than only
  'non-empty'".
- `test/predicator/conformance/package_boundary_test.exs:31-32` - "assertion
  below vacuous", `assert length(@shipped_lib_files) > 10`.
- `test/predicator/conformance/ratchet_registry_test.exs:47` - "the test below
  would pass vacuously".

### Statifier's practice, as written

`statifier-ex/docs/testing.md:78-134` and `statifier-ex/CLAUDE.md:125-129`:
every new or changed test asserting `lib/` behavior is sabotaged (break the
code, confirm red, revert) and carries a one-line
`# sabotage: <what was broken> -> red` note above the `test` line; harness
plumbing states an exemption rather than omitting the line
(`# sabotage: n/a - ...`). Generated corpus files are exempt. The doc names the
cost plainly: "This makes writing a test meaningfully slower, and that is the
trade being made deliberately."

### Constraints

- **No ratchet mechanics land here.** px-35i.8 shipped `conformance/RATCHET.md`,
  `conformance/schema/registry.json`, and
  `conformance/examples/registry.example.json` - a *format specification* plus
  one worked example bound by a test. The registries themselves, the runner, and
  the ratchet step live in the sibling repos, and `conformance/RATCHET.md`
  already states "There is no `mix conformance.ratchet`: the ratchet runs where
  the implementation is, and that is never here." Nothing in this bead may add
  one.
- **This bead touches no Elixir.** Its diff is `.claude/**`, `CLAUDE.md`, and
  `docs/`, so the Step 0 carve-out applies to its *own* commits and there is no
  gate to run - which must be said in the commit report rather than left to look
  like a green gate.
- **House style**: `CLAUDE.md` and every file under `.claude/skills/` use plain
  hyphens, no em dashes. Match that.

## Desired End State

1. `.claude/skills/commit/SKILL.md` treats a conformance-corpus diff as a change
   the commit message must explain, states that the generated corpus is never
   hand-edited, and no longer skips the gate on a corpus-only diff.
2. `.claude/skills/merge-request/SKILL.md` does the same for the PR body, with
   the matching carve-out narrowing.
3. `.claude/skills/implement-plan/SKILL.md` tells an implementing agent that a
   red `corpus_freshness_test.exs` is fixed by `mix corpus.generate`, never by
   editing the generated file.
4. `CLAUDE.md` states the authored-vs-generated rule once, as the authority the
   skills defer to.
5. The sabotage-note question is **decided, in writing**, with its reasoning and
   its cost, in `docs/research/260808-px-9ab-sabotage-notes.md`, and the decision
   is enforced in `CLAUDE.md` if adopted.
6. No ratchet registry, no ratchet mix task, and no ratchet step exists anywhere
   in this repo's workflow.

Verification that the end state holds:

- `grep -ri "ratchet" .claude/ CLAUDE.md` returns only references *pointing at*
  `conformance/RATCHET.md` as a sibling-repo artifact, never a step to run here.
- A dry read of `/commit` against a hypothetical corpus-only diff produces a
  message naming what moved and why, and does **not** skip `mix quality`.
- `docs/research/260808-px-9ab-sabotage-notes.md` states a decision in its first
  ten lines, not a survey of options.

### Key Discoveries

- `CLAUDE.md`, "Area labels" - `area:conformance` already exists (px-phw); the
  first acceptance clause is closed.
- `.claude/skills/commit/SKILL.md:84-92` - the carve-out that lets a corpus-only
  diff skip the gate.
- `.claude/skills/merge-request/SKILL.md:131-134` - the same carve-out,
  explicitly written to match `/commit`.
- `.claude/skills/commit/SKILL.md:100-107` - Step 1's "Analyze Changes" bullet
  list, the natural home for corpus detection.
- `.claude/skills/merge-request/SKILL.md:206-215` - the PR body's Why/What/Notes
  bullets, the natural home for the PR-side item.
- `test/predicator/conformance/corpus_freshness_test.exs:28` - the exact stale
  message the skills should quote so an agent recognises it.
- `conformance/README.md`, "How to add a case, without any Elixir" - why the
  rule is authored-vs-generated and not "do not touch `conformance/`".
- `docs/plans/260807-px-35i.4-conformance-corpus.md`, "Implementation Approach"
  - the mechanism decision that removes the suite from the corpus's source path,
  and with it most of the sabotage-note premise.
- `statifier-ex/docs/testing.md:119-121` - statifier exempts its own generated
  corpus from sabotage notes for the same construction argument.

## What We're NOT Doing

- **Not re-deciding or restating the area label.** px-phw closed it.
- **Not adding a gate step.** No new `mix` invocation, no
  `mix corpus.generate --check` bolted onto `/commit` or `/merge-request`. The
  suite already covers staleness; the additions here are things to *explain*.
  The one gate-adjacent change is *narrowing an existing skip*, which adds no
  step.
- **Not adding a ratchet registry, a ratchet mix task, or a ratchet step.**
  px-35i.8 put those in the sibling repos deliberately.
- **Not adopting statifier's full sabotage practice** (every test asserting
  `lib/` behavior). See Phase 3 for the scope actually adopted and why the broad
  form is rejected.
- **Not retrofitting sabotage notes onto the seven existing binding tests in
  this bead.** That is `area:conformance` + `area:evaluator` work and would
  blow px-9ab's predicted blast radius; it becomes a follow-on bead.
- **Not touching `conformance/**`, `lib/`, `test/`, or `mix.exs`.** This bead's
  labels predict `.claude/**` and `CLAUDE.md`, plus `docs/` for the research
  note, and the diff should match that prediction.
- **No ISA change**, so this plan carries no `## ISA Impact` section.

## Implementation Approach

Three phases, each independently committable, in descending order of how
load-bearing they are. The bead's two mandatory skill clauses land first
(Phase 1), the guardrail against the failure mode they describe lands second
(Phase 2), and the decision the bead escalates lands third (Phase 3) so it can
be overturned without unpicking anything else.

There is no Elixir in any phase, so each phase's gate is the Step 0 carve-out -
a diff review - and every phase must say so in its commit report rather than
implying a green gate.

The prose to add is short and normative, matching the register of the documents
it lands in: skills state a rule and the reason in the same breath, and neither
skill restates what `conformance/README.md` already says.

---

## Phase 1: `/commit` and `/merge-request` learn the corpus

### Overview

The bead's two mandatory clauses, plus the carve-out hole that would otherwise
make the premise behind them false.

### Changes Required:

#### 1. The generated-corpus rule, stated once per skill

**File**: `.claude/skills/commit/SKILL.md`, in "Important Context" (after the
`CHANGELOG.md` bullet at line 52-54)

Add a bullet on the authored/generated split, drawing the line at the right
place:

```markdown
- `conformance/corpus/*.json` and `conformance/manifest.json` are **generated
  output**, written only by `mix corpus.generate`. They are never hand-edited -
  not to fix a failing test, not to tidy a diff. The authored source is
  `conformance/cases/*.json`, which *is* hand-edited; that is how a case is
  added (`conformance/README.md`). A regenerated corpus is committed alongside
  the change that moved it, in the same commit.
```

**File**: `.claude/skills/merge-request/SKILL.md`, in "Guidelines"

The same rule in one sentence, pointing at `/commit` rather than repeating it -
`/merge-request` already defers to `/commit` for the carve-out and for
attribution, and a second full statement is how two documents start disagreeing.

#### 2. An unexplained corpus diff is a change to explain

**File**: `.claude/skills/commit/SKILL.md`, Step 1 "Analyze Changes"
(lines 100-107)

Add a fourth analysis bullet beside "Whether the ISA moved":

```markdown
   - Whether `conformance/corpus/*.json` or `conformance/manifest.json` moved,
     and **why**. A corpus diff is a change in what the reference implementation
     computes - it is the exported specification siblings verify against
     (ADR-0003) - so it is never incidental. Name the cause in the message: the
     authored case that was added, or the evaluator/compiler change whose
     semantics moved and the case ids that moved with it. A corpus diff nobody
     can explain from the message is a semantic change nobody meant to make, and
     it should stop the commit until it is understood.
```

Then, in Step 2's style rules (beside the `Refs:` rules), one line making it a
message requirement rather than only an analysis step:

```markdown
- **A corpus diff is named in the body**, with its cause. See Step 1.
```

**File**: `.claude/skills/merge-request/SKILL.md`, step 7's PR body bullets
(lines 206-215)

Add a bullet after **Notes**:

```markdown
   - **Corpus** - if `conformance/corpus/*.json` or `conformance/manifest.json`
     moved, say why in the body, naming the cause and the case ids that moved.
     The corpus is the exported specification siblings verify against
     (ADR-0003), so a corpus diff a reviewer cannot account for from the PR body
     is the single most reviewable form of an unintended semantic change - and
     the reviewer is the only one positioned to catch it, because the suite
     confirms the corpus is *fresh*, never that the change was *wanted*.
```

That last clause is the point worth making explicitly in both skills: the
freshness test proves the corpus matches the code, and says nothing about
whether the code should have changed. The gate cannot answer that question,
which is exactly why this is a message and PR-body item rather than a gate step.

#### 3. Close the carve-out hole

**File**: `.claude/skills/commit/SKILL.md`, Step 0 (lines 84-92)

Amend the carve-out's condition and add one sentence of reasoning:

```markdown
**Carve-out: a change touching no Elixir code has no gate to run.** If
`git diff main...HEAD --name-only` (plus unstaged files) touches nothing under
`lib/`, `test/`, `src/`, or `conformance/`, and neither `mix.exs` nor
`mix.lock`, the gate has nothing to measure - skills, docs, ADRs, and beads
exports cannot break a build. Skip `mix quality` and review the diff instead.

`conformance/` is in that list because a change to `conformance/cases/*.json`
and its regenerated output touches no Elixir file at all, so the unamended
carve-out would skip the one test that checks it -
`test/predicator/conformance/corpus_freshness_test.exs`. This is not a new gate
step; it stops an existing skip from covering the case the gate exists for.
```

**File**: `.claude/skills/merge-request/SKILL.md`, step 4's carve-out
(lines 131-134)

Make the identical change, keeping the "matching `/commit` Step 0" phrasing so
the two stay bound.

#### 4. Recognising the failure

**File**: `.claude/skills/commit/SKILL.md`, "Failure Recovery", under "If
Quality Checks Fail"

One short paragraph so an agent meeting the message knows the fix is a
regeneration and not an edit:

```markdown
### If the corpus is stale

`conformance/ is stale - run \`mix corpus.generate\` and review the diff:`
means the checked-in corpus no longer matches what the current code produces.
Run `mix corpus.generate`, then **read the diff before staging it** - it says,
case by case, what the change did to the exported specification. Never edit a
file under `conformance/corpus/` or `conformance/manifest.json` to make this
green; that hides the finding instead of recording it.
```

### Success Criteria:

#### Automated Verification:
- [x] `git diff main...HEAD --name-only` shows only `.claude/skills/commit/SKILL.md`
      and `.claude/skills/merge-request/SKILL.md`, so the Step 0 carve-out
      genuinely applies to this phase's own commit
- [x] No Elixir file is touched, so there is no gate to run - the commit report
      says "docs only, no quality gate applicable" rather than implying green
- [x] `grep -n "conformance" .claude/skills/commit/SKILL.md
      .claude/skills/merge-request/SKILL.md` shows the carve-out list, the
      analysis/body item, and the never-hand-edited rule in both files
- [x] `grep -c "ratchet" .claude/skills/commit/SKILL.md
      .claude/skills/merge-request/SKILL.md` returns 0 in both

#### Manual Verification:
- [ ] Read Step 0's amended carve-out cold: is it obvious that adding
      `conformance/` narrows a skip rather than adding a check?
- [ ] The two skills' statements of the never-hand-edited rule do not
      contradict `conformance/README.md`'s "How to add a case" - a contributor
      editing `conformance/cases/*.json` is doing the right thing
- [ ] The PR-body bullet reads as something a reviewer wants, not as boilerplate
      an author will paste an empty version of
- [ ] Nothing added reads as a new gate step

**Implementation Note**: This phase touches no Elixir, so `mix quality` has
nothing to measure and the Step 0 carve-out applies; review the diff instead.
In looped (`--loop`) execution the Automated Verification items above gate
advancement and the Manual items are deferred to the end.

---

## Phase 2: `CLAUDE.md` and `/implement-plan` carry the guardrail

### Overview

Put the authored-vs-generated rule where it is authoritative rather than only
where it is used, and close the one place an agent is actively tempted to
hand-edit generated output: an implementing agent staring at a red
`corpus_freshness_test.exs` mid-phase.

### Changes Required:

#### 1. State the rule in the authority document

**File**: `CLAUDE.md`, "## Conventions"

One bullet, in the existing register:

```markdown
- `conformance/corpus/*.json` and `conformance/manifest.json` are generated by
  `mix corpus.generate` and are never hand-edited; the authored source is
  `conformance/cases/*.json`. They are the exported specification the siblings
  verify against (ADR-0003), so a corpus diff is a semantic change and gets
  explained in the commit message and the PR body -
  `test/predicator/conformance/corpus_freshness_test.exs` proves the corpus is
  fresh, never that the change was intended.
```

Placed under Conventions rather than in the `area:conformance` prose, which is
about label algebra and should not grow a second subject.

#### 2. `/implement-plan` meets a red freshness test

**File**: `.claude/skills/implement-plan/SKILL.md`, in "If You Get Stuck" (or
"Verification Approach", whichever the surrounding structure fits better on
reading)

```markdown
### A red `corpus_freshness_test.exs`

The message `conformance/ is stale - run \`mix corpus.generate\` and review the
diff:` names the case ids whose exported behavior moved. The fix is always
`mix corpus.generate` plus a read of the resulting diff; it is never an edit to
a file under `conformance/corpus/` or to `conformance/manifest.json`, which are
generated output (CLAUDE.md, Conventions).

If the diff surprises you - cases moved that the plan's phase did not intend to
touch - that is a finding, not a chore. Stop and report it. A regeneration
committed without reading it is how an unintended semantic change reaches the
siblings looking like housekeeping.
```

### Success Criteria:

#### Automated Verification:
- [x] The diff touches only `CLAUDE.md` and
      `.claude/skills/implement-plan/SKILL.md`
- [x] `grep -n "corpus.generate" CLAUDE.md .claude/skills/implement-plan/SKILL.md`
      shows the rule in both
- [x] No Elixir file touched; Step 0 carve-out applies and is stated in the
      report

#### Manual Verification:
- [ ] The CLAUDE.md bullet reads in the register of its neighbours and does not
      duplicate the `area:conformance` prose
- [ ] `/implement-plan`'s addition would actually be read at the moment it is
      needed - it sits where a stuck agent looks, not in an introduction

---

## Phase 3: The sabotage-note decision

### Overview

Decide the bead's escalated question explicitly, record the reasoning and the
cost, and enforce the decision.

### The decision

**Adopt, narrowly: sabotage notes are required on the binding tests that keep
this repo's exported artifacts honest, and on nothing else. Statifier's broad
form - every test asserting `lib/` behavior - is rejected for this repo.**

The reasoning, in descending weight:

1. **The premise moved, and what is left is narrow and enumerable.** The bead's
   argument is that suite tests became the source of an exported specification.
   px-35i.4 chose a different mechanism: the corpus's source is authored JSON in
   `conformance/cases/*.json`, completed by the real compiler and evaluator, and
   an authored `expected` that disagrees fails generation loudly. A vacuous
   ExUnit test therefore ships nothing to siblings. What *can* ship a wrong
   specification is a **vacuous binding test** - one that claims to bind a
   generated artifact to its source and in fact asserts nothing. That class is
   seven files, not the whole suite.

2. **The repo already does this, three times, without a name for it.**
   `isa_sync_test.exs:29-30` guards with a literal `@opcode_count 27` and a
   comment saying why; `package_boundary_test.exs:31-32` and
   `ratchet_registry_test.exs:47` each carry a hand-written anti-vacuity guard
   and a comment. Codifying a practice already followed ad hoc costs almost
   nothing and stops the next binding test from being the one that forgets.

3. **Statifier's own doc supports the narrowing.** `statifier-ex/docs/testing.md:119-121`
   exempts its generated corpus because "the corpus is sabotage-proof by
   construction, since a broken interpreter shows up as a failing conformance
   test immediately". The same construction argument holds here, one level up:
   the corpus is regenerated from the real pipeline and byte-compared, so it
   cannot silently disagree with the code. It is the *bindings* that can.

4. **The broad form's cost is not payable here and buys less.** Predicator's
   suite is large and predominantly pure-function assertions over a lexer,
   parser, compiler, and evaluator - a domain where a vacuous test is both less
   likely and less consequential, because a wrong answer surfaces as a wrong
   answer rather than as a silent gap. Statifier names the cost plainly
   ("meaningfully slower"), and it is paying it for an interpreter whose
   correctness is judged largely by conformance corpora. Applying it to every
   new test here would tax hundreds of low-risk tests to protect seven
   high-risk ones.

**The cost of the decision as taken**, named rather than buried:

- Every new test in the binding class costs a real mutation, a confirmed red, a
  revert, and a one-line note. That is a few minutes each, a handful of times a
  year.
- The class boundary needs judgement at the margin, and a boundary judged
  wrongly is worse than no boundary because it looks like coverage. The
  mitigation is that the class is defined by an enumerated list of files in
  CLAUDE.md, not by a description, so extending it is a visible edit.
- Seven existing binding tests will not carry notes until the follow-on bead
  lands, so for that window the practice is stated but not fully evidenced.

**What would overturn it:** a vacuous non-binding test that ships a wrong
answer to a sibling would argue for widening; a binding test whose sabotage note
is unwritable because no single reasonable mutation reddens it would argue the
test is the wrong shape, not the rule.

### Changes Required:

#### 1. Record the decision

**File**: `docs/research/260808-px-9ab-sabotage-notes.md` (new)

Following `docs/research/260807-px-phw-conformance-area-label.md`'s shape - the
decision in the first lines, then the question, then ground truth with
`file:line` references, then the decision and its cost. Carry the four reasons
above, the three existing ad-hoc guards as evidence, statifier's exemption, and
the named cost. State explicitly that this is workflow governance, not
architecture: it moves no opcode and is not ADR-shaped, the same call px-phw
made.

#### 2. Enforce it

**File**: `CLAUDE.md`, "## Conventions"

```markdown
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
```

The file list is enumerated on purpose: it makes widening the class a visible
edit rather than a matter of taste.

#### 3. File the retrofit as its own bead

**Not a file change.** The seven named tests do not carry notes yet, and adding
them means editing `test/predicator/conformance/**` and
`test/predicator/isa_sync_test.exs` - `area:conformance` plus `area:evaluator`,
outside px-9ab's predicted blast radius and outside its labels. Under CLAUDE.md
that mismatch is "worth noticing at merge time, not silently accepting", so it
is a follow-on:

```bash
bd create "Sabotages the seven binding tests" \
  --type task --priority 3 \
  --label area:conformance --label area:evaluator \
  --description "Retrofit sabotage notes onto the binding tests CLAUDE.md now requires them on (px-9ab, docs/research/260808-px-9ab-sabotage-notes.md): test/predicator/isa_sync_test.exs and test/predicator/conformance/{corpus_freshness,opcode_coverage,function_coverage,schema_validation,ratchet_registry,package_boundary}_test.exs. For each: break what it covers with one plausible mutation, confirm it goes red for the right reason, revert, and record the mutation in a one-line '# sabotage: ... -> red' comment. A test that stays green under every plausible mutation is a finding, not a note to skip."
```

Then link it: `bd dep add <new-id> px-9ab`.

### Success Criteria:

#### Automated Verification:
- [x] `docs/research/260808-px-9ab-sabotage-notes.md` exists and states a
      decision, not a survey
- [x] `grep -n "sabotage" CLAUDE.md` shows the convention bullet with the
      enumerated file list
- [x] The follow-on bead exists, carries `area:conformance` and
      `area:evaluator`, and depends on px-9ab
- [x] The diff touches only `CLAUDE.md` and `docs/research/`; no test file is
      edited in this bead
- [x] `grep -rn "ratchet" CLAUDE.md .claude/` shows no ratchet *step* - only
      references to `conformance/RATCHET.md` as a sibling-repo artifact, if any

#### Manual Verification:
- [ ] The research note's cost section is honest enough that a reader who
      disagrees can act on it - the decision is overturnable from the note alone
- [ ] The CLAUDE.md bullet cannot be read as requiring notes on ordinary tests
- [ ] The enumerated file list matches what is on disk today

---

## Testing Strategy

This bead changes no Elixir, so there are no unit or integration tests to add
and no coverage to move. The equivalent verification is threefold:

### Structural checks
- `grep` assertions in each phase's Automated Verification, confirming each
  required statement landed in each required file and that no ratchet step
  appeared anywhere.
- Confirm the diff matches the bead's predicted blast radius (`.claude/**`,
  `CLAUDE.md`, `docs/research/`). A file outside it means the label prediction
  was wrong and that is worth naming at merge time (CLAUDE.md).

### Dry-run readings
1. Read `/commit` end to end as if handed a diff that adds one authored case and
   its regenerated corpus output. Confirm: the gate runs (carve-out no longer
   fires), the message names the corpus movement and its cause, and nothing
   suggests hand-editing the generated file.
2. Read `/commit` again as if handed a diff that changes an evaluator clause and
   the corpus that moved with it. Confirm the message requirement produces the
   case ids, not just "regenerated corpus".
3. Read `/merge-request` as a reviewer receiving a PR whose body has the corpus
   bullet. Confirm it says something a reviewer can act on.
4. Read `/implement-plan`'s new section as an agent mid-phase with a red
   freshness test. Confirm the next action is unambiguous.

### Negative checks
- Confirm nothing added contradicts `conformance/README.md`'s contributor flow,
  which depends on `conformance/cases/*.json` being hand-edited.
- Confirm no phase adds a `mix` invocation to any skill's gate sequence.

## References

- Beads issue: `px-9ab` (`area:docs`, `area:skills`, `workflow`); depends on
  closed `px-35i.4`; related epic `px-35i`
- `CLAUDE.md` - the area-label table (`area:conformance`, added by px-phw), the
  authority table, and the Conventions section this plan extends
- `docs/research/260807-px-phw-conformance-area-label.md` - the label decision
  that closes this bead's first acceptance clause, and the model this plan's
  research note follows
- `docs/plans/260807-px-35i.4-conformance-corpus.md` - the corpus mechanism:
  authored JSON completed by the real pipeline, and why the suite is not the
  source
- `docs/plans/260807-px-35i.8-sibling-conformance-ratchet.md` - why no ratchet
  mechanics land here
- `docs/adr/0003-the-elixir-implementation-leads-the-isa.md` - the corpus is the
  executable form of `docs/isa.md`; siblings adopt on a boundary of their own
  choosing
- `conformance/README.md` - the runner contract and "How to add a case, without
  any Elixir", which the never-hand-edited rule must not contradict
- `conformance/RATCHET.md` - the sibling-repo artifact; "the ratchet runs where
  the implementation is, and that is never here"
- `lib/mix/tasks/corpus.generate.ex` - the only writer of
  `conformance/corpus/*.json` and `conformance/manifest.json`; `--check` is the
  write-nothing drift check
- `test/predicator/conformance/corpus_freshness_test.exs:28` - the stale-corpus
  message the skills quote
- `test/predicator/isa_sync_test.exs:29-30`,
  `test/predicator/conformance/package_boundary_test.exs:31-32`,
  `test/predicator/conformance/ratchet_registry_test.exs:47` - the three
  existing ad-hoc anti-vacuity guards the Phase 3 decision codifies
- `.claude/skills/commit/SKILL.md:84-92,100-107` - the carve-out and the analysis
  step Phase 1 amends
- `.claude/skills/merge-request/SKILL.md:131-134,206-215` - the matching
  carve-out and the PR body bullets
- statifier-ex `docs/testing.md:78-134` and `CLAUDE.md:125-129` - the sabotage
  practice as written, including its generated-corpus exemption and its stated
  cost

## Deferred Manual Verification

Walked with the user on 2026-08-08. Two items failed and were fixed in a
follow-up commit on this branch; the wording below records what was found.

### Phase 1

- [x] Read Step 0's amended carve-out cold: is it obvious that adding
      `conformance/` narrows a skip rather than adding a check?
      **Yes** - the paragraph says so in place. Also confirmed there is no
      third copy of the carve-out path list to leave stale: `/release` only
      references the carve-out, it does not restate it.
- [x] The two skills' statements of the never-hand-edited rule do not
      contradict `conformance/README.md`'s "How to add a case" - a contributor
      editing `conformance/cases/*.json` is doing the right thing
      **They reconcile explicitly.** `conformance/README.md:213` is "How to add
      a case, without any Elixir" -> edit `conformance/cases/*.json`, and
      `/commit` names that file as authored and hand-edited by design.
- [x] The PR-body bullet reads as something a reviewer wants, not as boilerplate
      an author will paste an empty version of
      **Yes** - it is conditional on the corpus actually having moved, so there
      is no empty form to paste, and it asks for cause plus case ids.
- [x] Nothing added reads as a new gate step
      **Failed, then fixed.** `/commit` Step 1 ended "it should stop the commit
      until it is understood", which sits close enough to the real gate
      discussion to be read as a stop condition. Reworded as an authoring
      instruction that says outright there is no check to add.

### Phase 2

- [x] The CLAUDE.md bullet reads in the register of its neighbours and does not
      duplicate the `area:conformance` prose
      **Duplication: no** - `area:conformance` is about file collision, these
      are about authored-vs-generated. **Register: failed, then fixed.** The two
      bullets ran 7 and 11 lines against neighbours of 2-3, with bold lead-ins
      and an inline seven-file path glob. Both cut to 4 lines; the file list and
      the note format moved into the research note CLAUDE.md already cites.
- [x] `/implement-plan`'s addition would actually be read at the moment it is
      needed - it sits where a stuck agent looks, not in an introduction
      **Yes** - it is a subsection of the troubleshooting block and leads with
      the literal failure string.

### Phase 3

- [x] The research note's cost section is honest enough that a reader who
      disagrees can act on it - the decision is overturnable from the note alone
      **Yes** - three named costs including the unflattering one (the seven
      existing tests carry no notes until px-suw lands), plus a "What would
      overturn it" section with two concrete triggers.
- [x] The CLAUDE.md bullet cannot be read as requiring notes on ordinary tests
      **Correct** - "Ordinary tests need no note" is stated in the bullet.
- [x] The enumerated file list matches what is on disk today
      **All seven exist.** The five conformance tests *not* on the list
      (`coverage`, `features`, `generator`, `json`, `values`) are unit tests of
      generator internals, correctly excluded. `json_test.exs` and
      `values_test.exs` are the closest call, since they cover the canonical
      encoding the corpus is written in; left out deliberately, and this is the
      margin the research note warns needs judgement.
