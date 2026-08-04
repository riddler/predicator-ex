defmodule Predicator.ContextIntegrationTest do
  use ExUnit.Case, async: true

  alias Predicator.Context

  describe "evaluate/3 against a %Context{}" do
    test "string expression with builtin functions" do
      context = Context.new(%{"name" => "Ada"})

      assert Predicator.evaluate("len(name) > 2", context) == {:ok, true}
    end

    test "string expression with custom functions" do
      custom = %{"double" => {1, fn [n], _ctx -> {:ok, n * 2} end}}
      context = Context.new(%{"score" => 21}, functions: custom)

      assert Predicator.evaluate("double(score)", context) == {:ok, 42}
    end

    test "pre-compiled instructions" do
      context = Context.new(%{"score" => 90})
      {:ok, instructions} = Predicator.compile("score > 85")

      assert Predicator.evaluate(instructions, context) == {:ok, true}
    end
  end

  describe "statifier macrostep/microstep usage" do
    test "build once, rebind _event across microsteps, evaluate a guard after each" do
      context = Context.new(%{})
      {:ok, guard} = Predicator.compile("_event.name = 'go'")

      context_a = Context.bind(context, "_event", %{"name" => "go"})
      context_b = Context.bind(context, "_event", %{"name" => "stop"})

      assert Predicator.evaluate(guard, context_a) == {:ok, true}
      assert Predicator.evaluate(guard, context_b) == {:ok, false}

      # rebind never touches the functions map merged once at Context.new/2
      assert context_a.functions === context.functions
      assert context_b.functions === context.functions
    end
  end

  describe "bare-map backward compatibility" do
    test "bare map and an up-front Context.new/2 produce identical results" do
      expression = "score > 80"
      data = %{"score" => 85}

      assert Predicator.evaluate(expression, data) ==
               Predicator.evaluate(expression, Context.new(data))
    end
  end

  describe "Context.assign/3 feeding into a subsequent evaluate/3 call" do
    test "assign creates user.name, then evaluate reads it" do
      context = Context.new(%{})
      {:ok, context} = Context.assign(context, "user.name", "Ada")

      assert Predicator.evaluate("user.name", context) == {:ok, "Ada"}
    end
  end
end
