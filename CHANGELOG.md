# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [3.0.0] - 2025-08-25

### Added

#### Location Expressions for SCXML Assignment Operations (Phase 2 Complete)
- **SCXML Location Expressions**: Complete implementation of location path resolution for SCXML `<assign>` operations
- **New API Function**: `Predicator.context_location/3` - resolves assignable location paths from expressions
- **Location Path Resolution**: Returns navigation paths like `["user", "name"]`, `["items", 0, "property"]` for SCXML assignment targets
- **Assignment Validation**: Distinguishes valid assignment targets (l-values) from computed expressions (r-values)
- **Core Module**: `Predicator.ContextLocation` with comprehensive location resolution logic and error handling
- **Structured Error Handling**: `Predicator.Errors.LocationError` with detailed error types and context information

#### Location Expression Examples
```elixir
# Valid assignment targets resolve to location paths
Predicator.context_location("user.profile.name", %{})                    # {:ok, ["user", "profile", "name"]}
Predicator.context_location("items[0]", %{})                             # {:ok, ["items", 0]}
Predicator.context_location("data['users'][index]['profile']", %{"index" => 2})  # {:ok, ["data", "users", 2, "profile"]}

# Invalid assignment targets return structured errors
Predicator.context_location("len(name)", %{})                            # {:error, %LocationError{type: :not_assignable}}
Predicator.context_location("42", %{})                                   # {:error, %LocationError{type: :not_assignable}}
Predicator.context_location("score + 1", %{})                            # {:error, %LocationError{type: :not_assignable}}
```

#### Error Types and Validation
- **`:not_assignable`**: Expression cannot be used as assignment target (literals, functions, computed expressions)
- **`:invalid_node`**: Unknown or unsupported AST node type encountered during resolution
- **`:undefined_variable`**: Variable referenced in bracket key is not defined in evaluation context
- **`:invalid_key`**: Bracket key is not a valid string or integer type
- **`:computed_key`**: Computed expressions cannot be used as assignment target keys

#### Assignable vs Non-Assignable Classifications
- **✅ Valid Assignment Targets**: Simple identifiers, property access, bracket access, mixed notation
  - `user`, `score`, `config.database.host`
  - `items[0]`, `user['profile']`, `data["settings"]`
  - `user.settings['theme']`, `data['users'][0].profile`
- **❌ Invalid Assignment Targets**: Literals, function calls, computed expressions
  - `42`, `"hello"`, `true`, `#2024-01-15#`
  - `len(name)`, `upper(role)`, `max(a, b)`
  - `score + 1`, `items[i + 1]`, `score > 85`

#### Technical Implementation
- **Full Location Resolution**: Recursive resolution of nested property access and bracket access
- **Mixed Notation Support**: Complete support for expressions like `user.settings['theme']` and `data['users'][0].name`
- **Variable Key Resolution**: Bracket keys can reference context variables for dynamic access patterns
- **Context Integration**: Uses existing evaluation context for variable key resolution
- **Comprehensive Testing**: 49 comprehensive tests covering all location resolution scenarios and error cases

#### Type Coercion and Float Support
- **Float Literal Support**: Extended lexer to parse floating-point numbers (e.g., `3.14`, `0.5`)
- **Float Token Type**: Added `:float` token type to distinguish from integers
- **Parser Float Handling**: Updated parser to handle float tokens and create appropriate AST nodes
- **Arithmetic with Floats**: All arithmetic operations now support both integers and floats
  - Addition, subtraction, multiplication work seamlessly with mixed numeric types
  - Division returns float when needed, integer when evenly divisible
  - Modulo remains integer-only as per mathematical conventions
- **String Concatenation with `+` Operator**: Implemented JavaScript-like type coercion
  - `"Hello" + "World"` → `"HelloWorld"` (string concatenation)
  - `"Count: " + 5` → `"Count: 5"` (string + number coercion)
  - `42 + " items"` → `"42 items"` (number + string coercion)
- **Type Coercion Rules**:
  - Number + Number → Numeric addition (supports mixed int/float)
  - String + String → String concatenation
  - String + Number → String concatenation (number converted to string)
  - Number + String → String concatenation (number converted to string)
