# An `undefined` literal for the expression language

## Overview

Add `undefined` as a literal keyword to predicator's expression language, so an
author can write `x === undefined` and get a boolean answer under either
`on_unbound` policy. The literal lexes as a reserved word, parses to
`{:literal, :undefined, pos}`, lowers to the existing `["lit", :undefined]`
instruction, and renders back as `undefined`. No opcode is added and the ISA
version does not move. Bead: px-ocp.

## Current State Analysis

The research document `docs/research/260812-px-ocp-undefined-literal.md` is the
input to this plan; what follows is the part that drives the phases, plus the
behaviour re-verified in this worktree with `mix run` while planning.

**The word `undefined` is an ordinary identifier today.** It falls through
`classify_identifier/1`'s catch-all (`lib/predicator/lexer.ex:518`) and
compiles to `["load", "undefined"]`, which errors under *both* `on_unbound`
policies - the default policy errors too, via the trace-back rewrite at
`lib/predicator.ex:614-624`. That is the wall the statifier workaround hits.

**The instruction layer already does the right thing.** `["lit", value]`
pushes its operand unchanged with no error path
(`lib/predicator/evaluator.ex:489-491`, `docs/isa.md:284`), and `load` is the
only opcode that consults `on_unbound` (`lib/predicator/evaluator.ex:494-506`).
Re-verified in this worktree:

```
Predicator.evaluate([["load","x"],["lit",:undefined],["compare","STRICT_EQ"]], %{"x" => :undefined})
#=> {:ok, true}
... same instructions, on_unbound: :error                      #=> {:ok, true}
... %{"x" => nil}, on_unbound: :error                          #=> {:ok, true}   (Context normalizes nil)
[["load","m"],["access","k"],["lit",:undefined],["compare","STRICT_EQ"]], %{"m" => %{}}, on_unbound: :error
#=> {:ok, true}
[["lit",:undefined]], %{}, on_unbound: :error                  #=> {:ok, :undefined}
```

One boundary is worth stating because the bead's phrasing invites a wrong
reading: with `x` genuinely **unbound** and `on_unbound: :error`, the whole
expression still errors - the `load` of `x` fails before the comparison
happens. That is what `on_unbound: :error` *means*, and no literal can change
it. What the literal fixes is the sentinel itself no longer being an unbound
load. The statifier case is a *declared-but-undefined* variable (its engine
half seeds `_event` that way, st-unt), which is a bound key holding
`:undefined`, and that works under both policies.

**Where the work is**, then:

- `lib/predicator/lexer.ex:497-518` - `classify_identifier/1` is the
  reserved-word table, a flat clause set. The `handle_regular_identifier/6`
  function-call veto (`:535-545`) picks up a new keyword automatically.
- `lib/predicator/lexer.ex:40-92` - the `token()` typespec union.
- `lib/predicator/parser.ex:1363-1366` - the boolean primary clause is the
  exact model for a new literal clause.
- `lib/predicator/parser.ex:1559-1601` - `format_token/2` is an exhaustive
  clause set with **no catch-all**. A new token type that reaches it raises
  `FunctionClauseError`, and `user.undefined` and `{undefined: 1}` both reach
  it. This is the easiest thing in the change to miss.
- `lib/predicator/parser.ex:122-129` - the parser-local `value()` type.
- `lib/predicator/visitors/string_visitor.ex:120-164` - guard-dispatched
  render clauses with no catch-all. Verified today:
  `Predicator.Compiler.to_string({:literal, :undefined, nil})` raises
  `FunctionClauseError`.
- `lib/predicator/visitors/instructions_visitor.ex:174-176` - generic over the
  `{:literal, value, pos}` tag. **Needs no change.**
- `lib/predicator/evaluator.ex` - **needs no change.**

