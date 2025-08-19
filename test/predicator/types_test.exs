defmodule Predicator.TypesTest do
  use ExUnit.Case, async: true

  alias Predicator.Types

  doctest Predicator.Types

  describe "undefined?/1" do
    test "returns true for :undefined" do
      assert Types.undefined?(:undefined)
    end

    test "returns false for other values" do
      refute Types.undefined?(nil)
      refute Types.undefined?(42)
      refute Types.undefined?("hello")
      refute Types.undefined?(true)
      refute Types.undefined?(false)
      refute Types.undefined?([])
    end
  end

  describe "types_match?/2" do
    test "matches integers" do
      assert Types.types_match?(1, 2)
      assert Types.types_match?(0, -5)
    end

    test "matches booleans" do
      assert Types.types_match?(true, false)
      assert Types.types_match?(false, true)
    end

    test "matches binaries" do
      assert Types.types_match?("hello", "world")
      assert Types.types_match?("", "test")
    end

    test "matches lists" do
      assert Types.types_match?([], [1, 2, 3])
      assert Types.types_match?([1, 2], ["a", "b"])
    end

    test "does not match different types" do
      refute Types.types_match?(1, "hello")
      refute Types.types_match?(true, 42)
      refute Types.types_match?("test", [])
      refute Types.types_match?([], true)
      refute Types.types_match?(:undefined, nil)
    end
  end
end
