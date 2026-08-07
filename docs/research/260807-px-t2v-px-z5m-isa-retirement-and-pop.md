---
date: 2026-08-07T17:17:07-0600
researcher: Claude
git_commit: 0570151525156152bb2912f39efe18359611cf53
branch: px-t2v-isa-retirement-pop
repository: predicator-ex
beads_issue: px-t2v, px-z5m
topic: "Opcode retirement mechanics (px-t2v) and the pop / statement halt contract (px-z5m)"
tags: [research, codebase, isa, instructions, conformance, evaluator, docs]
status: complete
last_updated: 2026-08-07
last_updated_by: Claude
---

# Research: opcode retirement mechanics (px-t2v) and pop / statement halt (px-z5m)

**Date**: 2026-08-07T17:17:07-0600
**Git Commit**: 0570151525156152bb2912f39efe18359611cf53
**Branch**: px-t2v-isa-retirement-pop
**Beads Issues**: px-t2v, px-z5m

## Research Question

Both beads edit `docs/isa.md` and will be implemented back to back, so this is a
single pass over both sets of touchpoints.

**px-t2v** (opcode retirement mechanics): what `Predicator.Instructions` looks
like today; what `docs/isa.md` says about versioning, tiers, opcodes, and version
history; how strictly `isa_sync_test.exs` parses the doc; and what mechanically
breaks in the conformance corpus if an opcode the reference evaluator no longer
implements still needs coverage for a v1 sibling.

**px-z5m** (pop + statement halt contract): what section 2 says about halt,
result, and `empty_stack`; what section 6 reserves and what tier 6 says; and what
code or plan material exists today for `store`, `pop`, `Predicator.execute/2`,
and statement programs.

This document describes the codebase as it exists. It proposes nothing.

## Summary

**px-t2v.** The opcode table is one Elixir map, `@opcodes` in
`lib/predicator/instructions.ex:34-60`, whose values are exactly
`%{isa: integer, tier: integer}` - **there is no `removed_in`, no `since`, and no
status field of any kind**. `required_isa/1` and `tier/1` both answer from
`Map.fetch/2` on that map, and both construct the same `"unknown_opcode"` reason
on a miss, from two different call sites with two different messages. So deleting
the `"and"`/`"or"` rows is exactly the failure px-t2v names: `required_isa/1`
stops returning a version and starts returning `unknown_opcode`, which is the
opposite of ADR-0003's "refused with a message naming the version it needs".

Three separate mechanisms would also break, and all three are strict:
`isa_sync_test.exs` asserts a literal `@opcode_count 25` in **two** places
(the doc table and the evaluator clause heads) and asserts the tier-names table
lists *exactly* the opcodes the map assigns to each tier; the corpus's
opcode-coverage test requires every opcode in `Instructions.opcodes/0` to appear
in at least one case, with `relative_date` the single documented exclusion; and
five authored legacy cases in `conformance/cases/legacy.json` are completed by
running them through the **real reference evaluator**, so an evaluator that no
longer implements `and`/`or` cannot generate them at all. Beyond that,
`corpus_hash` moves, the checked-in `registry.example.json` is pinned to it, and
the ratchet's rule 1 fails on any entry whose `case_id` is no longer in the
corpus.

**px-z5m.** `pop` appears **nowhere** in `lib/`, `test/`, `docs/`, or
`conformance/` as an opcode - `grep -rn '"pop"'` over those trees returns
nothing, and the only occurrences of the token are the `_or_pop` suffixes and
bead prose. `store` is reserved in three places (section 6, the tier-6 row, and
a test that asserts it is currently *unknown*) but has no evaluator clause and no
table row. `Predicator.execute/2` does not exist; the only reference to it in
`lib/` is a stale forward mention in a `@doc` at `lib/predicator.ex:540`.
`Predicator.Context` does exist (`lib/predicator/context.ex`) and already names
"the future `store` opcode (`px-tbv.2`)" as a third caller of its write path.
The `empty_stack` error is constructed in exactly one place,
`lib/predicator/evaluator.ex:91-97`, in `run_prepared/1`, and it fires on a
`stack: []` at halt - which is precisely the state px-z5m says a statement
program ending in an assignment or a `pop` reaches by design.

---

## Detailed Findings

# Part A - px-t2v: opcode retirement mechanics

## 1. `Predicator.Instructions` as it stands

`lib/predicator/instructions.ex` (195 lines total).

### The table

`@opcodes` (`lib/predicator/instructions.ex:34-60`) is a 25-entry map whose
values carry **two fields only**:

```elixir
@opcodes %{
  "lit" => %{isa: 1, tier: 1},
  "load" => %{isa: 1, tier: 1},
  ...
  "and" => %{isa: 1, tier: 1},
  "or" => %{isa: 1, tier: 1},
  ...
  "make_list" => %{isa: 2, tier: 3},
  "jump_if_falsy_or_pop" => %{isa: 2, tier: 1},
  "jump_if_true_or_pop" => %{isa: 2, tier: 1}
}
```

The comment above it (`:29-33`) states the contract: "Opcode -> the ISA version
that introduced it, and the conformance tier it belongs to (docs/isa.md, section
4). An opcode's semantics never change under its own name (ADR-0003) ...
isa_sync_test binds both columns to docs/isa.md."

There is **no `removed_in`, no `since`, no `status`, no `emitted_by_compiler`
field**. "Emitted by compiler" is a column in the doc table (`docs/isa.md:147`)
that has no counterpart in the map, and the isa_sync regex does not read it
either.

`@isa_version 2` is a separate module attribute at `:27`.

### `opcodes/0`

`lib/predicator/instructions.ex:77-78`:

```elixir
@spec opcodes() :: %{optional(String.t()) => %{isa: pos_integer(), tier: pos_integer()}}
def opcodes, do: @opcodes
```

The whole map, unfiltered. Its `@spec` hard-codes the two-key value shape, so a
third key is a spec change as well as a data change. Three consumers read it:
`isa_sync_test.exs:87`, the corpus generator's manifest builder
(`lib/predicator/conformance/generator.ex:419-441`), and
`test/predicator/conformance/opcode_coverage_test.exs`.

### `tier/1`

`lib/predicator/instructions.ex:100-114`. `Map.fetch(@opcodes, opcode)` ->
`{:ok, tier}`, or on `:error`:

```elixir
{:error,
 EvaluationError.new(
   "Unknown opcode: #{inspect(opcode)}",
   "unknown_opcode",
   :tier
 )}
```

### `required_isa/1` - exactly what it returns

`lib/predicator/instructions.ex:158-167` reduces over the instruction list,
taking `max` of each element's version, seeded at `{:ok, 1}`. Three documented
outcomes (`@doc` at `:116-155`):

- **Known opcode**: `{:ok, version}` where version is the max over the list.
  Empty list is `{:ok, 1}` - "there is no v0, and the floor keeps
  `required_isa(list) <= isa_version()` correct without a `:none` case"
  (`:129-130`).
- **Unknown opcode** (`opcode_version/2`, `:171-184`):

  ```elixir
  {:error,
   EvaluationError.new(
     "Unknown opcode #{inspect(opcode)}; this build supports ISA v#{@isa_version}",
     "unknown_opcode",
     :required_isa
   )}
  ```

  The doctest at `:153-154` pins the exact struct:
  `%EvaluationError{reason: "unknown_opcode", message: "Unknown opcode \"nope\"; this build supports ISA v2", operation: :required_isa}`.
- **Malformed element** (`:186-193`): reason `"malformed_instruction"`,
  operation `:required_isa`.

The scan is **flat and opcode-only** - it never recurses into operands, for the
reason given at `:119-127` (a list literal compiles to a nested list that looks
like an instruction).

### Where `unknown_opcode` originates

Two constructors, both in `lib/predicator/instructions.ex`, distinguished only by
their `operation` field and message text:

