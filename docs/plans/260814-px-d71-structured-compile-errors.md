# Structured Compile Errors Implementation Plan

## Overview

Beads issue: `px-d71`

Implement ADR-0015: the error arm of all six compile entry points becomes a
structured value instead of a formatted binary. A parse failure is reported as
the existing `%Predicator.Errors.ParseError{}` - the parser's bare message in
`:message`, `{line, column}` in `:position`, and no location text appended to
the message. A compiler-stage failure keeps its own struct instead of being
flattened to `error.message`. `compile!/1` still raises, with its text composed
from the struct's fields.

This is a breaking change to a documented public return type on six functions,
so it targets release **8.0.0**. It does **not** move the ISA (stays at 6),
adds no opcode, and produces no corpus diff: a successful compile emits a
byte-identical instruction list. Release mechanics are out of scope for this
plan - no version bump, no changelog promotion, no tag.

## Current State Analysis

**The whole library change is two private helpers.** `lib/predicator.ex:881`
and `lib/predicator.ex:899` are the only construction sites for the compile
error arm, and every one of the six entry points routes through one of them:

| Entry point | `lib/predicator.ex` | Helper |
|---|---|---|
| `compile/1` | 716-719 | `build_instructions_result/1` |
| `compile_program/1` | 798-801 | `build_instructions_result/1` |
| `compile_with_positions/1` | 743-746 | `build_compiled_result/1` |
| `compile_with_spans/1` | 770-773 | `build_compiled_result/1` |
| `compile_program_with_positions/1` | 821-824 | `build_compiled_result/1` |
| `compile_program_with_spans/1` | 860-863 | `build_compiled_result/1` |

Both helpers flatten the parser's 4-tuple the same way
(`lib/predicator.ex:881-883` and `:899-901`):

```elixir
defp build_compiled_result({:error, message, line, column}) do
  {:error, "#{message} at line #{line}, column #{column}"}
end
```

and `build_instructions_result/1` additionally throws away a compiler-stage
struct at `lib/predicator.ex:892-897`:

```elixir
defp build_instructions_result({:ok, ast}) do
  case Compiler.to_instructions(ast) do
    {:error, error} -> {:error, error.message}
    instructions -> {:ok, instructions}
  end
end
```

**The rest of the façade already returns structs.** `evaluate/3`, `execute/3`,
`context_location/3`, and `context_assign/4` all build a `ParseError` from the
same 4-tuple via `ParseError.new/3` (`lib/predicator/errors/parse_error.ex:39`).
The compile arm is the single holdout - which is exactly ADR-0015's argument.

**The compiler-stage error arm is currently unreachable in practice.**
`Compiler.to_instructions/2` is specced `[[binary() | term()]] | {:error,
struct()}` (`lib/predicator/compiler.ex:56-58`), but
`InstructionsVisitor.visit/2` is specced and implemented to return only an
instruction list (`lib/predicator/visitors/instructions_visitor.ex:83-88`), and
grep finds no `{:error, ...}` return anywhere in that module. So today's
`{:error, error} -> {:error, error.message}` line is defensive, not exercised.
Returning the struct unchanged keeps it defensive and does not make it any more
or less reachable - it is a strictly smaller expression than what is there now.

**In-repo consumers of the compile error arm** (the ones that break if the arm
changes and nothing else is touched):

- `lib/predicator/conformance/generator.ex:333-336` - interpolates the error
  binary into a message string. This is the one place where a struct would
  raise `Protocol.UndefinedError` at runtime rather than merely mismatch, so it
  must move in the same phase.
- `lib/predicator/conformance/coverage.ex:218` - matches `{:error, _message}`
  and discards it. Behaviourally safe; the variable name becomes wrong.
- `test/predicator_test.exs:219-227` (the `compile/1` error test), `:257`,
  `:307` (cross-family equality assertions - these keep holding, since two
  identical structs compare equal), `:528-546` (`compile!/1`).
- `test/predicator/execute_test.exs:253-256` and `:330-333` - one test title
  literally says "returns a binary error".
- `test/predicator/reserved_words_test.exs` - 11 assertions of the form
  `{:error, "#{@msg} at line 1, column N"}` (lines 36, 58, 87, 109, 130, 180,
  203, 226, 259, 281, 303). Each already sits beside a `Predicator.evaluate/3`
  test asserting `%ParseError{message: ..., position: {1, N}}`, which is the
  exact shape to copy.
- `test/predicator/equals_grammar_break_test.exs:31-34` - same pattern, same
  sibling to copy from.

