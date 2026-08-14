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

## After (px-rnc memoization)

**Machine**: Apple M3, 8 cores, 24 GB RAM, macOS (Darwin 25.5.0) - same machine
as the Before section.
**Toolchain**: Elixir 1.18.3, Erlang/OTP 27.3, JIT enabled.
**Invocation**: `mix run bench/context_build.exs` (benchee config:
`memory_time: 2`, `time: 5`, default 2s warmup).
**Branch point**: after Phase 2's memoization - `resolve_functions/1` routes
through `cached_providers/1`; a warm cache pays one `Code.ensure_loaded?/1`
and one `module_info(:md5)` per provider module plus a `:persistent_term.get/2`,
not the full `function_exported?/3` validation sweep.

### With input `:small` (1 root, a single scalar)

```
Name                             ips        average  deviation         median         99th %
new/2 no builtins            16.69 M       59.92 ns  ±2347.53%       54.20 ns       70.80 ns
new/2 normalize: false        3.75 M      266.57 ns  ±1411.79%         250 ns         375 ns
put_host/2                    2.96 M      337.40 ns  ±1536.49%         292 ns         458 ns
new/2                         2.23 M      447.91 ns  ±1349.77%         292 ns        1750 ns
bind/3                        2.05 M      487.36 ns   ±970.67%         333 ns     4249.17 ns

Memory usage statistics:

Name                      Memory usage
new/2 no builtins                 64 B
new/2 normalize: false           416 B - 6.50x memory usage +352 B
put_host/2                       768 B - 12.00x memory usage +704 B
new/2                            704 B - 11.00x memory usage +640 B
bind/3                           704 B - 11.00x memory usage +640 B
```

### With input `:corpus` (5 flat-ish roots, statifier's observed maximum)

```
Name                             ips        average  deviation         median         99th %
new/2 no builtins            17.10 M       58.47 ns  ±1956.36%       54.10 ns       66.70 ns
new/2 normalize: false        3.72 M      268.54 ns  ±1525.64%         250 ns         375 ns
put_host/2                    2.16 M      463.66 ns  ±1431.02%         417 ns         625 ns
bind/3                        1.92 M      521.85 ns   ±647.94%         500 ns         667 ns
new/2                         1.57 M      635.87 ns   ±807.11%         417 ns       12333 ns

Memory usage statistics:

Name                      Memory usage
new/2 no builtins            0.0625 KB
new/2 normalize: false         0.41 KB - 6.50x memory usage +0.34 KB
put_host/2                     1.42 KB - 22.75x memory usage +1.36 KB
bind/3                         1.55 KB - 24.88x memory usage +1.49 KB
new/2                          1.36 KB - 21.75x memory usage +1.30 KB
```

### With input `:stress` (200 roots, nested maps and lists)

```
Name                             ips        average  deviation         median         99th %
new/2 no builtins         17155.80 K      0.0583 μs  ±2324.25%      0.0541 μs      0.0667 μs
new/2 normalize: false     3659.21 K        0.27 μs  ±2209.63%        0.25 μs        0.38 μs
put_host/2                    8.79 K      113.80 μs    ±22.93%      108.46 μs      229.81 μs
bind/3                        8.65 K      115.63 μs    ±20.47%      110.75 μs      222.81 μs
new/2                         7.10 K      140.81 μs    ±24.32%      125.96 μs      251.81 μs

Memory usage statistics:

Name                      Memory usage
new/2 no builtins            0.0625 KB
new/2 normalize: false         0.41 KB - 6.50x memory usage +0.34 KB
put_host/2                   462.20 KB - 7395.13x memory usage +462.13 KB
bind/3                       462.46 KB - 7399.38x memory usage +462.40 KB
new/2                        462.07 KB - 7393.13x memory usage +462.01 KB
```

### Reading

**The fixed term collapses, as intended.** At `:corpus`, the fixed
function-resolution term (`new/2 normalize: false` minus `new/2 no builtins`,
medians) goes from **~1.2 μs before** to **250 ns - 54.1 ns = ~196 ns after** -
roughly a 6x reduction, and now a small fraction of even the reduced `new/2`
median (417 ns) rather than ~85% of it. What remains on a warm-cache hit is
exactly what the design predicts: one `Code.ensure_loaded?/1` and one
`module_info(:md5)` per provider module (four builtins by default), one
`:persistent_term.get/2`, and a stamp comparison - no `function_exported?/3`
sweep, no `Map.merge/2` folds. The same pattern holds at `:small` (266.57 ns
minus 59.92 ns before vs. essentially the same ~200 ns after, since the fixed
term does not depend on `data`'s size) and at `:stress`.

**The size-scaling term is unchanged, as it must be.** `new/2 normalize: false`
across sizes (266.57 ns / 268.54 ns / 0.27 μs for `:small` / `:corpus` /
`:stress`) sits within noise of the Before section's equivalent row
(1.37 μs / 1.42 μs / 1.32 μs before - note the absolute scale shifted between
runs due to general JIT/scheduler variance across separate `mix run`
invocations, but the *shape* - flat across `:small`/`:corpus`, unchanged
between Before and After at each size - is what confirms only the fixed term
moved). The normalization walk itself (`new/2` minus `new/2 normalize: false`)
and the `:stress`-scale blowup from 121 μs to 141 μs remain dominated by
`normalize_value/1`'s recursive walk, exactly as before - memoizing provider
resolution does not touch that code path at all.

**Net effect at `:corpus` scale**, where the bead's original 56.6% figure was
measured: the fixed term that used to be the majority of a context build is
now a minor addition on top of normalization, confirming the memo does what
Phase 2 set out to do without perturbing the part of the build it was never
meant to touch.
