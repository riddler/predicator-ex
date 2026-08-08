# Location Expressions

Predicator provides specialized support for SCXML datamodel location
expressions, which determine valid assignment targets (l-values) for
`<assign>` operations.

## Resolving locations

```elixir
iex> Predicator.context_location("user.profile.name", %{})
{:ok, ["user", "profile", "name"]}

iex> Predicator.context_location("items[0]", %{})
{:ok, ["items", 0]}

iex> Predicator.context_location("data['users'][index]['profile']", %{"index" => 2})
{:ok, ["data", "users", 2, "profile"]}
```

Invalid targets and undefined bracket variables come back as
`Predicator.Errors.LocationError`. Bind-and-project the `type` field rather
than inlining a full struct literal, since the struct carries additional
`details` that can grow without changing what these examples assert:

```elixir
iex> {:error, err} = Predicator.context_location("len(name)", %{})
iex> err.type
:not_assignable

iex> {:error, err} = Predicator.context_location("42", %{})
iex> err.type
:not_assignable

iex> {:error, err} = Predicator.context_location("items[missing_var]", %{})
iex> err.type
:undefined_variable
```

## Valid assignment targets

- Simple identifiers: `user`, `score`, `config`
- Property access: `user.name`, `config.database.host`
- Bracket access: `items[0]`, `user['profile']`, `data["key"]`
- Mixed notation: `user.settings['theme']`, `data['users'][0].profile`

## Invalid assignment targets

- Literals: `42`, `"hello"`, `true`, `#2024-01-15#`
- Function calls: `len(name)`, `upper(role)`, `Math.max(a, b)`
- Arithmetic expressions: `score + 1`, `items[i + 1]`
- Comparison results: `score > 85`, `name == "John"`
- Any computed expression that cannot serve as a memory location

## LocationError types

`Predicator.Errors.LocationError` carries one of seven `type` values, one per
error-construction site in `Predicator.ContextLocation`:

| Type | Fires when |
|---|---|
| `:not_assignable` | The expression itself is a literal, function call, arithmetic, comparison, logical, or unary expression, or a list literal - anything that is not an identifier or an access chain |
| `:invalid_node` | The AST node is not one `ContextLocation` recognizes - a catch-all for an unknown node type |
| `:undefined_variable` | A bracket key is an identifier for a variable that is not present in the context |
| `:invalid_key` | A bracket key resolves to a value that is neither a string nor an integer |
| `:computed_key` | A bracket key is a computed expression - arithmetic, a function call, and so on - rather than a literal or a variable reference |
| `:not_a_container` | `put/3` traverses a value that is neither a map nor a list |
| `:invalid_index` | `put/3` traverses or writes at a negative list index |

## Location path format

Location paths are returned as lists representing the navigation path to a
specific location:

```text
["user"]                                  # user
["user", "name"]                          # user.name
["items", 0]                              # items[0]
["user", "profile", "settings", "theme"]  # user.profile.settings['theme']
["data", "users", 2, "name"]              # data['users'][2]['name']
```

This enables safe assignment operations in SCXML processors while preventing
assignment to computed values or literals.

## Assignment

Resolving a location tells you *where* to write. `Predicator.context_assign/4`
performs the write, and `Predicator.ContextLocation.put/3` does the same
given an already-resolved path. Note that `context_assign/4` takes the
context first, unlike `context_location/3`: it transforms a context and
returns a new one, so it composes in a pipeline.

```elixir
iex> Predicator.context_assign(%{}, "user.profile.name", "Ada")
{:ok, %{"user" => %{"profile" => %{"name" => "Ada"}}}}
```

Missing intermediate containers are created automatically - a string segment
vivifies a map, an integer segment vivifies a list:

```elixir
iex> Predicator.context_assign(%{}, "data['users'][0].name", "Ada")
{:ok, %{"data" => %{"users" => [%{"name" => "Ada"}]}}}
```

Existing siblings are preserved:

```elixir
iex> Predicator.context_assign(%{"user" => %{"id" => 1}}, "user.name", "Ada")
{:ok, %{"user" => %{"id" => 1, "name" => "Ada"}}}
```

Indices past the end of a list pad the gap with `:undefined`:

```elixir
iex> Predicator.context_assign(%{"items" => [1]}, "items[2]", "x")
{:ok, %{"items" => [1, :undefined, "x"]}}
```

`ContextLocation.put/3` does the same given an already-resolved path:

```elixir
iex> Predicator.ContextLocation.put(%{}, ["user", "profile", "name"], "Ada")
{:ok, %{"user" => %{"profile" => %{"name" => "Ada"}}}}
```

Auto-vivification never destroys existing data. Assigning through a value
that is neither a map nor a list is an error, as is a negative list index:

```elixir
iex> {:error, err} = Predicator.context_assign(%{"user" => 5}, "user.profile.name", "Ada")
iex> err.type
:not_a_container

iex> {:error, err} = Predicator.context_assign(%{"items" => [1, 2]}, "items[-1]", "x")
iex> err.type
:invalid_index
```

Two rules worth knowing:

- **The leaf is always overwritten**, whatever it currently holds - including
  a map or a list.
- **Only string and integer keys are consulted**, never atom keys. Assigning
  `user.name` into a context holding `%{user: %{}}` creates a new `"user"`
  map beside the atom key rather than descending into it. A caller reaching
  this through `Predicator.Context.assign/3` never hits this case in
  practice: `Context.new/2`/`bind/3` already convert atom keys to strings
  deeply and eagerly, so `data` has no atom keys left by the time `assign/3`
  calls in. It matters only for a caller invoking `ContextLocation.put/3`
  directly on a hand-built, unnormalized map.

`ContextLocation.put/3` is the contract-stable primitive that later releases
write through: `Predicator.Context.assign/3` and `Predicator.context_assign/4`
both call it directly rather than duplicating the write logic. Its signature
and the auto-vivification semantics documented above are frozen for that
reason - a change to either would move silently underneath every caller of
`assign/3` and `context_assign/4`.
