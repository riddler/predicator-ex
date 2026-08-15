# Should the span shape move toward statifier's Location?

Bead: px-hku (filed from px-dmt's open question 1)
Date: 2026-08-14
Decision: **no, twice. (a) `t:Predicator.Types.span/0` does not gain byte
offsets - the arithmetic statifier's `Location` moduledoc describes is
performed nowhere in statifier-ex, so the only demand for offsets is
aspirational prose, and the cost would land on every span-table entry riding
on every `%Predicator.Compiled{}`. (b) The parser error boundary stays the
px-dmt 5-tuple and the error structs stay as they are - the named-field
readability statifier's `Location` provides already exists here at the layer
diagnostics actually read (`%ParseError{}`'s `:message`, `:position`,
`:span`), and the one downstream caller of the raw tuple boundary is a
failure-path re-parse that statifier's own st-57w slates for deletion.** No
file changes follow from either answer, so no implementation bead is filed.

This is a shape-of-a-public-type call, but both answers are "keep what
exists", grounded in an empirical reading of the one downstream consumer
rather than in a new architectural commitment. It changes no opcode, no
grammar, no compiled artifact, and no rule - ADR-0003 (who owns the shape),
ADR-0009 (the envelope carries the table), and ADR-0015 (structured compile
errors, spans deferred to px-dmt) all stand untouched. Per
`docs/adr/README.md`'s third corollary it goes to `docs/research/`, named
after the bead, with `260807-px-phw-conformance-area-label.md` as the model.
No ADR was written. If a consumer ever files a bead with a real call site
that needs byte offsets, *that* decision would be ADR-shaped; this one is the
finding that no such call site exists today.

## The two questions, as filed

px-dmt chose a 5-tuple `{:error, message, line, column, span}` at the parser
boundary over a struct, noting a struct "can still be done later on its own
major version". Before that reshape is designed, px-hku asks two things
against `Statifier.Parser.Location` - flat named fields (`start_line`,
`start_column`, `end_line`, `end_column`), byte offsets (`start_offset`,
`end_offset`), exclusive end:

1. Should `t:Predicator.Types.span/0` carry byte offsets? Statifier's
   `Location` moduledoc claims it keeps offsets so that
   "`value_location.start_offset + span.start` is a byte offset" - i.e. so a
   predicator expression-relative span translates into a document position by
   arithmetic. The bead's instruction: verify whether that cost is actually
   being paid, from the call sites, not the prose.
2. Should the parser error boundary and the error structs move from tuples
   to a named struct in statifier's flat-named-field shape?

Under ADR-0003 this repo owns the span shape; statifier's bead is
authoritative only for how statifier consumes it. Matching statifier is a
candidate, not an obligation - and statifier's own ADR-0014 is the precedent
for influence running the other way: its `Location` took the exclusive-end
convention *from* predicator's span ("the shape ADR-0014 fixed for
expression spans, used here for XML nodes so the two compose",
`lib/statifier/parser/location.ex` moduledoc).

## Ground truth: what statifier-ex actually does (read 2026-08-14, statifier-ex@d65b47c)

Every claim below is from the checkout at
`/Users/johnnyt/repos/github/statifier-ex`, pinned to `predicator ~> 7.0`
(`mix.exs:41`).

### The byte-offset arithmetic is performed nowhere

A grep of the whole tree (`lib/` and `test/`) for `start_offset`,
`end_offset`, and `at_offset` finds the composition
`value_location.start_offset + span.start` exactly twice - both times as
prose:

- `lib/statifier/parser/location.ex:9` - the moduledoc sentence itself.
- `lib/statifier/parser/dom/attribute.ex:9` - "an expression span is
  relative to the expression string, so `value_location.start_offset` is
  what turns it into a document position".

No code performs it. The real `start_offset` call sites fall into four
groups, none of which touches a predicator span:

- **Error ordering.** `Enum.sort_by(... location.start_offset)` at
  `lib/statifier/lowering.ex:163`, `lib/statifier/validator.ex:91`,
  `lib/statifier/compiler.ex:241` and `:1324`, and
  `lib/statifier/validator/checks/ids.ex:54`. Sorting XML-node errors into
  document order - no expression span in sight.
- **XML span construction.** `lib/statifier/parser/markup.ex:305-312` and
  `lib/statifier/parser/handler.ex:150-199` build `Location`s while
  scanning the SCXML source.
