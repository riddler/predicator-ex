Object Literal Implementation Plan for Predicator

Based on the requirements document and Predicator's existing architecture, here's a comprehensive implementation plan for adding JavaScript-style object literal support.

Overview

This implementation will add support for {key: value, key2: value2} syntax to Predicator, enabling full SCXML compliance. The approach follows Predicator's existing patterns for lists, bracket access, and
property access.

Implementation Phases

Phase 1: Core Object Literal Support

Phase 1.1: Lexer Extensions

Estimated Time: 1 day

New Tokens:

# Add to lib/predicator/lexer.ex

| :left_brace    # {
| :right_brace   # }
| :colon         # :

Token Recognition:

# In scan_token/3

?{ -> {:left_brace, line, col, 1, "{"}
?} -> {:right_brace, line, col, 1, "}"}
?: -> {:colon, line, col, 1, ":"}

Files to Modify:

- lib/predicator/lexer.ex - Add token scanning
- lib/predicator/types.ex - Add token type specifications

Phase 1.2: Parser Grammar Extension

Estimated Time: 2 days

Grammar Updates:
primary → NUMBER | FLOAT | STRING | BOOLEAN | DATE | DATETIME
      | IDENTIFIER | function_call | list | object | "(" expression ")"

object → "{" ( object_entry ( "," object_entry )* )? "}"
object_entry → object_key ":" expression
object_key → IDENTIFIER | STRING

Parser Functions:

# Add to lib/predicator/parser.ex

defp parse_object(tokens, position)
defp parse_object_entries(tokens, position, entries \\ [])
defp parse_object_entry(tokens, position)
defp parse_object_key(tokens, position)

AST Node Structure:

# Add to lib/predicator/types.ex

@type ast_node ::
... existing types ...
| {:object, [object_entry()]}

@type object_entry :: {key_node(), ast_node()}
@type key_node :: {:identifier, binary()} | {:string_literal, binary()}

Phase 1.3: Instructions and Compilation

Estimated Time: 2 days

New Instruction Types:

# More efficient than stack-based approach - build entire object at once

["object", [{"key1", instructions1}, {"key2", instructions2}, ...]]

Compilation Strategy:

- Compile each value expression to instructions
- Combine into single object instruction with key-value pairs
- Simpler than stack-based approach used in requirements doc

Files to Modify:

- lib/predicator/compiler.ex - Add object compilation
- lib/predicator/visitors/instructions_visitor.ex - Add object visitor

Phase 1.4: Evaluator Implementation

Estimated Time: 2 days

Evaluation Logic:

# Add to lib/predicator/evaluator.ex

defp execute_instruction(["object", entries], stack, context, functions) do
case build_object(entries, context, functions) do
  {:ok, object} -> {:ok, [object | stack]}
  {:error, _} = error -> error
end
end

defp build_object(entries, context, functions) do

# Evaluate each value expression and build map

end

Integration Points:

- Objects work with property access: {name: 'John'}.name
- Objects work with bracket access: {items: [1,2,3]}['items'][0]
- Objects work in lists: [{id: 1}, {id: 2}]
- Objects in conditions: {score: 90}.score > 80

Phase 1.5: String Visitor Support

Estimated Time: 1 day

Decompilation Support:

# Add to lib/predicator/visitors/string_visitor.ex

def visit({:object, entries}, options) do
content = entries
  |> Enum.map(&visit_object_entry(&1, options))
  |> Enum.join(", ")
"{#{content}}"
end

defp visit_object_entry({key, value}, options) do
key_str = visit_object_key(key)
value_str = visit(value, options)
"#{key_str}: #{value_str}"
end

Phase 1.6: Comprehensive Testing

Estimated Time: 2 days

Test Categories:

# Basic functionality

"{}" → %{}
"{a: 1}" → %{"a" => 1}
"{name: 'John', age: 30}" → %{"name" => "John", "age" => 30}

# Nested objects

"{user: {name: 'John'}}" → %{"user" => %{"name" => "John"}}

# Mixed with existing types

"{items: [1, 2, 3], date: #2024-01-15#}"

# Integration with property access

"{user: {name: 'John'}}.user.name" → "John"

