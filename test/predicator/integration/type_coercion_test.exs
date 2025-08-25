defmodule Predicator.TypeCoercionTest do
  use ExUnit.Case, async: true
  alias Predicator

  describe "string concatenation with + operator" do
    test "concatenates two strings" do
      assert {:ok, "HelloWorld"} = Predicator.evaluate("'Hello' + 'World'", %{})
      assert {:ok, "Hello World"} = Predicator.evaluate("'Hello' + ' World'", %{})
      assert {:ok, "foo bar"} = Predicator.evaluate(~s["foo " + "bar"], %{})
    end

    test "concatenates string and number (string + number)" do
      assert {:ok, "Count: 5"} = Predicator.evaluate("'Count: ' + 5", %{})
      assert {:ok, "Value42"} = Predicator.evaluate("'Value' + 42", %{})
      assert {:ok, "Pi: 3.14"} = Predicator.evaluate("'Pi: ' + 3.14", %{})
    end

    test "concatenates number and string (number + string)" do
      assert {:ok, "5 items"} = Predicator.evaluate("5 + ' items'", %{})
      assert {:ok, "42 is the answer"} = Predicator.evaluate("42 + ' is the answer'", %{})
      assert {:ok, "3.14159"} = Predicator.evaluate("3.14 + '159'", %{})
    end

    test "concatenates with variables" do
      assert {:ok, "Hello John"} =
               Predicator.evaluate("greeting + name", %{"greeting" => "Hello ", "name" => "John"})

      assert {:ok, "Total: 100"} = Predicator.evaluate("'Total: ' + count", %{"count" => 100})
      assert {:ok, "100%"} = Predicator.evaluate("percentage + '%'", %{"percentage" => 100})
    end

    test "concatenates empty strings" do
      assert {:ok, ""} = Predicator.evaluate("'' + ''", %{})
      assert {:ok, "test"} = Predicator.evaluate("'' + 'test'", %{})
      assert {:ok, "test"} = Predicator.evaluate("'test' + ''", %{})
    end
  end

  describe "numeric addition with floats" do
    test "adds two floats" do
      assert {:ok, 5.5} = Predicator.evaluate("2.5 + 3.0", %{})
      assert {:ok, result} = Predicator.evaluate("3.14 + 4.0", %{})
      assert_in_delta result, 7.14, 0.0001
      assert {:ok, result2} = Predicator.evaluate("0.1 + 0.2", %{})
      assert_in_delta result2, 0.3, 0.0001
    end

    test "adds integer and float" do
      assert {:ok, 5.5} = Predicator.evaluate("2 + 3.5", %{})
      assert {:ok, 10.14} = Predicator.evaluate("6 + 4.14", %{})
      assert {:ok, 100.1} = Predicator.evaluate("100 + 0.1", %{})
    end

    test "adds float and integer" do
      assert {:ok, 5.5} = Predicator.evaluate("3.5 + 2", %{})
      assert {:ok, 10.14} = Predicator.evaluate("4.14 + 6", %{})
      assert {:ok, 100.1} = Predicator.evaluate("0.1 + 100", %{})
    end

    test "negative floats" do
      assert {:ok, -1.5} = Predicator.evaluate("-3.5 + 2.0", %{})
      assert {:ok, 1.5} = Predicator.evaluate("3.5 + -2.0", %{})
      assert {:ok, -5.5} = Predicator.evaluate("-2.5 + -3.0", %{})
    end
  end

  describe "arithmetic operations with floats" do
    test "subtraction with floats" do
      assert {:ok, 2.5} = Predicator.evaluate("5.5 - 3.0", %{})
      assert {:ok, -1.0} = Predicator.evaluate("2.5 - 3.5", %{})
      assert {:ok, result} = Predicator.evaluate("3.14 - 3.14", %{})
      assert result == 0.0
    end

    test "multiplication with floats" do
      assert {:ok, 7.5} = Predicator.evaluate("2.5 * 3.0", %{})
      assert {:ok, 12.56} = Predicator.evaluate("3.14 * 4.0", %{})
      assert {:ok, 6.25} = Predicator.evaluate("2.5 * 2.5", %{})
    end

    test "division with floats" do
      assert {:ok, 2.5} = Predicator.evaluate("7.5 / 3.0", %{})
      assert {:ok, 0.5} = Predicator.evaluate("1.0 / 2.0", %{})
      assert {:ok, result} = Predicator.evaluate("3.14 / 2.0", %{})
      assert_in_delta result, 1.57, 0.01
    end

    test "division with integers returns integer when evenly divisible" do
      assert {:ok, 2} = Predicator.evaluate("6 / 3", %{})
      assert {:ok, 5} = Predicator.evaluate("10 / 2", %{})
    end

    test "division with mixed types" do
      assert {:ok, 2.5} = Predicator.evaluate("5 / 2.0", %{})
      assert {:ok, 2.5} = Predicator.evaluate("5.0 / 2", %{})
    end

    test "modulo only works with integers" do
      assert {:ok, 1} = Predicator.evaluate("10 % 3", %{})
      assert {:ok, 0} = Predicator.evaluate("10 % 2", %{})

      # Modulo with floats should error
      assert {:error, _float_modulo_error} = Predicator.evaluate("10.5 % 3", %{})
      assert {:error, _int_float_modulo_error} = Predicator.evaluate("10 % 3.5", %{})
    end

    test "unary minus with floats" do
      assert {:ok, -3.14} = Predicator.evaluate("-3.14", %{})
      assert {:ok, 3.14} = Predicator.evaluate("--3.14", %{})
      assert {:ok, -2.5} = Predicator.evaluate("-(2.5)", %{})
    end
  end

  describe "comparison operations with mixed types" do
    test "compares numbers of different types" do
      assert {:ok, true} = Predicator.evaluate("3.5 > 3", %{})
      assert {:ok, false} = Predicator.evaluate("3 > 3.5", %{})
      assert {:ok, true} = Predicator.evaluate("3.0 = 3", %{})
      assert {:ok, true} = Predicator.evaluate("3 = 3.0", %{})
    end

    test "float comparisons" do
      assert {:ok, true} = Predicator.evaluate("3.14 > 3.13", %{})
      assert {:ok, false} = Predicator.evaluate("3.14 < 3.13", %{})
      assert {:ok, true} = Predicator.evaluate("3.14 >= 3.14", %{})
      assert {:ok, true} = Predicator.evaluate("3.14 <= 3.14", %{})
      assert {:ok, false} = Predicator.evaluate("3.14 != 3.14", %{})
    end
  end

  describe "complex expressions with type coercion" do
    test "mixed string concatenation in complex expressions" do
      assert {:ok, "Result: 15"} = Predicator.evaluate("'Result: ' + (10 + 5)", %{})

      # String concatenation is left-to-right: "Values: " + 5 = "Values: 5", then "Values: 5" + 5 = "Values: 55"
      assert {:ok, "Values: 55"} = Predicator.evaluate("'Values: ' + (2 + 3) + (4 + 1)", %{})
    end

    test "conditional with string concatenation" do
      assert {:ok, true} = Predicator.evaluate("('Hello' + 'World') = 'HelloWorld'", %{})
      assert {:ok, true} = Predicator.evaluate("('Count: ' + 5) = 'Count: 5'", %{})
      assert {:ok, false} = Predicator.evaluate("(3 + ' items') = '4 items'", %{})
    end

    test "arithmetic with variables of different types" do
      assert {:ok, 7.5} = Predicator.evaluate("a + b", %{"a" => 3, "b" => 4.5})
      assert {:ok, 1.5} = Predicator.evaluate("a - b", %{"a" => 4.5, "b" => 3})
      assert {:ok, 13.5} = Predicator.evaluate("a * b", %{"a" => 3, "b" => 4.5})
    end

    test "complex nested arithmetic with floats" do
      assert {:ok, result} = Predicator.evaluate("(2.5 + 3) * (4 - 2.1)", %{})
      # 5.5 * 1.9 = 10.45
      assert_in_delta result, 10.45, 0.01
      assert {:ok, result2} = Predicator.evaluate("((3.14 * 2) + 1.5) / 2", %{})
      assert_in_delta result2, 3.89, 0.01
    end
  end

  describe "error cases" do
    test "invalid type combinations for non-addition arithmetic" do
      assert {:error, _subtraction_error} = Predicator.evaluate("'hello' - 5", %{})
      assert {:error, _multiplication_error} = Predicator.evaluate("'hello' * 2", %{})
      assert {:error, _division_error} = Predicator.evaluate("'hello' / 2", %{})
      assert {:error, _boolean_addition_error} = Predicator.evaluate("true + false", %{})
    end

    test "division by zero with floats" do
      assert {:error, _float_div_zero_error} = Predicator.evaluate("3.14 / 0", %{})
      assert {:error, _float_div_float_zero_error} = Predicator.evaluate("3.14 / 0.0", %{})
      assert {:error, _int_div_float_zero_error} = Predicator.evaluate("5 / 0.0", %{})
    end

    test "modulo by zero" do
      assert {:error, _modulo_zero_error} = Predicator.evaluate("10 % 0", %{})
    end

    test "type mismatches in unary operations" do
      assert {:error, _unary_minus_string_error} = Predicator.evaluate("-'hello'", %{})
      assert {:error, _unary_minus_boolean_error} = Predicator.evaluate("-true", %{})
    end
  end

  describe "edge cases" do
    # Scientific notation is not currently supported in the lexer
    # test "very small and large floats" do
    #   assert {:ok, 1.0e10} = Predicator.evaluate("1.0e10", %{})
    #   assert {:ok, 1.0e-10} = Predicator.evaluate("1.0e-10", %{})
    #   assert {:ok, result} = Predicator.evaluate("1.0e10 + 1.0e10", %{})
    #   assert result == 2.0e10
    # end

    test "float precision edge cases" do
      # These test floating point precision handling
      assert {:ok, result} = Predicator.evaluate("0.1 + 0.2", %{})
      assert_in_delta result, 0.3, 0.000001

      assert {:ok, result} = Predicator.evaluate("1.0 - 0.9", %{})
      assert_in_delta result, 0.1, 0.000001
    end

    test "zero handling in floats" do
      assert {:ok, result1} = Predicator.evaluate("0.0 + 0.0", %{})
      assert result1 == 0.0
      assert {:ok, result2} = Predicator.evaluate("1.5 - 1.5", %{})
      assert result2 == 0.0
      assert {:ok, result3} = Predicator.evaluate("0.0 * 100", %{})
      assert result3 == 0.0
      assert {:ok, result4} = Predicator.evaluate("0 * 3.14", %{})
      assert result4 == 0.0
    end
  end
end
