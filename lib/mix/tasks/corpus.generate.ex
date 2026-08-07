defmodule Mix.Tasks.Corpus.Generate do
  @shortdoc "Regenerates the shipped conformance corpus from conformance/cases/*.json"

  @moduledoc """
  Regenerates `conformance/corpus/tier-*.json` and `conformance/manifest.json`
  from the authored cases in `conformance/cases/*.json` (`px-35i.4`).

  Each authored case is run through the real compiler and evaluator by
  `Predicator.Conformance.Generator.generate/1`, which fills in
  `instructions`, `expected_result`/`expected_error`, `tier`, and `features`.
  This task is the thin I/O shell around that pure function: it reads the
  authored files, writes the completed corpus (one case per line, sorted by
  id, via `Predicator.Conformance.JSON.encode_lines/1`) and the manifest, and
  is otherwise deliberately free of logic - anything that needs a test belongs
  in `Predicator.Conformance.*`, not here.

  ## Usage

      mix corpus.generate          # regenerate and write conformance/corpus/ and manifest.json
      mix corpus.generate --check  # regenerate in memory, diff against the checked-in files,
                                    # write nothing, exit non-zero on drift (for CI)

  A case that fails to generate - a compile error, an authored `expected` or
  `tier` mismatch, an unknown opcode, and so on - prints every failing case's
  id and problem (not just the first) and exits non-zero without writing
  anything.
  """

  use Mix.Task

  alias Predicator.Conformance.Generator
  alias Predicator.Conformance.JSON, as: CanonicalJSON

  @cases_glob "conformance/cases/*.json"
  @corpus_dir "conformance/corpus"
  @manifest_path "conformance/manifest.json"

  @typedoc "Relative path (from the project root) mapped to the exact bytes it should contain."
  @type file_map :: %{String.t() => binary()}

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    check? = "--check" in args

    case build_files() do
      {:ok, files} -> if check?, do: check(files), else: write(files)
      {:error, errors} -> report_errors(errors)
    end
  end

  @doc """
  Reads `conformance/cases/*.json`, runs `Predicator.Conformance.Generator.generate/1`,
  and returns the exact file map `mix corpus.generate` would write: relative
  path (from the project root) mapped to the exact bytes that file should
  contain.

  Public so `test/predicator/conformance/corpus_freshness_test.exs` can
  regenerate in memory and byte-compare against the checked-in files without
  duplicating the assembly logic (tier file naming, canonical encoding, the
  `corpus_hash` computation) - a second hand-maintained copy of that logic is
  exactly the kind of drift this whole bead exists to prevent.
  """
  @spec build_files() :: {:ok, file_map()} | {:error, [Generator.case_error()]}
  def build_files do
    with {:ok, authored} <- read_authored_cases(),
         {:ok, %{tiers: tiers, manifest: manifest}} <- Generator.generate(authored) do
      {:ok, assemble_files(tiers, manifest)}
    end
  end

  @spec read_authored_cases() ::
          {:ok, [Generator.authored_case()]} | {:error, [Generator.case_error()]}
  defp read_authored_cases do
    @cases_glob
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, acc} ->
      case decode_case_file(path) do
        {:ok, cases} -> {:cont, {:ok, acc ++ cases}}
        {:error, _problem} = error -> {:halt, error}
      end
    end)
  end

  @spec decode_case_file(String.t()) ::
          {:ok, [Generator.authored_case()]} | {:error, [Generator.case_error()]}
  defp decode_case_file(path) do
    with {:ok, content} <- File.read(path),
         {:ok, decoded} when is_list(decoded) <- JSON.decode(content) do
      {:ok, decoded}
    else
      {:ok, decoded} ->
        {:error,
         [%{id: nil, problem: "#{path}: expected a JSON array of cases, got #{inspect(decoded)}"}]}

      {:error, reason} ->
        {:error, [%{id: nil, problem: "#{path}: #{inspect(reason)}"}]}
    end
  end

  # Builds the exact file map `mix corpus.generate` writes (or `--check`
  # compares against): one `conformance/corpus/tier-N.json` per tier the
  # generator produced, plus `conformance/manifest.json` with `corpus_hash`
  # (a sha256 over the tier files' content, in tier order) and each tier
  # entry's `file` path filled in.
  @spec assemble_files(%{pos_integer() => [Generator.completed_case()]}, map()) :: file_map()
  defp assemble_files(tiers, manifest) do
    tier_entries =
      tiers
      |> Enum.sort_by(fn {tier, _cases} -> tier end)
      |> Enum.map(fn {tier, cases} ->
        {tier, tier_path(tier), CanonicalJSON.encode_lines(cases)}
      end)

    corpus_hash = hash_corpus(tier_entries)

    manifest_content =
      manifest
      |> Map.update!(
        "tiers",
        &Enum.map(&1, fn entry -> Map.put(entry, "file", relative_tier_path(entry["tier"])) end)
      )
      |> Map.put("corpus_hash", corpus_hash)
      |> CanonicalJSON.encode_canonical()
      |> Kernel.<>("\n")

    tier_entries
    |> Map.new(fn {_tier, path, content} -> {path, content} end)
    |> Map.put(@manifest_path, manifest_content)
  end

  @spec tier_path(pos_integer()) :: String.t()
  defp tier_path(tier), do: Path.join(@corpus_dir, "tier-#{tier}.json")

  @spec relative_tier_path(pos_integer()) :: String.t()
  defp relative_tier_path(tier), do: "corpus/tier-#{tier}.json"

  @spec hash_corpus([{pos_integer(), String.t(), binary()}]) :: String.t()
  defp hash_corpus(tier_entries) do
    content = Enum.map_join(tier_entries, "", fn {_tier, _path, content} -> content end)
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, content), case: :lower)
  end

  @spec write(file_map()) :: :ok
  defp write(files) do
    File.mkdir_p!(@corpus_dir)
    Enum.each(files, fn {path, content} -> File.write!(path, content) end)
    Mix.shell().info("Wrote #{map_size(files)} file(s) to conformance/.")
  end

  @spec check(file_map()) :: :ok
  defp check(files) do
    stale = files |> Enum.map(&drift/1) |> Enum.reject(&is_nil/1) |> Enum.sort()

    case stale do
      [] ->
        Mix.shell().info("conformance/ is up to date.")

      paths ->
        Enum.each(paths, &Mix.shell().error("stale: #{&1}"))

        Mix.raise(
          "conformance/ is out of date with conformance/cases/ (#{length(paths)} file(s)). " <>
            "Run `mix corpus.generate` and review the diff."
        )
    end
  end

  @spec drift({String.t(), binary()}) :: String.t() | nil
  defp drift({path, expected}) do
    case File.read(path) do
      {:ok, ^expected} -> nil
      _mismatch_or_missing -> path
    end
  end

  @spec report_errors([Generator.case_error()]) :: no_return()
  defp report_errors(errors) do
    Enum.each(errors, fn %{id: id, problem: problem} ->
      Mix.shell().error("#{id || "(case id unknown)"}: #{problem}")
    end)

    Mix.raise("corpus generation failed with #{length(errors)} error(s); wrote nothing.")
  end
end
