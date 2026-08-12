---
date: 2026-08-12T07:50:16-0600
researcher: Claude
git_commit: 2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1
branch: px-ocp-undefined-literal
repository: predicator-ex
beads_issue: px-ocp
topic: "An undefined literal for the expression language"
tags: [research, codebase, lexer-parser, evaluator, isa]
status: complete
last_updated: 2026-08-12
last_updated_by: Claude
---

# Research: An undefined literal for the expression language

**Date**: 2026-08-12T07:50:16-0600
**Git Commit**: 2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1
**Branch**: px-ocp-undefined-literal
**Bead**: px-ocp

## Research Question

px-ocp asks for a way to *write down* the undefined value in predicator's
expression language. `:undefined` is reachable as a result today - an absent
map key, a `nil` normalized by `Context.new/2`, a failed cast, a mismatched
comparison - but there is no literal an expression author can type. The bead
names the interaction with `on_unbound: :error` as the whole point: the
literal must not be reachable via the unbound-variable path, or it inherits
the problem the statifier workaround already has.

This document describes what exists today: how a keyword literal flows lexer
-> parser -> AST -> instructions -> evaluator, how `:undefined` is produced
and compared, what the ISA, corpus, and documentation obligations are, and
what the word `undefined` does in a predicate right now.

## Summary

**What the word `undefined` does today.** Nothing special. It is not in the
lexer's reserved-word table, so it lexes as an ordinary identifier and
compiles to a `load`. Verified in this worktree:

```
Predicator.compile("x == undefined")
#=> {:ok, [["load", "x"], ["load", "undefined"], ["compare", "EQ"]]}

Predicator.evaluate("x == undefined", %{"x" => 1})
#=> {:error, %UndefinedVariableError{variable: "undefined", position: {1, 6}}}

Predicator.evaluate("x == undefined", %{"x" => 1}, on_unbound: :error)
#=> {:error, %UndefinedVariableError{variable: "undefined", position: {1, 6}}}
```

