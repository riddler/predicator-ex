# Does this repo adopt statifier's sabotage-note practice?

Bead: px-9ab
Date: 2026-08-08
Decision: **adopt, narrowly - sabotage notes are required on the binding tests
that keep this repo's exported artifacts honest, and on nothing else.
Statifier's broad form (every test asserting `lib/` behavior) is rejected for
this repo.**

This is workflow governance, not architecture. It changes no instruction, no
opcode, and no grammar, so it **does not move the ISA** and it is not
ADR-shaped: every existing ADR is about the language or the architecture, and
test-writing convention already lives in CLAUDE.md's Conventions section. No
ADR was written, matching the call px-phw made for the `area:conformance`
label.

## The question

px-9ab's argument, as filed: once suite tests become the SOURCE of an exported
specification, a vacuous test ships a wrong specification to siblings as
normative - which is the argument for adopting statifier's sabotage notes here,
narrowly scoped to corpus-source tests. That is a recommendation with a real
cost, and the bead escalates the decision rather than making it.

## Ground truth: the premise moved

The bead's premise was written before px-35i.4 chose its mechanism, and the
mechanism it chose changes the shape of the risk.

- **The ExUnit suite is not the corpus's source.** px-35i.4's plan
  (`docs/plans/260807-px-35i.4-conformance-corpus.md`, "Implementation
  Approach") rejected static extraction from the suite (~25% coverage,
  fragile) and runtime capture (unstable ids) in favour of authored JSON
  completed by the real pipeline. A vacuous ExUnit test therefore ships
  nowhere. `mix corpus.coverage` reads the suite as an authoring checklist,
  which is advisory and fails no gate.
- **An authored case cannot be vacuous in the relevant sense.** The generator
  (`lib/mix/tasks/corpus.generate.ex`) computes the real result and fails
  loudly when an authored `expected` disagrees; a case with no `expected`
  still ships the value the real evaluator produced. Statifier's own testing
  doc reaches the same conclusion about its corpus and exempts it:
  `statifier-ex/docs/testing.md:119-121` - "the corpus is sabotage-proof by
  construction, since a broken interpreter shows up as a failing conformance
  test immediately".

What is exposed is a narrower and enumerable class: the **binding tests** that
keep the exported artifacts honest, where a vacuous pass ships a wrong
specification to siblings with nothing noticing. In this checkout that class
is `test/predicator/isa_sync_test.exs` plus
`test/predicator/conformance/{corpus_freshness,opcode_coverage,function_coverage,schema_validation,ratchet_registry,package_boundary}_test.exs`
- verified against the current tree; all seven files exist under those exact
names as of this checkout.

## Ground truth: the repo already does this, ad hoc, three times

- `test/predicator/isa_sync_test.exs:29-30` - `@opcode_count 27`, with the
  comment "vacuously - by asserting this literal count rather than only
  'non-empty'".
- `test/predicator/conformance/package_boundary_test.exs:31-32` - "assertion
  below vacuous", `assert length(@shipped_lib_files) > 10`.
- `test/predicator/conformance/ratchet_registry_test.exs:47` - "the test below
  would pass vacuously".

Each is a hand-written anti-vacuity guard with a hand-written comment
explaining why. Nothing names the pattern or requires it going forward.

## Ground truth: statifier's practice, as written

`statifier-ex/docs/testing.md:78-134` and `statifier-ex/CLAUDE.md:125-129`:
every new or changed test asserting `lib/` behavior is sabotaged (break the
code, confirm red, revert) and carries a one-line
`# sabotage: <what was broken> -> red` note above the `test` line; harness
plumbing states an exemption rather than omitting the line
(`# sabotage: n/a - ...`). Generated corpus files are exempt. The doc names
the cost plainly: "This makes writing a test meaningfully slower, and that is
the trade being made deliberately."

## The decision

Adopt, narrowly. Sabotage notes are required on the seven binding-test files
enumerated above, and on nothing else.

The practice on those seven: break what the test covers with one plausible
mutation, confirm it goes red for the right reason, revert, and record the
mutation in one line above the `test`:

```elixir
# sabotage: manifest tier table drops tier 3 -> red
```

A binding test that stays green under every plausible mutation is a finding,
not a note to skip.

The reasoning, in descending weight:

1. **The premise moved, and what is left is narrow and enumerable.** The
   bead's argument is that suite tests became the source of an exported
   specification. px-35i.4 chose a different mechanism: the corpus's source is
   authored JSON in `conformance/cases/*.json`, completed by the real compiler
   and evaluator, and an authored `expected` that disagrees fails generation
   loudly. A vacuous ExUnit test therefore ships nothing to siblings. What
   *can* ship a wrong specification is a vacuous binding test - one that
   claims to bind a generated artifact to its source and in fact asserts
   nothing. That class is seven files, not the whole suite.

