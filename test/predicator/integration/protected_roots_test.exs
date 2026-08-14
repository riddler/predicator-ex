defmodule Predicator.Integration.ProtectedRootsTest do
  @moduledoc """
  End-to-end coverage for the `:protected_roots` evaluation option
  (px-1xy), through `Predicator.execute/3` and `Predicator.execute_value/3`.

  `test/predicator/evaluator/store_test.exs` covers the refusal at the
  opcode; this file covers the host-facing contract the bead asks for: the
  partial context on the error arm, that later statements never observe the
  refused write, and that a write-then-restore program still errors (the
  case a post-hoc diff misses).
  """

  use ExUnit.Case, async: true

  alias Predicator.Errors.EvaluationError

  describe "Predicator.execute/3 refuses mid-program" do
    test "the partial context carries every earlier write and none of the later ones" do
      assert {:error, %EvaluationError{reason: "protected_root", details: %{root: "_event"}}, ctx} =
               Predicator.execute("x = 1; _event = 2; y = 3", %{}, protected_roots: ["_event"])

      assert ctx.data == %{"x" => 1}
    end

    test "later statements do not observe the refused write" do
      assert {:error, %EvaluationError{reason: "protected_root"}, ctx} =
               Predicator.execute("_event = 1; z = _event", %{}, protected_roots: ["_event"])

      assert ctx.data == %{}
    end

    test "a write-then-restore program still errors - the case a post-hoc diff misses" do
      assert {:error, %EvaluationError{reason: "protected_root"}, ctx} =
               Predicator.execute(
                 "_event = 1; _event = 'original'",
                 %{"_event" => "original"},
                 protected_roots: ["_event"]
               )

      assert ctx.data == %{"_event" => "original"}
    end

    test "a nested write under a protected root refuses" do
      assert {:error, %EvaluationError{reason: "protected_root", details: %{root: "_event"}},
              _ctx} =
               Predicator.execute("a = 1; _event.name = 2; b = 3", %{},
                 protected_roots: ["_event"]
               )
    end
  end

  describe "Predicator.execute_value/3 returns the same error arm" do
    test "the three-tuple shape matches execute/3's" do
      assert {:error, %EvaluationError{reason: "protected_root", details: %{root: "_event"}}, ctx} =
               Predicator.execute_value("x = 1; _event = 2", %{}, protected_roots: ["_event"])

      assert ctx.data == %{"x" => 1}
    end
  end

  describe "absent the option, behavior is unchanged" do
    test "a program that would have refused now succeeds" do
      assert {:ok, ctx} = Predicator.execute("_event = 1; y = 2", %{})
      assert ctx.data == %{"_event" => 1, "y" => 2}
    end

    test "execute_value/3 with no option succeeds as before" do
      assert {:ok, :undefined, ctx} = Predicator.execute_value("_event = 1; y = 2", %{})
      assert ctx.data == %{"_event" => 1, "y" => 2}
    end
  end

  describe "reading a protected root still works - protection is about writes, not reads" do
    test "a protected root that is bound in the incoming context can be loaded" do
      assert {:ok, 5} =
               Predicator.evaluate("_event", %{"_event" => 5}, protected_roots: ["_event"])
    end

    test "a program that only reads a protected root succeeds" do
      assert {:ok, ctx} =
               Predicator.execute("x = _event", %{"_event" => 5}, protected_roots: ["_event"])

      assert ctx.data == %{"_event" => 5, "x" => 5}
    end
  end

  describe "branch-only stores refuse only when the branch actually executes" do
    test "a protected write inside an untaken if-branch does not refuse" do
      assert {:ok, ctx} =
               Predicator.execute(
                 "if false { _event = 1 } else { y = 2 }",
                 %{},
                 protected_roots: ["_event"]
               )

      assert ctx.data == %{"y" => 2}
    end

    test "a protected write inside a taken if-branch refuses" do
      assert {:error, %EvaluationError{reason: "protected_root"}, ctx} =
               Predicator.execute(
                 "if true { _event = 1 } else { y = 2 }",
                 %{},
                 protected_roots: ["_event"]
               )

      assert ctx.data == %{}
    end

    test "a protected write inside a while body that never runs does not refuse" do
      assert {:ok, ctx} =
               Predicator.execute(
                 "i = 0; while i < 0 { _event = 1 }",
                 %{},
                 protected_roots: ["_event"]
               )

      assert ctx.data == %{"i" => 0}
    end
  end

  describe "malformed :protected_roots raises ArgumentError" do
    test "a non-list value" do
      assert_raise ArgumentError, fn ->
        Predicator.execute("x = 1", %{}, protected_roots: "_event")
      end
    end

    test "a list with a non-binary member" do
      assert_raise ArgumentError, fn ->
        Predicator.execute("x = 1", %{}, protected_roots: [:_event])
      end
    end

    test "execute_value/3 raises the same way" do
      assert_raise ArgumentError, fn ->
        Predicator.execute_value("x = 1", %{}, protected_roots: "_event")
      end
    end
  end
end
