defmodule Predicator.Functions.QualifiedFunctionsTest do
  @moduledoc """
  Tests for qualified function support (namespace.function) in Predicator.
  """

  use ExUnit.Case

  alias Predicator.Lexer
  alias Predicator.Functions.{JSONFunctions, MathFunctions}

  doctest JSONFunctions

  describe "lexer qualified identifiers" do
    test "tokenizes single qualified function" do
      {:ok, tokens} = Lexer.tokenize("JSON.stringify(value)")

      assert tokens == [
               {:qualified_function_name, 1, 1, 14, "JSON.stringify"},
               {:lparen, 1, 15, 1, "("},
               {:identifier, 1, 16, 5, "value"},
               {:rparen, 1, 21, 1, ")"},
               {:eof, 1, 22, 0, nil}
             ]
    end

    test "tokenizes multi-level qualified function" do
      {:ok, tokens} = Lexer.tokenize("Company.Utils.JSON.stringify(data)")

      assert tokens == [
               {:qualified_function_name, 1, 1, 28, "Company.Utils.JSON.stringify"},
               {:lparen, 1, 29, 1, "("},
               {:identifier, 1, 30, 4, "data"},
               {:rparen, 1, 34, 1, ")"},
               {:eof, 1, 35, 0, nil}
             ]
    end

    test "distinguishes qualified functions from property access" do
      {:ok, tokens} = Lexer.tokenize("user.name.first")

      assert tokens == [
               {:identifier, 1, 1, 4, "user"},
               {:dot, 1, 5, 1, "."},
               {:identifier, 1, 6, 4, "name"},
               {:dot, 1, 10, 1, "."},
               {:identifier, 1, 11, 5, "first"},
               {:eof, 1, 16, 0, nil}
             ]
    end

    test "handles mixed qualified functions and property access" do
      {:ok, tokens} = Lexer.tokenize("JSON.stringify(user.profile)")

      assert tokens == [
               {:qualified_function_name, 1, 1, 14, "JSON.stringify"},
               {:lparen, 1, 15, 1, "("},
               {:identifier, 1, 16, 4, "user"},
               {:dot, 1, 20, 1, "."},
               {:identifier, 1, 21, 7, "profile"},
               {:rparen, 1, 28, 1, ")"},
               {:eof, 1, 29, 0, nil}
             ]
    end
  end

  describe "parser qualified functions" do
    test "parses qualified function call" do
      {:ok, ast} = Predicator.parse("JSON.stringify(value)")

      assert ast == {:function_call, "JSON.stringify", [{:identifier, "value"}]}
    end

    test "parses qualified function in complex expression" do
      {:ok, ast} = Predicator.parse("Math.pow(2, 3) + JSON.stringify(user)")

      assert ast == {
               :arithmetic,
               :add,
               {:function_call, "Math.pow", [{:literal, 2}, {:literal, 3}]},
               {:function_call, "JSON.stringify", [{:identifier, "user"}]}
             }
    end

    test "parses nested qualified function calls" do
      {:ok, ast} = Predicator.parse("Math.max(Math.abs(a), Math.abs(b))")

      assert ast == {
               :function_call,
               "Math.max",
               [
                 {:function_call, "Math.abs", [{:identifier, "a"}]},
                 {:function_call, "Math.abs", [{:identifier, "b"}]}
               ]
             }
    end
  end

  describe "JSON functions" do
    setup do
      %{functions: JSONFunctions.all_functions()}
    end

    test "JSON.stringify converts objects to JSON strings", %{functions: functions} do
      data = %{"name" => "John", "age" => 30, "active" => true}

      {:ok, result} =
        Predicator.evaluate(
          "JSON.stringify(user)",
          %{"user" => data},
          functions: functions
        )

      # Parse it back to verify it's valid JSON
      {:ok, parsed} = Jason.decode(result)
      assert parsed == data
    end

    test "JSON.stringify converts arrays to JSON", %{functions: functions} do
      {:ok, result} =
        Predicator.evaluate(
          "JSON.stringify(items)",
          %{"items" => [1, 2, "three", true]},
          functions: functions
        )

      assert result == "[1,2,\"three\",true]"
    end

    test "JSON.stringify handles primitive values", %{functions: functions} do
      test_cases = [
        {42, "42"},
        {"hello", "\"hello\""},
        {true, "true"},
        {false, "false"}
      ]

      for {input, expected} <- test_cases do
        {:ok, result} =
          Predicator.evaluate(
            "JSON.stringify(value)",
            %{"value" => input},
            functions: functions
          )

        assert result == expected
      end
    end

    test "JSON.parse converts JSON strings to values", %{functions: functions} do
      {:ok, result} =
        Predicator.evaluate(
          "JSON.parse(json)",
          %{"json" => "{\"name\":\"Alice\",\"count\":5}"},
          functions: functions
        )

      assert result == %{"name" => "Alice", "count" => 5}
    end

    test "JSON.parse handles arrays", %{functions: functions} do
      {:ok, result} =
        Predicator.evaluate(
          "JSON.parse(json)",
          %{"json" => "[1, 2, \"three\"]"},
          functions: functions
        )

      assert result == [1, 2, "three"]
    end

    test "JSON.parse handles primitive values", %{functions: functions} do
      test_cases = [
        {"42", 42},
        {"\"hello\"", "hello"},
        {"true", true},
        {"false", false},
        {"null", nil}
      ]

      for {input, expected} <- test_cases do
        {:ok, result} =
          Predicator.evaluate(
            "JSON.parse(json)",
            %{"json" => input},
            functions: functions
          )

        assert result == expected
      end
    end

    test "JSON.parse returns error for invalid JSON", %{functions: functions} do
      {:error, %{message: message}} =
        Predicator.evaluate(
          "JSON.parse(json)",
          %{"json" => "{invalid json}"},
          functions: functions
        )

      assert String.contains?(message, "Invalid JSON")
    end

    test "JSON.parse returns error for non-string input", %{functions: functions} do
      {:error, %{message: message}} =
        Predicator.evaluate(
          "JSON.parse(value)",
          %{"value" => 42},
          functions: functions
        )

      assert String.contains?(message, "expects a string")
    end

    test "round-trip JSON stringify and parse", %{functions: functions} do
      original = %{"user" => "Alice", "items" => [1, 2, 3], "active" => true}

      {:ok, result} =
        Predicator.evaluate(
          "JSON.parse(JSON.stringify(data))",
          %{"data" => original},
          functions: functions
        )

      assert result == original
    end
  end

  describe "integration tests" do
    setup do
      json_functions = JSONFunctions.all_functions()
      math_functions = MathFunctions.all_functions()

      %{functions: Map.merge(json_functions, math_functions)}
    end

    test "complex expression with multiple qualified functions", %{functions: functions} do
      context = %{
        "user" => %{"name" => "Alice", "score" => 85},
        "multiplier" => 2
      }

      {:ok, result} =
        Predicator.evaluate(
          "JSON.stringify({name: user.name, total: Math.pow(user.score, multiplier)})",
          context,
          functions: functions
        )

      {:ok, parsed} = Jason.decode(result)
      # 85^2
      assert parsed == %{"name" => "Alice", "total" => 7225.0}
    end

    test "qualified functions with conditionals", %{functions: functions} do
      {:ok, result} =
        Predicator.evaluate(
          "Math.max(score, 0) > 50 AND JSON.stringify(user) != 'null'",
          %{"score" => 75, "user" => %{"active" => true}},
          functions: functions
        )

      assert result == true
    end

    test "error handling with qualified functions", %{functions: functions} do
      {:error, %{message: message}} =
        Predicator.evaluate(
          "Math.pow('not a number', 2)",
          %{},
          functions: functions
        )

      assert String.contains?(message, "Math.pow expects two numeric arguments")
    end
  end

  describe "function precedence and scoping" do
    test "qualified functions override regular functions" do
      system_functions = %{"len" => {1, fn [s], _ctx -> {:ok, String.length(to_string(s))} end}}

      qualified_functions = %{
        "String.len" => {1, fn [s], _ctx -> {:ok, "qualified_#{String.length(to_string(s))}"} end}
      }

      functions = Map.merge(system_functions, qualified_functions)

      # Regular function
      {:ok, result1} =
        Predicator.evaluate("len(text)", %{"text" => "hello"}, functions: functions)

      assert result1 == 5

      # Qualified function
      {:ok, result2} =
        Predicator.evaluate("String.len(text)", %{"text" => "hello"}, functions: functions)

      assert result2 == "qualified_5"
    end

    test "missing qualified function returns appropriate error" do
      {:error, %{message: message}} =
        Predicator.evaluate("Unknown.function()", %{}, functions: %{})

      assert String.contains?(message, "Unknown function: Unknown.function")
    end
  end
end
