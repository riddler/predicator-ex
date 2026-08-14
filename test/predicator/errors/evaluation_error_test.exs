defmodule Predicator.Errors.EvaluationErrorTest do
  use ExUnit.Case, async: true

  alias Predicator.Errors.EvaluationError

  describe "new/3" do
    test "leaves details nil - no existing error shape changed" do
      error = EvaluationError.new("Division by zero", "division_by_zero", :divide)

      assert error.message == "Division by zero"
      assert error.reason == "division_by_zero"
      assert error.operation == :divide
      assert error.details == nil
    end

    test "operation defaults to nil" do
      error = EvaluationError.new("boom", "some_reason")

      assert error.operation == nil
      assert error.details == nil
    end
  end

  describe "insufficient_operands/3" do
    test "leaves details nil" do
      error = EvaluationError.insufficient_operands(:store, 1, 2)

      assert error.reason == "insufficient_operands"
      assert error.operation == :store
      assert error.details == nil
    end
  end

  describe "protected_root/1" do
    test "carries the offending root in details, not just message" do
      error = EvaluationError.protected_root("_event")

      assert error.reason == "protected_root"
      assert error.operation == :store
      assert error.details == %{root: "_event"}
      assert error.message == "Cannot assign to protected context root '_event'"
    end

    test "position and span default to nil - the same as any freshly built error" do
      error = EvaluationError.protected_root("_sessionid")

      assert error.position == nil
      assert error.span == nil
    end
  end
end
