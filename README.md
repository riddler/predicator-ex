# Predicator

[![CI](https://github.com/riddler/predicator-ex/actions/workflows/ci.yml/badge.svg)](https://github.com/riddler/predicator-ex/actions/workflows/ci.yml)
[![Hex.pm Version](https://img.shields.io/hexpm/v/predicator.svg)](https://hex.pm/packages/predicator)
[![Hex Downloads](https://img.shields.io/hexpm/dt/predicator.svg)](https://hex.pm/packages/predicator)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/predicator/)
[![codecov](https://codecov.io/gh/riddler/predicator-ex/branch/main/graph/badge.svg)](https://codecov.io/gh/riddler/predicator-ex)
[![License](https://img.shields.io/hexpm/l/predicator.svg)](https://github.com/riddler/predicator-ex/blob/main/LICENSE)

Predicator is a secure, non-evaluative condition engine for end-user boolean
predicates. A user-authored expression like
`amount <= budget_remaining AND card_active` compiles
to a flat instruction list run by a small stack VM - there is no `eval`, no
`Code.eval_string`, and no dynamic code execution anywhere in the pipeline, so
untrusted input can never become code.

The language covers comparisons, arithmetic, logical and membership operators
(`in`, `contains`), dates and durations, lists and objects, type casts
(`amount::integer`), [nested data access](docs/guides/nested-data-access.md),
and both [builtin and custom functions](docs/reference/language.md). Beyond
single predicates it also runs short *programs* - `;`-separated statements with
assignment and `if`/`else` blocks - through
[`Predicator.execute/3`](#running-a-short-program).

## Installation

Add `predicator` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:predicator, "~> 9.0"}
  ]
end
```

Predicator requires Elixir 1.18 or later and has no runtime dependencies.

## Quick Start

Authorizing a card transaction against the account's remaining budget:

```elixir
iex> Predicator.evaluate!("amount <= budget_remaining AND card_active", %{"amount" => 120, "budget_remaining" => 500, "card_active" => true})
true

iex> Predicator.evaluate("amount <= budget_remaining", %{"amount" => 120, "budget_remaining" => 500})
{:ok, true}
```

Routing a visitor through a signup wizard that is running an A/B test:

```elixir
iex> Predicator.evaluate!("step == 'payment' AND variant == 'B'", %{"step" => "payment", "variant" => "B"})
true
```

## A worked example: an authorization rule

The shape most applications want is **compile once, evaluate many**. An
authorization rule is authored by a human - a risk analyst, not a developer -
stored as text, compiled when it is loaded, and then run against every
transaction that arrives.

Compile the rule once, when the account's ruleset is loaded:

```elixir
iex> rule = "amount <= budget_remaining AND card_active AND amount <= 2000"
iex> {:ok, authorize} = Predicator.compile(rule)
iex> hd(authorize)
["load", "amount"]
```

`authorize` is a plain list of instructions - ordinary Erlang term data, so it
can sit in ETS, in a GenServer's state, or in a database column. Run it against
each transaction:

```elixir
iex> {:ok, authorize} = Predicator.compile("amount <= budget_remaining AND card_active AND amount <= 2000")
iex> Predicator.evaluate(authorize, %{"amount" => 120, "budget_remaining" => 500, "card_active" => true})
{:ok, true}
iex> Predicator.evaluate(authorize, %{"amount" => 940, "budget_remaining" => 500, "card_active" => true})
{:ok, false}
```

A transaction missing a field the rule names is an **error value, not an
exception** - the whole library returns `{:ok, _} | {:error, _}` rather than
raising at a leaf, so a malformed payload cannot take the caller down:

```elixir
iex> {:error, error} = Predicator.evaluate("amount <= budget_remaining", %{"amount" => 120})
iex> error.variable
"budget_remaining"
iex> error.position
{1, 11}
```

Because the rule text came from a human, the position is worth keeping: compile
with `compile_with_positions/1` and a runtime error can be pointed at the
offending span of the source the analyst actually typed.

```elixir
iex> {:ok, compiled} = Predicator.compile_with_positions("amount > budget_remaining")
iex> Predicator.evaluate(compiled, %{"amount" => 940, "budget_remaining" => 500})
{:ok, true}
```

`compile_with_positions/1` and `compile_with_spans/1` return a
`%Predicator.Compiled{}` carrying the instructions and their source-location
table as one value, so runtime errors keep their positions without the caller
re-attaching anything.

Persist `compiled.instructions`, not the struct - the instruction list is the
portable artifact; the table holds offsets into the source string and is
meaningless without it. Want positions back after a round trip? Persist the
source too and recompile with `compile_with_positions/1` on load, rather than
storing the table - a table compiled from one source silently mismatches a
different source's instructions. See
[Embedding compiled programs](docs/guides/embedding.md) for the full
store/check/run lifecycle, including what to do when a stored artifact
predates a retired opcode.

### Running a short program

`evaluate/3` answers a single question. `execute/3` runs a `;`-separated
*program* - assignments and `if`/`else` blocks - and returns the resulting
context, which is how a settlement decision gets recorded rather than merely
computed:

```elixir
iex> program = "if amount > budget_remaining { decision = 'decline' } else { decision = 'approve' }"
iex> {:ok, context} = Predicator.execute(program, %{"amount" => 940, "budget_remaining" => 500})
iex> context.data["decision"]
"decline"
```

`execute_value/3` returns the last expression statement's value alongside that
context:

```elixir
iex> {:ok, approved?, context} = Predicator.execute_value("settled_amount = amount; settled_amount <= budget_remaining", %{"amount" => 120, "budget_remaining" => 500})
iex> approved?
true
iex> context.data["settled_amount"]
120
```

A program writes into the context, so a host that exposes its own state there
will want `:protected_roots` - the roots a program may not overwrite:

```elixir
iex> {:error, error, _context} = Predicator.execute("card_active = true", %{}, protected_roots: ["card_active"])
iex> error.reason
"protected_root"
```

Statements, assignment, and blocks are covered in full by the
[language reference](docs/reference/language.md). Note that `=` is assignment
only, never equality - see "Migrating from `=`" below.

## Embedding Predicator in a host application

The pattern most host applications need: a function provider that reads state
from the evaluation context's `host` slot, and a caller that swaps that slot
in O(1) as its own state changes. This mirrors how a state machine library
wires an SCXML `In(stateId)` guard into a running machine - the guard reads
current state through `context.host` rather than the caller re-threading it
as an ordinary predicate argument.

Define a provider module implementing `Predicator.FunctionProvider`, whose
callback reads `context.host`:

```elixir
defmodule MyApp.StateFunctions do
  @behaviour Predicator.FunctionProvider

  @impl Predicator.FunctionProvider
  def functions, do: %{"In" => {1, :call_in}}

  def call_in([state_id], context), do: {:ok, context.host.current_state == state_id}
end
```

Build the context once, wiring the provider in with `providers:`, and store
it in the embedder's own struct:

```elixir
defmodule MyApp.Machine do
  defstruct [:context]

  def new(initial_state) do
    context =
      Predicator.Context.new(%{},
        providers: [MyApp.StateFunctions],
        host: %{current_state: initial_state}
      )

    %__MODULE__{context: context}
  end

  def transition(%__MODULE__{context: context} = machine, new_state) do
    %{machine | context: Predicator.Context.put_host(context, %{current_state: new_state})}
  end
end
```

Each state change calls `put_host/2` - a single `Map.put/3`, not a context
rebuild - leaving `data` and the resolved function dispatch map untouched:

```elixir
iex> context = Predicator.Context.new(%{}, host: %{current_state: :idle})
iex> context = Predicator.Context.put_host(context, %{current_state: :running})
iex> context.host
%{current_state: :running}
```

A context built only from `providers:` is the form worth persisting or
handing to another process: a provider is a module atom and `host` is plain
data, so the whole context is ordinary Erlang term data. An inline
`functions:` closure works the same way at evaluation time but cannot be
serialized - `:erlang.term_to_binary/1` has no way to hand a `fun` back to a
different run. See [Custom functions](docs/guides/custom-functions.md) for
the full provider API and the host slot, and [Embedding compiled
programs](docs/guides/embedding.md#persisting-a-context-alongside-a-program)
for storing a context alongside a compiled program.

## Documentation

- [Language reference](docs/reference/language.md) - operators, builtin
  functions, data types, statements and `if`/`else` blocks, and error shapes
- [ISA reference](docs/isa.md) - the instruction set specification: opcodes,
  stack effects, error semantics, and versioning
- [Nested data access](docs/guides/nested-data-access.md) - dot and bracket
  notation over deep contexts
- [Custom functions](docs/guides/custom-functions.md) - extending the function
  set per evaluation
- [Location expressions](docs/guides/location-expressions.md) - SCXML
  assignment targets and writing into a context
- [Embedding compiled programs](docs/guides/embedding.md) - storing an
  instruction list and checking its ISA version before running it
- [Porting Predicator](docs/guides/porting.md) - implementing the instruction
  set in another language and verifying it against the conformance corpus
- [Architecture and language reference](docs/architecture.md) - the grammar
  with precedence, the compilation pipeline, and the component map
- [Architecture decision records](https://github.com/riddler/predicator-ex/blob/main/docs/adr/README.md) - the reasoning behind
  the design

## Migrating from `=`

`=` is no longer an equality operator. It is assignment, valid only at the
start of a statement (`Predicator.parse_program/2`) and only with an
assignable left side; a bare `=` in expression position - through
`Predicator.parse/2` or `Predicator.evaluate/3` - is a parse error naming `==`
as the fix, never a silent reinterpretation. `==` and `===` are the only
equality operators. See
[ADR-0002](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0002-the-equals-grammar-break.md) for the reasoning.

## Cross-Language Siblings

Predicator's Elixir implementation is the reference implementation of the
instruction set (the ISA), which is versioned. Ruby and JavaScript siblings,
in the [riddler/predicator](https://github.com/riddler/predicator) monorepo,
adopt each ISA version on their own schedule; a sibling running behind the
current version is an expected, documented state, not a defect. See
[ADR-0003](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0003-the-elixir-implementation-leads-the-isa.md) for the
reasoning and [docs/architecture.md](docs/architecture.md) for what each
sibling currently supports. [docs/isa.md](docs/isa.md) is the specification a
sibling implements against, and [conformance/](https://github.com/riddler/predicator-ex/blob/main/conformance/README.md) is how a
sibling verifies a claim of support against it: a checked-in, language-neutral
JSON corpus, tiered so a v1-only implementation runs a smaller, complete slice
rather than skipping its way through the whole thing. This is the
versioned-contract framing ADR-0003 asks for - a sibling behind the current
ISA version is expected and documented, not a parity deficit to apologize for.
If you are that implementer, [Porting Predicator](docs/guides/porting.md)
walks the path from picking a version to recording a conformance claim.

## Development

See `CLAUDE.md` for the contributor workflow and
[docs/contributing.md](docs/contributing.md) for the quality-check commands
and the checklists for adding operators and data types.

## License

MIT - see [LICENSE](LICENSE).
