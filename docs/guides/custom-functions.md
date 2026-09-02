# Custom Functions

A custom function is provided by a module implementing the one-callback
`Predicator.FunctionProvider` behaviour, `functions/0`, which returns
`%{name => {arity, atom}}` - the same shape the four builtin modules use for
`len`, `upper`, `abs`, and the rest. Wire a provider module in with
`Predicator.Context.new/2`'s `providers:` option:

```elixir
defmodule MyApp.AccountPredicates do
  @behaviour Predicator.FunctionProvider

  @impl Predicator.FunctionProvider
  def functions, do: %{"account_active" => {0, :call_account_active}}

  def call_account_active([], context), do: {:ok, context.host.account.status == :active}
end
```

Every function - builtin, provider, or inline closure - is called as
`(args, context)`, where `context` is the `%Predicator.Context{}` the
evaluation is running under, not a bare data map.

## The host slot

`Context.new/2`'s `host:` option carries whatever a provider needs at call
time - the account record behind a card transaction, a tenant id, a
database connection - separately from the evaluated data, and `put_host/2`
replaces it in O(1) without touching `data`. `host` is opaque: it is stored
exactly as given, and there is no syntax that reads it from predicate text
directly - only a function can see it. The same `(args, context)`
convention applies to an inline closure, so `host:` works there too:

```elixir
iex> custom_functions = %{"account_active" => {0, fn [], context -> {:ok, context.host.account.status == :active} end}}
iex> context = Predicator.Context.new(%{}, functions: custom_functions, host: %{account: %{status: :active}})
iex> Predicator.evaluate("account_active()", context)
{:ok, true}
iex> context = Predicator.Context.put_host(context, %{account: %{status: :frozen}})
iex> Predicator.evaluate("account_active()", context)
{:ok, false}
```

**A context built only from `providers:` - no inline `functions:` closures -
is serializable**: `:erlang.term_to_binary/1` round-trips it, because a
module atom and a host term are both plain data. A context carrying inline
closures works identically but cannot be stored - a `fun` is not a term
`:erlang.term_to_binary/1` can hand back to another process or a later run.
Reach for a provider module, not `functions:`, the moment a context needs to
be persisted or sent across a boundary.

## Inline closures (convenience form)

For a one-off function with nothing to persist, `Predicator.evaluate/3`'s
`functions:` option takes a `%{name => {arity, fun}}` map directly, without
building a context or a provider module first:

```elixir
iex> custom_functions = %{"double" => {1, fn [n], _context -> {:ok, n * 2} end}}
iex> Predicator.evaluate("double(limit) > 100", %{"limit" => 60}, functions: custom_functions)
{:ok, true}
```

A closure can read the evaluation context, not just its arguments -
`context.data` is the bound-variable map:

```elixir
iex> custom_functions = %{"holder_tier" => {0, fn [], context -> {:ok, Map.get(context.data, "account_tier", "standard")} end}}
iex> Predicator.evaluate("holder_tier() == 'premium'", %{"account_tier" => "premium"}, functions: custom_functions)
{:ok, true}
```

## Errors from functions

A function that returns `{:error, message}` surfaces as an
`EvaluationError`, not a bare string - see the [error shapes
reference](../reference/language.md#error-shapes). This applies equally to a
provider callback and an inline closure:

```elixir
iex> custom_functions = %{"divide" => {2, fn [a, b], _context ->
...>   if b == 0, do: {:error, "Division by zero"}, else: {:ok, a / b}
...> end}}
iex> Predicator.evaluate("divide(10, 2) == 5", %{}, functions: custom_functions)
{:ok, true}

iex> custom_functions = %{"divide" => {2, fn [a, b], _context ->
...>   if b == 0, do: {:error, "Division by zero"}, else: {:ok, a / b}
...> end}}
iex> {:error, err} = Predicator.evaluate("divide(10, 0)", %{}, functions: custom_functions)
iex> {err.__struct__, err.message}
{Predicator.Errors.EvaluationError, "Division by zero"}
```

## Overriding builtins

A custom function - provider or inline closure - with the same name as a
builtin overrides it for that evaluation only:

```elixir
iex> override_functions = %{"len" => {1, fn [_], _context -> {:ok, "custom_result"} end}}
iex> Predicator.evaluate("len('anything')", %{}, functions: override_functions)
{:ok, "custom_result"}

iex> Predicator.evaluate("len('hello')", %{})
{:ok, 5}
```

The full shadowing order, when both are given: the four builtin provider
modules, then `providers:` left to right, then `functions:` last - each step
shadowing a same-named entry from the step before it.

## Function format

Both a provider's `functions/0` and an inline `functions:` map share the same
value shape - `{arity, callable}` - and differ only in what `callable` is:

- **Map key**: function name (string)
- **Map value**: `{arity, callable}` tuple where:
  - `arity`: the number of arguments the function expects, as an integer -
    or as a **list of integers** for a function with optional arguments
    (`substring/2` and `/3` both register under `"substring" => {[2, 3],
    :call_substring}` in the builtin string functions, for example)
  - `callable`: for a provider, an atom naming a public 2-arity function
    exported by that same module; for an inline map, an anonymous function
    taking `[args], context`. Either form returns `{:ok, result}` or
    `{:error, message}`

Custom functions carry no global state - they are scoped to the single
`Context.new/2` or `evaluate/3` call that receives them, so concurrent
evaluations with different function sets never interfere with each other.
