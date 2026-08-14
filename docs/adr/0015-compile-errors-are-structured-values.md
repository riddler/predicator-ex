# ADR-0015: Compile errors are structured values (8.0)

Status: accepted (2026-08-14)

## Context

Predicator's six compile entry points - `compile/1`, `compile_with_positions/1`,
`compile_with_spans/1`, `compile_program/1`,
`compile_program_with_positions/1`, and `compile_program_with_spans/1` - all
return `{:error, binary()}` on failure. They share that arm through two private
helpers in `lib/predicator.ex`, `build_instructions_result/1` and
`build_compiled_result/1`, each of which takes the parser's
`{:error, message, line, column}` and flattens it:

```elixir
{:error, "#{message} at line #{line}, column #{column}"}
```

A caller who wants the line and column back has two choices: re-parse that
sentence, or bypass the compile façade and call `parse/2` or `parse_program/2`
directly, which return the 4-tuple unflattened. px-iov made the second route
explicit in all six `@doc`s and deferred the question of whether the arm itself
should change; this ADR is that question.

**The rest of the public surface already answers it.** `evaluate/3`,
`execute/3`, `context_location/3`, and `context_assign/4` all return
`{:error, struct()}`, and for a failure to parse they return a
`%Predicator.Errors.ParseError{}` built by the same `ParseError.new/3` from the
same 4-tuple (`lib/predicator.ex`, and `lib/predicator/context_location.ex`).
The struct exists, is public, is documented in `Predicator.evaluate/3`'s error
list, and carries `:position` typed `t:Predicator.Types.position/0` precisely so
generic error-reporting code can read a location uniformly across `ParseError`,
`EvaluationError`, `TypeMismatchError`, and `UndefinedVariableError`. The
compile arm is the one place in the façade where a failure that already has that
struct available is rendered to a sentence instead. The binary is not a design;
it is what the arm looked like before the error-struct family landed, preserved
across six functions by inertia.

ADR-0004 is directional support rather than a rule that settles this. Its
errors-are-values corollary is argued about *raising*, and the compile arm does
not raise - it returns a value, just a lossy one. What ADR-0004 does establish is
that the return-a-value contract is the same decision applied to failure, and a
value that has to be regex-matched to recover a fact the library already held is
that contract half-kept.

**The cost is a major version.** This changes a documented public return type on
six functions, so it is exactly the class of change 7.0.0 was cut for
(`Math.pow`'s integer results, 2026-08-14). It cannot ride a minor. That is also
the reason not to wait: every release adds call sites matching on the binary, and
the fix at each is a one-liner today.

**A span-bearing parse error is a separate question, and a smaller one than it
looked.** Spans are node metadata, produced as a node is built, and a parse error
is the case where no node was built - `parse_program("x =", spans: true)` returns
a point, never a span, and does so in span mode as much as in point mode. But the
extent data is not missing from the pipeline. `Predicator.Lexer`'s token type is
`{type, line, column, length, value}`: every token already carries its own
length, so the failing token's extent is available at the moment the parser
reports the failure and is simply discarded by the 4-tuple, which has room only
for a point. What is genuinely absent is an extent for a failure with no token at
all - end of input - and today several of those report a hardcoded `1, 1` rather
than the end of the source (`lib/predicator/parser.ex`, the block-open and
block-close end-of-input clauses). So the span work is real work, but it is
parser-side plumbing plus an end-of-input position fix, not a lexer redesign.

## Decision

**Yes. In 8.0.0, the compile error arm becomes a structured value: all six
compile entry points return `{:error, struct()}` in place of
`{:error, binary()}`, and a parse failure is reported as the existing
`%Predicator.Errors.ParseError{}`. Parse-error spans are not part of it.**

Six parts:

- **The error value is the existing `Predicator.Errors.ParseError`, not a new
  type.** A parse or tokenize failure reaching a compile entry point is the same
  failure `evaluate/3` already reports, from the same 4-tuple, and inventing a
  `CompileError` beside it would give one event two struct types chosen by which
  door the caller came through. The two helpers construct it the way
  `evaluate/3` does, with `ParseError.new(message, line, column)`.

- **`:message` holds the parser's own message; the location is `:position`, not
  prose.** The `" at line L, column C"` suffix the helpers append today is not
  part of the parser's message and stops being appended - the fact it encodes is
  `:position`, and duplicating it into the string is what made the value lossy in
  the first place. Rendering a sentence for a human is the caller's, and callers
  who want today's exact string can format it from the two fields. (`ParseError`'s
  own moduledoc example currently shows a message *with* the suffix baked in;
  that example is wrong about today's behaviour and is corrected in the same
  change.)