2. **The repo already does this, three times, without a name for it.**
   `isa_sync_test.exs:29-30` guards with a literal `@opcode_count 27` and a
   comment saying why; `package_boundary_test.exs:31-32` and
   `ratchet_registry_test.exs:47` each carry a hand-written anti-vacuity guard
   and a comment. Codifying a practice already followed ad hoc costs almost
   nothing and stops the next binding test from being the one that forgets.

3. **Statifier's own doc supports the narrowing.**
   `statifier-ex/docs/testing.md:119-121` exempts its generated corpus because
   "the corpus is sabotage-proof by construction, since a broken interpreter
   shows up as a failing conformance test immediately". The same construction
   argument holds here, one level up: the corpus is regenerated from the real
   pipeline and byte-compared, so it cannot silently disagree with the code.
   It is the bindings that can.

4. **The broad form's cost is not payable here and buys less.** Predicator's
   suite is large and predominantly pure-function assertions over a lexer,
   parser, compiler, and evaluator - a domain where a vacuous test is both
   less likely and less consequential, because a wrong answer surfaces as a
   wrong answer rather than as a silent gap. Statifier names the cost plainly
   ("meaningfully slower"), and it is paying it for an interpreter whose
   correctness is judged largely by conformance corpora. Applying it to every
   new test here would tax hundreds of low-risk tests to protect seven
   high-risk ones.

## The cost of the decision as taken

- Every new test in the binding class costs a real mutation, a confirmed red,
  a revert, and a one-line note. That is a few minutes each, a handful of
  times a year.
- The class boundary needs judgement at the margin, and a boundary judged
  wrongly is worse than no boundary because it looks like coverage. The
  mitigation is that the class is defined by an enumerated list of files in
  CLAUDE.md, not by a description, so extending it is a visible edit.
- Seven existing binding tests will not carry notes until the follow-on bead
  lands, so for that window the practice is stated but not fully evidenced.

## What would overturn it

A vacuous non-binding test that ships a wrong answer to a sibling would argue
for widening the class. A binding test whose sabotage note is unwritable
because no single reasonable mutation reddens it would argue the test is the
wrong shape, not the rule.

## What was changed

- `CLAUDE.md` - a "Binding tests carry a sabotage note" bullet in Conventions,
  pointing at this note for the file list and the reasoning.
- A follow-on bead, px-suw, which depends on px-9ab and so is blocked until it
  lands, to retrofit sabotage notes onto the seven existing binding tests -
  out of scope here because it touches `test/predicator/conformance/**` and
  `test/predicator/isa_sync_test.exs`, outside px-9ab's predicted
  `.claude/**` + `CLAUDE.md` + `docs/` blast radius.

No ratchet registry, ratchet mix task, or ratchet step is added anywhere by
this decision; `conformance/RATCHET.md` and the sibling-repo ratchet mechanics
are unaffected.

## Additions to the class

- 2026-08-10 (`px-ir1`): `test/docs_adr_links_test.exs`. The published
  documentation set is an exported artifact in the same sense as the corpus -
  hexdocs is what a consumer reads - and this test binds `mix.exs`'s `extras:`
  list to the ADR citations in the pages it publishes. A vacuous pass ships
  404s on the front door with nothing noticing, which is the class's test.
  Eight files now.

  Sabotage pass verified 2026-08-10. All four mutations went red naming the
  offending file and ADR number: dropping `0011` from `extras:`, restoring
  `docs/guides/embedding.md`'s ADR-0009 link to its absolute form, adding
  governance ADR-0007 to `extras:` (red twice - the governance guard and the
  absolute-link test caught it independently), and pointing an index row at a
  filename that does not exist.

  **A mutation that looks discriminating and is not.** The obvious way to
  check that `docs/adr/README.md` is covered - unpublish `0011` and expect the
  failure to name both of its relative citation sites - cannot work, because
  the assertion sits inside a `for` comprehension and fail-fasts on whichever
  site it reaches first. It named `docs/architecture.md` alone, and the index's
  absence from that message was evidence of nothing.

  The index is the file this test exists for, and it is the hard case: its
  targets are bare sibling filenames (`0011-casts-are-an-opcode.md`) with no
  `adr/` segment in the raw text, so a classifier that matches before resolving
  is blind to every row of it while still passing. Discriminating between
  "covered" and "blind" needs the index isolated as the *only* relative
  citation left: unpublish `0011` **and** temporarily rewrite
  `docs/architecture.md`'s two `0011` links to absolute form. The failure then
  reads `docs/adr/README.md links ADR-0011 (0011-casts-are-an-opcode.md)`,
  which is the resolve-then-classify ordering proving itself. That is the
  mutation to re-run if this test is ever reshaped; the single-mutation form is
  a weaker check wearing the same clothes.
