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

## Practice note: the stale-beam hazard

`mix`'s staleness check is mtime-based, so a mutate -> compile -> observe red
-> revert -> confirm green cycle that completes inside one second can leave
the *mutated* beam in place after the revert: the source reads correct,
`git status` is clean, and the module the next run loads is still the broken
one. Every later mutation in the batch is then judged against a stale module,
and its red proves nothing.

The symptom is an inexplicable red on clean source after the revert, which
reads like a failed revert. The existing "confirm green again" step does
catch it, but does not diagnose it.

This was hit on px-suw while re-verifying the seven binding tests.
`Predicator.Instructions.tier("load")` returned `{:ok, 2}` from a pristine
tree; five of Phase 1's six mutations produced plausible-looking but
worthless reds before it was caught. It was noticed only because one red
named tier 1 and `load` under a mutation that touched only the tier-6 row -
the wrong signature, not a wrong verdict.

The fix: run `MIX_ENV=test mix compile --force` after both the mutation and
the revert, and assert a green baseline before each mutation.

Files read at runtime rather than compiled in - `docs/isa.md`,
`conformance/**`, `mix.exs` - are not subject to this and need no forced
recompile. The hazard applies to mutations of Elixir source.

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

- 2026-08-11 (`px-qq6`): `test/predicator/conformance/values_test.exs`. The
  tagged encoding `Predicator.Conformance.Values` produces is an exported
  cross-language artifact in the same sense as the corpus - `conformance/
  README.md` documents it as the wire form a Ruby or JavaScript sibling reads
  - and the `describe "datetime canonicalization: ..."` block plus the
  `describe "from_json/1 - datetime precision canonicalization on decode"`
  block are what binds the fractional-seconds form (px-qq6) to the code.
  Nine files now.

  Sabotage pass verified 2026-08-11, two mutations, each reverted after:

  1. Dropped the `canonicalize_microsecond/1` call from `to_json/1`'s
     `%DateTime{}` clause (helper and the `from_json/1` call left in place).
     Reddened four: the `to_json/1` doctest for `~U[2026-08-06T12:00:00.5Z]`
     (`left: "...12:00:00.5Z", right: "...12:00:00.500000Z"`), the
     "DateTime with a non-zero sub-second component encodes as exactly six
     digits" test with the identical mismatch, and both encode-touching rows
     of the canonicalization `describe` block - the `.000000Z` case
     (`left: "...12:00:00.000000Z", right: "...12:00:00Z"`) and the `.5` case
     (same mismatch as above). 4 failures, exactly the predicted set.
  2. Dropped the call from `from_json/1`'s `"datetime"` clause instead
     (`{:ok, datetime, _utc_offset} -> {:ok, datetime}`). Reddened both
     hand-authored decode tests as predicted - `"...00.000Z"` decoded to
     `{0, 3}` instead of `{0, 0}`, `"...00.5Z"` decoded to `{500000, 1}`
     instead of `{500_000, 6}`. **It did not** redden the canonicalization
     `describe` block's own precision-field assertions, which is a finding
     worth recording rather than glossing over: those two tests call
     `to_json/1` first, and `to_json/1`'s own canonicalization (still intact
     under this mutation) always emits an already-canonical string - `DateTime.
     from_iso8601/1` sets precision `{0, 0}` for a bare `Z` and `{us, 6}` for
     six digits with no help from `from_json/1`'s own call. A round trip
     through `to_json/1` therefore cannot discriminate decode-side
     canonicalization at all; it is the two hand-authored-JSON tests, which
     call `from_json/1` directly on a non-canonical string, that are the only
     tests actually binding this half of the decision. This is the same shape
     of finding as the `px-ir1` entry above: a test that reads as covering a
     direction and does not.

