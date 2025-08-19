# Predicator

A secure, non-evaluative condition engine for processing end-user boolean predicates in Elixir. Predicator allows you to safely evaluate user-defined expressions without the security risks of dynamic code execution.

## Features

- 🔒 **Secure**: No `eval()` or dynamic code execution - safe for end-user input
- 🎯 **Simple**: Clean, intuitive expression syntax (`score > 85`, `name = "John"`)
- 🚀 **Fast**: Compiled expressions execute efficiently with minimal overhead
- 🛡️ **Type Safe**: Built with comprehensive specs and rigorous testing
- 🎨 **Flexible**: Support for literals, identifiers, comparisons, and parentheses
- 📊 **Observable**: Detailed error reporting with line/column information
- 🔄 **Reversible**: Convert AST back to string expressions with formatting options

## Quick Start

```elixir
# Basic evaluation
iex> Predicator.evaluate("score > 85", %{"score" => 92})
{:ok, true}

# String comparisons  
iex> Predicator.evaluate("name = \"Alice\"", %{"name" => "Alice"})
{:ok, true}

# Complex expressions with parentheses
iex> Predicator.evaluate("(age >= 18) = true", %{"age" => 25})
{:ok, true}

# Logical operators
iex> Predicator.evaluate("score > 85 AND age >= 18", %{"score" => 92, "age" => 25})
{:ok, true}

iex> Predicator.evaluate("role = \"admin\" OR role = \"manager\"", %{"role" => "admin"})  
{:ok, true}

iex> Predicator.evaluate("NOT expired = true", %{"expired" => false})
{:ok, true}

# Compile once, evaluate many times
iex> {:ok, instructions} = Predicator.compile("score > threshold")
iex> Predicator.evaluate(instructions, %{"score" => 95, "threshold" => 80})
{:ok, true}

# Decompile AST back to expressions
iex> {:ok, ast} = Predicator.parse("score > 85")
iex> Predicator.decompile(ast)
"score > 85"
```

## Supported Operations

| Operator | Description | Example |
|----------|-------------|---------|
| `>`      | Greater than | `score > 85` |
| `<`      | Less than | `age < 30` |
| `>=`     | Greater than or equal | `points >= 100` |
| `<=`     | Less than or equal | `count <= 5` |
| `=`      | Equal | `status = "active"` |
| `!=`     | Not equal | `role != "guest"` |
| `AND`    | Logical AND | `score > 85 AND age >= 18` |
| `OR`     | Logical OR | `role = "admin" OR role = "manager"` |
| `NOT`    | Logical NOT | `NOT expired = true` |

## Data Types

- **Numbers**: `42`, `3.14` (parsed as integers or floats)
- **Strings**: `"hello"`, `"world"` (double-quoted)
- **Booleans**: `true`, `false`
- **Identifiers**: `score`, `user_name`, `is_active`

## Architecture

Predicator uses a multi-stage compilation pipeline:

```
Expression String → Lexer → Parser → Compiler → Instructions
     ↓              ↓        ↓         ↓           ↓
"score > 85 AND age >= 18" → Tokens → AST → Instructions → Evaluation
```

### Core Components

- **Lexer** (`Predicator.Lexer`): Tokenizes input with position tracking
- **Parser** (`Predicator.Parser`): Builds Abstract Syntax Tree with error reporting  
- **Compiler** (`Predicator.Compiler`): Converts AST to executable instructions
- **Evaluator** (`Predicator.Evaluator`): Executes instructions against data
- **StringVisitor** (`Predicator.StringVisitor`): Converts AST back to expressions

## Error Handling

Predicator provides detailed error information with exact positioning:

```elixir
iex> Predicator.evaluate("score >> 85", %{})
{:error, "Unexpected character '>' at line 1, column 8"}

iex> Predicator.evaluate("score AND", %{})
{:error, "Expected number, string, boolean, identifier, or '(' but found end of input at line 1, column 1"}
```

## Advanced Usage

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

### Performance

For repeated evaluations with the same expression:

```elixir
# Compile once
{:ok, instructions} = Predicator.compile("score > threshold")

# Evaluate many times
results = 
  data_list
  |> Enum.map(&Predicator.evaluate(instructions, &1))
  |> Enum.map(fn {:ok, result} -> result end)
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

### Test Coverage

Current coverage: **93.7%** overall, **96.2%** on core components.

```bash
mix test.coverage.html  # Generate HTML coverage report
```

## Installation

Add `predicator` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:predicator, "~> 1.0.0"}
  ]
end
```

## Documentation

Full documentation is available at [HexDocs](https://hexdocs.pm/predicator).

