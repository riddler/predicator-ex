defmodule PredicatorTest do
  use ExUnit.Case, async: true

  doctest Predicator

  describe "evaluate/2 with string expressions" do
    test "evaluates simple comparison" do
      assert Predicator.evaluate("score > 85", %{"score" => 90}) == {:ok, true}
    end

    test "evaluates with different operators" do
      context = %{"x" => 10}

      assert Predicator.evaluate("x > 5", context) == {:ok, true}
      assert Predicator.evaluate("x < 5", context) == {:ok, false}
      assert Predicator.evaluate("x >= 10", context) == {:ok, true}
      assert Predicator.evaluate("x <= 10", context) == {:ok, true}
      assert Predicator.evaluate("x = 10", context) == {:ok, true}
      assert Predicator.evaluate("x != 5", context) == {:ok, true}
    end

    test "evaluates string comparisons" do
      context = %{"name" => "John"}

      assert Predicator.evaluate("name = \"John\"", context) == {:ok, true}
      assert Predicator.evaluate("name != \"Jane\"", context) == {:ok, true}
    end

    test "evaluates boolean comparisons" do
      context = %{"active" => true}

      assert Predicator.evaluate("active = true", context) == {:ok, true}
      assert Predicator.evaluate("active != false", context) == {:ok, true}
    end

    test "handles parentheses" do
      assert Predicator.evaluate("(score > 85)", %{"score" => 90}) == {:ok, true}
    end

    test "handles whitespace" do
      assert Predicator.evaluate("  score   >    85  ", %{"score" => 90}) == {:ok, true}
    end

    test "returns :undefined for missing variables" do
      assert Predicator.evaluate("missing > 5", %{}) == {:ok, :undefined}
    end

    test "returns error for parse failures" do
      result = Predicator.evaluate("score >", %{})

      assert {:error, %Predicator.Errors.ParseError{message: message, line: 1, column: 8}} =
               result

      assert message =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found end of input"
    end

    test "returns error for invalid syntax" do
      result = Predicator.evaluate("score > >", %{})
      assert {:error, %Predicator.Errors.ParseError{message: message}} = result

      assert message =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found '>'"
    end
  end

  describe "evaluate/2 with instruction lists" do
    test "evaluates literal instructions" do
      assert Predicator.evaluate([["lit", 42]], %{}) == {:ok, 42}
    end

    test "evaluates load instructions" do
      assert Predicator.evaluate([["load", "score"]], %{"score" => 85}) == {:ok, 85}
    end

    test "evaluates comparison instructions" do
      instructions = [["load", "score"], ["lit", 85], ["compare", "GT"]]
      assert Predicator.evaluate(instructions, %{"score" => 90}) == {:ok, true}
    end

    test "returns error for invalid instructions" do
      result = Predicator.evaluate([["unknown_op"]], %{})
      assert {:error, %Predicator.Errors.EvaluationError{message: message}} = result
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

      assert message =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, or '(' but found end of input"

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

      results =
        Enum.map(contexts, fn context ->
          Predicator.evaluate(instructions, context)
        end)

      assert results == [{:ok, true}, {:ok, false}, {:ok, true}, {:ok, false}]
    end

    test "string expressions work but are slower due to compilation" do
      expression = "score > 85"

      contexts = [
        %{"score" => 90},
        %{"score" => 80}
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
      ast = {:comparison, :gt, {:identifier, "score"}, {:literal, 85}}
      result = Predicator.decompile(ast)

      assert result == "score > 85"
    end

    test "converts literal AST" do
      ast = {:literal, 42}
      result = Predicator.decompile(ast)

      assert result == "42"
    end

    test "converts identifier AST" do
      ast = {:identifier, "name"}
      result = Predicator.decompile(ast)

      assert result == "name"
    end

    test "works with formatting options" do
      ast = {:comparison, :eq, {:identifier, "active"}, {:literal, true}}

      # Test spacing options
      assert Predicator.decompile(ast, spacing: :normal) == "active = true"
      assert Predicator.decompile(ast, spacing: :compact) == "active=true"
      assert Predicator.decompile(ast, spacing: :verbose) == "active  =  true"

      # Test parentheses options
      assert Predicator.decompile(ast, parentheses: :minimal) == "active = true"
      assert Predicator.decompile(ast, parentheses: :explicit) == "(active = true)"
      assert Predicator.decompile(ast, parentheses: :none) == "active = true"
    end

    test "handles string literals correctly" do
      ast = {:comparison, :ne, {:identifier, "name"}, {:literal, "test"}}
      result = Predicator.decompile(ast)

      assert result == ~s(name != "test")
    end

    test "round-trip with compile" do
      # Test compile -> decompile round trip
      original = "score >= 75"
      {:ok, _instructions} = Predicator.compile(original)

      # We can't directly get AST from instructions, but we can test with parser
      alias Predicator.{Lexer, Parser}
      {:ok, tokens} = Lexer.tokenize(original)
      {:ok, ast} = Parser.parse(tokens)

      decompiled = Predicator.decompile(ast)
      assert decompiled == original
    end
  end

  describe "edge cases" do
    test "empty context works with literals" do
      assert Predicator.evaluate("5 > 3", %{}) == {:ok, true}
    end

    test "nested parentheses work" do
      assert Predicator.evaluate("((score > 85))", %{"score" => 90}) == {:ok, true}
    end

    test "type mismatches return :undefined" do
      assert Predicator.evaluate("score > \"not_a_number\"", %{"score" => 90}) ==
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

  describe "logical operators - integration tests" do
    test "evaluates logical AND with true results" do
      assert Predicator.evaluate("score > 85 AND age >= 18", %{"score" => 90, "age" => 25}) ==
               {:ok, true}
    end

    test "evaluates logical AND with false results" do
      assert Predicator.evaluate("score > 85 AND age >= 18", %{"score" => 80, "age" => 25}) ==
               {:ok, false}

      assert Predicator.evaluate("score > 85 AND age >= 18", %{"score" => 90, "age" => 16}) ==
               {:ok, false}

      assert Predicator.evaluate("score > 85 AND age >= 18", %{"score" => 80, "age" => 16}) ==
               {:ok, false}
    end

    test "evaluates logical OR with true results" do
      assert Predicator.evaluate(~s(role = "admin" OR role = "manager"), %{"role" => "admin"}) ==
               {:ok, true}

      assert Predicator.evaluate(~s(role = "admin" OR role = "manager"), %{"role" => "manager"}) ==
               {:ok, true}
    end

    test "evaluates logical OR with false results" do
      assert Predicator.evaluate(~s(role = "admin" OR role = "manager"), %{"role" => "user"}) ==
               {:ok, false}
    end

    test "evaluates logical NOT with boolean variables" do
      assert Predicator.evaluate("NOT expired = true", %{"expired" => false}) == {:ok, true}

      assert Predicator.evaluate("NOT expired = true", %{"expired" => true}) == {:ok, false}
    end

    test "evaluates complex logical expressions" do
      # (score > 85 AND age >= 18) OR admin = true
      context1 = %{"score" => 90, "age" => 20, "admin" => false}

      assert Predicator.evaluate("score > 85 AND age >= 18 OR admin = true", context1) ==
               {:ok, true}

      context2 = %{"score" => 80, "age" => 16, "admin" => false}

      assert Predicator.evaluate("score > 85 AND age >= 18 OR admin = true", context2) ==
               {:ok, false}

      context3 = %{"score" => 80, "age" => 16, "admin" => true}

      assert Predicator.evaluate("score > 85 AND age >= 18 OR admin = true", context3) ==
               {:ok, true}
    end

    test "evaluates nested NOT expressions" do
      assert Predicator.evaluate("NOT NOT active = true", %{"active" => true}) == {:ok, true}

      assert Predicator.evaluate("NOT NOT active = true", %{"active" => false}) == {:ok, false}
    end

    test "evaluates operator precedence correctly" do
      # NOT false OR false AND true should be: (NOT false) OR (false AND true) = true OR false = true
      result =
        Predicator.evaluate(
          "NOT expired = false OR role = \"user\" AND score > 85",
          %{"expired" => true, "role" => "user", "score" => 90}
        )

      assert result == {:ok, true}

      # Same expression with different values - should be: false OR true = true
      result =
        Predicator.evaluate(
          "NOT expired = false OR role = \"user\" AND score > 85",
          %{"expired" => false, "role" => "user", "score" => 90}
        )

      assert result == {:ok, true}

      # Same expression with different values - should be: false OR false = false
      result =
        Predicator.evaluate(
          "NOT expired = false OR role = \"user\" AND score > 85",
          %{"expired" => false, "role" => "user", "score" => 80}
        )

      assert result == {:ok, false}
    end

    test "evaluates parenthesized logical expressions" do
      # (active = true OR role = \"admin\") AND score > 85
      context1 = %{"active" => true, "role" => "user", "score" => 90}

      result1 =
        Predicator.evaluate("(active = true OR role = \"admin\") AND score > 85", context1)

      assert result1 == {:ok, true}

      context2 = %{"active" => false, "role" => "admin", "score" => 90}

      result2 =
        Predicator.evaluate("(active = true OR role = \"admin\") AND score > 85", context2)

      assert result2 == {:ok, true}

      context3 = %{"active" => false, "role" => "user", "score" => 90}

      result3 =
        Predicator.evaluate("(active = true OR role = \"admin\") AND score > 85", context3)

      assert result3 == {:ok, false}

      context4 = %{"active" => true, "role" => "admin", "score" => 80}

      result4 =
        Predicator.evaluate("(active = true OR role = \"admin\") AND score > 85", context4)

      assert result4 == {:ok, false}
    end

    test "compiles and decompiles logical expressions correctly" do
      original_expressions = [
        "score > 85 AND age >= 18",
        "role = \"admin\" OR role = \"manager\"",
        "NOT expired = true",
        "score > 85 AND age >= 18 OR admin = true",
        "NOT false OR true AND false"
      ]

      for expression <- original_expressions do
        {:ok, ast} = Predicator.parse(expression)
        decompiled = Predicator.decompile(ast)
        assert decompiled == expression

        # Also test compilation to instructions
        {:ok, instructions} = Predicator.compile(expression)
        assert is_list(instructions)
        assert length(instructions) > 0
      end
    end

    test "parse function returns correct AST for logical operators" do
      {:ok, ast} = Predicator.parse("score > 85 AND age >= 18")
      assert match?({:logical_and, _, _}, ast)

      {:ok, ast} = Predicator.parse(~s(role = "admin" OR role = "manager"))
      assert match?({:logical_or, _, _}, ast)

      {:ok, ast} = Predicator.parse("NOT expired = true")
      assert match?({:logical_not, _}, ast)
    end

    test "compile function generates correct instructions for logical operators" do
      {:ok, instructions} = Predicator.compile("true AND false")
      assert instructions == [["lit", true], ["lit", false], ["and"]]

      {:ok, instructions} = Predicator.compile("true OR false")
      assert instructions == [["lit", true], ["lit", false], ["or"]]

      {:ok, instructions} = Predicator.compile("NOT true")
      assert instructions == [["lit", true], ["not"]]
    end

    test "evaluate! function works with logical operators" do
      result = Predicator.evaluate!("score > 85 AND age >= 18", %{"score" => 90, "age" => 25})
      assert result == true

      result = Predicator.evaluate!("NOT expired = true", %{"expired" => false})
      assert result == true
    end

    test "handles error cases in logical expressions" do
      # Syntax errors
      result = Predicator.evaluate("score AND", %{"score" => 90})
      assert {:error, _message} = result

      result = Predicator.evaluate("OR score > 85", %{"score" => 90})
      assert {:error, _message} = result

      result = Predicator.evaluate("NOT", %{})
      assert {:error, _message} = result
    end

    test "works with atom keys in context" do
      assert Predicator.evaluate("score > 85 AND age >= 18", %{score: 90, age: 25}) == {:ok, true}

      assert Predicator.evaluate("NOT expired = true", %{expired: false}) == {:ok, true}
    end

    test "works with mixed string and atom keys in context" do
      assert Predicator.evaluate("score > 85 AND age >= 18", %{"score" => 90, age: 25}) ==
               {:ok, true}

      result =
        Predicator.evaluate("role = \"admin\" OR active = true", %{
          "active" => false,
          role: "admin"
        })

      assert result == {:ok, true}
    end
  end

  describe "plain boolean expressions" do
    test "evaluates boolean literals without operators" do
      assert Predicator.evaluate("true", %{}) == {:ok, true}
      assert Predicator.evaluate("false", %{}) == {:ok, false}
    end

    test "evaluates boolean identifiers from context" do
      assert Predicator.evaluate("active", %{"active" => true}) == {:ok, true}
      assert Predicator.evaluate("active", %{"active" => false}) == {:ok, false}
      assert Predicator.evaluate("expired", %{"expired" => true}) == {:ok, true}
      assert Predicator.evaluate("expired", %{"expired" => false}) == {:ok, false}
    end

    test "evaluates boolean identifiers with atom keys" do
      assert Predicator.evaluate("active", %{active: true}) == {:ok, true}
      assert Predicator.evaluate("expired", %{expired: false}) == {:ok, false}
    end

    test "returns error for missing boolean variables" do
      assert {:error, %Predicator.Errors.UndefinedVariableError{variable: "missing"}} =
               Predicator.evaluate("missing", %{})
    end

    test "works with logical operators on plain boolean expressions" do
      context = %{"active" => true, "expired" => false, "verified" => true}

      assert Predicator.evaluate("active AND verified", context) == {:ok, true}
      assert Predicator.evaluate("active AND expired", context) == {:ok, false}
      assert Predicator.evaluate("active OR expired", context) == {:ok, true}
      assert Predicator.evaluate("expired OR verified", context) == {:ok, true}
      assert Predicator.evaluate("NOT expired", context) == {:ok, true}
      assert Predicator.evaluate("NOT active", context) == {:ok, false}
    end

    test "combines plain boolean expressions with comparisons" do
      context = %{"active" => true, "score" => 90, "admin" => false}

      assert Predicator.evaluate("active AND score > 85", context) == {:ok, true}
      assert Predicator.evaluate("active AND score < 85", context) == {:ok, false}
      assert Predicator.evaluate("admin OR score > 85", context) == {:ok, true}
      assert Predicator.evaluate("NOT admin AND score > 85", context) == {:ok, true}
    end

    test "compiles plain boolean expressions correctly" do
      {:ok, instructions} = Predicator.compile("true")
      assert instructions == [["lit", true]]

      {:ok, instructions} = Predicator.compile("active")
      assert instructions == [["load", "active"]]

      {:ok, instructions} = Predicator.compile("active AND expired")
      assert instructions == [["load", "active"], ["load", "expired"], ["and"]]
    end

    test "parses and decompiles plain boolean expressions" do
      {:ok, ast} = Predicator.parse("true")
      assert ast == {:literal, true}
      assert Predicator.decompile(ast) == "true"

      {:ok, ast} = Predicator.parse("active")
      assert ast == {:identifier, "active"}
      assert Predicator.decompile(ast) == "active"

      {:ok, ast} = Predicator.parse("active AND expired")
      assert match?({:logical_and, {:identifier, "active"}, {:identifier, "expired"}}, ast)
      assert Predicator.decompile(ast) == "active AND expired"
    end

    test "evaluate! works with plain boolean expressions" do
      assert Predicator.evaluate!("true", %{}) == true
      assert Predicator.evaluate!("active", %{"active" => true}) == true

      assert Predicator.evaluate!("active AND expired", %{"active" => true, "expired" => false}) ==
               false
    end

    test "handles complex expressions with plain booleans and literals" do
      context = %{"active" => true, "admin" => false, "score" => 95}

      # Mix of plain booleans, comparisons, and literals
      assert Predicator.evaluate("active AND score > 90 OR admin", context) == {:ok, true}

      result = Predicator.evaluate("NOT admin AND (active OR score < 80)", context)
      assert result == {:ok, true}

      assert Predicator.evaluate("false OR active AND true", context) == {:ok, true}
    end
  end

  describe "lowercase logical operators" do
    test "evaluates lowercase 'and' operator" do
      assert Predicator.evaluate("true and false", %{}) == {:ok, false}
      assert Predicator.evaluate("true and true", %{}) == {:ok, true}
      assert Predicator.evaluate("false and false", %{}) == {:ok, false}
    end

    test "evaluates lowercase 'or' operator" do
      assert Predicator.evaluate("true or false", %{}) == {:ok, true}
      assert Predicator.evaluate("false or false", %{}) == {:ok, false}
      assert Predicator.evaluate("false or true", %{}) == {:ok, true}
    end

    test "evaluates lowercase 'not' operator" do
      assert Predicator.evaluate("not true", %{}) == {:ok, false}
      assert Predicator.evaluate("not false", %{}) == {:ok, true}
    end

    test "works with boolean variables from context" do
      context = %{"active" => true, "expired" => false, "verified" => true}

      assert Predicator.evaluate("active and verified", context) == {:ok, true}
      assert Predicator.evaluate("active and expired", context) == {:ok, false}
      assert Predicator.evaluate("active or expired", context) == {:ok, true}
      assert Predicator.evaluate("expired or verified", context) == {:ok, true}
      assert Predicator.evaluate("not expired", context) == {:ok, true}
      assert Predicator.evaluate("not active", context) == {:ok, false}
    end

    test "combines with comparisons" do
      context = %{"score" => 85, "age" => 20, "admin" => false}

      assert Predicator.evaluate("score >= 80 and age >= 18", context) == {:ok, true}
      assert Predicator.evaluate("score >= 90 and age >= 18", context) == {:ok, false}
      assert Predicator.evaluate("score >= 90 or admin", context) == {:ok, false}
      assert Predicator.evaluate("not admin and score >= 80", context) == {:ok, true}
    end

    test "respects operator precedence with lowercase operators" do
      # not false or false and true should be: (not false) or (false and true) = true or false = true
      context = %{"expired" => true, "role" => "user", "score" => 90}

      result =
        Predicator.evaluate("not expired = false or role = \"user\" and score > 85", context)

      assert result == {:ok, true}
    end

    test "works with mixed case operators" do
      context = %{"active" => true, "admin" => false, "score" => 90}

      # Mix uppercase and lowercase
      assert Predicator.evaluate("active AND not admin", context) == {:ok, true}
      assert Predicator.evaluate("active and NOT admin", context) == {:ok, true}
      assert Predicator.evaluate("active or admin", context) == {:ok, true}
    end

    test "compiles lowercase operators correctly" do
      {:ok, instructions} = Predicator.compile("true and false")
      assert instructions == [["lit", true], ["lit", false], ["and"]]

      {:ok, instructions} = Predicator.compile("true or false")
      assert instructions == [["lit", true], ["lit", false], ["or"]]

      {:ok, instructions} = Predicator.compile("not true")
      assert instructions == [["lit", true], ["not"]]
    end

    test "parses lowercase operators correctly" do
      {:ok, ast} = Predicator.parse("true and false")
      assert match?({:logical_and, {:literal, true}, {:literal, false}}, ast)

      {:ok, ast} = Predicator.parse("true or false")
      assert match?({:logical_or, {:literal, true}, {:literal, false}}, ast)

      {:ok, ast} = Predicator.parse("not true")
      assert match?({:logical_not, {:literal, true}}, ast)
    end

    test "decompiles to preserve original case" do
      # Note: Decompilation uses StringVisitor which formats based on AST
      # The original case is preserved in the token value
      {:ok, ast} = Predicator.parse("active and expired")
      decompiled = Predicator.decompile(ast)
      # StringVisitor uses uppercase in output
      assert decompiled == "active AND expired"
    end

    test "works with complex expressions" do
      context = %{"user" => "admin", "active" => true, "score" => 95, "verified" => false}

      assert Predicator.evaluate("user = \"admin\" and active and score > 90", context) ==
               {:ok, true}

      result = Predicator.evaluate("not verified or (active and score > 85)", context)
      assert result == {:ok, true}

      assert Predicator.evaluate("verified and active or user = \"admin\"", context) ==
               {:ok, true}
    end
  end

  describe "list literals and membership operators" do
    test "evaluates list literals" do
      assert Predicator.evaluate("[1, 2, 3]", %{}) == {:ok, [1, 2, 3]}
      assert Predicator.evaluate("[]", %{}) == {:ok, []}
      assert Predicator.evaluate(~s(["admin", "manager"]), %{}) == {:ok, ["admin", "manager"]}
      assert Predicator.evaluate("[true, false]", %{}) == {:ok, [true, false]}
    end

    test "evaluates 'in' operator with literals" do
      assert Predicator.evaluate("1 in [1, 2, 3]", %{}) == {:ok, true}
      assert Predicator.evaluate("4 in [1, 2, 3]", %{}) == {:ok, false}
      assert Predicator.evaluate(~s("admin" in ["admin", "manager"]), %{}) == {:ok, true}
      assert Predicator.evaluate(~s("user" in ["admin", "manager"]), %{}) == {:ok, false}
      assert Predicator.evaluate("true in [true, false]", %{}) == {:ok, true}
      assert Predicator.evaluate("false in [true]", %{}) == {:ok, false}
    end

    test "evaluates 'contains' operator with literals" do
      assert Predicator.evaluate("[1, 2, 3] contains 2", %{}) == {:ok, true}
      assert Predicator.evaluate("[1, 2, 3] contains 4", %{}) == {:ok, false}
      assert Predicator.evaluate(~s(["admin", "manager"] contains "admin"), %{}) == {:ok, true}
      assert Predicator.evaluate(~s(["admin", "manager"] contains "user"), %{}) == {:ok, false}
      assert Predicator.evaluate("[true, false] contains false", %{}) == {:ok, true}
      assert Predicator.evaluate("[true] contains false", %{}) == {:ok, false}
    end

    test "evaluates 'in' operator with variables" do
      context = %{"role" => "admin", "permissions" => ["read", "write"]}

      assert Predicator.evaluate(~s(role in ["admin", "manager"]), context) == {:ok, true}
      assert Predicator.evaluate(~s(role in ["user", "guest"]), context) == {:ok, false}
      assert Predicator.evaluate(~s("write" in permissions), context) == {:ok, true}
      assert Predicator.evaluate(~s("delete" in permissions), context) == {:ok, false}
    end

    test "evaluates 'contains' operator with variables" do
      context = %{"roles" => ["admin", "manager"], "active" => true}

      assert Predicator.evaluate(~s(roles contains "admin"), context) == {:ok, true}
      assert Predicator.evaluate(~s(roles contains "user"), context) == {:ok, false}
      assert Predicator.evaluate("[true, false] contains active", context) == {:ok, true}
    end

    test "works with lowercase membership operators" do
      assert Predicator.evaluate("1 in [1, 2, 3]", %{}) == {:ok, true}
      assert Predicator.evaluate("1 IN [1, 2, 3]", %{}) == {:ok, true}
      assert Predicator.evaluate("[1, 2] contains 1", %{}) == {:ok, true}
      assert Predicator.evaluate("[1, 2] CONTAINS 1", %{}) == {:ok, true}
    end

    test "combines with logical operators" do
      context = %{"role" => "admin", "active" => true, "permissions" => ["read", "write"]}

      assert Predicator.evaluate(~s(role in ["admin", "manager"] AND active), context) ==
               {:ok, true}

      assert Predicator.evaluate(~s(role in ["admin", "manager"] OR active), context) ==
               {:ok, true}

      assert Predicator.evaluate(~s(NOT role in ["user", "guest"]), context) == {:ok, true}

      assert Predicator.evaluate(~s(permissions contains "write" AND active), context) ==
               {:ok, true}
    end

    test "handles empty lists" do
      assert Predicator.evaluate("1 in []", %{}) == {:ok, false}
      assert Predicator.evaluate("[] contains 1", %{}) == {:ok, false}
    end

    test "handles type mismatches" do
      # Different types should not match
      assert Predicator.evaluate(~s("1" in [1, 2, 3]), %{}) == {:ok, false}
      assert Predicator.evaluate(~s(1 in ["1", "2", "3"]), %{}) == {:ok, false}
      assert Predicator.evaluate("[1, 2, 3] contains \"1\"", %{}) == {:ok, false}
    end

    test "returns :undefined for missing variables" do
      assert Predicator.evaluate("missing_var in [1, 2, 3]", %{}) == {:ok, :undefined}
      assert Predicator.evaluate("[1, 2, 3] contains missing_var", %{}) == {:ok, :undefined}
    end

    test "parses list expressions correctly" do
      {:ok, ast} = Predicator.parse("[1, 2, 3]")
      assert match?({:list, [_literal1, _literal2, _literal3]}, ast)

      {:ok, ast} = Predicator.parse("1 in [1, 2, 3]")
      assert match?({:membership, :in, {:literal, 1}, {:list, _elements}}, ast)

      {:ok, ast} = Predicator.parse("[1, 2] contains 1")
      assert match?({:membership, :contains, {:list, _elements}, {:literal, 1}}, ast)
    end

    test "compiles list expressions correctly" do
      {:ok, instructions} = Predicator.compile("[1, 2, 3]")
      assert instructions == [["lit", [1, 2, 3]]]

      {:ok, instructions} = Predicator.compile("1 in [1, 2, 3]")
      assert instructions == [["lit", 1], ["lit", [1, 2, 3]], ["in"]]

      {:ok, instructions} = Predicator.compile("[1, 2] contains 1")
      assert instructions == [["lit", [1, 2]], ["lit", 1], ["contains"]]
    end

    test "decompiles list expressions" do
      {:ok, ast} = Predicator.parse("[1, 2, 3]")
      assert Predicator.decompile(ast) == "[1, 2, 3]"

      {:ok, ast} = Predicator.parse("1 in [1, 2, 3]")
      assert Predicator.decompile(ast) == "1 IN [1, 2, 3]"

      {:ok, ast} = Predicator.parse("[1, 2] contains 1")
      assert Predicator.decompile(ast) == "[1, 2] CONTAINS 1"
    end

    test "works with complex expressions" do
      context = %{
        "user_roles" => ["admin", "manager"],
        "permissions" => ["read", "write", "delete"],
        "active" => true
      }

      result =
        Predicator.evaluate(
          ~s(user_roles contains "admin" AND permissions contains "delete"),
          context
        )

      assert result == {:ok, true}

      result =
        Predicator.evaluate(
          ~s(user_roles contains "guest" OR permissions contains "read"),
          context
        )

      assert result == {:ok, true}

      result = Predicator.evaluate(~s(NOT user_roles contains "guest" AND active), context)
      assert result == {:ok, true}
    end

    test "handles error cases" do
      # IN with non-list on right side
      result = Predicator.evaluate("1 in 2", %{})
      assert {:error, _message} = result

      # CONTAINS with non-list on left side
      result = Predicator.evaluate("1 contains 2", %{})
      assert {:error, _message} = result
    end
  end

  describe "date literals and comparisons" do
    test "evaluates date literals" do
      assert Predicator.evaluate("#2024-01-15#", %{}) == {:ok, ~D[2024-01-15]}
    end

    test "evaluates datetime literals" do
      result = Predicator.evaluate("#2024-01-15T10:30:00Z#", %{})
      expected = DateTime.from_iso8601("2024-01-15T10:30:00Z") |> elem(1)
      assert result == {:ok, expected}
    end

    test "evaluates date comparisons with literals" do
      assert Predicator.evaluate("#2024-01-15# > #2024-01-10#", %{}) == {:ok, true}
      assert Predicator.evaluate("#2024-01-15# < #2024-01-10#", %{}) == {:ok, false}
      assert Predicator.evaluate("#2024-01-15# >= #2024-01-15#", %{}) == {:ok, true}
      assert Predicator.evaluate("#2024-01-15# <= #2024-01-15#", %{}) == {:ok, true}
      assert Predicator.evaluate("#2024-01-15# = #2024-01-15#", %{}) == {:ok, true}
      assert Predicator.evaluate("#2024-01-15# != #2024-01-10#", %{}) == {:ok, true}
    end

    test "evaluates datetime comparisons with literals" do
      dt1 = "#2024-01-15T10:30:00Z#"
      dt2 = "#2024-01-15T09:30:00Z#"
      dt3 = "#2024-01-15T10:30:00Z#"

      assert Predicator.evaluate("#{dt1} > #{dt2}", %{}) == {:ok, true}
      assert Predicator.evaluate("#{dt1} < #{dt2}", %{}) == {:ok, false}
      assert Predicator.evaluate("#{dt1} >= #{dt3}", %{}) == {:ok, true}
      assert Predicator.evaluate("#{dt1} <= #{dt3}", %{}) == {:ok, true}
      assert Predicator.evaluate("#{dt1} = #{dt3}", %{}) == {:ok, true}
      assert Predicator.evaluate("#{dt1} != #{dt2}", %{}) == {:ok, true}
    end

    test "evaluates date comparisons with variables" do
      context = %{
        "start_date" => ~D[2024-01-15],
        "end_date" => ~D[2024-01-20]
      }

      assert Predicator.evaluate("start_date < end_date", context) == {:ok, true}
      assert Predicator.evaluate("start_date > end_date", context) == {:ok, false}
      assert Predicator.evaluate("start_date <= start_date", context) == {:ok, true}
      assert Predicator.evaluate("#2024-01-18# > start_date", context) == {:ok, true}
      assert Predicator.evaluate("#2024-01-18# < end_date", context) == {:ok, true}
    end

    test "evaluates datetime comparisons with variables" do
      {:ok, start_dt, _offset1} = DateTime.from_iso8601("2024-01-15T10:00:00Z")
      {:ok, end_dt, _offset2} = DateTime.from_iso8601("2024-01-15T18:00:00Z")

      context = %{
        "meeting_start" => start_dt,
        "meeting_end" => end_dt
      }

      assert Predicator.evaluate("meeting_start < meeting_end", context) == {:ok, true}
      assert Predicator.evaluate("#2024-01-15T14:00:00Z# > meeting_start", context) == {:ok, true}
      assert Predicator.evaluate("#2024-01-15T14:00:00Z# < meeting_end", context) == {:ok, true}
    end

    test "handles mixed date and datetime comparisons" do
      # Different types should not match
      assert Predicator.evaluate("#2024-01-15# > #2024-01-15T10:00:00Z#", %{}) ==
               {:ok, :undefined}
    end

    test "combines with logical operators" do
      context = %{
        "start_date" => ~D[2024-01-15],
        "end_date" => ~D[2024-01-20],
        "active" => true
      }

      assert Predicator.evaluate("start_date < end_date AND active", context) == {:ok, true}
      assert Predicator.evaluate("start_date > end_date OR active", context) == {:ok, true}
      assert Predicator.evaluate("NOT start_date > end_date", context) == {:ok, true}
    end

    test "works in list membership operations" do
      dates = [~D[2024-01-15], ~D[2024-01-16], ~D[2024-01-17]]
      context = %{"dates" => dates}

      assert Predicator.evaluate("#2024-01-15# in dates", context) == {:ok, true}
      assert Predicator.evaluate("#2024-01-18# in dates", context) == {:ok, false}
      assert Predicator.evaluate("dates contains #2024-01-16#", context) == {:ok, true}
      assert Predicator.evaluate("dates contains #2024-01-18#", context) == {:ok, false}
    end

    test "handles :undefined for missing date variables" do
      assert Predicator.evaluate("missing_date > #2024-01-15#", %{}) == {:ok, :undefined}
      assert Predicator.evaluate("#2024-01-15# < missing_date", %{}) == {:ok, :undefined}
    end

    test "parses date expressions correctly" do
      {:ok, ast} = Predicator.parse("#2024-01-15#")
      assert match?({:literal, %Date{}}, ast)

      {:ok, ast} = Predicator.parse("#2024-01-15T10:30:00Z#")
      assert match?({:literal, %DateTime{}}, ast)

      {:ok, ast} = Predicator.parse("#2024-01-15# > #2024-01-10#")
      assert match?({:comparison, :gt, {:literal, %Date{}}, {:literal, %Date{}}}, ast)
    end

    test "compiles date expressions correctly" do
      {:ok, instructions} = Predicator.compile("#2024-01-15#")
      assert [["lit", %Date{}]] = instructions

      {:ok, instructions} = Predicator.compile("#2024-01-15# > #2024-01-10#")
      assert [["lit", %Date{}], ["lit", %Date{}], ["compare", "GT"]] = instructions
    end

    test "decompiles date expressions" do
      {:ok, ast} = Predicator.parse("#2024-01-15#")
      assert Predicator.decompile(ast) == "#2024-01-15#"

      {:ok, ast} = Predicator.parse("#2024-01-15T10:30:00Z#")
      decompiled = Predicator.decompile(ast)
      assert String.starts_with?(decompiled, "#2024-01-15T10:30:00")
      assert String.ends_with?(decompiled, "#")

      {:ok, ast} = Predicator.parse("#2024-01-15# > #2024-01-10#")
      assert Predicator.decompile(ast) == "#2024-01-15# > #2024-01-10#"
    end

    test "handles error cases" do
      # Invalid date format
      result = Predicator.evaluate("#invalid-date#", %{})
      assert {:error, _message} = result

      # Syntax errors
      result = Predicator.evaluate("#2024-01-15", %{})
      assert {:error, _message} = result
    end

    test "works with complex expressions" do
      {:ok, start_dt, _offset1} = DateTime.from_iso8601("2024-01-15T09:00:00Z")
      {:ok, end_dt, _offset2} = DateTime.from_iso8601("2024-01-15T17:00:00Z")

      context = %{
        "event_start" => start_dt,
        "event_end" => end_dt,
        "published" => true,
        "deadline" => ~D[2024-01-20]
      }

      # Complex date and boolean logic
      result =
        Predicator.evaluate(
          "published AND event_start < #2024-01-15T12:00:00Z# AND deadline > #2024-01-18#",
          context
        )

      assert result == {:ok, true}

      result =
        Predicator.evaluate(
          "(event_start > #2024-01-15T10:00:00Z# OR published) AND deadline < #2024-01-19#",
          context
        )

      assert result == {:ok, false}
    end
  end

  describe "nested context access" do
    test "simple nested access with string expressions" do
      context = %{"user" => %{"name" => %{"first" => "John", "last" => "Doe"}, "age" => 47}}

      assert Predicator.evaluate("user.name.first = \"John\"", context) == {:ok, true}
      assert Predicator.evaluate("user.name.last = \"Doe\"", context) == {:ok, true}
      assert Predicator.evaluate("user.age = 47", context) == {:ok, true}
      assert Predicator.evaluate("user.name.middle = \"X\"", context) == {:ok, :undefined}
    end

    test "nested access with atom keys" do
      context = %{user: %{name: %{first: "John"}, age: 47}}

      assert Predicator.evaluate("user.name.first = \"John\"", context) == {:ok, true}
      assert Predicator.evaluate("user.age > 18", context) == {:ok, true}
    end

    test "nested access with mixed key types" do
      context = %{"user" => %{profile: %{"name" => "John"}, age: 47}}

      assert Predicator.evaluate("user.profile.name = \"John\"", context) == {:ok, true}
      assert Predicator.evaluate("user.age >= 47", context) == {:ok, true}
    end

    test "nested access in complex expressions" do
      context = %{
        "user" => %{"name" => "John", "age" => 47},
        "config" => %{"enabled" => true, "level" => 3}
      }

      assert Predicator.evaluate("user.age > 18 AND config.enabled", context) == {:ok, true}

      assert Predicator.evaluate("user.name = \"John\" OR config.level > 5", context) ==
               {:ok, true}

      assert Predicator.evaluate("user.age < 18 AND config.enabled", context) == {:ok, false}
    end

    test "nested access with missing paths returns :undefined" do
      context = %{"user" => %{"name" => "John"}}

      assert Predicator.evaluate("user.profile.settings.theme = \"dark\"", context) ==
               {:ok, :undefined}

      assert Predicator.evaluate("missing.path.here = \"value\"", context) == {:ok, :undefined}
    end

    test "nested access with non-map intermediate values" do
      context = %{"user" => %{"name" => "John Doe"}}

      # "name" is a string, not a map, so "user.name.first" should be :undefined
      assert Predicator.evaluate("user.name.first = \"John\"", context) == {:ok, :undefined}
    end

    test "deeply nested structures" do
      context = %{
        "app" => %{
          "database" => %{
            "config" => %{
              "host" => "localhost",
              "port" => 5432,
              "settings" => %{
                "ssl" => true,
                "timeout" => 30
              }
            }
          }
        }
      }

      assert Predicator.evaluate("app.database.config.host = \"localhost\"", context) ==
               {:ok, true}

      assert Predicator.evaluate("app.database.config.port = 5432", context) == {:ok, true}
      assert Predicator.evaluate("app.database.config.settings.ssl", context) == {:ok, true}

      assert Predicator.evaluate("app.database.config.settings.timeout > 25", context) ==
               {:ok, true}
    end

    test "nested access with list values" do
      context = %{
        "user" => %{
          "name" => "John",
          "hobbies" => ["reading", "coding", "gaming"],
          "scores" => [85, 92, 78]
        }
      }

      # Access the list itself
      {:ok, hobbies} = Predicator.evaluate("user.hobbies", context)
      assert hobbies == ["reading", "coding", "gaming"]

      # Use list in membership test
      assert Predicator.evaluate("\"coding\" in user.hobbies", context) == {:ok, true}
      assert Predicator.evaluate("\"dancing\" in user.hobbies", context) == {:ok, false}
    end
  end

  describe "single quoted strings" do
    test "evaluates single quoted string comparisons" do
      context = %{"name" => "John"}

      assert Predicator.evaluate("name = 'John'", context) == {:ok, true}
      assert Predicator.evaluate("name = 'Jane'", context) == {:ok, false}
    end

    test "handles mixed single and double quotes" do
      context = %{"quote" => "don't", "apostrophe" => "he said \"hello\""}

      assert Predicator.evaluate("quote = 'don\\'t'", context) == {:ok, true}
      assert Predicator.evaluate("apostrophe = 'he said \"hello\"'", context) == {:ok, true}
    end

    test "preserves quote type in round trip compilation" do
      # Test that single quotes are preserved through parsing and decompilation
      single_quoted = "name = 'John'"
      double_quoted = "name = \"John\""

      {:ok, single_ast} = Predicator.parse(single_quoted)
      {:ok, double_ast} = Predicator.parse(double_quoted)

      single_decompiled = Predicator.decompile(single_ast)
      double_decompiled = Predicator.decompile(double_ast)

      assert single_decompiled == "name = 'John'"
      assert double_decompiled == "name = \"John\""
    end

    test "single quoted strings in complex expressions" do
      context = %{"status" => "active", "role" => "admin"}

      assert Predicator.evaluate("status = 'active' AND role = 'admin'", context) == {:ok, true}
      assert Predicator.evaluate("status = 'inactive' OR role = 'admin'", context) == {:ok, true}
    end

    test "single quoted strings in lists and membership" do
      context = %{"roles" => ["admin", "user"]}

      assert Predicator.evaluate("'admin' in roles", context) == {:ok, true}
      assert Predicator.evaluate("'guest' in roles", context) == {:ok, false}
    end
  end

  describe "custom functions" do
    test "evaluates custom functions with evaluate/3" do
      custom_functions = %{
        "double" => {1, fn [n], _context -> {:ok, n * 2} end},
        "add" => {2, fn [a, b], _context -> {:ok, a + b} end}
      }

      # Test single-argument function
      assert Predicator.evaluate("double(21)", %{}, functions: custom_functions) == {:ok, 42}

      # Test with context variable
      assert Predicator.evaluate("double(score)", %{"score" => 25}, functions: custom_functions) ==
               {:ok, 50}

      # Test two-argument function
      assert Predicator.evaluate("add(10, 15)", %{}, functions: custom_functions) == {:ok, 25}
    end

    test "custom functions work with built-in functions" do
      custom_functions = %{
        "double" => {1, fn [n], _context -> {:ok, n * 2} end}
      }

      # Built-in function still works
      assert Predicator.evaluate("len('hello')", %{}, functions: custom_functions) == {:ok, 5}

      # Custom function combined with built-in
      assert Predicator.evaluate("double(len('hello'))", %{}, functions: custom_functions) ==
               {:ok, 10}
    end

    test "custom functions can override built-in functions" do
      custom_functions = %{
        "len" => {1, fn [_string], _context -> {:ok, 999} end}
      }

      # Custom function overrides built-in
      assert Predicator.evaluate("len('hello')", %{}, functions: custom_functions) == {:ok, 999}
    end

    test "custom functions work with evaluate!/3" do
      custom_functions = %{
        "triple" => {1, fn [n], _context -> {:ok, n * 3} end}
      }

      assert Predicator.evaluate!("triple(7)", %{}, functions: custom_functions) == 21
    end

    test "backward compatibility still works" do
      # Without custom functions, built-ins still work
      assert Predicator.evaluate("len('world')", %{}) == {:ok, 5}
      assert Predicator.evaluate!("upper('test')", %{}) == "TEST"
    end

    test "custom function errors are handled properly" do
      custom_functions = %{
        "error_func" => {1, fn [_arg], _context -> {:error, "custom error"} end},
        "exception_func" => {1, fn [_arg], _context -> raise "something went wrong" end}
      }

      # Function returns error
      assert Predicator.evaluate("error_func(1)", %{}, functions: custom_functions) ==
               {:error,
                %Predicator.Errors.EvaluationError{
                  reason: "custom error",
                  message: "custom error",
                  operation: :function_call
                }}

      # Function raises exception
      assert {:error, %Predicator.Errors.EvaluationError{message: error_msg}} =
               Predicator.evaluate("exception_func(1)", %{}, functions: custom_functions)

      assert error_msg =~ "Function exception_func() raised:"
      assert error_msg =~ "something went wrong"
    end

    test "unknown custom function returns error" do
      assert {:error, %Predicator.Errors.EvaluationError{message: error_msg}} =
               Predicator.evaluate("unknown_func()", %{})

      assert error_msg == "Unknown function: unknown_func"
    end

    test "arity mismatch in custom function returns error" do
      custom_functions = %{
        "add" => {2, fn [a, b], _context -> {:ok, a + b} end}
      }

      # Too few arguments
      assert {:error, %Predicator.Errors.EvaluationError{message: error_msg}} =
               Predicator.evaluate("add(5)", %{}, functions: custom_functions)

      assert error_msg == "Function add() expects 2 arguments, got 1"

      # Too many arguments
      assert {:error, %Predicator.Errors.EvaluationError{message: error_msg}} =
               Predicator.evaluate("add(5, 10, 15)", %{}, functions: custom_functions)

      assert error_msg == "Function add() expects 2 arguments, got 3"
    end

    test "context-aware custom functions" do
      custom_functions = %{
        "get_user_role" => {0, fn [], context -> {:ok, Map.get(context, "role", "guest")} end},
        "multiply_by_factor" =>
          {1,
           fn [n], context ->
             factor = Map.get(context, "factor", 1)
             {:ok, n * factor}
           end}
      }

      context = %{"role" => "admin", "factor" => 5}

      assert Predicator.evaluate("get_user_role()", context, functions: custom_functions) ==
               {:ok, "admin"}

      assert Predicator.evaluate("multiply_by_factor(10)", context, functions: custom_functions) ==
               {:ok, 50}
    end
  end

  describe "evaluate/2 with bracket access expressions" do
    test "evaluates simple bracket access with string key" do
      context = %{"user" => %{"name" => "John", "age" => 30}}

      assert Predicator.evaluate("user['name']", context) == {:ok, "John"}
      assert Predicator.evaluate("user['age']", context) == {:ok, 30}
    end

    test "evaluates bracket access with atom keys" do
      context = %{"user" => %{:name => "John", :age => 30}}

      assert Predicator.evaluate("user['name']", context) == {:ok, "John"}
      assert Predicator.evaluate("user['age']", context) == {:ok, 30}
    end

    test "evaluates array access with numeric indices" do
      context = %{"items" => ["apple", "banana", "cherry"], "numbers" => [10, 20, 30]}

      assert Predicator.evaluate("items[0]", context) == {:ok, "apple"}
      assert Predicator.evaluate("items[1]", context) == {:ok, "banana"}
      assert Predicator.evaluate("numbers[2]", context) == {:ok, 30}
    end

    test "evaluates bracket access with variable key" do
      context = %{
        "user" => %{"name" => "John", "age" => 30},
        "key" => "name",
        "index" => 1,
        "items" => ["a", "b", "c"]
      }

      assert Predicator.evaluate("user[key]", context) == {:ok, "John"}
      assert Predicator.evaluate("items[index]", context) == {:ok, "b"}
    end

    test "evaluates chained bracket access" do
      context = %{
        "data" => %{
          "users" => [
            %{"name" => "John", "age" => 30},
            %{"name" => "Jane", "age" => 25}
          ]
        }
      }

      assert Predicator.evaluate("data['users'][0]['name']", context) == {:ok, "John"}
      assert Predicator.evaluate("data['users'][1]['age']", context) == {:ok, 25}
    end

    test "evaluates mixed dot notation and bracket access" do
      # Note: In the current implementation, dot notation creates nested identifiers
      # This tests that bracket access works alongside existing variable naming
      context = %{
        "user" => %{"name" => "John"},
        "settings" => %{"theme" => "dark"}
      }

      # Test that bracket access works
      assert Predicator.evaluate("user['name']", context) == {:ok, "John"}
      assert Predicator.evaluate("settings['theme']", context) == {:ok, "dark"}
    end

    test "evaluates bracket access with arithmetic expression key" do
      context = %{
        "items" => ["a", "b", "c", "d"],
        "offset" => 1,
        "multiplier" => 2
      }

      assert Predicator.evaluate("items[offset + 1]", context) == {:ok, "c"}
      assert Predicator.evaluate("items[offset * multiplier]", context) == {:ok, "c"}
    end

    test "evaluates bracket access in comparisons" do
      context = %{
        "user" => %{"age" => 30, "score" => 95},
        "thresholds" => %{"min_age" => 18, "passing_score" => 80}
      }

      assert Predicator.evaluate("user['age'] > 18", context) == {:ok, true}

      assert Predicator.evaluate("user['score'] >= thresholds['passing_score']", context) ==
               {:ok, true}

      assert Predicator.evaluate("user['age'] < thresholds['min_age']", context) == {:ok, false}
    end

    test "evaluates bracket access in arithmetic expressions" do
      context = %{
        "scores" => [85, 90, 78],
        "multipliers" => [2, 3, 4],
        "bonuses" => %{"effort" => 5, "attendance" => 3}
      }

      assert Predicator.evaluate("scores[0] + scores[1]", context) == {:ok, 175}
      assert Predicator.evaluate("scores[0] * multipliers[0]", context) == {:ok, 170}
      assert Predicator.evaluate("bonuses['effort'] + bonuses['attendance']", context) == {:ok, 8}
    end

    test "evaluates bracket access in logical expressions" do
      context = %{
        "user" => %{"active" => true, "verified" => true, "age" => 25},
        "settings" => %{"notifications" => false, "theme" => "dark"}
      }

      assert Predicator.evaluate("user['active'] AND user['verified']", context) == {:ok, true}

      assert Predicator.evaluate("user['active'] OR settings['notifications']", context) ==
               {:ok, true}

      assert Predicator.evaluate("NOT settings['notifications']", context) == {:ok, true}
    end

    test "evaluates complex nested bracket access expressions" do
      context = %{
        "company" => %{
          "departments" => [
            %{"name" => "Engineering", "employees" => [%{"name" => "John", "salary" => 80_000}]},
            %{"name" => "Marketing", "employees" => [%{"name" => "Jane", "salary" => 65_000}]}
          ]
        },
        "dept_index" => 0,
        "emp_index" => 0
      }

      assert Predicator.evaluate(
               "company['departments'][dept_index]['employees'][emp_index]['name']",
               context
             ) == {:ok, "John"}

      assert Predicator.evaluate(
               "company['departments'][0]['employees'][0]['salary'] > 75000",
               context
             ) == {:ok, true}
    end

    test "evaluates bracket access with function call keys" do
      context = %{
        "data" => %{"key_1" => "value1", "key_2" => "value2"},
        "keys" => ["key_1", "key_2"],
        "short" => "ab"
      }

      # Test with built-in len function (len("ab") = 2, so 2-1 = 1, keys[1] = "key_2")
      assert Predicator.evaluate("keys[len(short) - 1]", context) == {:ok, "key_2"}
    end

    test "evaluates bracket access with boolean keys" do
      context = %{
        "config" => %{true => "enabled", false => "disabled"},
        "status" => %{"active" => true, "debug" => false}
      }

      assert Predicator.evaluate("config[true]", context) == {:ok, "enabled"}
      assert Predicator.evaluate("config[false]", context) == {:ok, "disabled"}
      assert Predicator.evaluate("config[status['active']]", context) == {:ok, "enabled"}
    end

    test "evaluates bracket access with list membership" do
      context = %{
        "users" => [
          %{"name" => "John", "roles" => ["admin", "user"]},
          %{"name" => "Jane", "roles" => ["user"]}
        ],
        "admin_roles" => ["admin", "super_admin"]
      }

      assert Predicator.evaluate("'admin' in users[0]['roles']", context) == {:ok, true}
      assert Predicator.evaluate("users[0]['roles'] contains 'admin'", context) == {:ok, true}
      assert Predicator.evaluate("'admin' in users[1]['roles']", context) == {:ok, false}
    end

    test "returns :undefined for missing bracket access paths" do
      context = %{"user" => %{"name" => "John"}}

      assert Predicator.evaluate("user['missing_key']", context) == {:ok, :undefined}
      assert Predicator.evaluate("missing_object['key']", context) == {:ok, :undefined}
      assert Predicator.evaluate("user['name']['nested']", context) == {:ok, :undefined}
    end

    test "returns :undefined for out-of-bounds array access" do
      context = %{"items" => ["a", "b", "c"]}

      assert Predicator.evaluate("items[10]", context) == {:ok, :undefined}
      assert Predicator.evaluate("items[-1]", context) == {:ok, :undefined}
    end

    test "handles bracket access errors gracefully" do
      context = %{"data" => "not_a_map_or_list"}

      # Non-indexable object with string key returns :undefined
      assert Predicator.evaluate("data['key']", context) == {:ok, :undefined}

      # Non-indexable object with numeric key also returns :undefined
      assert Predicator.evaluate("data[0]", context) == {:ok, :undefined}
    end

    test "evaluates performance with deeply nested bracket access" do
      # Test that deeply nested access doesn't cause performance issues
      deeply_nested = %{
        "level1" => %{
          "level2" => %{
            "level3" => %{
              "level4" => %{
                "level5" => %{"final_value" => "success"}
              }
            }
          }
        }
      }

      context = %{"data" => deeply_nested}

      result =
        Predicator.evaluate(
          "data['level1']['level2']['level3']['level4']['level5']['final_value']",
          context
        )

      assert result == {:ok, "success"}
    end

    test "round-trip conversion with bracket access" do
      alias Predicator.{Lexer, Parser}
      alias Predicator.Visitors.StringVisitor
      expressions = [
        "user['name']",
        "items[0]",
        "data['users'][index]['profile']['settings']",
        "scores[0] + scores[1] > threshold['min']",
        "user['active'] AND config['enabled']"
      ]

      for expr <- expressions do
        {:ok, tokens} = Lexer.tokenize(expr)
        {:ok, ast} = Parser.parse(tokens)
        regenerated = StringVisitor.visit(ast)

        # Parse the regenerated expression to ensure it's valid
        {:ok, tokens2} = Lexer.tokenize(regenerated)
        assert {:ok, _ast2} = Parser.parse(tokens2)
      end
    end
  end
end
