---
date: 2026-08-13T11:18:04-0600
researcher: Claude
git_commit: 19b10f579d905fb51de59750c0ac1768860631ae
branch: px-o9v-null-vs-undefined
repository: predicator-ex
beads_issue: px-o9v
topic: "Distinguishing a semantic null from the :undefined sentinel in Predicator.Context"
tags: [research, codebase, context, evaluator, conformance]
status: complete
last_updated: 2026-08-13
last_updated_by: Claude
---

# Research: Distinguishing null from undefined in Predicator.Context

**Date**: 2026-08-13T11:18:04-0600
**Git Commit**: 19b10f579d905fb51de59750c0ac1768860631ae
**Branch**: px-o9v-null-vs-undefined
**Bead**: px-o9v

## Research Question

px-o9v asks whether a value that is "present and null" can be distinguished
from "unbound" once it crosses the context boundary. Today `Context.new/2`
rewrites `nil` to the `:undefined` sentinel recursively, so it cannot.

This document records what exists today, in seven parts: where the
normalization happens and who depends on it; how `:undefined` flows through
the evaluator and visitors; what the public API and docs say; whether the ISA
is implicated; what the conformance corpus says; the prior art for a
non-JSON-native operand; and which tests bind the current collapse.

## Summary

The `nil` -> `:undefined` rewrite is a **single clause in a single private
function**: `normalize_value(nil), do: Undefined.value()` at
[`lib/predicator/context.ex:327`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L327). It is reached from exactly two public
entry points, `Context.new/2` ([`lib/predicator/context.ex:126`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L126)) and
`Context.bind/3` ([`lib/predicator/context.ex:236`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L236)).

Three findings shape the blast radius.

