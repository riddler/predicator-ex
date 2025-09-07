defmodule FunctionCallsIntegrationTest do
  use ExUnit.Case, async: false

  import Predicator

  describe "function calls end-to-end" do
    test "evaluates simple string function" do
      assert {:ok, 5} = evaluate("len(\"hello\")")
    end

    test "evaluates function with variable" do
      context = %{"name" => "world"}
      assert {:ok, 5} = evaluate("len(name)", context)
    end

    test "evaluates function in comparison" do
      context = %{"name" => "alice"}
      assert {:ok, true} = evaluate("len(name) > 3", context)
    end

    test "evaluates nested functions" do
      context = %{"name" => " hello "}
      assert {:ok, 5} = evaluate("len(trim(name))", context)
    end

    test "evaluates numeric functions" do
      assert {:ok, 10} = evaluate("Math.max(5, 10)")
      assert {:ok, 5} = evaluate("Math.min(5, 10)")

      context = %{"negative_val" => -10}
      assert {:ok, 10} = evaluate("Math.abs(negative_val)", context)
    end

    test "evaluates date functions" do
      context = %{"created_at" => ~D[2024-03-15]}
      assert {:ok, 2024} = evaluate("Date.year(created_at)", context)
      assert {:ok, 3} = evaluate("Date.month(created_at)", context)
      assert {:ok, 15} = evaluate("Date.day(created_at)", context)
    end

    test "evaluates string functions" do
      context = %{"title" => "hello world"}
      assert {:ok, "HELLO WORLD"} = evaluate("upper(title)", context)
      assert {:ok, "hello world"} = evaluate("lower(upper(title))", context)
    end

    test "evaluates function with multiple arguments" do
      assert {:ok, 15} = evaluate("Math.max(10, 15)")

      context = %{"a" => 8, "b" => 12}
      assert {:ok, 12} = evaluate("Math.max(a, b)", context)
    end

    test "function in logical expression" do
      context = %{"password" => "secret123"}
      assert {:ok, true} = evaluate("len(password) >= 8 AND len(password) <= 20", context)
    end

    test "returns error for unknown function" do
      assert {:error, _msg} = evaluate("unknown(123)")
    end

    test "returns error for wrong argument count" do
      assert {:error, _msg} = evaluate("len()")
      assert {:error, _msg} = evaluate(~s|len("a", "b")|)
    end

    test "returns error for wrong argument type" do
      assert {:error, _msg} = evaluate("len(123)")
    end
  end

  describe "function calls decompilation" do
    test "decompiles simple function call" do
      {:ok, ast} = parse("len(name)")
      assert decompile(ast) == "len(name)"
    end

    test "decompiles function with multiple arguments" do
      {:ok, ast} = parse("max(a, b)")
      assert decompile(ast) == "max(a, b)"
    end

    test "decompiles nested function calls" do
      {:ok, ast} = parse("upper(trim(name))")
      assert decompile(ast) == "upper(trim(name))"
    end

    test "decompiles function in expression" do
      {:ok, ast} = parse("len(name) > 5")
      assert decompile(ast) == "len(name) > 5"
    end
  end
end
