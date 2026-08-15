defmodule Predicator.Errors.ParseErrorTest do
  use ExUnit.Case, async: true

  alias Predicator.Errors.ParseError

  doctest ParseError

  describe "new/3" do
    test "stores the line and column as a single :position tuple" do
      error = ParseError.new("bad input", 2, 5)

      assert error.message == "bad input"
      assert error.position == {2, 5}
    end

    test "does not carry separate :line and :column fields" do
      error = ParseError.new("bad input", 2, 5)

      refute Map.has_key?(error, :line)
      refute Map.has_key?(error, :column)
    end

    test "defaults :span to nil" do
      error = ParseError.new("bad input", 2, 5)

      assert error.span == nil
    end
  end

  describe "new/4" do
    test "stores the span and sets :position to the span's start" do
      error = ParseError.new("bad input", 2, 5, {{2, 5}, {2, 10}})

      assert error.message == "bad input"
      assert error.position == {2, 5}
      assert error.span == {{2, 5}, {2, 10}}
    end

    test "accepts nil as the span" do
      error = ParseError.new("bad input", 2, 5, nil)

      assert error.position == {2, 5}
      assert error.span == nil
    end
  end
end
