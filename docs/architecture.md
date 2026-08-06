# Predicator: Architecture and Language Reference

This document is the detailed reference for the Predicator codebase: the
grammar, the compilation pipeline, the component map, and the per-feature
history behind them. `CLAUDE.md` at the repo root is the entry point and holds
the working rules; this is what those rules are about.

## Project Overview

Predicator is a secure, non-evaluative condition engine for processing end-user boolean predicates in Elixir. It provides a complete compilation pipeline from string expressions to executable instructions without the security risks of dynamic code execution. Supports arithmetic operators (+, -, *, /, %) with proper precedence, comparison operators (>, <, >=, <=, =, !=), logical operators (AND, OR, NOT), date/datetime literals, list literals, object literals with JavaScript-style syntax, membership operators (in, contains), function calls with built-in system functions, nested data structure access using dot notation, and bracket access for dynamic property and array access.

## Architecture

```text
Expression String → Lexer → Parser → Compiler → Instructions → Evaluator
                                    ↓
                              StringVisitor (decompile)
```

### Grammar with Operator Precedence

```text
expression   → logical_or
logical_or   → logical_and ( ("OR" | "or") logical_and )*
logical_and  → logical_not ( ("AND" | "and") logical_not )*
logical_not  → ("NOT" | "not") logical_not | comparison
comparison   → addition ( ( ">" | "<" | ">=" | "<=" | "=" (deprecated) | "==" | "!=" | "===" | "!==" | "in" | "contains" ) addition )?
addition     → multiplication ( ( "+" | "-" ) multiplication )*
multiplication → unary ( ( "*" | "/" | "%" ) unary )*
unary        → ( "-" | "!" ) unary | postfix
postfix      → primary ( "[" expression "]" | "." IDENTIFIER )*
primary      → NUMBER | FLOAT | STRING | BOOLEAN | DATE | DATETIME | IDENTIFIER | duration | relative_date | list | object | function_call | "(" expression ")"
function_call → FUNCTION_NAME "(" ( expression ( "," expression )* )? ")"
list         → "[" ( expression ( "," expression )* )? "]"
object       → "{" ( object_entry ( "," object_entry )* )? "}"
object_entry → object_key ":" expression
object_key   → IDENTIFIER | STRING
duration     → NUMBER UNIT+
relative_date → duration "ago" | duration "from" "now" | "next" duration | "last" duration
```

`=` in the `comparison` production is **deprecated** as of 3.8. It still parses
and still compiles to `["compare", "EQ"]`, but parsing one emits a deprecation
warning (`px-8um.5`). 4.0 removes it from this production - see "The `=`
grammar break (4.0)" under Cross-Language Siblings for the rule that replaces
it and what it means for the Ruby and JavaScript implementations, and
[ADR-0002](adr/0002-the-equals-grammar-break.md) for the alternatives it was
weighed against and the known-consumer survey behind the one-release notice
period.

### Core Components

- **Lexer** (`lib/predicator/lexer.ex`): Tokenizes expressions with position tracking
- **Parser** (`lib/predicator/parser.ex`): Recursive descent parser building AST
- **Compiler** (`lib/predicator/compiler.ex`): Converts AST to executable instructions  
- **Evaluator** (`lib/predicator/evaluator.ex`): Executes instructions against data
- **Visitors** (`lib/predicator/visitors/`): AST transformation modules
  - **StringVisitor**: Converts AST back to strings
  - **InstructionsVisitor**: Converts AST to executable instructions
- **Functions** (`lib/predicator/functions/`): Function system components
  - **SystemFunctions**: Built-in system functions (len, upper, abs, max, etc.) provided via `all_functions/0`
- **Main API** (`lib/predicator.ex`): Public interface with convenience functions
- **Context** (`lib/predicator/context.ex`): A bound evaluation context - `data`,
  `functions` (builtins merged with `opts[:functions]` once, at construction),
  and an `on_unbound` policy (`:undefined` | `:error`). `new/2` builds one, `bind/3` rebinds
  a key in O(1), `assign/3` writes through `ContextLocation.put/3`,
  `bound?/2` answers whether a root name is present in `data` (string or atom
  key). `evaluate/3` accepts a `%Context{}` directly (skipping the per-call
  function merge) or a bare map (unchanged behavior, via an internal one-shot
  `Context.new/2`)
- **Undefined** (`lib/predicator/undefined.ex`): The one public module that
  owns the `:undefined` sentinel - `value/0`, `undefined?/1`, and
  `to_nil/1`/`from_nil/1` normalizers for a JSON-shaped boundary.
  `Predicator.Types.undefined?/1` delegates to it

## Cross-Language Siblings

