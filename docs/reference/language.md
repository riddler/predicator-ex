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
| `/`      | Division (integer) | `total / count`, `10 / 3` |
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