| Site | operation | message |
|---|---|---|
| `:107-112` (`tier/1`) | `:tier` | `Unknown opcode: "nope"` |
| `:177-182` (`required_isa/1`) | `:required_isa` | `Unknown opcode "nope"; this build supports ISA v2` |

`docs/isa.md:78-83` documents a *different* reason, `"unknown_instruction"`,
which belongs to the evaluator's catch-all clause
(`lib/predicator/evaluator.ex:509`) and covers malformed operands too; the
moduledoc at `:136-138` explicitly calls out that these are distinct.

`CHANGELOG.md:184-185` records the message wording change using `store` as its
worked example: `Unknown opcode "store"; this build supports ISA v2`.

The message-format change is also what
`test/predicator/instructions_test.exs:102-108` asserts, and that test is the
canonical statement of the pre-retirement invariant for a *reserved* name:

```elixir
# "store" is the reserved v-next opcode name (docs/isa.md section 6) and
# is not in the map yet - px-tbv.2 adds it, at which point this
# expectation flips intentionally rather than by accident.
test "store is currently an unknown opcode" do
  assert {:error, %EvaluationError{reason: "unknown_opcode"}} =
           Instructions.required_isa([["store", 0]])
end
```

## 2. What `docs/isa.md` says today

### Section 1, Versioning (`docs/isa.md:18-44`)

The retirement sentence, verbatim (`:33-35`) - this is the *entire* retirement
policy px-t2v names:

> - An additive version - new opcodes only, every existing instruction list
>   still valid - ships in a minor release. Retiring an opcode invalidates
>   stored artifacts and takes a major release plus an upgrade path.

The surrounding rules, verbatim (`:23-38`):

> - ISA versions are integers - v1, v2, v3 - with no correspondence to this
>   library's semver. All three ISA v2 opcodes shipped in 3.7.0; 3.8.0 then
>   refined v2 semantics without adding an opcode (it made every arithmetic and
>   legacy logical opcode report an unbound root rather than a type mismatch).
> - An opcode's semantics never change under its own name. A change to what an
>   opcode does is a new name at a new version. This is what makes "scan the
>   opcode names in a list" a sound answer to "what version does this list
>   require".
> - Adding an operand form or widening an accepted type is a new version but
>   not a new name.
> - An additive version - new opcodes only, every existing instruction list
>   still valid - ships in a minor release. Retiring an opcode invalidates
>   stored artifacts and takes a major release plus an upgrade path.
> - A sibling behind the current version is an expected, documented state.
>   Each sibling publishes the version it supports in its own repository; this
>   document maintains no support matrix.

Then `:40-44`:

> Current version: **ISA v2**.
>
> At runtime, `Predicator.isa_version/0` returns this build's version as an
> integer, and `Predicator.Instructions.required_isa/1` returns the minimum
> version a given instruction list needs.

Note what is *absent*: nothing says whether retirement mints a new integer, and
nothing says what a version means once its opcode set can shrink. The bullet at
`:29-30` ("scan the opcode names in a list" is a *sound* answer) is the property
that a removed row would break, since a scan of a deleted name yields an error
rather than a version.

### Section 4, tiers and the opcode table (`docs/isa.md:110-178`)

Preamble (`:112-121`):

> One row per opcode the evaluator accepts, including opcodes the compiler no
> longer emits. Columns: **Opcode**, **Operands**, **Pops**, **Pushes**,
> **ISA**, **Tier**, **Emitted by compiler**.
>
> [...]
>
> Every opcode is **ISA v1** except `jump_if_falsy_or_pop`,
> `jump_if_true_or_pop`, and `make_list`, which are **v2** (ADR-0001).

"One row per opcode **the evaluator accepts**" is the current membership rule for
the table, and it is the sentence that decides whether a retired opcode keeps a
row.

The tier table (`:130-137`), verbatim:

```
| Tier | Name | Opcodes it unlocks |
|---|---|---|
| 1 | core | `lit`, `load`, `compare`, `not`, `unary_bang`, `unary_minus`, `jump_if_falsy_or_pop`, `jump_if_true_or_pop`, `and`, `or` |
| 2 | arithmetic | `add`, `subtract`, `multiply`, `divide`, `modulo` |
| 3 | access | `in`, `contains`, `access`, `bracket_access`, `make_list` |
| 4 | rich types | `object_new`, `object_set`, `duration`, `relative_date` |
| 5 | functions | `call` |
| 6 | statements | (none yet - reserved for `store`) |
```

The opcode table's `and`/`or` rows (`:153-154`):

```
| `and` | - | 2 | 1 | v1 | 1 | no |
| `or` | - | 2 | 1 | v1 | 1 | no |
```

Both carry `no` in the "Emitted by compiler" column - the only two rows that do.

The per-opcode entry for them (`docs/isa.md:234-243`), verbatim, is where
retirement is currently forecast:

> - **`and`, `or`** - **legacy: accepted but never emitted by the
>   compiler.** Both operands must be booleans; anything else, including
>   `:undefined`, is `TypeMismatchError` with operation `logical_and` /
>   `logical_or` and expected type `boolean`. They do
>   not short-circuit: both operands are already on the stack by the time
>   either opcode runs. Kept for stored artifacts and for v1 sibling
>   implementations (ADR-0001); ADR-0003 permits retiring them at a major
>   version with an upgrade path (`px-tbv.9`). A v2 implementation still has to
>   run them - they are not deprecated out of the evaluator, only out of code
>   generation.

### Section 7, Version history (`docs/isa.md:381-395`)

Verbatim:

> ## 7. Version history
>
> | ISA | Opcodes introduced | Shipped in |
> |---|---|---|
> | v1 | everything not listed below | up to 3.6.x |
> | v2 | `jump_if_falsy_or_pop`, `jump_if_true_or_pop`, `make_list` | 3.7.0 |
>
> This table records the release each opcode was *introduced* in. A version's
> semantics can be refined in a later release without a new opcode and without
> a new ISA version - 3.8.0 did exactly that to v2, as noted in §1.
>
> ISA v1 is defined as the full opcode set the Elixir evaluator accepted
> before ADR-0001. A sibling declaring v1 support is claiming that whole set;
> where a sibling falls short of it, the sibling publishes that fact in its
> own repository. No support matrix is maintained here (ADR-0003).

The table has a column for *introduced* and none for *retired*. "ISA v1 is
defined as the full opcode set the Elixir evaluator accepted before ADR-0001" is
a definition anchored to a historical evaluator, not to the current one - so v1's
definition survives a retirement in the current evaluator by construction, which
is worth noting because it is the only place a version's opcode set is defined
independently of the live table.

## 3. `test/predicator/isa_sync_test.exs` - what it checks, and how strictly

`test/predicator/isa_sync_test.exs` (199 lines). Its moduledoc (`:2-17`) frames
the three surfaces: the `@opcodes` map, `docs/isa.md` section 4's table, and
`lib/predicator/evaluator.ex`'s `execute_instruction/2` clause heads.

### The literal count guard

`:23-27`:

```elixir
# The opcode set is 25 (docs/isa.md section 4; lib/predicator/evaluator.ex
# execute_instruction/2 clause heads at :371-509). Both parsing tests guard
# against a regex that silently matches nothing - and passes vacuously - by
# asserting this literal count rather than only "non-empty".
@opcode_count 25
```

`@opcode_count` is asserted **twice**, against two different surfaces:

- `:41-43` - `length(rows) == @opcode_count` for rows parsed out of the
  `docs/isa.md` section 4 table.
- `:121-124` - `MapSet.size(opcodes) == @opcode_count` for opcodes parsed out of
  `execute_instruction/2` clause heads in `lib/predicator/evaluator.ex`.

These two counts are independent. A retirement that removes evaluator clauses but
keeps doc rows makes them disagree; a retirement that removes both keeps them in
step but requires the literal to move to 23.

