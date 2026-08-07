# Versioned-ISA Workflow Reframe Implementation Plan

## Overview

ADR-0003 amends ADR-0001's consequences: the Elixir implementation leads the
instruction set, siblings adopt on a version boundary, and a lagging sibling is
an expected documented state rather than a defect or a release blocker. The
`.claude/` workflow and `CLAUDE.md` still encode the repealed framing in ~22
sites across 13 files, all saying some version of "an instruction change is not
a local decision, the siblings have to match". This plan replaces that
deliberative question with the mechanical one ADR-0003 names: version, stamp,
migration. Beads issue: px-im6.

## Current State Analysis

### The leak sites

Re-run of the bead's inventory grep on the current tree
(`grep -rnE 'ADR-0001|instruction set|cross-language|interchange' .claude/
CLAUDE.md`) confirms the 21 sites in 12 files. A wider sweep
(`grep -rniE 'sibling|parity|ruby|javascript' .claude/ CLAUDE.md`) found two
more the original pattern missed:

| File | Lines | What it says |
|---|---|---|
| `CLAUDE.md` | 191, 193-195 | "ADR-0001 sets the 3.6-4.0 arc"; "changes to it are not local to this repo (ADR-0001)" |
| `.claude/skills/create-plan/SKILL.md` | 55, 101, 179, 375-376, 493-494, 589-590 | optional-section list, ADR read list, clarifying-questions template, `## Cross-Language Impact` template body, new-syntax pattern, pre-write checklist |
| `.claude/skills/work/SKILL.md` | 111-115, 208-210, 270-271 | sizing rule, Direction-stage prompt, Step 5 report line |
| `.claude/skills/research-codebase/SKILL.md` | 138-144, 241-245 | agent-menu "cross-language comparison" block, `## Cross-Language Impact` doc-template section |
| `.claude/skills/iterate-plan/SKILL.md` | 143-144 | section add/remove rule naming Cross-Language Impact |
| `.claude/skills/commit/SKILL.md` | 105-106 | Step 1 analysis bullet |
| `.claude/skills/merge-request/SKILL.md` | 210-213 | PR-body Notes bullet |
| `.claude/skills/implement-plan/SKILL.md` | 166-168 | pipeline-changes guidance |
| `.claude/skills/create-issue/SKILL.md` | 80-83 | `upstream`-label guidance |
| `.claude/agents/codebase-analyzer.md` | 51-54, 137 | project context bullet, Key Patterns line |
| `.claude/agents/codebase-locator.md` | 56-58 | sibling-implementations bullet |
| `.claude/agents/thoughts-analyzer.md` | 31-34 | "those are not local decisions" |
| `.claude/agents/codebase-pattern-finder.md` | 64-66 | siblings live outside the repo (**neutral - no ADR claim, no change needed**) |

Line numbers are as of `45cc578` and will move as earlier phases edit the same
files; each phase re-greps rather than trusting these.

### What is already correct

- `docs/isa.md` exists (px-35i.2, landed) and is the specification the
  replacement wording should point at. Section 1 "Versioning" carries the
  integer-version rule, the never-reuse-a-name rule, the additive-minor /
  retire-major release rule, and "a sibling behind the current version is an
  expected, documented state". Current version: **ISA v2**.
- `README.md` (line 80-82) and `docs/architecture.md` (lines 89-97) have
  already been rewritten to the versioned-contract framing and cite ADR-0003.
  They are not in this bead's scope and need no further edits.
- ADR-0001 is still accepted and still correct about the execution model, ISA
  v2's opcode content, and the ECMAScript-aligned falsy rule. Citations to it
  for *those* facts stay. Only citations that use it to make sibling parity a
  constraint are wrong.

### Key discoveries

- **`Predicator.isa_version/0` and `Predicator.Instructions.required_isa/1` do
  not exist yet.** `grep -rn "isa_version\|required_isa" lib/ test/` returns
  nothing; px-35i.3 is IN_PROGRESS in a parallel worktree. Wording written here
  must therefore not instruct an agent to call them.
