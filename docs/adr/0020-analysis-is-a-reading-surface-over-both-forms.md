# ADR-0020: Analysis is a reading surface over both forms of a program

Status: accepted (2026-10-13, predicator 9.5.0; proposed 2026-10-13)

## Context

Tools around predicator keep asking three questions of a program without
running it: which variables does it read, which functions does it call, and
which locations does it store to. A host building rich charts wants to check
every path a condition reads against the shape it declared for that data.
statifier-ex walks compiled instruction lists by hand to find the function
names a chart calls. An editor wants to underline a read the host does not
know. Each of these writes its own walk today, and each walk is a second
reading of the grammar or of the instruction set that nothing keeps in step.

The answers have to come from two places, because a program exists in two
forms. Source parses to an AST that carries positions (`Predicator.parse/2`,
`Predicator.parse_program/2`). What a host stores is the instruction list:
`Predicator.Compiled`'s moduledoc tells a consumer to persist
`compiled.instructions` and nothing else, so a tool reading a stored program
has no AST to walk.

Three other routes were weighed.

**AST only.** Smaller, and positions come for free, but it cannot read a
stored program without its source, which is the case statifier-ex is in.

**Resolve through `Predicator.ContextLocation`.** It already knows how to
turn an assignment's location chain into a location, but it resolves against
a live context: it answers what a computed key evaluates to, given data. An
analysis has no data and wants the path as written, with a computed key
marked rather than evaluated. Assignments walk the location chain directly
(ruled by the operator, 2026-10-13).

**Deduplicated sets.** A set of paths is what a checker often wants, but it
throws away positions and occurrence counts, and a caller can always dedupe a
list; the reverse is not possible. The answers are lists of every occurrence,
in source order, as maps (ruled by the operator, 2026-10-12).

The pieces to build on already exist. `Predicator.AST` walks every node kind
`Predicator.Parser`'s `visitable/0` type names, children in source order.
`Predicator.Vocabulary` is the model for a module that reads the language
without taking part in it, held to its source by a sync test.

## Decision

**`Predicator.Analysis` answers `references/1`, `calls/1` and
`assignments/1` over either form of a program. It is a reading surface:
nothing in it lexes, parses, compiles or evaluates on the pipeline's behalf,
and no answer depends on a context.**

### The answers

Each function answers `{:ok, list}`, the list holding every occurrence in
source order (ruled by the operator, 2026-10-12):

| Function | Each item | Notes |
|---|---|---|
| `references/1` | `%{path: [segment], position: pos \| nil}` | a chain rooted at a variable |
| `calls/1` | `%{name: name, arity: n, position: pos \| nil}` | nested calls included, the outer call first; a qualified name keeps its dots |
| `assignments/1` | `%{path: [segment], position: pos \| nil}` | one per store |

A segment is a string, an integer or `:dynamic`:

| Segment | Where it comes from |
|---|---|
| a string | the root variable's name, a property name, or a string literal bracket key |
| an integer | an integer literal bracket key |
| `:dynamic` | any other bracket key: a computed one, or a literal that is neither a string nor an integer |

The path continues past a `:dynamic` segment, and the reads inside a computed
key are references of their own. A chain rooted anywhere other than a
variable - a call's result, a literal - reads no variable, so it yields no
reference of its own. The location an assignment writes is not a read; the
reads inside its bracket keys are.

A path's position starts where the path starts: the span of the whole chain
when the program carries spans, and otherwise the point position of the
chain's root variable. A call's position is the call node's own. An
assignment's position follows the same rule as a store's blame does in
`Predicator.Visitors.InstructionsVisitor`: the assignment's span, or the
root's point.

### The inputs

| Input | Read as | Positions |
|---|---|---|
| a source string | a program, as `Predicator.parse_program/2` reads it | from the parse |
| an AST, a statement or a block | the tree as given | the nodes' own slots |
| a program | the tree as given | the nodes' own slots |
| an instruction list | the instructions, through a stack | none: every position is `nil` |
| a `Predicator.Compiled` envelope | its instructions, through a stack | from its position or span table |

A source string is read as a program because every expression is a program
of one statement, and since [ADR-0002](0002-the-equals-grammar-break.md) `=`
is never an equality operator, so reading a condition as a program changes
nothing it reads, and an assignment written as a string is analysed too.

### The instruction form rebuilds what the AST holds

The instruction form runs the list through a symbolic stack (decided by the
conductor under a standing consent, 2026-10-12): a `load` starts a path,
`access` and `bracket_access` extend it, a `lit` before a `bracket_access`
folds to its segment when it is a string or an integer and anything else is
`:dynamic`, `call` yields a call, and `store` yields its target path from the
values it pops. A path becomes a reference when anything other than an access
consumes it. References are ordered by the index of their `load`, calls by
the first instruction that built them with the outer call first, and stores by
their index, which is source order for every list the compiler emits. A
short-circuit jump's two operands meet where the jump lands, so `(a and b).c`
reads `a` and `b` and no path through `c`, as the AST form does.

The two forms agree on paths, calls and stores for every source, and on
positions whenever the instruction form has a table. The one place they
cannot agree is a bare instruction list, which carries no positions; that is
the only difference `test/predicator/analysis_forms_test.exs` allows, over a
table of sources that reaches every node kind the parser builds and every
opcode the compiler emits.

### Refusals reuse existing terms

