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
{:cast, expression, type_name, pos}
{:duration, units, pos}
{:relative_date, duration, direction, pos}
```

`type_name` in a `cast` node is one of the seven scalar ISA type names
(`integer`, `float`, `string`, `boolean`, `date`, `datetime`, `duration`),
held as a binary; the parser rejects any other name, so a `cast` node can
never carry an invalid target. The names are contextual identifiers, not
keywords - they are only special immediately after `::`
([ADR-0011](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0011-casts-are-an-opcode.md)).

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

`{:program, statements, pos}`, `{:assignment, lhs, rhs, pos}`,
`{:if, condition, then_block, else_block, pos}`,
`{:while, condition, body, pos}`, and `{:block, statements, pos}` are produced
only by `Predicator.Parser.parse_program/2`, the statement entry point
alongside `parse/2`. None of the five is a member of `t:ast/0`: `parse/2`
never returns one, and an expression consumer never has to handle one.

```elixir
{:program, [statement], pos}
{:assignment, lhs, rhs, pos}
{:if, condition, then_block, else_block, pos}
{:while, condition, body, pos}
{:block, [statement], pos}
```

`lhs` in an assignment node is the unflattened access chain the parser already
builds for postfix expressions - an `{:identifier, ...}` optionally wrapped in
any number of `{:property_access, ...}` and `{:bracket_access, ...}` nodes -
kept as a chain rather than resolved to a path, because a bracket key can be
an arbitrary expression that only resolves against a context at runtime;
`Predicator.ContextLocation.resolve/2` does that resolution. The point
position is the `=` token; the span (under `spans: true`) runs from the `lhs`
start to the `rhs` end.

`condition` in an if node is a bare expression; `then_block` is always a
`{:block, statements, pos}`, never `nil`. `else_block` is `nil` when there is
no `else` and a `{:block, statements, pos}` when there is - including for
`else { }`, whose empty block stays distinguishable from an absent one
([ADR-0013](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0013-control-flow-lowers-to-new-jump-opcodes.md)). A block
introduces no scope: its `statements` are ordinary program statements, and a
`store` inside one is visible after the block.

`else if c2 { B }` is parser sugar with no chain node of its own: it parses as
an `else_block` holding a single-statement block whose one statement is the
nested `{:if, ...}`. For

```
if a { x = 1 } else if b { x = 2 } else { x = 3 }
```

the outer node's `else_block` is `{:block, [{:if, b, ..., ...}], pos}` - a
block wrapping the `if b { x = 2 } else { x = 3 }` node, not a three-way
chain. That synthetic block's own trailing slot is the nested `if` node's own
slot, so it needs no position of its own: in point mode it is the nested `if`
token, and under `spans: true` it is the nested `if`'s span, which already
starts at the same token and runs through the same final `}`.

Neither `if` nor `block` is a member of `t:ast/0`, the same as `program` and
`assignment`. `while` follows the same rule: `condition` in a while node is a
bare expression, `body` is always a `{:block, statements, pos}`, and the body
introduces no scope any more than an `if`'s blocks do - a `store` inside it is
visible after the loop.

`InstructionsVisitor` compiles the `program`, `assignment`, `if`, `while`, and
`block` nodes today. A `{:program, statements, pos}` compiles each statement in
order, concatenating the results; a `{:block, statements, pos}` compiles the
same way - a block introduces no scope of its own, so it is a plain statement
sequence. An `{:assignment, lhs, rhs, pos}` compiles to the `lhs` chain's
segments (root-to-leaf), then `rhs`, then `["store", n]`, where `n` is the
chain's segment depth; any other statement compiles to its own instructions
followed by `["pop"]`. That trailing `["pop"]` is emitted uniformly, including
after the program's last statement, so the stack is empty at every statement
boundary - **except an `if` or `while` statement**, neither of which, unlike
every other non-assignment statement, takes a trailing `["pop"]`: an `if`'s
condition is consumed by `pop_jump_if_falsy` and its blocks are already
stack-neutral by construction, and a `while`'s condition is consumed by
`pop_jump_if_falsy` on every iteration including the last, so in both cases
nothing is left for a `pop` to remove
([ADR-0013](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0013-control-flow-lowers-to-new-jump-opcodes.md)).

`{:if, condition, then_block, nil, pos}` (no `else`) lowers to `condition`'s
instructions, then `["pop_jump_if_falsy", offset]` sized to land one past the
then block, then the then block's own instructions.
`{:if, condition, then_block, else_block, pos}` (with an `else`) lowers to
`condition`, `["pop_jump_if_falsy", offset]` sized to land one past an
unconditional `["jump", offset]` appended after the then block, the then
block, that `jump` (sized to land one past the else block), then the else
block. Both the `pop_jump_if_falsy` and the `jump` carry the `if` node's own
position, not the condition's.

`{:while, condition, body, pos}` lowers to `condition`, then
`["pop_jump_if_falsy", offset]` sized to land one past a `["jump_backward",
offset]` appended after the body, the body's own instructions, then that
`jump_backward` - `c; ["pop_jump_if_falsy", lenA + 2]; A; ["jump_backward",
lenC + lenA + 1]` for `while c { A }` (ISA v6, ADR-0013). The `jump_backward`'s
offset is measured from its own index back to `condition`'s first
instruction, which is why it counts `lenC` as well as `lenA`. Both the
`pop_jump_if_falsy` and the `jump_backward` carry the `while` node's own
position, not the condition's. Execution of any compiled program containing a
`jump_backward` is bounded by the evaluator's loop budget (`docs/isa.md` §2,
§5) - a normal, expected part of running a `while` loop, not an error path.

In point mode the compiled `["store", n]` instruction is annotated with the
`lhs` root segment's own position rather than the assignment node's `=`, so a
store failure's caret lands on the location being written; under
`spans: true` it keeps the assignment's span, whose start is already that same
token.

Alongside that per-instruction position table, compiling an assignment also
produces a per-*segment* table: one source annotation per `lhs` location
segment, root-first, keyed by the `["store", n]` instruction's own index. A
segment's annotation is the annotation of the node that produced its value -
the `{:identifier, ...}` node for the root, the `{:property_access, ...}` node
for a dotted segment, and the key expression for a bracket segment, since the
key is what a bad or out-of-range segment value came from. The list's length
is the chain's segment depth, which is exactly `["store", n]`'s own operand,
so `n` bounds the index into it. Because a `property_access` node's point
position is the property-name token (see "Which token a node blames" below), a
dotted segment's point position names the property itself - for `a.b.c`, the
segment for `.b` points at column 17 in `a = {"b": 1}; a.b.c = 2`, `b` itself.
And because a `property_access` node's span starts at the chain root (see
"Which characters a node covers" below), narrowing a store failure to one
segment's span moves only the underline, never the caret - the segment for
`.b` in that same source spans `a.b`, whose start is still `a`, at column 15.
The point-mode caret (column 17) and the span-derived caret (column 15) are
deliberately different answers to different questions: the point names the
value that failed, the span's start names where the accessed location begins.

`docs/isa.md` §5 is the normative statement of `store`'s and `pop`'s
stack discipline and error shapes; this page only says what AST shape feeds
them.

## Which token a node blames

Leaves point at their own token. Most non-leaf nodes point at the token that
*names the operation*, so an error names the thing that failed rather than the
start of the subexpression it failed on - `a * true` reports column 3, not
column 1. `bracket_access` and `property_access` are the deliberate exception:
an access node blames the accessed operand instead, because for an access the
thing that failed is the property or key, not the punctuation that reached it
(the `.` or `[`). For a compound key the point is the key expression's first
token - `a[x + 1]` blames the `x`, not the `+` - which coincides with the
key's own blame position only when the key is a single token, as in
`user.name`:

| Node | Defining token |
|---|---|
| `literal`, `string_literal`, `identifier`, `object_key` | own token |
| `comparison`, `arithmetic`, `membership`, `logical_and`, `logical_or` | the operator |
| `unary`, `logical_not` | the operator |
| `list`, `object` | the opening bracket or brace |
| `function_call` | the name token |
| `bracket_access` | the first token of the key expression |
| `property_access` | the property-name token |
| `cast` | the type-name token |
| `duration` | its first number |
| `relative_date` | the direction keyword (`ago`, `from`, `next`, `last`) |
| `if` | the `if` keyword |
| `while` | the `while` keyword |
| `block` | the opening `{` token |
| a desugared else-if's synthetic block | the nested `if` keyword |

A new node type follows this rule: point it at the token a reader would blame.

The same rule governs a statement's compiled instructions, not just a node's
own point position: **blame lands on the token carrying the type rule that was
violated.** `if` and `while` each carry one (a boolean condition), the same way
`*` carries one (numbers) and `and` carries one (booleans), so their
`pop_jump_if_falsy` (and `if`'s `jump`, and `while`'s `jump_backward`) is
annotated with the statement keyword's own position, not the condition's - see
the `if` and `while` rows above and their lowering sentences earlier on this
page. `store_annotation/2` looks like a counterexample - `["store", n]` is
annotated with the `lhs` root's position, not the assignment's `=` - but `=`
carries no type rule at all; an assignment accepts any rhs, so when a store
fails the `=` has nothing to say about it and the location being written is
the only token that does. That is a single, closed exception, not the first of
a series: it is what happens when the operator has no rule to point at, not a
license to move blame off any other operator with one.

## Which characters a node covers

A point position tells a caller where to put a caret; a span tells it what to
underline. A span names the position one past a node's last character, so on a
single line `end_column - start_column` is the length and a zero-width range
is representable. This matches LSP ranges.

For most tokens that exclusive end is computed from the start position plus
the token's length. `:string` is the exception: because a string literal can
span multiple lines, its end position is not computed - it is read directly
off the token, which carries its own explicit end position for exactly this
reason. That is what keeps a multi-line literal's span correct.

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
| `cast` | target expression start | type-name token end |
| `duration` | its first number token | past the last duration unit |
| `relative_date` (`ago`) | duration start | past the `ago` token |
| `relative_date` (`from now`) | duration start | past the `now` token |
| `relative_date` (`next`, `last`) | the direction keyword token | duration end |
| parenthesized expression | the `(` token | past the `)` token |
| `if` | the `if` token | past the last block's `}` (the else block's if present, otherwise the then block's) |
| `while` | the `while` token | past the body block's `}` |
| `block` | the `{` token | past the `}` token |
| a desugared else-if's synthetic block | the nested `if`'s own span start | the nested `if`'s own span end |

Two consequences follow from this table: a quoted string's and a `#`-fenced
date's span include their delimiters, because the lexer's token length is the
full source extent; and an empty `[]`, `{}`, `f()`, or `{ }` block still spans
both delimiters, because the end comes from the closing token rather than
from a child.

A parenthesized expression's span includes its parentheses and composes to the
outermost pair.
