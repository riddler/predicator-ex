---
name: research-codebase
description: Document codebase as-is with docs/ directory for historical context
model: opus
argument-hint: ["research question or beads issue ID"]
---

# Research Codebase

You are tasked with conducting comprehensive research across the codebase to answer user questions by spawning parallel sub-agents and synthesizing their findings.

## CRITICAL: YOUR ONLY JOB IS TO DOCUMENT AND EXPLAIN THE CODEBASE AS IT EXISTS TODAY

- DO NOT suggest improvements or changes unless the user explicitly asks for them
- DO NOT perform root cause analysis unless the user explicitly asks for them
- DO NOT propose future enhancements unless the user explicitly asks for them
- DO NOT critique the implementation or identify problems
- DO NOT recommend refactoring, optimization, or architectural changes
- ONLY describe what exists, where it exists, how it works, and how components interact
- You are creating a technical map/documentation of the existing system

## Initial Setup

When this command is invoked:

1. **Check if a beads issue ID was provided as a parameter**:
   - If an issue ID is provided (e.g., `/research-codebase px-a42`), skip the default message
   - Proceed directly to the Beads Issue Research workflow below

2. **If no parameters provided**, respond with:

```
I'm ready to research the codebase. Please provide:

- A research question or area of interest, OR
- A beads issue ID (e.g., px-a42) to research

I'll analyze it thoroughly by exploring relevant components and connections.
```

Then wait for the user's input.

## Beads Issue Research Workflow

When a beads issue ID is provided:

### Step 1: Fetch the Issue

1. **Retrieve issue details**:
   ```bash
   bd show ISSUE_ID
   ```

2. **Extract from the output**:
   - Issue ID and title
   - Description
   - Type, priority, labels
   - Dependencies and linked issues (research those relationships too if relevant)

3. **If the issue doesn't exist or there's an error**:
   - Inform the user
   - Ask if they want to provide a different issue ID or research question

### Step 2: Gather Metadata

Collect metadata for the research document:

```bash
date +%Y-%m-%dT%H:%M:%S%z
git rev-parse HEAD
git branch --show-current
```

### Step 3: Frame the Research Question

Use the issue as the research prompt:

- Extract the research question from the issue description
- Research the codebase to understand:
  - Current implementation related to this issue
  - Components and files that would be involved
  - Existing patterns that are relevant
  - Dependencies and integration points
- Apply all the standard research workflow steps below
- The final research document filename should include the issue ID
  (e.g., `docs/research/260806-px-a42-short-circuit-semantics.md`)

### Step 4: After Research Completes

1. **Record the research on the issue**:
   ```bash
   bd note ISSUE_ID "Research doc: docs/research/[filename]"
   ```

2. **Present summary to user**:
   ```
   Research complete for beads issue ISSUE_ID

   Research document: docs/research/[research_doc_filename]

   [Brief summary of key findings]

   You can now use `/create-plan docs/research/[research_doc_filename]` to create an implementation plan based on this research.
   ```

## Steps to follow after receiving the research query

1. **Read any directly mentioned files first:**
   - If the user mentions specific files (docs, ADRs, plans, source files), read them FULLY first
   - **IMPORTANT**: Use the Read tool WITHOUT limit/offset parameters to read entire files
   - **CRITICAL**: Read these files yourself in the main context before spawning any sub-tasks
   - This ensures you have full context before decomposing the research

2. **Analyze and decompose the research question:**
   - Break down the user's query into composable research areas
   - Take time to ultrathink about the underlying patterns, connections, and architectural implications the user might be seeking
   - Identify specific components, patterns, or concepts to investigate
   - Consider which stage(s) of the pipeline are involved (lexer, parser, AST
     types, compiler, evaluator/stack VM, visitors, context, functions, errors)
   - Create a research plan to track all subtasks

