# Custom Functions

You can provide custom functions when evaluating expressions using the
`functions:` option.

```elixir
iex> custom_functions = %{"double" => {1, fn [n], _context -> {:ok, n * 2} end}}
iex> Predicator.evaluate("double(score) > 100", %{"score" => 60}, functions: custom_functions)
{:ok, true}
```

A function can read the evaluation context, not just its arguments. The
second argument is a `%Predicator.Context{}`, and `context.data` is the
bound-variable map:

```elixir
iex> custom_functions = %{"user_role" => {0, fn [], context -> {:ok, Map.get(context.data, "current_user_role", "guest")} end}}
iex> Predicator.evaluate("user_role() == 'admin'", %{"current_user_role" => "admin"}, functions: custom_functions)
{:ok, true}
```

## Providers and host state

A closure captures whatever it needs when it is defined, which is fine for a
one-off but does not scale to host state that changes between calls. A
`Predicator.FunctionProvider` module names its functions by atom instead of
closure, and is wired in with `providers:` instead of `functions:`:

```elixir
defmodule MyApp.Predicates do
  @behaviour Predicator.FunctionProvider

  @impl Predicator.FunctionProvider
  def functions, do: %{"is_admin" => {0, :call_is_admin}}

  def call_is_admin([], context), do: {:ok, context.host.role == :admin}
end
```

`Predicator.Context.new/2`'s `host:` option carries whatever a provider
needs - a request struct, a tenant id - separately from the evaluated data,
and `put_host/2` replaces it in O(1) without touching `data`. The same
`(args, context)` convention applies to an inline closure, so `host:` works
there too:

```elixir
iex> custom_functions = %{"is_admin" => {0, fn [], context -> {:ok, context.host.role == :admin} end}}
iex> context = Predicator.Context.new(%{}, functions: custom_functions, host: %{role: :admin})
iex> Predicator.evaluate("is_admin()", context)
{:ok, true}
iex> context = Predicator.Context.put_host(context, %{role: :guest})
iex> Predicator.evaluate("is_admin()", context)
{:ok, false}
```

A context built only from `providers:` - no inline `functions:` closures - is
serializable (`:erlang.term_to_binary/1` round-trips it), because a module
atom and a host term are both plain data. A context carrying inline closures
works identically but is not storable.

A function that returns `{:error, message}` surfaces as an
`EvaluationError`, not a bare string - see the [error shapes
reference](../reference/language.md#error-shapes):

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

Custom functions are merged with the builtin set, and a custom function with
the same name as a builtin overrides it for that evaluation only:

```elixir
iex> override_functions = %{"len" => {1, fn [_], _context -> {:ok, "custom_result"} end}}
iex> Predicator.evaluate("len('anything')", %{}, functions: override_functions)
{:ok, "custom_result"}

iex> Predicator.evaluate("len('hello')", %{})
{:ok, 5}
```

## Function format

Custom functions must follow this format:

- **Map key**: function name (string)
- **Map value**: `{arity, function}` tuple where:
  - `arity`: the number of arguments the function expects, as an integer -
    or as a **list of integers** for a function with optional arguments
    (`substring/2` and `/3` both register under `"substring" => {[2, 3],
    &call_substring/2}` in the builtin string functions, for example)
  - `function`: an anonymous function taking `[args], context` and returning
    `{:ok, result}` or `{:error, message}`

Custom functions carry no global state - they are scoped to the single
`evaluate/3` call that receives them, so concurrent evaluations with
different function sets never interfere with each other.
