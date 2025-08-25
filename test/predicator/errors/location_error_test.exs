defmodule Predicator.Errors.LocationErrorTest do
  use ExUnit.Case, async: true

  alias Predicator.Errors.LocationError

  describe "not_assignable/2" do
    test "creates error for literal values" do
      error = LocationError.not_assignable("literal value", 42)
      
      assert error.type == :not_assignable
      assert error.message == "Cannot assign to literal value"
      assert error.details.expression_type == "literal value"
      assert error.details.value == 42
    end

    test "creates error for function calls" do
      error = LocationError.not_assignable("function call", "len")
      
      assert error.type == :not_assignable
      assert error.message == "Cannot assign to function call"
      assert error.details.expression_type == "function call" 
      assert error.details.value == "len"
    end
  end

  describe "invalid_node/2" do
    test "creates error for unknown AST nodes" do
      unknown_node = {:unknown_type, "some_data"}
      error = LocationError.invalid_node("Unknown AST node type", unknown_node)
      
      assert error.type == :invalid_node
      assert error.message == "Unknown AST node type"
      assert error.details.node == unknown_node
    end
  end

  describe "undefined_variable/2" do
    test "creates error for missing variables" do
      error = LocationError.undefined_variable("Variable not found", "missing_var")
      
      assert error.type == :undefined_variable
      assert error.message == "Variable not found"
      assert error.details.variable == "missing_var"
    end
  end

  describe "invalid_key/2" do
    test "creates error for boolean key" do
      error = LocationError.invalid_key("Invalid key type", true)
      
      assert error.type == :invalid_key
      assert error.message == "Invalid key type"
      assert error.details.key_type == "boolean"
      assert error.details.key_value == true
    end

    test "creates error for float key" do
      error = LocationError.invalid_key("Invalid key type", 3.14)
      
      assert error.type == :invalid_key
      assert error.message == "Invalid key type"
      assert error.details.key_type == "float"
      assert error.details.key_value == 3.14
    end

    test "creates error for list key" do
      error = LocationError.invalid_key("Invalid key type", [1, 2, 3])
      
      assert error.type == :invalid_key
      assert error.message == "Invalid key type"
      assert error.details.key_type == "list"
      assert error.details.key_value == [1, 2, 3]
    end

    test "creates error for map key" do
      map_key = %{"nested" => "value"}
      error = LocationError.invalid_key("Invalid key type", map_key)
      
      assert error.type == :invalid_key
      assert error.message == "Invalid key type"
      assert error.details.key_type == "map"
      assert error.details.key_value == map_key
    end

    test "creates error for date key" do
      date_key = ~D[2024-01-15]
      error = LocationError.invalid_key("Invalid key type", date_key)
      
      assert error.type == :invalid_key
      assert error.message == "Invalid key type"
      assert error.details.key_type == "date"
      assert error.details.key_value == date_key
    end

    test "creates error for datetime key" do
      datetime_key = ~U[2024-01-15 10:30:00Z]
      error = LocationError.invalid_key("Invalid key type", datetime_key)
      
      assert error.type == :invalid_key
      assert error.message == "Invalid key type"
      assert error.details.key_type == "datetime"
      assert error.details.key_value == datetime_key
    end

    test "creates error for undefined key" do
      error = LocationError.invalid_key("Invalid key type", :undefined)
      
      assert error.type == :invalid_key
      assert error.message == "Invalid key type"
      assert error.details.key_type == "undefined"
      assert error.details.key_value == :undefined
    end

    test "creates error for unknown type" do
      # Test with a tuple which should fall into the catch-all case
      unknown_value = {:some, :tuple}
      error = LocationError.invalid_key("Invalid key type", unknown_value)
      
      assert error.type == :invalid_key
      assert error.message == "Invalid key type"
      assert error.details.key_type == "unknown"
      assert error.details.key_value == unknown_value
    end
  end

  describe "computed_key/2" do
    test "creates error for computed expressions" do
      expression = {:arithmetic, :add, {:identifier, "i"}, {:literal, 1}}
      error = LocationError.computed_key("Cannot use computed expression", expression)
      
      assert error.type == :computed_key
      assert error.message == "Cannot use computed expression"
      assert error.details.expression == expression
    end
  end
end