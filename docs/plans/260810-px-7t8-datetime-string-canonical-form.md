# Canonical `datetime::string` Form Implementation Plan

## Overview

Pin the fractional-seconds field of `datetime::string`, which `docs/isa.md` §5
left unspecified, to the form the Direction stage chose: **omitted entirely when
the sub-second component is zero, exactly six digits when it is not**, always
UTC with `Z`. That means one behavioral change in `lib/predicator/cast.ex`, the
normative bullet in `docs/isa.md` §5, its restatement in
`docs/reference/language.md`, and two conformance cases that lock the form into
the exported specification. Bead: `px-7t8`.

The decision itself is settled and is not reopened here. It is recorded in
[`docs/research/260810-px-7t8-datetime-string-fractional-seconds.md`](../research/260810-px-7t8-datetime-string-fractional-seconds.md),
including the exact replacement bullet for §5 and the argument for why this is
a v4 clarification rather than a v5.

## Current State Analysis

**The spec sentence does not determine the field.** `docs/isa.md:563` says of
`date`, `datetime` under **String formats (`::string`)**: "ISO 8601; datetimes
in UTC with `Z`". Elixir's, JavaScript's, and Ruby's host defaults all satisfy
that sentence with three different strings (`.000000Z`, `.000Z`, none), so three
implementations could each claim ISA v4 conformance and disagree on every
`datetime::string`.

**This repo emits six digits, always.** `lib/predicator/cast.ex:131-135` pipes
through `normalize_to_utc/1` (`:164-167`), whose
`DateTime.from_unix!(DateTime.to_unix(dt, :microsecond), :microsecond)` sets the
struct's `microsecond` precision field to `6` unconditionally, and then
`DateTime.to_iso8601/1` prints exactly that many digits. So
`"2026-08-09T10:30:00Z"::datetime::string` is `"2026-08-09T10:30:00.000000Z"` -
six zero digits that were never in the input.

**Two test assertions encode that, deliberately and with a comment.**
`test/predicator/cast_test.exs:144-154` asserts both `.000000Z` results and its
comment calls the six digits "the documented tradeoff of avoiding a time zone
database". Both assertions change in Phase 1; the comment is replaced, since
the tradeoff it describes is exactly what the new clause severs (the tz-free
route stays, its precision artifact stops leaking into the output).

**The corpus already leans the other way.** No `datetime::string` case exists
anywhere in `conformance/cases/*.json` (verified by grepping every `::string`
source in the file), so nothing is locked in yet. But the datetime values that
do reach the corpus go through `Predicator.Conformance.Values.to_json/1`, which
formats at the value's *own* precision, so `conformance/cases/casts.json:30`
and `:72` already expect `"2026-08-09T00:00:00Z"` and `"2026-08-09T10:30:00Z"`,
and `conformance/README.md:107`'s example does too. The chosen form agrees with
all three, so no existing expectation moves.

**One authored case's note is now stale.**
`conformance/cases/casts.json:155-159` (`casts/string-to-datetime-with-offset`)
chains onto `::date` and explains that it does so because "the parsed
datetime's own fractional-seconds field is not this repo's normative form yet
(px-7t8)". After this bead the form is normative, so the note is wrong about
the state of the world.

**Sub-second precision is real in this language.** The lexer's datetime literal
goes through `DateTime.from_iso8601/1` (`lib/predicator/lexer.ex:655`), so
`#2026-08-09T10:30:00.5Z#` is legal and `::datetime` parses the same way,
truncating past the sixth digit. That is why "seconds precision always" was
rejected: it would silently discard data the author supplied.

