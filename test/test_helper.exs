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

# Ensure the Predicator application is started before tests run
# This ensures system functions are registered and available
Application.ensure_all_started(:predicator)

# Predicates written with `=` emit a deprecation warning (px-8um.5), and the
# suite is full of them. Capture log output so the runner stays readable;
# tests that assert on the warning use ExUnit.CaptureLog explicitly.
ExUnit.start(capture_log: true)
