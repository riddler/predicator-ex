# AUTOGENERATED FILE - DO NOT EDIT
defmodule Predicator.IntInArrayTest do
  use ExUnit.Case, async: false

  setup_all do
    %{instructions: [["lit", 1], ["array", [1, 2]], ["compare", "IN"]]}
  end

  test "with_no_context", context do
    predicate_context = nil
    expected_result = true

    result = Predicator.Evaluator.execute context[:instructions], predicate_context
    assert expected_result == result
    #assert_empty e.stack
  end

end
