defmodule Predicator.ObjectEdgeCasesTest do
  @moduledoc """
  Comprehensive edge case and error testing for object literals.

  Tests error conditions, malformed syntax, integration with other features,
  and boundary conditions for object literal functionality.
  """

  use ExUnit.Case

  describe "object parsing edge cases" do
    test "handles malformed object syntax" do
      # Missing closing brace
      assert {:error, message, _line, _col} = Predicator.parse("{name: \"John\"")
      assert message =~ "Expected '}'"

      # Missing opening brace
      assert {:error, message, _line, _col} = Predicator.parse("name: \"John\"}")
      assert message =~ "Unexpected token"

      # Missing colon
      assert {:error, message, _line, _col} = Predicator.parse("{name \"John\"}")
      assert message =~ "Expected ':'"

      # Missing value
      assert {:error, message, _line, _col} = Predicator.parse("{name:}")

      assert message =~
               "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '('"

      # Invalid key type
      assert {:error, message, _line, _col} = Predicator.parse("{123: \"value\"}")
      assert message =~ "Expected identifier or string for object key"

      # Trailing comma (currently invalid)
      assert {:error, message, _line, _col} = Predicator.parse("{name: \"John\",}")
      assert message =~ "Expected identifier or string for object key"
    end

    test "handles empty object variations" do
      # Standard empty object
      assert {:ok, %{}} = Predicator.evaluate("{}", %{})

      # Empty object with whitespace
      assert {:ok, %{}} = Predicator.evaluate("{ }", %{})
      assert {:ok, %{}} = Predicator.evaluate("{\n}", %{})
      assert {:ok, %{}} = Predicator.evaluate("{\t}", %{})
    end

    test "handles complex whitespace in objects" do
      # Various whitespace patterns
      expressions = [
        "{ name : \"John\" }",
        "{\n  name: \"John\"\n}",
        "{\tname:\t\"John\"\t}",
        "{  name  :  \"John\"  ,  age  :  30  }"
      ]

      for expr <- expressions do
        result = Predicator.evaluate(expr, %{})
        assert {:ok, _obj} = result, "Failed for expression: #{expr}"
      end
    end

    test "handles nested objects with various depths" do
      # 3-level nesting
      deep_obj = "{level1: {level2: {level3: \"deep\"}}}"

      assert {:ok, %{"level1" => %{"level2" => %{"level3" => "deep"}}}} =
               Predicator.evaluate(deep_obj, %{})

      # Mixed nesting with simple lists (objects in lists not yet supported)
      mixed_obj = "{users: [\"John\", \"Jane\"], active: {status: true}}"
      expected = %{"users" => ["John", "Jane"], "active" => %{"status" => true}}
      assert {:ok, ^expected} = Predicator.evaluate(mixed_obj, %{})
    end

    test "handles objects with all supported value types" do
      obj = ~s|{
        str: "text",
        num: 42,
        float: 3.14,
        bool_true: true,
        bool_false: false,
        list: [1, 2, 3],
        date: #2024-01-15#,
        datetime: #2024-01-15T10:00:00Z#,
        nested: {inner: "value"}
      }|

      assert {:ok, result} = Predicator.evaluate(obj, %{})

      assert result["str"] == "text"
      assert result["num"] == 42
      assert result["float"] == 3.14
      assert result["bool_true"] == true
      assert result["bool_false"] == false
      assert result["list"] == [1, 2, 3]
      assert result["date"] == ~D[2024-01-15]
      assert result["datetime"] == ~U[2024-01-15 10:00:00Z]
      assert result["nested"] == %{"inner" => "value"}
    end
  end

  describe "object integration with existing features" do
    test "objects in logical expressions" do
      context = %{"user" => %{"role" => "admin"}, "active" => true}

      # Object comparison with logical AND
      result = Predicator.evaluate("{role: \"admin\"} == user AND active", context)
      assert {:ok, true} = result

      # Object in logical OR
      result = Predicator.evaluate("{role: \"guest\"} == user OR active", context)
      assert {:ok, true} = result

      # Object with logical NOT
      result = Predicator.evaluate("NOT ({role: \"guest\"} == user)", context)
      assert {:ok, true} = result
    end

    test "objects in membership operations" do
      context = %{"roles" => ["admin", "user"], "current_role" => "admin"}

      # This would require objects to be members of lists (currently not supported)
      # But we can test that objects work as containers in expressions
      result = Predicator.evaluate("current_role in roles", context)
      assert {:ok, true} = result
    end

    test "objects with function calls" do
      context = %{"name" => "Alice"}

      # Object with function call values
      result = Predicator.evaluate("{username: upper(name), length: len(name)}", context)
      assert {:ok, %{"username" => "ALICE", "length" => 5}} = result
    end

    test "objects with arithmetic expressions" do
      context = %{"base" => 100, "rate" => 0.1, "quantity" => 5}

      result =
        Predicator.evaluate(
          ~s|{
        unit_price: base,
        tax: base * rate,
        total_before_tax: base * quantity,
        total_with_tax: (base * quantity) + (base * quantity * rate)
      }|,
          context
        )

      assert {:ok, result_obj} = result
      assert result_obj["unit_price"] == 100
      assert result_obj["tax"] == 10.0
      assert result_obj["total_before_tax"] == 500
      assert result_obj["total_with_tax"] == 550.0
    end

    test "objects with bracket access" do
      context = %{
        "config" => %{"theme" => "dark", "lang" => "en"},
        "theme_key" => "theme"
      }

      # Object containing bracket access
      result =
        Predicator.evaluate(
          "{current_theme: config[\"theme\"], dynamic: config[theme_key]}",
          context
        )

      assert {:ok, %{"current_theme" => "dark", "dynamic" => "dark"}} = result
    end
  end

  describe "object evaluation error scenarios" do
    test "handles stack underflow in object operations" do
      # This would require manipulating the evaluator directly
      # For now, test that normal object operations don't cause stack issues
      result = Predicator.evaluate("{a: 1, b: 2, c: 3, d: 4, e: 5}", %{})
      assert {:ok, %{"a" => 1, "b" => 2, "c" => 3, "d" => 4, "e" => 5}} = result
    end

    test "handles undefined variables gracefully" do
      # Multiple undefined variables
      result = Predicator.evaluate("{a: missing1, b: missing2, c: \"defined\"}", %{})
      assert {:ok, %{"a" => :undefined, "b" => :undefined, "c" => "defined"}} = result
    end

    test "handles mixed defined and undefined variables" do
      context = %{"defined" => "value"}

      result = Predicator.evaluate("{good: defined, bad: missing, literal: 42}", context)
      assert {:ok, %{"good" => "value", "bad" => :undefined, "literal" => 42}} = result
    end
  end

  describe "object performance and limits" do
    test "handles objects with many keys" do
      # Generate object with 50 key-value pairs
      pairs = for i <- 1..50, do: "key#{i}: #{i}"
      obj_str = "{#{Enum.join(pairs, ", ")}}"

      expected = for i <- 1..50, into: %{}, do: {"key#{i}", i}

      assert {:ok, ^expected} = Predicator.evaluate(obj_str, %{})
    end

    test "handles deeply nested objects" do
      # Create 3-level nested structure manually to ensure correctness
      nested = "{level1: {level2: {level3: \"deep\"}}}"

      assert {:ok, result} = Predicator.evaluate(nested, %{})

      # Navigate to the deepest level
      level1 = result["level1"]
      level2 = level1["level2"]
      level3 = level2["level3"]

      assert level3 == "deep"
    end
  end

  describe "object string key edge cases" do
    test "handles various string key formats" do
      # Different quote types and special characters
      obj = ~s|{
        "simple": 1,
        "with spaces": 2,
        "with-dashes": 3,
        "with_underscores": 4,
        "with.dots": 5,
        "with/slashes": 6,
        "with123numbers": 7,
        "": 8
      }|

      assert {:ok, result} = Predicator.evaluate(obj, %{})

      assert result["simple"] == 1
      assert result["with spaces"] == 2
      assert result["with-dashes"] == 3
      assert result["with_underscores"] == 4
      assert result["with.dots"] == 5
      assert result["with/slashes"] == 6
      assert result["with123numbers"] == 7
      assert result[""] == 8
    end

    test "handles escaped characters in string keys" do
      # Keys with quotes and escape sequences
      obj = ~s|{"key\\"with\\"quotes": "value"}|

      assert {:ok, %{~s(key"with"quotes) => "value"}} = Predicator.evaluate(obj, %{})
    end
  end
end
