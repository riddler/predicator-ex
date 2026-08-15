# Language Reference

The complete Predicator expression language: data types, operators, builtin
functions, decompile formatting, and error shapes. For the grammar with
precedence, see [Architecture](../architecture.md); for the tree shape those
expressions parse into, see the node inventory in `docs/reference/ast.md`.

## Data Types

- **Numbers**: `42`, `-17` (integers), `3.14`, `-2.5` (floats)
- **Strings**: `'hello'`, `'world'` (single-quoted) or `"hello"`, `"world"`
  (double-quoted, with escape sequences)
- **Booleans**: `true`, `false` (or plain identifiers like `active`, `expired`)
- **Undefined**: `undefined` - the absent/unset value; see "Undefined and
  Sparse Data" below
- **Null**: `null` - the present-but-empty value; see "Null and undefined"
  below
- **Dates**: `#2024-01-15#` (ISO 8601 date format)
- **DateTimes**: `#2024-01-15T10:30:00Z#` (ISO 8601 datetime format with
  timezone)
- **Durations**: Natural units for time spans (e.g., `3d`, `2h`, `15m`)
  - In relative expressions: `3d ago`, `2w from now`, `next 1mo`, `last 1y`
  - In arithmetic: `#2024-01-10# + 5d`, `#2024-01-15T10:30:00Z# - 2h`
- **Lists**: `[1, 2, 3]`, `['admin', 'manager']` (homogeneous collections)
- **Objects**: `{}`, `{name: "John", age: 30}`, `{user: {role: "admin"}}`
  (JavaScript-style object literals)
- **Identifiers**: `score`, `user_name`, `is_active`, `user.profile.name`,
  `user['key']`, `items[0]` (variable references with dot notation and
  bracket notation for nested data)

## Arithmetic Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `+`      | Addition | `score + bonus`, `2 + 3 * 4` |
| `-`      | Subtraction | `total - discount`, `100 - 25` |
| `*`      | Multiplication | `price * quantity`, `3 * 4` |
| `/`      | Division (truncating if both operands are integers; float if either is a float) | `total / count`, `10 / 3`, `10 / 3.0` |
| `%`      | Modulo | `id % 2`, `17 % 5` |
| `-`      | Unary minus | `-amount`, `-(x + y)` |

### What `+` does with mixed operands

`+` is overloaded across these operand-type combinations:

| Left | Right | Result |
|---|---|---|
| Number | Number | Numeric addition |
| String | String | String concatenation |
| String | Number | String concatenation (number stringified) |
| Number | String | String concatenation (number stringified) |
| List | List | List concatenation |

Every other pairing is a `TypeMismatchError`, a list against a scalar
included: the stringifying coercion applies only when one operand is a
string and the other a number.

```elixir
iex> Predicator.evaluate("'Hello' + ' World'", %{})
{:ok, "Hello World"}

iex> Predicator.evaluate("'Count: ' + 42", %{})
{:ok, "Count: 42"}

iex> Predicator.evaluate("[1, 2] + [3]", %{})
{:ok, [1, 2, 3]}
```

## Comparison Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `>`      | Greater than | `score > 85`, `#2024-01-15# > #2024-01-10#` |
| `<`      | Less than | `age < 30`, `created_at < #2024-01-15T10:00:00Z#` |
| `>=`     | Greater than or equal | `points >= 100` |
| `<=`     | Less than or equal | `count <= 5` |
| `==`     | Equal | `status == 'active'`, `date == #2024-01-15#` |
| `!=`     | Not equal | `role != 'guest'` |
| `===`    | Strict equal (no type coercion) | `count === 5` |
| `!==`    | Strict not equal (no type coercion) | `count !== "5"` |

> **`=` is assignment, not equality.** `=` is valid only at the start of a
> statement in the [statement grammar](../architecture.md) - `Predicator.parse_program/2`
> - with an assignable left side; a bare `=` in expression position is a
> parse error naming `==`. `==` and `===` are the only equality operators. See
> [ADR-0002](../adr/0002-the-equals-grammar-break.md) for the reasoning.

## Comparing dates and datetimes

- **Same type**: `Date`/`Date` and `DateTime`/`DateTime` compare
  chronologically via `Date.compare/2` and `DateTime.compare/2`, never by
  Erlang's raw struct-key ordering.
- **Mixed pair**: a `Date` compared against a `DateTime` is coerced to
  `00:00:00` UTC of that day, then compared as two `DateTime`s. This applies
  to ordering (`>`, `<`, `>=`, `<=`), `==`/`!=`, and `in`/`contains`
  membership.
- **Strict equality is exempt**: `===` and `!==` resolve before any type
  dispatch, so a `Date` is never strictly equal to a `DateTime` regardless of
  the instant either denotes.
- **The anchor is fixed at UTC midnight**, with no option to configure it.

Every relative date (`3d ago`, `2w from now`, `next 1mo`, `last 1y`)
evaluates to a `DateTime`, so without the coercion a `Date` context value
could never be compared against one.

## Logical Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `AND`    | Logical AND (case-insensitive) | `score > 85 AND age >= 18` |
| `OR`     | Logical OR (case-insensitive) | `role == 'admin' OR role == 'manager'` |
| `NOT`    | Logical NOT (case-insensitive) | `NOT expired` |
| `!`      | Unary logical negation | `!expired` |

`!` rejects an `:undefined` operand the same way `NOT` does - see the
"Reject vs. propagate" table below.

## Membership Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `in`     | Element in collection | `role in ['admin', 'manager']` |
| `contains` | Collection contains element | `[1, 2, 3] contains 2` |

## Type Casts

