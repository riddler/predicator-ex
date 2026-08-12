defmodule Predicator.FunctionProvider do
  @moduledoc """
  Behaviour for a module that supplies callable functions to the evaluator.

  A provider names its functions by binding each name to an `{arity, atom}`
  pair - the atom is the name of a `def` on the same module, with signature
  `(args :: [Types.value()], context) :: {:ok, Types.value()} | {:error, binary()}`.
  Naming the implementation by atom, rather than exposing a closure directly,
  is what lets a caller resolve `module` and `atom` separately - `apply/3`
  against the pair - instead of carrying a `function()` value around.

  This is additive: the four builtin modules keep their existing
  `all_functions/0` closure maps and `functions/0` side by side. Nothing
  downstream reads `functions/0` yet.
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
end
