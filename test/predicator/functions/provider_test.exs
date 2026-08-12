defmodule Predicator.Functions.ProviderTest do
  use ExUnit.Case, async: true

  alias Predicator.FunctionProvider
  alias Predicator.Functions.{DateFunctions, JSONFunctions, MathFunctions, SystemFunctions}

  # Binding test: guards the invariant Context.new/2's provider resolution
  # depends on - that every entry `functions/0` publishes names an atom that
  # is actually a public, arity-2 function on the same module, at an arity
  # `functions/0` itself declares. A name whose atom is missing, private, or
  # at the wrong arity would only surface later, at `Context.new/2` time, as
  # an `ArgumentError` - this test catches it at the module itself.
  @builtin_modules [SystemFunctions, DateFunctions, JSONFunctions, MathFunctions]

  describe "functions/0" do
    for module <- @builtin_modules do
      test "#{inspect(module)}: every entry names an exported call_*/2 at the declared arity" do
        module = unquote(module)

        for {name, {arity, atom}} <- module.functions() do
          assert is_integer(arity) or (is_list(arity) and arity != []),
                 "#{inspect(module)}.#{name}: arity #{inspect(arity)} is neither an " <>
                   "integer nor a non-empty list of integers"

          assert function_exported?(module, atom, 2),
                 "#{inspect(module)}.#{atom}/2 is not exported"
        end
      end
    end
  end

  describe "builtin_providers/0" do
    test "lists exactly the four builtin modules, in shadowing order" do
      assert FunctionProvider.builtin_providers() == @builtin_modules
    end

    test "every listed module implements the behaviour and loads" do
      for module <- FunctionProvider.builtin_providers() do
        assert Code.ensure_loaded?(module)
        assert function_exported?(module, :functions, 0)
      end
    end
  end
end