`expr::type` converts `expr`'s value to a named type. The seven legal target
type names are `integer`, `float`, `string`, `boolean`, `date`, `datetime`,
and `duration` - the scalar ISA type names (`docs/isa.md` §3); `list` and
`map` are not among them. A name that is not one of the seven is a parse
error at authoring time, naming the accepted list:

```elixir
iex> Predicator.evaluate("'42'::integer", %{})
{:ok, 42}
```

`::` is postfix: it binds tighter than unary minus, so `-1::integer` is
`-(1::integer)`, i.e. `-1`, not `(-1)::integer`. It chains left-to-right like
the other postfix forms (`.` and `[]`), so a cast can feed another cast:

```elixir
iex> Predicator.evaluate("'42'::integer::float", %{})
{:ok, 42.0}
```

### Conversion matrix

`=` is identity (a same-type cast is a no-op), a description names the
conversion performed, and `-` means the pair always yields `:undefined`
(see "Failure is `:undefined`, never an error" below):

| source \ target | integer | float | string | boolean | date | datetime | duration |
|---|---|---|---|---|---|---|---|
| integer | = | widen | format | - | - | - | - |
| float | truncate | = | format | - | - | - | - |
| string | parse | parse | = | parse | parse | parse | parse |
| boolean | - | - | format | = | - | - | - |
| date | - | - | format | - | = | midnight UTC | - |
| datetime | - | - | format | - | calendar date | = | - |
| duration | - | - | format | - | - | - | = |

There is no boolean/number bridge: `1::boolean` and `true::integer` are both
`:undefined`, matching the language's rule that no operator treats a number
as truthy or a boolean as a number. Lists and maps are not among the seven
types casts accept, so `[1, 2]::string` is `:undefined` too - a cast never
serializes a collection.

**Numeric conversions.**

- `integer::float` widens to the nearest representable double, exact up to
  2^53 and rounding beyond it - not lossless for a very large integer.
- `float::integer` truncates toward zero (`-1.5::integer` is `-1`,
  `1.9::integer` is `1`), not PostgreSQL's round-to-nearest.

**String parses.** Each parse accepts the whole string, anchored start to
end, or yields `:undefined` - no trimming, no partial consumption, and a
trailing newline does not parse (`"42\n"::integer` is `:undefined`, not
`42`):

- `::integer` - an optionally-negated decimal integer (`-?[0-9]+`); no
  leading `+`, no underscores, no leading/trailing whitespace.
- `::float` - an optionally-negated decimal with an optional fraction
  (`-?[0-9]+(\.[0-9]+)?`); `"3"::float` is `3.0`. No exponent form
  (`"1e3"::float` is `:undefined`) and no bare fraction (`".5"::float` is
  `:undefined`).
- `::boolean` - exactly `"true"` or `"false"`, case-sensitive; `"TRUE"`,
  `"1"`, and `"yes"` are all `:undefined`.
- `::date` - an ISO 8601 calendar date (`"2026-08-09"`); a datetime-shaped
  string is `:undefined` here.
- `::datetime` - an ISO 8601 datetime **with a UTC offset**, normalized to
  UTC; a date-only string is `:undefined`. The supported spelling for a
  date-shaped string is `s::date::datetime`.
- `::duration` - the language's own duration-literal grammar (see below), now
  admitting a decimal fraction on a component (`"1.5s"`); see below for the
  exactness rule and the `mo`/`y` approximation commitment.

**String formats (`::string`).** Integer formats as decimal, float as the
shortest round-trip decimal, boolean as `"true"`/`"false"`, and date as ISO
8601. Datetime formats as ISO 8601 in UTC with a `Z` suffix, and the
fractional-seconds field is canonicalized: omitted entirely when the
sub-second component is zero (`"2026-08-09T12:00:00Z"`), and exactly six
digits when it is not (`"2026-08-09T12:00:00.500000Z"`). That makes
`::string` a canonicalization of the instant rather than a string identity -
a one-digit fraction widens to six, and a seventh input digit is truncated by
the `::datetime` parse before it ever reaches `::string`. Duration formats via
the duration-literal grammar, largest unit first with zero components
omitted (`"0s"` when every component is zero).

**The date/datetime bridge.** `date::datetime` lands at midnight UTC - the
same coercion `compare` and arithmetic already apply to a mixed date/datetime
pair. `datetime::date` keeps the datetime's calendar date and drops the time.

### Duration parsing is a canonicalizer, not `to_string`'s inverse

`::duration` accepts a sequence of `<digits>(.<digits>)?<unit>` pairs
(`y`, `mo`, `w`, `d`, `h`, `m`, `s`, `ms`) with no whitespace, no sign, and no
partial consumption - but unlike the other string parses, it does not
require a *canonical* ordering, and repeated units accumulate rather than
overwriting. `"30m3d"` parses to the same duration as `"3d30m"` (3 days,
30 minutes), and `"1s2s"` parses to 3 seconds, not the last `"2s"` seen. So
`::duration` is a canonicalizer over any equivalent spelling, not an inverse
of `::string`'s duration formatting: `some_string::duration::string` does not
reproduce `some_string` unless it was already in canonical (largest-unit-
first, non-repeating) form. Round-tripping the other direction -
`some_duration::string::duration` - does recover the original duration,
because `::string`'s output is already canonical.