- **Comparison Enhancements**: Numbers of different types (int/float) can be compared
- **Unary Minus for Floats**: Unary minus operator now works with floating-point numbers
- **Error Message Updates**: Updated error messages from "integer" to "number" where appropriate
- **Comprehensive Testing**: Added 28 new tests covering all type coercion scenarios

### Changed

#### Property Access Parsing Architecture Overhaul (Breaking Changes)
- **Complete Dot Notation Reimplementation**: Transformed from dotted identifiers to proper property access AST nodes
- **Lexer Breaking Change**: Dots removed from valid identifier characters, now parsed as separate tokens
- **Parser Grammar Enhancement**: Added property access grammar `postfix → primary ( "[" expression "]" | "." IDENTIFIER )*`
- **New AST Structure**: Expressions like `user.email` now parsed as `{:property_access, {:identifier, "user"}, "email"}`
- **Instruction Pipeline**: Evaluation generates separate `load` and `access` instructions instead of single `load` with dotted name
- **Mixed Notation Support**: Enables complex expressions like `user.settings['theme']` and `data['users'][0].profile`

### Breaking Changes

#### v3.0.0 - Property Access Parsing Overhaul
This is a **major breaking change** affecting how dot notation is parsed and evaluated:

**⚠️ Context Key Impact**: Context keys containing dots (e.g., `"user.email"`) will no longer match dot notation expressions (`user.email`). The expression `user.email` is now parsed as property access requiring nested structure `%{"user" => %{"email" => "..."}}`

**Migration Required**:
```elixir
# BEFORE (v2.2.0 and earlier) - WILL NO LONGER WORK
context = %{"user.email" => "john@example.com"}
Predicator.evaluate("user.email = 'john@example.com'", context)  # No longer matches

# AFTER (v3.0.0+) - Use proper nested structures
context = %{"user" => %{"email" => "john@example.com"}}
Predicator.evaluate("user.email = 'john@example.com'", context)  # Works correctly
```

**Technical Changes**:
- **Lexer**: Dots no longer valid in identifier characters, parsed as separate `:dot` tokens
- **Parser**: New property access AST nodes `{:property_access, left_node, property}`
- **Evaluator**: New `access` instruction handler, removed dotted identifier support from `load_from_context`
- **Instructions**: `user.email` generates `[["load", "user"], ["access", "email"]]` instead of `[["load", "user.email"]]`

**Benefits**:
- Enables mixed notation: `user.settings['theme']`, `data['users'][0].name`
- Supports SCXML location expressions for assignment operations
- Proper property access semantics for complex data structures
- Foundation for advanced SCXML datamodel integration

## [2.2.0] - 2025-08-24

### Added

#### Bracket Access and Property Access Enhancement
- **Complete Bracket Notation Support**: Implemented full bracket access functionality (`obj['key']`, `arr[0]`, `obj[variable]`)
- **Parser Extensions**: Added postfix parsing for bracket access with recursive chaining support
- **Grammar Enhancement**: Updated grammar with postfix operations: `unary → postfix`, `postfix → primary ( "[" expression "]" )*`
- **New AST Node Type**: Added `{:bracket_access, object, key}` AST node for bracket access expressions
- **Evaluator Support**: Implemented `["bracket_access"]` instruction with comprehensive evaluation logic
- **Mixed Access Patterns**: Full support for chained access like `data['users'][0]['name']`
- **Array Indexing**: Complete array access with bounds checking (`items[0]`, `scores[index]`)
- **Dynamic Key Access**: Support for variable and expression-based keys (`obj[key]`, `items[i + 1]`)
- **Type Safety**: Comprehensive error handling for invalid key types with structured error messages
- **String Visitor Support**: Added round-trip string conversion for bracket access expressions
- **Comprehensive Testing**: Added 12 new parser tests covering all bracket access scenarios

#### Error Handling Architecture Refactoring
- **Modular Error Structure**: Refactored monolithic error handling into individual error modules under `lib/predicator/errors/`
- **Shared Error Utilities**: Created `Predicator.Errors` module with common utility functions for consistent error formatting
- **Individual Error Modules**: Split error handling into focused modules:
  - `Predicator.Errors.TypeMismatchError` - Type validation and mismatch errors
  - `Predicator.Errors.EvaluationError` - Runtime evaluation errors (division by zero, insufficient operands)
  - `Predicator.Errors.UndefinedVariableError` - Variable access errors
  - `Predicator.Errors.ParseError` - Expression parsing and syntax errors
