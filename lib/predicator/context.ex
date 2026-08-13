defmodule Predicator.Context do
  @moduledoc """
  A bound evaluation context: data, functions, and the unbound-variable policy.

  Build one with `new/2`, evaluate `Predicator.evaluate/3` against it many
  times, and rebind cheaply with `bind/3` between evaluations - functions
  resolve once, at construction, not on every evaluate call.

  ## Functions

  `functions` is a closed dispatch map, resolved once by `new/2` from three
  sources, folded left so a later one shadows an earlier same-named entry:
  the four builtin provider modules (`:builtins`, default `true`), then
  `:providers` - a list of `Predicator.FunctionProvider` modules, left to
  right - then `:functions`, an inline `%{name => {arity, fun}}` closure map
  merged last. A provider module is validated at construction
  (`ArgumentError` on a bad one - host API misuse, not a predicate-derived
  failure); a resolved entry is either `{arity, {module, atom}}` or
  `{arity, fun}`, and the evaluator dispatches both the same way, handing the
  function `(args, context)`.

  ## The `host` slot

  `host` is an opaque carrier for whatever a function provider needs at call
  time - a database connection, a request struct, a tenant id. It is stored
  exactly as given, with no normalization: unlike `data`, atom keys inside a
  `host` term are never touched. It is never readable from
  predicate text - there is no syntax that reaches it - and it is never
  merged into `data`. Set it with `new/2`'s `:host` option or `put_host/2`.

  ## Examples

      iex> context = Predicator.Context.new(%{"score" => 85})
      iex> Predicator.evaluate("score > 80", context)
      {:ok, true}

      iex> context = Predicator.Context.new(%{})
      iex> context = Predicator.Context.bind(context, "score", 90)
      iex> Predicator.evaluate("score", context)
      {:ok, 90}
  """

  alias Predicator.{ContextLocation, Evaluator, FunctionProvider, Types}

  @typedoc """
  Policy for a load of an unbound root variable.

  `:undefined` (the default) pushes the `:undefined` sentinel and lets
  three-valued logic absorb it. `:error` makes the load fail with
  `Predicator.Errors.UndefinedVariableError`, halting the run.

  Roots only, under either policy: a missing key on a bound map
  (`user.nope`), a missing nested path, and an out-of-range index all stay
  `:undefined`. This mirrors ECMAScript - a `ReferenceError` for an
  undeclared variable, a silent `undefined` for a missing property - and
  keeps guards over sparse data usable.
  """
  @type on_unbound :: :undefined | :error

  @typedoc "A function entry the evaluator can dispatch: an MFA pair or a closure."
  @type function_entry :: {module(), atom()} | function()

  @typedoc "A bound evaluation context."
  @type t :: %__MODULE__{
          data: Types.context(),
          functions: %{binary() => {Evaluator.function_arity(), function_entry()}},
          on_unbound: on_unbound(),
          host: term()
        }

  defstruct data: %{}, functions: %{}, on_unbound: :undefined, host: nil

  @doc """
  Builds a context, resolving its function dispatch map once.

  ## Parameters

  - `data` - the bound-variable map (default `%{}`)
  - `opts`:
    - `:builtins` - `true` (default) includes the four builtin provider
      modules; `false` drops them, leaving only `:providers` and
      `:functions`
    - `:providers` - a list of `Predicator.FunctionProvider` modules,
      resolved left to right (a later module shadows an earlier one's
      same-named entry), after the builtins and before `:functions`. A
      module that fails to load, does not export `functions/0`, or names an
      atom not exported at arity 2 raises `ArgumentError`, naming the module
      and the offending entry
    - `:functions` - an inline `%{name => {arity, fun}}` closure map, merged
      last (shadows both builtins and `:providers`) - same as
      `Predicator.evaluate/3`'s `:functions` option
    - `:on_unbound` - `:undefined` (default) | `:error` - see
      `t:on_unbound/0`; any other value raises `ArgumentError`
    - `:host` - default `nil` - see the "The `host` slot" section above

  `data` is normalized deeply before it is stored: atom keys become string
  keys (a string key wins if both are present at the same level), recursing
  through nested maps and lists. `Date`, `DateTime`, and any other struct
  pass through unchanged. `nil` is preserved as-is - it is the null value,
  distinct from the `:undefined` sentinel; see `docs/reference/language.md`.

  `host`, by contrast, is stored exactly as given - no normalization, atom
  keys intact.

  ## Examples

      iex> Predicator.Context.new(%{"x" => 1}).data
      %{"x" => 1}

      iex> Predicator.Context.new(%{user: %{name: nil}}).data
      %{"user" => %{"name" => nil}}

      iex> context = Predicator.Context.new(%{"x" => nil})
      iex> {Predicator.Context.bound?(context, "x"), Predicator.evaluate("x === undefined", context)}
      {true, {:ok, false}}

      iex> Predicator.Context.new().on_unbound
      :undefined

      iex> context = Predicator.Context.new(%{}, on_unbound: :error)
      iex> {:error, error} = Predicator.evaluate("missing OR true", context)
      iex> {error.variable, error.position}
      {"missing", {1, 1}}

      iex> Predicator.Context.new(%{}, builtins: false).functions
      %{}
  """
  @spec new(Types.context(), keyword()) :: t()
  def new(data \\ %{}, opts \\ []) when is_map(data) do
    %__MODULE__{
      data: normalize_value(data),
      functions: resolve_functions(opts),
      on_unbound: validate_on_unbound!(Keyword.get(opts, :on_unbound, :undefined)),
      host: Keyword.get(opts, :host)
    }
  end

  @doc """
  Resolves `opts`'s `:builtins`, `:providers`, and `:functions` into a single
  dispatch map - the same resolution `new/2` performs internally, exposed so
  `Predicator.Evaluator.evaluate/3` can route its own `:functions`/
  `:providers`/`:builtins` opts through it without going through the rest of
  `new/2` (data normalization, `:on_unbound` validation, which `evaluate/3`
  deliberately does not enforce).

  Order: the builtin providers (`Predicator.FunctionProvider.builtin_providers/0`,
  unless `builtins: false`), then `opts[:providers]` left to right, then
  `opts[:functions]` merged last - each later source shadows a same-named
  entry from an earlier one.

  Raises `ArgumentError` under the same conditions `new/2` does, for the same
  reason: a bad provider module is host API misuse, not a predicate-derived
  failure (ADR-0004).
  """
  @spec resolve_functions(keyword()) :: %{
          binary() => {Evaluator.function_arity(), function_entry()}
        }
  def resolve_functions(opts \\ []) do
    builtins =
      if Keyword.get(opts, :builtins, true), do: FunctionProvider.builtin_providers(), else: []

    providers = Keyword.get(opts, :providers, [])

    (builtins ++ providers)
    |> resolve_providers()
    |> Map.merge(Keyword.get(opts, :functions, %{}))
  end

  @spec resolve_providers([module()]) :: %{
          binary() => {Evaluator.function_arity(), {module(), atom()}}
        }
  defp resolve_providers(providers) do
    Enum.reduce(providers, %{}, fn module, acc ->
      Map.merge(acc, validated_entries!(module))
    end)
  end

  # Validates one provider module and resolves its `functions/0` map into
  # `%{name => {arity, {module, atom}}}`. Raises `ArgumentError`, naming
  # `module` and the offending entry, when: `module` does not load
  # (`Code.ensure_loaded?/1` first - `function_exported?/3` answers `false`
  # for an unloaded module, which would otherwise misreport a typo'd module
  # name as "missing functions/0"), `module` does not export `functions/0`,
  # or a `functions/0` entry names an atom not exported at arity 2.
  @spec validated_entries!(module()) :: %{
          binary() => {Evaluator.function_arity(), {module(), atom()}}
        }
  defp validated_entries!(module) do
    unless Code.ensure_loaded?(module) do
      raise ArgumentError, "function provider #{inspect(module)} could not be loaded"
    end

    unless function_exported?(module, :functions, 0) do
      raise ArgumentError,
            "function provider #{inspect(module)} does not export functions/0"
    end

    Map.new(module.functions(), fn {name, {arity, fun_atom}} ->
      unless function_exported?(module, fun_atom, 2) do
        raise ArgumentError,
              "function provider #{inspect(module)} names #{inspect(fun_atom)} for " <>
                "#{inspect(name)}, but #{inspect(module)} does not export #{fun_atom}/2"
      end

      {name, {arity, {module, fun_atom}}}
    end)
  end

  @spec validate_on_unbound!(term()) :: on_unbound()
  defp validate_on_unbound!(policy) when policy in [:undefined, :error], do: policy

  defp validate_on_unbound!(other) do
    raise ArgumentError,
          "on_unbound must be :undefined or :error, got: #{inspect(other)}"
  end

  @doc """
  Binds `name` to `value` in `data`. O(1): a single `Map.put/3`, plus
  normalizing `value` itself (O(size of `value`), not O(size of `data`) -
  `data` is already normalized from construction or a prior `bind/3`).

  `value` is normalized the same way `new/2` normalizes `data`: atom keys
  become string keys (string keys win on collision), recursing through
  nested maps and lists; structs pass through unchanged. `nil` is preserved
  as-is - it is the null value, distinct from the `:undefined` sentinel; see
  `docs/reference/language.md`.

  `functions`, `on_unbound`, and `host` are carried over unchanged.

  ## Examples

      iex> context = Predicator.Context.new(%{"a" => 1})
      iex> Predicator.Context.bind(context, "b", 2).data
      %{"a" => 1, "b" => 2}

      iex> context = Predicator.Context.new(%{})
      iex> Predicator.Context.bind(context, "user", %{name: nil}).data
      %{"user" => %{"name" => nil}}
  """
  @spec bind(t(), binary(), Types.value()) :: t()
  def bind(%__MODULE__{data: data} = context, name, value) when is_binary(name) do
    %{context | data: Map.put(data, name, normalize_value(value))}
  end

  @doc """
  Replaces `context`'s `host` term, leaving `data`, `functions`, and
  `on_unbound` untouched. The new `host` is stored exactly as given - no
  normalization, same as `new/2`'s `:host` option.

  ## Examples

      iex> context = Predicator.Context.new(%{})
      iex> Predicator.Context.put_host(context, %{conn: :db}).host
      %{conn: :db}
  """
  @spec put_host(t(), term()) :: t()
  def put_host(%__MODULE__{} = context, host), do: %{context | host: host}

  @doc """
  Answers whether `name` is bound in `context`'s data, resolved by
  `Predicator.Evaluator.resolve_key/2` - the same lookup the evaluator uses
  when a `load` instruction records an unbound read, so the two cannot
  disagree. Presence, not definedness: a name bound to `:undefined` is bound.

  `resolve_key/2` also accepts an atom key, but a `Context`'s data never has
  one: `new/2` and `bind/3` normalized them to string keys already. The
  `%{score: 85}` example below is bound because of that normalization, not
  because of an atom lookup here.

  ## Examples

      iex> context = Predicator.Context.new(%{"score" => 85})
      iex> Predicator.Context.bound?(context, "score")
      true
      iex> Predicator.Context.bound?(context, "missing")
      false

      iex> context = Predicator.Context.new(%{score: 85})
      iex> Predicator.Context.bound?(context, "score")
      true
  """
  @spec bound?(t(), binary()) :: boolean()
  def bound?(%__MODULE__{data: data}, name) when is_binary(name) do
    match?({:ok, _key}, Evaluator.resolve_key(data, name))
  end

  @doc """
  Assigns `value` at `path_or_expression`, returning the rebound context.

  `path_or_expression` is either a location expression string (resolved
  against the context's current `data`, then written) or an
  already-resolved `t:Predicator.ContextLocation.location_path/0`. Writes
  through `Predicator.ContextLocation.put/3` - the same auto-vivifying write
  algorithm as `Predicator.context_assign/4` and the future `store` opcode
  (`px-tbv.2`). `functions`, `on_unbound`, and `host` are carried over
  unchanged. `value` is stored verbatim, the same as `bind/3` stores a
  scalar.

  ## Examples

      iex> context = Predicator.Context.new(%{})
      iex> {:ok, context} = Predicator.Context.assign(context, "user.name", "Ada")
      iex> context.data
      %{"user" => %{"name" => "Ada"}}

      iex> context = Predicator.Context.new(%{"items" => [1, 2, 3]})
      iex> {:ok, context} = Predicator.Context.assign(context, ["items", 1], "x")
      iex> context.data
      %{"items" => [1, "x", 3]}
  """
  @spec assign(t(), binary() | ContextLocation.location_path(), Types.value()) ::
          {:ok, t()} | {:error, struct()}
  def assign(%__MODULE__{data: data} = context, path_or_expression, value) do
    with {:ok, path} <- resolve_path(data, path_or_expression),
         {:ok, new_data} <- ContextLocation.put(data, path, value) do
      {:ok, %{context | data: new_data}}
    end
  end

  @spec resolve_path(Types.context(), binary() | ContextLocation.location_path()) ::
          ContextLocation.location_result() | {:error, struct()}
  defp resolve_path(_data, path) when is_list(path), do: {:ok, path}

  defp resolve_path(data, expression) when is_binary(expression) do
    ContextLocation.resolve_expression(expression, data)
  end

  # Deeply converts, for plain maps, atom keys to string keys (string keys
  # win on collision), recursing through nested maps and lists. Structs
  # (`Date`, `DateTime`, and any other) pass through unchanged - `is_map/1`
  # is true for structs too, which is why the struct clause must come before
  # the plain-map clause below. `nil` falls through the scalar catch-all
  # unchanged, along with `:undefined` itself, which a host may still bind
  # explicitly.
  @spec normalize_value(term()) :: term()
  defp normalize_value(list) when is_list(list) do
    Enum.map(list, &normalize_value/1)
  end

  defp normalize_value(%_struct{} = struct), do: struct

  defp normalize_value(map) when is_map(map), do: normalize_map(map)

  defp normalize_value(other), do: other

  # Splits `map`'s entries into non-atom-keyed and atom-keyed, builds the
  # base map from the non-atom entries first (normalizing their values along
  # the way), then folds in the atom entries - converting each key with
  # `Atom.to_string/1` and skipping it if a same-named string key already
  # won a slot in the base. This mirrors the current evaluator's "prefers
  # string key over atom key" precedence.
  #
  # `true`/`false` are atoms in Elixir but are boolean *data* keys here, not
  # variable-name-shaped atom keys - `config[true]` compiles to a literal
  # atom key lookup (`access_value/3`'s `is_atom(key)` clause), so stringifying
  # a `true`/`false` map key would silently break that lookup. They are left
  # as-is.
  @spec normalize_map(map()) :: map()
  defp normalize_map(map) do
    {atom_entries, base_entries} =
      Enum.split_with(map, fn {key, _value} -> is_atom(key) and not is_boolean(key) end)

    base =
      Map.new(base_entries, fn {key, value} -> {key, normalize_value(value)} end)

    Enum.reduce(atom_entries, base, fn {key, value}, acc ->
      string_key = Atom.to_string(key)

      if Map.has_key?(acc, string_key) do
        acc
      else
        Map.put(acc, string_key, normalize_value(value))
      end
    end)
  end
end