**Doctests that must change.** `test/docs_examples_test.exs` runs
`doctest_file/1` over `README.md`, `docs/reference/language.md`, and four
guides, and `mix quality` runs the module doctests in `lib/`. Two `iex>`
examples show the old binary directly - `lib/predicator.ex:710-711`
(`compile/1`) and `lib/predicator.ex:790-791` (`compile_program/1`). No
doctested `.md` file shows a compile error today (`docs/reference/language.md`
shows parse errors through `evaluate/3` and the raw `parse_program/2` 4-tuple,
neither of which moves), so the markdown side has no forced edit - only a
voluntary addition, in Phase 2.

**The px-iov paragraph.** All six `@doc`s end with a paragraph pointing callers
at `parse/2` / `parse_program/2` "for the line and column as data"
(`lib/predicator.ex:713-714`, `740-741`, `767-768`, `793-796`, `816-819`,
`853-855`). It is false after this change and gets rewritten, not deleted -
those functions keep their 4-tuple and are not deprecated.

**Other queued breaking work.** ADR-0015's open question asks the
implementation bead to check whether 8.0 should carry another break. The open
queue is `px-2gx` (a test-binding bug, not breaking) and `px-dmt` ("Gives parse
errors a source span"), which ADR-0015 explicitly says **must not** be folded
into this release. So there is nothing to pull in: 8.0 carries this change
alone. That question is settled by this plan and needs no re-litigating at
release time.

## Desired End State

All six compile entry points return `{:ok, ...} | {:error, struct()}`. A parse
or tokenize failure comes back as `%Predicator.Errors.ParseError{message:
<parser message, no location text>, position: {line, column}}`, identical to
what `evaluate/3` returns for the same source. A compiler-stage failure comes
back as whatever struct `Compiler.to_instructions/2` produced. `compile!/1`
raises a `RuntimeError` whose text is unchanged from today
(`"Compilation failed: <message> at line L, column C"`). The `ParseError`
moduledoc example no longer shows a location baked into `:message`.
`CHANGELOG.md` documents the migration in both directions under
`## [Unreleased]` -> `### Changed`. Full `mix quality` is green, the ISA
version reported by `Predicator.isa_version/0` is still `6`, and
`conformance/` has no diff.

Verify with: `mix quality` green; `git status` showing no change under
`conformance/`; and the manual checks in each phase.

### Key Discoveries:

- Both construction sites are private and adjacent: `lib/predicator.ex:881-883`
  and `lib/predicator.ex:899-901`. Editing them reaches all six functions.
- `ParseError.new/3` (`lib/predicator/errors/parse_error.ex:39`) already takes
  exactly the `(message, line, column)` shape the helpers hold.
- `lib/predicator/errors/parse_error.ex:18` bakes `" at line 1, column 10"`
  into the moduledoc example's `:message`, which is wrong about today's
  behaviour as well as tomorrow's (ADR-0015, Decision bullet 2).
- `lib/predicator/conformance/generator.ex:333-336` string-interpolates the
  error value; a struct there is a runtime crash, not a silent mismatch.
- `test/predicator/reserved_words_test.exs` and
  `test/predicator/equals_grammar_break_test.exs` each pair a `compile/1` test
  with an `evaluate/3` test asserting the `%ParseError{}` shape - the pattern to
  copy is already in the same file.
- ADR-0015 fixes the design: existing struct (not a new `CompileError`), bare
  message, `{:error, struct()}` as the declared spec, all six together,
  `compile!/1` keeps raising per ADR-0004's bang carve-out.
- `coveralls.json` sets `minimum_coverage: 90` on the total.

## What We're NOT Doing

- **Parse-error spans.** `ParseError` gains no `:span` field, the parser's
  `{:error, message, line, column}` tuple is unchanged, and the end-of-input
  `1, 1` position bug is untouched. That is ADR-0015's four-step follow-on and
  bead `px-dmt`, and it is a major version of its own because it changes
  `parse/2` and `parse_program/2`.
- **`Predicator.Errors.format/1`.** ADR-0015 records it as an open question and
  excludes it from the decision because it is additive and can land any time.
  The CHANGELOG shows callers the one-line re-format instead. Declining it here
  is deliberate, not an oversight.
- **A `:stage` field distinguishing lexical from syntactic failures.** Also an
  ADR-0015 open question, also additive, and nothing needs it yet.
- **A new `CompileError` struct.** ADR-0015 rejects it: one event would get two
  struct types chosen by which door the caller came through.
- **Any change to a success arm.** `compile/1` still returns a bare instruction
  list, the four `%Compiled{}` functions still return the envelope, and
  `%Compiled{}` is untouched. ADR-0009 is not reopened.
- **Deprecating `parse/2` or `parse_program/2`.** They keep the 4-tuple.
- **Release mechanics.** No `@version` bump in `mix.exs`, no promotion of
  `## [Unreleased]`, no tag, no `mix hex.publish`. `CLAUDE.md`'s authority table
  gates all of those on an explicit human request naming the version.
- **Making `build_compiled_result/1` handle a compiler-stage error.** Its
  `Compiler.to_instructions_with_segment_positions/2` call is specced with an
  `{:error, struct()}` arm (`lib/predicator/compiler.ex:117-120`) that the
  helper does not match on today, and does not match on after this change
  either. That is a pre-existing gap in an unreachable arm; fixing it would be
  scope creep into the compiler's spec surface and belongs in its own bead if
  it is ever worth doing. Noted here so a reviewer sees it was seen.
- **Editing historical documents.** `docs/plans/*` and `docs/research/*` quote
  the old binary in dozens of places. They are dated records of what was true
  when they were written and are left alone; only `docs/architecture.md`,
  `docs/reference/language.md`, `README.md`, and `CHANGELOG.md` are live.

## Implementation Approach

Two phases, split at the one seam that keeps both sides gate-green.

**Phase 1 is atomic by construction.** The moment either helper returns a
struct, every assertion on the binary goes red - so the helper edit, the spec
and doc updates, the `compile!/1` recomposition, the `ParseError` moduledoc
fix, the two conformance call sites, and every test assertion have to land in
one commit. Splitting them would leave an intermediate `mix quality` red, which
is exactly what the phase-sizing rule forbids.

**Phase 2 is the narrative surface**, which is green either way: `CHANGELOG.md`,
`docs/architecture.md`, and a new doctested example in
`docs/reference/language.md`. None of it is load-bearing for the tests in
Phase 1, and all of it is verifiable on its own (the language.md example is a
real doctest, so `mix quality` decides it).

No `## ISA Impact` section: this change adds, removes, renames, and alters
exactly zero opcodes, which is the condition `.claude/wurk/plan.md` states for
including it.

---

## Phase 1: The error arm becomes a struct

### Overview

Both helpers return structured values; the six specs, the six `@doc`s, the two
doctests, `compile!/1`, the `ParseError` moduledoc, the two conformance call
sites, and every test assertion on the old binary move with them. After this
phase the library's behaviour is final and the gate is green.

### Changes Required:

#### 1. The two construction sites

**File**: `lib/predicator.ex`
**Changes**: Alias `ParseError` if it is not already aliased in this module
(it is - it is used by `evaluate/3`'s parse arm), then:

```elixir
@spec build_compiled_result(
        {:ok, Parser.ast() | Parser.program()}
        | {:error, binary(), pos_integer(), pos_integer()}
      ) :: {:ok, Compiled.t()} | {:error, struct()}
defp build_compiled_result({:ok, ast}) do
  {instructions, positions, segment_positions} =
    Compiler.to_instructions_with_segment_positions(ast)

  {:ok, Compiled.new(instructions, positions, segment_positions)}
end

defp build_compiled_result({:error, message, line, column}) do
  {:error, ParseError.new(message, line, column)}
end

@spec build_instructions_result(
        {:ok, Parser.ast() | Parser.program()}
        | {:error, binary(), pos_integer(), pos_integer()}
      ) :: {:ok, Types.instruction_list()} | {:error, struct()}
defp build_instructions_result({:ok, ast}) do
  case Compiler.to_instructions(ast) do
    {:error, error} -> {:error, error}
    instructions -> {:ok, instructions}
  end
end

defp build_instructions_result({:error, message, line, column}) do
  {:error, ParseError.new(message, line, column)}
end
```

The comments above each helper (`lib/predicator.ex:865-869` and `885-887`) say
"becomes a `%Compiled{}` or a binary error" / "an instruction list or a binary
error"; update the wording to say a structured error.

#### 2. The six specs and docs

**File**: `lib/predicator.ex`
**Changes**: each of the six `@spec`s changes its error arm from
`{:error, binary()}` to `{:error, struct()}` - lines 716, 743, 770, 798, 821,
860. In each `@doc`:

- Replace the px-iov closing paragraph ("The error arm is a formatted binary;
  a caller that wants the line and column as data can call `parse/2`
  directly...", and the program-family variant) with a paragraph stating that
  the error arm is a `%Predicator.Errors.ParseError{}` carrying the parser's
  message in `:message` and `{line, column}` in `:position` - the same struct
  `evaluate/3` returns for the same source - and that `parse/2` /
  `parse_program/2` remain available for callers wanting the raw 4-tuple.
- `compile/1`'s `## Returns` list (`lib/predicator.ex:701-702`) changes
  `{:error, message}` to `{:error, error}` with the struct named.
- The two error doctests become, respectively:

```elixir
    iex> {:error, error} = Predicator.compile("score >")
    iex> {error.message, error.position}
    {"Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input", {1, 8}}
```

```elixir
    iex> {:error, error} = Predicator.compile_program("x =")
    iex> {error.message, error.position}
    {"Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input", {1, 4}}
```

Use the exact messages the parser emits; if the literal wraps past the line
limit, `mix format` decides the layout, and the doctest must be copied from a
real `iex -S mix` run rather than from this plan.

#### 3. `compile!/1`

**File**: `lib/predicator.ex` (1012-1018)
**Changes**: compose the raised text from the struct so it is byte-identical to
today's:

```elixir
def compile!(expression) when is_binary(expression) do
  case compile(expression) do
    {:ok, instructions} -> instructions
    {:error, error} -> raise "Compilation failed: #{describe_compile_error(error)}"
  end
end

# A parse failure carries a point position, which today's message text
# includes; a compiler-stage struct may not, so the location clause is
# separate rather than assumed.
@spec describe_compile_error(struct()) :: binary()
defp describe_compile_error(%{message: message, position: {line, column}}),
  do: "#{message} at line #{line}, column #{column}"

defp describe_compile_error(%{message: message}), do: message
```

The second clause is unreachable through the public façade today (a
`ParseError` always has a position, and the compiler-stage arm never fires), in
the same way the old `{:error, error.message}` line was. If coverage drops
below `coveralls.json`'s 90% because of it, collapse the two clauses into one
that matches only the `ParseError` shape rather than lowering the threshold -
`CLAUDE.md` forbids weakening the gate.

#### 4. The `ParseError` moduledoc example

**File**: `lib/predicator/errors/parse_error.ex` (15-21)
**Changes**: drop the `" at line 1, column 10"` from the example's `:message`
so the struct shows a bare message beside its `:position`. It is a fenced
example, not an `iex>` doctest, so nothing executes it - correctness here is a
review judgment. Consider also adding one sentence to the `## Fields` list
saying `:message` never contains the location, since that is the invariant this
bead establishes.

#### 5. The two conformance call sites

**File**: `lib/predicator/conformance/generator.ex` (333-336)
**Changes**: the interpolation is a runtime crash with a struct, so:

```elixir
{:error, error} ->
  {:error,
   "source #{inspect(source)} failed to compile: #{error.message}"}
```

Keep or drop the location in that operator message as reads best; the generator
message is developer-facing tooling output, not a public contract.

**File**: `lib/predicator/conformance/coverage.ex` (218)
**Changes**: rename `{:error, _message}` to `{:error, _error}`. Behaviourally
inert; it keeps the name honest.

#### 6. Every test assertion on the binary

**Files**:
- `test/predicator_test.exs` - the `compile/1` error test (219-227) asserts on
  a struct; the `compile_with_positions/1` == `compile/1` and
  `compile_with_spans/1` == `compile/1` equalities (257, 307) need no change
  but should be re-read to confirm struct equality still makes the assertion
  meaningful. The `compile!/1` raise test (542-546) keeps its `~r/Compilation
  failed:/` regex and should be tightened to also match the full old sentence,
  since preserving that text is an acceptance criterion.
- `test/predicator/execute_test.exs` - 253-256 and 330-333, including the test
  title "returns a binary error, not parse_program/2's raw 4-tuple", which
  becomes a structured-error title.
- `test/predicator/reserved_words_test.exs` - all 11 `compile/1` assertions
  become `assert {:error, %ParseError{message: ^msg, position: {1, N}}} =
  Predicator.compile(...)`, matching the `evaluate/3` test directly above each
  one. `ParseError` is already aliased in that file.
- `test/predicator/equals_grammar_break_test.exs` - 31-34, same transformation,
  same already-present alias.

**New tests** (`test/predicator_test.exs`, in a describe block of its own):

- All six entry points return a `%ParseError{}` with the same `:message` and
  `:position` for the same bad source - the uniformity ADR-0015 is buying.
- The returned `:message` does not contain `"at line"` - the regression guard
  for the specific defect being fixed.
- A compile error and the `evaluate/3` error for the same source are equal
  structs - the cross-façade uniformity claim, stated as a test rather than as
  prose.

These are ordinary tests, not binding tests, so they need no sabotage note and
no entry in `.claude/wurk.json`'s `gate.sabotage.test_roots`.

### Success Criteria:

#### Automated Verification:
- [ ] `mix quality` is green (format, compile with no warnings, credo --strict,
      dialyzer, deps audit, suite with coverage)
- [ ] Total coverage stays at or above the 90% `coveralls.json` minimum, with
      no threshold edit
- [ ] `grep -rn "at line" lib/predicator.ex lib/predicator/errors/parse_error.ex`
      returns only the `compile!/1` message composition
- [ ] `grep -rn 'at line 1, column' test/` returns nothing
- [ ] `grep -rn 'formatted binary\|binary error' lib/` returns nothing - this
      is the source `mix docs` renders from, so it settles the generated docs
      too and needs no separate `mix docs` pass
- [ ] `mix run -e 'IO.puts(Predicator.isa_version())'` prints `6`
- [ ] `git status --porcelain conformance/` is empty

#### Manual Verification:
- [ ] The raised `compile!/1` text is character-for-character what 7.0.0 raised
      for the same input: run `Predicator.compile!("score >")` in `iex -S mix`
      and compare against `git show HEAD:lib/predicator.ex`'s
      `"Compilation failed: #{reason}"` applied to the old binary
- [ ] Reading the six rewritten `@doc` paragraphs in order, each states the
      same contract in the same terms - a reviewer should not be able to tell
      from the wording which of the six they are looking at

Style note for the implementer, not a verification item: the six paragraphs
are one edit repeated, not six independent rewrites. Write one and adapt it.

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run full `mix quality` as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the
next phase. In looped (`--loop`) execution, this phase's Automated Verification
gates advancement automatically (via `/wurk:commit --auto`), and Manual
Verification items are deferred and surfaced once at the end instead of
blocking here.

---

## Phase 2: Changelog and the live documentation

### Overview

Record the break for consumers and update the two live documents that describe
the compile contract. Nothing here changes behaviour, and everything here is
verifiable - the `docs/reference/language.md` addition is a doctest that
`mix quality` runs.

### Changes Required:

#### 1. CHANGELOG

**File**: `CHANGELOG.md`
**Changes**: add a `### Changed` entry under the existing `## [Unreleased]`
heading (which today has only `### Added`). Do **not** promote the section to a
version header - that is release work under `CLAUDE.md`'s authority table. The
entry states, in the house style of the surrounding entries:

- All six compile entry points now return `{:error, struct()}` instead of
  `{:error, binary()}`, with a parse failure reported as
  `%Predicator.Errors.ParseError{}`; name all six functions.
- `:message` holds the parser's message with no location text; the location is
  `:position`.
- The migration, **both ways**: a caller that displayed the old sentence
  rebuilds it as
  `"#{error.message} at line #{elem(error.position, 0)}, column #{elem(error.position, 1)}"`;
  a caller that regex-matched the sentence for the line and column deletes the
  regex and reads `error.position`.
- What did **not** change: `compile/1`'s success arm, `%Compiled{}`,
  `compile!/1`'s raised text, `parse/2` and `parse_program/2`'s 4-tuple, and the
  ISA version (still 6) - so stored instruction lists need no migration.
- That this is why the next release is a major one.

#### 2. Architecture reference

**File**: `docs/architecture.md`
**Changes**: the "Compile entry points" section (130-147) describes the six
functions and their success shapes but says nothing about the error arm. Add
one sentence: all six share one error arm, `{:error, struct()}`, a parse
failure being a `%Predicator.Errors.ParseError{}` with the location in
`:position`. Cite ADR-0015. The "Error Handling" bullet list (237-243) already
says `{:ok, value} | {:error, struct}` from the `Predicator.Errors` family -
after this change that statement is true without exception, which is worth
saying explicitly.

#### 3. Language reference

**File**: `docs/reference/language.md`
**Changes**: the "Error Shapes" section (963+) opens with "Predicator returns
errors as structs under `Predicator.Errors`, never as bare strings" - true of
`evaluate/3` before this change and true of the whole façade after it. Add a
short doctested example showing a compile failure, beside the existing
`evaluate/3` one:

```elixir
iex> {:error, err} = Predicator.compile("score >>")
iex> {err.__struct__, err.position}
{Predicator.Errors.ParseError, {1, 8}}
```

Copy the real values from an `iex -S mix` run; `test/docs_examples_test.exs`
executes this file, so a wrong expectation is a red gate, not a stale doc.

`README.md` needs no edit - it shows only success arms (39-62) and links out
for error shapes.

### Success Criteria:

#### Automated Verification:
- [ ] `mix quality` is green, including the `docs/reference/language.md`
      doctests run by `test/docs_examples_test.exs`
- [ ] `CHANGELOG.md` has a `### Changed` entry under `## [Unreleased]` and the
      `## [Unreleased]` heading is still present and unpromoted
- [ ] `git diff --stat mix.exs` is empty (no version bump)
- [ ] `mix test test/docs_examples_test.exs` passes on its own

#### Manual Verification:
- [ ] The CHANGELOG entry gives a consumer enough to migrate without opening
      the source: both directions of the migration, and the explicit list of
      what did not change
- [ ] `docs/architecture.md` and `docs/reference/language.md` agree with each
      other and with the `@doc`s from Phase 1
- [ ] Prose style matches the surrounding entries in each file it touches
      (per-file house style, not a global preference)

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

- `test/predicator_test.exs` - the six-entry-point uniformity block described
  in Phase 1: same struct, same `:message`, same `:position` from every door;
  `:message` free of `"at line"`; a compile error equal to the `evaluate/3`
  error for the same source; `compile!/1`'s raised text pinned to the full old
  sentence, not just the `Compilation failed:` prefix.
- `test/predicator/reserved_words_test.exs` and
  `test/predicator/equals_grammar_break_test.exs` - the converted assertions
  are the real coverage of message-and-position fidelity across the interesting
  failure kinds (a keyword used as a variable, a property name, an object key,
  and the `=` fix-it error), because each already pins an exact message and
  column.
- `test/predicator/execute_test.exs` - the program family's error arm, and the
  `compile_program_with_spans/1` == `compile_program/1` error equality, which
  is what proves span mode does not sprout a different error shape (ADR-0015,
  step 4 of the deferred span work).
- Edge cases worth an explicit assertion: a lexer failure (`"a = @"`) and a
  parser failure produce the same struct type, since ADR-0015 declines to
  distinguish them; and a multi-line source reports a line other than 1, so the
  position is genuinely threaded and not a constant.

### Integration Tests:

`test/predicator/integration/` needs no new file. The façade-level uniformity
tests in `test/predicator_test.exs` are the end-to-end check here, and the
existing integration suites exercise `evaluate/3` and `execute/3`, whose error
construction this bead does not touch. Running them unchanged and green is the
regression signal that matters.

### Manual Testing Steps:

1. `iex -S mix`, then `Predicator.compile("score >")` - confirm a
   `%Predicator.Errors.ParseError{}` with a bare `:message` and `{1, 8}`.
2. `Predicator.compile("score >") == Predicator.evaluate("score >", %{})` -
   confirm `true`, the cross-façade uniformity claim.
3. `Predicator.compile!("score >")` - confirm the raised text matches 7.0.0's
   exactly.
4. `Predicator.compile("score > 85")` - confirm the success arm is the same
   bare instruction list as before, and `Predicator.isa_version()` is `6`.
5. `mix corpus.generate` followed by `git status conformance/` - confirm no
   corpus diff, per ADR-0015's "the conformance corpus is likewise untouched".

## References

- Bead: `px-d71` (no `mirrors:` line; no statifier-side counterpart is known,
  and ADR-0015 says not to invent one)
- Source ADR: `docs/adr/0015-compile-errors-are-structured-values.md`
- Related ADRs: `docs/adr/0004-no-eval-errors-are-values.md` (errors are values;
  the bang carve-out that lets `compile!/1` keep raising),
  `docs/adr/0009-the-compiled-envelope-carries-the-position-table.md`
  (`compile/1` stays a bare list; the six move together),
  `docs/adr/0003-*` (this change owes the ISA nothing),
  `docs/adr/0006-irreversibility-places-the-human-gates.md` (why release
  mechanics are out of scope here)
- Construction sites: `lib/predicator.ex:870-901`
- The struct: `lib/predicator/errors/parse_error.ex:39`
- The pattern to copy in tests: `test/predicator/equals_grammar_break_test.exs:20-22`
- Prior plan on this surface: `docs/plans/260814-px-iov-spans-program-compile.md`
- Follow-on bead, explicitly not folded in: `px-dmt` (parse-error spans)