3. **Spawn parallel sub-agent tasks for comprehensive research:**
   - Create multiple Task agents to research different aspects concurrently
   - We have specialized agents that know how to do specific research tasks:

   **For codebase research:**
   - Use the **codebase-locator** agent to find WHERE files and components live
   - Use the **codebase-analyzer** agent to understand HOW specific code works (without critiquing it)
   - Use the **codebase-pattern-finder** agent to find examples of existing patterns (without evaluating them)

   **IMPORTANT**: All agents are documentarians, not critics. They will describe what exists without suggesting improvements or identifying issues.

   **For project documents (docs/):**
   - Use the **thoughts-locator** agent to discover what documents exist about the topic (docs/research/, docs/plans/, docs/adr/, docs/design/, docs/guides/, docs/reference/, architecture.md)
   - Use the **thoughts-analyzer** agent to extract key insights from specific documents (only the most relevant ones)
   - Accepted ADRs are settled decisions: cite their numbers, do not re-argue them

   **For cross-language comparison (only when the question involves the
   instruction set or another implementation's behavior):**
   - The instruction set is the interchange format shared with the Ruby and
     JavaScript siblings (ADR-0001). Those repos live outside this checkout;
     point a codebase-locator/analyzer agent at a sibling path explicitly when
     the question genuinely needs it, and say in the prompt that it is looking
     outside `/Users/johnnyt/repos/github/predicator-ex`.

   **For web research (only if user explicitly asks):**
   - Use the **web-search-researcher** agent for external documentation and resources
   - IF you use web-research agents, instruct them to return LINKS with their findings, and please INCLUDE those links in your final report

   The key is to use these agents intelligently:
   - Start with locator agents to find what exists
   - Then use analyzer agents on the most promising findings to document how they work
   - Run multiple agents in parallel when they're searching for different things
   - Each agent knows its job - just tell it what you're looking for
   - Don't write detailed prompts about HOW to search - the agents already know
   - Remind agents they are documenting, not evaluating or improving

4. **Wait for all sub-agents to complete and synthesize findings:**
   - IMPORTANT: Wait for ALL sub-agent tasks to complete before proceeding
   - Compile all sub-agent results (both codebase and docs findings)
   - Prioritize live codebase findings as primary source of truth
   - Use docs/ findings as supplementary historical context
   - Connect findings across different components
   - Include specific file paths and line numbers for reference
   - Highlight patterns, connections, and architectural decisions (with ADR numbers)
   - Answer the user's specific questions with concrete evidence

5. **Gather metadata for the research document:**
   - Collect date/time with timezone, git commit hash, and branch name (see Step 2 commands above)
   - Filename: `docs/research/YYMMDD-description.md`
     - Format: `YYMMDD-[issue-id-]description.md` where:
       - YYMMDD is today's date
       - issue-id is the beads issue ID (omit if none)
       - description is a brief kebab-case description of the research topic
     - Examples:
       - With issue: `260806-px-a42-short-circuit-semantics.md`
       - Without issue: `260806-precedence-table-history.md`
   - `docs/research/` may not exist yet - create it.

6. **Generate research document:**
   - Use the metadata gathered in step 5
   - **CRITICAL: You MUST propose the complete document and write it to disk before presenting your summary.**
     1. Compose the full document content (frontmatter + body)
     2. Present the proposed file path and a brief description to the user
     3. Ask the user for permission to write the file
     4. Upon approval, write the file using the Write tool
     5. Confirm the file was written successfully
   - Structure the document with YAML frontmatter followed by content:

     ```markdown
     ---
     date: [Current date and time with timezone in ISO format]
     researcher: Claude
     git_commit: [Current commit hash]
     branch: [Current branch name]
     repository: predicator-ex
     beads_issue: [Issue ID, if applicable]
     topic: "[User's Question/Topic]"
     tags: [research, codebase, relevant-component-names]
     status: complete
     last_updated: [Current date in YYYY-MM-DD format]
     last_updated_by: Claude
     ---

     # Research: [User's Question/Topic]

     **Date**: [Current date and time with timezone]
     **Git Commit**: [Current commit hash]
     **Branch**: [Current branch name]
     **Beads Issue**: [Issue ID, if applicable]

     ## Research Question

     [Original user query]

     ## Summary

     [High-level documentation of what was found, answering the user's question by describing what exists]

     ## Detailed Findings

     ### [Component/Area 1]

     - Description of what exists (`lib/predicator/parser.ex:123`)
     - How it connects to other components
     - Current implementation details (without evaluation)

     ### [Component/Area 2]

     ...

     ## Code References

     - `lib/predicator/evaluator.ex:45` - Description of what's there
     - `test/predicator/integration/full_pipeline_test.exs:12-40` - Description of the code block

     ## Architecture Documentation

     [Current patterns, conventions, and design implementations found in the codebase; cite ADR numbers where applicable]

     ## Cross-Language Impact

     [Only when the instruction set is involved: what an ISA change here would
     mean for the Ruby and JavaScript siblings, per ADR-0001. Omit the section
     entirely when it does not apply.]

     ## Historical Context (from docs/)

     [Relevant insights from docs/ with references]
     - `docs/adr/0001-keep-the-stack-vm-revise-the-instruction-set.md` - Decision about X
     - `docs/architecture.md` - "Source Spans (v3.9.0)" section on Y

     ## Related Research

     [Links to other research documents in docs/research/]

     ## Open Questions

     [Any areas that need further investigation]
     ```

7. **Add GitHub permalinks (if applicable):**
   - Check if on main branch or if commit is pushed: `git branch --show-current` and `git status`
   - If on main/master or pushed, generate GitHub permalinks:
     - Get repo info: `gh repo view --json owner,name`
     - Create permalinks: `https://github.com/{owner}/{repo}/blob/{commit}/{file}#L{line}`
   - Replace local file references with permalinks in the document

8. **Present findings:**
   - Present a concise summary of findings to the user
   - Include key file references for easy navigation
   - Ask if they have follow-up questions or need clarification

9. **Handle follow-up questions:**
   - If the user has follow-up questions, append to the same research document
   - Update the frontmatter fields `last_updated` and `last_updated_by` to reflect the update
   - Add `last_updated_note: "Added follow-up research for [brief description]"` to frontmatter
   - Add a new section: `## Follow-up Research [timestamp]`
   - Spawn new sub-agents as needed for additional investigation
   - Continue updating the document

## Important notes

- Always use parallel Task agents to maximize efficiency and minimize context usage
- Always run fresh codebase research - never rely solely on existing research documents
- The docs/ directory provides historical context to supplement live findings.
  `docs/architecture.md` in particular carries per-feature history with version
  numbers, which is often the fastest answer to "when and why did this arrive"
- Focus on finding concrete file paths and line numbers for developer reference
- Research documents should be self-contained with all necessary context
- Each sub-agent prompt should be specific and focused on read-only documentation operations
- Document cross-component connections and how systems interact
- Include temporal context (when the research was conducted)
- Link to GitHub when possible for permanent references
- Keep the main agent focused on synthesis, not deep file reading
- Have sub-agents document examples and usage patterns as they exist
- Explore all of docs/ (research, plans, adr, design, guides, reference,
  architecture.md), not just docs/research/
- **CRITICAL**: You and all sub-agents are documentarians, not evaluators
- **REMEMBER**: Document what IS, not what SHOULD BE
- **NO RECOMMENDATIONS**: Only describe the current state of the codebase
- **File reading**: Always read mentioned files FULLY (no limit/offset) before spawning sub-tasks
- **Critical ordering**: Follow the numbered steps exactly
  - ALWAYS read mentioned files first before spawning sub-tasks (step 1)
  - ALWAYS wait for all sub-agents to complete before synthesizing (step 4)
  - ALWAYS gather metadata before writing the document (step 5 before step 6)
  - NEVER write the research document with placeholder values
- **Frontmatter consistency**:
  - Always include frontmatter at the beginning of research documents
  - Keep frontmatter fields consistent across all research documents
  - Update frontmatter when adding follow-up research
  - Use snake_case for multi-word field names (e.g., `last_updated`, `git_commit`)
  - Tags should be relevant to the research topic and components studied
