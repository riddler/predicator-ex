# Embedding Compiled Programs

This guide is for a host that compiles a predicate once, persists the result,
and evaluates it many times later - possibly under a different build of this
library than the one that compiled it. Follow it and a stored artifact is
never silently mis-run: it either still runs, or it is refused with a message
naming why ([ADR-0003](../adr/0003-the-elixir-implementation-leads-the-isa.md)).

## Choose a compile function

`Predicator.compile/1` returns `{:ok, instructions}` - the bare instruction
list, which is the portable artifact:

```elixir
iex> {:ok, instructions} = Predicator.compile("score > 85")
iex> instructions
[["load", "score"], ["lit", 85], ["compare", "GT"]]
```

`Predicator.compile!/1` is its raising form, for a caller that already treats
a parse failure as a bug rather than an expected outcome:

```elixir
iex> Predicator.compile!("score > 85")
[["load", "score"], ["lit", 85], ["compare", "GT"]]
```

`Predicator.compile_with_positions/1` and `Predicator.compile_with_spans/1`
return `{:ok, %Predicator.Compiled{}}` instead - the instructions and a
source-location table as one value:

```elixir
iex> {:ok, compiled} = Predicator.compile_with_positions("score > 85")
iex> compiled.instructions
[["load", "score"], ["lit", 85], ["compare", "GT"]]
```

`compiled.instructions` is byte-identical to what `compile/1` emits for the
same source:

```elixir
iex> {:ok, plain} = Predicator.compile("score > 85")
iex> {:ok, compiled} = Predicator.compile_with_positions("score > 85")
iex> plain == compiled.instructions
true
```

Pass the `%Predicator.Compiled{}` struct straight to `Predicator.evaluate/3` -
it accepts the struct directly, so the position table cannot be dropped
between compiling and evaluating
([ADR-0009](../adr/0009-the-compiled-envelope-carries-the-position-table.md)):

```elixir
iex> {:ok, compiled} = Predicator.compile_with_positions("score > 85")
iex> Predicator.evaluate(compiled, %{"score" => 92})
{:ok, true}
```

## Store the instruction list, not the struct

`%Predicator.Compiled{}` is an in-memory Elixir value, not a wire format.
Persist `compiled.instructions` - the bare JSON array - and nothing else.
`compiled.positions` holds offsets into the source string the program was
compiled from, and is meaningless to anything that does not also hold that
string.

A program loaded back as a bare instruction list evaluates fine and reports
`position: nil` on a runtime error, which is *correct* - the source is gone,
so there is nothing honest to point at.

To get positions back after a round trip, persist the **source**, not the
table, and recompile with `compile_with_positions/1` (or
`compile_with_spans/1`) on load. Recompiling the same source is deterministic:

```elixir
iex> {:ok, first} = Predicator.compile_with_positions("score > 85")
iex> {:ok, second} = Predicator.compile_with_positions("score > 85")
iex> first == second
true
```

Do not persist the table instead of the source. Nothing checks that a
`positions` table actually came from the `instructions` list it is attached
to, so a table compiled from one source and attached to another source's
instructions produces no error - just a confidently wrong position, which is
worse than the honest `nil` a bare instruction list reports
(`lib/predicator/compiled.ex`).

## Persisting a context alongside a program

The instruction list is not the only thing a long-lived host may want to
store or hand to another process - the `%Predicator.Context{}` it evaluates
against is a candidate too, if functions are wired in through `providers:`
rather than `functions:`. A provider is a module atom, and a `host` term is
whatever plain data the host put there, so a context built that way is
ordinary Erlang term data:

```elixir
iex> context = Predicator.Context.new(
...>   %{"score" => 92},
...>   providers: [Predicator.Functions.MathFunctions],
...>   builtins: false,
...>   host: %{tenant: "acme"}
...> )
iex> binary = :erlang.term_to_binary(context)
iex> restored = :erlang.binary_to_term(binary)
iex> Predicator.evaluate("Math.max(score, 0) > 85", restored)
{:ok, true}
```