Note the default policy errors too. That is not `on_unbound` - it is the
trace-back rule at [`lib/predicator.ex:614-624`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator.ex#L614-L624), which rewrites a bare
`:undefined` result into an `UndefinedVariableError` when the value traces to
a root this evaluation loaded and did not find bound. So the identifier
sentinel workaround the bead describes fails under *both* policies at the top
level, not only under `:error`.

**The instruction layer already answers the bead's crux.** `["lit", value]`
pushes its operand unchanged with no error path ([`docs/isa.md:284`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/isa.md#L284),
[`lib/predicator/evaluator.ex:489-491`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/evaluator.ex#L489-L491)), and `on_unbound` is consulted by
exactly one opcode - `load` ([`lib/predicator/evaluator.ex:498`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/evaluator.ex#L498)). Verified:

```
Predicator.evaluate([["lit", :undefined]], %{})                       #=> {:ok, :undefined}
Predicator.evaluate([["lit", :undefined]], %{}, on_unbound: :error)   #=> {:ok, :undefined}
Predicator.Evaluator.evaluate(
  [["lit", :undefined], ["lit", :undefined], ["compare", "STRICT_EQ"]], %{})  #=> true
```

A literal that lowers to `["lit", :undefined]` therefore never touches the
unbound-variable path, is not recorded by `record_unbound_load/3`, and is not
rewritten by the trace-back rule - it is a value like any other. `===` and
`!==` already handle `:undefined` as an ordinary operand
([`lib/predicator/evaluator.ex:757-758`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/evaluator.ex#L757-L758)), so `x === undefined` would work under
either policy without any evaluator change.

**Where the work actually is**, then, is the front half of the pipeline and
the paperwork: the lexer's reserved-word table, one parser clause, a
`StringVisitor` clause (which today would raise), and the ISA/corpus/docs
obligations. `InstructionsVisitor` needs nothing - its `{:literal, value, pos}`
clause is generic.

**ISA question.** `lit` already accepts `:undefined` in this build and
`docs/isa.md` §3 already lists `:undefined` in the value domain
([`docs/isa.md:168`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/isa.md#L168)). Whether shipping a source spelling for it constitutes
"widening an accepted type" under ADR-0003's rule (a new ISA version, not a
new opcode name) or is purely surface syntax that §6 puts outside the ISA
([`docs/isa.md:661-679`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/isa.md#L661-L679)) is the one genuinely open decision; both readings are
defensible from the documents as written, and this document does not choose
between them. See "ISA Impact" and "Open Questions".

## Detailed Findings

### How a keyword literal flows today (`true` as the model)

**1. Lexer** (`lib/predicator/lexer.ex`). Keywords are not scanned by a
character-level keyword matcher. The lexer consumes a raw identifier run with
`take_identifier/1` ([`lib/predicator/lexer.ex:482-495`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/lexer.ex#L482-L495)) and then reclassifies
it. `classify_identifier/1` ([`lib/predicator/lexer.ex:497-518`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/lexer.ex#L497-L518)) is the actual
reserved-word table - a flat sequence of function heads, not a map:

```elixir
defp classify_identifier("true"), do: {:boolean, true}
defp classify_identifier("false"), do: {:boolean, false}
...
defp classify_identifier("if"), do: {:if_kw, "if"}
defp classify_identifier("else"), do: {:else_kw, "else"}
defp classify_identifier("while"), do: {:while_kw, "while"}
defp classify_identifier(id), do: {:identifier, id}
```

The word `undefined` falls through to the catch-all at
[`lib/predicator/lexer.ex:518`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/lexer.ex#L518). Token shape is the standard 5-tuple
`{type, line, col, len, value}`; booleans emit `{:boolean, 1, 1, 4, true}`.
The token union is declared at [`lib/predicator/lexer.ex:40-92`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/lexer.ex#L40-L92).

A second site matters: `handle_regular_identifier/6`
([`lib/predicator/lexer.ex:520-553`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/lexer.ex#L520-L553)) looks ahead for `(` to decide whether an
identifier is a function name, and at [`lib/predicator/lexer.ex:535-545`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/lexer.ex#L535-L545)
explicitly vetoes that for anything `classify_identifier/1` returns as a
keyword. A new keyword inherits that veto automatically by being in the table.

Date and datetime literals take a different route - punctuation, not a keyword.
`?#` dispatches to `take_date/3` ([`lib/predicator/lexer.ex:637-654`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/lexer.ex#L637-L654)) and
`parse_date_content/1` (`:656-672`) picks `:date` vs `:datetime` on the
presence of `"T"`. They are the model for a *punctuated* literal, not a
keyword one.

**2. Parser** (`lib/predicator/parser.ex`). `parse_primary/1`
([`lib/predicator/parser.ex:1330`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/parser.ex#L1330)) dispatches to `parse_primary_token/2`, whose
clause set is the primary-expression production. The boolean clause
([`lib/predicator/parser.ex:1363-1366`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/parser.ex#L1363-L1366)):

```elixir
defp parse_primary_token(state, {:boolean, _line, _col, _len, value} = token) do
  {:ok, {:literal, value, leaf_loc(state, token)}, advance(state)}
end
```

Date (`:1368-1371`) and datetime (`:1373-1376`) clauses are structurally
identical. All three produce the same generic `{:literal, value, pos}` node -
there is no per-type AST tag.

Two easy-to-miss neighbors: the catch-all error clause at
[`lib/predicator/parser.ex:1444-1448`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/parser.ex#L1444-L1448) names the expected-token set
(`"number, string, boolean, date, datetime, identifier, function call, list,
object, or '('"`), a string dozens of parser tests assert verbatim; and
`format_token/2` ([`lib/predicator/parser.ex:1559-1561`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/parser.ex#L1559-L1561)) is a separate
exhaustive clause set used for error-message rendering.

**3. AST types.** The `ast()` union lives in the parser, not in `types.ex`:
[`lib/predicator/parser.ex:158-176`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/parser.ex#L158-L176), with a parser-local `value()` at
[`lib/predicator/parser.ex:122-129`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/parser.ex#L122-L129). The runtime value union is
`Predicator.Types.value/0` ([`lib/predicator/types.ex:53-62`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/types.ex#L53-L62)), which **already
includes `:undefined`** as a member. `Types.types_match?/2`
([`lib/predicator/types.ex:290-301`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/types.ex#L290-L301)) is the per-type exhaustive clause set that
governs non-strict comparison.

**4. InstructionsVisitor** (`lib/predicator/visitors/instructions_visitor.ex`).
One generic clause covers every literal
([`lib/predicator/visitors/instructions_visitor.ex:174-176`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/visitors/instructions_visitor.ex#L174-L176)):

```elixir
defp visit_annotated({:literal, value, position}, _opts) do
  [{["lit", value], position}]
end
```

Because it matches the tag and not the value's shape, a
`{:literal, :undefined, pos}` node would already lower to
`["lit", :undefined]` with no change to this file.

**5. StringVisitor** (`lib/predicator/visitors/string_visitor.ex`). The
round-trip side is *not* generic. Rendering is guard-dispatched per Elixir
value shape: `is_integer` (`:122-124`), `is_boolean` (`:126-128`), `is_binary`
(`:130-135`), `is_list` (`:152-156`), `%Date{}` (`:158-160`), `%DateTime{}`
(`:162-164`). There is **no catch-all clause**, and px-aen (the bead that adds
not-supported clauses to both visitors) has not landed - `grep` for
`unsupported`/`not_supported` in `lib/predicator/visitors/` returns nothing.
Verified: `Predicator.Compiler.to_string({:literal, :undefined, nil})` raises
`FunctionClauseError` today. A literal with a new value shape needs its own
clause here.

**6. Compiler** (`lib/predicator/compiler.ex`). A pass-through: `to_instructions/2`
(`:56-60`) and `to_string/2` (`:159-162`) delegate to the two visitors through
the `Predicator.Visitor` behaviour. No literal-specific logic.

**7. Evaluator** ([`lib/predicator/evaluator.ex:489-491`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/evaluator.ex#L489-L491)):

```elixir
defp execute_instruction(%__MODULE__{} = evaluator, ["lit", value]) do
  {:ok, push_stack(evaluator, value)}
end
```

Matches on the opcode name only, never on the operand's shape.
[`docs/isa.md:284`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/isa.md#L284): "`lit` - pushes the operand unchanged. No error path."

**Worked flow for `active == true`**: `{:boolean, 1, 11, 4, true}` ->
`{:literal, true, pos}` -> `["lit", true]` -> `push_stack(true)`; round-trip
renders `"true"` via `string_visitor.ex:126-128`.

### How `:undefined` is produced today

`Predicator.Undefined` (`lib/predicator/undefined.ex`) is the public owner of
the sentinel: `value/0` (`:26`), `undefined?/1` (`:43-44`), `to_nil/1` (`:62`),
`from_nil/1` (`:81`). `to_nil/1` and `from_nil/1` have no callers in `lib/` -
they exist for a host application's `nil`-speaking boundary.

Production sites:

- [`lib/predicator/context.ex:327`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/context.ex#L327) - `normalize_value(nil)` -> `Undefined.value()`,
  applied recursively by `Context.new/2` (`:126`) and `Context.bind/3` (`:236`).
  This is the `nil` normalization the bead names.
- [`lib/predicator/evaluator.ex:1339`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/evaluator.ex#L1339) - `load_from_context/2`:
  `Map.get(context, name, Undefined.value())`.
- `lib/predicator/evaluator.ex:1187,1192,1197,1202,1207` - `access_value/3`:
  absent map key, out-of-range index, negative index, non-map/non-list target,
  and the `:access` catch-all all push `:undefined`. The `:bracket_access`
  sibling clause (`:1209-1210`) instead returns a `TypeMismatchError`.
- [`lib/predicator/evaluator.ex:748-754`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/evaluator.ex#L748-L754) and `:790` - `compare_values/3`: an
  `:undefined` operand under a non-strict operator, and a mismatched
  non-undefined type pair, both yield `:undefined`. `compare` has **no**
  `TypeMismatchError` path at all.
- `lib/predicator/evaluator.ex:847,850,865,868` - `in`/`contains` propagate.
- [`lib/predicator/context_location.ex:445`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/context_location.ex#L445) - list-gap padding on a `store`.
- [`lib/predicator/evaluator.ex:83-84`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/evaluator.ex#L83-L84) - the struct's `last_value` default.

### `on_unbound` and why a `lit` literal sidesteps it

Declared as `@type on_unbound :: :undefined | :error`
([`lib/predicator/context.ex:58`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/context.ex#L58)), a struct field defaulting to `:undefined`
(`:71`), validated strictly by `validate_on_unbound!/1` (`:204-210`) - any
other value raises `ArgumentError`. `Predicator.Evaluator.evaluate/3` reads it
off `opts` unvalidated, where anything but `:error` behaves as `:undefined`
(`lib/predicator/evaluator.ex:295-300, 331`). It reaches the evaluator through
`build_evaluator/3`'s `on_unbound: context.on_unbound` ([`lib/predicator.ex:244`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator.ex#L244)).

The only opcode that consults it ([`lib/predicator/evaluator.ex:494-506`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/evaluator.ex#L494-L506)):

```elixir
defp execute_instruction(%__MODULE__{} = evaluator, ["load", variable_name])
     when is_binary(variable_name) do
  value = load_from_context(evaluator.context, variable_name)

  if evaluator.on_unbound == :error and unbound_load?(evaluator, variable_name, value) do
    {:error, UndefinedVariableError.new(variable_name)}
  else
    {:ok, evaluator |> record_unbound_load(variable_name, value) |> push_stack(value)}
  end
end
```

`unbound_load?/3` ([`lib/predicator/evaluator.ex:1406-1410`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/evaluator.ex#L1406-L1410)) is
`Undefined.undefined?(value) and resolve_key(context, name) == :unbound` - it
fires on genuine absence, not on a key bound to `:undefined`.

There is a second, API-layer application on top: `unbound_or_type_mismatch/2`
([`lib/predicator.ex:614-624`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator.ex#L614-L624)) and `undefined_result/1` (`:587-593`) rewrite a
bare `:undefined` result, or a `TypeMismatchError` whose rejected operand was
`:undefined`, into an `UndefinedVariableError` when the value traces back to an
executed unbound `load`. Both rewrites key off `record_unbound_load/3`'s
bookkeeping, which only `load` populates. A `["lit", :undefined]` therefore
passes through both untouched - confirmed above by the two `{:ok, :undefined}`
results.

### Comparison and truthiness of `:undefined`

- Non-strict (`GT LT EQ GTE LTE NE`): either operand `:undefined` -> `:undefined`
  ([`lib/predicator/evaluator.ex:748-754`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/evaluator.ex#L748-L754)), including `EQ`/`NE`. So
  `x == undefined` would be `:undefined`, not `true`/`false` - the
  ECMAScript-shaped boundness test the bead cites needs `===`.
- Strict (`STRICT_EQ`/`STRICT_NE`, source `===`/`!==`):
  [`lib/predicator/evaluator.ex:757-758`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/evaluator.ex#L757-L758) is plain `===`/`!==`, matched *before*
  the undefined-absorbing clauses (guarded `when operator not in [...]` at
  `:749`/`:753`). `:undefined === :undefined` is `true`; `:undefined === 5` is
  `false`. [`docs/isa.md:302-303`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/isa.md#L302-L303).
- Membership: `values_equal?(:undefined, _)` is `false`
  ([`lib/predicator/evaluator.ex:804-806`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/evaluator.ex#L804-L806)), but `execute_membership/2`
  short-circuits an `:undefined` on either side to `:undefined` before ever
  reaching it (`:846-850, 864-868`).
- Falsiness: `false` and `:undefined` are the two falsy values, matched
  literally by `jump_if_falsy_or_pop` (`:1642-1654`), `jump_if_true_or_pop`
  (`:1662-1674`), and `pop_jump_if_falsy` (`:1686-1702`); anything else is a
  `TypeMismatchError`. `not` has no absorption - it requires `is_boolean`
  (`:827-836`), so `:undefined` is a type mismatch under it.
- The user-facing reject-vs-propagate table is
  [`docs/reference/language.md:643-662`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/reference/language.md#L643-L662).

### Corpus and wire-format representation

The corpus already has a spelling for the sentinel: the tagged-value encoding
gives `:undefined` the form `{"$type": "undefined"}`
([`conformance/README.md:109`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/conformance/README.md#L109), `lib/predicator/conformance/values.ex:71,123`).
Crucially it is applied to **instruction operands**, not only to context and
expected values - `encode_instructions/1`
([`lib/predicator/conformance/generator.ex:262-264`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/conformance/generator.ex#L262-L264)) walks the whole
instruction list through `Values.to_json/1`, which is why date literals ship
as `["lit",{"$type":"date","value":"2024-01-15"}]`
([`conformance/corpus/tier-1.json:22`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/conformance/corpus/tier-1.json#L22)). So `["lit",{"$type":"undefined"}]` is
already a representable corpus instruction with no format change.

`undefined` is already a computed feature tag
(`lib/predicator/conformance/features.ex:130,143,146`), and existing cases
cover the sentinel extensively - `errors/unbound-root-variable`
([`conformance/cases/errors.json:3-8`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/conformance/cases/errors.json#L3-L8)), the `access/*-is-undefined` family
([`conformance/cases/access.json:9-69`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/conformance/cases/access.json#L9-L69)), cast propagation
(`conformance/cases/casts.json`), short-circuit
([`conformance/cases/short_circuit.json:31-50`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/conformance/cases/short_circuit.json#L31-L50)), membership
([`conformance/cases/membership.json:25-34`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/conformance/cases/membership.json#L25-L34)), rejection by `add` and legacy
`and`/`or` ([`conformance/cases/arithmetic.json:30`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/conformance/cases/arithmetic.json#L30),
[`conformance/cases/legacy.json:29`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/conformance/cases/legacy.json#L29)). A grep for `"source"` strings containing
the word `undefined` returns nothing - no case spells it as source today.

One scope note that bears on what the corpus can prove: the corpus does not
cover surface syntax or parse errors ([`conformance/README.md:14-24`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/conformance/README.md#L14-L24),
[`docs/isa.md:704-719`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/isa.md#L704-L719)). Every authored `source` must compile. A case can pin
that `undefined` *compiles to* `["lit",{"$type":"undefined"}]` and what that
evaluates to; it cannot be the place a lexer-level reservation is tested.

The plain-JSON wire format is a separate matter. [`docs/isa.md:141-144`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/isa.md#L141-L144) (ADR-0003)
says the wire format stays a plain JSON array, and `Jason.encode(["lit", :undefined])`
produces `["lit","undefined"]` - indistinguishable on decode from the string
`"undefined"`. Nothing in `lib/` encodes or decodes instruction lists to JSON
(no `Jason` reference in `lib/predicator.ex` or `lib/predicator/instructions.ex`);
that is a consumer's job, and `Predicator.Compiled` deliberately carries no
serialization of its own (`lib/predicator/compiled.ex:10-38, 74-77`). Recorded
as an open question rather than a finding, since no code here is affected.

### Documentation surface

- [`docs/reference/language.md:8-25`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/reference/language.md#L8-L25) (`## Data Types`) is the one enumeration of
  every literal form. `:392-396` (`### Reserved words`) is the only reserved-word
  list, naming `if`, `else`, `while`.
- [`docs/reference/language.md:554-736`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/reference/language.md#L554-L736) (`## Undefined and Sparse Data`) is the
  full narrative treatment, with `### Where :undefined comes from` (`:563-588`),
  `### Mismatched comparisons` (`:590-610`), `### AND/OR falsiness` (`:612-641`),
  `### Reject vs. propagate, per operator` (`:643-662`), and
  `### Unbound roots vs. missing paths, and on_unbound` (`:664-736`).
  `### Where :undefined comes from` currently lists three sources; a literal
  would be a fourth.
- [`docs/architecture.md:20-48`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/architecture.md#L20-L48) is the canonical EBNF grammar with precedence
  (`language.md:4-6` delegates to it); `:87-125` is the component map, naming
  `Predicator.Undefined` at `:122-125`.
- `docs/reference/ast.md` is the AST node inventory (`architecture.md:90`,
  `language.md:6`).
- `docs/guides/porting.md:46,51,59,125,206` is the sibling implementer's
  compressed restatement of the `:undefined`/`on_unbound` rules.
- `README.md` has no mention of `undefined` or `unbound` at all.
- `CHANGELOG.md` `## [Unreleased]` (`:8-166`) is where a language-feature entry
  goes. Two entries are the templates: the cast entry (`:83-97`) for a feature
  with an ISA consequence, and the reserved-words entry (`:146-154`) for a
  keyword that breaks identifier use:

  > - **`if`, `else` and `while` are reserved words.** The lexer now classifies
  >   all three as keywords rather than plain identifiers, so a predicate that
  >   used one as a variable name (`if = 3`), a bare property name (`user.if`),
  >   or a bare object key (`{if: 1}`) is now a parse error. [...]

## ISA Impact

`lit` is ISA v1, tier 1, operands "value", pops 0, pushes 1
([`docs/isa.md:226`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/isa.md#L226)), with the semantics "pushes the operand unchanged. No
error path" ([`docs/isa.md:284`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/isa.md#L284)). Its subsection does not enumerate or restrict
the operand's type - it is the one opcode in §5 with no error path at all. §3
([`docs/isa.md:165-168`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/isa.md#L165-L168)) already lists `:undefined` in the value domain, and
this build already executes `["lit", :undefined]` correctly.

Two ADR-0003 rules bear on whether a version integer moves:

- [`docs/isa.md:33-34`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/isa.md#L33-L34): "Adding an operand form or widening an accepted type is
  a new version but not a new name."
- [`docs/isa.md:661-679`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/isa.md#L661-L679) (§6, Not in the ISA): surface syntax is explicitly out
  of scope, with the `=`/`==` case as the worked example - both compile to
  `["compare","EQ"]`, so no instruction-level divergence exists.

Read one way, no widening occurs: `lit` accepts `:undefined` today, §3 already
admits it, and only the surface spelling is new - which §6 puts outside the
ISA, meaning no version bump, no new opcode, no `docs/isa.md` table change.
Read the other way, shipping a *compiler that emits* `["lit", :undefined]` for
the first time is the operand-form widening §1 has in mind, and the version
integer moves. The documents as written support both; this is left as an open
question below.

If a version bump *is* taken, the enumerated obligation set (from the
`jump_backward`/ISA v6 worked example) is:

- [`docs/isa.md:58`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/isa.md#L58) - `Current version: **ISA v6**.` (exact string, regex-matched
  by the sync test)
- [`docs/isa.md:191-195`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/isa.md#L191-L195) - the narrative version-assignment sentence
- [`docs/isa.md:224-256`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/isa.md#L224-L256) - the opcode table's ISA column
- [`docs/isa.md:681-690`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/isa.md#L681-L690) - §7 version-history table (a version whose only change
  is a widening still gets a row under §1's rules)
- [`lib/predicator/instructions.ex:45`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/instructions.ex#L45) - `@isa_version 6`
- [`lib/predicator/instructions.ex:64-96`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/instructions.ex#L64-L96) - the `@opcodes` map (only if a *name*
  is added; a widening adds none)
- `test/predicator/isa_sync_test.exs:23,30` - `@opcode_count 31` (only on a
  row count change)
- `conformance/manifest.json` - `"isa_version"`, regenerated by
  `mix corpus.generate`, never hand-edited
- `CHANGELOG.md` - the entry naming the ISA version

`test/predicator/isa_sync_test.exs` binds three artifacts to each other:
`docs/isa.md` §4's table prose, `Predicator.Instructions`'s `@opcodes`, and the
`execute_instruction/2` clause heads in `lib/predicator/evaluator.ex`, parsed
by regex at test time (`:216-306`). Its six assertions include the exact
`Current version: **ISA v#{n}**.` string (`:86-88`) and evaluator-clause-set
equality (`:163-204`). It is a binding test under the sabotage-note obligation
(`docs/research/260808-px-9ab-sabotage-notes.md`), carrying one `# sabotage:`
comment per test naming the mutation verified to redden it (`:37, 64, 85, 96,
126, 162`).

`test/predicator/conformance/corpus_freshness_test.exs` is the other binding
test in reach: it calls `CorpusGenerate.build_files/0` and byte-compares
against what is checked in (`:20-45`), with its own sabotage note at `:19`.

Stored artifacts are unaffected either way: no existing instruction list
changes meaning, and nothing is retired, so ADR-0003's retirement/upgrade-path
machinery (`lib/predicator/instructions/upgrade.ex`) is not engaged.

## Code References

- [`lib/predicator/lexer.ex:497-518`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/lexer.ex#L497-L518) - `classify_identifier/1`, the reserved-word table
- [`lib/predicator/lexer.ex:520-553`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/lexer.ex#L520-L553) - keyword-vs-function-call veto
- [`lib/predicator/lexer.ex:40-92`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/lexer.ex#L40-L92) - the `token()` typespec union
- [`lib/predicator/parser.ex:1363-1366`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/parser.ex#L1363-L1366) - the boolean primary-expression clause
- [`lib/predicator/parser.ex:1444-1448`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/parser.ex#L1444-L1448) - the expected-token error string
- [`lib/predicator/parser.ex:1559-1561`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/parser.ex#L1559-L1561) - `format_token/2`
- [`lib/predicator/parser.ex:158-176`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/parser.ex#L158-L176) - the `ast()` union
- [`lib/predicator/types.ex:53-62`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/types.ex#L53-L62) - `Types.value()`, already including `:undefined`
- [`lib/predicator/types.ex:290-301`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/types.ex#L290-L301) - `types_match?/2`
- [`lib/predicator/visitors/instructions_visitor.ex:174-176`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/visitors/instructions_visitor.ex#L174-L176) - the generic literal clause
- [`lib/predicator/visitors/string_visitor.ex:122-164`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/visitors/string_visitor.ex#L122-L164) - the guard-dispatched render clauses, no catch-all
- [`lib/predicator/evaluator.ex:489-491`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/evaluator.ex#L489-L491) - the `lit` execution clause
- [`lib/predicator/evaluator.ex:494-506`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/evaluator.ex#L494-L506) - the `load` clause, the only `on_unbound` consumer
- [`lib/predicator/evaluator.ex:748-758`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/evaluator.ex#L748-L758) - non-strict propagation and strict equality
- [`lib/predicator/evaluator.ex:1406-1410`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/evaluator.ex#L1406-L1410) - `unbound_load?/3`
- [`lib/predicator/undefined.ex:26-83`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/undefined.ex#L26-L83) - the sentinel's public owner
- `lib/predicator/context.ex:58,71,204-210,327` - `on_unbound` type, field, validation, nil normalization
- `lib/predicator.ex:244,587-593,614-624` - policy threading and the two trace-back rewrites
- `lib/predicator/conformance/values.ex:71,123` - `{"$type":"undefined"}` encode/decode
- [`lib/predicator/conformance/generator.ex:262-264`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/conformance/generator.ex#L262-L264) - operand encoding inside instructions
- `docs/isa.md:226,284` - `lit`'s table row and semantics
- `docs/isa.md:33-34,661-679` - the widening rule and the surface-syntax exclusion
- [`test/predicator/isa_sync_test.exs:23-204`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/test/predicator/isa_sync_test.exs#L23-L204) - the ISA binding test
- [`test/predicator/conformance/corpus_freshness_test.exs:19-45`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/test/predicator/conformance/corpus_freshness_test.exs#L19-L45) - the corpus binding test
- [`conformance/README.md:98-113`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/conformance/README.md#L98-L113) - the tagged-value encoding
- `docs/reference/language.md:8-25,392-396,554-736` - data types, reserved words, undefined semantics

## Architecture Documentation

- **ADR-0003** (`docs/adr/0003-the-elixir-implementation-leads-the-isa.md`) is
  the governing decision: this repo leads the ISA, sibling parity is downstream
  and never a gate, and every ISA change owes a version, a `docs/isa.md` entry,
  a corpus tier assignment, and a migration note if stored artifacts are
  affected. It amends ADR-0001 without superseding it; ADR-0001's
  cross-language-interchange framing is not live.
- **ADR-0004** (`docs/adr/0004-no-eval-errors-are-values.md`) - errors are
  values, never raised at a leaf. Relevant twice here: the `StringVisitor`
  `FunctionClauseError` on an unrenderable literal is a recorded convention
  breach px-aen is open against, and any new parse rejection must be a
  `ParseError` value.
- **ADR-0011** (`casts are an opcode`) is the closest prior art for a *value*
  semantics decision that added an opcode; **ADR-0013** (control flow) is the
  closest for a keyword reservation, and its CHANGELOG entry
  ([`CHANGELOG.md:146-154`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/CHANGELOG.md#L146-L154)) is the template for the breaking half of reserving a
  word.
- **The shared-tag pattern**: `{:literal, value, pos}` is one AST node for every
  scalar literal. `InstructionsVisitor` needs no type dispatch because the
  opcode carries the raw value; `StringVisitor` must guard per value shape.
- **Contextual vs reserved**: the seven cast type names
  ([`lib/predicator/cast.ex:20-27`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/cast.ex#L20-L27)) are *contextual* identifiers - special only
  after `::`, ordinary variable names everywhere else (ADR-0011, commented at
  [`lib/predicator/parser.ex:111-116`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/parser.ex#L111-L116)). The reserved words in
  `classify_identifier/1` are the other kind. Which kind a new literal keyword
  is, is a design question this document does not answer.

## Historical Context

- The `px-8um.*` plan series (2026-08-04/05) is the `:undefined`/`on_unbound`
  design arc: `docs/plans/260804-px-8um.4-undefined-bound-check.md` created
  `Predicator.Undefined`; `docs/plans/260805-px-8um.3-on-unbound-policy.md` is
  the `on_unbound` design; `docs/plans/260804-px-8um.8-runtime-unbound-tracking.md`
  added the runtime bookkeeping the API-layer rewrites read;
  `docs/plans/260805-px-8um.7-unbound-type-mismatch.md` added the
  type-mismatch-to-`UndefinedVariableError` rewrite.
- `docs/plans/260806-px-35i.2-isa-reference.md`,
  `260806-px-35i.3-isa-version-stamp.md`, and `260806-px-im6-versioned-isa-workflow.md`
  built the versioning machinery ADR-0003 depends on.
- `docs/plans/260807-px-35i.4-conformance-corpus.md` and
  `docs/design/260806-px-35i.4-corpus-format-and-tooling.md` stood up the corpus
  and its tagged-value encoding.
- `docs/plans/260811-px-aen-visitor-unsupported-node-error.md` is open and
  directly adjacent: it documents that neither visitor has a catch-all and that
  the resulting `FunctionClauseError` is an ADR-0004 breach.
- `docs/research/260808-px-9ab-sabotage-notes.md` is the sabotage-note
  convention both binding tests in reach are governed by.

## Related Research

- `docs/research/260807-px-t2v-px-z5m-isa-retirement-and-pop.md` - how the ISA
  moves in practice
- `docs/research/260808-px-9ab-sabotage-notes.md` - the binding-test obligation
- `docs/research/260809-*-cast-conversion-matrix` and the ADR-0011 plan series -
  the closest prior example of a feature whose failure mode is `:undefined`
  rather than an error

## Open Questions

1. **Does a source spelling for `:undefined` move the ISA version?**
   [`docs/isa.md:33-34`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/isa.md#L33-L34) says widening an accepted operand type is a new version
   but not a new name; [`docs/isa.md:661-679`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/docs/isa.md#L661-L679) says surface syntax is not in the
   ISA at all, and `lit` already accepts `:undefined` in this build. Both
   readings are supported by the documents as written. This is the one decision
   the research cannot settle from existing material, and it determines whether
   the ISA-version obligation list in "ISA Impact" is engaged.

2. **Reserved word or contextual keyword?** Reserving `undefined` in
   `classify_identifier/1` makes `undefined = 3`, `user.undefined`, and
   `{undefined: 1}` parse errors - the same break `if`/`else`/`while` took
   ([`CHANGELOG.md:146-154`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/CHANGELOG.md#L146-L154)), and a breaking change for any embedding using it
   as a variable or bare key. The contextual alternative (as with cast type
   names) avoids the break at the cost of a more complicated grammar. Not
   decided here.

3. **Should `x == undefined` be `:undefined` or `true`/`false`?** Under current
   semantics the non-strict operators propagate ([`lib/predicator/evaluator.ex:748-754`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/lib/predicator/evaluator.ex#L748-L754)),
   so only `===`/`!==` give a boolean answer. The bead's ECMAScript reference
   (`x === undefined`) matches the strict form, so no change may be wanted -
   but an author who writes `==` will get `:undefined`, and whether that needs
   documenting or diverging is unaddressed.

4. **Plain-JSON wire representation.** `Jason.encode(["lit", :undefined])`
   yields `["lit","undefined"]`, indistinguishable from the string operand.
   Nothing in `lib/` serializes instruction lists, and the corpus has its own
   tagged encoding, so no code here is affected - but a consumer that persists
   compiled artifacts as plain JSON (statifier's `{:compiled, instructions,
   source}`, per ADR-0003's context section) would round-trip such an
   instruction wrongly. Whether that is predicator's problem, a `docs/isa.md`
   note, or a downstream one is open.

5. **Round-trip rendering.** `StringVisitor` would need a clause, and there is
   no catch-all to fall into today (verified: `FunctionClauseError`). Whether
   that clause lands with this work or waits on px-aen's not-supported clauses
   is a sequencing question between two open beads.

6. **Corpus scope.** The corpus can pin what `undefined` compiles to and
   evaluates to, but not that it lexes as a keyword - surface syntax and parse
   errors are outside its scope ([`conformance/README.md:14-24`](https://github.com/riddler/predicator-ex/blob/2ae45aba482bc3ae8c78bb1f5c5e53d2168d51e1/conformance/README.md#L14-L24)). The
   reserved-word behavior needs ExUnit coverage in the
   `test/predicator/reserved_words_test.exs` mold instead.

7. **The statifier mirror.** The bead names `st-unt` (blocking `st-af3.2`) as
   the consuming half. Per CLAUDE.md's mirror obligation, the statifier tracker
   must be re-read and a dated note written before this bead is scheduled,
   claimed, planned against, or cited - not done in this pass, which was a
   codebase documentation pass only.
