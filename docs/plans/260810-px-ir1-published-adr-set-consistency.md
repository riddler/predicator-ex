# Published ADR Set Consistency Implementation Plan

## Overview

Make the ADR set that hexdocs publishes self-consistent: every ADR a published
page links to relatively is itself published, the governance ADRs stay
unpublished and are reached by absolute GitHub URL instead, and an ExUnit
binding test keeps the two halves from drifting apart the next time an ADR is
written and cited. Bead: `px-ir1` (labels `area:build`, `area:docs`, so it
lands alone under the exclusivity rule).

## Current State Analysis

`mix.exs`'s `docs/0` publishes 15 extras (`mix.exs:92-112`): README, the
language reference, the ISA spec, four guides, `docs/architecture.md`, the ADR
index (titled "Architecture Decision Records"), ADRs 0001/0002/0003,
`CHANGELOG.md`, and `LICENSE`. `groups_for_extras` files anything matching
`docs/(architecture|adr/)` under "Architecture", so a new ADR extra needs no
grouping change, and `package/0`'s comment (`mix.exs:53-56`) records that
extras paths are read off the publisher's disk and need no `files:` entry.

Eleven ADRs exist on disk. Five are language/ISA records that published pages
lean on as explanation (0001, 0002, 0003, 0009, 0011); six are governance
records with no audience among library consumers (0004-0008, 0010).

`mix docs` today emits exactly twelve "documentation references file ... but it
does not exist" warnings. Ten of them are ADR links:

| Source | Broken target(s) |
|---|---|
| `docs/adr/README.md` | `0004-...`, `0005-...`, `0006-...`, `0007-...`, `0008-...`, `0009-...`, `0010-...`, `0011-...` (8 rows of the index table) |
| `docs/architecture.md` | `adr/0011-casts-are-an-opcode.md` (cited twice, `docs/architecture.md:50` and `:130`) |
| `CHANGELOG.md` | `docs/adr/0009-...md` (`CHANGELOG.md:397`) |

The remaining two are out of scope and stay: `docs/contributing.md` (from
README, a file that does not exist at all) and `../conformance/RATCHET.md`
(from `docs/architecture.md`, a real file deliberately not published).

ExDoc resolves these links by matching the written path against the extras
list, and it tolerates differing prefixes: `docs/adr/0003-...md` from README
and `adr/0003-...md` from `docs/architecture.md` both resolve, because 0003 is
in `extras:`. So the fix for a broken relative link is exactly "publish the
target", with no rewriting of the citations themselves.

One citation is already absolute: `docs/guides/embedding.md:51` links ADR-0009
as `https://github.com/riddler/predicator-ex/blob/main/docs/adr/0009-...md`,
which is why that one never warned. It is the existing precedent for reaching
an unpublished document from a published page.

There is no test binding `extras:` to the docs tree. The nearest idioms are
`test/predicator/isa_sync_test.exs` (parses `docs/isa.md` at test time,
compares against `Predicator.Instructions`, guards against a
silently-matching-nothing regex with a literal `@opcode_count 28`, and carries
`# sabotage: ... -> red` notes) and `test/docs_examples_test.exs` (top-level
test file, module `Predicator.DocsExamplesTest`, runs `doctest_file/1` over six
published pages).

`docs/research/260808-px-9ab-sabotage-notes.md` defines the binding-test class:
tests that keep an exported artifact honest, currently seven enumerated files,
each carrying a one-line sabotage note verified by breaking what it covers.

### Key Discoveries:

- `mix.exs:92-112` - the `extras:` list; `docs: docs()` at `mix.exs:24` means
  `Mix.Project.config()[:docs][:extras]` is readable at test time, so the test
  needs no mix.exs text parsing.
- `docs/adr/README.md` is itself a published extra whose index table links all
  eleven ADRs relatively. It is the reason a naive "every ADR linked from a
  published page must be published" rule cannot be adopted as written -
  see "Implementation Approach".
- `docs/adr/0011-casts-are-an-opcode.md:10` links
  `../research/260809-px-2r5.1-cast-conversion-matrix.md`. Publishing 0011
  would introduce a *new* broken link on hexdocs unless that link is rewritten.
  ADR-0009 has no outbound links; ADR-0003 links ADR-0001 (already published).
- `docs/reference/ast.md:69` cites ADR-0011 relatively but `ast.md` is not in
  `extras:`, so no rule reaches it and `mix docs` never processes it.
