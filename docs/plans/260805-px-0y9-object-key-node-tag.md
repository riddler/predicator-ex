# Object Key Node Tag Implementation Plan

## Overview

Object keys currently reuse the expression node tags `:identifier` and
`:string_literal`, and are told apart from expression nodes by tuple arity
alone. This plan gives them their own tag - `{:object_key, value, style, pos}` -
so the distinction is explicit, and confines every pre-4.0 AST shape to the two
boundary normalizers that exist to hold it.

Beads issue: px-0y9.

## Current State Analysis

An object entry is `{key_node, value_node}`. The parser builds the key at
`lib/predicator/parser.ex:1274`:

```elixir
defp parse_object_key(state) do
  case peek_token(state) do
    {:identifier, line, col, _len, value} ->
      {:ok, {:identifier, value, {line, col}}, advance(state)}

    {:string, line, col, _len, value, _quote_type} ->
      {:ok, {:string_literal, value, {line, col}}, advance(state)}
    ...
```

Three problems follow from this.

**1. Arity is the only discriminator.** An expression string literal is
`{:string_literal, value, quote_type, pos}` (arity 4); a key's is
`{:string_literal, value, pos}` (arity 3). The identifier forms coincide
*exactly* at `{:identifier, name, pos}` - a key is distinguishable from a
variable reference only by the position it occupies in the tree. In a codebase
where every visitor clause is a pattern match, a future node landing on the same
arity silently matches the wrong clause. `strip_positions/1` already pays for
this with a guard whose only job is to disambiguate arity 3
(`lib/predicator/parser.ex:285`):

```elixir
def strip_positions({:string_literal, value, pos}) when is_tuple(pos) or is_nil(pos),
  do: {:string_literal, value}
```

**2. The lexer's quote type is discarded for keys.** `parse_object_key/1`
matches `_quote_type` and throws it away, so `{'first name': 1}` and
`{"first name": 1}` produce identical ASTs. `StringVisitor` therefore
hardcodes double quotes at `lib/predicator/visitors/string_visitor.ex:333`:

```elixir
defp format_object_key({:string_literal, value, _position}), do: ~s("#{value}")
```

Expression string literals do *not* work this way - `do_visit/2` at
`string_visitor.ex:113` honors the quote type and escapes the quote character.
The key path does neither, so a key containing a double quote decompiles to
syntactically broken source today. That is a latent round-trip bug this change
fixes as a side effect of carrying the style.

**3. Two shipped shapes, not one.** v3.7.0 is tagged and on Hex (released
2026-08-05), so the positioned key forms are public API, not an unreleased
detail. `docs/architecture.md:215` still labels the section "(v3.7.0,
unreleased)", which is stale. That means `ensure_positions/1` has *two* legacy
key shapes to absorb, not one:

| Era | Identifier key | String key |
|---|---|---|
| 3.6 (bare) | `{:identifier, name}` | `{:string_literal, value}` |
| 3.7 (positioned) | `{:identifier, name, pos}` | `{:string_literal, value, pos}` |

### Key Discoveries

- The full consumer set is five call sites, all private helpers:
  `extract_key_string/1` and `key_position/1`
  (`lib/predicator/visitors/instructions_visitor.ex:333-339`),
  `format_object_key/1` (`lib/predicator/visitors/string_visitor.ex:331-333`),
  plus `strip_entry/1` (`parser.ex:362`) and `ensure_entry/1`
  (`parser.ex:470`). Nothing outside the parser and the two visitors pattern
  matches an object key - the evaluator sees only the `object_set` instruction,
  which carries a plain string.
- `strip_positions/1` and `ensure_positions/1` are the codebase's one designated
  compatibility edge (`docs/architecture.md:279-286`): the visitors call
  `ensure_positions/1` at their public entry points, "which is what lets
  `Predicator.decompile/2` and `Compiler.to_instructions/2` keep accepting a
  hand-built 3.6-shaped AST. Visitor clauses therefore have exactly one form
  each." That sentence is what makes the fix cheap: legacy shapes are already
  quarantined, so retagging changes exactly one clause per consumer.
