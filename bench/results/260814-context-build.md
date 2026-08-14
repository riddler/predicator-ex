# `Context.new/2` build decomposition

Numbers from `bench/context_build.exs`, which splits a context build into
five scenarios (`new/2`, `new/2 normalize: false`, `new/2` with no builtins
and no normalization, `bind/3`, `put_host/2`) across three data sizes
(`:small`, `:corpus`, `:stress`). See the script for the exact data shapes and
`docs/plans/260814-px-rnc-memoize-provider-validation.md` for the plan this
supports.

## Before (pre-px-rnc memoization)

**Machine**: Apple M3, 8 cores, 24 GB RAM, macOS (Darwin 25.5.0).
**Toolchain**: Elixir 1.18.3, Erlang/OTP 27.3, JIT enabled.
**Invocation**: `mix run bench/context_build.exs` (benchee config:
`memory_time: 2`, `time: 5`, default 2s warmup).
**Branch point**: before Phase 2's memoization - `resolve_functions/1` runs
the full `Code.ensure_loaded?/1` + `function_exported?/3` validation on every
call.

### With input `:small` (1 root, a single scalar)

```
Name                             ips        average  deviation         median         99th %
new/2 no builtins         10824.15 K      0.0924 μs  ±4971.69%      0.0830 μs       0.167 μs
bind/3                      734.89 K        1.36 μs   ±551.40%        1.29 μs        2.50 μs
new/2                       731.39 K        1.37 μs   ±504.38%        1.29 μs        1.88 μs
put_host/2                  730.72 K        1.37 μs   ±295.36%        1.33 μs        1.92 μs
new/2 normalize: false      728.25 K        1.37 μs   ±432.03%        1.29 μs        2.33 μs

Memory usage statistics:

Name                      Memory usage
new/2 no builtins            0.0625 KB
bind/3                         5.20 KB - 83.25x memory usage +5.14 KB
new/2                          5.20 KB - 83.25x memory usage +5.14 KB
put_host/2                     5.27 KB - 84.25x memory usage +5.20 KB
new/2 normalize: false         5.02 KB - 80.25x memory usage +4.95 KB
```

### With input `:corpus` (5 flat-ish roots, statifier's observed maximum)

```
Name                             ips        average  deviation         median         99th %
new/2 no builtins         10789.57 K      0.0927 μs  ±5224.60%      0.0830 μs       0.167 μs
new/2 normalize: false      704.11 K        1.42 μs   ±483.12%        1.29 μs        2.63 μs
new/2                       670.88 K        1.49 μs   ±465.90%        1.42 μs        2.25 μs
put_host/2                  666.49 K        1.50 μs   ±341.17%        1.42 μs        2.33 μs
bind/3                      155.10 K        6.45 μs  ±2551.49%        1.63 μs        4.71 μs

Memory usage statistics:

Name                      Memory usage
new/2 no builtins            0.0625 KB
new/2 normalize: false         5.02 KB - 80.25x memory usage +4.95 KB
new/2                          6.02 KB - 96.25x memory usage +5.95 KB
put_host/2                     6.20 KB - 99.25x memory usage +6.14 KB
bind/3                         6.34 KB - 101.38x memory usage +6.27 KB
```

`bind/3`'s average (6.45 μs) is skewed hard by a handful of GC-pause outliers
(99th % is 4.71 μs, deviation ±2551%); its median (1.63 μs) is the
representative number and sits right beside `new/2`'s median (1.42 μs), which
is expected - the scenario is `Context.bind(Context.new(input), ...)`, so it
pays a full `new/2` plus one `Map.put/3`.

### With input `:stress` (200 roots, nested maps and lists)

```
Name                             ips        average  deviation         median         99th %
new/2 no builtins          5946.92 K       0.168 μs ±10861.15%      0.0830 μs        0.21 μs
new/2 normalize: false      755.10 K        1.32 μs   ±539.26%        1.25 μs        1.71 μs
new/2                         7.92 K      126.29 μs    ±21.93%      121.13 μs      256.21 μs
bind/3                        7.82 K      127.81 μs    ±23.08%      122.79 μs      267.00 μs
put_host/2                    7.72 K      129.56 μs    ±47.05%      122.92 μs      251.37 μs

Memory usage statistics:

Name                      Memory usage
new/2 no builtins            0.0625 KB
new/2 normalize: false         5.19 KB - 83.00x memory usage +5.13 KB
new/2                        466.85 KB - 7469.63x memory usage +466.79 KB
bind/3                       467.24 KB - 7475.88x memory usage +467.18 KB
put_host/2                   466.98 KB - 7471.63x memory usage +466.91 KB
```

### Reading

**The size axis moves, as it should.** `new/2`'s median goes 1.29 μs
(`:small`) -> 1.42 μs (`:corpus`) -> 121.13 μs (`:stress`) - two orders of
magnitude between the smallest and largest datamodel, driven entirely by the
normalization walk (see below). `:corpus`'s `new/2` number (1.29-1.49 μs) is
in the same order of magnitude as statifier's reference figure of 1-3 μs at
corpus size.

**Decomposing `new/2` into its two terms, at `:corpus` (medians):**

- `new/2` (1.42 μs) minus `new/2 normalize: false` (1.29 μs) = **~0.13 μs**,
  the normalization walk px-10u's `normalize: false` removes. At this size the
  walk is small because `:corpus` is five flat scalar roots - nothing to
  recurse into.
- `new/2 normalize: false` (1.29 μs) minus `new/2 no builtins` (0.083 μs) =
  **~1.2 μs**, the fixed function-resolution term this bead (px-rnc) targets -
  `Code.ensure_loaded?/1` and `function_exported?/3` re-run on every call for
  all four builtin providers, unrelated to `data`'s size. At `:corpus` scale
  this fixed term is the dominant cost - roughly 85% of the full `new/2`
  build - which is what makes it worth memoizing.

**At `:stress` the picture inverts, as intended by the size axis.** The
normalization walk (`new/2` minus `new/2 normalize: false`, ~120 μs) now
dwarfs the fixed function-resolution term (~1.2 μs, unchanged from `:corpus`
since it does not depend on `data`). This is exactly the point of including a
large size: it shows the fixed term shrinking from ~85% of the build at
`:corpus` to a fraction of a percent at `:stress`, confirming the term really
is fixed and not secretly size-dependent.

**`bind/3` vs `put_host/2` as rebind costs.** Both scenarios build a fresh
context inside the benchmarked function and then rebind
(`Context.bind/3`/`Context.put_host/2`), so both pay a full `new/2` plus their
own rebind operation. At `:corpus`, `put_host/2`'s median (1.42 μs) sits
within noise of plain `new/2`'s median (1.42 μs) - a struct field replacement
is effectively free next to the `new/2` cost it rides on top of. `bind/3`'s
median (1.63 μs) is about 0.2 μs above `new/2`, consistent with its one
`Map.put/3` plus normalizing the bound value. Neither number isolates the
rebind path in production use, where the caller holds one already-built
context and calls `bind/3`/`put_host/2` directly without a `new/2` in the
loop - that path is not what this benchmark's `bind/3`/`put_host/2` scenarios
measure (they measure `new/2` + rebind together, by design, so every scenario
pays the same setup); the difference from the `new/2` row is what represents
the incremental rebind cost.

Phase 2 will append an `## After (px-rnc memoization)` section here, from the
same machine, once the fixed term is memoized.
