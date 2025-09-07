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
      comparison   → addition ( ( ">" | "<" | ">=" | "<=" | "=" | "==" | "!=" | "===" | "!==" | "in" | "contains" ) addition )?
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

  ## Examples

      iex> {:ok, tokens} = Predicator.Lexer.tokenize("score > 85")
      iex> Predicator.Parser.parse(tokens)
      {:ok, {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}}

      iex> {:ok, tokens} = Predicator.Lexer.tokenize("(age >= 18)")
      iex> Predicator.Parser.parse(tokens)
      {:ok, {:comparison, :gte, {:identifier, "age"}, {:literal, 18}}}

      iex> {:ok, tokens} = Predicator.Lexer.tokenize("score > 85 AND age >= 18")
      iex> Predicator.Parser.parse(tokens)
      {:ok, {:logical_and, {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}, {:comparison, :gte, {:identifier, "age"}, {:literal, 18}}}}
  """

  alias Predicator.Lexer

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

  - `{:literal, value}` - A literal value (number, boolean, list, date, datetime, duration)
  - `{:string_literal, value, quote_type}` - A string literal with quote type information
  - `{:identifier, name}` - A variable reference
  - `{:comparison, operator, left, right}` - A comparison expression (including equality)
  - `{:arithmetic, operator, left, right}` - An arithmetic expression (+, -, *, /, %)
  - `{:unary, operator, operand}` - A unary expression (-, !)
  - `{:logical_and, left, right}` - A logical AND expression
  - `{:logical_or, left, right}` - A logical OR expression
  - `{:logical_not, operand}` - A logical NOT expression
  - `{:list, elements}` - A list literal
  - `{:object, entries}` - An object literal with key-value pairs
  - `{:membership, operator, left, right}` - A membership operation (in/contains)
  - `{:function_call, name, arguments}` - A function call with arguments
  - `{:bracket_access, object, key}` - A bracket access expression (obj[key])
  - `{:duration, units}` - A duration literal (e.g., 3d8h)
  - `{:relative_date, duration, direction}` - A relative date expression (e.g., 3d ago, next 2w)
  """
  @type ast ::
          {:literal, value()}
          | {:string_literal, binary(), :double | :single}
          | {:identifier, binary()}
          | {:comparison, comparison_op(), ast(), ast()}
          | {:arithmetic, arithmetic_op(), ast(), ast()}
          | {:unary, unary_op(), ast()}
          | {:membership, membership_op(), ast(), ast()}
          | {:logical_and, ast(), ast()}
          | {:logical_or, ast(), ast()}
          | {:logical_not, ast()}
          | {:list, [ast()]}
          | {:object, [object_entry()]}
          | {:function_call, binary(), [ast()]}
          | {:bracket_access, ast(), ast()}
          | {:duration, [{integer(), binary()}]}
          | {:relative_date, ast(), relative_direction()}

  @typedoc """
  An object entry (key-value pair) in an object literal.

  The key can be either an identifier or a string literal.
  """
  @type object_entry :: {object_key(), ast()}

  @typedoc """
  A key in an object literal - either an identifier or string literal.
  """
  @type object_key :: {:identifier, binary()} | {:string_literal, binary()}

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
      {:ok, {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}}

      iex> {:ok, tokens} = Predicator.Lexer.tokenize("name = \\"John\\"")
      iex> Predicator.Parser.parse(tokens)
      {:ok, {:comparison, :eq, {:identifier, "name"}, {:string_literal, "John", :double}}}

      iex> {:ok, tokens} = Predicator.Lexer.tokenize("active = true")
      iex> Predicator.Parser.parse(tokens)
      {:ok, {:comparison, :eq, {:identifier, "active"}, {:literal, true}}}
  """
  @spec parse([Lexer.token()]) :: result()
  def parse(tokens) when is_list(tokens) do
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
  defp parse_logical_or_rest_token(left, state, {:or_op, _line, _col, _len, _value}) do
    or_state = advance(state)

    case parse_logical_and(or_state) do
      {:ok, right, final_state} ->
        ast = {:logical_or, left, right}
        parse_logical_or_rest(ast, final_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  defp parse_logical_or_rest_token(left, state, {:or_or, _line, _col, _len, _value}) do
    or_state = advance(state)

    case parse_logical_and(or_state) do
      {:ok, right, final_state} ->
        ast = {:logical_or, left, right}
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
  defp parse_logical_and_rest_token(left, state, {:and_op, _line, _col, _len, _value}) do
    and_state = advance(state)

    case parse_logical_not(and_state) do
      {:ok, right, final_state} ->
        ast = {:logical_and, left, right}
        parse_logical_and_rest(ast, final_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  defp parse_logical_and_rest_token(left, state, {:and_and, _line, _col, _len, _value}) do
    and_state = advance(state)

    case parse_logical_not(and_state) do
      {:ok, right, final_state} ->
        ast = {:logical_and, left, right}
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
  defp parse_logical_not_token(state, {op, _line, _col, _len, _value})
       when op in [:not_op, :bang] do
    not_state = advance(state)

    case parse_logical_not(not_state) do
      {:ok, operand, final_state} ->
        ast = {:logical_not, operand}
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
          {op_type, _line, _col, _len, _value}
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

                ast = {:comparison, normalized_op, left, right}
                {:ok, ast, final_state}

              {:error, message, line, col} ->
                {:error, message, line, col}
            end

          # Membership operators
          {op_type, _line, _col, _len, _value}
          when op_type in [:in_op, :contains_op] ->
            operator = map_membership_operator(op_type)
            op_state = advance(new_state)

            case parse_addition(op_state) do
              {:ok, right, final_state} ->
                ast = {:membership, operator, left, right}
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
  defp parse_addition_rest_token(left, state, {:plus, _line, _col, _len, _value}) do
    add_state = advance(state)

    case parse_multiplication(add_state) do
      {:ok, right, final_state} ->
        ast = {:arithmetic, :add, left, right}
        parse_addition_rest(ast, final_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # Parse - operator
  defp parse_addition_rest_token(left, state, {:minus, _line, _col, _len, _value}) do
    sub_state = advance(state)

    case parse_multiplication(sub_state) do
      {:ok, right, final_state} ->
        ast = {:arithmetic, :subtract, left, right}
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
  defp parse_multiplication_rest_token(left, state, {:multiply, _line, _col, _len, _value}) do
    mul_state = advance(state)

    case parse_unary(mul_state) do
      {:ok, right, final_state} ->
        ast = {:arithmetic, :multiply, left, right}
        parse_multiplication_rest(ast, final_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # Parse / operator
  defp parse_multiplication_rest_token(left, state, {:divide, _line, _col, _len, _value}) do
    div_state = advance(state)

    case parse_unary(div_state) do
      {:ok, right, final_state} ->
        ast = {:arithmetic, :divide, left, right}
        parse_multiplication_rest(ast, final_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # Parse % operator
  defp parse_multiplication_rest_token(left, state, {:modulo, _line, _col, _len, _value}) do
    mod_state = advance(state)

    case parse_unary(mod_state) do
      {:ok, right, final_state} ->
        ast = {:arithmetic, :modulo, left, right}
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
  defp parse_unary_token(state, {:minus, _line, _col, _len, _value}) do
    minus_state = advance(state)

    case parse_unary(minus_state) do
      {:ok, operand, final_state} ->
        ast = {:unary, :minus, operand}
        {:ok, ast, final_state}

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # Parse unary bang
  defp parse_unary_token(state, {:bang, _line, _col, _len, _value}) do
    bang_state = advance(state)

    case parse_unary(bang_state) do
      {:ok, operand, final_state} ->
        ast = {:unary, :bang, operand}
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
      {:lbracket, _line, _col, _len, _value} ->
        # Parse bracket access: expr[key]
        bracket_state = advance(state)

        case parse_expression(bracket_state) do
          {:ok, key_expr, key_state} ->
            case peek_token(key_state) do
              {:rbracket, _line, _col, _len, _value} ->
                bracket_access = {:bracket_access, expr, key_expr}
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

      {:dot, _line, _col, _len, _value} ->
        # Parse property access: expr.property
        dot_state = advance(state)

        case peek_token(dot_state) do
          {:identifier, _line, _col, _len, property_name} ->
            property_access = {:property_access, expr, property_name}
            final_state = advance(dot_state)
            # Recursively parse more postfix operations
            parse_postfix_operations(property_access, final_state)

          # Allow duration operators as property names (like user.name.last)
          {:last_op, _line, _col, _len, property_name} ->
            property_access = {:property_access, expr, property_name}
            final_state = advance(dot_state)
            parse_postfix_operations(property_access, final_state)

          {:next_op, _line, _col, _len, property_name} ->
            property_access = {:property_access, expr, property_name}
            final_state = advance(dot_state)
            parse_postfix_operations(property_access, final_state)

          {:ago_op, _line, _col, _len, property_name} ->
            property_access = {:property_access, expr, property_name}
            final_state = advance(dot_state)
            parse_postfix_operations(property_access, final_state)

          {:from_op, _line, _col, _len, property_name} ->
            property_access = {:property_access, expr, property_name}
            final_state = advance(dot_state)
            parse_postfix_operations(property_access, final_state)

          {:now_op, _line, _col, _len, property_name} ->
            property_access = {:property_access, expr, property_name}
            final_state = advance(dot_state)
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
  defp parse_primary_token(state, {:integer, _line, _col, _len, value}) do
    # Check if this integer is followed by duration units
    next_state = advance(state)

    case parse_duration_sequence_from_integer(value, next_state) do
      {:ok, duration_ast, final_state} ->
        {:ok, duration_ast, final_state}

      {:error, message, line, col} ->
        {:error, message, line, col}

      :not_duration ->
        # Regular integer literal
        {:ok, {:literal, value}, next_state}
    end
  end

  # Parse float literal
  defp parse_primary_token(state, {:float, _line, _col, _len, value}) do
    {:ok, {:literal, value}, advance(state)}
  end

  # Parse string literal
  defp parse_primary_token(state, {:string, _line, _col, _len, value, quote_type}) do
    {:ok, {:string_literal, value, quote_type}, advance(state)}
  end

  # Parse boolean literal
  defp parse_primary_token(state, {:boolean, _line, _col, _len, value}) do
    {:ok, {:literal, value}, advance(state)}
  end

  # Parse date literal
  defp parse_primary_token(state, {:date, _line, _col, _len, value}) do
    {:ok, {:literal, value}, advance(state)}
  end

  # Parse datetime literal
  defp parse_primary_token(state, {:datetime, _line, _col, _len, value}) do
    {:ok, {:literal, value}, advance(state)}
  end

  # Parse identifier
  defp parse_primary_token(state, {:identifier, _line, _col, _len, value}) do
    {:ok, {:identifier, value}, advance(state)}
  end

  # Parse function call
  defp parse_primary_token(state, {:function_name, _line, _col, _len, name}) do
    parse_function_call(state, name)
  end

  # Parse qualified function call (namespace.function)
  defp parse_primary_token(state, {:qualified_function_name, _line, _col, _len, name}) do
    parse_function_call(state, name)
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
  defp parse_primary_token(state, {:lbracket, _line, _col, _len, _value}) do
    parse_list(state)
  end

  # Parse object literal
  defp parse_primary_token(state, {:lbrace, _line, _col, _len, _value}) do
    parse_object(state)
  end

  # Parse duration direction keywords
  defp parse_primary_token(state, {:next_op, _line, _col, _len, _value}) do
    parse_relative_date_expression(state, :next)
  end

  defp parse_primary_token(state, {:last_op, _line, _col, _len, _value}) do
    parse_relative_date_expression(state, :last)
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
  @spec parse_list(parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_list(state) do
    # Consume opening bracket
    bracket_state = advance(state)

    case peek_token(bracket_state) do
      # Empty list
      {:rbracket, _line, _col, _len, _value} ->
        {:ok, {:list, []}, advance(bracket_state)}

      # Non-empty list
      _token ->
        case parse_list_elements(bracket_state, []) do
          {:ok, elements, final_state} ->
            case peek_token(final_state) do
              {:rbracket, _line, _col, _len, _value} ->
                {:ok, {:list, Enum.reverse(elements)}, advance(final_state)}

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
  @spec parse_object(parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_object(state) do
    # Consume opening brace
    brace_state = advance(state)

    case peek_token(brace_state) do
      # Empty object
      {:rbrace, _line, _col, _len, _value} ->
        {:ok, {:object, []}, advance(brace_state)}

      # Non-empty object
      _token ->
        case parse_object_entries(brace_state, []) do
          {:ok, entries, final_state} ->
            case peek_token(final_state) do
              {:rbrace, _line, _col, _len, _value} ->
                {:ok, {:object, Enum.reverse(entries)}, advance(final_state)}

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
      {:identifier, _line, _col, _len, value} ->
        {:ok, {:identifier, value}, advance(state)}

      {:string, _line, _col, _len, value, _quote_type} ->
        {:ok, {:string_literal, value}, advance(state)}

      {type, line, col, _len, value} ->
        {:error,
         "Expected identifier or string for object key but found #{format_token(type, value)}",
         line, col}

      nil ->
        {:error, "Expected object key but reached end of input", 1, 1}
    end
  end

  # Parse function call: function_name(arg1, arg2, ...)
  @spec parse_function_call(parser_state(), binary()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_function_call(state, function_name) do
    # Consume function name token
    func_state = advance(state)

    case peek_token(func_state) do
      {:lparen, _line, _col, _len, _value} ->
        # Consume opening parenthesis
        paren_state = advance(func_state)

        case peek_token(paren_state) do
          # Empty argument list
          {:rparen, _line, _col, _len, _value} ->
            {:ok, {:function_call, function_name, []}, advance(paren_state)}

          # Non-empty argument list
          _token ->
            case parse_function_arguments(paren_state, []) do
              {:ok, arguments, final_state} ->
                case peek_token(final_state) do
                  {:rparen, _line, _col, _len, _value} ->
                    {:ok, {:function_call, function_name, Enum.reverse(arguments)},
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

  @spec parse_duration_sequence_from_integer(integer(), parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), integer(), integer()} | :not_duration
  defp parse_duration_sequence_from_integer(number, state) do
    case peek_token(state) do
      {:duration_unit, _line, _col, _len, unit} ->
        # Found duration unit, parse the full duration sequence
        parse_duration_sequence([{number, unit}], advance(state))

      _token ->
        # Not followed by duration unit
        :not_duration
    end
  end

  @spec parse_duration_sequence([{integer(), binary()}], parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), integer(), integer()}
  defp parse_duration_sequence(units, state) do
    case peek_token(state) do
      {:integer, _line, _col, _len, number} ->
        # Check if this integer is followed by a duration unit
        next_state = advance(state)

        case peek_token(next_state) do
          {:duration_unit, _line, _col, _len, unit} ->
            # Continue building duration sequence
            new_units = units ++ [{number, unit}]
            parse_duration_sequence(new_units, advance(next_state))

          _token ->
            # End of duration sequence, check for direction operators
            duration_ast = {:duration, Enum.reverse(units)}
            parse_duration_with_direction(duration_ast, state)
        end

      _token ->
        # End of duration sequence, check for direction operators
        duration_ast = {:duration, Enum.reverse(units)}
        parse_duration_with_direction(duration_ast, state)
    end
  end

  @spec parse_duration_with_direction(ast(), parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), integer(), integer()}
  defp parse_duration_with_direction(duration_ast, state) do
    case peek_token(state) do
      {:ago_op, _line, _col, _len, _value} ->
        {:ok, {:relative_date, duration_ast, :ago}, advance(state)}

      {:from_op, _line, _col, _len, _value} ->
        # Expect 'now' after 'from'
        from_state = advance(state)

        case peek_token(from_state) do
          {:now_op, _line, _col, _len, _value} ->
            {:ok, {:relative_date, duration_ast, :future}, advance(from_state)}

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

  @spec parse_relative_date_expression(parser_state(), relative_direction()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_relative_date_expression(state, direction) do
    # Advance past the direction keyword (next/last)
    next_state = advance(state)

    # Expect a duration expression
    case parse_primary(next_state) do
      {:ok, {:duration, _units} = duration_ast, final_state} ->
        {:ok, {:relative_date, duration_ast, direction}, final_state}

      {:ok, _other_ast, _final_state} ->
        {type, line, col, _len, value} = peek_token(next_state)

        {:error, "Expected duration after '#{direction}' but found #{format_token(type, value)}",
         line, col}

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end
end