**px-aen is closed** (2026-08-11, PR #136), and it did *not* add catch-alls:
it landed real clauses for `{:if, ...}`/`{:block, ...}`/`{:while, ...}` and
px-kbe bound the result with `test/predicator/visitor_clause_coverage_test.exs`,
which compares `Parser.visitable/0`'s 23 tuple *constructors* against each
visitor's clause *tags*. Adding a clause for a new *value shape* inside the
existing `:literal` tag changes neither side of that comparison, so there is
no sequencing constraint between px-ocp and px-aen in either direction. See
"Sequencing against px-aen" below.

**The corpus does not carry `on_unbound`.** `conformance/README.md:278` puts
it outside the corpus's scope, and `conformance/schema/case.json` has no field
for it, so the two-policy claim is ExUnit's job and the corpus's job is the
compiled form and the default-policy result.

**Adding a tier-1 corpus case has a second consequence.**
`test/predicator/conformance/ratchet_registry_test.exs` pins
`conformance/examples/registry.example.json` to the manifest's `corpus_hash`
*and* enforces RATCHET.md rule R5 - the example claims
`{"surface":"evaluator","tier":1}`, so every tier-1 case must have an
evaluator entry. There is no mix task that regenerates the example; it must be
rewritten in the same canonical encoding the test re-implements
(`ratchet_registry_test.exs:152-172`).

### Key Discoveries:

- `["lit", :undefined]` already evaluates correctly under both policies -
  `lib/predicator/evaluator.ex:489-491` matches on the opcode name only, and
  `docs/isa.md:284` says so normatively.
- `docs/isa.md:165-168` (§3) already lists `:undefined` in the ISA's value
  domain, so `lit`'s accepted operand set does not change.
- `docs/isa.md:661-679` (§6) puts surface syntax outside the ISA, with the
  `=`/`==` case as the worked example.
- `Predicator.Instructions.required_isa/1`
  (`lib/predicator/instructions.ex:294-303`) computes a version by scanning
  **opcode names** and taking the max. A version integer with no new name
  attached to it is unreachable by that scan.
- `true`/`false` are the precedent for a literal keyword and they are
  *reserved*: verified today, `Predicator.parse("true = 3")`,
  `Predicator.parse("user.true")` and `Predicator.parse("{true: 1}")` are all
  parse errors, with `{"true": 1}` still parsing.
- The cast type names (`lib/predicator/cast.ex:20-27`, ADR-0011) are the
  *contextual* precedent, and they are contextual only because `::` makes the
  position unambiguous.
- ADR-0004: errors are values. A new rejection must arrive as a `ParseError`,
  never a raise - which is why `format_token/2` must gain its clause.
- ADR-0003: an opcode's semantics never change under its own name. This is
  what forecloses redefining `compare`/`EQ` for `undefined`.

## Desired End State

`undefined` is a literal keyword of the language.

- `Predicator.compile("x === undefined")` returns
  `{:ok, [["load","x"], ["lit", :undefined], ["compare","STRICT_EQ"]]}`.
- `Predicator.evaluate("x === undefined", %{"x" => :undefined})` is `{:ok, true}`
  under the default policy and under `on_unbound: :error`.
- `Predicator.evaluate("user.missing === undefined", %{"user" => %{}})` is
  `{:ok, true}` under both policies.
- `Predicator.evaluate("x == undefined", %{"x" => 1})` is `{:ok, :undefined}` -
  the non-strict operators keep propagating, unchanged.
- `Predicator.decompile/2` renders the node back as `undefined`, and
  `parse |> decompile |> parse` is a fixpoint.
- `undefined = 3`, `user.undefined`, and `{undefined: 1}` are `ParseError`
  values with the same shapes `true`/`false` produce; `{"undefined": 1}` still
  parses; `UNDEFINED` and `Undefined` stay ordinary identifiers.
- The ISA version is still 6, `conformance/manifest.json`'s `isa_version` is
  still 6, and `docs/isa.md`'s opcode table is unchanged.
- The corpus, `docs/architecture.md`'s grammar, `docs/reference/language.md`,
  and `CHANGELOG.md` all describe the literal.

Verified by: `mix quality` green on each phase, plus the manual checks each
phase lists.

## ISA Impact

**1. Version - no. The ISA stays at v6.** Three independent reasons, any one
of which is sufficient:

- *Nothing widens.* `docs/isa.md:33-34`'s rule is about what the ISA
  **accepts**: "adding an operand form or widening an accepted type is a new
  version but not a new name". `lit`'s operand is documented as "value"
  (`docs/isa.md:226`), §3's value domain already contains `:undefined`
  (`docs/isa.md:165-168`), and this build already executes
  `["lit", :undefined]` correctly. The set of instruction lists a conformant
  v6 implementation must run is exactly the same before and after this change.
  What changes is only which of those lists *this compiler emits from source*.
- *§6 is on point, with a worked example.* `docs/isa.md:661-679` excludes
  surface syntax from the ISA and uses `=`/`==` to show what that looks like:
  two spellings, one instruction, difference entirely at the parser layer.
  `undefined` is the same shape - a new spelling for an instruction that
  already existed.
- *A bump would mint an unreachable version.* `required_isa/1`
  (`lib/predicator/instructions.ex:294-303`) computes a list's required
  version as `max` over `@opcodes[name].isa`. A v7 whose only content is "the
  compiler now emits an operand it could always execute" attaches to no opcode
  name, so no instruction list would ever report requiring it, and
  `opcode_set(7)` would equal `opcode_set(6)`. ADR-0003 makes the name scan a
  *sound* answer to "what version does this list require"; minting a version
  that the scan can never produce degrades that soundness for no benefit.

**Full consequent obligation list: none is engaged.** Stated explicitly so
implementation is unambiguous - do **not** touch any of these:

| Site | Action |
|---|---|
| `docs/isa.md:58` `Current version: **ISA v6**.` | unchanged |
| `docs/isa.md:191-195` version-assignment prose | unchanged |
| `docs/isa.md:224-256` §4 opcode table (ISA / tier / Removed-in columns) | unchanged |
| `docs/isa.md:681-690` §7 version-history table | unchanged - no new row |
| `lib/predicator/instructions.ex:45` `@isa_version 6` | unchanged |
| `lib/predicator/instructions.ex:64-96` `@opcodes` | unchanged - no new name |
| `test/predicator/isa_sync_test.exs` `@opcode_count 31` | unchanged |
| `conformance/manifest.json` `isa_version` | stays `6` (regenerated, never hand-edited) |
| `lib/predicator/instructions/upgrade.ex` | untouched - nothing retired |
| `CHANGELOG.md` ISA-version wording | none - the entry names a language feature, not an ISA version |

**2. Stamp.** No opcode subsection, no version entry, no new tier. Two
clarifying prose edits to `docs/isa.md` are in scope in Phase 3, both outside
every table the sync test parses (its regexes are anchored to table rows -
`isa_sync_test.exs:216,232,270`):

- §5's `lit` paragraph gains a sentence saying the operand may be any value in
  §3's domain, `:undefined` included, and that a source spelling for it exists
  as of this change.
- §6's surface-syntax bullet gains `undefined` as a second worked example
  beside `=`/`==`.

**3. Migration.** None. No stored instruction list changes meaning; no
instruction list becomes invalid; nothing is retired. A sibling at v6 that
already implements `lit` per §3's value domain needs no change to run the new
corpus cases - and if it does fail them, the corpus has surfaced a
pre-existing v6 conformance gap in that sibling, not a new obligation.

## What We're NOT Doing

- **Not bumping the ISA version, and not adding an opcode.** Argued above.
- **Not changing `==`/`!=` semantics for `:undefined`.** `x == undefined`
  stays `:undefined` (propagation, `lib/predicator/evaluator.ex:748-754`);
  `x === undefined` is the boundness test. Beyond the design argument that a
  three-valued `==` is what the strict operators exist to avoid, ADR-0003
  forbids it mechanically: changing the answer `compare`/`EQ` produces for an
  existing operand pair is a **new opcode name at a new ISA version**, never a
  redefinition. That is a much larger change than this bead, and nothing asks
  for it. Phase 3 documents the distinction instead.
- **Not making `undefined` a contextual keyword.** See Phase 1's rationale.
- **Not changing the parser's expected-token error string**
  (`lib/predicator/parser.ex:1444-1448`, "number, string, boolean, date,
  datetime, identifier, function call, list, object, or '('"). It enumerates
  token *categories*, not spellings - `true` and `false` are covered by
  "boolean" and are not named either - and dozens of tests assert it verbatim,
  so widening it would churn a large diff for no user-visible gain.
- **Not adding a catch-all clause to `StringVisitor` or
  `InstructionsVisitor`.** px-aen is closed and deliberately landed real
  clauses rather than a fallback; this change follows that by adding a real
  clause for the new value shape.
- **Not solving the plain-JSON round-trip ambiguity.** `Jason.encode(["lit",
  :undefined])` is `["lit","undefined"]`, indistinguishable from a string
  operand - but that is true today of `Date`, `DateTime`, and `duration`
  operands as well, nothing in `lib/` serializes instruction lists, and the
  corpus has its own tagged encoding. Filed as **px-a2w** rather than widened
  into here.
- **Not updating `docs/reference/ast.md`.** It lists node *constructors* and
  defers value details to `t:Predicator.Parser.ast/0`, whose typedoc Phase 1
  updates; no arm changes shape.
- **Not adding `undefined` to `docs/guides/porting.md`'s compressed rules.**
  Porting guidance is about the ISA and `on_unbound`, neither of which moves.

## Implementation Approach

Three phases, along the pipeline seams the project extension names, each
independently committable and gate-verifiable:

1. **The literal** - lexer, parser, both visitors' obligations, typespecs, and
   the full test set including reserved-word breakage. The project extension
   is explicit that a grammar change `StringVisitor` cannot render back is
   incomplete, never a follow-up, so the round-trip lands here.
2. **The corpus** - authored cases, `mix corpus.generate`, and the ratchet
   example the regenerated hash invalidates. Split from Phase 1 because it
   moves the exported specification (ADR-0003) and wants its own reviewable
   diff and its own commit-message explanation, not because Phase 1 is
   incomplete without it.
3. **The documentation** - grammar, language reference, the two `docs/isa.md`
   prose clarifications, and `CHANGELOG.md`.

Phase 2 depends on Phase 1 (its `source` fields must compile). Phase 3 depends
on Phase 1 for accuracy. Phases 2 and 3 are independent of each other.

### Sequencing against px-aen

None required: px-aen closed on 2026-08-11 (PR #136), and its successor
guard - `test/predicator/visitor_clause_coverage_test.exs` (px-kbe) - compares
`Parser.visitable/0`'s constructor tags against each visitor's clause tags.
Phase 1 adds a clause under the existing `:literal` tag and adds no
constructor, so both sides of that test are unchanged and its
`@constructor_count 23` stays 23. The only surface the two beads share is
`string_visitor.ex`, and they touch different clause groups.

---

## Phase 1: The literal - lexer, parser, and round-trip

### Overview

`undefined` becomes a reserved literal keyword that parses to
`{:literal, :undefined, pos}` and renders back as `undefined`.

**Reserved word, not contextual keyword.** The two precedents in this codebase
are `true`/`false` (reserved, in `classify_identifier/1`) and the seven cast
type names (contextual, ADR-0011). The cast names can be contextual because
`::` makes their position unambiguous - `x::integer` and `integer > 1` never
compete. `undefined` appears in ordinary primary-expression position, exactly
where an identifier may also appear, so there is no delimiter to key off: a
contextual reading would need the parser to decide between a literal and a
variable reference from the same token in the same position, which is not
decidable and would make `x === undefined` mean different things depending on
whether a variable named `undefined` happened to be bound. `undefined` is a
literal, and every other literal keyword in this language is reserved.

**What it breaks**, matching `true`/`false` exactly (all three verified in
this worktree against `true`):

| Source | Before | After |
|---|---|---|
| `Predicator.parse("undefined = 3")` | parses as `load`/`lit`/compare error path | `"'=' is not an equality operator - use '==' for equality. Assignment is only valid at the start of a statement."` at `{1, 11}` |
| `Predicator.parse_program("undefined = 3")` | assignment to a variable named `undefined` | `"Left side of '=' must be an assignable location - an identifier, a property access, or a bracket access."` |
| `Predicator.parse("user.undefined")` | property access | `"Expected property name after '.' but found 'undefined'"` |
| `Predicator.parse("{undefined: 1}")` | object with key `undefined` | `"Expected identifier or string for object key but found 'undefined'"` |
| `Predicator.parse(~s({"undefined": 1}))` | parses | still parses |
| `UNDEFINED`, `Undefined` | identifiers | still identifiers |

Only the lowercase spelling is reserved, matching `true`/`false` (the lexer
has no `TRUE` clause).

### Changes Required:

#### 1. Lexer
**File**: `lib/predicator/lexer.ex`
**Changes**: one clause in the reserved-word table, plus the two typespecs it
touches. Nothing else - `handle_regular_identifier/6`'s function-call veto
(`:535-545`) already refuses to turn any classified keyword into a
`:function_name`, so `undefined(1)` is handled for free.

```elixir
# beside the boolean clauses at the head of the table
defp classify_identifier("undefined"), do: {:undefined, :undefined}
```

- Widen `classify_identifier/1`'s `@spec` return to
  `{atom(), binary() | boolean() | :undefined}` - dialyzer will otherwise
  reject the new clause.
- Add `{:undefined, pos_integer(), pos_integer(), pos_integer(), :undefined}`
  to the `token()` union (`:40-92`), beside the `:boolean` arm, with the same
  doc-comment style as its neighbours.

The token type is named `:undefined` rather than `:undefined_kw` to sit with
the other *literal* token types (`:boolean`, `:date`, `:datetime`); `_kw` in
this lexer marks statement keywords and `_op` marks operators.

#### 2. Parser
**File**: `lib/predicator/parser.ex`
**Changes**: one primary-expression clause, one `format_token/2` clause, one
typespec.

```elixir
# immediately after the boolean clause at :1363-1366
# Parse the undefined literal
defp parse_primary_token(state, {:undefined, _line, _col, _len, _value} = token) do
  {:ok, {:literal, :undefined, leaf_loc(state, token)}, advance(state)}
end
```

```elixir
# with the other keyword clauses near :1599
defp format_token(:undefined, _value), do: "'undefined'"
```

`format_token/2` is **required, not optional**: it has no catch-all, and both
`user.undefined` (`:1284`) and `{undefined: 1}` (`:1773`) route their error
message through it. Without the clause those two inputs raise
`FunctionClauseError` instead of returning a `ParseError`, which is the
ADR-0004 breach this change must not introduce.

Add `| :undefined` to the parser-local `value()` type (`:122-129`) and name it
in that type's `@typedoc`.

#### 3. StringVisitor
**File**: `lib/predicator/visitors/string_visitor.ex`
**Changes**: one clause, placed beside the boolean clause at `:126-128`.

```elixir
defp do_visit({:literal, :undefined, _position}, _opts), do: "undefined"
```

Order is not load-bearing (`:undefined` satisfies none of the neighbouring
guards and matches neither struct pattern), but it belongs with the other
keyword-rendered literal. This also covers `:undefined` nested in a list
literal, since the `is_list(value)` clause (`:152-156`) recurses through
`do_visit/2`.

#### 4. `InstructionsVisitor` and the evaluator
**Files**: `lib/predicator/visitors/instructions_visitor.ex`,
`lib/predicator/evaluator.ex`
**Changes**: **none.** Stated so the implementer does not go looking. The
instructions visitor matches the `:literal` tag generically (`:174-176`) and
`execute_instruction(_, ["lit", value])` matches the opcode name only
(`:489-491`).

#### 5. Tests
**Files**:
- `test/predicator/lexer_test.exs` - `undefined` tokenizes as
  `{:undefined, 1, 1, 9, :undefined}`; `UNDEFINED` and `Undefined` tokenize as
  `:identifier`; `undefined(` does not produce a `:function_name`.
- `test/predicator/parser_test.exs` - `undefined` parses to
  `{:literal, :undefined, pos}` with the right position; `[undefined, 1]` and
  `{k: undefined}` parse.
- `test/predicator/reserved_words_test.exs` - a `describe` block per breakage
  row above, following the file's existing four-entry-point shape
  (`parse/2`, `parse_program/2`, `evaluate/3`, `compile/1`), plus the
  `{"undefined": 1}` still-parses test.
- `test/predicator/visitors/string_visitor_test.exs` - renders `"undefined"`;
  a `parse -> decompile -> parse` fixpoint for `x === undefined` and for
  `[undefined]`.
- `test/predicator/integration/on_unbound_test.exs` - the two-policy matrix:
  `x === undefined` with `x` bound to `:undefined`, with `x` bound to `nil`
  (Context normalizes), with `x` bound to `1`, and `user.missing === undefined`
  with `user` bound to `%{}` - each under the default policy and under
  `on_unbound: :error`, all four `{:ok, boolean}`. Plus the honest boundary:
  `x === undefined` with `x` genuinely unbound is `{:ok, true}` under the
  default policy and `{:error, %UndefinedVariableError{}}` under `:error`,
  because the `load` fails first.
- `test/predicator/integration/full_pipeline_test.exs` - `x == undefined`
  with `x` bound to `1` is `{:ok, :undefined}`; `x = undefined` through
  `Predicator.execute/2` binds `x` to `:undefined`.

### Success Criteria:

#### Automated Verification:
- [x] `mix quality` is green.
- [x] New and changed lines stay above the 90% coverage minimum in
      `coveralls.json` (the gate's coverage stage decides this).
- [x] `test/predicator/visitor_clause_coverage_test.exs` still passes with
      `@constructor_count 23` unchanged - no AST constructor was added.
- [x] `test/predicator/isa_sync_test.exs` still passes with no edit to it -
      no opcode, version, or tier moved.
- [x] A test in `test/predicator/integration/full_pipeline_test.exs` asserts
      `Predicator.compile("x === undefined") ==
      {:ok, [["load","x"],["lit",:undefined],["compare","STRICT_EQ"]]}`.
- [x] A test in `test/predicator/visitors/string_visitor_test.exs` asserts the
      `parse -> decompile` round-trip of `"x === undefined"` is `"x === undefined"`.

#### Manual Verification:
- [ ] `Predicator.parse("user.undefined")` and
      `Predicator.parse("{undefined: 1}")` return `{:error, message, line, col}`
      tuples - not a `FunctionClauseError`. This is the `format_token/2` clause
      being real, and a raise here is the ADR-0004 breach.
- [ ] The three breakage messages read as helpful to someone who used
      `undefined` as a variable name, and match the `true`/`false` shapes in
      the table above.
- [ ] `mix quality`'s dialyzer stage raised nothing about the widened
      `classify_identifier/1` and `value()` specs.

**Implementation Note**: Use `mix quality --profile loop` between edits and
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

## Phase 2: Conformance corpus

### Overview

Pin the literal into the exported specification: five authored cases, the
regenerated corpus, and the ratchet example the new `corpus_hash` invalidates.

The corpus can pin what `undefined` **compiles to** and what it **evaluates
to** under the default policy. It cannot pin that `undefined` lexes as a
keyword: surface syntax and parse errors are outside its scope
(`conformance/README.md:14-24`, `docs/isa.md:704-719`), and it carries no
`on_unbound` field (`conformance/README.md:278`,
`conformance/schema/case.json`). Phase 1's ExUnit tests are where those two
claims live, and that split is deliberate.

### Changes Required:

#### 1. Authored cases
**File**: `conformance/cases/core.json` (tier 1 - `lit`, `load`, `compare`)
**Changes**: four cases appended in the file's existing style.

```json
{
  "id": "core/literal-undefined",
  "source": "undefined",
  "expected": { "result": { "$type": "undefined" } },
  "notes": "the undefined literal (px-ocp): a source spelling for a lit operand the ISA's value domain already admitted (docs/isa.md section 3), so no ISA version moves - surface syntax is outside the ISA (section 6)"
},
{
  "id": "core/undefined-strict-eq-undefined",
  "source": "undefined === undefined",
  "expected": { "result": true }
},
{
  "id": "core/undefined-strict-ne-int",
  "source": "undefined !== 1",
  "expected": { "result": true }
},
{
  "id": "core/undefined-eq-propagates",
  "source": "undefined == undefined",
  "expected": { "result": { "$type": "undefined" } },
  "notes": "the non-strict operators propagate :undefined rather than answering (docs/reference/language.md, reject vs. propagate) - === is the boundness test, == is not"
}
```

**File**: `conformance/cases/access.json` (tier 3 - adds `access`)
**Changes**: one case, the statifier-shaped boundness test.

```json
{
  "id": "access/missing-key-strict-eq-undefined-literal",
  "source": "user.missing === undefined",
  "context": { "user": {} },
  "expected": { "result": true },
  "notes": "an absent key compared against the undefined literal - the boundness test px-ocp exists for. The literal lowers to lit, never load, so it is unaffected by on_unbound (an evaluation option outside this corpus's scope)"
}
```

`instructions`, `tier`, and `features` are computed by the generator; the
authored case supplies only `id`/`source`/`context`/`expected`/`notes`, and
generation fails loudly if `expected` disagrees with the real pipeline.

#### 2. Regenerate
**Files**: `conformance/corpus/tier-1.json`, `conformance/corpus/tier-3.json`,
`conformance/manifest.json`
**Changes**: `mix corpus.generate`. Never hand-edited. Expect tier-1's
`case_count` 49 -> 53, tier-3's 25 -> 26, a new `corpus_hash`, and
`isa_version` still `6` (if it is not 6, something in Phase 1 went wrong -
stop).

#### 3. Ratchet example
**File**: `conformance/examples/registry.example.json`
**Changes**: the new `corpus_hash`, plus one `{"case_id":...,"surface":"evaluator","tier":1}`
entry per new **tier-1** case, inserted in RATCHET.md's sort order (surface,
then tier, then `case_id`, all ascending by codepoint). The tier-3 case needs
no entry - the example claims `{"surface":"evaluator","tier":1}` only.

This file is not optional cleanup: `ratchet_registry_test.exs` goes red
without it, on both the pin (`:81`) and R5 completeness (`:112`). No mix task
generates it; produce it with a throwaway `mix run` script that mirrors the
canonical encoding the test re-implements at
`ratchet_registry_test.exs:152-172` (sorted top-level keys, one array element
per line via `Predicator.Conformance.JSON.encode_canonical/1`, exactly one
trailing newline), then delete the script.

### Success Criteria:

#### Automated Verification:
- [ ] `mix quality` is green - in particular
      `test/predicator/conformance/corpus_freshness_test.exs` (the corpus on
      disk is byte-identical to what `mix corpus.generate` writes) and
      `test/predicator/conformance/ratchet_registry_test.exs` (schema, pin,
      canonical encoding, R5 completeness).
- [ ] `mix corpus.generate` run a second time produces no diff.
- [ ] `conformance/manifest.json` still reports `"isa_version":6`.
- [ ] `git diff --stat conformance/` touches only `cases/core.json`,
      `cases/access.json`, `corpus/tier-1.json`, `corpus/tier-3.json`,
      `manifest.json`, and `examples/registry.example.json`.

#### Manual Verification:
- [ ] The corpus diff is reviewed line by line and is exactly the five new
      cases plus the manifest's hash and two case counts - no unrelated case
      re-ordered or re-encoded.
- [ ] The commit message and the PR body explain the corpus diff, per
      ADR-0003 and CLAUDE.md's conventions, stating that the exported
      specification gained a source spelling and that the ISA version did not
      move.
- [ ] A sibling reading `core/literal-undefined` can tell from `instructions`
      and `notes` that no new opcode is involved.

**Implementation Note**: Use `mix quality --profile loop` between edits and
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

## Phase 3: Documentation and changelog

### Overview

Every place that enumerates the language's literals, its reserved words, or
where `:undefined` comes from, plus the user-facing entry.

### Changes Required:

#### 1. Grammar
**File**: `docs/architecture.md`
**Changes**: in the EBNF (`:20-48`), add `UNDEFINED` to the `primary`
production, beside `BOOLEAN`:

```text
primary      → NUMBER | FLOAT | STRING | BOOLEAN | UNDEFINED | DATE | DATETIME | IDENTIFIER | duration | relative_date | list | object | function_call | "(" expression ")"
```

Precedence is untouched - a literal is a `primary`, the lowest-level
production, and no operator or associativity changes. (The project extension
requires checking the precedence table before proposing syntax; this is that
check, and the answer is that the table needs no edit.)

#### 2. Language reference
**File**: `docs/reference/language.md`
**Changes**, four sites:

- `## Data Types` (`:8-25`): a bullet after Booleans -
  `**Undefined**: `undefined` - the absent/unset value; see "Undefined and
  Sparse Data" below`.
- `### Reserved words` (`:392-396`): add `undefined` and say what it breaks
  (variable name, bare property name, bare object key), that a quoted key
  still works, and that it joins `true`/`false` as a literal keyword - the
  section currently names only the three statement keywords.
- `### Where :undefined comes from` (`:563-588`): add the literal as a fourth
  source, and note it is the only one that is *not* a load, which is why it is
  unaffected by `on_unbound`.
- A new subsection under `## Undefined and Sparse Data` (near
  `### Reject vs. propagate, per operator`, `:643-662`): **testing whether a
  value is undefined**. It must say, plainly:
  - `x === undefined` is the boundness test and answers `true`/`false`.
  - `x == undefined` is **not** - the non-strict operators propagate, so it
    evaluates to `:undefined` (falsy), and if `x` is an unbound root the
    top-level result is an `UndefinedVariableError` under either policy via
    the trace-back rewrite. This is decision 3 of the plan and the docs are
    where it is stated.
  - The literal itself is never affected by `on_unbound`, because it compiles
    to `lit` and only `load` consults the policy.
  - The remaining boundary: `x === undefined` on a *genuinely unbound root*
    under `on_unbound: :error` still errors, because the `load` of `x` fails
    before the comparison. To test a variable that may not exist at all under
    `:error`, bind it as declared-but-undefined, or reach it through a bound
    container (`ctx.maybe === undefined`).

#### 3. ISA prose
**File**: `docs/isa.md`
**Changes**: the two clarifications named in "ISA Impact" - a sentence in §5's
`lit` paragraph (`:284`) and `undefined` added as a second example in §6's
surface-syntax bullet (`:661-679`). **No table row, no version, no tier.**
The sync test's regexes are anchored to table rows
(`isa_sync_test.exs:216,232,270`), so prose is safe; re-run the gate to
confirm rather than assuming.

#### 4. Changelog
**File**: `CHANGELOG.md`
**Changes**: two entries under `## [Unreleased]`, modelled on the existing
pair - the cast entry (`:83-97`) for a language feature, the reserved-words
entry (`:146-154`) for the break.

Under `### Added`: the literal, what it compiles to (`["lit", :undefined]`),
that `x === undefined` works under both `on_unbound` policies, that
`x == undefined` propagates instead of answering, and that **the ISA version
does not move** because surface syntax is outside the ISA (`docs/isa.md` §6)
and `lit` already accepted the operand.

Under `### Changed`: `undefined` is a reserved word - variable name, bare
property name, and bare object key are now parse errors; the fix is renaming
or quoting the key; only the lowercase spelling is reserved.

### Success Criteria:

#### Automated Verification:
- [ ] `mix quality` is green - `test/predicator/isa_sync_test.exs` in
      particular, since `docs/isa.md` was edited.
- [ ] `grep -n "undefined" docs/architecture.md docs/reference/language.md
      CHANGELOG.md` shows a hit in each of the four sites above.
- [ ] `git diff docs/isa.md` shows no changed line beginning with `| \``  -
      no opcode-table, tier-table, or version-history row moved.

#### Manual Verification:
- [ ] The `x == undefined` versus `x === undefined` distinction is
      unambiguous to a reader who has not read this plan.
- [ ] The `on_unbound: :error` boundary is stated honestly - a reader must not
      come away believing `x === undefined` rescues a genuinely unbound root
      under `:error`.
- [ ] The changelog break entry gives a fix, matching the tone of the
      `if`/`else`/`while` entry.
- [ ] The grammar production reads correctly against the rest of the EBNF.

**Implementation Note**: This phase touches no Elixir code, so per CLAUDE.md
it may commit on review of the diff alone - but `mix quality` is still run,
because `docs/isa.md` is under a binding test. In interactive execution, pause
here for the human to confirm the manual testing. In looped (`--loop`)
execution, this phase's Automated Verification gates advancement automatically
(via `/wurk:commit --auto`), and Manual Verification items are deferred and
surfaced once at the end.

---

## Testing Strategy

### Unit Tests:

- **Lexer** (`test/predicator/lexer_test.exs`): classification of
  `undefined`, non-classification of `UNDEFINED`/`Undefined`/`undefined_x`/
  `x_undefined`, and the function-call veto for `undefined(`.
- **Parser** (`test/predicator/parser_test.exs`): the literal node and its
  position; the literal inside a list and as an object value; `undefined` as
  the operand of `===`, `!==`, `==`, `!`, and `::string`.
- **Reserved words** (`test/predicator/reserved_words_test.exs`): the four
  breakage inputs across all four entry points, plus `{"undefined": 1}`
  parsing. This file's four-entry-point `describe` shape is the pattern to
  copy - the point is that the same rejection reaches a user through
  `parse/2`, `parse_program/2`, `evaluate/3`, and `compile/1` alike.
- **StringVisitor** (`test/predicator/visitors/string_visitor_test.exs`):
  rendering, and a parse/decompile/parse fixpoint (the project extension
  requires a new grammar node to round-trip without information loss).
- **Edge cases that actually bite**: `!undefined` is a `TypeMismatchError`
  (`not` requires `is_boolean`, `lib/predicator/evaluator.ex:827-836`);
  `undefined in [1,2]` is `:undefined` (membership short-circuits,
  `:846-850`); `undefined AND true` is falsy, not an error
  (`jump_if_falsy_or_pop`, `:1642-1654`). None of these is new behaviour -
  they are the existing `:undefined` semantics now reachable from source, and
  a test each keeps them from drifting.

### Integration Tests:

In `test/predicator/integration/`, through `Predicator.evaluate/3` and
`Predicator.execute/2`:

- `test/predicator/integration/on_unbound_test.exs` - the two-policy matrix
  from Phase 1, including the honest unbound-root boundary.
- `test/predicator/integration/full_pipeline_test.exs` - `x == undefined`
  propagation with `x` bound; `x = undefined` as an assignment statement
  binding `x` to `:undefined`; source -> instructions -> result end to end.

### Manual Testing Steps:

1. `iex -S mix`, then `Predicator.evaluate("x === undefined", %{"x" => nil},
   on_unbound: :error)` - expect `{:ok, true}` (Context normalizes `nil`).
2. `Predicator.evaluate("x === undefined", %{}, on_unbound: :error)` - expect
   `{:error, %UndefinedVariableError{variable: "x"}}`, and confirm the plan's
   documented boundary matches.
3. `Predicator.parse("user.undefined")` and `Predicator.parse("{undefined: 1}")`
   - expect `{:error, message, line, col}`, never a raise.
4. `Predicator.decompile(elem(Predicator.parse("[undefined, 1]"), 1))` -
   expect `"[undefined, 1]"`.
5. Re-read the corpus diff from Phase 2 as a sibling implementer would: does
   `core/literal-undefined` make clear that no new opcode is involved?

## References

- Source document: `docs/research/260812-px-ocp-undefined-literal.md`
- Related ADRs: `docs/adr/0003-the-elixir-implementation-leads-the-isa.md`
  (the ISA moves when this repo needs it to; an opcode's semantics never
  change under its own name),
  `docs/adr/0004-no-eval-errors-are-values.md` (the `format_token/2`
  obligation), `docs/adr/0011-casts-are-an-opcode.md` (the contextual-keyword
  precedent this plan declines to follow),
  `docs/adr/0013-*` via `CHANGELOG.md:146-154` (the reserved-word break
  template)
- Specification: `docs/isa.md` §1 (versioning rules), §3 (the value domain),
  §5 (`lit`), §6 (not in the ISA)
- Similar implementation: `lib/predicator/parser.ex:1363-1366` (the boolean
  primary clause), `lib/predicator/lexer.ex:497-518` (the reserved-word
  table), `lib/predicator/visitors/string_visitor.ex:126-128` (the boolean
  render clause)
- Corpus contract: `conformance/README.md`, `conformance/RATCHET.md`,
  `test/predicator/conformance/ratchet_registry_test.exs:152-172` (the
  canonical encoding)
- Beads: px-ocp (this plan); mirrors statifier `st-unt`. The st-unt status
  cited here rests on the dated reconciliation note already on px-ocp
  ("2026-08-12 reconciliation (re-read st-unt before planning px-ocp)"), which
  is what CLAUDE.md's mirror rule requires before planning against a mirrored
  bead - it closes the research document's Open Question 7. That re-read found
  st-unt open, its engine half landed, and its notation half taking
  `_ioprocessors.__absent__` as a local fix explicitly **not** blocked on this
  bead. When this lands, `st-unt` gets a note that the workaround is
  revertible. px-a2w (filed during this planning, `area:docs`, P3) carries the
  plain-JSON round-trip question out of scope.

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] `Predicator.parse("user.undefined")` and
      `Predicator.parse("{undefined: 1}")` return `{:error, message, line, col}`
      tuples - not a `FunctionClauseError`. This is the `format_token/2` clause
      being real, and a raise here is the ADR-0004 breach.
- [ ] The three breakage messages read as helpful to someone who used
      `undefined` as a variable name, and match the `true`/`false` shapes in
      the table above.
- [ ] `mix quality`'s dialyzer stage raised nothing about the widened
      `classify_identifier/1` and `value()` specs.

**Implementation Note**: Use `mix quality --profile loop` between edits and
full `mix quality` as the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---
