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

      program      → statement ( ";" statement )* ( ";" )?
      statement    → if_statement | while_statement | assignment | expression
      if_statement → "if" expression block ( "else" ( block | if_statement ) )?
      while_statement → "while" expression block
      block        → "{" ( statement ( ";" statement )* ( ";" )? )? "}"
      assignment   → location "=" expression
      location     → IDENTIFIER ( "." IDENTIFIER | "[" expression "]" )*
      expression   → logical_or
      logical_or   → logical_and ( "OR" | "||" logical_and )*
      logical_and  → logical_not ( "AND" | "&&" logical_not )*
      logical_not  → "NOT" | "!" logical_not | comparison
      comparison   → addition ( ( ">" | "<" | ">=" | "<=" | "==" | "!=" | "===" | "!==" | "in" | "contains" ) addition )?
      addition     → multiplication ( ( "+" | "-" ) multiplication )*
      multiplication → unary ( ( "*" | "/" | "%" ) unary )*
      unary        → ( "-" | "!" ) unary | postfix
      postfix      → primary ( "[" expression "]" | "." IDENTIFIER | "::" TYPE_NAME )*
      TYPE_NAME    → "integer" | "float" | "string" | "boolean" | "date" | "datetime" | "duration"
      primary      → NUMBER | FLOAT | STRING | BOOLEAN | DATE | DATETIME | IDENTIFIER | duration | relative_date | function_call | list | object | "(" expression ")"
      function_call → FUNCTION_NAME "(" ( expression ( "," expression )* )? ")"
      list         → "[" ( expression ( "," expression )* )? "]"
      object       → "{" ( object_entry ( "," object_entry )* )? "}"
      object_entry → object_key ":" expression
      object_key   → IDENTIFIER | STRING
      duration     → NUMBER UNIT+
      relative_date → duration "ago" | duration "from" "now" | "next" duration | "last" duration

  `TYPE_NAME` is matched contextually against an `IDENTIFIER` token rather than
  lexed as its own keyword, so the seven names remain usable as variables,
  properties, and object keys everywhere else (ADR-0011).

  Two entry points reach those two grammars. `parse/2` parses the `expression`
  production alone and rejects a top-level `=`; `parse_program/2` parses the
  `program` production and is the only place `assignment` is legal. The mode -
  expression or statement - belongs to the entry point rather than to anything
  in the token stream, which is the same split `docs/isa.md` draws between
  `Predicator.evaluate/2,3` and `Predicator.execute/2`.

  `=` is assignment, not equality: it is valid only at the start of a statement
  and only with an assignable left side. A bare `=` in expression position is a
  parse error naming `==` as the fix. `==` and `===` are the only equality
  operators.

  ## Source positions

  Every AST node carries a trailing `{line, column}` giving the 1-based position
  of the token that defines it. Leaves point at their own token; operators point
  at the operator token, so the `arithmetic` node in `a * true` reports column 3.

  A node built by a caller rather than parsed carries `nil` in that slot. The
  slot is not optional: there is one AST shape, and the visitors match on it.

  ## Source spans

  Pass `spans: true` to `parse/2` and the same trailing slot carries a
  `t:Predicator.Types.span/0` instead - the source text the node covers, which
  is what a diagnostic underlines.

      # default
      {:arithmetic, :multiply, {:identifier, "a", {1, 1}}, {:literal, true, {1, 5}}, {1, 3}}

      # spans: true
      {:arithmetic, :multiply,
        {:identifier, "a", {{1, 1}, {1, 2}}},
        {:literal, true, {{1, 5}, {1, 9}}},
        {{1, 1}, {1, 9}}}

  A span's end is exclusive - one past the last character - so on a single line
  `end_column - start_column` is the length, matching LSP ranges. One parse
  produces one kind of metadata throughout; positions and spans are never mixed
  in a single tree.

  A parenthesized expression's span widens to include its parentheses: `(a + b)`
  gives the `arithmetic` node the span of `(a + b)`, not just `a + b`, so the
  span always reads as balanced. Nesting composes to the outermost pair -
  `((a))` gives the `identifier` node the span of `((a))` - and a parenthesized
  leaf widens the same way a parenthesized compound expression does.

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

  alias Predicator.Cast
  alias Predicator.Duration
  alias Predicator.Lexer

  # The seven scalar ISA type names (docs/isa.md section 3), from
  # Predicator.Cast - one definition, so the parser's vocabulary and the
  # evaluator's cast/2 dispatch cannot drift apart. ADR-0011: these are
  # contextual identifiers, not keywords - they are only special immediately
  # after `::` and stay valid as variable names everywhere else. `list` and `map`
  # are deliberately absent.
  @cast_type_names Cast.type_names()

  @typedoc """
  A value that can appear in literals, including the `undefined` and `null`
  literals.
  """
  @type value ::
          boolean()
          | integer()
          | binary()
          | [value()]
          | Date.t()
          | DateTime.t()
          | Predicator.Types.duration()
          | :undefined
          | nil

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
  - `{:object, entries, pos}` - An object literal whose keys are `t:object_key/0`
  - `{:membership, operator, left, right, pos}` - A membership operation (in/contains)
  - `{:function_call, name, arguments, pos}` - A function call with arguments
  - `{:bracket_access, object, key, pos}` - A bracket access expression (obj[key])
  - `{:property_access, object, property, pos}` - A property access expression (obj.prop)
  - `{:cast, expression, type_name, pos}` - a postfix type cast (`expr::integer`);
    `type_name` is one of the seven scalar ISA type names, validated at parse time
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
          | {:cast, ast(), binary(), position()}
          | {:duration, [{integer(), binary()}], position()}
          | {:relative_date, ast(), relative_direction(), position()}

  @typedoc """
  An assignment statement: `location "=" expression`.

  `location` is the raw access chain the parser built - an `{:identifier, ...}`
  optionally wrapped in any number of `{:property_access, ...}` and
  `{:bracket_access, ...}` nodes. It is kept as a chain rather than flattened to
  a path because a bracket key may be an arbitrary expression, resolvable only
  against a context; `Predicator.ContextLocation.resolve/2` does that at
  runtime. The chain's depth is the segment count `["store", n]` needs
  (ADR-0001).
  """
  @type assignment :: {:assignment, ast(), ast(), position()}

  @typedoc """
  A brace-delimited statement sequence: `"{" ( statement (";" statement)* (";")? )? "}"`.

  Produced only as the then/else slot of an `t:if_statement/0` or the body slot
  of a `t:while_statement/0` - a block has no meaning without the statement
  that holds it. Not a member of `t:ast/0`, the same as `t:program/0` and
  `t:assignment/0`.
  """
  @type block :: {:block, [statement()], position()}

  @typedoc """
  An if statement: `"if" expression block ( "else" ( block | if_statement ) )?`.

  `else_block` is `nil` when there is no `else` and a `t:block/0` when there is
  - including for `else { }`, whose empty block stays distinguishable from an
  absent one. `else if c { B }` desugars to an `else_block` of
  `{:block, [{:if, c, ..., ...}], pos}`, with no separate chain node in the AST
  (ADR-0013). Not a member of `t:ast/0`.
  """
  @type if_statement :: {:if, ast(), block(), block() | nil, position()}

  @typedoc """
  A while statement: `"while" expression block`.

  Statement-position only, on the same terms as `t:if_statement/0`: braces are
  mandatory and the body block opens no scope of its own (ADR-0013). Not a
  member of `t:ast/0`.
  """
  @type while_statement :: {:while, ast(), block(), position()}

  @typedoc """
  One statement: an if statement, a while statement, an assignment, or a bare
  expression.
  """
  @type statement :: assignment() | if_statement() | while_statement() | ast()

  @typedoc """
  Anything a visitor accepts: a whole program, any single statement, or the
  block an if statement holds. Wider than `t:ast/0`, which is the expression
  layer only.
  """
  @type visitable :: program() | statement() | block()

  @typedoc """
  A parsed statement sequence: `statement (";" statement)* [";"]`.

  Produced only by `parse_program/2`. A program is never an `t:ast/0`: the
  expression entry point cannot return one, and an expression consumer never
  has to handle one.
  """
  @type program :: {:program, [statement()], position()}

  @typedoc """
  Program parser result.
  """
  @type program_result ::
          {:ok, program()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}

  @typedoc """
  A node's trailing source metadata.

  A `t:Predicator.Types.position/0` by default - the `{line, column}` of the
  token that defines the node - or a `t:Predicator.Types.span/0` when the AST
  was parsed with `spans: true`, or `nil` when the node was not produced by the
  parser. One parse produces one kind throughout; the two are never mixed in a
  single tree.
  """
  @type position :: Predicator.Types.position() | Predicator.Types.span() | nil

  @typedoc """
  An object entry (key-value pair) in an object literal.

  The key can be either an identifier or a string literal.
  """
  @type object_entry :: {object_key(), ast()}

  @typedoc """
  A key in an object literal.

  Object keys have their own tag rather than reusing the expression node tags,
  so no consumer has to tell a key from an expression by tuple arity. `style`
  records how the key was written - bare, or quoted with which character - so
  `Predicator.Visitors.StringVisitor` can render it back as the author wrote it.
  """
  @type object_key :: {:object_key, binary(), object_key_style(), position()}

  @typedoc """
  How an object key was written: bare (`{name: 1}`), double-quoted
  (`{"name": 1}`), or single-quoted (`{'name': 1}`).
  """
  @type object_key_style :: :identifier | :double | :single

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
  @type result ::
          {:ok, ast()} | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}

  @typedoc """
  Internal parser state for tracking position and tokens.

  `spans?` records whether the caller asked for spans; it selects what `loc/3`
  puts in each node's trailing slot.
  """
  @type parser_state :: %{
          tokens: [Lexer.token()],
          position: non_neg_integer(),
          spans?: boolean()
        }

  @doc """
  Parses a list of tokens into an Abstract Syntax Tree.

  ## Parameters

  - `tokens` - List of tokens from the lexer
  - `opts` - Options:
    - `:spans` - when `true`, each node's trailing slot carries a
      `t:Predicator.Types.span/0` covering the source text the node spans,
      instead of the `{line, column}` of the token that defines it. Defaults to
      `false`.

  ## Returns

  - `{:ok, ast}` - Successfully parsed expression
  - `{:error, message, line, column}` - Parse error with position

  ## Examples

      iex> {:ok, tokens} = Predicator.Lexer.tokenize("score > 85")
      iex> Predicator.Parser.parse(tokens)
      {:ok, {:comparison, :gt, {:identifier, "score", {1, 1}}, {:literal, 85, {1, 9}}, {1, 7}}}

      iex> {:ok, tokens} = Predicator.Lexer.tokenize("name == \\"John\\"")
      iex> Predicator.Parser.parse(tokens)
      {:ok, {:comparison, :equal_equal, {:identifier, "name", {1, 1}}, {:string_literal, "John", :double, {1, 9}}, {1, 6}}}

      iex> {:ok, tokens} = Predicator.Lexer.tokenize("active == true")
      iex> Predicator.Parser.parse(tokens)
      {:ok, {:comparison, :equal_equal, {:identifier, "active", {1, 1}}, {:literal, true, {1, 11}}, {1, 8}}}

      iex> {:ok, tokens} = Predicator.Lexer.tokenize("a * true")
      iex> Predicator.Parser.parse(tokens, spans: true)
      {:ok, {:arithmetic, :multiply, {:identifier, "a", {{1, 1}, {1, 2}}}, {:literal, true, {{1, 5}, {1, 9}}}, {{1, 1}, {1, 9}}}}
  """
  @spec parse([Lexer.token()], keyword()) :: result()
  def parse(tokens, opts \\ []) when is_list(tokens) do
    state = %{tokens: tokens, position: 0, spans?: Keyword.get(opts, :spans, false) == true}

    case parse_expression(state) do
      {:ok, ast, final_state} ->
        # Ensure we consumed all tokens (except EOF)
        case peek_token(final_state) do
          {:eof, _line, _col, _len, _value} ->
            {:ok, ast}

          nil ->
            {:ok, ast}

          token ->
            unexpected_token_error(token, &"Unexpected token #{&1} after expression")
        end

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  @doc """
  Parses a list of tokens into a statement sequence.

  Implements `program := statement (";" statement)* [";"]`, where a statement
  is either an assignment (`location "=" expression`) or an ordinary
  expression. `parse/2` and `parse_program/2` are separate entry points
  because the mode - expression or statement - belongs to the entry point, not
  to the token stream (`docs/isa.md` section 2): `parse/2` never returns a
  `t:program/0`, and `parse_program/2` always returns one, even for a single
  statement.

  ## Parameters

  - `tokens` - List of tokens from the lexer
  - `opts` - Options: `:spans`, with the same meaning as `parse/2`

  ## Returns

  - `{:ok, program}` - Successfully parsed statement sequence
  - `{:error, message, line, column}` - Parse error with position

  ## Examples

      iex> {:ok, tokens} = Predicator.Lexer.tokenize("a = 1; b = a + 1")
      iex> {:ok, {:program, statements, _pos}} = Predicator.Parser.parse_program(tokens)
      iex> statements
      [
        {:assignment, {:identifier, "a", {1, 1}}, {:literal, 1, {1, 5}}, {1, 3}},
        {:assignment, {:identifier, "b", {1, 8}}, {:arithmetic, :add, {:identifier, "a", {1, 12}}, {:literal, 1, {1, 16}}, {1, 14}}, {1, 10}}
      ]

      iex> {:ok, tokens} = Predicator.Lexer.tokenize("42 = 1")
      iex> Predicator.Parser.parse_program(tokens)
      {:error, "Left side of '=' must be an assignable location - an identifier, a property access, or a bracket access.", 1, 4, {{1, 4}, {1, 5}}}
  """
  @spec parse_program([Lexer.token()], keyword()) :: program_result()
  def parse_program(tokens, opts \\ []) when is_list(tokens) do
    state = %{tokens: tokens, position: 0, spans?: Keyword.get(opts, :spans, false) == true}
    start_point = program_start_point(state)

    case parse_statement(state) do
      {:ok, first, next_state} ->
        case parse_statement_sequence(next_state, [first], :eof) do
          {:ok, statements, final_state} ->
            finish_program(state, start_point, statements, final_state)

          {:error, _message, _line, _col, _span} = error ->
            error
        end

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  # The program's point position, in position mode, is the {line, column} of
  # its very first token - captured before any statement is parsed, because a
  # statement's own trailing slot may point at an interior token (a
  # comparison points at its operator, not its leftmost operand) rather than
  # the statement's start.
  @spec program_start_point(parser_state()) :: Predicator.Types.position()
  defp program_start_point(state) do
    case peek_token(state) do
      nil -> {1, 1}
      token -> token_start(token)
    end
  end

  # Applies the same "did we consume everything" gate parse/2 uses, then
  # builds the program node.
  @spec finish_program(
          parser_state(),
          Predicator.Types.position(),
          [statement()],
          parser_state()
        ) :: program_result()
  defp finish_program(state, start_point, statements, final_state) do
    case peek_token(final_state) do
      {:eof, _line, _col, _len, _value} ->
        {:ok, {:program, statements, program_loc(state, start_point, statements)}}

      nil ->
        {:ok, {:program, statements, program_loc(state, start_point, statements)}}

      {:else_kw, line, col, _len, _value} = token ->
        {:error, statement_keyword_message(:else_kw), line, col, token_span(token)}

      token ->
        unexpected_token_error(token, &"Unexpected token #{&1} after statement")
    end
  end

  # The program's span excludes a trailing ";" - punctuation the node does not
  # own - so it is built from the statement list alone, never from
  # final_state.
  @spec program_loc(parser_state(), Predicator.Types.position(), [statement()]) :: position()
  defp program_loc(state, start_point, statements) do
    loc(state, start_point, fn ->
      {node_start(List.first(statements)), node_end(List.last(statements))}
    end)
  end

  # Walks `(";" statement)*` - the tail shared by a program body and a block
  # body, distinguished only by `terminator` (`:eof` at top level, `:rbrace`
  # inside a block; ADR-0013's block form is the same production as the
  # program body, just terminated differently). Consumes a ";" and, unless it
  # is the grammar's single optional trailing one, parses another statement
  # and recurses. A ";" immediately followed by another ";" is not consumed
  # here - it falls through to parse_statement/1, which reports it as an
  # ordinary unexpected-token error: empty statements are not allowed.
  #
  # ADR-0013 also makes the separator after a closing "}" optional: when the
  # most recently parsed statement is brace_terminated?/1 and the next token
  # is neither ";" nor the terminator, the walker parses the next statement
  # directly instead of stopping.
  @spec parse_statement_sequence(parser_state(), [statement()], atom()) ::
          {:ok, [statement()], parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_statement_sequence(state, acc, terminator) do
    case peek_token(state) do
      {:semicolon, _line, _col, _len, _value} ->
        after_semicolon = advance(state)

        if at_terminator?(after_semicolon, terminator) do
          {:ok, Enum.reverse(acc), after_semicolon}
        else
          case parse_statement(after_semicolon) do
            {:ok, statement, new_state} ->
              parse_statement_sequence(new_state, [statement | acc], terminator)

            {:error, _message, _line, _col, _span} = error ->
              error
          end
        end

      _not_semicolon ->
        if brace_terminated?(hd(acc)) and not at_terminator?(state, terminator) do
          case parse_statement(state) do
            {:ok, statement, new_state} ->
              parse_statement_sequence(new_state, [statement | acc], terminator)

            {:error, _message, _line, _col, _span} = error ->
              error
          end
        else
          {:ok, Enum.reverse(acc), state}
        end
    end
  end

  # True at the walker's terminator token or at a genuinely exhausted token
  # list (defensive: the lexer always appends an explicit `:eof` token, so
  # `nil` should not occur in practice).
  @spec at_terminator?(parser_state(), atom()) :: boolean()
  defp at_terminator?(state, terminator) do
    case peek_token(state) do
      {^terminator, _line, _col, _len, _value} -> true
      nil -> true
      _other -> false
    end
  end

  # A statement that ends in `}` may be followed directly by the next
  # statement; every other statement still needs its `;` (ADR-0013).
  @spec brace_terminated?(statement()) :: boolean()
  defp brace_terminated?({:if, _cond, _then, _else, _pos}), do: true
  defp brace_terminated?({:while, _cond, _body, _pos}), do: true
  defp brace_terminated?(_statement), do: false

  # The dedicated message for a statement keyword that cannot appear where it
  # was found - shared by parse_statement/1 (the keyword leads a statement)
  # and finish_program/4 (the keyword trails one), so the two can never say
  # different things about the same token. `while` no longer has a clause
  # here - it is a statement the parser now consumes, not a reserved-but-
  # unsupported keyword.
  @spec statement_keyword_message(:else_kw) :: binary()
  defp statement_keyword_message(:else_kw),
    do: "Unexpected 'else' - an 'else' block must follow an 'if' block."

  # A statement is an assignment, if the leading tokens are location-shaped
  # and followed by "=", or an ordinary expression otherwise.
  @spec parse_statement(parser_state()) ::
          {:ok, statement(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_statement(state) do
    case peek_token(state) do
      {:if_kw, line, col, _len, _value} ->
        parse_if_statement(state, {line, col})

      {:while_kw, line, col, _len, _value} ->
        parse_while_statement(state, {line, col})

      {:else_kw, line, col, _len, _value} = token ->
        {:error, statement_keyword_message(:else_kw), line, col, token_span(token)}

      _other ->
        case try_parse_assignment(state) do
          {:ok, _ast, _state} = ok -> ok
          {:error, _message, _line, _col, _span} = error -> error
          :not_assignment -> parse_expression(state)
        end
    end
  end

  # Parses `"if" expression block ( "else" ( block | if_statement ) )?`. The
  # leading "if" is still unconsumed in `state`, which `point` already names -
  # `advance/1` moves past it before the condition is parsed.
  @spec parse_if_statement(parser_state(), Predicator.Types.position()) ::
          {:ok, if_statement(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_if_statement(state, point) do
    case parse_expression(advance(state)) do
      {:ok, condition, after_cond} ->
        case parse_block(after_cond) do
          {:ok, then_block, after_then} ->
            case parse_else(after_then) do
              {:ok, else_block, final_state} ->
                node =
                  {:if, condition, then_block, else_block,
                   if_loc(state, point, then_block, else_block)}

                {:ok, node, final_state}

              error ->
                error
            end

          error ->
            error
        end

      error ->
        error
    end
  end

  # Parses `"while" expression block`. The leading "while" is still unconsumed
  # in `state`, which `point` already names - `advance/1` moves past it before
  # the condition is parsed, mirroring parse_if_statement/2.
  @spec parse_while_statement(parser_state(), Predicator.Types.position()) ::
          {:ok, while_statement(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_while_statement(state, point) do
    case parse_expression(advance(state)) do
      {:ok, condition, after_cond} ->
        case parse_block(after_cond) do
          {:ok, body, final_state} ->
            node = {:while, condition, body, while_loc(state, point, body)}
            {:ok, node, final_state}

          error ->
            error
        end

      error ->
        error
    end
  end

  # Parses a block body: "{" ( statement (";" statement)* (";")? )? "}",
  # requiring both delimiters. An empty block returns before entering the
  # statement-sequence walker, since a bare "}" is not statement-shaped.
  @spec parse_block(parser_state()) ::
          {:ok, block(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_block(state) do
    case peek_token(state) do
      {:lbrace, line, col, _len, _value} ->
        parse_block_body(state, advance(state), {line, col})

      nil ->
        end_of_input_error(state, "Expected '{' to open a block but found end of input")

      token ->
        unexpected_token_error(token, &"Expected '{' to open a block but found #{&1}")
    end
  end

  @spec parse_block_body(parser_state(), parser_state(), Predicator.Types.position()) ::
          {:ok, block(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_block_body(state, brace_state, point) do
    case peek_token(brace_state) do
      {:rbrace, _line, _col, _len, _value} = close ->
        {:ok, {:block, [], delimited_loc(state, point, close)}, advance(brace_state)}

      _token ->
        case parse_statement(brace_state) do
          {:ok, first, next_state} ->
            case parse_statement_sequence(next_state, [first], :rbrace) do
              {:ok, statements, final_state} ->
                finish_block(state, point, statements, final_state)

              {:error, _message, _line, _col, _span} = error ->
                error
            end

          {:error, _message, _line, _col, _span} = error ->
            error
        end
    end
  end

  @spec finish_block(parser_state(), Predicator.Types.position(), [statement()], parser_state()) ::
          {:ok, block(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp finish_block(state, point, statements, final_state) do
    case peek_token(final_state) do
      {:rbrace, _line, _col, _len, _value} = close ->
        {:ok, {:block, statements, delimited_loc(state, point, close)}, advance(final_state)}

      nil ->
        end_of_input_error(state, "Expected '}' to close the block but found end of input")

      token ->
        unexpected_token_error(token, &"Expected '}' to close the block but found #{&1}")
    end
  end

  # Parses the optional else clause: absent (nil), "else { ... }", or
  # "else if ...", which desugars into a synthetic block per ADR-0013.
  @spec parse_else(parser_state()) ::
          {:ok, block() | nil, parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_else(state) do
    case peek_token(state) do
      {:else_kw, _line, _col, _len, _value} ->
        parse_else_body(advance(state))

      _no_else ->
        {:ok, nil, state}
    end
  end

  @spec parse_else_body(parser_state()) ::
          {:ok, block(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_else_body(state) do
    case peek_token(state) do
      {:if_kw, line, col, _len, _value} ->
        case parse_if_statement(state, {line, col}) do
          {:ok, nested, final_state} ->
            # ADR-0013: else-if is sugar. The synthetic block borrows the
            # nested if's own trailing slot, which is its `if` token in point
            # mode and its span in span mode - correct in both without a
            # branch here.
            slot = elem(nested, tuple_size(nested) - 1)
            {:ok, {:block, [nested], slot}, final_state}

          {:error, _message, _line, _col, _span} = error ->
            error
        end

      _not_if ->
        parse_block(state)
    end
  end

  # Point: the `if` keyword. Span: the `if` token through past the closing `}`
  # of the last block present - the else block when there is one, otherwise
  # the then block.
  @spec if_loc(parser_state(), Predicator.Types.position(), block(), block() | nil) :: position()
  defp if_loc(state, point, then_block, else_block) do
    loc(state, point, fn -> {point, node_end(else_block || then_block)} end)
  end

  # Point: the `while` keyword. Span: the `while` token through past the
  # closing `}` of the body block.
  @spec while_loc(parser_state(), Predicator.Types.position(), block()) :: position()
  defp while_loc(state, point, body) do
    loc(state, point, fn -> {point, node_end(body)} end)
  end

  # Probes for an assignment by parsing an `addition`-level candidate - one
  # level below where parse_comparison/1 intercepts a bare "=" - and looking
  # at the next token. `parser_state` is a plain immutable map, so a discarded
  # probe costs nothing beyond the re-parse.
  #
  # A candidate-parse error is treated the same as "no candidate": falling
  # through to parse_expression/1 from the original state re-derives the
  # identical error, since an invalid leading token fails the same way
  # wherever the expression grammar meets it first.
  @spec try_parse_assignment(parser_state()) ::
          {:ok, assignment(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
          | :not_assignment
  defp try_parse_assignment(state) do
    case parse_addition(state) do
      {:ok, candidate, after_candidate} ->
        case peek_token(after_candidate) do
          {:eq, _eq_line, _eq_col, _len, _value} = eq_token ->
            build_assignment(state, candidate, eq_token, advance(after_candidate))

          _not_eq ->
            :not_assignment
        end

      {:error, _message, _line, _col, _span} ->
        :not_assignment
    end
  end

  # Commits to an assignment when `lhs` is location-shaped; otherwise reports
  # the location-shape error rather than falling through, since the caller has
  # already committed to seeing an assignment's "=".
  @spec build_assignment(
          parser_state(),
          ast(),
          Lexer.token(),
          parser_state()
        ) ::
          {:ok, assignment(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp build_assignment(state, lhs, eq_token, rhs_state) do
    point = token_start(eq_token)

    if assignable_location?(lhs) do
      case parse_expression(rhs_state) do
        {:ok, rhs, final_state} ->
          {:ok, {:assignment, lhs, rhs, binary_loc(state, point, lhs, rhs)}, final_state}

        {:error, _message, _line, _col, _span} = error ->
          error
      end
    else
      {eq_line, eq_col} = point

      {:error,
       "Left side of '=' must be an assignable location - an identifier, a property " <>
         "access, or a bracket access.", eq_line, eq_col, token_span(eq_token)}
    end
  end

  # An assignable location is an identifier, optionally wrapped in any number
  # of property or bracket accessors. Parenthesized expressions need no clause
  # here - parens are already transparent in the AST parse_postfix/1 builds,
  # so `(a)` parses to the same `{:identifier, ...}` node as `a`.
  @spec assignable_location?(ast()) :: boolean()
  defp assignable_location?({:identifier, _name, _pos}), do: true

  defp assignable_location?({:property_access, inner, _property, _pos}),
    do: assignable_location?(inner)

  defp assignable_location?({:bracket_access, inner, _key, _pos}),
    do: assignable_location?(inner)

  defp assignable_location?(_other), do: false

  # Parse expression (top level)
  @spec parse_expression(parser_state()) ::
          {:ok, ast(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_expression(state) do
    parse_logical_or(state)
  end

  # Parse logical OR expressions (lowest precedence)
  @spec parse_logical_or(parser_state()) ::
          {:ok, ast(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_logical_or(state) do
    case parse_logical_and(state) do
      {:ok, left, new_state} ->
        parse_logical_or_rest(left, new_state)

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  @spec parse_logical_or_rest(ast(), parser_state()) ::
          {:ok, ast(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_logical_or_rest(left, state) do
    token = peek_token(state)
    parse_logical_or_rest_token(left, state, token)
  end

  # Parse OR operator token (OR or ||)
  defp parse_logical_or_rest_token(left, state, {:or_op, line, col, _len, _value}) do
    or_state = advance(state)

    case parse_logical_and(or_state) do
      {:ok, right, final_state} ->
        ast = {:logical_or, left, right, binary_loc(state, {line, col}, left, right)}
        parse_logical_or_rest(ast, final_state)

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  defp parse_logical_or_rest_token(left, state, {:or_or, line, col, _len, _value}) do
    or_state = advance(state)

    case parse_logical_and(or_state) do
      {:ok, right, final_state} ->
        ast = {:logical_or, left, right, binary_loc(state, {line, col}, left, right)}
        parse_logical_or_rest(ast, final_state)

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  # No OR operator, return left operand
  defp parse_logical_or_rest_token(left, state, _token) do
    {:ok, left, state}
  end

  # Parse logical AND expressions (middle precedence)
  @spec parse_logical_and(parser_state()) ::
          {:ok, ast(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_logical_and(state) do
    case parse_logical_not(state) do
      {:ok, left, new_state} ->
        parse_logical_and_rest(left, new_state)

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  @spec parse_logical_and_rest(ast(), parser_state()) ::
          {:ok, ast(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_logical_and_rest(left, state) do
    token = peek_token(state)
    parse_logical_and_rest_token(left, state, token)
  end

  # Parse AND operator token (AND or &&)
  defp parse_logical_and_rest_token(left, state, {:and_op, line, col, _len, _value}) do
    and_state = advance(state)

    case parse_logical_not(and_state) do
      {:ok, right, final_state} ->
        ast = {:logical_and, left, right, binary_loc(state, {line, col}, left, right)}
        parse_logical_and_rest(ast, final_state)

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  defp parse_logical_and_rest_token(left, state, {:and_and, line, col, _len, _value}) do
    and_state = advance(state)

    case parse_logical_not(and_state) do
      {:ok, right, final_state} ->
        ast = {:logical_and, left, right, binary_loc(state, {line, col}, left, right)}
        parse_logical_and_rest(ast, final_state)

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  # No AND operator, return left operand
  defp parse_logical_and_rest_token(left, state, _token) do
    {:ok, left, state}
  end

  # Parse logical NOT expressions (highest precedence)
  @spec parse_logical_not(parser_state()) ::
          {:ok, ast(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
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
        ast = {:logical_not, operand, prefix_loc(state, {line, col}, operand)}
        {:ok, ast, final_state}

      {:error, _message, _line, _col, _span} = error ->
        error
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
          {:ok, ast(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_comparison(state) do
    case parse_addition(state) do
      {:ok, left, new_state} ->
        case peek_token(new_state) do
          # A bare `=` is never an equality operator in expression position -
          # it is either assignment (only legal at the start of a statement,
          # which is Predicator.Parser.parse_program/2's job, not parse/2's)
          # or a mistake. Either way this is a hard parse error, not a silent
          # reinterpretation (ADR-0002).
          {:eq, op_line, op_col, _len, _value} = token ->
            {:error,
             "'=' is not an equality operator - use '==' for equality. " <>
               "Assignment is only valid at the start of a statement.", op_line, op_col,
             token_span(token)}

          # Comparison operators (including equality)
          {op_type, op_line, op_col, _len, _value}
          when op_type in [
                 :gt,
                 :lt,
                 :gte,
                 :lte,
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

                ast =
                  {:comparison, normalized_op, left, right,
                   binary_loc(state, {op_line, op_col}, left, right)}

                {:ok, ast, final_state}

              {:error, _message, _line, _col, _span} = error ->
                error
            end

          # Membership operators
          {op_type, op_line, op_col, _len, _value}
          when op_type in [:in_op, :contains_op] ->
            operator = map_membership_operator(op_type)
            op_state = advance(new_state)

            case parse_addition(op_state) do
              {:ok, right, final_state} ->
                ast =
                  {:membership, operator, left, right,
                   binary_loc(state, {op_line, op_col}, left, right)}

                {:ok, ast, final_state}

              {:error, _message, _line, _col, _span} = error ->
                error
            end

          # Not a comparison, return the addition expression
          _token ->
            {:ok, left, new_state}
        end

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  # Parse addition expressions (+ -)
  @spec parse_addition(parser_state()) ::
          {:ok, ast(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_addition(state) do
    case parse_multiplication(state) do
      {:ok, left, new_state} ->
        parse_addition_rest(left, new_state)

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  @spec parse_addition_rest(ast(), parser_state()) ::
          {:ok, ast(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_addition_rest(left, state) do
    token = peek_token(state)
    parse_addition_rest_token(left, state, token)
  end

  # Parse + operator
  defp parse_addition_rest_token(left, state, {:plus, line, col, _len, _value}) do
    add_state = advance(state)

    case parse_multiplication(add_state) do
      {:ok, right, final_state} ->
        ast = {:arithmetic, :add, left, right, binary_loc(state, {line, col}, left, right)}
        parse_addition_rest(ast, final_state)

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  # Parse - operator
  defp parse_addition_rest_token(left, state, {:minus, line, col, _len, _value}) do
    sub_state = advance(state)

    case parse_multiplication(sub_state) do
      {:ok, right, final_state} ->
        ast =
          {:arithmetic, :subtract, left, right, binary_loc(state, {line, col}, left, right)}

        parse_addition_rest(ast, final_state)

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  # No addition operator, return left operand
  defp parse_addition_rest_token(left, state, _token) do
    {:ok, left, state}
  end

  # Parse multiplication expressions (* / %)
  @spec parse_multiplication(parser_state()) ::
          {:ok, ast(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_multiplication(state) do
    case parse_unary(state) do
      {:ok, left, new_state} ->
        parse_multiplication_rest(left, new_state)

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  @spec parse_multiplication_rest(ast(), parser_state()) ::
          {:ok, ast(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_multiplication_rest(left, state) do
    token = peek_token(state)
    parse_multiplication_rest_token(left, state, token)
  end

  # Parse * operator
  defp parse_multiplication_rest_token(left, state, {:multiply, line, col, _len, _value}) do
    mul_state = advance(state)

    case parse_unary(mul_state) do
      {:ok, right, final_state} ->
        ast =
          {:arithmetic, :multiply, left, right, binary_loc(state, {line, col}, left, right)}

        parse_multiplication_rest(ast, final_state)

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  # Parse / operator
  defp parse_multiplication_rest_token(left, state, {:divide, line, col, _len, _value}) do
    div_state = advance(state)

    case parse_unary(div_state) do
      {:ok, right, final_state} ->
        ast =
          {:arithmetic, :divide, left, right, binary_loc(state, {line, col}, left, right)}

        parse_multiplication_rest(ast, final_state)

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  # Parse % operator
  defp parse_multiplication_rest_token(left, state, {:modulo, line, col, _len, _value}) do
    mod_state = advance(state)

    case parse_unary(mod_state) do
      {:ok, right, final_state} ->
        ast =
          {:arithmetic, :modulo, left, right, binary_loc(state, {line, col}, left, right)}

        parse_multiplication_rest(ast, final_state)

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  # No multiplication operator, return left operand
  defp parse_multiplication_rest_token(left, state, _token) do
    {:ok, left, state}
  end

  # Parse unary expressions (- !)
  @spec parse_unary(parser_state()) ::
          {:ok, ast(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_unary(state) do
    token = peek_token(state)
    parse_unary_token(state, token)
  end

  # Parse unary minus
  defp parse_unary_token(state, {:minus, line, col, _len, _value}) do
    minus_state = advance(state)

    case parse_unary(minus_state) do
      {:ok, operand, final_state} ->
        ast = {:unary, :minus, operand, prefix_loc(state, {line, col}, operand)}
        {:ok, ast, final_state}

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  # Parse unary bang
  defp parse_unary_token(state, {:bang, line, col, _len, _value}) do
    bang_state = advance(state)

    case parse_unary(bang_state) do
      {:ok, operand, final_state} ->
        ast = {:unary, :bang, operand, prefix_loc(state, {line, col}, operand)}
        {:ok, ast, final_state}

      {:error, _message, _line, _col, _span} = error ->
        error
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

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  # Parse zero or more postfix operations (bracket access)
  defp parse_postfix_operations(expr, state) do
    token = peek_token(state)

    case token do
      {:lbracket, _line, _col, _len, _value} ->
        # Parse bracket access: expr[key]
        bracket_state = advance(state)
        # The point names the key, not the `[` that introduces it - an access
        # node blames the thing being accessed, same as `property_access`
        # below (docs/reference/ast.md).
        key_token = peek_token(bracket_state)

        case parse_expression(bracket_state) do
          {:ok, key_expr, key_state} ->
            case peek_token(key_state) do
              {:rbracket, _line, _col, _len, _value} = close ->
                location =
                  loc(state, token_start(key_token), fn ->
                    {node_start(expr), token_end(close)}
                  end)

                bracket_access = {:bracket_access, expr, key_expr, location}
                final_state = advance(key_state)
                # Recursively parse more postfix operations
                parse_postfix_operations(bracket_access, final_state)

              nil ->
                end_of_input_error(state, "Expected ']' but found end of input")

              token ->
                unexpected_token_error(token, &"Expected ']' but found #{&1}")
            end

          {:error, _message, _line, _col, _span} = error ->
            error
        end

      {:dot, _dot_line, _dot_col, _len, _value} ->
        # Parse property access: expr.property
        dot_state = advance(state)

        case peek_token(dot_state) do
          # Duration operators are allowed as property names (like user.name.last)
          {type, _line, _col, _len, property_name} = name_token
          when type in [:identifier, :last_op, :next_op, :ago_op, :from_op, :now_op] ->
            # The point names the property, not the `.` that introduces it -
            # an error should name the thing that failed, not the punctuation
            # (docs/reference/ast.md).
            location =
              loc(state, token_start(name_token), fn ->
                {node_start(expr), token_end(name_token)}
              end)

            property_access = {:property_access, expr, property_name, location}
            final_state = advance(dot_state)
            # Recursively parse more postfix operations
            parse_postfix_operations(property_access, final_state)

          nil ->
            end_of_input_error(state, "Expected property name after '.' but found end of input")

          token ->
            unexpected_token_error(token, &"Expected property name after '.' but found #{&1}")
        end

      {:double_colon, _line, _col, _len, _value} ->
        # Parse a postfix type cast: expr::type
        cast_state = advance(state)

        case peek_token(cast_state) do
          {:identifier, name_line, name_col, _len, type_name} = name_token ->
            if type_name in @cast_type_names do
              # The point names the type, not the `::` that introduces it - the
              # same rule `property_access` follows (docs/reference/ast.md).
              location =
                loc(state, token_start(name_token), fn ->
                  {node_start(expr), token_end(name_token)}
                end)

              parse_postfix_operations({:cast, expr, type_name, location}, advance(cast_state))
            else
              {:error,
               "Unknown cast type '#{type_name}' - expected one of: " <>
                 Enum.join(@cast_type_names, ", "), name_line, name_col, token_span(name_token)}
            end

          nil ->
            end_of_input_error(state, "Expected a type name after '::' but found end of input")

          token ->
            unexpected_token_error(token, &"Expected a type name after '::' but found #{&1}")
        end

      _other ->
        # No more postfix operations, return the expression
        {:ok, expr, state}
    end
  end

  # Parse primary expressions (literals, identifiers, parentheses)
  # This function handles multiple token types and nested error cases - inherent parser complexity
  @spec parse_primary(parser_state()) ::
          {:ok, ast(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_primary(state) do
    token = peek_token(state)
    parse_primary_token(state, token)
  end

  # Parse integer literal (may be start of duration)
  defp parse_primary_token(state, {:integer, line, col, _len, value} = token) do
    # Check if this integer is followed by duration units
    next_state = advance(state)

    case parse_duration_sequence_from_number(value, next_state, {line, col}) do
      {:ok, duration_ast, final_state} ->
        {:ok, duration_ast, final_state}

      {:error, _message, _line, _col, _span} = error ->
        error

      :not_duration ->
        # Regular integer literal
        {:ok, {:literal, value, leaf_loc(state, token)}, next_state}
    end
  end

  # Parse float literal
  defp parse_primary_token(state, {:float, _line, _col, _len, value} = token) do
    {:ok, {:literal, value, leaf_loc(state, token)}, advance(state)}
  end

  # Parse a fractional-number literal - always the start of a duration. The
  # lexer emits :fractional_number only when a decimal number is immediately
  # followed by a duration unit (the float arm of tokenize_chars/4 in
  # lib/predicator/lexer.ex mirrors the integer arm's lookahead), so the
  # :not_duration branch below is unreachable from any source the lexer can
  # produce - it exists only to keep this function total (ADR-0004: no raise
  # at a leaf) rather than reconstruct a float that was never a valid token.
  defp parse_primary_token(
         state,
         {:fractional_number, line, col, _len, {int_part, fraction_digits}} = token
       ) do
    next_state = advance(state)

    case parse_duration_sequence_from_number(
           {:frac, int_part, fraction_digits},
           next_state,
           {line, col}
         ) do
      {:ok, duration_ast, final_state} ->
        {:ok, duration_ast, final_state}

      {:error, _message, _line, _col, _span} = error ->
        error

      :not_duration ->
        unexpected_token_error(token, &"Expected a duration unit after #{&1}")
    end
  end

  # Parse string literal
  defp parse_primary_token(
         state,
         {:string, _line, _col, _len, value, quote_type, _end_position} = token
       ) do
    {:ok, {:string_literal, value, quote_type, leaf_loc(state, token)}, advance(state)}
  end

  # Parse boolean literal
  defp parse_primary_token(state, {:boolean, _line, _col, _len, value} = token) do
    {:ok, {:literal, value, leaf_loc(state, token)}, advance(state)}
  end

  # Parse the undefined literal
  defp parse_primary_token(state, {:undefined, _line, _col, _len, _value} = token) do
    {:ok, {:literal, :undefined, leaf_loc(state, token)}, advance(state)}
  end

  # Parse the null literal
  defp parse_primary_token(state, {:null, _line, _col, _len, _value} = token) do
    {:ok, {:literal, nil, leaf_loc(state, token)}, advance(state)}
  end

  # Parse date literal
  defp parse_primary_token(state, {:date, _line, _col, _len, value} = token) do
    {:ok, {:literal, value, leaf_loc(state, token)}, advance(state)}
  end

  # Parse datetime literal
  defp parse_primary_token(state, {:datetime, _line, _col, _len, value} = token) do
    {:ok, {:literal, value, leaf_loc(state, token)}, advance(state)}
  end

  # Parse identifier
  defp parse_primary_token(state, {:identifier, _line, _col, _len, value} = token) do
    {:ok, {:identifier, value, leaf_loc(state, token)}, advance(state)}
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
  defp parse_primary_token(state, {:lparen, _line, _col, _len, _value} = open) do
    paren_state = advance(state)

    case parse_expression(paren_state) do
      {:ok, expr, expr_state} ->
        case peek_token(expr_state) do
          {:rparen, _line, _col, _len, _value} = close ->
            {:ok, paren_loc(state, expr, open, close), advance(expr_state)}

          nil ->
            end_of_input_error(state, "Expected ')' but reached end of input")

          token ->
            unexpected_token_error(token, &"Expected ')' but found #{&1}")
        end

      {:error, _message, _line, _col, _span} = error ->
        error
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

  # `if`/`else`/`while` are statement keywords, never valid in expression
  # position - control flow only exists through Predicator.parse_program/2.
  defp parse_primary_token(_state, {kw, line, col, _len, value} = token)
       when kw in [:if_kw, :else_kw, :while_kw] do
    {:error,
     "'#{value}' is a statement keyword, not an expression - control flow is " <>
       "only valid in a program (Predicator.parse_program/2).", line, col, token_span(token)}
  end

  # Handle end of input
  defp parse_primary_token(state, nil) do
    end_of_input_error(state, "Unexpected end of input")
  end

  # Handle unexpected tokens
  defp parse_primary_token(_state, token) do
    expected =
      "number, string, boolean, date, datetime, identifier, function call, list, object, or '('"

    unexpected_token_error(token, &"Expected #{expected} but found #{&1}")
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

  # Selects a node's trailing metadata. The span is computed lazily so that
  # position mode - the default - pays nothing for it, and so that the span
  # closure may assume what is only true in span mode: that every child node's
  # trailing slot already holds a span.
  @spec loc(parser_state(), Predicator.Types.position(), (-> Predicator.Types.span())) ::
          position()
  defp loc(%{spans?: false}, point, _span_fun), do: point
  defp loc(%{spans?: true}, _point, span_fun), do: span_fun.()

  @spec previous_token(parser_state()) :: Lexer.token() | nil
  defp previous_token(%{tokens: tokens, position: pos}), do: Enum.at(tokens, pos - 1)

  @spec token_start(Lexer.token()) :: Predicator.Types.position()
  defp token_start({:string, line, col, _len, _value, _quote_type, _end}), do: {line, col}
  defp token_start({_type, line, col, _len, _value}), do: {line, col}

  # A token's type and value sit at the same index in either token arity -
  # `:string` carries two extra trailing slots (quote type, end position) and no
  # other token does. Reading them positionally is what lets an error path accept
  # any token without a clause per shape; the same reason token_start/1 and
  # token_end/1 below have a :string clause instead of the call sites having one.
  @spec token_type(Lexer.token()) :: atom()
  defp token_type(token), do: elem(token, 0)

  @spec token_value(Lexer.token()) :: term()
  defp token_value(token), do: elem(token, 4)

  # Exclusive: one past the token's last character. A `:string` token carries
  # its own end, because it is the only token that can contain a raw newline -
  # every other scanner's character class excludes one, and a date literal
  # containing one fails ISO 8601 parsing before a token is built (pinned by
  # "a date literal containing a newline is a lex error" in lexer_test.exs).
  # For those, the lexer's length is the full source extent, quotes and date
  # fences included, and `col + len` is exact.
  @spec token_end(Lexer.token()) :: Predicator.Types.position()
  defp token_end({:string, _line, _col, _len, _value, _quote_type, end_position}),
    do: end_position

  defp token_end({_type, line, col, len, _value}), do: {line, col + len}

  # A delimited node runs from its opening token - already the point position -
  # to past its closing token, which is not a descendant.
  @spec delimited_loc(parser_state(), Predicator.Types.position(), Lexer.token()) :: position()
  defp delimited_loc(state, start, close) do
    loc(state, start, fn -> {start, token_end(close)} end)
  end

  # A duration's last `:duration_unit` token has already been consumed by the
  # time the node is built, and both terminating branches leave the state
  # positioned immediately after it.
  @spec duration_loc(parser_state(), Predicator.Types.position()) :: position()
  defp duration_loc(state, start) do
    loc(state, start, fn -> {start, token_end(previous_token(state))} end)
  end

  # A leaf node covers exactly its own token.
  @spec leaf_loc(parser_state(), Lexer.token()) :: position()
  defp leaf_loc(state, token), do: loc(state, token_start(token), fn -> token_span(token) end)

  @spec token_span(Lexer.token()) :: Predicator.Types.span()
  defp token_span(token), do: {token_start(token), token_end(token)}

  # A failure with no token has no extent to borrow, so its span is a
  # zero-width point. Deriving the span from the point here is what lets
  # Phase 3 fix both by fixing only the point.
  @spec point_error(binary(), pos_integer(), pos_integer()) ::
          {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp point_error(message, line, col),
    do: {:error, message, line, col, {{line, col}, {line, col}}}

  # Every "expected X but found Y" failure is this: the token's own point, the
  # token's own span, and a message that names it. Taking the token whole rather
  # than its destructured parts is the point - a site that never writes a tuple
  # pattern cannot be wrong about how many elements a token has.
  @spec unexpected_token_error(Lexer.token(), (binary() -> binary())) ::
          {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp unexpected_token_error(token, message_fun) do
    {line, col} = token_start(token)
    description = format_token(token_type(token), token_value(token))
    {:error, message_fun.(description), line, col, token_span(token)}
  end

  # A failure with no token in scope reports the end of the source, not {1, 1}.
  # The lexer's :eof sentinel carries the true end position and a length of 0,
  # so token_span/1 gives a zero-width span there for free. The {1, 1} fallback
  # survives only for a hand-built token list with no sentinel at all, which the
  # public entry points cannot produce.
  @spec end_of_input_error(parser_state(), binary()) ::
          {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp end_of_input_error(%{tokens: tokens}, message) do
    case List.last(tokens) do
      nil ->
        point_error(message, 1, 1)

      token ->
        {line, col} = token_start(token)
        {:error, message, line, col, token_span(token)}
    end
  end

  # Only correct in span mode, where a child's trailing slot is its span.
  # Widened beyond ast() to statement() | block() because callers use these
  # to close over an if_statement's condition/blocks and a program's or
  # block's own statement list, neither of which is a member of t:ast/0.
  @spec node_start(statement() | block()) :: Predicator.Types.position()
  defp node_start(node), do: node |> elem(tuple_size(node) - 1) |> elem(0)

  @spec node_end(statement() | block()) :: Predicator.Types.position()
  defp node_end(node), do: node |> elem(tuple_size(node) - 1) |> elem(1)

  # An infix node spans from its left operand's start to its right operand's
  # end; the operator token is the point position and is interior to that.
  @spec binary_loc(parser_state(), Predicator.Types.position(), ast(), ast()) :: position()
  defp binary_loc(state, point, left, right) do
    loc(state, point, fn -> {node_start(left), node_end(right)} end)
  end

  # A prefix node spans from its operator token to its operand's end. The
  # operator is not a descendant, so this cannot come from the children alone.
  @spec prefix_loc(parser_state(), Predicator.Types.position(), ast()) :: position()
  defp prefix_loc(state, point, operand) do
    loc(state, point, fn -> {point, node_end(operand)} end)
  end

  # In span mode, rewrites the parenthesized expression's trailing slot to the
  # span of the enclosing parentheses - the `(` token's start to past the `)`
  # token - so the span reads as balanced instead of stopping at the inner
  # expression. This cannot be loc/3 itself: loc/3 yields a position for a node
  # under construction, and this rewrites a slot on a node that already exists.
  # The two-clause shape mirrors loc/3's spans? dispatch instead, which keeps
  # the same laziness guarantee - position mode returns the node unchanged and
  # builds no span tuple.
  @spec paren_loc(parser_state(), ast(), Lexer.token(), Lexer.token()) :: ast()
  defp paren_loc(%{spans?: false}, node, _open, _close), do: node

  defp paren_loc(%{spans?: true}, node, open, close) do
    put_elem(node, tuple_size(node) - 1, {token_start(open), token_end(close)})
  end

  @spec map_membership_operator(atom()) :: membership_op()
  defp map_membership_operator(:in_op), do: :in
  defp map_membership_operator(:contains_op), do: :contains

  @spec format_token(atom(), term()) :: binary()
  defp format_token(:integer, value), do: "number '#{value}'"
  defp format_token(:float, value), do: "number '#{value}'"

  # A :fractional_number token's value is {integer_part, fraction_digits} -
  # the fraction travels as literal digits, never the binary float (see the
  # lexer comment at the :fractional_number token's construction) - so it has
  # no single value to interpolate the way :integer and :float do. Rebuilding
  # "1.5" from the pair keeps the phrasing identical to its neighbors.
  defp format_token(:fractional_number, {integer_part, fraction_digits}),
    do: "number '#{integer_part}.#{fraction_digits}'"

  defp format_token(:string, value), do: "string \"#{value}\""
  defp format_token(:boolean, value), do: "boolean '#{value}'"
  defp format_token(:undefined, _value), do: "'undefined'"
  defp format_token(:null, _value), do: "'null'"
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
  defp format_token(:double_colon, _value), do: "'::'"
  defp format_token(:comma, _value), do: "','"
  defp format_token(:semicolon, _value), do: "';'"
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
  defp format_token(:if_kw, _value), do: "'if'"
  defp format_token(:else_kw, _value), do: "'else'"
  defp format_token(:while_kw, _value), do: "'while'"
  defp format_token(:eof, _value), do: "end of input"

  # Parse list literals: [element1, element2, ...]
  @spec parse_list(parser_state(), position()) ::
          {:ok, ast(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_list(state, position) do
    # Consume opening bracket
    bracket_state = advance(state)

    case peek_token(bracket_state) do
      # Empty list
      {:rbracket, _line, _col, _len, _value} = close ->
        {:ok, {:list, [], delimited_loc(state, position, close)}, advance(bracket_state)}

      # Non-empty list
      _token ->
        case parse_list_elements(bracket_state, []) do
          {:ok, elements, final_state} ->
            case peek_token(final_state) do
              {:rbracket, _line, _col, _len, _value} = close ->
                {:ok, {:list, Enum.reverse(elements), delimited_loc(state, position, close)},
                 advance(final_state)}

              nil ->
                end_of_input_error(state, "Expected ']' but reached end of input")

              token ->
                unexpected_token_error(token, &"Expected ']' but found #{&1}")
            end

          {:error, _message, _line, _col, _span} = error ->
            error
        end
    end
  end

  # Parse list elements recursively
  @spec parse_list_elements(parser_state(), [ast()]) ::
          {:ok, [ast()], parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
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

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  # Parse object literals: {key1: value1, key2: value2, ...}
  @spec parse_object(parser_state(), position()) ::
          {:ok, ast(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_object(state, position) do
    # Consume opening brace
    brace_state = advance(state)

    case peek_token(brace_state) do
      # Empty object
      {:rbrace, _line, _col, _len, _value} = close ->
        {:ok, {:object, [], delimited_loc(state, position, close)}, advance(brace_state)}

      # Non-empty object
      _token ->
        case parse_object_entries(brace_state, []) do
          {:ok, entries, final_state} ->
            case peek_token(final_state) do
              {:rbrace, _line, _col, _len, _value} = close ->
                {:ok, {:object, Enum.reverse(entries), delimited_loc(state, position, close)},
                 advance(final_state)}

              nil ->
                end_of_input_error(state, "Expected '}' but reached end of input")

              token ->
                unexpected_token_error(token, &"Expected '}' but found #{&1}")
            end

          {:error, _message, _line, _col, _span} = error ->
            error
        end
    end
  end

  # Parse object entries recursively
  @spec parse_object_entries(parser_state(), [object_entry()]) ::
          {:ok, [object_entry()], parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
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

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  # Parse a single object entry: key: value
  @spec parse_object_entry(parser_state()) ::
          {:ok, object_entry(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_object_entry(state) do
    case parse_object_key(state) do
      {:ok, key, key_state} ->
        case peek_token(key_state) do
          {:colon, _line, _col, _len, _value} ->
            colon_state = advance(key_state)

            case parse_expression(colon_state) do
              {:ok, value, value_state} ->
                {:ok, {key, value}, value_state}

              {:error, _message, _line, _col, _span} = error ->
                error
            end

          {:string, line, col, _len, value, _quote_type, _end_position} = token ->
            {:error, "Expected ':' after object key but found #{format_token(:string, value)}",
             line, col, token_span(token)}

          {type, line, col, _len, token_value} = token ->
            {:error, "Expected ':' after object key but found #{format_token(type, token_value)}",
             line, col, token_span(token)}

          nil ->
            end_of_input_error(state, "Expected ':' after object key but reached end of input")
        end

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  # Parse object key (identifier or string literal)
  @spec parse_object_key(parser_state()) ::
          {:ok, object_key(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_object_key(state) do
    case peek_token(state) do
      {:identifier, _line, _col, _len, value} = token ->
        {:ok, {:object_key, value, :identifier, leaf_loc(state, token)}, advance(state)}

      {:string, _line, _col, _len, value, quote_type, _end_position} = token ->
        {:ok, {:object_key, value, quote_type, leaf_loc(state, token)}, advance(state)}

      nil ->
        end_of_input_error(state, "Expected object key but reached end of input")

      token ->
        unexpected_token_error(
          token,
          &"Expected identifier or string for object key but found #{&1}"
        )
    end
  end

  # Parse function call: function_name(arg1, arg2, ...)
  @spec parse_function_call(parser_state(), binary(), position()) ::
          {:ok, ast(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_function_call(state, function_name, position) do
    # Consume function name token
    func_state = advance(state)

    case peek_token(func_state) do
      {:lparen, _line, _col, _len, _value} ->
        # Consume opening parenthesis
        paren_state = advance(func_state)

        case peek_token(paren_state) do
          # Empty argument list
          {:rparen, _line, _col, _len, _value} = close ->
            {:ok, {:function_call, function_name, [], delimited_loc(state, position, close)},
             advance(paren_state)}

          # Non-empty argument list
          _token ->
            case parse_function_arguments(paren_state, []) do
              {:ok, arguments, final_state} ->
                case peek_token(final_state) do
                  {:rparen, _line, _col, _len, _value} = close ->
                    {:ok,
                     {:function_call, function_name, Enum.reverse(arguments),
                      delimited_loc(state, position, close)}, advance(final_state)}

                  nil ->
                    end_of_input_error(state, "Expected ')' but reached end of input")

                  token ->
                    unexpected_token_error(token, &"Expected ')' but found #{&1}")
                end

              {:error, _message, _line, _col, _span} = error ->
                error
            end
        end

      nil ->
        end_of_input_error(state, "Expected '(' after function name but reached end of input")

      token ->
        unexpected_token_error(token, &"Expected '(' after function name but found #{&1}")
    end
  end

  # Parse function arguments recursively
  @spec parse_function_arguments(parser_state(), [ast()]) ::
          {:ok, [ast()], parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
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

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  # Duration parsing functions
  #
  # A duration's components accumulate as {value, unit, component_span}
  # triples - prepended, reversed once at the end - where value is either a
  # plain integer or {:frac, integer_part, fraction_digits}. The component
  # span runs from the number token's own start to the end of its unit
  # token, which is what lets the two new fractional-duration errors below
  # point at exactly one component (an inexact fraction) or the whole
  # literal (a post-expansion unit collision), following the date-literal
  # per-family span precedent (lib/predicator/lexer.ex:465-467).

  @typep duration_value :: integer() | {:frac, integer(), binary()}
  @typep duration_component :: {duration_value(), binary(), Predicator.Types.span()}

  @spec parse_duration_sequence_from_number(duration_value(), parser_state(), position()) ::
          {:ok, ast(), parser_state()}
          | {:error, binary(), integer(), integer(), Predicator.Types.span()}
          | :not_duration
  defp parse_duration_sequence_from_number(value, state, position) do
    case peek_token(state) do
      {:duration_unit, _line, _col, _len, unit} = unit_token ->
        # Found duration unit, parse the full duration sequence
        component = {value, unit, {position, token_end(unit_token)}}
        parse_duration_sequence([component], advance(state), position)

      _token ->
        # Not followed by duration unit
        :not_duration
    end
  end

  @spec parse_duration_sequence([duration_component()], parser_state(), position()) ::
          {:ok, ast(), parser_state()}
          | {:error, binary(), integer(), integer(), Predicator.Types.span()}
  defp parse_duration_sequence(components, state, position) do
    case peek_token(state) do
      {:integer, line, col, _len, number} ->
        # Check if this integer is followed by a duration unit
        next_state = advance(state)

        case peek_token(next_state) do
          {:duration_unit, _line, _col, _len, unit} = unit_token ->
            # Continue building duration sequence (prepended; reversed once at the end)
            component = {number, unit, {{line, col}, token_end(unit_token)}}
            parse_duration_sequence([component | components], advance(next_state), position)

          _token ->
            # End of duration sequence, check for direction operators
            finalize_duration_sequence(components, state, position)
        end

      {:fractional_number, line, col, _len, {int_part, fraction_digits}} ->
        next_state = advance(state)

        # The lexer emits :fractional_number only when a duration unit
        # immediately follows (see the float arm of tokenize_chars/4 in
        # lib/predicator/lexer.ex), so this hard match relies on that
        # invariant rather than reconstructing a fallback path no source
        # can reach - the same way duration_loc/2 below relies on a
        # lexer/parser invariant.
        {:duration_unit, _line, _col, _len, unit} = unit_token = peek_token(next_state)
        value = {:frac, int_part, fraction_digits}
        component = {value, unit, {{line, col}, token_end(unit_token)}}
        parse_duration_sequence([component | components], advance(next_state), position)

      _token ->
        # End of duration sequence, check for direction operators
        finalize_duration_sequence(components, state, position)
    end
  end

  # Builds the AST node from the accumulated components. Integer-only
  # literals lower byte-for-byte identically to before this feature existed
  # (Decision 6b/6c) - no fractional component means no expansion, no
  # collision check, and the same {integer, unit} pairs as always.
  @spec finalize_duration_sequence([duration_component()], parser_state(), position()) ::
          {:ok, ast(), parser_state()}
          | {:error, binary(), integer(), integer(), Predicator.Types.span()}
  defp finalize_duration_sequence(components, state, position) do
    ordered = Enum.reverse(components)

    if Enum.any?(ordered, fn {value, _unit, _span} -> match?({:frac, _, _}, value) end) do
      case expand_duration_components(ordered) do
        {:ok, pairs} ->
          build_duration_ast(pairs, state, position)

        {:error, _message, _line, _col, _span} = error ->
          error
      end
    else
      pairs = Enum.map(ordered, fn {value, unit, _span} -> {value, unit} end)
      build_duration_ast(pairs, state, position)
    end
  end

  @spec build_duration_ast([{integer(), binary()}], parser_state(), position()) ::
          {:ok, ast(), parser_state()}
  defp build_duration_ast(pairs, state, position) do
    duration_ast = {:duration, pairs, duration_loc(state, position)}
    parse_duration_with_direction(duration_ast, state)
  end

  # Expands every fractional component through Predicator.Duration and
  # concatenates the result in source order (Decision 6b: the AST keeps its
  # existing {integer(), binary()} pair shape, receiving already-expanded
  # pairs). An inexact fraction is a compile error spanning that component
  # alone (Decision 2/6a); a duplicate unit across the whole literal after
  # expansion is a compile error spanning the whole literal (Decision 6a) -
  # integer-only literals never reach this function, so their pinned
  # last-wins overwrite behavior at the opcode is untouched.
  @spec expand_duration_components([duration_component()]) ::
          {:ok, [{integer(), binary()}]}
          | {:error, binary(), integer(), integer(), Predicator.Types.span()}
  defp expand_duration_components(ordered) do
    ordered
    |> Enum.reduce_while({:ok, []}, fn component, {:ok, acc} ->
      expand_duration_component(component, acc)
    end)
    |> case do
      {:ok, reversed_pairs} ->
        pairs = Enum.reverse(reversed_pairs)
        check_no_duplicate_units(pairs, ordered)

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end

  defp expand_duration_component({{:frac, int_part, fraction_digits}, unit, span}, acc) do
    case Duration.expand_fraction(int_part, fraction_digits, unit) do
      {:ok, pairs} ->
        {:cont, {:ok, Enum.reduce(pairs, acc, fn pair, a -> [pair | a] end)}}

      {:error, _reason} ->
        # :subunit_remainder is the reachable case; :unknown_unit cannot
        # occur here because duration_unit?/1 in the lexer only recognizes
        # the same eight units Duration's expansion table knows.
        {line, col} = elem(span, 0)
        literal = "#{int_part}.#{fraction_digits}#{unit}"

        {:halt,
         {:error, "Duration fraction is not a whole number of milliseconds: #{literal}", line,
          col, span}}
    end
  end

  defp expand_duration_component({value, unit, _span}, acc) when is_integer(value) do
    {:cont, {:ok, [{value, unit} | acc]}}
  end

  @spec check_no_duplicate_units([{integer(), binary()}], [duration_component()]) ::
          {:ok, [{integer(), binary()}]}
          | {:error, binary(), integer(), integer(), Predicator.Types.span()}
  defp check_no_duplicate_units(pairs, ordered) do
    duplicate =
      pairs
      |> Enum.map(fn {_value, unit} -> unit end)
      |> Enum.frequencies()
      |> Enum.find_value(fn {unit, count} -> if count > 1, do: unit end)

    case duplicate do
      nil ->
        {:ok, pairs}

      unit ->
        {start, _end} = elem(List.first(ordered), 2)
        {_start, finish} = elem(List.last(ordered), 2)
        {line, col} = start

        {:error, "Duration literal names the '#{unit}' unit twice after expanding a fraction",
         line, col, {start, finish}}
    end
  end

  @spec parse_duration_with_direction(ast(), parser_state()) ::
          {:ok, ast(), parser_state()}
          | {:error, binary(), integer(), integer(), Predicator.Types.span()}
  defp parse_duration_with_direction(duration_ast, state) do
    case peek_token(state) do
      {:ago_op, line, col, _len, _value} = ago ->
        location =
          loc(state, {line, col}, fn -> {node_start(duration_ast), token_end(ago)} end)

        {:ok, {:relative_date, duration_ast, :ago, location}, advance(state)}

      {:from_op, line, col, _len, _value} ->
        # Expect 'now' after 'from'
        from_state = advance(state)

        case peek_token(from_state) do
          {:now_op, _line, _col, _len, _value} = now ->
            location =
              loc(state, {line, col}, fn -> {node_start(duration_ast), token_end(now)} end)

            {:ok, {:relative_date, duration_ast, :future, location}, advance(from_state)}

          nil ->
            end_of_input_error(state, "Expected 'now' after 'from' but reached end of input")

          token ->
            unexpected_token_error(token, &"Expected 'now' after 'from' but found #{&1}")
        end

      _token ->
        # Just a duration, no direction
        {:ok, duration_ast, state}
    end
  end

  @spec parse_relative_date_expression(parser_state(), relative_direction(), position()) ::
          {:ok, ast(), parser_state()}
          | {:error, binary(), pos_integer(), pos_integer(), Predicator.Types.span()}
  defp parse_relative_date_expression(state, direction, position) do
    # Advance past the direction keyword (next/last)
    next_state = advance(state)

    # Expect a duration expression
    case parse_primary(next_state) do
      {:ok, {:duration, _units, _duration_pos} = duration_ast, final_state} ->
        location = prefix_loc(state, position, duration_ast)
        {:ok, {:relative_date, duration_ast, direction, location}, final_state}

      {:ok, _other_ast, _final_state} ->
        case peek_token(next_state) do
          nil ->
            end_of_input_error(
              next_state,
              "Expected duration after '#{direction}' but found end of input"
            )

          token ->
            unexpected_token_error(
              token,
              &"Expected duration after '#{direction}' but found #{&1}"
            )
        end

      {:error, _message, _line, _col, _span} = error ->
        error
    end
  end
end
