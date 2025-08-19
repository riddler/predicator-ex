# Claude Code Development Context

This document provides context for Claude Code when working on the Predicator project.

## Project Overview

Predicator is a secure, non-evaluative condition engine for processing end-user boolean predicates in Elixir. It provides a complete compilation pipeline from string expressions to executable instructions without the security risks of dynamic code execution.

## Architecture

```
Expression String → Lexer → Parser → Compiler → Instructions → Evaluator
                                    ↓
                              StringVisitor (decompile)
```

### Core Components

- **Lexer** (`lib/predicator/lexer.ex`): Tokenizes expressions with position tracking
- **Parser** (`lib/predicator/parser.ex`): Recursive descent parser building AST
- **Compiler** (`lib/predicator/compiler.ex`): Converts AST to executable instructions  
- **Evaluator** (`lib/predicator/evaluator.ex`): Executes instructions against data
- **StringVisitor** (`lib/predicator/string_visitor.ex`): Converts AST back to strings
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
- **Overall**: 93.7%
- **StringVisitor**: 96.2% 
- **Target**: >90% for all components

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
├── string_visitor.ex  # AST to string decompilation
├── visitor.ex         # Visitor behavior definition
├── types.ex          # Type specifications
└── application.ex    # OTP application

test/predicator/
├── lexer_test.exs
├── parser_test.exs  
├── compiler_test.exs
├── evaluator_test.exs
├── string_visitor_test.exs
└── predicator_test.exs  # Integration tests
```

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
1. Update lexer tokenization
2. Update parser grammar  
3. Update type specifications
4. Add evaluation support
5. Add string visitor support
6. Add tests for all components

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