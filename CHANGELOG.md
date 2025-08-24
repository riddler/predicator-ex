# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2025-08-24

### Added

#### SCXML Enhancement Phases 1.2-1.4: Arithmetic and Logical Operators
- **Complete Parser Pipeline**: Added full parsing support for arithmetic operators (`+`, `-`, `*`, `/`, `%`)
- **Enhanced Logical Operators**: Added `&&` (logical AND), `||` (logical OR), `!` (logical NOT) with complete parsing
- **Equality Operator**: Added `==` for strict equality comparison with proper precedence handling
- **Grammar Extensions**: Implemented proper operator precedence hierarchy in recursive descent parser
- **AST Node Types**: Added new AST node types for arithmetic, equality, and unary expressions
- **Visitor Support**: Updated InstructionsVisitor and StringVisitor to handle new node types
- **Round-trip Compatibility**: Full string ↔ AST ↔ string conversion for all new operators

#### Operator Support Details
```elixir
# Arithmetic operators (parsing complete, evaluation pending)
2 + 3    # Addition - generates ["add"] instruction
5 - 2    # Subtraction - generates ["subtract"] instruction
3 * 4    # Multiplication - generates ["multiply"] instruction  
8 / 2    # Division - generates ["divide"] instruction
7 % 3    # Modulo - generates ["modulo"] instruction

# Logical operators (fully functional)
true && false   # Logical AND - works completely
true || false   # Logical OR - works completely
!active         # Logical NOT - works completely

# Equality operator (fully functional)  
x == y          # Strict equality - works completely
```

#### Foundation for SCXML Value Expressions
- **Parser Foundation**: Completed lexer, parser, and AST phases (1.2-1.4) of SCXML datamodel support
- **Instruction Generation**: Arithmetic expressions now generate proper stack machine instructions
- **Ready for Evaluation**: Next phase will implement instruction execution in evaluator
- **Backward Compatibility**: All existing functionality remains unchanged

### Technical Implementation
- **Lexer Enhancement**: Extended tokenization with 9 new token types
- **Parser Grammar**: Implemented arithmetic precedence hierarchy (unary → multiplication → addition → equality → comparison)
- **AST Extensions**: Added 4 new AST node types (:arithmetic, :equality, :unary, plus enhanced visitor support)
- **Instruction Generation**: Arithmetic expressions compile to proper stack machine instructions
- **Error Recovery**: Comprehensive error messages for parsing and evaluation phases
- **Test Coverage**: 604 tests passing with updated expectations for parser success
- **Code Quality**: Eliminated code duplication in StringVisitor through helper function extraction

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

#### Migration Guide
1. **Replace registry calls**: Convert `register_function` calls to function maps passed to `evaluate/3`
2. **Update function definitions**: Ensure functions return `{:ok, result}` or `{:error, message}`
3. **Remove initialization code**: Delete any registry setup from application startup
4. **Update tests**: Replace registry-based setup with evaluation-time function passing

#### Technical Implementation
- **Evaluator Enhancement**: Modified to accept `:functions` option and merge with system functions
- **SystemFunctions Refactor**: Added `all_functions/0` to provide system functions in evaluator format
- **Clean Architecture**: Removed ETS-based global registry and associated complexity
- **Backward Compatibility**: `evaluate/2` functions continue to work unchanged for expressions without custom functions

### Security
- **Improved Isolation**: Custom functions scoped to individual evaluation calls
- **No Global State**: Eliminates potential race conditions and global state mutations

### Performance  
- **Reduced Overhead**: No ETS lookups or global registry management
- **Better Concurrency**: Thread-safe by design with no shared state

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

#### Examples
```elixir
# Basic nested access
context = %{"user" => %{"name" => %{"first" => "John"}}}
Predicator.evaluate("user.name.first = \"John\"", context)  # {:ok, true}

# Complex expressions with nested access  
Predicator.evaluate("user.profile.age > 18 AND config.enabled", context)

# Mixed key types
mixed_context = %{"user" => %{profile: %{"active" => true}}}
Predicator.evaluate("user.profile.active", mixed_context)  # {:ok, true}

# Single quoted strings with nested access
Predicator.evaluate("user.name.first = 'John'", context)  # {:ok, true}

# Quote type preservation in round-trip
{:ok, ast} = Predicator.parse("user.role = 'admin'")
Predicator.decompile(ast)  # "user.role = 'admin'"
```

#### Technical Implementation
- **Lexer Enhancement**: Modified `take_identifier/3` to include dots in valid identifier characters
- **Evaluator Enhancement**: Enhanced `load_from_context/2` with nested path detection and delegation
- **Backwards Compatibility**: Simple variable names continue to work exactly as before
- **Comprehensive Testing**: Added 100+ new tests covering nested access scenarios

#### Breaking Changes
- **Dotted Variable Names**: Variables containing dots (e.g., `"user.email"`) are now parsed as nested access paths rather than literal key names
- **Flat Key Behavior**: Context keys like `"user.profile.name"` will no longer match the identifier `user.profile.name` - use proper nested structures instead

### Security
- No security implications - nested access maintains the same safe evaluation model
- All nested paths are validated and type-checked during traversal

