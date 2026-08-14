# Memoize resolve_functions/1's provider validation Implementation Plan

## Overview

`Predicator.Context.resolve_functions/1` re-validates every provider module -
`Code.ensure_loaded?/1` once per module, `function_exported?/3` once per module
and once per named function - and re-merges the resulting maps on every single
`Context.new/2` call. That cost is fixed: it does not shrink with the datamodel,
and statifier measured it at 1.29 us of a 2.28 us context build (56.6%) at its
corpus-typical size. This plan memoizes the resolved dispatch map per provider
list, adds a dev-only `bench/` that decomposes a context build into its fixed
and size-scaling terms, and puts a performance note on `Context.new/2` telling
per-evaluation callers to hold one context and rebind with `bind/3`/`put_host/2`.
Bead: px-rnc (mirrors st-sdh).

## Current State Analysis

**The cost.** `Predicator.Context.resolve_functions/1`
(`lib/predicator/context.ex:201-210`) builds `builtins ++ providers` -
`FunctionProvider.builtin_providers/0` (`lib/predicator/functions/provider.ex:44`)
returns the four builtin modules - hands that list to `resolve_providers/1`
(`lib/predicator/context.ex:215-219`), which folds `validated_entries!/1`
(`lib/predicator/context.ex:231-250`) over it with `Map.merge/2`. Per module
`validated_entries!/1` does:

1. `Code.ensure_loaded?(module)` - `ArgumentError` "could not be loaded";
2. `function_exported?(module, :functions, 0)` - `ArgumentError` "does not
   export functions/0";
3. `module.functions()`, then one `function_exported?(module, fun_atom, 2)` per
   entry - `ArgumentError` naming the entry and the missing `atom/2`.

The four builtins together name on the order of thirty functions, so a default
`Context.new/2` pays ~35 `function_exported?/3` calls, four `Code.ensure_loaded?/1`
calls, four `Map.new/2` builds and four `Map.merge/2` folds - identical work,
producing an identical map, on every call.

**Nothing about that result is call-dependent.** The resolved value is
`%{name => {arity, {module, atom}}}` - plain atoms and binaries, no closures, no
captured state (ADR-0014 decision point 5 is what makes it plain data). The only
thing that can change it is a provider module being recompiled with a different
`functions/0`, which in practice happens only in dev/test.

**Two callers.** `Context.new/2` (`lib/predicator/context.ex:175`) and
`Predicator.Evaluator.evaluate/3` (`lib/predicator/evaluator.ex:364`), which
routes its own `:functions`/`:providers`/`:builtins` opts through the same
function deliberately (`lib/predicator/context.ex:181-197`). Memoizing inside
`resolve_functions/1` therefore covers both with no second edit, including the
per-call `evaluate/3` path where the saving is largest.

**The error contract is tested and must not move.**
`test/predicator/context_test.exs:268-284` asserts all three `ArgumentError`
messages by regex, against `NoSuchModule`, `NoFunctionsProvider`
(`test/predicator/context_test.exs:45`) and `BadArityProvider`
(`test/predicator/context_test.exs:49`). ADR-0004 classifies these as host-API
misuse, explicitly left raisable, and ADR-0014 point 5 re-states the validation
as part of the design - so the raises stay, with the same messages, raised for
the same inputs in the same order.

**No process, no table, no supervision tree today.** `mix.exs`'s `application/0`
(`mix.exs:48-52`) declares `extra_applications: [:logger]` and nothing else -
predicator has no application callback module and starts no processes. Any
memoization that needs an owner process (`:ets` with a GenServer, `Agent`,
`Registry`) would introduce one into a library that currently has none, which
every embedder would inherit.

**No existing cache of any kind.** `grep` finds no `:persistent_term` and no
`:ets.` anywhere in `lib/` or `test/`. This is the first one.

**No `bench/` directory and no benchee dependency.** `mix.exs:8-16` lists six
dev/test deps; benchee is not among them. `.formatter.exs` inputs are
`{config,lib,test}/**` - a new `bench/` tree is not formatted today. `.credo.exs`
includes `lib/`, `src/`, `test/`, `web/` - `bench/` is not linted. `mix.exs`'s
package `files:` is a whitelist (`mix.exs:77`), so `bench/` is not published
either.

