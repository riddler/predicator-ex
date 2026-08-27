defmodule PredicatorFunctionsTest do
  use ExUnit.Case, async: true

  describe "custom functions" do
    test "evaluates custom functions with evaluate/3" do
      custom_functions = %{
        "double" => {1, fn [n], _context -> {:ok, n * 2} end},
        "add" => {2, fn [a, b], _context -> {:ok, a + b} end}
      }

      # Test single-argument function
      assert Predicator.evaluate("double(21)", %{}, functions: custom_functions) == {:ok, 42}

      # Test with context variable
      assert Predicator.evaluate("double(limit)", %{"limit" => 25}, functions: custom_functions) ==
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
                  operation: :function_call,
                  position: {1, 1}
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
        "get_user_role" =>
          {0, fn [], context -> {:ok, Map.get(context.data, "role", "guest")} end},
        "multiply_by_factor" =>
          {1,
           fn [n], context ->
             factor = Map.get(context.data, "factor", 1)
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
end