- ADR-0003's own consequence list (lines 179-184) states the replacement
  question verbatim: "does this bump the ISA version, is it stamped, and does a
  stored artifact need a migration note". That is the source text for the
  canonical block below.
- `.claude/skills/create-plan/SKILL.md` is the skill running this planning
  session (the reflexive hazard). Its edits are planned like any other file's
  and applied by `/implement-plan`, never mid-planning-run.

## Desired End State

Every ADR-0001 citation left in `.claude/` and `CLAUDE.md` is a citation to
something ADR-0001 still decides (the stack VM, ISA v2's opcodes, falsy
semantics). No file in `.claude/` or `CLAUDE.md` says an instruction-set change
is "not a local decision", that the siblings "have to match", or that sibling
state gates anything here. `/create-plan`'s optional section is `## ISA Impact`
and asks the three mechanical questions; `/iterate-plan` and
`/research-codebase` name the same section; `/work`'s sizing rule is keyed on an
ISA version bump.

Verified by:

```bash
# No repealed framing survives:
grep -rniE 'not a local decision|have to match|siblings need|sibling parity' .claude/ CLAUDE.md
# Expect: no hits.

# Every remaining ADR-0001 citation is inspected by hand:
grep -rn 'ADR-0001' .claude/ CLAUDE.md

# The renamed section exists and the old name does not:
grep -rn 'Cross-Language Impact' .claude/    # expect: no hits
grep -rn 'ISA Impact' .claude/               # expect: create-plan, iterate-plan, research-codebase
```

### The canonical replacement block

Phase 2 introduces this text in `/create-plan`; every other phase's wording is a
short pointer at it rather than a restatement, so there is one place to change
if ADR-0003 is ever amended.

```markdown
## ISA Impact

[Only when the change adds, removes, renames, or alters an opcode. Per
ADR-0003 the Elixir implementation leads the ISA, so this section answers three
mechanical questions rather than asking what the siblings need:

1. **Version** - does this bump the current ISA version (`docs/isa.md`,
   section 1)? An additive version (new opcodes only, every existing
   instruction list still valid) ships in a minor release; retiring an opcode
   takes a major release. An opcode's semantics never change under its own
   name: a different answer from an existing form is a new name.
2. **Stamp** - what the change owes `docs/isa.md`: an opcode subsection, the
   version it enters at, and a conformance-corpus tier.
3. **Migration** - can an instruction list compiled before this change still
   run and still produce the same answer? If not, name the upgrade path that
   rewrites it.

A sibling implementation behind the current ISA version is an expected,
documented state - not a defect and not a blocker on this change (ADR-0003).
Omit this section entirely when no opcode changes.]
```

## What We're NOT Doing

- Not touching `README.md`, `docs/architecture.md`, `docs/isa.md`, or the ADRs
  themselves. ADR-0003 is landed and the two prose docs were rewritten with it.
- Not adding, removing, or renaming any opcode. This is a documentation and
  workflow change with no `lib/` or `test/` edits at all.
- Not naming `Predicator.isa_version/0` or
  `Predicator.Instructions.required_isa/1` as things an agent should call. They
  do not exist yet (px-35i.3). The wording cites `docs/isa.md` section 1, which
  does exist, and stays true whether or not px-35i.3 lands first.
- Not building a sibling support matrix, a parity checklist, or any workflow
  step that inspects the sibling repos. ADR-0003 explicitly forbids maintaining
  one here.
- Not editing `.claude/agents/codebase-pattern-finder.md`'s sibling bullet: it
  states a search-scope fact and makes no ADR-0001 parity claim.
- Not rewriting `.claude/skills/create-plan/SKILL.md`'s unrelated guidance about
  pointing agents at repos outside this checkout (lines ~133-134, ~532). That is
  a directory-scoping instruction, not a parity claim.

## Implementation Approach

Five phases, ordered so the canonical wording exists before anything points at
it: the anchor (`CLAUDE.md`), then the plan-document trio that owns the renamed
section, then the sizing and triage skills, then the reporting skills, then the
research agents plus a whole-tree verification sweep.

