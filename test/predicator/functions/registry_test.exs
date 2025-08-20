defmodule Predicator.Functions.RegistryTest do
  use ExUnit.Case, async: false

  alias Predicator.Functions.Registry

  setup do
    # Clear registry before each test but preserve built-in functions
    Predicator.clear_custom_functions()
    :ok
  end

  describe "simple function registration" do
    test "registers and calls a simple function" do
      Registry.register_function("double", 1, fn [n], _context ->
        {:ok, n * 2}
      end)

      assert {:ok, 10} = Registry.call("double", [5], %{})
    end

    test "validates function arity" do
      Registry.register_function("add", 2, fn [a, b], _context ->
        {:ok, a + b}
      end)

      # Correct arity
      assert {:ok, 7} = Registry.call("add", [3, 4], %{})

      # Wrong arity
      assert {:error, "Function add() expects 2 arguments, got 1"} =
               Registry.call("add", [3], %{})
    end

    test "handles function errors gracefully" do
      Registry.register_function("divide", 2, fn [a, b], _context ->
        if b == 0 do
          {:error, "Division by zero"}
        else
          {:ok, a / b}
        end
      end)

      assert {:ok, 2.5} = Registry.call("divide", [5, 2], %{})
      assert {:error, "Division by zero"} = Registry.call("divide", [5, 0], %{})
    end

    test "handles function exceptions" do
      Registry.register_function("crash", 0, fn [], _context ->
        raise "Something went wrong"
      end)

      assert {:error, "Function crash() failed: Something went wrong"} =
               Registry.call("crash", [], %{})
    end

    test "returns error for unknown function" do
      assert {:error, "Unknown function: unknown"} =
               Registry.call("unknown", [], %{})
    end
  end

  describe "context-aware functions" do
    test "functions can access context" do
      Registry.register_function("user_role", 0, fn [], context ->
        {:ok, Map.get(context, "role", "guest")}
      end)

      assert {:ok, "admin"} = Registry.call("user_role", [], %{"role" => "admin"})
      assert {:ok, "guest"} = Registry.call("user_role", [], %{})
    end

    test "functions can use context for validation" do
      Registry.register_function("can_delete", 1, fn [resource_id], context ->
        user_role = Map.get(context, "role")
        user_id = Map.get(context, "user_id")
        resource_owner = Map.get(context, "resources", %{}) |> Map.get(resource_id)

        cond do
          user_role == "admin" -> {:ok, true}
          user_id == resource_owner -> {:ok, true}
          true -> {:ok, false}
        end
      end)

      context = %{
        "role" => "user",
        "user_id" => 123,
        "resources" => %{"doc1" => 123, "doc2" => 456}
      }

      assert {:ok, true} = Registry.call("can_delete", ["doc1"], context)
      assert {:ok, false} = Registry.call("can_delete", ["doc2"], context)

      admin_context = Map.put(context, "role", "admin")
      assert {:ok, true} = Registry.call("can_delete", ["doc2"], admin_context)
    end
  end

  describe "registry management" do
    test "lists registered functions" do
      Registry.register_function("func1", 1, fn [_arg], _context -> {:ok, 1} end)
      Registry.register_function("func2", 2, fn [_arg1, _arg2], _context -> {:ok, 2} end)

      functions = Registry.list_functions()
      # Should include built-in functions + 2 custom functions
      assert length(functions) >= 12

      names = Enum.map(functions, & &1.name)
      assert "func1" in names
      assert "func2" in names
      # Also check built-in functions are present
      assert "len" in names

      func1 = Enum.find(functions, &(&1.name == "func1"))
      assert func1.arity == 1
    end

    test "checks if function is registered" do
      refute Registry.function_registered?("missing")

      Registry.register_function("exists", 0, fn [], _context -> {:ok, true} end)
      assert Registry.function_registered?("exists")
    end

    test "clears registry" do
      Registry.register_function("temp", 0, fn [], _context -> {:ok, :temp} end)
      assert Registry.function_registered?("temp")

      Predicator.clear_custom_functions()
      refute Registry.function_registered?("temp")
    end
  end

  describe "error handling" do
    test "handles function that raises exception" do
      Registry.register_function("crash_func", 1, fn [_arg], _context ->
        raise "Intentional crash for testing"
      end)

      assert {:error, "Function crash_func() failed: Intentional crash for testing"} =
               Registry.call("crash_func", ["test"], %{})
    end

    test "handles function that raises different exception types" do
      Registry.register_function("runtime_error", 0, fn [], _context ->
        raise RuntimeError, "Runtime error test"
      end)

      Registry.register_function("argument_error", 0, fn [], _context ->
        raise ArgumentError, "Argument error test"
      end)

      assert {:error, "Function runtime_error() failed: Runtime error test"} =
               Registry.call("runtime_error", [], %{})

      assert {:error, "Function argument_error() failed: Argument error test"} =
               Registry.call("argument_error", [], %{})
    end

    test "handles function registration with invalid inputs" do
      # Test with invalid arity
      assert_raise FunctionClauseError, fn ->
        Registry.register_function("invalid", -1, fn [], _context -> {:ok, :test} end)
      end

      # Test with non-binary name
      assert_raise FunctionClauseError, fn ->
        Registry.register_function(:invalid_atom, 1, fn [_arg], _context ->
          {:ok, :test}
        end)
      end

      # Test with non-integer arity
      assert_raise FunctionClauseError, fn ->
        Registry.register_function("invalid", "one", fn [_arg], _context ->
          {:ok, :test}
        end)
      end
    end

    test "registry auto-starts when needed" do
      # Clear registry table completely (simulate it not existing)
      :ets.delete_all_objects(:predicator_function_registry)
      :ets.delete(:predicator_function_registry)

      # Registry should auto-start when we try to call a function
      Registry.register_function("test_auto_start", 0, fn [], _context ->
        {:ok, :started}
      end)

      assert {:ok, :started} = Registry.call("test_auto_start", [], %{})
    end
  end

  describe "registry state management" do
    test "start_registry creates table" do
      # Delete existing table
      :ets.delete_all_objects(:predicator_function_registry)
      :ets.delete(:predicator_function_registry)

      # Start registry
      assert :ok = Registry.start_registry()

      # Verify table exists (whereis returns table reference, not name)
      table_ref = :ets.whereis(:predicator_function_registry)
      assert table_ref != :undefined
    end

    test "function_registered? works correctly" do
      refute Registry.function_registered?("non_existent")

      Registry.register_function("exists", 0, fn [], _context -> {:ok, :yes} end)
      assert Registry.function_registered?("exists")

      Registry.clear_registry()
      refute Registry.function_registered?("exists")
    end

    test "list_functions returns sorted results" do
      Registry.register_function("zebra", 0, fn [], _context -> {:ok, :z} end)
      Registry.register_function("alpha", 1, fn [_arg], _context -> {:ok, :a} end)
      Registry.register_function("beta", 2, fn [_arg1, _arg2], _context -> {:ok, :b} end)

      functions = Registry.list_functions()
      names = Enum.map(functions, & &1.name)

      # Should be sorted alphabetically
      assert names == Enum.sort(names)

      # Should contain our functions plus built-ins
      assert "alpha" in names
      assert "beta" in names
      assert "zebra" in names
    end
  end

  describe "function registration edge cases" do
    test "handles function registration multiple times" do
      # Register the same function multiple times (should overwrite)
      Registry.register_function("multi_test", 1, fn [_arg], _context ->
        {:ok, "first"}
      end)

      assert {:ok, "first"} = Registry.call("multi_test", ["arg"], %{})

      # Register again with different implementation
      Registry.register_function("multi_test", 1, fn [_arg], _context ->
        {:ok, "second"}
      end)

      # Should use the latest registration
      assert {:ok, "second"} = Registry.call("multi_test", ["arg"], %{})
    end
  end

  describe "registry table management" do
    test "handles registry deletion and recreation" do
      # Register a function first
      Registry.register_function("before_delete", 0, fn [], _context -> {:ok, :before} end)

      assert {:ok, :before} = Registry.call("before_delete", [], %{})

      # Delete the entire table
      :ets.delete(:predicator_function_registry)

      # Should auto-recreate when needed
      Registry.register_function("after_delete", 0, fn [], _context -> {:ok, :after} end)
      assert {:ok, :after} = Registry.call("after_delete", [], %{})

      # Old function should be gone since table was deleted
      assert {:error, "Unknown function: before_delete"} =
               Registry.call("before_delete", [], %{})
    end

    test "function_registered? works with non-existent functions" do
      refute Registry.function_registered?("definitely_not_registered")
      refute Registry.function_registered?("")
      refute Registry.function_registered?("spaces in name")
    end

    test "list_functions returns empty list when no custom functions registered" do
      # Clear everything including built-ins
      Registry.clear_registry()

      functions = Registry.list_functions()
      assert [] = functions
    end

    test "clear_registry works when registry doesn't exist" do
      # Delete the table completely
      :ets.delete(:predicator_function_registry)

      # Should not crash
      assert :ok = Registry.clear_registry()
    end
  end

  describe "complex function implementations" do
    test "functions can access and modify context data" do
      Registry.register_function("context_reader", 1, fn [key], context ->
        case Map.get(context, key) do
          nil -> {:error, "Key not found in context"}
          value -> {:ok, "Found: #{value}"}
        end
      end)

      context = %{"test_key" => "test_value"}

      assert {:ok, "Found: test_value"} =
               Registry.call("context_reader", ["test_key"], context)

      assert {:error, "Key not found in context"} =
               Registry.call("context_reader", ["missing_key"], context)
    end

    test "functions can handle complex data structures" do
      Registry.register_function("process_map", 1, fn [data], _context ->
        case data do
          map when is_map(map) -> {:ok, Map.keys(map)}
          list when is_list(list) -> {:ok, Enum.count(list)}
          _other -> {:error, "Expected map or list"}
        end
      end)

      assert {:ok, ["key1", "key2"]} =
               Registry.call("process_map", [%{"key1" => 1, "key2" => 2}], %{})

      assert {:ok, 3} =
               Registry.call("process_map", [[1, 2, 3]], %{})

      assert {:error, "Expected map or list"} =
               Registry.call("process_map", ["string"], %{})
    end

    test "functions can raise exceptions that get caught" do
      Registry.register_function("exception_thrower", 0, fn [], _context ->
        raise ArgumentError, "This function always fails"
      end)

      assert {:error, message} = Registry.call("exception_thrower", [], %{})
      assert message =~ "This function always fails"
      assert message =~ "exception_thrower() failed:"
    end

    test "functions with zero arity work correctly" do
      Registry.register_function("zero_arity", 0, fn [], _context ->
        {:ok, "no arguments needed"}
      end)

      assert {:ok, "no arguments needed"} = Registry.call("zero_arity", [], %{})

      # Wrong arity should fail
      assert {:error, "Function zero_arity() expects 0 arguments, got 1"} =
               Registry.call("zero_arity", ["arg"], %{})
    end

    test "functions with high arity work correctly" do
      Registry.register_function("five_args", 5, fn [a, b, c, d, e], _context ->
        {:ok, a + b + c + d + e}
      end)

      assert {:ok, 15} = Registry.call("five_args", [1, 2, 3, 4, 5], %{})

      assert {:error, "Function five_args() expects 5 arguments, got 3"} =
               Registry.call("five_args", [1, 2, 3], %{})
    end
  end
end
