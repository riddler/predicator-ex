defmodule PredicatorLogicalOperatorsTest do
  use ExUnit.Case, async: true

  import Predicator.ParseShape

  alias Predicator.Errors.UndefinedVariableError

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
      assert Predicator.evaluate(~s(role == "admin" OR role == "manager"), %{"role" => "admin"}) ==
               {:ok, true}

      assert Predicator.evaluate(~s(role == "admin" OR role == "manager"), %{
               "role" => "manager"
             }) ==
               {:ok, true}
    end

    test "evaluates logical OR with false results" do
      assert Predicator.evaluate(~s(role == "admin" OR role == "manager"), %{"role" => "user"}) ==
               {:ok, false}
    end

    test "evaluates logical NOT with boolean variables" do
      assert Predicator.evaluate("NOT expired == true", %{"expired" => false}) == {:ok, true}

      assert Predicator.evaluate("NOT expired == true", %{"expired" => true}) == {:ok, false}
    end

    test "evaluates complex logical expressions" do
      # (score > 85 AND age >= 18) OR admin == true
      context1 = %{"score" => 90, "age" => 20, "admin" => false}

      assert Predicator.evaluate("score > 85 AND age >= 18 OR admin == true", context1) ==
               {:ok, true}

      context2 = %{"score" => 80, "age" => 16, "admin" => false}

      assert Predicator.evaluate("score > 85 AND age >= 18 OR admin == true", context2) ==
               {:ok, false}

      context3 = %{"score" => 80, "age" => 16, "admin" => true}

      assert Predicator.evaluate("score > 85 AND age >= 18 OR admin == true", context3) ==
               {:ok, true}
    end

    test "evaluates nested NOT expressions" do
      assert Predicator.evaluate("NOT NOT active == true", %{"active" => true}) == {:ok, true}

      assert Predicator.evaluate("NOT NOT active == true", %{"active" => false}) == {:ok, false}
    end

    test "evaluates operator precedence correctly" do
      # NOT false OR false AND true should be: (NOT false) OR (false AND true) = true OR false = true
      result =
        Predicator.evaluate(
          "NOT expired == false OR role == \"user\" AND score > 85",
          %{"expired" => true, "role" => "user", "score" => 90}
        )

      assert result == {:ok, true}

      # Same expression with different values - should be: false OR true = true
      result =
        Predicator.evaluate(
          "NOT expired == false OR role == \"user\" AND score > 85",
          %{"expired" => false, "role" => "user", "score" => 90}
        )

      assert result == {:ok, true}

      # Same expression with different values - should be: false OR false = false
      result =
        Predicator.evaluate(
          "NOT expired == false OR role == \"user\" AND score > 85",
          %{"expired" => false, "role" => "user", "score" => 80}
        )

      assert result == {:ok, false}
    end

    test "evaluates parenthesized logical expressions" do
      # (active == true OR role == \"admin\") AND score > 85
      context1 = %{"active" => true, "role" => "user", "score" => 90}

      result1 =
        Predicator.evaluate("(active == true OR role == \"admin\") AND score > 85", context1)

      assert result1 == {:ok, true}

      context2 = %{"active" => false, "role" => "admin", "score" => 90}

      result2 =
        Predicator.evaluate("(active == true OR role == \"admin\") AND score > 85", context2)

      assert result2 == {:ok, true}

      context3 = %{"active" => false, "role" => "user", "score" => 90}

      result3 =
        Predicator.evaluate("(active == true OR role == \"admin\") AND score > 85", context3)

      assert result3 == {:ok, false}

      context4 = %{"active" => true, "role" => "admin", "score" => 80}

      result4 =
        Predicator.evaluate("(active == true OR role == \"admin\") AND score > 85", context4)

      assert result4 == {:ok, false}
    end

    test "compiles and decompiles logical expressions correctly" do
      original_expressions = [
        "score > 85 AND age >= 18",
        "role == \"admin\" OR role == \"manager\"",
        "NOT expired == true",
        "score > 85 AND age >= 18 OR admin == true",
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
      {:ok, ast} = parse_positionless("score > 85 AND age >= 18")
      assert match?({:logical_and, _, _}, ast)

      {:ok, ast} = parse_positionless(~s(role == "admin" OR role == "manager"))
      assert match?({:logical_or, _, _}, ast)

      {:ok, ast} = parse_positionless("NOT expired == true")
      assert match?({:logical_not, _span}, ast)
    end

    test "compile function generates correct instructions for logical operators" do
      {:ok, instructions} = Predicator.compile("true AND false")
      assert instructions == [["lit", true], ["jump_if_falsy_or_pop", 2], ["lit", false]]

      {:ok, instructions} = Predicator.compile("true OR false")
      assert instructions == [["lit", true], ["jump_if_true_or_pop", 2], ["lit", false]]

      {:ok, instructions} = Predicator.compile("NOT true")
      assert instructions == [["lit", true], ["not"]]
    end

    test "evaluate! function works with logical operators" do
      result = Predicator.evaluate!("score > 85 AND age >= 18", %{"score" => 90, "age" => 25})
      assert result == true

      result = Predicator.evaluate!("NOT expired == true", %{"expired" => false})
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

      assert Predicator.evaluate("NOT expired == true", %{expired: false}) == {:ok, true}
    end

    test "works with mixed string and atom keys in context" do
      assert Predicator.evaluate("score > 85 AND age >= 18", %{"score" => 90, age: 25}) ==
               {:ok, true}

      result =
        Predicator.evaluate("role == \"admin\" OR active == true", %{
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
      assert {:error, %UndefinedVariableError{variable: "missing"}} =
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

      assert instructions == [
               ["load", "active"],
               ["jump_if_falsy_or_pop", 2],
               ["load", "expired"]
             ]
    end

    test "parses and decompiles plain boolean expressions" do
      {:ok, ast} = Predicator.parse("true")
      assert Predicator.ASTShape.strip(ast) == {:literal, true}
      assert Predicator.decompile(ast) == "true"

      {:ok, ast} = Predicator.parse("active")
      assert Predicator.ASTShape.strip(ast) == {:identifier, "active"}
      assert Predicator.decompile(ast) == "active"

      {:ok, ast} = Predicator.parse("active AND expired")

      assert match?(
               {:logical_and, {:identifier, "active"}, {:identifier, "expired"}},
               Predicator.ASTShape.strip(ast)
             )

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
        Predicator.evaluate("not expired == false or role == \"user\" and score > 85", context)

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
      assert instructions == [["lit", true], ["jump_if_falsy_or_pop", 2], ["lit", false]]

      {:ok, instructions} = Predicator.compile("true or false")
      assert instructions == [["lit", true], ["jump_if_true_or_pop", 2], ["lit", false]]

      {:ok, instructions} = Predicator.compile("not true")
      assert instructions == [["lit", true], ["not"]]
    end

    test "parses lowercase operators correctly" do
      {:ok, ast} = parse_positionless("true and false")
      assert match?({:logical_and, {:literal, true}, {:literal, false}}, ast)

      {:ok, ast} = parse_positionless("true or false")
      assert match?({:logical_or, {:literal, true}, {:literal, false}}, ast)

      {:ok, ast} = parse_positionless("not true")
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

      assert Predicator.evaluate("user == \"admin\" and active and score > 90", context) ==
               {:ok, true}

      result = Predicator.evaluate("not verified or (active and score > 85)", context)
      assert result == {:ok, true}

      assert Predicator.evaluate("verified and active or user == \"admin\"", context) ==
               {:ok, true}
    end
  end
end
