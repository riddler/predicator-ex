# Predicator: Architecture and Language Reference

This document is the detailed reference for the Predicator codebase: the
grammar, the compilation pipeline, and the component map. `CLAUDE.md` at the
repo root is the entry point and holds the working rules; this is what those
rules are about.

## Project Overview

Predicator is a secure, non-evaluative condition engine for processing end-user boolean predicates in Elixir. It provides a complete compilation pipeline from string expressions to executable instructions without the security risks of dynamic code execution. Supports arithmetic operators (+, -, *, /, %) with proper precedence, comparison operators (>, <, >=, <=, =, !=), logical operators (AND, OR, NOT), date/datetime literals, list literals, object literals with JavaScript-style syntax, membership operators (in, contains), function calls with built-in system functions, nested data structure access using dot notation, and bracket access for dynamic property and array access.

## Architecture

```text
Expression String → Lexer → Parser → Compiler → Instructions → Evaluator
                                    ↓
                              StringVisitor (decompile)
```

### Grammar with Operator Precedence

```text
program      → statement ( ";" statement )* ( ";" )?
statement    → assignment | expression
assignment   → location "=" expression
location     → IDENTIFIER ( "." IDENTIFIER | "[" expression "]" )*
expression   → logical_or
logical_or   → logical_and ( ("OR" | "or") logical_and )*
logical_and  → logical_not ( ("AND" | "and") logical_not )*
logical_not  → ("NOT" | "not") logical_not | comparison
comparison   → addition ( ( ">" | "<" | ">=" | "<=" | "==" | "!=" | "===" | "!==" | "in" | "contains" ) addition )?
addition     → multiplication ( ( "+" | "-" ) multiplication )*
multiplication → unary ( ( "*" | "/" | "%" ) unary )*
unary        → ( "-" | "!" ) unary | postfix
postfix      → primary ( "[" expression "]" | "." IDENTIFIER )*
primary      → NUMBER | FLOAT | STRING | BOOLEAN | DATE | DATETIME | IDENTIFIER | duration | relative_date | list | object | function_call | "(" expression ")"
function_call → FUNCTION_NAME "(" ( expression ( "," expression )* )? ")"
list         → "[" ( expression ( "," expression )* )? "]"
object       → "{" ( object_entry ( "," object_entry )* )? "}"
object_entry → object_key ":" expression
object_key   → IDENTIFIER | STRING
duration     → NUMBER UNIT+
relative_date → duration "ago" | duration "from" "now" | "next" duration | "last" duration
```

`=` is assignment, not equality. It is valid only at the start of a statement,
and only with an assignable left side - an identifier optionally followed by
`.name` and `[key]` accessors. A bare `=` in expression position is a parse
error naming `==` as the fix; there is no context where `=` silently means
equality. `==` and `===` are the only equality operators.

The two grammars above are reached by two separate entry points:
`Predicator.Parser.parse/2` parses the `expression` production alone and
rejects a top-level `=`, while `Predicator.Parser.parse_program/2` parses the
`program` production and is the only place `assignment` is legal. This is the
parser-level form of [`docs/isa.md`](isa.md) §2's rule that execution mode is
carried by the entry point, not by the artifact. See "The `=` grammar break
(4.0)" under Cross-Language Siblings for what this means for the Ruby and
JavaScript implementations, and
[ADR-0002](adr/0002-the-equals-grammar-break.md) for the alternatives it was
weighed against and the known-consumer survey behind the one-release notice
period.

### Core Components

- **Lexer** (`lib/predicator/lexer.ex`): Tokenizes expressions with position tracking
- **Parser** (`lib/predicator/parser.ex`): Recursive descent parser building AST. See the node inventory in `docs/reference/ast.md` for the shape of each node.
- **Compiler** (`lib/predicator/compiler.ex`): Converts AST to executable instructions  
- **Evaluator** (`lib/predicator/evaluator.ex`): Executes instructions against data. See [`docs/isa.md`](isa.md) for the instruction set specification.
- **Visitors** (`lib/predicator/visitors/`): AST transformation modules
  - **StringVisitor**: Converts AST back to strings
  - **InstructionsVisitor**: Converts AST to executable instructions
- **Functions** (`lib/predicator/functions/`): Function system components
  - **SystemFunctions**: Built-in system functions (len, upper, abs, max, etc.) provided via `all_functions/0`
- **Main API** (`lib/predicator.ex`): Public interface with convenience functions
- **Context** (`lib/predicator/context.ex`): A bound evaluation context - `data`,
  `functions` (builtins merged with `opts[:functions]` once, at construction),
  and an `on_unbound` policy (`:undefined` | `:error`). `new/2` builds one, `bind/3` rebinds
  a key in O(1), `assign/3` writes through `ContextLocation.put/3`,
  `bound?/2` answers whether a root name is present in `data` (string or atom
  key). `evaluate/3` accepts a `%Context{}` directly (skipping the per-call
  function merge) or a bare map (unchanged behavior, via an internal one-shot
  `Context.new/2`)
- **Undefined** (`lib/predicator/undefined.ex`): The one public module that
  owns the `:undefined` sentinel - `value/0`, `undefined?/1`, and
  `to_nil/1`/`from_nil/1` normalizers for a JSON-shaped boundary.
  `Predicator.Types.undefined?/1` delegates to it

