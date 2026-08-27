defmodule Predicator.Errors.PositionTest do
  use ExUnit.Case, async: true

  alias Predicator.Errors

  alias Predicator.Errors.{
    EvaluationError,
    LocationError,
    TypeMismatchError,
    UndefinedVariableError
  }

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
      error = UndefinedVariableError.new("limit")

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

  describe "put_position/2 with a span" do
    test "sets :span and :position on an EvaluationError" do
      error = EvaluationError.new("boom", "boom", :divide)
      decorated = Errors.put_position(error, {{1, 1}, {1, 9}})

      assert decorated.span == {{1, 1}, {1, 9}}
      assert decorated.position == {1, 1}
    end

    test "sets :span and :position on a TypeMismatchError" do
      error = TypeMismatchError.binary(:multiply, :integer, {:integer, :boolean}, {1, true})
      decorated = Errors.put_position(error, {{2, 1}, {2, 9}})

      assert decorated.span == {{2, 1}, {2, 9}}
      assert decorated.position == {2, 1}
    end

    test "sets :span and :position on an UndefinedVariableError" do
      error = UndefinedVariableError.new("limit")
      decorated = Errors.put_position(error, {{1, 4}, {1, 9}})

      assert decorated.span == {{1, 4}, {1, 9}}
      assert decorated.position == {1, 4}
    end

    test "a span crossing lines keeps both endpoints" do
      error = EvaluationError.new("boom", "boom")

      assert Errors.put_position(error, {{1, 1}, {3, 4}}).span == {{1, 1}, {3, 4}}
    end

    test "falls back to the span's start on a struct with :position but no :span" do
      # Every error struct in this codebase now carries :span (ParseError
      # included, as of the parse-error-spans work), so this branch has no
      # live struct to exercise it against - simulate one by deleting the
      # key from a real struct rather than asserting behavior no longer
      # reachable through any public constructor.
      error = EvaluationError.new("boom", "boom") |> Map.delete(:span)
      decorated = Errors.put_position(error, {{1, 1}, {1, 9}})

      refute Map.has_key?(decorated, :span)
      assert decorated.position == {1, 1}
    end

    test "a struct with neither field is returned unchanged" do
      error = LocationError.not_assignable("literal value", 42)

      assert Errors.put_position(error, {{1, 1}, {1, 9}}) == error
    end

    test "a bare string is returned unchanged" do
      assert Errors.put_position("boom", {{1, 1}, {1, 9}}) == "boom"
    end

    test "leaves everything but :span and :position untouched" do
      error = TypeMismatchError.unary(:unary_minus, :integer, :string, "text")

      assert Errors.put_position(error, {{1, 1}, {1, 6}}) ==
               %{error | span: {{1, 1}, {1, 6}}, position: {1, 1}}
    end
  end

  describe "put_position/2 pass-through cases" do
    test "a nil position returns the error unchanged" do
      error = EvaluationError.new("boom", "boom")

      assert Errors.put_position(error, nil) == error
    end

    test "a struct without a :position field is returned unchanged" do
      error = LocationError.not_assignable("literal value", 42)

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
