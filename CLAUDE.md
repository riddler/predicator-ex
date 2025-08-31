# Claude Code Development Context

This document provides context for Claude Code when working on the Predicator project.

## Project Overview

Predicator is a secure, non-evaluative condition engine for processing end-user boolean predicates in Elixir. It provides a complete compilation pipeline from string expressions to executable instructions without the security risks of dynamic code execution. Supports arithmetic operators (+, -, *, /, %) with proper precedence, comparison operators (>, <, >=, <=, =, !=), logical operators (AND, OR, NOT), date/datetime literals, list literals, object literals with JavaScript-style syntax, membership operators (in, contains), function calls with built-in system functions, nested data structure access using dot notation, and bracket access for dynamic property and array access.

## Architecture

```
Expression String → Lexer → Parser → Compiler → Instructions → Evaluator
                                    ↓
                              StringVisitor (decompile)
```

### Grammar with Operator Precedence

```
expression   → logical_or
logical_or   → logical_and ( ("OR" | "or") logical_and )*
logical_and  → logical_not ( ("AND" | "and") logical_not )*
logical_not  → ("NOT" | "not") logical_not | comparison
comparison   → addition ( ( ">" | "<" | ">=" | "<=" | "=" | "==" | "!=" | "in" | "contains" ) addition )?
addition     → multiplication ( ( "+" | "-" ) multiplication )*
multiplication → unary ( ( "*" | "/" | "%" ) unary )*
unary        → ( "-" | "!" ) unary | postfix
postfix      → primary ( "[" expression "]" | "." IDENTIFIER )*
primary      → NUMBER | FLOAT | STRING | BOOLEAN | DATE | DATETIME | IDENTIFIER | list | object | function_call | "(" expression ")"
function_call → IDENTIFIER "(" ( expression ( "," expression )* )? ")"
list         → "[" ( expression ( "," expression )* )? "]"
object       → "{" ( object_entry ( "," object_entry )* )? "}"
object_entry → object_key ":" expression
object_key   → IDENTIFIER | STRING
```

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

## Development

### Development Workflow

After implementing a new set of functionality

- ensure the local project is not on the main branch
- identify all code issues by running 'mix quality'
- fix those issues
- if necessary update the CHANGELOG, README and CLAUDE documents
- prompt me if I would like to create a git commit
- if so, create a git commit with title and message

### Testing Commands

```bash
mix test                    # Run all tests
mix test --watch           # Watch mode  
mix test.coverage          # Coverage report
mix test.coverage.html     # HTML coverage report
```

### Code Quality Commands

```bash
mix quality                # Run all quality checks (format, credo, coverage, dialyzer)
mix quality.check          # Check quality without fixing
mix format                 # Format code
mix credo --strict         # Lint with strict mode
mix dialyzer              # Type checking
```

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

```
lib/predicator/
├── lexer.ex           # Tokenization with position tracking
├── parser.ex          # Recursive descent parser  
├── compiler.ex        # AST to instructions conversion
├── evaluator.ex       # Instruction execution engine with custom function support
├── visitor.ex         # Visitor behavior definition
├── types.ex           # Type specifications
├── application.ex     # OTP application (simplified - no registry init)
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
  - **String functions**: `len(string)`, `upper(string)`, `lower(string)`, `trim(string)`
  - **Numeric functions**: `abs(number)`, `max(a, b)`, `min(a, b)`
  - **Date functions**: `year(date)`, `month(date)`, `day(date)`
- **Custom Functions**: Provided per evaluation via `functions:` option in `evaluate/3`
- **Function Format**: `%{name => {arity, function}}` where function takes `[args], context` and returns `{:ok, result}` or `{:error, message}`
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

### List Literals and Membership

- **Syntax**: `[1, 2, 3]`, `["admin", "manager"]`
- **Operators**: `in` (element in list), `contains` (list contains element)
- **Examples**: `role in ["admin", "manager"]`, `[1, 2, 3] contains 2`

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
- **API Function**: `Predicator.context_location/3` - resolves location paths for assignment targets
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
7. Add comprehensive tests

### Adding New Data Types

1. Update lexer tokenization (see date implementation)
2. Update parser grammar and AST types
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

- Elixir ~> 1.11 required
- All dependencies in development/test only
- No runtime dependencies for core functionality
