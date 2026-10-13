defmodule Predicator.Conformance.AnalysisGeneratorTest do
  use ExUnit.Case, async: true

  doctest Predicator.Conformance.AnalysisGenerator

  alias Predicator.Conformance.AnalysisGenerator

  @dynamic %{"$type" => "dynamic"}

  describe "generate/1 - the authored analysis cases" do
    test "conformance/analysis/cases.json generates cleanly, one case per authored case" do
      authored = "conformance/analysis/cases.json" |> File.read!() |> JSON.decode!()

      assert {:ok, completed} = AnalysisGenerator.generate(authored)
      assert length(completed) == length(authored)
      assert Enum.map(completed, & &1["id"]) == Enum.sort(Enum.map(authored, & &1["id"]))
    end

    # The bead's acceptance names what the authored cases must exercise; each
    # clause below is one of those, read off the generated cases rather than
    # off the case ids.
    test "the authored cases exercise every shape the surface promises" do
      authored = "conformance/analysis/cases.json" |> File.read!() |> JSON.decode!()
      {:ok, completed} = AnalysisGenerator.generate(authored)

      from_source = Enum.filter(completed, &is_binary(&1["source"]))
      from_instructions = Enum.filter(completed, &is_nil(&1["source"]))

      assert Enum.any?(from_source, &(&1["references"] != []))
      assert Enum.any?(from_source, &(&1["calls"] != []))
      assert Enum.any?(from_instructions, &(&1["references"] != []))
      assert Enum.any?(from_instructions, &(&1["calls"] != []))

      paths =
        Enum.flat_map(completed, fn c ->
          Enum.map(c["references"] ++ c["assignments"], & &1["path"])
        end)

      assert Enum.any?(paths, &(@dynamic in &1))
      assert Enum.any?(paths, fn path -> Enum.any?(path, &is_integer/1) end)

      # A call nested in an argument: on one line, an outer call that takes
      # arguments listed before a call that starts after it.
      assert Enum.any?(from_source, fn c ->
               match?(
                 [
                   %{"arity" => arity, "position" => [line, outer]},
                   %{"position" => [line, inner]} | _rest
                 ]
                 when arity > 0 and inner > outer,
                 c["calls"]
               )
             end)

      assert Enum.any?(from_source, &(&1["assignments"] != []))
    end
  end

  describe "generate/1 - one case" do
    test "a source case ships the program's instructions and the source form's answers" do
      assert {:ok, [completed]} =
               AnalysisGenerator.generate([
                 %{"id" => "analysis/t", "source" => "x = f(a[0])", "notes" => "kept"}
               ])

      assert completed == %{
               "id" => "analysis/t",
               "source" => "x = f(a[0])",
               "instructions" => [
                 ["lit", "x"],
                 ["load", "a"],
                 ["lit", 0],
                 ["bracket_access"],
                 ["call", "f", 1],
                 ["store", 1]
               ],
               "references" => [%{"path" => ["a", 0], "position" => [1, 7]}],
               "calls" => [%{"name" => "f", "arity" => 1, "position" => [1, 5]}],
               "assignments" => [%{"path" => ["x"], "position" => [1, 1]}],
               "notes" => "kept"
             }
    end

    test "an instruction case carries a null source and null positions" do
      assert {:ok, [completed]} =
               AnalysisGenerator.generate([
                 %{
                   "id" => "analysis/t",
                   "instructions" => [["load", "a"], ["load", "k"], ["bracket_access"]]
                 }
               ])

      assert completed["source"] == nil

      assert completed["references"] == [
               %{"path" => ["a", @dynamic], "position" => nil},
               %{"path" => ["k"], "position" => nil}
             ]
    end

    test "tagged values in an authored instruction list decode before the analysis reads them" do
      assert {:ok, [completed]} =
               AnalysisGenerator.generate([
                 %{
                   "id" => "analysis/t",
                   "instructions" => [
                     ["load", "due"],
                     ["lit", %{"$type" => "date", "value" => "2026-08-06"}],
                     ["compare", "LT"]
                   ]
                 }
               ])

      assert completed["instructions"] == [
               ["load", "due"],
               ["lit", %{"$type" => "date", "value" => "2026-08-06"}],
               ["compare", "LT"]
             ]

      assert completed["references"] == [%{"path" => ["due"], "position" => nil}]
    end
  end

  describe "generate/1 - refusals" do
    test "every failing case is reported, not just the first" do
      assert {:error, errors} =
               AnalysisGenerator.generate([
                 %{"id" => "analysis/ok", "source" => "a"},
                 %{"id" => "analysis/bad-1", "source" => "a >"},
                 %{"id" => "analysis/bad-2", "instructions" => [["no_such_opcode"]]}
               ])

      assert Enum.map(errors, & &1.id) == ["analysis/bad-1", "analysis/bad-2"]
      assert Enum.at(errors, 1).problem =~ "has no analysis"
    end

    test "an id outside analysis/ is refused" do
      assert {:error, [%{id: "core/x", problem: problem}]} =
               AnalysisGenerator.generate([%{"id" => "core/x", "source" => "a"}])

      assert problem =~ ~s(starting "analysis/")
    end

    test "a missing id is refused" do
      assert {:error, [%{id: nil}]} = AnalysisGenerator.generate([%{"source" => "a"}])
    end

    test "a duplicate id is refused on every copy" do
      assert {:error, errors} =
               AnalysisGenerator.generate([
                 %{"id" => "analysis/same", "source" => "a"},
                 %{"id" => "analysis/same", "source" => "b"}
               ])

      assert length(errors) == 2
      assert Enum.all?(errors, &(&1.problem =~ "duplicate case id"))
    end

    test "a case with both source and instructions, or neither, is refused" do
      assert {:error, [%{problem: both}, %{problem: neither}]} =
               AnalysisGenerator.generate([
                 %{"id" => "analysis/both", "source" => "a", "instructions" => [["load", "a"]]},
                 %{"id" => "analysis/neither"}
               ])

      assert both =~ "exactly one"
      assert neither =~ "exactly one"
    end

    test "an instruction list that does not decode is refused" do
      assert {:error, [%{problem: problem}]} =
               AnalysisGenerator.generate([
                 %{"id" => "analysis/t", "instructions" => [["lit", %{"$type" => "nope"}]]}
               ])

      assert problem =~ "failed to decode"
    end
  end
end
