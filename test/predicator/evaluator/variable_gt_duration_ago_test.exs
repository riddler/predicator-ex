# AUTOGENERATED FILE - DO NOT EDIT
defmodule Predicator.VariableGtDurationAgoTest do
  use ExUnit.Case, async: false

  setup_all do
    %{instructions: [["load", "start_date"], ["to_date"], ["lit", 259200], ["date_ago"], ["compare", "GT"]]}
  end

  test "with_no_context", context do
    predicate_context = nil
    expected_result = false

    result = Predicator.Evaluator.execute context[:instructions], predicate_context
    assert expected_result == result
    #assert_empty e.stack
  end

  test "with_blank_date", context do
    predicate_context = %{start_date: ""}
    expected_result = false

    result = Predicator.Evaluator.execute context[:instructions], predicate_context
    assert expected_result == result
    #assert_empty e.stack
  end

  test "with_future_date", context do
    predicate_context = %{start_date: "2299-01-01"}
    expected_result = true

    result = Predicator.Evaluator.execute context[:instructions], predicate_context
    assert expected_result == result
    #assert_empty e.stack
  end

  test "with_past_date", context do
    predicate_context = %{start_date: "1999-01-01"}
    expected_result = false

    result = Predicator.Evaluator.execute context[:instructions], predicate_context
    assert expected_result == result
    #assert_empty e.stack
  end

end
