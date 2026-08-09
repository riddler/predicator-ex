defmodule Predicator.Evaluator.LastValueTest do
  @moduledoc """
  Direct `Evaluator` coverage for `last_value/1` and the retention `["pop"]`
  performs into `%Evaluator{}.last_value` (px-tbv.10).

  These build `%Evaluator{}` structs and drive them through the public
  `Evaluator.run_state/1`, rather than going through `Predicator.evaluate/3` or
  `Predicator.execute/2`, so the phase is testable before any façade exists and
  does not depend on the compiler emitting `pop` at statement boundaries.
  """

  use ExUnit.Case, async: true

  alias Predicator.Evaluator

  describe "a fresh evaluator" do
    test "reports :undefined before any run" do
      assert Evaluator.last_value(%Evaluator{}) == :undefined
    end
  end

  describe "pop records the value it discarded" do
    test "an integer" do
      instructions = [["lit", 1], ["pop"]]

      assert {:ok, final} = Evaluator.run_state(%Evaluator{instructions: instructions})
      assert Evaluator.last_value(final) == 1
    end

    test "a string" do
      instructions = [["lit", "hello"], ["pop"]]

      assert {:ok, final} = Evaluator.run_state(%Evaluator{instructions: instructions})
      assert Evaluator.last_value(final) == "hello"
    end

    test "a boolean" do
      instructions = [["lit", true], ["pop"]]

      assert {:ok, final} = Evaluator.run_state(%Evaluator{instructions: instructions})
      assert Evaluator.last_value(final) == true
    end

    test "a list" do
      instructions = [["lit", [1, 2, 3]], ["pop"]]

      assert {:ok, final} = Evaluator.run_state(%Evaluator{instructions: instructions})
      assert Evaluator.last_value(final) == [1, 2, 3]
    end

    test "a map" do
      instructions = [["lit", %{"a" => 1}], ["pop"]]

      assert {:ok, final} = Evaluator.run_state(%Evaluator{instructions: instructions})
      assert Evaluator.last_value(final) == %{"a" => 1}
    end

    test ":undefined itself" do
      instructions = [["lit", :undefined], ["pop"]]

      assert {:ok, final} = Evaluator.run_state(%Evaluator{instructions: instructions})
      assert Evaluator.last_value(final) == :undefined
    end
  end

  describe "consecutive pops" do
    test "leave the last one's value" do
      instructions = [["lit", 1], ["pop"], ["lit", 2], ["pop"]]

      assert {:ok, final} = Evaluator.run_state(%Evaluator{instructions: instructions})
      assert Evaluator.last_value(final) == 2
    end
  end

  describe "no pop leaves :undefined" do
    test "an empty instruction list" do
      assert {:ok, final} = Evaluator.run_state(%Evaluator{instructions: []})
      assert Evaluator.last_value(final) == :undefined
    end

    test "a run that halts with a non-empty stack residue" do
      instructions = [["lit", 1]]

      assert {:ok, final} = Evaluator.run_state(%Evaluator{instructions: instructions})
      assert final.stack == [1]
      assert Evaluator.last_value(final) == :undefined
    end
  end

  describe "pop on an empty stack" do
    test "errors and leaves the prior last_value unchanged" do
      instructions = [["lit", 9], ["pop"], ["pop"]]

      assert {:error, _error_struct, final} =
               Evaluator.run_state(%Evaluator{instructions: instructions})

      assert Evaluator.last_value(final) == 9
    end
  end

  describe "the conditional pops do not record" do
    test "jump_if_falsy_or_pop leaves :undefined" do
      instructions = [["lit", false], ["jump_if_falsy_or_pop", 2], ["lit", true]]

      assert {:ok, final} = Evaluator.run_state(%Evaluator{instructions: instructions})
      assert Evaluator.last_value(final) == :undefined
    end

    test "jump_if_true_or_pop leaves :undefined" do
      instructions = [["lit", true], ["jump_if_true_or_pop", 2], ["lit", false]]

      assert {:ok, final} = Evaluator.run_state(%Evaluator{instructions: instructions})
      assert Evaluator.last_value(final) == :undefined
    end
  end

  describe "store does not write it" do
    test "a store instruction leaves :undefined" do
      instructions = [["lit", "x"], ["lit", 42], ["store", 1]]

      assert {:ok, final} =
               Evaluator.run_state(%Evaluator{instructions: instructions, context: %{}})

      assert Evaluator.last_value(final) == :undefined
    end
  end
end
