defmodule Predicator.Integration.StatementsTest do
  use ExUnit.Case, async: true

  describe "Predicator.execute/2 end to end" do
    test "vivification of a nested map through property access" do
      assert {:ok, ctx} = Predicator.execute("user.profile.name = 'Ada'", %{})
      assert ctx.data == %{"user" => %{"profile" => %{"name" => "Ada"}}}
    end

    test "vivification of a nested list through bracket access" do
      assert {:ok, ctx} = Predicator.execute("user.items[0].name = 'Ada'", %{})
      assert ctx.data == %{"user" => %{"items" => [%{"name" => "Ada"}]}}
    end

    test "a list index past the end pads with :undefined" do
      assert {:ok, ctx} = Predicator.execute("xs[2] = 'z'", %{})
      assert ctx.data == %{"xs" => [:undefined, :undefined, "z"]}
    end

    test "a computed bracket key" do
      assert {:ok, ctx} = Predicator.execute("xs[i + 1] = 'z'", %{"i" => 1})
      assert ctx.data == %{"xs" => [:undefined, :undefined, "z"], "i" => 1}
    end

    test "overwriting an existing leaf" do
      assert {:ok, ctx} = Predicator.execute("x = 2", %{"x" => 1})
      assert ctx.data == %{"x" => 2}
    end

    test "a program whose last statement is an expression, not an assignment" do
      assert {:ok, ctx} = Predicator.execute("x = 1; y = x + 1; y > x", %{})
      assert ctx.data == %{"x" => 1, "y" => 2}
    end

    test "multiple statements building on each other's writes" do
      assert {:ok, ctx} =
               Predicator.execute("total = 0; total = total + 1; total = total + 1", %{})

      assert ctx.data == %{"total" => 2}
    end

    test "a failing statement leaves prior writes intact and later statements unrun" do
      assert {:error, %Predicator.Errors.EvaluationError{reason: "not_a_container"}, ctx} =
               Predicator.execute("a = 1; a.b = 2; c = 3", %{})

      assert ctx.data == %{"a" => 1}
      refute Map.has_key?(ctx.data, "c")
    end
  end
end
