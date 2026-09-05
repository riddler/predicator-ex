# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [9.3.0] - 2026-09-05

### Added

- `Predicator.Simple` admits float literals. `card.amount >= 19.99` is now
  inside the picklist-renderable subset: `from_ast/1` and `from_source/1`
  read a non-negative float as the new `{:float, value}` scalar, and
  `to_ast/1` and `to_source/2` round-trip it under both laws. The exclusion
  was contingent on `Predicator.decompile/2` raising on a float, which
  px-ggb fixed.

  A float is **not** a new `Predicator.Vocabulary.value_kind/0`. Integers
  and floats are both `:number`, so `Predicator.Simple.operators/1` offers
  the same operators for either and an editor needs no new branch. A
  negative float stays outside, exactly as a negative integer does: the
  parser reads `-19.99` as a `unary` node, not as a literal.

### Fixed

- `Predicator.decompile/2` renders a float literal instead of raising, so
  `amount == 1.5` survives parse-then-decompile like any other literal.
- The string writer escapes a backslash inside a string literal, in both
  quote styles, so a value containing one survives parse-then-decompile
  instead of rendering source that parses back differently - or, for a value
  of a single backslash, source that does not parse at all. The quote style
  asked for is still the style that comes back.

## [9.2.0] - 2026-09-04

### Added

- `Predicator.Simple` names the subset of the language a picklist-style editor
  can render - clauses joined by one connective - and reads it out of an AST or
  source with `from_ast/1` and `from_source/1`, which answer `:outside` for a
  valid expression outside the subset rather than treating it as an error.
- `Predicator.Simple.to_ast/1` and `to_source/2` write a subset value back, so
  an expression can be handed to a form and the edited value rendered to source
  the author recognises; `to_source/2` takes `Predicator.decompile/2`'s
  formatting options.
- `Predicator.Simple.operators/1` answers, for one kind of value
  (`:string`, `:number`, `:boolean`, `:date`, `:datetime`, `:duration` or
  `:list`), which operators a picklist row should offer, each with the atom to
  put in a clause, the spelling `to_source/2` renders, a label and an arity.
- `Predicator.Vocabulary`'s operator entries carry four new keys - `:label`,
  `:arity`, `:ast_op` and `:value_kinds` - so an editor's operator control is
  read from the same enumeration the lexer is checked against rather than from
  a second copy of the grammar. `Predicator.Vocabulary.value_kinds/0`
  enumerates the kinds.

### Changed

- `Predicator.Vocabulary.tokens/0` and `operators/0` return entries carrying
  the four operator keys for operator-category lexemes. Entries outside those
  categories are unchanged, and no existing key moved or changed meaning.

### Fixed

- `Predicator.Simple`'s documentation attributed the float-literal exclusion to
  the bead that shipped the module. It is caused by `Predicator.decompile/2`
  raising on a float literal, and now cites that defect (px-ggb) instead.

## [9.1.0] - 2026-09-02

### Added

- `Predicator.Vocabulary` enumerates the grammar's fixed lexemes - operators,
  keywords, literal words, brackets, separators, duration units - and the
  callable function names, each with a token type, a category, a display form
  and a one-line doc, so an expression editor can offer completion without
  hard-coding a copy of the grammar.

## [9.0.2] - 2026-08-27

### Changed

- **Documentation-only release; no code or predicate-language changes.** The
  README's Quick Start is reworked into a worked example that compiles a rule
  once and evaluates it per transaction, and a new "Running a short program"
  section gives `execute/3`, `execute_value/3`, and the `:protected_roots`
  refusal a front-door example for the first time - the statement surface has
  shipped since 4.0.0 but was visible only in the language reference. Every
  illustrative identifier across the README, the guides, the language
  reference, and the moduledocs moves onto two canonical example domains
  (authorizing a transaction against an account budget, and a signup wizard
  running an A/B test). `docs/architecture.md` drops three stale facts: `=`
  listed as a comparison operator (retired in 4.0.0), an ISA-version list that
  stopped at v4, and a testing section naming property-based testing the
  project does not do.

## [9.0.1] - 2026-08-24

### Changed

- **Documentation-only release; no code or predicate-language changes.** ADRs
  are no longer published to hexdocs - ADR citations in published pages now
  point at the GitHub repository instead. `docs/contributing.md` is published
  (the README previously linked it as a dead page), the conformance
  README/RATCHET links no longer collapse into hexdocs' `readme.html`, the
  README badge row follows the shared standard with a license badge added,
  and `mix docs` completes with zero warnings.

## [9.0.0] - 2026-08-17

### Changed

- **A duration produced by the `duration` opcode now always carries all eight
  unit keys, `milliseconds` included.** Previously the evaluator seeded a
  seven-key accumulator and inserted `milliseconds` only when the expression
  named a `ms`-family unit, so `Predicator.evaluate("3d")` returned seven keys
  while `Predicator.evaluate("500ms")` returned eight - a key set that varied
  with the expression and did not satisfy `t:Predicator.Types.duration/0`,
  which has always declared all eight as required. Every other duration
  producer (`Duration.new/1`, `parse/1`, `from_units/1`, and `Date`/`DateTime`
  subtraction) already returned eight; the opcode now matches them. **This is
  a breaking change** for a consumer that pattern-matches on the seven-key
  shape, compares against a seven-key literal, or enumerates `Map.keys/1`; a
  consumer reading units with `Map.get/3` is unaffected, and the numeric value
  of every duration is unchanged, since an absent `milliseconds` always meant
  `0`. No ISA version moves and no compiled instruction list changes meaning -
  the conformance corpus's exported bytes are identical, because its JSON
  encoding already omitted a zero `milliseconds`.

## [8.0.0] - 2026-08-15

### Added

- **Duration values accept a decimal fraction on a component, at both the
  string entry point (`Duration.parse/1`, and therefore `::duration`) and
  the duration-literal grammar (`1.5s`).** `"1.5s"::duration` is now 1 second
  500 milliseconds instead of `:undefined`, and the literal `1.5s` compiles
  to the same integer unit pairs. A fractional component must convert to an
  exact whole number of milliseconds - a sub-millisecond remainder
  (`"0.5ms"`, `0.5ms`) is rejected rather than rounded or truncated - and a
  valid fraction expands to the integer part on its own unit plus a
  remainder decomposed largest-first through `d`, `h`, `m`, `s`, `ms` only.
  Fractions are accepted on every unit; a fractional `mo` or `y` commits this
  project's documented 30-day and 365-day approximations at parse time
  (`"0.5mo"` normalizes to 15 days). The expansion is downward normalization
  at parse/compile time - every duration map and every `["duration", units]`
  instruction operand stays integer-only, so no opcode, operand shape, or
  ISA version moves; the refined `::duration` string grammar is documented in
  `docs/isa.md` §5 as a v6 refinement, not a v7 change. `to_string/1` still
  never emits a fraction, so `"1.5s"::duration::string` is `"1s500ms"`, not
  `"1.5s"` - the guaranteed round trip remains
  `some_duration::string::duration`. Both spellings (string and literal) were
  errors before this change, so this is purely additive.

- **`Predicator.compile_program_with_spans/1`, the program-level counterpart
  to `compile_with_spans/1`.** Statement programs previously had two compile
  entry points, `compile_program/1` and `compile_program_with_positions/1`,
  neither of which could return span-quality diagnostics; expressions already
  had `compile_with_spans/1`. The new function closes that gap: it returns a
  `%Compiled{}` whose `positions` and `segment_positions` hold
  `t:Predicator.Types.span/0` values instead of point positions, with the
  instruction that terminates a statement - `store` for an assignment, `pop`
  for a bare expression statement - carrying that statement's own source
  extent. `compiled.instructions` is byte-identical to `compile_program/1`'s
  output; the existing program and expression compile functions are
  unchanged.

- **`:protected_roots`, an opt-in `execute/3`/`execute_value/3` option naming
  context roots a `store` may not write.** A `store` whose path's root
  segment is in the list refuses the write and returns
  `{:error, %Predicator.Errors.EvaluationError{reason: "protected_root"},
  context}` instead, with `error.details.root` naming the offending root; the
  returned `context` is unchanged from the ordinary partial-context contract
  - it still carries every write made before the refused statement. Additive:
  absent the option, behavior is byte-identical to today, so this is a minor
  release, not a breaking one.

- **`:normalize`, an opt-in `Context.new/2` option that skips the
  `normalize_value/1` walk over `data`.** `true` by default, matching today's
  behavior. `normalize: false` is a caller-vouches option: the caller
  asserts `data` already satisfies the normalization invariant (string keys
  throughout, at every level, with any nested map or list already
  normalized), and stores it exactly as given; violating the invariant is
  the caller's own bug, the same one `bind/3`'s O(1) claim already depends
  on. A non-boolean value raises `ArgumentError`. Additive and
  non-breaking.

### Changed

- **BREAKING: all six compile entry points now return `{:error, struct()}`
  instead of `{:error, binary()}`.** `compile/1`, `compile_with_positions/1`,
  `compile_with_spans/1`, `compile_program/1`,
  `compile_program_with_positions/1`, and `compile_program_with_spans/1` all
  route through the same construction site, and a parse failure is now
  reported as the same `%Predicator.Errors.ParseError{}` that `evaluate/3`
  already returns for the same source: `:message` holds the parser's bare
  message with no location text appended, and the location lives in
  `:position` as `{line, column}`. A caller that displayed the old
  `"<message> at line <line>, column <column>"` sentence rebuilds it with
  `"#{error.message} at line #{elem(error.position, 0)}, column #{elem(error.position, 1)}"`;
  a caller that regex-matched the sentence to recover the line and column
  deletes the regex and reads `error.position` directly. Unchanged:
  `compile/1`'s success arm, `%Compiled{}`, `compile!/1`'s raised text
  (still `"Compilation failed: <message> at line <line>, column <column>"`),
  and the ISA version (still 6) - a stored instruction list needs no
  migration. This is a breaking change to a documented public return type on
  six functions, which is why the next release is a major one, 8.0.0.

- **BREAKING: `parse/2`, `parse_program/2`, and `Predicator.Lexer.tokenize/1`
  now return `{:error, message, line, column, span}` instead of
  `{:error, message, line, column}`, and every `%Predicator.Errors.ParseError{}`
  carries the same extent in a new `:span` field.** The span is the source
  extent of the token that failed - `{{start_line, start_column},
  {end_line, end_column}}` with an exclusive end, the same
  `t:Predicator.Types.span/0` the position tables use - and its start is
  always the tuple's own `{line, column}`, so a caller reading only the first
  four elements reads exactly what it read before and a caller matching the
  4-tuple gets a loud `CaseClauseError` rather than a silent mis-bind. A
  failure at the end of the source reports a zero-width span there, borrowed
  from the lexer's `:eof` sentinel. The fourteen end-of-input clauses that
  previously reported a hardcoded `{1, 1}` now report the true position as
  well, but that correction is not observable through any string input: the
  lexer always appends `:eof`, so those clauses are reached only by
  `Predicator.Parser.parse/2` handed a token list built by the caller with no
  sentinel on the end. Every error message and position reachable from the six
  compile entry points is unchanged from 7.0.0 - only the new `:span` field
  and the widened tuple are. All six compile entry points
  carry the span in every mode - `compile/1` as much as `compile_with_spans/1`
  - because a parse error's extent comes from the token stream, not from the
  `spans: true` node-metadata option. `:span` is `nil` only on a `ParseError`
  built by a caller through `new/3`. The ISA version is unchanged (still 6),
  no instruction list moves, and the conformance corpus is untouched.

- **`Context.resolve_functions/1`'s provider validation is now memoized per
  provider list.** Repeat `Context.new/2` and `Predicator.Evaluator.evaluate/3`
  calls against an unchanged `:providers` list (the builtins included) no
  longer re-pay `Code.ensure_loaded?/1` and `function_exported?/3` validation
  or the `Map.merge/2` folds that build the dispatch map - the resolved map is
  cached in `:persistent_term`, keyed by the provider list and a per-module
  version stamp. A provider module recompiled with a different `functions/0`
  is picked up automatically on the next call: its stamp changes, which is a
  cache miss by construction, so no stale dispatch map survives a code reload
  in dev or test. The resolved map, the shadowing order, and all three
  `ArgumentError` messages for a bad provider are unchanged - a provider list
  that fails validation is never cached, so it re-validates, and re-raises
  identically, on every call. `Context.new/2`'s docs now carry a
  `## Performance` section naming both costs of a build - the size-scaling
  normalization walk and this now-memoized fixed term - and pointing at
  `bind/3`/`put_host/2` as the rebind paths a per-evaluation caller should use
  instead of calling `new/2` again; see `bench/context_build.exs` and
  `bench/results/260814-context-build.md` for the numbers behind both.

