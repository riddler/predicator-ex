defmodule Predicator.ErrorsTest do
  use ExUnit.Case, async: true
  doctest Predicator.Errors

  describe "expected_type_name/1" do
    test "formats integer with 'an'" do
      assert Predicator.Errors.expected_type_name(:integer) == "an integer"
    end

    test "formats other types with 'a'" do
      assert Predicator.Errors.expected_type_name(:boolean) == "a boolean"
      assert Predicator.Errors.expected_type_name(:string) == "a string"
      assert Predicator.Errors.expected_type_name(:custom_type) == "a custom_type"
    end
  end

  describe "type_name_with_value/2" do
    test "formats string values with quotes" do
      assert Predicator.Errors.type_name_with_value(:string, "hello") == "\"hello\" (string)"
      assert Predicator.Errors.type_name_with_value(:string, "world") == "\"world\" (string)"
    end

    test "formats non-string values with inspect" do
      assert Predicator.Errors.type_name_with_value(:integer, 42) == "42 (integer)"
      assert Predicator.Errors.type_name_with_value(:boolean, true) == "true (boolean)"

      assert Predicator.Errors.type_name_with_value(:undefined, :undefined) ==
               ":undefined (undefined)"
    end
  end

  describe "operation_display_name/1" do
    test "formats arithmetic operations" do
      assert Predicator.Errors.operation_display_name(:add) == "Arithmetic add"
      assert Predicator.Errors.operation_display_name(:subtract) == "Arithmetic subtract"
      assert Predicator.Errors.operation_display_name(:multiply) == "Arithmetic multiply"
      assert Predicator.Errors.operation_display_name(:divide) == "Arithmetic divide"
      assert Predicator.Errors.operation_display_name(:modulo) == "Arithmetic modulo"
    end

    test "formats unary operations" do
      assert Predicator.Errors.operation_display_name(:unary_minus) == "Unary minus"
      assert Predicator.Errors.operation_display_name(:unary_bang) == "Logical NOT"
    end

    test "formats logical operations" do
      assert Predicator.Errors.operation_display_name(:logical_and) == "Logical AND"
      assert Predicator.Errors.operation_display_name(:logical_or) == "Logical OR"
      assert Predicator.Errors.operation_display_name(:logical_not) == "Logical NOT"
    end

    test "formats unknown operations with capitalized words" do
      assert Predicator.Errors.operation_display_name(:custom_operation) == "Custom Operation"
      assert Predicator.Errors.operation_display_name(:multi_word_op) == "Multi Word Op"
    end

    test "handles special logical word formatting" do
      assert Predicator.Errors.operation_display_name(:test_and_check) == "Test AND Check"
      assert Predicator.Errors.operation_display_name(:run_or_fail) == "Run OR Fail"
      assert Predicator.Errors.operation_display_name(:is_not_valid) == "Is NOT Valid"
    end
  end
end
