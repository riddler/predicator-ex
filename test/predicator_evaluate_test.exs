defmodule PredicatorEvaluateTest do
  use ExUnit.Case, async: true

  alias Predicator.Errors.{EvaluationError, UndefinedVariableError}

  describe "evaluate/3 - :loop_budget (ISA v6, ADR-0013)" do
    # An unconditionally infinite loop - the condition is always true, so it
    # exhausts any finite budget, including the default. No compiler emits
    # jump_backward yet, so this is a hand-built instruction list.
    @infinite_loop [["lit", true], ["pop_jump_if_falsy", 2], ["jump_backward", 2]]

    test "loop_budget: 5 exhausts after five back edges" do
      assert {:error, %EvaluationError{reason: "loop_budget_exceeded"}} =
               Predicator.evaluate(@infinite_loop, %{}, loop_budget: 5)
    end

    test "loop_budget: 0 exhausts on the first back edge" do
      assert {:error, %EvaluationError{reason: "loop_budget_exceeded"}} =
               Predicator.evaluate(@infinite_loop, %{}, loop_budget: 0)
    end

    test "with no option, the default budget is honored" do
      assert {:error, %EvaluationError{reason: "loop_budget_exceeded"}} =
               Predicator.evaluate(@infinite_loop, %{})
    end

    test "loop_budget: -1 raises ArgumentError" do
      assert_raise ArgumentError, fn ->
        Predicator.evaluate(@infinite_loop, %{}, loop_budget: -1)
      end
    end

    test "loop_budget: :lots raises ArgumentError" do
      assert_raise ArgumentError, fn ->
        Predicator.evaluate(@infinite_loop, %{}, loop_budget: :lots)
      end
    end
  end

  describe "evaluate/2 with string expressions" do
    test "evaluates simple comparison" do
      assert Predicator.evaluate("limit > 85", %{"limit" => 90}) == {:ok, true}
    end

    test "evaluates with different operators" do
      context = %{"x" => 10}

      assert Predicator.evaluate("x > 5", context) == {:ok, true}
      assert Predicator.evaluate("x < 5", context) == {:ok, false}
      assert Predicator.evaluate("x >= 10", context) == {:ok, true}
      assert Predicator.evaluate("x <= 10", context) == {:ok, true}
      assert Predicator.evaluate("x == 10", context) == {:ok, true}
      assert Predicator.evaluate("x != 5", context) == {:ok, true}
    end

    test "evaluates string comparisons" do
      context = %{"name" => "John"}

      assert Predicator.evaluate("name == \"John\"", context) == {:ok, true}
      assert Predicator.evaluate("name != \"Jane\"", context) == {:ok, true}
    end

    test "evaluates boolean comparisons" do
      context = %{"active" => true}

      assert Predicator.evaluate("active == true", context) == {:ok, true}
      assert Predicator.evaluate("active != false", context) == {:ok, true}
    end

    test "handles parentheses" do
      assert Predicator.evaluate("(limit > 85)", %{"limit" => 90}) == {:ok, true}
    end

    test "handles whitespace" do
      assert Predicator.evaluate("  limit   >    85  ", %{"limit" => 90}) == {:ok, true}
    end

    test "returns an UndefinedVariableError for an unbound root variable inside a larger expression" do
      # Regression pin (px-8um.4): the old [["load", _]] single-instruction
      # heuristic only caught a bare `missing` load and silently returned
      # {:ok, :undefined} for anything longer, like this comparison.
      # px-1e1: positioned at the variable's own load.
      assert Predicator.evaluate("missing > 5", %{}) ==
               {:error,
                Predicator.Errors.put_position(UndefinedVariableError.new("missing"), {1, 1})}
    end

    test "returns error for parse failures" do
      result = Predicator.evaluate("limit >", %{})

      assert {:error,
              %Predicator.Errors.ParseError{message: message, position: {1, 8}, span: span}} =
               result

      refute is_nil(span)

      assert message =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found end of input"
    end

    test "returns error for invalid syntax" do
      result = Predicator.evaluate("limit > >", %{})
      assert {:error, %Predicator.Errors.ParseError{message: message}} = result

      assert message =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found '>'"
    end
  end

  describe "evaluate/2 with instruction lists" do
    test "evaluates literal instructions" do
      assert Predicator.evaluate([["lit", 42]], %{}) == {:ok, 42}
    end

    test "evaluates load instructions" do
      assert Predicator.evaluate([["load", "limit"]], %{"limit" => 85}) == {:ok, 85}
    end

    test "evaluates comparison instructions" do
      instructions = [["load", "limit"], ["lit", 85], ["compare", "GT"]]
      assert Predicator.evaluate(instructions, %{"limit" => 90}) == {:ok, true}
    end

    test "returns error for invalid instructions" do
      result = Predicator.evaluate([["unknown_op"]], %{})
      assert {:error, %Predicator.Errors.EvaluationError{message: message}} = result
      assert message =~ "Unknown instruction"
    end
  end

  describe "evaluate!/2" do
    test "returns result directly for string expressions" do
      result = Predicator.evaluate!("limit > 85", %{"limit" => 90})
      assert result == true
    end

    test "returns result directly for instruction lists" do
      result = Predicator.evaluate!([["lit", 42]], %{})
      assert result == 42
    end

    test "raises exception for parse errors" do
      assert_raise RuntimeError, ~r/Evaluation failed:/, fn ->
        Predicator.evaluate!("limit >", %{})
      end
    end

    test "raises exception for execution errors" do
      assert_raise RuntimeError, ~r/Evaluation failed:/, fn ->
        Predicator.evaluate!([["unknown_op"]], %{})
      end
    end
  end

  describe "runtime error spans" do
    test "a string expression with spans: true populates :span and :position" do
      assert {:error, error} = Predicator.evaluate("a * true", %{"a" => 1}, spans: true)
      assert error.span == {{1, 1}, {1, 9}}
      assert error.position == {1, 1}
    end

    test "without the option :span stays nil and :position names the operator" do
      assert {:error, error} = Predicator.evaluate("a * true", %{"a" => 1})
      assert error.span == nil
      assert error.position == {1, 3}
    end

    test "the rendered message is identical with and without spans" do
      assert {:error, spanned} = Predicator.evaluate("a * true", %{"a" => 1}, spans: true)
      assert {:error, plain} = Predicator.evaluate("a * true", %{"a" => 1})

      assert spanned.message == plain.message
    end

    test "spans: true is a no-op for instruction-list input" do
      instructions = [["lit", 1], ["lit", true], ["multiply"]]

      assert Predicator.evaluate(instructions, %{}, spans: true) ==
               Predicator.evaluate(instructions, %{})
    end

    test "a caller-supplied span table decorates a pre-compiled program" do
      {:ok, compiled} = Predicator.compile_with_spans("a * true")

      assert {:error, error} =
               Predicator.evaluate(compiled.instructions, %{"a" => 1},
                 positions: compiled.positions
               )

      assert error.span == {{1, 1}, {1, 9}}
      assert error.position == {1, 1}
    end
  end

  describe "runtime error positions" do
    test "a string expression populates :position" do
      assert {:error, error} = Predicator.evaluate("a * true", %{"a" => 1})
      assert error.position == {1, 3}
    end

    test "an instruction list without a table leaves :position nil" do
      assert {:error, error} =
               Predicator.evaluate([["lit", 1], ["lit", true], ["multiply"]], %{})

      assert error.position == nil
    end

    test "an instruction list with a caller-supplied table populates :position" do
      {:ok, compiled} = Predicator.compile_with_positions("a * true")

      assert {:error, error} =
               Predicator.evaluate(compiled.instructions, %{"a" => 1},
                 positions: compiled.positions
               )

      assert error.position == {1, 3}
    end

    test "a %Context{} evaluation populates :position too" do
      context = Predicator.Context.new(%{"a" => 1})

      assert {:error, error} = Predicator.evaluate("a * true", context)
      assert error.position == {1, 3}
    end
  end

  describe "evaluate/3 with a %Predicator.Compiled{}" do
    test "threads a position table without any keyword" do
      {:ok, compiled} = Predicator.compile_with_positions("a * true")

      assert {:error, error} = Predicator.evaluate(compiled, %{"a" => 1})
      assert error.position == {1, 3}
    end

    test "threads a span table, setting both :span and :position" do
      {:ok, compiled} = Predicator.compile_with_spans("a * true")

      assert {:error, error} = Predicator.evaluate(compiled, %{"a" => 1})
      assert error.span == {{1, 1}, {1, 9}}
      assert error.position == {1, 1}
    end

    test "works with a %Predicator.Context{} as the second argument" do
      {:ok, compiled} = Predicator.compile_with_positions("a * true")
      context = Predicator.Context.new(%{"a" => 1})

      assert {:error, error} = Predicator.evaluate(compiled, context)
      assert error.position == {1, 3}
    end

    test "raises ArgumentError when also given an explicit :positions option" do
      {:ok, compiled} = Predicator.compile_with_positions("a * true")

      assert_raise ArgumentError, ~r/already carries/, fn ->
        Predicator.evaluate(compiled, %{"a" => 1}, positions: compiled.positions)
      end
    end

    test "an unbound variable's own position is reported through the envelope" do
      {:ok, compiled} = Predicator.compile_with_positions("missing OR true")

      assert {:error, error} =
               Predicator.evaluate(compiled, %{}, on_unbound: :error)

      assert error.variable == "missing"
      assert error.position == {1, 1}
    end

    test "evaluate!/3 accepts a %Predicator.Compiled{}" do
      {:ok, compiled} = Predicator.compile_with_positions("limit > 85")

      assert Predicator.evaluate!(compiled, %{"limit" => 90}) == true
    end
  end

  describe "evaluate/3 with a bare instruction list and :positions" do
    test "still works alongside the option" do
      {:ok, compiled} = Predicator.compile_with_positions("a * true")

      assert {:error, error} =
               Predicator.evaluate(compiled.instructions, %{"a" => 1},
                 positions: compiled.positions
               )

      assert error.position == {1, 3}
    end
  end

  describe "performance scenarios" do
    test "pre-compiled instructions are faster for repeated evaluation" do
      # Compile once
      {:ok, instructions} = Predicator.compile("limit > 85")

      # Use many times with different contexts
      contexts = [
        %{"limit" => 90},
        %{"limit" => 80},
        %{"limit" => 95},
        %{"limit" => 70}
      ]

      results =
        Enum.map(contexts, fn context ->
          Predicator.evaluate(instructions, context)
        end)

      assert results == [{:ok, true}, {:ok, false}, {:ok, true}, {:ok, false}]
    end

    test "string expressions work but are slower due to compilation" do
      expression = "limit > 85"

      contexts = [
        %{"limit" => 90},
        %{"limit" => 80}
      ]

      results =
        Enum.map(contexts, fn context ->
          Predicator.evaluate(expression, context)
        end)

      assert results == [{:ok, true}, {:ok, false}]
    end
  end

  describe "decompile/2" do
    test "converts AST back to string" do
      ast = {:comparison, :gt, {:identifier, "limit", nil}, {:literal, 85, nil}, nil}
      result = Predicator.decompile(ast)

      assert result == "limit > 85"
    end

    test "converts literal AST" do
      ast = {:literal, 42, nil}
      result = Predicator.decompile(ast)

      assert result == "42"
    end

    test "converts identifier AST" do
      ast = {:identifier, "name", nil}
      result = Predicator.decompile(ast)

      assert result == "name"
    end

    test "works with formatting options" do
      ast = {:comparison, :eq, {:identifier, "active", nil}, {:literal, true, nil}, nil}

      # Test spacing options
      assert Predicator.decompile(ast, spacing: :normal) == "active == true"
      assert Predicator.decompile(ast, spacing: :compact) == "active==true"
      assert Predicator.decompile(ast, spacing: :verbose) == "active  ==  true"

      # Test parentheses options
      assert Predicator.decompile(ast, parentheses: :minimal) == "active == true"
      assert Predicator.decompile(ast, parentheses: :explicit) == "(active == true)"
      assert Predicator.decompile(ast, parentheses: :none) == "active == true"
    end

    test "handles string literals correctly" do
      ast = {:comparison, :ne, {:identifier, "name", nil}, {:literal, "test", nil}, nil}
      result = Predicator.decompile(ast)

      assert result == ~s(name != "test")
    end

    test "round-trip with compile" do
      # Test compile -> decompile round trip
      original = "limit >= 75"
      {:ok, _instructions} = Predicator.compile(original)

      # We can't directly get AST from instructions, but we can test with parser
      alias Predicator.Lexer
      {:ok, tokens} = Lexer.tokenize(original)
      {:ok, ast} = Predicator.Parser.parse(tokens)

      decompiled = Predicator.decompile(ast)
      assert decompiled == original
    end
  end

  describe "edge cases" do
    test "empty context works with literals" do
      assert Predicator.evaluate("5 > 3", %{}) == {:ok, true}
    end

    test "nested parentheses work" do
      assert Predicator.evaluate("((limit > 85))", %{"limit" => 90}) == {:ok, true}
    end

    test "type mismatches return :undefined" do
      assert Predicator.evaluate("limit > \"not_a_number\"", %{"limit" => 90}) ==
               {:ok, :undefined}
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
