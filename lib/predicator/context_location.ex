defmodule Predicator.ContextLocation do
  @moduledoc """
  Resolves location paths for assignment operations in SCXML datamodel expressions.

  This module takes parsed AST nodes and extracts location paths that can be used
  for assignment operations. It validates that expressions represent assignable
  locations (l-values) rather than computed values.

  ## Location Path Format

  Location paths are returned as lists of keys/indices that represent the path
  to a specific location in the context data structure:

  - `["user"]` - top-level variable `user`
  - `["user", "name"]` - property access `user.name`
  - `["items", 0]` - array access `items[0]`
  - `["user", "profile", "settings", "theme"]` - nested access `user.profile.settings.theme`

  ## Assignable vs Non-Assignable

  **Assignable (valid locations):**
  - Simple identifiers: `user`
  - Property access: `user.name`, `obj.prop`
  - Bracket access: `items[0]`, `obj["key"]`
  - Mixed notation: `user.items[0].name`, `data["users"][0]["profile"]`

  **Non-Assignable (invalid locations):**
  - Literals: `42`, `"string"`, `true`
  - Function calls: `len(items)`, `upper(name)`
  - Arithmetic expressions: `user.age + 1`, `items[i + 1]`
  - Any computed values that can't be used as assignment targets

  ## Assignment

  `put/3` writes a value at a resolved location path, creating any missing
  intermediate containers along the way (auto-vivification):

  - A segment whose current value is missing, `nil`, or `:undefined` is created:
    a `%{}` when the next segment is a string key, a `[]` when it is an integer
    index.
  - Existing data is never destroyed to make room. A path that traverses a
    scalar returns a `:not_a_container` error, as does a string segment against
    an existing list.
  - Integer indices past the end of a list pad the gap with `:undefined`;
    negative indices return `:invalid_index`.
  - The leaf is always overwritten, whatever it currently holds.

  ## Examples

      iex> alias Predicator.{ContextLocation, Lexer, Parser}
      iex> {:ok, tokens} = Lexer.tokenize("user.name")
      iex> {:ok, ast} = Parser.parse(tokens)
      iex> ContextLocation.resolve(ast, %{"user" => %{"name" => "John"}})
      {:ok, ["user", "name"]}

      iex> alias Predicator.{ContextLocation, Lexer, Parser}
      iex> {:ok, tokens} = Lexer.tokenize("items[0]")
      iex> {:ok, ast} = Parser.parse(tokens)
      iex> ContextLocation.resolve(ast, %{"items" => [1, 2, 3]})
      {:ok, ["items", 0]}

  """

  alias Predicator.{Lexer, Parser, Undefined}
  alias Predicator.Errors.{LocationError, ParseError}
  alias Predicator.Types

  @typedoc """
  A location path representing the sequence of keys/indices to reach a location in the context.

  String keys represent object properties, integer keys represent array indices.
  """
  @type location_path :: [binary() | integer()]

  @typedoc """
  Result of resolving a location expression.

  Returns either a successful path or a structured error explaining why the location is invalid.
  """
  @type location_result :: {:ok, location_path()} | {:error, LocationError.t()}

  @typedoc """
  Result of writing a value at a location path.

  Returns either the updated context or a structured error explaining why the
  write could not be performed.
  """
  @type put_result :: {:ok, Types.context()} | {:error, LocationError.t()}

  @doc """
  Resolves an AST node to a location path for assignment operations.

  Takes a parsed AST node and attempts to extract a valid location path.
  Validates that the expression represents an assignable location.

  ## Parameters

  - `ast_node` - The parsed AST node to resolve
  - `context` - The evaluation context (used for validating array bounds, etc.)

  ## Returns

  - `{:ok, path}` - A valid location path
  - `{:error, %LocationError{}}` - An error explaining why the location is invalid

  ## Examples

      # Simple identifier
      resolve({:identifier, "user"}, %{})
      #=> {:ok, ["user"]}

      # Property access
      resolve({:property_access, {:identifier, "user"}, "name"}, %{})
      #=> {:ok, ["user", "name"]}

      # Bracket access
      resolve({:bracket_access, {:identifier, "items"}, {:literal, 0}}, %{})
      #=> {:ok, ["items", 0]}

      # Invalid: literal value
      resolve({:literal, 42}, %{})
      #=> {:error, %LocationError{type: :not_assignable, message: "Cannot assign to literal value"}}

  """
  @spec resolve(term(), Types.context()) :: location_result()
  def resolve(ast_node, context) when is_map(context) do
    case ast_node |> Parser.ensure_positions() |> do_resolve_base(context) do
      {:ok, path} -> {:ok, path}
      {:error, _error} = error -> error
    end
  end

  @doc """
  Tokenizes, parses, and resolves a location expression in one step.

  Equivalent to parsing `expression` and calling `resolve/2` on the result,
  except parse and tokenize errors are wrapped as `Predicator.Errors.ParseError`
  the same way `Predicator.context_location/3` does - this *is* that
  function's implementation, extracted so `Predicator.Context.assign/3` can
  share it without depending on the `Predicator` module.
  """
  @spec resolve_expression(binary(), Types.context()) ::
          location_result() | {:error, ParseError.t()}
  def resolve_expression(expression, context)
      when is_binary(expression) and is_map(context) do
    case Lexer.tokenize(expression) do
      {:ok, tokens} ->
        case Parser.parse(tokens) do
          {:ok, ast} -> resolve(ast, context)
          {:error, message, line, column} -> {:error, ParseError.new(message, line, column)}
        end

      {:error, message, line, column} ->
        {:error, ParseError.new(message, line, column)}
    end
  end

  @doc """
  Writes `value` into `context` at `path`, creating missing intermediate containers.

  Auto-vivification is ECMAScript-like: a missing (or `nil`/`:undefined`) segment
  is created as a map when the next segment is a string key, and as a list when
  the next segment is an integer index. Existing data is never destroyed - a path
  that traverses a scalar returns a `:not_a_container` error. The leaf is always
  overwritten.

  Integer indices past the end of an existing list pad the gap with `:undefined`.
  Negative indices are rejected with `:invalid_index`. An integer segment against
  an existing *map* is allowed and writes with the integer key, because refusing
  would destroy data the caller put there.

  > #### String and integer keys only {: .info}
  >
  > `put/3` consults string and integer keys, never atom keys. Writing
  > `["user", "name"]` into a context holding `%{user: %{}}` vivifies a new
  > `"user"` map beside the atom key rather than descending into it. A caller
  > reaching `put/3` via `Predicator.Context.assign/3` never has atom keys to
  > worry about in the first place, since `Context.new/2`/`bind/3` already
  > normalize them away deeply and eagerly. This note matters only for a
  > caller invoking `put/3` directly on a hand-built map.

  ## Parameters

  - `context` - The context map to write into
  - `path` - A location path as returned by `resolve/2`
  - `value` - The value to write at the leaf

  ## Returns

  - `{:ok, context}` - The updated context
  - `{:error, %LocationError{}}` - An error explaining why the write failed

  ## Examples

      iex> Predicator.ContextLocation.put(%{}, ["user", "profile", "name"], "Ada")
      {:ok, %{"user" => %{"profile" => %{"name" => "Ada"}}}}

      iex> Predicator.ContextLocation.put(%{"items" => [1]}, ["items", 2], "x")
      {:ok, %{"items" => [1, :undefined, "x"]}}

      iex> {:error, error} = Predicator.ContextLocation.put(%{"user" => 5}, ["user", "name"], "Ada")
      iex> error.type
      :not_a_container

  """
  @spec put(Types.context(), location_path(), term()) :: put_result()
  def put(context, path, value)

  def put(context, [], _value) when is_map(context) do
    {:error, LocationError.not_assignable("empty location path", [])}
  end

  def put(context, path, value) when is_map(context) and is_list(path) do
    do_put(context, path, value, [])
  end

  # Private implementation functions

  # Simple identifier - base case
  defp do_resolve_base({:identifier, name, _position}, _context) when is_binary(name) do
    {:ok, [name]}
  end

  # Property access: obj.prop - collect path components from left to right
  defp do_resolve_base({:property_access, left_node, property, _position}, context)
       when is_binary(property) do
    case do_resolve_base(left_node, context) do
      {:ok, base_path} -> {:ok, base_path ++ [property]}
      {:error, _error} = error -> error
    end
  end

  # Bracket access: obj[key] - collect path components from left to right
  defp do_resolve_base({:bracket_access, left_node, key_node, _position}, context) do
    case resolve_bracket_key(key_node, context) do
      {:ok, key} ->
        case do_resolve_base(left_node, context) do
          {:ok, base_path} -> {:ok, base_path ++ [key]}
          {:error, _error} = error -> error
        end

      {:error, _error} = error ->
        error
    end
  end

  # Invalid cases - not assignable

  # Literals are not assignable
  defp do_resolve_base({:literal, value, _position}, _context) do
    {:error, LocationError.not_assignable("literal value", value)}
  end

  # String literals are not assignable
  defp do_resolve_base({:string_literal, value, _quote_type, _position}, _context) do
    {:error, LocationError.not_assignable("string literal", value)}
  end

  # Function calls are not assignable
  defp do_resolve_base({:function_call, name, _args, _position}, _context) do
    {:error, LocationError.not_assignable("function call", name)}
  end

  # Arithmetic operations are not assignable
  defp do_resolve_base({:arithmetic, op, _left, _right, _position}, _context) do
    {:error, LocationError.not_assignable("arithmetic expression", to_string(op))}
  end

  # Comparison operations are not assignable
  defp do_resolve_base({:comparison, op, _left, _right, _position}, _context) do
    {:error, LocationError.not_assignable("comparison expression", to_string(op))}
  end

  # Logical operations are not assignable
  defp do_resolve_base({:logical_and, _left, _right, _position}, _context) do
    {:error, LocationError.not_assignable("logical expression", "AND")}
  end

  defp do_resolve_base({:logical_or, _left, _right, _position}, _context) do
    {:error, LocationError.not_assignable("logical expression", "OR")}
  end

  defp do_resolve_base({:logical_not, _operand, _position}, _context) do
    {:error, LocationError.not_assignable("logical expression", "NOT")}
  end

  # Unary operations are not assignable
  defp do_resolve_base({:unary_minus, _operand}, _context) do
    {:error, LocationError.not_assignable("unary expression", "unary minus")}
  end

  defp do_resolve_base({:unary_bang, _operand}, _context) do
    {:error, LocationError.not_assignable("unary expression", "unary bang")}
  end

  # General unary operations (covers {:unary, :minus, _} and {:unary, :bang, _})
  defp do_resolve_base({:unary, op, _operand, _position}, _context) do
    {:error, LocationError.not_assignable("unary expression", to_string(op))}
  end

  # Lists are not assignable
  defp do_resolve_base({:list, _elements, _position}, _context) do
    {:error, LocationError.not_assignable("list literal", "list")}
  end

  # Catch-all for unknown node types
  defp do_resolve_base(unknown_node, _context) do
    {:error, LocationError.invalid_node("Unknown AST node type", unknown_node)}
  end

  # Resolve bracket access keys
  @spec resolve_bracket_key(term(), Types.context()) ::
          {:ok, binary() | integer()} | {:error, LocationError.t()}

  # String literals as keys (for object property access)
  defp resolve_bracket_key({:string_literal, key, _quote_type, _position}, _context)
       when is_binary(key) do
    {:ok, key}
  end

  # Integer literals as keys (for array access)
  defp resolve_bracket_key({:literal, index, _position}, _context) when is_integer(index) do
    {:ok, index}
  end

  # Handle unary minus for negative integers
  defp resolve_bracket_key(
         {:unary, :minus, {:literal, value, _inner_position}, _position},
         _context
       )
       when is_integer(value) do
    {:ok, -value}
  end

  # Variable references as keys - resolve to their values
  defp resolve_bracket_key({:identifier, var_name, _position}, context) do
    case Map.get(context, var_name) do
      key when is_binary(key) or is_integer(key) ->
        {:ok, key}

      nil ->
        {:error, LocationError.undefined_variable("Bracket key variable not found", var_name)}

      other ->
        {:error, LocationError.invalid_key("Bracket key must be string or integer", other)}
    end
  end

  # Computed expressions as keys are not allowed in location expressions
  defp resolve_bracket_key(computed_node, _context) do
    {:error,
     LocationError.computed_key(
       "Cannot use computed expression as assignment target key",
       computed_node
     )}
  end

  # Assignment implementation
  #
  # `trail` accumulates the segments already traversed so error messages can name
  # the offending location the way a document author wrote it.

  # Leaf: overwrite whatever is there.
  defp do_put(container, [segment], value, trail) do
    set_in(container, segment, value, trail)
  end

  # Interior: vivify or descend, then write the updated child back.
  defp do_put(container, [segment | rest], value, trail) do
    with {:ok, child} <- fetch_in(container, segment, trail),
         {:ok, child} <- vivify(child, hd(rest), trail ++ [segment]),
         {:ok, updated} <- do_put(child, rest, value, trail ++ [segment]) do
      set_in(container, segment, updated, trail)
    end
  end

  # A missing/nil/undefined slot becomes a container shaped by the *next* segment.
  defp vivify(absent, next_segment, _trail)
       when absent in [nil, :undefined] and is_integer(next_segment) do
    {:ok, []}
  end

  defp vivify(absent, _next_segment, _trail) when absent in [nil, :undefined] do
    {:ok, %{}}
  end

  defp vivify(child, _next_segment, _trail) when is_map(child) or is_list(child) do
    {:ok, child}
  end

  defp vivify(scalar, _next_segment, trail) do
    {:error, LocationError.not_a_container(format_path(trail), List.last(trail), scalar)}
  end

  # Reading a segment. Maps take any key; lists take non-negative integers only.
  defp fetch_in(map, segment, _trail) when is_map(map) do
    {:ok, Map.get(map, segment)}
  end

  defp fetch_in(list, index, _trail) when is_list(list) and is_integer(index) and index >= 0 do
    {:ok, Enum.at(list, index)}
  end

  defp fetch_in(list, index, trail) when is_list(list) and is_integer(index) do
    {:error, LocationError.invalid_index(format_path(trail ++ [index]), index)}
  end

  defp fetch_in(list, key, trail) when is_list(list) do
    {:error, LocationError.not_a_container(format_path(trail ++ [key]), key, list)}
  end

  # Writing a segment. Mirrors fetch_in, padding short lists with `:undefined`.
  defp set_in(map, segment, value, _trail) when is_map(map) do
    {:ok, Map.put(map, segment, value)}
  end

  defp set_in(list, index, value, _trail)
       when is_list(list) and is_integer(index) and index >= 0 do
    {:ok, write_at(list, index, value, length(list))}
  end

  defp set_in(list, index, _value, trail) when is_list(list) and is_integer(index) do
    {:error, LocationError.invalid_index(format_path(trail ++ [index]), index)}
  end

  defp set_in(list, key, _value, trail) when is_list(list) do
    {:error, LocationError.not_a_container(format_path(trail ++ [key]), key, list)}
  end

  defp write_at(list, index, value, size) when index < size do
    List.replace_at(list, index, value)
  end

  defp write_at(list, index, value, size) do
    list ++ List.duplicate(Undefined.value(), index - size) ++ [value]
  end

  # Renders a trail the way a document author wrote it: `user.profile`, `items[2]`.
  defp format_path(segments) do
    segments
    |> Enum.with_index()
    |> Enum.map_join(fn {segment, position} -> format_segment(segment, position) end)
  end

  defp format_segment(index, _position) when is_integer(index), do: "[#{index}]"
  defp format_segment(key, 0), do: "#{key}"
  defp format_segment(key, _position), do: ".#{key}"
end
