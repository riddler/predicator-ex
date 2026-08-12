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
statement    → if_statement | assignment | expression
if_statement → "if" expression block ( "else" ( block | if_statement ) )?
block        → "{" ( statement ( ";" statement )* ( ";" )? )? "}"
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
postfix      → primary ( "[" expression "]" | "." IDENTIFIER | "::" TYPE_NAME )*
TYPE_NAME    → "integer" | "float" | "string" | "boolean" | "date" | "datetime" | "duration"
primary      → NUMBER | FLOAT | STRING | BOOLEAN | DATE | DATETIME | IDENTIFIER | duration | relative_date | list | object | function_call | "(" expression ")"
function_call → FUNCTION_NAME "(" ( expression ( "," expression )* )? ")"
list         → "[" ( expression ( "," expression )* )? "]"
object       → "{" ( object_entry ( "," object_entry )* )? "}"
object_entry → object_key ":" expression
object_key   → IDENTIFIER | STRING
duration     → NUMBER UNIT+
relative_date → duration "ago" | duration "from" "now" | "next" duration | "last" duration
```

`::` is postfix, binds tighter than unary minus, and chains left-to-right like
the other two postfix forms; its seven-name vocabulary comes from
[`docs/isa.md`](isa.md) §3, with the reasoning in
[ADR-0011](adr/0011-casts-are-an-opcode.md).

`=` is assignment, not equality. It is valid only at the start of a statement,
and only with an assignable left side - an identifier optionally followed by
`.name` and `[key]` accessors. A bare `=` in expression position is a parse
error naming `==` as the fix; there is no context where `=` silently means
equality. `==` and `===` are the only equality operators.

`if` is statement-position only, like `=`: `parse/2` rejects it the same way
it rejects a top-level `=`, and there is no ternary form. Braces are
mandatory - a block may be empty, but there is no braceless single-statement
form - and they group statements without introducing a scope: a `store`
inside a taken branch writes to the same flat context as one outside it.
`else if c { B }` is parser sugar, not a grammar production of its own - it
desugars to an `else` block whose sole statement is the nested `if`, with no
chain node in the AST. See
[ADR-0013](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0013-control-flow-lowers-to-new-jump-opcodes.md)
for all three.

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
- **Functions** (`lib/predicator/functions/`): Function system components.
  Every function - builtin or host - is provided by a module implementing the
  one-callback `Predicator.FunctionProvider` behaviour, `functions/0`,
  returning `%{name => {arity, atom}}`. The four builtin modules
  (**SystemFunctions**, **DateFunctions**, **JSONFunctions**,
  **MathFunctions**) each implement it, and a host wires its own providers in
  the same way, via `providers:`
- **Main API** (`lib/predicator.ex`): Public interface with convenience functions
- **Context** (`lib/predicator/context.ex`): A bound evaluation context -
  `data`, `functions`, `host`, and an `on_unbound` policy (`:undefined` |
  `:error`). `new/2` resolves `functions` once, at construction, folding three
  sources left to right so a later one shadows an earlier same-named entry:
  the builtin provider modules (`:builtins`, default `true`), then
  `:providers` - a list of `Predicator.FunctionProvider` modules - then
  `:functions`, an inline `%{name => {arity, fun}}` closure map merged last.
  `host` is an opaque, unnormalized carrier for whatever a provider needs at
  call time (a connection, a request struct); it is never readable from
  predicate text. `bind/3` rebinds a data key in O(1), `put_host/2` replaces
  `host` in O(1), `assign/3` writes through `ContextLocation.put/3`,
  `bound?/2` answers whether a root name is present in `data` (string or atom
  key). `evaluate/3` accepts a `%Context{}` directly (skipping the per-call
  function resolution) or a bare map (unchanged behavior, via an internal
  one-shot `Context.new/2`). See
  [ADR-0014](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0014-functions-are-provided-by-modules.md)
  for the design and why a closure-map registry could not carry host state
  cheaply
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
`store`) to the ISA; the Elixir side now ships all four, and their `pop`
companion, as of 4.0.0, but no sibling implements any of the four yet - see
[`docs/isa.md`](isa.md)'s "Not in the ISA" section for what a sibling still
has to add. The Elixir side ships
`jump_if_falsy_or_pop` and `jump_if_true_or_pop` as of 3.7.0, so `AND` and `OR`
short-circuit here, and a compiled instruction list containing either will not
run on a sibling that hasn't adopted them. See
[ADR-0003](adr/0003-the-elixir-implementation-leads-the-isa.md) for why
sibling parity is a downstream obligation rather than a gate on changes made
here, [ADR-0001](adr/0001-keep-the-stack-vm-revise-the-instruction-set.md) for
the opcodes themselves, and [`docs/isa.md`](isa.md) for the specification each
ISA version refers to.

ISA versions are integers and do not track this library's version: v2 has been
landing across 3.7.0 and 3.8.0. v3 is minted by 4.0.0 and both retires
(`and`, `or`) and introduces (`store`, `pop`) opcodes in the same version -
no sibling, consumer, or stored artifact has ever seen v3, so widening its
set before release changes nothing observable. An additive ISA version ships
in a minor release;
retiring an opcode invalidates stored artifacts and takes a major one. v4
introduces the `cast` opcode in a new tier 7 and retires nothing, so it is
additive like v2 rather than mixed like v3; see
[`docs/isa.md`](isa.md)'s §5 for the conversion matrix and
[ADR-0011](adr/0011-casts-are-an-opcode.md) for why casting is an opcode
rather than a lowering to `call`.

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

Statement mode has two entry points: `Predicator.execute/2` returns the
context, and `Predicator.execute_value/2` returns the context plus the
program's last expression statement's value. The latter is implemented by
having the machine retain what `pop` discarded rather than by compiling the
program differently, so the compiled program is identical either way
(`docs/isa.md` §2, §5).

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

## Testing Philosophy

- **Unit Tests**: Each component tested in isolation
- **Integration Tests**: Full pipeline testing in `predicator_test.exs`  
- **Property Testing**: Comprehensive input validation
- **Error Path Testing**: All error conditions covered
- **Round-trip Testing**: AST → String → AST consistency

Run `mix test` for the current count and `mix test.coverage` for the coverage
reading; both change too often to transcribe here.