- `docs/guides/embedding.md` is one of the `doctest_file/1` targets
  (`test/docs_examples_test.exs:18`); the line being edited there is prose, not
  a doctest, so the examples test is unaffected.
- ADR-0003 governs how the ISA moves and is porter-facing; ADR-0002 documents
  the `=` grammar break and is user-facing. Nothing in this plan touches ADR
  content, status, or numbering, so no accepted ADR is contradicted.

## Desired End State

After this plan:

1. `extras:` publishes ADRs 0001, 0002, 0003, 0009, 0011, plus the index.
   Governance ADRs 0004-0008 and 0010 remain unpublished.
2. Every relative Markdown link from a published extra to `docs/adr/NNNN-*.md`
   names a published ADR and resolves on hexdocs.
3. Every link from a published extra to an *unpublished* ADR is an absolute
   `https://github.com/riddler/predicator-ex/blob/main/...` URL, which ExDoc
   leaves alone.
4. `mix docs` emits exactly two file-reference warnings, both non-ADR:
   `docs/contributing.md` and `../conformance/RATCHET.md`.
5. `test/docs_adr_links_test.exs` fails if a published page grows a relative
   link to an unpublished ADR, if a published ADR is linked by absolute URL
   from a published page, or if a governance ADR is added to `extras:`. It
   carries sabotage notes and is enumerated in the binding-test list.

## What We're NOT Doing

- **Not taking the bead's alternative** (unpublish every ADR and de-link the
  citations). The bead flags it as the user's call; no human is available for
  this planning pass, so the plan implements the bead's own proposal, which is
  the option it recommends. Reversing later is a one-commit change to
  `extras:` plus the citations, and the binding test would still be the thing
  that enforces whichever rule is chosen.
- **Not publishing the governance ADRs.** Explicit acceptance criterion.
- **Not fixing the two non-ADR link warnings.** `docs/contributing.md` exists
  on disk but is deliberately excluded from `extras:` (`CHANGELOG.md:239-241`,
  `px-7jd.3` moved contributor how-tos out of the published docs), and
  `../conformance/RATCHET.md` is unpublished for the same kind of reason. Both
  are the same unpublished-target pattern this bead fixes for ADRs, not missing
  files, and fixing either would mean deciding to publish it. Both are outside
  this bead's
  acceptance criteria, and folding them in would widen the binding test from
  "ADR links" to "all links", which is a different rule with a different
  argument. File a follow-on bead if wanted.
- **Not publishing `docs/reference/ast.md`.** It cites ADR-0011 and would
  benefit, but adding a new reference page to hexdocs is a docs-surface
  decision, not a consistency fix.
- **Not generalizing the test to all relative links** in published extras. It
  would go red today on the two warnings above, which this bead is not fixing.
- **Not adding `warnings_as_errors` to the docs config.** ExDoc's warning
  stream still carries the two file warnings above plus a dozen
  `references function ... but it is undefined` warnings from historical
  CHANGELOG entries; turning warnings into errors would fail `mix docs`
  outright and is a separate cleanup.

## Implementation Approach

The bead proposes the rule "a published page may cite only a published ADR".
That rule is false as stated, because `docs/adr/README.md` is a published page
whose whole job is to index all eleven ADRs, governance ones included. Three
resolutions were considered:

1. **Exempt the index from the rule.** Rejected: it leaves the eight index
   warnings in place, and the acceptance criterion is that `mix docs` emits no
   ADR link warnings at all. An exemption satisfies the test and fails the
   observable outcome, which is the worst combination.
2. **Split the index into a published and an unpublished half.** Rejected: it
   makes the register - the one place a reader sees every decision this project
   has taken - incomplete in the published copy, to satisfy a tooling
   constraint. The index's value is that it is exhaustive.
3. **Keep the index whole and change the *form* of the links it uses for
   unpublished ADRs**, from relative Markdown paths to absolute GitHub blob
   URLs. Chosen.

Option 3 needs no exemption, because it makes the rule true of the index too.
The invariant becomes a statement about link form rather than about which file
is doing the linking:

> In a published extra, a **relative** link to an ADR must name a published
> ADR; a link to an unpublished ADR must be an **absolute** GitHub URL.

ExDoc only resolves relative paths, so absolute URLs produce no warning and
navigate to the repository, where the governance ADRs genuinely live. The
precedent already exists in the tree at `docs/guides/embedding.md:51`, which
links ADR-0009 exactly that way today.

