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

# Ensure the Predicator application is started before tests run
# This ensures system functions are registered and available
Application.ensure_all_started(:predicator)

# Predicates written with `=` emit a deprecation warning (px-8um.5), and the
# suite is full of them. Capture log output so the runner stays readable;
# tests that assert on the warning use ExUnit.CaptureLog explicitly.
ExUnit.start(capture_log: true)