### Per-row round-trip

`:45-57` - every parsed row asserts both:

```elixir
assert Instructions.required_isa([[opcode]]) == {:ok, version}
assert Instructions.tier(opcode) == {:ok, doc_tier}
```

**This is the constraint that decides what a `removed_in:` marker may look like**:
any opcode that keeps a row in the section 4 table must still answer `{:ok, v}`
from `required_isa/1` **and** `{:ok, tier}` from `tier/1`. A row present in the
doc but absent from the map fails here, and so does a row whose opcode answers an
error tuple.

### The table row regex

`:135-144`:

```elixir
# Matches rows like:
#   | `lit` | value | 0 | 1 | v1 | 1 | yes |
# Column 1 is the opcode (backtick-quoted), column 5 is the ISA version
# (`v` + digits), column 6 is the tier (bare digits). If the table gains or
# loses a column, this regex still matches as long as columns 1, 5, and 6
# keep their positions and shape - it does not validate the other columns
# at all. If the table's shape changes (columns reordered, or the
# opcode/version/tier columns move), this regex will need updating to
# match.
@isa_table_row_regex ~r/^\|\s*`([a-z_]+)`\s*\|[^|]*\|[^|]*\|[^|]*\|\s*v(\d+)\s*\|\s*(\d+)\s*\|/m
```

Mechanical consequences for a `removed_in:` marker in the table:

- The opcode cell must be **a single backticked lowercase/underscore token**;
  `` `and` (removed in 4.0) `` in column 1 still matches the leading
  `` `and` `` (the regex is not anchored past the backtick span, only
  `\s*\|` follows), but anything before the backtick breaks it, and a struck-out
  or annotated opcode name with characters outside `[a-z_]` inside the backticks
  does not match at all.
- Columns 2-4 are `[^|]*` - free.
- Column 5 must be exactly `v` + digits, column 6 exactly digits. A marker cannot
  live in either of those cells (e.g. `v1 (removed 4.0)` fails).
- A **new column 8** ("Removed in") is invisible to the regex, since it stops
  after column 6's closing pipe. That is the shape the regex accommodates
  without modification.
- A row that is *deleted* simply reduces the count and trips `@opcode_count`.

### The tier-names table

`:77-104` asserts, per tier row, that the doc's opcode list equals *exactly*
what the map assigns to that tier (`doc_opcodes == map_opcodes` after sorting).
This is an equality, not a subset, so an opcode removed from one side and not the
other fails naming both lists.

Its regex and the tier-6 special case (`:155-183`):

```elixir
# Matches rows of the tier *names* table (docs/isa.md:130-137), e.g.:
#   | 1 | core | `lit`, `load`, `compare`, ... |
# Column 1 is the tier number, column 3 is the opcode list. Tier 6's list
# column is prose - "(none yet - reserved for `store`)" - rather than a
# comma-separated backtick list, so a cell starting with "(" is treated as
# an empty opcode list instead of scanning it for backtick spans (which
# would wrongly pick up `store`, an opcode that does not exist yet).
@tier_table_row_regex ~r/^\|\s*(\d+)\s*\|[^|]*\|\s*(.+?)\s*\|\s*$/m
@tier_table_opcode_regex ~r/`([a-z_]+)`/
```

`tier_row_opcodes/1` (`:174-183`) returns `[]` for any cell **starting with
`(`**, and otherwise scans every backtick span in the cell. So a tier row's
opcode cell is all-or-nothing: either it is prose beginning with a paren and
contributes nothing, or every backticked token in it is claimed as an opcode the
map must assign to that tier. An annotation like
`` `lit`, ..., `and` (removed in 4.0) `` would be scanned normally and `and`
would still be required in the map at tier 1.

This is directly relevant to **px-z5m** as well: the tier-6 row is currently
`(none yet - reserved for `store`)`, and it parses as empty *because it starts
with `(`*. Any tier-6 cell that keeps that leading paren keeps contributing zero
opcodes regardless of how many backticked names it mentions.

### Two more assertions in the same file

- `:60-65` - `isa_version/0` equals the **maximum** version appearing in the
  section 4 table. A v3 in the table without a matching `@isa_version` bump fails
  here, and vice versa.
- `:67-69` - the doc contains the literal string
  `Current version: **ISA v#{Instructions.isa_version()}**.`

### The evaluator clause head regex

`:185-190`:

```elixir
@evaluator_clause_regex ~r/defp execute_instruction\(%__MODULE__\{\}[^,]*, \["([a-z_]+)"/
```

with `:126-131` asserting every matched clause-head opcode is in the map. The
direction is one-way (evaluator -> map): an opcode in the map with *no* evaluator
clause passes this test, and is caught only by the `@opcode_count` equality at
`:121`.

## 4. The conformance corpus

### How `mix corpus.generate` builds cases

`lib/mix/tasks/corpus.generate.ex`:

- `read_authored_cases/0` (`:72-84`) globs `conformance/cases/*.json`
  (`@cases_glob`, `:34`), sorts paths, decodes each file's top-level JSON array,
  and concatenates.
- `build_files/0` (`:52-70`) - public specifically so `corpus_freshness_test.exs`
  can call it - chains that into `Predicator.Conformance.Generator.generate/1`
  (`:67`) then `assemble_files/2` (`:107-131`).
- `assemble_files/2` produces one `{tier, "conformance/corpus/tier-N.json",
  content}` triple per tier the generator returned, encoding each tier's cases
  with `Predicator.Conformance.JSON.encode_lines/1` (one canonical object per
  line), computes `corpus_hash`, fills the manifest, and returns a path -> bytes
  map.
- `hash_corpus/1` (`:139-143`), verbatim:

  ```elixir
  @spec hash_corpus([{pos_integer(), String.t(), binary()}]) :: String.t()
  defp hash_corpus(tier_entries) do
    content = Enum.map_join(tier_entries, "", fn {_tier, _path, content} -> content end)
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, content), case: :lower)
  end
  ```

  It is a sha256 over the **concatenated bytes of every tier file, in tier
  order**. Any change to any case in any tier moves it.
- `--check` (`:41-50`, `check/1` at `:152-168`) regenerates in memory, diffs
  against disk, reports every stale path, and `Mix.raise`s. It never writes.
- Generation errors (`report_errors/1`, `:178-185`) print every failing id and
  problem and raise, writing nothing.

### How a case is completed

`lib/predicator/conformance/generator.ex`:

- `fetch_endpoint/1` (`:171-192`) requires **exactly one** of `"source"` (string)
  or `"instructions"` (list). `resolve_instructions/1` (`:211-220`) compiles the
  source via `Predicator.compile/1` (a compile error is a case failure) or passes
  authored instructions through unchanged.
- `evaluate_case/2` (`:222-231`) runs `Predicator.evaluate(instructions, context,
  [])` - **the real reference evaluator, with default options** - and turns the
  outcome into `expected_result` (tagged via `Values.to_json/1`) or
  `expected_error` via `encode_error/1` (`:257-269`), which emits
  `{"type" => module short name, "reason" => reason}` and **never the message**.
  A raise during evaluation is a case failure (`rescue` at `:229-230`).
- Authored `"expected"` is an **assertion**: `check_expected/2` (`:271-288`)
  fails the case if the authored value disagrees with the computed one, in either
  direction (result-vs-error included). An absent `"expected"` is `:ok`
  unconditionally (`:275-276`).

### How tiers map to opcode lists

Tier is **computed**, never placed:

- `compute_tier/1` (`:326-337`) folds over instructions tracking the running
  maximum `{tier, forcing_opcode}`; `instruction_tier/1` (`:339-347`) calls
  `Predicator.Instructions.tier(opcode)` per instruction.
