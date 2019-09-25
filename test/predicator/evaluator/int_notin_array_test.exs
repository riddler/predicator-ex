# AUTOGENERATED FILE - DO NOT EDIT
defmodule Predicator.IntNotinArrayTest do
  use ExUnit.Case, async: false

  setup_all do
    %{instructions: [["lit", 0], ["array", [1, 2]], ["compare", "IN"]]}
  end

  test "with_no_context", context do
    predicate_context = nil
    expected_result = false

    result = Predicator.Evaluator.execute context[:instructions], predicate_context
    assert expected_result == result
    #assert_empty e.stack
  end

end
