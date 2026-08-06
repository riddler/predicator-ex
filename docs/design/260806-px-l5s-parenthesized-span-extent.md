# A parenthesized expression's span includes its parentheses

Bead: px-l5s. Status: proposed (2026-08-06), awaiting review.

px-3kr shipped source spans with decision 4: a parenthesized expression's span
*excludes* its parentheses, because parentheses build no AST node. This decides
the follow-up the bead names, reversing that decision. It settles the span
extent only; nothing about the AST shape, the metadata slot's polymorphism
(px-3kr decision 1), or point-position mode is revisited.

## Decision summary

**Option 1: in span mode, the `:lparen` clause of `parse_primary_token/2`
rewrites the inner expression's trailing slot to the span of `(` through past
`)`, and returns that node.** No new node type, no AST shape change, no visitor
learns anything, and position mode pays nothing.

The rule is one sentence: *a span covers the outermost parentheses that enclose
the node's own text.* `(a + b)` gives the `arithmetic` node the span of
`(a + b)`, and `(a + b) * c` gives the `multiply` node the whole source string.

**Rejected: option 2, a paren node behind the spans flag.** It preserves both
the inner and outer extents, but it makes span mode produce a *different AST
shape*, not merely a different metadata slot. That is the exact line px-3kr
decision 1 drew: the slot is polymorphic, the shape is not. Every visitor
(`StringVisitor`, `InstructionsVisitor`), the evaluator's pattern space, and
every consumer that matches on node tags would have to learn a node that exists
only when the caller passed `spans: true` - and `InstructionsVisitor` would
have to be careful to emit *nothing* for it, so that the byte-identical
instruction list that `compile_with_spans/1` guarantees stays byte-identical.
That is a large, permanently load-bearing cost for a distinction (section
"What is lost") that a consumer can recover from the source text in one line.

## Does this change the instruction set?

**No.** Stated explicitly because ADR-0001 makes the instruction set the
cross-language interchange format shared with the Ruby and JavaScript siblings,
so any change to it is not local to this repo.

Nothing here touches opcodes, operands, or their order. Spans live in the
parser's AST metadata slot and travel to callers through
`Predicator.compile_with_spans/1`'s *side table*; the instruction list that
function returns is byte-identical to `compile/1`'s, and the integration test
that pins that identity is unaffected. The siblings do not implement spans at
all, and this decision creates no obligation for them to. It is a
single-language refinement of an Elixir-only, opt-in output.

## Why widening is the right direction

The decisive asymmetry is **recoverability**.

- Under the current behavior, a consumer that wants the balanced extent has to
  re-lex the source to find the enclosing parentheses - which is what
  `docs/architecture.md` already tells it to do, and why the limit was
  documented rather than worked around.
- Under the widened behavior, a consumer that wants the inner extent slices the
  span and trims the balanced parens off the ends. That is a few lines against
  a string it already has, with no parser and no token stream.

Widening is also the direction every editor-facing consumer wants by default.
The span exists to answer "what do I underline"; LSP diagnostics, tree-sitter's
`parenthesized_expression`, and effectively every language server underline the
parens along with the expression, because an unbalanced squiggle reads as a
rendering bug. The current `a + b) * c` slice is exactly that.

## What is lost, and whether it matters

`a + b` and `(a + b)` become indistinguishable *by span*. Weighed against the
three consumers that could plausibly care:

- **Editor squiggle / diagnostic range.** Improved, not harmed. Underlining
  `(a + b) * c` for a type error in the multiply is correct; underlining
  `a + b) * c` is not.
- **Error caret.** Unaffected. A caret comes from the *point* position, which
  this does not move (px-3kr decision 5), and position mode is untouched.
- **Formatter / round-tripper.** Unaffected, because it never had this
  information to lose. Predicator's AST has never recorded that parentheses
  were present; `StringVisitor` re-inserts them from precedence. A formatter
  that wanted to preserve an author's redundant parens could not have done so
  before this change either, and option 2 is the only design that would give it
  that - which is a real argument for option 2 *if that feature is ever
  wanted*, and is listed under "What would change this decision".

The genuine loss is a consumer that wants to underline only the operands of a
parenthesized subexpression. It gets the trim described above.

## Consequences the bead does not spell out

**A parenthesized leaf widens too.** `(a)` gives the `identifier` node the span
of `(a)`, parens included. This is accepted deliberately rather than special-
cased: a rule that widens compound expressions but not leaves would need a
consumer to know the node's arity to predict its span, and it would be stated
in two sentences instead of one. The degenerate case is also rare and low-stakes
- nobody writes `(a)` in a predicate except transiently.