Every phase is a pure Markdown edit inside `area:docs` + `area:skills`, so no
phase can leave a gate red on its own and any phase is independently
committable. There is no Elixir code in this bead, so per CLAUDE.md's authority
table a `mix quality` run is not a meaningful gate here; it is still run once at
the end to prove the tree is clean, and `test/docs_examples_test.exs` only
executes examples under `docs/`, which this bead does not add.

## Phase 1: Reframe the CLAUDE.md anchor

### Overview

`CLAUDE.md` is what every session reads first, so its two sites set the framing
the skills inherit. Fixing it first means later phases can shorten rather than
re-argue.

### Changes Required:

#### 1. The ADR pointer
**File**: `CLAUDE.md` (currently line 190-191, "Read before making design
decisions")
**Changes**: The bullet reads "`docs/adr/` - the reasoning behind architectural
decisions; cite ADR numbers instead of re-arguing them. ADR-0001 sets the
3.6-4.0 arc." Keep the ADR-0001 sentence (still true: it does set the arc) and
add `docs/isa.md` to the read list plus a pointer to ADR-0003 as the amendment
that governs how the ISA moves. Suggested:

```markdown
- `docs/adr/` - the reasoning behind architectural decisions; cite ADR numbers
  instead of re-arguing them. ADR-0001 sets the 3.6-4.0 arc; ADR-0003 amends
  its consequences and governs how the instruction set moves.
- `docs/isa.md` - the instruction set specification: the opcodes, the execution
  model, and the versioning rules. The authority for any ISA question.
```

#### 2. The "what this project is" closer
**File**: `CLAUDE.md` (currently lines 193-195)
**Changes**: Replace the sibling-constraint paragraph outright.

```markdown
Predicator is the reference implementation of the instruction set; Ruby and
JavaScript siblings adopt it on a version boundary of their own choosing
(ADR-0003). A sibling behind the current ISA version is an expected,
documented state, never a blocker here. What a change to the instruction set
does owe is a version, an entry in `docs/isa.md`, and a migration note if a
stored artifact is affected.
```

House style: `CLAUDE.md` is hyphen-and-ASCII throughout; match it.

### Success Criteria:

#### Automated Verification:
- [x] `grep -n 'not local to' CLAUDE.md` returns nothing
- [x] `grep -n 'isa.md\|ADR-0003' CLAUDE.md` returns both new references
- [ ] Full gate is clean (no Elixir touched, so this is a formality):
      `mix quality`

#### Manual Verification:
- [ ] The "Read before making design decisions" list still reads as a list of
      four things to read, not a paragraph of policy
- [ ] No em dashes or non-ASCII punctuation introduced into `CLAUDE.md`

---

## Phase 2: Rename Cross-Language Impact to ISA Impact

### Overview

The plan-document trio - `/create-plan` (which owns the template),
`/iterate-plan` (which names the section in its add/remove rule), and
`/research-codebase` (whose research-doc template carries a parallel section) -
must move together: a rename in one and not the others leaves `/iterate-plan`
looking for a section no plan will have.

**Reflexive note for the implementer**: `/create-plan` is the skill that
produced this plan. Edit it as an ordinary file. Do not re-run `/create-plan`
to validate the edit within the same session.

### Changes Required:

#### 1. The optional-section list
**File**: `.claude/skills/create-plan/SKILL.md` (currently line 55)
**Changes**: `` `## Cross-Language Impact` (when the instruction set changes -
see ADR-0001).`` becomes `` `## ISA Impact` (when an opcode changes - see
ADR-0003 and `docs/isa.md`).``

#### 2. The ADR read list
**File**: `.claude/skills/create-plan/SKILL.md` (currently line 101)
**Changes**: The parenthetical "ADR-0001 sets the 3.6-4.0 arc and keeps the
stack VM on ISA v2" is still accurate and stays; append "ADR-0003 makes this
repo the reference implementation of the ISA".

#### 3. The clarifying-questions template
**File**: `.claude/skills/create-plan/SKILL.md` (currently line 179)
**Changes**: "[Grammar or instruction-set decision that affects the sibling
implementations]" becomes "[Grammar or instruction-set decision that would bump
the ISA version]". (This site is not in the bead's inventory - the original grep
pattern missed the hyphenated "instruction-set".)