The invariant has a second, symmetric half worth enforcing: an absolute GitHub
URL to an ADR that *is* published is now wrong, because it sends a hexdocs
reader out to GitHub for a page sitting next to the one they are reading. That
is the state `embedding.md:51` lands in the moment 0009 is published, so this
plan converts it to a relative link and the test asserts the converse
direction too. Enforcing both directions is what makes the test a real
consistency check rather than a one-way "is it broken yet" probe.

Phasing is docs-and-config first, test second. The reverse order would leave
the gate red at the end of phase 1 - the test would be asserting an invariant
the tree does not yet satisfy - which breaks the independently-committable
requirement.

---

## Phase 1: Publish the cited ADRs and normalize link form

### Overview

Add ADRs 0009 and 0011 to `extras:`, rewrite the index's governance links and
ADR-0011's research link as absolute GitHub URLs, pull `embedding.md`'s 0009
link back to relative, and record the docs change in the changelog. At the end
of this phase `mix docs` is down to the two known non-ADR warnings.

### Changes Required:

#### 1. Publish the two cited-but-missing ADRs

**File**: `mix.exs`
**Changes**: two entries in `extras:`, after the ADR-0003 line, keeping
numeric order. No `groups_for_extras`, `package/0`, or `files:` change is
needed - the `docs/adr/` regex and the disk-read comment already cover them.

```elixir
        "docs/adr/0003-the-elixir-implementation-leads-the-isa.md",
        "docs/adr/0009-the-compiled-envelope-carries-the-position-table.md",
        "docs/adr/0011-casts-are-an-opcode.md",
        "CHANGELOG.md",
```

#### 2. Make the ADR index's governance links absolute

**File**: `docs/adr/README.md`
**Changes**: in the index table, the six rows for the unpublished ADRs (0004,
0005, 0006, 0007, 0008, 0010) get absolute targets. The rows for 0001, 0002,
0003, 0009, and 0011 keep their relative targets unchanged. Link text (the
bare number) does not change in any row.

```markdown
| [0004](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0004-no-eval-errors-are-values.md) | No eval, ever; errors are values | accepted |
```

The same rewrite applies to 0005, 0006, 0007, 0008, and 0010, each with its own
filename. Add one sentence below the table recording why the forms differ, so
the next ADR author picks the right one:

```markdown
Link form is load-bearing: an ADR published to hexdocs is linked relatively so
the link resolves there, and an unpublished one is linked by absolute GitHub
URL. `test/docs_adr_links_test.exs` enforces both directions.
```

#### 3. Keep ADR-0011 self-contained once published

**File**: `docs/adr/0011-casts-are-an-opcode.md` (line 10)
**Changes**: `docs/research/` is never published, so the conversion-matrix link
becomes absolute by the same rule. Without this, publishing 0011 trades two
warnings for one new one.

```markdown
[`docs/research/260809-px-2r5.1-cast-conversion-matrix.md`](https://github.com/riddler/predicator-ex/blob/main/docs/research/260809-px-2r5.1-cast-conversion-matrix.md);
```

#### 4. Pull the embedding guide's ADR-0009 link back to relative

**File**: `docs/guides/embedding.md` (line 51)
**Changes**: 0009 is published as of change 1, so the absolute URL now sends a
hexdocs reader off-site for a neighbouring page.

```markdown
([ADR-0009](../adr/0009-the-compiled-envelope-carries-the-position-table.md)):
```

`docs/architecture.md` and `CHANGELOG.md` need no edit: their ADR-0011 and
ADR-0009 links are already relative and start resolving the moment change 1
lands.

#### 5. Changelog

**File**: `CHANGELOG.md`, under `## [Unreleased]`
**Changes**: a `### Changed` section (the section does not exist under
Unreleased yet; it goes after the existing `### Added`) with one entry.

```markdown
### Changed

- **Published ADR set.** The API documentation now carries every ADR its pages
  cite - ADR-0009 (the compiled envelope) and ADR-0011 (casts are an opcode)
  join 0001-0003 - so those citations resolve on hexdocs instead of 404ing.
  The governance ADRs stay unpublished and the ADR index links them by
  absolute GitHub URL.
```

### Success Criteria:

#### Automated Verification:

- [x] Full quality gate passes: `mix quality`
- [x] `mix docs` emits no ADR link warning:
      `mix docs 2>&1 | grep 'references file' | grep 'adr/'` prints nothing
      (grep exits 1)