- **`conformance/RATCHET.md` now states registry entry uniqueness
  normatively.** Rule 3 already grew `entries` by a set union, and rule 1 already
  keyed entry identity on the `(case_id, surface)` pair, so uniqueness on that
  pair was implied throughout - it is now written down, and
  `test/predicator/conformance/ratchet_registry_test.exs` binds it. No registry
  written by rule 3's verify-then-add step can violate it, so a compliant sibling
  registry needs no change; a registry carrying a repeated pair was hand-edited.
  The corpus, `corpus_hash`, the schema, and the ISA are unaffected.

- **`conformance/examples/registry.example.json`'s provenance prose now matches
  reality.** `test/predicator/conformance/ratchet_registry_test.exs`'s moduledoc
  and `conformance/schema/registry.json`'s `description` both claimed the
  example was generated from this checkout's own corpus; no generator exists,
  and none should - the file is hand-maintained, and the binding tests in that
  suite are what keep it honest. Prose only: the example, its `corpus_hash`,
  and the schema's constraints are unaffected.

- **A malformed or unterminated date or datetime literal now reports a span
  covering the whole literal.** `Predicator.Lexer.tokenize/1` previously
  returned a one-character span at the literal's opening `#` for
  `Invalid date format:`, `Invalid datetime format:`, and
  `Unterminated date literal`; the span now runs from the opening `#` through
  the closing `#`, or through end of input when the literal is unterminated.
  The message text, line, and column are unchanged, as are the spans for
  unexpected characters and for unterminated string literals - those stay one
  character wide, and the Lexer moduledoc now records why.

### Fixed

- **`Predicator.compile/1` no longer raises on a leading-dot duration
  spelling or any other bare `.` in a position the grammar rejects** -
  `.5s`, `.5`, and `a . . b` now return `{:error, %Predicator.Errors.
  ParseError{}}` instead of crashing with a `FunctionClauseError`. The cause
  was the same class of gap as the string-token fix below: the parser's
  `format_token/2` carries one clause per token type with no catch-all, and
  the `:dot` token had never had one. A leading-dot duration spelling is
  still rejected - `.5s` is deliberately not a valid way to write a
  fractional duration - but it is now an error value, not a crash. `1 . 2`
  is unaffected and still reports "Expected property name after '.' but
  found number '2'".

- **`Predicator.compile/1` and `compile_program/1` no longer raise when a
  string literal appears somewhere the parser rejects it** - `score "a"`,
  `x = 1 "a"`, `next "a"`, and other sources like them now return
  `{:error, %Predicator.Errors.ParseError{}}` instead of crashing with a
  `CaseClauseError` or `MatchError`. The cause was a token-shape assumption
  in sixteen parser error and fallback clauses: they matched the ordinary
  five-element token shape, and a string token - which carries two extra
  elements, its quote type and end position - matched none of them. Every
  such site now reads a token's type and value positionally instead of
  destructuring its arity, so the fix is behavioral only: no public type, no
  error message text, and no compiled instruction output changed.

- **The lexer now advances its line counter and resets its column for a raw
  newline consumed inside a string or date literal**, instead of treating it
  as an ordinary character. Every token that follows a multi-line string
  literal - and every parse error position derived from one - now reports
  the line and column it actually occupies. An escaped `\n` is unaffected:
  it is a two-character escape in the source and never a raw newline byte.
  A source with no multi-line literal is byte-identical to before. The AST
  span of a multi-line string literal now ends at its true end rather than
  `{start_line, start_col + length}`, which changes span values exported
  through `Predicator.compile_with_spans/1` and
  `Predicator.compile_program_with_spans/1` for any source containing a
  multi-line string literal. `Predicator.Lexer.token/0`'s `:string` shape
  changed - it now carries a seventh element, its exclusive end position -
  since it is a public type.

## [7.0.0] - 2026-08-14

### Changed

- **BREAKING: `Math.pow` and `Math.sqrt` now return integers for
  integer-exact results, instead of always returning a float.**
  `Math.pow(2, 3)` is now `8`, not `8.0`, so `Math.pow(2, 3) === 8` is now
  `true`; the result is computed exactly with `Integer.pow/2`, so
  `Math.pow(10, 20)` no longer loses precision to `:math.pow/2`'s float
  conversion. `Math.sqrt(16)` is now `4`, not `4.0`, when the argument is a
  non-negative integer with an exact integer root. A float argument or a
  negative exponent is unchanged and still returns a float:
  `Math.pow(2.0, 3)` is still `8.0`, `Math.pow(2, -1)` is still `0.5`, and
  `Math.sqrt(2)` is still `1.4142135623730951`. The conformance cases
  `functions/math-pow` and `functions/math-sqrt` moved to the new integer
  results, and `functions/math-pow-float-arg`,
  `functions/math-pow-negative-exponent`, and `functions/math-sqrt-inexact`
  were added to pin the float-returning half of each rule. This is a
  breaking change to a documented return type and warrants a major version.
  The ISA version does not move: no opcode changed, and the builtin
  function set is not part of the ISA.

## [6.0.0] - 2026-08-14

### Added

- **Null joins the ISA value domain, distinct from `:undefined`.** A value
  that is present and empty is now distinguishable from one that was never
  supplied: null is falsy at a jump alongside `false` and `:undefined`;
  it is rejected by `not`, unary minus, and the arithmetic opcodes, the same
  as `:undefined`; every non-strict comparison involving it (`==` and the
  ordering operators) yields `:undefined`, since null has no type peer; and
  `===`/`!==` and membership (`in`/`contains`) answer a plain boolean about
  it by identity - `null === null` is `true`, `null in [null]` is `true`.
  It enters through a host-supplied context, a nested access, a function
  return, or the `null` literal below. See `docs/isa.md` §2, §3, and §5 for
  the full semantics. **The ISA version does not move**: no opcode name
  changed and no *instruction-list* operand form widened - the value half of
  this change enters only at the host/context boundary, which §3 governs
  and §1's versioning rule does not (the same shape as the `undefined`
  literal in 5.0.0).
- **A `null` literal.** `null` is now a literal keyword: `x === null`
  compiles to `[["load","x"],["lit",nil],["compare","STRICT_EQ"]]` and
  answers the question the bullet above made answerable. Null's semantics
  are unchanged (the bullet above); this is a spelling. **The ISA version
  does not move** - §3's value domain already admitted null and §5's `lit`
  already accepted it, so no opcode name changed and no instruction list a
  conformant v6 build must run changed; surface syntax is outside the ISA
  (§6), the same shape as the `undefined` literal in 5.0.0.

### Documentation

- **`docs/isa.md` states what happens to an instruction list stored as plain
  JSON.** Section 3 gains "Crossing a plain-JSON boundary": four of the value
  domain's eleven types - `Date`, `DateTime`, duration, and `:undefined` -
  have no JSON-native form, so a `lit` operand carrying one decodes back as a
  string or a plain map, with no error on either side of the trip. The ISA
  defines no envelope and will not - section 6 now says so beside the other
  things it does not define - but the note names the two approaches that
  work: the conformance corpus's tagged-value encoding, recommended and
  pointed at rather than published as an API, and persisting the source to
  recompile on load. **No ISA version change and no code change**: all four
  types have been in the value domain since v1, and nothing in `lib/`
  serializes an instruction list. See
  `docs/research/260813-px-a2w-plain-json-round-trip.md` for why promoting
  the corpus codec into a supported serialization API was weighed and
  rejected.

### Changed

- **`Context.new/2` and `bind/3` no longer rewrite a bound `nil` to
  `:undefined`.** A context now stores a bound null verbatim, so it survives
  distinguishably from an absent key. The observable consequence:
  `x === undefined` on a variable bound to `nil` now answers `{:ok, false}`
  where it previously answered `{:ok, true}`. This is not a breaking change:
  `Predicator.Types.value()` never declared `nil` as an accepted input, so a
  host relying on the old collapse was relying on undeclared behavior. A
  host that wants the previous behavior - a variable that reads as
  `:undefined` - should bind `Predicator.Undefined.value()` explicitly
  instead of `nil`.
- **`Predicator.evaluate/3` can now return `{:ok, nil}`.** A null reaching
  the top of the stack is the evaluation's result like any other value -
  most easily via short-circuit, where `"flag AND other"` over a null `flag`
  yields `{:ok, nil}`. Previously no evaluation could produce a bare `nil`
  result, since the context boundary rewrote every `nil` before it could be
  loaded. A caller that matches exhaustively on result values should add a
  `nil` clause.
- **BREAKING: `null` is a reserved word.** The lexer now classifies it as a
  literal keyword rather than a plain identifier. The silent case first,
  because it is the one a grep will not find on its own: a predicate that
  used `null` as a variable name in expression position does not fail - it
  changes answer. `x === null` used to compile to
  `[["load","x"],["load","null"],["compare","STRICT_EQ"]]` and load a
  phantom variable named `null`, which yielded `:undefined` under the
  default `on_unbound` policy and made the comparison `false` for a bound
  null; it now compiles to `[["load","x"],["lit",nil],["compare","STRICT_EQ"]]`
  and answers `true`. Anyone with a context key literally named `"null"`
  stops reading it, and no automated check finds this - a consumer must grep
  their stored predicates for `null` as a bare name. Then the loud cases,
  which are self-announcing: a predicate that used `null` as a variable name
  (`null = 3`), a bare property name (`user.null`), or a bare object key
  (`{null: 1}`) is now a parse error. The fix is renaming the variable or,
  for an object key, quoting it (`{"null": 1}`, which still parses). Only
  the lowercase spelling is reserved - `NULL` and `Null` stay ordinary
  identifiers. The Ruby and JavaScript lexers do not adopt a grammar break
  automatically, so this is a deliberate, documented surface-syntax
  divergence until they adopt it on their own schedule (ADR-0002's sibling
  consequence, ADR-0003).

### Fixed

- **A `nil` operand no longer crashes the evaluator.** `not`, unary minus,
  unary bang, the five arithmetic opcodes, and the three jump opcodes each
  raised `FunctionClauseError` when handed a raw `nil` operand - a live
  violation of "errors are values, never raised at a leaf" (ADR-0004),
  reachable through several paths that already carried `nil` into
  evaluation with no defined semantics (a bare map passed to `evaluate/3`,
  a custom function returning `{:ok, nil}`, and others). Each now returns a
  `TypeMismatchError` naming type `:null`, or, at a jump, treats the `nil`
  as falsy - never a raise.

## [5.0.0] - 2026-08-12

### Added

- **An `undefined` literal.** `undefined` is now a literal keyword, parsing
  to `{:literal, :undefined, pos}` and compiling to `["lit", :undefined]` -
  the same instruction an absent map key or a normalized `nil` already
  produced, now with a source spelling an author can write directly. That
  makes `x === undefined` a boundness test that answers `{:ok, true}` or
  `{:ok, false}` for a bound value under either `on_unbound` policy - the
  literal itself is never affected by the policy, since it compiles to `lit`
  rather than `load` and only `load` consults it. A *genuinely unbound* root
  is the exception on the strict side: it answers `{:ok, true}` under the
  default policy, but still errors under `on_unbound: :error`, where the
  `load` of `x` fails before the comparison runs. `x == undefined` is not
  the same test and keeps propagating - it evaluates to `:undefined` rather
  than answering, since `==` is a non-strict comparison operator. **The ISA version does not move**: surface
  syntax is outside the ISA (`docs/isa.md` §6), and `lit`'s operand already
  admitted `:undefined` per §3's value domain, so this is a new spelling for
  an instruction that already existed, not a new opcode or a widened one.
  `Predicator.decompile/2` renders the literal back as `undefined`.
- **`if`/`else` statements parse.** `Predicator.parse_program/2` accepts
  `if cond { ... }` with an optional `else` block, producing two new AST
  nodes - `{:if, condition, then_block, else_block, pos}` and
  `{:block, statements, pos}`. Braces are mandatory, a block may be empty,
  and `{ }` groups statements without opening a scope, so an assignment
  inside a branch writes to the same flat context as one outside it.
  `else if` is parser sugar with no chain node of its own: it parses as an
  `else` block whose sole statement is the nested `if`, so
  `if a { A } else if b { B }` and the hand-nested form produce the same
  tree. `if` is statement-position only - `Predicator.parse/2` rejects it
  with a message naming `parse_program/2`. **`if`/`else` now lowers to
  instructions and runs**: `Predicator.execute/2,3` compiles an `if`
  statement to the ISA v5 jump opcodes below and executes it, with an
  unbound or non-boolean condition following the standing `on_unbound`/
  `TypeMismatchError` rules. **`Predicator.decompile/2` renders an `if`
  statement back to source**: an `else` block whose sole statement is an
  `if` prints as `else if` rather than nesting a new block, so
  `parse_program |> decompile |> parse_program` is a fixpoint.