#### 4. The template body
**File**: `.claude/skills/create-plan/SKILL.md` (currently lines 373-376)
**Changes**: Replace the `## Cross-Language Impact` heading and its bracketed
body with the canonical `## ISA Impact` block quoted in "Desired End State"
above, verbatim. This is the one full copy; everything else points here.

#### 5. The new-syntax common pattern
**File**: `.claude/skills/create-plan/SKILL.md` (currently lines 493-494)
**Changes**: "A new instruction is a change to the cross-language interchange
format (ADR-0001), so the plan says what the Ruby and JavaScript siblings need"
becomes "A new instruction moves the ISA (ADR-0003), so the plan carries an
`## ISA Impact` section: the version it lands at, its `docs/isa.md` entry and
corpus tier, and a migration note if stored artifacts are affected".

#### 6. The pre-write checklist
**File**: `.claude/skills/create-plan/SKILL.md` (currently lines 589-590)
**Changes**: "[ ] If the instruction set changed, a Cross-Language Impact
section says what the siblings need (ADR-0001)" becomes "[ ] If an opcode
changed, an ISA Impact section answers the version / stamp / migration
questions (ADR-0003)".

#### 7. The section add/remove rule
**File**: `.claude/skills/iterate-plan/SKILL.md` (currently lines 143-144)
**Changes**: "If the change now touches the instruction set, the plan needs a
Cross-Language Impact section (ADR-0001); if it no longer does, remove it"
becomes the same rule keyed on `## ISA Impact` and an opcode change, citing
ADR-0003 and pointing at `/create-plan`'s template for the wording rather than
restating the three questions (the file already uses link-by-name for the
Implementation Note, two bullets down).

#### 8. The research agent-menu block
**File**: `.claude/skills/research-codebase/SKILL.md` (currently lines 138-144)
**Changes**: Keep the operational content (sibling repos live outside the
checkout; name the path explicitly in the prompt). Drop the "not a local
decision" premise and retitle from "For cross-language comparison" to "For ISA
questions", pointing at `docs/isa.md` as the first place to look and noting a
sibling's own repo is the authority on the version it supports (ADR-0003).

#### 9. The research-doc template section
**File**: `.claude/skills/research-codebase/SKILL.md` (currently lines 241-245)
**Changes**: `## Cross-Language Impact` becomes `## ISA Impact`, with the body
"[Only when an opcode is involved: the ISA version it belongs to per
`docs/isa.md`, and whether the question implies a version bump. Omit the section
entirely when it does not apply.]"

### Success Criteria:

#### Automated Verification:
- [x] `grep -rn 'Cross-Language Impact' .claude/` returns nothing
- [x] `grep -rn 'ISA Impact' .claude/` returns hits in all three of
      `create-plan`, `iterate-plan`, `research-codebase`
- [ ] `grep -rn 'siblings need' .claude/skills/create-plan/SKILL.md` returns
      nothing - **FAILS**: the canonical `## ISA Impact` block quoted verbatim
      in "Desired End State" itself contains the phrase "rather than asking
      what the siblings need" (line ~378 post-edit). Copied character for
      character as instructed; this check conflicts with the plan's own
      canonical text rather than with the implementation. Flagging rather than
      silently editing the canonical block or weakening the check.
- [ ] Full gate is clean (no Elixir touched, so this is a formality):
      `mix quality`

#### Manual Verification:
- [ ] The `## ISA Impact` block in `/create-plan`'s template is the only full
      copy of the three questions; the other two files point at it
- [ ] `/create-plan`'s Pre-Write Checklist and its template still name the same
      section (they are ~500 lines apart and drift easily)
