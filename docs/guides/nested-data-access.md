# Nested Data Access

Predicator supports nested data structure access using both dot notation and
bracket notation, letting you reference deeply nested values in your context.

The examples below use the card-authorization context the rest of the docs
authorize against: an `account` with a holder, a budget and a status, the
`transaction` being decided, and two lists - the signup wizard's `steps` and
a run of recent `amounts`.

```elixir
iex> context = %{"account" => %{"holder" => %{"first" => "Ada", "last" => "Byron"}, "budget" => %{"remaining" => 500, "limit" => 2000}, "status" => %{"card_active" => true, "tier" => "gold"}}, "transaction" => %{"amount" => 120, "currency" => "USD"}, "steps" => ["payment", "review", "confirm"], "amounts" => [85, 92, 78, 96]}
iex> Predicator.evaluate("account.holder.first == 'Ada'", context)
{:ok, true}

iex> context = %{"account" => %{"holder" => %{"first" => "Ada", "last" => "Byron"}, "budget" => %{"remaining" => 500, "limit" => 2000}, "status" => %{"card_active" => true, "tier" => "gold"}}, "transaction" => %{"amount" => 120, "currency" => "USD"}, "steps" => ["payment", "review", "confirm"], "amounts" => [85, 92, 78, 96]}
iex> Predicator.evaluate("transaction.amount <= account.budget.remaining", context)
{:ok, true}

iex> context = %{"account" => %{"holder" => %{"first" => "Ada", "last" => "Byron"}, "budget" => %{"remaining" => 500, "limit" => 2000}, "status" => %{"card_active" => true, "tier" => "gold"}}, "transaction" => %{"amount" => 120, "currency" => "USD"}, "steps" => ["payment", "review", "confirm"], "amounts" => [85, 92, 78, 96]}
iex> Predicator.evaluate("account.budget.limit == 2000", context)
{:ok, true}
```

## Bracket notation

```elixir
iex> context = %{"account" => %{"holder" => %{"first" => "Ada"}, "status" => %{"tier" => "gold"}, "budget" => %{"remaining" => 500}}, "steps" => ["payment"], "amounts" => [85, 92]}
iex> Predicator.evaluate("account['holder']['first'] == 'Ada'", context)
{:ok, true}

iex> context = %{"account" => %{"holder" => %{"first" => "Ada"}, "status" => %{"tier" => "gold"}, "budget" => %{"remaining" => 500}}, "steps" => ["payment"], "amounts" => [85, 92]}
iex> Predicator.evaluate("account['status']['tier'] == 'gold'", context)
{:ok, true}
```

## Array access

```elixir
iex> context = %{"steps" => ["payment", "review", "confirm"], "amounts" => [85, 92, 78, 96]}
iex> Predicator.evaluate("steps[0] == 'payment'", context)
{:ok, true}

iex> context = %{"steps" => ["payment", "review", "confirm"], "amounts" => [85, 92, 78, 96]}
iex> Predicator.evaluate("amounts[1] > 90", context)
{:ok, true}

iex> context = %{"amounts" => [85, 92, 78, 96], "index" => 2}
iex> Predicator.evaluate("amounts[index] > 80", context)
{:ok, false}

iex> context = %{"steps" => ["payment", "review", "confirm"], "i" => 1}
iex> Predicator.evaluate("steps[i + 1]", context)
{:ok, "confirm"}

iex> context = %{"steps" => ["payment", "review"]}
iex> Predicator.evaluate("steps[5] == 'confirm'", context)
{:ok, :undefined}
```

Bracket keys accept any expression, not just a bare variable - `steps[i + 1]`
computes the index before indexing. An out-of-bounds index returns
`:undefined` rather than raising, the same as a missing map key.

## Mixed notation

```elixir
iex> context = %{"account" => %{"status" => %{"tier" => "gold"}, "budget" => %{"remaining" => 500}}}
iex> Predicator.evaluate("account.status['tier'] == 'gold'", context)
{:ok, true}

iex> context = %{"account" => %{"status" => %{"tier" => "gold"}, "budget" => %{"remaining" => 500}}}
iex> Predicator.evaluate("account['budget'].remaining == 500", context)
{:ok, true}
```

## Chained access and combined expressions

```elixir
iex> context = %{"account" => %{"holder" => %{"first" => "Ada", "last" => "Byron"}, "budget" => %{"remaining" => 500}, "status" => %{"card_active" => true}}}
iex> Predicator.evaluate("account['holder']['first'] + ' ' + account['holder']['last']", context)
{:ok, "Ada Byron"}

iex> context = %{"account" => %{"budget" => %{"remaining" => 500}, "status" => %{"card_active" => true}}}
iex> Predicator.evaluate("account.budget.remaining >= 100 AND account.status.card_active", context)
{:ok, true}
```

## Missing paths

A missing path returns `:undefined` rather than raising:

```elixir
iex> context = %{"account" => %{"holder" => %{"first" => "Ada"}}}
iex> Predicator.evaluate("account.holder.email == 'ada@example.com'", context)
{:ok, :undefined}
```

## Atom keys in the context you pass in

A context built with atom keys still works, but not because nested access
reads atom keys directly - `Predicator.evaluate/3` normalizes a bare map
through `Predicator.Context.new/2` before evaluation, which converts atom
keys to string keys deeply and eagerly. By the time access runs, only string
keys remain:

```elixir
iex> atom_context = %{account: %{holder: %{first: "Ada"}}}
iex> Predicator.evaluate("account.holder.first == 'Ada'", atom_context)
{:ok, true}
```

## Nested lists

```elixir
iex> list_context = %{"account" => %{"networks" => ["visa", "mastercard"]}}
iex> Predicator.evaluate("'visa' in account.networks", list_context)
{:ok, true}
```

## Summary

- **Dot notation**: `account.holder.first` for nested object access
- **Bracket notation**: `account['holder']['first']` for dynamic key access
- **Array indexing**: `steps[0]`, `amounts[index]` for list access
- **Mixed styles**: `account.status['tier']` combining both notations
- **Unlimited nesting depth**: `account.budget.limits.daily.ceiling`
- **Dynamic and expression keys**: `steps[index]`, `steps[i + 1]`
- **Graceful fallback**: returns `:undefined` for missing paths or
  out-of-bounds access
- **Type preservation**: maintains original data types (strings, numbers,
  booleans, lists)
- **Backwards compatible**: simple variable names work exactly as before
