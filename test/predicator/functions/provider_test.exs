defmodule Predicator.Functions.ProviderTest do
  use ExUnit.Case, async: true

  alias Predicator.Functions.{DateFunctions, JSONFunctions, MathFunctions, SystemFunctions}

  # Binding test: guards the invariant Phase 4's switch on `functions/0` will
  # depend on - that the provider map names exactly the same functions, at
  # exactly the same arities, as the closure map it sits beside. A name added
  # to one and not the other, or an arity that drifts between them, breaks
  # this test rather than silently dropping a name later.
  @builtin_modules [SystemFunctions, DateFunctions, JSONFunctions, MathFunctions]

  describe "functions/0 parity with all_functions/0" do
    for module <- @builtin_modules do
      test "#{inspect(module)}: key set, arities, and exported atoms match all_functions/0" do
        module = unquote(module)
        provider_functions = module.functions()
        closure_functions = module.all_functions()

        assert Map.keys(provider_functions) |> Enum.sort() ==
                 Map.keys(closure_functions) |> Enum.sort()

        for {name, {arity, atom}} <- provider_functions do
          {closure_arity, _fun} = Map.fetch!(closure_functions, name)

          assert arity == closure_arity,
                 "#{inspect(module)}.#{name}: arity #{inspect(arity)} in functions/0 " <>
                   "does not match #{inspect(closure_arity)} in all_functions/0"

          assert function_exported?(module, atom, 2),
                 "#{inspect(module)}.#{atom}/2 is not exported"
        end
      end
    end
  end
end
