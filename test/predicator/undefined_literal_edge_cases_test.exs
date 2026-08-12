defmodule Predicator.UndefinedLiteralEdgeCasesTest do
  @moduledoc """
  Edge cases for the `undefined` literal (px-ocp). None of this is new
  behaviour - `:undefined` already had these semantics when it arrived via a
  `load`; these tests pin that the same semantics hold now that `undefined`
  is reachable directly from source as a `lit`.
  """

  use ExUnit.Case, async: true

  alias Predicator.Errors.TypeMismatchError

  describe "!undefined" do
    test "is a TypeMismatchError - logical NOT requires a boolean" do
      assert {:error, %TypeMismatchError{operation: :logical_not, got: :undefined}} =
               Predicator.evaluate("!undefined")
    end
  end

  describe "undefined in [1, 2]" do
    test "is :undefined - membership short-circuits on an undefined operand" do
      assert Predicator.evaluate("undefined in [1, 2]") == {:ok, :undefined}
    end
  end

  describe "undefined AND true" do
    test "is falsy, not an error" do
      assert Predicator.evaluate("undefined AND true") == {:ok, :undefined}
    end
  end
end
