# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-08-XX

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
