# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Source spans.** A point position tells an editor where to put a caret; a
  span tells it what to underline. `Predicator.Parser.parse/2`,
  `Predicator.parse/2`, and `Predicator.evaluate/3` (string input only) take
  `spans: true`, under which every AST node's existing trailing slot carries a
  `t:Predicator.Types.span/0` - `{{start_line, start_col}, {end_line, end_col}}`
  with an **exclusive** end, matching LSP ranges - instead of a
  `{line, column}`. For `a * true` the `arithmetic` node spans the whole
  expression rather than naming column 3.

- `t:Predicator.Types.span/0` and `t:Predicator.Types.span_table/0`.

- `Predicator.compile_with_spans/1`, the span-mode sibling of
  `compile_with_positions/1`. Its instruction list is byte-identical to
  `compile/1`'s; the side table maps each instruction index to a span. Pass it
  to `evaluate/3` as `positions:` to get spans on errors from a pre-compiled
  program.

- `:span` on `Predicator.Errors.EvaluationError`,
  `Predicator.Errors.TypeMismatchError`, and
  `Predicator.Errors.UndefinedVariableError`, defaulting to `nil`.

- `Predicator.Errors.put_position/2` accepts a span: it sets `:span` to the span
  and `:position` to the span's start, so a caller reading only `:position`
  still gets a usable caret under `spans: true`.

### Unchanged

Stated explicitly, because this release adds a second location representation
and nothing about the first one moves:

- Point positions remain the default at every entry point. `Predicator.parse/1`,
  `Predicator.compile/1`, `Predicator.compile_with_positions/1`, and
  `Predicator.evaluate/3` without the option behave exactly as in 3.8.0.
- `t:Predicator.Types.position/0` is untouched and still means a point.
- No AST node gained or lost an element; spans reuse the trailing slot.
- Every rendered error `message` string is identical with and without spans.
- The instruction list produced by `compile/1` is byte-identical, so stored
  compiled artifacts and cross-language interchange with the Ruby and
  JavaScript siblings are unaffected (ADR-0001).
- A parenthesized expression's span excludes its parentheses, which build no
  AST node.

## [3.8.0] - 2026-08-05

### Changed