- **Saxy error conversion.** `lib/statifier/parser/parse_error.ex:59` and
  `:98` convert a `Saxy.ParseError` byte position via
  `Location.at_offset/2` - a *Saxy* offset, not a predicator span.
- **Slice-based tests.** `Location.slice/2` and `at_offset/2` in the
  location-accuracy and document tests, all against XML node spans.

Two further findings confirm the moduledoc is aspiration, not description:

- The prose does not even typecheck against what it names. Predicator's
  span is `{{line, column}, {line, column}}`
  (`lib/predicator/types.ex`, `t:span/0`) - a tuple with no `.start` field.
  `span.start` is written against a hypothetical named-field span that has
  never existed on either side.
- Statifier's own error carrier says the translation is deliberately *not*
  done where the predicator error is embedded, and then no reporting site
  does it either. `Statifier.Compiler.Error`'s reason typedoc: the embedded
  `%Predicator.Errors.ParseError{}` is kept "verbatim, in predicator's own
  `{line, column}` coordinate space - the translation into document columns
  happens at reporting time, not here"
  (`lib/statifier/compiler/error.ex:23-29`); the rendered message
  interpolates "predicator line #{line}, column #{column}" as-is
  (`lib/statifier/compiler/error.ex:71-75`).
  `Statifier.Evaluator.Error.new/2` lifts `:span` off the predicator struct
  with `Map.get/2` (`lib/statifier/evaluator/error.ex:44-46`) and nothing
  downstream computes with it. Statifier ADR-0014's own payoff example is
  expression-relative - "columns 22-27 of `user.age > 18 AND score > 5`
  loaded an unbound `score`" - a report in the expression's coordinate
  space, no document arithmetic.

So the cost the bead asked about is not being paid. Statifier reports
predicator failures in predicator coordinates, alongside a document-level
`Location` chosen by the caller (the attribute value span), and the two are
presented side by side, never merged.

### The raw tuple boundary has one consumer, and it is scheduled to vanish

`Predicator.Parser`, `Predicator.Lexer`, and `Predicator.parse*` appear in
statifier-ex code at exactly two call sites, both failure-path-only
re-parses that recover a structured position from the 7.0 compile facade's
formatted string:

- `lib/statifier/compiler/expressions.ex:188` -
  `{:error, message, line, column} = Predicator.parse(source, spans: true)`
- `lib/statifier/compiler/expressions.ex:195` -
  `{:error, message, line, column} = Predicator.parse_program(source)`

Both exist only because predicator 7.0's compile arm returned
`{:error, binary()}` (the module's own docs say so,
`lib/statifier/compiler/expressions.ex:65-73`). ADR-0015 (px-d71) makes the
compile arm return `%ParseError{}` directly and px-dmt puts the span on it;
statifier's st-57w (deferred to 2026-11-14) already carries the bullet to
replace the re-parse with the structured shape when it adopts 8.0. Both
sites match the 4-tuple positionally, so the 5-tuple fails their match
loudly at adoption time - the migration behaviour px-dmt chose the
appending shape for.

Everywhere else, statifier consumes the *struct*: `Statifier.Compiler.Error`
embeds `%Predicator.Errors.ParseError{}` whole in its reason union and
pattern-matches `position: {line, column}` on the named field
(`lib/statifier/compiler/error.ex:66`), and `Statifier.Evaluator.Error`
carries whichever predicator error struct came back, verbatim
(`lib/statifier/evaluator/error.ex`).

## Decision (a): no byte offsets on `t:Predicator.Types.span/0`

Four reasons, in order of weight:

1. **The demand is empirically absent.** The one consumer whose moduledoc
   motivated the question performs the arithmetic nowhere, defers the
   translation "to reporting time" and then never does it, and reports in
   expression coordinates by design (statifier ADR-0014 item 4). Widening a
   public type for a sentence of prose is building for a caller that does
   not exist.
2. **The cost is not confined to errors.** `t:span/0` is also the value
   type of `t:span_table/0` and appears in `t:segment_position_table/0`
   (`lib/predicator/types.ex`), riding as `compiled.positions` on every
   `%Predicator.Compiled{}`. Offsets take a span-table entry from four
   integers to six - a 50% size-class increase on a table statifier keeps
   in memory for every compiled `cond` for the life of a Machine, since its
   ADR-0014 item 3 makes spans always-on. Every consumer pays on every
   entry so that an error path nobody has written could someday do an
   addition.
