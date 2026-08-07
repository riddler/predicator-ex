defmodule Predicator.Conformance.FeaturesTest do
  use ExUnit.Case, async: true

  doctest Predicator.Conformance.Features

  alias Predicator.Conformance.Features
  alias Predicator.Errors.{EvaluationError, TypeMismatchError, UndefinedVariableError}

  describe "compute/4 - opcode-derived tags" do
    test "lit, load, not, and unary_bang carry no tag of their own" do
      assert Features.compute([["lit", 1]], %{}, {:result, 1}, []) == []
      assert Features.compute([["load", "x"]], %{"x" => 1}, {:result, 1}, []) == []
      assert Features.compute([["lit", true], ["not"]], %{}, {:result, false}, []) == []
      assert Features.compute([["lit", true], ["unary_bang"]], %{}, {:result, false}, []) == []
    end

    test "compare tags comparison; a strict operator also tags strict_equality" do
      assert Features.compute([["compare", "GT"]], %{}, {:result, true}, []) == ["comparison"]

      assert Features.compute([["compare", "STRICT_EQ"]], %{}, {:result, true}, []) == [
               "comparison",
               "strict_equality"
             ]

      assert Features.compute([["compare", "STRICT_NEQ"]], %{}, {:result, true}, []) == [
               "comparison",
               "strict_equality"
             ]
    end

    test "the short-circuit jumps tag short_circuit" do
      assert Features.compute([["jump_if_falsy_or_pop", 2]], %{}, {:result, true}, []) == [
               "short_circuit"
             ]

      assert Features.compute([["jump_if_true_or_pop", 2]], %{}, {:result, true}, []) == [
               "short_circuit"
             ]
    end

    test "the legacy and/or opcodes tag legacy_logical, not short_circuit" do
      assert Features.compute([["and"]], %{}, {:result, true}, []) == ["legacy_logical"]
      assert Features.compute([["or"]], %{}, {:result, true}, []) == ["legacy_logical"]
    end

    test "the five arithmetic opcodes and unary_minus tag arithmetic" do
      for opcode <- ["add", "subtract", "multiply", "divide", "modulo", "unary_minus"] do
        assert Features.compute([[opcode]], %{}, {:result, 1}, []) == ["arithmetic"]
      end
    end

    test "in and contains tag membership" do
      assert Features.compute([["in"]], %{}, {:result, true}, []) == ["membership"]
      assert Features.compute([["contains"]], %{}, {:result, true}, []) == ["membership"]
    end

    test "access, bracket_access, and make_list tag access" do
      for opcode <- ["access", "bracket_access", "make_list"] do
        assert Features.compute([[opcode]], %{}, {:result, 1}, []) == ["access"]
      end
    end

    test "object_new and object_set tag objects" do
      assert Features.compute([["object_new"]], %{}, {:result, %{}}, []) == ["objects"]
      assert Features.compute([["object_set"]], %{}, {:result, %{}}, []) == ["objects"]
    end

    test "duration tags durations; relative_date tags dates" do
      assert Features.compute([["duration"]], %{}, {:result, 1}, []) == ["durations"]
      assert Features.compute([["relative_date"]], %{}, {:result, 1}, []) == ["dates"]
    end

    test "call tags functions" do
      assert Features.compute([["call"]], %{}, {:result, 1}, []) == ["functions"]
    end

    test "a malformed instruction (not a non-empty list headed by a binary) contributes no tag" do
      assert Features.compute([[]], %{}, {:result, nil}, []) == []
      assert Features.compute([[1, 2]], %{}, {:result, nil}, []) == []
    end
  end

  describe "compute/4 - value-derived tags from context" do
    test "a Date context value tags dates" do
      assert Features.compute([["load", "d"]], %{"d" => ~D[2026-08-06]}, {:result, 1}, []) == [
               "dates"
             ]
    end

    test "a DateTime context value tags datetimes" do
      assert Features.compute(
               [["load", "d"]],
               %{"d" => ~U[2026-08-06T12:00:00Z]},
               {:result, 1},
               []
             ) ==
               ["datetimes"]
    end

    test "a duration-shaped map context value tags durations" do
      duration = Predicator.Duration.new(days: 3)

      assert Features.compute([["load", "d"]], %{"d" => duration}, {:result, 1}, []) == [
               "durations"
             ]
    end

    test "an :undefined context value tags undefined" do
      assert Features.compute([["load", "x"]], %{"x" => :undefined}, {:result, true}, []) == [
               "undefined"
             ]
    end

    test "a plain map context value that is not duration-shaped contributes no tag" do
      assert Features.compute([["load", "x"]], %{"x" => %{"a" => 1}}, {:result, 1}, []) == []
    end
  end

  describe "compute/4 - outcome-derived tags" do
    test "an :undefined result tags undefined" do
      assert Features.compute([["lit", 1]], %{}, {:result, :undefined}, []) == ["undefined"]
    end

    test "a defined result contributes no outcome tag" do
      assert Features.compute([["lit", 1]], %{}, {:result, 1}, []) == []
    end

    test "an UndefinedVariableError tags both errors and undefined" do
      error = UndefinedVariableError.new("x")

      assert Features.compute([["load", "x"]], %{}, {:error, error}, []) == [
               "errors",
               "undefined"
             ]
    end

    test "an EvaluationError tags errors" do
      error = EvaluationError.new("boom", "boom")
      assert Features.compute([["lit", 1]], %{}, {:error, error}, []) == ["errors"]
    end

    test "a TypeMismatchError tags errors" do
      error = TypeMismatchError.unary(:unary_minus, :integer, :string, "x")

      assert Features.compute([["unary_minus"]], %{}, {:error, error}, []) == [
               "arithmetic",
               "errors"
             ]
    end
  end

  describe "compute/4 - authored extras merge in" do
    test "an authored extra tag is added even when nothing computes it" do
      assert Features.compute([["lit", 1]], %{}, {:result, 1}, ["custom"]) == ["custom"]
    end

    test "extras merge with computed tags and the result is deduplicated and sorted" do
      assert Features.compute([["compare", "GT"]], %{}, {:result, true}, ["comparison", "extra"]) ==
               ["comparison", "extra"]
    end
  end
end
