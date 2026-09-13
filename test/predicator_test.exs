defmodule PredicatorTest do
  use ExUnit.Case, async: true

  doctest Predicator

  describe "evaluate/3 - non-ASCII string literals" do
    test "a string literal round-trips byte-identically through the public entry" do
      for value <- ["café", "✓", "🎉", "café ✓ 🎉", "日本語"] do
        assert Predicator.evaluate(~s("#{value}"), %{}) == {:ok, value}
      end
    end

    test "a non-ASCII literal compares equal to the same context value" do
      assert Predicator.evaluate(~s(label == "café"), %{"label" => "café"}) == {:ok, true}
    end

    test "parse/1 carries the literal through unchanged" do
      assert {:ok, ast} = Predicator.parse(~s("✓"))
      assert {:string_literal, "✓", :double, _position} = ast
    end

    test "a \\u escape is refused rather than decoded to the bare letter" do
      assert {:error, %Predicator.Errors.ParseError{message: message}} =
               Predicator.evaluate(~s("\\u0041"), %{})

      assert message =~ "\\u"
    end
  end
end