A component may also carry a decimal fraction (`"1.5s"`), just as bare here
as it is disallowed - a fraction requires digits on both sides of the dot,
so `".5s"` and `"1.s"` are both `:undefined`, the same position `::float`
already takes (`".5"::float` is `:undefined`). A fractional component must
convert to an *exact* whole number of milliseconds or the whole string is
`:undefined`: `"0.5ms"::duration` is `:undefined` (half a millisecond),
while `"0.5s"::duration`, `"0.25s"::duration`, and `"1.0s"::duration` all
succeed. A valid fraction expands to the integer part on its own unit plus a
remainder decomposed largest-first through `d`, `h`, `m`, `s`, `ms` only -
never back into `w`, `mo`, or `y`. Fractions are accepted on every unit;
`mo` and `y` commit this project's documented 30-day and 365-day
approximations at parse time, so `"0.5mo"::duration` has `days: 15` and no
`months` component. Repeated units keep accumulating with an expansion in
the mix: `"1.5s200ms"::duration` is 1 second 700 milliseconds, not a
collision - that stricter rule belongs to the compiled duration *literal*
grammar, not to `::duration`'s string parse.

Because `to_string/1` never emits a fraction (it is not part of this
canonicalizer's output vocabulary), a fractional spelling does not survive a
round trip through `::string`: `"1.5s"::duration::string` is `"1s500ms"`,
not `"1.5s"`. The guaranteed direction remains
`some_duration::string::duration`, unaffected by fractions since
`::string`'s output is always integer-only and already canonical.

### Failure is `:undefined`, never an error

A conversion that cannot produce a value of the target type yields
`:undefined`. It never raises and never returns an error - casting is total
over every value:

```elixir
iex> Predicator.evaluate("'abc'::integer", %{})
{:ok, :undefined}
```

Because `:undefined` is falsy at a jump (see "Undefined and Sparse Data"
below), a bad cast inside a larger expression is just falsy rather than a
crash:

```elixir
iex> Predicator.evaluate("'abc'::integer > 5", %{})
{:ok, :undefined}
```

Casting `:undefined` itself yields `:undefined` for every target type -
the same propagation rule a missing nested path already follows elsewhere in
the language. (A bare unbound *root* variable is different: as with any
other operator, `missing::integer` on an empty context still reports
`Predicator.Errors.UndefinedVariableError` under the rule in "Unbound roots
vs. missing paths" below, because it is the root itself that is unbound, not
a value the cast produced.)

```elixir
iex> Predicator.evaluate("user.age::integer", %{"user" => %{}})
{:ok, :undefined}
```

## Statements and control flow

Everything above this section is the `expression` grammar, reached through
`Predicator.parse/2` and `Predicator.evaluate/3`. A program is a
`;`-separated sequence of *statements*, reached through the separate
`Predicator.parse_program/2` entry point (and `Predicator.execute/2,3` for
running one) - the same split the `=` note above draws for assignment: `if`
is statement-position only, exactly like `=`, and `parse/2` rejects it with a
message naming `parse_program/2`.

```elixir
iex> Predicator.parse("if x { }")
{:error, "'if' is a statement keyword, not an expression - control flow is only valid in a program (Predicator.parse_program/2).", 1, 1, {{1, 1}, {1, 3}}}
```

### `if`/`else`

The `if_statement` production (see the grammar in
[Architecture](../architecture.md)) is `if cond { ... }`, optionally followed
by an `else`. It runs its `then` block when `cond` is `true` and skips it
otherwise; an `else` block runs when the condition does not:

```elixir
iex> {:ok, ast} = Predicator.parse_program("if score > 85 { grade = 'A' }")
iex> ast
{:program, [{:if, {:comparison, :gt, {:identifier, "score", {1, 4}}, {:literal, 85, {1, 12}}, {1, 10}}, {:block, [{:assignment, {:identifier, "grade", {1, 17}}, {:string_literal, "A", :single, {1, 25}}, {1, 23}}], {1, 15}}, nil, {1, 1}}], {1, 1}}
```

```elixir
iex> {:ok, ast} = Predicator.parse_program("if score > 85 { grade = 'A' } else { grade = 'B' }")
iex> {:if, _condition, _then_block, else_block, _pos} = hd(elem(ast, 1))
iex> else_block
{:block, [{:assignment, {:identifier, "grade", {1, 38}}, {:string_literal, "B", :single, {1, 46}}, {1, 44}}], {1, 36}}
```

`else if` chains are sugar, not a separate construct: `else if c2 { B }`
parses as an `else` block whose sole statement is another `{:if, ...}` node,
recursively. There is no chain node in the AST to learn - `if a { A } else if
b { B } else { C }` and a hand-nested `if a { A } else { if b { B } else { C
} }` desugar to the identical tree.

Braces are mandatory - there is no braceless single-statement form - and a
block may be empty:

```elixir
iex> Predicator.parse_program("if x { }")
{:ok, {:program, [{:if, {:identifier, "x", {1, 4}}, {:block, [], {1, 6}}, nil, {1, 1}}], {1, 1}}}
```

The separator between a block's closing `}` and the next statement is
optional - `if c { } a = 1` and `if c { }; a = 1` both parse - because a
statement ending in `}` is already unambiguously terminated.

### Braces introduce no scope

Unlike most C-family languages, `{ }` here only *groups* statements; it does
not open a new binding scope. An assignment made inside a taken branch is an
ordinary write to the same flat context every other assignment writes to, so
it is visible after the block and in `execute/2`'s result, whether or not the
branch that wrote it was the one taken - `x = 1; if x > 0 { y = 2 } else
{ y = 3 }` leaves both `x` and `y` bound at the top level, the same as if the
assignment inside the taken branch had been written without the surrounding
`if` at all:

```elixir
iex> {:ok, ctx} = Predicator.execute("x = 1; if x > 0 { y = 2 } else { y = 3 }", %{})
iex> ctx.data
%{"x" => 1, "y" => 2}
```

The same holds for a `while` body, which is why a counted loop can
accumulate at all: `i` in `i = 0; while i < 3 { i = i + 1 }` is one binding
the body rewrites, not a fresh one per iteration.

See [ADR-0013](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0013-control-flow-lowers-to-new-jump-opcodes.md)
for why: the statement layer has no declaration form to hang a scope on, and
statement mode's whole output is the context at halt, so a write that
vanished with its block would be a write to nowhere.

### The condition must be a boolean

`if`'s condition is a bare expression - parentheses are ordinary grouping,
never required - and its value must be a boolean. `false` and `:undefined`
skip the branch; `true` runs it; any other value is a `TypeMismatchError`
rather than being coerced (see "Error Shapes" below).

### `while`

The `while_statement` production (see the grammar in
[Architecture](../architecture.md)) is `while cond { ... }`. It runs its body
block for as long as `cond` is `true`, checking the condition again before
every iteration including the first:

```elixir
iex> {:ok, ast} = Predicator.parse_program("while i < 3 { i = i + 1 }")
iex> ast
{:program, [{:while, {:comparison, :lt, {:identifier, "i", {1, 7}}, {:literal, 3, {1, 11}}, {1, 9}}, {:block, [{:assignment, {:identifier, "i", {1, 15}}, {:arithmetic, :add, {:identifier, "i", {1, 19}}, {:literal, 1, {1, 23}}, {1, 21}}, {1, 17}}], {1, 13}}, {1, 1}}], {1, 1}}
```

```elixir
iex> {:ok, ctx} = Predicator.execute("i = 0; while i < 3 { i = i + 1 }", %{})
iex> ctx.data
%{"i" => 3}
```

`while` is statement-position only, on the same terms as `if`: `parse/2`
rejects it with the same message naming `parse_program/2`, braces are
mandatory, and the body block opens no scope - a `store` inside it writes to
the same flat context as one outside it (see "Braces introduce no scope"
above). The condition follows the same boolean rule `if`'s does: `false`
skips the body, `true` runs it, and any other value is a `TypeMismatchError`
rather than being coerced.

### The loop budget

`while` compiles to the ISA v6 `jump_backward` opcode (ADR-0013), and
execution of any program containing one is bounded: the evaluator charges a
budget on every back edge taken, shared across every loop in the program, not
per-loop. The default is 10,000 back edges per execution
(`Predicator.Evaluator.default_loop_budget/0`). A caller configures it per
call with the `:loop_budget` option on `evaluate/3`, `execute/3`, and
`execute_value/3`:

```elixir
iex> {:error, error, _ctx} = Predicator.execute("while true { }", %{}, loop_budget: 5)
iex> error.reason
"loop_budget_exceeded"
```

Exhaustion stops execution with `{:error, %Predicator.Errors.EvaluationError{
reason: "loop_budget_exceeded"}, context}` - an error value, never a raise or
a hang (ADR-0004). A budget of `0` forbids back edges entirely, so the very
first `jump_backward` a program takes fails; a malformed value (anything that
is not a non-negative integer) raises `ArgumentError`, the same host-API-misuse
line `:on_unbound` draws.

### Reserved words

`if`, `else`, and `while` are reserved words: none of the three can be used
as a variable name, a bare property name (`user.if`), or a bare object key
(`{if: 1}`) - only a quoted key (`{"if": 1}`) still works.

`undefined` is reserved too, joining `true`/`false` as a literal keyword
rather than the statement keywords above: `undefined = 3`, `user.undefined`,
and `{undefined: 1}` are all parse errors, the same shapes `true`/`false`
produce. A quoted key still works (`{"undefined": 1}` parses), and only the
lowercase spelling is reserved - `UNDEFINED` and `Undefined` stay ordinary
identifiers.

`null` is reserved the same way, as a literal keyword beside `undefined`:
`null = 3`, `user.null`, and `{null: 1}` are all parse errors, the same
shapes `true`/`false`/`undefined` produce. A quoted key still works
(`{"null": 1}` parses), and only the lowercase spelling is reserved - `NULL`
and `Null` stay ordinary identifiers.

## Builtin Functions

### String Functions

| Function | Description | Example |
|----------|-------------|---------|
| `len(string)` | String length | `len(name) > 3` |
| `upper(string)` | Convert to uppercase | `upper(role) == 'ADMIN'` |
| `lower(string)` | Convert to lowercase | `lower(name) == 'alice'` |
| `trim(string)` | Remove surrounding whitespace | `len(trim(input)) > 0` |
| `starts_with(string, prefix)` | Prefix test | `starts_with(email, 'admin')` |
| `ends_with(string, suffix)` | Suffix test | `ends_with(file, '.csv')` |
| `substring(string, start[, len])` | Substring by offset | `substring(code, 0, 3) == 'ABC'` |
| `index_of(string, sub)` | Index of substring, or `-1` | `index_of(path, '/') == 0` |

```elixir
iex> Predicator.evaluate("len('hello')", %{})
{:ok, 5}

iex> Predicator.evaluate("upper('world')", %{})
{:ok, "WORLD"}

iex> Predicator.evaluate("starts_with('hello world', 'hello')", %{})
{:ok, true}

iex> Predicator.evaluate("ends_with('hello world', 'world')", %{})
{:ok, true}

iex> Predicator.evaluate("substring('hello world', 6)", %{})
{:ok, "world"}

iex> Predicator.evaluate("substring('hello world', 0, 5)", %{})
{:ok, "hello"}

iex> Predicator.evaluate("index_of('hello world', 'world')", %{})
{:ok, 6}

iex> Predicator.evaluate("index_of('hello world', 'nope')", %{})
{:ok, -1}
```

### Numeric Functions

| Function | Description | Returns | Example |
|----------|-------------|---------|---------|
| `Math.abs(number)` | Absolute value | same type as the argument | `Math.abs(balance) < 100` |
| `Math.max(a, b)` | Maximum of two numbers | the winning argument, type unchanged | `Math.max(score1, score2) > 85` |
| `Math.min(a, b)` | Minimum of two numbers | the winning argument, type unchanged | `Math.min(age, 65) >= 18` |
| `Math.pow(base, exp)` | Exponentiation | integer when both are integers and `exp >= 0`; float otherwise | `Math.pow(2, 10) == 1024` |
| `Math.sqrt(number)` | Square root | integer for a non-negative integer with an exact root; float otherwise | `Math.sqrt(144) == 12` |
| `Math.floor(number)` | Round down | always an integer | `Math.floor(3.9) == 3` |
| `Math.ceil(number)` | Round up | always an integer | `Math.ceil(3.1) == 4` |
| `Math.round(number)` | Round to nearest integer | always an integer | `Math.round(3.5) == 4` |
| `Math.random()` | Random float in `[0, 1)` | always a float | `Math.random() < 1` |

`===` is type-strict (`8.0 === 8` is `false`), so the return type above is
observable at the language level, not just an implementation detail. `==` is
not type-strict, which is why `Math.pow(2, 10) == 1024` below reads as `true`
either way - it would also have been `true` when `Math.pow` returned `8.0`.
`Math.pow(2, 10) === 1024` demonstrates the strict case: it is `true` because
both arguments are integers and the exponent is non-negative, so `Math.pow`
returns the integer `1024`, not the float `1024.0`.

```elixir
iex> Predicator.evaluate("Math.abs(-5) == 5", %{})
{:ok, true}

iex> Predicator.evaluate("Math.max(1, 2) == 2", %{})
{:ok, true}

iex> Predicator.evaluate("Math.pow(2, 10) == 1024", %{})
{:ok, true}

iex> Predicator.evaluate("Math.pow(2, 10) === 1024", %{})
{:ok, true}
```

### Date Functions

| Function | Description | Example |
|----------|-------------|---------|
| `Date.year(date)` | Extract year | `Date.year(created_at) == 2024` |
| `Date.month(date)` | Extract month | `Date.month(birthday) == 12` |
| `Date.day(date)` | Extract day | `Date.day(deadline) <= 15` |

```elixir
iex> Predicator.evaluate("Date.year(created_at) == 2024", %{"created_at" => ~D[2024-03-15]})
{:ok, true}
```

Numeric and date functions moved under the `Math.` and `Date.` namespaces to
avoid colliding with likely user variable names; the unnamespaced string
functions predate that convention and were left as-is.

### List Functions

| Function | Description | Example |
|----------|-------------|---------|
| `concat(list1, list2)` | Concatenate two lists | `concat([1, 2], [3]) == [1, 2, 3]` |

```elixir
iex> Predicator.evaluate("concat([1, 2], [3])", %{})
{:ok, [1, 2, 3]}
```

`+` concatenates two lists as well (see "What `+` does with mixed operands"
above). On two lists the two are interchangeable; they differ only in what
else each accepts. `+` also joins strings and numbers, which `concat`
rejects with an `EvaluationError`. Neither one mixes a list with a scalar -
`concat([1, 2], 3)` is an `EvaluationError` and `[1, 2] + 3` is a
`TypeMismatchError`, so there is no coercion to fall back to.

## Decompiling and Formatting Options

`Predicator.decompile/2` converts a parsed AST back to source, preserving
quote style, with formatting options:

```elixir
iex> {:ok, ast} = Predicator.parse("score > 85")
iex> Predicator.decompile(ast, spacing: :compact)
"score>85"

iex> {:ok, ast} = Predicator.parse("score > 85")
iex> Predicator.decompile(ast, spacing: :verbose)
"score  >  85"

iex> {:ok, ast} = Predicator.parse("score > 85")
iex> Predicator.decompile(ast, parentheses: :explicit)
"(score > 85)"
```

It renders `if`/`else` too, applying the `else if` printing rule from
above: an `else` block whose sole statement is an `if` prints as `else if`
rather than nesting a new block, which is what makes the natural spelling
round-trip through `parse_program/2` -> `decompile/2` -> `parse_program/2`.

```elixir
iex> {:ok, ast} = Predicator.parse_program("if a { x = 1 } else { if b { x = 2 } }")
iex> Predicator.decompile(ast)
"if a { x = 1 } else if b { x = 2 }"
```

## Contexts and key normalization

`Predicator.Context.new/2` builds a persistent bound context: it resolves the
function dispatch map once, at construction, from builtins, `opts[:providers]`,
and `opts[:functions]` (each later source shadowing an earlier same-named
entry), rather than re-resolving it on every `evaluate/3` call - see the
[custom functions guide](../guides/custom-functions.md) for the provider
mechanism. `bind/3` is an O(1) rebind of a
single key onto that context's data. `assign/3` writes through
`Predicator.ContextLocation.put/3`, the same auto-vivifying algorithm the
[location expressions guide](../guides/location-expressions.md) documents.
`Predicator.evaluate/3` accepts either a `%Context{}` or a bare map - a bare
map gets a one-shot `Context.new/2` internally.

`new/2` and `bind/3` are the one edge where atom keys are accepted. Both
convert **deeply and eagerly** - through nested maps and lists - before
evaluation ever sees the data: an atom key becomes a string key (the string
key wins on collision). A `nil` value is stored verbatim as the null value -
see "Null and undefined" below - and a `Date`, `DateTime`, or any other
struct passes through unchanged; only plain maps have their keys touched.
The evaluator consults string keys only after that point - it has no
atom-key fallback.

Because the function merge happens once at construction rather than per
call, reusing a `Context` across many `evaluate/3` calls (e.g. `bind/3` in a
loop) avoids re-merging the function maps on every evaluation.

## Undefined and Sparse Data

Predicator treats missing data as a first-class value, `:undefined`, rather
than raising immediately. What a predicate does with it depends on where the
`:undefined` came from and which operator touches it next.
`Predicator.Undefined` is the one public module that owns the sentinel -
`value/0`, `undefined?/1`, and `to_nil/1`/`from_nil/1` for a JSON-shaped
boundary - and `Predicator.Types.undefined?/1` delegates to it.

### Where `:undefined` comes from

- **A bare unbound identifier** - a variable not present in the context at
  all - loads as `:undefined`.
- **A missing nested path** - dot access (`user.age`) or bracket access
  (`items[99]`) on a value that does not have the requested key or index -
  also evaluates to `:undefined`, never an error, regardless of whether the
  root itself is bound.

  ```elixir
  iex> Predicator.evaluate("user.age", %{"user" => %{}})
  {:ok, :undefined}
  ```

- **A failed cast** - `expr::type` where `expr`'s value cannot be converted
  to `type` - also evaluates to `:undefined`, never an error. See
  "Type Casts" above for the full conversion matrix.

  ```elixir
  iex> Predicator.evaluate("'abc'::integer", %{})
  {:ok, :undefined}
  ```

- **The `undefined` literal** - written directly in source - compiles to
  `["lit", :undefined]` and evaluates to `:undefined` unconditionally. It is
  the one source in this list that is not a `load`: `lit` pushes its operand
  unchanged and has no error path (`docs/isa.md` §5), so the literal is never
  affected by `on_unbound` - only `load` consults that policy. See "testing
  whether a value is undefined" below for what that makes it useful for.

  ```elixir
  iex> Predicator.evaluate("undefined", %{})
  {:ok, :undefined}
  ```

The first two cases produce the same value in isolation, but they are **not**
treated the same at the top level - see "Unbound roots vs. missing paths"
below.

### Mismatched comparisons

`1 > "a"` is not an error. A type-mismatched pair under a non-strict
comparison operator (`>`, `<`, `>=`, `<=`, `==`, `!=`) evaluates to
`:undefined`:

```elixir
iex> Predicator.evaluate("1 > 'a'", %{})
{:ok, :undefined}
iex> Predicator.evaluate("true == 1", %{})
{:ok, :undefined}
```

`===` and `!==` (strict equal/not-equal) never produce `:undefined` from a
type mismatch: they compare without coercion and simply return `false` or
`true` for two values of different types, `:undefined` included.

Numbers are the one place the two equality families disagree: integer and
float are the *same* type for `==`, so `1 == 1.0` is `true`, while
`1 === 1.0` is `false` because strict equality does not bridge integer and
float.

### AND/OR falsiness

At a jump, only `false` and `:undefined` count as falsy; `true` is the only
truthy value. `AND`/`OR` do not use symmetric three-valued (Kleene) logic -
they short-circuit ECMAScript-style, and the two are deliberately asymmetric:

- **`AND`** evaluates its left operand. If it is falsy (`false` or
  `:undefined`), that value is the result and the right side is never
  evaluated. If the left operand is `true`, the right operand's value is the
  result.
- **`OR`** evaluates its left operand. If it is `true`, that value is the
  result and the right side is never evaluated. If the left is falsy, the
  right operand's value is the result.

```elixir
iex> functions = %{"boom" => {0, fn [], _ctx -> raise "never runs" end}}
iex> Predicator.evaluate("false AND boom()", %{}, functions: functions)
{:ok, false}
iex> Predicator.evaluate("user.missing OR true", %{"user" => %{}})
{:ok, true}
iex> Predicator.evaluate("user.missing AND true", %{"user" => %{}})
{:ok, :undefined}
```

The asymmetry: an `:undefined` left operand short-circuits `AND` to
`:undefined` without touching the right side, while the same `:undefined` on
`OR`'s left falls through and the right side's value wins instead.

`NOT` is different from both: it requires a boolean operand, so `:undefined`
is a type mismatch under `NOT`, not a falsy value - see the table below.

### Reject vs. propagate, per operator

Some operators treat an `:undefined` operand as a value that flows through;
others treat it as a type error.

| Operator family | `:undefined` operand | Result |
|---|---|---|
| Arithmetic (`+`, `-`, `*`, `/`, `%`, unary `-`) | rejected | error (type mismatch) |
| Comparison, non-strict (`>`, `<`, `>=`, `<=`, `==`, `!=`) | propagated | `:undefined` |
| Comparison, strict (`===`, `!==`) | handled, not rejected | ordinary `true`/`false` |
| `AND`, `OR` | propagated, treated as falsy | short-circuits or falls through |
| `NOT` | rejected | error (type mismatch) |
| `in`, `contains` | propagated | `:undefined` |

Dot access, bracket access, and function arguments are not in this table
because they don't reject or propagate an *incoming* `:undefined` the way an
operator does: a missing key or index always produces `:undefined` rather
than erroring (see "Where `:undefined` comes from" above), and a function
receives whatever `:undefined`-or-not value its arguments evaluated to - a
custom function decides for itself what to do with one.

### Testing whether a value is undefined

`x === undefined` is the boundness test, and it answers plainly - `true` or
`false`:

```elixir
iex> Predicator.evaluate("x === undefined", %{"x" => :undefined})
{:ok, true}
iex> Predicator.evaluate("x === undefined", %{"x" => 1})
{:ok, false}
iex> Predicator.evaluate("user.missing === undefined", %{"user" => %{}})
{:ok, true}
```

`x == undefined` is **not** the same test. `==` is a non-strict comparison
operator, and non-strict operators propagate an `:undefined` operand rather
than answering with a boolean (see "Reject vs. propagate, per operator"
above), so `x == undefined` itself evaluates to `:undefined` - which is
falsy at a jump, but not the `true`/`false` a boundness check needs:

```elixir
iex> Predicator.evaluate("x == undefined", %{"x" => 1})
{:ok, :undefined}
```

If `x` is an unbound root rather than a bound value, the two comparisons
diverge under the default `on_unbound: :undefined`. `x === undefined` still
answers `true`: strict equality is resolved before any type dispatch, so it
never produces the `:undefined`-operand `TypeMismatchError` that the
trace-back rewrite keys on (see "Unbound roots vs. missing paths" below).
`x == undefined` does produce one, so it is rewritten to
`Predicator.Errors.UndefinedVariableError` and never reaches a boolean:

```elixir
iex> Predicator.evaluate("x === undefined", %{})
{:ok, true}
iex> {:error, err} = Predicator.evaluate("x == undefined", %{})
iex> err.__struct__
Predicator.Errors.UndefinedVariableError
```

That makes `===` the boundness test for an absent root as well as an
`:undefined` one - but only under this policy. Under `on_unbound: :error`
both comparisons error; see "The honest boundary" below.

The literal itself is never affected by `on_unbound`, under either
comparison operator - it compiles to `lit`, not `load`, and only `load`
consults the policy (see "Where `:undefined` comes from" above).

**The honest boundary.** `x === undefined` on a genuinely unbound root still
errors under `on_unbound: :error` - the boundness test does not rescue it,
because the `load` of `x` fails before the comparison ever runs:

```elixir
iex> {:error, err} = Predicator.evaluate("x === undefined", %{}, on_unbound: :error)
iex> err.variable
"x"
```

To test whether a variable that may not exist at all is undefined under
`:error`, bind it as declared-but-undefined
(`Predicator.Context.new(%{"x" => Predicator.Undefined.value()})`) rather
than leaving it absent - binding `nil` instead gives it the null value, not
`:undefined` (see "Null and undefined" above) - or reach it through a bound
container (`ctx.maybe === undefined`), where a missing nested path evaluates
to `:undefined` under either policy instead of erroring.

### Unbound roots vs. missing paths, and `on_unbound`

Not every `:undefined` stays silent at the top level. `Predicator.evaluate/3`
distinguishes an `:undefined` that traces back to a genuinely unbound root
variable from one that is just a legitimately absent nested value, and
reports the former as an error even without opting into anything:

```elixir
iex> {:error, err} = Predicator.evaluate("missing", %{})
iex> err.variable
"missing"

iex> {:error, err} = Predicator.evaluate("missing == 5", %{})
iex> err.variable
"missing"

iex> {:error, err} = Predicator.evaluate("not missing", %{})
iex> err.variable
"missing"

iex> Predicator.evaluate("user.age", %{"user" => %{}})
{:ok, :undefined}
```

The rule: if the final result is `:undefined`, or an operator rejected an
`:undefined` operand with a type-mismatch error, and that `:undefined`
traces back to a root variable this evaluation actually loaded and did not
find bound, Predicator reports `Predicator.Errors.UndefinedVariableError`
naming that variable instead of the bare `:undefined` or the type-mismatch
error. A missing nested path (`user.age` where `user` has no `age`) never
triggers this - only a bare unbound root does.

Short-circuiting still wins over this rule, and so does an operator that
*absorbs* the `:undefined` into a defined result - neither reports an error:

```elixir
iex> Predicator.evaluate("missing OR true", %{})
{:ok, true}
iex> Predicator.evaluate("false AND missing", %{})
{:ok, false}
iex> Predicator.evaluate("[missing]", %{})
{:ok, [:undefined]}
```

Set `on_unbound: :error` to make every load of an unbound root fail
immediately - including the cases just above, which the default behavior
would have absorbed into a defined result:

```elixir
iex> {:error, err} = Predicator.evaluate("missing OR true", %{}, on_unbound: :error)
iex> err.variable
"missing"
```

`on_unbound` accepts `:undefined` (the default) or `:error`. It is a keyword
option on `Predicator.evaluate/3` and `Predicator.Context.new/2` (which
validates it strictly - any other value raises `ArgumentError`). It only
affects a root `load`: a missing nested path stays `:undefined` under either
policy, since `access` and `bracket_access` never consult `on_unbound` - and
it never fires on a load a short-circuited branch skipped.

What actually changes under `:error` is narrower than it looks, because an
unbound root already errors under the default whenever its `:undefined`
reaches the result or is rejected by an operator. The policy's own cases are
the ones where the default *absorbs* the sentinel into a defined result:

| Expression, empty context | Default | Under `on_unbound: :error` |
|---|---|---|
| `missing OR true` | `{:ok, true}` | `{:error, ...}` |
| `[missing]` | `{:ok, [:undefined]}` | `{:error, ...}` |
| `{'a': missing}` | `{:ok, %{"a" => :undefined}}` | `{:error, ...}` |
| `missing`, `missing == 5`, `not missing`, `missing + 1` | `{:error, ...}` | same |
| `false AND missing`, `true OR missing` | `{:ok, false}` / `{:ok, true}` | unchanged - never loaded |

### Null and undefined

Predicator also has a null value - Elixir `nil` - and it is not the same
thing as `:undefined`. The rule in one sentence: **null is a value;
undefined is an absence.** `:undefined` means no value was ever supplied;
null means a value was supplied and it is empty. A `Context` bound from a
JSON payload keeps the two distinguishable: a field explicitly sent as
`null` stays null, and a field never sent at all stays undefined.

```elixir
iex> Predicator.evaluate("x === undefined", %{"x" => nil})
{:ok, false}
iex> Predicator.evaluate("x === undefined", %{})
{:ok, true}
```

**Comparisons.** Predicator has two equality operators, `==` (non-strict)
and `===` (strict), so "is null equal to undefined" is a four-way question,
not a single answer:

| Comparison | Result |
|---|---|
| `null === undefined` | `false` |
| `null == undefined` | `:undefined` |
| `null === null` | `true` |
| `null == null` | `:undefined` |

```elixir
iex> Predicator.evaluate("x === undefined", %{"x" => nil})
{:ok, false}
iex> Predicator.evaluate("x == undefined", %{"x" => nil})
{:ok, :undefined}
iex> Predicator.evaluate("x === y", %{"x" => nil, "y" => nil})
{:ok, true}
iex> Predicator.evaluate("x == y", %{"x" => nil, "y" => nil})
{:ok, :undefined}
```

`===` is the operator that answers a plain boolean about null, exactly as
it is for `:undefined`: `==` and the ordering operators are typed
comparisons, and null has no type peer, so every non-strict comparison
involving it yields `:undefined` rather than `true` or `false`.

**Membership is the one place null behaves as a value, not an absence.**
`in` and `contains` test identity for null rather than propagating it the
way they propagate `:undefined`:

```elixir
iex> Predicator.evaluate("x in [y]", %{"x" => nil, "y" => nil})
{:ok, true}
```

That is a real surface tension worth naming rather than smoothing over:
`null == null` is `:undefined` while `null in [null]` is `true`. `==` and
`in` already disagreed about `:undefined` in the opposite direction, so the
two operators were never one predicate to begin with.

**Falsiness.** Null is falsy at a jump, joining `false` and `:undefined`,
so `AND`/`OR` short-circuit over it the same way:

```elixir
iex> Predicator.evaluate("x AND true", %{"x" => nil})
{:ok, nil}
```

**Rejected, not coerced.** `NOT`, unary minus, and the arithmetic operators
require their usual types and treat a null operand as a type mismatch, the
same as they treat `:undefined`:

```elixir
iex> {:error, err} = Predicator.evaluate("not x", %{"x" => nil})
iex> {err.__struct__, err.got}
{Predicator.Errors.TypeMismatchError, :null}
```

**Casts.** A cast is total, so `null::T` is `:undefined` for every target
type - not `"null"`, not an error:

```elixir
iex> Predicator.evaluate("x::string", %{"x" => nil})
{:ok, :undefined}
```

**`null` is a literal keyword.** `x === null` is the direct boundness-against-
null test: it asks whether `x` is bound to the present-but-empty value.
`x === undefined` remains the separate question of whether anything was
bound at all - the two are not restatements of each other, and give
different answers for the same bound null:

```elixir
iex> Predicator.evaluate("x === undefined", %{"x" => nil})
{:ok, false}
```

null and undefined are distinct values with their own comparison,
membership, falsiness, and cast behavior, all shown above. Writing `null`
compiles it straight to a `lit` operand, never a `load`, so there is no
phantom variable and no dependence on `on_unbound`:

```elixir
iex> Predicator.compile("x === null")
{:ok, [["load", "x"], ["lit", nil], ["compare", "STRICT_EQ"]]}
iex> Predicator.evaluate("x === null", %{"x" => nil})
{:ok, true}
```

Being a literal keyword, `null` is reserved the same way `undefined` is (see
"Reserved words" above): `{null: 1}` is a parse error, not an object with a
key named `null`.

```elixir
iex> {:error, err} = Predicator.evaluate("{null: 1}", %{})
iex> err.__struct__
Predicator.Errors.ParseError
```

## Error Shapes

Predicator returns errors as structs under `Predicator.Errors`, never as bare
strings, and never raises at a leaf:

```elixir
iex> {:error, err} = Predicator.evaluate("score >> 85", %{})
iex> {err.__struct__, err.position}
{Predicator.Errors.ParseError, {1, 8}}
iex> err.message
"Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found '>'"

iex> {:error, err} = Predicator.evaluate("score AND", %{})
iex> err.position
{1, 10}
```

A compile failure returns the same struct, since `compile/1` and its five
siblings share `evaluate/3`'s error arm:

```elixir
iex> {:error, err} = Predicator.compile("score >>")
iex> {err.__struct__, err.position}
{Predicator.Errors.ParseError, {1, 8}}
```

A function that errors mid-evaluation surfaces as an `EvaluationError`:

```elixir
iex> custom_functions = %{"divide" => {2, fn [a, b], _ctx ->
...>   if b == 0, do: {:error, "Division by zero"}, else: {:ok, a / b}
...> end}}
iex> {:error, err} = Predicator.evaluate("divide(10, 0)", %{}, functions: custom_functions)
iex> {err.__struct__, err.message}
{Predicator.Errors.EvaluationError, "Division by zero"}
```

See the [location expressions guide](../guides/location-expressions.md) for
`Predicator.Errors.LocationError`, the third error struct.

### Positions and spans on errors

`EvaluationError`, `TypeMismatchError`, and `UndefinedVariableError` each
carry an optional `:position` and an optional `:span`. Under the default
options only `:position` is set; passing `spans: true` to `evaluate/3` also
sets `:span`, and in that case `:position` is set to the span's start, so a
caller that only ever reads `:position` keeps working unchanged. The
rendered `message` string is the same either way. See
`docs/reference/ast.md` for what a span covers.

An unbound variable's error is positioned at the *variable's own* load, not
at the operator that rejected its `:undefined` value:

```elixir
iex> {:error, err} = Predicator.evaluate("unbound + 1", %{})
iex> err.position
{1, 1}
```

`{1, 1}` is the position of `unbound`, not of `+`.