### Performance
- Minimal performance impact - dot notation detection adds only a string contains check
- Recursive traversal is efficient and stops early for missing paths

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

#### Code Organization
- **Modular Architecture**: Clean separation of concerns across lexer, parser, compiler, evaluator
- **Organized File Structure**:
  - `lib/predicator/functions/` - Function system components
  - `lib/predicator/visitors/` - AST transformation modules
- **Comprehensive Testing**: 616 tests with 66 doctests, achieving >90% code coverage

### Technical Details

#### Grammar
The language supports a complete expression grammar with proper operator precedence:
```ebnf
expression   → logical_or
logical_or   → logical_and ( ("OR" | "or") logical_and )*
logical_and  → logical_not ( ("AND" | "and") logical_not )*
logical_not  → ("NOT" | "not") logical_not | comparison
comparison   → primary ( ( ">" | "<" | ">=" | "<=" | "=" | "!=" | "in" | "contains" ) primary )?
primary      → NUMBER | STRING | BOOLEAN | DATE | DATETIME | IDENTIFIER | list | function_call | "(" expression ")"
function_call → IDENTIFIER "(" ( expression ( "," expression )* )? ")"
list         → "[" ( expression ( "," expression )* )? "]"
```

#### Security
- **No Dynamic Code Execution**: All expressions compiled to safe instruction sequences
- **Input Validation**: Comprehensive validation at lexer and parser levels
- **Type Safety**: Strong typing throughout compilation and evaluation pipeline
- **Sandboxed Evaluation**: No access to system functions or arbitrary code execution

#### Performance
- **Efficient Tokenization**: Single-pass lexer with position tracking
- **Recursive Descent Parser**: Clean, maintainable parsing with excellent error recovery
- **Optimized Instruction Set**: Minimal instruction overhead for fast evaluation
- **Memory Efficient**: Low allocation during expression evaluation

### Dependencies
- **Runtime**: Zero external dependencies for core functionality
- **Development**: Credo, Dialyzer, ExCoveralls for code quality and testing
- **Minimum Elixir**: ~> 1.11

### Breaking Changes

**⚠️ COMPLETE LIBRARY REWRITE ⚠️**

Version 1.0.0 is a **complete rewrite** of the Predicator library with entirely new:
- API design and function signatures
- Expression syntax and grammar
- Internal architecture and data structures
- Feature set and capabilities

### Migration Guide

**Migration from versions < 1.0.0 has NOT been tested and is NOT guaranteed to work.**

If you are upgrading from a pre-1.0.0 version:
1. **Treat this as a new library adoption**, not an upgrade
2. **Review all documentation** - APIs have completely changed
3. **Test thoroughly** in development environments
4. **Expect to rewrite** all integration code
5. **Plan for significant refactoring** of existing expressions

Future 1.x.x versions will maintain backwards compatibility and include proper migration guides.

---

## Legacy Versions (Pre-1.0.0)

The following versions are part of the original Predicator implementation, which has been completely rewritten for 1.0.0:

## [0.9.2]

### Documentation
- Adds additional information to README
- Adds documentation to functions in Predicator

### Enhancements
- Adds `compile!`, `evaluate`, `evaluate!`, `evaluate_instructions`, `evaluate_instructions!` functions to Predicator
- Adds `Ecto.PredicatorInstructions` Ecto type

## [0.9.1]

### Documentation
- Moves project from [predicator/predicator_elixir](https://github.com/predicator/predicator_elixir) to [riddler/predicator](https://github.com/riddler/predicator/tree/master/impl/ex)

## [0.9.0]

### Breaking Changes
- Evaluates `compare` instead of `comparator` to be compatible with ruby predicator lib

## [0.8.1]

### Enhancements
- Adds leex and parsing for `and` and `or`
- Adds leex and parsing for `!` and boolean

## [0.8.0]

### Added
- **Predicator.matches?/3** accepts evaluator options

### Enhancements
- Adds leex and parsing for `isblank` and `ispresent`
- Supports escaped double quote strings

### Fixed
- `in` and `notin` accept list of strings

## [0.7.3]

### Enhancements
- Adds leex and parsing for `in`, `notin`, `between`, `startswith`, `endswith` instructions

## [0.7.1]

### Added
- Adds `between` instruction for eval on dates

## [0.7.0]

### Added
- Adds 2 new comparison predicates for `starts_with` & `ends_with`

## [0.6.0]

### Added
- Adds 3 new evaluatable predicates for `to_date`, `date_ago`, and `date_from_now`

## [0.5.0]

### Changed
- Evaluator now reads new coercion instructions `to_int`, `to_str`, & `to_bool`

## [0.4.0]

### Added
- Adds 4 new functions to the `Predicator` module: `eval/3`, `leex_string/1`, `parsed_lexed/1`, & `leex_and_parse/1`

## [0.3.0]

### Enhancements
- Adds options to **Predicator.Evaluator.execute/3** as a keyword list to define if the context map is a string keyed list `[map_type: :string]` or atom keyed for the default `[map_type: :atom]`

---

For detailed information about upcoming features and development roadmap, see the project README.
