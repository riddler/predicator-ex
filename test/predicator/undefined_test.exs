defmodule Predicator.UndefinedTest do
  use ExUnit.Case, async: true

  alias Predicator.Undefined

  doctest Undefined

  describe "value/0" do
    test "returns the :undefined sentinel" do
      assert Undefined.value() == :undefined
    end
  end

  describe "undefined?/1" do
    test "true for the sentinel" do
      assert Undefined.undefined?(:undefined)
    end

    test "false for nil" do
      refute Undefined.undefined?(nil)
    end

    test "false for an ordinary value" do
      refute Undefined.undefined?(42)
    end
  end

  describe "to_nil/1" do
    test "converts the sentinel to nil" do
      assert Undefined.to_nil(:undefined) == nil
    end

    test "passes other values through unchanged" do
      assert Undefined.to_nil(42) == 42
      assert Undefined.to_nil("hello") == "hello"
    end
  end

  describe "from_nil/1" do
    test "converts nil to the sentinel" do
      assert Undefined.from_nil(nil) == :undefined
    end

    test "passes other values through unchanged" do
      assert Undefined.from_nil(42) == 42
      assert Undefined.from_nil("hello") == "hello"
    end
  end

  describe "to_nil/1 and from_nil/1 round-trip" do
    test "to_nil then from_nil returns the sentinel" do
      assert :undefined |> Undefined.to_nil() |> Undefined.from_nil() == :undefined
    end

    test "from_nil then to_nil returns nil" do
      assert nil |> Undefined.from_nil() |> Undefined.to_nil() == nil
    end
  end
end