- Routing keys through key-specific helpers means the two *global* legacy
  clauses can be deleted outright, not merely retagged: the arity guard at
  `parser.ex:285-286` and `ensure_positions({:string_literal, value})` at
  `parser.ex:383`. Both exist only to serve key nodes.
- The `bare_object_key` type (`parser.ex:159`) describes the frozen 3.6 output
  of `strip_positions/1` and is unchanged by this work.
- px-tbv is the 4.0.0 epic and is already the batching point for breaking
  removals (px-tbv.7 drops `ParseError`'s `:line`/`:column`; px-tbv.6 bumps the
  Elixir floor). The pre-4.0 shape layer should be cut there in one piece rather
  than dribbled across minors.
- ADR-0001 is untouched: no instruction gains an element and no opcode is added.
  `object_set` still carries a plain string key.

## Desired End State

An object key is `{:object_key, value, style, pos}` where `style` is
`:identifier`, `:double`, or `:single`. No consumer distinguishes node kinds by
arity. `parse_object_key/1` preserves the quote character, so single-quoted keys
round-trip as single-quoted and quote characters inside keys are escaped. Every
pre-4.0 key shape is accepted by `ensure_positions/1` and by nothing else.

Verified by: the full `mix quality` gate green; `Predicator.parse/1` returning
the new shape; `Predicator.decompile/2` round-tripping `{'a b': 1}` unchanged;
hand-built 3.6-shaped ASTs (including the `StringVisitor` doctest at
`string_visitor.ex:52`) still compiling and decompiling.

## What We're NOT Doing

- **Not removing the legacy shape acceptance.** `ensure_positions/1` keeps
  absorbing both the 3.6 bare and 3.7 positioned key forms, and
  `strip_positions/1` keeps emitting the 3.6 shape its `@doc` promises. Retiring
  the whole pre-4.0 layer is filed as a 4.0.0 bead under px-tbv (Phase 2) so it
  lands as one cut alongside px-tbv.7, not as half a break inside a minor.
- **Not making `strip_positions/1` lossless.** It discards `style` along with
  the position, exactly as it discards the expression `quote_type` today. Its
  contract is "the shape 3.6 produced", and 3.6 had no style on a key.
- **Not changing the instruction set.** No `Cross-Language Impact` section
  follows, because there is nothing for the Ruby and JavaScript siblings to do.
- **Not touching `bare_object_key`, the lexer, or the grammar.** The surface
  syntax `object_key -> IDENTIFIER | STRING` is unchanged; only the AST node it
  produces changes.
- **Not revisiting whether an identifier key should be a distinct concept from a
  quoted key at the grammar level.** They stay one node with a style field.

## Implementation Approach

Phase 1 is atomic: parser and both visitors must move together, because an
intermediate state where the parser emits `{:object_key, ...}` and the visitors
still match `{:identifier, ...}` leaves `mix quality` red. It is one shape change
across a five-call-site surface, so there is no smaller independently
gate-verifiable unit.

Phase 2 is documentation, the changelog entry, and the follow-up bead - green on
its own, and separable because it changes no Elixir.

The ordering inside Phase 1 is: type and parser first (so the new shape exists),
then the normalizers (so legacy input keeps working), then the two visitors, then
the tests. Use `mix quality --profile loop` between steps; the phase gate is the
full run.

## Phase 1: The `{:object_key, value, style, pos}` Node

### Overview

Introduce the tag, preserve the quote type, route keys through key-specific
normalizers, and delete the two global legacy clauses that only existed to serve
keys.

### Changes Required:

#### 1. The object key type

**File**: `lib/predicator/parser.ex`
**Changes**: Retag `object_key/0`, add a `style` typedoc. Leave
`bare_object_key/0` (line 159) alone - it describes `strip_positions/1` output.

