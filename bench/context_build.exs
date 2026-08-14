# Decomposes a Predicator.Context.new/2 build into its fixed cost (function
# resolution, independent of `data`) and its size-scaling cost (the
# normalization walk), across three data sizes. See
# bench/results/260814-context-build.md for the recorded numbers and reading.
#
# Run with: mix run bench/context_build.exs
alias Predicator.Context

# :corpus - 5 flat-ish roots, statifier's observed maximum and the size the
# bead's 56.6% figure is measured at.
corpus = %{
  "name" => "Ada Lovelace",
  "age" => 36,
  "active" => true,
  "score" => 92.5,
  "role" => "admin"
}

# :small - 1 root, a single scalar.
small = %{"flag" => true}

# :stress - 200 roots with nested maps and lists, to make the size-scaling
# term dominate and show the fixed term shrinking as a fraction.
stress =
  for i <- 1..200, into: %{} do
    {"root_#{i}",
     %{
       "id" => i,
       "name" => "item_#{i}",
       "active" => rem(i, 2) == 0,
       "tags" => ["tag_#{i}", "tag_#{i + 1}", "tag_#{i + 2}"],
       "meta" => %{
         "created_at" => "2026-01-0#{rem(i, 9) + 1}",
         "score" => i * 1.5,
         "nested" => %{"depth" => 3, "values" => [i, i + 1, i + 2]}
       }
     }}
  end

data = %{corpus: corpus, small: small, stress: stress}

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
