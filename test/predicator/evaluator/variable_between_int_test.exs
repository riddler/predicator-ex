# AUTOGENERATED FILE - DO NOT EDIT
defmodule Predicator.VariableBetweenIntTest do
  use ExUnit.Case, async: false
  @moduletag :spec

  setup_all do
    %{instructions: [["load", "age"], ["to_int"], ["lit", 10], ["lit", 20], ["compare", "BETWEEN"]]}
  end

  test "with_no_context", context do
    predicate_context = nil
    expected_result = false

    result = Predicator.Evaluator.execute context[:instructions], predicate_context
    assert expected_result == result
    #assert_empty e.stack
  end

  test "with_blank_string", context do
    predicate_context = %{age: ""}
    expected_result = false

    result = Predicator.Evaluator.execute context[:instructions], predicate_context
    assert expected_result == result
    #assert_empty e.stack
  end

  test "with_correct_int", context do
    predicate_context = %{age: 15}
    expected_result = true

    result = Predicator.Evaluator.execute context[:instructions], predicate_context
    assert expected_result == result
    #assert_empty e.stack
  end

  test "with_incorrect_int", context do
    predicate_context = %{age: 5}
    expected_result = false

    result = Predicator.Evaluator.execute context[:instructions], predicate_context
    assert expected_result == result
    #assert_empty e.stack
  end

  test "with_correct_string", context do
    predicate_context = %{age: "15"}
    expected_result = true

    result = Predicator.Evaluator.execute context[:instructions], predicate_context
    assert expected_result == result
    #assert_empty e.stack
  end

  test "with_incorrect_string", context do
    predicate_context = %{age: "5"}
    expected_result = false

    result = Predicator.Evaluator.execute context[:instructions], predicate_context
    assert expected_result == result
    #assert_empty e.stack
  end

end