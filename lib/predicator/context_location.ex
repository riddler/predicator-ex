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

  ## Examples

      iex> alias Predicator.{ContextLocation, Lexer, Parser}
      iex> {:ok, tokens} = Lexer.tokenize("user.name")
      iex> {:ok, ast} = Parser.parse(tokens)
      iex> ContextLocation.resolve(ast, %{"user" => %{"name" => "John"}})
      {:ok, ["user", "name"]}

      iex> {:ok, tokens} = Lexer.tokenize("items[0]")
      iex> {:ok, ast} = Parser.parse(tokens)
      iex> ContextLocation.resolve(ast, %{"items" => [1, 2, 3]})
      {:ok, ["items", 0]}

  """

  alias Predicator.Errors.LocationError
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
    case do_resolve_base(ast_node, context) do
      {:ok, path} -> {:ok, path}
      {:error, _error} = error -> error
    end
  end

  # Private implementation functions

  # Simple identifier - base case
  defp do_resolve_base({:identifier, name}, _context) when is_binary(name) do
    {:ok, [name]}
  end

  # Property access: obj.prop - collect path components from left to right
  defp do_resolve_base({:property_access, left_node, property}, context)
       when is_binary(property) do
    case do_resolve_base(left_node, context) do
      {:ok, base_path} -> {:ok, base_path ++ [property]}
      {:error, _error} = error -> error
    end
  end

  # Bracket access: obj[key] - collect path components from left to right
  defp do_resolve_base({:bracket_access, left_node, key_node}, context) do
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
  defp do_resolve_base({:literal, value}, _context) do
    {:error, LocationError.not_assignable("literal value", value)}
  end

  # String literals are not assignable
  defp do_resolve_base({:string_literal, value, _quote_type}, _context) do
    {:error, LocationError.not_assignable("string literal", value)}
  end

  # Function calls are not assignable
  defp do_resolve_base({:function_call, name, _args}, _context) do
    {:error, LocationError.not_assignable("function call", name)}
  end

  # Arithmetic operations are not assignable
  defp do_resolve_base({:arithmetic, op, _left, _right}, _context) do
    {:error, LocationError.not_assignable("arithmetic expression", to_string(op))}
  end

  # Comparison operations are not assignable
  defp do_resolve_base({:comparison, op, _left, _right}, _context) do
    {:error, LocationError.not_assignable("comparison expression", to_string(op))}
  end

  # Logical operations are not assignable
  defp do_resolve_base({:logical_and, _left, _right}, _context) do
    {:error, LocationError.not_assignable("logical expression", "AND")}
  end

  defp do_resolve_base({:logical_or, _left, _right}, _context) do
    {:error, LocationError.not_assignable("logical expression", "OR")}
  end

  defp do_resolve_base({:logical_not, _operand}, _context) do
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
  defp do_resolve_base({:unary, op, _operand}, _context) do
    {:error, LocationError.not_assignable("unary expression", to_string(op))}
  end

  # Lists are not assignable
  defp do_resolve_base({:list, _elements}, _context) do
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
  defp resolve_bracket_key({:string_literal, key, _quote_type}, _context) when is_binary(key) do
    {:ok, key}
  end

  # Integer literals as keys (for array access)
  defp resolve_bracket_key({:literal, index}, _context) when is_integer(index) do
    {:ok, index}
  end

  # Handle unary minus for negative integers
  defp resolve_bracket_key({:unary, :minus, {:literal, value}}, _context)
       when is_integer(value) do
    {:ok, -value}
  end

  # Variable references as keys - resolve to their values
  defp resolve_bracket_key({:identifier, var_name}, context) do
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
end