- An **opcode not in the table** turns into
  `{:error, "instructions use #{message}"}` (`:343`), which halts the fold
  (`:334`) and fails that case. There is no fallback tier and no way to place a
  case whose opcode the table does not know.
- A malformed instruction (anything not `[binary | _]`) fails at the catch-all
  clause (`:347`).
- An authored `"tier"` that disagrees fails, naming both tiers and the opcode
  that forced the higher one (`check_tier/3`, `:349-367`, message at `:360-362`).
- The manifest's per-tier `opcodes` array comes from `Instructions.opcodes()`
  grouped by tier (`build_manifest/1`, `:419-441`; `opcodes_by_tier` at
  `:421-423`, sorted at `:435`) - **not** from which cases exist. So the manifest
  lists an opcode for a tier whether or not any case uses it.
- `@tier_names` (`:43-50`) already carries `6 => "statements"`, with the comment
  at `:39-42`: "Tier 6 (statements) has no opcodes yet, so it never appears in a
  real manifest today, but the name is here so the day `store` lands this table
  does not need editing."

### Where tier 1's legacy evaluator-only cases live

`conformance/cases/legacy.json` (39 lines), five cases, all authoring
`"instructions"` and no `"source"`:

```json
[
  {
    "id": "legacy/and-true-true",
    "instructions": [["lit", true], ["lit", true], ["and"]],
    "expected": { "result": true },
    "features": ["legacy_logical"],
    "notes": "the bare and/or opcodes (ADR-0001): accepted by the evaluator forever but never emitted by the compiler, which always compiles source-level and/or to jump_if_falsy_or_pop/jump_if_true_or_pop instead (see short_circuit.json). Tier 1 by opcode; a v1 sibling must still run these."
  },
  {
    "id": "legacy/or-false-true",
    "instructions": [["lit", false], ["lit", true], ["or"]],
    "expected": { "result": true },
    "features": ["legacy_logical"]
  },
  {
    "id": "legacy/and-does-not-short-circuit",
    "instructions": [["lit", false], ["lit", true], ["and"]],
    "expected": { "result": false },
    "features": ["legacy_logical"],
    "notes": "docs/isa.md: and/or do not short-circuit - both operands are already on the stack by the time either opcode runs, unlike jump_if_falsy_or_pop/jump_if_true_or_pop"
  },
  {
    "id": "legacy/and-rejects-non-boolean",
    "instructions": [["lit", 1], ["lit", true], ["and"]],
    "expected": {
      "error": { "type": "TypeMismatchError", "reason": "logical_and" }
    },
    "features": ["legacy_logical"],
    "notes": "both operands must be booleans; anything else, including :undefined, is a TypeMismatchError"
  },
  {
    "id": "legacy/or-rejects-non-boolean",
    "instructions": [["lit", 1], ["lit", true], ["or"]],
    "expected": {
      "error": { "type": "TypeMismatchError", "reason": "logical_or" }
    },
    "features": ["legacy_logical"]
  }
]
```

The five ids: `legacy/and-true-true`, `legacy/or-false-true`,
`legacy/and-does-not-short-circuit`, `legacy/and-rejects-non-boolean`,
`legacy/or-rejects-non-boolean`. All compute to tier 1 and ship with
`"source": null` in `conformance/corpus/tier-1.json:35-39`. The two error cases
pick up an extra `errors` tag from `outcome_tags/1`
(`lib/predicator/conformance/features.ex:139-143`).

The `legacy_logical` tag is not a table entry - it is two dedicated clauses
(`lib/predicator/conformance/features.ex:102-107`):

```elixir
# ["and"]/["or"] appear in an instruction list only as the legacy
# evaluator-only opcodes (ADR-0001) - the compiler always emits
# jump_if_falsy_or_pop/jump_if_true_or_pop for source-level `and`/`or`, so
# seeing the bare opcode name is itself the signal.
defp instruction_tags(["and" | _rest]), do: ~w(legacy_logical)
defp instruction_tags(["or" | _rest]), do: ~w(legacy_logical)
```

`docs/plans/260807-px-35i.4-conformance-corpus.md:801-806` (Open Question 6)
records the placement decision as it stands:

> 6. **Where the `and`/`or` legacy cases sit.** They are tier 1 by opcode, and a
>    v1 sibling must run them. **Assumption: they stay in tier 1 with
>    `"source": null` and the `legacy_logical` feature tag**, so a sibling can
>    select them out by tag if it has taken px-tbv.9's retirement early, without
>    the tier moving.

### `conformance/README.md` on the `source: null` case set

Verbatim (`conformance/README.md:29-48`):

> ## The two surfaces
>
> Each case exercises up to two independent things a sibling implements:
>
> 1. **The evaluator.** Run `instructions` (already-compiled, tagged-value
>    encoded) against `context`, and compare the result to `expected_result`
>    (on success) or `expected_error` (on failure). Every case in the corpus has
>    an evaluator form.
> 2. **The compiler.** Parse `source` and compare the emitted instructions,
>    structurally, against `instructions`. Only cases where `source` is
>    non-`null` have a compiler form.
>
> A case with `"source": null` is an **evaluator-only** case - most commonly the
> legacy `["and"]`/`["or"]` opcodes ([ADR-0001](../docs/adr/0001-keep-the-stack-vm-revise-the-instruction-set.md)),
> which the compiler never emits but which the evaluator must still run forever
> for stored artifacts and v1 siblings. Such a case is **absent from the
> compiler surface's case set** - it is not a case the compiler surface skips,
> because there is nothing here for the compiler to do. A runner scoped to the
> compiler surface simply filters to `source != null` before it starts; it
> never reports these ids at all, passing or failing.

Note the phrase "must still run **forever**" - the README states the ADR-0001
promise ADR-0003 later amended.

### `conformance/manifest.json`

Single line, verbatim:

```json
{"corpus_hash":"sha256:9b3a6b0709f9346294d8466c4cf9c60f5d7437df665dd6f4bcca4474b45d85ae","isa_version":2,"tiers":[{"case_count":49,"file":"corpus/tier-1.json","name":"core","opcodes":["and","compare","jump_if_falsy_or_pop","jump_if_true_or_pop","lit","load","not","or","unary_bang","unary_minus"],"tier":1},{"case_count":19,"file":"corpus/tier-2.json","name":"arithmetic","opcodes":["add","divide","modulo","multiply","subtract"],"tier":2},{"case_count":23,"file":"corpus/tier-3.json","name":"access","opcodes":["access","bracket_access","contains","in","make_list"],"tier":3},{"case_count":14,"file":"corpus/tier-4.json","name":"rich types","opcodes":["duration","object_new","object_set","relative_date"],"tier":4},{"case_count":26,"file":"corpus/tier-5.json","name":"functions","opcodes":["call"],"tier":5}]}
```

`"and"` and `"or"` are the first and eighth entries of tier 1's `opcodes` array.
That array is derived from `Instructions.opcodes()`, so it moves the moment the
map does - and moving it moves the manifest bytes, but **not** `corpus_hash`,
which is computed over the tier files only, before the manifest is assembled
(`lib/mix/tasks/corpus.generate.ex:116-126`).

### The opcode-coverage test and its exclusion list

`test/predicator/conformance/opcode_coverage_test.exs`:

- `@excluded_opcodes ~w(relative_date)` (`:25`) - one entry.
- `:27-39` - every opcode in `Instructions.opcodes()` minus the exclusions must
  appear in at least one authored case's instructions (`covered_opcodes/0`,
  `:63-78`, regenerates all cases and flat-maps their opcodes).
- `:41-49` - each exclusion must genuinely have zero coverage, so a stale
  exclusion fails.
- `:51-58` - `@excluded_opcodes` is bound to `conformance/README.md`'s documented
  list by `readme_excluded_opcodes/0` (`:86-100`), which slices the README
  between `### Opcodes excluded from the coverage rule` and the next heading
  (`extract_section/2`, `:102-110`) and collects `` ~r/^- `([a-z_]+)`/m `` tokens
  that are also known opcode names. The assertion is set **equality**.

