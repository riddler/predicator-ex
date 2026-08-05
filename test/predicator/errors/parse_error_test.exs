defmodule Predicator.Errors.ParseErrorTest do
  use ExUnit.Case, async: true

  alias Predicator.Errors.ParseError

  describe "new/3" do
    test "populates :line and :column" do
      error = ParseError.new("bad input", 2, 5)

      assert error.message == "bad input"
      assert error.line == 2
      assert error.column == 5
    end

    test "derives :position as a {line, column} tuple matching :line and :column" do
      error = ParseError.new("bad input", 2, 5)

      assert error.position == {2, 5}
      assert error.position == {error.line, error.column}
    end
  end
end