- **A compiler-stage failure keeps its struct too.** `build_instructions_result/1`
  today calls `Compiler.to_instructions/2`, which is specced
  `... | {:error, struct()}`, and then throws the struct away in favour of
  `{:error, error.message}`. It returns the struct unchanged. So the declared
  return type of all six becomes `{:ok, ...} | {:error, struct()}` - the same
  spec `evaluate/3` and `execute/3` already carry - rather than a union naming
  `ParseError` alone.

- **All six move together, in one release.** They share two helpers and are
  documented, tested, and consumed as two families of three; a structured arm on
  some and a binary on others would be the asymmetry px-iov exists to remove,
  recreated on a different axis. This is the same reasoning ADR-0009 applied to
  `compile_with_positions/1` and `compile_with_spans/1`, and it is why the
  implementation is one bead: the helpers are the whole change surface, so
  moving them reaches all six at once and moving one function alone would cost
  *more* code than moving all six.

- **Only the error arm moves.** `compile/1` still returns a bare instruction
  list, the four `%Compiled{}` functions still return the envelope, and
  `%Compiled{}` itself is untouched. ADR-0009's "`compile/1` stays a bare list"
  is not reopened - this ADR is about the other arm entirely.

- **`compile!/1` keeps raising.** It is a bang variant, and ADR-0004's carve-out
  covers it: it converts a value into an exception at a call site the host wrote.
  Its message is composed from the struct's fields instead of interpolating a
  pre-formatted binary, so its text is preserved by construction rather than by
  accident.

### Parse-error spans: what would have to happen first

Deferred to its own bead, and named here so the follow-on is not re-derived. In
order:

1. **`ParseError` gains an optional `:span` field**, defaulting to `nil` and
   outside `@enforce_keys` (`:message` and `:position` stay enforced). This is
   additive and `Errors.put_position/2` already anticipates it - it discriminates
   a struct with a `:span` field from one without via `Map.has_key?/2` and sets
   `:position` to the span's start, so a caller reading only `:position` is
   unaffected.

2. **The parser's error tuple has to carry the extent it already receives.**
   `{:error, message, line, column}` is the shape of every error clause in
   `Predicator.Parser` and `Predicator.Lexer` and it has no room for an end
   position. The failing token's `length` is right there in the token being
   matched, so the change is to widen the error term (a 5-tuple, or an error term
   carrying a span) and thread it through the ~30 error sites and the pass-through
   clauses between them. That is mechanical but wide, and it is a public shape
   change to `parse/2` and `parse_program/2` in its own right - so it is a major
   version of its own, and it must not be folded into this one.

3. **End of input needs a real position before it can have a span.** A failure
   with no token has no extent to borrow; the answer is a zero-width span at the
   end of the source. Several end-of-input clauses currently report `1, 1`
   regardless of where the input actually ended, so this step is a correctness
   fix to the *point* position before it is a span feature, and it is worth
   landing on its own merits whether or not spans follow.

4. **Only then can a compile entry point return a span-bearing parse error**, and
   even then it does so in every mode, not only the `_with_spans` ones: a parse
   error's span comes from the token stream, not from the `spans: true` node
   metadata option, so gating it on the compile function's mode would be an
   arbitrary distinction. Until step 2 lands, a structured compile error carries a
   point position and a `nil` span, which is a complete and honest value.

### What this decision does and does not change about the instruction set

