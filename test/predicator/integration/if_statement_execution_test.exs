defmodule Predicator.Integration.IfStatementExecutionTest do
  use ExUnit.Case, async: true

  alias Predicator.Errors.TypeMismatchError

  describe "Predicator.execute/2 end to end - if/else (ADR-0013)" do
    test "a true condition takes the then branch" do
      assert {:ok, ctx} = Predicator.execute("if x > 1 { y = 2 } else { y = 3 }", %{"x" => 5})
      assert ctx.data == %{"x" => 5, "y" => 2}
    end

    test "a false condition takes the else branch" do
      assert {:ok, ctx} = Predicator.execute("if x > 1 { y = 2 } else { y = 3 }", %{"x" => 0})
      assert ctx.data == %{"x" => 0, "y" => 3}
    end

    test "a false condition with no else runs neither branch's writes" do
      assert {:ok, ctx} = Predicator.execute("if false { y = 2 }", %{})
      refute Map.has_key?(ctx.data, "y")
    end

    test "an else-if chain routes to each of its three arms" do
      source = "if a == 1 { r = 1 } else if a == 2 { r = 2 } else { r = 3 }"

      assert {:ok, ctx} = Predicator.execute(source, %{"a" => 1})
      assert ctx.data["r"] == 1

      assert {:ok, ctx} = Predicator.execute(source, %{"a" => 2})
      assert ctx.data["r"] == 2

      assert {:ok, ctx} = Predicator.execute(source, %{"a" => 3})
      assert ctx.data["r"] == 3
    end

    test "a branch write is visible after the if - the flat scope ADR-0013 requires" do
      assert {:ok, ctx} = Predicator.execute("if true { y = 2 }; z = y + 1", %{})
      assert ctx.data == %{"y" => 2, "z" => 3}
    end

    test "a non-boolean condition is a TypeMismatchError naming pop_jump_if_falsy" do
      assert {:error,
              %TypeMismatchError{operation: :pop_jump_if_falsy, expected: :boolean} = error,
              _ctx} = Predicator.execute("if 1 { x = 1 }", %{})

      assert error.got == :integer
    end

    test "a non-boolean condition blames the if keyword, not the condition" do
      assert {:error, %TypeMismatchError{operation: :pop_jump_if_falsy} = error, _ctx} =
               Predicator.execute(~s|if "a" { y = 1 }|, %{})

      assert error.position == {1, 1}
    end

    test "an unbound condition takes the falsy path, not an error" do
      assert {:ok, ctx} = Predicator.execute("if unbound { x = 1 } else { x = 2 }", %{})
      assert ctx.data == %{"x" => 2}
    end
  end

  describe "Predicator.execute_value/2 end to end - if/else (ADR-0013)" do
    test "reports the value of the last expression statement executed inside a taken branch" do
      assert {:ok, 2, ctx} = Predicator.execute_value("x = 1; if true { x + 1 }", %{})
      assert ctx.data == %{"x" => 1}
    end
  end
end
