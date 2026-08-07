defmodule Predicator.InstructionsTest do
  use ExUnit.Case, async: true

  doctest Predicator.Instructions

  alias Predicator.Errors.EvaluationError
  alias Predicator.Instructions

  describe "isa_version/0" do
    test "returns 2" do
      assert Instructions.isa_version() == 2
    end

    test "returns an integer, not a string or a Version struct" do
      assert is_integer(Instructions.isa_version())
    end
  end

  describe "in_isa?/2 - live entries (no :removed_in)" do
    test "at exactly the introducing version" do
      assert Instructions.in_isa?(%{isa: 1, tier: 1}, 1)
    end

    test "above the introducing version" do
      assert Instructions.in_isa?(%{isa: 1, tier: 1}, 5)
    end

    test "below the introducing version" do
      refute Instructions.in_isa?(%{isa: 2, tier: 3}, 1)
    end
  end

  describe "in_isa?/2 - retired entries (with :removed_in)" do
    test "before the removing version" do
      assert Instructions.in_isa?(%{isa: 1, tier: 1, removed_in: 3}, 2)
    end

    test "at the introducing version" do
      assert Instructions.in_isa?(%{isa: 1, tier: 1, removed_in: 3}, 1)
    end

    test "at exactly the removing version is out - the interval is half-open" do
      refute Instructions.in_isa?(%{isa: 1, tier: 1, removed_in: 3}, 3)
    end

    test "after the removing version" do
      refute Instructions.in_isa?(%{isa: 1, tier: 1, removed_in: 3}, 4)
    end

    test "one version below the removing version is the last one still in" do
      assert Instructions.in_isa?(%{isa: 1, tier: 1, removed_in: 3}, 2)
    end
  end

  describe "opcode_set/1" do
    test "opcode_set(1) excludes the three v2-only opcodes" do
      set = Instructions.opcode_set(1)
      refute MapSet.member?(set, "jump_if_falsy_or_pop")
      refute MapSet.member?(set, "jump_if_true_or_pop")
      refute MapSet.member?(set, "make_list")
    end

    test "opcode_set(1) contains a v1 opcode" do
      assert MapSet.member?(Instructions.opcode_set(1), "lit")
    end

    test "opcode_set(2) is all 25 opcodes" do
      assert MapSet.size(Instructions.opcode_set(2)) == 25
    end

    test "opcode_set(2) equals Map.keys(opcodes()) today - nothing is retired yet" do
      assert Instructions.opcode_set(2) == MapSet.new(Map.keys(Instructions.opcodes()))
    end
  end

  describe "retired_in/1" do
    test "every live opcode returns {:ok, nil}" do
      for opcode <- Map.keys(Instructions.opcodes()) do
        assert Instructions.retired_in(opcode) == {:ok, nil}
      end
    end

    test "an unrecognized opcode returns an unknown_opcode error" do
      assert {:error, %EvaluationError{reason: "unknown_opcode", operation: :retired_in}} =
               Instructions.retired_in("nope")
    end

    test "the message names the offending opcode" do
      {:error, error} = Instructions.retired_in("nope")
      assert String.contains?(error.message, "nope")
    end
  end

  # No opcode currently carries :removed_in - px-tbv.9 flips this
  # intentionally when it retires "and"/"or", the mirror of the "store is
  # currently an unknown opcode" test above.
  test "no opcode currently carries :removed_in" do
    refute Enum.any?(Instructions.opcodes(), fn {_opcode, info} ->
             Map.has_key?(info, :removed_in)
           end)
  end

  describe "required_isa/1 - happy paths" do
    test "an empty list returns {:ok, 1}" do
      assert Instructions.required_isa([]) == {:ok, 1}
    end

    test "a single v1 opcode returns {:ok, 1}" do
      assert Instructions.required_isa([["lit", 1]]) == {:ok, 1}
    end

    test "make_list returns {:ok, 2}" do
      assert Instructions.required_isa([["make_list", 2]]) == {:ok, 2}
    end

    test "jump_if_falsy_or_pop returns {:ok, 2}" do
      assert Instructions.required_isa([["jump_if_falsy_or_pop", 3]]) == {:ok, 2}
    end

    test "jump_if_true_or_pop returns {:ok, 2}" do
      assert Instructions.required_isa([["jump_if_true_or_pop", 3]]) == {:ok, 2}
    end

    test "a mixed list returns the maximum, v2 opcode in the middle" do
      instructions = [["lit", 1], ["make_list", 1], ["lit", 2]]
      assert Instructions.required_isa(instructions) == {:ok, 2}
    end

    test "a mixed list returns the maximum, v2 opcode at the end" do
      instructions = [["lit", 1], ["lit", 2], ["make_list", 2]]
      assert Instructions.required_isa(instructions) == {:ok, 2}
    end

    test "real compiler output: a > 1 is v1" do
      assert Instructions.required_isa(Predicator.compile!("a > 1")) == {:ok, 1}
    end

    test "real compiler output: a and b is v2 (compiler emits jumps)" do
      assert Instructions.required_isa(Predicator.compile!("a and b")) == {:ok, 2}
    end

    test "real compiler output: an all-literal list is v1" do
      assert Instructions.required_isa(Predicator.compile!("[1, 2, 3]")) == {:ok, 1}
    end

    test "real compiler output: a non-literal-element list forces make_list, v2" do
      assert Instructions.required_isa(Predicator.compile!("[a, 2]")) == {:ok, 2}
    end
  end

  describe "required_isa/1 - the no-recursion guarantee" do
    test "a list literal whose value spells a v1 opcode name stays v1" do
      assert Instructions.required_isa([["lit", ["load", "x"]]]) == {:ok, 1}
    end

    test "a list literal whose value spells a v2 opcode name stays v1" do
      assert Instructions.required_isa([["lit", ["make_list", 3]]]) == {:ok, 1}
    end

    test "an object literal keyed on an opcode name stays v1" do
      assert Instructions.required_isa([["lit", %{"jump_if_true_or_pop" => 1}]]) == {:ok, 1}
    end

    test "a real nested-operand instruction (duration) stays v1" do
      assert Instructions.required_isa([["duration", [[1, "d"]]]]) == {:ok, 1}
    end
  end

  describe "required_isa/1 - errors" do
    test "an unknown opcode returns an unknown_opcode error" do
      assert {:error, %EvaluationError{reason: "unknown_opcode", operation: :required_isa}} =
               Instructions.required_isa([["nope"]])
    end

    test "the message names the offending opcode" do
      {:error, error} = Instructions.required_isa([["nope"]])
      assert String.contains?(error.message, "nope")
    end

    test "the message names the ISA version this build supports" do
      {:error, error} = Instructions.required_isa([["nope"]])
      assert String.contains?(error.message, "nope")
      assert String.contains?(error.message, "ISA v#{Instructions.isa_version()}")
    end

    # "store" is the reserved v-next opcode name (docs/isa.md section 6) and
    # is not in the map yet - px-tbv.2 adds it, at which point this
    # expectation flips intentionally rather than by accident.
    test "store is currently an unknown opcode" do
      assert {:error, %EvaluationError{reason: "unknown_opcode"}} =
               Instructions.required_isa([["store", 0]])
    end

    # "pop" is the statement-boundary opcode reserved beside "store"
    # (docs/isa.md section 6) and is not in the map yet - px-tbv.2 adds it,
    # at which point this expectation flips intentionally rather than by
    # accident.
    test "pop is currently an unknown opcode" do
      assert {:error, %EvaluationError{reason: "unknown_opcode"}} =
               Instructions.required_isa([["pop"]])
    end

    test "the first bad opcode wins when there are two" do
      {:error, error} = Instructions.required_isa([["nope"], ["also_nope"]])
      assert String.contains?(error.message, "nope")
      refute String.contains?(error.message, "also_nope")
    end

    test "an empty list element is malformed" do
      assert {:error, %EvaluationError{reason: "malformed_instruction", operation: :required_isa}} =
               Instructions.required_isa([[]])
    end

    test "a non-list element is malformed" do
      assert {:error, %EvaluationError{reason: "malformed_instruction"}} =
               Instructions.required_isa([["lit", 1], "not_a_list"])
    end

    test "a numeric head is malformed" do
      assert {:error, %EvaluationError{reason: "malformed_instruction"}} =
               Instructions.required_isa([[42]])
    end

    test "an atom head is malformed" do
      assert {:error, %EvaluationError{reason: "malformed_instruction"}} =
               Instructions.required_isa([[:lit, 1]])
    end

    test "the message names the index of the offending element" do
      {:error, error} = Instructions.required_isa([["lit", 1], []])
      assert String.contains?(error.message, "1")
    end

    test "an error anywhere wins over an {:ok, 2} earlier in the list" do
      assert {:error, %EvaluationError{reason: "unknown_opcode"}} =
               Instructions.required_isa([["make_list", 2], ["nope"]])
    end
  end
end
