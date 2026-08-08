# AST Reference

The AST is the tree `Predicator.Parser.parse/2` and `parse_program/2` produce
from a token stream, and the shape every visitor consumes -
`Predicator.decompile/2` turns it back into source, `InstructionsVisitor`
turns it into instructions. This page describes that shape node by node, in
the present tense: what a node looks like, which token it blames when
something about it fails, and which characters it covers when a caller asks
for a span. `t:Predicator.Parser.ast/0` - the type in `lib/predicator/parser.ex`
- is the machine-checked authority; this page is the prose version of it.

## The trailing slot

Every AST node ends in one slot: a `{line, column}`, a span, or `nil`. There is
one AST shape, not two - a caller building a node by hand rather than parsing
supplies `nil` in that slot, and every visitor clause matches on "node with a
trailing slot in," never on a position-free variant.

Positions are the default at every entry point. `Predicator.Parser.parse/2`
and `parse_program/2` fill the slot with a `{line, column}` naming the token
that defines the node, unless the caller passes `spans: true`, in which case
the slot holds a `t:Predicator.Types.span/0` throughout instead:

```elixir
# default
{:arithmetic, :multiply, {:identifier, "a", {1, 1}}, {:literal, true, {1, 5}}, {1, 3}}

# spans: true
{:arithmetic, :multiply,
  {:identifier, "a", {{1, 1}, {1, 2}}},
  {:literal, true, {{1, 5}, {1, 9}}},
  {{1, 1}, {1, 9}}}
```

One parse produces one kind of metadata throughout; positions and spans are
never mixed within a single tree.

## Expression nodes

`t:Predicator.Parser.ast/0` is the union of these arms, each carrying its
trailing slot last:

```elixir
{:literal, value, pos}
{:string_literal, binary, :double | :single, pos}
{:identifier, name, pos}
{:comparison, op, left, right, pos}
{:arithmetic, op, left, right, pos}
{:unary, op, operand, pos}
{:membership, op, left, right, pos}
{:logical_and, left, right, pos}
{:logical_or, left, right, pos}
{:logical_not, operand, pos}
{:list, elements, pos}
{:object, entries, pos}
{:function_call, name, args, pos}
{:bracket_access, target, key, pos}
{:property_access, target, property, pos}
{:duration, units, pos}
{:relative_date, duration, direction, pos}
```

## Object keys

Object keys have their own node - `{:object_key, value, style, pos}` - rather
than reusing an expression tag, so nothing tells a key from an expression by
tuple arity alone. `style` is `:identifier`, `:double`, or `:single`,
recording whether the key was written bare (`{name: 1}`), double-quoted
(`{"name": 1}`), or single-quoted (`{'name': 1}`), so
`Predicator.Visitors.StringVisitor` can decompile it back exactly as written.
An `{:object, entries, pos}` node's `entries` are `{object_key, expression}`
pairs.

## Statement nodes

`{:program, statements, pos}` and `{:assignment, lhs, rhs, pos}` are produced
only by `Predicator.Parser.parse_program/2`, the statement entry point
alongside `parse/2`. Neither is a member of `t:ast/0`: `parse/2` never returns
one, and an expression consumer never has to handle one.

```elixir
{:program, [statement], pos}
{:assignment, lhs, rhs, pos}
```

`lhs` in an assignment node is the unflattened access chain the parser already
builds for postfix expressions - an `{:identifier, ...}` optionally wrapped in
any number of `{:property_access, ...}` and `{:bracket_access, ...}` nodes -
kept as a chain rather than resolved to a path, because a bracket key can be
an arbitrary expression that only resolves against a context at runtime;
`Predicator.ContextLocation.resolve/2` does that resolution. The point
position is the `=` token; the span (under `spans: true`) runs from the `lhs`
start to the `rhs` end.

## Which token a node blames

Leaves point at their own token. Everything else points at the token that
*names the operation*, so an error names the thing that failed rather than the
start of the subexpression it failed on - `a * true` reports column 3, not
column 1:

| Node | Defining token |
|---|---|
| literals, identifiers, object keys | own token |
| `comparison`, `arithmetic`, `membership`, `logical_and`, `logical_or` | the operator |
| `unary`, `logical_not` | the operator |
| `list`, `object`, `bracket_access` | the opening bracket or brace |
| `function_call` | the name token |
| `property_access` | the `.` |
| `duration` | its first number |
| `relative_date` | the direction keyword (`ago`, `from`, `next`, `last`) |

A new node type follows this rule: point it at the token a reader would blame.

## Which characters a node covers

A point position tells a caller where to put a caret; a span tells it what to
underline. A span names the position one past a node's last character, so on a
single line `end_column - start_column` is the length and a zero-width range
is representable. This matches LSP ranges.

Where the table above says which token to *blame*, this one says which
characters to *underline*. A new node type needs a row in both:

| Node | Span start | Span end |
|---|---|---|
| `literal` | own token | own token end |
| `string_literal` | own token, opening quote included | own token end, past the closing quote |
| `identifier` | own token | own token end |
| `object_key` | own token, opening quote included if quoted | own token end |
| `comparison`, `membership` | left operand start | right operand end |
| `arithmetic` | left operand start | right operand end |
| `logical_and`, `logical_or` | left operand start | right operand end |
| `unary`, `logical_not` | the operator token | operand end |
| `list` | the `[` token | past the `]` token |
| `object` | the `{` token | past the `}` token |
| `function_call` | the name token | past the `)` token |
| `bracket_access` | target expression start | past the `]` token |
| `property_access` | target expression start | property-name token end |
| `duration` | its first number token | past the last duration unit |
| `relative_date` (`ago`) | duration start | past the `ago` token |
| `relative_date` (`from now`) | duration start | past the `now` token |
| `relative_date` (`next`, `last`) | the direction keyword token | duration end |
| parenthesized expression | the `(` token | past the `)` token |

Two consequences follow from this table: a quoted string's and a `#`-fenced
date's span include their delimiters, because the lexer's token length is the
full source extent; and an empty `[]`, `{}`, or `f()` still spans both
delimiters, because the end comes from the closing token rather than from a
child.

A parenthesized expression's span includes its parentheses and composes to the
outermost pair.