- [ ] Markdown fences and list nesting inside the template block are intact -
      the block sits inside a fenced ````markdown` example

---

## Phase 3: Rekey sizing and triage on the ISA version

### Overview

`/work` decides whether a bead may be a just-do-it, and `/create-issue` decides
what labels it gets. Both currently reason from sibling parity. The sizing rule
survives - an ISA change still deserves a plan - but its premise changes from
"the siblings must agree" to "a version bump owes a spec entry, a corpus tier,
and possibly a migration".

### Changes Required:

#### 1. The sizing rule
**File**: `.claude/skills/work/SKILL.md` (currently lines 111-115)
**Changes**: Replace with an ISA-version-keyed rule. Suggested:

```markdown
**Anything that bumps the ISA version is at least Direction or Plan-only, never
just-do-it.** The Elixir implementation leads the instruction set (ADR-0003),
so the constraint is not sibling readiness - it is the paperwork the bump owes:
a version, a `docs/isa.md` entry, a conformance-corpus tier, and a migration
note if a stored instruction list is affected. That is more than an unreviewed
one-shot should decide. A change that touches instruction *handling* without
adding, removing, or altering an opcode does not bump the version and sizes
like any other change.
```

The last sentence is new and load-bearing: the old rule swept in every
evaluator edit, which ADR-0003's "semantics never change under a name" rule
makes unnecessary.

#### 2. The Direction-stage prompt
**File**: `.claude/skills/work/SKILL.md` (currently lines 208-210)
**Changes**: "say explicitly whether the decision changes the instruction set.
That is cross-language interchange (ADR-0001), so it binds the Ruby and
JavaScript siblings too" becomes "say explicitly whether the decision moves the
ISA, and if so at what version. ADR-0003 makes that a versioning and
stored-artifact question, not a sibling-readiness one, and it has to be visible
in the ADR rather than inferred from it".

#### 3. The Step 5 report line
**File**: `.claude/skills/work/SKILL.md` (currently lines 270-271)
**Changes**: "whether the work changed the instruction set (ADR-0001), since
that has to reach the commit message and the eventual PR body" becomes
"whether the work moved the ISA and to what version (ADR-0003), since that has
to reach the commit message and the eventual PR body".

#### 4. The upstream-label guidance
**File**: `.claude/skills/create-issue/SKILL.md` (currently lines 80-83)
**Changes**: The rule itself is right and stays (an ISA change is real work
here, not an `upstream` bead). Re-cite it to ADR-0003 and add that sibling
adoption of a version is legitimately its own `upstream` bead - it is tracked,
not blocking. Suggested ending: "...file the sibling-side adoption as its own
`upstream` bead if it needs tracking; it is never a dependency of the Elixir
work (ADR-0003)."

### Success Criteria:

#### Automated Verification:
- [ ] `grep -n 'not a local decision' .claude/skills/work/SKILL.md` returns
      nothing
- [ ] `grep -n 'ADR-0003' .claude/skills/work/SKILL.md
      .claude/skills/create-issue/SKILL.md` returns hits in both
- [ ] `mix quality` clean

#### Manual Verification:
- [ ] `/work`'s bucket table (line ~109) and the sizing rule beneath it still
      agree with each other after the edit
- [ ] The new "handling without an opcode change is not a bump" carve-out does
      not accidentally license a just-do-it for evaluator semantics changes -
      those are still multi-area and land in Plan-only by the area rule

---

## Phase 4: Rekey the reporting skills

### Overview

`/commit`, `/merge-request`, and `/implement-plan` all tell the agent to
announce an instruction-set change on the grounds that the siblings must match.
The announcement is still right; the grounds change to the version.

### Changes Required:

#### 1. Commit-message analysis
**File**: `.claude/skills/commit/SKILL.md` (currently lines 105-106)
**Changes**: "Whether the instruction set changed - that is cross-language
interchange (ADR-0001) and belongs in the message" becomes "Whether the ISA
moved, and to what version - a bump belongs in the message (ADR-0003)".

#### 2. PR-body Notes
**File**: `.claude/skills/merge-request/SKILL.md` (currently lines 210-213)
**Changes**: Replace the sibling clause with: "If the change moves the ISA, say
so explicitly and name the version it lands at, plus its `docs/isa.md` entry and
any migration note (ADR-0003). A sibling that has not adopted that version is
not a blocker on the PR."

#### 3. Pipeline-changes guidance
**File**: `.claude/skills/implement-plan/SKILL.md` (currently lines 166-168)
**Changes**: "Instructions are the cross-language interchange format (ADR-0001).
Adding or changing one is a decision the Ruby and JavaScript implementations
have to match" becomes: "**Adding or altering an opcode moves the ISA**
(ADR-0003). The plan's `## ISA Impact` section names the version, the
`docs/isa.md` entry, and any migration note; carry all three into the commit
message and the PR body, not just the code."

