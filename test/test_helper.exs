defmodule Predicator.SpanSlicing do
  @moduledoc """
  Slices the source text a `t:Predicator.Types.span/0` covers.

  Span tests assert on the text a span names rather than on hand-counted
  coordinates, so this lives here rather than in either test file: the parser
  suite and the integration suite both need it.
  """

  @doc "Returns the substring of `source` that `span` covers. Exclusive end."
  @spec slice(binary(), Predicator.Types.span()) :: binary()
  def slice(source, {start_position, end_position}) do
    lines = String.split(source, "\n")
    start_offset = offset(lines, start_position)

    String.slice(source, start_offset, offset(lines, end_position) - start_offset)
  end

  defp offset(lines, {line, column}) do
    lines
    |> Enum.take(line - 1)
    |> Enum.reduce(column - 1, fn text, acc -> acc + String.length(text) + 1 end)
  end
end

defmodule Predicator.ASTShape do
  @moduledoc """
  Drops the trailing source slot from every node of an AST.

  Most parser assertions are about node *shape* - what the tree is - while
  positions and spans have their own suites (`parser_positions_test.exs`,
  `parser_spans_test.exs`). This lets those assertions read as the shape they
  mean. It is test-only: `Predicator.Parser` has no position-stripping function
  as of 4.0, because the AST has one shape and consumers are expected to keep
  the slot.
  """

  @doc "Returns `ast` with every node's trailing slot removed."
  @spec strip(term()) :: term()
  def strip({:literal, value, _slot}), do: {:literal, value}

  def strip({:string_literal, value, quote_type, _slot}),
    do: {:string_literal, value, quote_type}

  def strip({:identifier, name, _slot}), do: {:identifier, name}
  def strip({:duration, units, _slot}), do: {:duration, units}

  def strip({:comparison, op, left, right, _slot}),
    do: {:comparison, op, strip(left), strip(right)}

  def strip({:arithmetic, op, left, right, _slot}),
    do: {:arithmetic, op, strip(left), strip(right)}

  def strip({:membership, op, left, right, _slot}),
    do: {:membership, op, strip(left), strip(right)}

  def strip({:unary, op, operand, _slot}), do: {:unary, op, strip(operand)}
  def strip({:logical_and, left, right, _slot}), do: {:logical_and, strip(left), strip(right)}
  def strip({:logical_or, left, right, _slot}), do: {:logical_or, strip(left), strip(right)}
  def strip({:logical_not, operand, _slot}), do: {:logical_not, strip(operand)}
  def strip({:list, elements, _slot}), do: {:list, Enum.map(elements, &strip/1)}
  def strip({:object, entries, _slot}), do: {:object, Enum.map(entries, &strip_entry/1)}

  def strip({:function_call, name, args, _slot}),
    do: {:function_call, name, Enum.map(args, &strip/1)}

  def strip({:bracket_access, object, key, _slot}),
    do: {:bracket_access, strip(object), strip(key)}

  def strip({:property_access, object, property, _slot}),
    do: {:property_access, strip(object), property}

  def strip({:relative_date, duration, direction, _slot}),
    do: {:relative_date, strip(duration), direction}

  def strip(node), do: node

  defp strip_entry({{:object_key, value, style, _slot}, node}),
    do: {{:object_key, value, style}, strip(node)}

  @doc """
  Returns `ast` with every node's trailing slot set to `nil`.

  This is the shape a caller hand-builds: a well-formed AST that carries no
  source metadata, which the visitors must still accept.
  """
  @spec blank(term()) :: term()
  def blank({:literal, value, _slot}), do: {:literal, value, nil}

  def blank({:string_literal, value, quote_type, _slot}),
    do: {:string_literal, value, quote_type, nil}

  def blank({:identifier, name, _slot}), do: {:identifier, name, nil}
  def blank({:duration, units, _slot}), do: {:duration, units, nil}

  def blank({:comparison, op, left, right, _slot}),
    do: {:comparison, op, blank(left), blank(right), nil}

  def blank({:arithmetic, op, left, right, _slot}),
    do: {:arithmetic, op, blank(left), blank(right), nil}

  def blank({:membership, op, left, right, _slot}),
    do: {:membership, op, blank(left), blank(right), nil}

  def blank({:unary, op, operand, _slot}), do: {:unary, op, blank(operand), nil}

  def blank({:logical_and, left, right, _slot}),
    do: {:logical_and, blank(left), blank(right), nil}

  def blank({:logical_or, left, right, _slot}), do: {:logical_or, blank(left), blank(right), nil}
  def blank({:logical_not, operand, _slot}), do: {:logical_not, blank(operand), nil}
  def blank({:list, elements, _slot}), do: {:list, Enum.map(elements, &blank/1), nil}
  def blank({:object, entries, _slot}), do: {:object, Enum.map(entries, &blank_entry/1), nil}

  def blank({:function_call, name, args, _slot}),
    do: {:function_call, name, Enum.map(args, &blank/1), nil}

  def blank({:bracket_access, object, key, _slot}),
    do: {:bracket_access, blank(object), blank(key), nil}

  def blank({:property_access, object, property, _slot}),
    do: {:property_access, blank(object), property, nil}

  def blank({:relative_date, duration, direction, _slot}),
    do: {:relative_date, blank(duration), direction, nil}

  def blank(node), do: node

  defp blank_entry({{:object_key, value, style, _slot}, node}),
    do: {{:object_key, value, style, nil}, blank(node)}
end

