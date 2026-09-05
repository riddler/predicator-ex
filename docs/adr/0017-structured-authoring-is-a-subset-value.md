# ADR-0017: Structured authoring is a subset value over the AST, not a second grammar

Status: accepted (2026-09-05, campaign-030; proposed 2026-09-04, campaign-028)

## Context

Consumers in this family want to author a condition without typing one. A
picklist - a row of dropdowns reading *field*, *operator*, *value*, with a
connective between rows - is the shape a non-developer can fill in, and it is
the shape `statifier-ui` and `statifier_blocks` need in order to offer
condition editing beside the free-text field they already have. A picklist can
only offer what it can render, so something has to say which expressions are
picklist-shaped and which are not.

Two routes were considered before this one and both were rejected.

**A restricted parser mode.** `Predicator.parse/2` would take an option that
makes it accept only the picklist-shaped subset and reject everything else.
This gives one language two acceptors, chosen by a flag, and every stage below
the parser then has to know which one ran: the compiler, the decompiler, the
error surface, and the conformance corpus each acquire a variant. It is also
wrong about the question being asked. `(amount >= 500 AND status == 'active')
OR plan == 'pro'` is not an error - it is a perfectly good predicator
expression that a picklist cannot draw - and a parser mode reports it as a
parse failure, which is a lie a host would then have to translate back.

**A second grammar upstream.** The consumer defines its own JSON predicate AST,
authors into that, and compiles it down to predicator source when it needs to
evaluate. This is the route that looks cheapest at the component and is the
most expensive everywhere else: two representations of one predicate, each
needing its own serialization, its own migration story when a field is added,
and a compiler between them that is a second implementation of predicator's
precedence rules maintained by people who do not own predicator. It also
breaks the family's standing arrangement that predicator is the *only*
expression language in it - a chart condition, a guard, and a picklist row
would stop being the same artifact.

**The pieces to do it as a value already exist.** `Predicator.parse/2`
(`lib/predicator.ex`) takes source text and returns an AST;
`Predicator.decompile/2` (`lib/predicator.ex`) takes an AST and returns source
text, with formatting options. (`Predicator.Parser.parse/2` in
`lib/predicator/parser.ex` is the *token*-taking function one layer down, not
the source-taking one; a reader reaching for the entry point wants
`Predicator.parse/2`.) `Predicator.Vocabulary` is already the public,
lexer-synced enumeration of the operator table, built for exactly this class of
editor tooling. Nothing about picklist authoring needs new grammar; it needs a
predicate over the AST plus a name for the answer.

**The boundary question is mixed `and`/`or`.** Everything else about the subset
falls out of what a row of dropdowns can show. Mixed precedence does not: a
picklist *could* grow grouping affordances - nesting, indentation, a parenthesis
control - and each step in that direction is a step back toward a free canvas
that renders arbitrary trees, which is the interface the picklist exists to
avoid. The alternative is a hard edge and a text field behind it.

## Decision

**The picklist-authorable subset is a value, `Predicator.Simple`, computed from
the AST. The parser has no mode, there is no second grammar, and an expression
outside the subset is a normal predicator expression that the subset simply
does not describe.**

### The subset is a value, with a total classifier (D28-1)

`Predicator.Simple` is a struct with four functions across the seam:

- **`from_ast/1` is total: `{:ok, t()} | :outside`.** It never raises and has
  no error arm, because it is handed an AST that already parsed - the only
  question left is whether that AST is picklist-shaped.
- **`from_source/1` adds the parse arm: `{:ok, t()} | :outside |
  {:error, ParseError.t()}`.** Three answers, because there are three
  situations: this is picklist-shaped, this is valid predicator that a picklist
  cannot draw, and this is not predicator at all. Collapsing the middle two is
  the mistake the rejected parser mode makes.
- **`to_ast/1` returns the AST**, which is the value every existing predicator
  entry point already accepts.
- **`to_source/2` returns source text, via `decompile/2`.** It is not a second
  renderer: it is a call into the one this repo already ships, and it takes the
  same options, so `:parentheses` and `:spacing` reach structured authoring for
  free and the two can never disagree about how an operator is spelled.

`:outside` is a bare atom rather than `{:error, :outside}` deliberately. Being
outside the subset is not a failure, and a consumer that pattern-matches it as
one will report it to an author as one. Under ADR-0004 errors are values; this
is the other half of that discipline - a non-error is not dressed as an error
either.