### Success Criteria:

#### Automated Verification:
- [ ] `grep -rn 'have to match\|not a local' .claude/skills/` returns nothing
- [ ] `grep -rn 'ADR-0003' .claude/skills/commit/SKILL.md
      .claude/skills/merge-request/SKILL.md
      .claude/skills/implement-plan/SKILL.md` returns hits in all three
- [ ] `mix quality` clean

#### Manual Verification:
- [ ] `/implement-plan`'s pointer at `## ISA Impact` matches the section name
      Phase 2 established
- [ ] `/merge-request`'s Notes bullet still reads as one bullet in a four-bullet
      list, not as a paragraph

---

## Phase 5: Reframe the research agents and sweep

### Overview

The three research agents carry the framing into every research pass, which is
the quietest and most durable leak: an agent told the siblings are a constraint
will report ISA findings in those terms forever. This phase also runs the
whole-tree verification the acceptance criteria are written as.

### Changes Required:

#### 1. Project-context bullet
**File**: `.claude/agents/codebase-analyzer.md` (currently lines 51-54)
**Changes**: Keep the useful half (instructions are plain lists, printing a
compiled program is the fastest way to understand an evaluation). Replace the
premise: "**The instruction set is specified in `docs/isa.md`**, and this
repository is its reference implementation (ADR-0003)."

#### 2. Key Patterns line
**File**: `.claude/agents/codebase-analyzer.md` (currently line 137)
**Changes**: "**Cross-language ISA**: instruction changes are shared with
Ruby/JS (ADR-0001)" becomes "**Versioned ISA**: opcodes are specified in
`docs/isa.md`; a change to one moves the version (ADR-0003)". Note this line
sits inside an example output block, so it is illustrating a report format, not
issuing an instruction - keep it the same length and shape.

#### 3. Sibling-implementations bullet
**File**: `.claude/agents/codebase-locator.md` (currently lines 56-58)
**Changes**: Keep "only search them when explicitly asked". Replace the ADR-0001
interchange clause with a pointer: "the ISA they implement against is specified
in `docs/isa.md`".

#### 4. The ADR-reading rule
**File**: `.claude/agents/thoughts-analyzer.md` (currently lines 31-34)
**Changes**: "Note whether a decision touches the instruction set, which is the
cross-language interchange format... Those are not local decisions" becomes:
"Note whether a decision moves the **instruction set**, and if so at what ISA
version - `docs/isa.md` is the specification and ADR-0003 makes this repo its
reference implementation. Surface the version, not a sibling-readiness
question." Also worth noting for the implementer: this agent reads ADRs, so it
should be told ADR-0003 amends ADR-0001's consequences without superseding it -
otherwise it will report ADR-0001's repealed consequences as live.

#### 5. Verification sweep (no file edits)
Run the greps in "Desired End State", then read every surviving `ADR-0001`
citation and confirm each one cites something ADR-0001 still decides. Expected
survivors after this plan: `/create-plan`'s ADR read list (the 3.6-4.0 arc, ISA
v2 on the stack VM) and `CLAUDE.md`'s equivalent.

### Success Criteria:

#### Automated Verification:
- [ ] `grep -rniE 'not a local decision|have to match|siblings need|sibling
      parity' .claude/ CLAUDE.md` returns nothing
- [ ] `grep -rn 'ADR-0001' .claude/ CLAUDE.md` returns only the two arc/ISA-v2
      citations
