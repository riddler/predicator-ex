defmodule Predicator.Parser do
  # Disable credo checks that are inherent to recursive descent parsing
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity

  @moduledoc """
  Recursive descent parser for predicator expressions.

  The parser converts a stream of tokens from the lexer into an Abstract Syntax Tree (AST)
  with comprehensive error reporting including exact position information.

  ## Grammar

  The parser implements this grammar with proper operator precedence:

      expression   → logical_or
      logical_or   → logical_and ( "OR" | "||" logical_and )*
      logical_and  → logical_not ( "AND" | "&&" logical_not )*
      logical_not  → "NOT" | "!" logical_not | comparison
      comparison   → addition ( ( ">" | "<" | ">=" | "<=" | "=" (deprecated) | "==" | "!=" | "===" | "!==" | "in" | "contains" ) addition )?
      addition     → multiplication ( ( "+" | "-" ) multiplication )*
      multiplication → unary ( ( "*" | "/" | "%" ) unary )*
      unary        → ( "-" | "!" ) unary | postfix
      postfix      → primary ( "[" expression "]" | "." IDENTIFIER )*
      primary      → NUMBER | FLOAT | STRING | BOOLEAN | DATE | DATETIME | IDENTIFIER | duration | relative_date | function_call | list | object | "(" expression ")"
      function_call → FUNCTION_NAME "(" ( expression ( "," expression )* )? ")"
      list         → "[" ( expression ( "," expression )* )? "]"
      object       → "{" ( object_entry ( "," object_entry )* )? "}"
      object_entry → object_key ":" expression
      object_key   → IDENTIFIER | STRING
      duration     → NUMBER UNIT+
      relative_date → duration "ago" | duration "from" "now" | "next" duration | "last" duration

  > #### Deprecated: `=` as equality {: .warning}
  >
  > Using `=` as an equality operator is deprecated. It still parses and still
  > compiles to `["compare", "EQ"]`, but parsing one emits a deprecation
  > warning, and Predicator 4.0 makes expression-position `=` a parse error.
  > Use `==` instead.

  ## Source positions

  Every AST node carries a trailing `{line, column}` giving the 1-based position
  of the token that defines it. Leaves point at their own token; operators point
  at the operator token, so the `arithmetic` node in `a * true` reports column 3.

  Use `strip_positions/1` to recover the position-free shape Predicator 3.6
  produced, and `ensure_positions/1` to bring a position-free AST up to the
  shape the visitors expect.

  ## Examples

      iex> {:ok, tokens} = Predicator.Lexer.tokenize("score > 85")
      iex> Predicator.Parser.parse(tokens)
      {:ok, {:comparison, :gt, {:identifier, "score", {1, 1}}, {:literal, 85, {1, 9}}, {1, 7}}}

      iex> {:ok, tokens} = Predicator.Lexer.tokenize("(age >= 18)")
      iex> Predicator.Parser.parse(tokens)
      {:ok, {:comparison, :gte, {:identifier, "age", {1, 2}}, {:literal, 18, {1, 9}}, {1, 6}}}

      iex> {:ok, tokens} = Predicator.Lexer.tokenize("score > 85 AND age >= 18")
      iex> Predicator.Parser.parse(tokens)
      {:ok, {:logical_and, {:comparison, :gt, {:identifier, "score", {1, 1}}, {:literal, 85, {1, 9}}, {1, 7}}, {:comparison, :gte, {:identifier, "age", {1, 16}}, {:literal, 18, {1, 23}}, {1, 20}}, {1, 12}}}
  """

  alias Predicator.Lexer

  require Logger

  @typedoc """
  A value that can appear in literals.
  """
  @type value ::
          boolean()
          | integer()
          | binary()
          | [value()]
          | Date.t()
          | DateTime.t()
          | Predicator.Types.duration()

  @typedoc """
  Abstract Syntax Tree node types.

  Every node carries a trailing source position - the `{line, column}` of the
  token that defines it, or `nil` for a node built by a caller rather than
  parsed.

  - `{:literal, value, pos}` - A literal value (number, boolean, list, date, datetime, duration)
  - `{:string_literal, value, quote_type, pos}` - A string literal with quote type information
  - `{:identifier, name, pos}` - A variable reference
  - `{:comparison, operator, left, right, pos}` - A comparison expression (including equality)
  - `{:arithmetic, operator, left, right, pos}` - An arithmetic expression (+, -, *, /, %)
  - `{:unary, operator, operand, pos}` - A unary expression (-, !)
  - `{:logical_and, left, right, pos}` - A logical AND expression
  - `{:logical_or, left, right, pos}` - A logical OR expression
  - `{:logical_not, operand, pos}` - A logical NOT expression
  - `{:list, elements, pos}` - A list literal
  - `{:object, entries, pos}` - An object literal with key-value pairs
  - `{:membership, operator, left, right, pos}` - A membership operation (in/contains)
  - `{:function_call, name, arguments, pos}` - A function call with arguments
  - `{:bracket_access, object, key, pos}` - A bracket access expression (obj[key])
  - `{:property_access, object, property, pos}` - A property access expression (obj.prop)
  - `{:duration, units, pos}` - A duration literal (e.g., 3d8h)
  - `{:relative_date, duration, direction, pos}` - A relative date expression (e.g., 3d ago, next 2w)
  """
  @type ast ::
          {:literal, value(), position()}
          | {:string_literal, binary(), :double | :single, position()}
          | {:identifier, binary(), position()}
          | {:comparison, comparison_op(), ast(), ast(), position()}
          | {:arithmetic, arithmetic_op(), ast(), ast(), position()}
          | {:unary, unary_op(), ast(), position()}
          | {:membership, membership_op(), ast(), ast(), position()}
          | {:logical_and, ast(), ast(), position()}
          | {:logical_or, ast(), ast(), position()}
          | {:logical_not, ast(), position()}
          | {:list, [ast()], position()}
          | {:object, [object_entry()], position()}
          | {:function_call, binary(), [ast()], position()}
          | {:bracket_access, ast(), ast(), position()}
          | {:property_access, ast(), binary(), position()}
          | {:duration, [{integer(), binary()}], position()}
          | {:relative_date, ast(), relative_direction(), position()}

  @typedoc """
  A node's source position, or `nil` when the node was not produced by the
  parser.
  """
  @type position :: Predicator.Types.position() | nil

  @typedoc """
  The position-free AST shape Predicator 3.6 produced, as returned by
  `strip_positions/1`. The visitors still consume this shape; they move to
  `t:ast/0` when they learn to carry positions.
  """
  @type bare_ast ::
          {:literal, value()}
          | {:string_literal, binary(), :double | :single}
          | {:identifier, binary()}
          | {:comparison, comparison_op(), bare_ast(), bare_ast()}
          | {:arithmetic, arithmetic_op(), bare_ast(), bare_ast()}
          | {:unary, unary_op(), bare_ast()}
          | {:membership, membership_op(), bare_ast(), bare_ast()}
          | {:logical_and, bare_ast(), bare_ast()}
          | {:logical_or, bare_ast(), bare_ast()}
          | {:logical_not, bare_ast()}
          | {:list, [bare_ast()]}
          | {:object, [{bare_object_key(), bare_ast()}]}
          | {:function_call, binary(), [bare_ast()]}
          | {:bracket_access, bare_ast(), bare_ast()}
          | {:property_access, bare_ast(), binary()}
          | {:duration, [{integer(), binary()}]}
          | {:relative_date, bare_ast(), relative_direction()}

  @typedoc """
  A position-free object key, as returned by `strip_positions/1`.
  """
  @type bare_object_key :: {:identifier, binary()} | {:string_literal, binary()}

  @typedoc """
  An object entry (key-value pair) in an object literal.

  The key can be either an identifier or a string literal.
  """
  @type object_entry :: {object_key(), ast()}

  @typedoc """
  A key in an object literal - either an identifier or string literal.
  """
  @type object_key ::
          {:identifier, binary(), position()} | {:string_literal, binary(), position()}

  @typedoc """
  Comparison operators in the AST.
  """
  @type comparison_op ::
          :gt | :lt | :gte | :lte | :eq | :equal_equal | :ne | :strict_eq | :strict_ne

  @typedoc """
  Arithmetic operators in the AST.
  """
  @type arithmetic_op :: :add | :subtract | :multiply | :divide | :modulo

  @typedoc """
  Unary operators in the AST.
  """
  @type unary_op :: :minus | :bang

  @typedoc """
  Membership operators in the AST.
  """
  @type membership_op :: :in | :contains

  @typedoc """
  Relative date directions in the AST.
  """
  @type relative_direction :: :ago | :future | :next | :last

  @typedoc """
  Parser result - either success with AST or error with details.
  """
  @type result :: {:ok, ast()} | {:error, binary(), pos_integer(), pos_integer()}

  @typedoc """
  Internal parser state for tracking position and tokens.
  """
  @type parser_state :: %{
          tokens: [Lexer.token()],
          position: non_neg_integer()
        }

  @doc """
  Parses a list of tokens into an Abstract Syntax Tree.

  ## Parameters

  - `tokens` - List of tokens from the lexer

  ## Returns

  - `{:ok, ast}` - Successfully parsed expression
  - `{:error, message, line, column}` - Parse error with position

  ## Examples

      iex> {:ok, tokens} = Predicator.Lexer.tokenize("score > 85")
      iex> Predicator.Parser.parse(tokens)
      {:ok, {:comparison, :gt, {:identifier, "score", {1, 1}}, {:literal, 85, {1, 9}}, {1, 7}}}

      iex> {:ok, tokens} = Predicator.Lexer.tokenize("name = \\"John\\"")
      iex> Predicator.Parser.parse(tokens)
      {:ok, {:comparison, :eq, {:identifier, "name", {1, 1}}, {:string_literal, "John", :double, {1, 8}}, {1, 6}}}

      iex> {:ok, tokens} = Predicator.Lexer.tokenize("active = true")
      iex> Predicator.Parser.parse(tokens)
      {:ok, {:comparison, :eq, {:identifier, "active", {1, 1}}, {:literal, true, {1, 10}}, {1, 8}}}
  """
  @spec parse([Lexer.token()]) :: result()
  def parse(tokens) when is_list(tokens) do
    warn_deprecated_equals(tokens)

    state = %{tokens: tokens, position: 0}

    case parse_expression(state) do
      {:ok, ast, final_state} ->
        # Ensure we consumed all tokens (except EOF)
        case peek_token(final_state) do
          {:eof, _line, _col, _len, _value} ->
            {:ok, ast}

          {type, line, col, _len, value} ->
            {:error, "Unexpected token #{format_token(type, value)} after expression", line, col}

          nil ->
            {:ok, ast}
        end

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  @doc """
  Removes source positions from an AST, producing the position-free shape
  Predicator 3.6 used.

  Total and idempotent: an AST that already carries no positions is returned
  unchanged, and an unrecognized node is passed through rather than raising.

  ## Examples

      iex> Predicator.Parser.strip_positions({:literal, 42, {1, 1}})
      {:literal, 42}

      iex> Predicator.Parser.strip_positions({:literal, 42})
      {:literal, 42}
  """
  @spec strip_positions(term()) :: term()
  def strip_positions({:literal, value, _pos}), do: {:literal, value}

  def strip_positions({:string_literal, value, quote_type, _pos}),
    do: {:string_literal, value, quote_type}

  def strip_positions({:string_literal, value, pos}) when is_tuple(pos) or is_nil(pos),
    do: {:string_literal, value}

  def strip_positions({:identifier, name, _pos}), do: {:identifier, name}
  def strip_positions({:duration, units, _pos}), do: {:duration, units}

  def strip_positions({:comparison, op, left, right, _pos}),
    do: strip_positions({:comparison, op, left, right})

  def strip_positions({:comparison, op, left, right}),
    do: {:comparison, op, strip_positions(left), strip_positions(right)}

  def strip_positions({:arithmetic, op, left, right, _pos}),
    do: strip_positions({:arithmetic, op, left, right})

  def strip_positions({:arithmetic, op, left, right}),
    do: {:arithmetic, op, strip_positions(left), strip_positions(right)}

  def strip_positions({:membership, op, left, right, _pos}),
    do: strip_positions({:membership, op, left, right})

  def strip_positions({:membership, op, left, right}),
    do: {:membership, op, strip_positions(left), strip_positions(right)}

  def strip_positions({:unary, op, operand, _pos}), do: strip_positions({:unary, op, operand})
  def strip_positions({:unary, op, operand}), do: {:unary, op, strip_positions(operand)}

  def strip_positions({:logical_and, left, right, _pos}),
    do: strip_positions({:logical_and, left, right})

  def strip_positions({:logical_and, left, right}),
    do: {:logical_and, strip_positions(left), strip_positions(right)}

  def strip_positions({:logical_or, left, right, _pos}),
    do: strip_positions({:logical_or, left, right})

  def strip_positions({:logical_or, left, right}),
    do: {:logical_or, strip_positions(left), strip_positions(right)}

  def strip_positions({:logical_not, operand, _pos}), do: strip_positions({:logical_not, operand})
  def strip_positions({:logical_not, operand}), do: {:logical_not, strip_positions(operand)}

  def strip_positions({:list, elements, _pos}), do: strip_positions({:list, elements})
  def strip_positions({:list, elements}), do: {:list, Enum.map(elements, &strip_positions/1)}

  def strip_positions({:object, entries, _pos}), do: strip_positions({:object, entries})

  def strip_positions({:object, entries}),
    do: {:object, Enum.map(entries, &strip_entry/1)}

  def strip_positions({:function_call, name, args, _pos}),
    do: strip_positions({:function_call, name, args})

  def strip_positions({:function_call, name, args}),
    do: {:function_call, name, Enum.map(args, &strip_positions/1)}

  def strip_positions({:bracket_access, object, key, _pos}),
    do: strip_positions({:bracket_access, object, key})

  def strip_positions({:bracket_access, object, key}),
    do: {:bracket_access, strip_positions(object), strip_positions(key)}

  def strip_positions({:property_access, object, property, _pos}),
    do: strip_positions({:property_access, object, property})

  def strip_positions({:property_access, object, property}),
    do: {:property_access, strip_positions(object), property}

  def strip_positions({:relative_date, duration, direction, _pos}),
    do: strip_positions({:relative_date, duration, direction})

  def strip_positions({:relative_date, duration, direction}),
    do: {:relative_date, strip_positions(duration), direction}

  def strip_positions(node), do: node

  @spec strip_entry({term(), term()}) :: {term(), term()}
  defp strip_entry({key, value}), do: {strip_positions(key), strip_positions(value)}

  @doc """
  Appends a `nil` position to any node that lacks one, producing the shape
  visitors expect.

  This is what lets `Predicator.decompile/2` and
  `Predicator.Compiler.to_instructions/2` keep accepting a caller-supplied
  3.6-shaped AST. A `nil` position produces no entry in the side table.

  ## Examples

      iex> Predicator.Parser.ensure_positions({:literal, 42})
      {:literal, 42, nil}

      iex> Predicator.Parser.ensure_positions({:literal, 42, {1, 1}})
      {:literal, 42, {1, 1}}
  """
  @spec ensure_positions(term()) :: term()
  def ensure_positions({:literal, value}), do: {:literal, value, nil}

  def ensure_positions({:string_literal, value}), do: {:string_literal, value, nil}

  def ensure_positions({:string_literal, value, quote_type})
      when quote_type in [:double, :single],
      do: {:string_literal, value, quote_type, nil}

  def ensure_positions({:identifier, name}), do: {:identifier, name, nil}
  def ensure_positions({:duration, units}), do: {:duration, units, nil}

  def ensure_positions({:comparison, op, left, right}),
    do: ensure_positions({:comparison, op, left, right, nil})

  def ensure_positions({:comparison, op, left, right, pos}),
    do: {:comparison, op, ensure_positions(left), ensure_positions(right), pos}

  def ensure_positions({:arithmetic, op, left, right}),
    do: ensure_positions({:arithmetic, op, left, right, nil})

  def ensure_positions({:arithmetic, op, left, right, pos}),
    do: {:arithmetic, op, ensure_positions(left), ensure_positions(right), pos}

  def ensure_positions({:membership, op, left, right}),
    do: ensure_positions({:membership, op, left, right, nil})

  def ensure_positions({:membership, op, left, right, pos}),
    do: {:membership, op, ensure_positions(left), ensure_positions(right), pos}

  def ensure_positions({:unary, op, operand}), do: ensure_positions({:unary, op, operand, nil})

  def ensure_positions({:unary, op, operand, pos}),
    do: {:unary, op, ensure_positions(operand), pos}

  def ensure_positions({:logical_and, left, right}),
    do: ensure_positions({:logical_and, left, right, nil})

  def ensure_positions({:logical_and, left, right, pos}),
    do: {:logical_and, ensure_positions(left), ensure_positions(right), pos}

  def ensure_positions({:logical_or, left, right}),
    do: ensure_positions({:logical_or, left, right, nil})

  def ensure_positions({:logical_or, left, right, pos}),
    do: {:logical_or, ensure_positions(left), ensure_positions(right), pos}

  def ensure_positions({:logical_not, operand}),
    do: ensure_positions({:logical_not, operand, nil})

  def ensure_positions({:logical_not, operand, pos}),
    do: {:logical_not, ensure_positions(operand), pos}

  def ensure_positions({:list, elements}), do: ensure_positions({:list, elements, nil})

  def ensure_positions({:list, elements, pos}),
    do: {:list, Enum.map(elements, &ensure_positions/1), pos}

  def ensure_positions({:object, entries}), do: ensure_positions({:object, entries, nil})

  def ensure_positions({:object, entries, pos}),
    do: {:object, Enum.map(entries, &ensure_entry/1), pos}

  def ensure_positions({:function_call, name, args}),
    do: ensure_positions({:function_call, name, args, nil})

  def ensure_positions({:function_call, name, args, pos}),
    do: {:function_call, name, Enum.map(args, &ensure_positions/1), pos}

  def ensure_positions({:bracket_access, object, key}),
    do: ensure_positions({:bracket_access, object, key, nil})

  def ensure_positions({:bracket_access, object, key, pos}),
    do: {:bracket_access, ensure_positions(object), ensure_positions(key), pos}

  def ensure_positions({:property_access, object, property}),
    do: ensure_positions({:property_access, object, property, nil})

  def ensure_positions({:property_access, object, property, pos}),
    do: {:property_access, ensure_positions(object), property, pos}

  def ensure_positions({:relative_date, duration, direction}),
    do: ensure_positions({:relative_date, duration, direction, nil})

  def ensure_positions({:relative_date, duration, direction, pos}),
    do: {:relative_date, ensure_positions(duration), direction, pos}

  def ensure_positions(node), do: node

  @spec ensure_entry({term(), term()}) :: {term(), term()}
  defp ensure_entry({key, value}), do: {ensure_positions(key), ensure_positions(value)}

  # Emits a single deprecation warning if the token stream uses `=` as an
  # equality operator. In 3.8 there is no assignment grammar, so every `:eq`
  # token is expression-position; the statement grammar (px-tbv.1) must refine
  # this check rather than inherit it.
  @spec warn_deprecated_equals([Lexer.token()]) :: :ok
  defp warn_deprecated_equals(tokens) do
    if deprecation_warnings_enabled?() do
      case Enum.find(tokens, &match?({:eq, _line, _col, _len, _value}, &1)) do
        {:eq, line, col, _len, _value} ->
          Logger.warning(
            "[predicator] `=` as an equality operator is deprecated and becomes " <>
              "a parse error in Predicator 4.0. Use `==` instead. " <>
              "First occurrence at line #{line}, column #{col}. " <>
              "Silence with `config :predicator, deprecation_warnings: false`."
          )

        nil ->
          :ok
      end
    end

    :ok
  end

  @spec deprecation_warnings_enabled?() :: boolean()
  defp deprecation_warnings_enabled? do
    Application.get_env(:predicator, :deprecation_warnings, true) != false
  end

  # Parse expression (top level)
  @spec parse_expression(parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_expression(state) do
    parse_logical_or(state)
  end

  # Parse logical OR expressions (lowest precedence)
  @spec parse_logical_or(parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_logical_or(state) do
    case parse_logical_and(state) do
      {:ok, left, new_state} ->
        parse_logical_or_rest(left, new_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  @spec parse_logical_or_rest(ast(), parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_logical_or_rest(left, state) do
    token = peek_token(state)
    parse_logical_or_rest_token(left, state, token)
  end

  # Parse OR operator token (OR or ||)
  defp parse_logical_or_rest_token(left, state, {:or_op, line, col, _len, _value}) do
    or_state = advance(state)

    case parse_logical_and(or_state) do
      {:ok, right, final_state} ->
        ast = {:logical_or, left, right, {line, col}}
        parse_logical_or_rest(ast, final_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  defp parse_logical_or_rest_token(left, state, {:or_or, line, col, _len, _value}) do
    or_state = advance(state)

    case parse_logical_and(or_state) do
      {:ok, right, final_state} ->
        ast = {:logical_or, left, right, {line, col}}
        parse_logical_or_rest(ast, final_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # No OR operator, return left operand
  defp parse_logical_or_rest_token(left, state, _token) do
    {:ok, left, state}
  end

  # Parse logical AND expressions (middle precedence)
  @spec parse_logical_and(parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_logical_and(state) do
    case parse_logical_not(state) do
      {:ok, left, new_state} ->
        parse_logical_and_rest(left, new_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  @spec parse_logical_and_rest(ast(), parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_logical_and_rest(left, state) do
    token = peek_token(state)
    parse_logical_and_rest_token(left, state, token)
  end

  # Parse AND operator token (AND or &&)
  defp parse_logical_and_rest_token(left, state, {:and_op, line, col, _len, _value}) do
    and_state = advance(state)

    case parse_logical_not(and_state) do
      {:ok, right, final_state} ->
        ast = {:logical_and, left, right, {line, col}}
        parse_logical_and_rest(ast, final_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  defp parse_logical_and_rest_token(left, state, {:and_and, line, col, _len, _value}) do
    and_state = advance(state)

    case parse_logical_not(and_state) do
      {:ok, right, final_state} ->
        ast = {:logical_and, left, right, {line, col}}
        parse_logical_and_rest(ast, final_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # No AND operator, return left operand
  defp parse_logical_and_rest_token(left, state, _token) do
    {:ok, left, state}
  end

  # Parse logical NOT expressions (highest precedence)
  @spec parse_logical_not(parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_logical_not(state) do
    token = peek_token(state)
    parse_logical_not_token(state, token)
  end

  # Parse NOT operator token (NOT or !)
  defp parse_logical_not_token(state, {op, line, col, _len, _value})
       when op in [:not_op, :bang] do
    not_state = advance(state)

    case parse_logical_not(not_state) do
      {:ok, operand, final_state} ->
        ast = {:logical_not, operand, {line, col}}
        {:ok, ast, final_state}

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # No NOT operator, parse comparison
  defp parse_logical_not_token(state, _token) do
    parse_comparison(state)
  end

  # Parse comparison expressions
  # NOTE: Nesting depth (3) is expected and appropriate for recursive descent parsing.
  # The nested case statements handle: parse left operand -> check for operator ->
  # parse right operand -> construct AST, with proper error propagation at each step.
  @spec parse_comparison(parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_comparison(state) do
    case parse_addition(state) do
      {:ok, left, new_state} ->
        case peek_token(new_state) do
          # Comparison operators (including equality)
          {op_type, op_line, op_col, _len, _value}
          when op_type in [
                 :gt,
                 :lt,
                 :gte,
                 :lte,
                 :eq,
                 :equal_equal,
                 :ne,
                 :strict_equal,
                 :strict_ne
               ] ->
            op_state = advance(new_state)

            case parse_addition(op_state) do
              {:ok, right, final_state} ->
                # Map tokens to AST operators
                normalized_op =
                  case op_type do
                    :equal_equal -> :equal_equal
                    :strict_equal -> :strict_eq
                    :strict_ne -> :strict_ne
                    _other_op_type -> op_type
                  end

                ast = {:comparison, normalized_op, left, right, {op_line, op_col}}
                {:ok, ast, final_state}

              {:error, message, line, col} ->
                {:error, message, line, col}
            end

          # Membership operators
          {op_type, op_line, op_col, _len, _value}
          when op_type in [:in_op, :contains_op] ->
            operator = map_membership_operator(op_type)
            op_state = advance(new_state)

            case parse_addition(op_state) do
              {:ok, right, final_state} ->
                ast = {:membership, operator, left, right, {op_line, op_col}}
                {:ok, ast, final_state}

              {:error, message, line, col} ->
                {:error, message, line, col}
            end

          # Not a comparison, return the addition expression
          _token ->
            {:ok, left, new_state}
        end

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # Parse addition expressions (+ -)
  @spec parse_addition(parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_addition(state) do
    case parse_multiplication(state) do
      {:ok, left, new_state} ->
        parse_addition_rest(left, new_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  @spec parse_addition_rest(ast(), parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_addition_rest(left, state) do
    token = peek_token(state)
    parse_addition_rest_token(left, state, token)
  end

  # Parse + operator
  defp parse_addition_rest_token(left, state, {:plus, line, col, _len, _value}) do
    add_state = advance(state)

    case parse_multiplication(add_state) do
      {:ok, right, final_state} ->
        ast = {:arithmetic, :add, left, right, {line, col}}
        parse_addition_rest(ast, final_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # Parse - operator
  defp parse_addition_rest_token(left, state, {:minus, line, col, _len, _value}) do
    sub_state = advance(state)

    case parse_multiplication(sub_state) do
      {:ok, right, final_state} ->
        ast = {:arithmetic, :subtract, left, right, {line, col}}
        parse_addition_rest(ast, final_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # No addition operator, return left operand
  defp parse_addition_rest_token(left, state, _token) do
    {:ok, left, state}
  end

  # Parse multiplication expressions (* / %)
  @spec parse_multiplication(parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_multiplication(state) do
    case parse_unary(state) do
      {:ok, left, new_state} ->
        parse_multiplication_rest(left, new_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  @spec parse_multiplication_rest(ast(), parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_multiplication_rest(left, state) do
    token = peek_token(state)
    parse_multiplication_rest_token(left, state, token)
  end

  # Parse * operator
  defp parse_multiplication_rest_token(left, state, {:multiply, line, col, _len, _value}) do
    mul_state = advance(state)

    case parse_unary(mul_state) do
      {:ok, right, final_state} ->
        ast = {:arithmetic, :multiply, left, right, {line, col}}
        parse_multiplication_rest(ast, final_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # Parse / operator
  defp parse_multiplication_rest_token(left, state, {:divide, line, col, _len, _value}) do
    div_state = advance(state)

    case parse_unary(div_state) do
      {:ok, right, final_state} ->
        ast = {:arithmetic, :divide, left, right, {line, col}}
        parse_multiplication_rest(ast, final_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # Parse % operator
  defp parse_multiplication_rest_token(left, state, {:modulo, line, col, _len, _value}) do
    mod_state = advance(state)

    case parse_unary(mod_state) do
      {:ok, right, final_state} ->
        ast = {:arithmetic, :modulo, left, right, {line, col}}
        parse_multiplication_rest(ast, final_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # No multiplication operator, return left operand
  defp parse_multiplication_rest_token(left, state, _token) do
    {:ok, left, state}
  end

  # Parse unary expressions (- !)
  @spec parse_unary(parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_unary(state) do
    token = peek_token(state)
    parse_unary_token(state, token)
  end

  # Parse unary minus
  defp parse_unary_token(state, {:minus, line, col, _len, _value}) do
    minus_state = advance(state)

    case parse_unary(minus_state) do
      {:ok, operand, final_state} ->
        ast = {:unary, :minus, operand, {line, col}}
        {:ok, ast, final_state}

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # Parse unary bang
  defp parse_unary_token(state, {:bang, line, col, _len, _value}) do
    bang_state = advance(state)

    case parse_unary(bang_state) do
      {:ok, operand, final_state} ->
        ast = {:unary, :bang, operand, {line, col}}
        {:ok, ast, final_state}

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # No unary operator, parse postfix
  defp parse_unary_token(state, _token) do
    parse_postfix(state)
  end

  # Parse postfix expressions (bracket access)
  defp parse_postfix(state) do
    case parse_primary(state) do
      {:ok, expr, new_state} ->
        parse_postfix_operations(expr, new_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # Parse zero or more postfix operations (bracket access)
  defp parse_postfix_operations(expr, state) do
    token = peek_token(state)

    case token do
      {:lbracket, line, col, _len, _value} ->
        # Parse bracket access: expr[key]
        bracket_state = advance(state)

        case parse_expression(bracket_state) do
          {:ok, key_expr, key_state} ->
            case peek_token(key_state) do
              {:rbracket, _line, _col, _len, _value} ->
                bracket_access = {:bracket_access, expr, key_expr, {line, col}}
                final_state = advance(key_state)
                # Recursively parse more postfix operations
                parse_postfix_operations(bracket_access, final_state)

              {type, line, col, _len, value} ->
                {:error, "Expected ']' but found #{format_token(type, value)}", line, col}

              nil ->
                {:error, "Expected ']' but found end of input", 1, 1}
            end

          {:error, message, line, col} ->
            {:error, message, line, col}
        end

      {:dot, dot_line, dot_col, _len, _value} ->
        # Parse property access: expr.property
        dot_state = advance(state)

        case peek_token(dot_state) do
          # Duration operators are allowed as property names (like user.name.last)
          {type, _line, _col, _len, property_name}
          when type in [:identifier, :last_op, :next_op, :ago_op, :from_op, :now_op] ->
            property_access = {:property_access, expr, property_name, {dot_line, dot_col}}
            final_state = advance(dot_state)
            # Recursively parse more postfix operations
            parse_postfix_operations(property_access, final_state)

          {type, line, col, _len, value} ->
            {:error, "Expected property name after '.' but found #{format_token(type, value)}",
             line, col}

          nil ->
            {:error, "Expected property name after '.' but found end of input", 1, 1}
        end

      _other ->
        # No more postfix operations, return the expression
        {:ok, expr, state}
    end
  end

  # Parse primary expressions (literals, identifiers, parentheses)
  # This function handles multiple token types and nested error cases - inherent parser complexity
  @spec parse_primary(parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_primary(state) do
    token = peek_token(state)
    parse_primary_token(state, token)
  end

  # Parse integer literal (may be start of duration)
  defp parse_primary_token(state, {:integer, line, col, _len, value}) do
    # Check if this integer is followed by duration units
    next_state = advance(state)

    case parse_duration_sequence_from_integer(value, next_state, {line, col}) do
      {:ok, duration_ast, final_state} ->
        {:ok, duration_ast, final_state}

      {:error, message, line, col} ->
        {:error, message, line, col}

      :not_duration ->
        # Regular integer literal
        {:ok, {:literal, value, {line, col}}, next_state}
    end
  end

  # Parse float literal
  defp parse_primary_token(state, {:float, line, col, _len, value}) do
    {:ok, {:literal, value, {line, col}}, advance(state)}
  end

  # Parse string literal
  defp parse_primary_token(state, {:string, line, col, _len, value, quote_type}) do
    {:ok, {:string_literal, value, quote_type, {line, col}}, advance(state)}
  end

  # Parse boolean literal
  defp parse_primary_token(state, {:boolean, line, col, _len, value}) do
    {:ok, {:literal, value, {line, col}}, advance(state)}
  end

  # Parse date literal
  defp parse_primary_token(state, {:date, line, col, _len, value}) do
    {:ok, {:literal, value, {line, col}}, advance(state)}
  end

  # Parse datetime literal
  defp parse_primary_token(state, {:datetime, line, col, _len, value}) do
    {:ok, {:literal, value, {line, col}}, advance(state)}
  end

  # Parse identifier
  defp parse_primary_token(state, {:identifier, line, col, _len, value}) do
    {:ok, {:identifier, value, {line, col}}, advance(state)}
  end

  # Parse function call
  defp parse_primary_token(state, {:function_name, line, col, _len, name}) do
    parse_function_call(state, name, {line, col})
  end

  # Parse qualified function call (namespace.function)
  defp parse_primary_token(state, {:qualified_function_name, line, col, _len, name}) do
    parse_function_call(state, name, {line, col})
  end

  # Parse parenthesized expression
  defp parse_primary_token(state, {:lparen, _line, _col, _len, _value}) do
    paren_state = advance(state)

    case parse_expression(paren_state) do
      {:ok, expr, expr_state} ->
        case peek_token(expr_state) do
          {:rparen, _line, _col, _len, _value} ->
            {:ok, expr, advance(expr_state)}

          {type, line, col, _len, value} ->
            {:error, "Expected ')' but found #{format_token(type, value)}", line, col}

          nil ->
            {:error, "Expected ')' but reached end of input", 1, 1}
        end

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # Parse list literal
  defp parse_primary_token(state, {:lbracket, line, col, _len, _value}) do
    parse_list(state, {line, col})
  end

  # Parse object literal
  defp parse_primary_token(state, {:lbrace, line, col, _len, _value}) do
    parse_object(state, {line, col})
  end

  # Parse duration direction keywords
  defp parse_primary_token(state, {:next_op, line, col, _len, _value}) do
    parse_relative_date_expression(state, :next, {line, col})
  end

  defp parse_primary_token(state, {:last_op, line, col, _len, _value}) do
    parse_relative_date_expression(state, :last, {line, col})
  end

  # Handle unexpected tokens
  defp parse_primary_token(_state, {type, line, col, _len, value}) do
    expected =
      "number, string, boolean, date, datetime, identifier, function call, list, object, or '('"

    {:error, "Expected #{expected} but found #{format_token(type, value)}", line, col}
  end

  # Handle end of input
  defp parse_primary_token(_state, nil) do
    {:error, "Unexpected end of input", 1, 1}
  end

  # Helper functions

  @spec peek_token(parser_state()) :: Lexer.token() | nil
  defp peek_token(%{tokens: tokens, position: pos}) do
    Enum.at(tokens, pos)
  end

  @spec advance(parser_state()) :: parser_state()
  defp advance(%{position: pos} = state) do
    %{state | position: pos + 1}
  end

  @spec map_membership_operator(atom()) :: membership_op()
  defp map_membership_operator(:in_op), do: :in
  defp map_membership_operator(:contains_op), do: :contains

  @spec format_token(atom(), term()) :: binary()
  defp format_token(:integer, value), do: "number '#{value}'"
  defp format_token(:float, value), do: "number '#{value}'"
  defp format_token(:string, value), do: "string \"#{value}\""
  defp format_token(:boolean, value), do: "boolean '#{value}'"
  defp format_token(:date, value), do: "date '#{Date.to_iso8601(value)}'"
  defp format_token(:datetime, value), do: "datetime '#{DateTime.to_iso8601(value)}'"
  defp format_token(:identifier, value), do: "identifier '#{value}'"
  defp format_token(:gt, _value), do: "'>'"
  defp format_token(:lt, _value), do: "'<'"
  defp format_token(:gte, _value), do: "'>='"
  defp format_token(:lte, _value), do: "'<='"
  defp format_token(:eq, _value), do: "'='"
  defp format_token(:ne, _value), do: "'!='"
  defp format_token(:equal_equal, _value), do: "'=='"
  defp format_token(:strict_equal, _value), do: "'==='"
  defp format_token(:strict_ne, _value), do: "'!=='"
  defp format_token(:and_op, _value), do: "'AND'"
  defp format_token(:or_op, _value), do: "'OR'"
  defp format_token(:not_op, _value), do: "'NOT'"
  defp format_token(:in_op, _value), do: "'IN'"
  defp format_token(:contains_op, _value), do: "'CONTAINS'"
  defp format_token(:duration_unit, value), do: "duration unit '#{value}'"
  defp format_token(:ago_op, _value), do: "'ago'"
  defp format_token(:from_op, _value), do: "'from'"
  defp format_token(:now_op, _value), do: "'now'"
  defp format_token(:next_op, _value), do: "'next'"
  defp format_token(:last_op, _value), do: "'last'"
  defp format_token(:lparen, _value), do: "'('"
  defp format_token(:rparen, _value), do: "')'"
  defp format_token(:lbracket, _value), do: "'['"
  defp format_token(:rbracket, _value), do: "']'"
  defp format_token(:lbrace, _value), do: "'{'"
  defp format_token(:rbrace, _value), do: "'}'"
  defp format_token(:colon, _value), do: "':'"
  defp format_token(:comma, _value), do: "','"
  defp format_token(:plus, _value), do: "'+'"
  defp format_token(:minus, _value), do: "'-'"
  defp format_token(:multiply, _value), do: "'*'"
  defp format_token(:divide, _value), do: "'/'"
  defp format_token(:modulo, _value), do: "'%'"
  defp format_token(:and_and, _value), do: "'&&'"
  defp format_token(:or_or, _value), do: "'||'"
  defp format_token(:bang, _value), do: "'!'"
  defp format_token(:function_name, value), do: "function '#{value}'"
  defp format_token(:qualified_function_name, value), do: "function '#{value}'"
  defp format_token(:eof, _value), do: "end of input"

  # Parse list literals: [element1, element2, ...]
  @spec parse_list(parser_state(), position()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_list(state, position) do
    # Consume opening bracket
    bracket_state = advance(state)

    case peek_token(bracket_state) do
      # Empty list
      {:rbracket, _line, _col, _len, _value} ->
        {:ok, {:list, [], position}, advance(bracket_state)}

      # Non-empty list
      _token ->
        case parse_list_elements(bracket_state, []) do
          {:ok, elements, final_state} ->
            case peek_token(final_state) do
              {:rbracket, _line, _col, _len, _value} ->
                {:ok, {:list, Enum.reverse(elements), position}, advance(final_state)}

              {type, line, col, _len, value} ->
                {:error, "Expected ']' but found #{format_token(type, value)}", line, col}

              nil ->
                {:error, "Expected ']' but reached end of input", 1, 1}
            end

          {:error, message, line, col} ->
            {:error, message, line, col}
        end
    end
  end

  # Parse list elements recursively
  @spec parse_list_elements(parser_state(), [ast()]) ::
          {:ok, [ast()], parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_list_elements(state, acc) do
    case parse_expression(state) do
      {:ok, element, new_state} ->
        new_acc = [element | acc]

        case peek_token(new_state) do
          {:comma, _line, _col, _len, _value} ->
            # More elements, consume comma and continue
            comma_state = advance(new_state)
            parse_list_elements(comma_state, new_acc)

          _token ->
            # No more elements
            {:ok, new_acc, new_state}
        end

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # Parse object literals: {key1: value1, key2: value2, ...}
  @spec parse_object(parser_state(), position()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_object(state, position) do
    # Consume opening brace
    brace_state = advance(state)

    case peek_token(brace_state) do
      # Empty object
      {:rbrace, _line, _col, _len, _value} ->
        {:ok, {:object, [], position}, advance(brace_state)}

      # Non-empty object
      _token ->
        case parse_object_entries(brace_state, []) do
          {:ok, entries, final_state} ->
            case peek_token(final_state) do
              {:rbrace, _line, _col, _len, _value} ->
                {:ok, {:object, Enum.reverse(entries), position}, advance(final_state)}

              {type, line, col, _len, value} ->
                {:error, "Expected '}' but found #{format_token(type, value)}", line, col}

              nil ->
                {:error, "Expected '}' but reached end of input", 1, 1}
            end

          {:error, message, line, col} ->
            {:error, message, line, col}
        end
    end
  end

  # Parse object entries recursively
  @spec parse_object_entries(parser_state(), [object_entry()]) ::
          {:ok, [object_entry()], parser_state()}
          | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_object_entries(state, acc) do
    case parse_object_entry(state) do
      {:ok, entry, new_state} ->
        new_acc = [entry | acc]

        case peek_token(new_state) do
          {:comma, _line, _col, _len, _value} ->
            # More entries, consume comma and continue
            comma_state = advance(new_state)
            parse_object_entries(comma_state, new_acc)

          _token ->
            # No more entries
            {:ok, new_acc, new_state}
        end

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # Parse a single object entry: key: value
  @spec parse_object_entry(parser_state()) ::
          {:ok, object_entry(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_object_entry(state) do
    case parse_object_key(state) do
      {:ok, key, key_state} ->
        case peek_token(key_state) do
          {:colon, _line, _col, _len, _value} ->
            colon_state = advance(key_state)

            case parse_expression(colon_state) do
              {:ok, value, value_state} ->
                {:ok, {key, value}, value_state}

              {:error, message, line, col} ->
                {:error, message, line, col}
            end

          {:string, line, col, _len, value, _quote_type} ->
            {:error, "Expected ':' after object key but found #{format_token(:string, value)}",
             line, col}

          {type, line, col, _len, token_value} ->
            {:error, "Expected ':' after object key but found #{format_token(type, token_value)}",
             line, col}

          nil ->
            {:error, "Expected ':' after object key but reached end of input", 1, 1}
        end

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # Parse object key (identifier or string literal)
  @spec parse_object_key(parser_state()) ::
          {:ok, object_key(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_object_key(state) do
    case peek_token(state) do
      {:identifier, line, col, _len, value} ->
        {:ok, {:identifier, value, {line, col}}, advance(state)}

      {:string, line, col, _len, value, _quote_type} ->
        {:ok, {:string_literal, value, {line, col}}, advance(state)}

      {type, line, col, _len, value} ->
        {:error,
         "Expected identifier or string for object key but found #{format_token(type, value)}",
         line, col}

      nil ->
        {:error, "Expected object key but reached end of input", 1, 1}
    end
  end

  # Parse function call: function_name(arg1, arg2, ...)
  @spec parse_function_call(parser_state(), binary(), position()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_function_call(state, function_name, position) do
    # Consume function name token
    func_state = advance(state)

    case peek_token(func_state) do
      {:lparen, _line, _col, _len, _value} ->
        # Consume opening parenthesis
        paren_state = advance(func_state)

        case peek_token(paren_state) do
          # Empty argument list
          {:rparen, _line, _col, _len, _value} ->
            {:ok, {:function_call, function_name, [], position}, advance(paren_state)}

          # Non-empty argument list
          _token ->
            case parse_function_arguments(paren_state, []) do
              {:ok, arguments, final_state} ->
                case peek_token(final_state) do
                  {:rparen, _line, _col, _len, _value} ->
                    {:ok, {:function_call, function_name, Enum.reverse(arguments), position},
                     advance(final_state)}

                  {type, line, col, _len, value} ->
                    {:error, "Expected ')' but found #{format_token(type, value)}", line, col}

                  nil ->
                    {:error, "Expected ')' but reached end of input", 1, 1}
                end

              {:error, message, line, col} ->
                {:error, message, line, col}
            end
        end

      {type, line, col, _len, value} ->
        {:error, "Expected '(' after function name but found #{format_token(type, value)}", line,
         col}

      nil ->
        {:error, "Expected '(' after function name but reached end of input", 1, 1}
    end
  end

  # Parse function arguments recursively
  @spec parse_function_arguments(parser_state(), [ast()]) ::
          {:ok, [ast()], parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_function_arguments(state, acc) do
    case parse_expression(state) do
      {:ok, argument, new_state} ->
        new_acc = [argument | acc]

        case peek_token(new_state) do
          {:comma, _line, _col, _len, _value} ->
            # More arguments, consume comma and continue
            comma_state = advance(new_state)
            parse_function_arguments(comma_state, new_acc)

          _token ->
            # No more arguments
            {:ok, new_acc, new_state}
        end

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # Duration parsing functions

  @spec parse_duration_sequence_from_integer(integer(), parser_state(), position()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), integer(), integer()} | :not_duration
  defp parse_duration_sequence_from_integer(number, state, position) do
    case peek_token(state) do
      {:duration_unit, _line, _col, _len, unit} ->
        # Found duration unit, parse the full duration sequence
        parse_duration_sequence([{number, unit}], advance(state), position)

      _token ->
        # Not followed by duration unit
        :not_duration
    end
  end

  @spec parse_duration_sequence([{integer(), binary()}], parser_state(), position()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), integer(), integer()}
  defp parse_duration_sequence(units, state, position) do
    case peek_token(state) do
      {:integer, _line, _col, _len, number} ->
        # Check if this integer is followed by a duration unit
        next_state = advance(state)

        case peek_token(next_state) do
          {:duration_unit, _line, _col, _len, unit} ->
            # Continue building duration sequence (prepended; reversed once at the end)
            parse_duration_sequence([{number, unit} | units], advance(next_state), position)

          _token ->
            # End of duration sequence, check for direction operators
            duration_ast = {:duration, Enum.reverse(units), position}
            parse_duration_with_direction(duration_ast, state)
        end

      _token ->
        # End of duration sequence, check for direction operators
        duration_ast = {:duration, Enum.reverse(units), position}
        parse_duration_with_direction(duration_ast, state)
    end
  end

  @spec parse_duration_with_direction(ast(), parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), integer(), integer()}
  defp parse_duration_with_direction(duration_ast, state) do
    case peek_token(state) do
      {:ago_op, line, col, _len, _value} ->
        {:ok, {:relative_date, duration_ast, :ago, {line, col}}, advance(state)}

      {:from_op, line, col, _len, _value} ->
        # Expect 'now' after 'from'
        from_state = advance(state)

        case peek_token(from_state) do
          {:now_op, _line, _col, _len, _value} ->
            {:ok, {:relative_date, duration_ast, :future, {line, col}}, advance(from_state)}

          {type, line, col, _len, value} ->
            {:error, "Expected 'now' after 'from' but found #{format_token(type, value)}", line,
             col}

          nil ->
            {:error, "Expected 'now' after 'from' but reached end of input", 1, 1}
        end

      _token ->
        # Just a duration, no direction
        {:ok, duration_ast, state}
    end
  end

  @spec parse_relative_date_expression(parser_state(), relative_direction(), position()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_relative_date_expression(state, direction, position) do
    # Advance past the direction keyword (next/last)
    next_state = advance(state)

    # Expect a duration expression
    case parse_primary(next_state) do
      {:ok, {:duration, _units, _duration_pos} = duration_ast, final_state} ->
        {:ok, {:relative_date, duration_ast, direction, position}, final_state}

      {:ok, _other_ast, _final_state} ->
        {type, line, col, _len, value} = peek_token(next_state)

        {:error, "Expected duration after '#{direction}' but found #{format_token(type, value)}",
         line, col}

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end
end