**Nesting composes to the outermost pair.** `((a))` widens twice: the inner
`:lparen` clause rewrites the identifier's slot to `(a)`, then the outer clause
rewrites the same node's slot to `((a))`. Each rewrite replaces the slot rather
than merging, so the result is the outermost pair, and the intermediate extent
is not retained. That is the correct reading of the rule as stated.

**Upward propagation is exactly the effect wanted.** `binary_loc/4` composes
`{node_start(left), node_end(right)}` and `prefix_loc/3` composes
`{point, node_end(operand)}`, both reading the child's already-written slot. So
for `(a + b) * c`, the left child's slot is `{{1, 1}, {1, 8}}` before
`binary_loc/4` runs, and the `multiply` node's span becomes `{{1, 1}, {1, 12}}`
- the whole source, which is the bead's acceptance criterion. No helper changes;
the widening propagates because the helpers were already written to read
children rather than tokens.

**The nesting invariant still holds.** Widening a child could in principle push
it outside its parent, and the corpus test in
`test/predicator/integration/spans_test.exs` asserts it never does. It cannot
here, because every parent derives its extent either from the child itself
(`binary_loc/4`, and `property_access`/`bracket_access` targets - the widened
start becomes the parent's start) or from an opening token that necessarily
precedes the `(` and a closing token that necessarily follows the `)`
(`delimited_loc/3` for lists, objects, and function calls; `prefix_loc/3`'s
operator token). Both parenthesis tokens are consumed inside the enclosing
production, so they are inside the enclosing extent by construction.

**Position mode pays nothing, and the implementation is confined to one
clause.** The `:lparen` clause already has both tokens in scope - the `(` in
the function head and the `)` in the `{:rparen, ...}` match that currently
discards it. The rewrite is a `put_elem/3` on the returned node's last element,
behind a private helper that dispatches on `spans?` the way `loc/3` does, with
the `%{spans?: false}` clause returning the node unchanged. `loc/3` itself
cannot be reused directly, because it yields a *position* and what is needed
here is a *node*; the helper mirrors its two-clause shape rather than wrapping
it, which preserves the same laziness guarantee - no span tuple is built and no
tuple is copied in the default mode.

## What else moves

- `docs/architecture.md`, "Source Spans": the "Parentheses are excluded, by
  design" paragraph and its knock-on paragraph are replaced by a statement of
  the widening rule, and the "Which characters a node covers" table gains a row
  for it.
- `test/predicator/integration/spans_test.exs`: the test named "a span stops at
  the inner expression, not at the parentheses" is re-pinned to the new slices
  (`(a + b)` for the left child, the whole source for the outer), renamed, and
  gains a nested `((a))` case and a `(a)` leaf case.
- `CHANGELOG.md`, under `## [Unreleased]`: this is user-facing behavior for
  anyone consuming `spans: true`.
- px-3kr's plan document is **not** rewritten. Its decision 4 stays visible as
  the path taken, superseded by this document, on the same principle
  `docs/adr/README.md` states for ADRs.

## Why this is not an ADR

The repo's ADRs are architecture-level and cross-language: ADR-0001 is the
instruction set, ADR-0002 is a grammar break that invalidates stored user
predicates. This is neither. It refines the extent of an opt-in, Elixir-only
metadata value shipped one release ago, changes no instruction, breaks no
stored predicate, and binds no sibling implementation. It belongs beside the
plan it amends, in `docs/design/`, keyed to its bead.

## Open questions

- **No editor integration was available to confirm what it wants underlined.**
  The bead asks for that confirmation and it could not be obtained: statifier is
  the only known consumer outside this repo, it does not use spans, and no
  human was available to ask. The decision rests instead on the recoverability
  asymmetry above, which does not depend on the answer - the widened form can
  be narrowed cheaply, so a consumer that turns out to want the inner extent is
  not blocked, whereas today's form leaves a consumer that wants the balanced
  extent with a re-lex. If a real integration later reports it wants both
  extents simultaneously, that is the option 2 trigger below.
- **Whether the whitespace inside parens should be trimmed** - `( a + b )`
  widens to the full extent including the interior spaces, which is what the
  parens delimit and is consistent with how quoted strings include their
  delimiters. Recorded as noticed and deliberately not special-cased.

## What would change this decision

- **A formatter or round-tripper that must preserve an author's parentheses.**
  Spans cannot carry that, and neither could the pre-change behavior; it needs
  option 2's node, or a separate paren flag on the node, and it would be its
  own bead with its own visitor cost.
- **A consumer that genuinely needs both extents at once** - not "wants the
  inner one", which the trim answers, but needs to distinguish `a + b` from
  `(a + b)` structurally. That is the only evidence that would make option 2's
  cost worth paying.
