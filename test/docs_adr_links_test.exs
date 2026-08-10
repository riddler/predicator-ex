defmodule Predicator.DocsAdrLinksTest do
  @moduledoc """
  Binds `mix.exs`'s published `extras:` list to the ADR citations inside the
  pages it publishes.

  The invariant: in a published extra, a *relative* link to an ADR must name a
  published ADR, and a link to an *unpublished* ADR must be an *absolute*
  GitHub URL (`docs/adr/README.md`'s "Link form is load-bearing" note).
  Nothing at compile time keeps this true - `extras:` is a literal list in
  `mix.exs`, and the citations are prose scattered across Markdown files - so
  this test reads both at test time and checks the invariant in both
  directions. A vacuous pass here ships a 404 on hexdocs, or sends a reader
  off-site for a page that is actually right next to the one they are on,
  with nothing noticing.
  """

  use ExUnit.Case, async: true

  # Publishing one of these is a decision, not a drift fix, and this literal
  # is where that decision becomes a visible edit (docs/adr/README.md's
  # governance rows: beads, the quality gate, worktree parallelism, tracker
  # authority, the human-gate placement, and the not-yet-accepted mirror
  # obligation).
  @governance_adrs ~w(0004 0005 0006 0007 0008 0010)

  @blob_prefix "https://github.com/riddler/predicator-ex/blob/main/"

  # Anti-vacuity floors, in the docs/isa.md `@opcode_count` idiom: a link
  # regex that starts silently matching nothing must fail the suite, not pass
  # it. The tree carries 24 relative ADR links and 6 absolute ones as of this
  # writing; the floors sit a few below both so ordinary docs work does not
  # trip them.
  @min_relative_adr_links 20
  @min_absolute_adr_links 5

  @link_target_regex ~r/\]\(\s*([^)\s]+)/
  @adr_path_regex ~r/(?:^|\/)adr\/(\d{4})-[^\/]*\.md$/
  @adr_extra_regex ~r/docs\/adr\/(\d{4})-/

  describe "relative ADR links" do
    # sabotage: drop the 0011 entry from mix.exs extras: -> red. To prove the
    # index itself is covered rather than merely reached, also rewrite
    # docs/architecture.md's two 0011 links to absolute form, so
    # docs/adr/README.md is the only relative citation left - the assert below
    # is inside a comprehension and fail-fasts, so a single mutation names
    # whichever site it hits first and says nothing about the index. See
    # docs/research/260808-px-9ab-sabotage-notes.md.
    test "every relative ADR link in a published extra names a published ADR" do
      relative_links = adr_links() |> Enum.filter(&(&1.form == :relative))

      assert length(relative_links) >= @min_relative_adr_links,
             "expected at least #{@min_relative_adr_links} relative ADR links " <>
               "across published extras, found #{length(relative_links)} - the " <>
               "link-scanning regex may be matching nothing"

      for source <- ~w(README.md docs/architecture.md docs/adr/README.md) do
        assert Enum.any?(relative_links, &(&1.source == source)),
               "expected at least one relative ADR link from #{source}, found " <>
                 "none - the scan may not be reaching this file, and the " <>
                 "aggregate floor above could be met by other files alone"
      end

      published = published_adr_numbers()

      for %{source: source, target: target, adr: adr} <- relative_links do
        assert MapSet.member?(published, adr),
               "#{source} links ADR-#{adr} (#{target}) relatively, but ADR-#{adr} " <>
                 "is not in mix.exs's extras: - either publish it or turn this " <>
                 "citation into an absolute GitHub URL"
      end
    end
  end

  describe "absolute ADR links" do
    # sabotage: restore embedding.md's ADR-0009 link to its absolute form -> red
    test "a published ADR is never linked from a published extra by absolute URL" do
      absolute_links = adr_links() |> Enum.filter(&(&1.form == :absolute))

      assert length(absolute_links) >= @min_absolute_adr_links,
             "expected at least #{@min_absolute_adr_links} absolute ADR links " <>
               "across published extras, found #{length(absolute_links)} - the " <>
               "link-scanning regex may be matching nothing"

      published = published_adr_numbers()

      for %{source: source, target: target, adr: adr} <- absolute_links do
        refute MapSet.member?(published, adr),
               "#{source} links ADR-#{adr} (#{target}) by absolute URL, but " <>
                 "ADR-#{adr} is published in mix.exs's extras: - it should be a " <>
                 "relative link so it resolves on hexdocs instead of sending " <>
                 "readers off-site for a page that is right next to this one"
      end
    end
  end

  describe "governance ADRs" do
    # sabotage: add ADR-0007 to mix.exs extras: -> red
    test "no governance ADR is published" do
      for adr <- MapSet.to_list(published_adr_numbers()) do
        refute adr in @governance_adrs,
               "ADR-#{adr} is a governance ADR with no audience among library " <>
                 "consumers, but it is listed in mix.exs's extras: - publishing " <>
                 "it is a decision, not a drift fix; if it was intended, update " <>
                 "@governance_adrs in this test too"
      end
    end
  end

  describe "ADR link targets" do
    # sabotage: point an index row at a filename that does not exist -> red
    test "every ADR link target exists on disk" do
      relative_links = adr_links() |> Enum.filter(&(&1.form == :relative))

      for %{source: source, target: target, resolved: resolved} <- relative_links do
        assert File.exists?(resolved),
               "#{source} links #{target} (relative), naming ADR-" <>
                 "#{adr_number(resolved)}, but the resolved path #{resolved} " <>
                 "does not exist on disk"
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

  # Every ADR number named by a published extra's own entry (`docs/adr/NNNN-
  # ....md`), as opposed to a number some other page merely *links to*.
  @spec published_adr_numbers() :: MapSet.t(String.t())
  defp published_adr_numbers do
    published_extras()
    |> Enum.flat_map(&extra_adr_number/1)
    |> MapSet.new()
  end

  @spec extra_adr_number(String.t()) :: [String.t()]
  defp extra_adr_number(path) do
    case Regex.run(@adr_extra_regex, path) do
      [_match, number] -> [number]
      nil -> []
    end
  end

  # Every ADR link in every published extra, classified by form. Resolution
  # happens before classification: a relative target is expanded against its
  # source's directory into an absolute filesystem path *first*, and only the
  # resolved path is matched for an ADR number. Doing it the other way round
  # would miss every row of docs/adr/README.md, whose targets are bare
  # sibling filenames ("0009-....md") with no "adr/" segment in the raw text
  # at all - resolving against docs/adr/, the source's own directory, is what
  # produces the "/adr/0009-....md" the classifier matches on.
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

  # An absolute GitHub blob URL is already a full path suffix once the
  # prefix is stripped, so no filesystem resolution is needed - the ADR
  # pattern is applied directly to what remains.
  @spec classify_absolute(String.t(), String.t()) :: map() | nil
  defp classify_absolute(source, target) do
    remainder = String.replace_prefix(target, @blob_prefix, "")

    case adr_number(remainder) do
      nil -> nil
      number -> %{source: source, target: target, form: :absolute, adr: number, resolved: nil}
    end
  end

  # A relative target is resolved against its source file's own directory
  # before classification, per the module-level comment on adr_links/0.
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
