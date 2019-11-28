# AUTOGENERATED FILE - DO NOT EDIT
defmodule Predicator.NestedContextTest do
  use ExUnit.Case, async: false
  @moduletag :spec

  setup_all do
    %{instructions: [["load", "person.age"], ["to_int"], ["lit", 13], ["compare", "GT"]]}
  end

  test "with_no_context", context do
    predicate_context = nil
    expected_result = false

    result = Predicator.Evaluator.execute context[:instructions], predicate_context
    assert expected_result == result
    #assert_empty e.stack
  end

  test "with_nested_hash", context do
    predicate_context = %{person: %{age: 20}}
    expected_result = true

    result = Predicator.Evaluator.execute context[:instructions], predicate_context
    assert expected_result == result
    #assert_empty e.stack
  end

end