**Two round-trip laws hold, and are the implementation's obligation:**

1. `from_ast(to_ast(s)) == {:ok, s}` for every `s` the constructor can produce.
   A subset value survives the trip out to the AST and back unchanged.
2. `to_source(s)` parses to an AST equal to `to_ast(s)`, modulo positions.
   Positions are source coordinates and a rendered string has its own; equality
   that included them would be asserting that the renderer reproduces the
   original whitespace, which is not a property anyone wants.

### Mixed `and`/`or` is `:outside`, by decision (D28-3)

**A subset value is a list of clauses under a single connective.**
`connective` is `nil` for exactly one clause - a lone clause is joined to
nothing, and `status == 'active'` by itself is inside the subset and is the
commonest picklist state there is - and it is `:and` or `:or` for two or more.
A mixture at any depth is `:outside`, and so are parentheses, `not`,
arithmetic, and function calls, by the same decision and for the same reason.

So these are inside:

```
plan == 'pro'
status == 'active' AND amount >= 500
step in ['payment', 'review'] OR plan == 'pro'
```

and this is outside:

```
(amount >= 500 AND status == 'active') OR plan == 'pro'
```

**This is a scope boundary, not a limitation.** A picklist that offers grouping
is the canvas problem again: the moment the UI can nest, it has to render
arbitrary trees, show precedence it did not author, and offer a control for
every level of depth - which is the general expression editor the picklist was
introduced instead of. An author who needs `(a AND b) OR c` types it, and the
component shows the text. That is a complete answer, and this ADR records it as
one rather than as a gap with a schedule attached.

### Two exclusions that are not decisions

Everything excluded above is excluded by this decision, on purpose. Two further
value kinds are outside the subset today for reasons that are not decisions at
all, and a reader must not mistake one kind of exclusion for the other.

**A float is outside contingently, and only until a defect is fixed.**
`Predicator.decompile/2` raises a `FunctionClauseError` on a float literal:
`Predicator.Visitors.StringVisitor`'s literal clause guards `is_integer(value)`
and the module has no `is_float/1` clause, while `Predicator.parse/2` produces
a float literal from `amount == 1.5` without complaint - so parse-then-decompile
is partial today for any float. `to_source/2` runs through `decompile/2` and the
subset promises totality, so a float value kind cannot be admitted while that
holds. The defect is tracked as **px-ggb**, the exclusion is pinned by a test
asserting that a float source parses and classifies `:outside`, and admitting
the value kind once px-ggb lands is a small change that flips that test.
Nothing about a float is unsuited to a picklist.

**A negative number is outside structurally.** `Predicator.parse/2` reads `-5`
as a unary-minus node over a positive literal rather than as a negative
literal, so a negative value cannot reach a clause from a parse at all. That is
a fact about the AST rather than a decision taken here, and it is not a defect.

### The operator table has one source

An operator a picklist offers is an entry in `Predicator.Vocabulary`, and
`Predicator.Simple` names the subset of those entries a clause may use. It does
not carry a table of its own, and neither does a consumer. `Vocabulary` is
already bound to the lexer by `test/predicator/vocabulary_sync_test.exs`, so an
operator added to the grammar without an entry turns the suite red; a second
table beside it would be a copy with no such binding, kept in sync by whoever
last remembered. Where structured authoring needs a field `Vocabulary` does not
yet expose, **the field is added to `Vocabulary` itself**, not to `Simple` and
not to the consumer.

## Consequences

- **The component stores source text and owns no second representation.** What
  a picklist saves is a predicator expression; what it loads is a predicator
  expression; `Predicator.Simple` is the lens it looks through in between and
  is never itself persisted. There is no JSON predicate AST upstream, no
  migration between two shapes of the same predicate, and no second
  implementation of precedence in a component library. Predicator stays the
  only expression language in the family.

- **An expression outside the subset degrades to text, and nothing is lost.**
  The component shows the source in its free-text field, the expression
  evaluates exactly as it always did, and switching a stored expression from
  picklist authoring to text authoring and back costs nothing because both are
  views of one string.

