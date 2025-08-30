# Object Literal Support Requirements for Predicator

## Executive Summary

This document outlines the requirements for adding object literal syntax support to Predicator to enable full SCXML compliance in the Statifier library. Object literals are the primary missing feature preventing approximately 15-20 SCXML test cases from passing.

## Motivation

### Current Gap

Predicator v3.0 supports comprehensive expression evaluation including arrays, nested property access, and custom functions. However, it lacks support for JavaScript-style object literal syntax, which is required by the SCXML specification for data initialization and assignment operations.

### Impact on Statifier

The Statifier SCXML implementation currently fails several test cases that require object literal support:

- `test/scion_tests/data/data_obj_literal_test.exs` - Data initialization with object literals
- `test/scion_tests/assign/assign_obj_literal_test.exs` - Assignment of object literals
- Various other tests requiring structured data initialization

## Syntax Requirements

### Basic Object Literal Syntax

Support for JavaScript-style object literal notation with key-value pairs:

```javascript
// Simple object
{p1: 'v1', p2: 'v2'}

// Nested objects
{user: {name: 'John', age: 30}, active: true}

// Mixed with arrays
{items: [1, 2, 3], config: {theme: 'dark'}}

// Empty object
{}
```

### Key Formats

Support multiple key notation styles for compatibility:

```javascript
// Unquoted keys (JavaScript style - preferred for SCXML)
{name: 'John', age: 30}

// Quoted keys (optional enhancement)
{'name': 'John', 'age': 30}
{"name": "John", "age": 30}

// Mixed (if feasible)
{name: 'John', 'last-name': 'Doe'}
```

### Value Types

Object values should support all existing Predicator data types:

```javascript
{
  string: 'hello',
  number: 42,
  float: 3.14,
  boolean: true,
  date: #2024-01-15#,
  datetime: #2024-01-15T10:30:00Z#,
  array: [1, 2, 3],
  nested: {inner: 'value'},
  null_value: null,  // If null support exists
  expression: score + 10  // Computed values
}
```

## Grammar Extension

### Proposed Grammar Changes

Extend the existing Predicator grammar to include object literals:

```ebnf
// Current primary rule
primary → NUMBER | FLOAT | STRING | BOOLEAN | DATE | DATETIME 
        | IDENTIFIER | function_call | list | "(" expression ")"

// Extended with object literal
primary → NUMBER | FLOAT | STRING | BOOLEAN | DATE | DATETIME 
        | IDENTIFIER | function_call | list | object | "(" expression ")"

// New object literal rules
object → "{" ( object_entry ( "," object_entry )* )? "}"
object_entry → object_key ":" expression
object_key → IDENTIFIER | STRING  // Support both unquoted and quoted keys
```

## Lexer Modifications

### New Tokens

- `{` (LBRACE) - Object opening delimiter
- `}` (RBRACE) - Object closing delimiter
- `:` (COLON) - Key-value separator (distinct from existing operators)

### Token Recognition

The lexer should distinguish between:

- `:` as object key-value separator
- `:` in other contexts (if used elsewhere)

## Parser Implementation

### AST Node Structure

New AST node type for object literals:

```elixir
# Proposed AST structure
{:object, meta, entries}
# where entries is a list of {:entry, key, value}

# Example AST for {name: 'John', age: 30}
{:object, %{line: 1, column: 1}, [
  {:entry, {:identifier, %{}, "name"}, {:string, %{}, "John"}},
  {:entry, {:identifier, %{}, "age"}, {:number, %{}, 30}}
]}
```

## Compiler Instructions

### New Instruction Types

Define instructions for object construction:

```elixir
# Proposed instruction format
["obj_new"]                    # Create new empty object
["obj_set", key]               # Set a key-value pair
["obj_build", num_keys]        # Build object from stack

# Example compilation of {name: 'John', age: 30}
[
  ["obj_new"],
  ["lit", "John"],
  ["obj_set", "name"],
  ["lit", 30],
  ["obj_set", "age"]
]
```

## Evaluator Behavior

### Runtime Evaluation

Object literals should evaluate to Elixir maps:

```elixir
# Input expression
"{name: 'John', age: 30}"

# Evaluated result
%{"name" => "John", "age" => 30}
```

### Integration with Existing Features

Ensure seamless integration with current Predicator features:

```elixir
# Object literals in conditions
Predicator.evaluate("{status: 'active'}.status = 'active'", %{})
# => {:ok, true}

# Objects with nested access
Predicator.evaluate("config.theme", %{"config" => {theme: 'dark'}})
# => {:ok, "dark"}

# Objects in lists
Predicator.evaluate("[{id: 1}, {id: 2}]", %{})
# => {:ok, [%{"id" => 1}, %{"id" => 2}]}

# Objects as function arguments (if applicable)
Predicator.evaluate("process({name: 'test'})", %{}, functions: custom_fns)
```

## Location Expression Support

### Assignment to Object Properties

Ensure object properties can be assignment targets:

```elixir
# Valid location expressions with objects
Predicator.context_location("data.user", %{})
# Can assign: data.user = {name: 'John', age: 30}

# Creating nested structures
Predicator.context_location("config.database", %{})
# Can assign: config.database = {host: 'localhost', port: 5432}
```

## Backward Compatibility

### Non-Breaking Changes

- All existing Predicator expressions must continue to work
- No changes to existing AST nodes or instruction formats
- Object literals are purely additive functionality

## Test Cases

### Basic Functionality

```elixir
# Empty object
assert {:ok, %{}} = Predicator.evaluate("{}", %{})

# Simple object
assert {:ok, %{"a" => 1}} = Predicator.evaluate("{a: 1}", %{})

# Multiple properties
assert {:ok, %{"name" => "John", "age" => 30}} = 
  Predicator.evaluate("{name: 'John', age: 30}", %{})

# Nested objects
assert {:ok, %{"user" => %{"name" => "John"}}} = 
  Predicator.evaluate("{user: {name: 'John'}}", %{})

# Objects with arrays
assert {:ok, %{"items" => [1, 2, 3]}} = 
  Predicator.evaluate("{items: [1, 2, 3]}", %{})
```

### Integration Tests

```elixir
# Object in expression context
assert {:ok, true} = 
  Predicator.evaluate("{score: 90}.score > 80", %{})

# Object with variables
assert {:ok, %{"name" => "Alice", "score" => 95}} = 
  Predicator.evaluate("{name: user_name, score: user_score}", 
    %{"user_name" => "Alice", "user_score" => 95})

# Computed property values
assert {:ok, %{"total" => 15}} = 
  Predicator.evaluate("{total: 5 + 10}", %{})
```

### SCXML-Specific Tests

```elixir
# Data initialization (from data_obj_literal_test.exs)
assert {:ok, %{"p1" => "v1", "p2" => "v2"}} = 
  Predicator.evaluate("{p1: 'v1', p2: 'v2'}", %{})

# Assignment operations (from assign_obj_literal_test.exs)
context = %{"o1" => nil}
assert {:ok, %{"p1" => "v1", "p2" => "v2"}} = 
  Predicator.evaluate("{p1: 'v1', p2: 'v2'}", context)
```

## Implementation Priority

### Phase 1: Core Object Literal Support (Required)

- Basic object literal syntax with unquoted keys
- Support for all existing Predicator value types as values
- Integration with evaluation pipeline

### Phase 2: Enhanced Features (Optional)

- Quoted key support for special characters
- Computed property keys: `{[key_var]: value}`
- Shorthand property notation: `{name}` → `{name: name}`
- Spread operator: `{...other_obj, new_prop: value}`

## Alternative Considerations

### Map Literal Syntax

If JavaScript-style syntax proves complex, consider Elixir-style map literals:

```elixir
%{name: "John", age: 30}
```

However, JavaScript-style is preferred for SCXML compliance.

### Function-Based Workaround

As an interim solution, a custom function could construct objects:

```javascript
obj('p1', 'v1', 'p2', 'v2')  // Returns {p1: 'v1', p2: 'v2'}
```

This is less elegant but could unblock testing.

## Success Criteria

1. **Parsing**: Successfully parse object literal syntax without errors
2. **Evaluation**: Object literals evaluate to Elixir maps with correct key-value pairs
3. **Integration**: Objects work seamlessly with existing operators and functions
4. **SCXML Tests**: Enable passing of Statifier tests that require object literals:
   - `data_obj_literal_test.exs` passes
   - `assign_obj_literal_test.exs` passes
   - Related tests with object initialization pass
5. **Performance**: No significant performance degradation for existing expressions
6. **Documentation**: Complete documentation with examples

## Conclusion

Adding object literal support to Predicator would close the primary gap preventing full SCXML compliance in Statifier. The implementation should prioritize JavaScript-style syntax for maximum compatibility with SCXML specifications while maintaining Predicator's security and performance characteristics.

This enhancement would enable approximately 15-20 additional SCXML test cases to pass, significantly improving Statifier's compliance with the W3C SCXML specification.