A context carrying an inline `functions:` closure evaluates identically but
is not storable this way - `:erlang.term_to_binary/1` has no way to hand a
`fun` back to a different run or a different node, so it is only ever safe to
call on a providers-only context. See the [custom functions
guide](custom-functions.md#the-host-slot) for the provider + host pattern
this depends on.

## Check the ISA version before you run a stored program

`Predicator.Instructions.required_isa/1` gives the minimum ISA version an
instruction list needs:

```elixir
iex> {:ok, instructions} = Predicator.compile("score > 85")
iex> Predicator.Instructions.required_isa(instructions)
{:ok, 1}
```

An empty list requires `{:ok, 1}` - there is no v0:

```elixir
iex> Predicator.Instructions.required_isa([])
{:ok, 1}
```

`Predicator.isa_version/0` gives the version this build emits and can run:

```elixir
iex> Predicator.isa_version()
5
```

**A bare `required_isa(list) <= isa_version()` comparison is not enough once
any opcode has been retired.** A retired opcode still reports the version
that *introduced* it, not the version that removed it, so `required_isa/1`
alone cannot see that this build no longer runs it. The check to perform
instead is membership of every opcode in
`Predicator.Instructions.opcode_set(Predicator.isa_version())`
(`docs/isa.md` section 1, `lib/predicator/instructions.ex`):

```elixir
iex> instructions = [["lit", true], ["lit", false], ["and"]]
iex> current_set = Predicator.Instructions.opcode_set(Predicator.isa_version())
iex> Enum.all?(instructions, fn [opcode | _operands] -> MapSet.member?(current_set, opcode) end)
false
```

Run that check at load time, before evaluating, and branch on why it failed:

- If `required_isa/1` itself returns `{:error, %{reason: "unknown_opcode"}}`
  or `{:error, %{reason: "malformed_instruction"}}`, the artifact is not
  something this build understands at all - refuse it.
- If an opcode is outside `opcode_set/1` and
  `Predicator.Instructions.retired_in/1` names a version for it, the artifact
  predates a retirement - run `Predicator.Instructions.upgrade/1` over it.
  `upgrade/1` carries an identity guarantee (a list containing no retired
  opcode comes back unchanged), so it is safe to call unconditionally over
  every stored artifact rather than pre-filtering for the ones that need it.
- Anything else - refuse rather than mis-run
  ([ADR-0003](../adr/0003-the-elixir-implementation-leads-the-isa.md)).

The evaluator carries its own backstop for a check you skip or get wrong:
running a stored list containing the retired `and`/`or` opcodes on this build
is refused, not mis-evaluated, naming the ISA version that removed them and
pointing at `upgrade/1`:

```elixir
iex> {:error, err} = Predicator.evaluate([["lit", true], ["lit", false], ["and"]], %{})
iex> {err.reason, err.message}
{"retired_opcode", "Instruction [\"and\"] was retired at ISA v3. Run Predicator.Instructions.upgrade/1 over this instruction list to migrate it."}
```

Performing the `opcode_set/1` check up front exists so that refusal happens
before a partial run, not because this backstop is missing.

## What a major ISA version does to a stored artifact

Retiring an opcode mints the next ISA integer, takes a major library release,
and requires an upgrade path (`docs/isa.md` section 1;
[ADR-0003](../adr/0003-the-elixir-implementation-leads-the-isa.md)).
A stored instruction list is therefore never stranded and never silently
mis-run by a later build: it either still runs unchanged, or it is refused
with a message naming the version, or `upgrade/1` rewrites it onto the
current instruction set.

Two consequences follow that an embedder has to plan for, not just an
implementer:

- **`upgrade/1` is not answer-preserving against the legacy opcodes.** It
  moves a stored artifact onto the same semantics every source-compiled
  expression has had since the retirement shipped, and documents exactly
  three divergences (short-circuiting, `:undefined` operands, and a
  non-boolean right operand). See `Predicator.Instructions.upgrade/1`'s
  `@doc` for the full list rather than assuming they don't apply to your
  stored predicates.
- **The upgraded list requires a higher ISA version than the original.**
  Upgrading a list containing `and`/`or` raises its `required_isa/1` answer
  from `1` to `2`, because jumps are v2 opcodes. This matters when the
  artifact is shared with another implementation: upgrade it in step with
  its other consumers, not ahead of them, or a consumer still on the lower
  version will refuse the upgraded list
  (`lib/predicator/instructions.ex`).

## Runtime errors and positions

What a runtime error carries depends on whether the program that produced it
was evaluated with a position table: evaluating a bare instruction list
yields `position: nil` on error, while evaluating a `%Predicator.Compiled{}`
struct yields a real `{line, column}` (and a `:span` too, if the struct was
built with `compile_with_spans/1`). See
[Error Shapes](../reference/language.md#error-shapes) in the language
reference for the error structs themselves and what each field means.
