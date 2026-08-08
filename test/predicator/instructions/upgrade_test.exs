defmodule Predicator.Instructions.UpgradeTest do
  use ExUnit.Case, async: true

  alias Predicator.Errors.EvaluationError
  alias Predicator.Evaluator
  alias Predicator.Instructions
  alias Predicator.Instructions.Upgrade

  # --------------------------------------------------------------------
  # Equivalence, cashed in from Phase 1: the legacy list is now refused as a
  # retired opcode (Phase 2), and the upgraded form is checked against the
  # boolean answer the two semantics agreed on while both paths still ran.
  # --------------------------------------------------------------------

  describe "equivalence with the legacy evaluator (boolean-only inputs)" do
    test "and over all four boolean combinations" do
      for left <- [true, false], right <- [true, false] do
        legacy = [["lit", left], ["lit", right], ["and"]]
        assert {:ok, upgraded} = Upgrade.upgrade(legacy)

        assert {:error, %EvaluationError{reason: "retired_opcode"}} =
                 Evaluator.evaluate(legacy)

        assert Evaluator.evaluate(upgraded) == (left and right)
      end
    end

    test "or over all four boolean combinations" do
      for left <- [true, false], right <- [true, false] do
        legacy = [["lit", left], ["lit", right], ["or"]]
        assert {:ok, upgraded} = Upgrade.upgrade(legacy)

        assert {:error, %EvaluationError{reason: "retired_opcode"}} =
                 Evaluator.evaluate(legacy)

        assert Evaluator.evaluate(upgraded) == (left or right)
      end
    end

    test "nested: (a and b) or c" do
      for a <- [true, false], b <- [true, false], c <- [true, false] do
        legacy = [
          ["lit", a],
          ["lit", b],
          ["and"],
          ["lit", c],
          ["or"]
        ]

        assert {:ok, upgraded} = Upgrade.upgrade(legacy)

        assert {:error, %EvaluationError{reason: "retired_opcode"}} =
                 Evaluator.evaluate(legacy)

        assert Evaluator.evaluate(upgraded) == ((a and b) or c)
      end
    end

    test "a comparison feeding an and, evaluator_test.exs's composite" do
      legacy = [
        ["load", "score"],
        ["lit", 85],
        ["compare", "GT"],
        ["load", "age"],
        ["lit", 18],
        ["compare", "GTE"],
        ["and"],
        ["load", "admin"],
        ["lit", true],
        ["compare", "EQ"],
        ["or"]
      ]

      for context <- [
            %{"score" => 90, "age" => 20, "admin" => false},
            %{"score" => 90, "age" => 10, "admin" => false},
            %{"score" => 10, "age" => 10, "admin" => true},
            %{"score" => 10, "age" => 10, "admin" => false}
          ] do
        assert {:ok, upgraded} = Upgrade.upgrade(legacy)

        assert {:error, %EvaluationError{reason: "retired_opcode"}} =
                 Evaluator.evaluate(legacy, context)

        expected = (context["score"] > 85 and context["age"] >= 18) or context["admin"] == true
        assert Evaluator.evaluate(upgraded, context) == expected
      end
    end
  end

  # --------------------------------------------------------------------
  # Divergence: the three documented ways the upgraded form differs from
  # the legacy one. Pinned rather than avoided, so Phase 2 keeps the
  # upgraded half and the record of what changed survives.
  # --------------------------------------------------------------------

  describe "divergence 1: short-circuiting" do
    # The legacy list here still fails before it ever reaches the retired
    # ["and"]/["or"] instruction: "load missing" under on_unbound: :error
    # raises UndefinedVariableError at the load itself, since the legacy
    # opcode is non-short-circuiting and both operands are already loaded
    # onto the stack before it runs. This is the divergence being pinned,
    # not a case that exercises the retired_opcode refusal.
    test "and: a falsy left skips a right that would have raised" do
      legacy = [["lit", false], ["load", "missing"], ["and"]]
      upgraded_legacy = [["lit", false], ["jump_if_falsy_or_pop", 2], ["load", "missing"]]

      assert {:ok, upgraded_legacy} == Upgrade.upgrade(legacy)

      assert {:error, %Predicator.Errors.UndefinedVariableError{}} =
               Evaluator.evaluate(legacy, %{}, on_unbound: :error)

      assert Evaluator.evaluate(upgraded_legacy, %{}, on_unbound: :error) == false
    end

    test "or: a true left skips a right that would have raised" do
      legacy = [["lit", true], ["load", "missing"], ["or"]]

      assert {:ok, upgraded} = Upgrade.upgrade(legacy)

      assert {:error, %Predicator.Errors.UndefinedVariableError{}} =
               Evaluator.evaluate(legacy, %{}, on_unbound: :error)

      assert Evaluator.evaluate(upgraded, %{}, on_unbound: :error) == true
    end
  end

  describe "divergence 2: :undefined operands" do
    test "and: undefined and x is :undefined upgraded, TypeMismatchError legacy" do
      legacy = [["lit", :undefined], ["lit", true], ["and"]]

      assert {:ok, upgraded} = Upgrade.upgrade(legacy)
      assert {:error, %EvaluationError{reason: "retired_opcode"}} = Evaluator.evaluate(legacy)
      assert Evaluator.evaluate(upgraded) == :undefined
    end

    test "or: undefined or x is x's value upgraded, TypeMismatchError legacy" do
      legacy = [["lit", :undefined], ["lit", 42], ["or"]]

      assert {:ok, upgraded} = Upgrade.upgrade(legacy)
      assert {:error, %EvaluationError{reason: "retired_opcode"}} = Evaluator.evaluate(legacy)
      assert Evaluator.evaluate(upgraded) == 42
    end
  end

  describe "divergence 3: a non-boolean right operand the left did not decide" do
    test "true and 1 is 1 upgraded, TypeMismatchError legacy" do
      legacy = [["lit", true], ["lit", 1], ["and"]]

      assert {:ok, upgraded} = Upgrade.upgrade(legacy)
      assert {:error, %EvaluationError{reason: "retired_opcode"}} = Evaluator.evaluate(legacy)
      assert Evaluator.evaluate(upgraded) == 1
    end

    test "a non-boolean left is still a TypeMismatchError upgraded" do
      legacy = [["lit", 1], ["lit", true], ["and"]]

      assert {:ok, upgraded} = Upgrade.upgrade(legacy)
      assert {:error, %EvaluationError{reason: "retired_opcode"}} = Evaluator.evaluate(legacy)
      assert {:error, %Predicator.Errors.TypeMismatchError{}} = Evaluator.evaluate(upgraded)
    end
  end

  # --------------------------------------------------------------------
  # Structural
  # --------------------------------------------------------------------

  describe "structural" do
    test "identity on a jump-form list (no legacy opcode present)" do
      instructions = [["lit", true], ["jump_if_falsy_or_pop", 2], ["lit", false]]
      assert Upgrade.upgrade(instructions) == {:ok, instructions}
    end

    test "identity on a list with no logical opcode at all" do
      instructions = [["lit", 1], ["lit", 2], ["add"]]
      assert Upgrade.upgrade(instructions) == {:ok, instructions}
    end

    test "nested rewrite produces correct relative offsets" do
      legacy = [
        ["lit", true],
        ["lit", false],
        ["and"],
        ["lit", true],
        ["or"]
      ]

      assert Upgrade.upgrade(legacy) ==
               {:ok,
                [
                  ["lit", true],
                  ["jump_if_falsy_or_pop", 2],
                  ["lit", false],
                  ["jump_if_true_or_pop", 2],
                  ["lit", true]
                ]}
    end

    test "a multi-value final stack is preserved in order" do
      legacy = [["lit", 1], ["lit", true], ["lit", false], ["and"]]

      assert Upgrade.upgrade(legacy) ==
               {:ok,
                [
                  ["lit", 1],
                  ["lit", true],
                  ["jump_if_falsy_or_pop", 2],
                  ["lit", false]
                ]}
    end
  end

  # --------------------------------------------------------------------
  # Refusals
  # --------------------------------------------------------------------

  describe "refusal: an ISA v2 opcode alongside a retired opcode" do
    test "refuses with unsupported_upgrade" do
      instructions = [["make_list", 0], ["lit", true], ["lit", false], ["and"]]

      assert {:error,
              %EvaluationError{reason: "unsupported_upgrade", operation: :upgrade} = error} =
               Upgrade.upgrade(instructions)

      assert error.message =~ "make_list"
    end
  end

  describe "refusal: stack underflow" do
    test "refuses when an opcode pops more chunks than the stack holds" do
      instructions = [["lit", true], ["and"]]

      assert {:error,
              %EvaluationError{reason: "unsupported_upgrade", operation: :upgrade} = error} =
               Upgrade.upgrade(instructions)

      assert error.message =~ "underflow"
    end
  end

  describe "refusal: an unknown opcode" do
    test "refuses on an opcode not in the ISA v1 table" do
      instructions = [["lit", true], ["lit", false], ["nope"], ["and"]]

      assert {:error,
              %EvaluationError{reason: "unsupported_upgrade", operation: :upgrade} = error} =
               Upgrade.upgrade(instructions)

      assert error.message =~ "nope"
    end

    test "refuses on a call whose count operand is not a non-negative integer" do
      instructions = [
        ["lit", true],
        ["lit", false],
        ["call", "len", "not-a-count"],
        ["and"]
      ]

      assert {:error,
              %EvaluationError{reason: "unsupported_upgrade", operation: :upgrade} = error} =
               Upgrade.upgrade(instructions)

      assert error.message =~ "call"
    end
  end

  describe "refusal: a malformed element" do
    test "refuses on an element that is not a non-empty list headed by a binary" do
      instructions = [["lit", true], [], ["lit", false], ["and"]]

      assert {:error,
              %EvaluationError{reason: "unsupported_upgrade", operation: :upgrade} = error} =
               Upgrade.upgrade(instructions)

      assert error.message =~ "malformed"
    end
  end

  # --------------------------------------------------------------------
  # Pop table
  # --------------------------------------------------------------------

  describe "pops/0" do
    test "its key set matches ISA v1's opcode set exactly" do
      assert MapSet.new(Map.keys(Upgrade.pops())) == Instructions.opcode_set(1)
    end
  end
end