- **Nothing under `lib/` moves except an addition.** No parser option, no lexer
  change, no new opcode, no ISA version, and no conformance corpus entry: the
  corpus pins evaluation semantics, and this decision adds no semantics.
  The Ruby and JavaScript siblings owe nothing - `Predicator.Simple` is an
  Elixir value over an Elixir AST, and a sibling may add its own classifier,
  or none, without divergence.

- **Widening the subset later is additive; narrowing it is breaking.** An
  expression that answered `{:ok, s}` and later answers `:outside` takes a
  working picklist away from an author who had one, so removals need the same
  care as any public-surface removal. Additions are a minor release.

- **A function-call clause kind is explicitly not in scope, and is the first
  follow-up candidate.** `len(name) > 3` is the shape - a call on the left of a
  comparison - and it is the one exclusion taken *by decision* with an obvious
  picklist rendering, since a function with a fixed arity is a dropdown plus its
  arguments. It is left out here because it needs its own decisions (which
  providers a consumer may offer, and what an editor shows for a function whose
  `:doc` is `nil` under ADR-0014) and because leaving it out costs an author
  nothing today. It is recorded as the next question, not as owed work.

- **Status is `proposed`.** Per `docs/adr/README.md`, an agent may draft and
  only the maintainer accepts; the flip to `accepted` is a separate reviewed
  change.

## Notes

### 2026-09-05: the float exclusion is lifted

The contingent exclusion recorded under "Two exclusions that are not
decisions" has resolved on both halves, and a float is inside the subset as of
predicator 9.3.0.

- [#209](https://github.com/riddler/predicator-ex/pull/209) closed **px-ggb**:
  `Predicator.Visitors.StringVisitor` gained its `is_float` literal clause, so
  parse-then-decompile is total for a float literal and `to_source/2` can
  render one.
- [#211](https://github.com/riddler/predicator-ex/pull/211) removed the
  exclusion: `Predicator.Simple` reads a non-negative float as a new
  `{:float, value}` scalar shape under the existing `:number` value kind, and
  the test that pinned a float source as `:outside` now pins the opposite.

The paragraph above stands as the record of why the exclusion existed and on
what it was contingent; this Note records only that the contingency is spent.

The negative-number exclusion beside it is untouched and is still structural -
a negative float stays outside for the same reason a negative integer does.

### 2026-09-05: the status is now `accepted`

The Consequences list's last bullet reads "Status is `proposed`" and describes
the state this record was drafted in. That state has ended: the maintainer's
campaign-030 grant accepted this record on 2026-09-05 and the header above
says so. The bullet stands as written, under the same amend-by-addition rule
as the paragraph above; this Note is the forward pointer it would otherwise
lack.

### 2026-09-05: which paragraph the first Note means

The first Note above closes "The paragraph above stands as the record of why
the exclusion existed and on what it was contingent", and does not name the
paragraph. It is not the bullet list of pull requests immediately above that
sentence. It is the paragraph opening **"A float is outside contingently, and
only until a defect is fixed."**, under "Two exclusions that are not
decisions" in the Decision section - the paragraph that states the exclusion,
the missing `is_float/1` clause behind it, and the **px-ggb** contingency it
was held on. That paragraph stays as written. Naming it here rather than
editing the Note keeps this record amend-by-addition, under the dated-note
form in `docs/adr/README.md`.

### 2026-09-05: "four functions" names the seam, not the export count

The Decision's first sentence reads "`Predicator.Simple` is a struct with four
functions across the seam", and the four bullets that follow it enumerate what
it counts: `from_ast/1`, `from_source/1`, `to_ast/1`, and `to_source/2`. Those
are the functions that carry a value **across** the seam between an AST and a
picklist, which is the decision this section is making.

`Predicator.Simple` exports eight functions as of predicator 9.4.0 - the four
above plus `well_formed?/1`, `duration_units/0`, `value_kind/1`, and
`operators/1` - so a cold reader can take the sentence for an inventory that
has gone stale. It is not one. The other four answer questions *about* the
subset and cross nothing; the sentence was never a count of the module's
exports, and it does not become wrong as more of them are added.

Nothing above changes. This Note records only which reading of "four" is the
intended one. It was raised by the direction review on
[#218](https://github.com/riddler/predicator-ex/pull/218), which accepted this
record, and recorded by
[#221](https://github.com/riddler/predicator-ex/pull/221) under **px-353**.
