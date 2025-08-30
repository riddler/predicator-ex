# SCXML Enhancement Implementation Plan

This document outlines the detailed implementation plan for extending Predicator to support SCXML datamodel expressions.

## Overview

We are implementing enhancements to support three types of SCXML expressions:

1. **Conditional Expressions** ✅ (Already supported)
2. **Value Expressions** ❌ (New - return any data value)
3. **Location Expressions** ❌ (New - assignment targets)

## Implementation Phases

### PHASE 1: Basic Value Expressions and Arithmetic Operations

#### Phase 1.1: Grammar Extensions

**Status**: Planning
**Estimated Time**: 1 day

**Objectives**:

- Define new grammar rules for arithmetic operations
- Add bracket notation for property access
- Update operator precedence hierarchy

**New Grammar Rules**:

```ebnf
expression    → assignment
assignment    → logical_or
logical_or    → logical_and ( ("||" | "OR" | "or") logical_and )*
logical_and   → logical_not ( ("&&" | "AND" | "and") logical_not )*
logical_not   → ("!" | "NOT" | "not") logical_not | equality
equality      → comparison ( ("==" | "!=") comparison )*
comparison    → addition ( ( ">" | "<" | ">=" | "<=" ) addition )*
addition      → multiplication ( ( "+" | "-" ) multiplication )*
multiplication → unary ( ( "*" | "/" | "%" ) unary )*
unary         → ( "!" | "-" ) unary | postfix
postfix       → primary ( "." IDENTIFIER | "[" expression "]" )*
primary       → NUMBER | STRING | BOOLEAN | IDENTIFIER | "(" expression ")"
```

**Deliverables**:

- Updated grammar documentation
- Operator precedence specification

#### Phase 1.2: Lexer Enhancements

**Status**: Pending
**Estimated Time**: 2 days

**Objectives**:

- Add new token types for arithmetic operators
- Add bracket tokens for array/object access
- Update tokenization logic

**New Token Types**:

```elixir
@type token_type :: 
  ... existing types ...
  | :plus          # +
  | :minus         # - 
  | :multiply      # *
  | :divide        # /
  | :modulo        # %
  | :left_bracket  # [
  | :right_bracket # ]
  | :equal_equal   # ==
  | :not_equal     # !=
  | :and_and       # &&
  | :or_or         # ||
  | :bang          # !
```

**Files to Modify**:

- `lib/predicator/lexer.ex`
- `lib/predicator/types.ex`

**Testing**:

- Unit tests for each new token type
- Edge cases (spaces around operators, etc.)
- Performance impact assessment

#### Phase 1.3: Parser Updates

**Status**: Pending  
**Estimated Time**: 3 days

**Objectives**:

- Implement recursive descent parsing for arithmetic expressions
- Add property access parsing (dot and bracket notation)
- Update AST generation

**Parser Functions to Add**:

```elixir
defp parse_addition(tokens, position)
defp parse_multiplication(tokens, position)
defp parse_unary(tokens, position)
defp parse_postfix(tokens, position)
defp parse_property_access(tokens, position, left_expr)
defp parse_bracket_access(tokens, position, left_expr)
```

**Files to Modify**:

- `lib/predicator/parser.ex`

**Testing**:

- Parser tests for each grammar rule
- Complex nested expressions
- Error handling for invalid syntax

#### Phase 1.4: AST Node Types

**Status**: Pending
**Estimated Time**: 1 day

**Objectives**:

- Define new AST node types for arithmetic operations
- Add property and bracket access nodes
- Update type specifications

**New AST Node Types**:

```elixir
@type arithmetic_op :: :add | :subtract | :multiply | :divide | :modulo
@type ast_node :: 
  ... existing types ...
  | {:arithmetic, arithmetic_op(), ast_node(), ast_node()}
  | {:property_access, ast_node(), binary()}
  | {:bracket_access, ast_node(), ast_node()}
  | {:unary_minus, ast_node()}
```

**Files to Modify**:

- `lib/predicator/types.ex`

#### Phase 1.5: Evaluator Enhancements

**Status**: Pending
**Estimated Time**: 4 days

**Objectives**:

- Implement instruction execution for arithmetic operations
- Add property and bracket access evaluation
- Handle type coercion and error cases