- **ISA v5: `jump` and `pop_jump_if_falsy`.** Two new opcodes, tier 8
  (control flow) - `jump` is an unconditional relative forward jump; `pop_jump_if_falsy`
  pops the stack top always and jumps to it when falsy, unlike
  `jump_if_falsy_or_pop`, which preserves the value on the taken branch. Both
  are what `if`/`else` statement lowering needs (ADR-0013), and the compiler
  now emits both when lowering an `if` statement. Every ISA v5 instruction
  list still provably halts in at most `length(program)` steps, since neither
  opcode introduces a backward jump.
- **ISA v6: `jump_backward`, the only back edge, and the loop budget.** A new
  opcode, tier 9 (loops) - an unconditional relative jump to `index - offset`,
  distinct from `jump` rather than a negative offset on it, so opcode-name
  scanning stays a sound version check and the *absence* of `jump_backward`
  in a list remains a termination proof. Execution of a list containing it is
  bounded: a per-execution loop budget is charged on every back edge taken,
  by default 10,000, shared across every loop in the program, configurable
  per call with the new `:loop_budget` evaluation option (`evaluate/3`,
  `execute/3`, `Predicator.Evaluator.evaluate/3`) - a non-negative integer, or
  `0` to forbid back edges entirely; anything else raises `ArgumentError`, the
  same line `:on_unbound` draws. Exhaustion stops execution with an
  `EvaluationError` whose reason is `"loop_budget_exceeded"`, carrying the
  failing `jump_backward` instruction's position.
- **`while` statements parse, compile, and round-trip.**
  `Predicator.parse_program/2` accepts `while cond { ... }`, producing a new
  AST node - `{:while, condition, body, pos}`. `while` is statement-position
  only, exactly like `if`: `Predicator.parse/2` rejects it with a message
  naming `parse_program/2`. Braces are mandatory and the body block opens no
  scope, so an assignment inside the loop writes to the same flat context as
  one outside it. `while` lowers to the ISA v6 `jump_backward` opcode above -
  `docs/isa.md`'s "Emitted by compiler" column now reads `yes` - and every
  execution is bounded by the loop budget. `Predicator.decompile/2` now
  round-trips `while`, rendering `while cond { ... }` and re-parsing to the
  identical tree; `if`/`block` still decline pending `px-3so.5`. `while` was
  already a reserved word from the v5 release (it could not be used as a
  variable name, a bare property name, or a bare object key), so this is no
  new grammar break.
- **Conformance corpus: tier 9 (loops) covers `jump_backward` and budget
  exhaustion.** Six hand-authored cases in `conformance/cases/loops.json` -
  no compiler emits the opcode yet, so these are instruction lists rather than
  source - covering a counted loop running to completion, a loop whose
  condition is falsy from the start, that the back edge is unconditional, an
  unconditionally infinite loop exhausting the default budget with reason
  `"loop_budget_exceeded"`, and a zero offset and a target before index 0
  each falling through to `unknown_instruction`.
- **Conformance corpus: tier 8 covers else-if chains, nesting, and empty
  blocks.** `conformance/cases/control_flow.json` gains eleven if/else
  statement-shaped cases exercising ADR-0013's full lowering: an else-if
  chain taking each of its three branches, a nested if/else inside a then-
  branch (both inner branches, plus the outer else skipping the nested
  check entirely), an empty then-block and an empty else-block each taken
  and not taken, and a non-boolean condition raising `TypeMismatchError`
  inside the full if/else lowering rather than a bare `pop_jump_if_falsy`.
  Tier 8's case count moves from 6 to 17 and the corpus hash advances
  (`px-3so.6`).
- **Type casts (`::`).** A postfix `expr::type` operator converts a value to
  one of the seven scalar types - `string`, `integer`, `float`, `boolean`,
  `date`, `datetime`, `duration` - and chains, so `"42"::integer::float` casts
  twice left to right. It binds tighter than unary minus, so `-1::integer` is
  `-(1::integer)`, i.e. `-1`, matching PostgreSQL. Casting compiles to a new
  `cast` opcode at ISA v4, tier 7 - additive, no stored artifact changes
  meaning. A conversion that cannot produce a value of the target type is
  `:undefined`, not an error: `"abc"::integer` evaluates to `:undefined`
  rather than raising, so a bad cast inside a larger expression like
  `"abc"::integer > 5` is just falsy. `datetime::string` omits the
  fractional-seconds field when the sub-second component is zero and emits
  exactly six digits otherwise, never any other shape. `Predicator.decompile/2`
  renders a cast back to `::` syntax, parenthesizing the operand only when it
  binds looser than the postfix level (`(1 + 2)::string`, `(-1)::integer`), so
  casts round-trip losslessly.
- **The conformance corpus's tagged `datetime` encoding pins its
  fractional-seconds form.** `{"$type": "datetime", "value": ...}` now
  canonicalizes on both encode and decode, so the emitted `value` string is a
  function of the instant alone: the fraction is omitted entirely when the
  sub-second component is zero and is exactly six digits when it is not, the
  same form `datetime::string` already carries. Previously the emitted digit
  count tracked Elixir's internal `microsecond` precision field, so the same
  instant could encode two different ways depending on which code path
  produced it. Every tagged `datetime` value shipped in the 4.0.0 corpus is
  already zero-fraction, so this makes precise a specification a sibling may
  already be reading, without moving any byte currently on disk.
- **`Predicator.FunctionProvider` behaviour.** A module implements one
  callback, `functions/0`, returning `%{name => {arity, atom}}` - the atom
  names a public `(args, context)` function on the same module. The four
  builtin modules (`SystemFunctions`, `DateFunctions`, `JSONFunctions`,
  `MathFunctions`) implement it and are the default provider list, named by
  `Predicator.FunctionProvider.builtin_providers/0`.
- **`Context.new/2` gains `providers:`, `builtins:`, and `host:`.**
  `providers:` is a list of `FunctionProvider` modules, resolved left to
  right into the dispatch map after the builtins (unless `builtins: false`)
  and before the inline `:functions` closure map - each later source shadows
  a same-named entry from an earlier one. A provider module that fails to
  load, lacks `functions/0`, or names an atom not exported at arity 2 raises
  `ArgumentError` at construction, naming the module and the offending
  entry - host API misuse, not a predicate-derived failure (ADR-0004).
  `host:` carries an opaque term - a database connection, a request struct, a
  tenant id - stored exactly as given, with no normalization, and never
  reachable from predicate text. `Context.put_host/2` replaces it in O(1),
  independent of the data map's size, leaving `data`, `functions`, and
  `on_unbound` untouched.

### Changed

- **Every custom function's second argument is now the `%Predicator.Context{}`
  struct, not the bare data map.** Read the data namespace with
  `context.data` (was: the second argument itself) and, for a provider
  function, host state with `context.host`. The rewrite for an existing
  closure is a one-line change at each data read in the function body:
  `fn [args], context -> ... Map.get(context, "x") ... end` becomes
  `fn [args], context -> ... Map.get(context.data, "x") ... end`. Provider
  registration (`providers:`) replaces the closure map as the primary
  interface; an inline `:functions` closure map survives as a convenience for
  one-off calls and tests, still called under the same `(args, context)`
  convention, but a context carrying one is not serializable (a context built
  only from `providers:` is - `:erlang.term_to_binary/1` round-trips it).
  This is a breaking change and ships as 5.0.0 (ADR-0014).
- **`if`, `else` and `while` are reserved words.** The lexer now classifies
  all three as keywords rather than plain identifiers, so a predicate that
  used one as a variable name (`if = 3`), a bare property name (`user.if`),
  or a bare object key (`{if: 1}`) is now a parse error. The fix is renaming
  the variable or, for an object key, quoting it (`{"if": 1}`, which still
  parses). Only the lowercase spelling is reserved - `IF`, `Else`, and
  similar stay ordinary identifiers. All three words are reserved together
  even though `while` does not gain real grammar until a later release, so
  the break lands once instead of twice (ADR-0013).
- **`undefined` is a reserved word.** The lexer now classifies it as a
  literal keyword rather than a plain identifier, so a predicate that used it
  as a variable name (`undefined = 3`), a bare property name
  (`user.undefined`), or a bare object key (`{undefined: 1}`) is now a parse
  error. The fix is renaming the variable or, for an object key, quoting it
  (`{"undefined": 1}`, which still parses). Only the lowercase spelling is
  reserved - `UNDEFINED` and `Undefined` stay ordinary identifiers.
- **Published ADR set.** The API documentation now carries every ADR its pages
  cite - ADR-0009 (the compiled envelope) and ADR-0011 (casts are an opcode)
  join 0001-0003 - so those citations resolve on hexdocs instead of 404ing.
  The governance ADRs stay unpublished and the ADR index links them by
  absolute GitHub URL.
- Type-mismatch errors raised by an instruction that only exists as the
  lowering of a source construct now name the construct rather than the
  opcode. `if "a" { y = 1 }` and `while "a" { y = 1 }` report `Condition
  requires a boolean, got "a" (string)` instead of `Pop Jump If Falsy
  requires ...`; `"a" and true` and `"a" or true` report `Logical AND` and
  `Logical OR`, matching their non-short-circuit twins; a failing store
  reports `Assignment requires a string or an integer, got true (boolean)`
  instead of `Store requires ...`. Error positions, the instruction set, and
  the conformance corpus are unchanged. `in` and `contains` keep their
  existing `In` / `Contains` rendering deliberately - both are operators the
  author types, so neither leaks an opcode name.

### Removed

- **`Evaluator.merge_functions/1`.** Replaced by provider resolution at
  `Context.new/2`; the shadowing order (builtins first, then `providers:`
  left to right, then `:functions`) is unchanged.
- **`all_functions/0`** on the four builtin function modules. Each module's
  `functions/0` (added non-breaking, ahead of this release) is the only
  registration surface now; the underlying `call_*` implementations are
  unchanged.

## [4.0.0] - 2026-08-08

### Added

- **Statement grammar.** `Predicator.parse_program/2` and
  `Predicator.Parser.parse_program/2` parse
  `program := statement (";" statement)* [";"]`, where a statement is either an
  assignment (`location "=" expression`, the left side an identifier optionally
  followed by `.name` and `[key]` accessors) or an ordinary expression. Programs
  parse to `{:program, [statement], position}`, assignments to
  `{:assignment, lhs, rhs, position}`; both carry positions or spans like every
  other node, and both round-trip through `Predicator.decompile/2`. The
  expression grammar is otherwise unchanged, and `Predicator.parse/2` still
  returns a bare expression AST. Compiling and running a program is the
  `store` and `pop` opcodes and `Predicator.execute/2`, below.

- **The `store` and `pop` opcodes; compiling and running a program.** ISA v3
  gains two tier-6 opcodes: `["store", n]` pops a value and the `n` location
  segments beneath it and writes `path -> value` into the evaluator's
  context - the only opcode that does - and `["pop"]` discards the stack top.
  `docs/isa.md` §5 has the full stack discipline and error shapes. **No
  existing instruction list changes meaning**: this is additive on top of a
  retirement (`and`, `or`) that v3 has never shipped, so every instruction
  list valid before this change stays valid and means the same thing after
  it. `Compiler.to_instructions/2` and `to_instructions_with_positions/2` now
  accept a `Parser.program()` as well as an expression AST, compiling
  `{:program, ...}` and `{:assignment, ...}` per `docs/reference/ast.md`'s
  "Statement nodes" section. `Predicator.compile_program/1` and
  `compile_program_with_positions/1` are the program-shaped echoes of
  `compile/1` and `compile_with_positions/1`. `Predicator.execute/1,2,3` is
  the statement-mode entry point: `execute(program_or_source, context \\ %{},
  opts \\ [])` accepts source, an instruction list, or a `%Compiled{}`, and
  returns `{:ok, %Context{}} | {:error, error, %Context{}}`. On error the
  third element is the context as of the last statement that completed
  successfully - prior writes survive a later failure, and whether to keep or
  discard them is the caller's policy, not the engine's: a caller wanting
  all-or-nothing drops the third element and keeps the context it already
  had. `Predicator.Evaluator.run_state/1`, the state-preserving runner
  statement mode needs, is now public. `Predicator.execute/1,2,3` has a
  sibling, `execute_value/1,2,3`, below, for a caller who also wants the
  program's last expression statement's value.

