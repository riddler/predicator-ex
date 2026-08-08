# Nested Data Access

Predicator supports nested data structure access using both dot notation and
bracket notation, letting you reference deeply nested values in your context.

```elixir
iex> context = %{"user" => %{"age" => 47, "name" => %{"first" => "John", "last" => "Doe"}, "profile" => %{"role" => "admin"}, "settings" => %{"theme" => "dark", "notifications" => true}}, "config" => %{"database" => %{"host" => "localhost", "port" => 5432}}, "items" => ["apple", "banana", "cherry"], "scores" => [85, 92, 78, 96]}
iex> Predicator.evaluate("user.name.first == 'John'", context)
{:ok, true}

iex> context = %{"user" => %{"age" => 47, "name" => %{"first" => "John", "last" => "Doe"}, "profile" => %{"role" => "admin"}, "settings" => %{"theme" => "dark", "notifications" => true}}, "config" => %{"database" => %{"host" => "localhost", "port" => 5432}}, "items" => ["apple", "banana", "cherry"], "scores" => [85, 92, 78, 96]}
iex> Predicator.evaluate("user.age > 18", context)
{:ok, true}

iex> context = %{"user" => %{"age" => 47, "name" => %{"first" => "John", "last" => "Doe"}, "profile" => %{"role" => "admin"}, "settings" => %{"theme" => "dark", "notifications" => true}}, "config" => %{"database" => %{"host" => "localhost", "port" => 5432}}, "items" => ["apple", "banana", "cherry"], "scores" => [85, 92, 78, 96]}
iex> Predicator.evaluate("config.database.port == 5432", context)
{:ok, true}
```

## Bracket notation

```elixir
iex> context = %{"user" => %{"name" => %{"first" => "John"}, "settings" => %{"theme" => "dark"}, "profile" => %{"role" => "admin"}}, "items" => ["apple"], "scores" => [85, 92]}
iex> Predicator.evaluate("user['name']['first'] == 'John'", context)
{:ok, true}

iex> context = %{"user" => %{"name" => %{"first" => "John"}, "settings" => %{"theme" => "dark"}, "profile" => %{"role" => "admin"}}, "items" => ["apple"], "scores" => [85, 92]}
iex> Predicator.evaluate("user['settings']['theme'] == 'dark'", context)
{:ok, true}
```

## Array access

```elixir
iex> context = %{"items" => ["apple", "banana", "cherry"], "scores" => [85, 92, 78, 96]}
iex> Predicator.evaluate("items[0] == 'apple'", context)
{:ok, true}

iex> context = %{"items" => ["apple", "banana", "cherry"], "scores" => [85, 92, 78, 96]}
iex> Predicator.evaluate("scores[1] > 90", context)
{:ok, true}

iex> context = %{"scores" => [85, 92, 78, 96], "index" => 2}
iex> Predicator.evaluate("scores[index] > 80", context)
{:ok, false}

iex> context = %{"items" => ["a", "b", "c"], "i" => 1}
iex> Predicator.evaluate("items[i + 1]", context)
{:ok, "c"}

iex> context = %{"items" => ["a", "b"]}
iex> Predicator.evaluate("items[5] == 'z'", context)
{:ok, :undefined}
```

Bracket keys accept any expression, not just a bare variable - `items[i + 1]`
computes the index before indexing. An out-of-bounds index returns
`:undefined` rather than raising, the same as a missing map key.

## Mixed notation

```elixir
iex> context = %{"user" => %{"settings" => %{"theme" => "dark"}, "profile" => %{"role" => "admin"}}}
iex> Predicator.evaluate("user.settings['theme'] == 'dark'", context)
{:ok, true}

iex> context = %{"user" => %{"settings" => %{"theme" => "dark"}, "profile" => %{"role" => "admin"}}}
iex> Predicator.evaluate("user['profile'].role == 'admin'", context)
{:ok, true}
```

## Chained access and combined expressions

```elixir
iex> context = %{"user" => %{"name" => %{"first" => "John", "last" => "Doe"}, "profile" => %{"role" => "admin"}, "settings" => %{"notifications" => true}}}
iex> Predicator.evaluate("user['name']['first'] + ' ' + user['name']['last']", context)
{:ok, "John Doe"}

iex> context = %{"user" => %{"profile" => %{"role" => "admin"}, "settings" => %{"notifications" => true}}}
iex> Predicator.evaluate("user.profile.role == 'admin' AND user.settings.notifications", context)
{:ok, true}
```

## Missing paths

A missing path returns `:undefined` rather than raising:

```elixir
iex> context = %{"user" => %{"profile" => %{"role" => "admin"}}}
iex> Predicator.evaluate("user.profile.email == 'test'", context)
{:ok, :undefined}
```

## Atom keys in the context you pass in

A context built with atom keys still works, but not because nested access
reads atom keys directly - `Predicator.evaluate/3` normalizes a bare map
through `Predicator.Context.new/2` before evaluation, which converts atom
keys to string keys deeply and eagerly. By the time access runs, only string
keys remain:

```elixir
iex> atom_context = %{user: %{name: %{first: "Jane"}}}
iex> Predicator.evaluate("user.name.first == 'Jane'", atom_context)
{:ok, true}
```

## Nested lists

```elixir
iex> list_context = %{"user" => %{"hobbies" => ["reading", "coding"]}}
iex> Predicator.evaluate("'coding' in user.hobbies", list_context)
{:ok, true}
```

## Summary

- **Dot notation**: `user.profile.name` for nested object access
- **Bracket notation**: `user['profile']['name']` for dynamic key access
- **Array indexing**: `items[0]`, `scores[index]` for list access
- **Mixed styles**: `user.settings['theme']` combining both notations
- **Unlimited nesting depth**: `app.database.config.settings.ssl`
- **Dynamic and expression keys**: `items[index]`, `items[i + 1]`
- **Graceful fallback**: returns `:undefined` for missing paths or
  out-of-bounds access
- **Type preservation**: maintains original data types (strings, numbers,
  booleans, lists)
- **Backwards compatible**: simple variable names work exactly as before