**New Instruction Types**:

```elixir
- ["add"]              # Stack: [right, left] → [result]
- ["subtract"]         # Stack: [right, left] → [result]
- ["multiply"]         # Stack: [right, left] → [result]
- ["divide"]           # Stack: [right, left] → [result]
- ["modulo"]           # Stack: [right, left] → [result]
- ["prop_access", key] # Stack: [object] → [object[key]]
- ["bracket_access"]   # Stack: [key, object] → [object[key]]
- ["unary_minus"]      # Stack: [value] → [-value]
```

**Files to Modify**:

- `lib/predicator/evaluator.ex`
- `lib/predicator/compiler.ex`

**Type Coercion Rules**:

- String + String → String concatenation
- Number + Number → Numeric addition
- String + Number → String concatenation (convert number to string)
- Division by zero → Error

#### Phase 1.6: New API Functions

**Status**: Pending
**Estimated Time**: 2 days

**Objectives**:

- Create `evaluate_value/3` function for value expressions
- Enhanced error types for SCXML compatibility
- Maintain backward compatibility

**New API**:

```elixir
@spec evaluate_value(binary() | Types.instruction_list(), Types.context(), keyword()) :: 
  {:ok, Types.value()} | Types.scxml_error()

@type scxml_error :: 
  {:error, :undefined_variable, %{variable: binary()}} |
  {:error, :type_mismatch, %{expected: atom(), got: atom()}} |
  {:error, :evaluation_error, %{reason: binary()}}
```

**Files to Modify**:

- `lib/predicator.ex`
- `lib/predicator/types.ex`

### PHASE 2: Location Expressions (Future)

**Status**: Planning
**Estimated Time**: 1 week

**Objectives**:

- Parse assignment target expressions
- Validate assignability
- Return path structures for assignment

### PHASE 3: Advanced Operations (Future)

**Status**: Planning  
**Estimated Time**: 2 weeks

**Objectives**:

- Method calls and property methods
- Safe navigation operators
- Advanced type coercion

## Quality Assurance Process

### After Each Sub-Phase

1. Run `mix quality` and fix all issues
2. Ensure test coverage >90%
3. Update documentation
4. Verify backward compatibility

### Quality Checks

```bash
mix quality           # Run all quality checks
mix test             # Run test suite
mix credo --strict   # Linting
mix dialyzer        # Type checking
mix format          # Code formatting
```

## Testing Strategy

### Unit Tests

- Each new token type and parser rule
- All arithmetic operations and edge cases
- Property access (dot and bracket notation)
- Error conditions and recovery

### Integration Tests

- Complex expressions combining multiple operations
- SCXML use case scenarios
- Performance benchmarks

### Property-Based Tests

- Arithmetic operation properties
- Type coercion consistency
- Parser correctness

## Backward Compatibility

- All existing APIs remain unchanged
- New functionality through new APIs
- Existing test suite must continue to pass
- No breaking changes to current behavior

## Documentation Updates

### Files to Update

- `README.md` - New features and examples
- `CLAUDE.md` - Development context
- `CHANGELOG.md` - Version history
- Function documentation - All new APIs

## Risk Mitigation

### Potential Issues

- **Parser Complexity**: Manage with careful testing and modular design
- **Performance Impact**: Benchmark against existing functionality
- **Type Coercion**: Follow JavaScript-like rules for SCXML compatibility
- **Security**: Maintain no-eval security model

### Mitigation Strategies

- Incremental implementation with testing at each step
- Performance monitoring and optimization
- Comprehensive error handling
- Security review of all new features

## Success Criteria

### Phase 1 Complete When

- [x] All new tokens properly lexed
- [x] Parser handles arithmetic expressions with correct precedence
- [x] Evaluator executes arithmetic operations correctly
- [x] `evaluate_value/3` API functional
- [x] All tests pass with >90% coverage
- [x] `mix quality` passes without issues
- [x] Backward compatibility maintained

### Integration Success

- SCXML expressions evaluate correctly
- Performance within acceptable bounds
- Security model maintained
- Documentation complete and accurate

---

This implementation plan will be updated as we progress through each phase, with actual timelines and issues encountered documented for future reference.
