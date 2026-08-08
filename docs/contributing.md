# Contributing to Predicator

This document is how to work on the predicator codebase: the commands, the
checklists for extending the language, and where to look when something
breaks. `CLAUDE.md` at the repo root is the single authority on the workflow
rules - branch, gate, commit, push, close, release; this document does not
restate them. What follows is instruction, not governance: how to run the
gate, how to add an operator or a data type without missing a step, and where
things tend to go wrong.

## Commands

### Testing

```bash
mix test                    # Run all tests
mix test.coverage          # Coverage report
mix test.coverage.html     # HTML coverage report
```

### Quality gate

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
tools that own them - `coveralls.json` for the 90% coverage minimum,
`.credo.exs` for the checks, `mix.exs` for the Dialyzer PLT.

## Adding New Operators

1. Add token type to `lexer.ex`
2. Add parsing logic to `parser.ex`
3. Add instruction type to `types.ex`
4. Add evaluation logic to `evaluator.ex`
5. Add compilation logic to `compiler.ex`
6. Add string formatting to `string_visitor.ex`
7. Point the new node at its operator token - see the "which token a node
   blames" table in `docs/reference/ast.md`. The trailing slot is part of the
   node shape, not an add-on
8. Give the new node a span rule too - see the "which characters a node
   covers" table in `docs/reference/ast.md`
9. Add comprehensive tests

## Adding New Data Types

1. Update lexer tokenization (see date implementation)
2. Update parser grammar and AST types, giving the node a source position and
   a span rule - see `docs/reference/ast.md` for the blame-token and span
   tables a new node must fit into
3. Update type specifications in `types.ex`
4. Add evaluation support with type checking
5. Add string visitor formatting support
6. Add tests for all pipeline components

## Debugging Issues

- Use `mix test --trace` for detailed test output
- Check coverage with `mix test.coverage.html`
- Use `mix dialyzer` for type issues
- Run `mix credo explain <issue>` for linting details

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
