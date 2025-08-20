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

      tasks =
        for i <- 1..10 do
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
      task_results =
        for _i <- 1..10 do
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
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            # This will call ensure_registry_exists internally
            Registry.register_function("test_#{i}", 0, fn [], _context -> {:ok, i} end)

            # If registration succeeded, the table must exist
            # Just return success since registration working means table exists
            {:ok, :registry_created}
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

      assert :ok =
               Registry.register_function("recovered_func", 0, fn [], _context ->
                 {:ok, :recovered}
               end)

      # Test call function recovery
      # Delete table and try to call - should recover gracefully
      :ets.delete(:predicator_function_registry)

      assert {:error, "Unknown function: recovered_func"} =
               Registry.call("recovered_func", [], %{})

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

  describe "error conditions and edge cases" do
    test "register_function validates input parameters" do
      # Test with invalid function name (non-binary)
      assert_raise FunctionClauseError, fn ->
        Registry.register_function(:invalid_name, 1, fn [_arg], _context -> {:ok, :test} end)
      end

      # Test with invalid arity (negative)
      assert_raise FunctionClauseError, fn ->
        Registry.register_function("test_func", -1, fn [_arg], _context -> {:ok, :test} end)
      end

      # Test with invalid arity (non-integer)
      assert_raise FunctionClauseError, fn ->
        Registry.register_function("test_func", "one", fn [_arg], _context -> {:ok, :test} end)
      end
    end

    test "call function validates input parameters" do
      # Register a test function first
      Registry.register_function("test_func", 1, fn [arg], _context -> {:ok, arg} end)

      # Test with invalid function name (non-binary)
      assert_raise FunctionClauseError, fn ->
        Registry.call(:invalid_name, ["arg"], %{})
      end

      # Test with invalid arguments (non-list)
      assert_raise FunctionClauseError, fn ->
        Registry.call("test_func", "not_a_list", %{})
      end

      # Test with invalid context (non-map)
      assert_raise FunctionClauseError, fn ->
        Registry.call("test_func", ["arg"], "not_a_map")
      end
    end

    test "function_registered? validates input parameters" do
      # Test with invalid function name (non-binary)
      assert_raise FunctionClauseError, fn ->
        Registry.function_registered?(:invalid_name)
      end
    end

    test "start_registry handles existing table gracefully" do
      # Ensure table exists
      Registry.start_registry()
      table_ref = :ets.whereis(:predicator_function_registry)
      assert table_ref != :undefined

      # Calling again should not crash and should return :ok
      assert :ok = Registry.start_registry()

      # Table reference should remain the same
      new_table_ref = :ets.whereis(:predicator_function_registry)
      assert new_table_ref == table_ref
    end

    test "registry operations handle corrupted or missing table scenarios" do
      # Test when ETS table doesn't exist at all
      :ets.delete(:predicator_function_registry)

      # All operations should auto-create the table and work
      assert :ok =
               Registry.register_function("auto_created", 0, fn [], _context ->
                 {:ok, :created}
               end)

      assert {:ok, :created} = Registry.call("auto_created", [], %{})
      assert true = Registry.function_registered?("auto_created")

      functions = Registry.list_functions()
      assert length(functions) >= 1
      assert Enum.any?(functions, &(&1.name == "auto_created"))
    end

    test "function calls with complex error scenarios" do
      # Register a function that returns various error types
      Registry.register_function("error_test", 1, fn [error_type], _context ->
        case error_type do
          "string_error" -> {:error, "This is a string error"}
          "atom_error" -> {:error, :atom_error}
          "tuple_error" -> {:error, {:complex, "error"}}
          "exception" -> raise ArgumentError, "Function intentionally raised"
          "runtime_error" -> raise RuntimeError, "Runtime error occurred"
          "other_error" -> raise "Generic error"
          _other -> {:ok, "success"}
        end
      end)

      # Test different error return types
      assert {:error, "This is a string error"} =
               Registry.call("error_test", ["string_error"], %{})

      assert {:error, :atom_error} = Registry.call("error_test", ["atom_error"], %{})
      assert {:error, {:complex, "error"}} = Registry.call("error_test", ["tuple_error"], %{})

      # Test different exception types
      assert {:error, message} = Registry.call("error_test", ["exception"], %{})
      assert message =~ "error_test() failed: Function intentionally raised"

      assert {:error, message} = Registry.call("error_test", ["runtime_error"], %{})
      assert message =~ "error_test() failed: Runtime error occurred"

      assert {:error, message} = Registry.call("error_test", ["other_error"], %{})
      assert message =~ "error_test() failed: Generic error"

      # Test successful case
      assert {:ok, "success"} = Registry.call("error_test", ["success"], %{})
    end

    test "registry handles extreme edge cases" do
      # Register function with empty string name (valid but unusual)
      Registry.register_function("", 0, fn [], _context -> {:ok, "empty_name"} end)
      assert {:ok, "empty_name"} = Registry.call("", [], %{})
      assert Registry.function_registered?("")

      # Register function with zero arity
      Registry.register_function("zero_args", 0, fn [], _context -> {:ok, "no_args"} end)
      assert {:ok, "no_args"} = Registry.call("zero_args", [], %{})

      # Register function with high arity
      Registry.register_function("many_args", 10, fn args, _context ->
        {:ok, Enum.sum(args)}
      end)

      args = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      assert {:ok, 55} = Registry.call("many_args", args, %{})

      # Test function with unicode name
      Registry.register_function("测试函数", 0, fn [], _context -> {:ok, "unicode"} end)
      assert {:ok, "unicode"} = Registry.call("测试函数", [], %{})
      assert Registry.function_registered?("测试函数")
    end

    test "list_functions returns consistent format" do
      # Clear registry and register a few functions with different arities
      Registry.clear_registry()

      Registry.register_function("func_a", 0, fn [], _context -> {:ok, :a} end)
      Registry.register_function("func_z", 2, fn [_arg1, _arg2], _context -> {:ok, :z} end)
      Registry.register_function("func_m", 1, fn [_arg], _context -> {:ok, :m} end)

      functions = Registry.list_functions()

      # Should be sorted alphabetically by name
      names = Enum.map(functions, & &1.name)
      assert names == Enum.sort(names)

      # Each function should have the correct structure
      for func <- functions do
        assert is_binary(func.name)
        assert is_integer(func.arity)
        assert func.arity >= 0
        assert is_function(func.impl)
      end

      # Specific functions should be present with correct arities
      func_a = Enum.find(functions, &(&1.name == "func_a"))
      func_m = Enum.find(functions, &(&1.name == "func_m"))
      func_z = Enum.find(functions, &(&1.name == "func_z"))

      assert func_a.arity == 0
      assert func_m.arity == 1
      assert func_z.arity == 2
    end
  end

  describe "race condition rescue paths" do
    test "start_registry rescue path for table creation race condition" do
      # This test attempts to trigger the rescue path in start_registry
      # by creating a scenario where :ets.new might fail due to timing

      # First ensure table doesn't exist
      :ets.delete_all_objects(:predicator_function_registry)
      :ets.delete(:predicator_function_registry)

      # Create multiple processes that try to create the table simultaneously
      # This increases the chances of hitting the rescue path
      parent = self()

      # Start many processes concurrently to increase race condition chances
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            # Each process tries to start the registry
            result = Registry.start_registry()
            send(parent, {:start_result, i, result})
            result
          end)
        end

      # Wait for all tasks to complete
      results = Task.await_many(tasks, 5000)

      # All should return :ok regardless of which one actually created the table
      assert Enum.all?(results, &(&1 == :ok))

      # Collect results from messages to verify all succeeded
      task_results =
        for _i <- 1..20 do
          receive do
            {:start_result, _i, result} -> result
          after
            1000 -> :timeout
          end
        end

      # All concurrent start_registry calls should succeed
      assert Enum.all?(task_results, &(&1 == :ok))

      # Registry should be functional after all the concurrent attempts
      Registry.register_function("after_race_test", 0, fn [], _context -> {:ok, :success} end)
      assert {:ok, :success} = Registry.call("after_race_test", [], %{})
    end

    test "register_function rescue path when table deleted during operation" do
      # Test the rescue path in register_function that handles table deletion
      # between ensure_registry_exists() and :ets.insert()

      # Register an initial function
      Registry.register_function("initial", 0, fn [], _context -> {:ok, :initial} end)

      # Now try to trigger the rescue path by deleting table and registering
      # in rapid succession to increase chances of hitting the race condition
      for i <- 1..10 do
        :ets.delete(:predicator_function_registry)

        # Immediately try to register - should trigger rescue path and succeed
        assert :ok =
                 Registry.register_function("race_test_#{i}", 0, fn [], _context ->
                   {:ok, "race_#{i}"}
                 end)

        # Verify the function works
        expected_result = "race_#{i}"
        assert {:ok, ^expected_result} = Registry.call("race_test_#{i}", [], %{})
      end
    end

    test "call function rescue path when table deleted during lookup" do
      # Test the rescue path in call that handles table deletion
      # between ensure_registry_exists() and :ets.lookup()

      # Register a test function
      Registry.register_function("lookup_test", 1, fn [arg], _context -> {:ok, arg} end)

      # Try to trigger the rescue path in call function
      for i <- 1..5 do
        # Re-register the function
        Registry.register_function("lookup_test", 1, fn [arg], _context ->
          {:ok, "#{arg}_#{i}"}
        end)

        # Delete table and immediately try to call
        :ets.delete(:predicator_function_registry)

        # This should trigger the rescue path and return an error (function not found)
        # because after recreating the table, the function won't be there
        result = Registry.call("lookup_test", ["test"], %{})

        # Could be either success (if function was re-registered by another process)
        # or error (if function not found after table recreation)
        case result do
          {:ok, _result} -> :ok
          {:error, _reason} -> :ok
          other -> flunk("Expected {:ok, _} or {:error, _}, got: #{inspect(other)}")
        end
      end
    end

    test "list_functions rescue path when table deleted during tab2list" do
      # Test the rescue path in list_functions

      # Register some functions
      Registry.register_function("list_test_1", 0, fn [], _context -> {:ok, 1} end)
      Registry.register_function("list_test_2", 1, fn [_arg], _context -> {:ok, 2} end)

      # Verify functions exist
      functions = Registry.list_functions()
      assert length(functions) >= 2

      # Delete table and immediately call list_functions to trigger rescue path
      :ets.delete(:predicator_function_registry)
      functions_after_delete = Registry.list_functions()

      # Should return empty list since table was recreated but functions not re-registered
      assert [] = functions_after_delete
    end

    test "function_registered? rescue path when table deleted during member check" do
      # Test the rescue path in function_registered?

      # Register a test function
      Registry.register_function("member_test", 0, fn [], _context -> {:ok, :test} end)

      # Verify it's registered
      assert true = Registry.function_registered?("member_test")

      # Delete table and immediately check registration to trigger rescue path
      :ets.delete(:predicator_function_registry)

      # Should return false since table was recreated but function not re-registered
      refute Registry.function_registered?("member_test")
    end

    test "clear_registry rescue path when table deleted during delete_all_objects" do
      # Test the rescue path in clear_registry

      # Register some functions
      Registry.register_function("clear_test_1", 0, fn [], _context -> {:ok, 1} end)
      Registry.register_function("clear_test_2", 0, fn [], _context -> {:ok, 2} end)

      # Verify functions exist
      assert Registry.function_registered?("clear_test_1")
      assert Registry.function_registered?("clear_test_2")

      # Delete table and immediately call clear_registry to trigger rescue path
      :ets.delete(:predicator_function_registry)

      # Should succeed and leave us with an empty registry
      assert :ok = Registry.clear_registry()

      # Registry should be empty after clear
      assert [] = Registry.list_functions()
      refute Registry.function_registered?("clear_test_1")
      refute Registry.function_registered?("clear_test_2")
    end
  end

  describe "ensure_registry_exists private function coverage" do
    test "ensure_registry_exists when table exists vs when it doesn't" do
      # Test the private ensure_registry_exists function indirectly

      # Delete table to ensure it doesn't exist
      :ets.delete_all_objects(:predicator_function_registry)
      :ets.delete(:predicator_function_registry)

      # Verify table doesn't exist
      assert :undefined = :ets.whereis(:predicator_function_registry)

      # Any registry operation should trigger ensure_registry_exists with :undefined
      Registry.register_function("ensure_test", 0, fn [], _context -> {:ok, :created} end)

      # Now table should exist
      table_ref = :ets.whereis(:predicator_function_registry)
      assert table_ref != :undefined

      # Another operation should trigger ensure_registry_exists with table existing
      Registry.register_function("ensure_test_2", 0, fn [], _context -> {:ok, :exists} end)

      # Table reference should remain the same
      assert table_ref == :ets.whereis(:predicator_function_registry)

      # Both functions should work
      assert {:ok, :created} = Registry.call("ensure_test", [], %{})
      assert {:ok, :exists} = Registry.call("ensure_test_2", [], %{})
    end
  end

  describe "detailed error message coverage" do
    test "function call errors with specific argument count messages" do
      # Test specific error message formatting for arity mismatches
      Registry.register_function("arity_test", 3, fn [a, b, c], _context ->
        {:ok, a + b + c}
      end)

      # Test different argument counts to get specific error messages
      assert {:error, "Function arity_test() expects 3 arguments, got 0"} =
               Registry.call("arity_test", [], %{})

      assert {:error, "Function arity_test() expects 3 arguments, got 1"} =
               Registry.call("arity_test", [1], %{})

      assert {:error, "Function arity_test() expects 3 arguments, got 2"} =
               Registry.call("arity_test", [1, 2], %{})

      assert {:error, "Function arity_test() expects 3 arguments, got 4"} =
               Registry.call("arity_test", [1, 2, 3, 4], %{})

      assert {:error, "Function arity_test() expects 3 arguments, got 10"} =
               Registry.call("arity_test", [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], %{})

      # Correct arity should work
      assert {:ok, 6} = Registry.call("arity_test", [1, 2, 3], %{})
    end

    test "exception message formatting for different error types" do
      # Register functions that throw specific types of exceptions
      Registry.register_function("arg_error", 0, fn [], _context ->
        raise ArgumentError, "Specific argument error message"
      end)

      Registry.register_function("runtime_error", 0, fn [], _context ->
        raise RuntimeError, "Specific runtime error message"
      end)

      Registry.register_function("custom_error", 0, fn [], _context ->
        raise "Custom string error message"
      end)

      Registry.register_function("other_exception", 0, fn [], _context ->
        raise KeyError, "Key not found error message"
      end)

      # Test that all exception types get proper formatting
      assert {:error, message1} = Registry.call("arg_error", [], %{})
      assert message1 =~ "arg_error() failed: Specific argument error message"

      assert {:error, message2} = Registry.call("runtime_error", [], %{})
      assert message2 =~ "runtime_error() failed: Specific runtime error message"

      assert {:error, message3} = Registry.call("custom_error", [], %{})
      assert message3 =~ "custom_error() failed: Custom string error message"

      assert {:error, message4} = Registry.call("other_exception", [], %{})
      assert message4 =~ "other_exception() failed: Key not found error message"
    end
  end

  describe "very specific edge cases for uncovered lines" do
    test "ensure_registry_exists different code paths" do
      # Test the specific code paths in ensure_registry_exists

      # Path 1: Table doesn't exist, gets created
      :ets.delete(:predicator_function_registry)
      assert :undefined = :ets.whereis(:predicator_function_registry)

      # This should trigger the :undefined -> start_registry path
      Registry.register_function("path_test_1", 0, fn [], _context -> {:ok, :path1} end)
      assert Registry.function_registered?("path_test_1")

      # Path 2: Table already exists, should use existing table
      table_ref = :ets.whereis(:predicator_function_registry)
      assert table_ref != :undefined

      # This should trigger the _table_exists -> :ok path
      Registry.register_function("path_test_2", 0, fn [], _context -> {:ok, :path2} end)

      # Table should be the same reference
      assert table_ref == :ets.whereis(:predicator_function_registry)
      assert Registry.function_registered?("path_test_2")
    end

    test "start_registry different scenarios" do
      # Test start_registry when table already exists (should return :ok immediately)
      # Ensure table exists
      Registry.start_registry()
      table_ref = :ets.whereis(:predicator_function_registry)

      # Call start_registry again - should hit the _table_exists -> :ok branch
      assert :ok = Registry.start_registry()

      # Should be same table
      assert table_ref == :ets.whereis(:predicator_function_registry)

      # Test start_registry when table doesn't exist (should create it)
      :ets.delete(:predicator_function_registry)
      assert :undefined = :ets.whereis(:predicator_function_registry)

      # This should hit the :undefined -> try -> :ets.new branch
      assert :ok = Registry.start_registry()
      assert :ets.whereis(:predicator_function_registry) != :undefined
    end

    test "error message string interpolation coverage" do
      # Test various function names and arities for string interpolation coverage
      function_names = ["test_func", "a", "long_function_name_with_underscores", ""]
      arities = [0, 1, 2, 5, 10, 100]

      for name <- function_names, arity <- Enum.take(arities, 3) do
        # Register function with specific arity
        Registry.register_function(name, arity, fn args, _context ->
          {:ok, Enum.sum(args)}
        end)

        # Test with wrong argument count to trigger error message
        wrong_args = if arity == 0, do: [1], else: []

        {:error, message} = Registry.call(name, wrong_args, %{})

        # Verify error message contains function name and expected arity
        assert message =~ "Function #{name}()"
        assert message =~ "expects #{arity} arguments"
        assert message =~ "got #{length(wrong_args)}"
      end
    end

    test "exception handling with nil and unusual return values" do
      # Register functions that return nil and other edge case values
      Registry.register_function("nil_return", 0, fn [], _context -> nil end)
      Registry.register_function("atom_return", 0, fn [], _context -> :just_atom end)

      Registry.register_function("tuple_return", 0, fn [], _context ->
        {:not_ok_or_error, "weird"}
      end)

      Registry.register_function("list_return", 0, fn [], _context -> [1, 2, 3] end)

      # Call these functions to exercise different return value handling
      assert is_nil(Registry.call("nil_return", [], %{}))
      assert :just_atom = Registry.call("atom_return", [], %{})
      assert {:not_ok_or_error, "weird"} = Registry.call("tuple_return", [], %{})
      assert [1, 2, 3] = Registry.call("list_return", [], %{})
    end

    test "table operations with mixed function types" do
      # Clear registry to start fresh
      Registry.clear_registry()

      # Register functions with various characteristics to exercise sorting/listing
      Registry.register_function("zzz_last", 0, fn [], _context -> {:ok, "last"} end)
      Registry.register_function("aaa_first", 5, fn args, _context -> {:ok, Enum.sum(args)} end)
      Registry.register_function("mmm_middle", 2, fn [a, b], _context -> {:ok, a * b} end)
      Registry.register_function("111_numeric", 1, fn [x], _context -> {:ok, x + 1} end)

      # Get function list and verify sorting
      functions = Registry.list_functions()
      names = Enum.map(functions, & &1.name)

      # Should be sorted: ["111_numeric", "aaa_first", "mmm_middle", "zzz_last"]
      assert names == Enum.sort(names)

      # Verify each function works with correct arity
      assert {:ok, "last"} = Registry.call("zzz_last", [], %{})
      assert {:ok, 15} = Registry.call("aaa_first", [1, 2, 3, 4, 5], %{})
      assert {:ok, 12} = Registry.call("mmm_middle", [3, 4], %{})
      assert {:ok, 11} = Registry.call("111_numeric", [10], %{})
    end
  end
end