```elixir
@typedoc """
A key in an object literal.

Object keys have their own tag rather than reusing the expression node tags,
so no consumer has to tell a key from an expression by tuple arity. `style`
records how the key was written - bare, or quoted with which character - so
`Predicator.Visitors.StringVisitor` can render it back as the author wrote it.
"""
@type object_key :: {:object_key, binary(), object_key_style(), position()}

@typedoc """
How an object key was written: bare (`{name: 1}`), double-quoted
(`{"name": 1}`), or single-quoted (`{'name': 1}`).
"""
@type object_key_style :: :identifier | :double | :single
```

Also update the `{:object, entries, pos}` bullet in the `ast/0` typedoc
(`parser.ex:99`) to point at `object_key/0`.

#### 2. The parser production

**File**: `lib/predicator/parser.ex` (`parse_object_key/1`, line 1274)
**Changes**: Emit the new tag and stop discarding `quote_type`.

```elixir
defp parse_object_key(state) do
  case peek_token(state) do
    {:identifier, line, col, _len, value} ->
      {:ok, {:object_key, value, :identifier, {line, col}}, advance(state)}

    {:string, line, col, _len, value, quote_type} ->
      {:ok, {:object_key, value, quote_type, {line, col}}, advance(state)}

    {type, line, col, _len, value} ->
      {:error,
       "Expected identifier or string for object key but found #{format_token(type, value)}",
       line, col}

    nil ->
      {:error, "Expected object key but reached end of input", 1, 1}
  end
end
```

The position rule is unchanged: a key points at its own token
(`docs/architecture.md:255`).

#### 3. The boundary normalizers

**File**: `lib/predicator/parser.ex`
**Changes**: Give keys their own normalizers, called from `strip_entry/1` and
`ensure_entry/1`, and **delete** the two global clauses that only served keys.

```elixir
@spec strip_entry({term(), term()}) :: {term(), term()}
defp strip_entry({key, value}), do: {strip_object_key(key), strip_positions(value)}

# Object keys strip back to the 3.6 shape, which had no style on a key.
@spec strip_object_key(term()) :: term()
defp strip_object_key({:object_key, value, :identifier, _pos}), do: {:identifier, value}
defp strip_object_key({:object_key, value, _style, _pos}), do: {:string_literal, value}
defp strip_object_key(key), do: strip_positions(key)

@spec ensure_entry({term(), term()}) :: {term(), term()}
defp ensure_entry({key, value}), do: {ensure_object_key(key), ensure_positions(value)}

# Accepts every pre-4.0 key shape: 3.6 bare and 3.7 positioned, identifier and
# string. A string key predating this change carries no quote type, so it
# normalizes to `:double` - the quote character StringVisitor always used for
# it. Retired wholesale in 4.0.0 (see px-tbv).
@spec ensure_object_key(term()) :: term()
defp ensure_object_key({:object_key, _value, _style, _pos} = key), do: key
defp ensure_object_key({:object_key, value, style}), do: {:object_key, value, style, nil}
defp ensure_object_key({:identifier, value}), do: {:object_key, value, :identifier, nil}
defp ensure_object_key({:identifier, value, pos}), do: {:object_key, value, :identifier, pos}
defp ensure_object_key({:string_literal, value}), do: {:object_key, value, :double, nil}

defp ensure_object_key({:string_literal, value, pos}) when is_tuple(pos) or is_nil(pos),
  do: {:object_key, value, :double, pos}

defp ensure_object_key(key), do: key
```

Delete outright:

- `strip_positions({:string_literal, value, pos}) when is_tuple(pos) or is_nil(pos)`
  (`parser.ex:285-286`) - the arity guard. Keys no longer reach
  `strip_positions/1`, and an arity-3 `:string_literal` in expression position is
  the 3.6 `{:string_literal, value, quote_type}` form, already handled.
- `ensure_positions({:string_literal, value})` (`parser.ex:383`) - the bare-key
  clause. A two-element `:string_literal` was never a valid expression node; it
  is a key, and keys now go through `ensure_object_key/1`. Outside key position
  it falls to the existing passthrough, which is the correct answer for a node
  that has no valid expression reading.

