# How to list what an expression reads and calls

This guide is for a host that needs the facts in a rule without running it: an
editor that lists the fields a condition reads, or a checker that compares
those reads against the fields a form declares. `Predicator.Analysis` answers
three questions about any rule or script - which variables it reads, which
functions it calls, and which locations it stores to - without evaluating
anything and without a context. The decision behind its answers is
[ADR-0020](https://github.com/riddler/predicator-ex/blob/main/docs/adr/0020-analysis-is-a-reading-surface-over-both-forms.md).

## List the reads and the calls

Pass a source string to `Predicator.Analysis.references/1` and
`Predicator.Analysis.calls/1`. Each answers `{:ok, list}`, with one entry per
occurrence in source order:

```elixir
iex> rule = "loan.status == 'active' and len(patron.cards) > limit"
iex> {:ok, reads} = Predicator.Analysis.references(rule)
iex> Enum.map(reads, & &1.path)
[["loan", "status"], ["patron", "cards"], ["limit"]]
iex> {:ok, calls} = Predicator.Analysis.calls(rule)
iex> Enum.map(calls, &{&1.name, &1.arity})
[{"len", 1}]
```

A read is a path: a list of segments, one for the variable and one for each
property or bracket key after it. A segment is a string, an integer for a
literal index, or `:dynamic` for any other key: a computed one, or a literal that is neither a
string nor an integer. The path keeps going
past a `:dynamic` segment, and the reads inside the computed key are listed
as reads of their own:

```elixir
iex> {:ok, reads} = Predicator.Analysis.references("items[i].price > limits['max']")
iex> Enum.map(reads, & &1.path)
[["items", :dynamic, "price"], ["i"], ["limits", "max"]]
```

An entry is listed every time it occurs; a caller that wants a set dedupes.
`Predicator.Analysis.assignments/1` lists the locations a script stores to in
the same shape, and an expression stores nothing:

```elixir
iex> {:ok, program} = Predicator.parse_program("if overdue { fine = days * rate }")
iex> {:ok, reads} = Predicator.Analysis.references(program)
iex> Enum.map(reads, & &1.path)
[["overdue"], ["days"], ["rate"]]
iex> {:ok, stores} = Predicator.Analysis.assignments(program)
iex> Enum.map(stores, & &1.path)
[["fine"]]
```

A location a script writes is not a read. A source string that does not parse,
or an instruction list the analysis cannot read, gets no list at all; the
"Errors" section of `Predicator.Analysis` says what it gets instead, and this
guide shows only the success path.

## Choose an input form

The three functions accept the same five inputs, which fall into two forms of
one program:

| You hold | Form | Positions |
|---|---|---|
| a source string | tree, read as a program | from the parse |
| an AST from `Predicator.parse/2`, or a program from `Predicator.parse_program/2` | tree | from the nodes' own slots |
| an instruction list from `Predicator.compile/1` | instructions | none |
| a `Predicator.Compiled` envelope | instructions | from the envelope's table, when it has one |

The two forms give the same paths, calls and stores for the same source. Use
the form you already hold: a host that stores compiled rules analyses the
stored instructions and never needs the source text.

```elixir
iex> {:ok, instructions} = Predicator.compile("loan.status == 'active'")
iex> {:ok, from_instructions} = Predicator.Analysis.references(instructions)
iex> {:ok, from_source} = Predicator.Analysis.references("loan.status == 'active'")
iex> Enum.map(from_instructions, & &1.path) == Enum.map(from_source, & &1.path)
true
```

## Know when positions exist

Every entry carries a `position`. A position is a `{line, column}` point, a
span of two such points, or `nil`, and what you get depends on what you
analysed:

  * A source string always gives points. An AST or a program carries the
    positions the parse put in its nodes: points by default, spans when you
    parsed it with `spans: true` and pass the result in.
  * A bare instruction list carries no positions, so every position is `nil`.
  * A `Predicator.Compiled` envelope carries a table when it came from one of
    the `compile_with_positions` or `compile_with_spans` functions (or their
    `compile_program_` counterparts), and the
    entries take their positions from it.

A path's position starts where the path starts. For a read like `loan.status`
it is the point of the variable `loan`, or the span of the whole chain when
the program carries spans:

```elixir
iex> {:ok, instructions} = Predicator.compile("loan.status == 'active'")
iex> {:ok, [read]} = Predicator.Analysis.references(instructions)
iex> read.position
nil
iex> {:ok, compiled} = Predicator.compile_with_positions("loan.status == 'active'")
iex> {:ok, [read]} = Predicator.Analysis.references(compiled)
iex> read.position
{1, 1}
iex> {:ok, spanned} = Predicator.compile_with_spans("loan.status == 'active'")
iex> {:ok, [read]} = Predicator.Analysis.references(spanned)
iex> read.position
{{1, 1}, {1, 12}}
```

A host that wants to point at the offending text later keeps the envelope, not
only the instruction list, when it stores a compiled rule.

## Check reads against a declared set

A checker compares each path a rule reads with the paths a host declares. A
`MapSet` of paths is enough; the check is plain Elixir over the answer:

```elixir
iex> declared = MapSet.new([["loan", "status"], ["loan", "due"], ["grace"]])
iex> undeclared = fn source ->
...>   {:ok, reads} = Predicator.Analysis.references(source)
...>   for %{path: path, position: position} <- reads,
...>       not MapSet.member?(declared, path),
...>       do: {path, position}
...> end
iex> undeclared.("loan.status == 'active' and loan.fine > grace")
[{["loan", "fine"], {1, 29}}]
```

Each undeclared read arrives with the position of the text to underline.

A `:dynamic` segment names no declared field, so a path with one never matches
a declared path exactly. Compare the part of the path before the first
`:dynamic` segment, which names the collection the computed key indexes into:

```elixir
iex> declared = MapSet.new([["items"], ["limit"]])
iex> {:ok, reads} = Predicator.Analysis.references("items[i].price > limit")
iex> for %{path: path} <- reads,
...>     known = Enum.take_while(path, &(&1 != :dynamic)),
...>     not MapSet.member?(declared, known),
...>     do: path
[["i"]]
```

The key `i` is a read of its own, and it is the one the declared set is
missing. The same shape checks calls against the function names a host
provides:

```elixir
iex> provided = MapSet.new([{"len", 1}, {"upper", 1}])
iex> {:ok, calls} = Predicator.Analysis.calls("len(name) > 3 and slug(name) == 'x'")
iex> for %{name: name, arity: arity} <- calls,
...>     not MapSet.member?(provided, {name, arity}),
...>     do: {name, arity}
[{"slug", 1}]
```

## Walk the tree yourself

When the question is not a read, a call or a store, `Predicator.AST` walks the
tree with the callback shape of the standard library's `Macro` walks.
`Predicator.AST.reduce/3` folds over every node pre-order without rewriting
anything; `Predicator.AST.prewalk/3` and `Predicator.AST.postwalk/3` thread an
accumulator and may replace nodes. Counting the comparisons in a rule:

```elixir
iex> {:ok, ast} = Predicator.parse("fine > 1 and renewals < 3")
iex> Predicator.AST.reduce(ast, 0, fn
...>   {:comparison, _op, _left, _right, _pos}, count -> count + 1
...>   _node, count -> count
...> end)
2
```

The shape of each node is in the [AST reference](../reference/ast.md#traversing-and-analysing-the-tree).
