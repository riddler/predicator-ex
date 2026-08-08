defmodule Predicator.Conformance.GeneratorTest do
  use ExUnit.Case, async: true

  doctest Predicator.Conformance.Generator

  alias Predicator.Conformance.Generator

  describe "generate/1 - the seed corpus" do
    test "conformance/cases/core.json generates cleanly end to end" do
      cases = "conformance/cases/core.json" |> File.read!() |> JSON.decode!()

      assert {:ok, %{tiers: tiers, manifest: manifest}} = Generator.generate(cases)

      assert length(tiers[1]) == length(cases)
      assert Enum.all?(tiers[1], &(&1["tier"] == 1))
      assert manifest["isa_version"] == Predicator.isa_version()

      tier_1_entry = Enum.find(manifest["tiers"], &(&1["tier"] == 1))
      assert tier_1_entry["name"] == "core"
      assert tier_1_entry["case_count"] == length(cases)
      assert "lit" in tier_1_entry["opcodes"]
    end
  end

  describe "generate/1 - a single well-formed case" do
    test "a literal source case computes instructions, expected_result, tier, and features" do
      cases = [%{"id" => "t/literal", "source" => "42"}]

      assert {:ok, %{tiers: %{1 => [completed]}}} = Generator.generate(cases)

      assert completed == %{
               "id" => "t/literal",
               "source" => "42",
               "instructions" => [["lit", 42]],
               "context" => %{},
               "expected_result" => 42,
               "tier" => 1,
               "features" => []
             }
    end

    test "an evaluator-only case (instructions, no source) is absent \"source\": nil" do
      cases = [
        %{"id" => "t/hand-built", "instructions" => [["lit", 1], ["lit", 2], ["compare", "LT"]]}
      ]

      assert {:ok, %{tiers: %{1 => [completed]}}} = Generator.generate(cases)
      assert completed["source"] == nil
      assert completed["expected_result"] == true
    end

    test "context is decoded through the tagged codec and used for evaluation" do
      cases = [
        %{"id" => "t/ctx", "source" => "score > 85", "context" => %{"score" => 90}}
      ]

      assert {:ok, %{tiers: %{1 => [completed]}}} = Generator.generate(cases)
      assert completed["expected_result"] == true
      assert completed["context"] == %{"score" => 90}
    end

    test "notes are carried into the completed case; absent notes add no key" do
      with_notes = [%{"id" => "t/n1", "source" => "42", "notes" => "a note"}]
      without_notes = [%{"id" => "t/n2", "source" => "42"}]

      assert {:ok, %{tiers: %{1 => [c1]}}} = Generator.generate(with_notes)
      assert {:ok, %{tiers: %{1 => [c2]}}} = Generator.generate(without_notes)

      assert c1["notes"] == "a note"
      refute Map.has_key?(c2, "notes")
    end

    test "an error outcome records expected_error, not expected_result" do
      cases = [%{"id" => "t/err", "source" => "1 / 0"}]

      assert {:ok, %{tiers: %{2 => [completed]}}} = Generator.generate(cases)

      assert completed["expected_error"] == %{
               "type" => "EvaluationError",
               "reason" => "division_by_zero"
             }

      refute Map.has_key?(completed, "expected_result")
    end
  end

  describe "generate/1 - failure mode: missing id" do
    test "a case with no id fails naming the problem, with id: nil" do
      cases = [%{"source" => "42"}]

      assert {:error, [%{id: nil, problem: problem}]} = Generator.generate(cases)
      assert problem =~ ~s("id")
    end
  end

  describe "generate/1 - failure mode: duplicate id" do
    test "two cases sharing an id both fail, naming the id" do
      cases = [
        %{"id" => "dup", "source" => "1"},
        %{"id" => "dup", "source" => "2"}
      ]

      assert {:error, errors} = Generator.generate(cases)
      assert length(errors) == 2
      assert Enum.all?(errors, &(&1.id == "dup"))
      assert Enum.all?(errors, &(&1.problem =~ "duplicate"))
    end
  end

  describe "generate/1 - failure mode: both source and instructions" do
    test "a case authoring both fails naming the conflict" do
      cases = [%{"id" => "t/both", "source" => "42", "instructions" => [["lit", 42]]}]

      assert {:error, [%{id: "t/both", problem: problem}]} = Generator.generate(cases)
      assert problem =~ "both"
    end
  end

  describe "generate/1 - failure mode: neither source nor instructions" do
    test "a case authoring neither fails naming the requirement" do
      cases = [%{"id" => "t/neither"}]

      assert {:error, [%{id: "t/neither", problem: problem}]} = Generator.generate(cases)
      assert problem =~ "neither"
    end
  end

  describe "generate/1 - failure mode: uncompilable source" do
    test "a parse-failing source is a generator error, not a case" do
      cases = [%{"id" => "t/badsource", "source" => "score >"}]

      assert {:error, [%{id: "t/badsource", problem: problem}]} = Generator.generate(cases)
      assert problem =~ "failed to compile"
    end
  end

  describe "generate/1 - failure mode: unknown opcode" do
    test "instructions naming an opcode outside the table fail generation" do
      cases = [%{"id" => "t/unknown", "instructions" => [["nope"]]}]

      assert {:error, [%{id: "t/unknown", problem: problem}]} = Generator.generate(cases)
      assert problem =~ "nope"
    end
  end

  describe "generate/1 - failure mode: expected result mismatch" do
    test "an authored expected result that disagrees fails naming both values" do
      cases = [%{"id" => "t/mismatch", "source" => "42", "expected" => %{"result" => 43}}]

      assert {:error, [%{id: "t/mismatch", problem: problem}]} = Generator.generate(cases)
      assert problem =~ "43"
      assert problem =~ "42"
    end

    test "authoring a result when evaluation actually errors fails naming both" do
      cases = [%{"id" => "t/mismatch2", "source" => "1 / 0", "expected" => %{"result" => 1}}]

      assert {:error, [%{id: "t/mismatch2", problem: problem}]} = Generator.generate(cases)
      assert problem =~ "error"
    end
  end

  describe "generate/1 - failure mode: expected error mismatch" do
    test "an authored expected error whose reason disagrees fails naming both" do
      cases = [
        %{
          "id" => "t/errmismatch",
          "source" => "1 / 0",
          "expected" => %{"error" => %{"type" => "EvaluationError", "reason" => "wrong_reason"}}
        }
      ]

      assert {:error, [%{id: "t/errmismatch", problem: problem}]} = Generator.generate(cases)
      assert problem =~ "wrong_reason"
      assert problem =~ "division_by_zero"
    end

    test "authoring an error when evaluation actually succeeds fails naming both" do
      cases = [
        %{
          "id" => "t/errmismatch2",
          "source" => "42",
          "expected" => %{"error" => %{"type" => "EvaluationError", "reason" => "whatever"}}
        }
      ]

      assert {:error, [%{id: "t/errmismatch2", problem: problem}]} = Generator.generate(cases)
      assert problem =~ "result"
    end
  end

  describe "generate/1 - failure mode: tier mismatch" do
    test "a tier-3 case computes tier 3 regardless of an authored tier, naming the opcode" do
      cases = [
        %{
          "id" => "t/tiermismatch",
          "source" => "[a, b, c]",
          "context" => %{"a" => 1, "b" => 2, "c" => 3},
          "tier" => 1
        }
      ]

      assert {:error, [%{id: "t/tiermismatch", problem: problem}]} = Generator.generate(cases)
      assert problem =~ "1"
      assert problem =~ "3"
      assert problem =~ "make_list"
    end

    test "an authored tier that matches the computed tier passes" do
      cases = [
        %{
          "id" => "t/tierok",
          "source" => "[a, b, c]",
          "context" => %{"a" => 1, "b" => 2, "c" => 3},
          "tier" => 3
        }
      ]

      assert {:ok, %{tiers: %{3 => [completed]}}} = Generator.generate(cases)
      assert completed["tier"] == 3
    end
  end

  describe "generate/1 - failure mode: $type collision" do
    test "a computed result that is a plain map with a literal \"$type\" key fails generation" do
      cases = [%{"id" => "t/collision", "source" => ~s({"$type": 1})}]

      assert {:error, [%{id: "t/collision", problem: problem}]} = Generator.generate(cases)
      assert problem =~ "$type"
    end
  end

  describe "generate/1 - errors accumulate" do
    test "three independently-broken cases report three errors, not one" do
      cases = [
        %{"id" => "t/bad1", "source" => "score >"},
        %{"id" => "t/bad2", "instructions" => [["nope"]]},
        %{"id" => "t/bad3", "source" => "42", "expected" => %{"result" => 1}}
      ]

      assert {:error, errors} = Generator.generate(cases)
      assert length(errors) == 3
      assert Enum.map(errors, & &1.id) |> Enum.sort() == ["t/bad1", "t/bad2", "t/bad3"]
    end
  end

  describe "generate/1 - authored features are merged, not replacement" do
    test "an authored extra tag merges alongside computed tags" do
      cases = [
        %{
          "id" => "t/feat2",
          "source" => "score > 85",
          "context" => %{"score" => 90},
          "features" => ["custom_tag"]
        }
      ]

      assert {:ok, %{tiers: %{1 => [completed]}}} = Generator.generate(cases)
      assert "custom_tag" in completed["features"]
      assert "comparison" in completed["features"]
    end
  end

  describe "generate/1 - failure mode: malformed context" do
    test "a context value with an unrecognized $type tag fails naming the decode error" do
      cases = [%{"id" => "t/ctxbad", "source" => "1", "context" => %{"$type" => "nope"}}]

      assert {:error, [%{id: "t/ctxbad", problem: problem}]} = Generator.generate(cases)
      assert problem =~ "context"
    end

    test "a context field that is not a JSON object fails naming the requirement" do
      cases = [%{"id" => "t/ctxnotmap", "source" => "1", "context" => "oops"}]

      assert {:error, [%{id: "t/ctxnotmap", problem: problem}]} = Generator.generate(cases)
      assert problem =~ "\"context\""
    end
  end

  describe "generate/1 - failure mode: malformed expected shape" do
    test "an \"expected\" that is neither {result: _} nor {error: _} fails naming the shape" do
      cases = [%{"id" => "t/expbad", "source" => "1", "expected" => %{"nonsense" => 1}}]

      assert {:error, [%{id: "t/expbad", problem: problem}]} = Generator.generate(cases)
      assert problem =~ "\"expected\""
    end
  end

  describe "generate/1 - failure mode: malformed tier" do
    test "a \"tier\" that is not an integer fails naming the requirement" do
      cases = [%{"id" => "t/tierbad", "source" => "1", "tier" => "one"}]

      assert {:error, [%{id: "t/tierbad", problem: problem}]} = Generator.generate(cases)
      assert problem =~ "\"tier\""
    end
  end

  describe "generate/1 - error outcomes encode type and reason, never message" do
    test "an undefined root variable produces UndefinedVariableError / unbound_variable" do
      cases = [%{"id" => "t/undef", "source" => "missing"}]

      assert {:ok, %{tiers: %{1 => [completed]}}} = Generator.generate(cases)

      assert completed["expected_error"] == %{
               "type" => "UndefinedVariableError",
               "reason" => "unbound_variable"
             }
    end

    test "a type mismatch produces TypeMismatchError / the failing operation" do
      cases = [%{"id" => "t/typemismatch", "source" => "5 * true"}]

      assert {:ok, %{tiers: %{2 => [completed]}}} = Generator.generate(cases)

      assert completed["expected_error"] == %{
               "type" => "TypeMismatchError",
               "reason" => "multiply"
             }
    end
  end

  describe "generate/1 - evaluation that raises is a generator error, not a crash" do
    test "unary_minus on an atom (not producible by any opcode) is caught and reported" do
      cases = [
        %{"id" => "t/crash", "instructions" => [["lit", :foo], ["unary_minus"]]}
      ]

      assert {:error, [%{id: "t/crash", problem: problem}]} = Generator.generate(cases)
      assert problem =~ "raised"
    end
  end

  # `and` is picked here only as a stand-in opcode to inject via
  # `:retired_opcodes`, exercising the classification path itself
  # independent of which opcode is actually retired. `and` (with `or`) is
  # now genuinely retired at ISA v3 (px-tbv.9); these tests still pass an
  # explicit set rather than relying on the default, so they keep testing
  # the mechanism rather than duplicating the default-set test above.
  describe "generate/2 - the retired-opcode path" do
    test "a frozen result case takes the authored expected verbatim, tier and legacy_logical intact" do
      cases = [
        %{
          "id" => "t/retired-result",
          "instructions" => [["lit", true], ["lit", true], ["and"]],
          "expected" => %{"result" => true}
        }
      ]

      assert {:ok, %{tiers: %{1 => [completed]}}} =
               Generator.generate(cases, retired_opcodes: MapSet.new(["and"]))

      assert completed["expected_result"] == true
      assert completed["tier"] == 1
      assert "retired" in completed["features"]
      assert "legacy_logical" in completed["features"]
      assert completed["source"] == nil
    end

    test "a frozen error case takes the authored expected_error verbatim, with the errors tag" do
      cases = [
        %{
          "id" => "t/retired-error",
          "instructions" => [["lit", 1], ["lit", 0], ["and"]],
          "expected" => %{"error" => %{"type" => "EvaluationError", "reason" => "made_up"}}
        }
      ]

      assert {:ok, %{tiers: %{1 => [completed]}}} =
               Generator.generate(cases, retired_opcodes: MapSet.new(["and"]))

      assert completed["expected_error"] == %{"type" => "EvaluationError", "reason" => "made_up"}
      refute Map.has_key?(completed, "expected_result")
      assert "retired" in completed["features"]
      assert "errors" in completed["features"]
    end

    test "a retired case with no expected fails, naming the opcode" do
      cases = [%{"id" => "t/retired-noexpected", "instructions" => [["lit", true], ["and"]]}]

      assert {:error, [%{id: "t/retired-noexpected", problem: problem}]} =
               Generator.generate(cases, retired_opcodes: MapSet.new(["and"]))

      assert problem =~ "and"
      assert problem =~ "expected"
    end

    test "a retired case authoring source fails, naming the opcode" do
      # "and"/"or" are never source-emitted (the compiler always emits
      # jump_if_falsy_or_pop/jump_if_true_or_pop for source-level and/or), so
      # this test picks "compare" as the stand-in retired opcode instead -
      # any opcode the source compiles to works, and this rule is about
      # authoring "source" at all for a retired-opcode case, not specific to
      # "and"/"or".
      cases = [
        %{"id" => "t/retired-source", "source" => "1 = 1", "expected" => %{"result" => true}}
      ]

      assert {:error, [%{id: "t/retired-source", problem: problem}]} =
               Generator.generate(cases, retired_opcodes: MapSet.new(["compare"]))

      assert problem =~ "compare"
      assert problem =~ "source"
    end

    test "a case using no retired opcode is unaffected when the option is passed" do
      cases = [%{"id" => "t/not-retired", "source" => "42"}]

      assert {:ok, %{tiers: %{1 => [completed]}}} =
               Generator.generate(cases, retired_opcodes: MapSet.new(["and"]))

      assert completed["expected_result"] == 42
      refute "retired" in completed["features"]
    end

    test "the default :retired_opcodes is exactly and/or, so generate/1 agrees with generate/2 given that explicit set" do
      cases = "conformance/cases/legacy.json" |> File.read!() |> JSON.decode!()

      assert Generator.generate(cases) ==
               Generator.generate(cases, retired_opcodes: MapSet.new(["and", "or"]))
    end
  end
end
