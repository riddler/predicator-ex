defmodule Predicator.Parser do
  @moduledoc """
  Recursive descent parser for predicator expressions.

  The parser converts a stream of tokens from the lexer into an Abstract Syntax Tree (AST)
  with comprehensive error reporting including exact position information.

  ## Grammar

  The parser implements this grammar with proper operator precedence:

      expression   → logical_or
      logical_or   → logical_and ( "OR" logical_and )*
      logical_and  → logical_not ( "AND" logical_not )*
      logical_not  → "NOT" logical_not | comparison
      comparison   → primary ( ( ">" | "<" | ">=" | "<=" | "=" | "!=" ) primary )?
      primary      → NUMBER | STRING | BOOLEAN | IDENTIFIER | "(" expression ")"

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
  @type value :: boolean() | integer() | binary()

  @typedoc """
  Abstract Syntax Tree node types.

  - `{:literal, value}` - A literal value (number, string, boolean)
  - `{:identifier, name}` - A variable reference
  - `{:comparison, operator, left, right}` - A comparison expression
  - `{:logical_and, left, right}` - A logical AND expression
  - `{:logical_or, left, right}` - A logical OR expression
  - `{:logical_not, operand}` - A logical NOT expression
  """
  @type ast ::
          {:literal, value()}
          | {:identifier, binary()}
          | {:comparison, comparison_op(), ast(), ast()}
          | {:logical_and, ast(), ast()}
          | {:logical_or, ast(), ast()}
          | {:logical_not, ast()}

  @typedoc """
  Comparison operators in the AST.
  """
  @type comparison_op :: :gt | :lt | :gte | :lte | :eq | :ne

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
      {:ok, {:comparison, :eq, {:identifier, "name"}, {:literal, "John"}}}

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
    case peek_token(state) do
      {:or_op, _line, _col, _len, _value} ->
        or_state = advance(state)

        case parse_logical_and(or_state) do
          {:ok, right, final_state} ->
            ast = {:logical_or, left, right}
            parse_logical_or_rest(ast, final_state)

          {:error, message, line, col} ->
            {:error, message, line, col}
        end

      _token ->
        {:ok, left, state}
    end
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
    case peek_token(state) do
      {:and_op, _line, _col, _len, _value} ->
        and_state = advance(state)

        case parse_logical_not(and_state) do
          {:ok, right, final_state} ->
            ast = {:logical_and, left, right}
            parse_logical_and_rest(ast, final_state)

          {:error, message, line, col} ->
            {:error, message, line, col}
        end

      _token ->
        {:ok, left, state}
    end
  end

  # Parse logical NOT expressions (highest precedence)
  @spec parse_logical_not(parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  defp parse_logical_not(state) do
    case peek_token(state) do
      {:not_op, _line, _col, _len, _value} ->
        not_state = advance(state)

        case parse_logical_not(not_state) do
          {:ok, operand, final_state} ->
            ast = {:logical_not, operand}
            {:ok, ast, final_state}

          {:error, message, line, col} ->
            {:error, message, line, col}
        end

      _token ->
        parse_comparison(state)
    end
  end

  # Parse comparison expressions
  # NOTE: Nesting depth (3) is expected and appropriate for recursive descent parsing.
  # The nested case statements handle: parse left operand -> check for operator ->
  # parse right operand -> construct AST, with proper error propagation at each step.
  @spec parse_comparison(parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  # credo:disable-for-lines:27 Credo.Check.Refactor.Nesting
  defp parse_comparison(state) do
    case parse_primary(state) do
      {:ok, left, new_state} ->
        case peek_token(new_state) do
          # Comparison operators
          {op_type, _line, _col, _len, _value}
          when op_type in [:gt, :lt, :gte, :lte, :eq, :ne] ->
            operator = map_operator(op_type)
            op_state = advance(new_state)

            case parse_primary(op_state) do
              {:ok, right, final_state} ->
                ast = {:comparison, operator, left, right}
                {:ok, ast, final_state}

              {:error, message, line, col} ->
                {:error, message, line, col}
            end

          # Not a comparison, return the primary expression
          _token ->
            {:ok, left, new_state}
        end

      {:error, message, line, col} ->
        {:error, message, line, col}
    end
  end

  # Parse primary expressions (literals, identifiers, parentheses)
  # This function handles multiple token types and nested error cases - inherent parser complexity
  @spec parse_primary(parser_state()) ::
          {:ok, ast(), parser_state()} | {:error, binary(), pos_integer(), pos_integer()}
  # credo:disable-for-lines:46 Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-lines:46 Credo.Check.Refactor.Nesting
  defp parse_primary(state) do
    case peek_token(state) do
      # Literals
      {:integer, _line, _col, _len, value} ->
        {:ok, {:literal, value}, advance(state)}

      {:string, _line, _col, _len, value} ->
        {:ok, {:literal, value}, advance(state)}

      {:boolean, _line, _col, _len, value} ->
        {:ok, {:literal, value}, advance(state)}

      # Identifiers
      {:identifier, _line, _col, _len, value} ->
        {:ok, {:identifier, value}, advance(state)}

      # Parenthesized expressions
      {:lparen, _line, _col, _len, _value} ->
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

      # Unexpected tokens
      {type, line, col, _len, value} ->
        expected = "number, string, boolean, identifier, or '('"
        {:error, "Expected #{expected} but found #{format_token(type, value)}", line, col}

      # End of input
      nil ->
        {:error, "Unexpected end of input", 1, 1}
    end
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
  defp map_operator(:ne), do: :ne

  @spec format_token(atom(), term()) :: binary()
  defp format_token(:integer, value), do: "number '#{value}'"
  defp format_token(:string, value), do: "string \"#{value}\""
  defp format_token(:boolean, value), do: "boolean '#{value}'"
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
  defp format_token(:lparen, _value), do: "'('"
  defp format_token(:rparen, _value), do: "')'"
  defp format_token(:eof, _value), do: "end of input"
end
