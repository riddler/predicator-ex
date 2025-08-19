defmodule PredicatorTest do
  use ExUnit.Case, async: true

  doctest Predicator

  describe "evaluate/2 with string expressions" do
    test "evaluates simple comparison" do
      result = Predicator.evaluate("score > 85", %{"score" => 90})
      assert result == true
    end

    test "evaluates with different operators" do
      context = %{"x" => 10}
      
      assert Predicator.evaluate("x > 5", context) == true
      assert Predicator.evaluate("x < 5", context) == false
      assert Predicator.evaluate("x >= 10", context) == true
      assert Predicator.evaluate("x <= 10", context) == true
      assert Predicator.evaluate("x = 10", context) == true
      assert Predicator.evaluate("x != 5", context) == true
    end

    test "evaluates string comparisons" do
      context = %{"name" => "John"}
      
      assert Predicator.evaluate("name = \"John\"", context) == true
      assert Predicator.evaluate("name != \"Jane\"", context) == true
    end

    test "evaluates boolean comparisons" do
      context = %{"active" => true}
      
      assert Predicator.evaluate("active = true", context) == true
      assert Predicator.evaluate("active != false", context) == true
    end

    test "handles parentheses" do
      result = Predicator.evaluate("(score > 85)", %{"score" => 90})
      assert result == true
    end

    test "handles whitespace" do
      result = Predicator.evaluate("  score   >    85  ", %{"score" => 90})
      assert result == true
    end

    test "returns :undefined for missing variables" do
      result = Predicator.evaluate("missing > 5", %{})
      assert result == :undefined
    end

    test "returns error for parse failures" do
      result = Predicator.evaluate("score >", %{})
      assert {:error, message} = result
      assert message =~ "Expected number, string, boolean, identifier, or '(' but found end of input"
      assert message =~ "line 1, column 8"
    end

    test "returns error for invalid syntax" do
      result = Predicator.evaluate("score > >", %{})
      assert {:error, message} = result
      assert message =~ "Expected number, string, boolean, identifier, or '(' but found '>'"
    end
  end

  describe "evaluate/2 with instruction lists" do
    test "evaluates literal instructions" do
      result = Predicator.evaluate([["lit", 42]], %{})
      assert result == 42
    end

    test "evaluates load instructions" do
      result = Predicator.evaluate([["load", "score"]], %{"score" => 85})
      assert result == 85
    end

    test "evaluates comparison instructions" do
      instructions = [["load", "score"], ["lit", 85], ["compare", "GT"]]
      result = Predicator.evaluate(instructions, %{"score" => 90})
      assert result == true
    end

    test "returns error for invalid instructions" do
      result = Predicator.evaluate([["unknown_op"]], %{})
      assert {:error, message} = result
      assert message =~ "Unknown instruction"
    end
  end

  describe "evaluate!/2" do
    test "returns result directly for string expressions" do
      result = Predicator.evaluate!("score > 85", %{"score" => 90})
      assert result == true
    end

    test "returns result directly for instruction lists" do
      result = Predicator.evaluate!([["lit", 42]], %{})
      assert result == 42
    end

    test "raises exception for parse errors" do
      assert_raise RuntimeError, ~r/Evaluation failed:/, fn ->
        Predicator.evaluate!("score >", %{})
      end
    end

    test "raises exception for execution errors" do
      assert_raise RuntimeError, ~r/Evaluation failed:/, fn ->
        Predicator.evaluate!([["unknown_op"]], %{})
      end
    end
  end

  describe "compile/1" do
    test "compiles simple expression" do
      {:ok, instructions} = Predicator.compile("score > 85")
      
      expected = [
        ["load", "score"],
        ["lit", 85],
        ["compare", "GT"]
      ]
      
      assert instructions == expected
    end

    test "compiles different operators" do
      test_cases = [
        {"x > 5", [["load", "x"], ["lit", 5], ["compare", "GT"]]},
        {"x < 5", [["load", "x"], ["lit", 5], ["compare", "LT"]]},
        {"x >= 5", [["load", "x"], ["lit", 5], ["compare", "GTE"]]},
        {"x <= 5", [["load", "x"], ["lit", 5], ["compare", "LTE"]]},
        {"x = 5", [["load", "x"], ["lit", 5], ["compare", "EQ"]]},
        {"x != 5", [["load", "x"], ["lit", 5], ["compare", "NE"]]}
      ]

      for {expression, expected_instructions} <- test_cases do
        {:ok, instructions} = Predicator.compile(expression)
        assert instructions == expected_instructions
      end
    end

    test "compiles string expressions" do
      {:ok, instructions} = Predicator.compile("name = \"John\"")
      
      expected = [
        ["load", "name"],
        ["lit", "John"],
        ["compare", "EQ"]
      ]
      
      assert instructions == expected
    end

    test "compiles boolean expressions" do
      {:ok, instructions} = Predicator.compile("active = true")
      
      expected = [
        ["load", "active"],
        ["lit", true],
        ["compare", "EQ"]
      ]
      
      assert instructions == expected
    end

    test "handles parentheses" do
      {:ok, instructions} = Predicator.compile("(score > 85)")
      
      expected = [
        ["load", "score"],
        ["lit", 85],
        ["compare", "GT"]
      ]
      
      assert instructions == expected
    end

    test "returns error for invalid syntax" do
      result = Predicator.compile("score >")
      assert {:error, message} = result
      assert message =~ "Expected number, string, boolean, identifier, or '(' but found end of input"
      assert message =~ "line 1, column 8"
    end
  end

  describe "compile!/1" do
    test "compiles successfully" do
      instructions = Predicator.compile!("score > 85")
      
      expected = [
        ["load", "score"],
        ["lit", 85],
        ["compare", "GT"]
      ]
      
      assert instructions == expected
    end

    test "raises exception for parse errors" do
      assert_raise RuntimeError, ~r/Compilation failed:/, fn ->
        Predicator.compile!("score >")
      end
    end
  end

  describe "performance scenarios" do
    test "pre-compiled instructions are faster for repeated evaluation" do
      # Compile once
      {:ok, instructions} = Predicator.compile("score > 85")
      
      # Use many times with different contexts
      contexts = [
        %{"score" => 90},
        %{"score" => 80},
        %{"score" => 95},
        %{"score" => 70}
      ]
      
      results = Enum.map(contexts, fn context ->
        Predicator.evaluate(instructions, context)
      end)
      
      assert results == [true, false, true, false]
    end

    test "string expressions work but are slower due to compilation" do
      expression = "score > 85"
      
      contexts = [
        %{"score" => 90},
        %{"score" => 80}
      ]
      
      results = Enum.map(contexts, fn context ->
        Predicator.evaluate(expression, context)
      end)
      
      assert results == [true, false]
    end
  end

  describe "edge cases" do
    test "empty context works with literals" do
      result = Predicator.evaluate("5 > 3", %{})
      assert result == true
    end

    test "nested parentheses work" do
      result = Predicator.evaluate("((score > 85))", %{"score" => 90})
      assert result == true
    end

    test "type mismatches return :undefined" do
      result = Predicator.evaluate("score > \"not_a_number\"", %{"score" => 90})
      assert result == :undefined
    end
  end

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
