defmodule Predicator.CompiledTest do
  use ExUnit.Case, async: true

  doctest Predicator.Compiled

  alias Predicator.Compiled

  describe "new/2" do
    test "defaults positions to an empty map" do
      compiled = Compiled.new([["lit", 1]])

      assert compiled.instructions == [["lit", 1]]
      assert compiled.positions == %{}
    end

    test "pairs instructions with a position table" do
      instructions = [["load", "score"], ["lit", 85], ["compare", "GT"]]
      positions = %{0 => {1, 1}, 1 => {1, 9}, 2 => {1, 7}}

      compiled = Compiled.new(instructions, positions)

      assert compiled.instructions == instructions
      assert compiled.positions == positions
    end

    test "pairs instructions with a span table" do
      instructions = [["lit", 42]]
      spans = %{0 => {{1, 1}, {1, 3}}}

      compiled = Compiled.new(instructions, spans)

      assert compiled.instructions == instructions
      assert compiled.positions == spans
    end
  end

  describe "struct defaults" do
    test "%Predicator.Compiled{} defaults instructions to [] and positions to %{}" do
      compiled = %Compiled{}

      assert compiled.instructions == []
      assert compiled.positions == %{}
    end
  end
end
