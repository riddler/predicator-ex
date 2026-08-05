# Custom Functions

You can provide custom functions when evaluating expressions using the
`functions:` option.

```elixir
iex> custom_functions = %{"double" => {1, fn [n], _context -> {:ok, n * 2} end}}
iex> Predicator.evaluate("double(score) > 100", %{"score" => 60}, functions: custom_functions)
{:ok, true}
```

A function can read the evaluation context, not just its arguments:

```elixir
iex> custom_functions = %{"user_role" => {0, fn [], context -> {:ok, Map.get(context, "current_user_role", "guest")} end}}
iex> Predicator.evaluate("user_role() == 'admin'", %{"current_user_role" => "admin"}, functions: custom_functions)
{:ok, true}
```

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