The bound README section (`conformance/README.md:186-197`):

> ### Opcodes excluded from the coverage rule
>
> `test/predicator/conformance/opcode_coverage_test.exs` asserts that every
> opcode in `Predicator.Instructions.opcodes/0` appears in at least one case,
> **except** the opcode named below - and a test binds that exclusion list to
> this exact section, so removing the exclusion in one place without the other
> fails the suite.
>
> - `relative_date` - its result depends on the system clock at evaluation time
>   (`docs/isa.md` section 5: it calls `DateTime.utc_now/0`), so no case can pin
>   an expected value. A clock-injection seam would make this coverable and is
>   its own future issue if wanted.

### The freshness test

`test/predicator/conformance/corpus_freshness_test.exs:19-30` calls
`Mix.Tasks.Corpus.Generate.build_files/0`, reads each file at the same path, and
asserts byte identity. On mismatch, `describe_mismatch/3` (`:51-69`) parses both
sides into id-keyed maps (`lines_by_id/1`, `:71-83`) and names exactly which
case ids were added, removed, or changed. Manifest mismatches are reported whole
(`:67`). All failures accumulate into one message (`:22-29`).

### The ratchet's consumption of the corpus

`conformance/RATCHET.md`:

- **Rule 1** (`:129-158`): "A registry entry whose `(case_id, surface)` pair is
  not a member of that surface's case set in the pinned corpus FAILS the run."
  The compiler surface's set is "every case with `source != null`"; a
  `source: null` case is *absent* from it, not skipped (`:138-141`).
- The literal worked example (`:102-118`) includes
  `{"case_id":"legacy/and-true-true","surface":"evaluator","tier":1}`.
- The reference runner pseudocode (`:189-211`) filters
  `cases.filter(c -> c.source != null)` for the compiler surface.
- The check pseudocode (`:230-243`) includes
  `fail unless (e.case_id, e.surface) in surface_case_set(corpus, e.surface)`
  and `fail unless e.tier == corpus[e.case_id].tier`.

`conformance/examples/registry.example.json:46-50` carries all five legacy case
ids as `"evaluator"`-surface, tier-1 entries and none on the compiler surface.
Its `corpus_hash` and `isa_version` equal the manifest's exactly.

`test/predicator/conformance/ratchet_registry_test.exs`:

- `:40-76` - rule 1: every entry's `case_id` must resolve in
  `conformance/corpus/tier-1.json` (`flunk` at `:56-61` otherwise), a
  `"compiler"` entry on a `source: null` case flunks (`:63-69`), and the entry's
  `tier` must match (`:71-73`).
- `:78-92` - the pin: `example["corpus_hash"] == manifest["corpus_hash"]` and the
  same for `isa_version`.
- `:94-105` - rule 2: re-encode and byte-compare against the file.
- `:107-130` - R5 completeness: **every** tier-1 corpus case id (all 49,
  including the five legacy ones) must have a matching evaluator-surface entry.

### What breaks mechanically if a retired opcode still needs corpus coverage

Stated as observed facts about the current tooling, in the order a
`mix corpus.generate` run hits them:

1. **Generation cannot complete a case the evaluator cannot run.**
   `evaluate_case/2` (`generator.ex:222-231`) calls the real
   `Predicator.evaluate/3`. With the `and`/`or` clauses gone from
   `lib/predicator/evaluator.ex`, those instruction lists fall through to the
   catch-all at `:509` and evaluate to an `unknown_instruction` `EvaluationError`
   - so each of the five cases' computed outcome flips from its authored
   `"expected"` to an error, and `check_expected/2` fails the case. Five case
   errors, nothing written.
2. **Tier computation fails first if the opcode also leaves the table.**
   `instruction_tier/1` (`:339-347`) calls `Instructions.tier(opcode)`; a missing
   row makes that `{:error, ...}`, so the case fails on tier before it is ever
   evaluated. There is no "unknown opcode -> some tier" path.
3. **Coverage fails if the opcode stays in the table and the cases go.**
   `opcode_coverage_test.exs:27-39` requires every opcode in
   `Instructions.opcodes()` to have a case, and `:51-58` requires the exclusion
   list to match `conformance/README.md` exactly - so an exclusion added in one
   place only is red.
4. **`corpus_hash` moves.** `hash_corpus/1` covers the concatenated tier files,
   so removing or changing tier-1 cases changes it
   (`lib/mix/tasks/corpus.generate.ex:139-143`).
5. **The pinned example goes stale.** `ratchet_registry_test.exs:78-92` compares
   the example's `corpus_hash` to the manifest's; that fails until the example is
   regenerated.
6. **The example's legacy entries become unmatched.** `:40-76`'s rule-1 check
   flunks per orphaned `case_id`; R5 completeness at `:107-130` would then have
   to be satisfied against a shrunk tier-1 set.
7. **The manifest's tier-1 `opcodes` array drops `and`/`or`** as soon as the map
   does (`generator.ex:419-441`), independently of whether the cases exist -
   which is what a v1 sibling reading the manifest would see.
8. **`isa_sync_test.exs`'s two `@opcode_count 25` assertions** and the tier-names
   equality (`:77-104`) all bind the same set from other directions.

There is **no per-ISA-version corpus snapshot** anywhere in the tree: the corpus
is one set of files regenerated from the current pipeline, `manifest.json` names
a single `isa_version`, and `RATCHET.md`'s pin is a single `corpus_hash`. A v1
sibling and a v3 sibling read the same files.

---

# Part B - px-z5m: pop and the statement halt contract

## 5. What `docs/isa.md` says about halt, result, `empty_stack`, and tier 6

### Section 2, execution model (`docs/isa.md:46-94`)

The halt and result rules, verbatim (`:57-62`):

> - Execution is sequential from index 0. The program halts when the
>   instruction pointer reaches or passes the end of the list, so a forward
>   jump past the last instruction is a normal halt, not an error.
> - The result is the top of the stack at halt. An empty stack at halt is an
>   `EvaluationError` with reason `"empty_stack"`; it is the one error that
>   belongs to no instruction and therefore carries no source position.

The whole section is prefaced (`:48-49`) with "The rules that govern **every**
opcode, stated once here rather than repeated in each row", and the two
statements above are written unconditionally - there is no mode qualifier
anywhere in section 2, and no notion of a program that is not an expression.

Two other bullets in the same section bear on a statement layer:

- `:78-83` - "**A malformed operand is an unknown instruction, not a bad
  operand.** Every opcode's clause is guarded on its operand's shape, so an
  out-of-range or wrong-typed operand falls through to the catch-all clause and
  returns an `EvaluationError` with reason `"unknown_instruction"`."
- `:90-94` - "The Elixir-side `on_unbound` policy ... is an *evaluation option*,
  not part of the ISA."

### Section 6, "Not in the ISA" (`docs/isa.md:361-379`)

Verbatim, whole section:

> ## 6. Not in the ISA
>
> What a reader might expect to find here and will not:
>
> - `["store", n]` - specified by ADR-0001 for the 4.0 statement layer, not
>   implemented and not accepted by any current evaluator clause. Reserved
>   name, tier 6.
> - Source positions and spans - these travel in an Elixir-side side table,
>   never serialized as part of the instruction list. See
>   `docs/architecture.md`'s Source Positions and Source Spans sections.
> - Surface syntax, including the `=` grammar break
>   ([ADR-0002](adr/0002-the-equals-grammar-break.md)). Both `=` and `==`
>   compile to `["compare", "EQ"]`, so no instruction-level divergence exists
>   between them: a parse-time deprecation warning is the entire difference,
>   and it is outside the conformance corpus's scope.
> - The builtin function set - see
>   [Language Reference](reference/language.md).
> - Backward jumps and absolute jumps. Every jump in the ISA is relative and
>   forward-only.

