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

      assert message =~
               "Expected number, string, boolean, identifier, or '(' but found end of input"

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

      assert message =~
               "Expected number, string, boolean, identifier, or '(' but found end of input"

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

      assert results == [true, false, true, false]
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

      assert results == [true, false]
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

  describe "logical operators - integration tests" do
    test "evaluates logical AND with true results" do
      result = Predicator.evaluate("score > 85 AND age >= 18", %{"score" => 90, "age" => 25})
      assert result == true
    end

    test "evaluates logical AND with false results" do
      result = Predicator.evaluate("score > 85 AND age >= 18", %{"score" => 80, "age" => 25})
      assert result == false

      result = Predicator.evaluate("score > 85 AND age >= 18", %{"score" => 90, "age" => 16})
      assert result == false

      result = Predicator.evaluate("score > 85 AND age >= 18", %{"score" => 80, "age" => 16})
      assert result == false
    end

    test "evaluates logical OR with true results" do
      result = Predicator.evaluate(~s(role = "admin" OR role = "manager"), %{"role" => "admin"})
      assert result == true

      result =
        Predicator.evaluate(~s(role = "admin" OR role = "manager"), %{"role" => "manager"})

      assert result == true
    end

    test "evaluates logical OR with false results" do
      result = Predicator.evaluate(~s(role = "admin" OR role = "manager"), %{"role" => "user"})
      assert result == false
    end

    test "evaluates logical NOT with boolean variables" do
      result = Predicator.evaluate("NOT expired = true", %{"expired" => false})
      assert result == true

      result = Predicator.evaluate("NOT expired = true", %{"expired" => true})
      assert result == false
    end

    test "evaluates complex logical expressions" do
      # (score > 85 AND age >= 18) OR admin = true
      context1 = %{"score" => 90, "age" => 20, "admin" => false}
      result1 = Predicator.evaluate("score > 85 AND age >= 18 OR admin = true", context1)
      assert result1 == true

      context2 = %{"score" => 80, "age" => 16, "admin" => false}
      result2 = Predicator.evaluate("score > 85 AND age >= 18 OR admin = true", context2)
      assert result2 == false

      context3 = %{"score" => 80, "age" => 16, "admin" => true}
      result3 = Predicator.evaluate("score > 85 AND age >= 18 OR admin = true", context3)
      assert result3 == true
    end

    test "evaluates nested NOT expressions" do
      result = Predicator.evaluate("NOT NOT active = true", %{"active" => true})
      assert result == true

      result = Predicator.evaluate("NOT NOT active = true", %{"active" => false})
      assert result == false
    end

    test "evaluates operator precedence correctly" do
      # NOT false OR false AND true should be: (NOT false) OR (false AND true) = true OR false = true
      result =
        Predicator.evaluate(
          "NOT expired = false OR role = \"user\" AND score > 85",
          %{"expired" => true, "role" => "user", "score" => 90}
        )

      assert result == true

      # Same expression with different values - should be: false OR true = true
      result =
        Predicator.evaluate(
          "NOT expired = false OR role = \"user\" AND score > 85",
          %{"expired" => false, "role" => "user", "score" => 90}
        )

      assert result == true

      # Same expression with different values - should be: false OR false = false
      result =
        Predicator.evaluate(
          "NOT expired = false OR role = \"user\" AND score > 85",
          %{"expired" => false, "role" => "user", "score" => 80}
        )

      assert result == false
    end

    test "evaluates parenthesized logical expressions" do
      # (active = true OR role = \"admin\") AND score > 85
      context1 = %{"active" => true, "role" => "user", "score" => 90}

      result1 =
        Predicator.evaluate("(active = true OR role = \"admin\") AND score > 85", context1)

      assert result1 == true

      context2 = %{"active" => false, "role" => "admin", "score" => 90}

      result2 =
        Predicator.evaluate("(active = true OR role = \"admin\") AND score > 85", context2)

      assert result2 == true

      context3 = %{"active" => false, "role" => "user", "score" => 90}

      result3 =
        Predicator.evaluate("(active = true OR role = \"admin\") AND score > 85", context3)

      assert result3 == false

      context4 = %{"active" => true, "role" => "admin", "score" => 80}

      result4 =
        Predicator.evaluate("(active = true OR role = \"admin\") AND score > 85", context4)

      assert result4 == false
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
      result = Predicator.evaluate("score > 85 AND age >= 18", %{score: 90, age: 25})
      assert result == true

      result = Predicator.evaluate("NOT expired = true", %{expired: false})
      assert result == true
    end

    test "works with mixed string and atom keys in context" do
      result = Predicator.evaluate("score > 85 AND age >= 18", %{"score" => 90, age: 25})
      assert result == true

      result =
        Predicator.evaluate("role = \"admin\" OR active = true", %{
          "active" => false,
          role: "admin"
        })

      assert result == true
    end
  end

  describe "plain boolean expressions" do
    test "evaluates boolean literals without operators" do
      assert Predicator.evaluate("true", %{}) == true
      assert Predicator.evaluate("false", %{}) == false
    end

    test "evaluates boolean identifiers from context" do
      assert Predicator.evaluate("active", %{"active" => true}) == true
      assert Predicator.evaluate("active", %{"active" => false}) == false
      assert Predicator.evaluate("expired", %{"expired" => true}) == true
      assert Predicator.evaluate("expired", %{"expired" => false}) == false
    end

    test "evaluates boolean identifiers with atom keys" do
      assert Predicator.evaluate("active", %{active: true}) == true
      assert Predicator.evaluate("expired", %{expired: false}) == false
    end

    test "returns :undefined for missing boolean variables" do
      assert Predicator.evaluate("missing", %{}) == :undefined
    end

    test "works with logical operators on plain boolean expressions" do
      context = %{"active" => true, "expired" => false, "verified" => true}

      assert Predicator.evaluate("active AND verified", context) == true
      assert Predicator.evaluate("active AND expired", context) == false
      assert Predicator.evaluate("active OR expired", context) == true
      assert Predicator.evaluate("expired OR verified", context) == true
      assert Predicator.evaluate("NOT expired", context) == true
      assert Predicator.evaluate("NOT active", context) == false
    end

    test "combines plain boolean expressions with comparisons" do
      context = %{"active" => true, "score" => 90, "admin" => false}

      assert Predicator.evaluate("active AND score > 85", context) == true
      assert Predicator.evaluate("active AND score < 85", context) == false
      assert Predicator.evaluate("admin OR score > 85", context) == true
      assert Predicator.evaluate("NOT admin AND score > 85", context) == true
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
      result = Predicator.evaluate("active AND score > 90 OR admin", context)
      assert result == true

      result = Predicator.evaluate("NOT admin AND (active OR score < 80)", context)
      assert result == true

      result = Predicator.evaluate("false OR active AND true", context)
      assert result == true
    end
  end

  describe "lowercase logical operators" do
    test "evaluates lowercase 'and' operator" do
      assert Predicator.evaluate("true and false", %{}) == false
      assert Predicator.evaluate("true and true", %{}) == true
      assert Predicator.evaluate("false and false", %{}) == false
    end

    test "evaluates lowercase 'or' operator" do
      assert Predicator.evaluate("true or false", %{}) == true
      assert Predicator.evaluate("false or false", %{}) == false
      assert Predicator.evaluate("false or true", %{}) == true
    end

    test "evaluates lowercase 'not' operator" do
      assert Predicator.evaluate("not true", %{}) == false
      assert Predicator.evaluate("not false", %{}) == true
    end

    test "works with boolean variables from context" do
      context = %{"active" => true, "expired" => false, "verified" => true}

      assert Predicator.evaluate("active and verified", context) == true
      assert Predicator.evaluate("active and expired", context) == false
      assert Predicator.evaluate("active or expired", context) == true
      assert Predicator.evaluate("expired or verified", context) == true
      assert Predicator.evaluate("not expired", context) == true
      assert Predicator.evaluate("not active", context) == false
    end

    test "combines with comparisons" do
      context = %{"score" => 85, "age" => 20, "admin" => false}

      assert Predicator.evaluate("score >= 80 and age >= 18", context) == true
      assert Predicator.evaluate("score >= 90 and age >= 18", context) == false
      assert Predicator.evaluate("score >= 90 or admin", context) == false
      assert Predicator.evaluate("not admin and score >= 80", context) == true
    end

    test "respects operator precedence with lowercase operators" do
      # not false or false and true should be: (not false) or (false and true) = true or false = true
      context = %{"expired" => true, "role" => "user", "score" => 90}

      result =
        Predicator.evaluate("not expired = false or role = \"user\" and score > 85", context)

      assert result == true
    end

    test "works with mixed case operators" do
      context = %{"active" => true, "admin" => false, "score" => 90}

      # Mix uppercase and lowercase
      assert Predicator.evaluate("active AND not admin", context) == true
      assert Predicator.evaluate("active and NOT admin", context) == true
      assert Predicator.evaluate("active or admin", context) == true
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

      result = Predicator.evaluate("user = \"admin\" and active and score > 90", context)
      assert result == true

      result = Predicator.evaluate("not verified or (active and score > 85)", context)
      assert result == true

      result = Predicator.evaluate("verified and active or user = \"admin\"", context)
      assert result == true
    end
  end
end
