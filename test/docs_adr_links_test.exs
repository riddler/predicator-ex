defmodule Predicator.DocsAdrLinksTest do
  @moduledoc """
  Binds `mix.exs`'s published `extras:` list to the ADR citations inside the
  pages it publishes.

  The invariant: ADRs are not published to hexdocs (the shared docs standard,
  px-la6), so no ADR appears in `extras:`, and every ADR citation in a
  published extra is an *absolute* GitHub URL (`docs/adr/README.md`'s "Link
  form is load-bearing" note). A relative ADR link in a published extra ships
  a 404 - or worse, an ex_doc warning-free page whose link silently targets a
  file hexdocs never received. Nothing at compile time keeps this true -
  `extras:` is a literal list in `mix.exs`, and the citations are prose
  scattered across Markdown files - so this test reads both at test time.
  """

  use ExUnit.Case, async: true

  @blob_prefix "https://github.com/riddler/predicator-ex/blob/main/"

  # Anti-vacuity floor, in the docs/isa.md `@opcode_count` idiom: a link
  # regex that starts silently matching nothing must fail the suite, not pass
  # it. The tree carries 24 absolute ADR links across published extras as of
  # this writing; the floor sits a few below so ordinary docs work does not
  # trip it.
  @min_absolute_adr_links 20

  @link_target_regex ~r/\]\(\s*([^)\s]+)/
  @adr_path_regex ~r/(?:^|\/)adr\/(\d{4})-[^\/]*\.md$/
  @adr_extra_regex ~r/docs\/adr\//

  describe "published extras" do
    # sabotage: add an ADR entry back to mix.exs extras: -> red
    test "no ADR is published as an extra" do
      for path <- published_extras() do
        refute Regex.match?(@adr_extra_regex, path),
               "#{path} is listed in mix.exs's extras:, but ADRs are not " <>
                 "published to hexdocs - cite them from published pages by " <>
                 "absolute GitHub URL instead"
      end
    end
  end

  describe "relative ADR links" do
    # sabotage: rewrite one of docs/architecture.md's absolute ADR links back
    # to its old relative form -> red
    test "no published extra links an ADR relatively" do
      for %{source: source, target: target, adr: adr} <-
            adr_links() |> Enum.filter(&(&1.form == :relative)) do
        flunk(
          "#{source} links ADR-#{adr} (#{target}) relatively, but ADRs are " <>
            "not published to hexdocs, so this link cannot resolve there - " <>
            "turn the citation into an absolute GitHub URL"
        )
      end
    end
  end

  describe "absolute ADR links" do
    # sabotage: change @blob_prefix to a URL no citation uses -> red
    test "the scan finds the ADR citations" do
      absolute_links = adr_links() |> Enum.filter(&(&1.form == :absolute))

      assert length(absolute_links) >= @min_absolute_adr_links,
             "expected at least #{@min_absolute_adr_links} absolute ADR links " <>
               "across published extras, found #{length(absolute_links)} - the " <>
               "link-scanning regex may be matching nothing"

      for source <- ~w(README.md docs/isa.md docs/architecture.md) do
        assert Enum.any?(absolute_links, &(&1.source == source)),
               "expected at least one absolute ADR link from #{source}, found " <>
                 "none - the scan may not be reaching this file, and the " <>
                 "aggregate floor above could be met by other files alone"
      end
    end
  end

  describe "ADR link targets" do
    # sabotage: point one citation at a filename that does not exist -> red
    test "every ADR link target exists on disk" do
      for %{source: source, target: target, adr: adr, resolved: resolved} <- adr_links() do
        assert File.exists?(resolved),
               "#{source} links #{target}, naming ADR-#{adr}, but the " <>
                 "resolved path #{resolved} does not exist on disk"
      end
    end
  end

  # The extras: entries, normalized from `path | {path, opts}` to a bare path.
  @spec published_extras() :: [String.t()]
  defp published_extras do
    Mix.Project.config()[:docs][:extras]
    |> Enum.map(&extra_path/1)
  end

  @spec extra_path({String.t(), keyword()} | String.t()) :: String.t()
  defp extra_path({path, _opts}), do: path
  defp extra_path(path), do: path

  # Every ADR link in every published extra, classified by form. A relative
  # target is expanded against its source's directory into a filesystem path
  # before the ADR pattern is applied, so citations like "../adr/0003-....md"
  # classify correctly; an absolute GitHub blob URL is already a full path
  # suffix once the prefix is stripped, and that remainder doubles as the
  # repo-relative path checked for existence.
  @spec adr_links() :: [map()]
  defp adr_links do
    for source <- published_extras(),
        target <- links_in(source),
        link = classify(source, target),
        link != nil do
      link
    end
  end

  @spec links_in(String.t()) :: [String.t()]
  defp links_in(source) do
    @link_target_regex
    |> Regex.scan(File.read!(source))
    |> Enum.map(fn [_match, target] -> target end)
  end

  @spec classify(String.t(), String.t()) :: map() | nil
  defp classify(source, target) do
    if String.starts_with?(target, @blob_prefix) do
      classify_absolute(source, target)
    else
      classify_relative(source, target)
    end
  end

  @spec classify_absolute(String.t(), String.t()) :: map() | nil
  defp classify_absolute(source, target) do
    remainder = String.replace_prefix(target, @blob_prefix, "")

    case adr_number(remainder) do
      nil ->
        nil

      number ->
        %{source: source, target: target, form: :absolute, adr: number, resolved: remainder}
    end
  end

  @spec classify_relative(String.t(), String.t()) :: map() | nil
  defp classify_relative(source, target) do
    resolved = Path.expand(target, Path.dirname(source))

    case adr_number(resolved) do
      nil ->
        nil

      number ->
        %{source: source, target: target, form: :relative, adr: number, resolved: resolved}
    end
  end

  @spec adr_number(String.t()) :: String.t() | nil
  defp adr_number(path) do
    case Regex.run(@adr_path_regex, path) do
      [_match, number] -> number
      nil -> nil
    end
  end
end