- **Consistent Error Messages**: Unified error message formatting across all error types
- **Code Quality Improvements**: Resolved all credo issues with proper module aliasing and organization

## [2.1.0] - 2025-08-24

### Added

#### Arithmetic and Unary Operations (Complete Implementation)
- **Full Arithmetic Support**: Complete parsing and evaluation pipeline for arithmetic expressions
  - **Binary operations**: `+` (addition), `-` (subtraction), `*` (multiplication), `/` (division), `%` (modulo)
  - **Unary operations**: `-` (unary minus), `!` (unary bang/logical NOT)
- **Proper Precedence**: Mathematical precedence handling (unary → multiplication → addition → equality → comparison)
- **Instruction Execution**: Stack-based evaluator with 7 new instruction handlers
- **Error Handling**: Division by zero protection, type checking, comprehensive error messages
- **Pattern Matching**: Idiomatic Elixir implementation using pattern matching for clean code

## [2.0.0] - 2025-08-21

### Changed

#### Custom Function Architecture Overhaul
- **Breaking Change**: Removed global function registry system in favor of evaluation-time function parameters
- **New API**: Custom functions now passed via `functions:` option in `Predicator.evaluate/3` calls
- **Function Format**: Custom functions use `%{name => {arity, function}}` format where function takes `[args], context` and returns `{:ok, result}` or `{:error, message}`
- **Thread Safety**: Eliminated global state for improved concurrency and thread safety
- **Function Merging**: SystemFunctions always available with custom functions merged in, allowing overrides
- **Simplified Startup**: No application-level function registry initialization required

#### Examples
```elixir
# Old registry-based approach (removed)
Predicator.register_function("double", 1, fn [n], _context -> {:ok, n * 2} end)
Predicator.evaluate("double(21)", %{})

# New evaluation-time approach
custom_functions = %{"double" => {1, fn [n], _context -> {:ok, n * 2} end}}
Predicator.evaluate("double(21)", %{}, functions: custom_functions)

# Custom functions can override built-ins
custom_len = %{"len" => {1, fn [_], _context -> {:ok, "custom_result"} end}}
Predicator.evaluate("len('anything')", %{}, functions: custom_len)  # {:ok, "custom_result"}
```

#### Removed APIs
- `Predicator.register_function/3` - Use `functions:` option instead
- `Predicator.clear_custom_functions/0` - No longer needed
- `Predicator.list_custom_functions/0` - No longer needed
- `Predicator.Functions.Registry` module - Entire registry system removed

### Breaking Changes

#### v2.0.0 - Custom Function Architecture Overhaul
- **Removed**: Global function registry system (`Predicator.Functions.Registry` module)
- **Removed**: `Predicator.register_function/3`, `Predicator.clear_custom_functions/0`, `Predicator.list_custom_functions/0`
- **Changed**: Custom functions now passed via `functions:` option in `evaluate/3` calls instead of global registration
- **Benefit**: Thread-safe, no global state, per-evaluation function scoping
- **Migration**: Replace registry calls with function maps passed to `evaluate/3`

## [1.1.0] - 2025-08-20

### Added

#### Nested Data Structure Access
- **Dot Notation Support**: Access deeply nested data structures using dot notation syntax
- **Enhanced Lexer**: Extended identifier tokenization to include dots (`.`) as valid characters
- **Recursive Context Loading**: Added `load_nested_value/2` function for traversing nested maps
- **Mixed Key Type Support**: Works seamlessly with string keys, atom keys, or mixed key types
- **Graceful Error Handling**: Returns `:undefined` for missing paths or non-map intermediate values
- **Unlimited Nesting Depth**: Support for arbitrarily deep nested structures

#### Single Quote String Support
- **Dual Quote Types**: Added support for single-quoted strings (`'hello'`) alongside double-quoted strings (`"hello"`)
- **Quote Type Preservation**: Round-trip parsing and decompilation preserves original quote type
- **Enhanced Lexer**: Extended string tokenization to handle both quote types with proper escaping
- **AST Enhancement**: New `{:string_literal, value, quote_type}` AST node for quote-aware string handling
- **Escape Sequences**: Full escape sequence support in both quote types (`\'`, `\"`, `\n`, `\t`, etc.)

