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

    test "defaults segment_positions to an empty map too" do
      compiled = Compiled.new([["lit", 1]], %{0 => {1, 1}})

      assert compiled.segment_positions == %{}
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

  describe "new/3" do
    test "sets segment_positions alongside instructions and positions" do
      instructions = [["lit", "a"], ["lit", "b"], ["lit", 1], ["store", 2]]
      positions = %{0 => {1, 1}, 1 => {1, 2}, 2 => {1, 7}, 3 => {1, 1}}
      segment_positions = %{3 => [{1, 1}, {1, 2}]}

      compiled = Compiled.new(instructions, positions, segment_positions)

      assert compiled.instructions == instructions
      assert compiled.positions == positions
      assert compiled.segment_positions == segment_positions
    end
  end

  describe "struct defaults" do
    test "%Predicator.Compiled{} defaults instructions to [], positions to %{}, and segment_positions to %{}" do
      compiled = %Compiled{}

      assert compiled.instructions == []
      assert compiled.positions == %{}
      assert compiled.segment_positions == %{}
    end
  end
end
