defmodule Predicator.Errors.LocationError do
  @moduledoc """
  Error struct for location expression validation failures.

  This error is raised when attempting to resolve a location path for assignment
  operations, but the expression does not represent a valid assignable location.
  It also covers the write-time failures of `Predicator.ContextLocation.put/3`.

  ## Error Types

  Resolution failures:

  - `:not_assignable` - Expression cannot be used as an assignment target
  - `:invalid_node` - Unknown or unsupported AST node type
  - `:undefined_variable` - Variable referenced in bracket key is not defined
  - `:invalid_key` - Bracket key is not a valid string or integer
  - `:computed_key` - Computed expressions cannot be used as assignment keys

  Write failures:

  - `:not_a_container` - Path traverses a value that is neither a map nor a list
  - `:invalid_index` - List index in the path is out of range (negative)

  ## Examples

      # Cannot assign to literal values
      %LocationError{
        type: :not_assignable,
        message: "Cannot assign to literal value",
        details: %{expression_type: "literal value", value: 42}
      }

      # Cannot assign to function calls
      %LocationError{
        type: :not_assignable,
        message: "Cannot assign to function call",
        details: %{expression_type: "function call", value: "len"}
      }

      # Invalid bracket key type
      %LocationError{
        type: :invalid_key,
        message: "Bracket key must be string or integer",
        details: %{key_type: "boolean", key_value: true}
      }

  """

  @type error_type ::
          :not_assignable
          | :invalid_node
          | :undefined_variable
          | :invalid_key
          | :computed_key
          | :not_a_container
          | :invalid_index

  @type t :: %__MODULE__{
          type: error_type(),
          message: binary(),
          details: map()
        }

  defstruct [:type, :message, :details]

  @doc """
  Creates a LocationError for non-assignable expressions.

  Used when an expression cannot be used as an assignment target (l-value).
  """
  @spec not_assignable(binary(), term()) :: t()
  def not_assignable(expression_type, value) do
    %__MODULE__{
      type: :not_assignable,
      message: "Cannot assign to #{expression_type}",
      details: %{
        expression_type: expression_type,
        value: value
      }
    }
  end

  @doc """
  Creates a LocationError for invalid or unknown AST node types.
  """
  @spec invalid_node(binary(), term()) :: t()
  def invalid_node(message, node) do
    %__MODULE__{
      type: :invalid_node,
      message: message,
      details: %{
        node: node
      }
    }
  end

  @doc """
  Creates a LocationError for undefined variables in bracket keys.
  """
  @spec undefined_variable(binary(), binary()) :: t()
  def undefined_variable(message, variable_name) do
    %__MODULE__{
      type: :undefined_variable,
      message: message,
      details: %{
        variable: variable_name
      }
    }
  end

  @doc """
  Creates a LocationError for invalid bracket key types.
  """
  @spec invalid_key(binary(), term()) :: t()
  def invalid_key(message, key_value) do
    %__MODULE__{
      type: :invalid_key,
      message: message,
      details: %{
        key_type: get_type_name(key_value),
        key_value: key_value
      }
    }
  end

  @doc """
  Creates a LocationError for computed expressions used as bracket keys.
  """
  @spec computed_key(binary(), term()) :: t()
  def computed_key(message, expression) do
    %__MODULE__{
      type: :computed_key,
      message: message,
      details: %{
        expression: expression
      }
    }
  end

  @doc """
  Creates a LocationError for assignment through a non-container value.

  Used when a location path traverses a value that is neither a map nor a list,
  so intermediate structure cannot be created without destroying existing data.

  `path_index` is the failing segment's 0-based index in the root-first location
  path, or `nil` when the caller cannot identify one. `Predicator.Evaluator`'s
  `store` path joins it with the run's segment-position table to point a store
  failure at the segment that failed rather than at the location's root (px-ids).
  It is deliberately a `details` key rather than a struct field: this struct is
  shared with `Predicator.ContextLocation.resolve/2` and
  `Predicator.Context.assign/3`, which have no path to index.
  """
  @spec not_a_container(binary(), term(), term(), non_neg_integer() | nil) :: t()
  def not_a_container(location, segment, value, path_index \\ nil) do
    %__MODULE__{
      type: :not_a_container,
      message: "Cannot assign through non-container value at '#{location}'",
      details: %{
        location: location,
        segment: segment,
        value: value,
        value_type: get_type_name(value),
        path_index: path_index
      }
    }
  end

  @doc """
  Creates a LocationError for an out-of-range list index in a location path.

  `path_index` is the failing segment's 0-based index in the root-first location
  path, or `nil` when the caller cannot identify one - see `not_a_container/4`.
  It is unrelated to `index`: `index` is the out-of-range *list* index the
  segment held, `path_index` is where that segment sits in the path itself, and
  the two are different integers that happen to share a neighborhood in
  `details`.
  """
  @spec invalid_index(binary(), integer(), non_neg_integer() | nil) :: t()
  def invalid_index(location, index, path_index \\ nil) do
    %__MODULE__{
      type: :invalid_index,
      message: "Invalid list index #{index} at '#{location}'",
      details: %{location: location, index: index, path_index: path_index}
    }
  end

  # Helper function to get readable type names
  defp get_type_name(%Date{}), do: "date"
  defp get_type_name(%DateTime{}), do: "datetime"
  defp get_type_name(value) when is_binary(value), do: "string"
  defp get_type_name(value) when is_integer(value), do: "integer"
  defp get_type_name(value) when is_float(value), do: "float"
  defp get_type_name(value) when is_boolean(value), do: "boolean"
  defp get_type_name(value) when is_list(value), do: "list"
  defp get_type_name(value) when is_map(value), do: "map"
  defp get_type_name(:undefined), do: "undefined"
  defp get_type_name(_unknown), do: "unknown"
end