- 2026-08-11 (`px-kbe`): `test/predicator/visitor_clause_coverage_test.exs`.
  `Predicator.Parser`'s `t:visitable/0` typespec is the enumerated contract
  for what `StringVisitor.do_visit/2` and `InstructionsVisitor.visit_annotated/2`
  must each handle (ADR-0004: an unsupported node is an error value, never a
  `FunctionClauseError`); nothing at compile time keeps a visitor's clause
  heads in sync with that typespec, so a vacuous version of this test would
  ship the same silent gap px-aen's manual verification found and closed by
  hand. Ten files now.

  Sabotage pass verified 2026-08-11. Added a throwaway `{:while, ast(),
  block(), position()}` member to `ast/0`: all three tests went red, the
  constructor-count test naming `:while` as the 23rd constructor and both
  coverage tests naming `:while` as missing a clause in their respective
  visitor. Reverted, confirmed green. Separately, renamed
  `string_visitor.ex`'s `{:duration, ...}` `do_visit/2` clause head to
  `:durationx`: the missing-direction assertion named `:duration`; verified
  independently (ExUnit stops at a test's first failed assertion) that the
  parsed clause-tag set contained `:durationx` and not `:duration`, confirming
  the extra-direction assertion would have caught it too. Reverted, confirmed
  green; `git diff lib/` empty throughout except during the sabotage window.

- 2026-08-12 (`px-3so.4`): `test/predicator/visitor_clause_coverage_test.exs`,
  re-taken. `px-kbe`'s pass above used `{:while, ast(), block(), position()}`
  as its mutation target - a fiction at the time, since `:while` did not yet
  exist as an AST tag. This bead makes `while` real: `Parser.parse_statement/1`
  now produces `{:while, condition, body, pos}`, `InstructionsVisitor` lowers
  it, and `@constructor_count` moves to `23`. The old mutation is no longer a
  probe of anything - `:while` is a genuine constructor with genuine clauses in
  both visitors, so "mutate to add `:while`" would no longer redden the test at
  all. The three sabotage comments in the test file were rewritten to a fresh
  throwaway tag, `:sabotage_probe`, and the pass re-run against it.

  Sabotage pass verified 2026-08-12. Added a throwaway `{:sabotage_probe,
  ast(), block(), position()}` member to `ast/0`: all three tests went red -
  the constructor-count test naming `:sabotage_probe` as the 24th constructor
  (`got 24`, full sorted list including both `:while` and `:sabotage_probe`),
  and both coverage tests naming `:sabotage_probe` as missing a clause in
  their respective visitor (`StringVisitor` and `InstructionsVisitor`).
  Reverted, confirmed green; `git diff lib/` empty throughout except during
  the sabotage window. `:while` appearing correctly in the constructor list
  and in neither "missing" list during this run is itself evidence the new
  clauses in both visitors and the typespec are wired together correctly.

  Re-verified after rebasing onto `px-3so.5`, which landed `StringVisitor`'s
  real `{:if, ...}` and `{:block, ...}` clauses and conflicted with this bead
  in the same file's moduledoc. The merged moduledoc asserts something neither
  side asserted alone - that *both* visitors now cover every constructor,
  `:while` included - so the pass was taken again against the merged file
  rather than carried over. Same outcome, and the `StringVisitor` failure
  naming only `:sabotage_probe` as missing is the evidence for the merged
  claim: had the conflict resolution dropped a clause, that list would name it
  too.

- 2026-08-14 (`px-wy8`): `test/predicator/conformance/ratchet_registry_test.exs`,
  addendum. This is not a new file in the class - the file has been a binding
  test since px-9ab and has been in `gate.sabotage.test_roots` since px-lxs -
  so the count does not move; ten files, still. What changed is a new assertion
  inside an already-listed file: `conformance/RATCHET.md` rule 3 now states
  normatively that `entries` holds at most one entry per `(case_id, surface)`
  pair, and a sixth `describe` block binds it, so this is a fresh sabotage pass
  on that assertion, not a class extension.

  The mutation: inserted a byte-identical copy of
  `{"case_id":"comparison/gt-int-true","surface":"compiler","tier":1},` directly
  beneath the original in `conformance/examples/registry.example.json`. Ran
  `mix test test/predicator/conformance/ratchet_registry_test.exs`: 6 tests, 1
  failure - exactly the new uniqueness test, "no (case_id, surface) pair appears
  in entries more than once", with the message naming
  `[{"comparison/gt-int-true", "compiler"}]` and nothing else failing. Reverted
  with `git checkout -- conformance/examples/registry.example.json`; re-ran the
  same command: 6 tests, 0 failures; `git status --porcelain` reported no diff
  for the file.

  The isolation to exactly one test depends on `reencode/1`
  (`test/predicator/conformance/ratchet_registry_test.exs:181-198`) re-emitting
  `entries` in parse order rather than sorting it - the canonical-encoding test
  therefore re-encodes the duplicated line to itself and stays green under this
  mutation. If px-2gx's sortedness follow-on lands and `reencode/1` (or a
  companion assertion) starts enforcing order, this pass is stale and must be
  re-run rather than carried forward, because a sort-order check could catch
  this same mutation for a different reason and the "exactly one test goes red"
  claim would need re-verifying.

