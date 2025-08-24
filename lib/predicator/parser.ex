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
      logical_not  → "NOT" | "!" logical_not | equality
      equality     → comparison ( ( "==" | "!=" ) comparison )*
      comparison   → addition ( ( ">" | "<" | ">=" | "<=" | "=" | "in" | "contains" ) addition )?
      addition     → multiplication ( ( "+" | "-" ) multiplication )*
      multiplication → unary ( ( "*" | "/" | "%" ) unary )*
      unary        → ( "-" | "!" ) unary | primary
      primary      → NUMBER | STRING | BOOLEAN | DATE | DATETIME | IDENTIFIER | function_call | list | "(" expression ")"
      function_call → FUNCTION_NAME "(" ( expression ( "," expression )* )? ")"
      list         → "[" ( expression ( "," expression )* )? "]"

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
  @type value :: boolean() | integer() | binary() | [value()] | Date.t() | DateTime.t()

  @typedoc """
  Abstract Syntax Tree node types.

  - `{:literal, value}` - A literal value (number, boolean, list, date, datetime)
  - `{:string_literal, value, quote_type}` - A string literal with quote type information
  - `{:identifier, name}` - A variable reference
  - `{:comparison, operator, left, right}` - A comparison expression
  - `{:equality, operator, left, right}` - An equality expression (== !=)
  - `{:arithmetic, operator, left, right}` - An arithmetic expression (+, -, *, /, %)
  - `{:unary, operator, operand}` - A unary expression (-, !)
  - `{:logical_and, left, right}` - A logical AND expression
  - `{:logical_or, left, right}` - A logical OR expression
  - `{:logical_not, operand}` - A logical NOT expression
  - `{:list, elements}` - A list literal
  - `{:membership, operator, left, right}` - A membership operation (in/contains)
  - `{:function_call, name, arguments}` - A function call with arguments
  """
  @type ast ::
          {:literal, value()}
          | {:string_literal, binary(), :double | :single}
          | {:identifier, binary()}
          | {:comparison, comparison_op(), ast(), ast()}
          | {:equality, equality_op(), ast(), ast()}
          | {:arithmetic, arithmetic_op(), ast(), ast()}
          | {:unary, unary_op(), ast()}
          | {:membership, membership_op(), ast(), ast()}
          | {:logical_and, ast(), ast()}
          | {:logical_or, ast(), ast()}
          | {:logical_not, ast()}
          | {:list, [ast()]}
          | {:function_call, binary(), [ast()]}

  @typedoc """
  Comparison operators in the AST.
  """
  @type comparison_op :: :gt | :lt | :gte | :lte | :eq

  @typedoc """
  Equality operators in the AST.
  """
  @type equality_op :: :equal_equal | :ne

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

  # No NOT operator, parse equality
  defp parse_logical_not_token(state, _token) do
    parse_equality(state)
  end

  # Parse equality expressions (== !=)
  @spec parse_equality(parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_equality(state) do
    case parse_comparison(state) do
      {:ok, left, new_state} ->
        parse_equality_rest(left, new_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  @spec parse_equality_rest(ast(), parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_equality_rest(left, state) do
    token = peek_token(state)
    parse_equality_rest_token(left, state, token)
  end

  # Parse == operator
  defp parse_equality_rest_token(left, state, {:equal_equal, _line, _col, _len, _value}) do
    eq_state = advance(state)

    case parse_comparison(eq_state) do
      {:ok, right, final_state} ->
        ast = {:equality, :equal_equal, left, right}
        parse_equality_rest(ast, final_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # Parse != operator
  defp parse_equality_rest_token(left, state, {:ne, _line, _col, _len, _value}) do
    ne_state = advance(state)

    case parse_comparison(ne_state) do
      {:ok, right, final_state} ->
        ast = {:equality, :ne, left, right}
        parse_equality_rest(ast, final_state)

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # No equality operator, return left operand
  defp parse_equality_rest_token(left, state, _token) do
    {:ok, left, state}
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
          # Comparison operators
          {op_type, _line, _col, _len, _value}
          when op_type in [:gt, :lt, :gte, :lte, :eq] ->
            operator = map_operator(op_type)
            op_state = advance(new_state)

            case parse_addition(op_state) do
              {:ok, right, final_state} ->
                ast = {:comparison, operator, left, right}
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

  # No unary operator, parse primary
  defp parse_unary_token(state, _token) do
    parse_primary(state)
  end

  # Parse primary expressions (literals, identifiers, parentheses)
  # This function handles multiple token types and nested error cases - inherent parser complexity
  @spec parse_primary(parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_primary(state) do
    token = peek_token(state)
    parse_primary_token(state, token)
  end

  # Parse integer literal
  defp parse_primary_token(state, {:integer, _line, _col, _len, value}) do
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

  # Handle unexpected tokens
  defp parse_primary_token(_state, {type, line, col, _len, value}) do
    expected = "number, string, boolean, date, datetime, identifier, function call, list, or '('"
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

  @spec map_operator(atom()) :: comparison_op()
  defp map_operator(:gt), do: :gt
  defp map_operator(:lt), do: :lt
  defp map_operator(:gte), do: :gte
  defp map_operator(:lte), do: :lte
  defp map_operator(:eq), do: :eq

  @spec map_membership_operator(atom()) :: membership_op()
  defp map_membership_operator(:in_op), do: :in
  defp map_membership_operator(:contains_op), do: :contains

  @spec format_token(atom(), term()) :: binary()
  defp format_token(:integer, value), do: "number '#{value}'"
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
  defp format_token(:and_op, _value), do: "'AND'"
  defp format_token(:or_op, _value), do: "'OR'"
  defp format_token(:not_op, _value), do: "'NOT'"
  defp format_token(:in_op, _value), do: "'IN'"
  defp format_token(:contains_op, _value), do: "'CONTAINS'"
  defp format_token(:lparen, _value), do: "'('"
  defp format_token(:rparen, _value), do: "')'"
  defp format_token(:lbracket, _value), do: "'['"
  defp format_token(:rbracket, _value), do: "']'"
  defp format_token(:comma, _value), do: "','"
  defp format_token(:plus, _value), do: "'+'"
  defp format_token(:minus, _value), do: "'-'"
  defp format_token(:multiply, _value), do: "'*'"
  defp format_token(:divide, _value), do: "'/'"
  defp format_token(:modulo, _value), do: "'%'"
  defp format_token(:equal_equal, _value), do: "'=='"
  defp format_token(:and_and, _value), do: "'&&'"
  defp format_token(:or_or, _value), do: "'||'"
  defp format_token(:bang, _value), do: "'!'"
  defp format_token(:function_name, value), do: "function '#{value}'"
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
end