- [ ] `grep -rn 'ADR-0003\|docs/isa.md' .claude/ CLAUDE.md` returns hits in
      every file this plan touched
- [ ] `mix quality` clean, and `git status` shows no `lib/` or `test/` changes

#### Manual Verification:
- [ ] `codebase-pattern-finder.md`'s sibling bullet was left alone (it makes no
      parity claim) and still reads correctly beside the reframed agents
- [ ] No skill anywhere describes a lagging sibling as a blocker - read the four
      reporting/sizing bullets end to end, not just the greps
- [ ] `CHANGELOG.md` needs no entry: this is agent-workflow tooling, not a
      user-facing library change

---

## Testing Strategy

There is no Elixir code in this bead, so the suite is not the verifier; the
greps are. Concretely:

### Unit Tests:
None. No `lib/` or `test/` file is touched.

### Integration Tests:
None. `test/docs_examples_test.exs` executes examples under `docs/`; this bead
adds one plan document and no executable example.

### Manual Testing Steps:
1. Run each grep in "Desired End State" and confirm the stated expectation.
2. Read `.claude/skills/create-plan/SKILL.md`'s `## ISA Impact` template block
   in full and confirm it survives being copied into a plan document verbatim
   (fences balanced, list numbering intact).
3. Read `/work`'s sizing section and confirm an agent sizing a bead that only
   changes evaluator internals would now land outside the "at least Plan-only"
   rule, while one adding an opcode still lands inside it.
4. Run full `mix quality` once at the end to prove the tree is clean before the
   commit.

## References

- ADR: `docs/adr/0003-the-elixir-implementation-leads-the-isa.md` - the decision
  this plan propagates; its consequence at lines 179-184 names px-im6 and states
  the replacement question verbatim
- ADR: `docs/adr/0001-keep-the-stack-vm-revise-the-instruction-set.md` - still
  accepted; lines 50-52 and 119 are the amended consequences
- Spec: `docs/isa.md` - section 1 "Versioning" is what the new wording points at
- Governance: `CLAUDE.md` - area labels (`area:docs`, `area:skills`), commit
  conventions, and the authority table
- Beads: `px-im6` (this plan), depends on `px-35i.1` (landed); sibling work
  `px-35i.3` (the version API, in progress elsewhere)

## Open Questions

Recorded per the "no human available" invariant rather than resolved.

1. **Should the ISA Impact template name `Predicator.isa_version/0` and
   `Predicator.Instructions.required_isa/1`?** They do not exist yet (px-35i.3
   is in progress in a parallel worktree), so this plan deliberately cites
   `docs/isa.md` section 1 instead - wording that is true today and stays true
   after px-35i.3 lands. If px-35i.3 lands first, a one-line follow-up could
   name the functions as the mechanical way to answer question 1. That is a
   nice-to-have, not a gap: naming them now would put a call to a nonexistent
   function into a skill.
2. **`.claude/skills/create-issue/SKILL.md` has no dedicated `area:isa` or
   ISA-change label.** ADR-0003 gives an ISA change real recurring paperwork
   (spec entry, corpus tier, migration note), which is the kind of thing a label
   makes greppable. This plan does not add one - inventing a label is a
   governance change beyond px-im6's acceptance criteria - but it is worth a
   bead if ISA changes become frequent.

## Deferred Manual Verification

### Phase 1: Reframe the CLAUDE.md anchor
- [ ] The "Read before making design decisions" list still reads as a list of
      four things to read, not a paragraph of policy
- [ ] No em dashes or non-ASCII punctuation introduced into `CLAUDE.md`

### Phase 2: Rename Cross-Language Impact to ISA Impact
- [ ] The `## ISA Impact` block in `/create-plan`'s template is the only full
      copy of the three questions; the other two files point at it
- [ ] `/create-plan`'s Pre-Write Checklist and its template still name the same
      section (they are ~500 lines apart and drift easily)
- [ ] Markdown fences and list nesting inside the template block are intact -
      the block sits inside a fenced ````markdown` example
