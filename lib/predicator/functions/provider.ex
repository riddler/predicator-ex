defmodule Predicator.FunctionProvider do
  @moduledoc """
  Behaviour for a module that supplies callable functions to the evaluator.

  A provider names its functions by binding each name to an `{arity, atom}`
  pair - the atom is the name of a `def` on the same module, with signature
  `(args :: [Types.value()], context) :: {:ok, Types.value()} | {:error, binary()}`.
  Naming the implementation by atom, rather than exposing a closure directly,
  is what lets a caller resolve `module` and `atom` separately - `apply/3`
  against the pair - instead of carrying a `function()` value around.

  `Predicator.Context.new/2`'s `:providers` option resolves a list of provider
  modules into the evaluator's dispatch map; the four builtin modules
  (`SystemFunctions`, `DateFunctions`, `JSONFunctions`, `MathFunctions`) are
  the default provider list, named by `builtin_providers/0`.
  """

  @typedoc "A function name, as it appears in a predicator expression."
  @type name :: binary()

  @typedoc "A function's binding: its accepted arity/arities, and the atom naming its implementation."
  @type entry :: {Predicator.Evaluator.function_arity(), atom()}

  @doc """
  Returns the functions this provider exposes, keyed by name.

  Each value is `{arity, atom}`, where `atom` names a public function on the
  same module accepting `(args, context)` and returning
  `{:ok, Types.value()} | {:error, binary()}`.
  """
  @callback functions() :: %{name() => entry()}

  @doc """
  The four builtin provider modules, in shadowing order.

  `Predicator.Context.new/2` resolves this list first when `builtins: true`
  (the default), so a later entry - a `:providers` module, then the inline
  `:functions` map - overrides a same-named builtin. This is the one place
  the default list is written down; conformance tooling that needs "every
  registered name" calls `Predicator.Context.new().functions` rather than
  duplicating it.
  """
  @spec builtin_providers() :: [module()]
  def builtin_providers do
    [
      Predicator.Functions.SystemFunctions,
      Predicator.Functions.DateFunctions,
      Predicator.Functions.JSONFunctions,
      Predicator.Functions.MathFunctions
    ]
  end
end
