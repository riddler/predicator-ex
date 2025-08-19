defmodule CustomFunctionsIntegrationTest do
  use ExUnit.Case, async: true

  import Predicator

  # CompanyFunctions module removed - using manual registration instead

  setup do
    # Clear custom functions before each test
    clear_custom_functions()
    :ok
  end

  describe "simple function registration" do
    test "registers and uses simple anonymous functions" do
      # Register simple functions
      register_function("double", 1, fn [n], _context ->
        {:ok, n * 2}
      end)

      register_function("concat", 2, fn [a, b], _context ->
        {:ok, a <> b}
      end)

      # Test in expressions
      assert {:ok, 10} = evaluate("double(5)")
      assert {:ok, "helloworld"} = evaluate(~s|concat("hello", "world")|)
      assert {:ok, true} = evaluate("double(5) > 8")
      assert {:ok, false} = evaluate(~s|len(concat("ab", "cd")) > 5|)
    end

    test "context-aware functions" do
      register_function("user_name", 0, fn [], context ->
        {:ok, Map.get(context, "user_name", "anonymous")}
      end)

      register_function("is_admin", 0, fn [], context ->
        role = Map.get(context, "role")
        {:ok, role == "admin"}
      end)

      # Test with context
      context = %{"user_name" => "Alice", "role" => "admin"}
      assert {:ok, true} = evaluate("user_name() = \"Alice\"", context)
      assert {:ok, true} = evaluate("is_admin() AND user_name() = \"Alice\"", context)

      # Test without context
      assert {:ok, true} = evaluate("user_name() = \"anonymous\"")
      assert {:ok, false} = evaluate("is_admin()")
    end
  end

  describe "module-based registration" do
    test "registers and uses module-based functions" do
      # Register company functions manually
      register_function("employee_count", 1, fn [dept_id], context ->
        company_id = Map.get(context, "company_id")

        counts = %{
          {"eng", 123} => 45,
          {"sales", 123} => 12,
          {"hr", 123} => 5
        }

        count = Map.get(counts, {dept_id, company_id}, 0)
        {:ok, count}
      end)

      register_function("is_business_hours", 0, fn [], context ->
        current_hour = Map.get(context, "current_hour", 12)
        timezone = Map.get(context, "timezone", "UTC")

        business_hours =
          case timezone do
            "PST" -> 9..17
            "EST" -> 12..20
            _other_timezone -> 8..16
          end

        {:ok, current_hour in business_hours}
      end)

      register_function("department_budget", 1, fn [dept_id], context ->
        budgets = Map.get(context, "budgets", %{})
        budget = Map.get(budgets, dept_id, 0)
        {:ok, budget}
      end)

      context = %{
        "company_id" => 123,
        "current_hour" => 14,
        "timezone" => "PST",
        "budgets" => %{"eng" => 500_000, "sales" => 200_000}
      }

      # Test individual functions
      assert {:ok, 45} = evaluate("employee_count(\"eng\")", context)
      assert {:ok, true} = evaluate("is_business_hours()", context)
      assert {:ok, 500_000} = evaluate("department_budget(\"eng\")", context)

      # Test in complex expressions
      assert {:ok, true} = evaluate("employee_count(\"eng\") > 40", context)

      assert {:ok, true} =
               evaluate(~s|is_business_hours() AND employee_count("eng") > 30|, context)

      assert {:ok, false} =
               evaluate(~s|department_budget("sales") > department_budget("eng")|, context)
    end

    test "functions work with different contexts" do
      # Register business hours function manually
      register_function("is_business_hours", 0, fn [], context ->
        current_hour = Map.get(context, "current_hour", 12)
        timezone = Map.get(context, "timezone", "UTC")

        business_hours =
          case timezone do
            "PST" -> 9..17
            "EST" -> 12..20
            _other_timezone -> 8..16
          end

        {:ok, current_hour in business_hours}
      end)

      # Morning context (not business hours for PST)
      morning_context = %{"company_id" => 123, "current_hour" => 7, "timezone" => "PST"}
      assert {:ok, false} = evaluate("is_business_hours()", morning_context)

      # Business hours context
      work_context = %{"company_id" => 123, "current_hour" => 14, "timezone" => "PST"}
      assert {:ok, true} = evaluate("is_business_hours()", work_context)

      # Different timezone
      est_context = %{"company_id" => 123, "current_hour" => 14, "timezone" => "EST"}
      assert {:ok, true} = evaluate("is_business_hours()", est_context)
    end

    test "handles function errors gracefully" do
      register_function("divide_safe", 2, fn [a, b], _context ->
        if b == 0 do
          {:error, "Cannot divide by zero"}
        else
          {:ok, a / b}
        end
      end)

      assert {:ok, 2.5} = evaluate("divide_safe(5, 2)")
      assert {:error, "Cannot divide by zero"} = evaluate("divide_safe(10, 0)")
    end

    test "mixed built-in and custom functions" do
      register_function("cube", 1, fn [n], _context -> {:ok, n * n * n} end)

      # Mix custom and built-in functions
      # built-in
      assert {:ok, true} = evaluate("len(\"hello\") = 5")
      # custom
      assert {:ok, true} = evaluate("cube(3) = 27")
      # mixed
      assert {:ok, true} = evaluate("cube(len(\"ab\")) = 8")
    end
  end

  describe "function listing and management" do
    test "lists custom functions" do
      register_function("func1", 1, fn [_arg], _context -> {:ok, 1} end)
      register_function("func2", 2, fn [_arg1, _arg2], _context -> {:ok, 2} end)

      functions = list_custom_functions()
      # Should include built-in functions (10) plus the 2 custom functions
      assert length(functions) >= 12

      names = Enum.map(functions, & &1.name)
      assert "func1" in names
      assert "func2" in names
      # Also check that built-in functions are included
      assert "len" in names
      assert "max" in names
    end

    test "clears custom functions" do
      register_function("temp", 0, fn [], _context -> {:ok, :temp} end)
      assert {:ok, :temp} = evaluate("temp()")

      clear_custom_functions()
      assert {:error, _msg} = evaluate("temp()")
    end
  end

  describe "nested and complex expressions" do
    test "nested function calls with custom functions" do
      register_function("add_one", 1, fn [n], _context -> {:ok, n + 1} end)
      register_function("multiply_by", 2, fn [n, factor], _context -> {:ok, n * factor} end)

      # Nested custom functions
      assert {:ok, 15} = evaluate("multiply_by(add_one(4), 3)")

      # Mix with built-in functions
      assert {:ok, true} = evaluate("len(\"test\") = add_one(3)")
      assert {:ok, 20} = evaluate("multiply_by(len(\"hello\"), add_one(3))")
    end

    test "functions in logical expressions" do
      register_function("in_range", 3, fn [value, min, max], _context ->
        {:ok, value >= min and value <= max}
      end)

      register_function("user_age", 0, fn [], context ->
        {:ok, Map.get(context, "age", 0)}
      end)

      context = %{"age" => 25}

      assert {:ok, true} = evaluate("in_range(user_age(), 18, 65)", context)
      assert {:ok, true} = evaluate("user_age() > 18 AND in_range(user_age(), 20, 30)", context)
    end
  end

  describe "error handling" do
    test "unknown custom function" do
      assert {:error, "Unknown function: unknown_func"} = evaluate("unknown_func()")
    end

    test "wrong arity for custom function" do
      register_function("test_func", 2, fn [a, b], _context -> {:ok, a + b} end)

      assert {:error, "Function test_func() expects 2 arguments, got 1"} =
               evaluate("test_func(5)")
    end

    test "custom function runtime error" do
      register_function("error_func", 0, fn [], _context ->
        {:error, "Something went wrong"}
      end)

      assert {:error, "Something went wrong"} = evaluate("error_func()")
    end
  end
end
