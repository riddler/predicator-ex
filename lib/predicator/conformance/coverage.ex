defmodule Predicator.Conformance.Coverage do
  @moduledoc """
  The diffing logic behind `mix corpus.coverage` (`px-35i.4` Phase 6).

  The corpus is authored JSON, not extracted from the existing 16k-line
  ExUnit suite (see the plan's "The generation mechanism" section) - so
  nothing keeps the corpus in step with what that suite actually exercises.
  This module is the coverage instrument that closes that loop: it turns the
  suite into an authoring checklist rather than a source, without making it
  the corpus's source of truth.

  ## What this measures, and what it does not

  This is a **heuristic, best-effort report**, not a precise instrument. It
  works in three steps, all pure functions here plus real compiler calls -
  never `eval`, never hand-rolled opcode matching against source text:

  1. `extract_sources/1` statically scans one `.exs` file's AST for calls to
     `Predicator.evaluate/2`, `Predicator.evaluate/3`, or `Predicator.compile/1`
     whose first argument is a literal string, and returns those literal
     source strings. This is exactly the ~25% static-AST pass the plan's
     "Current State Analysis" section already describes and sanctions as a
     legitimate, partial signal - used here for a report, not as the corpus's
     authoring mechanism, so the drift caveats that ruled it out as the
     mechanism do not apply.
  2. `suite_pattern_frequencies/1` compiles each extracted source through the
     real `Predicator.compile/1` (not string matching) and counts **patterns**:
     an opcode name for most instructions, but `"compare:OPERATOR"` for
     `compare` and `"call:function_name"` for `call`, because those two
     opcodes carry the operand that actually distinguishes one case from
     another (`STRICT_EQ` vs `GT`, `len` vs `upper`) - the same operand-aware
     cut `Predicator.Conformance.Features` already makes for feature tags.
     A source that fails to compile is skipped; the AST scan is approximate
     and a false-positive extraction (e.g. a string that merely looks like a
     literal source but is test scaffolding) is expected and harmless here.
  3. `corpus_pattern_frequencies/1` computes the same patterns from the
     shipped corpus's own `instructions` (already decoded JSON case maps),
     and `diff/2` reports every pattern the suite's static extraction hits
     more often than the corpus does, grouped by tier.

  What this does **not** see: the ~75% of suite assertions that build context
  from a bound variable or executed setup (unresolvable without running the
  suite), any assertion carrying a third `opts` argument, error-shape
  assertions, or instruction-list literals fed directly to `evaluate/2,3`.
  Those are exactly the classes the bead's own extractability note names as
  unreachable by a static pass. The report is therefore a floor on suite
  coverage, not a ceiling, and its top entries need a human read before being
  authored as cases - some will be Elixir-internal scaffolding (opts
  handling, struct internals) rather than genuine corpus gaps.

  ## Classifying tier-5 (`call:<name>`) gaps

  `diff/2` alone cannot tell a genuine builtin gap from noise: a `call:<name>`
  pattern's name might be a test-registered function (`boom`, `double`, ...)
  that a sibling implementation could never implement, or a builtin whose
  result is non-deterministic (`Date.now`, `Math.random`) and therefore can
  never get a pinned corpus case either. `classify/2` sorts every gap into
  one of three statuses (`px-q1f`):

  - `:gap` - a genuine builtin gap, worth authoring.
  - `:excluded` - a documented exclusion: `relative_date` (an opcode, see
    `conformance/README.md`'s "Opcodes excluded from the coverage rule") or a
    name in `documented_exclusion_functions/0` (see the README's "Functions
    excluded from the coverage rule"). Shown inline with a note rather than as
    a bare `corpus: 0` row.
  - `:suite_local` - a `call:<name>` whose name is not a key of the caller-
    supplied builtin registry (in practice `Predicator.Evaluator.
    merge_functions([])`), so it was registered by an individual ExUnit test
    via its own `opts[:functions]` map and can never become a corpus case.
    `format_report/1` moves these to a trailing labelled section rather than
    dropping them silently - the report is a heuristic instrument, and a
    reader who remembers writing a test for one of these names should be able
    to see where it went rather than wonder if the scan missed it.

  Classification is deliberately **not** a hardcoded name list on the "this is
  a builtin" side: `classify/2` takes the registry as data from the caller
  (`mix corpus.coverage` passes `Predicator.Evaluator.merge_functions([])`'s
  keys) so a new builtin needs no update here to stop showing up as
  suite-local.

  Report only: nothing here writes a case or fails a gate.
  """

  alias Predicator.Instructions

  @typedoc "A pattern: an opcode name, or `\"opcode:operand\"` for `compare`/`call`."
  @type pattern :: String.t()

  @typedoc "pattern => how many times it was observed."
  @type pattern_frequencies :: %{pattern() => pos_integer()}

  @typedoc """
  A gap's classification, set by `classify/2` (absent - equivalently `:gap` -
  on a gap fresh out of `diff/2`, which knows nothing about the builtin
  registry):

  - `:gap` - worth authoring.
  - `:excluded` - a documented, non-deterministic exclusion; see the
    moduledoc's "Classifying tier-5 gaps" section.
  - `:suite_local` - a test-registered function name, never a corpus
    candidate.
  """
  @type gap_status :: :gap | :excluded | :suite_local

  @typedoc "One coverage gap: a pattern the suite hits more than the corpus does."
  @type gap :: %{
          required(:tier) => pos_integer(),
          required(:tier_name) => String.t(),
          required(:pattern) => pattern(),
          required(:suite_count) => pos_integer(),
          required(:corpus_count) => non_neg_integer(),
          optional(:status) => gap_status()
        }

  # The opcode-level documented exclusion (conformance/README.md's "Opcodes
  # excluded from the coverage rule"). A plain list, not a MapSet, because
  # classify_gap/2 below matches it in a function-head guard, and `in` is
  # only guard-safe against a literal list or range. Kept here as the
  # tier-5-adjacent sibling of @documented_exclusion_functions below rather
  # than imported from opcode_coverage_test.exs's @excluded_opcodes - that
  # module attribute is private to a test module, and duplicating one atom is
  # cheaper than reaching into a test file from lib code.
  @documented_exclusion_opcodes ~w(relative_date)

  # Function-level documented exclusions (conformance/README.md's "Functions
  # excluded from the coverage rule") - non-deterministic builtins that, like
  # relative_date above, no case can pin an expected value for. Kept in sync
  # with the README by Predicator.Conformance.CoverageTest's
  # "documented exclusion functions match conformance/README.md" test.
  @documented_exclusion_functions MapSet.new(["Date.now", "Math.random"])

  # Display names only - Predicator.Instructions.opcodes/0 remains the single
  # source of truth for tier membership; this table exists purely so the
  # printed report reads "Tier 3 (access)" instead of a bare number, and it is
  # never consulted to decide what tier an opcode is in.
  @tier_names %{
    1 => "core",
    2 => "arithmetic",
    3 => "access",
    4 => "rich types",
    5 => "functions",
    6 => "statements",
    7 => "casts"
  }

  @doc """
  Extracts literal source strings from one file's Elixir source.

  Scans the AST (not a regex over the text) for calls to
  `Predicator.evaluate/2`, `Predicator.evaluate/3`, or `Predicator.compile/1`
  whose first argument is a literal string. A file that fails to parse
  returns `[]` rather than raising - this is a best-effort scan over test
  files, not a compiler.

  ## Examples

      iex> Predicator.Conformance.Coverage.extract_sources("Predicator.evaluate(\\"a > 1\\", %{})")
      ["a > 1"]

      iex> Predicator.Conformance.Coverage.extract_sources("Predicator.compile(\\"x\\")")
      ["x"]

      iex> Predicator.Conformance.Coverage.extract_sources("Predicator.evaluate(source, %{})")
      []

      iex> Predicator.Conformance.Coverage.extract_sources("not valid elixir (")
      []
  """
  @spec extract_sources(String.t()) :: [String.t()]
  def extract_sources(file_content) when is_binary(file_content) do
    case Code.string_to_quoted(file_content) do
      {:ok, ast} -> ast |> collect_literal_sources() |> Enum.uniq()
      {:error, _reason} -> []
    end
  end

  @spec collect_literal_sources(Macro.t()) :: [String.t()]
  defp collect_literal_sources(ast) do
    {_ast, sources} = Macro.prewalk(ast, [], &collect_node/2)
    Enum.reverse(sources)
  end

  @spec collect_node(Macro.t(), [String.t()]) :: {Macro.t(), [String.t()]}
  defp collect_node(
         {{:., _meta, [{:__aliases__, _alias_meta, [:Predicator]}, fun]}, _call_meta,
          [source | _rest]} = node,
         acc
       )
       when fun in [:evaluate, :compile] and is_binary(source) do
    {node, [source | acc]}
  end

  defp collect_node(node, acc), do: {node, acc}

  @doc """
  Computes pattern frequencies for a list of extracted source strings.

  Each source is compiled through the real `Predicator.compile/1`. A source
  that fails to compile contributes nothing - the extraction in
  `extract_sources/1` is approximate, so an uncompilable "source" is expected
  (e.g. a string that merely looked like one).

  ## Examples

      iex> Predicator.Conformance.Coverage.suite_pattern_frequencies(["1 > 2", "1 > 2", "a == b"])
      %{"compare:GT" => 2, "compare:EQ" => 1, "lit" => 4, "load" => 2}
  """
  @spec suite_pattern_frequencies([String.t()]) :: pattern_frequencies()
  def suite_pattern_frequencies(sources) when is_list(sources) do
    sources
    |> Enum.flat_map(&patterns_for_source/1)
    |> Enum.frequencies()
  end

  @spec patterns_for_source(String.t()) :: [pattern()]
  defp patterns_for_source(source) do
    case Predicator.compile(source) do
      {:ok, instructions} -> patterns_for_instructions(instructions)
      {:error, _message} -> []
    end
  rescue
    _exception -> []
  end

  @doc """
  Computes pattern frequencies from decoded corpus case maps (the shipped
  `conformance/corpus/tier-*.json` cases, already `JSON.decode/1`-ed).

  Reads each case's `"instructions"` field the same way `suite_pattern_frequencies/1`
  reads a compiled instruction list - the tagged-value codec only affects
  operand *values*, never the opcode strings this counts.

  ## Examples

      iex> cases = [%{"instructions" => [["load", "a"], ["lit", 1], ["compare", "GT"]]}]
      iex> Predicator.Conformance.Coverage.corpus_pattern_frequencies(cases)
      %{"load" => 1, "lit" => 1, "compare:GT" => 1}
  """
  @spec corpus_pattern_frequencies([map()]) :: pattern_frequencies()
  def corpus_pattern_frequencies(cases) when is_list(cases) do
    cases
    |> Enum.flat_map(fn case_map ->
      patterns_for_instructions(Map.get(case_map, "instructions", []))
    end)
    |> Enum.frequencies()
  end

  @spec patterns_for_instructions(list()) :: [pattern()]
  defp patterns_for_instructions(instructions) when is_list(instructions) do
    instructions |> Enum.map(&pattern_for_instruction/1) |> Enum.reject(&is_nil/1)
  end

  defp patterns_for_instructions(_not_a_list), do: []

  @spec pattern_for_instruction(term()) :: pattern() | nil
  defp pattern_for_instruction(["compare", operator | _rest]) when is_binary(operator) do
    "compare:" <> operator
  end

  defp pattern_for_instruction(["call", function_name | _rest]) when is_binary(function_name) do
    "call:" <> function_name
  end

  defp pattern_for_instruction([opcode | _rest]) when is_binary(opcode), do: opcode
  defp pattern_for_instruction(_malformed), do: nil

  @doc """
  Diffs suite pattern frequencies against corpus pattern frequencies.

  Returns every pattern the suite hits **more** than the corpus does (corpus
  absence counts as `0`), grouped implicitly by carrying each entry's tier -
  `format_report/1` does the grouping for display. A pattern whose opcode is
  not in `Predicator.Instructions.opcodes/0` (should not happen for anything
  that compiled, but kept defensive) is skipped rather than crashing the
  report.

  Sorted by tier, then by descending suite count, then by pattern name, so
  the most-exercised gap in the lowest tier sorts first - the tier a sibling
  is most likely to be working on right now.

  ## Examples

      iex> suite = %{"compare:GT" => 5, "compare:STRICT_EQ" => 2, "lit" => 10}
      iex> corpus = %{"compare:GT" => 5, "lit" => 3}
      iex> Predicator.Conformance.Coverage.diff(suite, corpus)
      [
        %{tier: 1, tier_name: "core", pattern: "lit", suite_count: 10, corpus_count: 3},
        %{tier: 1, tier_name: "core", pattern: "compare:STRICT_EQ", suite_count: 2, corpus_count: 0}
      ]
  """
  @spec diff(pattern_frequencies(), pattern_frequencies()) :: [gap()]
  def diff(suite_freqs, corpus_freqs) when is_map(suite_freqs) and is_map(corpus_freqs) do
    suite_freqs
    |> Enum.flat_map(fn {pattern, suite_count} -> gap_for(pattern, suite_count, corpus_freqs) end)
    |> Enum.sort_by(&{&1.tier, -&1.suite_count, &1.pattern})
  end

  @spec gap_for(pattern(), pos_integer(), pattern_frequencies()) :: [gap()]
  defp gap_for(pattern, suite_count, corpus_freqs) do
    corpus_count = Map.get(corpus_freqs, pattern, 0)

    with true <- suite_count > corpus_count,
         {:ok, tier} <- Instructions.tier(opcode_of(pattern)) do
      [
        %{
          tier: tier,
          tier_name: Map.get(@tier_names, tier, "tier #{tier}"),
          pattern: pattern,
          suite_count: suite_count,
          corpus_count: corpus_count
        }
      ]
    else
      _not_a_gap_or_unknown_opcode -> []
    end
  end

  @spec opcode_of(pattern()) :: String.t()
  defp opcode_of(pattern), do: pattern |> String.split(":", parts: 2) |> List.first()

  @doc """
  The builtin function names documented as non-deterministic exclusions in
  `conformance/README.md`'s "Functions excluded from the coverage rule"
  section - `Date.now` and `Math.random`. `classify/2` marks a `call:<name>`
  gap whose name is in this set as `:excluded` rather than `:gap`, the same
  treatment `relative_date` gets as an opcode-level exclusion.

  ## Examples

      iex> Predicator.Conformance.Coverage.documented_exclusion_functions() |> Enum.sort()
      ["Date.now", "Math.random"]
  """
  @spec documented_exclusion_functions() :: MapSet.t(String.t())
  def documented_exclusion_functions, do: @documented_exclusion_functions

  @doc """
  Classifies each gap's `:status` (see the moduledoc's "Classifying tier-5
  gaps" section and `t:gap_status/0`): `:gap`, `:excluded`, or `:suite_local`.

  `builtin_names` is the set of function names the classifier treats as
  real builtins - in practice the caller passes
  `Predicator.Evaluator.merge_functions([])`'s keys, so this module never
  hardcodes "what is a builtin" itself. A gap whose pattern is not a
  `call:<name>` pattern (i.e. not tier 5) is `:gap` unless it is the
  documented opcode exclusion `relative_date`.

  ## Examples

      iex> gaps = [
      ...>   %{tier: 5, tier_name: "functions", pattern: "call:Math.abs", suite_count: 3, corpus_count: 0},
      ...>   %{tier: 5, tier_name: "functions", pattern: "call:Date.now", suite_count: 6, corpus_count: 0},
      ...>   %{tier: 5, tier_name: "functions", pattern: "call:boom", suite_count: 2, corpus_count: 0},
      ...>   %{tier: 4, tier_name: "rich types", pattern: "relative_date", suite_count: 4, corpus_count: 0}
      ...> ]
      iex> Predicator.Conformance.Coverage.classify(gaps, MapSet.new(["Math.abs", "Date.now"]))
      ...> |> Enum.map(& &1.status)
      [:gap, :excluded, :suite_local, :excluded]
  """
  @spec classify([gap()], MapSet.t(String.t())) :: [gap()]
  def classify(gaps, builtin_names) when is_list(gaps) do
    Enum.map(gaps, &classify_gap(&1, builtin_names))
  end

  @spec classify_gap(gap(), MapSet.t(String.t())) :: gap()
  defp classify_gap(%{pattern: pattern} = gap, _builtin_names)
       when pattern in @documented_exclusion_opcodes do
    Map.put(gap, :status, :excluded)
  end

  defp classify_gap(%{pattern: "call:" <> function_name} = gap, builtin_names) do
    Map.put(gap, :status, call_status(function_name, builtin_names))
  end

  defp classify_gap(gap, _builtin_names), do: Map.put(gap, :status, :gap)

  @spec call_status(String.t(), MapSet.t(String.t())) :: gap_status()
  defp call_status(function_name, builtin_names) do
    cond do
      MapSet.member?(@documented_exclusion_functions, function_name) -> :excluded
      MapSet.member?(builtin_names, function_name) -> :gap
      true -> :suite_local
    end
  end

  @doc """
  Formats a list of gaps (as returned by `diff/2`, typically classified by
  `classify/2` first) as a human-readable report, grouped by tier so it is
  actionable one tier at a time.

  A gap's `:status` (absent counts as `:gap`) controls how it is shown:
  `:gap` prints plainly, `:excluded` gets an inline note instead of
  appearing as an unqualified `corpus: 0` row, and `:suite_local` entries are
  pulled out of every tier and moved to a trailing labelled section rather
  than being silently dropped - this is a heuristic instrument, and a reader
  who remembers writing a test against one of these names should see where it
  went, not wonder if the scan missed it.

  ## Examples

      iex> Predicator.Conformance.Coverage.format_report([])
      "No coverage gaps found: every pattern the suite's extracted sources exercise\\nappears at least as often in the corpus.\\n"
  """
  @spec format_report([gap()]) :: String.t()
  def format_report([]) do
    "No coverage gaps found: every pattern the suite's extracted sources exercise\n" <>
      "appears at least as often in the corpus.\n"
  end

  def format_report(gaps) when is_list(gaps) do
    {suite_local, reportable} = Enum.split_with(gaps, &(status_of(&1) == :suite_local))

    tiers_report =
      reportable
      |> Enum.group_by(& &1.tier)
      |> Enum.sort_by(fn {tier, _entries} -> tier end)
      |> Enum.map_join("\n", &format_tier/1)

    tiers_report <> format_suite_local_section(suite_local)
  end

  @spec status_of(gap()) :: gap_status()
  defp status_of(gap), do: Map.get(gap, :status, :gap)

  @spec format_tier({pos_integer(), [gap()]}) :: String.t()
  defp format_tier({tier, entries}) do
    %{tier_name: tier_name} = List.first(entries)
    header = "Tier #{tier} (#{tier_name}):\n"
    lines = Enum.map_join(entries, "\n", &format_gap_line/1)

    header <> lines <> "\n"
  end

  @spec format_gap_line(gap()) :: String.t()
  defp format_gap_line(entry) do
    base = "  #{entry.pattern} - suite: #{entry.suite_count}, corpus: #{entry.corpus_count}"

    case status_of(entry) do
      :excluded -> base <> " (documented exclusion: non-deterministic, see conformance/README.md)"
      _gap -> base
    end
  end

  @spec format_suite_local_section([gap()]) :: String.t()
  defp format_suite_local_section([]), do: ""

  defp format_suite_local_section(entries) do
    lines =
      entries
      |> Enum.sort_by(&{-&1.suite_count, &1.pattern})
      |> Enum.map_join("\n", fn entry ->
        "  #{entry.pattern} - suite: #{entry.suite_count}, corpus: #{entry.corpus_count}"
      end)

    "\nNot corpus candidates (suite-local test functions, never real corpus " <>
      "gaps - not a key in the builtin registry):\n" <> lines <> "\n"
  end
end