## Cross-Language Siblings

Predicator's Elixir implementation is the reference implementation of the
instruction set (the ISA). Ruby and JavaScript implementations live in the
[riddler/predicator](https://github.com/riddler/predicator) monorepo
(`impl/rb`, `impl/ts`); the instruction list is the interchange format between
all three, and the expression string is not.

The ISA is versioned, and each sibling declares the version it supports and
adopts a newer one on its own schedule. **A sibling running behind the current
ISA version is an expected, documented state - not a defect.** ADR-0001 added
four opcodes (`jump_if_falsy_or_pop`, `jump_if_true_or_pop`, `make_list`,
`store`) to the ISA, of which `store` is not yet implemented by any evaluator,
Elixir or sibling - see [`docs/isa.md`](isa.md)'s "Not in the ISA" section; the
siblings do not yet implement the other three either. The Elixir side ships
`jump_if_falsy_or_pop` and `jump_if_true_or_pop` as of 3.7.0, so `AND` and `OR`
short-circuit here, and a compiled instruction list containing either will not
run on a sibling that hasn't adopted them. See
[ADR-0003](adr/0003-the-elixir-implementation-leads-the-isa.md) for why
sibling parity is a downstream obligation rather than a gate on changes made
here, [ADR-0001](adr/0001-keep-the-stack-vm-revise-the-instruction-set.md) for
the opcodes themselves, and [`docs/isa.md`](isa.md) for the specification each
ISA version refers to.

ISA versions are integers and do not track this library's version: v2 has been
landing across 3.7.0 and 3.8.0. v3 is minted by 4.0.0 and is the first version
whose only change is a retirement (`and`, `or`), which is why the integer
moved without a new opcode. An additive ISA version ships in a minor release;
retiring an opcode invalidates stored artifacts and takes a major one.

As of 2026-08-06 both siblings are ISA v1 implementations. That is a snapshot,
not a tracked matrix - each sibling publishes the version it supports in the
monorepo, and that is the authority.

This repo publishes three artifacts and maintains no support matrix of its
own: the spec ([`docs/isa.md`](isa.md)), the corpus
([`conformance/`](../conformance/README.md)) that makes a sibling's claim
verifiable by running it, and the ratchet format
([`conformance/RATCHET.md`](../conformance/RATCHET.md), `px-35i.8`) a sibling
uses to record which cases it passes and defend that claim against a moving
corpus over time.

### The `=` grammar break (4.0)

`=` is assignment-only and valid only in statement position; `==` and
`===` are the only equality operators, and `=` in expression position is a
parse error. 3.8 warned first, so consumers got one release of notice before
4.0 landed the break. See [ADR-0002](adr/0002-the-equals-grammar-break.md) for
the decision record.

The siblings' lexers still tokenize `=` as an equality operator
(`impl/rb/lib/predicator/lexer.rex` line 21, `impl/ts/src/tokens.js` line 70),
and their parsers will keep accepting `status = 'active'` until they adopt the
same rule.

Scope of the divergence:

- **Surface syntax only.** A rule string using `=` for equality parses in Ruby
  and JavaScript and fails to parse in Elixir on 4.0.
- **The instruction set is untouched.** `=` and `==` both compile to
  `["compare", "EQ"]`, so compiled artifacts still interchange in every
  direction and no stored instruction list is invalidated by the break.

ADR-0001's consequences call for the matching note in each sibling README.
Adopting the rule in the siblings is coordinated in that repo, not here.

## Development

### Development Workflow

The workflow rules - branch, gate, commit, push, close, release - live in
`CLAUDE.md`'s agent-authority table, which is the single authority on them.
The short version: work happens on a feature branch, full `mix quality` must
be green before a commit, and user-facing changes update `CHANGELOG.md` under
`## [Unreleased]` plus this document and the README where they are affected.

### Testing Commands

```bash
mix test                    # Run all tests
mix test.coverage          # Coverage report
mix test.coverage.html     # HTML coverage report
```

### Code Quality Commands

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
tools that own them - `coveralls.json` for the 90% coverage minimum, `.credo.exs`
for the checks, `mix.exs` for the Dialyzer PLT.

## Key Design Decisions

### Security First

- No `eval()` or dynamic code execution
- All expressions compiled to safe instruction sequences
- Input validation at lexer/parser level

### Error Handling

- Comprehensive error messages with line/column positions
- Graceful error propagation through pipeline stages
- Type-safe error handling with `{:ok, value} | {:error, struct}` tuples, where the
  struct comes from the `Predicator.Errors` family

### Performance

- Compile-once, evaluate-many pattern supported
- Efficient instruction-based execution
- Minimal memory allocation during evaluation

### Complexity Management

- Credo complexity warnings suppressed for lexer/parser with explanatory comments
- High complexity is appropriate and necessary for these functions
- Well-tested and contained complexity

## Common Tasks

### Adding New Operators

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

### Adding New Data Types

1. Update lexer tokenization (see date implementation)
2. Update parser grammar and AST types, giving the node a source position and
   a span rule - see `docs/reference/ast.md` for the blame-token and span
   tables a new node must fit into
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

Run `mix test` for the current count and `mix test.coverage` for the coverage
reading; both change too often to transcribe here.

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