- 2026-08-14 (`px-ty0`): `test/predicator/parser_format_token_coverage_test.exs`,
  new file. `Predicator.Parser`'s private `format_token/2` renders one
  `Predicator.Lexer.t:token/0` token type into every "expected X but found Y"
  message and carries no catch-all clause, so a token type with no matching
  clause raises `FunctionClauseError` instead of returning the `ParseError`
  value ADR-0004 requires - the same defect class as
  `visitor_clause_coverage_test.exs` guards for the two AST visitors, one
  level down the pipeline. This has already happened twice by hand: px-yoq's
  `:string`-token arity mismatch (`b49dd97`) and px-ty0's own notes, which
  found `:fractional_number` (fixed on `6f78179`, same branch) and `:dot`
  (fixed by this bead) both missing by literally counting clauses against
  token types. A vacuous version of this test would ship the same kind of
  silent gap a third time. Eleven files now.

  Sabotage pass verified 2026-08-14, three mutations, `MIX_ENV=test mix
  compile --force` run after every mutation and every revert per the
  stale-beam hazard noted above, green baseline confirmed before each:

  1. Removed the `defp format_token(:dot, _value), do: "'.'"` clause from
     `lib/predicator/parser.ex`. Reddened the clause-count assertion in the
     "versus" test: "expected 55 distinct format_token/2 clause tags ...,
     got 54", `:dot` absent from the listed tags. (ExUnit stops at a test's
     first failed assertion, so this fired before the "missing" assertion was
     ever reached.) Reverted, confirmed green.
  2. Renamed that clause's head to `format_token(:dotx, _value)` instead -
     this holds the clause count at 55, so the run reaches the
     "missing"/"extra" comparison instead. The "missing" assertion went red
     naming exactly `[:dot]`. Verified independently (again, ExUnit stops at
     the first failure) that the parsed clause-tag set contained `:dotx` and
     not `:dot`, confirming the "extra" assertion would have caught it too.
     Reverted, confirmed green.
  3. Added a throwaway `| {:sabotage_probe, pos_integer(), pos_integer(),
     pos_integer(), binary()}` member to `Lexer.token/0`'s union. Both tests
     in the file went red: the token-type-count test ("got 56",
     `:sabotage_probe` present in the listed tags) and the "versus" test's
     "missing" assertion, naming exactly `[:sabotage_probe]`. Reverted,
     confirmed green; `git status --porcelain` reported no diff for
     `lib/predicator/lexer.ex` throughout except during the sabotage window.

## Enforcement: gate.sabotage, from 2026-08-12 (px-lxs)

