defmodule Predicator.Conformance.AnalysisGenerator do
  @moduledoc """
  The pure half of the corpus's analysis surface.

  `generate/1` takes decoded authored analysis cases - the maps in
  `conformance/analysis/cases.json` - and completes each one from
  `Predicator.Analysis`: the instructions a `source` compiles to (through
  `Predicator.compile_program/1`), and the `references`, `calls` and
  `assignments` the analysis lists for it. `mix corpus.generate` is the I/O
  shell that writes the result to `conformance/analysis/corpus.json`.

  The expected values are always computed, never authored: a case names a
  program, and the reference implementation says what it reads, calls and
  stores. A case authored as `source` is analysed in both forms - the source
  string and its compiled instructions - and generation fails, naming the
  case, when the two forms disagree on anything but positions, since the
  instruction form carries none. That keeps one expected set per case honest
  for both forms a runner may read.

  Only cases the analysis answers `{:ok, list}` for are shipped: a source that
  does not parse, or an instruction the analysis cannot read, fails
  generation rather than becoming a case.

  The JSON spelling of an answer (`conformance/README.md`, "The analysis
  surface"): a segment is a string, an integer, or `{"$type": "dynamic"}`; a
  position is `[line, column]` or `null`.

  ## Examples

      iex> Predicator.Conformance.AnalysisGenerator.generate([
      ...>   %{"id" => "analysis/example", "source" => "items[k] > 1"}
      ...> ])
      {:ok,
       [
         %{
           "id" => "analysis/example",
           "source" => "items[k] > 1",
           "instructions" => [
             ["load", "items"],
             ["load", "k"],
             ["bracket_access"],
             ["lit", 1],
             ["compare", "GT"],
             ["pop"]
           ],
           "references" => [
             %{"path" => ["items", %{"$type" => "dynamic"}], "position" => [1, 1]},
             %{"path" => ["k"], "position" => [1, 7]}
           ],
           "calls" => [],
           "assignments" => []
         }
       ]}
  """

  alias Predicator.Analysis
  alias Predicator.Conformance.Values

  @typedoc "An authored analysis case, already JSON-decoded."
  @type authored_case :: %{optional(String.t()) => term()}

  @typedoc "A completed analysis case, as one line of `conformance/analysis/corpus.json`."
  @type completed_case :: %{optional(String.t()) => term()}

  @typedoc "One per-case generation failure, in `Predicator.Conformance.Generator`'s shape."
  @type case_error :: %{id: String.t() | nil, problem: String.t()}

  @answers [:references, :calls, :assignments]

  @doc """
  Completes every authored analysis case, sorted by id.

  Returns `{:ok, cases}` when every case generates cleanly, or
  `{:error, errors}` naming every failing case, not just the first.

  ## Examples

      iex> Predicator.Conformance.AnalysisGenerator.generate([%{"id" => "analysis/bad", "source" => "limit >"}])
      {:error, [%{id: "analysis/bad", problem: "source \\"limit >\\" has no analysis: Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input"}]}
  """
  @spec generate([authored_case()]) :: {:ok, [completed_case()]} | {:error, [case_error()]}
  def generate(cases) when is_list(cases) do
    duplicates = duplicate_ids(cases)

    {oks, errors} =
      cases
      |> Enum.map(&generate_case(&1, duplicates))
      |> Enum.split_with(&match?({:ok, _completed}, &1))

    case errors do
      [] -> {:ok, oks |> Enum.map(&elem(&1, 1)) |> Enum.sort_by(& &1["id"])}
      _some -> {:error, Enum.map(errors, &elem(&1, 1))}
    end
  end

  @spec generate_case(authored_case(), MapSet.t(term())) ::
          {:ok, completed_case()} | {:error, case_error()}
  defp generate_case(raw, duplicates) do
    with {:ok, id} <- fetch_id(raw, duplicates),
         {:ok, endpoint} <- fetch_endpoint(raw),
         {:ok, instructions} <- resolve_instructions(endpoint),
         {:ok, found} <- analyse(endpoint, instructions),
         {:ok, encoded_instructions} <- encode_instructions(instructions),
         {:ok, answers} <- encode_answers(found) do
      {:ok, assemble(id, raw, endpoint, encoded_instructions, answers)}
    else
      {:error, problem} -> {:error, %{id: Map.get(raw, "id"), problem: problem}}
    end
  end

  @spec duplicate_ids([authored_case()]) :: MapSet.t(term())
  defp duplicate_ids(cases) do
    cases
    |> Enum.map(&Map.get(&1, "id"))
    |> Enum.frequencies()
    |> Enum.filter(fn {_id, count} -> count > 1 end)
    |> MapSet.new(fn {id, _count} -> id end)
  end

  @spec fetch_id(authored_case(), MapSet.t(term())) :: {:ok, String.t()} | {:error, String.t()}
  defp fetch_id(raw, duplicates) do
    case Map.get(raw, "id") do
      "analysis/" <> rest = id when rest != "" ->
        if MapSet.member?(duplicates, id),
          do: {:error, "duplicate case id #{inspect(id)} - case ids must be unique"},
          else: {:ok, id}

      other ->
        {:error, ~s(case needs a string "id" starting "analysis/", got #{inspect(other)})}
    end
  end

  @spec fetch_endpoint(authored_case()) ::
          {:ok, {:source, String.t()} | {:instructions, list()}} | {:error, String.t()}
  defp fetch_endpoint(raw) do
    case {Map.get(raw, "source"), Map.get(raw, "instructions")} do
      {source, nil} when is_binary(source) -> {:ok, {:source, source}}
      {nil, instructions} when is_list(instructions) -> {:ok, {:instructions, instructions}}
      _both_or_neither -> {:error, ~s(case needs exactly one of "source" or "instructions")}
    end
  end

  @spec resolve_instructions({:source, String.t()} | {:instructions, list()}) ::
          {:ok, list()} | {:error, String.t()}
  defp resolve_instructions({:source, source}) do
    case Predicator.compile_program(source) do
      {:ok, instructions} -> {:ok, instructions}
      {:error, error} -> {:error, "source #{inspect(source)} has no analysis: #{error.message}"}
    end
  end

  defp resolve_instructions({:instructions, json}) do
    case Values.from_json(json) do
      {:ok, instructions} -> {:ok, instructions}
      {:error, reason} -> {:error, "instructions failed to decode: #{inspect(reason)}"}
    end
  end

  # A source case is analysed as a source string and as its instructions; the
  # two must agree once positions are set aside, and the source form's answer
  # (the one with positions) is the one shipped.
  @spec analyse({:source, String.t()} | {:instructions, list()}, list()) ::
          {:ok, %{atom() => [map()]}} | {:error, String.t()}
  defp analyse({:source, source}, instructions) do
    with {:ok, from_source} <- run_analysis(source),
         {:ok, from_instructions} <- run_analysis(instructions) do
      if without_positions(from_source) == from_instructions do
        {:ok, from_source}
      else
        {:error,
         "the source and instruction forms disagree: #{inspect(from_source)} from the source, " <>
           "#{inspect(from_instructions)} from the instructions"}
      end
    end
  end

  defp analyse({:instructions, _json}, instructions), do: run_analysis(instructions)

  @spec run_analysis(Analysis.input()) :: {:ok, %{atom() => [map()]}} | {:error, String.t()}
  defp run_analysis(input) do
    Enum.reduce_while(@answers, {:ok, %{}}, fn answer, {:ok, acc} ->
      case apply(Analysis, answer, [input]) do
        {:ok, items} ->
          {:cont, {:ok, Map.put(acc, answer, items)}}

        {:error, error} ->
          {:halt, {:error, "#{inspect(input)} has no analysis: #{error.message}"}}
      end
    end)
  end

  @spec without_positions(%{atom() => [map()]}) :: %{atom() => [map()]}
  defp without_positions(found) do
    Map.new(found, fn {answer, items} ->
      {answer, Enum.map(items, &%{&1 | position: nil})}
    end)
  end

  @spec encode_instructions(list()) :: {:ok, [Values.json()]} | {:error, String.t()}
  defp encode_instructions(instructions) do
    case Values.to_json(instructions) do
      {:ok, encoded} -> {:ok, encoded}
      {:error, reason} -> {:error, "instructions could not be encoded: #{inspect(reason)}"}
    end
  end

  @spec encode_answers(%{atom() => [map()]}) ::
          {:ok, %{String.t() => [map()]}} | {:error, String.t()}
  defp encode_answers(found) do
    Enum.reduce_while(@answers, {:ok, %{}}, fn answer, {:ok, acc} ->
      case encode_items(found[answer]) do
        {:ok, items} -> {:cont, {:ok, Map.put(acc, Atom.to_string(answer), items)}}
        {:error, _problem} = error -> {:halt, error}
      end
    end)
  end

  @spec encode_items([map()]) :: {:ok, [map()]} | {:error, String.t()}
  defp encode_items(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case encode_item(item) do
        {:ok, encoded} -> {:cont, {:ok, [encoded | acc]}}
        {:error, _problem} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, encoded} -> {:ok, Enum.reverse(encoded)}
      error -> error
    end
  end

  @spec encode_item(map()) :: {:ok, map()} | {:error, String.t()}
  defp encode_item(%{position: position} = item) do
    with {:ok, encoded_position} <- encode_position(position) do
      fields = item |> Map.delete(:position) |> Map.new(&encode_field/1)
      {:ok, Map.put(fields, "position", encoded_position)}
    end
  end

  @spec encode_field({atom(), term()}) :: {String.t(), term()}
  defp encode_field({:path, path}), do: {"path", Enum.map(path, &encode_segment/1)}
  defp encode_field({key, value}), do: {Atom.to_string(key), value}

  @spec encode_segment(Analysis.segment()) :: String.t() | integer() | map()
  defp encode_segment(:dynamic), do: %{"$type" => "dynamic"}
  defp encode_segment(segment), do: segment

  # A source string is parsed without spans, so every position here is a
  # point or nil; a span would mean the analysis read the source some other
  # way, which this surface does not describe.
  @spec encode_position(Analysis.position()) ::
          {:ok, [pos_integer()] | nil} | {:error, String.t()}
  defp encode_position(nil), do: {:ok, nil}

  defp encode_position({line, column}) when is_integer(line) and is_integer(column),
    do: {:ok, [line, column]}

  defp encode_position(other), do: {:error, "unexpected position #{inspect(other)}"}

  @spec assemble(String.t(), authored_case(), tuple(), [Values.json()], map()) ::
          completed_case()
  defp assemble(id, raw, endpoint, instructions, answers) do
    source =
      case endpoint do
        {:source, source} -> source
        {:instructions, _json} -> nil
      end

    completed =
      Map.merge(%{"id" => id, "source" => source, "instructions" => instructions}, answers)

    case Map.get(raw, "notes") do
      nil -> completed
      notes -> Map.put(completed, "notes", notes)
    end
  end
end