A source string that does not parse answers the `ParseError`
`Predicator.compile_program/1` answers for it. An instruction the analysis
cannot read - an opcode outside `Predicator.Instructions.opcodes/0`, or an
operand of the wrong shape - answers an `EvaluationError` with the
evaluator's own `"unknown_instruction"` reason. A list that pops more values
than it pushed is read as far as it goes: the missing values read nothing.
No new reason term is introduced.

### Two vocabularies bind it

`Predicator.Analysis` holds one AST clause per constructor of the parser's
`visitable/0` type and one instruction clause per opcode of
`Predicator.Instructions.opcodes/0`, the retired `and` and `or` included (a
clause that reads both operands; decided by the conductor under a standing
consent, 2026-10-13). `test/predicator/analysis_clause_coverage_test.exs`
compares both clause lists with their sources both ways, so a node kind or an
opcode added without an analysis clause turns the suite red.

## Consequences

- **Nothing under `lib/` moves except an addition.** No parser option, no
  compiler change, no opcode, no ISA version and no conformance corpus entry:
  the corpus pins evaluation semantics, and this decision adds none. Every
  existing function answers as it did.

- **A stored program can be checked without its source.** A tool holding only
  `compiled.instructions` gets the same paths and calls the source would
  give, without positions. A tool that wants positions recompiles the source,
  as `Predicator.Compiled` already advises.

- **The answers are a public shape a sibling may mirror.** The Ruby and
  JavaScript siblings owe nothing; one that adds an analysis copies these
  shapes, and a corpus surface for analysis is a separate, later decision.

- **Widening is additive; reshaping is breaking.** A new key in an item, or a
  new input form, is a minor release. Changing a segment's meaning, the order,
  or the list-of-every-occurrence answer is a breaking change.

- **Status is `proposed`.** Per `docs/adr/README.md`, an agent may draft and
  only the maintainer accepts; the flip to `accepted` is a separate reviewed
  change once the code ships in a published version.

## Notes

### 2026-10-13: the conformance corpus gains an analysis surface

The consequence above that this decision adds "no conformance corpus entry"
held for the change it records, and the later decision it names has now been
taken: the corpus carries a third surface for analysis, beside the evaluator
and the compiler and outside both, specified in `conformance/README.md`
("The analysis surface"). Its cases are generated from this module's answers
in the shape decided here, with a computed key spelled `{"$type": "dynamic"}`
and a position as `[line, column]` or `null`. The evaluator and compiler
surfaces, their cases, the tier files, the manifest and `corpus_hash` are
unchanged, and the ratchet registry does not yet name the analysis surface.
The placement of the analysis surface outside the evaluator and compiler
surfaces was decided by the conductor under a standing consent, 2026-10-13.
Nothing under `lib/` that ships in the package changes with it.

### 2026-10-13: the status is now `accepted`

This record stayed proposed until the code it decides had shipped in a
published version, and it has. predicator 9.5.0 carries it: the traversal it
builds on landed in [#248](https://github.com/riddler/predicator-ex/pull/248)
at `01f5ddc9`, the analysis and this record in
[#249](https://github.com/riddler/predicator-ex/pull/249) at `6103ecf9`, the
corpus's analysis surface in
[#250](https://github.com/riddler/predicator-ex/pull/250) at `6bf0d8ad`, the
9.5.0 release prep ([#252](https://github.com/riddler/predicator-ex/pull/252))
merged at `fd7fb015`, and the tag `v9.5.0` on that commit started
<https://github.com/riddler/predicator-ex/actions/runs/38413868048>, whose
branch, version and Hex checks, full gate and publish step all passed on its
first attempt; Hex shows 9.5.0 as the latest version. The flip was decided by
the conductor under a standing consent, 2026-10-13. The consequence above
that reads "Status is `proposed`" is met here: the flip is this separate
change, made once the code shipped.

Every claim above was re-verified on 2026-10-13 against `origin/main` at
`fd7fb015`, which no commit has followed: `references/1`, `calls/1` and
`assignments/1` in `lib/predicator/analysis.ex`, each answering `{:ok, list}`
in the item shapes and segment rules of the two tables, with the outer call
first and a qualified name kept whole; a chain rooted anywhere but a variable
yielding no reference, and an assignment's location read as no reference
while its bracket keys are; the path position rule beside the store blame
rule in `lib/predicator/visitors/instructions_visitor.ex`; the five input
forms, with a source string read through `Predicator.parse_program/2`; the
symbolic stack of the instruction form, its ordering and its short-circuit
merge; the `ParseError` that `Predicator.compile_program/1` answers and the
evaluator's `"unknown_instruction"` reason, with no new reason term; the two
binding tests named above, the clause coverage test reading both clause lists
both ways with the retired `and` and `or` included, and the forms test
comparing the AST with both envelopes on positions and with the bare list on
paths and calls only; the context's citations of `Predicator.Compiled`'s
storage advice, `Predicator.ContextLocation`'s resolution against a context,
`Predicator.AST`'s walks, `Predicator.Vocabulary`'s sync test and
[ADR-0002](0002-the-equals-grammar-break.md). Between `v9.4.4` and `v9.5.0`
no parser, compiler, evaluator or opcode file changed, `docs/isa.md` and
`conformance/manifest.json` did not move, and no evaluator or compiler case
changed. The one change under `lib/` that is not an addition, the extended
`mix corpus.generate` task, is the corpus decision the 2026-10-13 Note above
records, and that task does not ship in the package; that Note's own claims
hold at the same SHA. No other sentence above is superseded.
