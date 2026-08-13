defmodule Predicator.Integration.OnUnboundTest do
  use ExUnit.Case, async: true

  alias Predicator.Context
  alias Predicator.Errors.UndefinedVariableError

  setup do
    %{error_context: Context.new(%{}, on_unbound: :error), default: Context.new(%{})}
  end

  describe ":error catches the absorbed cases the default misses" do
    test "an unbound operand a truthy OR would have absorbed", %{
      error_context: error_context,
      default: default
    } do
      assert Predicator.evaluate("missing OR true", default) == {:ok, true}

      assert {:error, %UndefinedVariableError{variable: "missing"}} =
               Predicator.evaluate("missing OR true", error_context)
    end

    test "an unbound element inside a list literal", %{
      error_context: error_context,
      default: default
    } do
      assert Predicator.evaluate("[missing]", default) == {:ok, [:undefined]}

      assert {:error, %UndefinedVariableError{variable: "missing"}} =
               Predicator.evaluate("[missing]", error_context)
    end

    test "an unbound value inside an object literal", %{
      error_context: error_context,
      default: default
    } do
      assert Predicator.evaluate("{'a': missing}", default) == {:ok, %{"a" => :undefined}}

      assert {:error, %UndefinedVariableError{variable: "missing"}} =
               Predicator.evaluate("{'a': missing}", error_context)
    end
  end

  describe ":error agrees with the default where the default already errors" do
    for expression <- [
          "missing",
          "missing == 5",
          "missing AND false",
          "not missing",
          "missing + 1",
          "missing in [1, 2]"
        ] do
      test "#{expression}", %{error_context: error_context, default: default} do
        assert {:error, %UndefinedVariableError{variable: "missing"}} =
                 Predicator.evaluate(unquote(expression), default)

        assert {:error, %UndefinedVariableError{variable: "missing"}} =
                 Predicator.evaluate(unquote(expression), error_context)
      end
    end
  end

  describe "short-circuiting still skips the load (W3C)" do
    test "a falsy AND never executes the load", %{error_context: error_context} do
      assert Predicator.evaluate("false AND missing", error_context) == {:ok, false}
    end

    test "a truthy OR never executes the load", %{error_context: error_context} do
      assert Predicator.evaluate("true OR missing", error_context) == {:ok, true}
    end

    test "a skipped branch does not call a function either" do
      functions = %{"boom" => {0, fn _args, _context -> raise "called" end}}
      context = Context.new(%{}, on_unbound: :error, functions: functions)

      assert Predicator.evaluate("false AND boom()", context) == {:ok, false}
    end

    test "a nested skipped load names only the load that ran (px-8um.8)", %{
      error_context: error_context
    } do
      assert {:error, %UndefinedVariableError{variable: "other_missing"}} =
               Predicator.evaluate("(false AND missing) OR other_missing", error_context)
    end
  end

  describe "roots only" do
    setup do
      %{context: Context.new(%{"user" => %{}, "items" => [1]}, on_unbound: :error)}
    end

    for expression <- ["user.nope", "user['nope']", "items[99]", "user.nope.deeper"] do
      test "#{expression} stays :undefined under :error", %{context: context} do
        assert Predicator.evaluate(unquote(expression), context) == {:ok, :undefined}
      end
    end

    test "an unbound root under an access still errors, naming the root", %{context: context} do
      assert {:error, %UndefinedVariableError{variable: "nope"}} =
               Predicator.evaluate("nope.field", context)
    end
  end

  describe "the error's position" do
    test "points at the variable under either policy", %{
      error_context: error_context,
      default: default
    } do
      assert {:error, %UndefinedVariableError{position: {1, 5}}} =
               Predicator.evaluate("not missing", error_context)

      # px-1e1: the default policy's after-the-run rewrite now uses the location
      # recorded at the load, so it agrees with the :error policy's load site.
      assert {:error, %UndefinedVariableError{position: {1, 5}}} =
               Predicator.evaluate("not missing", default)
    end
  end

  describe "the undefined literal (px-ocp) - the boundness test under both policies" do
    test "x === undefined with x bound to :undefined is true under either policy" do
      assert Predicator.evaluate("x === undefined", %{"x" => :undefined}) == {:ok, true}

      assert Predicator.evaluate(
               "x === undefined",
               Context.new(%{"x" => :undefined}, on_unbound: :error)
             ) == {:ok, true}
    end

    test "x === undefined with x bound to nil is false under either policy - null is not undefined" do
      assert Predicator.evaluate("x === undefined", %{"x" => nil}) == {:ok, false}

      # Under :error, x is present (bound to nil), so the load does not count
      # as unbound and no UndefinedVariableError fires.
      assert Predicator.evaluate(
               "x === undefined",
               Context.new(%{"x" => nil}, on_unbound: :error)
             ) ==
               {:ok, false}
    end

    test "x === undefined with x bound to 1 is false under either policy" do
      assert Predicator.evaluate("x === undefined", %{"x" => 1}) == {:ok, false}

      assert Predicator.evaluate("x === undefined", Context.new(%{"x" => 1}, on_unbound: :error)) ==
               {:ok, false}
    end

    test "user.missing === undefined with user bound to %{} is true under either policy" do
      assert Predicator.evaluate("user.missing === undefined", %{"user" => %{}}) == {:ok, true}

      assert Predicator.evaluate(
               "user.missing === undefined",
               Context.new(%{"user" => %{}}, on_unbound: :error)
             ) == {:ok, true}
    end

    test "x === undefined with x genuinely unbound - the honest boundary" do
      assert Predicator.evaluate("x === undefined", %{}) == {:ok, true}

      assert {:error, %UndefinedVariableError{variable: "x"}} =
               Predicator.evaluate("x === undefined", %{}, on_unbound: :error)
    end
  end

  describe "the bare-map option form" do
    test "behaves identically to the %Context{} form" do
      assert {:error, %UndefinedVariableError{variable: "missing"}} =
               Predicator.evaluate("missing OR true", %{}, on_unbound: :error)
    end

    test "an unrecognized policy raises from Context.new/2's validation" do
      assert_raise ArgumentError, fn ->
        Predicator.evaluate("x", %{}, on_unbound: :bogus)
      end
    end

    test "evaluate!/3 raises where it returned a value before" do
      assert Predicator.evaluate!("missing OR true", %{}) == true

      assert_raise RuntimeError, fn ->
        Predicator.evaluate!("missing OR true", %{}, on_unbound: :error)
      end
    end
  end
end
