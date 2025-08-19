# Claude Code Development Context

This document provides context for Claude Code when working on the Predicator project.

## Project Overview

Predicator is a secure, non-evaluative condition engine for processing end-user boolean predicates in Elixir. It provides a complete compilation pipeline from string expressions to executable instructions without the security risks of dynamic code execution. Supports comparison operators (>, <, >=, <=, =, !=), logical operators (AND, OR, NOT) with proper precedence, date/datetime literals, list literals, membership operators (in, contains), and function calls with built-in system functions.

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
comparison   → primary ( ( ">" | "<" | ">=" | "<=" | "=" | "!=" | "in" | "contains" ) primary )?
primary      → NUMBER | STRING | BOOLEAN | DATE | DATETIME | IDENTIFIER | list | function_call | "(" expression ")"
function_call → IDENTIFIER "(" ( expression ( "," expression )* )? ")"
list         → "[" ( expression ( "," expression )* )? "]"
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
  - **SystemFunctions**: Built-in system functions (len, upper, abs, max, etc.)
  - **Registry**: Custom function registration and dispatch
- **Main API** (`lib/predicator.ex`): Public interface with convenience functions

## Development Commands

### Testing
```bash
mix test                    # Run all tests
mix test --watch           # Watch mode  
mix test.coverage          # Coverage report
mix test.coverage.html     # HTML coverage report
```

### Code Quality
```bash
mix quality                # Run all quality checks (format, credo, coverage, dialyzer)
mix quality.check          # Check quality without fixing
mix format                 # Format code
mix credo --strict         # Lint with strict mode
mix dialyzer              # Type checking
```

### Coverage Stats
- **Overall**: 92.6%
- **Lexer**: 100% (date/datetime tokenization)
- **Types**: 100% (date type checking)
- **Evaluator**: 90.1% (all operations and errors)
- **Parser**: 86.8% (complex expressions) 
- **StringVisitor**: 94.8% (formatting)
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
├── evaluator.ex       # Instruction execution engine
├── visitor.ex         # Visitor behavior definition
├── types.ex           # Type specifications
├── application.ex     # OTP application
├── functions/         # Function system components
│   ├── system_functions.ex  # Built-in functions (len, upper, abs, etc.)
│   └── registry.ex          # Function registration and dispatch
└── visitors/          # AST transformation modules
    ├── string_visitor.ex      # AST to string decompilation  
    └── instructions_visitor.ex # AST to instructions conversion

test/predicator/
├── lexer_test.exs
├── parser_test.exs  
├── compiler_test.exs
├── evaluator_test.exs
├── predicator_test.exs        # Integration tests
├── functions/                 # Function system tests
│   ├── system_functions_test.exs
│   └── registry_test.exs
└── visitors/                  # Visitor tests
    ├── string_visitor_test.exs
    └── instructions_visitor_test.exs
```

## Recent Additions (2025)

### Function Call System
- **Built-in Functions**: System functions automatically available
  - **String functions**: `len(string)`, `upper(string)`, `lower(string)`, `trim(string)`
  - **Numeric functions**: `abs(number)`, `max(a, b)`, `min(a, b)`
  - **Date functions**: `year(date)`, `month(date)`, `day(date)`
- **Custom Functions**: Register anonymous functions with `Predicator.register_function/3`
- **Function Registry**: ETS-based registry with arity validation and error handling
- **Examples**: 
  - `len(name) > 5` 
  - `upper(status) = "ACTIVE"`
  - `year(created_date) = 2024`
  - `max(score1, score2) > 85`

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

### Logical Operator Enhancements
- **Case-insensitive**: Both `AND`/`and`, `OR`/`or`, `NOT`/`not` supported
- **Pattern matching**: Refactored evaluator and parser to use pattern matching over case statements
- **Plain boolean expressions**: Support for `active`, `expired` without `= true`

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
- **Current Test Count**: 428 tests (64 doctests + 364 regular tests)
- **Coverage**: 92.6% overall, 100% on critical components

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