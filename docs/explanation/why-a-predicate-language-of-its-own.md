# Why a predicate language of its own

A library lends copies of books to patrons, and the rules around a loan change
more often than the application that enforces them: how many times a loan may
be renewed, when a patron with unpaid fines stops borrowing, how long an
overdue copy waits before it is declared lost. The people who know those rules
are circulation staff, not the developers. This page is about why Predicator
answers that situation with a small language of its own, which alternatives it
turned down, and what the choice costs.

## Who writes a rule, and who executes it

A rule such as `status == 'on_loan' AND renewals < 3 AND NOT on_hold` passes
through three hands. A member of staff writes it in a settings form. The
application stores it. Later, every time a patron asks to renew, a process the
author never sees evaluates it against that loan. Nobody reviews the text
between the first step and the last, and nothing assumes it was written in
good faith: a typo, a misunderstanding or a hostile string arrives at the
third step exactly as it left the first.

That is the threat model the whole package is shaped by. The process that
evaluates a rule has to stay safe against whoever wrote it, whatever they
wrote. Each alternative below is measured against that one requirement.

## The alternatives

### Every rule written in code

The safest answer is to keep rules out of the data altogether: each renewal
policy is a function a developer writes, reviews and releases. Nothing a
member of staff types can reach the process, because they type nothing.

The cost is that every policy change waits for a release, and the person who
understands the policy cannot make the change. Rules that differ by branch, by
patron type or by season multiply into code paths. For an application whose
users or configuration genuinely decide when something may happen, this
answer moves the problem rather than solving it.

### Evaluating the text as Elixir

The cheapest way to let staff write rules is to evaluate what they type with
`Code.eval_string/3`. It works on the first afternoon, and it hands the author
the host's whole runtime: shell commands, the file system, every module loaded
in the node. There is no subset of Elixir it can be restricted to, so a rule
field becomes a way to execute anything at all.

### A tree walker that calls host functions by name

A middle road parses the text into a tree and walks it, calling a host
function whenever the tree names one. If the name chooses the function -
through `apply/3` on whatever the parse produced, or a lookup across every
loaded module - the author still chooses which host code executes. The
vocabulary is smaller than with `eval`, but the vocabulary was never the
boundary. A quieter version of the same mistake is turning names from the text
into atoms: atoms are never garbage collected and the atom table is a fixed
size, so a stream of invented variable names can bring down the node without
executing any code.

### A rule format of the application's own

Some applications avoid text entirely: a rule is a JSON structure of field,
operator and value rows, drawn by a form and compiled to an expression only
when it is evaluated. For a form that is the right shape, but as the rule's
stored form it means two representations of one rule, two serializations, two
migration stories when a field is added, and a translator that is a second
implementation of the language's precedence rules. Predicator keeps one
language and offers the form-shaped part of it as a value computed from the
parsed tree instead; [the simple subset](../guides/simple-subset.md) describes
it, and
[the decision record](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0017-structured-authoring-is-a-subset-value.md)
weighs the routes it turned down, including a restricted parser mode.

## What a language of its own buys

**The rule stays data at every stage.** Source text becomes tokens, tokens
become a tree, the tree becomes a flat list of instructions, and a small stack
machine interprets that list over a closed set of operations it defines
itself. No stage hands any part of the text to the host language. The pipeline
is not an implementation detail wrapped around the safety property; it is the
mechanism that provides it.

**Functions come from the host, by its choice.** A rule can call a function,
but only one the application made available: the builtins, plus
whatever functions the host passes in. A name the rule invents comes back as an "Unknown function"
error rather than reaching for a module, and a host function that raises is
caught and turned into an error value. The author of a rule selects from what
the host offered and nothing else; [custom functions](../guides/custom-functions.md)
covers how a host offers more.

**Failures are values.** A rule that names a value the loan does not carry,
or calls a function the host never offered, returns an error value that names
the problem; it does not raise. The reason is the same threat model applied to
failure: if bad input raised, the author of a rule would choose, by choosing
input, which exception the host process sees and how far its stack unwinds.
The bang variants (`evaluate!/3`, `compile!/1`) do raise, because there the
host asked for an exception at a call site it wrote.

**A compiled rule is something you can keep.** The instruction list is a plain
term. It can sit in a process's state, in ETS or in a database column, and be
evaluated against each returned copy without compiling the text again. It
carries the version of the instruction set it was compiled for, so a rule
stored under an earlier release is either executed as written or refused with
a reason, never silently misread; [the embedding guide](../guides/embedding.md)
covers that check.

**The same rule means the same thing in another language.** Because the
instruction list, not the source text, is the contract, an implementation in
another language can execute what this one compiles and prove it against a
shared conformance corpus. [The architecture page](../architecture.md#cross-language-siblings)
describes how those implementations adopt each version of the instruction set.

## Why compile at all

Once the language is its own, a tree walker over the parsed rule would be the
simpler interpreter, and it would get one thing free that the stack machine
had to earn: `AND` and `OR` that stop at the first decisive side, so
`renewals < 3 AND NOT on_hold` never looks at `on_hold` once the renewals are
used up. Predicator compiles anyway, and added jump instructions to make the
operators short-circuit, because the compiled list is what makes a rule
storable and what other languages share. A tree is tied to this
implementation's data structures; a list of instructions with a version
number is an artifact.
[The decision record](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0001-keep-the-stack-vm-revise-the-instruction-set.md)
sets out that trade in full.

## What it costs

Every feature of the language is built rather than borrowed. Elixir already
has a tokenizer, a parser, operator precedence, arithmetic, comparison rules
and a standard library, and none of them can be used: Predicator carries its
own lexer, parser, compiler and evaluator to re-earn a fraction of them, and
its own function set to re-earn a standard library one function at a time.
Every new operator or literal is work that `eval` would have supplied for
nothing, and that bill is paid on every feature.

The same rule refuses a whole class of convenient requests: a lambda inside a
rule, a call into an arbitrary host module, a pattern compiled from rule text,
a template that interpolates into code. Each would be easy to add and each
would reopen the question the package exists to close. A condition that needs
more than the language offers belongs in a host function the application
writes and reviews, which the rule then calls by name.

It is also one more language for the people who write rules to learn. The
grammar leans on what they already know - comparisons, `AND`, `OR`, `NOT`,
`in`, dates and durations - and departs from it deliberately in places, most
visibly in reading `=` as assignment rather than equality;
[that decision record](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0002-the-equals-grammar-break.md)
explains the break.

## Related reading

- [The language reference](../reference/language.md) lists every operator,
  function, data type and error shape the language has.
- [The architecture page](../architecture.md) maps the compilation pipeline
  component by component.
- [The decision record on no `eval`](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0004-no-eval-errors-are-values.md)
  states the threat model this page starts from, and the boundaries of the
  errors-as-values rule.
