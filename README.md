# Predicator

[![CI](https://github.com/riddler/predicator-ex/actions/workflows/ci.yml/badge.svg)](https://github.com/riddler/predicator-ex/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/riddler/predicator-ex/branch/main/graph/badge.svg)](https://codecov.io/gh/riddler/predicator-ex)
[![Hex.pm Version](https://img.shields.io/hexpm/v/predicator.svg)](https://hex.pm/packages/predicator)
[![Hex Downloads](https://img.shields.io/hexpm/dt/predicator.svg)](https://hex.pm/packages/predicator)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/predicator/)

Predicator is a secure, non-evaluative condition engine for end-user boolean
predicates. A user-authored expression like `score > 85 AND active` compiles
to a flat instruction list run by a small stack VM - there is no `eval`, no
`Code.eval_string`, and no dynamic code execution anywhere in the pipeline, so
untrusted input can never become code.

The language covers comparisons, arithmetic, logical operators, dates and
durations, lists and objects, [nested data access](docs/guides/nested-data-access.md),
and both [builtin and custom functions](docs/reference/language.md).

## Installation

Add `predicator` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:predicator, "~> 7.0"}
  ]
end
```

Predicator requires Elixir 1.18 or later and has no runtime dependencies.

## Quick Start

```elixir
iex> Predicator.evaluate!("score > 85 AND active", %{"score" => 92, "active" => true})
true

iex> {:ok, instructions} = Predicator.compile("score > threshold")
iex> Predicator.evaluate!(instructions, %{"score" => 95, "threshold" => 80})
true

iex> Predicator.evaluate("score > 85", %{"score" => 92})
{:ok, true}

iex> {:ok, compiled} = Predicator.compile_with_positions("score > threshold")
iex> Predicator.evaluate(compiled, %{"score" => 95, "threshold" => 80})
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
  functions, data types, and error shapes
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
- [Architecture decision records](docs/adr/README.md) - the reasoning behind
  the design

## Migrating from `=`

`=` is no longer an equality operator. It is assignment, valid only at the
start of a statement (`Predicator.parse_program/2`) and only with an
assignable left side; a bare `=` in expression position - through
`Predicator.parse/2` or `Predicator.evaluate/3` - is a parse error naming `==`
as the fix, never a silent reinterpretation. `==` and `===` are the only
equality operators. See
[ADR-0002](docs/adr/0002-the-equals-grammar-break.md) for the reasoning.

## Cross-Language Siblings

Predicator's Elixir implementation is the reference implementation of the
instruction set (the ISA), which is versioned. Ruby and JavaScript siblings,
in the [riddler/predicator](https://github.com/riddler/predicator) monorepo,
adopt each ISA version on their own schedule; a sibling running behind the
current version is an expected, documented state, not a defect. See
[ADR-0003](docs/adr/0003-the-elixir-implementation-leads-the-isa.md) for the
reasoning and [docs/architecture.md](docs/architecture.md) for what each
sibling currently supports. [docs/isa.md](docs/isa.md) is the specification a
sibling implements against, and [conformance/](conformance/README.md) is how a
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