3. **It is new lexer bookkeeping, not a repackaging.** The token type is
   `{type, line, column, length, value}` - the lexer counts lines and
   columns (codepoints), never bytes. Columns and byte offsets are not
   derivable from each other under UTF-8, so offsets mean threading a byte
   counter through the whole lexer, and the parser's `token_span/1` family
   after it.
4. **The composition statifier wants is available without offsets.** If a
   reporting site is ever written, an expression span composes with
   `value_location` by line/column arithmetic alone: a span starting on the
   expression's line 1 lands at
   `{value_location.start_line, value_location.start_column + col - 1}`,
   and a later line lands at
   `{value_location.start_line + line - 1, col}`. That helper belongs in
   statifier, next to its `Location`, and needs nothing from this repo.
   (Even byte offsets would not make the mapping exact: statifier's own
   `Attribute` moduledoc records that entity references make value-interior
   offsets diverge from raw source,
   `lib/statifier/parser/dom/attribute.ex:14-18` - a caveat offsets on our
   side would inherit, not solve.)

ADR-0003's paperwork test agrees with the outcome: the span table is never
part of the instruction list, so offsets would not move the ISA - but
`t:span/0` is a documented public type across the facade, error structs, and
`%Compiled{}`, so changing it is a major-version break for every consumer,
with no measured beneficiary. Under ADR-0003 statifier's convenience is a
downstream candidate, never an upstream constraint; the day a consumer
brings a real call site, the question reopens with evidence, and that
decision would earn an ADR.

## Decision (b): the boundary stays a 5-tuple; the structs stay as they are

1. **The named-field benefit already exists at the layer that reads it.**
   What makes statifier's `Location` pleasant in a diagnostic is named
   fields, and predicator diagnostics are read off `%ParseError{}` - which
   has them: `:message`, `:position`, `:span`. The nested tuples survive
   only *inside* those fields, and statifier already pattern-matches
   `position: {line, column}` on the struct without friction
   (`lib/statifier/compiler/error.ex:66`). Restructuring the tuple interior
   into a six-field flat struct would reshape a value every consumer
   currently destructures in one line.
2. **The raw tuple boundary's one external consumer is scheduled for
   deletion.** The two `expressions.ex` re-parse sites exist to work around
   the 7.0 string arm that ADR-0015 removed; st-57w replaces them with the
   structured `ParseError` on statifier's 8.0 adoption. A struct at the
   parser boundary would be built for a caller about to stop calling.
3. **px-dmt's reasons for the 5-tuple still hold.** It keeps `Parser` and
   `Lexer` free of any dependency on `Predicator.Errors`, it changed ~100
   pass-through clauses and `@spec`s by one element instead of rewriting
   them, and a consumer still matching the old 4-tuple fails loudly instead
   of silently mis-binding. Nothing measured here weighs against any of
   that.
4. **Adopting statifier's shape without its offsets would be a false
   cognate.** `Location`'s flatness and its offsets are one design - the
   flat fields exist so the offsets sit beside the lines and columns. Given
   decision (a), a predicator struct in that shape would mimic the
   silhouette while dropping the field the shape was built around, inviting
   exactly the `span.start` confusion statifier's moduledoc already
   exhibits.

Statifier ADR-0014's exclusive-end adoption remains the model for how the
two repos converge: statifier took the span convention from predicator so
the shapes compose, and composition - not field-for-field identity - is the
actual requirement. The shapes compose today.

## What follows

Nothing, in this repo. Both answers are "no change", so no implementation
bead is filed, no CHANGELOG entry is owed (no user-facing behaviour moves),
and px-dmt's deferred "struct at the boundary, later, on its own major" is
answered: not on current evidence.

Two observations recorded for whoever touches the seam next, neither
actionable here:

- `Statifier.Parser.Location`'s moduledoc sentence about
  `value_location.start_offset + span.start` describes arithmetic its own
  tree never performs, against a span field shape that has never existed.
  Whether to reword it is statifier's call, in statifier's tracker; this
  repo does not file beads there (ADR-0010).
- `lib/statifier/evaluator/error.ex:15-16` says "`Predicator.Errors.ParseError`
  has no `:span` field, hence `Map.get/2`" - true against the 7.0 pin it is
  written on, false after px-dmt. st-57w's 8.0 adoption pass is where that
  sentence gets corrected, and its `Map.get/2` keeps working either way.
