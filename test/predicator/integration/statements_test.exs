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

    test "a store failure on an interior segment blames that segment, not the lhs root" do
      # px-ids: pinning at the integration layer too, not only in
      # execute_test.exs. `a` is at column 15; the failing segment `.b`'s
      # point position is column 17, the property name `b` itself.
      assert {:error,
              %Predicator.Errors.EvaluationError{reason: "not_a_container", position: {1, 17}},
              ctx} = Predicator.execute(~s(a = {"b": 1}; a.b.c = 2), %{})

      assert ctx.data == %{"a" => %{"b" => 1}}
    end
  end

  describe "Predicator.execute_value/2 end to end" do
    test "a multi-statement program with vivification and a computed bracket key" do
      assert {:ok, "z", ctx} =
               Predicator.execute_value(
                 "user.items[i + 1] = 'z'; user.items[i + 1]",
                 %{"i" => 1}
               )

      assert ctx.data == %{"user" => %{"items" => [:undefined, :undefined, "z"]}, "i" => 1}
    end

    test "a short-circuiting and/or final expression statement reports the statement's value, not the left operand's" do
      assert {:ok, false, ctx} = Predicator.execute_value("flag = false; flag and true", %{})
      assert ctx.data == %{"flag" => false}

      assert {:ok, true, ctx} = Predicator.execute_value("flag = true; flag or false", %{})
      assert ctx.data == %{"flag" => true}
    end
  end

  describe "type-mismatch messages name the source construct, not the opcode" do
    test "if blames the keyword and names the condition rule" do
      assert {:error,
              %Predicator.Errors.TypeMismatchError{
                operation: :pop_jump_if_falsy,
                position: {1, 1},
                message: "Condition requires a boolean, got \"a\" (string)"
              }, _ctx} = Predicator.execute(~s|if "a" { y = 1 }|, %{})
    end

    test "while blames the keyword and names the condition rule" do
      assert {:error,
              %Predicator.Errors.TypeMismatchError{
                operation: :pop_jump_if_falsy,
                position: {1, 1},
                message: "Condition requires a boolean, got \"a\" (string)"
              }, _ctx} = Predicator.execute(~s|while "a" { y = 1 }|, %{})
    end

    test "and names its rule Logical AND, not the short-circuit opcode" do
      assert {:error,
              %Predicator.Errors.TypeMismatchError{
                operation: :jump_if_falsy_or_pop,
                position: {1, 5},
                message: "Logical AND requires a boolean, got \"a\" (string)"
              }, _ctx} = Predicator.execute(~s|"a" and true|, %{})
    end

    test "or names its rule Logical OR, not the short-circuit opcode" do
      assert {:error,
              %Predicator.Errors.TypeMismatchError{
                operation: :jump_if_true_or_pop,
                position: {1, 5},
                message: "Logical OR requires a boolean, got \"a\" (string)"
              }, _ctx} = Predicator.execute(~s|"a" or true|, %{})
    end

    test "a failing store names the rule Assignment, not the opcode" do
      # Duplicates test/predicator/execute_test.exs:204 by design - that test
      # is about which segment is blamed, this one is about the construct
      # name - so both stay.
      assert {:error,
              %Predicator.Errors.TypeMismatchError{
                operation: :store,
                position: {1, 3},
                message: "Assignment requires a string or an integer, got true (boolean)"
              }, _ctx} = Predicator.execute("a[true] = 1", %{})
    end
  end
end