Note the deliberate asymmetry, which mirrors `ensure_positions/1`'s own tolerance
of a mixed tree: `strip_object_key/1` falls back to `strip_positions/1` so an
already-legacy key in a hand-built tree strips idempotently, while
`ensure_object_key/1` passes an unrecognized node through, matching
`ensure_positions/1`'s "unrecognized node passes through rather than raising"
contract (`parser.ex:269`).

#### 4. `InstructionsVisitor`

**File**: `lib/predicator/visitors/instructions_visitor.ex` (lines 333-339)
**Changes**: Both helpers collapse to one clause each.

```elixir
# Helper function to extract string from object key node
@spec extract_key_string(Parser.object_key()) :: binary()
defp extract_key_string({:object_key, value, _style, _position}), do: value

@spec key_position(Parser.object_key()) :: Types.position() | nil
defp key_position({:object_key, _value, _style, position}), do: position
```

The emitted `object_set` instruction is byte-identical to today's; only the node
it reads from changed.

#### 5. `StringVisitor`

**File**: `lib/predicator/visitors/string_visitor.ex` (lines 331-333)
**Changes**: Render by style, reusing the escaping the expression path already
does at `string_visitor.ex:113-126`.

```elixir
@spec format_object_key(Parser.object_key()) :: binary()
defp format_object_key({:object_key, value, :identifier, _position}), do: value

defp format_object_key({:object_key, value, :double, _position}),
  do: ~s("#{String.replace(value, "\"", "\\\"")}")

defp format_object_key({:object_key, value, :single, _position}),
  do: ~s('#{String.replace(value, "'", "\\'")}')
```

The module doctests at `string_visitor.ex:44-54` use 3.6-shaped ASTs and must
keep producing the same strings unchanged - that is the compatibility check,
so do not "modernize" them to the new tag.

#### 6. Tests

**Files**: `test/predicator/parser_positions_test.exs:113-118`,
`test/predicator/parser_normalization_test.exs:65-66,107,122-123`,
`test/predicator/object_parser_test.exs`,
`test/predicator/parser_edge_cases_test.exs:136-161`,
`test/predicator_test.exs:1006`, and any `visitors/` test asserting a key shape.

Update assertions to the new tag, and add coverage for what is new:

```elixir
test "an object key carries its quote style" do
  assert {:ok, {:object, [{{:object_key, "a b", :single, {1, 2}}, _v}], {1, 1}}} =
           Predicator.parse("{'a b': 1}")

  assert {:ok, {:object, [{{:object_key, "a b", :double, {1, 2}}, _v}], {1, 1}}} =
           Predicator.parse(~s({"a b": 1}))

  assert {:ok, {:object, [{{:object_key, "a", :identifier, {1, 2}}, _v}], {1, 1}}} =
           Predicator.parse("{a: 1}")
end

test "a single-quoted object key round-trips as single-quoted" do
  {:ok, ast} = Predicator.parse("{'a b': 1}")
  assert Predicator.decompile(ast) == "{'a b': 1}"
end

test "ensure_positions/1 lifts every pre-4.0 object key shape" do
  for legacy <- [
        {:identifier, "k"},
        {:identifier, "k", {1, 2}},
        {:string_literal, "k"},
        {:string_literal, "k", {1, 2}}
      ] do
    assert {:object, [{{:object_key, "k", style, _pos}}, _v], _} =
             Parser.ensure_positions({:object, [{legacy, {:literal, 1}}]})

    assert style in [:identifier, :double]
  end
end
```

The `parser_normalization_test.exs` test named "distinguishes an object-key
string literal from an expression one" (line 106) is testing the arity guard
being deleted. Rewrite it to assert the key/expression distinction through key
*position* instead of through arity - that is the property that replaces it.

