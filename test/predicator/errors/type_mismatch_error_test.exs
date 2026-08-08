defmodule Predicator.Errors.TypeMismatchErrorTest do
  use ExUnit.Case, async: true

  alias Predicator.Errors.TypeMismatchError

  doctest TypeMismatchError

  describe "unary/4 delegates to unary/5" do
    test "produces the same message as unary/5 with the default expected-type text" do
      via_arity4 = TypeMismatchError.unary(:unary_minus, :integer, :string, "text")

      via_arity5 =
        TypeMismatchError.unary(
          :unary_minus,
          :integer,
          :string,
          "text",
          Predicator.Errors.expected_type_name(:integer)
        )

      assert via_arity4 == via_arity5
      assert via_arity4.message == "Unary minus requires an integer, got \"text\" (string)"
    end
  end
end