- **`Predicator.execute_value/1,2,3`.** The sibling of `execute/1,2,3` for a
  caller who also wants the program's last expression statement's value:
  it returns `{:ok, value, %Context{}} | {:error, error, %Context{}}`, where
  `value` is that statement's value, or `:undefined` when the program has no
  expression statement (an assignments-only program, for instance).
  `Predicator.execute/1,2,3` is unchanged and still returns
  `{:ok, %Context{}}`. The value comes from `Predicator.Evaluator.last_value/1`,
  a new accessor over a new `last_value` field on `%Evaluator{}` that the
  machine fills in as it runs. No compiled program changes and the ISA does
  not move - the value is retained by the machine, not encoded by the
  compiler, so an instruction list compiled before this change runs
  identically and reports the same value under `execute_value/2`.

- **Source spans.** A point position tells an editor where to put a caret; a
  span tells it what to underline. `Predicator.Parser.parse/2`,
  `Predicator.parse/2`, and `Predicator.evaluate/3` (string input only) take
  `spans: true`, under which every AST node's existing trailing slot carries a
  `t:Predicator.Types.span/0` - `{{start_line, start_col}, {end_line, end_col}}`
  with an **exclusive** end, matching LSP ranges - instead of a
  `{line, column}`. For `a * true` the `arithmetic` node spans the whole
  expression rather than naming column 3. A parenthesized expression's span
  widens to include its parentheses, so `(a + b)` spans `(a + b)` rather than
  `a + b`, and this composes upward: `(a + b) * c` gives the `multiply` node a
  span slicing to the whole source string. Nesting composes to the outermost
  pair, so `((a))` spans `((a))`.

- `t:Predicator.Types.span/0` and `t:Predicator.Types.span_table/0`.

- `Predicator.compile_with_spans/1`, the span-mode sibling of
  `compile_with_positions/1`. Returns `{:ok, %Predicator.Compiled{}}` whose
  `positions` holds a span table mapping each instruction index to a span;
  `instructions` is byte-identical to `compile/1`'s output. Pass the struct
  straight to `evaluate/3`, which threads the table itself.

- **`Predicator.Compiled`**, a two-field struct pairing an instruction list
  (`instructions`) with its source-location table (`positions`), plus a
  doctested `new/2` for a caller who stored the two separately and wants them
  back as one value. Returned by `compile_with_positions/1` and
  `compile_with_spans/1` and accepted directly by `evaluate/3`. It is an
  in-memory Elixir value, not a wire format - see ADR-0009.

- `:span` on `Predicator.Errors.EvaluationError`,
  `Predicator.Errors.TypeMismatchError`, and
  `Predicator.Errors.UndefinedVariableError`, defaulting to `nil`.

- `Predicator.Errors.put_position/2` accepts a span: it sets `:span` to the span
  and `:position` to the span's start, so a caller reading only `:position`
  still gets a usable caret under `spans: true`.

- `Predicator.Evaluator.unbound_loads_with_locations/1`, returning each unbound
  load paired with the source location of the instruction that read it.
  `unbound_loads/1` is unchanged.

- **ISA version stamping.** `Predicator.isa_version/0` returns the integer ISA
  version this build emits and can run, currently `2`, independent of the
  library's semantic version (ADR-0003). `Predicator.Instructions.required_isa/1`
  takes a compiled instruction list and returns the minimum ISA version it
  needs, computed by scanning its opcode names against the table in
  `docs/isa.md`: `{:ok, integer}`, or `{:error, %Predicator.Errors.EvaluationError{}}`
  for an unknown opcode or a malformed element. Together they let a consumer
  holding a stored artifact, or a sibling implementation handed an instruction
  list, refuse it up front instead of failing partway through a run. **No
  instruction changed**: the wire format is still a bare list, no opcode was
  added or altered, and every instruction list valid before this release is
  valid after it.

- `Predicator.Instructions.opcodes/0`, returning the full opcode table -
  every opcode mapped to the ISA version that introduced it and its
  conformance tier - and `Predicator.Instructions.tier/1`, returning a single
  opcode's tier as `{:ok, integer}` or the same `"unknown_opcode"`
  `{:error, %Predicator.Errors.EvaluationError{}}` `required_isa/1` returns.
  Tier is a conformance-corpus grouping (`px-35i.4`), a function of opcode
  only, per `docs/isa.md` section 4.

- **The conformance corpus** (`px-35i.4`). `conformance/` in the repository -
  deliberately not shipped in the hex package, since nothing an application
  does at runtime reads it. The tooling that maintains it is excluded for the
  same reason and is **not public API**: the `mix corpus.*` tasks and the
  `Predicator.Conformance.*` modules they call exist only in a git checkout.
  Authored cases live in `conformance/cases/*.json`;
  the generated, checked-in corpus in `conformance/corpus/tier-*.json` (one
  case per line, sorted by id); and `conformance/manifest.json` (ISA version, a
  `corpus_hash` sha256 over the corpus content, and the tier/opcode/case-count
  table). `mix corpus.generate` regenerates both from the authored cases by
  running each through the real compiler and evaluator; `mix corpus.generate
  --check` regenerates in memory and exits non-zero on drift without writing,
  for CI. `test/predicator/conformance/corpus_freshness_test.exs` does the
  same in-process and fails the suite naming the affected case ids, so a
  semantic change nobody meant to make turns the gate red instead of silently
  shipping a stale corpus.

- **Conformance corpus breadth, schemas, and the runner contract** (`px-35i.4`
  Phase 5). Cases now cover every opcode except the two documented exclusions
  (`relative_date`, clock-dependent; `object_set` on a non-map, unspecified),
  a rule `test/predicator/conformance/opcode_coverage_test.exs` enforces and
  binds to `conformance/README.md`'s own exclusion list. `conformance/schema/`
  gains `corpus.json`, `manifest.json`, and `report.json` (JSON Schema, draft
  2020-12) alongside the existing `case.json`; every generated artifact is
  validated against its own schema. `conformance/README.md` is the runner
  contract a sibling implementer reads first: the two surfaces (evaluator and
  compiler), the tagged-value encoding normatively, the never-skip rule and
  why `schema/report.json`'s `result` enum has no skip value, how to add a
  case without an Elixir toolchain, and the known-uncovered list. `docs/isa.md`
  now points at `conformance/README.md` as the spec's executable form.

- **`mix corpus.coverage`** (`px-35i.4` Phase 6). The corpus is authored, not
  extracted from the existing ExUnit suite, so nothing else tells an author
  what that suite exercises that the corpus does not. This dev-only task
  statically scans `test/**/*.exs` (excluding the corpus's own test suite)
  for literal `Predicator.evaluate/2,3` and `Predicator.compile/1` sources,
  compiles each through the real compiler, and diffs the resulting opcode/
  operand patterns against the shipped corpus's own instructions, printing a
  checklist of gaps grouped by tier. `Predicator.Conformance.Coverage` holds
  the diffing logic; report only, it never writes a case and never fails the
  gate. Function gaps are classified against the builtin registry: a name no
  builtin module registers is suite-local test scaffolding and prints under a
  trailing "Not corpus candidates" heading, and the non-deterministic
  exclusions carry an inline note instead of a bare `corpus: 0` row.

- **`conformance/RATCHET.md`: the sibling conformance ratchet format**
  (`px-35i.8`). Specifies the registry a sibling implementation (`impl/rb`,
  `impl/ts`, or any future port) writes to record which corpus cases it
  passes, on which surface, against which corpus version - this repo
  publishes the format only, and ships no registry and no runner itself. A
  registry entry keys on `(case_id, surface)`, not `case_id` alone, because a
  `source: null` case is absent from the compiler's case set rather than
  present-and-skipped, and a flat id list cannot express that a `compiler`
  claim on such a case is meaningless. Rule 1: an entry whose
  `(case_id, surface)` pair (or `tier`) disagrees with the pinned corpus fails
  the run, never silently drops. Rule 2: entries are sorted by
  `(surface, tier, case_id)` and encoded one per line with no indentation, so
  ratcheting a case in is a one-line diff rather than a reflowed array nobody
  reviews. Rule 3: the registry is grown only by verify-then-add - written
  solely from a runner report, refusing to record a failing case and never
  removing an existing entry - so every line in the file is a claim a run
  actually observed. The whole registry pins to a single
  `corpus_hash` from `conformance/manifest.json`; a mismatch is a hard
  failure, not an auto-refresh. `conformance/schema/registry.json` is the
  schema and `conformance/examples/registry.example.json` the worked example,
  both validated against the shipped corpus by
  `test/predicator/conformance/ratchet_registry_test.exs`. RATCHET.md also
  carries language-neutral pseudocode for the reference runner and the CI-side
  check step, so a sibling with no Elixir toolchain can implement both without
  guessing. Nothing here enters the hex package: `conformance/` is excluded
  from `mix.exs`'s `files:` list, same as the rest of the corpus tree.

- **Opcode retirement mechanics** (`px-t2v`). `Predicator.Instructions.in_isa?/2`
  answers whether an opcode's table entry is in a given ISA version's set;
  `opcode_set/1` returns the full set of opcode names a given ISA version
  comprises; `retired_in/1` returns the ISA version that retired an opcode, or
  `{:ok, nil}` for one still live, mirroring `tier/1`'s error shape for an
  unknown name. `opcodes/0`'s value shape widens to carry an optional
  `:removed_in` key alongside the existing `:isa` and `:tier` - no opcode
  carries it yet, so every existing return value is unchanged.

- **Two new guides** (`px-ycj`). [Porting Predicator](docs/guides/porting.md)
  is the path a sibling implementation follows: what an ISA version obliges it
  to implement, the two conformance surfaces and which to lead with, how to
  run the tiered corpus, and what "conformant at tier N" claims.
  [Embedding compiled programs](docs/guides/embedding.md) is the
  compile-once/store/check lifecycle: `compile/1` versus
  `compile_with_spans/1`, what is safe to store, the `required_isa/1` check
  against `isa_version/0`, and what a major version does to a stored
  artifact. Both are published as hexdocs extras and linked from the README.

### Documentation

- **Contributor how-tos move out of the published docs** (`px-7jd.3`).
  `docs/architecture.md`'s Development, Common Tasks, Code Standards,
  Performance Considerations, and Troubleshooting sections - the quality-check
  commands, the "Adding New Operators" and "Adding New Data Types" checklists,
  and debugging notes - move to the new `docs/contributing.md`, which is not
  listed in `mix.exs`'s hexdocs extras and so is neither published nor shipped
  in the hex package. `docs/architecture.md` now reads as architecture; the
  README's Development section points at the new file. **No behavior
  changed**; this only moves where contributor instructions live.

- **`docs/reference/language.md` documents `:undefined` and sparse-data
  semantics.** A new "Undefined and Sparse Data" section covers where
  `:undefined` comes from (unbound roots, missing nested paths), mismatched
  non-strict comparisons, `AND`/`OR` falsiness and its ECMAScript-style
  asymmetry, a per-operator reject-vs-propagate table, and the `on_unbound`
  option, including the API-layer rule that reports a genuinely unbound root
  as `UndefinedVariableError` even under the default policy. The Arithmetic
  Operators table's `/` row is corrected: it previously read "Division
  (integer)" for every case, when a float operand actually produces float
  division. **No behavior changed**; this is a documentation-only addition.

- **`docs/isa.md` reserves `pop` and specifies the statement-mode halt
  contract.** `["pop"]` joins `["store"]` as a reserved tier-6 name for the
  future 4.0 statement layer - not implemented, not accepted by any current
  evaluator clause, distinct from the live `jump_if_falsy_or_pop` /
  `jump_if_true_or_pop` opcodes despite the shared word. Section 2 now
  specifies two execution modes, distinguished by entry point rather than by
  anything in the instruction list: expression mode, where the result is the
  stack top at halt; and statement mode, where the result is the context at
  halt, with an empty stack at halt by design. `empty_stack` is now documented
  as an expression-mode rule only - a statement program halting with an empty
  stack is a normal halt, not an error. A statement program that halts on an
  error has no result; whether the host keeps or discards the partial context
  from statements that already completed is the host's policy, not the VM's.
  **No instruction-set behavior changed**: no opcode is added, removed, or
  resemanticized, and the ISA version stays v2.

- **`docs/isa.md`: the ISA reference.** The single specification of
  predicator's instruction set - one table row per opcode naming its arity,
  operand types, stack effect, error semantics, ISA version, and conformance-
  corpus tier, plus the cross-cutting rules that previously existed only as
  prose in ADR-0001: what "falsy" means at a jump (`false` or `:undefined`),
  that jumps are relative and forward-only, that opcodes validate rather than
  coerce, and that a malformed operand is an unknown instruction rather than a
  bad one. It also records ADR-0003's versioning scheme (integer ISA versions
  independent of this library's semver) rather than re-arguing it. The
  `Predicator.Evaluator` moduledoc and `t:Predicator.Types.instruction/0` no
  longer carry their own opcode lists - both now point at `docs/isa.md`
  instead. **No instruction-set behavior changed**: this is a documentation
  addition that consolidates specification already true of the evaluator, not
  a change to what any opcode does.

- **ADR-0003: the Elixir implementation leads the ISA.** Amends ADR-0001's
  consequences (not its decision): sibling parity in Ruby and JavaScript is a
  downstream obligation, not a gate on ISA changes made here, and the ISA is
  versioned so a sibling behind the current version is an expected, documented
  state rather than a defect. Stored-artifact compatibility remains the
  stronger, separate guarantee. The ADR also settles three rules the ISA moves
  under: an opcode's semantics never change under its own name, ISA versions are
  integers independent of this library's version (additive versions ship in a
  minor release, opcode retirement in a major one), and each sibling publishes
  its own supported version rather than being tracked in a matrix here. This
  does not change the instruction set - no opcode is added, removed, or
  resemanticized. `README.md`'s "Cross-Language Siblings" section and the
  equivalent section in `docs/architecture.md` are reworded to match.

