defmodule Predicator.Conformance.PackageBoundaryTest do
  @moduledoc """
  Guards the invariant `mix.exs`'s `exclude_patterns` rests on: the conformance
  apparatus is dev tooling, so no code that ships in the hex package may
  reference it.

  `Predicator.Conformance.*` is matched by `package/0`'s `lib/predicator*` glob
  and then removed again by `exclude_patterns`, so those modules do not exist
  in a consumer's dependency tree. A shipped module that grew a reference to
  one would compile green here - where the whole repository is present - and
  fail for whoever pulled predicator from hex. Nothing in the suite would
  notice, which is why this is checked rather than assumed (`px-35i.4`).

  The same reasoning covers `Mix.Tasks.Corpus.*`: never matched by the glob,
  never shipped, equally unavailable to a consumer.
  """

  use ExUnit.Case, async: true

  # Everything under lib/ that the package ships, minus the two directories
  # that are deliberately excluded from it.
  @excluded_dirs ["lib/predicator/conformance/", "lib/mix/"]

  @shipped_lib_files Path.wildcard("lib/**/*.ex")
                     |> Enum.reject(fn path ->
                       Enum.any?(@excluded_dirs, &String.starts_with?(path, &1))
                     end)

  test "no shipped module references the conformance apparatus" do
    # Sanity floor: a wildcard that silently matched nothing would make every
    # assertion below vacuous.
    assert length(@shipped_lib_files) > 10

    offenders =
      Enum.filter(@shipped_lib_files, fn path ->
        source = File.read!(path)

        String.contains?(source, "Predicator.Conformance") or
          String.contains?(source, "Mix.Tasks.Corpus")
      end)

    assert offenders == [],
           """
           These files ship in the hex package but reference code that does not
           (mix.exs excludes lib/predicator/conformance/ and never matched
           lib/mix/). A consumer would fail to compile:

           #{Enum.join(offenders, "\n")}

           Either move the shared code out of Predicator.Conformance, or widen
           package/0's files: to ship it.
           """
  end

  test "mix.exs still excludes the conformance modules it claims to" do
    # Binds the comment in mix.exs to the code: dropping exclude_patterns
    # would ship the generator again, and the test above would stop meaning
    # anything without failing.
    assert Mix.Project.config()[:package][:exclude_patterns] == [
             ~r{\Alib/predicator/conformance/}
           ]
  end
end