- [x] The residual file warnings are exactly the two known non-ADR ones:
      `mix docs 2>&1 | grep 'references file' | sort -u` prints exactly the
      `docs/contributing.md` and `../conformance/RATCHET.md` lines
- [x] Every ADR path in `extras:` exists on disk:
      `mix run -e 'Mix.Project.config()[:docs][:extras] |> Enum.map(fn {p, _} -> p; p -> p end) |> Enum.each(&(File.exists?(&1) || raise &1))'`
- [x] The doctests over `docs/guides/embedding.md` still pass:
      `mix test test/docs_examples_test.exs`

The `references file` string in the two grep criteria is ExDoc's own wording
(`warning: documentation references file "..." but it does not exist`),
verified by running `mix docs` in this checkout against `ex_doc ~> 0.40`. If a
dependency bump changes it, the greps are what needs updating, not the docs -
the durable enforcement is Phase 2's test, which does not shell out to ExDoc.

#### Manual Verification:

- [ ] `mix docs` then open `doc/architecture-decision-records.html`: all eleven
      rows link somewhere, the five published numbers land on hexdocs pages and
      the six governance numbers land on GitHub
- [ ] ADR-0009 and ADR-0011 appear in the sidebar under the Architecture group,
      in number order with 0001-0003
- [ ] `doc/embedding.html`'s ADR-0009 link stays inside hexdocs
- [ ] No regressions in related features: the other extras render unchanged

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run full `mix quality` as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the
next phase. In looped (`--loop`) execution, this phase's Automated Verification
gates advancement automatically (via `/wurk:commit --auto`), and Manual
Verification items are deferred and surfaced once at the end instead of
blocking here.

---

## Phase 2: Bind the rule with a test

### Overview

Add the binding test that fails when the invariant breaks, and enumerate it in
the binding-test list so it inherits the sabotage-note obligation. This phase
changes no published content; it only makes phase 1's state enforced.

### Changes Required:

#### 1. The binding test

**File**: `test/docs_adr_links_test.exs` (new)
**Changes**: a new module `Predicator.DocsAdrLinksTest`, placed at the top
level of `test/` alongside `test/docs_examples_test.exs`, which is the existing
home for tests about published documentation rather than about a module.

Structure, modelled on `test/predicator/isa_sync_test.exs`:

- A `@moduledoc` stating the invariant and why it cannot be checked at compile
  time (the `extras:` list is a literal in `mix.exs`, the citations are prose).
- `@governance_adrs ~w(0004 0005 0006 0007 0008 0010)` - a literal list with a
  comment saying that publishing one of these is a decision, and this literal
  is where that decision becomes a visible edit.
- `@blob_prefix "https://github.com/riddler/predicator-ex/blob/main/"`.
- `@min_relative_adr_links 20` and `@min_absolute_adr_links 6` - anti-vacuity
  floors in the `@opcode_count` idiom, so a link regex that silently matches
  nothing fails instead of passing. Floors rather than exact counts, because
  citation count moves with ordinary docs work while a regex breaking drops it
  to zero. The tree carries 25 relative ADR links and 6 absolute ones after
  Phase 1; the implementer recounts and, if the real numbers differ, sets the
  floors a few below them rather than at them.
- `published_extras/0`: `Mix.Project.config()[:docs][:extras]`, normalizing
  each entry from `path | {path, opts}` to a path string.
- `links_in/1`: scan a file with `~r/\]\(\s*([^)\s]+)/` and return targets.
- **Resolution happens before classification, and this ordering is
  load-bearing.** A raw target is resolved first -
  `Path.expand(target, Path.dirname(source))` for a relative one - and only the
  resolved absolute path is matched against
  `~r{/adr/(\d{4})-[^/]*\.md$}` by `adr_number/1`. Doing it the other way round
  would miss every row of `docs/adr/README.md`, whose targets are bare sibling
  filenames (`0009-....md`) with no `adr/` segment in them at all - which is
  the file the whole design turns on. Resolution is also what makes
  `docs/architecture.md`'s `adr/...`, README's `docs/adr/...`, and
  `embedding.md`'s `../adr/...` normalize to one comparable form, against
  `Path.expand(extra)` for each published extra.
- An absolute target is classified separately: strip `@blob_prefix`, then apply
  the same `adr_number/1` to what remains.

Four tests, each with a sabotage note:

