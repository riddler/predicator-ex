defmodule Predicator.Lexer do
  # Disable credo checks that are inherent to recursive descent parsing
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

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
          | {:float, pos_integer(), pos_integer(), pos_integer(), float()}
          | {:string, pos_integer(), pos_integer(), pos_integer(), binary(), :double | :single}
          | {:boolean, pos_integer(), pos_integer(), pos_integer(), boolean()}
          | {:date, pos_integer(), pos_integer(), pos_integer(), Date.t()}
          | {:datetime, pos_integer(), pos_integer(), pos_integer(), DateTime.t()}
          | {:gt, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:lt, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:gte, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:lte, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:eq, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:ne, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:equal_equal, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:plus, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:minus, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:multiply, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:divide, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:modulo, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:and_and, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:or_or, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:bang, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:and_op, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:or_op, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:not_op, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:lparen, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:rparen, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:lbracket, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:rbracket, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:lbrace, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:rbrace, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:colon, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:comma, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:dot, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:in_op, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:contains_op, pos_integer(), pos_integer(), pos_integer(), binary()}
          | {:function_name, pos_integer(), pos_integer(), pos_integer(), binary()}
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
        {:string, 1, 8, 6, "John", :double},
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

        token =
          if is_integer(number) do
            {:integer, line, col, consumed, number}
          else
            {:float, line, col, consumed, number}
          end

        tokenize_chars(remaining, line, col + consumed, [token | tokens])

      # Identifiers (including potential function calls)
      c when (c >= ?a and c <= ?z) or (c >= ?A and c <= ?Z) or c == ?_ ->
        {identifier, remaining, consumed} = take_identifier([char | rest])

        # Check if this is a function call by looking ahead for '('
        case skip_whitespace(remaining) do
          [?( | _rest] ->
            # Check if this identifier is a keyword that should not become a function
            case classify_identifier(identifier) do
              {:identifier, _value} ->
                # This is a regular identifier followed by '(', so it's a function call
                token = {:function_name, line, col, consumed, identifier}
                tokenize_chars(remaining, line, col + consumed, [token | tokens])

              {token_type, value} ->
                # This is a keyword, keep it as the keyword (don't make it a function)
                token = {token_type, line, col, consumed, value}
                tokenize_chars(remaining, line, col + consumed, [token | tokens])
            end

          _no_function_call ->
            # Regular identifier or keyword
            {token_type, value} = classify_identifier(identifier)
            token = {token_type, line, col, consumed, value}
            tokenize_chars(remaining, line, col + consumed, [token | tokens])
        end

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
            token = {:bang, line, col, 1, "!"}
            tokenize_chars(rest, line, col + 1, [token | tokens])
        end

      ?= ->
        case rest do
          [?= | rest2] ->
            token = {:equal_equal, line, col, 2, "=="}
            tokenize_chars(rest2, line, col + 2, [token | tokens])

          _rest ->
            token = {:eq, line, col, 1, "="}
            tokenize_chars(rest, line, col + 1, [token | tokens])
        end

      ?+ ->
        token = {:plus, line, col, 1, "+"}
        tokenize_chars(rest, line, col + 1, [token | tokens])

      ?- ->
        token = {:minus, line, col, 1, "-"}
        tokenize_chars(rest, line, col + 1, [token | tokens])

      ?* ->
        token = {:multiply, line, col, 1, "*"}
        tokenize_chars(rest, line, col + 1, [token | tokens])

      ?/ ->
        token = {:divide, line, col, 1, "/"}
        tokenize_chars(rest, line, col + 1, [token | tokens])

      ?% ->
        token = {:modulo, line, col, 1, "%"}
        tokenize_chars(rest, line, col + 1, [token | tokens])

      ?& ->
        case rest do
          [?& | rest2] ->
            token = {:and_and, line, col, 2, "&&"}
            tokenize_chars(rest2, line, col + 2, [token | tokens])

          _rest ->
            {:error, "Unexpected character '&'", line, col}
        end

      ?| ->
        case rest do
          [?| | rest2] ->
            token = {:or_or, line, col, 2, "||"}
            tokenize_chars(rest2, line, col + 2, [token | tokens])

          _rest ->
            {:error, "Unexpected character '|'", line, col}
        end

      ?( ->
        token = {:lparen, line, col, 1, "("}
        tokenize_chars(rest, line, col + 1, [token | tokens])

      ?) ->
        token = {:rparen, line, col, 1, ")"}
        tokenize_chars(rest, line, col + 1, [token | tokens])

      ?[ ->
        token = {:lbracket, line, col, 1, "["}
        tokenize_chars(rest, line, col + 1, [token | tokens])

      ?] ->
        token = {:rbracket, line, col, 1, "]"}
        tokenize_chars(rest, line, col + 1, [token | tokens])

      ?{ ->
        token = {:lbrace, line, col, 1, "{"}
        tokenize_chars(rest, line, col + 1, [token | tokens])

      ?} ->
        token = {:rbrace, line, col, 1, "}"}
        tokenize_chars(rest, line, col + 1, [token | tokens])

      ?: ->
        token = {:colon, line, col, 1, ":"}
        tokenize_chars(rest, line, col + 1, [token | tokens])

      ?, ->
        token = {:comma, line, col, 1, ","}
        tokenize_chars(rest, line, col + 1, [token | tokens])

      ?. ->
        token = {:dot, line, col, 1, "."}
        tokenize_chars(rest, line, col + 1, [token | tokens])

      # String literals (double quotes)
      ?" ->
        case take_string(rest, "", 1, :double) do
          {:ok, content, remaining, consumed} ->
            # +1 for opening quote
            token = {:string, line, col, consumed + 1, content, :double}
            tokenize_chars(remaining, line, col + consumed + 1, [token | tokens])

          {:error, message} ->
            {:error, message, line, col}
        end

      # String literals (single quotes)
      ?' ->
        case take_string(rest, "", 1, :single) do
          {:ok, content, remaining, consumed} ->
            # +1 for opening quote
            token = {:string, line, col, consumed + 1, content, :single}
            tokenize_chars(remaining, line, col + consumed + 1, [token | tokens])

          {:error, message} ->
            {:error, message, line, col}
        end

      # Date literals
      ?# ->
        case take_date(rest, "", 1) do
          {:ok, date_value, remaining, consumed, token_type} ->
            # +1 for opening #
            token = {token_type, line, col, consumed + 1, date_value}
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
  @spec take_number(charlist()) :: {number(), charlist(), pos_integer()}
  defp take_number(chars), do: take_number(chars, [], 0, false)

  @spec take_number(charlist(), charlist(), non_neg_integer(), boolean()) ::
          {number(), charlist(), pos_integer()}
  defp take_number([c | rest], acc, count, has_decimal) when c >= ?0 and c <= ?9 do
    take_number(rest, [c | acc], count + 1, has_decimal)
  end

  # Handle decimal point - only one allowed
  defp take_number([?. | rest] = chars, acc, count, false) do
    # Check if there's at least one digit after the decimal
    case rest do
      [next | _remaining] when next >= ?0 and next <= ?9 ->
        take_number(rest, [?. | acc], count + 1, true)

      _no_digits_after_decimal ->
        # No digit after decimal, treat as end of number
        finalize_number(chars, acc, count, false)
    end
  end

  defp take_number(remaining, acc, count, has_decimal) do
    finalize_number(remaining, acc, count, has_decimal)
  end

  defp finalize_number(remaining, acc, count, has_decimal) do
    number_string = acc |> Enum.reverse() |> List.to_string()

    number =
      if has_decimal do
        String.to_float(number_string)
      else
        String.to_integer(number_string)
      end

    {number, remaining, count}
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
  defp classify_identifier("and"), do: {:and_op, "and"}
  defp classify_identifier("or"), do: {:or_op, "or"}
  defp classify_identifier("not"), do: {:not_op, "not"}
  defp classify_identifier("IN"), do: {:in_op, "IN"}
  defp classify_identifier("in"), do: {:in_op, "in"}
  defp classify_identifier("CONTAINS"), do: {:contains_op, "CONTAINS"}
  defp classify_identifier("contains"), do: {:contains_op, "contains"}
  defp classify_identifier(id), do: {:identifier, id}

  # Helper function to skip whitespace characters for lookahead
  @spec skip_whitespace(charlist()) :: charlist()
  defp skip_whitespace([?\s | rest]), do: skip_whitespace(rest)
  defp skip_whitespace([?\t | rest]), do: skip_whitespace(rest)
  defp skip_whitespace([?\n | rest]), do: skip_whitespace(rest)
  defp skip_whitespace([?\r | rest]), do: skip_whitespace(rest)
  defp skip_whitespace(chars), do: chars

  @spec take_string(charlist(), binary(), pos_integer(), :double | :single) ::
          {:ok, binary(), charlist(), pos_integer()} | {:error, binary()}
  defp take_string([], _acc, _count, quote_type) do
    quote_name = if quote_type == :double, do: "double", else: "single"
    {:error, "Unterminated #{quote_name}-quoted string literal"}
  end

  defp take_string([?" | rest], acc, count, :double) do
    {:ok, acc, rest, count}
  end

  defp take_string([?' | rest], acc, count, :single) do
    {:ok, acc, rest, count}
  end

  defp take_string([?\\ | [escaped | rest]], acc, count, quote_type) do
    char =
      case escaped do
        ?" -> "\""
        ?' -> "'"
        ?\\ -> "\\"
        ?n -> "\n"
        ?t -> "\t"
        ?r -> "\r"
        c -> <<c>>
      end

    take_string(rest, acc <> char, count + 2, quote_type)
  end

  defp take_string([c | rest], acc, count, quote_type) do
    take_string(rest, acc <> <<c>>, count + 1, quote_type)
  end

  @spec take_date(charlist(), binary(), pos_integer()) ::
          {:ok, Date.t() | DateTime.t(), charlist(), pos_integer(), :date | :datetime}
          | {:error, binary()}
  defp take_date([], _acc, _count), do: {:error, "Unterminated date literal"}

  defp take_date([?# | rest], acc, count) do
    case parse_date_content(acc) do
      {:ok, date_value, token_type} ->
        {:ok, date_value, rest, count, token_type}

      {:error, message} ->
        {:error, message}
    end
  end

  defp take_date([c | rest], acc, count) do
    take_date(rest, acc <> <<c>>, count + 1)
  end

  @spec parse_date_content(binary()) ::
          {:ok, Date.t() | DateTime.t(), :date | :datetime} | {:error, binary()}
  defp parse_date_content(content) do
    if String.contains?(content, "T") do
      # Check for DateTime first (contains T)
      case DateTime.from_iso8601(content) do
        {:ok, datetime, _offset} -> {:ok, datetime, :datetime}
        {:error, _reason} -> {:error, "Invalid datetime format: #{content}"}
      end
    else
      # Try Date format
      case Date.from_iso8601(content) do
        {:ok, date} -> {:ok, date, :date}
        {:error, _reason} -> {:error, "Invalid date format: #{content}"}
      end
    end
  end
end
