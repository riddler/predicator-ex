defmodule Predicator.ObjectEvaluationTest do
  @moduledoc """
  Tests for object literal evaluation functionality.

  Verifies that object literals can be properly parsed, compiled to instructions,
  and evaluated to produce the expected object values.
  """

  use ExUnit.Case

  describe "object literal evaluation" do
    test "evaluates empty object" do
      result = Predicator.evaluate("{}", %{})
      assert {:ok, %{}} = result
    end

    test "evaluates simple object with literal values" do
      result = Predicator.evaluate("{name: \"John\", age: 30}", %{})
      assert {:ok, %{"name" => "John", "age" => 30}} = result
    end

    test "evaluates object with variable references" do
      result =
        Predicator.evaluate("{user: name, score: points}", %{"name" => "Alice", "points" => 85})

      assert {:ok, %{"user" => "Alice", "score" => 85}} = result
    end

    test "evaluates object with mixed value types" do
      result = Predicator.evaluate(~s|{active: true, count: 0, items: ["a", "b"]}|, %{})
      assert {:ok, %{"active" => true, "count" => 0, "items" => ["a", "b"]}} = result
    end

    test "evaluates nested objects" do
      result =
        Predicator.evaluate(
          ~s|{user: {name: "Bob", role: "admin"}, settings: {theme: "dark"}}|,
          %{}
        )

      expected = %{
        "user" => %{"name" => "Bob", "role" => "admin"},
        "settings" => %{"theme" => "dark"}
      }

      assert {:ok, ^expected} = result
    end

    test "evaluates object with expression values" do
      result =
        Predicator.evaluate("{total: price + tax, discount: price * 0.1}", %{
          "price" => 100,
          "tax" => 10
        })

      assert {:ok, %{"total" => 110, "discount" => 10.0}} = result
    end

    test "evaluates object with string key syntax" do
      result = Predicator.evaluate(~s|{"first name": "John", "last name": "Doe"}|, %{})
      assert {:ok, %{"first name" => "John", "last name" => "Doe"}} = result
    end
  end

  describe "object evaluation error handling" do
    test "handles undefined variables in object values" do
      result = Predicator.evaluate("{name: missing_var}", %{})
      assert {:ok, %{"name" => :undefined}} = result
    end

    test "handles empty context" do
      result = Predicator.evaluate("{status: \"active\"}", %{})
      assert {:ok, %{"status" => "active"}} = result
    end
  end

  describe "integration with existing operations" do
    test "object equality comparison" do
      # Test object equality using == operator
      context = %{"user_data" => %{"score" => 85}}

      # First test that both sides evaluate correctly
      {:ok, left} = Predicator.evaluate("{score: 85}", %{})
      {:ok, right} = Predicator.evaluate("user_data", context)

      assert left == %{"score" => 85}
      assert right == %{"score" => 85}

      # Then test the comparison
      result = Predicator.evaluate("{score: 85} == user_data", context)
      assert {:ok, true} = result
    end

    test "object inequality comparison" do
      context = %{"user_data" => %{"score" => 90}}

      result = Predicator.evaluate("{score: 85} != user_data", context)
      assert {:ok, true} = result

      result = Predicator.evaluate("{score: 90} != user_data", context)
      assert {:ok, false} = result
    end

    test "empty object comparisons" do
      result = Predicator.evaluate("{} == {}", %{})
      assert {:ok, true} = result

      result = Predicator.evaluate("{} != {name: \"test\"}", %{})
      assert {:ok, true} = result
    end

    test "object property access" do
      # Note: This will be supported once property access on expressions is implemented
      # For now, this tests that objects can be created properly
      result = Predicator.evaluate("{name: \"John\", age: 30}", %{})
      assert {:ok, %{"name" => "John", "age" => 30}} = result
    end
  end
end
