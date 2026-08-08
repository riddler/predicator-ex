# Language Reference

The complete Predicator expression language: data types, operators, builtin
functions, decompile formatting, and error shapes. For the grammar with
precedence, see [Architecture](../architecture.md).

## Data Types

- **Numbers**: `42`, `-17` (integers), `3.14`, `-2.5` (floats)
- **Strings**: `'hello'`, `'world'` (single-quoted) or `"hello"`, `"world"`
  (double-quoted, with escape sequences)
- **Booleans**: `true`, `false` (or plain identifiers like `active`, `expired`)
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
| `=`      | Equal - **deprecated**, use `==` | `status = 'active'` |

> **Deprecated: `=` as equality.** Using `=` for equality still works and
> still compiles to `["compare", "EQ"]`, but parsing one emits a deprecation
> warning. **Predicator 4.0 makes expression-position `=` a parse error** -
> `=` is being reserved for assignment in the forthcoming statement grammar.
> Migrate to `==` before upgrading. Silence the warning with
> `config :predicator, deprecation_warnings: false`. See
> [ADR-0002](../adr/0002-the-equals-grammar-break.md) for the reasoning.

## Logical Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `AND`    | Logical AND (case-insensitive) | `score > 85 AND age >= 18` |
| `OR`     | Logical OR (case-insensitive) | `role == 'admin' OR role == 'manager'` |
| `NOT`    | Logical NOT (case-insensitive) | `NOT expired` |

## Membership Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `in`     | Element in collection | `role in ['admin', 'manager']` |
| `contains` | Collection contains element | `[1, 2, 3] contains 2` |

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

| Function | Description | Example |
|----------|-------------|---------|
| `Math.abs(number)` | Absolute value | `Math.abs(balance) < 100` |
| `Math.max(a, b)` | Maximum of two numbers | `Math.max(score1, score2) > 85` |
| `Math.min(a, b)` | Minimum of two numbers | `Math.min(age, 65) >= 18` |
| `Math.pow(base, exp)` | Exponentiation | `Math.pow(2, 10) == 1024` |
| `Math.sqrt(number)` | Square root | `Math.sqrt(144) == 12` |
| `Math.floor(number)` | Round down | `Math.floor(3.9) == 3` |
| `Math.ceil(number)` | Round up | `Math.ceil(3.1) == 4` |
| `Math.round(number)` | Round to nearest integer | `Math.round(3.5) == 4` |

```elixir
iex> Predicator.evaluate("Math.abs(-5) == 5", %{})
{:ok, true}

iex> Predicator.evaluate("Math.max(1, 2) == 2", %{})
{:ok, true}

iex> Predicator.evaluate("Math.pow(2, 10) == 1024", %{})
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

## Undefined and Sparse Data

Predicator treats missing data as a first-class value, `:undefined`, rather
than raising immediately. What a predicate does with it depends on where the
`:undefined` came from and which operator touches it next.

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

Both cases produce the same value in isolation, but they are **not** treated
the same at the top level - see "Unbound roots vs. missing paths" below.

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
