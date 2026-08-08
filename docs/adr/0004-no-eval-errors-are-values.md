# ADR-0004: No eval, ever; errors are values

Status: proposed (2026-08-07)

## Context

Predicator's first sentence in `README.md` is a security claim: "there is no
`eval`, no `Code.eval_string`, and no dynamic code execution anywhere in the
pipeline, so untrusted input can never become code." `docs/architecture.md`
repeats it as three bullets under "Key Design Decisions" (Security First), and
`CLAUDE.md` restates it in "What this project is". It is the premise the whole
library is built on, and until now it has never been recorded as a decision -
only asserted as a property. ADR-0001 spends its Context arguing which
*execution model* to keep and never states why the library compiles anything at
all rather than walking a tree in the host language and calling host functions
directly. That unstated premise is this ADR.

**The threat model.** A predicate is authored by an end user - a business
analyst writing a rule in a form field, an SCXML document author writing a
`cond` guard - then stored, then evaluated later, in a host application process
that the author does not own and cannot see. The three parties are distinct:
whoever wrote the string, whoever stored it, and whoever runs it. Predicator's
job is to make the third party's process safe against the first party, with no
review step in between and no assumption that the string was written in good
faith.

That threat model closes every cheap implementation of an expression language
in Elixir:

- **`Code.eval_string/3`.** The obvious one. It gives the predicate author the
  host's full runtime: `System.cmd/3`, `File.rm_rf/1`, the process dictionary,
  every module loaded in the VM. There is no subset of Elixir it can be
  restricted to.
- **`String.to_atom/1` on user tokens.** Atoms are never garbage collected and
  the atom table is a fixed-size resource, so a variable or function name taken
  from user input and interned is a remote denial-of-service against the host
  node - no code execution required.
- **A tree-walker that dispatches on user-supplied names.** `apply(mod, fun,
  args)` where `fun` came out of the parse, or a function registry keyed by
  whatever module the host has loaded, hands the choice of *which host code
  runs* to the predicate author. It is `Code.eval_string` with extra steps and
  a smaller vocabulary; the vocabulary is not the security boundary.
- **Raising on bad input.** Less obviously in the same family, and argued below.

**What this costs.** Every language feature has to be built rather than
borrowed. Elixir's own tokenizer, parser, operator precedence, arithmetic
promotion, comparison semantics, and function dispatch are all sitting right
there and none of them are usable, so predicator carries `lib/predicator/
lexer.ex`, `lib/predicator/parser.ex`, `lib/predicator/compiler.ex`, and
`lib/predicator/evaluator.ex` to re-earn a fraction of them, plus a function
registry in `lib/predicator/functions/` to re-earn a standard library one
function at a time. Every new operator, literal type, or builtin is work that a
host-language `eval` would have provided free. That bill is paid on every
feature, forever, and it is the intended trade.

## Decision

**User-authored input never becomes code.** No `eval`, no `Code.eval_string`,
no `String.to_atom` on anything derived from a predicate, no `apply/3` on a
user-supplied name, no runtime code generation, anywhere in the pipeline. A
predicate is data at every stage: source text becomes tokens, tokens become an
AST, the AST becomes a flat instruction list, and the instruction list is
*interpreted* by a stack VM that dispatches on a closed set of opcodes it
defines itself. The compile-to-instructions architecture exists **because** of
this constraint. ADR-0001 chose to keep it over a tree-walker on grounds of
serializable compiled artifacts; that argument is downstream of this one, which
would have closed a host-dispatching tree-walker regardless of how the artifact
question came out.

**Errors are values, as a corollary of the same decision.** Every leaf returns
`{:ok, result} | {:error, struct}` and does not raise. This is not a separate
style preference filed next to the security decision - it is the same decision
applied to failure. A raise at a leaf hands control of the host's behavior to
whoever wrote the predicate: the author picks, by choosing input, which
exception the host process sees and where its stack unwinds to. That is the
same class of failure as an eval, differing only in how much of the host is
reachable. An expression engine whose contract is "safe against untrusted
input" cannot have a second contract that says "unless the input is shaped like
*this*, in which case your supervisor finds out".

Three things are deliberately *not* covered by the no-raise half:

- **Bang variants.** `Predicator.evaluate!/3`, `Predicator.compile!/1`, and
  `Predicator.Evaluator.evaluate!/3` raise by construction. They are the
  caller's explicit request to convert a value into an exception, taken by the
  host, at a call site the host wrote.
- **Host-API misuse.** `Predicator.Context.new/2` raises `ArgumentError` on an
  invalid `on_unbound` option (`lib/predicator/context.ex`). The offending
  value came from the host's own code, not from a predicate; it is a
  programming error in the caller, and the untrusted-input rule does not
  reach it.