```elixir
# sabotage: drop the 0011 entry from mix.exs extras: -> red
test "every relative ADR link in a published extra names a published ADR"

# sabotage: restore embedding.md's ADR-0009 link to its absolute form -> red
test "a published ADR is never linked from a published extra by absolute URL"

# sabotage: add ADR-0007 to mix.exs extras: -> red
test "no governance ADR is published"

# sabotage: point an index row at a filename that does not exist -> red
test "every ADR link target exists on disk"
```

The first test also asserts that the scan found links in
`README.md`, `docs/architecture.md`, and `docs/adr/README.md` specifically, so
the floor cannot be met by one file alone. Failure messages name the offending
source file, the target, and which of the two link forms the rule wanted -
the whole point of a binding test is that the red tells the next person what
to change.

Keep helper functions small and single-purpose; `mix credo --strict` runs over
`test/` too.

#### 2. Enumerate it in the binding-test list

**File**: `docs/research/260808-px-9ab-sabotage-notes.md`
**Changes**: the note is a dated decision record, so it is amended by addition,
not rewritten. Append a short section at the end:

```markdown
## Additions to the class

- 2026-08-10 (`px-ir1`): `test/docs_adr_links_test.exs`. The published
  documentation set is an exported artifact in the same sense as the corpus -
  hexdocs is what a consumer reads - and this test binds `mix.exs`'s `extras:`
  list to the ADR citations in the pages it publishes. A vacuous pass ships
  404s on the front door with nothing noticing, which is the class's test.
  Eight files now.
```

No `CLAUDE.md` edit is needed: its Conventions bullet already points at this
note for the file list.

### Success Criteria:

#### Automated Verification:

- [x] Full quality gate passes: `mix quality`
- [x] The new test runs and passes: `mix test test/docs_adr_links_test.exs` -
      its anti-vacuity floors are part of that run, so a link regex matching
      nothing reddens it rather than passing
- [x] `mix docs 2>&1 | grep 'references file' | grep 'adr/'` still prints
      nothing

#### Manual Verification:

Deferred Manual Verification - the sabotage pass required by
`docs/research/260808-px-9ab-sabotage-notes.md`. For each of the four tests:
apply the mutation named in its `# sabotage:` note, confirm the suite goes red
*for that reason* and that the failure message names the offending file and
target, then revert.

- [ ] Remove `docs/adr/0011-casts-are-an-opcode.md` from `mix.exs` `extras:` ->
      the relative-link test fails naming 0011 and both of its relative
      citation sites, `docs/architecture.md` and `docs/adr/README.md`. If the
      index is not among them, the resolve-then-classify ordering above was not
      implemented and the test is blind to the file it exists for
- [ ] Restore `docs/guides/embedding.md:51` to the absolute GitHub URL for
      ADR-0009 -> the absolute-link test fails naming `embedding.md` and 0009
- [ ] Add `docs/adr/0007-beads-for-issue-tracking.md` to `extras:` -> the
      governance test fails naming 0007
- [ ] Point one `docs/adr/README.md` row at a filename that does not exist ->
      the existence test fails naming that target
- [ ] A test that stays green under its mutation is a finding, not a note to
      skip: reshape the test rather than weakening the note
- [ ] The working tree is clean after the pass (`git status`) - every mutation
      reverted

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run full `mix quality` as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the
next phase. In looped (`--loop`) execution, this phase's Automated Verification
gates advancement automatically (via `/wurk:commit --auto`), and Manual
Verification items are deferred and surfaced once at the end instead of
blocking here.

---

## Testing Strategy

### Unit Tests:

- `test/docs_adr_links_test.exs` is the whole of the new test surface. It is a
  binding test, not a unit test of library behavior: it reads
  `Mix.Project.config()`, walks the published Markdown, and asserts the
  invariant in both directions.
