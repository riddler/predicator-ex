defmodule Predicator.Simple do
  @moduledoc """
  The subset of the expression language a picklist-style editor can render.

  A structured authoring surface - the row of dropdowns that reads
  *field / operator / value*, repeated down a form - cannot render an
  arbitrary expression. It has no place to put a parenthesis, no second
  precedence level, and no way to draw `NOT`. What it can render is a flat
  list of comparisons joined by one connective, and that is exactly what this
  module names as a value.

  `t:t/0` is that value: a list of `t:clause/0`s joined by one
  `t:connective/0`. A clause is `{path, op, value}` - a field path, a
  comparison or membership operator, and a literal (or a list of literals).
  Nothing else is in the subset.

      iex> {:ok, simple} = Predicator.Simple.from_source("status == 'active' AND amount >= 500")
      iex> simple.connective
      :and
      iex> Predicator.Simple.to_source(simple)
      "status == 'active' AND amount >= 500"

  ## Outside the subset

  Everything the editor cannot draw answers `:outside` - a plain atom, not an
  error, because being outside the subset is an ordinary and expected answer
  about a perfectly valid expression. Mixed `AND`/`OR`, parentheses, `NOT`,
  arithmetic, function calls, casts, and object literals are all outside, by
  decision rather than by omission.

      iex> Predicator.Simple.from_source("status == 'active' AND (amount >= 500 OR plan == 'pro')")
      :outside

      iex> Predicator.Simple.from_source("amount + 1 >= 500")
      :outside

  `:outside` is not a judgement about the expression. `from_source/1` keeps
  `{:error, error}` for source that does not parse at all, so a caller can
  tell "this is a valid expression my editor cannot draw" from "this is not an
  expression".

      iex> {:error, error} = Predicator.Simple.from_source("status == ==")
      iex> error.position
      {1, 11}

  ## Round-tripping

  Two laws hold for every well-formed `t:t/0`, and
  `test/predicator/simple_test.exs` exercises both over an enumerated corpus:

  - `from_ast(to_ast(simple)) == {:ok, simple}`
  - `to_source(simple)` parses to `to_ast(simple)`, modulo source positions

  The second law is what constrains the subset's edges. It is why the subset
  admits `:equal_equal` but not `:eq`, admits `{:string_literal, value, style}`
  but not a bare binary `{:literal, value}`, and admits only non-negative
  numbers - in each case the excluded shape decompiles to source that parses
  back as something else, so a value carrying it could not survive a trip
  through the editor. See "What the subset admits" below.

  ## What the subset admits

  A `t:path/0` is an identifier, optionally followed by property and bracket
  accesses: `status`, `card.brand`, `cart['items']`. A bracket key is a string
  or a non-negative integer, never a computed expression.

  A `t:value/0` is one scalar or a list of scalars. A scalar is a non-negative
  integer, a boolean, a string (carrying the quote style it was written with),
  a date, a datetime, a duration, or a relative date.

  Three exclusions are deliberate and each has a reason:

  | Excluded | Why |
  |---|---|
  | Float literals | `Predicator.decompile/2` has no clause for them and raises, so `to_source/2` could not stay total (px-4jp, 2026-09-04) |
  | Negative numbers | The parser reads `-5` as a `unary` node, never as a negative literal, so a negative literal could not have come from a parse and does not survive one |
  | `:eq`, and a bare binary `{:literal, "text"}` | Both decompile to source that parses back as a different node (`:equal_equal` and `:string_literal`), breaking the source round-trip |

  ## Purity

  Nothing here evaluates, and nothing here raises on input.
  `from_ast/1` is total over every `t:Predicator.Parser.ast/0`: the answer to a
  node it does not recognise is `:outside`, never an exception.
  """

  alias Predicator.Errors.ParseError
  alias Predicator.Parser
  alias Predicator.Vocabulary

  @comparison_ops [:gt, :gte, :lt, :lte, :equal_equal, :ne, :strict_eq, :strict_ne]
  @membership_ops [:in, :contains]
  @ops @comparison_ops ++ @membership_ops
  @quote_styles [:single, :double]
  @directions [:ago, :future, :next, :last]

  @typedoc """
  The connective joining the clauses.

  `nil` for a single clause, which is joined to nothing. A `t:t/0` carrying one
  clause and a non-`nil` connective is not well-formed - see `well_formed?/1`.
  """
  @type connective :: :and | :or | nil

  @typedoc "A comparison or membership operator, spelled as the AST spells it."
  @type op ::
          :gt
          | :gte
          | :lt
          | :lte
          | :equal_equal
          | :ne
          | :strict_eq
          | :strict_ne
          | :in
          | :contains

  @typedoc """
  One step along a field path.

  The first segment of a path is always `{:root, name}` and no later segment
  ever is. A `{:key, ...}` segment is a bracket access and a `{:property, ...}`
  segment is a dotted one; the two are kept apart because `cart['items']` and
  `cart.items` are different source text for the same lookup.
  """
  @type segment ::
          {:root, binary()}
          | {:property, binary()}
          | {:key, binary() | non_neg_integer()}

  @typedoc "A field path: a root identifier and the accesses that follow it."
  @type path :: [segment(), ...]

  @typedoc """
  A single value in a clause.

  A string carries the quote style it was written with, so `plan == 'pro'`
  decompiles back to single quotes rather than switching house style under the
  author.
  """
  @type scalar ::
          {:integer, non_neg_integer()}
          | {:boolean, boolean()}
          | {:string, binary(), :single | :double}
          | {:date, Date.t()}
          | {:datetime, DateTime.t()}
          | {:duration, [{non_neg_integer(), binary()}, ...]}
          | {:relative_date, [{non_neg_integer(), binary()}, ...], :ago | :future | :next | :last}

  @typedoc "The right-hand side of a clause: one scalar, or a list of them."
  @type value :: scalar() | {:list, [scalar()]}

  @typedoc "One row of the editor: a field path, an operator, and a value."
  @type clause :: {path(), op(), value()}

  @typedoc """
  The subset value: clauses joined by one connective.

  `:clauses` is never empty. `:connective` is `nil` exactly when there is one
  clause.
  """
  @type t :: %__MODULE__{connective: connective(), clauses: [clause(), ...]}

  @enforce_keys [:connective, :clauses]
  defstruct [:connective, :clauses]

  @doc """
  Reads a `t:t/0` out of an AST, or answers `:outside`.

  Total: every `t:Predicator.Parser.ast/0` gets an answer, and an AST outside
  the subset gets `:outside` rather than an exception. Source positions are
  ignored, so a hand-built node carrying `nil` reads the same as a parsed one.

  ## Examples

      iex> {:ok, ast} = Predicator.parse("amount >= 500")
      iex> Predicator.Simple.from_ast(ast)
      {:ok, %Predicator.Simple{connective: nil, clauses: [{[root: "amount"], :gte, {:integer, 500}}]}}

      iex> {:ok, ast} = Predicator.parse("NOT plan == 'pro'")
      iex> Predicator.Simple.from_ast(ast)
      :outside
  """
  @spec from_ast(Parser.ast()) :: {:ok, t()} | :outside
  def from_ast({:logical_and, _left, _right, _pos} = ast), do: joined(:and, ast)
  def from_ast({:logical_or, _left, _right, _pos} = ast), do: joined(:or, ast)

  def from_ast(ast) do
    case clause_from_ast(ast) do
      {:ok, clause} -> {:ok, %__MODULE__{connective: nil, clauses: [clause]}}
      :outside -> :outside
    end
  end

  @doc """
  Parses source and reads a `t:t/0` out of it.

  Adds one arm to `from_ast/1`'s two: `{:error, error}` for source that does
  not parse, carrying a `t:Predicator.Errors.ParseError.t/0` with the position
  and span of the failure (ADR-0015). The three arms answer three different
  questions - in the subset, a valid expression outside it, and not an
  expression - and a caller that collapses any two of them loses information
  an editor needs.

  ## Examples

      iex> Predicator.Simple.from_source("step in ['payment', 'review']")
      {:ok,
       %Predicator.Simple{
         connective: nil,
         clauses: [{[root: "step"], :in, {:list, [{:string, "payment", :single}, {:string, "review", :single}]}}]
       }}

      iex> Predicator.Simple.from_source("len(step) > 0")
      :outside

      iex> {:error, %Predicator.Errors.ParseError{}} = Predicator.Simple.from_source("step in [")
      iex> :ok
      :ok
  """
  @spec from_source(binary()) :: {:ok, t()} | :outside | {:error, ParseError.t()}
  def from_source(source) when is_binary(source) do
    case Predicator.parse(source) do
      {:ok, ast} ->
        from_ast(ast)

      {:error, message, line, column, span} ->
        {:error, ParseError.new(message, line, column, span)}
    end
  end

  @doc """
  Builds the AST for a `t:t/0`.

  Every node carries `nil` in its trailing position slot - the value records
  what the expression means, not where it was written. Clauses are joined
  left-associatively, which is the shape `Predicator.Parser.parse/2` produces
  for the same source.

  Expects a well-formed value; see `well_formed?/1`.

  ## Examples

      iex> {:ok, simple} = Predicator.Simple.from_source("plan == 'pro'")
      iex> Predicator.Simple.to_ast(simple)
      {:comparison, :equal_equal, {:identifier, "plan", nil}, {:string_literal, "pro", :single, nil}, nil}
  """
  @spec to_ast(t()) :: Parser.ast()
  def to_ast(%__MODULE__{connective: connective, clauses: [first | rest]}) do
    tag = if connective == :or, do: :logical_or, else: :logical_and

    Enum.reduce(rest, clause_to_ast(first), fn clause, acc ->
      {tag, acc, clause_to_ast(clause), nil}
    end)
  end

  @doc """
  Renders a `t:t/0` back to source, through `Predicator.decompile/2`.

  `opts` are that function's formatting options - `:parentheses` and
  `:spacing` - so a caller that renders the rest of its expressions one way
  renders these the same way.

  ## Examples

      iex> {:ok, simple} = Predicator.Simple.from_source("status == 'active' AND amount >= 500")
      iex> Predicator.Simple.to_source(simple)
      "status == 'active' AND amount >= 500"

      iex> {:ok, simple} = Predicator.Simple.from_source("plan == 'pro'")
      iex> Predicator.Simple.to_source(simple, spacing: :compact)
      "plan=='pro'"
  """
  @spec to_source(t(), keyword()) :: binary()
  def to_source(%__MODULE__{} = simple, opts \\ []) do
    simple |> to_ast() |> Predicator.decompile(opts)
  end

  @doc """
  Answers whether a value satisfies the invariants `to_ast/1` expects.

  Every value `from_ast/1` returns is well-formed; this function is for
  values a caller assembled itself - an editor building one from form state.
  The invariants are that `:clauses` is a non-empty list of structurally valid
  clauses, and that `:connective` is `nil` exactly when there is one clause.

  ## Examples

      iex> {:ok, simple} = Predicator.Simple.from_source("amount >= 500")
      iex> Predicator.Simple.well_formed?(simple)
      true

      iex> Predicator.Simple.well_formed?(%Predicator.Simple{connective: :and, clauses: [{[root: "amount"], :gte, {:integer, 500}}]})
      false
  """
  @spec well_formed?(term()) :: boolean()
  def well_formed?(%__MODULE__{connective: connective, clauses: clauses})
      when is_list(clauses) and clauses != [] do
    connective_ok? =
      case clauses do
        [_one] -> connective == nil
        _many -> connective in [:and, :or]
      end

    connective_ok? and Enum.all?(clauses, &clause?/1)
  end

  def well_formed?(_other), do: false

  @doc """
  The duration units a `t:scalar/0` duration may use.

  Read from `Predicator.Vocabulary`, which is the grammar's single enumerated
  source (px-15q), so a unit added to the lexer reaches this subset without a
  second list to update by hand.

  ## Examples

      iex> "d" in Predicator.Simple.duration_units()
      true
  """
  @spec duration_units() :: [binary()]
  def duration_units do
    :duration_unit |> Vocabulary.by_category() |> Enum.map(& &1.lexeme)
  end

  # -- from_ast ---------------------------------------------------------------

  @spec joined(:and | :or, Parser.ast()) :: {:ok, t()} | :outside
  defp joined(connective, ast) do
    tag = if connective == :or, do: :logical_or, else: :logical_and

    tag
    |> flatten(ast)
    |> reduce_clauses()
    |> case do
      {:ok, clauses} -> {:ok, %__MODULE__{connective: connective, clauses: clauses}}
      :outside -> :outside
    end
  end

  @spec flatten(atom(), Parser.ast()) :: [Parser.ast()]
  defp flatten(tag, {tag, left, right, _pos}), do: flatten(tag, left) ++ flatten(tag, right)
  defp flatten(_tag, node), do: [node]

  @spec reduce_clauses([Parser.ast()]) :: {:ok, [clause()]} | :outside
  defp reduce_clauses(nodes) do
    Enum.reduce_while(nodes, {:ok, []}, fn node, {:ok, acc} ->
      case clause_from_ast(node) do
        {:ok, clause} -> {:cont, {:ok, [clause | acc]}}
        :outside -> {:halt, :outside}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      :outside -> :outside
    end
  end

  @spec clause_from_ast(Parser.ast()) :: {:ok, clause()} | :outside
  defp clause_from_ast({:comparison, op, left, right, _pos}) when op in @comparison_ops,
    do: build_clause(left, op, right)

  defp clause_from_ast({:membership, op, left, right, _pos}) when op in @membership_ops,
    do: build_clause(left, op, right)

  defp clause_from_ast(_other), do: :outside

  @spec build_clause(Parser.ast(), op(), Parser.ast()) :: {:ok, clause()} | :outside
  defp build_clause(left, op, right) do
    with {:ok, path} <- path_from_ast(left),
         {:ok, value} <- value_from_ast(right) do
      {:ok, {path, op, value}}
    end
  end

  @spec path_from_ast(Parser.ast()) :: {:ok, path()} | :outside
  defp path_from_ast({:identifier, name, _pos}) when is_binary(name), do: {:ok, [{:root, name}]}

  defp path_from_ast({:property_access, target, property, _pos}) when is_binary(property) do
    with {:ok, path} <- path_from_ast(target), do: {:ok, path ++ [{:property, property}]}
  end

  defp path_from_ast({:bracket_access, target, key, _pos}) do
    with {:ok, path} <- path_from_ast(target),
         {:ok, segment} <- key_from_ast(key) do
      {:ok, path ++ [segment]}
    end
  end

  defp path_from_ast(_other), do: :outside

  @spec key_from_ast(Parser.ast()) :: {:ok, segment()} | :outside
  defp key_from_ast({:string_literal, value, style, _pos})
       when is_binary(value) and style in @quote_styles,
       do: {:ok, {:key, value}}

  defp key_from_ast({:literal, value, _pos}) when is_integer(value) and value >= 0,
    do: {:ok, {:key, value}}

  defp key_from_ast(_other), do: :outside

  @spec value_from_ast(Parser.ast()) :: {:ok, value()} | :outside
  defp value_from_ast({:list, elements, _pos}) when is_list(elements) do
    Enum.reduce_while(elements, {:ok, []}, fn element, {:ok, acc} ->
      case scalar_from_ast(element) do
        {:ok, scalar} -> {:cont, {:ok, [scalar | acc]}}
        :outside -> {:halt, :outside}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, {:list, Enum.reverse(reversed)}}
      :outside -> :outside
    end
  end

  defp value_from_ast(node), do: scalar_from_ast(node)

  @spec scalar_from_ast(Parser.ast()) :: {:ok, scalar()} | :outside
  defp scalar_from_ast({:literal, value, _pos}) when is_boolean(value),
    do: {:ok, {:boolean, value}}

  defp scalar_from_ast({:literal, value, _pos}) when is_integer(value) and value >= 0,
    do: {:ok, {:integer, value}}

  defp scalar_from_ast({:literal, %Date{} = value, _pos}), do: {:ok, {:date, value}}
  defp scalar_from_ast({:literal, %DateTime{} = value, _pos}), do: {:ok, {:datetime, value}}

  defp scalar_from_ast({:string_literal, value, style, _pos})
       when is_binary(value) and style in @quote_styles,
       do: {:ok, {:string, value, style}}

  defp scalar_from_ast({:duration, units, _pos}) do
    if units?(units), do: {:ok, {:duration, units}}, else: :outside
  end

  defp scalar_from_ast({:relative_date, {:duration, units, _dpos}, direction, _pos})
       when direction in @directions do
    if units?(units), do: {:ok, {:relative_date, units, direction}}, else: :outside
  end

  defp scalar_from_ast(_other), do: :outside

  # -- to_ast -----------------------------------------------------------------

  @spec clause_to_ast(clause()) :: Parser.ast()
  defp clause_to_ast({path, op, value}) when op in @membership_ops,
    do: {:membership, op, path_to_ast(path), value_to_ast(value), nil}

  defp clause_to_ast({path, op, value}),
    do: {:comparison, op, path_to_ast(path), value_to_ast(value), nil}

  @spec path_to_ast(path()) :: Parser.ast()
  defp path_to_ast([{:root, name} | rest]) do
    Enum.reduce(rest, {:identifier, name, nil}, fn
      {:property, property}, acc ->
        {:property_access, acc, property, nil}

      {:key, key}, acc when is_binary(key) ->
        {:bracket_access, acc, {:string_literal, key, :single, nil}, nil}

      {:key, key}, acc ->
        {:bracket_access, acc, {:literal, key, nil}, nil}
    end)
  end

  @spec value_to_ast(value()) :: Parser.ast()
  defp value_to_ast({:list, scalars}), do: {:list, Enum.map(scalars, &scalar_to_ast/1), nil}
  defp value_to_ast(scalar), do: scalar_to_ast(scalar)

  @spec scalar_to_ast(scalar()) :: Parser.ast()
  defp scalar_to_ast({:integer, value}), do: {:literal, value, nil}
  defp scalar_to_ast({:boolean, value}), do: {:literal, value, nil}
  defp scalar_to_ast({:date, value}), do: {:literal, value, nil}
  defp scalar_to_ast({:datetime, value}), do: {:literal, value, nil}
  defp scalar_to_ast({:string, value, style}), do: {:string_literal, value, style, nil}
  defp scalar_to_ast({:duration, units}), do: {:duration, units, nil}

  defp scalar_to_ast({:relative_date, units, direction}),
    do: {:relative_date, {:duration, units, nil}, direction, nil}

  # -- validation -------------------------------------------------------------

  @spec clause?(term()) :: boolean()
  defp clause?({path, op, value}) when op in @ops, do: path?(path) and value?(value)
  defp clause?(_other), do: false

  @spec path?(term()) :: boolean()
  defp path?([{:root, name} | rest]) when is_binary(name), do: Enum.all?(rest, &segment?/1)
  defp path?(_other), do: false

  @spec segment?(term()) :: boolean()
  defp segment?({:property, property}), do: is_binary(property)
  defp segment?({:key, key}) when is_binary(key), do: true
  defp segment?({:key, key}) when is_integer(key), do: key >= 0
  defp segment?(_other), do: false

  @spec value?(term()) :: boolean()
  defp value?({:list, scalars}) when is_list(scalars), do: Enum.all?(scalars, &scalar?/1)
  defp value?(other), do: scalar?(other)

  @spec scalar?(term()) :: boolean()
  defp scalar?({:integer, value}) when is_integer(value), do: value >= 0
  defp scalar?({:boolean, value}), do: is_boolean(value)
  defp scalar?({:string, value, style}) when style in @quote_styles, do: is_binary(value)
  defp scalar?({:date, %Date{}}), do: true
  defp scalar?({:datetime, %DateTime{}}), do: true
  defp scalar?({:duration, units}), do: units?(units)

  defp scalar?({:relative_date, units, direction}) when direction in @directions,
    do: units?(units)

  defp scalar?(_other), do: false

  @spec units?(term()) :: boolean()
  defp units?(units) when is_list(units) and units != [] do
    known = duration_units()

    Enum.all?(units, fn
      {amount, unit} when is_integer(amount) and is_binary(unit) -> amount >= 0 and unit in known
      _other -> false
    end)
  end

  defp units?(_other), do: false
end
