# Predicator

[![CI](https://github.com/riddler/predicator-ex/actions/workflows/ci.yml/badge.svg)](https://github.com/riddler/predicator-ex/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/riddler/predicator-ex/branch/main/graph/badge.svg)](https://codecov.io/gh/riddler/predicator-ex)
[![Hex.pm Version](https://img.shields.io/hexpm/v/predicator.svg)](https://hex.pm/packages/predicator)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/predicator/)

A secure, non-evaluative condition engine for processing end-user boolean predicates in Elixir.
Predicator allows you to safely evaluate user-defined expressions without the security risks of dynamic code execution.

## Features

- 🔒 **Secure**: No `eval()` or dynamic code execution - safe for end-user input
- 🎯 **Simple**: Clean, intuitive expression syntax (`score > 85`, `name = 'John'`)
- 🚀 **Fast**: Compiled expressions execute efficiently with minimal overhead
- 🛡️ **Type Safe**: Built with comprehensive specs and rigorous testing
- 🎨 **Flexible**: Support for literals, identifiers, comparisons, and parentheses
- 📊 **Observable**: Detailed error reporting with line/column information
- 🔄 **Reversible**: Convert AST back to string expressions with formatting options
- 🧮 **Arithmetic**: Full arithmetic operations (`+`, `-`, `*`, `/`, `%`) with proper precedence
- 📅 **Date Support**: Native date and datetime literals with ISO 8601 format
- 📋 **Lists**: List literals with membership operations (`in`, `contains`)
- 🧠 **Smart Logic**: Logical operators with proper precedence (`AND`, `OR`, `NOT`)
- 🔧 **Functions**: Built-in functions for string, numeric, and date operations
- 🌳 **Nested Access**: Dot notation and bracket access for deep data structures (`user.profile.name`, `user['profile']['name']`, `items[0]`)

## Installation

Add `predicator` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:predicator, "~> 2.2"}
  ]
end
```
## Quick Start

```elixir
# Basic evaluation
iex> Predicator.evaluate!("score > 85", %{"score" => 92})
true

# String comparisons (double or single quotes)
iex> Predicator.evaluate!("name = 'Alice'", %{"name" => "Alice"})
true

iex> Predicator.evaluate!("name = \"Alice\"", %{"name" => "Alice"})
true

# Date and datetime literals
iex> Predicator.evaluate!("#2024-01-15# > #2024-01-10#", %{})
true

iex> Predicator.evaluate!("created_at < #2024-01-15T10:30:00Z#", %{"created_at" => ~U[2024-01-10 09:00:00Z]})
true

# List literals and membership
iex> Predicator.evaluate!("role in ['admin', 'manager']", %{"role" => "admin"})
true

iex> Predicator.evaluate!("[1, 2, 3] contains 2", %{})
true

# Arithmetic operations with proper precedence
iex> Predicator.evaluate!("2 + 3 * 4", %{})
14

iex> Predicator.evaluate!("(10 - 5) * 2", %{})
10

iex> Predicator.evaluate!("score + bonus > 100", %{"score" => 85, "bonus" => 20})
true

iex> Predicator.evaluate!("-amount > -50", %{"amount" => 30})
true

# Logical operators with proper precedence
iex> Predicator.evaluate!("score > 85 AND age >= 18", %{"score" => 92, "age" => 25})
true

iex> Predicator.evaluate!("role = 'admin' OR role = 'manager'", %{"role" => "admin"})  
true

iex> Predicator.evaluate!("NOT expired AND active", %{"expired" => false, "active" => true})
true

# Complex expressions with parentheses
iex> Predicator.evaluate!("(score > 85 OR admin) AND active", %{"score" => 80, "admin" => true, "active" => true})
true

# Built-in functions
iex> Predicator.evaluate!("len(name) > 3", %{"name" => "Alice"})
true

iex> Predicator.evaluate!("upper(role) = 'ADMIN'", %{"role" => "admin"})
true

iex> Predicator.evaluate!("year(created_at) = 2024", %{"created_at" => ~D[2024-03-15]})
true

# Compile once, evaluate many times for performance
iex> {:ok, instructions} = Predicator.compile("score > threshold AND active")
iex> Predicator.evaluate!(instructions, %{"score" => 95, "threshold" => 80, "active" => true})
true

# Using evaluate/2 (returns {:ok, result} or {:error, message})
iex> Predicator.evaluate("score > 85", %{"score" => 92})
{:ok, true}

iex> Predicator.evaluate("invalid >> syntax", %{})
{:error, "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found '>' at line 1, column 10"}

# Using evaluate/1 for expressions without context (strings or instruction lists)
iex> Predicator.evaluate("#2024-01-15# > #2024-01-10#")
{:ok, true}

iex> Predicator.evaluate([["lit", 42]])
{:ok, 42}

# Round-trip: parse and decompile expressions (preserves quote style)
iex> {:ok, ast} = Predicator.parse("name = 'John'")
iex> Predicator.decompile(ast)
"name = 'John'"

iex> {:ok, ast} = Predicator.parse("score > 85 AND #2024-01-15# in dates")
iex> Predicator.decompile(ast)
"score > 85 AND #2024-01-15# IN dates"
```

## Nested Data Access

Predicator supports nested data structure access using both dot notation and bracket notation, allowing you to reference deeply nested values in your context:

```elixir
# Context with nested data structures
context = %{
  "user" => %{
    "age" => 47,
    "name" => %{"first" => "John", "last" => "Doe"},
    "profile" => %{"role" => "admin"},
    "settings" => %{"theme" => "dark", "notifications" => true}
  },
  "config" => %{
    "database" => %{"host" => "localhost", "port" => 5432}
  },
  "items" => ["apple", "banana", "cherry"],
  "scores" => [85, 92, 78, 96]
}

# Access nested values with dot notation
iex> Predicator.evaluate("user.name.first = 'John'", context)
{:ok, true}

iex> Predicator.evaluate("user.age > 18", context)
{:ok, true}

iex> Predicator.evaluate("config.database.port = 5432", context)
{:ok, true}

# Access with bracket notation
iex> Predicator.evaluate("user['name']['first'] = 'John'", context)
{:ok, true}

iex> Predicator.evaluate("user['settings']['theme'] = 'dark'", context)
{:ok, true}

# Array access with bracket notation
iex> Predicator.evaluate("items[0] = 'apple'", context)
{:ok, true}

iex> Predicator.evaluate("scores[1] > 90", context)
{:ok, true}

# Mixed notation styles
iex> Predicator.evaluate("user.settings['theme'] = 'dark'", context)
{:ok, true}

iex> Predicator.evaluate("user['profile'].role = 'admin'", context)
{:ok, true}

# Dynamic array access
iex> Predicator.evaluate("scores[index] > 80", Map.put(context, "index", 2))
{:ok, false}

# Chained bracket access
iex> Predicator.evaluate("user['name']['first'] + ' ' + user['name']['last']", context)
{:ok, "John Doe"}

# Use in complex expressions
iex> Predicator.evaluate("user.profile.role = 'admin' AND user.settings.notifications", context)
{:ok, true}

# Missing paths return :undefined
iex> Predicator.evaluate("user.profile.email = 'test'", context)
{:ok, :undefined}

# Works with both string and atom keys
atom_context = %{user: %{name: %{first: "Jane"}}}
iex> Predicator.evaluate("user.name.first = 'Jane'", atom_context)
{:ok, true}

# Access nested lists
list_context = %{"user" => %{"hobbies" => ["reading", "coding"]}}
iex> Predicator.evaluate("'coding' in user.hobbies", list_context)
{:ok, true}
```

### Key Features:
- **Dot notation**: `user.profile.name` for nested object access
- **Bracket notation**: `user['profile']['name']` for dynamic key access  
- **Array indexing**: `items[0]`, `scores[index]` for list access
- **Mixed styles**: `user.settings['theme']` combining both notations
- **Unlimited nesting depth**: `app.database.config.settings.ssl`
- **Mixed key types**: Works with string keys, atom keys, or both
- **Graceful fallback**: Returns `:undefined` for missing paths or out-of-bounds access
- **Type preservation**: Maintains original data types (strings, numbers, booleans, lists)
- **Backwards compatible**: Simple variable names work exactly as before

## Supported Operations

### Arithmetic Operators
| Operator | Description | Example |
|----------|-------------|---------|
| `+`      | Addition | `score + bonus`, `2 + 3 * 4` |
| `-`      | Subtraction | `total - discount`, `100 - 25` |
| `*`      | Multiplication | `price * quantity`, `3 * 4` |
| `/`      | Division (integer) | `total / count`, `10 / 3` |
| `%`      | Modulo | `id % 2`, `17 % 5` |
| `-`      | Unary minus | `-amount`, `-(x + y)` |

### Comparison Operators
| Operator | Description | Example |
|----------|-------------|---------|
| `>`      | Greater than | `score > 85`, `#2024-01-15# > #2024-01-10#` |
| `<`      | Less than | `age < 30`, `created_at < #2024-01-15T10:00:00Z#` |
| `>=`     | Greater than or equal | `points >= 100` |
| `<=`     | Less than or equal | `count <= 5` |
| `=`      | Equal | `status = 'active'`, `date = #2024-01-15#` |
| `!=`     | Not equal | `role != 'guest'` |

### Logical Operators
| Operator | Description | Example |
|----------|-------------|---------|
| `AND`    | Logical AND (case-insensitive) | `score > 85 AND age >= 18` |
| `OR`     | Logical OR (case-insensitive) | `role = 'admin' OR role = 'manager'` |
| `NOT`    | Logical NOT (case-insensitive) | `NOT expired` |

### Membership Operators
| Operator | Description | Example |
|----------|-------------|---------|
| `in`     | Element in collection | `role in ['admin', 'manager']` |
| `contains` | Collection contains element | `[1, 2, 3] contains 2` |

### Built-in Functions

#### String Functions
| Function | Description | Example |
|----------|-------------|---------|
| `len(string)` | String length | `len(name) > 3` |
| `upper(string)` | Convert to uppercase | `upper(role) = 'ADMIN'` |
| `lower(string)` | Convert to lowercase | `lower(name) = 'alice'` |
| `trim(string)` | Remove whitespace | `len(trim(input)) > 0` |

#### Numeric Functions  
| Function | Description | Example |
|----------|-------------|---------|
| `abs(number)` | Absolute value | `abs(balance) < 100` |
| `max(a, b)` | Maximum of two numbers | `max(score1, score2) > 85` |
| `min(a, b)` | Minimum of two numbers | `min(age, 65) >= 18` |

#### Date Functions
| Function | Description | Example |
|----------|-------------|---------|
| `year(date)` | Extract year | `year(created_at) = 2024` |
| `month(date)` | Extract month | `month(birthday) = 12` |
| `day(date)` | Extract day | `day(deadline) <= 15` |

## Data Types

- **Numbers**: `42`, `-17` (integers)
- **Strings**: `'hello'`, `'world'` (single-quoted) or `"hello"`, `"world"` (double-quoted, with escape sequences)
- **Booleans**: `true`, `false` (or plain identifiers like `active`, `expired`)
- **Dates**: `#2024-01-15#` (ISO 8601 date format)
- **DateTimes**: `#2024-01-15T10:30:00Z#` (ISO 8601 datetime format with timezone)
- **Lists**: `[1, 2, 3]`, `['admin', 'manager']` (homogeneous collections)
- **Identifiers**: `score`, `user_name`, `is_active`, `user.profile.name`, `user['key']`, `items[0]` (variable references with dot notation and bracket notation for nested data)

## Architecture

Predicator uses a multi-stage compilation pipeline:

```
  Expression String  →  Lexer → Parser → Compiler → Evaluator
         ↓                ↓       ↓         ↓           ↓
'score > 85 OR admin' → Tokens → AST → Instructions → Result
```

### Grammar

```ebnf
expression   → logical_or
logical_or   → logical_and ( ("OR" | "or") logical_and )*
logical_and  → logical_not ( ("AND" | "and") logical_not )*
logical_not  → ("NOT" | "not") logical_not | equality
equality     → comparison ( ("==" | "!=") comparison )*
comparison   → addition ( ( ">" | "<" | ">=" | "<=" | "=" | "!=" | "in" | "contains" ) addition )?
addition     → multiplication ( ( "+" | "-" ) multiplication )*
multiplication → unary ( ( "*" | "/" | "%" ) unary )*
unary        → ( "-" | "!" ) unary | postfix
postfix      → primary ( "[" expression "]" )*
primary      → NUMBER | STRING | BOOLEAN | DATE | DATETIME | IDENTIFIER | function_call | list | "(" expression ")"
function_call → FUNCTION_NAME "(" ( expression ( "," expression )* )? ")"
list         → "[" ( expression ( "," expression )* )? "]"
```

### Core Components

- **Lexer** (`Predicator.Lexer`): Tokenizes input with position tracking
- **Parser** (`Predicator.Parser`): Builds Abstract Syntax Tree with error reporting  
- **Compiler** (`Predicator.Compiler`): Converts AST to executable instructions
- **Evaluator** (`Predicator.Evaluator`): Executes instructions against data
- **Visitors**: AST transformation modules
  - **StringVisitor** (`Predicator.Visitors.StringVisitor`): Converts AST back to expressions
  - **InstructionsVisitor** (`Predicator.Visitors.InstructionsVisitor`): Converts AST to instructions
- **Functions**: Function system components
  - **SystemFunctions** (`Predicator.Functions.SystemFunctions`): Built-in system functions
  - **Registry** (`Predicator.Functions.Registry`): Function registration and dispatch

## Error Handling

Predicator provides detailed error information with exact positioning:

```elixir
iex> Predicator.evaluate("score >> 85", %{})
{:error, "Unexpected character '>' at line 1, column 8"}

iex> Predicator.evaluate("score AND", %{})
{:error, "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found end of input at line 1, column 1"}
```

## Advanced Usage

### Custom Functions

You can provide custom functions when evaluating expressions using the `functions:` option:

```elixir
# Define custom functions in a map
custom_functions = %{
  "double" => {1, fn [n], _context -> {:ok, n * 2} end},
  "user_role" => {0, fn [], context -> 
    {:ok, Map.get(context, "current_user_role", "guest")} 
  end},
  "divide" => {2, fn [a, b], _context ->
    if b == 0 do
      {:error, "Division by zero"}
    else
      {:ok, a / b}
    end
  end}
}

# Use custom functions in expressions
iex> Predicator.evaluate("double(score) > 100", %{"score" => 60}, functions: custom_functions)
{:ok, true}

iex> Predicator.evaluate("user_role() = 'admin'", %{"current_user_role" => "admin"}, functions: custom_functions)
{:ok, true}

iex> Predicator.evaluate("divide(10, 2) = 5", %{}, functions: custom_functions)
{:ok, true}

iex> Predicator.evaluate("divide(10, 0)", %{}, functions: custom_functions)
{:error, "Division by zero"}

# Custom functions can override built-in functions
override_functions = %{
  "len" => {1, fn [_], _context -> {:ok, "custom_result"} end}
}

iex> Predicator.evaluate("len('anything')", %{}, functions: override_functions)
{:ok, "custom_result"}

# Without custom functions, built-ins work as expected
iex> Predicator.evaluate("len('hello')", %{})
{:ok, 5}
```

#### Function Format

Custom functions must follow this format:
- **Map Key**: Function name (string)
- **Map Value**: `{arity, function}` tuple where:
  - `arity`: Number of arguments the function expects (integer)
  - `function`: Anonymous function that takes `[args], context` and returns `{:ok, result}` or `{:error, message}`

### String Formatting Options

The StringVisitor supports multiple formatting modes:

```elixir
# Compact formatting (no spaces)
iex> Predicator.decompile(ast, spacing: :compact)
"score>85"

# Verbose formatting (extra spaces)  
iex> Predicator.decompile(ast, spacing: :verbose)
"score  >  85"

# Explicit parentheses
iex> Predicator.decompile(ast, parentheses: :explicit)
"(score > 85)"
```

## Development

### Setup

```bash
mix deps.get
mix test
```

### Quality Checks

```bash
# Run all quality checks
mix quality

# Individual checks  
mix format              # Format code
mix credo --strict     # Linting
mix coveralls          # Test coverage  
mix dialyzer           # Type checking
```

## Documentation

Full documentation is available at [HexDocs](https://hexdocs.pm/predicator).

