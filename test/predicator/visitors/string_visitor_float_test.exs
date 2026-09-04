defmodule Predicator.Visitors.StringVisitorFloatTest do
  @moduledoc """
  px-ggb: `StringVisitor` must be able to render every literal the parser can
  produce, floats included, or parse-then-decompile is partial and
  `Predicator.Simple.to_source/2` cannot be total.

  The corpus is enumerated rather than randomised - this repo carries no
  property-testing dependency and gains none here - and it is generated from
  the lexer's number rule (`digits "." digits`, `take_number/4` in
  `lexer.ex`) rather than transcribed, so it ranges over the magnitudes where
  `Float.to_string/1` switches to scientific notation instead of only over the
  examples someone happened to think of.

  Integers are carried through the same laws so the clause sitting beside the
  new one is pinned against regression.
  """

  use ExUnit.Case, async: true

  alias Predicator.Visitors.StringVisitor

  # The lexer accepts an unsigned digit run, a point, and another digit run,
  # with no exponent form and no leading sign. Every source below is built from
  # that rule.
  @integer_parts ["0", "1", "2", "500", "1234567890123456789"]
  @fraction_parts [
    "0",
    "1",
    "5",
    "50",
    "99",
    "0000001",
    "000000000000001",
    "123456789012345",
    "3333333333333333"
  ]

  defp float_sources do
    for integer_part <- @integer_parts,
        fraction_part <- @fraction_parts,
        do: integer_part <> "." <> fraction_part
  end

  defp integer_sources, do: @integer_parts

  # The values the sources parse to, plus the magnitudes reachable only by
  # building an AST by hand: what a writer that must be total has to render.
  defp float_values do
    parsed =
      for source <- float_sources() do
        {:ok, {:literal, value, _position}} = Predicator.parse(source)
        value
      end

    Enum.uniq(parsed ++ [0.0, 1.0e-300, 1.0e300, 1.0e-308, 1.0e308])
  end

  defp strip_positions(node) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> Enum.drop(-1)
    |> Enum.map(&strip_positions/1)
    |> List.to_tuple()
  end

  defp strip_positions(list) when is_list(list), do: Enum.map(list, &strip_positions/1)
  defp strip_positions(other), do: other

  describe "a float literal renders to source that parses back to an equal node" do
    test "for every value in the corpus" do
      values = float_values()
      assert length(values) > 30

      for value <- values do
        source = StringVisitor.visit({:literal, value, nil}, [])

        assert {:ok, reparsed} = Predicator.parse(source),
               "rendered #{inspect(source)} for #{inspect(value)}, which does not parse"

        assert reparsed == {:literal, value, {1, 1}},
               "#{inspect(value)} rendered as #{inspect(source)}, which parses to " <>
                 "#{inspect(reparsed)}"
      end
    end

    test "the rendered source never uses scientific notation, which the lexer rejects" do
      for value <- float_values() do
        source = StringVisitor.visit({:literal, value, nil}, [])

        refute source =~ "e", "#{inspect(value)} rendered as #{inspect(source)}"
      end
    end

    test "parse -> decompile -> parse is a fixed point for every float source" do
      for source <- float_sources() do
        expression = "amount == " <> source

        assert {:ok, ast} = Predicator.parse(expression)
        written = Predicator.decompile(ast)
        assert {:ok, reparsed} = Predicator.parse(written)

        assert strip_positions(reparsed) == strip_positions(ast),
               "#{expression} decompiled to #{inspect(written)}, which parses to a " <>
                 "different node"
      end
    end
  end

  describe "the named cases the bead calls out" do
    test "1.5 renders as the source 1.5, not as 1 and not as a raise" do
      assert StringVisitor.visit({:literal, 1.5, nil}, []) == "1.5"
    end

    test "an integral float stays a float, distinct from the integer node" do
      assert StringVisitor.visit({:literal, 1.0, nil}, []) == "1.0"
      assert {:ok, {:literal, 1.0, _position}} = Predicator.parse("1.0")
      assert {:ok, {:literal, 1, _position}} = Predicator.parse("1")
    end

    test "a small magnitude expands instead of going scientific" do
      # `Float.to_string(1.0e-7)` is "1.0e-7", which lexes as a float then an
      # identifier and fails to parse.
      assert StringVisitor.visit({:literal, 1.0e-7, nil}, []) == "0.0000001"
    end

    test "a large magnitude expands instead of going scientific" do
      assert StringVisitor.visit({:literal, 1.0e21, nil}, []) == "1000000000000000000000.0"
    end

    test "the parser produces no negative float literal, only a unary node" do
      assert {:ok, {:unary, :minus, {:literal, 1.5, _inner}, _outer}} = Predicator.parse("-1.5")
    end

    test "a hand-built negative float renders the way a negative integer does" do
      assert StringVisitor.visit({:literal, -1.5, nil}, []) == "-1.5"
      assert StringVisitor.visit({:literal, -15, nil}, []) == "-15"
    end
  end

  describe "the integer path is unchanged" do
    test "every integer source still renders exactly as it parsed" do
      for source <- integer_sources() do
        assert {:ok, {:literal, value, _position} = ast} = Predicator.parse(source)
        assert is_integer(value)
        assert StringVisitor.visit(ast, []) == source
      end
    end

    test "a float inside a list literal renders alongside the other scalars" do
      ast = {:literal, [1, 1.5, true], nil}

      assert StringVisitor.visit(ast, []) == "[1, 1.5, true]"
    end
  end

  describe "a float in a card-domain expression survives the trip" do
    test "an amount with cents decompiles and parses back unchanged" do
      assert {:ok, ast} = Predicator.parse("amount >= 500.25")
      assert Predicator.decompile(ast) == "amount >= 500.25"
    end
  end
end
