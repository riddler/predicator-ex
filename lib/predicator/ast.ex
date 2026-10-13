defmodule Predicator.AST do
  @moduledoc """
  Traversal primitives over the tree `Predicator.Parser` builds.

  `prewalk/3`, `postwalk/3` and `reduce/3` follow the shape of the standard
  library's `Macro` walks: the callback receives a node and an accumulator, and
  the accumulator is threaded through the whole traversal. They walk anything
  `t:Predicator.Parser.visitable/0` names - a bare expression, a single
  statement, a block, or a whole program from `Predicator.parse_program/2` -
  so a tool that reads or rewrites a tree no longer hand-writes a clause per
  node kind.

  ## What is a node

  Every constructor of `t:Predicator.Parser.visitable/0` is a node: the
  expression layer (`t:Predicator.Parser.ast/0`) plus `program`, `assignment`,
  `if`, `while` and `block`. The callback sees each node once, whole, with its
  trailing position slot as the parser (or a caller) put it. The walks never
  read, change or drop that slot; a node built by hand with a `nil` position
  walks like any other.

  Children are visited in source order:

    * `{:comparison, op, left, right, pos}` and the other binary nodes:
      `left`, then `right`.
    * `{:function_call, name, args, pos}`: each argument, left to right.
    * `{:assignment, location, value, pos}`: the location chain, then the value.
    * `{:if, condition, then_block, else_block, pos}`: the condition, the then
      block, then the else block when there is one.
    * `{:program, statements, pos}` and `{:block, statements, pos}`: each
      statement in order.

  Three shapes need a stated rule:

    * An object literal's key (`t:Predicator.Parser.object_key/0`) is part of
      its entry, not a node of the tree: the walk does not hand it to the
      callback and carries it through untouched, and visits each entry's value
      in entry order.
    * A `:duration` node holds `{integer, unit}` pairs, which are plain data.
      It has no children.
    * A `:relative_date` node's first element is itself a node (its
      `:duration`), so it is walked as a child.

  A literal, string literal and identifier have no children. A value that is
  not one of these tuples (a tuple with an unknown tag) raises a
  `FunctionClauseError`; `test/predicator/ast_clause_coverage_test.exs` keeps
  the clause list in step with `t:Predicator.Parser.visitable/0`.
  """

  alias Predicator.Parser

  @typedoc """
  Anything the walks accept: a whole program, a statement, a block or an
  expression.
  """
  @type t :: Parser.visitable()

  @doc """
  Walks `ast` pre-order, threading `acc` through `fun`.

  `fun` is called on a node before its children, as `fun.(node, acc)`, and
  returns `{node, acc}`. The children of the node it returns are the ones
  walked next, so a callback may replace a node and have the replacement's
  children visited. Returns `{ast, acc}`.

  ## Examples

  Collect identifier names in source order, leaving the tree as it was:

      iex> {:ok, ast} = Predicator.parse("score > limit and ok")
      iex> {^ast, names} =
      ...>   Predicator.AST.prewalk(ast, [], fn
      ...>     {:identifier, name, _pos} = node, acc -> {node, [name | acc]}
      ...>     node, acc -> {node, acc}
      ...>   end)
      iex> Enum.reverse(names)
      ["score", "limit", "ok"]

  Replace a node and keep walking into its replacement:

      iex> {:ok, ast} = Predicator.parse("1 + 2")
      iex> {rewritten, count} =
      ...>   Predicator.AST.prewalk(ast, 0, fn
      ...>     {:arithmetic, :add, left, right, pos}, n ->
      ...>       {{:arithmetic, :multiply, left, right, pos}, n + 1}
      ...>
      ...>     {:literal, v, pos}, n when is_integer(v) ->
      ...>       {{:literal, v * 10, pos}, n + 1}
      ...>
      ...>     node, n ->
      ...>       {node, n}
      ...>   end)
      iex> {count, rewritten}
      {3, {:arithmetic, :multiply, {:literal, 10, {1, 1}}, {:literal, 20, {1, 5}}, {1, 3}}}
  """
  @spec prewalk(t(), acc, (t(), acc -> {t(), acc})) :: {t(), acc} when acc: term()
  def prewalk(ast, acc, fun) when is_function(fun, 2) do
    {node, acc} = fun.(ast, acc)
    map_children(node, acc, &prewalk(&1, &2, fun))
  end

  @doc """
  Walks `ast` post-order, threading `acc` through `fun`.

  `fun` is called on a node after its children have been walked, as
  `fun.(node, acc)`, and sees the node with its already-rewritten children. It
  returns `{node, acc}`; the node it returns is not walked again. Returns
  `{ast, acc}`.

  ## Examples

  Fold constant additions bottom-up:

      iex> {:ok, ast} = Predicator.parse("(1 + 2) + 3")
      iex> {folded, folds} =
      ...>   Predicator.AST.postwalk(ast, 0, fn
      ...>     {:arithmetic, :add, {:literal, a, _}, {:literal, b, _}, pos}, n
      ...>     when is_integer(a) and is_integer(b) ->
      ...>       {{:literal, a + b, pos}, n + 1}
      ...>
      ...>     node, n ->
      ...>       {node, n}
      ...>   end)
      iex> {folds, elem(folded, 1)}
      {2, 6}

  Children are visited before their parent:

      iex> {:ok, ast} = Predicator.parse("a > 1")
      iex> {_ast, tags} =
      ...>   Predicator.AST.postwalk(ast, [], fn node, acc -> {node, [elem(node, 0) | acc]} end)
      iex> Enum.reverse(tags)
      [:identifier, :literal, :comparison]
  """
  @spec postwalk(t(), acc, (t(), acc -> {t(), acc})) :: {t(), acc} when acc: term()
  def postwalk(ast, acc, fun) when is_function(fun, 2) do
    {node, acc} = map_children(ast, acc, &postwalk(&1, &2, fun))
    fun.(node, acc)
  end

  @doc """
  Folds `fun` over every node of `ast` pre-order, without rewriting anything.

  `fun` is called as `fun.(node, acc)` and returns the new accumulator.
  Returns the final accumulator.

  ## Examples

      iex> {:ok, ast} = Predicator.parse("max(a, b) > 3")
      iex> Predicator.AST.reduce(ast, [], fn node, acc -> [elem(node, 0) | acc] end)
      ...> |> Enum.reverse()
      [:comparison, :function_call, :identifier, :identifier, :literal]

  A whole program is walked statement by statement:

      iex> {:ok, program} = Predicator.parse_program("a = 1; b = a + 1")
      iex> Predicator.AST.reduce(program, 0, fn
      ...>   {:assignment, _location, _value, _pos}, n -> n + 1
      ...>   _node, n -> n
      ...> end)
      2
  """
  @spec reduce(t(), acc, (t(), acc -> acc)) :: acc when acc: term()
  def reduce(ast, acc, fun) when is_function(fun, 2) do
    {_ast, acc} = prewalk(ast, acc, fn node, acc -> {node, fun.(node, acc)} end)
    acc
  end

  # One clause per constructor of Parser.visitable/0, in source order. The
  # callback `walk` takes `(child, acc)` and returns `{child, acc}`.
  # ast_clause_coverage_test.exs reads these heads against the typespec.
  @spec map_children(t(), acc, (t(), acc -> {t(), acc})) :: {t(), acc} when acc: term()
  defp map_children({:literal, _value, _pos} = node, acc, _walk), do: {node, acc}
  defp map_children({:string_literal, _value, _quote, _pos} = node, acc, _walk), do: {node, acc}
  defp map_children({:identifier, _name, _pos} = node, acc, _walk), do: {node, acc}
  defp map_children({:duration, _units, _pos} = node, acc, _walk), do: {node, acc}

  defp map_children({:comparison, op, left, right, pos}, acc, walk) do
    {left, acc} = walk.(left, acc)
    {right, acc} = walk.(right, acc)
    {{:comparison, op, left, right, pos}, acc}
  end

  defp map_children({:arithmetic, op, left, right, pos}, acc, walk) do
    {left, acc} = walk.(left, acc)
    {right, acc} = walk.(right, acc)
    {{:arithmetic, op, left, right, pos}, acc}
  end

  defp map_children({:membership, op, left, right, pos}, acc, walk) do
    {left, acc} = walk.(left, acc)
    {right, acc} = walk.(right, acc)
    {{:membership, op, left, right, pos}, acc}
  end

  defp map_children({:unary, op, operand, pos}, acc, walk) do
    {operand, acc} = walk.(operand, acc)
    {{:unary, op, operand, pos}, acc}
  end

  defp map_children({:logical_and, left, right, pos}, acc, walk) do
    {left, acc} = walk.(left, acc)
    {right, acc} = walk.(right, acc)
    {{:logical_and, left, right, pos}, acc}
  end

  defp map_children({:logical_or, left, right, pos}, acc, walk) do
    {left, acc} = walk.(left, acc)
    {right, acc} = walk.(right, acc)
    {{:logical_or, left, right, pos}, acc}
  end

  defp map_children({:logical_not, operand, pos}, acc, walk) do
    {operand, acc} = walk.(operand, acc)
    {{:logical_not, operand, pos}, acc}
  end

  defp map_children({:list, elements, pos}, acc, walk) do
    {elements, acc} = Enum.map_reduce(elements, acc, walk)
    {{:list, elements, pos}, acc}
  end

  # The key is part of the entry, not a node: it is carried through untouched.
  defp map_children({:object, entries, pos}, acc, walk) do
    {entries, acc} =
      Enum.map_reduce(entries, acc, fn {key, value}, acc ->
        {value, acc} = walk.(value, acc)
        {{key, value}, acc}
      end)

    {{:object, entries, pos}, acc}
  end

  defp map_children({:function_call, name, args, pos}, acc, walk) do
    {args, acc} = Enum.map_reduce(args, acc, walk)
    {{:function_call, name, args, pos}, acc}
  end

  defp map_children({:bracket_access, object, key, pos}, acc, walk) do
    {object, acc} = walk.(object, acc)
    {key, acc} = walk.(key, acc)
    {{:bracket_access, object, key, pos}, acc}
  end

  defp map_children({:property_access, object, property, pos}, acc, walk) do
    {object, acc} = walk.(object, acc)
    {{:property_access, object, property, pos}, acc}
  end

  defp map_children({:cast, expression, type_name, pos}, acc, walk) do
    {expression, acc} = walk.(expression, acc)
    {{:cast, expression, type_name, pos}, acc}
  end

  defp map_children({:relative_date, duration, direction, pos}, acc, walk) do
    {duration, acc} = walk.(duration, acc)
    {{:relative_date, duration, direction, pos}, acc}
  end

  defp map_children({:assignment, location, value, pos}, acc, walk) do
    {location, acc} = walk.(location, acc)
    {value, acc} = walk.(value, acc)
    {{:assignment, location, value, pos}, acc}
  end

  defp map_children({:if, condition, then_block, else_block, pos}, acc, walk) do
    {condition, acc} = walk.(condition, acc)
    {then_block, acc} = walk.(then_block, acc)

    {else_block, acc} =
      case else_block do
        nil -> {nil, acc}
        block -> walk.(block, acc)
      end

    {{:if, condition, then_block, else_block, pos}, acc}
  end

  defp map_children({:while, condition, body, pos}, acc, walk) do
    {condition, acc} = walk.(condition, acc)
    {body, acc} = walk.(body, acc)
    {{:while, condition, body, pos}, acc}
  end

  defp map_children({:block, statements, pos}, acc, walk) do
    {statements, acc} = Enum.map_reduce(statements, acc, walk)
    {{:block, statements, pos}, acc}
  end

  defp map_children({:program, statements, pos}, acc, walk) do
    {statements, acc} = Enum.map_reduce(statements, acc, walk)
    {{:program, statements, pos}, acc}
  end
end