- **Custom functions supplied by the host.** A host-registered function that
  raises is caught and converted (`lib/predicator/evaluator.ex`, in
  `call_function/4`), which is the rule being enforced across an API boundary
  rather than an exception to it.

### This decision does not move the instruction set

**No ISA change. No opcode is added, removed, renamed, or given different
semantics, and no ISA version is bumped.** This ADR records a premise the
existing instruction set already embodies: the opcodes are a closed set defined
by `docs/isa.md`, and executing an instruction list has never involved
interpreting any part of it as host code. Per ADR-0003 an ISA change owes a
version, a `docs/isa.md` entry, a corpus tier, and a migration note if stored
artifacts are affected; none of those are owed here, because nothing about a
stored instruction list changes. The one thing this ADR *does* have a claim on
in ISA territory is px-pp7, which is already scoped as its own spec change at
its own version (see Consequences).

## Consequences

- **The pipeline is not an implementation detail, it is the mechanism.**
  Lexer, parser, compiler, and stack VM (`docs/architecture.md`, "Architecture
  Overview") exist to keep user text on the data side of the line. Replacing
  any stage with something that reaches into the host language means
  superseding this ADR, not optimizing under it. ADR-0001 and ADR-0003 both
  keep the tree-walker closed for their own reasons; this ADR closes the
  specific variant that dispatches on user-supplied names, and that closure
  does not depend on either of theirs surviving.
- **The function registry is closed by construction.** Builtins come from
  `lib/predicator/functions/` - `SystemFunctions`, `DateFunctions`,
  `JSONFunctions`, `MathFunctions` - merged into a plain map of name to
  `{arity, fun}`, with `opts[:functions]` merged last by
  `Evaluator.merge_functions/1`. Dispatch is a `Map.get/2` on that map, and an
  unrecognized name returns `{:error, "Unknown function: ..."}` rather than
  reaching for a module. A host extends the vocabulary by passing functions it
  wrote; a predicate author can only select from what the host passed.
- **Atom creation from user text is confined to one guarded site.**
  `lib/predicator/evaluator.ex` uses `String.to_existing_atom/1` exactly once,
  in `resolve_atom_key/2`, to let a variable name find an atom-keyed context
  entry - and it rescues `ArgumentError` into `:unbound`, so a name with no
  existing atom is an ordinary unbound variable rather than an error or a new
  atom. There is no `String.to_atom/1` in `lib/`. Any future need to turn
  predicate text into an atom inherits this shape.
- **The error struct family is the errors-are-values half made concrete.**
  `Predicator.Errors.{EvaluationError, TypeMismatchError,
  UndefinedVariableError, ParseError, LocationError}` under
  `lib/predicator/errors/`, with
  `Predicator.Errors` carrying the shared formatting and `put_position/2`. The
  public surface is `@spec evaluate(...) :: {:ok, Types.value()} | {:error,
  struct()}` in `lib/predicator.ex`, and a new failure mode adds a struct or a
  reason to that family rather than a raise.
- **px-pp7 is a live violation of this ADR, not a matter of taste.**
  `["object_set", key]` against a non-map returns a bare binary error
  (`lib/predicator/evaluator.ex:1301`), and
  `advance_instruction_pointer/1` has clauses only for `{:ok, t()}` and
  `{:error, struct}`, so the bare tuple falls through and raises
  `FunctionClauseError`. It is unreachable from compiled source - the compiler
  always emits `object_new` before `object_set` - but reachable from a
  hand-built instruction list, which is exactly what a sibling implementer
  produces. This ADR is the standard px-pp7 is measured against: the fix is
  owed because the rule says so, not because the crash is inconvenient.
  px-pp7 already carries the spec work (a normative error row in `docs/isa.md`
  section 5, the conformance carve-out removed) and is tagged `release:4.0.0`;
  that is where the ISA-facing part of this decision gets discharged.
- **"No eval" becomes citable instead of re-argued.** The README paragraph,
  the `docs/architecture.md` bullets, and the `CLAUDE.md` description are
  assertions of a property; they can now cite ADR-0004 as the record of the
  decision, the way ADR-0002 and ADR-0003 are cited today.
- **The build-it-yourself bill is accepted in advance.** A future request of
  the form "just let the host evaluate this bit" - a lambda literal, a
  host-module call, a regex compiled from a predicate, a template that
  interpolates into code - is refused by this ADR without needing a fresh
  argument each time. Granting one means superseding this ADR, not adding an
  option beside it.

### Open questions

- `docs/architecture.md` ("Key Design Decisions", Error Handling) still
  describes the error contract as `{:ok, result} | {:error, message, line,
  col}`, which is the pre-struct shape; the actual public surface is
  `{:ok, value} | {:error, struct}`. Correcting that line is documentation
  drift outside this ADR's scope and is left for a follow-up bead.