`store` is the only reserved opcode name. `pop` is not mentioned.

### The tier-6 row (`docs/isa.md:137`)

```
| 6 | statements | (none yet - reserved for `store`) |
```

As noted in Part A, `isa_sync_test.exs`'s `tier_row_opcodes/1` (`:174-183`)
returns `[]` for this row solely because the cell starts with `(`.

## 6. Existing code and plan material on store, pop, execute, and statements

### `pop`

`grep -rn '"pop"'` over `lib/`, `test/`, `docs/`, and `conformance/` returns
**nothing**. The token appears only as the `_or_pop` suffix of
`jump_if_falsy_or_pop` / `jump_if_true_or_pop`, and in bead prose. There is no
evaluator clause, no opcode-table row, no tier assignment, no corpus case, and no
mention in `docs/isa.md`, `docs/architecture.md`, or any ADR.

### `store`

No evaluator clause (`lib/predicator/evaluator.ex:371-509` are all the
`execute_instruction/2` clauses; `:509` is the catch-all), no compiler emit
(`lib/predicator/compiler.ex` and
`lib/predicator/visitors/instructions_visitor.ex` mention only the word
"stored", at `compiler.ex:60` and `instructions_visitor.ex:15`), and no row in
`@opcodes`. Every reference in the tree is forward-looking:

| file:line | quoted |
|---|---|
| `lib/predicator/context.ex:158-159` | "algorithm as `Predicator.context_assign/4` and the future `store` opcode (`px-tbv.2`)." |
| `lib/predicator/conformance/generator.ex:39-42` | "Tier 6 (statements) has no opcodes yet, so it never appears in a real manifest today, but the name is here so the day `store` lands this table does not need editing." |
| `test/predicator/instructions_test.exs:102-108` | asserts `required_isa([["store", 0]])` is `{:error, %EvaluationError{reason: "unknown_opcode"}}`, with the comment "px-tbv.2 adds it, at which point this expectation flips intentionally rather than by accident" |
| `test/predicator/isa_sync_test.exs:157-161` | the tier-6 prose-cell special case, written so the regex does not "wrongly pick up `store`, an opcode that does not exist yet" |
| `docs/isa.md:137`, `:365-367` | the tier-6 row and the section 6 reservation |
| `docs/architecture.md:87-89` | "four opcodes (`jump_if_falsy_or_pop`, `jump_if_true_or_pop`, `make_list`, `store`) to the ISA, of which `store` is not yet implemented by any evaluator, Elixir or sibling" |
| `docs/adr/0001-...md:83-84` | "- **`[\"store\", n]`** - the assignment opcode for the statement layer, popping n path segments plus a value and writing through `ContextLocation.put/3`." |
| `docs/adr/0001-...md:115` | "`make_list`, or `store` will not run there - a wider gap than the existing" |
| `CHANGELOG.md:184-185` | uses `store` as the worked example of the `required_isa/1` message change |

`README.md` mentions none of `store`, `pop`, or `execute`.

### `Predicator.execute/2`

**Does not exist.** `lib/predicator.ex` has no `def execute`. The only occurrence
in `lib/` is a stale forward reference inside `run_evaluator/1`'s `@doc`:

- `lib/predicator.ex:540` - "where you need more control than the `execute/2`
  function provides."

Elsewhere:

- `docs/plans/260804-px-8um.1-context-struct.md:119-120` - "**No `[\"store\", n]`
  opcode or `Predicator.execute/2`.** That's `px-tbv.2`, which depends on this
  bead for `%Context{}` as its return type."
- `docs/plans/260804-px-8um.1-context-struct.md:647` - lists
  "`px-tbv.2` (`[\"store\", n]` opcode, `Predicator.execute/2`)" as a downstream
  dependent.

Everything else matching `execute` in `lib/` is `execute_instruction/2` and its
`execute_*` helpers (`lib/predicator/evaluator.ex:369-1016`).

### How the result and `empty_stack` are produced today

`lib/predicator/evaluator.ex:86-102`, `run_prepared/1` - the single place
stack-top-at-halt becomes a result, and the only construction of `empty_stack`:

```elixir
def run_prepared(%__MODULE__{} = evaluator) do
  case run_state(evaluator) do
    {:ok, %__MODULE__{stack: [result | _rest]} = final} ->
      {:ok, result, final}

    {:ok, %__MODULE__{stack: []} = final} ->
      {:error,
       EvaluationError.new(
         "Evaluation completed with empty stack",
         "empty_stack",
         :evaluate
       ), final}

    {:error, error_struct, final} when is_struct(error_struct) ->
      {:error, error_struct, final}
  end
end
```

`evaluate_prepared/1` (`:111-117`) wraps it and drops the final state. Halting
itself is `step/1` (`:306-321`): `if finished?(evaluator) do {:ok, halt(evaluator)}`.

Note the first clause matches `[result | _rest]` - a **non-empty** stack of any
depth returns its top and discards the rest silently. Only the empty case errors.

Occurrences of the `"empty_stack"` string:

- `lib/predicator/evaluator.ex:95` - the only one in `lib/`
- `test/predicator/evaluator_positions_test.exs:129` - the only one in `test/`
- `conformance/cases/errors.json:35` and `conformance/corpus/tier-1.json:29` -
  case `errors/empty-stack-at-halt`, `"instructions":[]`, notes: "docs/isa.md:
  the one error that belongs to no instruction and therefore carries no source
  position - only reachable via an empty hand-built instruction list"
- `docs/isa.md:60-62`
- plans: `260804-px-8um.1:207`, `260804-px-8um.8:370`, `260805-px-8um.7:240`,
  `260806-px-35i.2:197`

The corpus note "**only reachable via an empty hand-built instruction list**" is
the current characterization of the error, and it is the sentence a statement
program halting empty by design would sit against.

### `Predicator.Context`

Exists at `lib/predicator/context.ex` (separate from
`lib/predicator/context_location.ex`). Shape (`:36-45`):

```elixir
@type on_unbound :: :undefined | :error

@type t :: %__MODULE__{
        data: Types.context(),
        functions: %{binary() => {Evaluator.function_arity(), function()}},
        on_unbound: on_unbound()
      }

defstruct data: %{}, functions: %{}, on_unbound: :undefined
```

`new/2` (`:80`) normalizes data deeply (atom keys to string keys, `nil` to
`:undefined`). `assign/3` (`:151-159`) is the existing write path and already
names the future opcode as a third caller of the same algorithm. The struct is
plain and immutable, which is what px-tbv.2's "cheap because contexts are
immutable" all-or-nothing error story rests on.

### The downstream beads, verbatim where they bind this work

**px-tbv.2** ("Adds the store opcode and Predicator.execute/2", P3, OPEN,
`area:api, area:build, area:docs, area:evaluator`) - the two AC bullets px-z5m
cites:

> • A statement boundary compiles to ["pop"], discarding expression-statement
> values.
> • Predicator.execute(program_or_source, ctx) returns
> {:ok, %Context{}} | {:error, e}; the final context is the program's value,
> plus cheaply the last expression's value.

and:

> • ["store", n] pops n lhs segment values plus the value, calls
> ContextLocation.put/3 against the evaluator's context, and replaces it.
> One write algorithm, three entry points (put/3, Context.assign, store).
> • Errors abort the sequence and the context from completed statements is not
> committed - matching SCXML's all-or-nothing error story, cheap
> because contexts are immutable.

px-tbv.2's 2026-08-06 note: "The store opcode is an additive ISA change, and
ADR-0003's consequences say the license it grants must not be drawn on until
px-35i.2 (spec), px-35i.3 (stamp) and px-35i.4 (corpus) land. px-35i.4's manifest
already reserves tier 6 for store by name."