### Breaking Changes

#### v1.1.0 - Nested Access Parsing
- **Changed**: Variables containing dots (e.g., `"user.email"`) now parsed as nested access paths
- **Impact**: Context keys like `"user.profile.name"` will no longer match identifier `user.profile.name`
- **Solution**: Use proper nested data structures instead of flat keys with dots

## [1.0.1] - 2025-08-20

### Documentation
- Fixes main page for Hex docs

## [1.0.0] - 2025-08-19

### Added

#### Core Language Features
- **Comparison Operators**: Full support for `>`, `<`, `>=`, `<=`, `=`, `!=` with proper type handling
- **Logical Operators**: Case-insensitive `AND`/`and`, `OR`/`or`, `NOT`/`not` with correct precedence
- **Data Types**:
  - Numbers (integers): `42`, `-17`
  - Strings (double-quoted): `"hello"`, `"world"`
  - Booleans: `true`, `false`
  - Date literals: `#2024-01-15#` (ISO 8601 format)
  - DateTime literals: `#2024-01-15T10:30:00Z#` (ISO 8601 with timezone)
  - List literals: `[1, 2, 3]`, `["admin", "manager"]`
  - Identifiers: `score`, `user_name`, `is_active`

#### Advanced Operations
- **Membership Operators**:
  - `in` for element-in-collection testing (`role in ["admin", "manager"]`)
  - `contains` for collection-contains-element testing (`[1, 2, 3] contains 2`)
- **Parenthesized Expressions**: Full support with proper precedence handling
- **Plain Boolean Expressions**: Support for bare identifiers (`active`, `expired`) without explicit `= true`

#### Function System
- **Built-in System Functions**:
  - **String functions**: `len(string)`, `upper(string)`, `lower(string)`, `trim(string)`
  - **Numeric functions**: `abs(number)`, `max(a, b)`, `min(a, b)`
  - **Date functions**: `year(date)`, `month(date)`, `day(date)`
- **Custom Function Registration**: Register anonymous functions with `Predicator.register_function/3`
- **Function Registry**: ETS-based registry with automatic arity validation and error handling
- **Context-Aware Functions**: Functions receive evaluation context for dynamic behavior

#### Architecture & Performance
- **Multi-Stage Compilation Pipeline**: Expression → Lexer → Parser → Compiler → Instructions → Evaluator
- **Compile-Once, Evaluate-Many**: Pre-compile expressions for repeated evaluation
- **Stack-Based Evaluator**: Efficient instruction execution with minimal overhead
- **Comprehensive Error Handling**: Detailed error messages with line/column positioning

#### Developer Experience
- **String Decompilation**: Convert AST back to readable expressions with formatting options
- **Multiple Evaluation APIs**:
  - `evaluate/2` - Returns `{:ok, result}` or `{:error, message}`
  - `evaluate!/2` - Returns result directly or raises exception
  - `compile/1` - Pre-compile expressions to instructions
  - `parse/1` - Parse expressions to AST for inspection
- **Formatting Options**: Configurable spacing (`:normal`, `:compact`, `:verbose`) and parentheses (`:minimal`, `:explicit`, `:none`)

### Breaking Changes

**⚠️ COMPLETE LIBRARY REWRITE ⚠️**

Version 1.0.0 is a **complete rewrite** of the Predicator library with entirely new:
- API design and function signatures
- Expression syntax and grammar
- Internal architecture and data structures
- Feature set and capabilities

#### Migration Guide

**Migration from versions < 1.0.0 has NOT been tested and is NOT guaranteed to work.**

If you are upgrading from a pre-1.0.0 version:
1. **Treat this as a new library adoption**, not an upgrade
2. **Review all documentation** - APIs have completely changed
3. **Test thoroughly** in development environments
4. **Expect to rewrite** all integration code
5. **Plan for significant refactoring** of existing expressions

Future 1.x.x versions will maintain backwards compatibility and include proper migration guides.

---

For detailed information about upcoming features and development roadmap, see the project README.
