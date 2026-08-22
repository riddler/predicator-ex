defmodule Mix.Tasks.Gate.Verify do
  @shortdoc "Run the full quality gate and attest that the run was not narrowed"

  @moduledoc """
  Runs `mix quality` and attests that what it ran was the full gate.

  A green run is not by itself evidence of a green gate: `--profile loop`,
  `--test-scope changed`, `--quick` and `--skip` all produce one, and each of
  them checks less. ADR-0008 makes the full gate the pre-commit bar, and
  CLAUDE.md's rule that a scoped green never substitutes for it is how a run
  gets reported; this task is how that claim gets checked rather than
  remembered.

  ## Usage

      mix gate.verify

  The run passes only when the report says `status: "ok"`, `scope: "all"`, no
  profile, and no stage skipped for a reason that names this run rather than the
  project. Exit status is 0 when it attests and 1 when it does not.

  A stage skipped for a project-level reason (`:sobelow not installed`,
  `disabled in .quality.exs`, a custom stage's own skip) is named in the output
  but does not fail the attestation: that is a gap in what the project checks at
  all, which a fuller run cannot close.
  """

  use Mix.Task

  # ExQuality's own distinction: these reasons name the run, everything else
  # names the project (`deps/ex_quality/usage-rules.md:102-105`).
  @narrowing ["--quick", "--until-first-failure", "not in profile", "--skip"]

  @impl Mix.Task
  def run(argv) do
    case execute(argv) do
      {:ok, output} -> Mix.shell().info(output)
      {:error, reason} -> Mix.raise(reason)
    end
  end

  @doc """
  Runs the gate and reports the attestation instead of halting.

  `opts[:runner]` replaces the `mix quality` shell-out with a function of an
  argument list returning `{output, status}`, so tests drive this without a
  nested gate run.
  """
  @spec execute(argv :: [String.t()], opts :: keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def execute(argv, opts \\ []) do
    {_parsed, _rest} = OptionParser.parse!(argv, strict: [])
    runner = Keyword.get(opts, :runner, &mix_quality/1)

    with {:ok, report} <- gate(runner), do: attest(report)
  end

  # A red gate still writes a report, so the exit status is only worth reporting
  # when there is no report to read.
  defp gate(runner) do
    {output, status} = runner.(["quality", "--report", "-"])

    case JSON.decode(output) do
      {:ok, report} when is_map(report) ->
        {:ok, report}

      _other ->
        {:error, "no report to verify: `mix quality --report -` exited #{status} without one"}
    end
  end

  defp attest(report) do
    stages = Map.get(report, "stages", [])

    case problems(report, stages) do
      [] -> {:ok, attestation(report, stages)}
      problems -> {:error, "Not a full gate: #{Enum.join(problems, " and ")}."}
    end
  end

  defp problems(report, stages) do
    Enum.reject(
      [status_problem(report, stages), profile_problem(report), scope_problem(report)] ++
        narrowed(stages),
      &is_nil/1
    )
  end

  defp status_problem(%{"status" => "ok"}, _stages), do: nil

  defp status_problem(_report, stages) do
    case Enum.filter(stages, &(&1["status"] == "error")) do
      [] -> "the run did not report status ok"
      failed -> "the gate is red (#{names(failed)})"
    end
  end

  defp profile_problem(%{"profile" => profile}) when is_binary(profile),
    do: "run used profile :#{profile}"

  defp profile_problem(_report), do: nil

  defp scope_problem(%{"scope" => "all"}), do: nil
  defp scope_problem(%{"scope" => scope}), do: "scope was #{scope} rather than all"
  defp scope_problem(_report), do: "the run reported no scope"

  defp narrowed(stages) do
    for stage <- skipped(stages), narrowing?(stage["summary"]) do
      "#{stage["name"]} was skipped (#{stage["summary"]})"
    end
  end

  defp skipped(stages), do: Enum.filter(stages, &(&1["status"] == "skipped"))

  defp narrowing?(summary) when is_binary(summary),
    do: Enum.any?(@narrowing, &String.contains?(summary, &1))

  defp narrowing?(_summary), do: false

  defp attestation(report, stages) do
    line =
      "Full gate green: scope #{report["scope"]}, no profile, " <>
        "#{length(stages)} stages considered."

    case Enum.reject(skipped(stages), &narrowing?(&1["summary"])) do
      [] -> line
      gaps -> "#{line}\n#{gap_note(gaps)}"
    end
  end

  # Named rather than counted: a project-level skip is a standing gap in what the
  # gate covers, and the reader is the one who decides whether it matters.
  defp gap_note(gaps) do
    "Not checked by this project at all: " <>
      Enum.map_join(gaps, ", ", &"#{&1["name"]} (#{&1["summary"]})")
  end

  defp names(stages), do: Enum.map_join(stages, ", ", & &1["name"])

  defp mix_quality(args) do
    System.cmd("mix", args)
  end
end
