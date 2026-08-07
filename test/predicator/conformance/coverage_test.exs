defmodule Predicator.Conformance.CoverageTest do
  use ExUnit.Case, async: true

  doctest Predicator.Conformance.Coverage

  alias Predicator.Conformance.Coverage

  describe "extract_sources/1" do
    test "extracts a literal source from Predicator.evaluate/2" do
      content = "Predicator.evaluate(\"score > 85\", %{\"score\" => 90})"
      assert Coverage.extract_sources(content) == ["score > 85"]
    end

    test "extracts a literal source from Predicator.evaluate/3 with an opts argument" do
      content = "Predicator.evaluate(\"a and b\", %{}, on_unbound: :error)"
      assert Coverage.extract_sources(content) == ["a and b"]
    end

    test "extracts a literal source from Predicator.compile/1" do
      content = "Predicator.compile(\"1 + 1\")"
      assert Coverage.extract_sources(content) == ["1 + 1"]
    end

    test "extracts every literal call site in a file, deduplicated" do
      content = """
      defmodule Sample do
        def run do
          Predicator.evaluate("a > 1", %{"a" => 2})
          Predicator.evaluate("a > 1", %{"a" => 2})
          Predicator.compile("b < 2")
        end
      end
      """

      assert Coverage.extract_sources(content) |> Enum.sort() == ["a > 1", "b < 2"]
    end

    test "does not extract a call whose source argument is a variable" do
      content = """
      source = "a > 1"
      Predicator.evaluate(source, %{})
      """

      assert Coverage.extract_sources(content) == []
    end

    test "does not extract calls to unrelated modules or functions" do
      content = "SomeOther.evaluate(\"a > 1\", %{})"
      assert Coverage.extract_sources(content) == []
    end

    test "returns an empty list for a file that fails to parse" do
      assert Coverage.extract_sources("def broken(") == []
    end
  end

  describe "suite_pattern_frequencies/1" do
    test "compiles each source and counts opcode patterns" do
      freqs = Coverage.suite_pattern_frequencies(["1 > 2", "1 > 2", "a == b"])

      assert freqs["compare:GT"] == 2
      assert freqs["compare:EQ"] == 1
      assert freqs["lit"] == 4
      assert freqs["load"] == 2
    end

    test "a source that fails to compile contributes nothing, without raising" do
      freqs = Coverage.suite_pattern_frequencies(["score >", "1 > 2"])
      assert freqs == %{"compare:GT" => 1, "lit" => 2}
    end

    test "call patterns are keyed by function name" do
      freqs = Coverage.suite_pattern_frequencies(["len(\"abc\")"])
      assert freqs["call:len"] == 1
    end
  end

  describe "corpus_pattern_frequencies/1" do
    test "reads instructions from decoded corpus case maps" do
      cases = [
        %{"instructions" => [["load", "a"], ["lit", 1], ["compare", "GT"]]},
        %{"instructions" => [["lit", true]]}
      ]

      assert Coverage.corpus_pattern_frequencies(cases) == %{
               "load" => 1,
               "lit" => 2,
               "compare:GT" => 1
             }
    end

    test "a case with no instructions field contributes nothing" do
      assert Coverage.corpus_pattern_frequencies([%{"id" => "no-instructions"}]) == %{}
    end
  end

  describe "diff/2" do
    test "reports only patterns the suite hits more than the corpus" do
      suite = %{"compare:GT" => 5, "compare:STRICT_EQ" => 2, "lit" => 10}
      corpus = %{"compare:GT" => 5, "lit" => 3}

      assert Coverage.diff(suite, corpus) == [
               %{
                 tier: 1,
                 tier_name: "core",
                 pattern: "lit",
                 suite_count: 10,
                 corpus_count: 3
               },
               %{
                 tier: 1,
                 tier_name: "core",
                 pattern: "compare:STRICT_EQ",
                 suite_count: 2,
                 corpus_count: 0
               }
             ]
    end

    test "a pattern the corpus covers at least as often as the suite is not a gap" do
      assert Coverage.diff(%{"lit" => 3}, %{"lit" => 3}) == []
      assert Coverage.diff(%{"lit" => 3}, %{"lit" => 5}) == []
    end

    test "an unrecognized opcode is skipped rather than crashing" do
      assert Coverage.diff(%{"nonexistent_opcode" => 1}, %{}) == []
    end

    test "sorted by tier, then descending suite count, then pattern" do
      suite = %{"add" => 2, "lit" => 1, "modulo" => 5}
      corpus = %{}

      assert Coverage.diff(suite, corpus) |> Enum.map(& &1.pattern) ==
               ["lit", "modulo", "add"]
    end
  end

  describe "format_report/1" do
    test "an empty gap list prints a clean-report message" do
      assert Coverage.format_report([]) =~ "No coverage gaps found"
    end

    test "groups entries by tier with a header naming the tier and its name" do
      gaps = [
        %{tier: 1, tier_name: "core", pattern: "lit", suite_count: 10, corpus_count: 3},
        %{tier: 2, tier_name: "arithmetic", pattern: "add", suite_count: 4, corpus_count: 1}
      ]

      report = Coverage.format_report(gaps)

      assert report =~ "Tier 1 (core):"
      assert report =~ "lit - suite: 10, corpus: 3"
      assert report =~ "Tier 2 (arithmetic):"
      assert report =~ "add - suite: 4, corpus: 1"
    end
  end
end
