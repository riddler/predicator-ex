defmodule Predicator.Errors.PositionTest do
  use ExUnit.Case, async: true

  alias Predicator.Errors
  alias Predicator.Errors.{EvaluationError, ParseError, TypeMismatchError, UndefinedVariableError}

  describe "put_position/2 on structs carrying :position" do
    test "attaches to an EvaluationError" do
      error = EvaluationError.new("boom", "boom", :divide)

      assert error.position == nil
      assert Errors.put_position(error, {2, 5}).position == {2, 5}
    end

    test "attaches to a TypeMismatchError" do
      error = TypeMismatchError.binary(:multiply, :integer, {:integer, :boolean}, {1, true})

      assert error.position == nil
      assert Errors.put_position(error, {1, 3}).position == {1, 3}
    end

    test "attaches to an UndefinedVariableError" do
      error = UndefinedVariableError.new("score")

      assert error.position == nil
      assert Errors.put_position(error, {1, 1}).position == {1, 1}
    end

    test "overwrites a position that is already set" do
      error = Errors.put_position(EvaluationError.new("boom", "boom"), {1, 1})

      assert Errors.put_position(error, {3, 9}).position == {3, 9}
    end

    test "leaves everything but :position untouched" do
      error = TypeMismatchError.unary(:unary_minus, :integer, :string, "text")

      assert Errors.put_position(error, {1, 1}) == %{error | position: {1, 1}}
    end
  end

  describe "put_position/2 pass-through cases" do
    test "a nil position returns the error unchanged" do
      error = EvaluationError.new("boom", "boom")

      assert Errors.put_position(error, nil) == error
    end

    test "a struct without a :position field is returned unchanged" do
      error = ParseError.new("bad", 1, 1)

      assert Errors.put_position(error, {1, 3}) == error
      refute Map.has_key?(error, :position)
    end

    test "a bare string error is returned unchanged" do
      assert Errors.put_position("something failed", {1, 3}) == "something failed"
    end

    test "a non-struct map is returned unchanged" do
      assert Errors.put_position(%{position: nil}, {1, 3}) == %{position: nil}
    end
  end
end
