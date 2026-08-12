# ADR-0014: Functions are provided by modules; the context carries a host slot

Status: accepted (2026-08-11)

Amends ADR-0004 in place, per the amendment rule in `docs/adr/README.md`. The
sentences replaced are in ADR-0004's Consequences bullet "The function registry
is closed by construction": the description of registration as builtin modules
"merged into a plain map of name to `{arity, fun}`, with `opts[:functions]`
merged last by `Evaluator.merge_functions/1`". That was the registry's
*mechanism*, and this ADR replaces the mechanism. ADR-0004's *decision* - a
closed, host-chosen vocabulary that predicate text can only select names from -
is unchanged, and everything below is written under it.

## Context

A host function is registered today as `%{"name" => {arity, fun}}` where `fun`
is a 2-arity closure receiving `(args, data)` - `data` being the context's
normalized data map (`lib/predicator/evaluator.ex`, `call_function/4`). The
builtins in `lib/predicator/functions/` are registered the same way, as local
captures of private functions (`"len" => {1, &call_len/2}`).

That shape gives a host function exactly one channel for host state: capture
it in the closure. px-8ii (mirroring statifier's st-sdh) records what that
costs an embedder whose host state moves faster than its data:

- **The context goes stale as a whole when only its functions did.** A
  captured value that moves makes the closure a snapshot, and the only refresh
  is `Context.new/2`, which deep-normalizes the entire data map. `bind/3` made
  the reverse case O(1) - update data, keep functions - and there is no
  counterpart. Statifier's profile is exactly the expensive one: its datamodel
  changes rarely, while the state configuration its `In(stateId)` function
  reads changes every microstep, so it pays O(datamodel) per evaluation site
  to refresh one function.
- **A closure-bearing context cannot be stored.** Statifier's interpreter
  position struct must be a complete, inspectable, resumable value (its
  ADR-0012); a struct carrying an anonymous function cannot be serialized,
  persisted, or diffed, so the context must be rebuilt per evaluation instead
  of stored.
- **The data map is not a usable side channel.** For an embedder whose data
  map is a specified, user-visible namespace - SCXML section 5.10 defines what
  a datamodel contains - injecting engine internals into `data` leaks them to
  expression authors and risks colliding with author-declared names.

px-8ii proposed additive repairs: a `put_functions/2`, a host slot, an MFA
form beside the closure form. Bolted onto the current API those work, but they
leave the closure map as the primary interface with the calling convention
forked by entry type - legacy 2-arity closures receiving bare data next to a
3-arity MFA form receiving data and host. The moment to avoid that fork is
now: 4.0.0 shipped on 2026-08-08, statifier - the consumer that raised this -
is itself mid-design, and none of this touches the instruction set, so a
breaking 5.0 costs almost nothing and a forked convention would be carried
forever.

## Decision

**Functions are registered by provider modules, and every function receives
the context.** Concretely, in predicator 5.0.0:

1. **A `Predicator.FunctionProvider` behaviour** with one callback,
   `functions/0`, returning `%{name => {arity, function_atom}}` - the same
   name and arity vocabulary as today (`arity` is an integer or a list of
   integers), with the implementation named by an atom on the provider module
   instead of captured as a fun.

2. **Providers are wired at construction.**
   `Context.new(data, providers: [MyApp.Predicates], host: engine_state)`.
   The builtin modules (`SystemFunctions`, `DateFunctions`, `JSONFunctions`,
   `MathFunctions`) become the default provider list; later providers shadow
   earlier ones name-by-name, preserving today's merge order, and
   `builtins: false` drops the defaults entirely for hosts that want a
   minimal vocabulary.

3. **One calling convention for every function**: `(args, %Context{})`,
   returning `{:ok, value} | {:error, message}` as today. A function reads
   `context.data` for data-namespace values and `context.host` for host
   state. Builtins and host functions use the same signature; there is no
   legacy form beside it.

4. **The context carries an opaque `host` slot.** `Context.new/2` accepts
   `host: term`, `put_host/2` replaces it as a plain struct update - O(1),
   independent of the data's size. The host term is never normalized, never
   readable from predicate text, and never merged into the data namespace.

5. **Dispatch stays a closed-map lookup, and the closed set is resolved
   before any predicate text is seen.** At `Context.new/2`, the provider list
   is resolved into a plain dispatch map of
   `%{name => {arity, {module, function_atom}}}` - the modules and function
   atoms come from host code, at construction, and are validated there
   (`function_exported?/3`, raising `ArgumentError` on a bad provider - host
   API misuse, which ADR-0004 explicitly leaves raisable). Evaluation then
   does what it always did: `Map.get/2` on the user-supplied *name*, then
   invokes the entry. The `apply/3` this introduces takes a module and
   function that no predicate byte ever influenced; the predicate author
   still only selects from what the host passed. ADR-0004 closed dispatch on
   user-supplied *names reaching the host language*; this keeps the name a
   map key and nothing more.

6. **Inline closures survive as a convenience, not a foundation.** The
   `:functions` option on `Predicator.evaluate/3` and `Context.new/2` still
   accepts `%{name => {arity, fun}}` - one-off calls, tests, and doctests
   live on it - with the fun called under the same `(args, %Context{})`
   convention. The documented rule: a context built only from providers
   contains no closures and is serializable by the embedder; a context with
   inline closures works identically but is not storable.

The result for the embedder that motivated this: a `%Context{}` built from
providers is plain data - module atoms, a normalized data map, an opaque host
term - so it can live inside the embedder's own state struct, and refreshing
fast-moving host state is one `put_host/2` instead of a context rebuild.

### This decision does not move the instruction set

**No ISA change. No opcode is added, removed, renamed, or given different
semantics, and no ISA version is bumped.** Function registration and dispatch
are host-side plumbing behind the existing `call` opcode; how the host builds
the function map is invisible to a compiled instruction list. Per ADR-0003
nothing is owed to `docs/isa.md` or the corpus, and the siblings adopt or
ignore the provider concept on their own schedule.

## Consequences

- **This is 5.0.0, and the break is the calling convention.** Every custom
  function's second argument changes from the bare data map to the
  `%Context{}` (data moves to `context.data`), and provider registration
  replaces the closure map as the primary interface. The changelog carries a
  migration note; the mechanical rewrite for an existing closure is one
  pattern-match. Release mechanics remain human-gated per ADR-0006 - the
  work lands under `## [Unreleased]` and waits.
- **The builtins' implementations become public callbacks.** The private
  `call_*` functions behind today's captures are exposed (directly or via
  thin public wrappers) so the default providers are MFA-resolvable. Their
  behavior does not change.
- **`Evaluator.merge_functions/1` is replaced by provider resolution** at
  `Context.new/2`; the shadowing order (builtins first, host providers last,
  later wins) is preserved as a documented rule.
- **px-8ii's additive proposals are subsumed.** `put_functions/2` is not
  built: providers are static modules, so the stale-functions problem that
  motivated it no longer exists - the fast-moving part lives in `host`,
  which is where `put_host/2` points. The MFA form and the host slot land as
  parts of this design rather than as options beside the old one.
- **`builtins: false` is a new security-posture knob.** ADR-0004's registry
  was closed but unconditionally included the builtins; a host can now state
  its predicate vocabulary exactly. The default list is unchanged, so
  existing expressions keep evaluating.
- **Documentation is owed with the code**: `docs/architecture.md`'s function
  registry sections, the README's embedding guide (the provider + host
  pattern is the headline for "wire predicator into your app"), and this
  ADR's acceptance. ADR-0004 is *not* rewritten - the amendment note at the
  top of this file is the record, per the README's amendment rule.
- **Statifier's side changes shape.** st-sdh's bind-vs-rebuild question
  becomes "where to store the context" once a provider-built context is
  storable; that is statifier's call, in its tracker, per ADR-0010.