It depends on px-z5m, px-tbv.1, px-h66, and seven closed beads.

**px-tbv.1** ("Adds the statement grammar and parser", P3, OPEN,
`area:api, area:lexer-parser`) carries the grammar:

```
program    := statement (";" statement)* [";"]
statement  := assignment | expression
assignment := location "=" expression   -- lhs must parse assignable
```

with the AC bullet "Statements run left to right and no control flow ships in v1".
It depends on px-z5m.

**px-tbv.9** ("Retires the legacy and/or opcodes", P3, OPEN,
`area:docs, area:evaluator, release:4.0.0`) - AC verbatim:

> and/or clauses removed from the evaluator and from its moduledoc; upgrade/1
> shipped or its absence justified; CHANGELOG breaking-change entry naming the
> pre-3.7 artifact case; docs/isa.md marks both opcodes removed-in-4.0

and its description recommends "Predicator.Instructions.upgrade/1 rewriting a
pre-3.7 list into jump form - a consumer with stored artifacts runs it once, and
gets short-circuiting behavior they were otherwise silently missing." It depends
on px-t2v.

**px-tbv** (epic, "Predicator 4.0.0 - statements and the `=` grammar break") is
5/9 complete; px-tbv.1, .2, .5, .9 remain open.

### Plans

There is **no statement-layer plan** in `docs/plans/` (26 files). Every reference
is an out-of-scope carve-out:

- `260806-px-35i.2-isa-reference.md:43-48` - "**`store` is specified but not
  implemented.** ADR-0001 lists `[\"store\", n]` as an ISA v2 addition and
  `docs/architecture.md:87-88` repeats it, but there is no
  `execute_instruction/2` clause for it and nothing in `lib/` emits it ... isa.md
  documents what the evaluator accepts, so `store` gets no row - only a
  forward-looking note."
- `260806-px-35i.3-isa-version-stamp.md:150` - "**Not adding a `store` entry.**
  It is a reserved name with no evaluator clause"; `:628` - "`[\"store\", 0]` is
  currently an unknown opcode - a named test"; `:739` - open question "Does
  `store` belong in the map now, at some version, so `px-tbv.2` only ..."
- `260804-px-e3g.1-short-circuit-opcodes.md:174`,
  `260804-px-e3g.2-make-list-opcode.md:109`,
  `260805-px-8um.2-context-key-normalization.md:118`,
  `260807-px-35i.4-conformance-corpus.md:37`.

`docs/architecture.md` has no statement-grammar or statement-program section. Its
statement-adjacent material is the `=` grammar break (`:116-131`), the 4.0
removal notes (`:44-45`, `:277`), and the ContextLocation / SCXML `<assign>`
section (`:799-830`).

---

## Code References

- `lib/predicator/instructions.ex:27` - `@isa_version 2`
- `lib/predicator/instructions.ex:34-60` - `@opcodes`, 25 entries, `%{isa:, tier:}` only
- `lib/predicator/instructions.ex:77-78` - `opcodes/0` and its two-key `@spec`
- `lib/predicator/instructions.ex:100-114` - `tier/1`, `unknown_opcode` with `operation: :tier`
- `lib/predicator/instructions.ex:158-193` - `required_isa/1`, `opcode_version/2`, `unknown_opcode` with `operation: :required_isa`, `malformed_instruction`
- `lib/predicator/evaluator.ex:86-102` - `run_prepared/1`, stack top at halt, the sole `empty_stack` construction
- `lib/predicator/evaluator.ex:306-321` - `step/1` and `finished?/1`
- `lib/predicator/evaluator.ex:371-509` - all `execute_instruction/2` clauses; `:509` catch-all
- `lib/predicator/context.ex:36-45` - the `%Context{}` shape
- `lib/predicator/context.ex:151-159` - `assign/3`, naming "the future `store` opcode (`px-tbv.2`)"
- `lib/predicator.ex:540` - stale `execute/2` mention in a `@doc`
- `lib/predicator/conformance/generator.ex:39-50` - `@tier_names`, tier 6 reserved
- `lib/predicator/conformance/generator.ex:171-231` - endpoint resolution and evaluation against the real evaluator
- `lib/predicator/conformance/generator.ex:326-367` - computed tier, unknown-opcode failure, tier assertion
- `lib/predicator/conformance/generator.ex:419-441` - manifest tier table from `Instructions.opcodes/0`
- `lib/predicator/conformance/features.ex:102-107` - the `legacy_logical` clauses
- `lib/mix/tasks/corpus.generate.ex:52-70` - `build_files/0`
- `lib/mix/tasks/corpus.generate.ex:139-143` - `hash_corpus/1`
- `lib/mix/tasks/corpus.generate.ex:152-168` - `--check`
- `test/predicator/isa_sync_test.exs:23-27` - `@opcode_count 25`
- `test/predicator/isa_sync_test.exs:45-57` - the per-row `required_isa/1` + `tier/1` round-trip
- `test/predicator/isa_sync_test.exs:60-69` - max-version and current-version-line assertions
- `test/predicator/isa_sync_test.exs:77-104` - tier-names equality
- `test/predicator/isa_sync_test.exs:135-144` - `@isa_table_row_regex`
- `test/predicator/isa_sync_test.exs:155-183` - `@tier_table_row_regex` and the leading-paren rule
- `test/predicator/isa_sync_test.exs:185-190` - `@evaluator_clause_regex`
- `test/predicator/instructions_test.exs:102-108` - "store is currently an unknown opcode"
- `test/predicator/conformance/opcode_coverage_test.exs:25,27-58` - coverage rule and README binding
- `test/predicator/conformance/corpus_freshness_test.exs:19-83` - byte-compare and per-id drift reporting
- `test/predicator/conformance/ratchet_registry_test.exs:40-130` - rule 1, the pin, rule 2, R5
- `conformance/cases/legacy.json:1-39` - the five authored legacy cases
- `conformance/corpus/tier-1.json:29` - `errors/empty-stack-at-halt`
- `conformance/corpus/tier-1.json:35-39` - the five generated legacy cases
- `conformance/manifest.json:1` - `corpus_hash`, `isa_version: 2`, tier-1 opcodes including `and`/`or`
- `conformance/README.md:29-48` - the two surfaces and the `source: null` rule
- `conformance/README.md:186-197` - the bound exclusion section
- `conformance/RATCHET.md:102-118, 129-158, 189-211, 230-243` - example, rule 1, runner, check
- `conformance/examples/registry.example.json:46-50` - the legacy entries
- `docs/isa.md:33-35` - the retirement sentence
- `docs/isa.md:57-62` - halt, result, `empty_stack`
- `docs/isa.md:112-121, 130-137, 147-173` - table preamble, tier table, opcode table
- `docs/isa.md:234-243` - the `and`/`or` per-opcode entry
- `docs/isa.md:361-379` - section 6
- `docs/isa.md:381-395` - section 7 version history

## Architecture Documentation

- The opcode set has **five** representations that tests bind pairwise:
  `@opcodes` (the map), `docs/isa.md` section 4's opcode table,
  `docs/isa.md`'s tier-names table, `execute_instruction/2`'s clause heads, and
  `conformance/manifest.json`'s per-tier `opcodes` arrays. Only the last is
  generated; the other four are hand-maintained and bound by
  `isa_sync_test.exs`.
