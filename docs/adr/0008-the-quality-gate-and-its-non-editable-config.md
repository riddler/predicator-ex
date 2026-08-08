# ADR-0008: `mix quality` is the gate, and its config is not agent-editable

Status: proposed (2026-08-07)

## Context

ADR-0006 places the human gate where an action stops being reversible, and its
first rung - local, undoable work, including `git commit` on the issue's own
feature branch - has **no human trigger at all**. That grant is only defensible
because something else is checking the work. What checks it is a machine gate,
and this ADR records what that gate is and why it is shaped the way it is.

Two things have to be true for a machine gate to carry that weight, and neither
is automatic.

**The gate has to be the same gate every time.** An agent working unattended in
a fresh worktree has no memory of the last session. If the pre-commit bar is
described as a list of steps - format, then compile, then credo, then dialyzer,
then the audit, then the suite with coverage - then every session reassembles
that list from a document, and reassembly is where it degrades. A session under
time pressure drops dialyzer because it is slow. A session that has only touched
one module runs one test file. A session reads "run the checks" and runs the two
it remembers. None of those is a lie in the session's report; each one honestly
says the checks passed, for its own value of "the checks". A gate whose
composition varies per session is not a gate, it is a habit, and its green tells
a reviewer nothing about what actually ran.

**The gate has to not be movable by the party it constrains.** This is the same
structural point ADR-0006 makes about authority: a rule enforced only by the
judgment of the party it constrains is not enforced. An agent that has been told
to get to green and can also edit the definition of green has been given two
routes to the same goal, and the cheaper one is always to move the line. Drop
the coverage minimum from 90 to 85. Add the failing check to `:disabled`. Put
`@tag :skip` on the test. Pass `--skip-dialyzer` to the final run. Each of these
is a one-line edit that produces a genuinely green run, and each of them is
locally reasonable - the agent is not being adversarial, it is optimizing for
the objective it was given. The failure mode is not deceit, it is gradient
descent on the wrong surface.

There is a real tension against both of these. The full gate is slow: dialyzer
alone dominates it, and the PLT has to exist before it is fast. An agent
iterating between edits, running the whole thing after each one, spends most of
its wall clock waiting on stages that cannot have been affected by the edit it
just made. A gate too slow to run is a gate that gets skipped, which is the
failure the first requirement was trying to prevent, arriving by another road.

### Prior art

statifier's ADR-0009 and ADR-0011 reached related conclusions in that repo, and
the practice arrived here from there. This ADR is not a citation to them.
Predicator carries its own record where the reasoning overlaps, per the decision
on px-4lz, and everything argued here is argued in predicator's terms and is
readable without that repo.

## Decision

### One command is the gate

**The quality gate is `mix quality`, a single aggregated command supplied by the
`ex_quality` dependency and configured in `.quality.exs`.** It runs format,
compile with `warnings_as_errors: true`, `credo --strict`, dialyzer, a
dependency audit, and the full test suite with coverage. Full `mix quality`
green is the precondition for every commit.

The aggregation is the point, not a convenience. Because the gate is one
command, "did the gate pass" is a question with one answer, the composition of
the gate lives in a versioned file rather than in a session's recollection, and
changing what the gate does is an edit to that file that shows up in a diff. An
agent cannot partially run a command it invokes as a whole, which removes the
entire class of failure where the gate quietly shrinks to fit the session.

`--format json` is the machine-readable form of the same run. The automated loop
uses it to route on **which stage failed** without parsing human output, which
matters because the response to a red format stage (the gate's own formatter
fixes it) is not the response to a red dialyzer stage (a real finding to
report).

### The `--profile loop` split, and why it does not undermine the above

`mix quality --profile loop` runs `:format`, `:compile`, `:credo`, and `:test`
only. It **skips dialyzer and coverage**, and it scopes the test run to code
changed against `origin/main` (`test: [scope: :changed, coverage: false,
base_ref: "origin/main"]`). It exists because the alternative is worse: an agent
that pays the full gate's latency on every edit either stops running the gate
between edits, or spends its session waiting, and both outcomes push real
checking later than it should happen.

