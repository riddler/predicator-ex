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

  describe "concurrent table creation (race condition fixes)" do
    test "start_registry is idempotent and safe to call multiple times" do
      # Delete the table completely to start fresh
      :ets.delete_all_objects(:predicator_function_registry)
      :ets.delete(:predicator_function_registry)

      # Should succeed the first time
      assert :ok = Registry.start_registry()
      
      # Should succeed when called again (table already exists)
      assert :ok = Registry.start_registry()
      assert :ok = Registry.start_registry()
      
      # Table should still be functional
      Registry.register_function("test", 0, fn [], _context -> {:ok, :works} end)
      assert {:ok, :works} = Registry.call("test", [], %{})
    end

    test "concurrent start_registry calls don't crash" do
      # Delete the table completely to start fresh
      :ets.delete_all_objects(:predicator_function_registry)
      :ets.delete(:predicator_function_registry)

      # Simulate concurrent table creation by starting multiple processes
      parent = self()
      
      tasks = for i <- 1..10 do
        Task.async(fn ->
          result = Registry.start_registry()
          send(parent, {:task_result, i, result})
          result
        end)
      end

      # All tasks should complete successfully
      results = Task.await_many(tasks, 5000)
      assert Enum.all?(results, &(&1 == :ok))

      # Collect all results from messages
      task_results = for _i <- 1..10 do
        receive do
          {:task_result, _i, result} -> result
        after 
          1000 -> :timeout
        end
      end

      # All concurrent calls should have succeeded
      assert Enum.all?(task_results, &(&1 == :ok))
      
      # Table should be functional after concurrent creation attempts
      Registry.register_function("concurrent_test", 0, fn [], _context -> {:ok, :success} end)
      assert {:ok, :success} = Registry.call("concurrent_test", [], %{})
    end

    test "start_registry handles race condition between check and creation" do
      # This test verifies the specific race condition fix where multiple processes
      # see :undefined from whereis() but only one can successfully create the table
      
      # Delete the table completely
      :ets.delete_all_objects(:predicator_function_registry)
      :ets.delete(:predicator_function_registry)

      # Verify table doesn't exist
      assert :undefined = :ets.whereis(:predicator_function_registry)

      # Create a scenario where we manually test the race condition path
      # First call should create the table
      assert :ok = Registry.start_registry()
      
      # Verify table now exists  
      table_ref = :ets.whereis(:predicator_function_registry)
      assert table_ref != :undefined
      
      # Second call should handle the "table already exists" case gracefully
      assert :ok = Registry.start_registry()
      
      # Table should still be the same and functional
      table_ref_after = :ets.whereis(:predicator_function_registry)
      assert table_ref_after != :undefined
      assert table_ref_after == table_ref
    end

    test "ensure_registry_exists works correctly with concurrent access" do
      # Delete the table to test ensure_registry_exists creating it
      :ets.delete_all_objects(:predicator_function_registry)
      :ets.delete(:predicator_function_registry)

      # Verify table doesn't exist initially
      assert :undefined = :ets.whereis(:predicator_function_registry)

      # Test that multiple concurrent calls to ensure_registry_exists work
      # by having each task try to register and immediately verify the table exists
      tasks = for i <- 1..5 do
        Task.async(fn ->
          # This will call ensure_registry_exists internally
          Registry.register_function("test_#{i}", 0, fn [], _context -> {:ok, i} end)
          
          # Verify that after registration, the table definitely exists
          case :ets.whereis(:predicator_function_registry) do
            :undefined -> {:error, "Registry not created after registration"}
            _table_ref -> {:ok, :registry_created}
          end
        end)
      end

      results = Task.await_many(tasks, 5000)
      
      # All tasks should have successfully created/found the registry
      expected_results = List.duplicate({:ok, :registry_created}, 5)
      assert Enum.sort(results) == Enum.sort(expected_results)
      
      # Verify the table is still functional by testing a simple operation
      Registry.register_function("final_test", 0, fn [], _context -> {:ok, :works} end)
      assert {:ok, :works} = Registry.call("final_test", [], %{})
    end

    test "all registry functions handle table deletion between check and operation" do
      # This test verifies that all Registry functions can recover from race conditions
      # where the ETS table gets deleted between ensure_registry_exists() and the actual ETS operation
      
      # First register a test function
      Registry.register_function("test_func", 1, fn [x], _context -> {:ok, x} end)
      
      # Test register_function recovery
      # Delete table and try to register - should recover gracefully
      :ets.delete(:predicator_function_registry)
      assert :ok = Registry.register_function("recovered_func", 0, fn [], _context -> {:ok, :recovered} end)
      
      # Test call function recovery
      # Delete table and try to call - should recover gracefully
      :ets.delete(:predicator_function_registry)
      assert {:error, "Unknown function: recovered_func"} = Registry.call("recovered_func", [], %{})
      
      # Register the function again and test successful call after recovery
      Registry.register_function("recovered_func", 0, fn [], _context -> {:ok, :recovered} end)
      assert {:ok, :recovered} = Registry.call("recovered_func", [], %{})
      
      # Test function_registered? recovery
      :ets.delete(:predicator_function_registry)
      refute Registry.function_registered?("recovered_func")
      
      # Test list_functions recovery
      :ets.delete(:predicator_function_registry)
      assert [] = Registry.list_functions()
      
      # Test clear_registry recovery
      :ets.delete(:predicator_function_registry)
      assert :ok = Registry.clear_registry()
      
      # Verify table is functional after all operations
      Registry.register_function("final_check", 0, fn [], _context -> {:ok, :all_good} end)
      assert {:ok, :all_good} = Registry.call("final_check", [], %{})
    end
  end
end
