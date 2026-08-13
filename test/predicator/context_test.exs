defmodule Predicator.ContextTest.EchoProvider do
  @moduledoc false
  @behaviour Predicator.FunctionProvider

  @impl Predicator.FunctionProvider
  def functions, do: %{"echo" => {1, :call_echo}}

  @spec call_echo([term()], Predicator.Context.t()) :: {:ok, term()}
  def call_echo([value], _context), do: {:ok, value}
end

defmodule Predicator.ContextTest.HostReader do
  @moduledoc false
  @behaviour Predicator.FunctionProvider

  @impl Predicator.FunctionProvider
  def functions, do: %{"host_value" => {0, :call_host_value}}

  @spec call_host_value([term()], Predicator.Context.t()) :: {:ok, term()}
  def call_host_value([], context), do: {:ok, context.host}
end

defmodule Predicator.ContextTest.ProviderA do
  @moduledoc false
  @behaviour Predicator.FunctionProvider

  @impl Predicator.FunctionProvider
  def functions, do: %{"len" => {1, :call_len}}

  @spec call_len([term()], Predicator.Context.t()) :: {:ok, atom()}
  def call_len([_value], _context), do: {:ok, :from_a}
end

defmodule Predicator.ContextTest.ProviderB do
  @moduledoc false
  @behaviour Predicator.FunctionProvider

  @impl Predicator.FunctionProvider
  def functions, do: %{"len" => {1, :call_len}}

  @spec call_len([term()], Predicator.Context.t()) :: {:ok, atom()}
  def call_len([_value], _context), do: {:ok, :from_b}
end

defmodule Predicator.ContextTest.NoFunctionsProvider do
  @moduledoc false
end

defmodule Predicator.ContextTest.BadArityProvider do
  @moduledoc false
  @behaviour Predicator.FunctionProvider

  @impl Predicator.FunctionProvider
  def functions, do: %{"broken" => {1, :not_exported}}
end

