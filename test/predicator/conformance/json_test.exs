defmodule Predicator.Conformance.JSONTest do
  use ExUnit.Case, async: true

  doctest Predicator.Conformance.JSON

  alias Predicator.Conformance.JSON, as: CanonicalJSON

  describe "encode_canonical/1 - scalars" do
    test "integers, floats, strings, booleans, and nil delegate to JSON.encode!/1" do
      assert CanonicalJSON.encode_canonical(42) == "42"
      assert CanonicalJSON.encode_canonical(3.5) == "3.5"
      assert CanonicalJSON.encode_canonical("hello") == ~s("hello")
      assert CanonicalJSON.encode_canonical(true) == "true"
      assert CanonicalJSON.encode_canonical(false) == "false"
      assert CanonicalJSON.encode_canonical(nil) == "null"
    end

    test "strings are escaped the same way JSON.encode!/1 escapes them" do
      assert CanonicalJSON.encode_canonical("a\"b\nc") == JSON.encode!("a\"b\nc")
    end
  end

  describe "encode_canonical/1 - arrays" do
    test "empty array" do
      assert CanonicalJSON.encode_canonical([]) == "[]"
    end

    test "array of scalars preserves element order" do
      assert CanonicalJSON.encode_canonical([3, 1, 2]) == "[3,1,2]"
    end

    test "nested arrays" do
      assert CanonicalJSON.encode_canonical([[1, 2], [3]]) == "[[1,2],[3]]"
    end
  end

  describe "encode_canonical/1 - objects" do
    test "empty object" do
      assert CanonicalJSON.encode_canonical(%{}) == "{}"
    end

    test "object keys are sorted by codepoint regardless of insertion order" do
      map_a = %{} |> Map.put("b", 1) |> Map.put("a", 2) |> Map.put("c", 3)
      map_b = %{} |> Map.put("c", 3) |> Map.put("a", 2) |> Map.put("b", 1)

      assert CanonicalJSON.encode_canonical(map_a) == ~s({"a":2,"b":1,"c":3})
      assert CanonicalJSON.encode_canonical(map_b) == ~s({"a":2,"b":1,"c":3})
    end

    test "two maps built by inserting the same keys in different orders encode byte-identically" do
      built_ascending =
        Enum.reduce(["a", "b", "c", "d"], %{}, fn key, acc -> Map.put(acc, key, key) end)

      built_descending =
        Enum.reduce(["d", "c", "b", "a"], %{}, fn key, acc -> Map.put(acc, key, key) end)

      assert CanonicalJSON.encode_canonical(built_ascending) ==
               CanonicalJSON.encode_canonical(built_descending)
    end

    test "nested objects and arrays" do
      term = %{"list" => [1, %{"z" => 1, "a" => 2}], "flag" => true}
      assert CanonicalJSON.encode_canonical(term) == ~s({"flag":true,"list":[1,{"a":2,"z":1}]})
    end

    test "atom keys are stringified before sorting" do
      assert CanonicalJSON.encode_canonical(%{b: 1, a: 2}) == ~s({"a":2,"b":1})
    end

    test "no incidental whitespace anywhere in the output" do
      term = %{"a" => [1, 2, %{"b" => 3}]}
      refute CanonicalJSON.encode_canonical(term) =~ " "
    end
  end

  describe "encode_lines/1" do
    test "empty list encodes to an empty binary" do
      assert CanonicalJSON.encode_lines([]) == ""
    end

    test "each item is one canonical-JSON line" do
      items = [%{"id" => 2}, %{"id" => 1}]

      assert CanonicalJSON.encode_lines(items) == ~s({"id":2}\n{"id":1}\n)
    end

    test "a single item is one line, readable in a terminal" do
      output = CanonicalJSON.encode_lines([%{"id" => "core/lit-int", "tier" => 1}])

      assert output == ~s({"id":"core/lit-int","tier":1}\n)
      assert output |> String.trim_trailing("\n") |> String.contains?("\n") == false
    end
  end
end