**The gate is `mix quality`** and `conformance/` is a gated path
(`.claude/wurk.json`'s `gate.also_gated_paths`).
`test/predicator/conformance/corpus_freshness_test.exs` regenerates the corpus
in memory and byte-compares it against the checked-in files, so any phase that
changes what the pipeline computes must ship the regenerated corpus in the same
commit or go red.

## Desired End State

- `docs/isa.md` §5's **String formats (`::string`)** subsection states the
  fractional-seconds field normatively, in the words the research document
  fixed, and `docs/reference/language.md`'s restatement agrees with it.
- `Predicator.Cast.cast(%DateTime{}, "string")` emits `2026-08-09T12:00:00Z`
  for a whole-second instant and `2026-08-09T12:00:00.500000Z` for a sub-second
  one, and no other shape.
- `conformance/cases/casts.json` carries two `datetime::string` cases - one
  zero-fraction, one non-zero - and `conformance/corpus/tier-7.json` plus
  `conformance/manifest.json` are the regenerated form of that.
- ISA stays **v4**: no row in §7, `Predicator.isa_version/0` unchanged,
  `test/predicator/isa_sync_test.exs` untouched and green.
- `mix quality` green, coverage still above the `coveralls.json` floor.

Verification: `mix quality` from a clean tree, plus reading the two new corpus
cases in `conformance/corpus/tier-7.json` and confirming their `expected`
strings are the two shapes above.

### Key Discoveries:

- `lib/predicator/cast.ex:131-135` is the single behavioral site; the precision
  forcing that causes the six digits is at `:164-167` and stays, because it is
  what keeps UTC normalization tz-database-free.
- `test/predicator/cast_test.exs:144-154` is the only place in `lib/`, `test/`,
  `docs/` (outside the research document) or `conformance/` that asserts the
  `.000000Z` form.
- No `datetime::string` corpus case exists, so **Phase 1 is expected to produce
  no corpus diff at all**; `corpus_freshness_test` is what decides that rather
  than an assumption.
- `conformance/cases/casts.json:30` and `:72` and `conformance/README.md:107`
  already show the zero-fraction form, which is why the chosen form costs no
  existing expectation.
- ADR-0011 settles that `::` is a `cast` opcode with `:undefined` totality;
  ADR-0003 makes this repo the ISA reference, which is why §5 states the form
  normatively instead of warning about it.
- `docs/isa.md`'s `bracket_access` bullet is the in-repo precedent for
  tightening a previously-unspecified §5 statement without an ISA bump, and §7
  records the general allowance ("A version's semantics can also be refined in
  a later release without a new opcode and without a new ISA version").

## What We're NOT Doing

- **No ISA version bump.** ISA stays v4, §7 gains no row, and
  `Predicator.isa_version/0` does not move. The reasoning is in the research
  document's "Version" section; do not re-derive it.
- **`lib/predicator/parser.ex:1287`** - formats a datetime inside a parse error
  message. Human-facing prose, not an exported value. Untouched.
- **`lib/predicator/visitors/string_visitor.ex:161`** - `decompile` renders a
  `#…#` literal. §6 puts surface syntax outside both the ISA and the corpus, and
  the lexer round trip holds under either form. Untouched, and no follow-on.
- **`lib/predicator/conformance/values.ex:71`** - the corpus's tagged
  `{"$type": "datetime"}` encoding. It has the same underspecification and
  should end up with the same form, but adopting it collides with
  `to_json/1`'s documented `from_json(to_json(v)) == {:ok, v}` property
  (asserted at `test/predicator/conformance/values_test.exs:34`), which is a
  design call about the harness's value domain. Filed as **px-qq6**. Nothing
  here depends on it: both cases this plan pins expect a **string** result, so
  `to_json/1`'s datetime clause is not on their path.
- **`normalize_to_utc/1` is not changed.** Forcing precision 6 there is what
  makes it tz-database-free, and it also feeds the `string::datetime` parse,
  which is not this bead's surface. The canonicalization is applied after it, on
  the `::string` path only.
- **No corpus case for the truncation-past-six behavior.** A seventh input digit
  is not constructible in a JavaScript sibling backed by `Date`, and pinning it
  in the corpus would export a case a conforming sibling cannot run. It is
  covered as an Elixir unit test instead, and §5's bullet states the microsecond
  bound in prose.
- **No new `docs/adr/` entry.** One field of one cell of one opcode's
  conversion matrix is not ADR-shaped; `docs/adr/README.md`'s third corollary
  routes a call this narrow to `docs/research/`, which is where it went.

## Implementation Approach

Two phases, split at the seam between *what the implementation does* and *what
the exported specification says it does* - which is also the only ordering that
keeps both gates green.

Phase 1 changes behavior, its tests, and the prose specification together. That
grouping is deliberate rather than tidy: ADR-0003 requires an ISA statement and
its implementation to land in the same change, and splitting them would leave an
intermediate commit whose §5 bullet contradicts its own `cast.ex`. It expects a
zero-line corpus diff, and `corpus_freshness_test` proves that rather than
assuming it.

Phase 2 then authors the two pinning cases and regenerates. It has to come
second: `mix corpus.generate` computes the real result and **fails loudly** when
an authored `expected` disagrees with it, so a case pinning the new form authored
before Phase 1 lands would simply refuse to generate. Both phases are
independently committable, and each is green on its own.

## ISA Impact

1. **Version** - **no bump. ISA stays v4.** §1's rule that an opcode's
   semantics never change under its own name bites on a change to *specified*
   behavior; this field was never specified, so no conforming implementation
   could have depended on it. §5's own `bracket_access` bullet is the precedent
   ("not the ISA version, changed to state the above precisely"), §7 records the
   general allowance, and v4 has not shipped at all - `cast` is still under
   `## [Unreleased]` and §7 promises v4 in 4.1.0, which does not exist. v4 ships
   already pinned. `docs/isa.md` §7 gains no row and
   `test/predicator/isa_sync_test.exs` is not touched.
2. **Stamp** - what the change owes `docs/isa.md`: the replacement `date` /
   `datetime` bullet under §5's **String formats (`::string`)**, and nothing
   else. No opcode subsection (the `cast` subsection already exists), no version
   row, and the conformance tier is unchanged - `cast` is already tier 7, and
   this adds two cases to the existing tier rather than opening a new one.
3. **Migration** - an instruction list compiled before this change still runs
   and still produces a `cast` result; only the *string rendering* of a datetime
   moves, and it moves toward the form the corpus already used everywhere else.
   No stored artifact changes meaning, so there is no upgrade path to name. The
   one visible consequence for a consumer is that a whole-second datetime
   rendered through `::string` loses six zero digits it should never have had.

---

## Phase 1: Canonicalize the emitted form and state it normatively

### Overview

Make `datetime::string` emit the chosen two shapes, replace the two test
assertions that encoded the old one, add coverage for the non-zero and
truncation cases, and write the normative bullet into `docs/isa.md` §5 with its
restatement in `docs/reference/language.md`. Fold the fact into the existing
`## [Unreleased]` cast entry in `CHANGELOG.md`.

### Changes Required:

#### 1. The cast clause

**File**: `lib/predicator/cast.ex`
**Changes**: Canonicalize the `microsecond` precision field between
`normalize_to_utc/1` and `DateTime.to_iso8601/1`. `normalize_to_utc/1` is
unchanged.

```elixir
  def cast(%DateTime{} = value, "string") do
    value
    |> normalize_to_utc()
    |> canonicalize_microsecond()
    |> DateTime.to_iso8601()
  end
```

with a private helper beside `normalize_to_utc/1`:

```elixir
  # docs/isa.md section 5: datetime::string omits the fractional-seconds field
  # entirely when the sub-second component is zero and emits exactly six digits
  # when it is not. normalize_to_utc/1 forces precision 6 to stay
  # tz-database-free, so this is where that internal artifact stops.
  @spec canonicalize_microsecond(DateTime.t()) :: DateTime.t()
  defp canonicalize_microsecond(%DateTime{microsecond: {0, _precision}} = datetime),
    do: %{datetime | microsecond: {0, 0}}

  defp canonicalize_microsecond(%DateTime{microsecond: {microseconds, _precision}} = datetime),
    do: %{datetime | microsecond: {microseconds, 6}}
```

The second clause's precision assignment is a no-op for anything arriving from
`normalize_to_utc/1`, which already sets 6; it is written explicitly so the
helper states the whole rule on its own rather than depending on its caller.
Both clauses are exercised by the tests below, so neither is dead for coverage
purposes.

`@moduledoc` needs no change - it already points at `docs/isa.md` §5 as the
normative matrix, which is where the new sentence lands.

#### 2. Unit tests

**File**: `test/predicator/cast_test.exs`
**Changes**: Replace the `.000000Z` assertions at `:144-154` and the comment
above them, and add the sub-second and truncation cases.

```elixir
    test "datetime with a zero sub-second component formats with no fraction" do
      # docs/isa.md section 5 pins this: the fraction is omitted entirely when
      # the sub-second component is zero. normalize_to_utc/1 still forces
      # microsecond precision internally - that is what keeps UTC
      # normalization tz-database-free - but the precision field is an Elixir
      # struct detail and no longer reaches the output.
      assert Cast.cast(~U[2026-08-09T10:00:00Z], "string") == "2026-08-09T10:00:00Z"

      {:ok, offset_dt, _offset} = DateTime.from_iso8601("2026-08-09T12:00:00+02:00")
      assert Cast.cast(offset_dt, "string") == "2026-08-09T10:00:00Z"
    end

    test "datetime with a non-zero sub-second component formats with six digits" do
      assert Cast.cast(~U[2026-08-09T10:00:00.5Z], "string") ==
               "2026-08-09T10:00:00.500000Z"

      assert Cast.cast(~U[2026-08-09T10:00:00.123456Z], "string") ==
               "2026-08-09T10:00:00.123456Z"
    end

    test "datetime::string is a canonicalization, not a string identity" do
      # A seventh input digit is truncated by the ::datetime parse, and a
      # one-digit fraction widens to six. Both are docs/isa.md section 5's
      # stated behavior, not an accident of the host type.
      assert "2026-08-09T10:00:00.123456789Z" |> Cast.cast("datetime") |> Cast.cast("string") ==
               "2026-08-09T10:00:00.123456Z"

      assert "2026-08-09T10:00:00.5Z" |> Cast.cast("datetime") |> Cast.cast("string") ==
               "2026-08-09T10:00:00.500000Z"

      assert "2026-08-09T10:00:00Z" |> Cast.cast("datetime") |> Cast.cast("string") ==
               "2026-08-09T10:00:00Z"
    end
```

The last assertion of the last test is the one worth having: it is the identity
on the string that a reader of §5 would predict, and it is what the old six-digit
behavior violated.

**Sabotage notes do not apply to these tests.** The binding-test class is the
eight enumerated files in
[`docs/research/260808-px-9ab-sabotage-notes.md`](../research/260808-px-9ab-sabotage-notes.md)
(`test/predicator/isa_sync_test.exs`, the six
`test/predicator/conformance/*_test.exs` binders, and
`test/docs_adr_links_test.exs`). `test/predicator/cast_test.exs` is an ordinary
pure-function test file and is not in it; that decision explicitly rejected the
broad form. No `# sabotage:` line is added, and none is removed.

#### 3. The normative bullet

**File**: `docs/isa.md`
**Changes**: Replace the single `date`, `datetime` bullet at `:563` under
**String formats (`::string`)** with the two bullets the research document
fixed, verbatim:

```markdown
  - `date` - ISO 8601 calendar date (`2026-08-09`).
  - `datetime` - ISO 8601 in UTC with `Z`, and the fractional-seconds field is
    **normative**: omitted entirely when the sub-second component is zero
    (`2026-08-09T12:00:00Z`), and exactly six digits when it is not
    (`2026-08-09T12:00:00.500000Z`). Never any other digit count, and never a
    zero fraction spelled out. Sub-second precision is microseconds - the
    `::datetime` parse truncates digits past the sixth - so the field is
    stated in terms of the instant, not in terms of any host type's precision
    or scale field.
```

and add the round-trip note alongside, in the same shape as the `duration`
bullet's existing round-trip sentence: `dt::string::datetime` preserves the
instant, while `s::datetime::string` is a **canonicalization** rather than a
string identity (`"…:00.5Z"` returns as `"…:00.500000Z"`, and a seventh digit is
gone).

Match the file's existing indentation for this bullet list (two spaces, inside
the `cast` subsection) and its typography, which uses plain hyphens.

**§7 gets nothing.** Do not add a version row and do not touch
`Predicator.isa_version/0`.

#### 4. The user-facing restatement

**File**: `docs/reference/language.md`
**Changes**: `:192-196`'s **String formats (`::string`)** paragraph currently
says "date and datetime as ISO 8601 (datetime in UTC with a `Z` suffix)". Extend
the datetime half to carry the same rule in reference-doc register - no fraction
when the sub-second component is zero, exactly six digits when it is not, with
both example strings - and note that `::string` is therefore a canonicalization
of the instant. Keep it a restatement: `docs/isa.md` stays the authority, and
this page must not introduce a form the ISA does not state.

#### 5. Changelog

**File**: `CHANGELOG.md`
**Changes**: **Fold into the existing `## [Unreleased]` → `### Added` cast
bullet** (`:12-24`); do not add a new bullet and do not add a `### Changed`
entry. The `cast` operator has not shipped, so there is no user-visible change
to announce - only a specification that is now precise. One sentence inside that
bullet, near its other `::string` material, stating that `datetime::string`
omits the fraction when the sub-second component is zero and emits exactly six
digits otherwise.

### Success Criteria:

#### Automated Verification:
- [x] `mix quality` (full) is green.
- [x] `mix test test/predicator/cast_test.exs` passes, and the three datetime
      `::string` tests above are present and passing.
- [x] `grep -rn '000000Z' lib/ test/ docs/isa.md docs/reference/ conformance/`
      returns nothing. `docs/research/` is deliberately not searched: the
      research document quotes the old six-digit behavior as history and is
      correct to keep it.
- [x] `test/predicator/conformance/corpus_freshness_test.exs` passes **without**
      `mix corpus.generate` having been run - the expected outcome, since no
      corpus case renders a datetime through `::string`. If it goes red, the
      diff is real: run `mix corpus.generate`, and the corpus diff ships in this
      phase's commit with the ADR-0003 explanation in the commit message and PR
      body.
- [x] `test/predicator/isa_sync_test.exs` passes with no edit to it, confirming
      the ISA did not move.
- [x] Coverage stays above the `coveralls.json` floor (>90% per component);
      `Predicator.Cast`'s new helper has both clauses covered.

#### Manual Verification:
- [ ] `docs/isa.md` §5's new bullet reads as the research document wrote it, and
      `docs/reference/language.md` does not contradict it.
- [ ] `iex -S mix` spot check: `Predicator.evaluate!(~s(#2026-08-09T10:30:00Z#::string))`
      is `"2026-08-09T10:30:00Z"` and
      `Predicator.evaluate!(~s("2026-08-09T10:30:00.5Z"::datetime::string))` is
      `"2026-08-09T10:30:00.500000Z"`.
- [ ] `CHANGELOG.md`'s cast bullet still reads as one coherent paragraph after
      the fold, rather than as a sentence stapled on.
- [ ] No regressions in the neighbouring datetime surfaces, both of which are
      deliberately out of scope, so any change there is a defect in this phase.
      Both render at the *value's own* precision today and must continue to:
      `Predicator.decompile(~s(#2026-08-09T10:30:00Z# = x))` still renders the
      literal as `#2026-08-09T10:30:00Z#`
      (`lib/predicator/visitors/string_visitor.ex:159-161`), and a parse error
      on a misplaced datetime token still reads
      `datetime '2026-08-09T10:30:00Z'` (`lib/predicator/parser.ex:1287`).

**Implementation Note**: Use the project's loop gate between edits while
iterating; run the full gate as the phase gate. In interactive execution, pause
here for the human to confirm the manual testing before moving to the next
phase. In looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

## Phase 2: Pin the form in the conformance corpus

### Overview

Author the two `datetime::string` cases the acceptance criteria require, correct
the now-stale note on `casts/string-to-datetime-with-offset`, and regenerate the
corpus. This is what makes the form part of the exported specification a sibling
runs against, rather than an Elixir-only fact.

### Changes Required:

#### 1. The authored cases

**File**: `conformance/cases/casts.json`
**Changes**: Add two cases in the `::string` format neighbourhood (beside
`casts/date-to-string` at `:193` and `casts/duration-to-string` at `:199`, which
is where the other format cases live). This file is the **authored** source and
is hand-edited; `conformance/corpus/*.json` and `conformance/manifest.json` are
not.

```json
  {
    "id": "casts/datetime-to-string-zero-fraction-omitted",
    "source": "#2026-08-09T10:30:00Z#::string",
    "expected": { "result": "2026-08-09T10:30:00Z" },
    "notes": "datetime::string omits the fractional-seconds field entirely when the sub-second component is zero (docs/isa.md section 5, pinned by px-7t8). The sentence 'ISO 8601; datetimes in UTC with Z' did not determine this field, and the three implementations' host defaults disagreed on it - Elixir six digits, JavaScript three, Ruby none - so all three could claim ISA v4 while producing different strings for this cast. This case is the form, not one language's default"
  },
  {
    "id": "casts/datetime-to-string-non-zero-fraction-is-six-digits",
    "source": "\"2026-08-09T10:30:00.500Z\"::datetime::string",
    "expected": { "result": "2026-08-09T10:30:00.500000Z" },
    "notes": "a non-zero sub-second component formats as exactly six digits, never a variable or minimal count (docs/isa.md section 5, px-7t8). The pinned value is expressible in milliseconds deliberately, so a JavaScript sibling backed by Date rather than Temporal can construct the input at all - the same portability discipline the float::string case applies. Note this also shows that datetime::string is a canonicalization and not a string identity: three input digits come back as six"
  }
```

The zero-fraction case uses a datetime **literal**, matching the existing
`casts/datetime-to-datetime-identity` case (`:70-74`), which already proves that
spelling is constructible by a sibling. The non-zero case goes through the
`::datetime` **string parse** rather than a fractional literal, because a
fractional datetime literal is not exercised anywhere else in the corpus and
this case's subject is the format, not the lexer.

#### 2. The stale note

**File**: `conformance/cases/casts.json`
**Changes**: Rewrite the `notes` on `casts/string-to-datetime-with-offset`
(`:155-159`). It currently explains that the case chains onto `::date` because
the fractional form "is not this repo's normative form yet (px-7t8)". Keep the
chained shape - the case's own subject is that the parse requires a UTC offset,
and `::date` is a fine way to confirm that - but replace the reason: the form is
now pinned, by the two cases above, and this case simply is not the one that
pins it.

#### 3. Regenerate

**File**: `conformance/corpus/tier-7.json`, `conformance/manifest.json`
**Changes**: `mix corpus.generate`. Never hand-edited. Expect tier 7's
`case_count` to move 54 → 56, and `corpus_hash` in `conformance/manifest.json`
to change with it.

A corpus diff moves the exported specification (ADR-0003), so it is explained in
the commit message **and** in the PR body: which cases were added, what they
pin, and that no existing expectation moved.

### Success Criteria:

#### Automated Verification:
- [ ] `mix corpus.generate` completes without a disagreement error - the
      generator computes the real result and fails loudly if an authored
      `expected` is wrong, so a clean run is itself the confirmation that
      Phase 1's behavior matches these two cases.
- [ ] `mix quality` (full) is green, including
      `test/predicator/conformance/corpus_freshness_test.exs`, which byte-compares
      the checked-in corpus against a fresh in-memory generation.
- [ ] `conformance/manifest.json` reports tier 7 `case_count` 56, and
      `test/predicator/conformance/schema_validation_test.exs` accepts both new
      cases.
- [ ] `grep -c 'datetime-to-string' conformance/corpus/tier-7.json` is 2, and
      the two `expected` strings there are exactly `2026-08-09T10:30:00Z` and
      `2026-08-09T10:30:00.500000Z`.
- [ ] No `px-7t8`-as-open-question text remains in `conformance/cases/`:
      `grep -rn 'px-7t8' conformance/` finds only settled references.

#### Manual Verification:
- [ ] The two new cases read as portable: a Ruby or JavaScript implementer can
      construct both inputs and produce both outputs in one line of their host
      language (`iso8601(6)` / a `.000` strip plus padding), which was the whole
      criterion the form was chosen on.
- [ ] The corpus diff contains only the two added cases and the reworded note -
      no unrelated case, hash, or ordering churn.
- [ ] The commit message and PR body both explain the corpus diff per ADR-0003.

**Implementation Note**: Use the project's loop gate between edits while
iterating; run the full gate as the phase gate. In interactive execution, pause
here for the human to confirm the manual testing before moving to the next
phase. In looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

## Testing Strategy

### Unit Tests:

`test/predicator/cast_test.exs`, in the existing `cast/2 to string` describe
block, pattern-matching style, replacing the two `.000000Z` assertions:

- Zero sub-second component, both from a `~U` sigil and from a non-UTC offset
  string, formats with no fraction. The offset case matters because it is the
  path through `normalize_to_utc/1` that motivated the old comment.
- Non-zero component formats as six digits, checked at a one-digit input (`.5`
  widens) and at a full six-digit input (`.123456` passes through).
- `::datetime::string` composition: a seventh digit truncates, a one-digit
  fraction widens, and a whole-second string is the identity on itself. The
  identity assertion is the behavioral regression guard - it is precisely what
  the old six-digit form broke.

Edge cases deliberately covered here rather than in the corpus: the
truncation-past-six input, which a JavaScript `Date`-backed sibling cannot
construct.

No new test file, and no sabotage note - `cast_test.exs` is outside the
binding-test class (see Phase 1).

### Integration Tests:

No new file in `test/predicator/integration/`. The end-to-end path is already
covered twice over by the two conformance cases in Phase 2, which run through
the real compiler and evaluator via the corpus harness, and adding a third
assertion of the same fact in `Predicator.evaluate/3` form would be duplication.
The `iex` spot check in Phase 1's manual criteria covers the public façade by
hand.

### Manual Testing Steps:

1. `iex -S mix`, then
   `Predicator.evaluate!(~s(#2026-08-09T10:30:00Z#::string))` - expect
   `"2026-08-09T10:30:00Z"` with no fraction.
2. `Predicator.evaluate!(~s("2026-08-09T10:30:00.5Z"::datetime::string))` -
   expect `"2026-08-09T10:30:00.500000Z"`.
3. `Predicator.evaluate!(~s(#2026-08-09#::datetime::string))` - expect
   `"2026-08-09T00:00:00Z"`, confirming the `date::datetime` bridge's midnight
   agrees with the corpus's existing datetime encodings.
4. Read `docs/isa.md` §5's `cast` subsection start to finish and confirm the new
   bullet does not contradict the `::datetime` parse bullet above it.
5. Read the Phase 2 corpus diff as a sibling implementer would: are both inputs
   constructible and both outputs producible in Ruby and in JavaScript?

## Open Questions

None for this plan. Every decision it depends on is settled - the form itself
and the no-bump call in
[`docs/research/260810-px-7t8-datetime-string-fractional-seconds.md`](../research/260810-px-7t8-datetime-string-fractional-seconds.md),
casts-as-an-opcode in ADR-0011, and this repo's ISA leadership in ADR-0003.

The one genuinely open design question in this area - whether the corpus's
tagged `{"$type": "datetime"}` encoding can adopt the same canonical form
without breaking `Values.to_json/1`'s documented round-trip property - is
**px-qq6**, filed separately. It does not gate anything here: both cases this
plan pins expect a string result, so the tagged datetime encoder is not on their
path.

## References

- Source document: `docs/research/260810-px-7t8-datetime-string-fractional-seconds.md`
- Related ADRs: `docs/adr/0011-casts-are-an-opcode.md` (casts are an opcode,
  totality is `:undefined`),
  `docs/adr/0003-the-elixir-implementation-leads-the-isa.md` (this repo is the
  ISA reference implementation; a corpus diff moves the exported specification)
- The matrix's working specification: `docs/research/260809-px-2r5.1-cast-conversion-matrix.md`
- The binding-test class this plan checks itself against:
  `docs/research/260808-px-9ab-sabotage-notes.md`
- Prior implementation of the same surface: `docs/plans/260809-px-2r5.3-cast-compile-eval.md`
- Behavioral site: `lib/predicator/cast.ex:131-135`, `:164-167`
- Spec site: `docs/isa.md:556-568`
- Bead: `px-7t8`; deferred sibling question: `px-qq6`

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] `docs/isa.md` §5's new bullet reads as the research document wrote it, and
      `docs/reference/language.md` does not contradict it.
- [ ] `iex -S mix` spot check: `Predicator.evaluate!(~s(#2026-08-09T10:30:00Z#::string))`
      is `"2026-08-09T10:30:00Z"` and
      `Predicator.evaluate!(~s("2026-08-09T10:30:00.5Z"::datetime::string))` is
      `"2026-08-09T10:30:00.500000Z"`.
- [ ] `CHANGELOG.md`'s cast bullet still reads as one coherent paragraph after
      the fold, rather than as a sentence stapled on.
- [ ] No regressions in the neighbouring datetime surfaces, both of which are
      deliberately out of scope, so any change there is a defect in this phase.
      Both render at the *value's own* precision today and must continue to:
      `Predicator.decompile(~s(#2026-08-09T10:30:00Z# = x))` still renders the
      literal as `#2026-08-09T10:30:00Z#`
      (`lib/predicator/visitors/string_visitor.ex:159-161`), and a parse error
      on a misplaced datetime token still reads
      `datetime '2026-08-09T10:30:00Z'` (`lib/predicator/parser.ex:1287`).

**Implementation Note**: Use the project's loop gate between edits while
iterating; run the full gate as the phase gate. In interactive execution, pause
here for the human to confirm the manual testing before moving to the next
phase. In looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---
