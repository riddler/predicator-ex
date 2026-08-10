# Predicator-ex extension: /wurk:branch

Why the cloned dialyzer PLT matters, and its recovery command. Adds only - see
`~/.claude/skills/wurk:branch/SKILL.md` for everything this does not repeat.

## Why the PLT clone matters

`mix.exs:41` pins the dialyzer PLT to `priv/plts/dialyzer.plt`. Dialyxir keys
it on the OTP/Elixir versions and the dep set via the adjacent `.hash`, so a
cloned PLT is picked up as-is by the new worktree and full `mix quality` skips
a multi-minute PLT build on its first run there.

## Recovery when `priv/plts/` is empty

If the source checkout has no PLT to clone, the generic skill emits a
`warm_cache_missing` warning and suggests rebuilding without naming the
command. The command is:

```bash
mix dialyzer --plt
```

Run it once, in either checkout, then re-clone into the new worktree (or let
the new worktree build its own).

## Gitignored, rarely rebuilt

`deps/`, `_build/`, and `priv/plts/` are gitignored, so the clones never
appear in `git status`. `mise.toml` pins OTP and Elixir, so a PLT rebuild
triggered by a version mismatch should be rare.