The `@corpus` round-trip tests in `parser_normalization_test.exs:75-92` should
gain an object literal with a single-quoted key if they lack one, since strip ->
ensure is now style-lossy in a new way (`:single` returns as `:double`) and the
round-trip assertion must be written to expect that rather than accidentally
pass.

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality`
- [x] Coverage stays above the 90% minimum in `coveralls.json`, including the
      three `format_object_key/1` style clauses and every `ensure_object_key/1`
      legacy arm
- [x] `grep -rn "string_literal, [a-z_]*, position}" lib` returns nothing - no
      arity-3 string literal clause survives outside key normalization
- [x] The `StringVisitor` module doctests at `string_visitor.ex:44-54` pass
      unmodified

#### Manual Verification:
- [x] `Predicator.parse("{'a b': 1}") |> elem(1) |> Predicator.decompile()`
      returns `{'a b': 1}`, not `{"a b": 1}`
- [x] A key containing a quote character decompiles to re-parseable source:
      `Predicator.parse(~s({"say \\"hi\\"": 1}))` round-trips
- [x] A hand-built 3.6-shaped object AST still compiles:
      `Predicator.Compiler.to_instructions({:object, [{{:identifier, "a"}, {:literal, 1}}]})`
- [x] The parse error for `{1: 2}` still names the right position

**Implementation Note**: Use `mix quality --profile loop` between edits while
iterating; run the full `mix quality` as the phase gate. In interactive
execution, pause here for manual confirmation before Phase 2. In looped
(`--loop`) execution, the Automated Verification gates advancement and Manual
Verification is surfaced at the end.

---

## Phase 2: Documentation, Changelog, and the 4.0 Follow-Up

### Overview

Record the break, correct two stale statements in the architecture doc, and file
the deferred cleanup where it will actually be done.

### Changes Required:

#### 1. `docs/architecture.md`

**Changes**: Three edits in the "Source Positions" section.

- Line 215: the heading says "(v3.7.0, unreleased)". It shipped on 2026-08-05.
  Drop "unreleased".
- Lines 244-246: this paragraph is now false.

  ```markdown
  Object keys have their own node - `{:object_key, value, style, pos}`, where
  `style` is `:identifier`, `:double`, or `:single`. They do not reuse the
  expression tags, so nothing tells a key from an expression by tuple arity, and
  the style records how the key was written so it decompiles back the same way.
  ```

- Add `{:object_key, value, style, pos}` to the node inventory block
  (lines 224-242).

The "Boundary normalizers" paragraph (lines 279-286) gains a sentence noting
that `ensure_positions/1` also lifts the pre-4.0 key shapes, and that this
acceptance is scheduled for removal in 4.0.0.

Match the file's existing typography when editing it.

#### 2. `CHANGELOG.md`

**Changes**: An entry under `## [Unreleased]` -> `### Changed`, in the style of
3.7.0's own "one more trailing element" note (`CHANGELOG.md:76-80`). It must
cover both observable changes:

- Object keys are now `{:object_key, value, style, pos}` rather than
  `{:identifier, name, pos}` / `{:string_literal, value, pos}`. Callers
  pattern-matching a parsed object entry's key update their patterns;
  `Parser.strip_positions/1` still returns the 3.6 shape, and
  `Parser.ensure_positions/1` still accepts every earlier shape, so a hand-built
  AST passed to `decompile/2` or `to_instructions/2` is unaffected.
- `Predicator.decompile/2` now renders a single-quoted object key with single
  quotes instead of rewriting it to double quotes, and escapes a quote character
  inside a key - which previously produced syntactically invalid output.

#### 3. The 4.0.0 follow-up bead

**Changes**: File it under the px-tbv epic (non-interactive flags only, per
CLAUDE.md - no `bd edit`):

```bash
bd create "Retires the pre-4.0 AST shape acceptance" \
  --parent px-tbv --type task -p 3 \
  --label area:lexer-parser --label area:docs \
  --description "..."
```

The description records: delete every legacy arm of
`Parser.strip_positions/1`, `Parser.ensure_positions/1`, `strip_object_key/1`,
and `ensure_object_key/1`; decide whether `ensure_positions/1` survives at all as
a convenience for hand-built ASTs once the legacy shapes are gone, or whether the
visitors simply require positioned input; drop the `bare_ast/0` and
`bare_object_key/0` types. Note it should land with px-tbv.7 so 4.0.0 carries one
AST break, not two.

