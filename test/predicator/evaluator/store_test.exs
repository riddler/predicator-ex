defmodule Predicator.Evaluator.StoreTest do
  @moduledoc """
  Direct `Evaluator` coverage for the `store` and `pop` opcodes (px-tbv.2).

  These build `%Evaluator{}` structs and drive them through the public
  `Evaluator.run/1`, rather than going through `Predicator.evaluate/3`, so a
  test can inspect the run's final `context` - `store`'s only observable
  effect on the VM's own struct - not just the stack value expression mode
  surfaces. `docs/isa.md` section 5's `store`/`pop` bullets are the
  specification these assert against.
  """

  use ExUnit.Case, async: true

  alias Predicator.Errors.{EvaluationError, TypeMismatchError}
  alias Predicator.Evaluator

  describe "store: writing a root variable" do
    test "writes a new root variable into the context" do
      instructions = [["lit", "x"], ["lit", 42], ["store", 1]]

      assert {:ok, final} = Evaluator.run(%Evaluator{instructions: instructions, context: %{}})
      assert final.context == %{"x" => 42}
      assert final.stack == []
    end

    test "overwrites an existing leaf, whatever it currently holds" do
      instructions = [["lit", "x"], ["lit", 2], ["store", 1]]

      assert {:ok, final} =
               Evaluator.run(%Evaluator{instructions: instructions, context: %{"x" => 1}})

      assert final.context == %{"x" => 2}
    end
  end

  describe "store: auto-vivification" do
    test "vivifies a missing interior slot as a map when the next segment is a string key" do
      instructions = [["lit", "a"], ["lit", "b"], ["lit", 1], ["store", 2]]

      assert {:ok, final} = Evaluator.run(%Evaluator{instructions: instructions, context: %{}})
      assert final.context == %{"a" => %{"b" => 1}}
    end

    test "vivifies a missing interior slot as a list when the next segment is an integer index" do
      instructions = [["lit", "xs"], ["lit", 0], ["lit", 7], ["store", 2]]

      assert {:ok, final} = Evaluator.run(%Evaluator{instructions: instructions, context: %{}})
      assert final.context == %{"xs" => [7]}
    end

    test "an integer index past a list's end pads the gap with :undefined" do
      instructions = [["lit", "xs"], ["lit", 2], ["lit", 7], ["store", 2]]

      context = %{"xs" => [1]}

      assert {:ok, final} =
               Evaluator.run(%Evaluator{instructions: instructions, context: context})

      assert final.context == %{"xs" => [1, :undefined, 7]}
    end
  end

  describe "store: not_assignable" do
    test "[\"store\", 0] pops only the value and writes the empty path - not_assignable" do
      instructions = [["lit", 1], ["store", 0]]

      assert {:error, %EvaluationError{reason: "not_assignable", operation: :store}} =
               Evaluator.run(%Evaluator{instructions: instructions, context: %{}})
    end
  end

  describe "store: not_a_container" do
    test "a path that traverses an existing scalar is not_a_container" do
      instructions = [["lit", "a"], ["lit", "b"], ["lit", 2], ["store", 2]]

      assert {:error, %EvaluationError{reason: "not_a_container", operation: :store}} =
               Evaluator.run(%Evaluator{instructions: instructions, context: %{"a" => 1}})
    end
  end

  describe "store: insufficient_operands" do
    test "fewer than n + 1 values on the stack" do
      instructions = [["lit", "x"], ["store", 1]]

      assert {:error, %EvaluationError{reason: "insufficient_operands", operation: :store}} =
               Evaluator.run(%Evaluator{instructions: instructions, context: %{}})
    end

    test "an empty stack against store 0" do
      instructions = [["store", 0]]

      assert {:error, %EvaluationError{reason: "insufficient_operands", operation: :store}} =
               Evaluator.run(%Evaluator{instructions: instructions, context: %{}})
    end
  end

  describe "store: a non-scalar segment is a TypeMismatchError" do
    test "a boolean segment is rejected: a path segment must be a string or an integer" do
      instructions = [["lit", true], ["lit", 1], ["store", 1]]

      assert {:error, %TypeMismatchError{operation: :store, expected: :string, got: :boolean}} =
               Evaluator.run(%Evaluator{instructions: instructions, context: %{}})
    end

    test "an :undefined segment (an unbound computed bracket key) is rejected" do
      instructions = [["lit", :undefined], ["lit", 1], ["store", 1]]

      assert {:error, %TypeMismatchError{operation: :store, expected: :string}} =
               Evaluator.run(%Evaluator{instructions: instructions, context: %{}})
    end

    test "the message names both accepted segment types" do
      instructions = [["lit", true], ["lit", 1], ["store", 1]]

      assert {:error, %TypeMismatchError{message: message}} =
               Evaluator.run(%Evaluator{instructions: instructions, context: %{}})

      assert message == "Store requires a string or an integer, got true (boolean)"
    end
  end

  describe "store: malformed operands fall to unknown_instruction" do
    test "a negative n" do
      instructions = [["store", -1]]

      assert {:error, %EvaluationError{reason: "unknown_instruction"}} =
               Evaluator.run(%Evaluator{instructions: instructions, context: %{}})
    end

    test "a non-integer n" do
      instructions = [["store", "2"]]

      assert {:error, %EvaluationError{reason: "unknown_instruction"}} =
               Evaluator.run(%Evaluator{instructions: instructions, context: %{}})
    end
  end

  describe "store: a wrapped LocationError reads the position table at the store's own instruction index" do
    test "not_a_container carries the [\"store\", n] instruction's position" do
      instructions = [["lit", "a"], ["lit", "b"], ["lit", 2], ["store", 2]]
      # This list is hand-built, so this pins the evaluator-side lookup (a
      # store error reads the table at the store's own index, here 3) and not
      # the compiler's choice of blame token, which
      # instructions_visitor_positions_test.exs pins.
      positions = %{3 => {5, 9}}

      assert {:error, error} =
               Evaluator.run(%Evaluator{
                 instructions: instructions,
                 context: %{"a" => 1},
                 positions: positions
               })

      assert %EvaluationError{reason: "not_a_container", position: {5, 9}} = error
    end

    test "insufficient_operands reads the same table entry" do
      instructions = [["lit", "a"], ["store", 2]]
      positions = %{1 => {7, 3}}

      assert {:error, %EvaluationError{reason: "insufficient_operands", position: {7, 3}}} =
               Evaluator.run(%Evaluator{
                 instructions: instructions,
                 context: %{},
                 positions: positions
               })
    end
  end

  describe "pop" do
    test "discards the stack top and pushes nothing" do
      instructions = [["lit", 1], ["pop"], ["lit", 2]]

      assert {:ok, final} = Evaluator.run(%Evaluator{instructions: instructions, context: %{}})
      assert final.stack == [2]
    end

    test "an empty stack is insufficient_operands" do
      instructions = [["pop"]]

      assert {:error, %EvaluationError{reason: "insufficient_operands", operation: :pop}} =
               Evaluator.run(%Evaluator{instructions: instructions, context: %{}})
    end

    test "a malformed operand falls to unknown_instruction" do
      instructions = [["lit", 1], ["pop", 1]]

      assert {:error, %EvaluationError{reason: "unknown_instruction"}} =
               Evaluator.run(%Evaluator{instructions: instructions, context: %{}})
    end
  end
end