### Fixed

- `Predicator.decompile/2` under the default `parentheses: :minimal` now adds
  parentheses when a child subexpression binds looser than its parent, or
  ties with it in a position where left-associativity would otherwise regroup
  it. Previously `:minimal` added no parentheses at all, so
  `{:arithmetic, :multiply, {:arithmetic, :add, 1, 2}, 3}` rendered as
  `"1 + 2 * 3"`, which re-parses as `1 + (2 * 3)` - a different AST and a
  different value than the one decompiled. `parentheses: :explicit` and
  `parentheses: :none` are unchanged.

- `Predicator.Errors.UndefinedVariableError` now carries a `:position` (and a
  `:span` under `spans: true`) on every path. The evaluator records each unbound
  load's source location alongside its name, so the error `Predicator.evaluate/3`
  builds after the run - for a bare unbound root, and for the `px-8um.7` rewrite
  of a `TypeMismatchError` that rejected an unbound root's `:undefined` - points
  at the variable's own token. It was the one runtime error type whose
  `:position` was always `nil`. An instruction-list caller who passes no
  `positions:` still sees `nil`.

- **`bracket_access` on a list with a non-integer key no longer crashes.**
  `xs[flag]` against a list target with a boolean (or any other non-integer)
  key raised `FunctionClauseError` from ordinary user-authored source instead
  of returning an error value; it now returns `{:error,
  %Predicator.Errors.TypeMismatchError{}}` with `expected: :integer`. The same
  crash via `.property` (the `access` opcode) against a list target now pushes
  `:undefined`, matching that opcode's existing "never an error" contract.

- **`docs/isa.md`'s `bracket_access` bullet corrected**: a boolean key against
  a map target has always been an accepted key, not a `TypeMismatchError` -
  the bullet previously left a reader to guess whether a boolean fell on the
  atom side or the rejected side of that line. This is a documentation
  correction, not a behavior change: no ISA version change and no existing
  instruction list changes meaning.

- **A store failure blames the location, not the `=`.** In point-position mode
  the `["store", n]` instruction is now annotated with the lhs root segment's
  position rather than the assignment node's operator token, so
  `Predicator.execute("a = 1; a.b = 2", %{})` reports `position: {1, 8}` (the
  `a` being written) instead of `{1, 12}` (the `=`). Span mode is unchanged -
  the assignment's span already started at the lhs root, and this makes the two
  modes agree. Every emitted instruction list is byte-identical; no ISA version,
  error type, reason, or `{:error, error, context}` shape moves.

- **The store segment-type message names both accepted types.** An out-of-domain
  location segment now reports `Store requires a string or an integer, got true
  (boolean)` rather than `Store requires a string`, which was false about what
  `store` accepts - integer segments index lists. The normative
  `expected: :string` field is unchanged, matching how `docs/isa.md` states
  `bracket_access`'s key rule. `Predicator.Errors.TypeMismatchError.unary/5` is
  the new constructor that separates the message text from the `expected` atom.

- **A store failure blames the exact failing location segment.** Building on
  the fix above, the compiler now emits a per-store side table mapping each
  `["store", n]` instruction's index to one source annotation per location
  segment, and the evaluator joins it with the failing segment's path index.
  `Predicator.execute(~s(a = {"b": 1}; a.b.c = 2), %{})` reports
  `position: {1, 17}` - the property `b`, which held a scalar - instead of
  `{1, 15}`, the location's root;
  `Predicator.execute("a[true] = 1", %{"a" => %{}})` reports `{1, 3}`, the
  offending key, instead of `{1, 1}`. Under `spans: true` the
  underline narrows to the failing segment (`a.b`) instead of covering the whole
  statement; the caret is unchanged, because a chain node's span already started
  at the chain root. `Predicator.Compiled` gains a `segment_positions` field and
  `Predicator.Compiled.new/3`, `Predicator.Compiler` gains
  `to_instructions_with_segment_positions/2`, and
  `Predicator.Evaluator.evaluate/3` accepts a `:segment_positions` option - all
  additive. A run without the table (a bare instruction list, a stored program)
  positions a store failure exactly as it did before, at the location's root.
  Every emitted instruction list is byte-identical; no ISA version, error type,
  reason, `expected`, or `{:error, error, context}` shape moves.

### Changed

- **Property and bracket access blame the accessed thing, not the accessor.**
  A `{:property_access, ...}` node's point position is now the property-name
  token rather than the `.`, and a `{:bracket_access, ...}` node's is the
  first token of the key expression rather than the `[`.
  `Predicator.parse("user.name")` reports `{1, 6}` instead of `{1, 5}`; the
  position table entry for an `["access", ...]` or `["bracket_access"]`
  instruction moves with it, and so does any error stamped from one. Spans are
  unchanged: `spans: true` still runs a chain node from the chain root to the
  accessor's end. No instruction list, opcode, ISA version, error type, or
  reason moves.

- `Predicator.compile_with_positions/1` now returns `{:ok, %Predicator.Compiled{}}`
  instead of `{:ok, instructions, position_table}`. The envelope carries the
  instruction list and its source-location table as one value, so the table
  cannot be silently dropped between compilation and evaluation;
  `Predicator.evaluate/3` accepts a `%Predicator.Compiled{}` directly and
  threads the table itself. Read `compiled.instructions` and
  `compiled.positions` for the old tuple elements; `evaluate/3`'s `:positions`
  option still works for a bare instruction list. `Predicator.compile/1` and
  `Predicator.compile!/1` are unchanged and still return a bare instruction
  list, which remains what a consumer serializes and stores. No instruction
  changed and the ISA stays at version 3, so stored artifacts need no
  migration. See [ADR-0009](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0009-the-compiled-envelope-carries-the-position-table.md).

- `Predicator.decompile/2` renders a `{:comparison, :eq, ...}` node as `==`
  rather than `=`, so decompiled output always re-parses under the 4.0 grammar.
  The node's meaning and compiled instructions are unchanged.

- `docs/isa.md` now specifies opcode retirement mechanics: retiring an opcode
  mints the next ISA version, a version's opcode set is a half-open interval
  so a retired opcode keeps its table row instead of being deleted, and the
  conformance corpus freezes a retired case's expectation rather than
  recomputing it through an evaluator clause that no longer exists.

- `Predicator.Instructions.required_isa/1`'s `unknown_opcode` error message now
  names the ISA version this build supports, not just the offending opcode:
  `Unknown opcode "store"; this build supports ISA v2` instead of
  `Unknown opcode: "store"`. The error struct is unchanged - reason
  `"unknown_opcode"`, operation `:required_isa`.

- **BREAKING: the minimum Elixir version is now 1.18.** `mix.exs` previously
  declared `~> 1.11`, but CI has tested only 1.17 and 1.18 for a long time, so
  the declaration promised support that was neither verified nor known to work.
  1.18 is required for the built-in `JSON` module; consumers on 1.17 or earlier
  must stay on 3.x.

- `object_set` on a non-map target is now specified behavior. The evaluator
  returns `%Predicator.Errors.EvaluationError{}` with reason
  `"invalid_stack_value"` and operation `:object_set` instead of raising a
  `FunctionClauseError`, matching how `relative_date` reports a non-duration on
  the stack. `docs/isa.md` section 5 states it normatively rather than calling
  it unspecified, and the conformance corpus covers it in the errors group - so
  a sibling implementation must now produce this error to claim tier 4. The
  shape is reachable only from a hand-built instruction list; the compiler
  always emits `object_new` immediately before `object_set`, so nothing
  compiled from source changes.

### Removed

- **`=` as an equality operator.** `==` and `===` are the only equality
  operators. `=` is assignment, valid only at the start of a statement and only
  with an assignable left side; a bare `=` in expression position - through
  `Predicator.parse/2`, `Predicator.evaluate/3`, or nested inside a statement -
  is a parse error naming `==` as the fix, never a silent reinterpretation. The
  3.7.0 deprecation warning was the notice period; migrate to `==` before
  upgrading. **The instruction set is unaffected**: `=` and `==` always compiled
  to `["compare", "EQ"]`, `{:comparison, :eq, ...}` remains a fully supported
  AST node, and no stored instruction list is invalidated. See
  [ADR-0002](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0002-the-equals-grammar-break.md).

- The `config :predicator, deprecation_warnings` setting, which existed only to
  silence that warning. It is now inert and has been deleted; remove it from
  your config.

- **Breaking:** `:line` and `:column` on `Predicator.Errors.ParseError`. The
  struct now stores the location once, in `:position`, as the
  `{line, column}` tuple typed `t:Predicator.Types.position/0` that
  `EvaluationError`, `TypeMismatchError`, and `UndefinedVariableError` already
  carry. Code reading `error.line` reads `elem(error.position, 0)` instead, or
  better, matches `%ParseError{position: {line, column}}`.
  `ParseError.new/3` keeps its `(message, line, column)` signature, and error
  message text is unchanged.

- **BREAKING: the pre-4.0 AST shape acceptance.**
  `Predicator.Parser.strip_positions/1` and
  `Predicator.Parser.ensure_positions/1` are gone, along with the
  `t:Predicator.Parser.bare_ast/0` and `t:Predicator.Parser.bare_object_key/0`
  types. The AST has one shape: every node carries a trailing slot holding a
  position, a span, or `nil`.

  `Predicator.decompile/2`, `Predicator.Compiler.to_instructions/2`,
  `Predicator.Compiler.to_string/2`, and `Predicator.ContextLocation.resolve/2`
  no longer accept the position-free shape Predicator 3.6 produced. A caller
  building an AST by hand adds the slot:
  `{:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}`.
  A caller that was calling `strip_positions/1` to compare two ASTs while
  ignoring positions writes that traversal itself; it is a few lines and its
  exact semantics - whether object-key style is significant, for one - are the
  caller's to choose.

  The instruction set is unchanged, so stored compiled artifacts and the
  cross-language interchange format are unaffected (ADR-0001).

- **Breaking: the legacy `and`/`or` opcodes are retired from the evaluator.**
  ISA v2 becomes v3 (`Predicator.isa_version/0` now returns `3`). This only
  affects a consumer holding an instruction list that was compiled before
  3.7.0 and stored somewhere; nothing compiled by 3.7.0 or later contains
  these opcodes, since the compiler stopped emitting them then, so
  recompiling from source and every surface `AND` / `OR` expression are
  unaffected. Running such a stored list now returns an `EvaluationError` with
  reason `"retired_opcode"`, naming ISA v3 and the upgrade path, instead of
  being silently mis-run. The migration is
  `Predicator.Instructions.upgrade/1`, run once over stored artifacts to
  rewrite them into jump form (identity on anything containing neither
  opcode); the upgraded list short-circuits and follows the
  ECMAScript-aligned `:undefined` rules that ADR-0001 documented for 3.7.0,
  so a right operand that errored or was `:undefined` can now produce a
  value where it previously produced a `TypeMismatchError`. Because jumps are
  ISA v2 opcodes, upgrading also raises the list's `required_isa/1` answer
  from `1` to `2`, so an artifact shared with an implementation still on ISA
  v1 - which both siblings are - should be upgraded in step with those
  consumers rather than ahead of them. `and` and `or` keep their rows in the
  ISA table - `required_isa/1` and `tier/1` still answer for them - and the
  conformance corpus still carries all five legacy cases.