defmodule Predicator.Conformance.SchemaValidator do
  @moduledoc """
  A small, hand-rolled structural JSON Schema validator: required keys, JSON
  types, `enum`, `pattern`, one level of `items`, and `oneOf` over `required`.
  Not a general JSON Schema engine - no `$ref` resolution, no
  `allOf`/`not`, no `format` (`px-35i.4` Phase 5).

  Shared by `test/predicator/conformance/schema_validation_test.exs` and
  `test/predicator/conformance/ratchet_registry_test.exs` (`px-35i.8`) so both
  suites check against the same rules rather than two validators drifting
  apart. Lives in `test_helper.exs`, matching this repo's existing
  test-support pattern (`Predicator.SpanSlicing`, `Predicator.ASTShape`
  above) rather than a `test/support/` directory, which would need an
  `elixirc_paths` change to `mix.exs`.
  """

  @doc "Validates `instance` against `schema`, returning `:ok` or `{:error, reason}`."
  @spec validate(map(), term()) :: :ok | {:error, term()}
  def validate(schema, instance) do
    with :ok <- validate_type(schema["type"], instance),
         :ok <- validate_enum(schema["enum"], instance),
         :ok <- validate_pattern(schema["pattern"], instance),
         :ok <- validate_required(schema["required"], instance),
         :ok <- validate_properties(schema["properties"], instance),
         :ok <- validate_additional_properties(schema, instance),
         :ok <- validate_items(schema["items"], instance) do
      validate_one_of(schema["oneOf"], instance)
    end
  end

  @spec validate_type(String.t() | [String.t()] | nil, term()) :: :ok | {:error, term()}
  defp validate_type(nil, _instance), do: :ok
  defp validate_type(true, _instance), do: :ok

  defp validate_type(type, instance) when is_binary(type) do
    if json_type?(type, instance), do: :ok, else: {:error, {:wrong_type, type, instance}}
  end

  defp validate_type(types, instance) when is_list(types) do
    if Enum.any?(types, &json_type?(&1, instance)),
      do: :ok,
      else: {:error, {:wrong_type, types, instance}}
  end

  @spec json_type?(String.t(), term()) :: boolean()
  defp json_type?("string", v), do: is_binary(v)
  defp json_type?("integer", v), do: is_integer(v)
  defp json_type?("number", v), do: is_number(v)
  defp json_type?("boolean", v), do: is_boolean(v)
  defp json_type?("array", v), do: is_list(v)
  defp json_type?("null", v), do: is_nil(v)
  defp json_type?("object", v), do: is_map(v)

  @spec validate_enum([term()] | nil, term()) :: :ok | {:error, term()}
  defp validate_enum(nil, _instance), do: :ok

  defp validate_enum(allowed, instance) do
    if instance in allowed, do: :ok, else: {:error, {:not_in_enum, allowed, instance}}
  end

  @spec validate_pattern(String.t() | nil, term()) :: :ok | {:error, term()}
  defp validate_pattern(nil, _instance), do: :ok

  defp validate_pattern(pattern, instance) when is_binary(instance) do
    if Regex.match?(Regex.compile!(pattern), instance),
      do: :ok,
      else: {:error, {:pattern_mismatch, pattern, instance}}
  end

  defp validate_pattern(_pattern, _instance), do: :ok

  @spec validate_required([String.t()] | nil, term()) :: :ok | {:error, term()}
  defp validate_required(nil, _instance), do: :ok

  defp validate_required(keys, instance) when is_map(instance) do
    missing = Enum.reject(keys, &Map.has_key?(instance, &1))
    if missing == [], do: :ok, else: {:error, {:missing_required, missing}}
  end

  defp validate_required(_keys, _instance), do: :ok

  @spec validate_properties(map() | nil, term()) :: :ok | {:error, term()}
  defp validate_properties(nil, _instance), do: :ok

  defp validate_properties(properties, instance) when is_map(instance) do
    properties
    |> Enum.filter(fn {key, _subschema} -> Map.has_key?(instance, key) end)
    |> Enum.reduce_while(:ok, fn {key, subschema}, :ok ->
      case validate(subschema, instance[key]) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:property, key, reason}}}
      end
    end)
  end

  defp validate_properties(_properties, _instance), do: :ok

  @spec validate_additional_properties(map(), term()) :: :ok | {:error, term()}
  defp validate_additional_properties(%{"additionalProperties" => false} = schema, instance)
       when is_map(instance) do
    known = schema |> Map.get("properties", %{}) |> Map.keys() |> MapSet.new()
    extra = instance |> Map.keys() |> Enum.reject(&MapSet.member?(known, &1))

    if extra == [], do: :ok, else: {:error, {:unexpected_properties, extra}}
  end

  defp validate_additional_properties(_schema, _instance), do: :ok

  @spec validate_items(map() | nil, term()) :: :ok | {:error, term()}
  defp validate_items(nil, _instance), do: :ok
  defp validate_items(true, _instance), do: :ok

  defp validate_items(item_schema, instance) when is_list(instance) do
    instance
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {item, index}, :ok ->
      case validate(item_schema, item) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:item, index, reason}}}
      end
    end)
  end

  defp validate_items(_item_schema, _instance), do: :ok

  @spec validate_one_of([map()] | nil, term()) :: :ok | {:error, term()}
  defp validate_one_of(nil, _instance), do: :ok

  defp validate_one_of(subschemas, instance) do
    matches = Enum.count(subschemas, &(validate(&1, instance) == :ok))

    if matches == 1, do: :ok, else: {:error, {:one_of_matched, matches, subschemas}}
  end
end

# Ensure the Predicator application is started before tests run
# This ensures system functions are registered and available
Application.ensure_all_started(:predicator)

# Predicates written with `=` emit a deprecation warning (px-8um.5), and the
# suite is full of them. Capture log output so the runner stays readable;
# tests that assert on the warning use ExUnit.CaptureLog explicitly.
ExUnit.start(capture_log: true)