**A scoped green is not a full green, and it never substitutes for the
pre-commit run.** `CLAUDE.md` says so, `.quality.exs`'s own header comment says
so at the point of configuration ("Use between edits, never as the final
check"), and `/implement-plan` says so in the instructions it hands to the agent
doing the work.

That discipline holds because it does not depend on the iterating agent's
honesty. **`/commit` runs the full `mix quality` itself, in its Step 0, before
it writes anything**, and it refuses to commit on a red gate or on a narrowed
one - a `--quick`, a `--profile loop`, or a `--test-scope changed` run is
explicitly not a green gate for commit purposes. The subagent's self-report is
not the input to that decision; a fresh full run is. So a session that
substitutes the fast profile for the real one does not get a quiet pass, it gets
a red gate at commit time. The fast profile is an accelerator inside the loop,
not a smaller version of the bar at the end of it.

The one carve-out is scoped and stated rather than inferred: a change touching
no Elixir code - no `lib/`, `test/`, or `src/`, and neither `mix.exs` nor
`mix.lock` - has no gate to run, and `/commit` reviews the diff instead. When
that applies it must be reported as "docs only, no quality gate applicable",
precisely so a reader does not assume a green run that never happened.

### The gate config is not agent-editable

**`.quality.exs`, `.credo.exs`, and `coveralls.json` are off limits to an agent
trying to get a run green.** Concretely, and as `CLAUDE.md` states: no lowered
coverage threshold, no `enabled: false` on a check, no `--skip-*` flag on the
final run, no `@tag :skip` on a failing test. The gate is not weakened to pass;
the code changes until the gate passes.

This is the same structural reasoning as ADR-0006 applied one layer down. There,
the point is that an agent cannot supply its own authorization for an
irreversible act. Here, the point is that an agent cannot supply its own
definition of correct. Both follow from the same observation: a constraint whose
enforcement is delegated to the party being constrained is not a constraint, and
the failure will not look like a violation - it will look like a green run and a
confident report.

**The escape valve is real, and it is a different act.** If a finding is
genuinely wrong for this repo, the agent **reports it and lets a human decide**.
The rule is not "the gate is always right". It is "the agent is not the one who
gets to decide the gate is wrong". Those are different claims, and only the
second one is being made. A false positive is a legitimate outcome to surface;
what is not legitimate is resolving it unilaterally on the way to a green run,
because the agent's incentive at that moment is exactly the one that makes its
judgment untrustworthy.

**Deliberately retuning the gate is ordinary work, not a violation.** A bead
whose purpose is to tighten a threshold, enable a check, or change a profile is
legitimate and expected. What separates it from the prohibited edit is not the
content of the change but its provenance: it is proposed as the work, reviewed
as a change in its own right, and it carries `area:build`, which under ADR-0005
is exclusive - the bead lands on `main` alone, batched with nothing. The
prohibition is on gate config moving as a *side effect* of getting something
else to pass, where it arrives inside a diff about something else and is
reviewed, if at all, as noise.

The thresholds are also deliberately not centralized into one file.
`.quality.exs` carries the gate's composition, `coveralls.json` carries the 90%
coverage minimum, and `.credo.exs` carries the check list, so each has exactly
one home and there is no second place a limit can be quietly restated.

### This decision does not move the instruction set

**No ISA change. No opcode is added, removed, renamed, or given different
semantics, and no ISA version is bumped.** This is a decision about how this
repo's code is checked before it is committed; it touches no grammar, no
compiler output, no opcode, and no stored artifact. Per ADR-0003 an ISA change
owes a version, a `docs/isa.md` entry, and a migration note where stored
artifacts are affected - none of that is owed here. The one adjacency worth
naming is directional and does not run the other way: because ADR-0003 makes
this repo the ISA's reference implementation, the gate is what stands between an
ISA change and a release the siblings adopt against. That raises what the gate
is protecting; it does not make the gate part of the instruction set.

## Consequences

- **The gate is a machine gate, not a human one, and that is what pays for
  ADR-0006's rung 1.** The authority table grants `git commit` on a feature
  branch with no human trigger. It can do that because the green run *is* the
  review for reversible work - the commit is on a private branch, undone with
  `git reset --soft HEAD~1`, and the thing standing between a bad edit and a
  commit is a check that ran identically for every other commit. Remove the
  gate's uniformity or its non-editability and that grant stops being
  defensible, because there would be nothing checking the work at all.

- **Coverage is enforced, not encouraged.** The >90% target is
  `minimum_coverage: 90` in `coveralls.json`, applied per component, with
  `test/support` skipped. It is a build failure, not a convention someone is
  expected to honor, which is the only form of a coverage target that survives
  contact with an unattended agent. The practical consequence is that new code
  arrives with tests or does not arrive.

- **The credo suppressions in the lexer and parser are documented exceptions,
  and are not a precedent.** `lib/predicator/lexer.ex` and
  `lib/predicator/parser.ex` carry `credo:disable-for-this-file` and
  `credo:disable-for-next-line` comments for `Refactor.Nesting` and
  `Refactor.CyclomaticComplexity`, with an explanation at the point of
  suppression. These are inherent to hand-written tokenizing and recursive
  descent, they were accepted knowingly, and they live in the source next to the
  code they excuse rather than in the config where they would silently apply to
  everything. `CLAUDE.md` names them and adds the warning explicitly: they are
  not an invitation to suppress others. A new suppression is a change that needs
  an argument, not a pattern to follow.

- **The gate is slow, and that cost is accepted.** Dialyzer dominates the full
  run, and it needs a PLT (`priv/plts/dialyzer.plt`, pinned in `mix.exs`) that
  is expensive to build from scratch. Under ADR-0005 every bead gets its own
  worktree, so the PLT problem is per-worktree, and `/new-worktree` warms it by
  cloning `deps/`, `_build/`, and `priv/plts/` from the main checkout so the
  first quality run there takes seconds instead of minutes. That warming step
  exists because of this ADR: the alternative to warming is not a faster gate,
  it is a gate people stop running.

- **`area:build` exclusivity is partly a consequence of this decision.** The
  gate config and `mix.lock` are what every other worktree's warmed `_build` and
  quality run depend on, so a branch that moves them turns parallel branches red
  for reasons unrelated to their own work. That is why a bead carrying
  `area:build` lands alone - see ADR-0005.

- **Changing the gate now has a shape.** Tightening it, loosening it, adding a
  stage, or moving a threshold is a bead with `area:build`, reviewed on its own,
  landing alone, with the reasoning in the bead. Adding or adjusting a check
  does not supersede this ADR. What would supersede it is abandoning the single
  aggregated command, or making gate config something an agent may edit in the
  course of getting other work green - those are the two claims this ADR
  actually makes.

- **A red gate on unattended work stops the loop rather than being repaired.**
  `/commit` in auto mode does not fix gate failures unasked, and
  `/implement-plan --loop` treats a red or narrowed gate as a refusal and halts
  immediately with a note on the bead, rather than retrying. This is the
  non-editability rule expressed as control flow: the agent that would be most
  tempted to move the line is the one running with nobody watching, so that is
  the case where the loop stops.

### Open questions

- **The prohibition is a rule, not a mechanism.** Nothing mechanically prevents
  an agent from editing `.quality.exs`, `.credo.exs`, or `coveralls.json` - the
  files are writable, and the check is that a human reads the diff. A hook or a
  permissions deny-rule could enforce it structurally, which would make this ADR
  self-consistent (a rule the constrained party cannot move) rather than
  relying on the same review it argues is insufficient elsewhere. Whether that
  is worth the friction on legitimate `area:build` work is undecided.

- **`.claude/agents/code-quality-enforcer.md` is generic and predates this
  record.** It describes formatting and linting in language-neutral terms and
  does not mention `mix quality`, `.quality.exs`, or the non-editability rule.
  It is not part of the enforcement path today - `/commit` and
  `/implement-plan` run the gate directly - and whether it should be rewritten
  against this ADR or retired is left open.

- **Nothing records what to do when the gate is red for a reason outside the
  branch** - a dependency advisory published upstream, or a new credo check
  arriving with a version bump. Under the rule as written the agent reports and
  a human decides, which is probably right, but it means an unrelated upstream
  event can block every in-flight worktree at once, and no mitigation is
  written down.
