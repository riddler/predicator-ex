defmodule Predicator.ContextFunctionCacheTest.OneFunctionProvider do
  @moduledoc false
  @behaviour Predicator.FunctionProvider

  @impl Predicator.FunctionProvider
  def functions, do: %{"echo" => {1, :call_echo}}

  @spec call_echo([term()], Predicator.Context.t()) :: {:ok, term()}
  def call_echo([value], _context), do: {:ok, value}
end

defmodule Predicator.ContextFunctionCacheTest.NoFunctionsProvider do
  @moduledoc false
end

defmodule Predicator.ContextFunctionCacheTest.BadArityProvider do
  @moduledoc false
  @behaviour Predicator.FunctionProvider

  @impl Predicator.FunctionProvider
  def functions, do: %{"broken" => {1, :not_exported}}
end

defmodule Predicator.ContextFunctionCacheTest do
  # The memo key is VM-global (`:persistent_term`), and roughly 837 call sites
  # across the async suite read and write it. This file stays async: false so
  # its own seeding/reset assertions are not perturbed by another test's write
  # landing mid-assertion - see the plan's Performance Considerations, "That
  # argument covers production and not the test suite."
  use ExUnit.Case, async: false

  alias Predicator.Context

  alias Predicator.ContextFunctionCacheTest.{
    BadArityProvider,
    NoFunctionsProvider,
    OneFunctionProvider
  }

  @cache_key {Predicator.Context, :function_resolution}
  @function_cache_limit 64

  setup do
    on_exit(fn -> :persistent_term.erase(@cache_key) end)
    :ok
  end

  describe "resolving twice" do
    test "returns an equal map and the second call is a memo hit" do
      first = Context.new(%{}, builtins: false, providers: [OneFunctionProvider])
      second = Context.new(%{}, builtins: false, providers: [OneFunctionProvider])

      assert first.functions == second.functions

      cache = :persistent_term.get(@cache_key, %{})
      assert {stamps, resolved} = Map.get(cache, [OneFunctionProvider])
      assert is_list(stamps)
      assert resolved == first.functions
    end
  end

  describe "Evaluator.evaluate/3" do
    test "benefits from the same memo" do
      context1 = Context.new(%{"x" => 1}, builtins: false, providers: [OneFunctionProvider])
      context2 = Context.new(%{"x" => 2}, builtins: false, providers: [OneFunctionProvider])

      assert Predicator.evaluate("echo(x)", context1) == {:ok, 1}
      assert Predicator.evaluate("echo(x)", context2) == {:ok, 2}

      cache = :persistent_term.get(@cache_key, %{})
      assert Map.has_key?(cache, [OneFunctionProvider])
    end
  end

  describe "a stale stamp" do
    test "forces a recompute and gets rewritten" do
      context = Context.new(%{}, builtins: false, providers: [OneFunctionProvider])

      cache = :persistent_term.get(@cache_key, %{})
      {_stamps, resolved} = Map.get(cache, [OneFunctionProvider])

      bogus_cache = Map.put(cache, [OneFunctionProvider], {[:bogus_stamp], resolved})
      :persistent_term.put(@cache_key, bogus_cache)

      recomputed = Context.new(%{}, builtins: false, providers: [OneFunctionProvider])

      assert recomputed.functions == context.functions

      cache_after = :persistent_term.get(@cache_key, %{})
      assert {stamps_after, _resolved} = Map.get(cache_after, [OneFunctionProvider])
      refute stamps_after == [:bogus_stamp]
    end
  end

  describe "a genuinely recompiled provider" do
    test "invalidates the memo" do
      module_name = :"Elixir.Predicator.ContextFunctionCacheTest.RuntimeProvider"

      previous_flag = Code.compiler_options()[:ignore_module_conflict]
      Code.put_compiler_option(:ignore_module_conflict, true)

      try do
        quoted_v1 =
          quote do
            defmodule unquote(module_name) do
              @moduledoc false
              @behaviour Predicator.FunctionProvider

              @impl Predicator.FunctionProvider
              def functions, do: %{"first_name" => {0, :call_first}}

              def call_first([], _context), do: {:ok, :first}
            end
          end

        Code.compile_quoted(quoted_v1)

        first = Context.new(%{}, builtins: false, providers: [module_name])
        assert Map.has_key?(first.functions, "first_name")

        quoted_v2 =
          quote do
            defmodule unquote(module_name) do
              @moduledoc false
              @behaviour Predicator.FunctionProvider

              @impl Predicator.FunctionProvider
              def functions, do: %{"second_name" => {0, :call_second}}

              def call_second([], _context), do: {:ok, :second}
            end
          end

        Code.compile_quoted(quoted_v2)

        second = Context.new(%{}, builtins: false, providers: [module_name])

        assert Map.has_key?(second.functions, "second_name")
        refute Map.has_key?(second.functions, "first_name")
      after
        Code.put_compiler_option(:ignore_module_conflict, previous_flag || false)
        :code.purge(module_name)
        :code.delete(module_name)
      end
    end
  end

  describe "the cap" do
    test "resets on overflow but the fresh entry still lands" do
      seeded =
        Map.new(1..@function_cache_limit, fn n ->
          {[:"Predicator.ContextFunctionCacheTest.Synthetic#{n}"], {[:seed_stamp], %{}}}
        end)

      :persistent_term.put(@cache_key, seeded)

      context = Context.new(%{}, builtins: false, providers: [OneFunctionProvider])

      cache_after = :persistent_term.get(@cache_key, %{})
      assert {stamps, resolved} = Map.get(cache_after, [OneFunctionProvider])
      assert is_list(stamps)
      assert resolved == context.functions
    end
  end

  describe "the error contract" do
    test "an unloadable provider raises the same ArgumentError twice, uncached" do
      for _attempt <- 1..2 do
        assert_raise ArgumentError, ~r/could not be loaded/, fn ->
          Context.new(%{}, providers: [Predicator.ContextFunctionCacheTest.NoSuchModule])
        end
      end
    end

    test "a provider without functions/0 raises the same ArgumentError twice, uncached" do
      for _attempt <- 1..2 do
        assert_raise ArgumentError, ~r/does not export functions\/0/, fn ->
          Context.new(%{}, providers: [NoFunctionsProvider])
        end
      end
    end

    test "a bad-arity provider raises the same ArgumentError twice, uncached" do
      for _attempt <- 1..2 do
        assert_raise ArgumentError, ~r/does not export not_exported\/2/, fn ->
          Context.new(%{}, providers: [BadArityProvider])
        end
      end
    end
  end

  describe "resolve_functions/1 with builtins: false and no providers" do
    test "never touches persistent_term" do
      :persistent_term.erase(@cache_key)

      assert Context.resolve_functions(builtins: false) == %{}
      assert :persistent_term.get(@cache_key, :absent) == :absent
    end
  end
end
