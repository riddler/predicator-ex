defmodule PredicatorTest do
  use ExUnit.Case, async: true

  doctest Predicator

  describe "execute/2 API" do
    test "executes simple literal instruction" do
      assert Predicator.execute([["lit", 42]]) == 42
    end

    test "executes load instruction with context" do
      context = %{"score" => 85}
      assert Predicator.execute([["load", "score"]], context) == 85
    end

    test "handles missing context variables" do
      assert Predicator.execute([["load", "missing"]], %{}) == :undefined
    end
  end

  describe "evaluator/2 and run_evaluator/1" do
    test "creates and runs evaluator" do
      evaluator = Predicator.evaluator([["lit", 42]])
      {:ok, final_state} = Predicator.run_evaluator(evaluator)

      assert final_state.stack == [42]
      assert final_state.halted == true
    end

    test "evaluator preserves context" do
      context = %{"x" => 10}
      evaluator = Predicator.evaluator([["load", "x"]], context)

      assert evaluator.context == context
    end
  end
end