# Variables in values

"{name: user_name}" with context %{"user_name" => "Alice"}

# Computed values

"{total: 5 + 10}" → %{"total" => 15}

Files to Create:

- test/predicator/object_literal_test.exs - Core object literal tests
- Add object tests to existing integration test files

Integration with Existing Features

Property Access Compatibility

Objects automatically work with existing property access:

# These should work without additional implementation

"{config: {theme: 'dark'}}.config.theme"
"{user: {settings: {mode: 'admin'}}}.user.settings.mode"

Bracket Access Compatibility

Objects work with existing bracket access:
"{items: [1, 2, 3]}['items'][0]"
"{user: {name: 'John'}}['user']['name']"

Context Location Support

Objects as values in location expressions:

# Assignment target resolution

Predicator.context_location("config.database", %{})

# Can assign: config.database = {host: 'localhost', port: 5432}

Key Design Decisions

1. Key Handling Strategy

- Unquoted keys (preferred): {name: 'John'} - keys parsed as identifiers
- Quoted keys (optional): {'name': 'John'} - keys parsed as string literals
- Both evaluate to string keys in the final map: %{"name" => "John"}

2. AST Structure

- Use {:object, [entries]} format matching existing list pattern
- Entries as {key_node, value_node} tuples
- Key nodes can be {:identifier, name} or {:string_literal, value}

3. Instruction Format

- Single ["object", entries] instruction rather than stack-based building
- More efficient and cleaner than the stack approach in requirements
- Matches Predicator's existing patterns for complex structures

4. Error Handling

- Duplicate keys: Use last value (JavaScript behavior)
- Invalid keys: Return structured error
- Value evaluation errors: Propagate up with context

Backward Compatibility

- Zero breaking changes - purely additive functionality
- All existing expressions continue to work unchanged
- New syntax only activated by presence of { tokens
- No changes to existing AST nodes or instructions

Quality Assurance

Testing Strategy

- Unit tests: Each component (lexer, parser, evaluator) tested separately
- Integration tests: Objects with all existing Predicator features
- SCXML compliance: Test cases from Statifier requirements
- Performance tests: Ensure no degradation for existing expressions

Quality Checks

mix quality              # All quality checks must pass
mix test                # Full test suite >90% coverage
mix dialyzer            # Type checking with new object types
mix credo --strict      # Linting compliance

SCXML Integration Benefits

Test Cases Enabled

- data_obj_literal_test.exs - Data initialization with objects
- assign_obj_literal_test.exs - Assignment of object literals
- Approximately 15-20 additional SCXML tests pass

SCXML Use Cases

# Data initialization

datamodel_expr = "{p1: 'v1', p2: 'v2'}"
Predicator.evaluate(datamodel_expr, %{})

# Assignment operations

assign_expr = "{status: 'active', timestamp: #2024-01-15T10:30:00Z#}"
Predicator.evaluate(assign_expr, context)

# Conditional with objects

cond_expr = "user_data.role = 'admin' and config.mode = 'production'"
Predicator.evaluate(cond_expr, context)

Timeline and Deliverables

Week 1: Lexer and Parser (Phases 1.1-1.2)

- New tokens and grammar rules
- Parser functions for object syntax
- Basic AST generation

Week 2: Compilation and Evaluation (Phases 1.3-1.4)

- Instruction generation
- Evaluator object building
- Integration with existing features

Week 3: Testing and Polish (Phases 1.5-1.6)

- String visitor support
- Comprehensive test suite
- Documentation updates
- Performance validation

Success Criteria

1. ✅ Parsing: Object literals parse to correct AST structure
2. ✅ Evaluation: Objects evaluate to Elixir maps with correct data
3. ✅ Integration: Seamless work with property/bracket access, functions, conditions
4. ✅ SCXML Tests: Statifier object literal tests pass
5. ✅ Performance: No degradation for existing expressions
6. ✅ Quality: >90% coverage, all quality checks pass
7. ✅ Documentation: Complete docs with examples

This implementation plan adapts the requirements document to Predicator's actual architecture, following established patterns for lists, property access, and bracket access while maintaining the security
and performance characteristics that define Predicator.