Predicator has Ruby and JavaScript implementations in the
[riddler/predicator](https://github.com/riddler/predicator) monorepo
(`impl/rb`, `impl/ts`). The instruction list is the interchange format; the
expression string is not. Parity is already partial - objects, durations, and
strict equality postdate the siblings - and ADR-0001 adds four more opcodes
(`jump_if_falsy_or_pop`, `jump_if_true_or_pop`, `make_list`, `store`) that they
do not yet implement. The Elixir side ships the first two as of 3.7.0: `AND`
and `OR` now short-circuit, and a compiled instruction list containing
`jump_if_falsy_or_pop` or `jump_if_true_or_pop` will not run on a sibling that
hasn't added them.

### The `=` grammar break (4.0)

4.0 makes `=` assignment-only and valid only in statement position; `==` and
`===` are the only equality operators, and `=` in expression position is a
parse error. 3.8 warns first, so consumers get one release of notice. See
[ADR-0002](adr/0002-the-equals-grammar-break.md) for the decision record.

The siblings' lexers still tokenize `=` as an equality operator
(`impl/rb/lib/predicator/lexer.rex` line 21, `impl/ts/src/tokens.js` line 70),
and their parsers will keep accepting `status = 'active'` until they adopt the
same rule.

Scope of the divergence:

- **Surface syntax only.** A rule string using `=` for equality parses in Ruby
  and JavaScript and fails to parse in Elixir on 4.0.
- **The instruction set is untouched.** `=` and `==` both compile to
  `["compare", "EQ"]`, so compiled artifacts still interchange in every
  direction and no stored instruction list is invalidated by the break.

ADR-0001's consequences call for the matching note in each sibling README.
Adopting the rule in the siblings is coordinated in that repo, not here.

## Development

### Development Workflow

The workflow rules - branch, gate, commit, push, close, release - live in
`CLAUDE.md`'s agent-authority table, which is the single authority on them.
The short version: work happens on a feature branch, full `mix quality` must
be green before a commit, and user-facing changes update `CHANGELOG.md` under
`## [Unreleased]` plus this document and the README where they are affected.

### Testing Commands

```bash
mix test                    # Run all tests
mix test.coverage          # Coverage report
mix test.coverage.html     # HTML coverage report
```

### Code Quality Commands

```bash
mix quality                # Run all quality checks (format, compile, credo,
                           # dialyzer, deps audit, suite with coverage)
mix quality --profile loop # Inner loop: no dialyzer, no coverage, changed
                           # tests only. Never the final check.
mix format                 # Format code
mix credo --strict         # Lint with strict mode
mix dialyzer              # Type checking
```

The gate is [ex_quality](https://hex.pm/packages/ex_quality); what it runs is
configured in `.quality.exs`, and the thresholds it enforces stay with the
tools that own them - `coveralls.json` for the 90% coverage minimum, `.credo.exs`
for the checks, `mix.exs` for the Dialyzer PLT.

### Coverage Stats

- **Overall**: 92.2%
- **Evaluator**: 95.7% (arithmetic with type coercion, unary, and all operations)
- **StringVisitor**: 97.5% (all formatting options)
- **InstructionsVisitor**: 95.2% (all AST node types)
- **Lexer**: 98.4% (all token types including floats and arithmetic)
- **Parser**: 86.4% (complex expressions with precedence and float support)
- **Target**: >90% for all components ✅

## Key Design Decisions

### Security First

- No `eval()` or dynamic code execution
- All expressions compiled to safe instruction sequences
- Input validation at lexer/parser level

### Error Handling

- Comprehensive error messages with line/column positions
- Graceful error propagation through pipeline stages
- Type-safe error handling with `{:ok, result} | {:error, message, line, col}` tuples

### Performance

- Compile-once, evaluate-many pattern supported
- Efficient instruction-based execution
- Minimal memory allocation during evaluation

### Complexity Management

- Credo complexity warnings suppressed for lexer/parser with explanatory comments
- High complexity is appropriate and necessary for these functions
- Well-tested and contained complexity

## File Structure

```text
lib/predicator/
├── lexer.ex           # Tokenization with position tracking
├── parser.ex          # Recursive descent parser  
├── compiler.ex        # AST to instructions conversion
├── evaluator.ex       # Instruction execution engine with custom function support
├── visitor.ex         # Visitor behavior definition
├── types.ex           # Type specifications
├── functions/         # Function system components
│   └── system_functions.ex   # Built-in functions (len, upper, abs, etc.)
└── visitors/          # AST transformation modules
    ├── string_visitor.ex      # AST to string decompilation  
    └── instructions_visitor.ex # AST to instructions conversion

test/predicator/
├── lexer_test.exs
├── parser_test.exs  
├── compiler_test.exs
├── evaluator_test.exs
├── object_evaluation_test.exs     # Object literal evaluation tests
├── object_edge_cases_test.exs     # Object literal edge cases
├── object_integration_test.exs    # Object literal integration tests
├── predicator_test.exs            # Integration tests
└── visitors/                      # Visitor tests
    ├── string_visitor_test.exs
    └── instructions_visitor_test.exs
```

## Recent Additions (2025)

### Source Positions (v3.7.0)

Every AST node carries a trailing `{line, column}` naming the token that
defines it, the compiler emits a side table from instruction index to position,
and runtime errors carry the position of the instruction that failed.

**Node inventory.** `Parser.ast/0` is the authority; each arm below shows the
trailing position:

```elixir
{:literal, value, pos}
{:string_literal, binary, :double | :single, pos}
{:identifier, name, pos}
{:comparison, op, left, right, pos}
{:arithmetic, op, left, right, pos}
{:membership, op, left, right, pos}
{:logical_and, left, right, pos}
{:logical_or, left, right, pos}
{:logical_not, operand, pos}
{:unary, op, operand, pos}
{:list, elements, pos}
{:object, entries, pos}
{:function_call, name, args, pos}
{:bracket_access, target, key, pos}
{:property_access, target, property, pos}
{:duration, units, pos}
{:relative_date, duration, direction, pos}
{:object_key, value, style, pos}
```

Object keys have their own node - `{:object_key, value, style, pos}`, where
`style` is `:identifier`, `:double`, or `:single`. They do not reuse the
expression tags, so nothing tells a key from an expression by tuple arity, and
the style records how the key was written so it decompiles back the same way.

**Which token a node points at.** Leaves point at their own token. Everything
else points at the token that *names the operation*, so an error names the thing
that failed rather than the start of the subexpression it failed on - `a * true`
reports column 3, not column 1:

| Node | Defining token |
|---|---|
| literals, identifiers, object keys | own token |
| `comparison`, `arithmetic`, `membership`, `logical_and`, `logical_or` | the operator |
| `unary`, `logical_not` | the operator |
| `list`, `object`, `bracket_access` | the opening bracket or brace |
| `function_call` | the name token |
| `property_access` | the `.` |
| `duration` | its first number |
| `relative_date` | the direction keyword (`ago`, `from`, `next`, `last`) |

A new node type follows this rule: point it at the token a reader would blame.

**The side table.** `Compiler.to_instructions_with_positions/2` (and
`Predicator.compile_with_positions/1`) returns `{instructions, table}` where the
table maps a 0-based instruction index to the position of the node that emitted
it. It is an **Elixir-side companion value**: no instruction gains an element,
no opcode is added, and the table is never serialized into the instruction list.
The cross-language interchange format specified by ADR-0001 is therefore
unchanged, as are any compiled artifacts consumers have already stored. The Ruby
and JavaScript siblings need no work, and may adopt an equivalent table
independently.

A node with a `nil` position contributes no table entry, so a position-free AST
compiles to an empty table.

**One AST shape.** Every node carries a trailing slot: a `{line, column}`, a
span under `spans: true`, or `nil` for a node a caller built rather than parsed.
There is no normalization at the visitors' entry points and no position-free
variant of the AST - visitor clauses have exactly one form each and their
contract is "node with a trailing slot in". Object keys are
`{:object_key, value, style, slot}` nodes throughout (px-0y9).

Predicator 3.7 and 3.8 accepted the position-free 3.6 shape at those entry
points via `Parser.strip_positions/1` and `Parser.ensure_positions/1`. Both were
removed in 4.0.0 (px-tbv.8) along with the `bare_ast/0` and `bare_object_key/0`
types; a caller hand-building an AST supplies `nil` in the slot.

**Runtime errors.** `EvaluationError`, `TypeMismatchError`, and
`UndefinedVariableError` gained an optional `:position`. The evaluator carries
the table in `positions:` and decorates at `step/1` - the single point where an
error and the failing instruction pointer are both in scope - so every error
site in the evaluator is covered by one call to `Errors.put_position/2`.
`Predicator.evaluate/3` threads the table automatically for string input; an
instruction-list caller sees `position: nil` unless they pass `positions:`.
Rendered `message` strings are unchanged.

Two errors keep `position: nil` by construction: the empty-stack error, which
belongs to no instruction, and the `UndefinedVariableError` that
`Predicator.evaluate/3` builds *after* the run from the loads the evaluator
recorded. The `UndefinedVariableError` that `px-8um.7` rewrites a
`TypeMismatchError` into does too, deliberately: the position on hand belongs
to the *rejecting operator* - `{1,1}` for the `not` in `"not unbound"`, `{1,9}`
for the `+` in `"unbound + 1"` - not to the variable, so carrying it over would
point a caller's editor at the wrong token.

The third construction site is the one that *does* carry a position: the
`on_unbound: :error` policy (`px-8um.3`) builds its `UndefinedVariableError`
at the `load` instruction itself, so `step/1` hands it the variable's own
`{line, column}`. `"not missing"` under `:error` reports `{1, 5}` - the
`missing` - where the default policy's rewrite of the same expression reports
`nil`. The asymmetry is intentional: the policy has the right token in scope
and the other two do not.

### Source Spans (v3.9.0, unreleased)

A point position tells an editor where to put a caret. A span tells it what to
underline. `Predicator.Parser.parse/2` takes `spans: true`, and under it every
AST node's **existing trailing slot** carries a `t:Predicator.Types.span/0`
instead of a `{line, column}`. No node gained or lost an element, and point
positions remain the default at every entry point.

```elixir
# default, unchanged
{:arithmetic, :multiply, {:identifier, "a", {1, 1}}, {:literal, true, {1, 5}}, {1, 3}}

# spans: true
{:arithmetic, :multiply,
  {:identifier, "a", {{1, 1}, {1, 2}}},
  {:literal, true, {{1, 5}, {1, 9}}},
  {{1, 1}, {1, 9}}}
```

One parse produces one kind throughout; the two are never mixed in a single
tree. Every stage between the parser and the error decoration treats the slot as
opaque, which is what makes the change small - only the parser knows the
difference.

**The end is exclusive.** A span names the position one past its last
character, so on a single line `end_column - start_column` is the length and a
zero-width range is representable. This matches LSP ranges, which is what an
editor consuming this wants. `score` at line 1 column 1 spans `{{1, 1}, {1, 6}}`.

**Which characters a node covers.** Where the defining-token table above says
which token to *blame*, this one says which characters to *underline*. A new
node type needs a row in both.

| Node | Span start | Span end |
|---|---|---|
| `literal` | own token | own token end |
| `string_literal` | own token, opening quote included | own token end, past the closing quote |
| `identifier` | own token | own token end |
| `object_key` | own token, opening quote included if quoted | own token end |
| `comparison`, `membership` | left operand start | right operand end |
| `arithmetic` | left operand start | right operand end |
| `logical_and`, `logical_or` | left operand start | right operand end |
| `unary`, `logical_not` | the operator token | operand end |
| `list` | the `[` token | past the `]` token |
| `object` | the `{` token | past the `}` token |
| `function_call` | the name token | past the `)` token |
| `bracket_access` | target expression start | past the `]` token |
| `property_access` | target expression start | property-name token end |
| `duration` | its first number token | past the last duration unit |
| `relative_date` (`ago`) | duration start | past the `ago` token |
| `relative_date` (`from now`) | duration start | past the `now` token |
| `relative_date` (`next`, `last`) | the direction keyword token | duration end |
| parenthesized expression | the `(` token | past the `)` token |

Two consequences worth stating: a quoted string's and a `#`-fenced date's span
include their delimiters, because the lexer's `length` is the full source
extent; and an empty `[]`, `{}`, or `f()` still spans both delimiters, because
the end comes from the closing token rather than from a child.

**Parentheses widen the span, by design.** `(a + b)` gives the `arithmetic`
node the span of `(a + b)`, not just `a + b`. Parentheses build no node of
their own - `parse_primary_token/2`'s `:lparen` clause returns the inner
expression, rewriting its trailing slot to run from the `(` token's start to
past the `)` token before handing it back - so the widened span still belongs
to the inner expression's node; nothing new is attributed to it, only more of
the source the parentheses already delimit.

Because a parent inherits its child's start, this composes upward for free:
`(a + b) * c` gives the `multiply` node a span slicing to the whole source
string, since the left operand's span already runs from `(` to past `)`.
Nesting composes to the outermost pair - `((a))` widens twice, once per
`:lparen` clause, and each rewrite replaces the slot rather than merging, so
the result is the outermost extent and the intermediate one is not retained.
A parenthesized leaf widens the same way: `(a)` gives the `identifier` node
the span of `(a)`. The one thing lost is the inner extent itself - `a + b` and
`(a + b)` become indistinguishable by span - which a consumer that wants it
back can recover by trimming the balanced parens off the ends of the slice it
already has.

**The side table.** `Predicator.compile_with_spans/1` is the span-mode sibling
of `compile_with_positions/1`, returning a `t:Predicator.Types.span_table/0`.
The instruction list it returns is byte-identical to `compile/1`'s. Like the
position table, the span table is an **Elixir-side companion value**: no opcode
is added, no instruction gains an element, and nothing is serialized, so
ADR-0001's interchange guarantee and any stored compiled artifacts are
untouched.

**Runtime errors.** `EvaluationError`, `TypeMismatchError`, and
`UndefinedVariableError` gained an optional `:span` alongside `:position`.
Handed a span, `Errors.put_position/2` sets `:span` to the span *and*
`:position` to the span's start, so a caret-only consumer keeps working under
`spans: true` instead of seeing `position: nil`. The two fields answer different
questions and both are available: for `a * true`, `position: {1, 3}` blames the
`*` under the default, and `span: {{1,1},{1,9}}` with `position: {1, 1}`
underlines the whole expression under `spans: true`. Rendered `message` strings
are unchanged either way.

`Predicator.evaluate/3` takes `spans: true` for string input. For
instruction-list input it is a no-op - there is no source to span - and such a
caller passes `positions:` from `compile_with_spans/1` instead.

### `Predicator.Context` Struct (v3.8.0, unreleased)

- **Persistent bound context**: `Predicator.Context.new/2` merges the four
  builtin function maps plus `opts[:functions]` once, at construction, instead
  of on every `evaluate/3` call
- **`bind/3`**: an O(1) `Map.put/3` on `data`; `functions` and `on_unbound`
  carry over unchanged
- **`assign/3`**: writes through the existing `ContextLocation.put/3`
  auto-vivifying algorithm, accepting either a location expression string or
  an already-resolved path
- **`Predicator.evaluate/3` dispatch**: accepts a `%Context{}` (evaluates
  against its `data`/`functions` directly, no per-call merge) or a bare map
  (unchanged behavior - a one-shot `Context.new/2` internally)
- Foundation bead for the `px-8um` epic; `on_unbound` is stored and validated
  here and acted on by the evaluator (`px-8um.3`, below)
- **Context key normalization (`px-8um.2`)**: `new/2` and `bind/3` are the one
  edge where atom keys and `nil` values are accepted. Both convert deeply and
  eagerly - through nested maps and lists - before evaluation ever sees the
  data: atom keys become string keys (string key wins on collision), and
  `nil` becomes `:undefined`. A `Date`/`DateTime` (or any other struct) passes
  through unchanged; only plain maps have their keys touched. The evaluator's
  `load_from_context/2` and `access_value/2` consult string keys only - the
  `String.to_existing_atom/1` read-time fallbacks they used to carry are gone,
  since a context that reached them through `Context.new/2`/`bind/3` never has
  atom keys left to fall back to.
- Examples:

  ```elixir
  context = Predicator.Context.new(%{"score" => 85})
  Predicator.evaluate("score > 80", context)  # {:ok, true}, functions merged once
  context = Predicator.Context.bind(context, "score", 90)
  Predicator.evaluate("score > 80", context)  # {:ok, true}, no re-merge
  ```

### `Predicator.Undefined` and `Context.bound?/2` (v3.8.0, unreleased)

- **`Predicator.Undefined`**: the one public module that owns the
  `:undefined` sentinel - `value/0` (returns `:undefined`), `undefined?/1`,
  and `to_nil/1`/`from_nil/1` normalizers for a JSON-shaped boundary. The
  atom stays the runtime representation (pervasive in tests and the
  Ruby/JavaScript siblings, part of the instruction interchange format);
  this module names it and checks for it in one place instead of every call
  site writing the literal atom. `Predicator.Types.undefined?/1` delegates
  to it.
- **`Predicator.Context.bound?/2`**: answers whether a root name is present
  in a context's `data`. For `Context`-routed data this is always a string
  key, since `new/2`/`bind/3` normalize atom keys away at construction
  (`px-8um.2`); it still recognizes an atom key too, for the low-level
  `Evaluator` API that bypasses `Context.new/2` entirely, via
  `Evaluator.resolve_key/2`'s own resolution.
- **Fixes the `[["load", _]]` heuristic**: `Predicator.evaluate_instructions/3`
  used to distinguish "unbound variable" from "bound to `:undefined`" by
  matching the compiled program against a single-instruction shape - correct
  only for a bare `variable_name` expression, and silently wrong for
  anything longer (`"missing > 5"` compiles to three instructions and fell
  through to an unconditional `{:ok, :undefined}`). The fixed check named the
  first unbound root the run reported; see `px-8um.8` below for how it
  identifies that root today.
- Depends on `px-8um.1` (`Predicator.Context`); the `on_unbound` policy
  itself (`px-8um.3`, below) is a separate bead that builds on this one. Context key
  normalization (`px-8um.2`) also builds on this one and has landed - see
  above.
- Example:

  ```elixir
  Predicator.evaluate("missing > 5", %{})
  # {:error, %Predicator.Errors.UndefinedVariableError{variable: "missing"}}

  Predicator.evaluate("user.name.middle = \"X\"", %{"user" => %{"name" => %{}}})
  # {:ok, :undefined} - "user" is bound, only the nested path is missing
  ```

- **Runtime unbound tracking (`px-8um.8`, v3.8.0)**: the evaluator records
  each `["load", name]` it executes whose `name` `Evaluator.resolve_key/2`
  finds absent, and `Predicator.evaluate_instructions/3` reads that list off
  the final evaluator state. The full-list scan `px-8um.4` shipped was exact
  only while ISA v1 had no branches; once `jump_if_falsy_or_pop` /
  `jump_if_true_or_pop` landed (`px-e3g.1`), a load could be present in the
  program and never executed, and the scan named skipped variables -
  `(false AND missing) OR unbound_b` reported `missing`. `Context.bound?/2`
  delegates to `resolve_key/2` too, so the two cannot drift.

- **Unbound roots behind a rejected `:undefined` operand (`px-8um.7`,
  v3.8.0)**: `undefined_result/1` only fires when the whole program evaluates
  to `:undefined`. An opcode that *rejects* an `:undefined` operand - `not`,
  `unary_minus`, `unary_bang`, the five arithmetic opcodes, the legacy
  `["and"]`/`["or"]` - errors first, and its `TypeMismatchError` names no
  variable. `Predicator.evaluate/3` now rewrites that error into
  `UndefinedVariableError` when the error's `got` mentions `:undefined` **and**
  the run recorded an unbound load, which is why `Evaluator.run_prepared/1`
  returns its final state on the error path too. `in`/`contains` are not in the
  class: they propagate `:undefined` rather than rejecting it, so they already
  reported the root. Bound-to-`:undefined` data (`%{"b" => :undefined}`) and
  missing nested paths (`user.nope`) keep their `TypeMismatchError` -
  `unbound_loads` records absent keys only. The low-level
  `Evaluator.evaluate/3` is unchanged; this is an API-layer rewrite.

### The `on_unbound` policy (`px-8um.3`, v3.8.0, unreleased)

`Predicator.Context`'s `on_unbound` field selects what a load of an unbound
root does. `:undefined`, the default, pushes the `:undefined` sentinel and
lets three-valued logic absorb it - today's behavior, unchanged. `:error`
makes the load return
`{:error, %Predicator.Errors.UndefinedVariableError{}}` and halts the run:
nothing is pushed, and no later instruction executes.

- **It fires at the `load` instruction**, through `unbound_load?/3` - the same
  `Evaluator.resolve_key/2` presence test that `unbound_loads` and
  `Context.bound?/2` use, so the policy, the recorder, and the public
  predicate cannot drift. Presence, not definedness: `%{"x" => :undefined}`
  and `%{"x" => nil}` are both bound and neither trips the policy.
- **Roots only.** Only `["load", name]` reads a root; `["access", prop]` and
  `["bracket_access"]` operate on a value already on the stack. So
  `user.nope` on a bound `user`, `items[99]`, and a missing nested path all
  stay `:undefined` under either policy, with no guard written for them. This
  mirrors ECMAScript - a `ReferenceError` for an undeclared variable, a silent
  `undefined` for a missing property - and keeps guards over sparse data
  usable. An unbound root *under* an access (`nope.field`) still errors, at
  the load of `nope`.
- **Short-circuiting wins.** A load a branch skipped is never executed, so the
  policy never sees it: `false AND missing` is `{:ok, false}` and
  `true OR missing` is `{:ok, true}` under `:error`. That is what the W3C
  SCXML tests expect, and it holds for free - the branch opcodes are
  untouched.
- **What actually changes** is narrower than it looks, because since
  `px-8um.4`/`px-8um.7`/`px-8um.8` an unbound root already errors under the
  default whenever its `:undefined` reaches the result or is rejected by an
  operator. The policy's own cases are the ones where a defined result
  *absorbs* the sentinel:

  | Expression, empty context | Default | Under `:error` |
  |---|---|---|
  | `missing OR true` | `{:ok, true}` | `{:error, ...}` |
  | `[missing]` | `{:ok, [:undefined]}` | `{:error, ...}` |
  | `{'a': missing}` | `{:ok, %{"a" => :undefined}}` | `{:error, ...}` |
  | `missing`, `missing == 5`, `not missing`, `missing + 1` | `{:error, ...}` | same, now with a position |
  | `false AND missing`, `true OR missing` | `{:ok, false}` / `{:ok, true}` | unchanged - never loaded |

- **Plumbing**: `%Evaluator{}` gained an `on_unbound` field;
  `Predicator.evaluate/3` propagates it from a `%Context{}`, and from a bare
  map plus `on_unbound: :error` in `opts` via `Context.new/2`.
  `Evaluator.evaluate/3` accepts it as an option too, but does *not* validate
  it - validation stays at the `Context.new/2` edge, and any other value
  behaves as the default.
- **Why it exists**: statifier sets `:error` and maps the returned struct onto
  SCXML's `error.execution` event (W3C semantics for illegal expressions).
  `variable` and `position` are structured fields, so no message string needs
  parsing.
- **ISA-neutral.** No instruction is added or re-encoded, so the Ruby and
  JavaScript siblings need nothing to stay in sync (ADR-0001).

### Durations and Relative Dates (v3.4.0)

- Natural-language durations and relative time expressions
- Relative dates: `3d ago`, `2w from now`, `next 1mo`, `last 1y`
- Date/DateTime arithmetic: `#2024-01-10# + 5d`, `#2024-01-15T10:30:00Z# - 2h`
- Grammar updates: `duration` and `relative_date` productions
- Full pipeline support (lexer, parser, compiler, evaluator, string visitor) with tests
- Examples:

  ```elixir
  Predicator.evaluate("created_at > 3d ago", %{"created_at" => ~U[2024-01-20 00:00:00Z]})
  Predicator.evaluate("due_at < 2w from now", %{"due_at" => Date.add(Date.utc_today(), 10)})
  Predicator.evaluate("#2024-01-10# + 5d = #2024-01-15#", %{})
  Predicator.evaluate("#2024-01-15T10:30:00Z# - 2h < #2024-01-15T10:30:00Z#", %{})
  ```

### Object Literals (v3.1.0 - JavaScript-Style Objects)

- **Syntax Support**: Complete JavaScript-style object literal syntax (`{}`, `{name: "John"}`, `{user: {role: "admin"}}`)
- **Lexer Extensions**: Added `:lbrace`, `:rbrace`, `:colon` tokens for object parsing
- **Parser Grammar**: Comprehensive object parsing with proper precedence and error handling
- **AST Nodes**: New `{:object, entries}` AST node type for object representation
- **Stack-based Compilation**: Uses `object_new` and `object_set` instructions for efficient evaluation
- **Evaluator Support**: Object construction and equality comparison with type-safe guards
- **String Decompilation**: Round-trip formatting preserves original object syntax
- **Key Types**: Both identifier keys (`name`) and string keys (`"name"`) supported
- **Nested Objects**: Unlimited nesting depth with proper evaluation order
- **Type Safety**: Enhanced type matching guards to support maps while preserving Date/DateTime separation
- **Comprehensive Testing**: 47 new tests covering evaluation, edge cases, and integration scenarios
- **Examples**:

  ```elixir
  Predicator.evaluate("{name: 'John', age: 30}", %{})  # Object construction
  Predicator.evaluate("{score: 85} = user_data", %{"user_data" => %{"score" => 85}})  # Comparison
  Predicator.evaluate("{user: {role: 'admin'}}", %{})  # Nested objects
  ```

### Type Coercion and Float Support (v2.3.0)

- **Float Literals**: Lexer supports floating-point numbers (e.g., `3.14`, `0.5`)
- **Numeric Types**: Both integers and floats supported in arithmetic operations
- **String Concatenation**: `+` operator performs string concatenation when at least one operand is a string
- **Type Coercion Rules**:
  - Number + Number → Numeric addition
  - String + String → String concatenation  
  - String + Number → String concatenation (number converted to string)
  - Number + String → String concatenation (number converted to string)
- **Examples**:

  ```elixir
  Predicator.evaluate("3.14 * 2", %{})           # {:ok, 6.28}
  Predicator.evaluate("'Hello' + ' World'", %{}) # {:ok, "Hello World"}
  Predicator.evaluate("'Count: ' + 42", %{})     # {:ok, "Count: 42"}
  Predicator.evaluate("100 + ' items'", %{})     # {:ok, "100 items"}
  ```

### Function System (v2.0.0 - Architecture Overhaul)

- **Built-in Functions**: System functions automatically available in all evaluations
  - **String functions**: `len(string)`, `upper(string)`, `lower(string)`, `trim(string)`,
    `starts_with(string, prefix)`, `ends_with(string, suffix)`, `substring(string, start[, len])`,
    `index_of(string, sub)`
  - **Numeric functions**: `abs(number)`, `max(a, b)`, `min(a, b)`
  - **Date functions**: `year(date)`, `month(date)`, `day(date)`
  - **List functions**: `concat(list1, list2)`
- **Custom Functions**: Provided per evaluation via `functions:` option in `evaluate/3`
- **Function Format**: `%{name => {arity, function}}` where `arity` is an integer, or a list of
  integers for a function with optional arguments (e.g. `substring/2` or `/3`); function takes
  `[args], context` and returns `{:ok, result}` or `{:error, message}`
- **Function Merging**: Custom functions merged with system functions, allowing overrides
- **Thread Safety**: No global state - functions scoped to individual evaluation calls
- **Examples**:

  ```elixir
  custom_functions = %{
    "double" => {1, fn [n], _context -> {:ok, n * 2} end},
    "len" => {1, fn [_], _context -> {:ok, "custom_override"} end}  # Override built-in
  }
  
  Predicator.evaluate("double(score) > 100", %{"score" => 60}, functions: custom_functions)
  Predicator.evaluate("len('anything')", %{}, functions: custom_functions)  # Uses override
  Predicator.evaluate("len('hello')", %{})  # Uses built-in (returns 5)
  ```

### Arithmetic and Unary Operations (v2.1.0 - Complete Implementation)

- **Full Arithmetic Support**: Complete parsing and evaluation pipeline for arithmetic expressions
  - **Binary operations**: `+` (addition), `-` (subtraction), `*` (multiplication), `/` (division), `%` (modulo)
  - **Unary operations**: `-` (unary minus), `!` (unary bang/logical NOT)
- **Proper Precedence**: Mathematical precedence handling (unary → multiplication → addition → equality → comparison)
- **Instruction Execution**: Stack-based evaluator with 7 new instruction handlers
- **Error Handling**: Division by zero protection, type checking, comprehensive error messages
- **Pattern Matching**: Idiomatic Elixir implementation using pattern matching for clean code
- **Examples**:

  ```elixir
  Predicator.evaluate("2 + 3 * 4", %{})        # {:ok, 14} - correct precedence
  Predicator.evaluate("(10 - 5) / 2", %{})     # {:ok, 2} - parentheses and division
  Predicator.evaluate("-score > -100", %{"score" => 85})  # {:ok, true} - unary minus
  Predicator.evaluate("total % 2 = 0", %{"total" => 14})  # {:ok, true} - modulo
  ```

### Date and DateTime Support

- **Syntax**: `#2024-01-15#` (date), `#2024-01-15T10:30:00Z#` (datetime)
- **Lexer**: Added date tokenization with ISO 8601 parsing
- **Parser**: Extended AST to support date literals
- **Evaluator**: Date/datetime comparisons and membership operations
- **StringVisitor**: Round-trip formatting `#date#` syntax

### Temporal Comparison Semantics

- **Same type**: `Date`/`Date` and `DateTime`/`DateTime` compare
  chronologically via `Date.compare/2` and `DateTime.compare/2`, never by
  Erlang's struct-key ordering.
- **Mixed pair**: a `Date` compared against a `DateTime` is coerced to
  `00:00:00` UTC of that day, then compared as two `DateTime`s. This applies
  to ordering, `==`/`!=`, and `in`/`contains` membership. It matters in
  practice because every relative date (`3d ago`, `2w from now`, `next 1mo`,
  `last 1y`) evaluates to a `DateTime`, so without the coercion a `Date`
  context value cannot be compared against one.
- **Why coerce**: `apply_subtraction/2` already performs exactly this
  coercion for the same pair, so refusing to order it was an inconsistency
  inside one module; and the mismatch was silent - `:undefined` rather than a
  type error - which gave rule authors no signal that anything was wrong.
- **Strict equality is exempt**: `===` and `!==` are resolved before any type
  dispatch, so a `Date` is never strictly equal to a `DateTime` regardless of
  the instant either denotes.
- **The anchor is fixed at UTC midnight**, matching subtraction. Making it
  configurable would be a new feature, not part of this semantics.

### List Literals and Membership

- **Syntax**: `[1, 2, 3]`, `["admin", "manager"]`
- **Operators**: `in` (element in list), `contains` (list contains element)
- **Examples**: `role in ["admin", "manager"]`, `[1, 2, 3] contains 2`
- **Compilation**: all-literal lists compile to a single `["lit", [...]]`;
  a list with any non-literal element compiles its elements in order followed
  by `["make_list", n]`, which pops n values and pushes the list (ADR-0001)
- **Examples**: `[1, 2, 3]` -> `[["lit", [1, 2, 3]]]`;
  `[x + 1, y]` -> `[["load","x"],["lit",1],["add"],["load","y"],["make_list",2]]`
- **Cross-language**: `make_list` is an ISA v2 addition. The Ruby and
  JavaScript siblings do not implement it yet, so an instruction list
  containing it will not run there. All-literal lists remain portable.
- **Concatenation**: `+` concatenates two lists (`[1, 2] + [3]` ->
  `[1, 2, 3]`); `concat(a, b)` does the same as an explicit function call.
  Both are list-only - `+` still coerces string/number as before, and
  `concat` does not accept strings or numbers.

### Object Literals (v3.1.0 - JavaScript-Style Objects)

- **Syntax**: `{}`, `{name: "John"}`, `{user: {role: "admin", active: true}}`
- **Key Types**: Identifiers (`name`) and strings (`"name"`) supported as keys
- **Nested Objects**: Unlimited nesting depth with proper evaluation order
- **Stack-based Compilation**: Uses `object_new` and `object_set` instructions for efficient evaluation
- **Type Safety**: Object equality comparisons with proper map type guards
- **String Decompilation**: Round-trip formatting preserves original syntax
- **Examples**:

  ```elixir
  Predicator.evaluate("{name: 'John'} = user_data", %{})  # Object comparison
  Predicator.evaluate("{score: 85, active: true}", %{})   # Object construction
  Predicator.evaluate("user = {profile: {name: 'Alice'}}", %{})  # Nested objects
  ```

### Logical Operator Enhancements

- **Case-insensitive**: Both `AND`/`and`, `OR`/`or`, `NOT`/`not` supported
- **Pattern matching**: Refactored evaluator and parser to use pattern matching over case statements
- **Plain boolean expressions**: Support for `active`, `expired` without `= true`

### Short-Circuit Evaluation (v3.7.0)

- **Compilation**: `a AND b` compiles to `a`'s instructions, then
  `["jump_if_falsy_or_pop", offset]`, then `b`'s instructions; `a OR b`
  mirrors it with `["jump_if_true_or_pop", offset]`. `offset` is the distance
  from the jump instruction to the instruction after `b`.
- **`:undefined` is ECMAScript-aligned, not symmetric**: "falsy" is `false` or
  `:undefined`; "true" is exactly `true`. `undefined AND x` short-circuits to
  `:undefined` without evaluating `x`; `undefined OR x` falls through and takes
  `x`'s value. A non-boolean, non-`:undefined` value at a jump is still a
  `TypeMismatchError` - the opcodes validate, they don't coerce.
- **Examples**: `a AND b` ->
  `[["load","a"],["jump_if_falsy_or_pop",2],["load","b"]]`;
  `evaluate("false AND score > 5", %{})` -> `{:ok, false}` without evaluating
  `score > 5` at all, where 3.5.0 raised `TypeMismatchError` on an unbound
  `score`
- **Backward compatible**: `["and"]` and `["or"]` remain accepted by the
  evaluator for previously compiled artifacts; the compiler simply stops
  emitting them (ADR-0001)
- **Cross-language**: `jump_if_falsy_or_pop` and `jump_if_true_or_pop` are ISA
  v2 additions. The Ruby and JavaScript siblings do not implement them yet, so
  an instruction list containing either will not run there.

### Nested Data Structure Access (v1.1.0 + Bracket Access Enhancement)

- **Dot Notation**: Access deeply nested data structures using `.` syntax
- **Bracket Notation**: Dynamic property and array access using `[key]` syntax (NEW)
- **Mixed Access**: Combine both notations like `user.settings['theme']` (NEW)
- **Syntax**:
  - Dot: `user.profile.name`, `config.database.settings.ssl`
  - Bracket: `user['profile']['name']`, `items[0]`, `scores[index]`
  - Mixed: `user.settings['theme']`, `data['users'][0].name`
- **Key Types**: Supports string keys, atom keys, integer keys, and mixed types
- **Array Indexing**: Full array access with bounds checking (`items[0]`, `scores[index]`)
- **Dynamic Keys**: Variable and expression-based keys (`obj[key]`, `items[i + 1]`)
- **Parser**: Added postfix parsing for bracket access with recursive chaining
- **Evaluator**:
  - Enhanced `load_nested_value/2` for dot notation
  - New `access_value/2` for bracket access with comprehensive type handling
- **Error Handling**: Returns `:undefined` for missing paths, out-of-bounds access, or non-map/non-array intermediate values
- **Examples**:
  - `user.name.first = "John"` (dot notation)
  - `user['profile']['role'] = "admin"` (bracket notation)
  - `items[0] = "apple"` (array access)
  - `data['users'][index]['name']` (chained bracket access)
  - `user.settings['theme'] = 'dark'` (mixed notation)
- **Backwards Compatible**: Simple variable names and existing dot notation work exactly as before

### Location Expressions for SCXML (v2.2.0 - Phase 2 Complete)

- **Purpose**: SCXML datamodel location expressions for assignment operations (`<assign>` elements)
- **API Functions**:
  - `Predicator.context_location/3` - resolves location paths for assignment targets
  - `Predicator.context_assign/4` - resolves a location expression and writes at it (Unreleased)
  - `Predicator.ContextLocation.put/3` - writes at an already-resolved path (Unreleased)
- **Location Paths**: Returns lists like `["user", "name"]`, `["items", 0, "property"]` for navigation
- **Validation**: Distinguishes assignable locations (l-values) from computed expressions (r-values)
- **Error Handling**: Structured `LocationError` with detailed error types and context
- **Core Module**: `Predicator.ContextLocation` with comprehensive location resolution logic
- **Error Types**:
  - `:not_assignable` - Expression cannot be used as assignment target (literals, functions, etc.)
  - `:invalid_node` - Unknown or unsupported AST node type
  - `:undefined_variable` - Variable referenced in bracket key is not defined
  - `:invalid_key` - Bracket key is not a valid string or integer
  - `:computed_key` - Computed expressions cannot be used as assignment keys
  - `:not_a_container` - Write path traverses a value that is neither a map nor a list
  - `:invalid_index` - List index in a write path is negative
- **Examples**:

  ```elixir
  Predicator.context_location("user.profile.name", %{})          # {:ok, ["user", "profile", "name"]}
  Predicator.context_location("items[0]", %{})                   # {:ok, ["items", 0]}
  Predicator.context_location("data['users'][i]['name']", %{"i" => 2})  # {:ok, ["data", "users", 2, "name"]}
  Predicator.context_location("len(name)", %{})                  # {:error, %LocationError{type: :not_assignable}}
  Predicator.context_location("42", %{})                         # {:error, %LocationError{type: :not_assignable}}
  ```

- **Assignable Locations**: Simple identifiers, property access, bracket access, mixed notation
- **Non-Assignable**: Literals, function calls, arithmetic expressions, comparisons, any computed values
- **Mixed Notation Support**: `user.settings['theme']`, `data['users'][0].profile` fully supported
- **SCXML Integration**: Enables safe assignment operations while preventing assignment to computed expressions
- **Assignment Semantics** (Unreleased): auto-vivification is ECMAScript-like - a missing,
  `nil`, or `:undefined` segment becomes a `%{}` when the next segment is a string and a
  `[]` when it is an integer; integer indices past the end of a list pad with `:undefined`;
  the leaf is always overwritten; existing data is never destroyed, so a scalar intermediate
  or a string segment against a list is `:not_a_container`. Only string and integer keys are
  consulted, never atom keys - `put/3` is the contract-stable primitive that later
  releases write through, so its signature and these semantics are frozen

  ```elixir
  Predicator.context_assign(%{}, "user.profile.name", "Ada")     # {:ok, %{"user" => %{"profile" => %{"name" => "Ada"}}}}
  Predicator.context_assign(%{"items" => [1]}, "items[2]", "x")  # {:ok, %{"items" => [1, :undefined, "x"]}}
  Predicator.context_assign(%{"user" => 5}, "user.name", "Ada")  # {:error, %LocationError{type: :not_a_container}}
  ```

## Breaking Changes

### v2.2.0 - Property Access Parsing Overhaul

- **Changed**: Complete reimplementation of dot notation parsing from dotted identifiers to proper property access AST
- **Breaking**: Expressions like `user.email` now parsed as `{:property_access, {:identifier, "user"}, "email"}` instead of `{:identifier, "user.email"}`
- **Impact**: Context keys with dots like `"user.email"` will no longer match the identifier `user.email` - they are now parsed as property access
- **Instructions**: Evaluation now generates separate `load` and `access` instructions instead of single `load` with dotted name
- **Benefit**: Enables proper mixed notation like `user.settings['theme']` and SCXML location expressions
- **Migration**: Use proper nested data structures `%{"user" => %{"email" => "..."}}` instead of flat keys `%{"user.email" => "..."}`
- **Lexer Change**: Dots removed from valid identifier characters, now parsed as separate tokens
- **Parser Enhancement**: Added property access grammar `postfix → primary ( "[" expression "]" | "." IDENTIFIER )*`
- **New AST Nodes**: `{:property_access, left_node, property}` for dot notation parsing
- **Evaluator Update**: New `access` instruction handler, removed old dotted identifier support from `load_from_context`
- **Full Compatibility**: All existing expressions without dots work exactly as before

### v2.0.0 - Custom Function Architecture Overhaul

- **Removed**: Global function registry system (`Predicator.Functions.Registry` module)
- **Removed**: `Predicator.register_function/3`, `Predicator.clear_custom_functions/0`, `Predicator.list_custom_functions/0`
- **Changed**: Custom functions now passed via `functions:` option in `evaluate/3` calls instead of global registration
- **Benefit**: Thread-safe, no global state, per-evaluation function scoping
- **Migration**: Replace registry calls with function maps passed to `evaluate/3`

### v1.1.0 - Nested Access Parsing

- **Changed**: Variables containing dots (e.g., `"user.email"`) now parsed as nested access paths
- **Impact**: Context keys like `"user.profile.name"` will no longer match identifier `user.profile.name`
- **Solution**: Use proper nested data structures instead of flat keys with dots

## Common Tasks

### Adding New Operators

1. Add token type to `lexer.ex`
2. Add parsing logic to `parser.ex`  
3. Add instruction type to `types.ex`
4. Add evaluation logic to `evaluator.ex`
5. Add compilation logic to `compiler.ex`
6. Add string formatting to `string_visitor.ex`
7. Point the new node at its operator token (see Source Positions) - the
   trailing slot is part of the node shape, not an add-on
8. Give the new node a span rule too (see Source Spans): which characters it
   covers, not just which token it blames
9. Add comprehensive tests

### Adding New Data Types

1. Update lexer tokenization (see date implementation)
2. Update parser grammar and AST types, giving the node a source position and a
   span rule
3. Update type specifications in `types.ex`
4. Add evaluation support with type checking
5. Add string visitor formatting support
6. Add tests for all pipeline components

### Debugging Issues

- Use `mix test --trace` for detailed test output
- Check coverage with `mix test.coverage.html`
- Use `mix dialyzer` for type issues
- Run `mix credo explain <issue>` for linting details

## Testing Philosophy

- **Unit Tests**: Each component tested in isolation
- **Integration Tests**: Full pipeline testing in `predicator_test.exs`  
- **Property Testing**: Comprehensive input validation
- **Error Path Testing**: All error conditions covered
- **Round-trip Testing**: AST → String → AST consistency
- **Current Test Count**: 886 tests (65 doctests + 821 regular tests)

## Code Standards

- **Documentation**: All public functions have `@doc` and `@spec`
- **Type Safety**: Comprehensive `@type` and `@spec` definitions
- **Error Handling**: Consistent `{:ok, result} | {:error, ...}` patterns
- **Testing**: >90% coverage requirement
- **Formatting**: Automatic with `mix format`
- **Linting**: Credo strict mode compliance

## Performance Considerations

- Lexer/parser complexity is intentional and appropriate
- String concatenation optimized in StringVisitor
- Instruction execution designed for repeated evaluation
- Memory usage minimized during compilation pipeline

## Troubleshooting

### Common Issues

- **Credo Complexity**: Intentionally suppressed for lexer/parser functions
- **Doctest Escaping**: Use simple examples without nested quotes  
- **Coverage Gaps**: Focus on error paths and edge cases
- **Type Errors**: Check `@spec` definitions match implementation

### Development Environment

- Elixir ~> 1.18 required
- All dependencies in development/test only
- No runtime dependencies for core functionality

- When creating git commit messages:
  - be concise but informative, and highlight the functional changes
  - no need to mention code quality improvements as they are expected (unless the functional change is about code quality improvements)
  - commit titles should be less than 50 characters and be in the simple present tense (active voice)
  - commit descriptions should wrap at about 72 characters and also be in the simple present tense (active voice)