- The Hex package tarball no longer bundles the markdown doc sources under
  `docs/`. Every guide, the language and architecture references, and the
  ADRs are still published in full at
  [hexdocs.pm/predicator](https://hexdocs.pm/predicator) and still live in
  the GitHub repository; only the copy that `mix deps.get` unpacked into
  `deps/predicator/docs/` is gone. Read them online or from a repo checkout
  instead.

- `Predicator.Evaluator.run_prepared/1` returns `{:error, error, evaluator}`
  instead of `{:error, error}`, so the final evaluator state - and with it
  `unbound_loads/1` - is available on the error path as well as the success
  path. `run/1`, `evaluate/3`, `evaluate!/3`, `evaluate_prepared/1`, and
  `Predicator.run_evaluator/1` are unchanged.

- **Context keys and `nil` values are now normalized eagerly and deeply.**
  `Predicator.Context.new/2` and `bind/3` convert atom keys to string keys
  (string key wins on collision) and `nil` values to `:undefined`, recursing
  through nested maps and lists, before evaluation ever sees the data. This
  is the one edge where atom keys and `nil` are accepted; the two
  `String.to_existing_atom/1` read-time fallbacks that used to paper over
  their absence - in `Predicator.Evaluator.load_from_context/2` (variable
  load) and `access_value/2` (property/bracket access) - are deleted, since a
  context reaching them through `Context.new/2`/`bind/3` never has atom keys
  left to fall back to. Ordinary `Predicator.evaluate/3`/`evaluate!/3`
  callers passing a bare map are unaffected - atom-keyed and `nil`-bearing
  contexts keep working exactly as before, now via the edge instead of the
  read-time fallback. The low-level `Predicator.Evaluator.evaluate/3`/
  `evaluate!/3` and `Predicator.evaluator/2` APIs, which construct an
  evaluator directly and bypass `Context.new/2`, no longer accept atom keys:
  this is better-defined behavior for that narrow surface, not a removal - a
  caller who wants atom-key or `nil` normalization goes through
  `Predicator.Context` or `Predicator.evaluate/3` instead.

  One narrowing follows from "deep and total": a duration value
  (`t:Predicator.Types.duration/0`) is a plain atom-keyed map, not a struct,
  so a pre-built `Predicator.Duration.new/1` result *bound into a context*
  now has its keys stringified like any other map and is no longer recognized
  as a duration by date arithmetic. Durations built the documented way - by a
  `duration(...)` or `3d8h` literal in the expression, during evaluation -
  never pass through this normalization and are unaffected.

- **Object keys are now `{:object_key, value, style, pos}`** rather than
  `{:identifier, name, pos}` / `{:string_literal, value, pos}`, where `style`
  is `:identifier`, `:double`, or `:single` and records how the key was
  written. Keys no longer reuse the expression node tags, so nothing tells a
  key from an expression by tuple arity. Callers pattern-matching a parsed
  object entry's key update their patterns to the new tag;
  `Predicator.Parser.strip_positions/1` still returns the 3.6 shape and
  `Predicator.Parser.ensure_positions/1` still accepts every earlier key
  shape, so a hand-built AST passed to `Predicator.decompile/2` or
  `Predicator.Compiler.to_instructions/2` is unaffected, and the instruction
  list is byte-identical.
- `Predicator.decompile/2` now renders a single-quoted object key with single
  quotes instead of rewriting it to double quotes, and escapes a quote
  character inside a key. A key containing the quote character previously
  decompiled to syntactically invalid source.

### Added

- `on_unbound: :error` on `Predicator.Context.new/2` (and as an option to
  `Predicator.evaluate/3` and `Predicator.Evaluator.evaluate/3`): a load of an
  unbound root variable returns
  `{:error, %Predicator.Errors.UndefinedVariableError{}}` instead of the
  `:undefined` sentinel. Roots only - a missing key on a bound map stays
  `:undefined` under either policy - and a load a short-circuit skipped never
  fires it. The default, `:undefined`, is unchanged behavior.

- `Predicator.Errors.ParseError` gains a `:position` field - `{line, column}`,
  derived from the existing `:line` and `:column` fields, which stay
  populated unchanged. Generic error-reporting code can now read `:position`
  uniformly across `ParseError`, `EvaluationError`, `TypeMismatchError`, and
  `UndefinedVariableError` instead of special-casing `ParseError`. Additive
  and non-breaking - no existing caller matching on `:line`/`:column` needs
  to change.

### Fixed

- **An unbound variable is no longer hidden behind a nameless type mismatch.**
  `Predicator.evaluate/3` reported `TypeMismatchError "Logical NOT requires a
  boolean, got :undefined"` for `not unbound`, naming no variable, while
  `unbound > 5` correctly returned `UndefinedVariableError`. Every opcode that
  rejects an `:undefined` operand - `not`, `unary_minus`, `unary_bang`, `add`,
  `subtract`, `multiply`, `divide`, `modulo`, and the legacy `["and"]`/`["or"]`
  instructions - now reports the unbound root instead, when the operand came
  from a variable the run loaded and did not find bound. A key *bound* to
  `:undefined` (`%{"b" => :undefined}`) and a missing nested path on a bound
  root (`user.nope`) still produce a `TypeMismatchError`: those are genuine
  type mismatches on data the caller supplied. Evaluation semantics are
  unchanged - `:undefined` still errors in these positions - and the low-level
  `Predicator.Evaluator.evaluate/3` still returns the bare `TypeMismatchError`.

- The Hex package `files:` list named a bare `docs` entry, which swept the
  whole `docs/` tree - including `docs/plans/*.md` and `docs/design/*.md`,
  the agent workflow's internal per-bead planning documents. It now names the
  published doc subtrees explicitly (`docs/reference`, `docs/guides`,
  `docs/adr`, `docs/architecture.md`), matching what the `docs()` extras list
  already publishes to hexdocs.

## [3.7.0] - 2026-08-05

### Changed

- **`AND` and `OR` now short-circuit.** Previously the compiler evaluated both
  sides of every `AND`/`OR` unconditionally, so an unbound variable or a
  runtime error on the side that should have been skipped surfaced as an
  error - `false AND score > 5` with `score` unbound raised
  `TypeMismatchError`, and `true OR (1 / 0) > 1` raised a division-by-zero
  error. Both now evaluate to `false` and `true` respectively, matching every
  mainstream language's `AND`/`OR` semantics and this library's own graceful
  undefined-handling documentation. **This is an observable behavior change**:
  expressions that previously returned `{:error, _}` now return `{:ok, _}`. A
  consumer relying on the error was relying on the bug. `:undefined`
  propagation is ECMAScript-aligned rather than symmetric - see
  `docs/architecture.md`'s "Short-Circuit Evaluation" section for the exact
  rule. Old compiled artifacts using `["and"]`/`["or"]` directly are
  unaffected; the evaluator still accepts both opcodes.
- `Predicator.parse/1` now returns positioned AST nodes, so every node has one
  more trailing element than it did in 3.6. Callers that pattern-match on node
  shape either wrap the result in `Predicator.Parser.strip_positions/1` to get
  the old shape back, or add a trailing `_position` to their patterns.
  `Predicator.decompile/2` and `Predicator.Compiler.to_instructions/2` still
  accept a hand-built 3.6-shaped AST unchanged, and the instruction list
  `Predicator.compile/1` produces is byte-identical, so stored compiled
  artifacts and cross-language interchange are unaffected.
- Documentation restructured: the README is now a slim entry point, with the
  language reference, nested data access, custom functions, and location
  expressions moved to `docs/reference/` and `docs/guides/` and published to
  hexdocs. All documentation examples are now executed by the test suite.

### Added

- **ISA v2** (ADR-0001): the instruction set is Predicator's cross-language
  interchange format, and both entries below are new opcodes the Ruby and
  JavaScript siblings need to add for parity with this release.
  - `["make_list", n]` instruction: pops n values from the stack and pushes
    them as a list, in source order.
  - `["jump_if_falsy_or_pop", offset]` and `["jump_if_true_or_pop", offset]`
    instructions: relative, forward-only conditional jumps used to
    short-circuit `AND`/`OR`.
- `Predicator.Context`: a bound evaluation context built once with `new/2`
  (merging builtin and custom functions a single time), rebound cheaply with
  `bind/3` and `assign/3`, and evaluated against many times via
  `Predicator.evaluate/3`, which now accepts either a `%Context{}` or a bare
  map
- `Predicator.Undefined`: the one public module that owns the `:undefined`
  sentinel - `value/0`, `undefined?/1`, and `to_nil/1`/`from_nil/1`
  normalizers for a JSON-shaped boundary. `Predicator.Types.undefined?/1`
  now delegates to it.
- `Predicator.Context.bound?/2`: answers whether a root variable is bound in
  a context's data, checking both string and atom keys.
- `starts_with(s, prefix)`, `ends_with(s, suffix)`, `substring(s, start[, len])`,
  and `index_of(s, sub)` builtin string functions
- `concat(list1, list2)` builtin function: concatenates two lists.
- `+` now concatenates two lists (`[1, 2] + [3]` -> `[1, 2, 3]`), alongside
  its existing numeric and string coercions.
- `Predicator.Evaluator.run_prepared/1` (result plus final evaluator state),
  `Predicator.Evaluator.unbound_loads/1`, and
  `Predicator.Evaluator.resolve_key/2`.
- Source positions on every AST node: each node carries a trailing
  `{line, column}` naming the token that defines it (the operator token for
  binary and unary operators, the opening bracket for lists and objects, the
  name token for function calls).
- `Predicator.Parser.strip_positions/1` and
  `Predicator.Parser.ensure_positions/1`: total, idempotent normalizers between
  the positioned AST and the position-free shape Predicator 3.6 produced.
- `Predicator.Compiler.to_instructions_with_positions/2` and
  `Predicator.Visitors.InstructionsVisitor.visit_with_positions/2`: compile to
  the usual instruction list plus a side table mapping each instruction's
  0-based index to the `{line, column}` of the AST node that emitted it. The
  table is an Elixir-side companion value and never enters the instruction
  format itself.
- `Predicator.compile_with_positions/1`: compiles a string expression to the
  instruction list `compile/1` returns plus that side table.
- An optional `:position` field on `Predicator.Errors.EvaluationError`,
  `Predicator.Errors.TypeMismatchError`, and
  `Predicator.Errors.UndefinedVariableError`, holding the `{line, column}` of
  the source token behind the failing instruction, or `nil` when no side table
  was available.
- `Predicator.Errors.put_position/2`: attaches a position to any error value,
  returning it unchanged when the position is `nil` or the value has no
  `:position` field.
- A `:positions` option on `Predicator.evaluate/3` and
  `Predicator.Evaluator.evaluate/3`, seeding the side table used to populate
  `:position` on runtime errors. Evaluating a string expression threads its own
  table automatically; an instruction-list caller who omits the option sees
  `position: nil` and no other change.

### Fixed

- `Predicator.decompile/2` and `Predicator.Compiler.to_string/2` no longer
  raise `FunctionClauseError` on ASTs containing dotted property access
  (`user.name`). `Predicator.Visitors.StringVisitor` was missing the
  `:property_access` clause; it now renders `object.property`, including
  chains (`user.profile.email`) and mixes with bracket access.
- Duration units now parse in source order: `3d8h` produces
  `[{3, "d"}, {8, "h"}]` instead of the reversed `[{8, "h"}, {3, "d"}]`, and
  multi-unit durations round-trip through the string visitor unchanged
- Comparing a `Date` against a `DateTime` now returns a boolean instead of
  silently evaluating to `:undefined`. The `Date` is coerced to `00:00:00`
  UTC of that day, matching the coercion mixed date subtraction already
  performs. This covers ordering, `==`/`!=`, and `in`/`contains`, and it
  makes every relative date (`3d ago`, `2w from now`, `next 1mo`, `last 1y`,
  all of which produce a `DateTime`) usable against a `Date` context value.
  Strict equality (`===`/`!==`) stays type-strict and never crosses the
  boundary.
- `Date` and `DateTime` ordering (`<`, `>`, `<=`, `>=`) is now chronological.
  The evaluator previously dispatched ordering comparisons to Erlang's `<`/`>`
  after confirming both sides were the same struct type, but Erlang orders
  structs by sorted map key, not by field meaning - `Date`'s keys sort
  `day, month, year`, so `#2026-08-14# < #2030-01-01#` compared day 14 against
  day 1 and returned `false`. `DateTime` was worse, sorting `microsecond`
  ahead of `month`. Ordering now goes through `Date.compare/2` and
  `DateTime.compare/2`, and `EQ`/`NE`/list-membership on `DateTime` now agree
  with `DateTime.compare/2` rather than structural equality, so two `DateTime`
  values denoting the same instant in different time zones compare equal.
- `Predicator.evaluate/3` now correctly reports `UndefinedVariableError` for
  any unbound root variable, not just a bare `variable_name` expression. The
  old check only matched a single-instruction `[["load", _]]` program, so an
  unbound variable inside a larger expression (`"missing > 5"`) silently
  returned `{:ok, :undefined}` instead of an error.
- Unbound-variable reporting now reflects the loads a run actually executed
  rather than the loads the compiled program contains. With short-circuiting
  `AND`/`OR`, a load inside a skipped branch is never read, but the previous
  check scanned the whole instruction list and could name it -
  `(false AND missing) OR unbound_b` reported `missing` instead of
  `unbound_b`.
- List literals with non-literal elements (`[x + 1, y]`) now compile and
  evaluate. Previously the compiler raised
  `"Non-literal list elements are not yet supported"`, the one place the
  errors-are-values convention was broken; errors from such expressions are now
  returned as `{:error, _}` values like every other failure.

### Deprecated

#### `=` as an equality operator

- Parsing an expression that uses `=` as an equality operator now emits a
  deprecation warning naming `==` as the replacement
- Behavior is otherwise unchanged: `=` still parses and still compiles to
  `["compare", "EQ"]`
- **Predicator 4.0 will make expression-position `=` a parse error.** Migrate
  to `==` before upgrading
- The warning is emitted once per parse and can be silenced with
  `config :predicator, deprecation_warnings: false`

```elixir
# Deprecated - warns, still works in 3.x
Predicator.evaluate("status = 'active'", context)

# Preferred
Predicator.evaluate("status == 'active'", context)
```

## [3.6.0] - 2026-08-04

### Added

#### Auto-vivifying path assignment for SCXML location expressions

- `Predicator.ContextLocation.put/3` writes a value at a resolved location path,
  creating missing intermediate maps and lists
- `Predicator.context_assign/4` resolves a location expression and writes in one call
- Integer path segments index lists and pad gaps with `:undefined`
- Assigning through an existing scalar returns a `:not_a_container` error rather than
  destroying data; negative indices return `:invalid_index`

#### Examples

```elixir
Predicator.context_assign(%{}, "user.profile.name", "Ada")
# {:ok, %{"user" => %{"profile" => %{"name" => "Ada"}}}}

Predicator.context_assign(%{"items" => [1]}, "items[2]", "x")
# {:ok, %{"items" => [1, :undefined, "x"]}}

Predicator.ContextLocation.put(%{}, ["data", "users", 0, "name"], "Ada")
# {:ok, %{"data" => %{"users" => [%{"name" => "Ada"}]}}}
```

### Changed

#### Replaces the hand-rolled quality gate with ex_quality

- `mix quality` is now [ex_quality](https://hex.pm/packages/ex_quality), configured
  in `.quality.exs`; the vendored `lib/mix/tasks/quality.ex` has been removed
- The gate runs format, compile (warnings as errors), Credo `--strict`, Dialyzer,
  an unused-dependency and security audit, and the full suite with the existing
  90% coverage minimum - stages run in parallel and report `file:line` findings
- `mix quality --profile loop` replaces `--skip-dialyzer`: it skips Dialyzer and
  coverage and runs only the tests covering changed code
- `mix quality --format json` emits a machine-readable report
- `mix quality.check` and `mix test --watch` are gone; the former no longer
  existed as a task and the latter's `mix_test_watch` dependency was undeclared

## [3.5.0] - 2025-09-09

### Added

#### Adds milliseconds support to duration system

- New 'ms' unit support in lexer, parser, and evaluator
- Duration.to_milliseconds/1 function for high-precision calculations
- Pattern matching guards for automatic precision selection
- Smart DateTime arithmetic (millisecond vs second precision)
- Comprehensive test coverage with 89 new tests
- Refactors evaluator to use Duration module functions (DRY)

#### Examples

- 500ms ago, 2s750ms from now
- #2024-01-15T10:30:00.000Z# + 1s500ms
- Automatic precision: ms > 0 triggers millisecond precision

## [3.4.0] - 2025-09-09

### Added

#### Durations and relative date/time arithmetic

- New duration literals and relative date expressions (e.g., `3d ago`, `2w from now`, `next 1mo`, `last 1y`)
- Date and DateTime arithmetic using durations (e.g., `#2024-01-10# + 5d`, `#2024-01-15T10:30:00Z# - 2h`)
- Grammar additions: `duration` and `relative_date` productions
- Full pipeline support (lexer, parser, compiler, evaluator, string visitor) with tests

#### Examples

```elixir
Predicator.evaluate("created_at > 3d ago", %{"created_at" => ~U[2024-01-20 00:00:00Z]})
Predicator.evaluate("due_at < 2w from now", %{"due_at" => Date.add(Date.utc_today(), 10)})
Predicator.evaluate("#2024-01-10# + 5d = #2024-01-15#", %{})
Predicator.evaluate("#2024-01-15T10:30:00Z# - 2h < #2024-01-15T10:30:00Z#", %{})
```

### Documentation

- Updated EBNF grammar in docs
- Added AGENTS.md with model-agnostic agent guidance; `CLAUDE.md` now references the same content

## [3.3.0] - 2025-08-31

### Added

- Depends on Jason library

## [3.2.0] - 2025-08-31

### Added

#### Strict Equality Operators

- **New Operators**: Added `===` (strict equality) and `!==` (strict inequality) operators
- **Type-Safe Comparisons**: Strict operators compare both value and type, unlike loose equality
- **Round-Trip Preservation**: Operators maintain their exact form during parse/decompile cycles
- **Complete Pipeline Support**: Full lexer, parser, evaluator, and visitor implementation
- **Comprehensive Testing**: 23 tests covering all aspects of strict equality functionality

#### Examples

```elixir
# Strict equality - same type and value required
Predicator.evaluate("5 === 5", %{})      # {:ok, true}
Predicator.evaluate("5 === '5'", %{})    # {:ok, false} - different types

# Strict inequality - true when type or value differs
Predicator.evaluate("5 !== '5'", %{})    # {:ok, true} - different types
Predicator.evaluate("1 !== true", %{})   # {:ok, true} - different types

# Operator distinction preserved
Predicator.parse("x = y") |> elem(1) |> Predicator.decompile()   # "x = y"
Predicator.parse("x == y") |> elem(1) |> Predicator.decompile()  # "x == y"  
Predicator.parse("x === y") |> elem(1) |> Predicator.decompile() # "x === y"
```

#### Technical Implementation

- **Lexer**: Added `:strict_equal` and `:strict_ne` token types with proper precedence
- **Parser**: Extended comparison grammar to support strict operators
- **Evaluator**: Added `STRICT_EQ` and `STRICT_NE` instruction handlers
- **StringVisitor**: Added decompilation support for round-trip accuracy
- **Type Safety**: Works with all data types including `:undefined` values

## [3.1.0] - 2025-08-30

### Added

#### JavaScript-Style Object Literals (Complete Implementation)

- **Object Literal Syntax**: Full support for JavaScript-style object notation with `{key: value}` syntax
- **Multiple Key Types**: Both identifier keys (`name: "John"`) and string keys (`"first name": "John"`)
- **Nested Objects**: Unlimited nesting depth for complex data structures
- **All Value Types**: Objects support all Predicator value types (strings, numbers, booleans, dates, lists, expressions)
- **Object Comparisons**: Full equality and inequality operations between objects
- **Integration**: Seamless compatibility with all existing features (functions, operators, property access)

#### Object Literal Examples

```elixir
# Basic object creation
Predicator.evaluate("{}", %{})                                    # {:ok, %{}}
Predicator.evaluate("{name: \"John\", age: 30}", %{})            # {:ok, %{"name" => "John", "age" => 30}}

# Variable references and expressions
Predicator.evaluate("{user: name, total: price + tax}", %{"name" => "Alice", "price" => 100, "tax" => 10})
# {:ok, %{"user" => "Alice", "total" => 110}}

# Nested objects
Predicator.evaluate("{user: {name: \"Bob\", role: \"admin\"}, active: true}", %{})
# {:ok, %{"user" => %{"name" => "Bob", "role" => "admin"}, "active" => true}}

# String keys for complex property names
Predicator.evaluate("{\"first name\": \"John\", \"last-name\": \"Doe\"}", %{})
# {:ok, %{"first name" => "John", "last-name" => "Doe"}}

# Object comparisons
Predicator.evaluate("{score: 85} == user_data", %{"user_data" => %{"score" => 85}})
# {:ok, true}
```

#### Complete Pipeline Support

- **Lexer**: Added `{`, `}`, `:` token recognition
- **Parser**: Full object grammar with proper precedence and error handling
- **Instructions**: Stack-based `object_new` and `object_set` instruction execution
- **Evaluator**: Efficient object construction and comparison operations
- **String Visitor**: Bidirectional transformation support (AST ↔ string representation)
- **Type System**: Enhanced type matching for object equality comparisons

#### Integration Features

- **Function Integration**: Objects work as function parameters and return values
- **Property Access**: Objects integrate with dot notation (`obj.property`) and bracket access (`obj["key"]`)
- **Boolean Logic**: Objects support all logical operations (AND, OR, NOT)
- **Arithmetic**: Object properties can contain arithmetic expressions and results
- **Date Support**: Objects can contain date/datetime literals and date function results
- **Custom Functions**: Objects work seamlessly with user-defined functions

#### Quality and Testing

- **886 Total Tests**: Comprehensive test coverage including edge cases and integration scenarios
- **91.8% Coverage**: High test coverage across all components
- **Parser Error Handling**: Robust error recovery for malformed object syntax
- **Performance Tested**: Validated with large objects and repeated evaluations
- **Production Ready**: Full quality assurance (formatting, linting, type checking)

## [3.0.0] - 2025-08-25

### Added

#### Location Expressions for SCXML Assignment Operations (Phase 2 Complete)

- **SCXML Location Expressions**: Complete implementation of location path resolution for SCXML `<assign>` operations
- **New API Function**: `Predicator.context_location/3` - resolves assignable location paths from expressions
- **Location Path Resolution**: Returns navigation paths like `["user", "name"]`, `["items", 0, "property"]` for SCXML assignment targets
- **Assignment Validation**: Distinguishes valid assignment targets (l-values) from computed expressions (r-values)
- **Core Module**: `Predicator.ContextLocation` with comprehensive location resolution logic and error handling
- **Structured Error Handling**: `Predicator.Errors.LocationError` with detailed error types and context information

#### Location Expression Examples

```elixir
# Valid assignment targets resolve to location paths
Predicator.context_location("user.profile.name", %{})                    # {:ok, ["user", "profile", "name"]}
Predicator.context_location("items[0]", %{})                             # {:ok, ["items", 0]}
Predicator.context_location("data['users'][index]['profile']", %{"index" => 2})  # {:ok, ["data", "users", 2, "profile"]}

# Invalid assignment targets return structured errors
Predicator.context_location("len(name)", %{})                            # {:error, %LocationError{type: :not_assignable}}
Predicator.context_location("42", %{})                                   # {:error, %LocationError{type: :not_assignable}}
Predicator.context_location("score + 1", %{})                            # {:error, %LocationError{type: :not_assignable}}
```

#### Error Types and Validation

- **`:not_assignable`**: Expression cannot be used as assignment target (literals, functions, computed expressions)
- **`:invalid_node`**: Unknown or unsupported AST node type encountered during resolution
- **`:undefined_variable`**: Variable referenced in bracket key is not defined in evaluation context
- **`:invalid_key`**: Bracket key is not a valid string or integer type
- **`:computed_key`**: Computed expressions cannot be used as assignment target keys

#### Assignable vs Non-Assignable Classifications

- **✅ Valid Assignment Targets**: Simple identifiers, property access, bracket access, mixed notation
  - `user`, `score`, `config.database.host`
  - `items[0]`, `user['profile']`, `data["settings"]`
  - `user.settings['theme']`, `data['users'][0].profile`
- **❌ Invalid Assignment Targets**: Literals, function calls, computed expressions
  - `42`, `"hello"`, `true`, `#2024-01-15#`
  - `len(name)`, `upper(role)`, `max(a, b)`
  - `score + 1`, `items[i + 1]`, `score > 85`

#### Technical Implementation

- **Full Location Resolution**: Recursive resolution of nested property access and bracket access
- **Mixed Notation Support**: Complete support for expressions like `user.settings['theme']` and `data['users'][0].name`
- **Variable Key Resolution**: Bracket keys can reference context variables for dynamic access patterns
- **Context Integration**: Uses existing evaluation context for variable key resolution
- **Comprehensive Testing**: 49 comprehensive tests covering all location resolution scenarios and error cases

#### Type Coercion and Float Support

- **Float Literal Support**: Extended lexer to parse floating-point numbers (e.g., `3.14`, `0.5`)
- **Float Token Type**: Added `:float` token type to distinguish from integers
- **Parser Float Handling**: Updated parser to handle float tokens and create appropriate AST nodes
- **Arithmetic with Floats**: All arithmetic operations now support both integers and floats
  - Addition, subtraction, multiplication work seamlessly with mixed numeric types
  - Division returns float when needed, integer when evenly divisible
  - Modulo remains integer-only as per mathematical conventions
- **String Concatenation with `+` Operator**: Implemented JavaScript-like type coercion
  - `"Hello" + "World"` → `"HelloWorld"` (string concatenation)
  - `"Count: " + 5` → `"Count: 5"` (string + number coercion)
  - `42 + " items"` → `"42 items"` (number + string coercion)
- **Type Coercion Rules**:
  - Number + Number → Numeric addition (supports mixed int/float)
  - String + String → String concatenation
  - String + Number → String concatenation (number converted to string)
  - Number + String → String concatenation (number converted to string)
- **Comparison Enhancements**: Numbers of different types (int/float) can be compared
- **Unary Minus for Floats**: Unary minus operator now works with floating-point numbers
- **Error Message Updates**: Updated error messages from "integer" to "number" where appropriate
- **Comprehensive Testing**: Added 28 new tests covering all type coercion scenarios

### Changed

#### Property Access Parsing Architecture Overhaul (Breaking Changes)

- **Complete Dot Notation Reimplementation**: Transformed from dotted identifiers to proper property access AST nodes
- **Lexer Breaking Change**: Dots removed from valid identifier characters, now parsed as separate tokens
- **Parser Grammar Enhancement**: Added property access grammar `postfix → primary ( "[" expression "]" | "." IDENTIFIER )*`
- **New AST Structure**: Expressions like `user.email` now parsed as `{:property_access, {:identifier, "user"}, "email"}`
- **Instruction Pipeline**: Evaluation generates separate `load` and `access` instructions instead of single `load` with dotted name
- **Mixed Notation Support**: Enables complex expressions like `user.settings['theme']` and `data['users'][0].profile`

### Breaking Changes

#### v3.0.0 - Property Access Parsing Overhaul

This is a **major breaking change** affecting how dot notation is parsed and evaluated:

**⚠️ Context Key Impact**: Context keys containing dots (e.g., `"user.email"`) will no longer match dot notation expressions (`user.email`). The expression `user.email` is now parsed as property access requiring nested structure `%{"user" => %{"email" => "..."}}`

**Migration Required**:

```elixir
# BEFORE (v2.2.0 and earlier) - WILL NO LONGER WORK
context = %{"user.email" => "john@example.com"}
Predicator.evaluate("user.email = 'john@example.com'", context)  # No longer matches

# AFTER (v3.0.0+) - Use proper nested structures
context = %{"user" => %{"email" => "john@example.com"}}
Predicator.evaluate("user.email = 'john@example.com'", context)  # Works correctly
```

**Technical Changes**:

- **Lexer**: Dots no longer valid in identifier characters, parsed as separate `:dot` tokens
- **Parser**: New property access AST nodes `{:property_access, left_node, property}`
- **Evaluator**: New `access` instruction handler, removed dotted identifier support from `load_from_context`
- **Instructions**: `user.email` generates `[["load", "user"], ["access", "email"]]` instead of `[["load", "user.email"]]`

**Benefits**:

- Enables mixed notation: `user.settings['theme']`, `data['users'][0].name`
- Supports SCXML location expressions for assignment operations
- Proper property access semantics for complex data structures
- Foundation for advanced SCXML datamodel integration

## [2.2.0] - 2025-08-24

### Added

#### Bracket Access and Property Access Enhancement

- **Complete Bracket Notation Support**: Implemented full bracket access functionality (`obj['key']`, `arr[0]`, `obj[variable]`)
- **Parser Extensions**: Added postfix parsing for bracket access with recursive chaining support
- **Grammar Enhancement**: Updated grammar with postfix operations: `unary → postfix`, `postfix → primary ( "[" expression "]" )*`
- **New AST Node Type**: Added `{:bracket_access, object, key}` AST node for bracket access expressions
- **Evaluator Support**: Implemented `["bracket_access"]` instruction with comprehensive evaluation logic
- **Mixed Access Patterns**: Full support for chained access like `data['users'][0]['name']`
- **Array Indexing**: Complete array access with bounds checking (`items[0]`, `scores[index]`)
- **Dynamic Key Access**: Support for variable and expression-based keys (`obj[key]`, `items[i + 1]`)
- **Type Safety**: Comprehensive error handling for invalid key types with structured error messages
- **String Visitor Support**: Added round-trip string conversion for bracket access expressions
- **Comprehensive Testing**: Added 12 new parser tests covering all bracket access scenarios

#### Error Handling Architecture Refactoring

- **Modular Error Structure**: Refactored monolithic error handling into individual error modules under `lib/predicator/errors/`
- **Shared Error Utilities**: Created `Predicator.Errors` module with common utility functions for consistent error formatting
- **Individual Error Modules**: Split error handling into focused modules:
  - `Predicator.Errors.TypeMismatchError` - Type validation and mismatch errors
  - `Predicator.Errors.EvaluationError` - Runtime evaluation errors (division by zero, insufficient operands)
  - `Predicator.Errors.UndefinedVariableError` - Variable access errors
  - `Predicator.Errors.ParseError` - Expression parsing and syntax errors
- **Consistent Error Messages**: Unified error message formatting across all error types
- **Code Quality Improvements**: Resolved all credo issues with proper module aliasing and organization

## [2.1.0] - 2025-08-24

### Added

#### Arithmetic and Unary Operations (Complete Implementation)

- **Full Arithmetic Support**: Complete parsing and evaluation pipeline for arithmetic expressions
  - **Binary operations**: `+` (addition), `-` (subtraction), `*` (multiplication), `/` (division), `%` (modulo)
  - **Unary operations**: `-` (unary minus), `!` (unary bang/logical NOT)
- **Proper Precedence**: Mathematical precedence handling (unary → multiplication → addition → equality → comparison)
- **Instruction Execution**: Stack-based evaluator with 7 new instruction handlers
- **Error Handling**: Division by zero protection, type checking, comprehensive error messages
- **Pattern Matching**: Idiomatic Elixir implementation using pattern matching for clean code

## [2.0.0] - 2025-08-21

### Changed

#### Custom Function Architecture Overhaul

- **Breaking Change**: Removed global function registry system in favor of evaluation-time function parameters
- **New API**: Custom functions now passed via `functions:` option in `Predicator.evaluate/3` calls
- **Function Format**: Custom functions use `%{name => {arity, function}}` format where function takes `[args], context` and returns `{:ok, result}` or `{:error, message}`
- **Thread Safety**: Eliminated global state for improved concurrency and thread safety
- **Function Merging**: SystemFunctions always available with custom functions merged in, allowing overrides
- **Simplified Startup**: No application-level function registry initialization required

#### Examples

```elixir
# Old registry-based approach (removed)
Predicator.register_function("double", 1, fn [n], _context -> {:ok, n * 2} end)
Predicator.evaluate("double(21)", %{})

# New evaluation-time approach
custom_functions = %{"double" => {1, fn [n], _context -> {:ok, n * 2} end}}
Predicator.evaluate("double(21)", %{}, functions: custom_functions)

# Custom functions can override built-ins
custom_len = %{"len" => {1, fn [_], _context -> {:ok, "custom_result"} end}}
Predicator.evaluate("len('anything')", %{}, functions: custom_len)  # {:ok, "custom_result"}
```

#### Removed APIs

- `Predicator.register_function/3` - Use `functions:` option instead
- `Predicator.clear_custom_functions/0` - No longer needed
- `Predicator.list_custom_functions/0` - No longer needed
- `Predicator.Functions.Registry` module - Entire registry system removed

### Breaking Changes

#### v2.0.0 - Custom Function Architecture Overhaul

- **Removed**: Global function registry system (`Predicator.Functions.Registry` module)
- **Removed**: `Predicator.register_function/3`, `Predicator.clear_custom_functions/0`, `Predicator.list_custom_functions/0`
- **Changed**: Custom functions now passed via `functions:` option in `evaluate/3` calls instead of global registration
- **Benefit**: Thread-safe, no global state, per-evaluation function scoping
- **Migration**: Replace registry calls with function maps passed to `evaluate/3`

## [1.1.0] - 2025-08-20

### Added

#### Nested Data Structure Access

- **Dot Notation Support**: Access deeply nested data structures using dot notation syntax
- **Enhanced Lexer**: Extended identifier tokenization to include dots (`.`) as valid characters
- **Recursive Context Loading**: Added `load_nested_value/2` function for traversing nested maps
- **Mixed Key Type Support**: Works seamlessly with string keys, atom keys, or mixed key types
- **Graceful Error Handling**: Returns `:undefined` for missing paths or non-map intermediate values
- **Unlimited Nesting Depth**: Support for arbitrarily deep nested structures

#### Single Quote String Support

- **Dual Quote Types**: Added support for single-quoted strings (`'hello'`) alongside double-quoted strings (`"hello"`)
- **Quote Type Preservation**: Round-trip parsing and decompilation preserves original quote type
- **Enhanced Lexer**: Extended string tokenization to handle both quote types with proper escaping
- **AST Enhancement**: New `{:string_literal, value, quote_type}` AST node for quote-aware string handling
- **Escape Sequences**: Full escape sequence support in both quote types (`\'`, `\"`, `\n`, `\t`, etc.)

### Breaking Changes

#### v1.1.0 - Nested Access Parsing

- **Changed**: Variables containing dots (e.g., `"user.email"`) now parsed as nested access paths
- **Impact**: Context keys like `"user.profile.name"` will no longer match identifier `user.profile.name`
- **Solution**: Use proper nested data structures instead of flat keys with dots

## [1.0.1] - 2025-08-20

### Documentation

- Fixes main page for Hex docs

## [1.0.0] - 2025-08-19

### Added

#### Core Language Features

- **Comparison Operators**: Full support for `>`, `<`, `>=`, `<=`, `=`, `!=` with proper type handling
- **Logical Operators**: Case-insensitive `AND`/`and`, `OR`/`or`, `NOT`/`not` with correct precedence
- **Data Types**:
  - Numbers (integers): `42`, `-17`
  - Strings (double-quoted): `"hello"`, `"world"`
  - Booleans: `true`, `false`
  - Date literals: `#2024-01-15#` (ISO 8601 format)
  - DateTime literals: `#2024-01-15T10:30:00Z#` (ISO 8601 with timezone)
  - List literals: `[1, 2, 3]`, `["admin", "manager"]`
  - Identifiers: `score`, `user_name`, `is_active`

#### Advanced Operations

- **Membership Operators**:
  - `in` for element-in-collection testing (`role in ["admin", "manager"]`)
  - `contains` for collection-contains-element testing (`[1, 2, 3] contains 2`)
- **Parenthesized Expressions**: Full support with proper precedence handling
- **Plain Boolean Expressions**: Support for bare identifiers (`active`, `expired`) without explicit `= true`

#### Function System

- **Built-in System Functions**:
  - **String functions**: `len(string)`, `upper(string)`, `lower(string)`, `trim(string)`
  - **Numeric functions**: `abs(number)`, `max(a, b)`, `min(a, b)`
  - **Date functions**: `year(date)`, `month(date)`, `day(date)`
- **Custom Function Registration**: Register anonymous functions with `Predicator.register_function/3`
- **Function Registry**: ETS-based registry with automatic arity validation and error handling
- **Context-Aware Functions**: Functions receive evaluation context for dynamic behavior

#### Architecture & Performance

- **Multi-Stage Compilation Pipeline**: Expression → Lexer → Parser → Compiler → Instructions → Evaluator
- **Compile-Once, Evaluate-Many**: Pre-compile expressions for repeated evaluation
- **Stack-Based Evaluator**: Efficient instruction execution with minimal overhead
- **Comprehensive Error Handling**: Detailed error messages with line/column positioning

#### Developer Experience

- **String Decompilation**: Convert AST back to readable expressions with formatting options
- **Multiple Evaluation APIs**:
  - `evaluate/2` - Returns `{:ok, result}` or `{:error, message}`
  - `evaluate!/2` - Returns result directly or raises exception
  - `compile/1` - Pre-compile expressions to instructions
  - `parse/1` - Parse expressions to AST for inspection
- **Formatting Options**: Configurable spacing (`:normal`, `:compact`, `:verbose`) and parentheses (`:minimal`, `:explicit`, `:none`)

### Breaking Changes

#### ⚠️ COMPLETE LIBRARY REWRITE ⚠️

Version 1.0.0 is a **complete rewrite** of the Predicator library with entirely new:

- API design and function signatures
- Expression syntax and grammar
- Internal architecture and data structures
- Feature set and capabilities

#### Migration Guide

**Migration from versions < 1.0.0 has NOT been tested and is NOT guaranteed to work.**

If you are upgrading from a pre-1.0.0 version:

1. **Treat this as a new library adoption**, not an upgrade
2. **Review all documentation** - APIs have completely changed
3. **Test thoroughly** in development environments
4. **Expect to rewrite** all integration code
5. **Plan for significant refactoring** of existing expressions

Future 1.x.x versions will maintain backwards compatibility and include proper migration guides.

---

For detailed information about upcoming features and development roadmap, see the project README.
