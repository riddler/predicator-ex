defmodule Mix.Tasks.Corpus.GenerateTest do
  # Not async: the task reads and writes paths relative to the process cwd
  # (conformance/cases/*.json, conformance/corpus/, conformance/manifest.json),
  # so each test below `File.cd!`s into a scratch directory for the duration
  # of the run. ExUnit runs `async: false` suites only after every `async:
  # true` suite has finished, so this never races another test's relative-path
  # reads (e.g. generator_test.exs's "conformance/cases/core.json").
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Corpus.Generate, as: Task

  setup do
    tmp =
      Path.join(System.tmp_dir!(), "corpus_generate_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(tmp, "conformance/cases"))
    original_cwd = File.cwd!()
    File.cd!(tmp)

    on_exit(fn ->
      File.cd!(original_cwd)
      File.rm_rf!(tmp)
    end)

    :ok
  end

  defp write_cases(cases) do
    File.write!("conformance/cases/seed.json", JSON.encode!(cases))
  end

  describe "run/1 - writing" do
    test "writes one tier file per known tier and a manifest" do
      write_cases([%{"id" => "t/lit", "source" => "42", "expected" => %{"result" => 42}}])

      capture_io(fn -> Task.run([]) end)

      assert File.exists?("conformance/corpus/tier-1.json")
      assert File.exists?("conformance/manifest.json")

      manifest = "conformance/manifest.json" |> File.read!() |> JSON.decode!()
      assert manifest["isa_version"] == Predicator.isa_version()
      assert String.starts_with?(manifest["corpus_hash"], "sha256:")

      tier_1 = Enum.find(manifest["tiers"], &(&1["tier"] == 1))
      assert tier_1["file"] == "corpus/tier-1.json"
      assert tier_1["case_count"] == 1
    end

    test "running twice produces byte-identical files" do
      write_cases([%{"id" => "t/lit", "source" => "42"}])

      capture_io(fn -> Task.run([]) end)
      first_manifest = File.read!("conformance/manifest.json")
      first_tier_1 = File.read!("conformance/corpus/tier-1.json")

      capture_io(fn -> Task.run([]) end)
      second_manifest = File.read!("conformance/manifest.json")
      second_tier_1 = File.read!("conformance/corpus/tier-1.json")

      assert first_manifest == second_manifest
      assert first_tier_1 == second_tier_1
    end
  end

  describe "run/1 --check" do
    test "exits cleanly (no raise) when the tree already matches" do
      write_cases([%{"id" => "t/lit", "source" => "42"}])
      capture_io(fn -> Task.run([]) end)

      output = capture_io(fn -> Task.run(["--check"]) end)
      assert output =~ "up to date"
    end

    test "raises naming the stale tier file when a case changes" do
      write_cases([%{"id" => "t/lit", "source" => "42"}])
      capture_io(fn -> Task.run([]) end)

      write_cases([%{"id" => "t/lit", "source" => "43"}])

      {_stdout, stderr} =
        with_io(:stderr, fn ->
          assert_raise Mix.Error, ~r/out of date/, fn ->
            capture_io(fn -> Task.run(["--check"]) end)
          end
        end)

      assert stderr =~ "stale: conformance/corpus/tier-1.json"
    end

    test "raises when the checked-in files are missing entirely" do
      write_cases([%{"id" => "t/lit", "source" => "42"}])

      {_stdout, stderr} =
        with_io(:stderr, fn ->
          assert_raise Mix.Error, ~r/out of date/, fn ->
            capture_io(fn -> Task.run(["--check"]) end)
          end
        end)

      assert stderr =~ "stale: conformance/corpus/tier-1.json"
      assert stderr =~ "stale: conformance/manifest.json"
    end
  end

  describe "run/1 - generator failures" do
    test "raises and reports every failing case's problem, not just the first" do
      write_cases([
        %{"id" => "bad1", "source" => "limit >"},
        %{"id" => "bad2", "source" => "1 / 0", "expected" => %{"result" => 999}}
      ])

      output =
        capture_io(:stderr, fn ->
          assert_raise Mix.Error, ~r/2 error/, fn -> Task.run([]) end
        end)

      assert output =~ "bad1"
      assert output =~ "bad2"
    end

    test "raises when an authored file is not a JSON array" do
      File.write!("conformance/cases/bad.json", JSON.encode!(%{"not" => "a list"}))

      assert_raise Mix.Error, fn ->
        capture_io(:stderr, fn -> capture_io(fn -> Task.run([]) end) end)
      end
    end

    test "raises when an authored file is not valid JSON" do
      File.write!("conformance/cases/bad.json", "{not json")

      assert_raise Mix.Error, fn ->
        capture_io(:stderr, fn -> capture_io(fn -> Task.run([]) end) end)
      end
    end
  end

  describe "build_files/0" do
    test "returns the file map directly, without touching disk" do
      write_cases([%{"id" => "t/lit", "source" => "42"}])

      assert {:ok, files} = Task.build_files()
      assert Map.has_key?(files, "conformance/manifest.json")
      assert Map.has_key?(files, "conformance/corpus/tier-1.json")
      refute File.exists?("conformance/manifest.json")
    end
  end
end