defmodule Predicator.ContextTest do
  use ExUnit.Case, async: true

  doctest Predicator.Context

  alias Predicator.Context
  alias Predicator.Errors.LocationError
  alias Predicator.Evaluator

  alias Predicator.ContextTest.{
    BadArityProvider,
    EchoProvider,
    HostReader,
    NoFunctionsProvider,
    ProviderA,
    ProviderB
  }

  describe "new/2" do
    test "defaults data, functions, and on_unbound" do
      context = Context.new()

      assert context.data == %{}
      assert context.on_unbound == :undefined
      assert map_size(context.functions) > 0
    end

    test "defaults host to nil" do
      context = Context.new()

      assert context.host == nil
    end

    test "stores the given host term without normalization" do
      context = Context.new(%{}, host: %{a: nil})

      assert context.host == %{a: nil}
    end

    test "stores the given data" do
      context = Context.new(%{"a" => 1})

      assert context.data == %{"a" => 1}
    end

    test "merges custom functions over the builtins" do
      custom = %{"double" => {1, fn [n], _ctx -> {:ok, n * 2} end}}
      context = Context.new(%{}, functions: custom)

      assert Map.has_key?(context.functions, "double")
      assert Map.has_key?(context.functions, "len")
    end

    test "custom functions can shadow a builtin of the same name" do
      shadow = %{"len" => {1, fn [_arg], _ctx -> {:ok, :shadowed} end}}
      context = Context.new(%{}, functions: shadow)

      assert {1, fun} = context.functions["len"]
      assert fun.([[1, 2, 3]], %{}) == {:ok, :shadowed}
    end

    test "accepts on_unbound: :undefined" do
      context = Context.new(%{}, on_unbound: :undefined)

      assert context.on_unbound == :undefined
    end

    test "accepts on_unbound: :error" do
      context = Context.new(%{}, on_unbound: :error)

      assert context.on_unbound == :error
    end

    test "raises ArgumentError for an invalid on_unbound value" do
      assert_raise ArgumentError, ~r/on_unbound must be :undefined or :error/, fn ->
        Context.new(%{}, on_unbound: :nope)
      end
    end

    test "deeply converts atom keys to string keys in nested maps" do
      context = Context.new(%{user: %{name: "Jane"}})

      assert context.data == %{"user" => %{"name" => "Jane"}}
    end

    test "deeply converts atom keys to string keys in nested maps and nil survives" do
      context = Context.new(%{user: %{name: nil}})

      assert context.data == %{"user" => %{"name" => nil}}
    end

    test "prefers a string key over a same-named atom key at a nested level" do
      context = Context.new(%{user: %{"name" => "Ada", name: "Ignored"}})

      assert context.data == %{"user" => %{"name" => "Ada"}}
    end

    test "converts atom keys inside a list of maps and nil survives" do
      context = Context.new(%{items: [%{label: "a"}, %{label: nil}]})

      assert context.data == %{"items" => [%{"label" => "a"}, %{"label" => nil}]}
    end

    test "passes a Date value through unchanged" do
      date = ~D[2024-01-01]
      context = Context.new(%{"d" => date})

      assert context.data == %{"d" => date}
    end

    test "passes a DateTime value through unchanged" do
      datetime = ~U[2024-01-01 12:00:00Z]
      context = Context.new(%{"d" => datetime})

      assert context.data == %{"d" => datetime}
    end
  end

  describe "new/2 provider resolution" do
    test "builtins: false drops the four default providers" do
      assert Context.new(%{}, builtins: false).functions == %{}
    end

    test "builtins: false leaves a builtin name unknown" do
      context = Context.new(%{}, builtins: false)

      assert {:error, %{message: message}} = Predicator.evaluate("len('x')", context)
      assert message =~ "Unknown function: len"
    end

    test "a provider resolves to an {arity, {module, atom}} entry" do
      context = Context.new(%{}, providers: [EchoProvider], builtins: false)

      assert context.functions["echo"] == {1, {EchoProvider, :call_echo}}
    end

    test "a provider's function evaluates via apply/3 dispatch" do
      context = Context.new(%{"x" => 1}, providers: [EchoProvider])

      assert Predicator.evaluate("echo(x)", context) == {:ok, 1}
    end

    test "a provider shadows a same-named builtin" do
      context = Context.new(%{}, providers: [ProviderA])

      assert Predicator.evaluate("len('x')", context) == {:ok, :from_a}
    end

    test "shadowing order: a later provider shadows an earlier provider" do
      context = Context.new(%{}, providers: [ProviderA, ProviderB])

      assert Predicator.evaluate("len('x')", context) == {:ok, :from_b}
    end

    test "shadowing order: :functions shadows both builtins and providers" do
      context =
        Context.new(%{},
          providers: [ProviderA],
          functions: %{"len" => {1, fn [_arg], _ctx -> {:ok, :from_inline} end}}
        )

      assert Predicator.evaluate("len('x')", context) == {:ok, :from_inline}
    end

    test "a provider function reads context.host" do
      context = Context.new(%{}, providers: [HostReader], host: "first")

      assert Predicator.evaluate("host_value()", context) == {:ok, "first"}
    end

    test "put_host/2 changes what a provider function reads next, without touching data" do
      context = Context.new(%{"a" => 1}, providers: [HostReader], host: "first")
      context = Context.put_host(context, "second")

      assert Predicator.evaluate("host_value()", context) == {:ok, "second"}
      assert context.data == %{"a" => 1}
    end

    test "an inline-closure context still evaluates" do
      context = Context.new(%{}, functions: %{"double" => {1, fn [n], _ctx -> {:ok, n * 2} end}})

      assert Predicator.evaluate("double(21)", context) == {:ok, 42}
    end

    test "a providers-only context round-trips through :erlang.term_to_binary/1 and evaluates" do
      context = Context.new(%{"x" => 1}, providers: [EchoProvider], host: %{tenant: "acme"})

      revived = context |> :erlang.term_to_binary() |> :erlang.binary_to_term()

      assert revived == context
      assert Predicator.evaluate("echo(x)", revived) == {:ok, 1}
    end

    test "raises ArgumentError naming a provider module that does not load" do
      assert_raise ArgumentError, ~r/could not be loaded/, fn ->
        Context.new(%{}, providers: [Predicator.ContextTest.NoSuchModule])
      end
    end

    test "raises ArgumentError naming a provider module without functions/0" do
      assert_raise ArgumentError, ~r/does not export functions\/0/, fn ->
        Context.new(%{}, providers: [NoFunctionsProvider])
      end
    end

    test "raises ArgumentError naming a functions/0 entry whose atom is not exported at arity 2" do
      assert_raise ArgumentError, ~r/does not export not_exported\/2/, fn ->
        Context.new(%{}, providers: [BadArityProvider])
      end
    end
  end

  describe "bind/3" do
    test "binds a new key" do
      context = Context.new(%{"a" => 1})

      assert Context.bind(context, "b", 2).data == %{"a" => 1, "b" => 2}
    end

    test "overwrites an existing key" do
      context = Context.new(%{"a" => 1})

      assert Context.bind(context, "a", 2).data == %{"a" => 2}
    end

    test "leaves functions and on_unbound untouched" do
      context = Context.new(%{}, on_unbound: :error)
      bound = Context.bind(context, "a", 1)

      assert bound.functions === context.functions
      assert bound.on_unbound == :error
    end

    test "normalizes the bound value's atom keys and preserves nil" do
      context = Context.new(%{})
      bound = Context.bind(context, "user", %{role: nil})

      assert bound.data == %{"user" => %{"role" => nil}}
    end

    test "preserves host" do
      context = Context.new(%{}, host: %{conn: :db})
      bound = Context.bind(context, "a", 1)

      assert bound.host === context.host
    end
  end

  describe "put_host/2" do
    test "replaces host" do
      context = Context.new(%{})
      updated = Context.put_host(context, %{conn: :db})

      assert updated.host == %{conn: :db}
    end

    test "leaves data, functions, and on_unbound identical" do
      context = Context.new(%{"a" => 1}, on_unbound: :error)
      updated = Context.put_host(context, %{conn: :db})

      assert updated.data === context.data
      assert updated.functions === context.functions
      assert updated.on_unbound === context.on_unbound
    end
  end

  describe "bound?/2" do
    test "true for a bound string key" do
      context = Context.new(%{"score" => 85})
      assert Context.bound?(context, "score")
    end

    test "true for a bound atom key, looked up by string name" do
      context = Context.new(%{score: 85})
      assert Context.bound?(context, "score")
    end

    test "false for a name that isn't bound" do
      context = Context.new(%{"score" => 85})
      refute Context.bound?(context, "missing")
    end

    test "false for a name that has never been an atom, without raising" do
      context = Context.new(%{"score" => 85})
      refute Context.bound?(context, "definitely_not_an_existing_atom_xyz123")
    end

    test "true even when the bound value is :undefined itself" do
      context = Context.new(%{"score" => :undefined})
      assert Context.bound?(context, "score")
    end

    test "true for a string key bound to nil, which stays null" do
      # Presence, not definedness.
      context = Context.new(%{"x" => nil})
      assert context.data == %{"x" => nil}
      assert Context.bound?(context, "x")
      assert Predicator.evaluate("x > 5", context) == {:ok, :undefined}
    end
  end

  describe "assign/3 with a string expression" do
    test "simple identifier" do
      context = Context.new(%{})
      assert {:ok, bound} = Context.assign(context, "user", "Ada")

      assert bound.data == %{"user" => "Ada"}
    end

    test "property access" do
      context = Context.new(%{"user" => %{}})
      assert {:ok, bound} = Context.assign(context, "user.name", "Ada")

      assert bound.data == %{"user" => %{"name" => "Ada"}}
    end

    test "bracket access" do
      context = Context.new(%{"items" => [1, 2, 3]})
      assert {:ok, bound} = Context.assign(context, "items[1]", "x")

      assert bound.data == %{"items" => [1, "x", 3]}
    end

    test "nested vivifying path" do
      context = Context.new(%{})
      assert {:ok, bound} = Context.assign(context, "user.profile.name", "Ada")

      assert bound.data == %{"user" => %{"profile" => %{"name" => "Ada"}}}
    end

    test "preserves host" do
      context = Context.new(%{}, host: %{conn: :db})
      assert {:ok, bound} = Context.assign(context, "user", "Ada")

      assert bound.host === context.host
    end
  end

  describe "assign/3 with an already-resolved path" do
    test "skips expression resolution" do
      context = Context.new(%{"items" => [1, 2, 3]})
      assert {:ok, bound} = Context.assign(context, ["items", 1], "x")

      assert bound.data == %{"items" => [1, "x", 3]}
    end
  end

  describe "assign/3 errors" do
    test "non-assignable expression returns a LocationError" do
      context = Context.new(%{"items" => [1, 2, 3]})

      assert {:error, %LocationError{type: :not_assignable}} =
               Context.assign(context, "len(items)", 1)
    end

    test "write-time collision returns a LocationError" do
      context = Context.new(%{"user" => 5})

      assert {:error, %LocationError{type: :not_a_container}} =
               Context.assign(context, "user.name", "Ada")
    end
  end

  describe "host is invisible to predicate text" do
    test "a name matching a host key evaluates to :undefined" do
      # Wrapped in an object literal, not evaluated bare: a bare unbound root
      # is itself ambiguous - ADR-driven behavior (px-8um.7) turns that case
      # into an UndefinedVariableError rather than {:ok, :undefined}. Wrapping
      # sidesteps that ambiguity and isolates what this test is about - "conn"
      # resolves from host, not from data.
      context = Context.new(%{}, host: %{"conn" => :db})

      assert Predicator.evaluate("{value: conn}", context) == {:ok, %{"value" => :undefined}}
    end
  end

  describe "Evaluator.evaluate_prepared/1" do
    test "does not consult the builtins, only evaluator.functions" do
      evaluator = %Evaluator{
        instructions: [["lit", 42]],
        context: %{},
        functions: %{"nonstandard" => {0, fn [], _ctx -> {:ok, :ignored} end}}
      }

      assert Evaluator.evaluate_prepared(evaluator) == 42
    end
  end

  describe "null is not undefined (px-o9v)" do
    test "new/2 stores a top-level nil verbatim" do
      assert Context.new(%{"x" => nil}).data == %{"x" => nil}
    end

    test "bind/3 stores nil verbatim" do
      context = Context.new(%{})
      assert Context.bind(context, "x", nil).data == %{"x" => nil}
    end

    test "assign/3 stores nil the same way bind/3 stores it nested" do
      context = Context.new(%{})
      assert {:ok, assigned} = Context.assign(context, "user.name", nil)

      bound = Context.bind(context, "user", %{"name" => nil})

      assert assigned.data == bound.data
      assert assigned.data == %{"user" => %{"name" => nil}}
    end

    test "a host can still explicitly bind :undefined" do
      assert Context.new(%{"x" => :undefined}).data == %{"x" => :undefined}
    end

    test "a nil-bound key and an unbound key are distinguishable via bound?/2" do
      with_nil = Context.new(%{"x" => nil})
      without = Context.new(%{})

      assert Context.bound?(with_nil, "x")
      refute Context.bound?(without, "x")
    end

    test "a nil-bound key and a genuinely unbound key are distinguishable via evaluate/2" do
      with_nil = Context.new(%{"x" => nil}, on_unbound: :error)
      without = Context.new(%{}, on_unbound: :error)

      assert Predicator.evaluate("x === undefined", with_nil) == {:ok, false}

      assert {:error, %Predicator.Errors.UndefinedVariableError{}} =
               Predicator.evaluate("x === undefined", without)
    end

    test "a nested null is not undefined, but a genuinely missing nested key is" do
      with_null = Context.new(%{"user" => %{"name" => nil}})
      without = Context.new(%{"user" => %{}})

      assert Predicator.evaluate("user.name === undefined", with_null) == {:ok, false}
      assert Predicator.evaluate("user.name === undefined", without) == {:ok, true}
    end
  end
end
