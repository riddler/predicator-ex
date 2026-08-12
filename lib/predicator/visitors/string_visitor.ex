defmodule Predicator.Visitors.StringVisitor do
  @moduledoc """
  Visitor that converts AST nodes back to string expressions.

  This visitor implements the inverse of parsing - it takes an Abstract Syntax Tree
  and generates a readable string representation. This is useful for debugging,
  documentation, and round-trip testing.

  A node's trailing slot is ignored: rendering a parsed AST and rendering the
  same tree with `nil` in every slot produce identical strings. A caller
  hand-building an AST supplies `nil` there - the slot is part of the node
  shape, not an add-on.

  ## Examples

      iex> ast = {:literal, 42, nil}
      iex> Predicator.Visitors.StringVisitor.visit(ast, [])
      "42"

      iex> ast = {:identifier, "score", nil}
      iex> Predicator.Visitors.StringVisitor.visit(ast, [])
      "score"

      iex> ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      iex> Predicator.Visitors.StringVisitor.visit(ast, [])
      "score > 85"

      iex> {:ok, ast} = Predicator.parse(~s(name == "John"))
      iex> Predicator.Visitors.StringVisitor.visit(ast, [])
      ~s(name == "John")

      iex> ast = {:logical_and, {:literal, true, nil}, {:literal, false, nil}, nil}
      iex> Predicator.Visitors.StringVisitor.visit(ast, [])
      "true AND false"

      iex> ast = {:logical_not, {:literal, true, nil}, nil}
      iex> Predicator.Visitors.StringVisitor.visit(ast, [])
      "NOT true"

      iex> ast = {:function_call, "len", [{:identifier, "name", nil}], nil}
      iex> Predicator.Visitors.StringVisitor.visit(ast, [])
      "len(name)"

      iex> ast = {:cast, {:identifier, "score", nil}, "integer", nil}
      iex> Predicator.Visitors.StringVisitor.visit(ast, [])
      "score::integer"

      iex> ast = {:object, [], nil}
      iex> Predicator.Visitors.StringVisitor.visit(ast, [])
      "{}"

      iex> {:ok, ast} = Predicator.parse(~s({name: "John"}))
      iex> Predicator.Visitors.StringVisitor.visit(ast, [])
      ~s({name: "John"})

      iex> {:ok, ast} = Predicator.parse(~s({"first name": "John"}))
      iex> Predicator.Visitors.StringVisitor.visit(ast, [])
      ~s({"first name": "John"})
  """

  @behaviour Predicator.Visitor

  alias Predicator.Parser

  # Precedence levels, loosest to tightest, matching the grammar in
  # docs/architecture.md's "Grammar with Operator Precedence" section:
  #
  #   logical_or < logical_and < logical_not < comparison/membership
  #     < addition < multiplication < unary < postfix/primary
  #
  # `:minimal` parentheses mode uses these to decide whether a child
  # subexpression needs wrapping: a child binds looser than its parent, or
  # ties with it in a position where associativity would otherwise regroup
  # it (see `maybe_wrap_child/4`).
  @level_logical_or 1
  @level_logical_and 2
  @level_logical_not 3
  @level_comparison 4
  @level_addition 5
  @level_multiplication 6
  @level_unary 7
  @level_primary 8
  @level_statement 0

  @doc """
  Visits an AST node and returns its string representation.

  ## Parameters

  - `ast_node` - The AST node to convert to a string
  - `opts` - Optional visitor options:
    - `:parentheses` - `:minimal` (default) | `:explicit` | `:none`
    - `:spacing` - `:normal` (default) | `:compact` | `:verbose`

  ## Returns

  String representation of the AST node

  ## Options

  - `:parentheses` controls parentheses generation:
    - `:minimal` - only add parentheses when necessary for precedence
    - `:explicit` - add parentheses around all comparisons
    - `:none` - never add parentheses (may change meaning!)

  - `:spacing` controls whitespace:
    - `:normal` - standard spacing: "score > 85"
    - `:compact` - minimal spacing: "score>85"
    - `:verbose` - extra spacing: "score  >  85"
  """
  @impl Predicator.Visitor
  @spec visit(Parser.visitable(), keyword()) :: binary()
  def visit(ast_node, opts \\ []) do
    do_visit(ast_node, opts)
  end

  @spec do_visit(Parser.ast() | Parser.program() | Parser.statement(), keyword()) :: binary()
  defp do_visit(ast_node, opts)

  defp do_visit({:literal, value, _position}, _opts) when is_integer(value) do
    Integer.to_string(value)
  end

  defp do_visit({:literal, value, _position}, _opts) when is_boolean(value) do
    Atom.to_string(value)
  end

  defp do_visit({:literal, value, _position}, _opts) when is_binary(value) do
    # For backwards compatibility with older AST nodes that still use {:literal, string}
    # Default to double quotes
    escaped = String.replace(value, "\"", "\\\"")
    "\"#{escaped}\""
  end

  defp do_visit({:string_literal, value, quote_type, _position}, _opts) when is_binary(value) do
    # Use the original quote type to preserve round-trip accuracy
    case quote_type do
      :double ->
        # Escape double quotes and wrap in double quotes
        escaped = String.replace(value, "\"", "\\\"")
        "\"#{escaped}\""

      :single ->
        # Escape single quotes and wrap in single quotes
        escaped = String.replace(value, "'", "\\'")
        "'#{escaped}'"
    end
  end

  defp do_visit({:literal, value, position}, opts) when is_list(value) do
    # Handle list literals (future extension)
    items = Enum.map(value, fn item -> do_visit({:literal, item, position}, opts) end)
    "[#{Enum.join(items, ", ")}]"
  end

  defp do_visit({:literal, %Date{} = value, _position}, _opts) do
    "##{Date.to_iso8601(value)}#"
  end

  defp do_visit({:literal, %DateTime{} = value, _position}, _opts) do
    "##{DateTime.to_iso8601(value)}#"
  end

  defp do_visit({:identifier, name, _position}, _opts) when is_binary(name) do
    name
  end

  defp do_visit({:comparison, op, left, right, _position}, opts) do
    format_binary(left, right, format_operator(op), opts, @level_comparison, :none)
  end

  defp do_visit({:logical_and, left, right, _position}, opts) do
    format_binary(left, right, "AND", opts, @level_logical_and, :left)
  end

  defp do_visit({:logical_or, left, right, _position}, opts) do
    format_binary(left, right, "OR", opts, @level_logical_or, :left)
  end

  defp do_visit({:logical_not, operand, _position}, opts) do
    spacing = get_spacing(opts)
    mode = get_parentheses_mode(opts)
    operand_str = maybe_wrap_child(do_visit(operand, opts), operand, @level_logical_not, mode)

    case mode do
      :explicit -> "(NOT#{spacing}#{operand_str})"
      _other -> "NOT#{spacing}#{operand_str}"
    end
  end

  defp do_visit({:arithmetic, op, left, right, _position}, opts) do
    {level, assoc} = arithmetic_precedence(op)
    format_binary(left, right, format_operator(op), opts, level, assoc)
  end

  defp do_visit({:unary, op, operand, _position}, opts) do
    mode = get_parentheses_mode(opts)
    operand_str = maybe_wrap_child(do_visit(operand, opts), operand, @level_unary, mode)
    op_str = format_operator(op)

    # Unary operators typically don't use spacing
    "#{op_str}#{operand_str}"
  end

  defp do_visit({:bracket_access, object, key, _position}, opts) do
    object_str = do_visit(object, opts)
    key_str = do_visit(key, opts)

    # Bracket access format: object[key]
    "#{object_str}[#{key_str}]"
  end

  defp do_visit({:property_access, object, property, _position}, opts) do
    object_str = do_visit(object, opts)

    # Property access format: object.property
    "#{object_str}.#{property}"
  end

  defp do_visit({:cast, expression, type_name, _position}, opts) do
    mode = get_parentheses_mode(opts)

    # A cast binds at the postfix/primary level, same as property and bracket
    # access above: the operand needs parens whenever it binds looser (e.g.
    # `(1 + 2)::string`, `(-1)::integer`, `(a AND b)::boolean`), and a chain
    # of casts (`x::integer::string`) needs none since each cast is itself
    # primary-level.
    expression_str =
      maybe_wrap_child(do_visit(expression, opts), expression, @level_primary, mode)

    "#{expression_str}::#{type_name}"
  end

  defp do_visit({:list, elements, _position}, opts) do
    element_strings = Enum.map(elements, fn element -> do_visit(element, opts) end)
    "[#{Enum.join(element_strings, ", ")}]"
  end

  defp do_visit({:membership, op, left, right, _position}, opts) do
    format_binary(left, right, format_membership_operator(op), opts, @level_comparison, :none)
  end

  defp do_visit({:function_call, function_name, arguments, _position}, opts) do
    arg_strings = Enum.map(arguments, fn arg -> do_visit(arg, opts) end)
    args_str = Enum.join(arg_strings, ", ")
    "#{function_name}(#{args_str})"
  end

  defp do_visit({:object, entries, _position}, opts) do
    case entries do
      [] ->
        "{}"

      _non_empty_entries ->
        entry_strings =
          Enum.map(entries, fn {key, value} ->
            key_str = format_object_key(key)
            value_str = do_visit(value, opts)
            "#{key_str}: #{value_str}"
          end)

        entries_str = Enum.join(entry_strings, ", ")
        "{#{entries_str}}"
    end
  end

  defp do_visit({:duration, units, _position}, _opts) do
    unit_strings = Enum.map(units, fn {value, unit} -> "#{value}#{unit}" end)
    Enum.join(unit_strings, "")
  end

  defp do_visit({:relative_date, duration_ast, direction, _position}, opts) do
    duration_str = do_visit(duration_ast, opts)

    case direction do
      :ago -> "#{duration_str} ago"
      :future -> "#{duration_str} from now"
      :next -> "next #{duration_str}"
      :last -> "last #{duration_str}"
    end
  end

  defp do_visit({:program, statements, _position}, opts) do
    Enum.map_join(statements, "; ", &do_visit(&1, opts))
  end

  defp do_visit({:assignment, lhs, rhs, _position}, opts) do
    "#{do_visit(lhs, opts)} = #{do_visit(rhs, opts)}"
  end

  # Helper functions

  @spec format_operator(
          Parser.comparison_op()
          | Parser.arithmetic_op()
          | Parser.unary_op()
        ) :: binary()
  defp format_operator(:gt), do: ">"
  defp format_operator(:lt), do: "<"
  defp format_operator(:gte), do: ">="
  defp format_operator(:lte), do: "<="
  defp format_operator(:eq), do: "=="
  defp format_operator(:equal_equal), do: "=="
  defp format_operator(:ne), do: "!="
  defp format_operator(:strict_eq), do: "==="
  defp format_operator(:strict_ne), do: "!=="
  defp format_operator(:add), do: "+"
  defp format_operator(:subtract), do: "-"
  defp format_operator(:multiply), do: "*"
  defp format_operator(:divide), do: "/"
  defp format_operator(:modulo), do: "%"
  defp format_operator(:minus), do: "-"
  defp format_operator(:bang), do: "!"

  @spec format_membership_operator(Parser.membership_op()) :: binary()
  defp format_membership_operator(:in), do: "IN"
  defp format_membership_operator(:contains), do: "CONTAINS"

  # Renders a binary infix node ("left <op_str> right"), wrapping either
  # child in parentheses when :minimal mode requires it for precedence, and
  # wrapping the whole result when mode is :explicit. :none never wraps -
  # unchanged from before this module tracked precedence.
  @spec format_binary(
          Parser.ast(),
          Parser.ast(),
          binary(),
          keyword(),
          non_neg_integer(),
          :left | :none
        ) ::
          binary()
  defp format_binary(left, right, op_str, opts, level, assoc) do
    spacing = get_spacing(opts)
    mode = get_parentheses_mode(opts)

    left_str = maybe_wrap_child(do_visit(left, opts), left, level, assoc, :left, mode)
    right_str = maybe_wrap_child(do_visit(right, opts), right, level, assoc, :right, mode)

    joined = "#{left_str}#{spacing}#{op_str}#{spacing}#{right_str}"

    case mode do
      :explicit -> "(#{joined})"
      _other -> joined
    end
  end

  @spec arithmetic_precedence(Parser.arithmetic_op()) :: {non_neg_integer(), :left}
  defp arithmetic_precedence(op) when op in [:add, :subtract], do: {@level_addition, :left}
  defp arithmetic_precedence(_op), do: {@level_multiplication, :left}

  # Whether `child` needs parentheses when rendered at `position` (:left or
  # :right) under a parent node with precedence `level` and associativity
  # `assoc` (`:left` for the left-associative binary operators, `:none` for
  # the non-associative comparison/membership level). Only :minimal mode
  # wraps; :explicit and :none leave the child's own rendering untouched -
  # :explicit already self-wraps recursively, :none never wraps at all.
  @spec maybe_wrap_child(
          binary(),
          Parser.ast() | Parser.statement(),
          non_neg_integer(),
          :left | :none,
          :left | :right,
          :minimal | :explicit | :none
        ) :: binary()
  defp maybe_wrap_child(str, child, level, assoc, position, :minimal) do
    child_level = precedence(child)
    looser? = child_level < level
    ties_and_regroups? = child_level == level and (assoc == :none or position == :right)

    if looser? or ties_and_regroups? do
      "(#{str})"
    else
      str
    end
  end

  defp maybe_wrap_child(str, _child, _level, _assoc, _position, _other_mode), do: str

  @spec maybe_wrap_child(
          binary(),
          Parser.ast() | Parser.statement(),
          non_neg_integer(),
          :minimal | :explicit | :none
        ) :: binary()
  defp maybe_wrap_child(str, child, level, mode),
    do: maybe_wrap_child(str, child, level, :left, :left, mode)

  # The precedence level of a node, for comparison against a prospective
  # parent's level (see `maybe_wrap_child/6`). Every clause in `do_visit/2`
  # has a corresponding clause here. Atoms and postfix/primary forms bind
  # tightest and never need parentheses; `:program` and `:assignment` are
  # statement-layer nodes that are never wrapped by a parent, so their level
  # is nominal.
  @spec precedence(Parser.ast() | Parser.program() | Parser.statement()) :: non_neg_integer()
  defp precedence({:logical_or, _left, _right, _position}), do: @level_logical_or
  defp precedence({:logical_and, _left, _right, _position}), do: @level_logical_and
  defp precedence({:logical_not, _operand, _position}), do: @level_logical_not
  defp precedence({:comparison, _op, _left, _right, _position}), do: @level_comparison
  defp precedence({:membership, _op, _left, _right, _position}), do: @level_comparison

  defp precedence({:arithmetic, op, _left, _right, _position}) do
    {level, _assoc} = arithmetic_precedence(op)
    level
  end

  defp precedence({:unary, _op, _operand, _position}), do: @level_unary
  defp precedence({:program, _statements, _position}), do: @level_statement
  defp precedence({:assignment, _lhs, _rhs, _position}), do: @level_statement
  defp precedence(_atom_or_postfix_node), do: @level_primary

  @spec get_spacing(keyword()) :: binary()
  defp get_spacing(opts) do
    case Keyword.get(opts, :spacing, :normal) do
      :compact -> ""
      :verbose -> "  "
      :normal -> " "
    end
  end

  @spec get_parentheses_mode(keyword()) :: :minimal | :explicit | :none
  defp get_parentheses_mode(opts) do
    Keyword.get(opts, :parentheses, :minimal)
  end

  @spec format_object_key(Parser.object_key()) :: binary()
  defp format_object_key({:object_key, value, :identifier, _position}), do: value

  defp format_object_key({:object_key, value, :double, _position}),
    do: ~s("#{String.replace(value, "\"", "\\\"")}")

  defp format_object_key({:object_key, value, :single, _position}),
    do: ~s('#{String.replace(value, "'", "\\'")}')
end
