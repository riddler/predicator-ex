defmodule Mix.Tasks.Corpus.CoverageTest do
  # Not async: the task reads test/**/*.exs and conformance/corpus/*.json
  # relative to the process cwd, so each test below File.cd!s into a scratch
  # directory for the duration of the run - the same pattern
  # corpus_generate_test.exs uses, for the same reason.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Corpus.Coverage, as: Task

  setup do
    tmp =
      Path.join(System.tmp_dir!(), "corpus_coverage_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(tmp, "test/predicator/conformance"))
    File.mkdir_p!(Path.join(tmp, "conformance/corpus"))
    original_cwd = File.cwd!()
    File.cd!(tmp)

    on_exit(fn ->
      File.cd!(original_cwd)
      File.rm_rf!(tmp)
    end)

    :ok
  end

  defp write_test_file(relative_path, content) do
    File.mkdir_p!(Path.dirname(relative_path))
    File.write!(relative_path, content)
  end

  defp write_corpus_tier(tier, lines) do
    content = Enum.map_join(lines, &(JSON.encode!(&1) <> "\n"))
    File.write!("conformance/corpus/tier-#{tier}.json", content)
  end

  test "prints a non-empty report naming a gap the suite has and the corpus does not" do
    write_test_file(
      "test/some_test.exs",
      ~S"""
      defmodule SomeTest do
        use ExUnit.Case

        test "checks something" do
          assert Predicator.evaluate("a > 1", %{"a" => 2}) == {:ok, true}
        end
      end
      """
    )

    write_corpus_tier(1, [%{"instructions" => [["lit", 1]]}])

    output = capture_io(fn -> Task.run([]) end)

    assert output =~ "Scanned 1 suite file(s), extracted 1 literal source(s)"
    assert output =~ "Tier 1"
    assert output =~ "load"
  end

  test "excludes test/predicator/conformance/** from the scan" do
    write_test_file(
      "test/predicator/conformance/generator_test.exs",
      ~S"""
      defmodule Excluded do
        use ExUnit.Case
        test "x", do: Predicator.evaluate("only_in_excluded_dir_xyz", %{})
      end
      """
    )

    write_corpus_tier(1, [%{"instructions" => [["lit", 1]]}])

    output = capture_io(fn -> Task.run([]) end)

    assert output =~ "Scanned 0 suite file(s), extracted 0 literal source(s)"
    refute output =~ "only_in_excluded_dir_xyz"
  end

  test "a clean tree (nothing extracted) prints the no-gaps message" do
    write_corpus_tier(1, [%{"instructions" => [["lit", 1]]}])

    output = capture_io(fn -> Task.run([]) end)

    assert output =~ "No coverage gaps found"
  end

  test "classifies tier-5 gaps: builtin gap plain, non-deterministic builtin marked inline, suite-local moved to a trailing section" do
    write_test_file(
      "test/some_test.exs",
      ~S"""
      defmodule SomeTest do
        use ExUnit.Case

        test "checks something" do
          assert Predicator.evaluate("Math.abs(-1)", %{}) == {:ok, 1}
          assert Predicator.evaluate("Date.now()", %{}) != nil
          assert Predicator.evaluate("boom()", %{}, functions: %{"boom" => {0, fn _, _ -> {:ok, 1} end}}) != nil
        end
      end
      """
    )

    write_corpus_tier(1, [%{"instructions" => [["lit", 1]]}])

    output = capture_io(fn -> Task.run([]) end)

    assert output =~ "call:Math.abs - suite: 1, corpus: 0\n"

    assert output =~
             "call:Date.now - suite: 1, corpus: 0 (documented exclusion: non-deterministic, see conformance/README.md)"

    assert output =~ "Not corpus candidates"
    assert output =~ "call:boom - suite: 1, corpus: 0"
  end
end