- **Breaking: the `jason` runtime dependency.**
  `Predicator.Functions.JSONFunctions` now uses Elixir 1.18's built-in `JSON`
  module, so **predicator has no runtime dependencies at all**. The error text
  from `JSON.parse` on malformed input changes wording - it now reads e.g.
  `Invalid JSON: unexpected byte 0x6F at position 1` - because the built-in
  decoder reports failures differently. `JSON.stringify` behavior, including
  the `inspect/1` fallback for values that cannot be encoded, is unchanged.

### Unchanged

Stated explicitly, because this release adds a second location representation
and nothing about the first one moves:

- Point positions remain the default at every entry point. `Predicator.parse/1`,
  `Predicator.compile/1`, `Predicator.compile_with_positions/1`, and
  `Predicator.evaluate/3` without the option behave exactly as in 3.8.0.
- `t:Predicator.Types.position/0` is untouched and still means a point.
- No AST node gained or lost an element; spans reuse the trailing slot.
- Every rendered error `message` string is identical with and without spans.
- The instruction list produced by `compile/1` is byte-identical, so stored
  compiled artifacts and cross-language interchange with the Ruby and
  JavaScript siblings are unaffected (ADR-0001).
- A parenthesized expression's span excludes its parentheses, which build no
  AST node.

## [3.8.0] - 2026-08-05

### Changed

