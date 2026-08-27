defmodule Predicator.DocsExamplesTest do
  @moduledoc """
  Executes the code examples in the published documentation.

  The docs are the library's front door; a stale example there is worse than
  no example. `doctest_file/1` requires Elixir 1.15+, which every version the
  CI matrix runs satisfies - `mix.exs` now declares `~> 1.18`, so the guard is
  vestigial and kept only as a cheap safeguard against a future widening of
  the supported range.
  """
  use ExUnit.Case, async: true

  if Version.match?(System.version(), ">= 1.15.0") do
    doctest_file("README.md")
    doctest_file("docs/reference/language.md")
    doctest_file("docs/guides/nested-data-access.md")
    doctest_file("docs/guides/custom-functions.md")
    doctest_file("docs/guides/location-expressions.md")
    doctest_file("docs/guides/embedding.md")
  end
end