#### 4. The bead's area labels

**Changes**: px-0y9 carries `area:lexer-parser` and `area:visitors`, but this
work also edits `docs/architecture.md` and `CHANGELOG.md`. Add the missing label
rather than letting the branch touch an unlabeled area (CLAUDE.md):

```bash
bd update px-0y9 --label area:docs
```

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes: `mix quality` (the docs are compiled into
      `ex_doc`, so a malformed link or code fence fails here)
- [x] `bd show px-tbv` lists the new child bead
- [x] `bd show px-0y9` shows `area:docs`

#### Manual Verification:
- [x] The architecture doc's node inventory matches `Parser.ast/0` and
      `Parser.object_key/0` exactly, with no arity claim left in the prose
- [x] The changelog entry tells a caller what to change in their code, not just
      what moved
- [x] The follow-up bead is specific enough to act on without rereading this
      plan

---

## Testing Strategy

### Unit Tests:
- **Parser** (`test/predicator/object_parser_test.exs`,
  `parser_positions_test.exs`): the three styles produce the right `style` atom;
  the key's position is its own token; the empty object and the parse errors for
  a missing key and a missing colon are unchanged.
- **Normalizers** (`test/predicator/parser_normalization_test.exs`): every
  pre-4.0 key shape lifts through `ensure_positions/1`; `strip_positions/1`
  returns the 3.6 form for each style; both stay total and idempotent; a mixed
  tree with one legacy key and one new key normalizes correctly.
- **StringVisitor** (`test/predicator/visitors/string_visitor_test.exs`): each
  style renders as written; a quote character inside a key is escaped; the
  3.6-shaped module doctests still pass.
- **InstructionsVisitor** (`test/predicator/visitors/instructions_visitor_test.exs`,
  `instructions_visitor_positions_test.exs`): `object_set` is byte-identical to
  before for every style, and carries the key's position.

### Integration Tests:
- `test/predicator/object_integration_test.exs`: end-to-end
  `Predicator.evaluate/3` over objects is unchanged - this change must be
  invisible to evaluation, which is the strongest evidence it is behavior
  preserving.
- A source -> parse -> decompile -> parse round trip over an object literal with
  one key of each style, asserting the two ASTs are equal.

### Manual Testing Steps:
1. In `iex -S mix`, parse `{a: 1, "b c": 2, 'd e': 3}` and confirm all three
   keys carry the right style and their own positions.
2. Decompile that AST and confirm the output re-parses to an equal AST.
3. Compile a hand-built 3.6-shaped object AST through
   `Predicator.Compiler.to_instructions/1` and confirm the instructions match
   the parsed equivalent.
4. Confirm `{1: 2}` and `{a 1}` still produce their existing error messages and
   positions.

## Performance Considerations

None. The node gains one element; the visitors do the same work in one clause
instead of two. `ensure_object_key/1` adds a handful of clauses on a path that
already exists.

## References

- Beads issue: `px-0y9` (discovered from px-e3g.4, decision 4)
- Related epic: `px-tbv` (Predicator 4.0.0), where the deferred cleanup lands
- Related ADR: `docs/adr/0001-keep-the-stack-vm-revise-the-instruction-set.md` -
  unaffected; no instruction or opcode changes
- Prior plan: `docs/plans/260805-px-e3g.4-source-positions.md:145-146`, which
  named this asymmetry when it created it
- Architecture: `docs/architecture.md:213-286` (Source Positions), specifically
  `:244-246` (the arity sentence) and `:279-286` (boundary normalizers)
- Parser: `lib/predicator/parser.ex:159-172` (types), `:280-362`
  (`strip_positions/1`), `:381-470` (`ensure_positions/1`), `:1274-1290`
  (`parse_object_key/1`)
- Visitors: `lib/predicator/visitors/instructions_visitor.ex:238-249,333-339`;
  `lib/predicator/visitors/string_visitor.ex:44-54,113-126,233-249,331-333`