**This decision does not move the ISA. The ISA version stays at 6.** No opcode is
added, removed, renamed, or given different semantics; no instruction gains an
element. The instruction list a successful compile returns is byte-identical
before and after, stored artifacts need no migration, and the ISA has nothing to
say about the shape of an Elixir return value on the failure path. Per ADR-0003
the obligation a change creates is measured in ISA versions, `docs/isa.md`
entries, and corpus tiers, and this change produces none of the three. **The Ruby
and JavaScript siblings owe nothing** - `Predicator.Errors.ParseError` is an
Elixir struct with no cross-language counterpart, and a sibling may adopt a
structured error, keep a string, or use its host language's exceptions, as it
already does.

The conformance corpus is likewise untouched: it pins evaluation semantics, not
façade return shapes, and no instruction, value, or function behaviour moves.

## Consequences

- **Migration for every caller matching on the binary (8.0, breaking).**
  `{:error, message} = Predicator.compile(src)` becomes
  `{:error, %ParseError{message: message, position: {line, column}}}`. A caller
  who was displaying the old sentence rebuilds it as
  `"#{error.message} at line #{line}, column #{column}"`; a caller who was
  regex-matching it for the line and column deletes the regex. The CHANGELOG
  entry says both, and says that `compile/1`'s success arm and `%Compiled{}` are
  unchanged so the majority of the surface sees nothing.
- **`parse/2` and `parse_program/2` remain the raw route and are not deprecated.**
  They keep returning the 4-tuple. What changes is that reaching for them is no
  longer the *only* way to get a location out of a compile failure, so the
  paragraph px-iov added to all six `@doc`s - pointing callers at them for line
  and column as data - is rewritten rather than kept.
- **The façade's error contract becomes uniform, which is the point.** After 8.0
  every public function in `Predicator` that can fail returns
  `{:error, struct()}`, so a host can write one error renderer that reads
  `:message` and `:position` off whatever comes back, instead of one for the
  compile path and one for everything else.
- **`{:error, struct()}` is a deliberately wide spec.** It matches what
  `evaluate/3` and `execute/3` already declare, and it is what lets a
  compiler-stage failure keep its own struct type without the compile functions
  enumerating every error module. Narrowing it later is a compatible change;
  widening it after promising a narrow union would not be.
- **This is a smaller change than its version bump suggests.** Both helpers are
  private and are the only construction sites; the tests that assert on the
  binary are the bulk of the diff, not the library code.
- **The 8.0 release should carry any other queued façade break with it.** A major
  version is the scarce resource here, not the edit - a second breaking façade
  change arriving one release later charges every consumer a second migration for
  work that could have shared this one.
- **Doing nothing has an ongoing cost, which is why the alternative was
  declined.** Keeping the binary is free today and charges interest: each release
  adds callers whose only route to a location is a regex over an error message
  the library is free to reword, which makes the message text an accidental
  compatibility surface. Structuring the arm converts that surface into fields.
- Reverting to a formatted binary means superseding this ADR, not adding a
  string-returning function beside it.

### Open questions left to the implementation

Recorded rather than settled; none of them block the implementation.

- **Should `Predicator.Errors` gain a public `format/1`** that renders a struct as
  today's `"<message> at line L, column C"` sentence? It would make the migration
  a one-word change at any call site that was only displaying the string, and it
  puts the formatting in one place rather than in every host. It is excluded from
  the decision above because it is additive and can land any time, including
  after 8.0.
- **Does `ParseError` want to distinguish a lexical failure from a syntactic
  one?** `Lexer.tokenize/1` and `Parser.parse/2` failures are both reported as
  `ParseError` today, with nothing on the struct saying which. Nothing needs the
  distinction yet, and a `:stage` field is additive if something does.
- **Is 8.0 the right release, or should this wait for a break it can share?** The
  argument for waiting is that a major version spent on one error arm is a
  version other queued breaks then cannot use; the argument against is that the
  cost of the migration grows with the number of released call sites. The
  implementation bead should check for other queued breaking work before the
  release is cut, and pull it in rather than push this out.
- **No statifier-side mirror bead is known.** px-iov mirrors st-57w, but nothing
  in statifier-ex is known to track this follow-on. If statifier files one, the
  implementation bead gains a `mirrors:` line then - it is not invented in
  advance.
