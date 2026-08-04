---
name: create-plan
description: Create detailed implementation plans through interactive research and iteration
model: opus
argument-hint: ["beads issue ID, or path to a design/research doc"]
---

# Implementation Plan

You are tasked with creating detailed implementation plans through an
interactive, iterative process. You should be skeptical, thorough, and work
collaboratively with the user to produce high-quality technical specifications.

Planning runs on the Opus tier (this skill's frontmatter); implementation runs
on Sonnet via `/implement-plan`.

---

## MANDATORY Output Requirements

**You MUST follow these requirements exactly. Re-read this section before
writing the final plan.**

### File Location

**ALWAYS** write the plan to: `docs/plans/YYMMDD-issue-id-description.md`

- `YYMMDD` = today's date
- `issue-id` = beads issue ID (omit if none)
- `description` = brief kebab-case description

Examples:
- `docs/plans/260804-px-abc-object-notation.md`
- `docs/plans/260804-improve-parse-errors.md`

`docs/plans/` may not exist yet - create it. **NEVER** write the plan to
`.claude/`, the project root, or any other directory.

### Template Structure

The plan document **MUST** include ALL of the following sections in this order:

1. `# [Feature/Task Name] Implementation Plan` (title)
2. `## Overview` (brief description, beads issue ID)
3. `## Current State Analysis` (what exists, constraints)
4. `## Desired End State` (specification of end state, how to verify)
5. `## What We're NOT Doing` (explicit out-of-scope items)
6. `## Implementation Approach` (high-level strategy)
7. `## Phase N: [Name]` (one or more phases, each with Overview, Changes
   Required, and Success Criteria split into Automated/Manual Verification)
8. `## Testing Strategy` (unit, integration, manual)
9. `## References` (source docs, ADR numbers, file:line refs)

Optional sections (include if applicable): `## Performance Considerations`,
`## Cross-Language Impact` (when the instruction set changes - see ADR-0001).

---

## Initial Response

When this command is invoked:

1. **Check if parameters were provided**:
   - If a file path was provided (design doc, research note, or other), skip the
     default message
   - Immediately read any provided files FULLY
   - Begin the research process
   - **Supported inputs**:
     - Beads issue IDs: e.g. `px-abc` (fetch with `bd show px-abc`)
     - Design docs: `docs/design/YYYY-MM-DD-topic.md`
     - Any other path the user hands you

2. **If no parameters provided**, respond with:

```
I'll help you create a detailed implementation plan. Let me start by understanding what we're building.

Please provide:
1. The task description, beads issue ID, or design document
2. Any relevant context, constraints, or specific requirements
3. Links to related design notes or previous implementations

I'll analyze this information and work with you to create a comprehensive plan.

Examples:
- `/create-plan px-abc` (beads issue ID)
- `/create-plan docs/design/2026-08-03-statifier-seams.md`
- `/create-plan think deeply about docs/design/2026-08-03-statifier-seams.md`
```

Then wait for the user's input.

## Process Steps

### Step 1: Context Gathering & Initial Analysis

1. **Read all mentioned files immediately and FULLY**:
   - Design or research documents under `docs/`
   - Related implementation plans in `docs/plans/`
   - Relevant ADRs in `docs/adr/` (accepted ADRs are settled; the plan must fit
     them - ADR-0001 sets the 3.6-4.0 arc and keeps the stack VM on ISA v2)
   - `docs/architecture.md` for the grammar, precedence table, and component map
   - **IMPORTANT**: Use the Read tool WITHOUT limit/offset parameters to read
     entire files
   - **CRITICAL**: DO NOT spawn sub-agents before reading these files yourself
     in the main context
   - **NEVER** read files partially - if a file is mentioned, read it completely

   **When starting from a beads issue**:
   - Fetch it with `bd show <id>`; note dependencies, labels, and linked issues
   - Check `bd show` output for notes pointing at existing design docs

   **When starting from a design doc**:
   - Use it as the foundation for the plan - it has already done the
     investigation
   - Focus on structuring the implementation rather than re-researching
   - Validate that its recommendations are still current if the doc is old

2. **Spawn research agents to gather context**:
   If the input did not come with full `file:line` detail, use the `Explore`
   agent (read-only, breadth-first) in parallel before asking the user any
   questions. Give each one a narrow question and ask for `file:line`
   references back. Useful splits in this codebase:

   - the lexer/parser path for a syntax change (`lib/predicator/lexer.ex`,
     `parser.ex`, `types.ex`)
   - the compile path for an instruction-set change
     (`lib/predicator/compiler.ex`, `visitors/instructions_visitor.ex`)
   - the runtime path (`lib/predicator/evaluator.ex`, `functions/**`)
   - the round-trip path (`lib/predicator/visitor.ex`, `visitors/**`) - a
     grammar change that `StringVisitor` cannot render back is an incomplete
     change
   - the test layout for the area being touched (`test/predicator/**`)

   Use `general-purpose` when the question needs more than reading - running
   `mix run` snippets, checking behavior in `iex`, or reading the Ruby and
   JavaScript siblings if the user has them checked out locally.

3. **Read all files identified by the research agents**:
   - After they complete, read ALL files they identified as relevant
   - Read them FULLY into the main context
   - This ensures you have complete understanding before proceeding

4. **Analyze and verify understanding**:
   - Cross-reference the issue requirements with actual code
   - Check the grammar and precedence table in `docs/architecture.md` before
     proposing syntax; precedence is a whole-language decision, not a local one
   - Identify any discrepancies or misunderstandings
   - Note assumptions that need verification
   - Determine true scope based on codebase reality

5. **Present informed understanding and focused questions**:

   ```
   Based on the issue and my research of the codebase, I understand we need to [accurate summary].

   I've found that:
   - [Current implementation detail with file:line reference]
   - [Relevant pattern or constraint discovered, e.g. an ADR that bounds the design]
   - [Potential complexity or edge case identified]

   Questions that my research couldn't answer:
   - [Specific technical question that requires human judgment]
   - [Grammar or instruction-set decision that affects the sibling implementations]
   - [Design preference that affects implementation]
   ```

   Only ask questions that you genuinely cannot answer through code
   investigation.

### Step 2: Research & Discovery

After getting initial clarifications:

1. **If the user corrects any misunderstanding**:
   - DO NOT just accept the correction
   - Spawn new research tasks to verify the correct information
   - Read the specific files/directories they mention
   - Only proceed once you've verified the facts yourself

2. **Create a research todo list** to track exploration tasks

3. **Spawn parallel sub-agents for comprehensive research**, each focused on one
   question, each asked to return specific `file:line` references. `Explore` is
   the default; `general-purpose` when the answer needs execution or web
   lookups (hexdocs, the sibling implementations' repos).

4. **Wait for ALL sub-tasks to complete** before proceeding

5. **Present findings and design options**:

   ```
   Based on my research, here's what I found:

   **Current State:**
   - [Key discovery about existing code]
   - [Pattern or convention to follow]

   **Design Options:**
   1. [Option A] - [pros/cons]
   2. [Option B] - [pros/cons]

   **Open Questions:**
   - [Technical uncertainty]
   - [Design decision needed]

   Which approach aligns best with your vision?
   ```

### Step 3: Plan Structure Development

Once aligned on approach:

1. **Create initial plan outline**:

   ```
   Here's my proposed plan structure:

   ## Overview
   [1-2 sentence summary]

   ## Implementation Phases:
   1. [Phase name] - [what it accomplishes]
   2. [Phase name] - [what it accomplishes]
   3. [Phase name] - [what it accomplishes]

   Does this phasing make sense? Should I adjust the order or granularity?
   ```

   Phases should split along the pipeline's natural seams where possible -
   lexer, parser, compiler/instructions, evaluator, visitors - so they can be
   parallelized across worktrees, and so each phase maps cleanly onto one
   `area:` label (CLAUDE.md).

   A phase should also be the smallest unit that is independently
   gate-verifiable and independently committable. If two candidate phases
   would leave an intermediate `mix quality` gate red on their own (a new
   instruction emitted in one phase and handled by the evaluator in the next,
   with nothing exercising it in between), combine them into one phase rather
   than splitting - this keeps `/implement-plan --loop`'s per-phase gate
   meaningful, and it is the answer to grouping small phases together: sizing
   at authoring time, not a runtime grouping mechanism.

2. **Get feedback on structure** before writing details

### Step 4: Detailed Plan Writing

After structure approval:

1. **CRITICAL: You MUST write the plan to disk before presenting your summary.**
   - **Re-read the "MANDATORY Output Requirements" section at the top of this
     document NOW**
   - Compose the full document content following the MANDATORY template
     structure
   - Present the proposed file path and a brief description to the user
   - Ask the user for permission to write the file
   - Upon approval, write the file using the Write tool
   - Confirm the file was written successfully
2. **Use this template structure** (see also MANDATORY Output Requirements
   above):

````markdown
# [Feature/Task Name] Implementation Plan

## Overview

[Brief description of what we're implementing and why. Beads issue: px-xxx]

## Current State Analysis

[What exists now, what's missing, key constraints discovered]

## Desired End State

[A specification of the desired end state after this plan is complete, and how
to verify it]

### Key Discoveries:
- [Important finding with file:line reference]
- [Pattern to follow]
- [Constraint to work within, e.g. ADR number]

## What We're NOT Doing

[Explicitly list out-of-scope items to prevent scope creep]

## Implementation Approach

[High-level strategy and reasoning]

## Phase 1: [Descriptive Name]

### Overview
[What this phase accomplishes]

### Changes Required:

#### 1. [Component/File Group]
**File**: `lib/predicator/parser.ex`
**Changes**: [Summary of changes]

```elixir
# Specific code to add/modify
```

### Success Criteria:

#### Automated Verification:
- [ ] Full quality gate passes (format, compile, credo --strict, dialyzer, deps
      audit, full suite with coverage): `mix quality`
- [ ] New code is covered - coverage stays above the 90% minimum in
      `coveralls.json`

#### Manual Verification:
- [ ] Round-trips through `StringVisitor` without losing information
- [ ] Edge case handling verified manually (e.g. via an iex session)
- [ ] No regressions in related features

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run the full `mix quality` as the phase gate. In interactive
execution, pause here for manual confirmation from the human that the manual
testing was successful before proceeding to the next phase. In looped
(`--loop`) execution, this phase's Automated Verification gates advancement
automatically (via `/commit --auto`); Manual Verification items are deferred and
surfaced once at the end instead of blocking here.

---

## Phase 2: [Descriptive Name]

[Similar structure with both automated and manual success criteria...]

---

## Testing Strategy

### Unit Tests:
- [What to test in test/predicator/, pattern-matching style]
- [Key edge cases - precedence, type mismatches, error positions]

### Integration Tests:
- [End-to-end `Predicator.evaluate/3` cases in test/predicator/integration/]

### Manual Testing Steps:
1. [Specific step to verify feature]
2. [Another verification step]
3. [Edge case to test manually]

## Performance Considerations

[Any performance implications or optimizations needed]

## Cross-Language Impact

[If the instruction set changed: what the Ruby and JavaScript implementations
need, per ADR-0001. Omit this section if the ISA is untouched.]

## References

- Source document: `docs/design/[relevant].md`
- Related ADRs: `docs/adr/NNNN-...`
- Similar implementation: `[file:line]`
- Beads issue: `px-xxx`
````

### Step 5: Review

1. **Present the draft plan location**:

   ```
   I've created the initial implementation plan at:
   `docs/plans/YYMMDD-issue-id-description.md`

   Please review it and let me know:
   - Are the phases properly scoped?
   - Are the success criteria specific enough?
   - Any technical details that need adjustment?
   - Missing edge cases or considerations?
   ```

2. **Iterate based on feedback** - be ready to:
   - Add missing phases
   - Adjust technical approach
   - Clarify success criteria (both automated and manual)
   - Add/remove scope items

3. **Continue refining** until the user is satisfied

## Important Guidelines

1. **Be Skeptical**:
   - Question vague requirements
   - Identify potential issues early
   - Ask "why" and "what about"
   - Don't assume - verify with code

2. **Be Interactive**:
   - Don't write the full plan in one shot
   - Get buy-in at each major step
   - Allow course corrections
   - Work collaboratively

3. **Be Thorough**:
   - Read all context files COMPLETELY before planning
   - Research actual code patterns using parallel sub-agents
   - Include specific file paths and line numbers
   - Write measurable success criteria with a clear automated vs manual
     distinction
   - Automated steps use the ex_quality flow: `mix quality --profile loop` while
     iterating, full `mix quality` as the per-phase gate, and
     `mix quality --format json` when an agent needs to route on results

4. **Be Practical**:
   - Focus on incremental, testable changes
   - Think about edge cases: precedence, empty input, type mismatches, error
     positions
   - Include "what we're NOT doing"

5. **Track Progress**:
   - Track planning tasks as todos
   - Update todos as you complete research
   - Mark planning tasks complete when done

6. **No Open Questions in Final Plan**:
   - If you encounter open questions during planning, STOP
   - Research or ask for clarification immediately
   - Do NOT write the plan with unresolved questions
   - The implementation plan must be complete and actionable
   - Every decision must be made before finalizing the plan

## Success Criteria Guidelines

**Always separate success criteria into two categories:**

1. **Automated Verification** (can be run by execution agents):
   - `mix quality --profile loop` for the iteration loop (format, compile,
     credo, changed-scope tests)
   - `mix quality` as the full per-phase gate (adds dialyzer, deps audit, full
     suite with coverage)
   - `mix quality --format json` when results must be machine-readable
   - Specific files that should exist

2. **Manual Verification** (requires human testing):
   - Grammar and precedence judgment calls
   - Behavior exercised interactively (iex, example predicates)
   - Error messages a human has to read to judge
   - User acceptance criteria

**Format example:**

```markdown
### Success Criteria:

#### Automated Verification:
- [ ] Full gate passes: `mix quality`
- [ ] Coverage for the new module is above 90%

#### Manual Verification:
- [ ] `"a > 1 and b < 2"` parses with the documented precedence
- [ ] The parse error for `"a >"` names the right position
- [ ] StringVisitor round-trips every new node type
```

## Common Patterns

### For New Syntax (operators, literals, notation)

- Extend the lexer with the new token, then the parser with its precedence -
  and update the grammar and precedence table in `docs/architecture.md`
- Extend `InstructionsVisitor` so it compiles, and `StringVisitor` so it
  round-trips
- Handle the new instructions in the evaluator
- A new instruction is a change to the cross-language interchange format
  (ADR-0001), so the plan says what the Ruby and JavaScript siblings need

### For New Functions

- Add to the right module under `lib/predicator/functions/`
- Arity and type checking are values, not exceptions: return
  `{:ok, result} | {:error, ...}`
- Cover the error paths, not just the happy path - they are the coverage gap
  that shows up in the gate

### For Refactoring

- Document current behavior
- Plan incremental changes
- Keep the suite green throughout
- State what would prove the refactor changed no behavior

## Project-Specific Code Patterns

Follow the conventions in `CLAUDE.md` and `docs/architecture.md`: `@doc` and
`@spec` on every public function, errors as `{:ok, result} | {:error, ...}`
values never raised at a leaf, no `eval` and no dynamic code execution anywhere
in the pipeline. Cite ADR numbers rather than restating their reasoning.

## Sub-agent Spawning Best Practices

When spawning research sub-agents:

1. **Spawn multiple in parallel** for efficiency - one message, several Agent
   calls
2. **Each should be focused** on a specific area
3. **Provide detailed instructions** including:
   - Exactly what to search for
   - Which directories to focus on
   - What information to extract
   - Expected output format
4. **Be EXTREMELY specific about directories** - include the full path context
   in your prompts, and say explicitly when a task should look outside this repo
   (a sibling implementation, a downstream consumer)
5. **Prefer `Explore`** - it is read-only, which is what research wants
6. **Request specific `file:line` references** in responses
7. **Wait for all tasks to complete** before synthesizing
8. **Verify sub-agent results**:
   - If one returns unexpected results, spawn a follow-up
   - Cross-check findings against the actual codebase
   - Don't accept results that seem incorrect

## Example Interaction Flow

### From a beads issue:

```
User: /create-plan px-abc
Assistant: Let me fetch the details for issue px-abc...

[Runs bd show px-abc]

Based on the issue, I understand we need to add object literal notation. Let me research the codebase...

[Interactive process continues...]
```

### From a design document:

```
User: /create-plan docs/design/2026-08-03-statifier-seams.md
Assistant: Let me read that design document completely first...

[Reads file fully]

Based on your design note, I see the seams are already identified with file references. Let me structure this into an implementation plan...

[Proceeds with less initial research since the doc already contains findings]
```

---

## Pre-Write Checklist

**STOP. Before writing the plan file, verify ALL of the following:**

- [ ] File path is `docs/plans/YYMMDD-...md` (NOT `.claude/`, NOT project root)
- [ ] File name follows format: `YYMMDD-issue-id-kebab-description.md`
- [ ] Document starts with `# [Name] Implementation Plan`
- [ ] Contains ALL mandatory sections: Overview, Current State Analysis,
      Desired End State, What We're NOT Doing, Implementation Approach,
      Phase(s), Testing Strategy, References
- [ ] Each Phase has Success Criteria split into Automated Verification and
      Manual Verification
- [ ] Automated criteria use the ex_quality commands (`mix quality --profile
      loop`, `mix quality`)
- [ ] If the instruction set changed, a Cross-Language Impact section says what
      the siblings need (ADR-0001)
- [ ] No unresolved open questions remain in the document
