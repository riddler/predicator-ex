defmodule Predicator.ObjectIntegrationTest do
  @moduledoc """
  Integration tests for object literals with all existing Predicator features.

  Ensures object literals work seamlessly with functions, operators,
  nested access, bracket access, and complex expressions.
  """

  use ExUnit.Case

  describe "objects with custom functions" do
    test "uses custom functions in object values" do
      custom_functions = %{
        "double" => {1, fn [n], _context -> {:ok, n * 2} end},
        "concat" => {2, fn [a, b], _context -> {:ok, "#{a}#{b}"} end}
      }

      context = %{"base" => 5, "prefix" => "user_"}

      result =
        Predicator.evaluate(
          "{doubled: double(base), name: concat(prefix, \"alice\")}",
          context,
          functions: custom_functions
        )

      assert {:ok, %{"doubled" => 10, "name" => "user_alice"}} = result
    end

    test "uses system functions in object values" do
      context = %{"name" => "john", "items" => ["a", "b", "c"]}

      result =
        Predicator.evaluate(
          "{upper_name: upper(name), name_length: len(name), trimmed: trim(\" hello \")}",
          context
        )

      assert {:ok, %{"upper_name" => "JOHN", "name_length" => 4, "trimmed" => "hello"}} = result
    end

    test "passes objects to custom functions" do
      custom_functions = %{
        "get_name" =>
          {1,
           fn [obj], _context when is_map(obj) ->
             {:ok, Map.get(obj, "name", "unknown")}
           end}
      }

      result =
        Predicator.evaluate(
          "get_name({name: \"alice\", age: 30})",
          %{},
          functions: custom_functions
        )

      assert {:ok, "alice"} = result
    end
  end

  describe "objects with nested property access" do
    test "creates objects that can be accessed with dot notation" do
      # First create the object, then access its properties
      context = %{}

      # Create object
      {:ok, user_obj} = Predicator.evaluate("{name: \"John\", age: 30}", context)

      # Use object in context for dot notation access
      context_with_user = %{"user" => user_obj}

      result = Predicator.evaluate("user.name", context_with_user)
      assert {:ok, "John"} = result

      result = Predicator.evaluate("user.age", context_with_user)
      assert {:ok, 30} = result
    end

    test "creates nested objects accessible with chained dot notation" do
      nested_context = %{}

      {:ok, config} =
        Predicator.evaluate(
          ~s|{database: {host: "localhost", port: 5432}, app: {name: "myapp"}}|,
          nested_context
        )

      context = %{"config" => config}

      assert {:ok, "localhost"} = Predicator.evaluate("config.database.host", context)
      assert {:ok, 5432} = Predicator.evaluate("config.database.port", context)
      assert {:ok, "myapp"} = Predicator.evaluate("config.app.name", context)
    end
  end

  describe "objects with bracket access" do
    test "creates objects accessible with bracket notation" do
      context = %{}

      {:ok, user} =
        Predicator.evaluate(
          ~s|{"first name": "John", "last-name": "Doe", age: 30}|,
          context
        )

      context_with_user = %{"user" => user}

      assert {:ok, "John"} = Predicator.evaluate("user[\"first name\"]", context_with_user)
      assert {:ok, "Doe"} = Predicator.evaluate("user[\"last-name\"]", context_with_user)
      assert {:ok, 30} = Predicator.evaluate("user[\"age\"]", context_with_user)
    end

    test "uses dynamic keys in object bracket access" do
      context = %{
        "key_name" => "status",
        "user" => %{"status" => "active", "role" => "admin"}
      }

      # Create object with dynamic property access
      result = Predicator.evaluate("{current: user[key_name]}", context)
      assert {:ok, %{"current" => "active"}} = result
    end

    test "combines object creation with array indexing" do
      context = %{"items" => ["first", "second", "third"]}

      result =
        Predicator.evaluate(
          "{first_item: items[0], last_item: items[2], middle_item: items[1]}",
          context
        )

      assert {:ok, %{"first_item" => "first", "last_item" => "third", "middle_item" => "second"}} =
               result
    end
  end

  describe "objects in complex boolean expressions" do
    test "uses objects in logical AND/OR operations" do
      context = %{
        "user1" => %{"role" => "admin", "active" => true},
        "user2" => %{"role" => "user", "active" => true},
        "admin_role" => %{"role" => "admin"}
      }

      # Complex boolean with object comparisons
      result =
        Predicator.evaluate(
          "(user1 == {role: \"admin\", active: true}) AND (user2.active = true)",
          context
        )

      assert {:ok, true} = result

      result =
        Predicator.evaluate(
          "(user1 != admin_role) OR (user2.role = \"admin\")",
          context
        )

      assert {:ok, true} = result
    end

    test "uses objects with membership operators" do
      context = %{
        "roles" => ["admin", "user", "guest"],
        "permissions" => ["read", "write"],
        "current_role" => "admin"
      }

      result =
        Predicator.evaluate(
          "{has_role: current_role in roles, can_write: \"write\" in permissions}",
          context
        )

      assert {:ok, %{"has_role" => true, "can_write" => true}} = result
    end
  end

  describe "objects with all operator types" do
    test "combines objects with arithmetic operations" do
      context = %{"base" => 100, "rate" => 0.15, "quantity" => 3}

      result =
        Predicator.evaluate(
          ~s|{
          unit_price: base,
          tax_rate: rate,
          quantity: quantity,
          subtotal: base * quantity,
          tax_amount: (base * quantity) * rate,
          total: (base * quantity) + ((base * quantity) * rate),
          discount: (base * quantity) * 0.1,
          final_total: ((base * quantity) + ((base * quantity) * rate)) - ((base * quantity) * 0.1)
        }|,
          context
        )

      assert {:ok, result_obj} = result
      assert result_obj["unit_price"] == 100
      assert result_obj["tax_rate"] == 0.15
      assert result_obj["quantity"] == 3
      assert result_obj["subtotal"] == 300
      assert result_obj["tax_amount"] == 45.0
      assert result_obj["total"] == 345.0
      assert result_obj["discount"] == 30.0
      assert result_obj["final_total"] == 315.0
    end

    test "combines objects with comparison operations" do
      context = %{
        "score1" => 85,
        "score2" => 92,
        "passing_score" => 80,
        "excellent_score" => 90
      }

      result =
        Predicator.evaluate(
          ~s|{
          score1_passing: score1 >= passing_score,
          score2_passing: score2 >= passing_score,
          score1_excellent: score1 >= excellent_score,
          score2_excellent: score2 >= excellent_score,
          better_score: score2 > score1,
          scores_equal: score1 = score2
        }|,
          context
        )

      assert {:ok, result_obj} = result
      assert result_obj["score1_passing"] == true
      assert result_obj["score2_passing"] == true
      assert result_obj["score1_excellent"] == false
      assert result_obj["score2_excellent"] == true
      assert result_obj["better_score"] == true
      assert result_obj["scores_equal"] == false
    end

    test "combines objects with unary operations" do
      context = %{"positive" => 42, "negative" => -17, "flag" => true}

      result =
        Predicator.evaluate(
          "{negated: -positive, absolute: -negative, inverted: !flag}",
          context
        )

      assert {:ok, %{"negated" => -42, "absolute" => 17, "inverted" => false}} = result
    end
  end

  describe "objects with date and datetime" do
    test "creates objects with date/datetime values" do
      result =
        Predicator.evaluate(
          ~s|{
          start_date: #2024-01-15#,
          end_datetime: #2024-12-31T23:59:59Z#,
          today: #2024-08-30#
        }|,
          %{}
        )

      assert {:ok, result_obj} = result
      assert result_obj["start_date"] == ~D[2024-01-15]
      assert result_obj["end_datetime"] == ~U[2024-12-31 23:59:59Z]
      assert result_obj["today"] == ~D[2024-08-30]
    end

    test "uses date functions with objects" do
      context = %{"event_date" => ~D[2024-03-15]}

      result =
        Predicator.evaluate(
          "{year: year(event_date), month: month(event_date), day: day(event_date)}",
          context
        )

      assert {:ok, %{"year" => 2024, "month" => 3, "day" => 15}} = result
    end
  end

  describe "performance and stress testing" do
    test "handles large objects efficiently" do
      # Create object with 100 computed values
      pairs = for i <- 1..100, do: "computed#{i}: #{i} * 2"
      large_obj = "{#{Enum.join(pairs, ", ")}}"

      start_time = System.monotonic_time(:microsecond)
      result = Predicator.evaluate(large_obj, %{})
      end_time = System.monotonic_time(:microsecond)

      assert {:ok, result_obj} = result
      assert map_size(result_obj) == 100
      assert result_obj["computed1"] == 2
      assert result_obj["computed100"] == 200

      # Should complete in reasonable time (< 100ms)
      duration = end_time - start_time
      assert duration < 100_000, "Large object took too long: #{duration}μs"
    end

    test "handles repeated object evaluation efficiently" do
      obj_expr = "{total: price * quantity, tax: (price * quantity) * 0.1}"
      context = %{"price" => 10, "quantity" => 5}

      # Evaluate same expression 50 times
      start_time = System.monotonic_time(:microsecond)

      results =
        for _i <- 1..50 do
          Predicator.evaluate(obj_expr, context)
        end

      end_time = System.monotonic_time(:microsecond)

      # All evaluations should succeed
      assert Enum.all?(results, fn {:ok, _result} -> true end)

      # Should complete in reasonable time (< 200ms total)
      duration = end_time - start_time
      assert duration < 200_000, "Repeated evaluation took too long: #{duration}μs"
    end
  end
end