1. **The collapse is not universal today.** Several paths already carry a raw
   `nil` into evaluation without ever meeting `normalize_value/1`:
   `Predicator.Evaluator.evaluate/3` called directly with a bare map,
   `Predicator.evaluator/2`, `Context.assign/3` and
   `Predicator.context_assign/4` (which write through
   `ContextLocation.put/3` with the raw value), custom function return
   values, and the `host` slot. The evaluator has no `nil` clause anywhere,
   so a `nil` that reaches it today falls through to catch-alls: it compares
   as a type mismatch (`compare_values/3`'s final clause,
   [`lib/predicator/evaluator.ex:790`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L790), yielding `:undefined`), and it is a
   `TypeMismatchError` at a jump. [`test/predicator/evaluator_test.exs:1523`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/test/predicator/evaluator_test.exs#L1523)
   is an existing test that *documents* this boundary.

2. **Only 7 things go red** if the collapse stops: 5 ExUnit tests and 2
   doctests, all in `Context`'s own suite plus one `on_unbound` integration
   test. Nothing in the conformance corpus, no doc doctest, no property test.

3. **Nothing in the ISA is implicated by the value half.** `lit`'s operand
   domain is `docs/isa.md` §3's ten-type value list, stated once; the ISA
   never enumerates "permitted `lit` operand types" separately, and
   `lib/predicator/instructions.ex` tracks opcode *names* only, never operand
   types. `docs/isa.md` §6 already records that the `undefined` literal moved
   no version for exactly this reason. A value-level null sentinel that never
   acquires a source spelling touches no opcode. Widening the ISA's §3 value
   domain to admit a tenth-plus type is nonetheless a §3 edit and a
   documentation obligation under ADR-0003, and every opcode whose semantics
   `docs/isa.md` §5 states in terms of `:undefined` would need a stated rule
   for the new value.

The bead's own inference - that the value half is additive - holds against
the test suite, with one nuance recorded under Open Questions: the `nil`
paths that bypass normalization today have no defined semantics anywhere, so
"a null sentinel" and "the raw `nil` that already leaks" are two different
things that a change here would have to reconcile.

## Detailed Findings

### 1. Where `nil` becomes `:undefined`, and who depends on it

**The definition site.** [`lib/predicator/context.ex:326-337`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L326-L337):

- `normalize_value(nil), do: Undefined.value()` ([`lib/predicator/context.ex:327`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L327))
  is the one place in the repo that converts `nil` to the sentinel as part of
  data ingestion.
- `normalize_value(list) when is_list(list)` ([`lib/predicator/context.ex:329-331`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L329-L331))
  recurses element-wise.
- `normalize_value(%_struct{} = struct), do: struct` ([`lib/predicator/context.ex:333`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L333))
  passes every struct through untouched, and **must precede** the plain-map
  clause because `is_map/1` is true for structs. `Date` and `DateTime` are
  never scanned for interior nils.
- `normalize_value(map) when is_map(map), do: normalize_map(map)`
  ([`lib/predicator/context.ex:335`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L335)), and the scalar catch-all at
  [`lib/predicator/context.ex:337`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L337).
- `normalize_map/1` ([`lib/predicator/context.ex:351-368`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L351-L368)) is the atom-key
  half: non-atom entries build the base map (values normalized), then atom
  entries fold in with `Atom.to_string/1`, skipped when a string key already
  claimed the slot. `true`/`false` map keys are deliberately exempt
  ([`lib/predicator/context.ex:346-354`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L346-L354)).

**Callers inside `Context`.**

- `new/2` - `data: normalize_value(data)` ([`lib/predicator/context.ex:126`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L126)),
  whole-map deep normalization at construction.
- `bind/3` - `Map.put(data, name, normalize_value(value))`
  ([`lib/predicator/context.ex:236`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L236)), value only.
- `assign/3` ([`lib/predicator/context.ex:304-311`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L304-L311)) does **not** normalize. It
  resolves the path and calls `ContextLocation.put/3` with the raw value.
  `set_in/4` ([`lib/predicator/context_location.ex:423-438`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context_location.ex#L423-L438)) stores the value
  verbatim. So `Context.assign(ctx, "user.name", nil)` stores a literal `nil`
  today, where `Context.bind(ctx, "user", %{"name" => nil})` stores
  `:undefined`. This asymmetry exists now and is neither documented nor
  tested.
- `host` never normalizes, by design and by documentation
  ([`lib/predicator/context.ex:22-29`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L22-L29), [`lib/predicator/context.ex:129`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L129),
  [`lib/predicator/context.ex:250-251`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L250-L251)).

**The sentinel module.** `lib/predicator/undefined.ex` is the whole public
API surface for the sentinel: `value/0` (line 25), `undefined?/1` (42-44),
`to_nil/1` (61-63), `from_nil/1` (80-82). Note that `Context.normalize_value/1`
duplicates `from_nil/1`'s single-clause logic rather than delegating to it -
there are two definition sites for the same rule.

**Consumers of `:undefined` elsewhere in `lib/`** (these consume the
sentinel; most do not care where it came from):

- [`lib/predicator/evaluator.ex:1333-1340`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L1333-L1340) - `load_from_context/2` uses
  `Map.get(context, name, Undefined.value())`. The default fires only on
  *absence*; a key present with value `nil` returns `nil`.
- [`lib/predicator/evaluator.ex:1178-1211`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L1178-L1211) - `access_value/3`, every miss path.
- [`lib/predicator/evaluator.ex:1406-1427`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L1406-L1427) - `unbound_load?/3` and
  `record_unbound_load/3`: a load is "unbound" only when the value is
  `:undefined` **and** `resolve_key/2` says the name is absent. A key bound to
  `:undefined` (or to `nil`) is bound. `resolve_key/2`'s doc
  ([`lib/predicator/evaluator.ex:1350-1367`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L1350-L1367)) states this explicitly.
- [`lib/predicator.ex:257-258`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator.ex#L257-L258), [`lib/predicator.ex:587-593`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator.ex#L587-L593),
  [`lib/predicator.ex:628-632`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator.ex#L628-L632) - the trace-back rewrite that turns a result
  `:undefined` or an `:undefined`-operand `TypeMismatchError` into an
  `UndefinedVariableError`.
- [`lib/predicator/context_location.ex:382-389`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context_location.ex#L382-L389) - `vivify/3` treats `nil` **and**
  `:undefined` alike as "absent"; [`lib/predicator/context_location.ex:440-446`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context_location.ex#L440-L446)
  pads list gaps with `Undefined.value()`.
- [`lib/predicator/cast.ex:40`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/cast.ex#L40) - `:undefined` propagates to every cast target.
  `cast/2` has no `nil` clause at all.
- [`lib/predicator/types.ex:62`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/types.ex#L62) - `:undefined` is in the `value()` type;
  [`lib/predicator/types.ex:261-262`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/types.ex#L261-L262) delegates `undefined?/1`.
- [`lib/predicator/errors/location_error.ex:197`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/errors/location_error.ex#L197) and
  [`lib/predicator/errors.ex:87-88`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/errors.ex#L87-L88) - message formatting.
- The four function providers reference neither `nil` nor `:undefined` (zero
  grep hits across `lib/predicator/functions/`).

**Paths by which a raw `nil` reaches evaluation today, bypassing normalization**:

1. `Predicator.Evaluator.evaluate/3` on a bare map
   ([`lib/predicator/evaluator.ex:321-334`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L321-L334)) - context stored verbatim.
2. `Predicator.evaluator/2` ([`lib/predicator.ex:959-965`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator.ex#L959-L965)) - same.
3. Nested access on such a map ([`lib/predicator/evaluator.ex:1187`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L1187)).
4. Custom function returns - `call_function/3`
   ([`lib/predicator/evaluator.ex:1284-1310`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L1284-L1310)) pushes `{:ok, result}` unchanged.
5. `Context.assign/3`, `Predicator.context_assign/4`
   ([`lib/predicator.ex:1140-1148`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator.ex#L1140-L1148)), `ContextLocation.put/3` directly.
6. The `host` slot (never reachable from predicate text).

By contrast `Predicator.evaluate/3` on a bare map always routes through
`Context.new/2` ([`lib/predicator.ex:265-267`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator.ex#L265-L267), [`lib/predicator.ex:544-546`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator.ex#L544-L546)),
so the public façade does normalize.

**Doctests in `lib/` asserting the collapse or the sentinel**:

- [`lib/predicator/context.ex:109-110`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L109-L110) - `new(%{user: %{name: nil}}).data` ->
  `%{"user" => %{"name" => :undefined}}`
- [`lib/predicator/context.ex:231-232`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L231-L232) - the `bind/3` equivalent
- `lib/predicator/undefined.ex:22-23, 33-40, 55-59, 74-78` - the sentinel API,
  including `undefined?(nil) == false` and `from_nil(nil) == :undefined`
- [`lib/predicator/types.ex:255-259`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/types.ex#L255-L259), [`lib/predicator/context_location.ex:198-199`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context_location.ex#L198-L199),
  [`lib/predicator/evaluator.ex:224-226`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L224-L226), [`lib/predicator/errors.ex:87-88`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/errors.ex#L87-L88),
  [`lib/predicator.ex:459-461`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator.ex#L459-L461),
  `lib/predicator/conformance/values.ex:49-50, 110-111`

Only the first two assert the nil-collapse itself.

### 2. How `:undefined` flows through evaluation

**Comparison** ([`lib/predicator/evaluator.ex:746-802`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L746-L802)):

- `compare_values(:undefined, _right, operator) when operator not in ["STRICT_EQ", "STRICT_NE"]`
  -> `:undefined` (lines 748-750); the mirror clause at 752-754.
- `compare_values(left, right, "STRICT_EQ")` -> raw `===` (line 757);
  `"STRICT_NE"` -> `!==` (line 758).
- Therefore, precisely:
  - `undefined == undefined` evaluates to **`:undefined`**, not `true` - the
    non-strict clause fires first.
  - `undefined === undefined` evaluates to **`true`**.
  - `undefined == "undefined"` evaluates to **`:undefined`**.
  - `undefined === "undefined"` evaluates to **`false`**.
- `values_equal?/2` ([`lib/predicator/evaluator.ex:804-806`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L804-L806)), used by `in`/
  `contains`, is stricter still: `:undefined` on either side is hard-coded
  `false`.
- The generic fallthrough `compare_values(_left, _right, _operator), do: Undefined.value()`
  ([`lib/predicator/evaluator.ex:790`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L790)) is what a raw `nil` operand hits today.

**Truthiness.** There is no general truthiness rule - `docs/isa.md` §2 states
"Opcodes validate, they do not coerce." `:undefined` is falsy in exactly one
family, the jumps:

- `execute_jump_if_falsy_or_pop/2` ([`lib/predicator/evaluator.ex:1642-1645`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L1642-L1645))
- `execute_jump_if_true_or_pop/2` ([`lib/predicator/evaluator.ex:1660-1667`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L1660-L1667))
- `execute_pop_jump_if_falsy/2` ([`lib/predicator/evaluator.ex:1684-1688`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L1684-L1688))

each guarded `when top == false or top == :undefined`. Anything else at a
jump is a `TypeMismatchError`. `docs/isa.md` §2 records this as
ECMAScript-aligned and deliberately not symmetric-Kleene, citing ADR-0001.

**Where `:undefined` is rejected rather than propagated**: `not` /
`unary_bang` ([`lib/predicator/evaluator.ex:826-840`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L826-L840), `1134-1159`), all five
arithmetic opcodes ([`lib/predicator/evaluator.ex:889-1108`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L889-L1108)), and the retired
legacy `and`/`or` ([`lib/predicator/evaluator.ex:666-672`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L666-L672)). `get_value_type(:undefined)`
returns `:undefined` as the reported type in those errors
([`lib/predicator/evaluator.ex:1119`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L1119)).

**Where it propagates**: `compare` under non-strict operators, `in`/`contains`
(`lib/predicator/evaluator.ex:846-850, 864-868`), `cast`
([`lib/predicator/cast.ex:40`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/cast.ex#L40)), and all access misses.

**Visitors.**

- [`lib/predicator/lexer.ex:501`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/lexer.ex#L501) - `classify_identifier("undefined"), do: {:undefined, :undefined}`.
  `undefined` is a reserved literal keyword today, lowercase spelling only.
- [`lib/predicator/parser.ex:1369-1372`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/parser.ex#L1369-L1372) - produces `{:literal, :undefined, pos}`,
  the same `:literal` tag every other scalar uses.
- [`lib/predicator/visitors/instructions_visitor.ex:174-176`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/visitors/instructions_visitor.ex#L174-L176) - the generic
  `{:literal, value, position}` clause lowers it to `["lit", :undefined]`.
  There is no `:undefined`-specific visitor clause and none is needed.
- [`lib/predicator/visitors/string_visitor.ex:130`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/visitors/string_visitor.ex#L130) - one dedicated clause
  renders it back as `"undefined"`.

### 3. Public API surface today

**`@doc`/`@spec`.**

- [`lib/predicator/context.ex:96-102`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L96-L102) (`new/2`) states the rule in prose: "atom
  keys become string keys ... and `nil` values become the `:undefined`
  sentinel, recursing through nested maps and lists. `Date`, `DateTime`, and
  any other struct pass through unchanged."
- [`lib/predicator/context.ex:217-222`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L217-L222) (`bind/3`) repeats it.
- [`lib/predicator/context.ex:22-29`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L22-L29) documents `host`'s exemption.
- [`lib/predicator/context.ex:45-57`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L45-L57) (`t:on_unbound/0`) cites ECMAScript's
  `ReferenceError` framing.
- `assign/3`'s docs ([`lib/predicator/context.ex:281-303`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L281-L303)) say nothing about
  value normalization, matching the behavior.
- `@spec new(Types.context(), keyword()) :: t()` -
  `Types.context()` is `%{required(binary() | atom()) => value()}`
  ([`lib/predicator/types.ex:64`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/types.ex#L64)), and `value()` ([`lib/predicator/types.ex:47-62`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/types.ex#L47-L62))
  does **not** include `nil`. So a `nil` in an input map is already outside the
  declared input type; the normalization is what makes the spec honest.

**`docs/reference/language.md`.**

- Line 14 lists `undefined` among the literals.
- Lines 394-405, "Reserved words": `undefined` is reserved, joining
  `true`/`false` as a literal keyword; `UNDEFINED` and `Undefined` are
  ordinary identifiers; quoted keys still work.
- Lines 551-557 state the deep, eager normalization rule for `new/2` and
  `bind/3` in full.
- Lines 563-601, "Undefined and Sparse Data": where `:undefined` comes from -
  unbound identifier, missing nested path, failed cast, the literal.
- Lines 634-645: the falsy-at-a-jump and short-circuit rules.
- Lines 710-732: the `===` vs `==` boundness-test divergence under
  `on_unbound`.
- Lines 751-780: the unbound-root vs missing-path trace-back rule.

There is no mention of `null` as a concept anywhere in the reference; "null"
appears in the language reference only as part of `nil` normalization prose.

**`docs/architecture.md`** carries one component-map entry for
`Predicator.Undefined` ("the one public module that owns the `:undefined`
sentinel").

**`docs/isa.md`**: §2 (lines 84-107) the execution model and falsy rule; §3
(line 168) the ten-type value domain including `:undefined`; §5 the
per-opcode rules (`lit` 284-287, `load` 288-292, `access` 293-298, `compare`
299-321, legacy `and`/`or` 336-346, `not` 347-349, `in`/`contains` 350-357,
arithmetic 358-390, `bracket_access` 391-414, the jumps 448-466 and 617-621,
`store` 483-500, `cast` 512-545); §6 (678-681) the literal's ISA neutrality.

**`CHANGELOG.md`**: the `[5.0.0] - 2026-08-12` entry documents the `undefined`
literal and states "**The ISA version does not move**"; `[3.8.0]`/`[3.7.0] -
2026-08-05` document the eager context key/`nil` normalization and the
`on_unbound` policy; earlier entries back to `[1.0.0]` cover `:undefined` for
missing paths and sparse list padding. `README.md` mentions none of
`undefined`, `null`, or `nil`.

## ISA Impact

**The value half implicates no opcode.**

- `lib/predicator/instructions.ex` maintains an opcode-name -> `{isa version,
  tier}` table only (`@opcodes`, lines 64-96). `required_isa/1`
  (lines 292-329) scans the opcode head and deliberately never recurses into
  operands (comment at lines 255-263). No file enumerates permitted `lit`
  operand types.
- `docs/isa.md` §3 (line 168) is the closed statement of the value domain:
  "integer, float, string, boolean, list, map (object), `Date`, `DateTime`,
  duration, and `:undefined`". `lit`'s §5 entry (284-287) points at it rather
  than restating a list.
- `docs/isa.md` §6 (678-681) already records the precedent: the `undefined`
  literal "compiles to the existing `["lit", :undefined]`, an instruction this
  ISA's value domain (§3) already admitted, so the new spelling attaches to no
  opcode name and moves no version."

The precedent cuts both ways, and the distinction matters for sizing. A null
sentinel that only ever *enters through the context* and never appears as a
`lit` operand changes no ISA text. A null sentinel that can be a `lit`
operand - which it becomes the moment a `null` literal exists, i.e. the
bead's breaking literal half - widens §3's value domain, which is an ISA
edit under ADR-0003 regardless of whether any opcode name or version moves,
and obliges a stated rule in every §5 entry that currently states a rule for
`:undefined` (comparison propagation, jump falsiness, arithmetic rejection,
cast propagation, access, store vivification).

The one closed enumeration of *type names* in the codebase is
`@cast_type_names = Cast.type_names()` ([`lib/predicator/evaluator.ex:30`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L30),
`docs/isa.md` line 530: the seven scalar type names). That is `cast`'s target
operand list, not `lit`'s value domain, and it is unaffected by a value the
grammar cannot name.

## 5. The conformance corpus

**The tagged-value codec** (`lib/predicator/conformance/values.ex`) defines
exactly four `$type` tags: `undefined`, `date`, `datetime`, `duration`
(moduledoc, lines 1-27).

- `to_json(:undefined), do: {:ok, %{"$type" => "undefined"}}`
  ([`lib/predicator/conformance/values.ex:71`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/conformance/values.ex#L71))
- `from_json(%{"$type" => "undefined"}), do: {:ok, :undefined}`
  ([`lib/predicator/conformance/values.ex:123`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/conformance/values.ex#L123))
- **A bare `nil` is not representable.** `to_json(nil)` matches no clause and
  falls to the catch-all `{:error, {:unencodable, value}}`
  ([`lib/predicator/conformance/values.ex:96`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/conformance/values.ex#L96)); `from_json(nil)` likewise
  returns `{:error, {:undecodable, nil}}`
  ([`lib/predicator/conformance/values.ex:153`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/conformance/values.ex#L153)). A JSON `null` in a case file
  is rejected outright - it decodes to neither `nil` nor `:undefined`.
- `encode_plain_map/1` rejects a map carrying a literal `"$type"` key
  ([`lib/predicator/conformance/values.ex:201-208`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/conformance/values.ex#L201-L208)).

**Schema.** `conformance/schema/case.json` and `corpus.json` do not enumerate
`$type` tags at all (zero grep hits). `context`, `expected`, and
`expected_error` are typed as bare `"type": "object"` with no value
constraints (`conformance/schema/case.json:26-30, 31-68`). The only schema-level
`null` is the top-level `source` field, `"type": ["string", "null"]`
([`conformance/schema/case.json:13-16`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/conformance/schema/case.json#L13-L16)), meaning "evaluator-only case, no
source string" - unrelated to value encoding.

**Where `undefined` appears in authored cases.** `conformance/cases/core.json`
(`core/literal-undefined`, `core/undefined-strict-eq-undefined`,
`core/undefined-strict-ne-int`, `core/undefined-eq-propagates`, lines 73-92);
`conformance/cases/access.json` (six miss-is-undefined cases plus
`access/missing-key-strict-eq-undefined-literal`);
`conformance/cases/short_circuit.json` (lines 31-42);
`conformance/cases/control_flow.json` (lines 23-30);
`conformance/cases/membership.json` (lines 25-34);
`conformance/cases/casts.json` (extensive, lines 9-374);
`conformance/cases/comparison.json` (lines 61-82).
`conformance/cases/arithmetic.json` and `legacy.json` mention it in prose
notes only.

**Literal `null` in the corpus**: zero occurrences in
`conformance/cases/*.json`. In generated `conformance/corpus/tier-*.json` it
appears only as `"source": null` for evaluator-only cases (e.g.
`conformance/corpus/tier-1.json:34, 36`). Never inside `context`,
`instructions` operands, `expected_result`, or `expected_error`. So no corpus
case exercises a context `nil` today, and none would break.

**What a new value type would owe the corpus.** By the pattern the four
existing tags follow: an encode and decode clause pair in
`lib/predicator/conformance/values.ex`; a row in `conformance/README.md`'s
tagged-value table (lines 98-145); an entry in `conformance/RATCHET.md`'s
reference-runner decode table (lines 227-228), which is the contract siblings
implement; a round-trip entry in `@round_trip_values`
([`test/predicator/conformance/values_test.exs:11-33`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/test/predicator/conformance/values_test.exs#L11-L33)); and at least one
authored case, which regenerates `conformance/manifest.json`'s `corpus_hash`
and thereby invalidates every existing sibling ratchet pin until re-verified
(`conformance/RATCHET.md:129-171, 260-267`).

**The tests that bind the corpus**:

- `test/predicator/conformance/values_test.exs` - the codec's shapes and the
  round-trip property for every ISA value type
- `test/predicator/conformance/corpus_freshness_test.exs` - regenerates and
  byte-compares against the checked-in corpus
- `test/predicator/conformance/schema_validation_test.exs` - every corpus
  line, `manifest.json`, and every authored case against the schemas
- `test/predicator/conformance/opcode_coverage_test.exs` - every opcode in
  `Instructions.opcode_set/1` appears in at least one authored case
- `test/predicator/conformance/ratchet_registry_test.exs` - the example
  registry against `RATCHET.md`'s rules
- `test/predicator/conformance/package_boundary_test.exs` - no shipped module
  references `Predicator.Conformance`

All six are in `gate.sabotage.test_roots` (`.claude/wurk.json`).

## 6. Prior art: the non-JSON-native operand types

Four exist today. The table below is the shape a fifth would be measured
against; the code is in the references that follow it.

| Checkpoint | `:undefined` | `Date` / `DateTime` | duration |
|---|---|---|---|
| Representation | bare atom, `lib/predicator/undefined.ex` | Elixir stdlib structs, no predicator module | plain map with seven required keys, `lib/predicator/duration.ex` |
| Lexer | `classify_identifier("undefined")`, [`lib/predicator/lexer.ex:501`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/lexer.ex#L501) | `#...#` bracket syntax, disambiguated by a `T`, [`lib/predicator/lexer.ex:658-673`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/lexer.ex#L658-L673) | integer + unit-suffix token pair, [`lib/predicator/lexer.ex:749-758`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/lexer.ex#L749-L758) |
| AST tag | `{:literal, :undefined, pos}`, [`lib/predicator/parser.ex:1369-1372`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/parser.ex#L1369-L1372) | `{:literal, %Date{}, pos}` etc., [`lib/predicator/parser.ex:1375-1382`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/parser.ex#L1375-L1382) | its **own** tag `{:duration, units, pos}`, [`lib/predicator/parser.ex:1877-1899`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/parser.ex#L1877-L1899) |
| Lowering | generic `["lit", value]`, [`lib/predicator/visitors/instructions_visitor.ex:174-176`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/visitors/instructions_visitor.ex#L174-L176) | same generic clause | its **own** opcode `["duration", units]`, [`lib/predicator/visitors/instructions_visitor.ex:328-333`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/visitors/instructions_visitor.ex#L328-L333) |
| Rendering | dedicated clause, [`lib/predicator/visitors/string_visitor.ex:130`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/visitors/string_visitor.ex#L130) | dedicated clauses, [`lib/predicator/visitors/string_visitor.ex:160-165`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/visitors/string_visitor.ex#L160-L165) | dedicated clause, [`lib/predicator/visitors/string_visitor.ex:271-274`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/visitors/string_visitor.ex#L271-L274) |
| Comparison | propagate on non-strict, raw `===` on strict, [`lib/predicator/evaluator.ex:748-758`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L748-L758) | chronological, with `Date`<->`DateTime` coercion, [`lib/predicator/evaluator.ex:764-778`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L764-L778) | falls through as an ordinary map |
| Type naming | `get_value_type(:undefined)`, [`lib/predicator/evaluator.ex:1119`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L1119) | struct match, [`lib/predicator/evaluator.ex:1116-1117`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L1116-L1117) | **structural** check `duration_map?/1`, [`lib/predicator/evaluator.ex:1126-1132`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L1126-L1132) |
| `types.ex` | `\| :undefined` in `value()`, [`lib/predicator/types.ex:62`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/types.ex#L62) | `Date.t() \| DateTime.t()` | the `duration()` type, [`lib/predicator/types.ex:27-38`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/types.ex#L27-L38) |
| Corpus codec | `{"$type":"undefined"}`, `lib/predicator/conformance/values.ex:71, 123` | `{"$type":"date"\|"datetime","value":<iso8601>}`, `lib/predicator/conformance/values.ex:73-80, 125-136` | `{"$type":"duration","value":{...}}`, `lib/predicator/conformance/values.ex:82-88, 138-141` |
| `cast.ex` | propagates to every target, [`lib/predicator/cast.ex:40`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/cast.ex#L40) | identity, parse-or-`:undefined`, format-to-string, `Date`->`DateTime` bridge, [`lib/predicator/cast.ex:47-154`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/cast.ex#L47-L154) | identity + parse + format, same lines |

Two patterns worth naming. **`:undefined` is the only one of the four that
needs no new opcode and no new AST tag** - it rides the generic `{:literal,
...}` / `["lit", value]` path end to end, and its only bespoke code is one
`StringVisitor` clause and a handful of evaluator clauses. **Duration is the
opposite extreme**: its own token pair, its own AST tag, its own opcode, its
own evaluator handler (`lib/predicator/evaluator.ex:629-632, 1737-1747`), and
a structural rather than nominal type check.

**px-a2w**, read in full for this research, is the bead that owns the
serialization ambiguity: `Jason.encode(["lit", :undefined])` produces
`["lit","undefined"]`, indistinguishable on decode from the string operand.
Its findings, recorded on the bead: nothing in `lib/` serializes or
deserializes instruction lists (`Predicator.Compiled` deliberately carries no
serialization, `lib/predicator/compiled.ex:10-38, 74-77`), so no code here is
affected; the conformance corpus has its own tagged encoding and is
unaffected; what is missing is a statement in `docs/isa.md` about what a
consumer persisting compiled artifacts as plain JSON should do. It names three
options - (a) an `docs/isa.md` note pointing at the corpus tagged-value
encoding as the recommended envelope, (b) promoting that encoding out of
`conformance/` into a supported serialization API, (c) declaring it a consumer
concern. It is `area:docs`, P3, in progress, with no document of its own; its
only prose lives in the bead and in
`docs/plans/260812-px-ocp-undefined-literal.md`'s scope-out note.

A null sentinel joins `:undefined`, `Date`, `DateTime`, and duration in that
set, and px-o9v's own bead note says whatever px-a2w decides should cover it.
Note the asymmetry px-a2w does not currently mention: `null` is the one member
of that set that **is** JSON-native as a syntax while being non-native as a
*distinct* predicator value - `Jason.encode` would render it as JSON `null`,
which round-trips to Elixir `nil` cleanly, unlike the atom `:undefined`
rendering as the string `"undefined"`.

## 7. Tests that bind the current collapse

Seven, exhaustively swept.

**`test/predicator/context_test.exs`**

- `:142` `test "deeply converts nil to :undefined in nested maps"` -
  `assert context.data == %{"user" => %{"name" => :undefined}}` (`:145`)
- `:154` `test "converts atom keys and nil inside a list of maps"` -
  `assert context.data == %{"items" => [%{"label" => "a"}, %{"label" => :undefined}]}` (`:157`)
- `:290` `test "normalizes the bound value's atom keys and nil"` -
  `assert bound.data == %{"user" => %{"role" => :undefined}}` (`:294`)
- `:349` `test "true for a string key bound to nil, eagerly normalized to :undefined"` -
  `assert context.data == %{"x" => :undefined}` (`:354`) is the failing line;
  `:355` (`bound?/2`, presence) and `:356` (`evaluate("x > 5") == {:ok, :undefined}`)
  both still pass, the latter because `nil` vs `5` hits `compare_values/3`'s
  catch-all ([`lib/predicator/evaluator.ex:790`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L790))

**`test/predicator/integration/on_unbound_test.exs`**

- `:128` `test "x === undefined with x bound to nil is true under either policy - Context normalizes nil"` -
  both assertions fail (`:129` and `:131-136`); `nil === :undefined` is
  `false`, and under `:error` the key is still present so no error fires

**Doctests** (via `doctest Predicator.Context`)

- [`lib/predicator/context.ex:109`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L109) and [`lib/predicator/context.ex:231`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L231)

**Tests that assert `nil` is preserved, which stay green** (they guard the
opposite invariant and would break only if a change over-reached):

- `test/predicator/context_test.exs:84, 90` - `host` defaults to `nil` and is
  stored unnormalized
- [`test/predicator/evaluator_test.exs:1523`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/test/predicator/evaluator_test.exs#L1523) -
  `test "bound to nil is bound too - only Context.new/2 normalizes nil"`,
  `assert Evaluator.evaluate([["load", "x"]], %{"x" => nil}, on_unbound: :error) == nil`.
  This is the test that documents the bypass boundary.
- [`test/predicator/context_location_test.exs:424`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/test/predicator/context_location_test.exs#L424) -
  `test "treats a nil intermediate as absent and vivifies it"`
- `test/predicator/undefined_test.exs:19, 29, 40, 51, 55` and
  `test/predicator/types_test.exs:14, 61`

**Confirmed clear**: no property tests or generators exist (no StreamData
dependency); no conformance case puts `null` in a `context`
(`grep -oE '"context":\{[^}]*null[^}]*\}' conformance/` is empty); no doc
doctest in `test/docs_examples_test.exs`'s roots (README, language.md, the
four guides) puts `nil` in a context - [`docs/reference/language.md:551-554`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/docs/reference/language.md#L551-L554)
and `:746` describe the normalization in prose only.
[`test/predicator/functions/system_functions_test.exs:108`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/test/predicator/functions/system_functions_test.exs#L108)'s `len(nil)` is
source-level identifier text, not an Elixir `nil`.

## Code References

- [`lib/predicator/context.ex:327`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L327) - the single `nil` -> `:undefined` clause
- [`lib/predicator/context.ex:126`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L126) - `new/2` calls it on the whole map
- [`lib/predicator/context.ex:236`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L236) - `bind/3` calls it on the bound value
- [`lib/predicator/context.ex:304-311`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L304-L311) - `assign/3` does not call it
- [`lib/predicator/context.ex:351-368`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L351-L368) - `normalize_map/1`, atom-key folding
- [`lib/predicator/undefined.ex:25-82`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/undefined.ex#L25-L82) - the sentinel's whole public API
- [`lib/predicator/evaluator.ex:746-819`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L746-L819) - `compare_values/3` and `values_equal?/2`
- [`lib/predicator/evaluator.ex:1333-1340`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L1333-L1340) - `load_from_context/2`
- [`lib/predicator/evaluator.ex:1406-1427`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L1406-L1427) - the bound-vs-undefined distinction
- [`lib/predicator/evaluator.ex:1642-1688`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/evaluator.ex#L1642-L1688) - the three jump-falsiness clauses
- [`lib/predicator/cast.ex:40`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/cast.ex#L40) - `:undefined` propagates through every cast
- [`lib/predicator/types.ex:47-64`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/types.ex#L47-L64) - `value()` excludes `nil`; `context()`
- `lib/predicator/conformance/values.ex:71, 96, 123, 153` - the codec's
  `undefined` tag and its two catch-alls that reject `nil`
- `lib/predicator/instructions.ex:64-96, 292-329` - opcode names only, never
  operand types
- `docs/isa.md` §2 lines 84-107, §3 line 168, §5, §6 lines 678-681
- `docs/reference/language.md:14, 394-405, 551-557, 563-601, 634-645, 710-732, 751-780`

## Architecture Documentation

- **ADR-0001** (`docs/adr/0001-keep-the-stack-vm-revise-the-instruction-set.md`)
  names "typed undefined" as one of six upstream seams and fixes the
  ECMAScript-aligned falsy rule (`false` or `:undefined`, deliberately not
  symmetric-Kleene) for the short-circuit jump opcodes. `docs/isa.md` §2 and
  [`docs/reference/language.md:634-645`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/docs/reference/language.md#L634-L645) are its enforcement.
- **ADR-0003** (`docs/adr/0003-the-elixir-implementation-leads-the-isa.md`)
  governs how the instruction set moves and fixes the plain-JSON wire format
  for instruction lists - the constraint px-a2w exists inside. Per
  `.claude/wurk/research.md`, ADR-0003 amends ADR-0001 without superseding it,
  and a decision's ISA effect is a versioning and stored-artifact question,
  never a sibling-readiness one.
- **ADR-0004** (`docs/adr/0004-no-eval-errors-are-values.md`) - errors are
  values; `UndefinedVariableError` is one of the five structs.
- **ADR-0011** (`docs/adr/0011-casts-are-an-opcode.md`) - `:undefined` as the
  total-failure result of a cast.
- **ADR-0013** (`docs/adr/0013-control-flow-lowers-to-new-jump-opcodes.md`) -
  falsy as the jump condition for `if`/`else`.

The governing convention for this bead's area labels (`area:context`,
`area:evaluator`) is ADR-0005's file-collision algebra; neither label is
`area:build`, so the bead batches with anything touching disjoint files. Note
that a change reaching `docs/reference/language.md`, `docs/isa.md`, or
`CHANGELOG.md` would also carry `area:docs`, and one reaching
`conformance/` would carry `area:conformance`.

## Historical Context

- `docs/plans/260805-px-8um.2-context-key-normalization.md` - the plan that
  introduced the normalization this bead questions (atom-key folding and
  `nil` -> `:undefined`), shipped in `[3.7.0]`/`[3.8.0]`.
- `docs/plans/260805-px-8um.3-on-unbound-policy.md` - the `:undefined` vs
  `:error` policy.
- `docs/plans/260804-px-8um.4-undefined-bound-check.md` - the `===` vs `==`
  distinction, written before the literal existed.
- `docs/plans/260804-px-8um.8-runtime-unbound-tracking.md` - the trace-back
  rule that distinguishes an unbound root from an absent nested path.
- `docs/plans/260804-px-8um.1-context-struct.md` - the `%Context{}` struct.
- `docs/research/260812-px-ocp-undefined-literal.md` and
  `docs/plans/260812-px-ocp-undefined-literal.md` - the `undefined` literal
  (5.0.0). The plan's scope-out note is where px-a2w was filed, and its ISA
  argument ("a new spelling for an instruction that already existed") is the
  precedent this bead's value half would lean on.
- `docs/research/260808-px-tbv.2-store-opcode-execute.md` and
  `docs/plans/260808-px-tbv.2-store-opcode-execute.md` - the `store` opcode
  and its `:undefined`-slot auto-vivification.
- `docs/design/260806-px-35i.4-corpus-format-and-tooling.md` - the corpus
  format including the `$type` encoding.
- `docs/design/260807-px-h66-scxml-error-semantics.md` - SCXML error
  semantics, the statifier-facing surface px-o9v was raised from.

Statifier-side: the bead's `mirrors`-adjacent tracking is `st-7ft`, with the
gap recorded in statifier's
`docs/plans/260812-st-af3.3-datamodel-data-early-late-binding.md`, open
question 8. Per ADR-0010 and CLAUDE.md's cross-repo table, this repo owns the
language decision and statifier's bead owns how statifier consumes it; that
statifier document was not read for this research and its note has not been
refreshed here.

## Related Research

- `docs/research/260812-px-ocp-undefined-literal.md` - the closest prior
  research; the literal half of the same subject
- `docs/research/260808-px-tbv.2-store-opcode-execute.md` - `:undefined` in
  context writes
- `docs/research/260807-px-t2v-px-z5m-isa-retirement-and-pop.md` - ISA
  retirement mechanics
- `docs/research/260807-px-phw-conformance-area-label.md` - the area-label
  argument for `area:conformance`

## Open Questions

1. **The bead's first open question, answered with a caveat.** The bead asks
   whether anything relies on the `nil` -> `:undefined` collapse. Against the
   test suite: only 7 assertions, all in `Context`'s own suite plus one
   `on_unbound` integration test, listed in section 7. Nothing in `lib/`
   depends on it structurally - the evaluator consumes `:undefined` without
   caring where it came from. **The caveat**: `nil` already reaches evaluation
   by six non-Context paths (section 1), where it has no defined semantics at
   all - it silently falls through evaluator catch-alls. Any change here has
   to decide whether those paths now produce the new null value, keep
   producing raw `nil`, or start erroring. That decision is a design question
   this document does not answer.

2. **The comparison semantics question is genuinely open and is not derivable
   from the codebase.** The bead asks whether `null === undefined` is false
   (ECMAScript `===`) or true (ECMAScript `==`). Predicator has *both*
   operators (`==` non-strict, `===` strict), which the bead's framing
   ("Predicator has one equality operator") does not reflect - so the choice
   is actually four-way, not two-way: what `null == undefined`,
   `null === undefined`, `null == null`, and `null === null` each answer.
   Today's `:undefined` answers `:undefined`, `true`, `:undefined`, `true`
   respectively for the corresponding self- and cross-comparisons
   (section 2). No existing artifact constrains the null answers.

3. **`Context.assign/3`'s undocumented asymmetry.** `assign/3` does not
   normalize its value, so it already stores a raw `nil` where `bind/3` would
   store `:undefined`. No test covers it and no `@doc` mentions it. Whether
   that is intended, and whether it changes under this bead, is unresolved.

4. **Two definition sites for one rule.** `Undefined.from_nil/1`
   ([`lib/predicator/undefined.ex:80-82`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/undefined.ex#L80-L82)) and
   `Context.normalize_value(nil)` ([`lib/predicator/context.ex:327`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/context.ex#L327)) implement
   the same conversion independently. `from_nil/1` is public API documented
   for "normalizing an incoming `nil` at the edge", so a consumer may be
   relying on it directly; this research found no in-repo caller.

5. **Whether a null sentinel is a struct, an atom, or `nil` itself.** The
   prior art gives three shapes (atom sentinel, stdlib struct, structural
   plain map) with no obvious precedent for a second atom sentinel. Nothing
   in the codebase forecloses any of them. Related: `Types.value()`
   ([`lib/predicator/types.ex:47-62`](https://github.com/riddler/predicator-ex/blob/19b10f579d905fb51de59750c0ac1768860631ae/lib/predicator/types.ex#L47-L62)) does not include `nil`, so representing
   null *as* `nil` would widen the declared value type in a way the other
   three options would not.

6. **px-a2w's scope relative to this bead.** px-a2w is `area:docs` and in
   progress with no document of its own; it currently enumerates four
   non-JSON-native operand types. Whether it should be extended before or
   after px-o9v decides on a representation - and whether a JSON-native
   `null` even belongs in its set, given it round-trips cleanly where
   `:undefined` does not - is unresolved. No human was available to ask.

7. **Whether the ISA §3 value domain would need to widen.** Answered
   conditionally in the ISA Impact section: not for a context-only value,
   yes for anything that can be a `lit` operand. Which of the two the value
   half is depends on a design decision not yet made - specifically whether
   `Predicator.Compiled` instruction lists (built by the compiler, never
   hand-written) could ever carry the new value in a `lit`, e.g. via constant
   folding or a future `store` of a null.