- **The discipline is now enforced, not only written down.** `px-lxs` declared
  `gate.sabotage` in `.claude/wurk.json`'s `gate` object, naming all ten files
  in this document's class as `test_roots` (the original seven above plus the
  three "Additions to the class" entries) and this repo's ExUnit
  `test_pattern`. The ten paths, spelled out rather than brace-expanded so
  they read as literal filenames in both places:
  `test/predicator/isa_sync_test.exs`,
  `test/predicator/conformance/corpus_freshness_test.exs`,
  `test/predicator/conformance/opcode_coverage_test.exs`,
  `test/predicator/conformance/function_coverage_test.exs`,
  `test/predicator/conformance/schema_validation_test.exs`,
  `test/predicator/conformance/ratchet_registry_test.exs`,
  `test/predicator/conformance/package_boundary_test.exs`,
  `test/docs_adr_links_test.exs`,
  `test/predicator/conformance/values_test.exs`, and
  `test/predicator/visitor_clause_coverage_test.exs`.
  `ruby ~/.claude/skills/wurk:kit/scripts/gate.rb` now reports
  `data.sabotage.enabled: true` on every run, and a diff touching a listed file
  with an undocumented `test "..."` declaration surfaces as a
  `sabotage_note_missing` warning. The scan is a report, never a gate - it
  never flips `ok` - so a present note is still not evidence a mutation was
  actually run; that judgment stays with `/wurk:commit`'s Step 0.

- **This reverses `px-hhu`'s "leave off" row.**
  `docs/plans/260812-px-hhu-wurk-config-catchup.md:436` left `gate.sabotage`
  unset with the stated reason that narrowing the scan to the binding-test set
  "would need `test_roots` granularity the field does not have." That claim
  was false: wurk `wu-4r7` settled it as a documentation gap, not a real kit
  limitation. `test_roots` entries are handed verbatim to `git diff` as a
  pathspec, and a pathspec accepts exact file paths and bare globs, not only
  directory prefixes - so the narrow allowlist form (ten exact paths, nothing
  else) worked with no kit change. The landed plan is left as-is; it is a
  dated record of what was decided and why, not a live document, and this
  section is where the reversal is recorded instead.

- **`test_roots` is a second copy of this document's class list, and the two
  must move together.** A binding test added to a file not named in
  `gate.sabotage.test_roots` is invisible to the scan - it is simply not among
  the files the scan diffs. Extending the "Additions to the class" section
  above without also adding the new file's path to `test_roots` in
  `.claude/wurk.json` leaves the addition documented but unenforced, and the
  scan's continued silence about that file is not evidence it is clean. The
  two lists are added to in the same change, every time.

- **Phase 1 hand-verification, 2026-08-12.** Both directions of the scan were
  probed by hand, each as a real commit reset afterward (the scan reads
  `main...HEAD`, so uncommitted work is invisible to it).

  Negative probe: committed `test/predicator/scratch_probe_test.exs`
  containing one undocumented `test "probe" do`, a file outside
  `test_roots`. `ruby ~/.claude/skills/wurk:kit/scripts/gate.rb --profile loop`
  reported:

  ```json
  "sabotage":{"enabled":true,"reason":null,"missing":[]}
  ```

  with no `sabotage_note_missing` warning - an ordinary test outside the
  allowlist is not flagged, which is the narrow form's whole point. Reset with
  `git reset --hard HEAD~1`.

  Positive probe: committed an undocumented `test "probe" do` line inside
  `test/predicator/isa_sync_test.exs`, a listed file. The same command
  reported:

  ```json
  "sabotage":{"enabled":true,"reason":null,"missing":[{"file":"test/predicator/isa_sync_test.exs","text":"test \"probe\" do"}]}
  ```

  with the warning `test/predicator/isa_sync_test.exs: test "probe" do has no
  \`# sabotage:\` note directly above it (a present note is not evidence the
  mutation was run)` - exactly one entry, naming the file and the line. Reset
  with `git reset --hard HEAD~1`. The negative probe alone could not
  distinguish "correctly not flagged" from "scan silently doing nothing";
  running both directions is what rules that out. `git status --porcelain`
  was empty and `git log --oneline -1` was back at the manifest commit after
  both probes, confirming no throwaway commit or probe file survived.
