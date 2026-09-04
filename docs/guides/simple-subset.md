# The simple subset

A structured authoring surface - the row of dropdowns that reads
*field / operator / value*, repeated down a form - is how most people write a
condition. It is also strictly less expressive than the language: there is no
place in a picklist to put a parenthesis, no second precedence level, and no
way to draw `NOT`.

`Predicator.Simple` names the part of the language such a surface can render,
so an editor can ask about an expression rather than guess. It is a reading
and writing surface over the AST; it evaluates nothing and it raises nothing.

## The value

A `Predicator.Simple` is a list of clauses joined by one connective. A clause
is a field path, an operator, and a value.

```elixir
iex> Predicator.Simple.from_source("status == 'active'")
{:ok,
 %Predicator.Simple{
   connective: nil,
   clauses: [{[root: "status"], :equal_equal, {:string, "active", :single}}]
 }}
```

One clause carries no connective, because it is joined to nothing. Two or more
carry the one connective that joins them all:

```elixir
iex> {:ok, simple} = Predicator.Simple.from_source("status == 'active' AND amount >= 500")
iex> simple.connective
:and
iex> length(simple.clauses)
2
```

That is the whole shape. A form renders one row per clause and one connective
control for the form; nothing in the value can fail to fit.

## Three answers, not two

`from_source/1` answers three different questions, and an editor needs all
three kept apart.

**In the subset** - render it as rows:

```elixir
iex> {:ok, %Predicator.Simple{}} = Predicator.Simple.from_source("plan == 'pro'")
iex> :in_the_subset
:in_the_subset
```

**Outside the subset** - a perfectly valid expression the form cannot draw.
Offer the text editor instead, and do not call it an error:

```elixir
iex> Predicator.Simple.from_source("status == 'active' AND (amount >= 500 OR plan == 'pro')")
:outside

iex> Predicator.Simple.from_source("NOT plan == 'pro'")
:outside
```

**Not an expression** - a `Predicator.Errors.ParseError` with the position and
span of the failure, which is what underlines the mistake:

```elixir
iex> {:error, error} = Predicator.Simple.from_source("amount >= >=")
iex> error.position
{1, 11}
```

`from_ast/1` is the same function without the parse: it answers `{:ok, simple}`
or `:outside` for any AST, and it is total - there is no node shape that makes
it raise.

## What is in

Paths are an identifier and the accesses that follow it:

```elixir
iex> {:ok, simple} = Predicator.Simple.from_source("card.brand == 'visa'")
iex> [{path, _op, _value}] = simple.clauses
iex> path
[root: "card", property: "brand"]

iex> {:ok, simple} = Predicator.Simple.from_source("cart['items'] contains 'gift'")
iex> [{path, _op, _value}] = simple.clauses
iex> path
[root: "cart", key: "items"]
```

Operators are the comparisons and the two membership operators. Values are one
scalar or a list of them:

```elixir
iex> {:ok, simple} = Predicator.Simple.from_source("step in ['payment', 'review']")
iex> simple.clauses
[{[root: "step"], :in, {:list, [{:string, "payment", :single}, {:string, "review", :single}]}}]
```

Durations and relative dates are values like any other, which is what lets a
form offer "in the last N days" as a value control:

```elixir
iex> {:ok, simple} = Predicator.Simple.from_source("signup.created_at < 30d ago")
iex> simple.clauses
[{[root: "signup", property: "created_at"], :lt, {:relative_date, [{30, "d"}], :ago}}]
```

## What is out, and why

Mixed `AND`/`OR`, parentheses, `NOT`, arithmetic, function calls, casts, and
object literals are outside the subset by decision. Each of them needs a
control a picklist does not have.

Three narrower exclusions are worth knowing about, because they look like
oversights and are not. Each exists to keep the round-trip laws below true:

| Excluded | Why |
|---|---|
| Float literals | `Predicator.decompile/2` has no clause for a float and raises on one, so admitting floats would make `to_source/2` partial |
| Negative numbers | The parser reads `-5` as a `unary` node, so a negative literal is not something a parse can produce |
| A bare binary `{:literal, "text"}` | It decompiles to `"text"`, which parses back as a `string_literal` - a different node |

The clause's path is always on the left. `amount >= 500` is in the subset and
`500 <= amount` is not, because a form has one field control and it is on the
left:

```elixir
iex> Predicator.Simple.from_source("500 <= amount")
:outside
```

## Round-tripping

Two laws hold for every value the module produces.

**The AST law**: reading a value back out of its own AST returns the same
value.

```elixir
iex> {:ok, simple} = Predicator.Simple.from_source("plan == 'pro'")
iex> Predicator.Simple.from_ast(Predicator.Simple.to_ast(simple)) == {:ok, simple}
true
```

**The source law**: rendering a value to source and parsing it back gives the
same AST, modulo source positions.

```elixir
iex> {:ok, simple} = Predicator.Simple.from_source("status == 'active' AND amount >= 500")
iex> Predicator.Simple.to_source(simple)
"status == 'active' AND amount >= 500"
```

Together they are what lets an editor hand an expression to a form, take the
edited value back, and write source the author recognises. Quote style
survives the trip, so an expression written with single quotes does not come
back double-quoted:

```elixir
iex> {:ok, simple} = Predicator.Simple.from_source("plan == 'pro'")
iex> Predicator.Simple.to_source(simple)
"plan == 'pro'"
```

`to_source/2` takes `Predicator.decompile/2`'s formatting options, so a host
that renders the rest of its expressions one way renders these the same way:

```elixir
iex> {:ok, simple} = Predicator.Simple.from_source("plan == 'pro'")
iex> Predicator.Simple.to_source(simple, spacing: :compact)
"plan=='pro'"
```

## Building a value by hand

An editor assembling a value from form state rather than from source can check
it before calling `to_ast/1`:

```elixir
iex> simple = %Predicator.Simple{connective: nil, clauses: [{[root: "amount"], :gte, {:integer, 500}}]}
iex> Predicator.Simple.well_formed?(simple)
true
iex> Predicator.Simple.to_source(simple)
"amount >= 500"
```

The invariant that catches most hand-built mistakes is the connective one:
`nil` for exactly one clause, `:and` or `:or` for two or more.

```elixir
iex> Predicator.Simple.well_formed?(%Predicator.Simple{connective: :and, clauses: [{[root: "amount"], :gte, {:integer, 500}}]})
false
```
