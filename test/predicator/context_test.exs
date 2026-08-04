defmodule Predicator.ContextTest do
  use ExUnit.Case, async: true

  doctest Predicator.Context

  alias Predicator.Context
  alias Predicator.Errors.LocationError
  alias Predicator.Evaluator

  describe "new/2" do
    test "defaults data, functions, and on_unbound" do
      context = Context.new()

      assert context.data == %{}
      assert context.on_unbound == :undefined
      assert map_size(context.functions) > 0
    end

    test "stores the given data" do
      context = Context.new(%{"a" => 1})

      assert context.data == %{"a" => 1}
    end

    test "merges custom functions over the builtins" do
      custom = %{"double" => {1, fn [n], _ctx -> {:ok, n * 2} end}}
      context = Context.new(%{}, functions: custom)

      assert Map.has_key?(context.functions, "double")
      assert Map.has_key?(context.functions, "len")
    end

    test "custom functions can shadow a builtin of the same name" do
      shadow = %{"len" => {1, fn [_arg], _ctx -> {:ok, :shadowed} end}}
      context = Context.new(%{}, functions: shadow)

      assert {1, fun} = context.functions["len"]
      assert fun.([[1, 2, 3]], %{}) == {:ok, :shadowed}
    end

    test "accepts on_unbound: :undefined" do
      context = Context.new(%{}, on_unbound: :undefined)

      assert context.on_unbound == :undefined
    end

    test "accepts on_unbound: :error" do
      context = Context.new(%{}, on_unbound: :error)

      assert context.on_unbound == :error
    end

    test "raises ArgumentError for an invalid on_unbound value" do
      assert_raise ArgumentError, ~r/on_unbound must be :undefined or :error/, fn ->
        Context.new(%{}, on_unbound: :nope)
      end
    end
  end

  describe "bind/3" do
    test "binds a new key" do
      context = Context.new(%{"a" => 1})

      assert Context.bind(context, "b", 2).data == %{"a" => 1, "b" => 2}
    end

    test "overwrites an existing key" do
      context = Context.new(%{"a" => 1})

      assert Context.bind(context, "a", 2).data == %{"a" => 2}
    end

    test "leaves functions and on_unbound untouched" do
      context = Context.new(%{}, on_unbound: :error)
      bound = Context.bind(context, "a", 1)

      assert bound.functions === context.functions
      assert bound.on_unbound == :error
    end
  end

  describe "assign/3 with a string expression" do
    test "simple identifier" do
      context = Context.new(%{})
      assert {:ok, bound} = Context.assign(context, "user", "Ada")

      assert bound.data == %{"user" => "Ada"}
    end

    test "property access" do
      context = Context.new(%{"user" => %{}})
      assert {:ok, bound} = Context.assign(context, "user.name", "Ada")

      assert bound.data == %{"user" => %{"name" => "Ada"}}
    end

    test "bracket access" do
      context = Context.new(%{"items" => [1, 2, 3]})
      assert {:ok, bound} = Context.assign(context, "items[1]", "x")

      assert bound.data == %{"items" => [1, "x", 3]}
    end

    test "nested vivifying path" do
      context = Context.new(%{})
      assert {:ok, bound} = Context.assign(context, "user.profile.name", "Ada")

      assert bound.data == %{"user" => %{"profile" => %{"name" => "Ada"}}}
    end
  end

  describe "assign/3 with an already-resolved path" do
    test "skips expression resolution" do
      context = Context.new(%{"items" => [1, 2, 3]})
      assert {:ok, bound} = Context.assign(context, ["items", 1], "x")

      assert bound.data == %{"items" => [1, "x", 3]}
    end
  end

  describe "assign/3 errors" do
    test "non-assignable expression returns a LocationError" do
      context = Context.new(%{"items" => [1, 2, 3]})

      assert {:error, %LocationError{type: :not_assignable}} =
               Context.assign(context, "len(items)", 1)
    end

    test "write-time collision returns a LocationError" do
      context = Context.new(%{"user" => 5})

      assert {:error, %LocationError{type: :not_a_container}} =
               Context.assign(context, "user.name", "Ada")
    end
  end

  describe "Evaluator.evaluate_prepared/1" do
    test "does not consult the builtins, only evaluator.functions" do
      evaluator = %Evaluator{
        instructions: [["lit", 42]],
        context: %{},
        functions: %{"nonstandard" => {0, fn [], _ctx -> {:ok, :ignored} end}}
      }

      assert Evaluator.evaluate_prepared(evaluator) == 42
    end
  end
end