- The Hex package tarball no longer bundles the markdown doc sources under
  `docs/`. Every guide, the language and architecture references, and the
  ADRs are still published in full at
  [hexdocs.pm/predicator](https://hexdocs.pm/predicator) and still live in
  the GitHub repository; only the copy that `mix deps.get` unpacked into
  `deps/predicator/docs/` is gone. Read them online or from a repo checkout
  instead.

- `Predicator.Evaluator.run_prepared/1` returns `{:error, error, evaluator}`
  instead of `{:error, error}`, so the final evaluator state - and with it
  `unbound_loads/1` - is available on the error path as well as the success
  path. `run/1`, `evaluate/3`, `evaluate!/3`, `evaluate_prepared/1`, and
  `Predicator.run_evaluator/1` are unchanged.

- **Context keys and `nil` values are now normalized eagerly and deeply.**
  `Predicator.Context.new/2` and `bind/3` convert atom keys to string keys
  (string key wins on collision) and `nil` values to `:undefined`, recursing
  through nested maps and lists, before evaluation ever sees the data. This
  is the one edge where atom keys and `nil` are accepted; the two
  `String.to_existing_atom/1` read-time fallbacks that used to paper over
  their absence - in `Predicator.Evaluator.load_from_context/2` (variable
  load) and `access_value/2` (property/bracket access) - are deleted, since a
  context reaching them through `Context.new/2`/`bind/3` never has atom keys
  left to fall back to. Ordinary `Predicator.evaluate/3`/`evaluate!/3`
  callers passing a bare map are unaffected - atom-keyed and `nil`-bearing
  contexts keep working exactly as before, now via the edge instead of the
  read-time fallback. The low-level `Predicator.Evaluator.evaluate/3`/
  `evaluate!/3` and `Predicator.evaluator/2` APIs, which construct an
  evaluator directly and bypass `Context.new/2`, no longer accept atom keys:
  this is better-defined behavior for that narrow surface, not a removal - a
  caller who wants atom-key or `nil` normalization goes through
  `Predicator.Context` or `Predicator.evaluate/3` instead.

  One narrowing follows from "deep and total": a duration value
  (`t:Predicator.Types.duration/0`) is a plain atom-keyed map, not a struct,
  so a pre-built `Predicator.Duration.new/1` result *bound into a context*
  now has its keys stringified like any other map and is no longer recognized
  as a duration by date arithmetic. Durations built the documented way - by a
  `duration(...)` or `3d8h` literal in the expression, during evaluation -
  never pass through this normalization and are unaffected.

- **Object keys are now `{:object_key, value, style, pos}`** rather than
  `{:identifier, name, pos}` / `{:string_literal, value, pos}`, where `style`
  is `:identifier`, `:double`, or `:single` and records how the key was
  written. Keys no longer reuse the expression node tags, so nothing tells a
  key from an expression by tuple arity. Callers pattern-matching a parsed
  object entry's key update their patterns to the new tag;
  `Predicator.Parser.strip_positions/1` still returns the 3.6 shape and
  `Predicator.Parser.ensure_positions/1` still accepts every earlier key
  shape, so a hand-built AST passed to `Predicator.decompile/2` or
  `Predicator.Compiler.to_instructions/2` is unaffected, and the instruction
  list is byte-identical.
- `Predicator.decompile/2` now renders a single-quoted object key with single
  quotes instead of rewriting it to double quotes, and escapes a quote
  character inside a key. A key containing the quote character previously
  decompiled to syntactically invalid source.

### Added

- `on_unbound: :error` on `Predicator.Context.new/2` (and as an option to
  `Predicator.evaluate/3` and `Predicator.Evaluator.evaluate/3`): a load of an
  unbound root variable returns
  `{:error, %Predicator.Errors.UndefinedVariableError{}}` instead of the
  `:undefined` sentinel. Roots only - a missing key on a bound map stays
  `:undefined` under either policy - and a load a short-circuit skipped never
  fires it. The default, `:undefined`, is unchanged behavior.

- `Predicator.Errors.ParseError` gains a `:position` field - `{line, column}`,
  derived from the existing `:line` and `:column` fields, which stay
  populated unchanged. Generic error-reporting code can now read `:position`
  uniformly across `ParseError`, `EvaluationError`, `TypeMismatchError`, and
  `UndefinedVariableError` instead of special-casing `ParseError`. Additive
  and non-breaking - no existing caller matching on `:line`/`:column` needs
  to change.

### Fixed

- **An unbound variable is no longer hidden behind a nameless type mismatch.**
  `Predicator.evaluate/3` reported `TypeMismatchError "Logical NOT requires a
  boolean, got :undefined"` for `not unbound`, naming no variable, while
  `unbound > 5` correctly returned `UndefinedVariableError`. Every opcode that
  rejects an `:undefined` operand - `not`, `unary_minus`, `unary_bang`, `add`,
  `subtract`, `multiply`, `divide`, `modulo`, and the legacy `["and"]`/`["or"]`
  instructions - now reports the unbound root instead, when the operand came
  from a variable the run loaded and did not find bound. A key *bound* to
  `:undefined` (`%{"b" => :undefined}`) and a missing nested path on a bound
  root (`user.nope`) still produce a `TypeMismatchError`: those are genuine
  type mismatches on data the caller supplied. Evaluation semantics are
  unchanged - `:undefined` still errors in these positions - and the low-level
  `Predicator.Evaluator.evaluate/3` still returns the bare `TypeMismatchError`.

- The Hex package `files:` list named a bare `docs` entry, which swept the
  whole `docs/` tree - including `docs/plans/*.md` and `docs/design/*.md`,
  the agent workflow's internal per-bead planning documents. It now names the
  published doc subtrees explicitly (`docs/reference`, `docs/guides`,
  `docs/adr`, `docs/architecture.md`), matching what the `docs()` extras list
  already publishes to hexdocs.

## [3.7.0] - 2026-08-05

### Changed

- **`AND` and `OR` now short-circuit.** Previously the compiler evaluated both
  sides of every `AND`/`OR` unconditionally, so an unbound variable or a
  runtime error on the side that should have been skipped surfaced as an
  error - `false AND score > 5` with `score` unbound raised
  `TypeMismatchError`, and `true OR (1 / 0) > 1` raised a division-by-zero
  error. Both now evaluate to `false` and `true` respectively, matching every
  mainstream language's `AND`/`OR` semantics and this library's own graceful
  undefined-handling documentation. **This is an observable behavior change**:
  expressions that previously returned `{:error, _}` now return `{:ok, _}`. A
  consumer relying on the error was relying on the bug. `:undefined`
  propagation is ECMAScript-aligned rather than symmetric - see
  `docs/architecture.md`'s "Short-Circuit Evaluation" section for the exact
  rule. Old compiled artifacts using `["and"]`/`["or"]` directly are
  unaffected; the evaluator still accepts both opcodes.
- `Predicator.parse/1` now returns positioned AST nodes, so every node has one
  more trailing element than it did in 3.6. Callers that pattern-match on node
  shape either wrap the result in `Predicator.Parser.strip_positions/1` to get
  the old shape back, or add a trailing `_position` to their patterns.
  `Predicator.decompile/2` and `Predicator.Compiler.to_instructions/2` still
  accept a hand-built 3.6-shaped AST unchanged, and the instruction list
  `Predicator.compile/1` produces is byte-identical, so stored compiled
  artifacts and cross-language interchange are unaffected.
- Documentation restructured: the README is now a slim entry point, with the
  language reference, nested data access, custom functions, and location
  expressions moved to `docs/reference/` and `docs/guides/` and published to
  hexdocs. All documentation examples are now executed by the test suite.

### Added

- **ISA v2** (ADR-0001): the instruction set is Predicator's cross-language
  interchange format, and both entries below are new opcodes the Ruby and
  JavaScript siblings need to add for parity with this release.
  - `["make_list", n]` instruction: pops n values from the stack and pushes
    them as a list, in source order.
  - `["jump_if_falsy_or_pop", offset]` and `["jump_if_true_or_pop", offset]`
    instructions: relative, forward-only conditional jumps used to
    short-circuit `AND`/`OR`.
- `Predicator.Context`: a bound evaluation context built once with `new/2`
  (merging builtin and custom functions a single time), rebound cheaply with
  `bind/3` and `assign/3`, and evaluated against many times via
  `Predicator.evaluate/3`, which now accepts either a `%Context{}` or a bare
  map
- `Predicator.Undefined`: the one public module that owns the `:undefined`
  sentinel - `value/0`, `undefined?/1`, and `to_nil/1`/`from_nil/1`
  normalizers for a JSON-shaped boundary. `Predicator.Types.undefined?/1`
  now delegates to it.
- `Predicator.Context.bound?/2`: answers whether a root variable is bound in
  a context's data, checking both string and atom keys.
- `starts_with(s, prefix)`, `ends_with(s, suffix)`, `substring(s, start[, len])`,
  and `index_of(s, sub)` builtin string functions
- `concat(list1, list2)` builtin function: concatenates two lists.
- `+` now concatenates two lists (`[1, 2] + [3]` -> `[1, 2, 3]`), alongside
  its existing numeric and string coercions.
- `Predicator.Evaluator.run_prepared/1` (result plus final evaluator state),
  `Predicator.Evaluator.unbound_loads/1`, and
  `Predicator.Evaluator.resolve_key/2`.
- Source positions on every AST node: each node carries a trailing
  `{line, column}` naming the token that defines it (the operator token for
  binary and unary operators, the opening bracket for lists and objects, the
  name token for function calls).
- `Predicator.Parser.strip_positions/1` and
  `Predicator.Parser.ensure_positions/1`: total, idempotent normalizers between
  the positioned AST and the position-free shape Predicator 3.6 produced.
- `Predicator.Compiler.to_instructions_with_positions/2` and
  `Predicator.Visitors.InstructionsVisitor.visit_with_positions/2`: compile to
  the usual instruction list plus a side table mapping each instruction's
  0-based index to the `{line, column}` of the AST node that emitted it. The
  table is an Elixir-side companion value and never enters the instruction
  format itself.
- `Predicator.compile_with_positions/1`: compiles a string expression to the
  instruction list `compile/1` returns plus that side table.
- An optional `:position` field on `Predicator.Errors.EvaluationError`,
  `Predicator.Errors.TypeMismatchError`, and
  `Predicator.Errors.UndefinedVariableError`, holding the `{line, column}` of
  the source token behind the failing instruction, or `nil` when no side table
  was available.
- `Predicator.Errors.put_position/2`: attaches a position to any error value,
  returning it unchanged when the position is `nil` or the value has no
  `:position` field.
- A `:positions` option on `Predicator.evaluate/3` and
  `Predicator.Evaluator.evaluate/3`, seeding the side table used to populate
  `:position` on runtime errors. Evaluating a string expression threads its own
  table automatically; an instruction-list caller who omits the option sees
  `position: nil` and no other change.

### Fixed

- `Predicator.decompile/2` and `Predicator.Compiler.to_string/2` no longer
  raise `FunctionClauseError` on ASTs containing dotted property access
  (`user.name`). `Predicator.Visitors.StringVisitor` was missing the
  `:property_access` clause; it now renders `object.property`, including
  chains (`user.profile.email`) and mixes with bracket access.
- Duration units now parse in source order: `3d8h` produces
  `[{3, "d"}, {8, "h"}]` instead of the reversed `[{8, "h"}, {3, "d"}]`, and
  multi-unit durations round-trip through the string visitor unchanged
- Comparing a `Date` against a `DateTime` now returns a boolean instead of
  silently evaluating to `:undefined`. The `Date` is coerced to `00:00:00`
  UTC of that day, matching the coercion mixed date subtraction already
  performs. This covers ordering, `==`/`!=`, and `in`/`contains`, and it
  makes every relative date (`3d ago`, `2w from now`, `next 1mo`, `last 1y`,
  all of which produce a `DateTime`) usable against a `Date` context value.
  Strict equality (`===`/`!==`) stays type-strict and never crosses the
  boundary.
- `Date` and `DateTime` ordering (`<`, `>`, `<=`, `>=`) is now chronological.
  The evaluator previously dispatched ordering comparisons to Erlang's `<`/`>`
  after confirming both sides were the same struct type, but Erlang orders
  structs by sorted map key, not by field meaning - `Date`'s keys sort
  `day, month, year`, so `#2026-08-14# < #2030-01-01#` compared day 14 against
  day 1 and returned `false`. `DateTime` was worse, sorting `microsecond`
  ahead of `month`. Ordering now goes through `Date.compare/2` and
  `DateTime.compare/2`, and `EQ`/`NE`/list-membership on `DateTime` now agree
  with `DateTime.compare/2` rather than structural equality, so two `DateTime`
  values denoting the same instant in different time zones compare equal.
- `Predicator.evaluate/3` now correctly reports `UndefinedVariableError` for
  any unbound root variable, not just a bare `variable_name` expression. The
  old check only matched a single-instruction `[["load", _]]` program, so an
  unbound variable inside a larger expression (`"missing > 5"`) silently
  returned `{:ok, :undefined}` instead of an error.
- Unbound-variable reporting now reflects the loads a run actually executed
  rather than the loads the compiled program contains. With short-circuiting
  `AND`/`OR`, a load inside a skipped branch is never read, but the previous
  check scanned the whole instruction list and could name it -
  `(false AND missing) OR unbound_b` reported `missing` instead of
  `unbound_b`.
- List literals with non-literal elements (`[x + 1, y]`) now compile and
  evaluate. Previously the compiler raised
  `"Non-literal list elements are not yet supported"`, the one place the
  errors-are-values convention was broken; errors from such expressions are now
  returned as `{:error, _}` values like every other failure.

### Deprecated

#### `=` as an equality operator

- Parsing an expression that uses `=` as an equality operator now emits a
  deprecation warning naming `==` as the replacement
- Behavior is otherwise unchanged: `=` still parses and still compiles to
  `["compare", "EQ"]`
- **Predicator 4.0 will make expression-position `=` a parse error.** Migrate
  to `==` before upgrading
- The warning is emitted once per parse and can be silenced with
  `config :predicator, deprecation_warnings: false`

```elixir
# Deprecated - warns, still works in 3.x
Predicator.evaluate("status = 'active'", context)

# Preferred
Predicator.evaluate("status == 'active'", context)
```

## [3.6.0] - 2026-08-04

### Added

#### Auto-vivifying path assignment for SCXML location expressions

- `Predicator.ContextLocation.put/3` writes a value at a resolved location path,
  creating missing intermediate maps and lists
- `Predicator.context_assign/4` resolves a location expression and writes in one call
- Integer path segments index lists and pad gaps with `:undefined`
- Assigning through an existing scalar returns a `:not_a_container` error rather than
  destroying data; negative indices return `:invalid_index`

#### Examples

```elixir
Predicator.context_assign(%{}, "user.profile.name", "Ada")
# {:ok, %{"user" => %{"profile" => %{"name" => "Ada"}}}}

Predicator.context_assign(%{"items" => [1]}, "items[2]", "x")
# {:ok, %{"items" => [1, :undefined, "x"]}}

Predicator.ContextLocation.put(%{}, ["data", "users", 0, "name"], "Ada")
# {:ok, %{"data" => %{"users" => [%{"name" => "Ada"}]}}}
```

### Changed

#### Replaces the hand-rolled quality gate with ex_quality

- `mix quality` is now [ex_quality](https://hex.pm/packages/ex_quality), configured
  in `.quality.exs`; the vendored `lib/mix/tasks/quality.ex` has been removed
- The gate runs format, compile (warnings as errors), Credo `--strict`, Dialyzer,
  an unused-dependency and security audit, and the full suite with the existing
  90% coverage minimum - stages run in parallel and report `file:line` findings
- `mix quality --profile loop` replaces `--skip-dialyzer`: it skips Dialyzer and
  coverage and runs only the tests covering changed code
- `mix quality --format json` emits a machine-readable report
- `mix quality.check` and `mix test --watch` are gone; the former no longer
  existed as a task and the latter's `mix_test_watch` dependency was undeclared

## [3.5.0] - 2025-09-09

### Added

#### Adds milliseconds support to duration system

- New 'ms' unit support in lexer, parser, and evaluator
- Duration.to_milliseconds/1 function for high-precision calculations
- Pattern matching guards for automatic precision selection
- Smart DateTime arithmetic (millisecond vs second precision)
- Comprehensive test coverage with 89 new tests
- Refactors evaluator to use Duration module functions (DRY)

#### Examples

- 500ms ago, 2s750ms from now
- #2024-01-15T10:30:00.000Z# + 1s500ms
- Automatic precision: ms > 0 triggers millisecond precision

## [3.4.0] - 2025-09-09

### Added

#### Durations and relative date/time arithmetic

- New duration literals and relative date expressions (e.g., `3d ago`, `2w from now`, `next 1mo`, `last 1y`)
- Date and DateTime arithmetic using durations (e.g., `#2024-01-10# + 5d`, `#2024-01-15T10:30:00Z# - 2h`)
- Grammar additions: `duration` and `relative_date` productions
- Full pipeline support (lexer, parser, compiler, evaluator, string visitor) with tests

#### Examples

```elixir
Predicator.evaluate("created_at > 3d ago", %{"created_at" => ~U[2024-01-20 00:00:00Z]})
Predicator.evaluate("due_at < 2w from now", %{"due_at" => Date.add(Date.utc_today(), 10)})
Predicator.evaluate("#2024-01-10# + 5d = #2024-01-15#", %{})
Predicator.evaluate("#2024-01-15T10:30:00Z# - 2h < #2024-01-15T10:30:00Z#", %{})
```

### Documentation

- Updated EBNF grammar in docs
- Added AGENTS.md with model-agnostic agent guidance; `CLAUDE.md` now references the same content

## [3.3.0] - 2025-08-31

### Added

- Depends on Jason library

## [3.2.0] - 2025-08-31

### Added

#### Strict Equality Operators

- **New Operators**: Added `===` (strict equality) and `!==` (strict inequality) operators
- **Type-Safe Comparisons**: Strict operators compare both value and type, unlike loose equality
- **Round-Trip Preservation**: Operators maintain their exact form during parse/decompile cycles
- **Complete Pipeline Support**: Full lexer, parser, evaluator, and visitor implementation
- **Comprehensive Testing**: 23 tests covering all aspects of strict equality functionality

#### Examples

```elixir
# Strict equality - same type and value required
Predicator.evaluate("5 === 5", %{})      # {:ok, true}
Predicator.evaluate("5 === '5'", %{})    # {:ok, false} - different types

# Strict inequality - true when type or value differs
Predicator.evaluate("5 !== '5'", %{})    # {:ok, true} - different types
Predicator.evaluate("1 !== true", %{})   # {:ok, true} - different types

# Operator distinction preserved
Predicator.parse("x = y") |> elem(1) |> Predicator.decompile()   # "x = y"
Predicator.parse("x == y") |> elem(1) |> Predicator.decompile()  # "x == y"  
Predicator.parse("x === y") |> elem(1) |> Predicator.decompile() # "x === y"
```

#### Technical Implementation

- **Lexer**: Added `:strict_equal` and `:strict_ne` token types with proper precedence
- **Parser**: Extended comparison grammar to support strict operators
- **Evaluator**: Added `STRICT_EQ` and `STRICT_NE` instruction handlers
- **StringVisitor**: Added decompilation support for round-trip accuracy
- **Type Safety**: Works with all data types including `:undefined` values

## [3.1.0] - 2025-08-30

### Added

#### JavaScript-Style Object Literals (Complete Implementation)

- **Object Literal Syntax**: Full support for JavaScript-style object notation with `{key: value}` syntax
- **Multiple Key Types**: Both identifier keys (`name: "John"`) and string keys (`"first name": "John"`)
- **Nested Objects**: Unlimited nesting depth for complex data structures
- **All Value Types**: Objects support all Predicator value types (strings, numbers, booleans, dates, lists, expressions)
- **Object Comparisons**: Full equality and inequality operations between objects
- **Integration**: Seamless compatibility with all existing features (functions, operators, property access)

#### Object Literal Examples

```elixir
# Basic object creation
Predicator.evaluate("{}", %{})                                    # {:ok, %{}}
Predicator.evaluate("{name: \"John\", age: 30}", %{})            # {:ok, %{"name" => "John", "age" => 30}}

# Variable references and expressions
Predicator.evaluate("{user: name, total: price + tax}", %{"name" => "Alice", "price" => 100, "tax" => 10})
# {:ok, %{"user" => "Alice", "total" => 110}}

# Nested objects
Predicator.evaluate("{user: {name: \"Bob\", role: \"admin\"}, active: true}", %{})
# {:ok, %{"user" => %{"name" => "Bob", "role" => "admin"}, "active" => true}}

# String keys for complex property names
Predicator.evaluate("{\"first name\": \"John\", \"last-name\": \"Doe\"}", %{})
# {:ok, %{"first name" => "John", "last-name" => "Doe"}}

# Object comparisons
Predicator.evaluate("{score: 85} == user_data", %{"user_data" => %{"score" => 85}})
# {:ok, true}
```

#### Complete Pipeline Support

- **Lexer**: Added `{`, `}`, `:` token recognition
- **Parser**: Full object grammar with proper precedence and error handling
- **Instructions**: Stack-based `object_new` and `object_set` instruction execution
- **Evaluator**: Efficient object construction and comparison operations
- **String Visitor**: Bidirectional transformation support (AST ↔ string representation)
- **Type System**: Enhanced type matching for object equality comparisons

#### Integration Features

- **Function Integration**: Objects work as function parameters and return values
- **Property Access**: Objects integrate with dot notation (`obj.property`) and bracket access (`obj["key"]`)
- **Boolean Logic**: Objects support all logical operations (AND, OR, NOT)
- **Arithmetic**: Object properties can contain arithmetic expressions and results
- **Date Support**: Objects can contain date/datetime literals and date function results
- **Custom Functions**: Objects work seamlessly with user-defined functions

#### Quality and Testing

- **886 Total Tests**: Comprehensive test coverage including edge cases and integration scenarios
- **91.8% Coverage**: High test coverage across all components
- **Parser Error Handling**: Robust error recovery for malformed object syntax
- **Performance Tested**: Validated with large objects and repeated evaluations
- **Production Ready**: Full quality assurance (formatting, linting, type checking)

## [3.0.0] - 2025-08-25

### Added

#### Location Expressions for SCXML Assignment Operations (Phase 2 Complete)

- **SCXML Location Expressions**: Complete implementation of location path resolution for SCXML `<assign>` operations
- **New API Function**: `Predicator.context_location/3` - resolves assignable location paths from expressions
- **Location Path Resolution**: Returns navigation paths like `["user", "name"]`, `["items", 0, "property"]` for SCXML assignment targets
- **Assignment Validation**: Distinguishes valid assignment targets (l-values) from computed expressions (r-values)
- **Core Module**: `Predicator.ContextLocation` with comprehensive location resolution logic and error handling
- **Structured Error Handling**: `Predicator.Errors.LocationError` with detailed error types and context information

#### Location Expression Examples

```elixir
# Valid assignment targets resolve to location paths
Predicator.context_location("user.profile.name", %{})                    # {:ok, ["user", "profile", "name"]}
Predicator.context_location("items[0]", %{})                             # {:ok, ["items", 0]}
Predicator.context_location("data['users'][index]['profile']", %{"index" => 2})  # {:ok, ["data", "users", 2, "profile"]}

# Invalid assignment targets return structured errors
Predicator.context_location("len(name)", %{})                            # {:error, %LocationError{type: :not_assignable}}
Predicator.context_location("42", %{})                                   # {:error, %LocationError{type: :not_assignable}}
Predicator.context_location("score + 1", %{})                            # {:error, %LocationError{type: :not_assignable}}
```

#### Error Types and Validation

- **`:not_assignable`**: Expression cannot be used as assignment target (literals, functions, computed expressions)
- **`:invalid_node`**: Unknown or unsupported AST node type encountered during resolution
- **`:undefined_variable`**: Variable referenced in bracket key is not defined in evaluation context
- **`:invalid_key`**: Bracket key is not a valid string or integer type
- **`:computed_key`**: Computed expressions cannot be used as assignment target keys

#### Assignable vs Non-Assignable Classifications

- **✅ Valid Assignment Targets**: Simple identifiers, property access, bracket access, mixed notation
  - `user`, `score`, `config.database.host`
  - `items[0]`, `user['profile']`, `data["settings"]`
  - `user.settings['theme']`, `data['users'][0].profile`
- **❌ Invalid Assignment Targets**: Literals, function calls, computed expressions
  - `42`, `"hello"`, `true`, `#2024-01-15#`
  - `len(name)`, `upper(role)`, `max(a, b)`
  - `score + 1`, `items[i + 1]`, `score > 85`

#### Technical Implementation

- **Full Location Resolution**: Recursive resolution of nested property access and bracket access
- **Mixed Notation Support**: Complete support for expressions like `user.settings['theme']` and `data['users'][0].name`
- **Variable Key Resolution**: Bracket keys can reference context variables for dynamic access patterns
- **Context Integration**: Uses existing evaluation context for variable key resolution
- **Comprehensive Testing**: 49 comprehensive tests covering all location resolution scenarios and error cases

#### Type Coercion and Float Support

- **Float Literal Support**: Extended lexer to parse floating-point numbers (e.g., `3.14`, `0.5`)
- **Float Token Type**: Added `:float` token type to distinguish from integers
- **Parser Float Handling**: Updated parser to handle float tokens and create appropriate AST nodes
- **Arithmetic with Floats**: All arithmetic operations now support both integers and floats
  - Addition, subtraction, multiplication work seamlessly with mixed numeric types
  - Division returns float when needed, integer when evenly divisible
  - Modulo remains integer-only as per mathematical conventions
- **String Concatenation with `+` Operator**: Implemented JavaScript-like type coercion
  - `"Hello" + "World"` → `"HelloWorld"` (string concatenation)
  - `"Count: " + 5` → `"Count: 5"` (string + number coercion)
  - `42 + " items"` → `"42 items"` (number + string coercion)
- **Type Coercion Rules**:
  - Number + Number → Numeric addition (supports mixed int/float)
  - String + String → String concatenation
  - String + Number → String concatenation (number converted to string)
  - Number + String → String concatenation (number converted to string)
- **Comparison Enhancements**: Numbers of different types (int/float) can be compared
- **Unary Minus for Floats**: Unary minus operator now works with floating-point numbers
- **Error Message Updates**: Updated error messages from "integer" to "number" where appropriate
- **Comprehensive Testing**: Added 28 new tests covering all type coercion scenarios

### Changed

#### Property Access Parsing Architecture Overhaul (Breaking Changes)

- **Complete Dot Notation Reimplementation**: Transformed from dotted identifiers to proper property access AST nodes
- **Lexer Breaking Change**: Dots removed from valid identifier characters, now parsed as separate tokens
- **Parser Grammar Enhancement**: Added property access grammar `postfix → primary ( "[" expression "]" | "." IDENTIFIER )*`
- **New AST Structure**: Expressions like `user.email` now parsed as `{:property_access, {:identifier, "user"}, "email"}`
- **Instruction Pipeline**: Evaluation generates separate `load` and `access` instructions instead of single `load` with dotted name
- **Mixed Notation Support**: Enables complex expressions like `user.settings['theme']` and `data['users'][0].profile`

### Breaking Changes

#### v3.0.0 - Property Access Parsing Overhaul

This is a **major breaking change** affecting how dot notation is parsed and evaluated:

**⚠️ Context Key Impact**: Context keys containing dots (e.g., `"user.email"`) will no longer match dot notation expressions (`user.email`). The expression `user.email` is now parsed as property access requiring nested structure `%{"user" => %{"email" => "..."}}`

**Migration Required**:

```elixir
# BEFORE (v2.2.0 and earlier) - WILL NO LONGER WORK
context = %{"user.email" => "john@example.com"}
Predicator.evaluate("user.email = 'john@example.com'", context)  # No longer matches

# AFTER (v3.0.0+) - Use proper nested structures
context = %{"user" => %{"email" => "john@example.com"}}
Predicator.evaluate("user.email = 'john@example.com'", context)  # Works correctly
```

**Technical Changes**:

- **Lexer**: Dots no longer valid in identifier characters, parsed as separate `:dot` tokens
- **Parser**: New property access AST nodes `{:property_access, left_node, property}`
- **Evaluator**: New `access` instruction handler, removed dotted identifier support from `load_from_context`
- **Instructions**: `user.email` generates `[["load", "user"], ["access", "email"]]` instead of `[["load", "user.email"]]`

**Benefits**:

- Enables mixed notation: `user.settings['theme']`, `data['users'][0].name`
- Supports SCXML location expressions for assignment operations
- Proper property access semantics for complex data structures
- Foundation for advanced SCXML datamodel integration

## [2.2.0] - 2025-08-24

### Added

#### Bracket Access and Property Access Enhancement

- **Complete Bracket Notation Support**: Implemented full bracket access functionality (`obj['key']`, `arr[0]`, `obj[variable]`)
- **Parser Extensions**: Added postfix parsing for bracket access with recursive chaining support
- **Grammar Enhancement**: Updated grammar with postfix operations: `unary → postfix`, `postfix → primary ( "[" expression "]" )*`
- **New AST Node Type**: Added `{:bracket_access, object, key}` AST node for bracket access expressions
- **Evaluator Support**: Implemented `["bracket_access"]` instruction with comprehensive evaluation logic
- **Mixed Access Patterns**: Full support for chained access like `data['users'][0]['name']`
- **Array Indexing**: Complete array access with bounds checking (`items[0]`, `scores[index]`)
- **Dynamic Key Access**: Support for variable and expression-based keys (`obj[key]`, `items[i + 1]`)
- **Type Safety**: Comprehensive error handling for invalid key types with structured error messages
- **String Visitor Support**: Added round-trip string conversion for bracket access expressions
- **Comprehensive Testing**: Added 12 new parser tests covering all bracket access scenarios

#### Error Handling Architecture Refactoring

- **Modular Error Structure**: Refactored monolithic error handling into individual error modules under `lib/predicator/errors/`
- **Shared Error Utilities**: Created `Predicator.Errors` module with common utility functions for consistent error formatting
- **Individual Error Modules**: Split error handling into focused modules:
  - `Predicator.Errors.TypeMismatchError` - Type validation and mismatch errors
  - `Predicator.Errors.EvaluationError` - Runtime evaluation errors (division by zero, insufficient operands)
  - `Predicator.Errors.UndefinedVariableError` - Variable access errors
  - `Predicator.Errors.ParseError` - Expression parsing and syntax errors
- **Consistent Error Messages**: Unified error message formatting across all error types
- **Code Quality Improvements**: Resolved all credo issues with proper module aliasing and organization

## [2.1.0] - 2025-08-24

### Added

#### Arithmetic and Unary Operations (Complete Implementation)

- **Full Arithmetic Support**: Complete parsing and evaluation pipeline for arithmetic expressions
  - **Binary operations**: `+` (addition), `-` (subtraction), `*` (multiplication), `/` (division), `%` (modulo)
  - **Unary operations**: `-` (unary minus), `!` (unary bang/logical NOT)
- **Proper Precedence**: Mathematical precedence handling (unary → multiplication → addition → equality → comparison)
- **Instruction Execution**: Stack-based evaluator with 7 new instruction handlers
- **Error Handling**: Division by zero protection, type checking, comprehensive error messages
- **Pattern Matching**: Idiomatic Elixir implementation using pattern matching for clean code

## [2.0.0] - 2025-08-21

### Changed

#### Custom Function Architecture Overhaul

- **Breaking Change**: Removed global function registry system in favor of evaluation-time function parameters
- **New API**: Custom functions now passed via `functions:` option in `Predicator.evaluate/3` calls
- **Function Format**: Custom functions use `%{name => {arity, function}}` format where function takes `[args], context` and returns `{:ok, result}` or `{:error, message}`
- **Thread Safety**: Eliminated global state for improved concurrency and thread safety
- **Function Merging**: SystemFunctions always available with custom functions merged in, allowing overrides
- **Simplified Startup**: No application-level function registry initialization required

#### Examples

```elixir
# Old registry-based approach (removed)
Predicator.register_function("double", 1, fn [n], _context -> {:ok, n * 2} end)
Predicator.evaluate("double(21)", %{})

# New evaluation-time approach
custom_functions = %{"double" => {1, fn [n], _context -> {:ok, n * 2} end}}
Predicator.evaluate("double(21)", %{}, functions: custom_functions)

# Custom functions can override built-ins
custom_len = %{"len" => {1, fn [_], _context -> {:ok, "custom_result"} end}}
Predicator.evaluate("len('anything')", %{}, functions: custom_len)  # {:ok, "custom_result"}
```

#### Removed APIs

- `Predicator.register_function/3` - Use `functions:` option instead
- `Predicator.clear_custom_functions/0` - No longer needed
- `Predicator.list_custom_functions/0` - No longer needed
- `Predicator.Functions.Registry` module - Entire registry system removed

### Breaking Changes

#### v2.0.0 - Custom Function Architecture Overhaul

- **Removed**: Global function registry system (`Predicator.Functions.Registry` module)
- **Removed**: `Predicator.register_function/3`, `Predicator.clear_custom_functions/0`, `Predicator.list_custom_functions/0`
- **Changed**: Custom functions now passed via `functions:` option in `evaluate/3` calls instead of global registration
- **Benefit**: Thread-safe, no global state, per-evaluation function scoping
- **Migration**: Replace registry calls with function maps passed to `evaluate/3`

## [1.1.0] - 2025-08-20

### Added

#### Nested Data Structure Access

- **Dot Notation Support**: Access deeply nested data structures using dot notation syntax
- **Enhanced Lexer**: Extended identifier tokenization to include dots (`.`) as valid characters
- **Recursive Context Loading**: Added `load_nested_value/2` function for traversing nested maps
- **Mixed Key Type Support**: Works seamlessly with string keys, atom keys, or mixed key types
- **Graceful Error Handling**: Returns `:undefined` for missing paths or non-map intermediate values
- **Unlimited Nesting Depth**: Support for arbitrarily deep nested structures

#### Single Quote String Support

- **Dual Quote Types**: Added support for single-quoted strings (`'hello'`) alongside double-quoted strings (`"hello"`)
- **Quote Type Preservation**: Round-trip parsing and decompilation preserves original quote type
- **Enhanced Lexer**: Extended string tokenization to handle both quote types with proper escaping
- **AST Enhancement**: New `{:string_literal, value, quote_type}` AST node for quote-aware string handling
- **Escape Sequences**: Full escape sequence support in both quote types (`\'`, `\"`, `\n`, `\t`, etc.)

### Breaking Changes

#### v1.1.0 - Nested Access Parsing

- **Changed**: Variables containing dots (e.g., `"user.email"`) now parsed as nested access paths
- **Impact**: Context keys like `"user.profile.name"` will no longer match identifier `user.profile.name`
- **Solution**: Use proper nested data structures instead of flat keys with dots

## [1.0.1] - 2025-08-20

### Documentation

- Fixes main page for Hex docs

## [1.0.0] - 2025-08-19

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

### Breaking Changes

#### ⚠️ COMPLETE LIBRARY REWRITE ⚠️

Version 1.0.0 is a **complete rewrite** of the Predicator library with entirely new:

- API design and function signatures
- Expression syntax and grammar
- Internal architecture and data structures
- Feature set and capabilities

#### Migration Guide

**Migration from versions < 1.0.0 has NOT been tested and is NOT guaranteed to work.**

If you are upgrading from a pre-1.0.0 version:

1. **Treat this as a new library adoption**, not an upgrade
2. **Review all documentation** - APIs have completely changed
3. **Test thoroughly** in development environments
4. **Expect to rewrite** all integration code
5. **Plan for significant refactoring** of existing expressions

Future 1.x.x versions will maintain backwards compatibility and include proper migration guides.

---

For detailed information about upcoming features and development roadmap, see the project README.