**The moduledoc already tells half the story.** `lib/predicator/context.ex:4-7`
states the hold-one-context pattern ("Build one with `new/2`, evaluate ... many
times, and rebind cheaply with `bind/3`"). What is missing is the warning that
`new/2` per evaluation is the expensive anti-pattern, with a number on it. The
`:normalize` section (`lib/predicator/context.ex:129-136`, added by px-10u on
this same branch) already cites px-rnc as "the fixed-term counterpart", so the
new note is the other half of a cross-reference that already exists.

**No `## ISA Impact` section in this plan.** `.claude/wurk/plan.md` requires it
only when a change "adds, removes, renames, or alters an opcode". This adds none
and alters none: function resolution is host-side plumbing behind the existing
`call` opcode, and ADR-0014's own "This decision does not move the instruction
set" already settles that for provider machinery. No corpus regeneration either -
`conformance/` is untouched.

### Key Discoveries:

- The resolved dispatch map is pure data - `{arity, {module, atom}}` - so it is
  safe to cache and safe to share across processes (ADR-0014 point 5).
- `Predicator.Evaluator.evaluate/3` funnels through the same
  `resolve_functions/1` (`lib/predicator/evaluator.ex:364`), so one memo serves
  both entry points.
- Predicator starts no processes (`mix.exs:48-52`), which rules out any
  `:ets`-based cache that needs an owner.
- The three `ArgumentError` messages are asserted by regex at
  `test/predicator/context_test.exs:268-284` and are ADR-0004-sanctioned
  host-API misuse; they are a fixed point of this change.
- `bench/` falls outside `.formatter.exs` inputs, `.credo.exs` includes,
  `elixirc_paths`, and the package whitelist - so it is invisible to the gate
  unless deliberately wired in.
- px-10u's `normalize: false` already landed on this branch and removes the
  other half of the build cost; the bench must be able to show both terms
  separately.

## Desired End State

1. Two `Context.new/2` calls with the same provider list resolve their function
   map once. The second call performs no `function_exported?/3` and no
   `Map.merge/2` of provider entries; it performs one `Code.ensure_loaded?/1`
   plus one `module_info(:md5)` per provider module, one `:persistent_term.get/2`,
   and a stamp comparison.
2. Every observable behavior of `resolve_functions/1` is unchanged: the same
   resolved map, the same shadowing order (builtins, then `:providers` left to
   right, then `:functions` last), the same three `ArgumentError` messages for
   the same inputs, `builtins: false` still yielding `%{}` for an empty
   `:providers`.
3. A provider module recompiled with a different `functions/0` is picked up on
   the next call - no stale dispatch map survives a code reload in dev or test.
4. `bench/context_build.exs` exists, runs under `mix run`, and decomposes a
   context build into: full `new/2`, `new/2` with `normalize: false`, `new/2`
   with `builtins: false`, `bind/3`, and `put_host/2`, across three data sizes.
   `bench/results/260814-context-build.md` records before and after numbers from
   the same machine.
5. `Context.new/2`'s moduledoc carries a performance note naming the fixed
   function-resolution cost and pointing per-evaluation callers at `bind/3` and
   `put_host/2`.

Verify with: `mix quality` green; the new tests in
`test/predicator/context_test.exs`; `mix run bench/context_build.exs` completing
and its numbers matching what `bench/results/260814-context-build.md` records.

## What We're NOT Doing

- **Not adding an `:ets` cache.** It needs an owner process and predicator has
  no supervision tree (`mix.exs:48-52`); making a library start a process to
  cache thirty atoms is a worse trade than the alternative below.
- **Not making the builtin map a compile-time module attribute.** Calling
  `validated_entries!/1` at compile time would make the builtin half literally
  free, but it inverts the dependency direction: `Predicator.Context` would
  acquire a compile-time dependency on all four builtin function modules, each
  of which already depends back on `Predicator.Context` for `Context.t()` in
  every function spec (`lib/predicator/functions/math_functions.ex:36,68`). That
  is an export dependency today and compiles fine, but pairing it with a
  compile-time dependency the other way makes `Predicator.Context` recompile
  whenever any builtin provider is touched, and puts the whole arrangement one
  refactor - a `%Context{}` pattern in a provider head - away from a genuine
  cycle. It also does nothing for host providers, which is exactly the case the
  bead names (statifier registers its own).
- **Not adding an eviction policy beyond a hard cap.** No LRU, no TTL, no
  reference counting. The cap plus a whole-cache reset is deliberately the
  dumbest thing that bounds memory (see Performance Considerations).
- **Not exposing a public cache API.** No `Predicator.Context.clear_function_cache/0`,
  no configuration knob. The memo is an implementation detail with an
  automatically-correct invalidation rule; a public knob would be a promise
  about the mechanism.
- **Not changing `resolve_functions/1`'s signature, its `@spec`, or its
  documented contract.**
- **Not touching px-10u's `normalize: false` commit** already on this branch,
  and not re-litigating it. The bench measures it; that is all.
- **Not doing release mechanics.** Changelog entries land under
  `## [Unreleased]`; no version bump, no tag (ADR-0006).
- **Not publishing `bench/` to Hex.** The package `files:` whitelist
  (`mix.exs:77`) already excludes it and stays as it is.

## Implementation Approach

**Memoize the whole resolved provider map, keyed by the provider list, in
`:persistent_term`, validated by a module-version stamp, with the miss path
being today's code unchanged.**

The shape:

- One `:persistent_term` key for the entire cache:
  `{Predicator.Context, :function_resolution}`, holding
  `%{[module] => {[stamp], resolved_map}}`.
- A stamp is `module.module_info(:md5)` for a loaded module, `:not_loaded`
  otherwise. A recompiled provider gets a different md5, so a changed
  `functions/0` is a cache miss by construction - this is what makes the design
  safe under dev/test code reloading without any reliance on the code server's
  purge callbacks.
- **Hit path**: compute the stamps, look up the list, compare stamps, return the
  stored map. No `function_exported?/3`, no `Map.merge/2`.
- **Miss path** (absent entry, stamp mismatch, unloaded module, or a cap
  overflow): call the *existing, unmodified* `resolve_providers/1`, then store.

That last point is the correctness argument and the reason to prefer this shape
over per-module memoization: **every path that can raise is the old path.** The
fast path is only ever taken when a previously-successful validation of exactly
these module versions is on record, so it cannot swallow an `ArgumentError`, and
it cannot reorder two errors from two different bad providers either - a list
containing a bad provider never gets cached in the first place, so it takes the
old path, in the old order, every time.

`:persistent_term` over the process dictionary because the win must survive
across processes (statifier builds contexts from whatever process is stepping the
machine) and the read is the operation being optimized -
`:persistent_term.get/2` is a constant-time read with no copy. Its known cost is
on the write side, which this design makes rare by construction (see Performance
Considerations).

**Phase order is bench first.** The bead asks for before/after numbers, and the
"before" can only be measured against un-memoized code. Phase 1 lands the
harness and the before numbers, Phase 2 lands the memoization and appends the
after numbers to the same results file, Phase 3 lands the documentation. Each is
independently committable and independently gate-verifiable.

**Merge-time observation, not a label change:** Phase 1 edits `mix.exs`,
`mix.lock`, and `.formatter.exs`, which are `area:build` territory
(`CLAUDE.md`), while px-rnc carries `area:context` only. The label is a
prediction made before the work existed and this branch is already cut, so the
labels stay as they are; the mismatch is worth noticing at merge time per
`CLAUDE.md`'s own rule ("a branch that ends up touching an area it was not
labeled with is worth noticing at merge time"), and it means this branch should
not be batched with another live `area:build` branch.

---

## Phase 1: A dev-only `bench/` and the before numbers

### Overview

Add benchee, a `bench/context_build.exs` that decomposes a context build into
its fixed and size-scaling terms, and a results document holding the before
numbers. No `lib/` change in this phase, so the gate outcome is unaffected by
anything but the new dependency.

### Changes Required:

#### 1. The dependency

**File**: `mix.exs`
**Changes**: add benchee to `@deps` as a dev-only, non-runtime dependency.

```elixir
{:benchee, "~> 1.3", only: :dev, runtime: false},
```

`mix deps.get` updates `mix.lock` (benchee pulls `deep_merge` and `statistex`).
Nothing else in `mix.exs` changes: `package/0`'s `files:` whitelist already
excludes `bench/`, and dev-only deps are not published as package requirements.

#### 2. Formatting coverage for the new tree

**File**: `.formatter.exs`
**Changes**: extend `inputs` so the gate's format stage sees `bench/`.

```elixir
inputs: ["{mix,.formatter}.exs", "{config,lib,test,bench}/**/*.{ex,exs}"]
```

`.credo.exs` is deliberately left alone - a benchmark script is not library code
and credo's strict style rules (module docs, alias ordering) are noise on it.

#### 3. The benchmark

**File**: `bench/context_build.exs`
**Changes**: new file. A benchee run over five scenarios and three data sizes.

Scenarios, chosen so the reader can subtract terms rather than guess at them:

| Scenario | What it isolates |
|---|---|
| `new/2` | the full build: normalization + function resolution |
| `new/2 normalize: false` | the fixed term alone (px-10u removes the walk) |
| `new/2 builtins: false, normalize: false` | the floor: struct construction only |
| `bind/3` | the rebind path a per-evaluation caller should be on |
| `put_host/2` | the host-refresh path (ADR-0014's `put_host/2`) |

Data sizes, named for what they model:

- `:corpus` - 5 flat-ish roots, statifier's observed maximum and the size the
  bead's 56.6% figure is measured at;
- `:small` - 1 root, a single scalar;
- `:stress` - 200 roots with nested maps and lists, to make the size-scaling term
  dominate and show the fixed term shrinking as a fraction.

Structure:

```elixir
# bench/context_build.exs
alias Predicator.Context

data = %{corpus: ..., small: ..., stress: ...}

Benchee.run(
  %{
    "new/2" => fn input -> Context.new(input) end,
    "new/2 normalize: false" => fn input -> Context.new(input, normalize: false) end,
    "new/2 no builtins" => fn input -> Context.new(input, builtins: false, normalize: false) end,
    "bind/3" => fn input -> Context.bind(Context.new(input), "flag", true) end,
    "put_host/2" => fn input -> Context.put_host(Context.new(input), :host) end
  },
  inputs: data,
  memory_time: 2,
  time: 5
)
```

`bind/3` and `put_host/2` are benchmarked against a context built inside the
scenario so every scenario pays the same setup; the results document states that
explicitly and reports the *difference* from the `new/2` row as the rebind cost,
which is the decomposition statifier had to hand-roll.

#### 4. The results document

**File**: `bench/results/260814-context-build.md`
**Changes**: new file. Records the machine (CPU, OTP/Elixir versions, as benchee
prints them), the invocation, the raw table, and a short reading. In this phase
it carries a `## Before (pre-px-rnc memoization)` section only; Phase 2 appends
the after section beside it.

### Success Criteria:

#### Automated Verification:
- [x] Full quality gate passes (`mix quality`) - format now covers `bench/`,
      so an unformatted benchmark fails the gate.
- [x] `mix deps.get` resolves and `mix.lock` contains `benchee`.
- [x] `mix run bench/context_build.exs` exits 0.
- [x] `bench/results/260814-context-build.md` exists and its `## Before` section
      is populated.
- [x] Coverage stays above the 90% minimum in `coveralls.json` - `bench/` is
      outside `elixirc_paths`, so it contributes no uncovered lines.

#### Manual Verification:
- [ ] The three data sizes actually produce visibly different `new/2` timings -
      a size axis that does not move means the generator is wrong.
- [ ] The `new/2` minus `new/2 normalize: false` difference is recognizably
      px-10u's normalization walk, and the `normalize: false` minus `no builtins`
      difference is recognizably the fixed function-resolution term the bead is
      about.
- [ ] Numbers are in the same order of magnitude as statifier's (1-3 us at
      corpus size); a wild divergence means the benchmark is measuring something
      else.

**Implementation Note**: Use the project's loop gate between edits while
iterating; run the full gate as the phase gate. In interactive execution, pause
here for the human to confirm the manual testing before moving to the next
phase. In looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

## Phase 2: Memoize the resolved provider map

### Overview

Insert a `:persistent_term`-backed memo between `resolve_functions/1` and
`resolve_providers/1`. `resolve_providers/1` and `validated_entries!/1` are not
edited: they remain the miss path, verbatim, which is what keeps the error
contract intact.

### Changes Required:

#### 1. The memo

**File**: `lib/predicator/context.ex`
**Changes**: `resolve_functions/1` calls a new private `cached_providers/1`
instead of `resolve_providers/1`; three new private functions and two module
attributes are added below it.

```elixir
# The one persistent_term key holding every memoized provider resolution.
@function_cache_key {__MODULE__, :function_resolution}

# The most distinct provider lists memoized at once. Provider lists come from
# host code, not from predicate text, so the realistic count is one or two;
# the cap exists so a host that generates provider modules cannot grow the
# term unboundedly. Overflow resets the cache rather than evicting - see the
# plan's Performance Considerations for why an LRU is not worth its tests.
@function_cache_limit 64

def resolve_functions(opts \\ []) do
  builtins =
    if Keyword.get(opts, :builtins, true), do: FunctionProvider.builtin_providers(), else: []

  providers = Keyword.get(opts, :providers, [])

  (builtins ++ providers)
  |> cached_providers()
  |> Map.merge(Keyword.get(opts, :functions, %{}))
end

# Returns the resolved dispatch map for `providers`, from the memo when the
# recorded module versions still match and recomputing it otherwise.
#
# Every path that can raise is the recompute path, unchanged: a provider list
# containing a module that fails validation never reaches the memo, so it
# takes `resolve_providers/1` on every call, raising the same ArgumentError,
# in the same module order, as it did before this cache existed. A module
# recompiled with a different `functions/0` gets a different md5 stamp, which
# is a miss - so no stale dispatch map survives a code reload.
@spec cached_providers([module()]) :: %{
        binary() => {Evaluator.function_arity(), {module(), atom()}}
      }
defp cached_providers([]), do: %{}

defp cached_providers(providers) do
  stamps = Enum.map(providers, &module_stamp/1)
  cache = :persistent_term.get(@function_cache_key, %{})

  case Map.get(cache, providers) do
    {^stamps, resolved} ->
      resolved

    _miss ->
      resolved = resolve_providers(providers)
      put_function_cache(cache, providers, stamps, resolved)
      resolved
  end
end

# A module's identity-plus-version stamp. `:not_loaded` for a module that is
# not loaded, which is always a miss - the recompute path is what turns that
# into the documented ArgumentError.
@spec module_stamp(module()) :: binary() | :not_loaded
defp module_stamp(module) do
  if Code.ensure_loaded?(module), do: module.module_info(:md5), else: :not_loaded
end

@spec put_function_cache(map(), [module()], [binary() | :not_loaded], map()) :: :ok
defp put_function_cache(cache, providers, stamps, resolved) do
  cache = if grows_past_limit?(cache, providers), do: %{}, else: cache
  :persistent_term.put(@function_cache_key, Map.put(cache, providers, {stamps, resolved}))
end

# Only a genuinely new key can grow the cache. Refreshing the stamp of a list
# already on record - what a dev recompiling a provider does, repeatedly - is
# a same-key Map.put/3 that leaves map_size/1 alone, so it must not trip the
# reset. Without this guard a session sitting at the cap would throw the whole
# cache away on every recompile.
@spec grows_past_limit?(map(), [module()]) :: boolean()
defp grows_past_limit?(cache, providers) do
  map_size(cache) >= @function_cache_limit and not Map.has_key?(cache, providers)
end
```

Note `cached_providers([])` - `builtins: false` with no `:providers` returns
`%{}` without touching `:persistent_term` at all, preserving the
`Context.new(%{}, builtins: false).functions == %{}` doctest
(`lib/predicator/context.ex:161`) on the cheapest possible path.

#### 2. Tests

**File**: `test/predicator/context_function_cache_test.exs` (new,
`use ExUnit.Case, async: false`)
**Changes**: the memoization suite. `test/predicator/context_test.exs` is **not
edited at all** - its existing provider tests are the behavior-preservation
suite, and a zero-line diff there is the signal that the memo changed nothing
observable.

- resolving twice returns an equal map, and the second call is a memo hit -
  asserted by reading `:persistent_term.get({Predicator.Context,
  :function_resolution}, %{})` and matching the entry for the builtin list;
- `evaluate/3`'s path benefits too: two `Predicator.Evaluator.evaluate/3` calls
  with the same `:providers` produce the same answers and one memo entry;
- a stale stamp forces a recompute: overwrite the memo entry's stamp list with a
  bogus value, call `resolve_functions/1`, and assert the returned map is still
  correct and the stamp was rewritten;
- a genuinely recompiled provider invalidates: compile a module at runtime with
  `Code.compile_quoted/1` (under `Code.put_compiler_option(:ignore_module_conflict,
  true)`, restored after) whose `functions/0` names one function, resolve,
  recompile the same module name with a second function, resolve again, and
  assert the second name is present. This is the reload-safety claim, tested
  directly rather than argued;
- the cap resets: seed the memo with `@function_cache_limit` synthetic entries,
  resolve a fresh list, and assert the fresh entry is present with a matching
  stamp. **Do not assert on `map_size/1`** - see the async note below;
- the error contract survives the cache: a bad provider raises the same
  `ArgumentError` on the *second* call as on the first (i.e. the failure was not
  cached), for all three failure modes.

**The memo key is VM-global, and the suite is async - the tests must be written
for that.** `test/predicator/context_test.exs:58` is `use ExUnit.Case, async: true`,
70 test files across the suite are async, and roughly 837 call sites call
`Context.new/2` or `Predicator.evaluate/3` - every one of them reading and
writing this same `:persistent_term` key while these tests run. Two consequences,
both of which the implementation must respect:

- **The memoization tests go in their own file,
  `test/predicator/context_function_cache_test.exs`, with `async: false`.**
  ExUnit's `async` flag is file-scoped, so a `describe` block inside the
  existing async `context_test.exs` cannot opt out. An async-false file still
  runs concurrently with nothing else, which is what seeding and resetting a
  global key requires. Keeping it out of `context_test.exs` also leaves that
  file's provider tests byte-identical, which is the behavior-preservation
  signal Phase 2 depends on.
- **No assertion reads `map_size/1` of the whole cache.** Even under
  `async: false` that number is a global other tests have legitimately written
  to; assert instead on the presence and stamp of the specific entry under
  test. The cap-reset test asserts the fresh entry survived a seeded-full
  cache, not that the map shrank to a particular size.

Tests that write `:persistent_term` clean up in an `on_exit/1` that erases the
key, so no test leaks a memo into another.

#### 3. Changelog

**File**: `CHANGELOG.md`
**Changes**: an entry under `## [Unreleased]` / `### Changed` describing the
memoization, its user-visible effect (repeat `Context.new/2` and
`Evaluator.evaluate/3` calls against an unchanged provider list no longer re-pay
provider validation), and its invalidation rule (a recompiled provider is picked
up automatically). No behavior change to document beyond speed.

#### 4. The after numbers

**File**: `bench/results/260814-context-build.md`
**Changes**: append `## After (px-rnc memoization)` with the same table from the
same machine, plus a one-paragraph reading of the delta.

### Success Criteria:

#### Automated Verification:
- [ ] Full quality gate passes (`mix quality`), dialyzer included.
- [ ] The pre-existing provider tests at `test/predicator/context_test.exs:193-284`
      pass unmodified - the shadowing order, the serialization test, and all
      three `ArgumentError` regexes.
- [ ] `mix test test/predicator/context_function_cache_test.exs` passes,
      including the runtime-recompile invalidation test and the
      repeat-`ArgumentError` test, and `git diff --stat` shows
      `test/predicator/context_test.exs` unchanged.
- [ ] The full suite passes with `mix test` twice in a row and with
      `mix test --seed 0` - a memo leaking across tests shows up as an
      order-dependent failure, not as a single red test.
- [ ] `lib/predicator/context.ex` coverage stays above the 90% minimum in
      `coveralls.json`.
- [ ] `mix run bench/context_build.exs` exits 0 and the `## After` section of
      `bench/results/260814-context-build.md` is populated.

#### Manual Verification:
- [ ] The after numbers show the fixed term (the `new/2 normalize: false` minus
      `no builtins` difference from Phase 1) substantially reduced, and the
      size-scaling term unchanged - if both moved, something other than the memo
      changed.
- [ ] `iex -S mix`, resolve twice, `:persistent_term.get/2` shows exactly one
      entry for the builtin list; recompile a provider with `r/1` and confirm
      the next resolution reflects the new `functions/0`.
- [ ] No regressions in related features: a providers-only context still
      round-trips through `:erlang.term_to_binary/1`
      (`test/predicator/context_test.exs:259`).

**Implementation Note**: Use the project's loop gate between edits while
iterating; run the full gate as the phase gate. In interactive execution, pause
here for the human to confirm the manual testing before moving to the next
phase. In looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

## Phase 3: The performance note on `Context.new/2`

### Overview

Document the shape the previous two phases measured: construction has a fixed
cost, and a per-evaluation caller should hold one context and rebind.

### Changes Required:

#### 1. The moduledoc note

**File**: `lib/predicator/context.ex`
**Changes**: a `## Performance` section in `new/2`'s `@doc`, after the
`:normalize` section, saying:

- a build has two costs - the normalization walk, proportional to `data`
  (px-10u's `normalize: false` removes it), and a fixed function-resolution
  term that does not shrink with the data;
- the fixed term is memoized as of px-rnc, so repeat builds against the same
  provider list no longer re-pay validation - but a build is still a build;
- the anti-pattern, named: calling `new/2` once per evaluation. The rebind
  paths are `bind/3` (O(1) in `data`) and `put_host/2` (a struct update), and
  both are what ADR-0014's design exists to make possible;
- a pointer to `bench/context_build.exs` and its results file for the numbers,
  rather than transcribing figures that go stale - the existing `:normalize`
  paragraph's inline figures stay as they are, since they were measured against
  a specific documented scale.

The existing cross-reference at `lib/predicator/context.ex:134` ("see also
px-rnc for the fixed-term counterpart") is kept and now points at something that
exists.

#### 2. Changelog

**File**: `CHANGELOG.md`
**Changes**: extend or add an `## [Unreleased]` entry noting the documented
performance guidance. If Phase 2's entry is still the nearest neighbor, fold
this into it rather than writing a second bullet about the same change.

### Success Criteria:

#### Automated Verification:
- [ ] Full quality gate passes (`mix quality`) - moduledoc changes compile and
      any doctest in the edited `@doc` still runs.
- [ ] `mix docs` builds without warnings for `Predicator.Context`.

#### Manual Verification:
- [ ] The rendered `Predicator.Context.new/2` docs read as guidance a first-time
      embedder can act on, and the `bind/3`/`put_host/2` pointer is unmissable -
      statifier's own report is that it did not find `bind/3` until a benchmark
      forced the question.
- [ ] The note does not contradict the `:normalize` section beside it, and the
      px-10u/px-rnc cross-references still agree.

**Implementation Note**: Use the project's loop gate between edits while
iterating; run the full gate as the phase gate. In interactive execution, pause
here for the human to confirm the manual testing before moving to the next
phase. In looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---

## Performance Considerations

**What the memo costs on a hit.** One `Code.ensure_loaded?/1` and one
`module_info(:md5)` per provider module, one `:persistent_term.get/2`, one
`Map.get/2` on a small map, and one list comparison. `:persistent_term.get/2` is
a constant-time read that does not copy the term into the calling process, which
is precisely why the resolved map - the thing being reused - is the right thing
to store there. The residual is O(number of providers), not O(number of named
functions), which is the ~35-to-5 reduction in checks the bench should show.

**What it costs on a write.** `:persistent_term.put/2` is globally expensive: it
triggers a scan of every process for references to the old term. This design
makes writes rare by construction - one per distinct provider list, plus one per
provider recompilation. In a running system with a stable provider set that is a
handful of writes at startup and none thereafter. In dev, it is one write per
provider recompile, which is the same frequency the code server is already doing
far more expensive work at.

**Why a hard cap and a reset rather than an LRU.** The failure mode a cap guards
against is a host that generates provider modules dynamically, giving an
unbounded set of distinct provider lists and therefore an unbounded term and a
`put` per call. That host is pathological and out of scope (provider lists come
from host code, and ADR-0004 puts malformed host input in the misuse category,
not the untrusted-input one), but "unbounded `persistent_term` growth" is a
footgun worth closing cheaply. A reset-on-overflow is a few lines and one test;
an LRU is a data structure, an eviction policy, and a test suite for both,
bought for a scenario nobody should be in.

The reset is deliberately coarse, and `grows_past_limit?/2` is the one piece of
precision it does buy: without it, a cache sitting at the cap would be thrown
away on *every* write, including the same-key stamp refresh a dev recompiling a
provider performs over and over - turning an ordinary recompile into full-cache
thrash. Guarding on `Map.has_key?/2` costs one line and confines the reset to
the case that actually grows the term. Everything past that - which entry to
evict when the cap is genuinely reached - stays coarse on purpose.

**Why not the process dictionary.** It would avoid the global write cost
entirely and bound memory per-process automatically, but the memo would not
survive across processes - and the embedder that raised this builds contexts
from whichever process is stepping its state machine. A per-process memo would
be a cache that misses exactly when it matters.

**Concurrency.** Two processes racing to memoize the same list can each compute
and each write; the loser's entry is simply overwritten with an identical value.
There is no correctness consequence, only a duplicated computation, so no lock
is warranted - every caller returns its own freshly computed, correct map
regardless of who won the write.

That argument covers production and **not** the test suite, which is the one
place a lost update is observable: an assertion that reads the global cache can
be perturbed by an unrelated async test's write landing between the write under
test and the read. That is why the memoization tests are a separate
`async: false` file that asserts on its own entry rather than on the cache's
size - see Phase 2's testing note.

## Testing Strategy

### Unit Tests:

- `test/predicator/context_function_cache_test.exs` (new, `async: false`) - the
  memoization suite described in Phase 2. Key edge cases: empty provider list
  (`builtins: false`, no `:providers`) never touching `:persistent_term`; a
  stale stamp; a genuine runtime recompile; the cap reset; all three
  `ArgumentError` modes raising identically on a repeat call.
- The existing provider-resolution tests
  (`test/predicator/context_test.exs:193-284`) are the behavior-preservation
  suite and stay byte-identical. A diff to any of them in this branch is a
  signal that the memo changed observable behavior.
- No new binding test is introduced, so `gate.sabotage.test_roots` in
  `.claude/wurk.json` is not extended. The memoization tests are ordinary tests
  and need no sabotage note.

### Integration Tests:

- `test/predicator/integration/` gains nothing new: `Predicator.evaluate/3`'s
  behavior is unchanged by construction, and the existing integration suite
  running green over a memoized resolver is the integration check. The Phase 2
  test asserting two `Evaluator.evaluate/3` calls share one memo entry covers
  the second entry point (`lib/predicator/evaluator.ex:364`) at unit level.

### Manual Testing Steps:

1. `mix run bench/context_build.exs` on the branch point (before Phase 2) and
   again after Phase 2, on the same machine, with nothing else running; record
   both in `bench/results/260814-context-build.md`.
2. `iex -S mix`: build two contexts with the same providers, inspect
   `:persistent_term.get({Predicator.Context, :function_resolution})`, confirm
   one entry.
3. In the same session, edit a provider's `functions/0`, `recompile`, build a
   third context, and confirm the new function name is present in
   `context.functions`.
4. Build a context with a deliberately broken provider twice; confirm the same
   `ArgumentError` message both times.
5. Read the rendered `mix docs` page for `Predicator.Context.new/2` and check the
   performance note against the numbers just recorded.

## References

- Bead: `px-rnc` (mirrors `st-sdh`); source measurements are statifier-ex's
  `bench/results/260814-context-build.md` and `bench/results/260814-macrostep.md`
- `lib/predicator/context.ex:201-250` - `resolve_functions/1`,
  `resolve_providers/1`, `validated_entries!/1`
- `lib/predicator/evaluator.ex:364` - the second `resolve_functions/1` caller
- `lib/predicator/functions/provider.ex:44` - `builtin_providers/0`
- `test/predicator/context_test.exs:193-284` - the provider-resolution and
  `ArgumentError` suite this change must leave intact
- `docs/adr/0014-functions-are-provided-by-modules.md` - point 5 (resolution and
  validation at construction), the `host` slot, and `put_host/2`
- `docs/adr/0004-no-eval-errors-are-values.md` - host-API misuse is raisable;
  the `ArgumentError`s stay
- `docs/adr/0006-irreversibility-places-the-human-gates.md` - changelog under
  `## [Unreleased]`, no release mechanics here
- `docs/plans/260811-px-e1n.1-function-provider-host-slot.md` - the plan that
  built the resolution path being memoized
- `CLAUDE.md`, "Area labels" - the `area:build` observation recorded above

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] The three data sizes actually produce visibly different `new/2` timings -
      a size axis that does not move means the generator is wrong.
- [ ] The `new/2` minus `new/2 normalize: false` difference is recognizably
      px-10u's normalization walk, and the `normalize: false` minus `no builtins`
      difference is recognizably the fixed function-resolution term the bead is
      about.
- [ ] Numbers are in the same order of magnitude as statifier's (1-3 us at
      corpus size); a wild divergence means the benchmark is measuring something
      else.

**Implementation Note**: Use the project's loop gate between edits while
iterating; run the full gate as the phase gate. In interactive execution, pause
here for the human to confirm the manual testing before moving to the next
phase. In looped (`--loop`) execution, this phase's Automated Verification gates
advancement automatically (via `/wurk:commit --auto`), and Manual Verification
items are deferred and surfaced once at the end instead of blocking here.

---