- Edge cases the scan must handle, each present in the tree today: a bare
  sibling filename (`docs/adr/README.md` rows), a `docs/`-prefixed path
  (`README.md`, `CHANGELOG.md`), a `docs/`-relative path
  (`docs/architecture.md`), a `../`-relative path (the new `embedding.md`
  link), an absolute GitHub URL, a link with inline code in the link text
  (ADR-0011's research citation), and the same ADR cited twice in one file
  (`docs/architecture.md` cites 0011 at lines 50 and 130).
- Files that are not extras must be ignored: `docs/reference/ast.md:69` cites
  ADR-0011 relatively and is out of scope; if the scan reaches it, the scope
  filter is wrong.
- Coverage is unaffected - the change adds no `lib/` code, so the 90% per-file
  minimum in `coveralls.json` is not in play.

### Manual Testing Steps:

1. `mix docs` and open `doc/index.html`; confirm the Architecture group lists
   the index plus 0001, 0002, 0003, 0009, 0011 and nothing else.
2. From `doc/architecture-decision-records.html`, click one published row and
   one governance row; the first stays in hexdocs, the second goes to GitHub.
3. From `doc/embedding.html` and `doc/architecture.html`, click the ADR-0009
   and ADR-0011 citations; both resolve inside hexdocs.
4. Run the four sabotage mutations from Phase 2's Deferred Manual Verification
   and revert each.

## Open Questions

These are recorded rather than resolved because no human was available during
planning. Each has a default already chosen and implemented by the plan; none
blocks execution.

1. **Publish the language/ISA ADRs, or unpublish all of them?** The bead names
   the second option as a real alternative and calls the decision the user's.
   **Default taken: publish**, per the bead's own proposal - ADR-0002 and
   ADR-0003 are user- and porter-facing, and de-linking would leave 14
   citations poorer.
2. **Should the absolute URLs pin `main` or a version tag?** **Default taken:
   `blob/main`**, matching the only existing precedent in the tree
   (`docs/guides/embedding.md:51`). A tag would be more stable per release but
   would need updating at every release, and the release recipe does not do
   that today.
3. **Should `docs/reference/ast.md` be published too?** It cites ADR-0011 and
   is a reference page sitting outside `extras:`. **Default taken: no** - out
   of this bead's scope; worth its own bead.

## References

- Bead: `px-ir1`
- Source: the bead description's proposed rule and its stated alternative
- Related ADRs: `docs/adr/0003-the-elixir-implementation-leads-the-isa.md`
  (nothing here moves the ISA), `docs/adr/0005-worktree-parallelism-and-the-area-label-algebra.md`
  (`area:build` exclusivity, why this bead lands alone),
  `docs/adr/0009-the-compiled-envelope-carries-the-position-table.md` and
  `docs/adr/0011-casts-are-an-opcode.md` (the two being published)
- Binding-test practice: `docs/research/260808-px-9ab-sabotage-notes.md`
- Similar implementations: `test/predicator/isa_sync_test.exs:29-30` (the
  anti-vacuity literal and sabotage notes), `test/docs_examples_test.exs:1-20`
  (top-level docs test placement and module naming)
- Config under change: `mix.exs:85-118`

## Deferred Manual Verification

Deferred from --loop execution; confirm these manually before considering the
work fully verified:

**From Phase 1:**

- [ ] `mix docs` then open `doc/architecture-decision-records.html`: all eleven
      rows link somewhere, the five published numbers land on hexdocs pages and
      the six governance numbers land on GitHub
- [ ] ADR-0009 and ADR-0011 appear in the sidebar under the Architecture group,
      in number order with 0001-0003
- [ ] `doc/embedding.html`'s ADR-0009 link stays inside hexdocs
- [ ] No regressions in related features: the other extras render unchanged

**From Phase 2:**

The mechanical sabotage pass itself was performed during implementation and
passed on the first attempt for all four mutations (each went red naming the
offending file and target, then was reverted cleanly); the items below are
still listed verbatim per the plan's own convention, for the human-facing
record.

- [ ] Remove `docs/adr/0011-casts-are-an-opcode.md` from `mix.exs` `extras:` ->
      the relative-link test fails naming 0011 and both of its relative
      citation sites, `docs/architecture.md` and `docs/adr/README.md`. If the
      index is not among them, the resolve-then-classify ordering above was not
      implemented and the test is blind to the file it exists for
- [ ] Restore `docs/guides/embedding.md:51` to the absolute GitHub URL for
      ADR-0009 -> the absolute-link test fails naming `embedding.md` and 0009
- [ ] Add `docs/adr/0007-beads-for-issue-tracking.md` to `extras:` -> the
      governance test fails naming 0007
- [ ] Point one `docs/adr/README.md` row at a filename that does not exist ->
      the existence test fails naming that target
- [ ] A test that stays green under its mutation is a finding, not a note to
      skip: reshape the test rather than weakening the note
- [ ] The working tree is clean after the pass (`git status`) - every mutation
      reverted
