defmodule PredicatorEdgeCasesTest do
  use ExUnit.Case, async: true

  import Predicator
  alias Predicator.Functions.{Registry, SystemFunctions}

  setup do
    # Ensure built-in functions are available
    Registry.clear_registry()
    SystemFunctions.register_all()
    :ok
  end

  describe "main API edge cases" do
    test "handles empty expressions" do
      assert {:error, _message} = evaluate("")
      assert {:error, _message} = evaluate("   ")
      assert {:error, _message} = evaluate("\n\t")
    end

    test "handles very complex nested expressions" do
      complex_expr = """
      ((len(upper(name)) > 5 AND age >= 18) OR
       (role IN ["admin", "super_admin"] AND
        max(score1, score2) > 80)) AND
      NOT (status = "banned")
      """

      context = %{
        "name" => "john_doe",
        "age" => 25,
        "role" => "admin",
        "score1" => 85,
        "score2" => 90,
        "status" => "active"
      }

      assert {:ok, true} = evaluate(complex_expr, context)
    end

    test "handles expressions with all supported data types" do
      context = %{
        "str" => "hello",
        "num" => 42,
        "bool" => true,
        "list" => [1, 2, 3],
        "date" => ~D[2024-01-15]
      }

      # Test each type
      assert {:ok, "hello"} = evaluate("str", context)
      assert {:ok, 42} = evaluate("num", context)
      assert {:ok, true} = evaluate("bool", context)
      assert {:ok, [1, 2, 3]} = evaluate("list", context)
      assert {:ok, ~D[2024-01-15]} = evaluate("date", context)
    end

    test "handles function calls with all data types" do
      context = %{
        "date" => ~D[2024-03-15],
        "datetime" => ~U[2024-03-15 14:30:00Z]
      }

      assert {:ok, 5} = evaluate("len(\"hello\")", context)
      assert {:ok, 10} = evaluate("max(5, 10)", context)
      assert {:ok, 2024} = evaluate("year(date)", context)
      assert {:ok, 2024} = evaluate("year(datetime)", context)
    end

    test "handles mixed string and evaluate calls" do
      # Test that both string expressions and pre-compiled instructions work
      instructions = [["lit", 42]]

      assert {:ok, 42} = evaluate(instructions)
      assert {:ok, 42} = evaluate("42")
    end

    test "handles custom functions with errors" do
      # Register a function that can return errors
      register_function("validate_email", 1, fn [email], _context ->
        if is_binary(email) and String.contains?(email, "@") do
          {:ok, true}
        else
          {:error, "Invalid email format"}
        end
      end)

      assert {:ok, true} = evaluate("validate_email(\"user@example.com\")")
      assert {:error, "Invalid email format"} = evaluate("validate_email(\"invalid\")")
      assert {:error, "Invalid email format"} = evaluate("validate_email(123)")
    end

    test "handles context with nil values" do
      context = %{
        "nullable_field" => nil,
        "empty_string" => "",
        "zero_number" => 0
      }

      # When loading a variable that exists but has nil value, it should return :undefined
      # This matches the evaluator's behavior for nil context values
      assert {:ok, :undefined} = evaluate("nullable_field", context)
      assert {:ok, ""} = evaluate("empty_string", context)
      assert {:ok, 0} = evaluate("zero_number", context)

      # Test comparisons with nil - comparing nil values returns :undefined in the evaluator
      assert {:ok, :undefined} = evaluate("nullable_field = nil", context)
      assert {:ok, :undefined} = evaluate("empty_string = nil", context)
    end

    test "handles very long variable names" do
      long_var_name = String.duplicate("very_long_variable_name_", 10)
      context = %{long_var_name => "test_value"}

      assert {:ok, "test_value"} = evaluate(long_var_name, context)
    end

    test "handles expressions with unicode characters" do
      context = %{
        "name" => "José María",
        "emoji" => "🚀",
        "japanese" => "こんにちは"
      }

      assert {:ok, "José María"} = evaluate("name", context)
      assert {:ok, "🚀"} = evaluate("emoji", context)
      assert {:ok, "こんにちは"} = evaluate("japanese", context)

      # Test string functions with unicode
      # José María = 10 chars
      assert {:ok, 10} = evaluate("len(name)", context)
      # emoji = 1 char
      assert {:ok, 1} = evaluate("len(emoji)", context)
    end
  end

  describe "function registry integration" do
    test "handles function overrides" do
      # Register a custom version of a built-in function name
      register_function("len", 1, fn [_value], _context ->
        {:ok, "custom_len_result"}
      end)

      # Should use the custom version (last registered wins)
      assert {:ok, "custom_len_result"} = evaluate("len(\"anything\")")

      # Clear and re-register built-ins to restore normal behavior
      clear_custom_functions()
      assert {:ok, 8} = evaluate("len(\"restored\")")
    end

    test "handles function registry state across tests" do
      # Register a test function
      register_function("test_func", 0, fn [], _context -> {:ok, :test} end)
      assert {:ok, :test} = evaluate("test_func()")

      # Clear functions
      clear_custom_functions()

      # Function should be gone but built-ins should remain
      assert {:error, _message} = evaluate("test_func()")
      # built-in should work
      assert {:ok, 4} = evaluate("len(\"test\")")
    end

    test "handles function listing with mixed types" do
      register_function("custom1", 1, fn [_arg], _context -> {:ok, 1} end)
      register_function("custom2", 2, fn [_arg1, _arg2], _context -> {:ok, 2} end)

      functions = list_custom_functions()

      # Should include built-ins + custom functions
      names = Enum.map(functions, & &1.name)
      assert "custom1" in names
      assert "custom2" in names
      # built-in
      assert "len" in names
      # built-in
      assert "max" in names

      # Should have correct arities
      custom1 = Enum.find(functions, &(&1.name == "custom1"))
      custom2 = Enum.find(functions, &(&1.name == "custom2"))
      len_func = Enum.find(functions, &(&1.name == "len"))

      assert custom1.arity == 1
      assert custom2.arity == 2
      assert len_func.arity == 1
    end
  end

  describe "error message quality" do
    test "provides helpful error messages for parsing errors" do
      result = evaluate("1 +")
      assert {:error, message} = result
      assert message =~ "Unexpected character" or message =~ "Expected"
    end

    test "provides helpful error messages for function errors" do
      result = evaluate("unknown_function()")
      assert {:error, message} = result
      assert message =~ "Unknown function"
      assert message =~ "unknown_function"
    end

    test "provides helpful error messages for type errors" do
      result = evaluate("len(123)")
      assert {:error, message} = result
      assert message =~ "expects a string"
    end

    test "provides helpful error messages for arity errors" do
      result = evaluate("len()")
      assert {:error, message} = result
      assert message =~ "expects 1 arguments, got 0"
    end

    test "provides helpful error messages for invalid syntax" do
      invalid_expressions = [
        "1 + + 2",
        "func(,)",
        "AND OR",
        "1 = = 2"
      ]

      for expr <- invalid_expressions do
        result = evaluate(expr)
        assert {:error, _message} = result
      end
    end
  end
end
