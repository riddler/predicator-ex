defmodule Predicator.EvaluatorUnboundTest do
  use ExUnit.Case, async: true

  alias Predicator.Errors.{TypeMismatchError, UndefinedVariableError}
  alias Predicator.Evaluator

  describe "unbound_loads/1" do
    test "records executed unbound loads in execution order" do
      evaluator = %Evaluator{
        instructions: [["load", "a"], ["load", "b"], ["load", "c"]],
        context: %{"b" => 1}
      }

      {:ok, _result, final} = Evaluator.run_prepared(evaluator)
      assert Evaluator.unbound_loads(final) == ["a", "c"]
    end

    test "does not record a name bound to :undefined" do
      evaluator = %Evaluator{
        instructions: [["load", "a"]],
        context: %{"a" => :undefined}
      }

      {:ok, :undefined, final} = Evaluator.run_prepared(evaluator)
      assert Evaluator.unbound_loads(final) == []
    end

    test "does not record a name bound under an atom key" do
      # Intentional asymmetry for this Context-bypassing, low-level API
      # (px-8um.2): load_from_context/2 no longer falls back to an atom key,
      # so the *value* comes back :undefined - the string key "score" is
      # genuinely absent from this hand-built context. But resolve_key/2
      # (deliberately out of scope for px-8um.2 - it powers Context.bound?/2
      # and unbound-load bookkeeping, a presence check, not a value read)
      # still finds the atom key :score present, so unbound_loads stays []
      # rather than recording "score". This asymmetry is only reachable by
      # bypassing Predicator.Context.new/2; Predicator.evaluate/3's
      # unbound_loads reporting only ever sees Context.new/2-normalized data,
      # where the atom key would already be a string key and both checks
      # would agree.
      evaluator = %Evaluator{instructions: [["load", "score"]], context: %{score: 85}}

      {:ok, :undefined, final} = Evaluator.run_prepared(evaluator)
      assert Evaluator.unbound_loads(final) == []
    end

    test "records a repeated unbound load once" do
      evaluator = %Evaluator{instructions: [["load", "a"], ["load", "a"]], context: %{}}

      {:ok, :undefined, final} = Evaluator.run_prepared(evaluator)
      assert Evaluator.unbound_loads(final) == ["a"]
    end

    test "is empty for a program with no loads" do
      {:ok, 42, final} = Evaluator.run_prepared(%Evaluator{instructions: [["lit", 42]]})
      assert Evaluator.unbound_loads(final) == []
    end

    test "survives a failing run - run_prepared/1 returns the state on the error path" do
      evaluator = %Evaluator{
        instructions: [["load", "a"], ["load", "b"], ["not"]],
        context: %{"a" => 1}
      }

      assert {:error, %Predicator.Errors.TypeMismatchError{}, final} =
               Evaluator.run_prepared(evaluator)

      assert Evaluator.unbound_loads(final) == ["b"]
    end
  end

  describe "unbound_loads_with_locations/1" do
    test "a covered index records its {line, column}" do
      evaluator = %Evaluator{
        instructions: [["load", "a"]],
        context: %{},
        positions: %{0 => {1, 1}}
      }

      {:ok, :undefined, final} = Evaluator.run_prepared(evaluator)
      assert Evaluator.unbound_loads_with_locations(final) == [{"a", {1, 1}}]
    end

    test "an uncovered index records nil" do
      evaluator = %Evaluator{
        instructions: [["load", "a"]],
        context: %{},
        positions: %{1 => {1, 1}}
      }

      {:ok, :undefined, final} = Evaluator.run_prepared(evaluator)
      assert Evaluator.unbound_loads_with_locations(final) == [{"a", nil}]
    end

    test "an absent positions table records nil" do
      evaluator = %Evaluator{instructions: [["load", "a"]], context: %{}}

      {:ok, :undefined, final} = Evaluator.run_prepared(evaluator)
      assert Evaluator.unbound_loads_with_locations(final) == [{"a", nil}]
    end

    test "a span table records the span unchanged, not narrowed to its start" do
      evaluator = %Evaluator{
        instructions: [["load", "a"]],
        context: %{},
        positions: %{0 => {{1, 1}, {1, 2}}}
      }

      {:ok, :undefined, final} = Evaluator.run_prepared(evaluator)
      assert Evaluator.unbound_loads_with_locations(final) == [{"a", {{1, 1}, {1, 2}}}]
    end

    test "a repeated load keeps the first occurrence's location" do
      evaluator = %Evaluator{
        instructions: [["load", "a"], ["load", "a"]],
        context: %{},
        positions: %{0 => {1, 1}, 1 => {1, 9}}
      }

      {:ok, :undefined, final} = Evaluator.run_prepared(evaluator)
      assert Evaluator.unbound_loads_with_locations(final) == [{"a", {1, 1}}]
    end
  end

  describe "evaluate/3 with on_unbound: :error" do
    test "an unbound root errors instead of loading :undefined" do
      assert Evaluator.evaluate([["load", "x"]], %{}, on_unbound: :error) ==
               {:error, UndefinedVariableError.new("x")}
    end

    test "the same call without the option keeps today's :undefined" do
      assert Evaluator.evaluate([["load", "x"]], %{}) == :undefined
    end

    test "bound to :undefined is bound - presence, not value" do
      assert Evaluator.evaluate([["load", "x"]], %{"x" => :undefined}, on_unbound: :error) ==
               :undefined
    end

    test "bound to nil is bound too - only Context.new/2 normalizes nil" do
      assert Evaluator.evaluate([["load", "x"]], %{"x" => nil}, on_unbound: :error) == nil
    end

    test "a hand-built atom key resolves as bound, so the policy does not fire" do
      assert Evaluator.evaluate([["load", "x"]], %{x: 1}, on_unbound: :error) == :undefined
    end

    test "an unrecognized policy value behaves as the default - no validation here" do
      assert Evaluator.evaluate([["load", "x"]], %{}, on_unbound: :bogus) == :undefined
    end

    test "evaluate!/3 raises where it returned :undefined before" do
      assert_raise RuntimeError, fn ->
        Evaluator.evaluate!([["load", "x"]], %{}, on_unbound: :error)
      end
    end
  end

  describe "null as a value (px-o9v)" do
    # D2's four-row comparison matrix. Driven through evaluate/3 on a bare
    # map - the bypass path that already carries a raw nil into the
    # evaluator with no Context involvement.

    test "null === undefined is false" do
      instructions = [["load", "x"], ["lit", :undefined], ["compare", "STRICT_EQ"]]
      assert Evaluator.evaluate(instructions, %{"x" => nil}) == false
    end

    test "null == undefined is :undefined" do
      instructions = [["load", "x"], ["lit", :undefined], ["compare", "EQ"]]
      assert Evaluator.evaluate(instructions, %{"x" => nil}) == :undefined
    end

    test "null === null is true" do
      instructions = [["load", "x"], ["load", "y"], ["compare", "STRICT_EQ"]]
      assert Evaluator.evaluate(instructions, %{"x" => nil, "y" => nil}) == true
    end

    test "null == null is :undefined - null has no type peer under a typed comparison" do
      instructions = [["load", "x"], ["load", "y"], ["compare", "EQ"]]
      assert Evaluator.evaluate(instructions, %{"x" => nil, "y" => nil}) == :undefined
    end

    # The three former crash sites (ADR-0004): get_value_type/1 had no nil
    # clause, so each of these raised FunctionClauseError before this phase.
    # Now every one returns a TypeMismatchError value naming :null.

    test "not null is a TypeMismatchError naming :null, not a raise" do
      instructions = [["load", "x"], ["not"]]

      assert {:error, %TypeMismatchError{got: :null}} =
               Evaluator.evaluate(instructions, %{"x" => nil})
    end

    test "null + 1 is a TypeMismatchError naming :null, not a raise" do
      instructions = [["load", "x"], ["lit", 1], ["add"]]

      assert {:error, %TypeMismatchError{got: {:null, :integer}}} =
               Evaluator.evaluate(instructions, %{"x" => nil})
    end

    test "-null (unary_minus) is a TypeMismatchError naming :null, not a raise" do
      instructions = [["load", "x"], ["unary_minus"]]

      assert {:error, %TypeMismatchError{got: :null}} =
               Evaluator.evaluate(instructions, %{"x" => nil})
    end

    # D4: null joins false and :undefined as falsy at the three jumps. This is
    # also the resolution of the third former crash site ("a jump opcode") -
    # it no longer reaches get_value_type/1 at all, because the widened guard
    # catches it first.

    test "jump_if_falsy_or_pop with null on top jumps, leaving null as the result" do
      instructions = [["load", "x"], ["jump_if_falsy_or_pop", 3], ["lit", 1], ["divide"]]
      assert Evaluator.evaluate(instructions, %{"x" => nil}) == nil
    end

    test "jump_if_true_or_pop with null on top pops and falls through" do
      instructions = [["load", "x"], ["jump_if_true_or_pop", 2], ["lit", 5]]
      assert Evaluator.evaluate(instructions, %{"x" => nil}) == 5
    end

    test "pop_jump_if_falsy with null on top pops it and jumps, leaving the prior value" do
      instructions = [
        ["lit", 1],
        ["load", "x"],
        ["pop_jump_if_falsy", 3],
        ["lit", 999],
        ["divide"]
      ]

      assert Evaluator.evaluate(instructions, %{"x" => nil}) == 1
    end

    # D2a: membership is the one place null behaves as a value, not an
    # absence - values_equal?(nil, nil) is identity, so `in` answers a
    # boolean rather than propagating :undefined the way it does for
    # :undefined itself.

    test "null in [null] is true" do
      instructions = [["load", "x"], ["lit", [nil]], ["in"]]
      assert Evaluator.evaluate(instructions, %{"x" => nil}) == true
    end

    test "null in [1] is false" do
      instructions = [["load", "x"], ["lit", [1]], ["in"]]
      assert Evaluator.evaluate(instructions, %{"x" => nil}) == false
    end

    # cast and access: no new code, both already total over null before this
    # phase (Cast's rule-2 catch-all, access_value/3's existing branch).

    test "null::string is :undefined, not the string \"null\"" do
      instructions = [["load", "x"], ["cast", "string"]]
      assert Evaluator.evaluate(instructions, %{"x" => nil}) == :undefined
    end

    test "null.foo is :undefined, same as accessing into a non-map" do
      instructions = [["load", "x"], ["access", "foo"]]
      assert Evaluator.evaluate(instructions, %{"x" => nil}) == :undefined
    end
  end
end
