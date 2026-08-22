defmodule Mix.Tasks.Gate.VerifyTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Gate.Verify

  # The task's only side effect is the `mix quality` shell-out, so every test
  # feeds it a synthetic report through a stub runner.
  defp runner(report, status \\ 0) do
    fn ["quality", "--report", "-"] -> {JSON.encode!(report), status} end
  end

  defp report(overrides \\ %{}) do
    Map.merge(
      %{
        "status" => "ok",
        "profile" => nil,
        "scope" => "all",
        "stages" => [stage("Format"), stage("Credo"), stage("Tests")]
      },
      overrides
    )
  end

  defp stage(name, overrides \\ %{}) do
    Map.merge(%{"name" => name, "status" => "ok", "summary" => "", "findings" => []}, overrides)
  end

  defp skipped(name, summary), do: stage(name, %{"status" => "skipped", "summary" => summary})

  # sabotage: drop the stage count from attestation/2's line -> red
  test "a full green run attests, naming its scope and stage count" do
    assert {:ok, output} = Verify.execute([], runner: runner(report()))
    assert output == "Full gate green: scope all, no profile, 3 stages considered."
  end

  # sabotage: drop the profile_problem/1 clause matching a binary profile -> red
  test "a profiled run is not a full gate" do
    assert {:error, reason} = Verify.execute([], runner: runner(report(%{"profile" => "loop"})))
    assert reason == "Not a full gate: run used profile :loop."
  end

  # sabotage: have scope_problem/1 accept any scope -> red
  test "a scoped run is not a full gate" do
    assert {:error, reason} = Verify.execute([], runner: runner(report(%{"scope" => "changed"})))
    assert reason == "Not a full gate: scope was changed rather than all."
  end

  # sabotage: have status_problem/2 return nil for a non-ok status -> red
  test "a red gate names the stages that failed" do
    stages = [stage("Format"), stage("Credo", %{"status" => "error"})]

    assert {:error, reason} =
             Verify.execute([],
               runner: runner(report(%{"status" => "error", "stages" => stages}))
             )

    assert reason == "Not a full gate: the gate is red (Credo)."
  end

  # sabotage: have narrowing?/1 return false for every summary -> red
  test "a stage skipped for a reason naming this run is not a full gate" do
    stages = [stage("Format"), skipped("Dialyzer", "--quick")]

    assert {:error, reason} = Verify.execute([], runner: runner(report(%{"stages" => stages})))
    assert reason == "Not a full gate: Dialyzer was skipped (--quick)."
  end

  # sabotage: have narrowing?/1 return true for every summary -> red
  test "a stage skipped for a project-level reason attests and is named" do
    stages = [stage("Format"), skipped("Sobelow", ":sobelow not installed")]

    assert {:ok, output} = Verify.execute([], runner: runner(report(%{"stages" => stages})))

    assert output ==
             "Full gate green: scope all, no profile, 2 stages considered.\n" <>
               "Not checked by this project at all: Sobelow (:sobelow not installed)"
  end

  # sabotage: report only the first problem instead of joining them all -> red
  test "several narrowings are all reported" do
    stages = [skipped("Dialyzer", "not in profile :loop")]
    overrides = %{"profile" => "loop", "scope" => "changed", "stages" => stages}

    assert {:error, reason} = Verify.execute([], runner: runner(report(overrides)))

    assert reason ==
             "Not a full gate: run used profile :loop and scope was changed rather than all " <>
               "and Dialyzer was skipped (not in profile :loop)."
  end

  # sabotage: decode the report with a fallback to %{} instead of erroring -> red
  test "output that is not a report fails rather than attesting" do
    assert {:error, reason} =
             Verify.execute([], runner: fn _args -> {"** (Mix) no such task\n", 1} end)

    assert reason == "no report to verify: `mix quality --report -` exited 1 without one"
  end

  # sabotage: have status_problem/2's fallback clause return nil -> red
  test "a report with no status and no failed stages is not a full gate" do
    stages = [stage("Format")]
    report = Map.delete(report(%{"stages" => stages}), "status")

    assert {:error, reason} = Verify.execute([], runner: runner(report))
    assert reason == "Not a full gate: the run did not report status ok."
  end

  # sabotage: have scope_problem/1's fallback clause return nil -> red
  test "a report with no scope at all is not a full gate" do
    report = Map.delete(report(), "scope")

    assert {:error, reason} = Verify.execute([], runner: runner(report))
    assert reason == "Not a full gate: the run reported no scope."
  end

  # sabotage: have narrowing?/1's fallback clause return true -> red
  test "a skipped stage with no summary is not treated as narrowing" do
    stages = [stage("Format"), skipped("Sobelow", "") |> Map.delete("summary")]

    assert {:ok, output} = Verify.execute([], runner: runner(report(%{"stages" => stages})))

    assert output ==
             "Full gate green: scope all, no profile, 2 stages considered.\n" <>
               "Not checked by this project at all: Sobelow ()"
  end

  # run/1 has no `opts` parameter to inject a stub `runner` through, and its
  # real default (`mix_quality/1`) shells out to a full `mix quality --report
  # -` - a nested run of the whole gate, including its own Tests stage, which
  # would itself run this very file again. Driving run/1's real defaults down
  # either of its two dispatch clauses is therefore not a cheap or safe
  # in-process test. This test
  # exercises run/1's other real-default line instead - the
  # `case execute(argv) do` dispatch itself - through an OptionParser
  # failure, which raises before the case can match either arm.
  # sabotage: change execute/2's `OptionParser.parse!/2` call to
  #           `OptionParser.parse/2` (which does not raise on an unknown
  #           switch) -> red (a MatchError from the 2-tuple/3-tuple mismatch
  #           replaces the expected OptionParser.ParseError)
  test "run/1 propagates an OptionParser error for an unrecognized switch" do
    assert_raise OptionParser.ParseError, fn -> Verify.run(["--not-a-real-switch"]) end
  end
end
