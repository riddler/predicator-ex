defmodule Predicator.Lexer do
  @moduledoc """
  Lexical analyzer for predicator expressions.

  The lexer converts input strings into a stream of tokens with complete
  position tracking for detailed error reporting. Each token includes:
  - Token type and value
  - Line and column position
  - Length for precise error highlighting

  ## Example

      iex> Predicator.Lexer.tokenize("score > 85")
      {:ok, [
        {:identifier, 1, 1, 5, "score"},
        {:gt, 1, 7, 1, ">"},  
        {:integer, 1, 9, 2, 85},
        {:eof, 1, 11, 0, nil}
      ]}
  """

  @typedoc """
  Position information for a token.

  Contains:
  - `line` - 1-based line number
  - `column` - 1-based column number  
  - `length` - number of characters in the token
  """
  @type position :: {line :: pos_integer(), column :: pos_integer(), length :: pos_integer()}

  @typedoc """
  A lexical token with position information.

  Format: `{type, line, column, length, value}`
  """
  @type token ::
          {:identifier, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:integer, pos_integer(), pos_integer(), pos_integer(), integer()}
          | {:string, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:boolean, pos_integer(), pos_integer(), pos_integer(), boolean()}
          | {:gt, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:lt, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:gte, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:lte, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:eq, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:ne, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:and_op, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:or_op, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:not_op, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:lparen, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:rparen, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:eof, pos_integer(), pos_integer(), pos_integer(), nil}

  @typedoc """
  Lexer result - either success with tokens or error with details.
  """
  @type result :: {:ok, [token()]} | {:error, binary(), pos_integer(), pos_integer()}

  @typedoc """
  Internal lexer state for position tracking.
  """
  @type lexer_state :: %{
          input: binary(),
          position: non_neg_integer(),
          line: pos_integer(),
          column: pos_integer(),
          tokens: [token()]
        }

  @doc """
  Tokenizes an input string into a list of tokens.

  ## Parameters

  - `input` - The expression string to tokenize

  ## Returns

  - `{:ok, tokens}` - Successfully tokenized input
  - `{:error, message, line, column}` - Lexical error with position

  ## Examples

      iex> Predicator.Lexer.tokenize("score > 85")
      {:ok, [
        {:identifier, 1, 1, 5, "score"},
        {:gt, 1, 7, 1, ">"},
        {:integer, 1, 9, 2, 85},
        {:eof, 1, 11, 0, nil}
      ]}

      iex> Predicator.Lexer.tokenize("age >= 18")
      {:ok, [
        {:identifier, 1, 1, 3, "age"},
        {:gte, 1, 5, 2, ">="},
        {:integer, 1, 8, 2, 18},
        {:eof, 1, 10, 0, nil}
      ]}

      iex> Predicator.Lexer.tokenize("name = \\"John\\"")
      {:ok, [
        {:identifier, 1, 1, 4, "name"},
        {:eq, 1, 6, 1, "="},
        {:string, 1, 8, 6, "John"},
        {:eof, 1, 14, 0, nil}
      ]}

      iex> Predicator.Lexer.tokenize("score > 85 AND age >= 18")
      {:ok, [
        {:identifier, 1, 1, 5, "score"},
        {:gt, 1, 7, 1, ">"},
        {:integer, 1, 9, 2, 85},
        {:and_op, 1, 12, 3, "AND"},
        {:identifier, 1, 16, 3, "age"},
        {:gte, 1, 20, 2, ">="},
        {:integer, 1, 23, 2, 18},
        {:eof, 1, 25, 0, nil}
      ]}
  """
  @spec tokenize(binary()) :: result()
  def tokenize(input) when is_binary(input) do
    input
    |> String.to_charlist()
    |> tokenize_chars(1, 1, [])
  end

  # Main tokenization function
  @spec tokenize_chars(charlist(), pos_integer(), pos_integer(), [token()]) :: result()
  defp tokenize_chars([], line, col, tokens) do
    {:ok, Enum.reverse([{:eof, line, col, 0, nil} | tokens])}
  end

  # NOTE: High cyclomatic complexity (28) is expected and appropriate for lexer functions.
  # This function must handle all possible input characters and token types in a single
  # pattern matching expression, which naturally results in high complexity but is the
  # correct approach for lexical analysis. The complexity is well-contained and tested.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp tokenize_chars([char | rest], line, col, tokens) do
    case char do
      # Skip whitespace
      ?\s ->
        tokenize_chars(rest, line, col + 1, tokens)

      ?\t ->
        tokenize_chars(rest, line, col + 1, tokens)

      ?\n ->
        tokenize_chars(rest, line + 1, 1, tokens)

      ?\r ->
        tokenize_chars(rest, line, col, tokens)

      # Numbers
      c when c >= ?0 and c <= ?9 ->
        {number, remaining, consumed} = take_number([char | rest])
        token = {:integer, line, col, consumed, number}
        tokenize_chars(remaining, line, col + consumed, [token | tokens])

      # Identifiers
      c when (c >= ?a and c <= ?z) or (c >= ?A and c <= ?Z) or c == ?_ ->
        {identifier, remaining, consumed} = take_identifier([char | rest])
        {token_type, value} = classify_identifier(identifier)
        token = {token_type, line, col, consumed, value}
        tokenize_chars(remaining, line, col + consumed, [token | tokens])

      # Operators
      ?> ->
        case rest do
          [?= | rest2] ->
            token = {:gte, line, col, 2, ">="}
            tokenize_chars(rest2, line, col + 2, [token | tokens])

          _rest ->
            token = {:gt, line, col, 1, ">"}
            tokenize_chars(rest, line, col + 1, [token | tokens])
        end

      ?< ->
        case rest do
          [?= | rest2] ->
            token = {:lte, line, col, 2, "<="}
            tokenize_chars(rest2, line, col + 2, [token | tokens])

          _rest ->
            token = {:lt, line, col, 1, "<"}
            tokenize_chars(rest, line, col + 1, [token | tokens])
        end

      ?! ->
        case rest do
          [?= | rest2] ->
            token = {:ne, line, col, 2, "!="}
            tokenize_chars(rest2, line, col + 2, [token | tokens])

          _rest ->
            {:error, "Unexpected character '!'", line, col}
        end

      ?= ->
        token = {:eq, line, col, 1, "="}
        tokenize_chars(rest, line, col + 1, [token | tokens])

      ?( ->
        token = {:lparen, line, col, 1, "("}
        tokenize_chars(rest, line, col + 1, [token | tokens])

      ?) ->
        token = {:rparen, line, col, 1, ")"}
        tokenize_chars(rest, line, col + 1, [token | tokens])

      # String literals
      ?" ->
        case take_string(rest, "", 1) do
          {:ok, content, remaining, consumed} ->
            # +1 for opening quote
            token = {:string, line, col, consumed + 1, content}
            tokenize_chars(remaining, line, col + consumed + 1, [token | tokens])

          {:error, message} ->
            {:error, message, line, col}
        end

      # Unknown character
      _char ->
        {:error, "Unexpected character '#{[char]}'", line, col}
    end
  end

  # Helper functions
  @spec take_number(charlist()) :: {integer(), charlist(), pos_integer()}
  defp take_number(chars), do: take_number(chars, [], 0)

  @spec take_number(charlist(), charlist(), non_neg_integer()) ::
          {integer(), charlist(), pos_integer()}
  defp take_number([c | rest], acc, count) when c >= ?0 and c <= ?9 do
    take_number(rest, [c | acc], count + 1)
  end

  defp take_number(remaining, acc, count) do
    number_string = acc |> Enum.reverse() |> List.to_string()
    {String.to_integer(number_string), remaining, count}
  end

  @spec take_identifier(charlist()) :: {binary(), charlist(), pos_integer()}
  defp take_identifier(chars), do: take_identifier(chars, [], 0)

  @spec take_identifier(charlist(), charlist(), non_neg_integer()) ::
          {binary(), charlist(), pos_integer()}
  defp take_identifier([c | rest], acc, count)
       when (c >= ?a and c <= ?z) or (c >= ?A and c <= ?Z) or (c >= ?0 and c <= ?9) or c == ?_ do
    take_identifier(rest, [c | acc], count + 1)
  end

  defp take_identifier(remaining, acc, count) do
    identifier = acc |> Enum.reverse() |> List.to_string()
    {identifier, remaining, count}
  end

  @spec classify_identifier(binary()) :: {atom(), binary() | boolean()}
  defp classify_identifier("true"), do: {:boolean, true}
  defp classify_identifier("false"), do: {:boolean, false}
  defp classify_identifier("AND"), do: {:and_op, "AND"}
  defp classify_identifier("OR"), do: {:or_op, "OR"}
  defp classify_identifier("NOT"), do: {:not_op, "NOT"}
  defp classify_identifier(id), do: {:identifier, id}

  @spec take_string(charlist(), binary(), pos_integer()) ::
          {:ok, binary(), charlist(), pos_integer()} | {:error, binary()}
  defp take_string([], _acc, _count), do: {:error, "Unterminated string literal"}

  defp take_string([?" | rest], acc, count) do
    {:ok, acc, rest, count}
  end

  defp take_string([?\\ | [escaped | rest]], acc, count) do
    char =
      case escaped do
        ?" -> "\""
        ?\\ -> "\\"
        ?n -> "\n"
        ?t -> "\t"
        ?r -> "\r"
        c -> <<c>>
      end

    take_string(rest, acc <> char, count + 2)
  end

  defp take_string([c | rest], acc, count) do
    take_string(rest, acc <> <<c>>, count + 1)
  end
end