- Tier is computed, never authored (ADR-0003's corpus arm, via
  `docs/plans/260807-px-35i.4-conformance-corpus.md`'s "The tier check
  (mechanical, not editorial)"). There is exactly one opcode-to-tier map in the
  tree.
- Corpus cases are **completed by the real pipeline** rather than asserted
  statically, which is the property that makes an evaluator change show up as a
  corpus diff - and the same property that makes an opcode the evaluator no
  longer implements ungeneratable.
- `corpus_hash` is a single global pin over all tier files
  (`lib/mix/tasks/corpus.generate.ex:139-143`), and `RATCHET.md`'s R1 makes a
  mismatch a hard failure with no auto-refresh
  (`docs/plans/260807-px-35i.8-sibling-conformance-ratchet.md`, Open Question 3).

## ISA Impact

Neither bead changes the instruction set as executed - both are specification
work in `docs/isa.md`. What they touch is the *rules around* the set:

- **px-t2v** governs a future retirement (px-tbv.9, `["and"]`/`["or"]`). Today's
  spec says retirement "takes a major release plus an upgrade path"
  (`docs/isa.md:33-35`) and ADR-0003 says the same at `:92-97` and `:119-121`,
  but neither says whether the integer moves. Current version is ISA v2
  (`docs/isa.md:40`, `lib/predicator/instructions.ex:27`), and
  `isa_sync_test.exs:60-65` binds `isa_version/0` to the maximum version in the
  section 4 table - so a v3 row and an `@isa_version 3` must move together.
- **px-z5m** concerns two opcode names, `store` (reserved, tier 6) and `pop`
  (unreserved, unmentioned). Reserving a name is not an ISA version change under
  today's rules: `store` is reserved in section 6 with no table row, no map
  entry, and a test asserting it is unknown
  (`test/predicator/instructions_test.exs:102-108`). Actually adding either
  opcode is px-tbv.2's additive change.

## Historical Context (from docs/)

- `docs/adr/0001-keep-the-stack-vm-revise-the-instruction-set.md:74-76` - the
  original promise: "The existing `["and"]` and `["or"]` opcodes remain
  *accepted* by the evaluator, for previously compiled artifacts and for sibling
  implementations, but the Elixir compiler stops emitting them."
- `docs/adr/0001-...:83-84` - `["store", n]`, "popping n path segments plus a
  value and writing through `ContextLocation.put/3`".
- `docs/adr/0001-...:107-112` - "Statement-level control flow (`if`, `while`)
  stays possible without redesign ... The instruction list remains a flat,
  JSON-serializable artifact through every seam, including statement programs."
- `docs/adr/0001-...:116-118` - "Old compiled artifacts keep running: `["and"]`
  and `["or"]` stay accepted. A stored instruction list is never invalidated by
  this revision."
- `docs/adr/0003-the-elixir-implementation-leads-the-isa.md:113-121` - the clause
  px-t2v's item (b) turns on: "A compiled instruction list that was valid when it
  was written keeps producing the same answer, **or is refused with a message
  naming the version it needs**. It is never silently mis-run. That guarantee is
  delivered by the version stamp plus an **explicit upgrade path** ... Retiring
  an opcode is permitted at a major version when an upgrade path exists for it
  (`px-tbv.9` is the first case: `["and"]` and `["or"]`)."
- `docs/adr/0003-...:92-97` - "an **additive** ISA version ... is a minor
  release, while **retiring** an opcode is what invalidates stored artifacts and
  takes a major release plus the upgrade path below." Again silent on the
  integer.
- `docs/adr/0003-...:167-173` - "ADR-0001's promise that 'a stored instruction
  list is never invalidated by this revision' is kept, but is now discharged by
  the version stamp and an upgrade path rather than by permanent acceptance."
- `docs/adr/0003-...:191-195` - "The ISA gains a real cost it did not have: every
  change to it now owes a version bump, a `docs/isa.md` entry, a corpus tier
  assignment, and a migration note if stored artifacts are affected."
- `docs/plans/260807-px-35i.4-conformance-corpus.md:801-806` - Open Question 6,
  where the legacy cases sit and the `legacy_logical` tag as the selector for "a
  sibling ... has taken px-tbv.9's retirement early".
- `docs/plans/260807-px-35i.8-sibling-conformance-ratchet.md:98-135` - the
  registry key is a `(case_id, surface)` pair; the two surfaces have structurally
  different case sets *because* `source: null` legacy cases exist; ADR-0003
  bounds what the ratchet may oblige.
- `docs/plans/260806-px-35i.3-isa-version-stamp.md:739` - a prior, still-open
  formulation of the same question px-z5m raises from the other side: "Does
  `store` belong in the map now, at some version, so `px-tbv.2` only ...".

## Related Research

- `docs/research/260807-px-phw-conformance-area-label.md` - why
  `area:conformance` exists and why `area:build` on a corpus bead serializes the
  queue. Relevant because px-t2v carries `area:conformance, area:docs` and px-z5m
  carries `area:docs`, and the two collide on `docs/isa.md` (px-z5m's own note
  says they "batch into one worktree or run serially, not in parallel").

## Open Questions

These are questions the codebase does not answer. They are recorded, not
resolved; no human was available during this research pass.

1. **Does retirement mint a new ISA integer?** `docs/isa.md:33-35` and
   ADR-0003:92-97 both say retirement takes a major *library* release and an
   upgrade path, and neither says anything about the ISA integer. Section 7's
   history table has an "Opcodes introduced" column and no retirement column, and
   §7's definition of v1 ("the full opcode set the Elixir evaluator accepted
   before ADR-0001") is anchored to a historical evaluator rather than the live
   table. `isa_sync_test.exs:60-65` will require `@isa_version` and the table's
   maximum to move together whichever way this is settled.

2. **What is a version's opcode set once it can shrink?** §1's soundness argument
   ("scan the opcode names in a list") assumes every name maps to a version. A
   retired-but-listed opcode makes that scan still total; a deleted one does not.
   Nothing today states which set a sibling declaring "v2" is claiming if v3
   removes rows.

3. **What shape may a `removed_in:` marker take?** The binding constraints found
   are: `@isa_table_row_regex` (`isa_sync_test.exs:144`) needs column 1 to be a
   bare backticked `[a-z_]+`, column 5 exactly `v\d+`, column 6 exactly `\d+`,
   and ignores anything past column 6; `tier_row_opcodes/1` (`:174-183`) claims
   *every* backtick span in a non-paren-leading tier cell; `opcodes/0`'s `@spec`
   (`instructions.ex:77`) pins the value map to exactly `%{isa:, tier:}`; and
   `opcode_coverage_test.exs:27-39` requires a case for every key of
   `opcodes/0`. Which of those move is a design decision this document does not
   make.

4. **Is there to be a per-ISA-version corpus snapshot?** There is none today: one
   `conformance/corpus/`, one `manifest.json` with one `isa_version`, one
   `corpus_hash`. The tooling has no notion of "the v1 corpus". Whether v1
   coverage for retired opcodes lives in a frozen snapshot, in a tag/feature
   filter on the live corpus (`legacy_logical` already exists as such a tag), or
   nowhere, is unsettled.

5. **Does `empty_stack` become mode-scoped, and if so what carries the mode?**
   Section 2 states the rule unconditionally and the evaluator implements it in
   one place (`evaluator.ex:91-97`) with no mode parameter. A program is a flat
   list with no header, so nothing in the wire format distinguishes an expression
   program from a statement program - the distinction, if any, would have to come
   from the entry point (`evaluate/3` vs a future `execute/2`) rather than from
   the instruction list.

6. **Does reserving `pop` require anything beyond section 6 and the tier row?**
   `store`'s reservation today is section 6 + the tier-6 row + a test asserting
   it is *unknown* (`instructions_test.exs:102-108`). Whether `pop` gets the
   symmetric treatment, including a mirror test, is not settled by anything in
   the tree.

7. **The tier-6 cell's leading paren.** `isa_sync_test.exs:174-183` treats any
   tier cell starting with `(` as contributing zero opcodes. A tier-6 cell that
   names both `store` and `pop` must either keep that leading paren or add both
   to `@opcodes` - which would contradict `instructions_test.exs:102-108` and
   `opcode_coverage_test.exs`. This is a mechanical constraint on the wording of
   px-z5m's edit, not a design question, but it is easy to trip.
