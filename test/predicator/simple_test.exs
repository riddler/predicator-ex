defmodule Predicator.SimpleTest do
  @moduledoc """
  Tests for `Predicator.Simple`, the picklist-renderable subset.

  The two round-trip laws are checked over an enumerated corpus rather than a
  randomised one. This repo carries no property-testing dependency and px-4jp
  is explicitly a no-new-deps bead, so the corpus is built by taking the
  cartesian product of every path shape, every operator, and every value shape
  the subset admits, then joining samples of it under both connectives. That is
  a few thousand cases, generated rather than transcribed, and it is
  exhaustive over the subset's shape vocabulary in a way a random sample would
  only be probably.
  """

  use ExUnit.Case, async: true

  alias Predicator.Errors.ParseError
  alias Predicator.Lexer
  alias Predicator.Simple
  alias Predicator.Vocabulary

  doctest Predicator.Simple

  # -- the corpus -------------------------------------------------------------

  @paths [
    [root: "status"],
    [root: "card", property: "brand"],
    [root: "cart", key: "items"],
    [root: "cart", key: 0],
    [root: "signup", property: "step", key: "current"]
  ]

  @ops [:gt, :gte, :lt, :lte, :equal_equal, :ne, :strict_eq, :strict_ne, :in, :contains]

  @scalars [
    {:integer, 0},
    {:integer, 500},
    {:float, 0.0},
    {:float, 19.99},
    {:float, 500.0},
    {:float, 0.0000001},
    {:boolean, true},
    {:boolean, false},
    {:string, "active", :single},
    {:string, "visa", :double},
    {:date, ~D[2024-01-15]},
    {:datetime, ~U[2024-01-15 10:30:00Z]},
    {:duration, [{3, "d"}]},
    {:duration, [{3, "d"}, {8, "h"}]},
    {:relative_date, [{30, "d"}], :ago},
    {:relative_date, [{2, "w"}], :future},
    {:relative_date, [{1, "m"}], :next},
    {:relative_date, [{1, "m"}], :last}
  ]

  @values @scalars ++
            [
              {:list, []},
              {:list, [{:string, "payment", :single}]},
              {:list, [{:string, "payment", :single}, {:string, "review", :single}]},
              {:list, [{:integer, 1}, {:integer, 2}, {:integer, 3}]},
              {:list, [{:float, 1.5}, {:float, 2.0}]},
              {:list, [{:integer, 1}, {:float, 1.5}]}
            ]

  defp single_clauses do
    for path <- @paths, op <- @ops, value <- @values, do: {path, op, value}
  end

  defp singles do
    Enum.map(single_clauses(), &%Simple{connective: nil, clauses: [&1]})
  end

  # Pairs and triples, taken from a strided sample of the clause corpus so the
  # multi-clause cases still range over every path, operator, and value shape
  # without multiplying the corpus by itself.
  defp multis do
    clauses = single_clauses()
    count = length(clauses)

    for connective <- [:and, :or],
        size <- [2, 3],
        offset <- 0..(count - 1)//7 do
      picked = for i <- 0..(size - 1), do: Enum.at(clauses, rem(offset + i * 37, count))
      %Simple{connective: connective, clauses: picked}
    end
  end

  defp corpus, do: singles() ++ multis()

  # -- the laws ---------------------------------------------------------------

  describe "round-trip law: from_ast(to_ast(simple)) == {:ok, simple}" do
    test "holds for every value in the corpus" do
      corpus = corpus()
      assert length(corpus) > 1_000

      for simple <- corpus do
        assert Simple.from_ast(Simple.to_ast(simple)) == {:ok, simple},
               "AST round-trip lost information for #{inspect(simple)}"
      end
    end
  end

  describe "round-trip law: to_source(simple) parses to to_ast(simple)" do
    test "holds for every value in the corpus, modulo source positions" do
      for simple <- corpus() do
        source = Simple.to_source(simple)

        assert {:ok, parsed} = Predicator.parse(source),
               "to_source produced unparseable source #{inspect(source)} for #{inspect(simple)}"

        assert strip_positions(parsed) == strip_positions(Simple.to_ast(simple)),
               "source round-trip changed the AST for #{inspect(source)}"
      end
    end

    test "the reparsed source reads back as the same subset value" do
      for simple <- corpus() do
        assert Simple.from_source(Simple.to_source(simple)) == {:ok, simple}
      end
    end
  end

  describe "every corpus value is well-formed" do
    test "well_formed?/1 accepts everything from_ast/1 can produce" do
      for simple <- corpus(), do: assert(Simple.well_formed?(simple))
    end
  end

  # -- from_source: the three arms --------------------------------------------

  describe "from_source/1" do
    test "reads the canonical picklist expressions" do
      assert {:ok,
              %Simple{
                connective: nil,
                clauses: [{[root: "status"], :equal_equal, {:string, "active", :single}}]
              }} =
               Simple.from_source("status == 'active'")

      assert {:ok, %Simple{connective: nil, clauses: [{[root: "amount"], :gte, {:integer, 500}}]}} =
               Simple.from_source("amount >= 500")

      assert {:ok,
              %Simple{
                connective: nil,
                clauses: [
                  {[root: "step"], :in,
                   {:list, [{:string, "payment", :single}, {:string, "review", :single}]}}
                ]
              }} = Simple.from_source("step in ['payment', 'review']")

      assert {:ok,
              %Simple{
                connective: nil,
                clauses: [{[root: "plan"], :equal_equal, {:string, "pro", :single}}]
              }} =
               Simple.from_source("plan == 'pro'")
    end

    test "joins clauses under one connective" do
      assert {:ok, %Simple{connective: :and, clauses: clauses}} =
               Simple.from_source("status == 'active' AND amount >= 500 AND plan == 'pro'")

      assert length(clauses) == 3

      assert {:ok, %Simple{connective: :or, clauses: [_first, _second]}} =
               Simple.from_source("plan == 'pro' OR amount >= 500")
    end

    test "accepts both cases of the word connectives and the symbol forms" do
      {:ok, expected} = Simple.from_source("status == 'active' AND amount >= 500")

      for source <- [
            "status == 'active' and amount >= 500",
            "status == 'active' && amount >= 500"
          ] do
        assert Simple.from_source(source) == {:ok, expected}
      end
    end

    test "reads property and bracket access chains as paths" do
      assert {:ok, %Simple{clauses: [{[root: "card", property: "brand"], _op, _value}]}} =
               Simple.from_source("card.brand == 'visa'")

      assert {:ok, %Simple{clauses: [{[root: "cart", key: "items"], _op, _value}]}} =
               Simple.from_source("cart['items'] contains 'gift'")

      assert {:ok, %Simple{clauses: [{[root: "cart", key: 0], _op, _value}]}} =
               Simple.from_source("cart[0] == 'gift'")
    end

    test "reads durations and relative dates as values" do
      assert {:ok, %Simple{clauses: [{_path, :lt, {:relative_date, [{30, "d"}], :ago}}]}} =
               Simple.from_source("signup.created_at < 30d ago")

      assert {:ok, %Simple{clauses: [{_path, :gt, {:relative_date, [{2, "w"}], :future}}]}} =
               Simple.from_source("card.expires_at > 2w from now")

      assert {:ok, %Simple{clauses: [{_path, :equal_equal, {:duration, [{3, "d"}, {8, "h"}]}}]}} =
               Simple.from_source("step.timeout == 3d8h")
    end

    test "answers :outside for a valid expression the subset excludes" do
      outside = [
        "NOT plan == 'pro'",
        "!(plan == 'pro')",
        "status == 'active' AND (amount >= 500 OR plan == 'pro')",
        "status == 'active' AND amount >= 500 OR plan == 'pro'",
        "status == 'active' OR amount >= 500 AND plan == 'pro'",
        "amount + 1 >= 500",
        "amount >= 500 - 1",
        "len(step) > 0",
        "amount::integer >= 500",
        "status == {plan: 'pro'}",
        "amount >= 500",
        "500 <= amount",
        "amount",
        "true"
      ]

      # `amount >= 500` is in the list as a control: it must NOT be :outside.
      assert {:ok, _simple} = Simple.from_source("amount >= 500")

      for source <- outside -- ["amount >= 500"] do
        assert Simple.from_source(source) == :outside,
               "expected :outside for #{inspect(source)}"
      end
    end

    test "a reversed clause is outside: the path is always on the left" do
      assert Simple.from_source("500 <= amount") == :outside
      assert Simple.from_source("'active' == status") == :outside
    end

    test "a float literal is inside, now that decompile/2 renders one" do
      # This test pinned the opposite until px-gv1. The exclusion was contingent
      # on Predicator.decompile/2 raising FunctionClauseError on
      # {:literal, 1.5, _} (px-ggb: StringVisitor had no is_float clause).
      # px-ggb gave the writer that clause, so the reason went and the exclusion
      # went with it. The property is still pinned, in the other direction.
      assert {:ok, {:comparison, _op, _left, {:literal, 19.99, _pos}, _cpos}} =
               Predicator.parse("card.amount == 19.99")

      assert {:ok, %Simple{clauses: [{path, :equal_equal, value}]} = simple} =
               Simple.from_source("card.amount == 19.99")

      assert path == [root: "card", property: "amount"]
      assert value == {:float, 19.99}
      assert Simple.to_source(simple) == "card.amount == 19.99"
      assert Simple.from_ast(Simple.to_ast(simple)) == {:ok, simple}
    end

    test "a negative float is outside, exactly as a negative integer is" do
      assert {:ok, {:comparison, _op, _left, {:unary, :minus, _operand, _upos}, _cpos}} =
               Predicator.parse("card.amount == -19.99")

      assert Simple.from_source("card.amount == -19.99") == :outside
    end

    test "a negative number is outside: the parser reads it as a unary node" do
      assert {:ok, {:comparison, _op, _left, {:unary, :minus, _operand, _upos}, _cpos}} =
               Predicator.parse("amount == -5")

      assert Simple.from_source("amount == -5") == :outside
    end

    test "returns a structured ParseError for source that does not parse" do
      assert {:error, %ParseError{} = error} = Simple.from_source("status == ==")
      assert error.position == {1, 11}
      assert error.span != nil
      assert is_binary(error.message)
    end

    test "the three arms are distinguishable" do
      assert {:ok, %Simple{}} = Simple.from_source("plan == 'pro'")
      assert :outside == Simple.from_source("NOT plan == 'pro'")
      assert {:error, %ParseError{}} = Simple.from_source("plan == ==")
    end
  end

  # -- from_ast is total ------------------------------------------------------

  describe "from_ast/1 is total" do
    test "answers :outside rather than raising for every non-subset node shape" do
      nodes = [
        {:literal, 1, nil},
        {:literal, nil, nil},
        {:literal, :undefined, nil},
        {:literal, "bare", nil},
        {:string_literal, "active", :single, nil},
        {:identifier, "status", nil},
        {:arithmetic, :add, {:identifier, "amount", nil}, {:literal, 1, nil}, nil},
        {:unary, :minus, {:literal, 5, nil}, nil},
        {:logical_not, {:identifier, "status", nil}, nil},
        {:list, [{:literal, 1, nil}], nil},
        {:object, [], nil},
        {:function_call, "len", [{:identifier, "step", nil}], nil},
        {:bracket_access, {:identifier, "cart", nil}, {:identifier, "i", nil}, nil},
        {:property_access, {:literal, 1, nil}, "brand", nil},
        {:cast, {:identifier, "amount", nil}, "integer", nil},
        {:duration, [{3, "d"}], nil},
        {:relative_date, {:duration, [{3, "d"}], nil}, :ago, nil},
        {:comparison, :eq, {:identifier, "plan", nil}, {:string_literal, "pro", :single, nil},
         nil},
        {:comparison, :equal_equal, {:identifier, "plan", nil}, {:function_call, "f", [], nil},
         nil},
        {:membership, :in, {:identifier, "step", nil}, {:list, [{:identifier, "x", nil}], nil},
         nil},
        {:logical_and, {:identifier, "a", nil}, {:identifier, "b", nil}, nil},
        {:logical_or, {:literal, true, nil}, {:literal, false, nil}, nil},
        {:duration, [], nil},
        {:duration, [{3, "parsec"}], nil},
        {:relative_date, {:duration, [{3, "d"}], nil}, :sideways, nil}
      ]

      for node <- nodes do
        assert Simple.from_ast(node) == :outside, "expected :outside for #{inspect(node)}"
      end
    end

    test "ignores source positions: a parsed node and a hand-built one read alike" do
      {:ok, parsed} = Predicator.parse("plan == 'pro'")
      {:ok, spanned} = Predicator.parse("plan == 'pro'", spans: true)

      handmade =
        {:comparison, :equal_equal, {:identifier, "plan", nil},
         {:string_literal, "pro", :single, nil}, nil}

      assert Simple.from_ast(parsed) == Simple.from_ast(handmade)
      assert Simple.from_ast(spanned) == Simple.from_ast(handmade)
    end

    test "flattens a right-nested spine of one connective" do
      left_nested = "status == 'active' AND amount >= 500 AND plan == 'pro'"
      right_nested = "status == 'active' AND (amount >= 500 AND plan == 'pro')"

      assert {:ok, %Simple{connective: :and, clauses: clauses}} = Simple.from_source(left_nested)

      assert Simple.from_source(right_nested) ==
               {:ok, %Simple{connective: :and, clauses: clauses}}
    end
  end

  # -- to_ast / to_source -----------------------------------------------------

  describe "to_ast/1" do
    test "builds nodes with nil in every position slot" do
      {:ok, simple} = Simple.from_source("status == 'active' AND amount >= 500")
      ast = Simple.to_ast(simple)

      assert ast == strip_positions(ast)
    end

    test "joins clauses left-associatively, as the parser does" do
      {:ok, simple} = Simple.from_source("a == 1 AND b == 2 AND c == 3")

      assert {:logical_and, {:logical_and, _a, _b, nil}, _c, nil} = Simple.to_ast(simple)
    end

    test "a single clause carries no connective node" do
      {:ok, simple} = Simple.from_source("plan == 'pro'")
      assert {:comparison, :equal_equal, _left, _right, nil} = Simple.to_ast(simple)
    end

    test "membership clauses build membership nodes" do
      {:ok, simple} = Simple.from_source("step in ['payment']")
      assert {:membership, :in, _left, {:list, _elements, nil}, nil} = Simple.to_ast(simple)
    end
  end

  describe "to_source/2" do
    test "passes formatting options through to decompile/2" do
      {:ok, simple} = Simple.from_source("status == 'active' AND amount >= 500")

      assert Simple.to_source(simple) == "status == 'active' AND amount >= 500"
      assert Simple.to_source(simple, spacing: :compact) == "status=='active'ANDamount>=500"

      assert Simple.to_source(simple, parentheses: :explicit) =~ "("
    end

    test "preserves the quote style a string was written with" do
      {:ok, single} = Simple.from_source("plan == 'pro'")
      {:ok, double} = Simple.from_source(~s(plan == "pro"))

      assert Simple.to_source(single) == "plan == 'pro'"
      assert Simple.to_source(double) == ~s(plan == "pro")
    end
  end

  # -- well_formed? -----------------------------------------------------------

  describe "well_formed?/1" do
    test "rejects a connective that disagrees with the clause count" do
      clause = {[root: "amount"], :gte, {:integer, 500}}

      refute Simple.well_formed?(%Simple{connective: :and, clauses: [clause]})
      refute Simple.well_formed?(%Simple{connective: :or, clauses: [clause]})
      refute Simple.well_formed?(%Simple{connective: nil, clauses: [clause, clause]})
      assert Simple.well_formed?(%Simple{connective: nil, clauses: [clause]})
      assert Simple.well_formed?(%Simple{connective: :and, clauses: [clause, clause]})
    end

    test "rejects an empty clause list" do
      refute Simple.well_formed?(%Simple{connective: nil, clauses: []})
      refute Simple.well_formed?(%Simple{connective: :and, clauses: []})
    end

    test "rejects structurally invalid clauses" do
      bad = [
        {[root: "amount"], :plus, {:integer, 500}},
        {[], :gte, {:integer, 500}},
        {[property: "brand"], :gte, {:integer, 500}},
        {[root: "amount", root: "other"], :gte, {:integer, 500}},
        {[root: "amount"], :gte, {:integer, -1}},
        {[root: "amount"], :gte, {:float, -1.5}},
        {[root: "amount"], :gte, {:float, 1}},
        {[root: "amount"], :gte, {:string, "pro", :backtick}},
        {[root: "amount"], :gte, {:duration, []}},
        {[root: "amount"], :gte, {:duration, [{3, "parsec"}]}},
        {[root: "amount"], :gte, {:relative_date, [{3, "d"}], :sideways}},
        {[root: "cart", key: -1], :gte, {:integer, 1}},
        {[root: "amount"], :gte, {:list, [{:float, -1.5}]}},
        {[root: "amount"], :gte},
        :not_a_clause
      ]

      for clause <- bad do
        refute Simple.well_formed?(%Simple{connective: nil, clauses: [clause]}),
               "expected #{inspect(clause)} to be rejected"
      end
    end

    test "accepts a non-negative float, as a scalar and inside a list" do
      for value <- [{:float, 0.0}, {:float, 19.99}, {:list, [{:float, 1.5}, {:integer, 2}]}] do
        assert Simple.well_formed?(%Simple{
                 connective: nil,
                 clauses: [{[root: "card", property: "amount"], :gte, value}]
               }),
               "expected #{inspect(value)} to be accepted"
      end
    end

    test "rejects anything that is not a Simple struct" do
      refute Simple.well_formed?(nil)
      refute Simple.well_formed?(%{connective: nil, clauses: []})
      refute Simple.well_formed?("status == 'active'")
    end
  end

  describe "duration_units/0" do
    test "comes from the Vocabulary rather than a second hand-kept list" do
      assert Simple.duration_units() ==
               :duration_unit |> Predicator.Vocabulary.by_category() |> Enum.map(& &1.lexeme)

      assert "d" in Simple.duration_units()
      refute "parsec" in Simple.duration_units()
    end
  end

  describe "operators/1" do
    test "offers only operators the lexer accepts, spelled as it accepts them" do
      for kind <- Vocabulary.value_kinds(), offered <- Simple.operators(kind) do
        assert {:ok, tokens} = Lexer.tokenize(offered.lexeme),
               "operators(#{inspect(kind)}) offers #{inspect(offered.lexeme)}, which the " <>
                 "lexer rejects outright"

        types = tokens |> Enum.map(&elem(&1, 0)) |> Enum.reject(&(&1 == :eof))

        entry = Enum.find(Vocabulary.operators(), &(&1.lexeme == offered.lexeme))

        assert entry != nil,
               "operators(#{inspect(kind)}) offers #{inspect(offered.lexeme)}, which is " <>
                 "not a Predicator.Vocabulary operator entry at all"

        assert entry.token_type in types,
               "operators(#{inspect(kind)}) offers #{inspect(offered.lexeme)} as " <>
                 "#{inspect(entry.token_type)}, but it lexes to #{inspect(types)}"
      end
    end

    test "offers only operators a clause can carry" do
      for kind <- Vocabulary.value_kinds(), offered <- Simple.operators(kind) do
        simple = %Simple{connective: nil, clauses: [{[root: "amount"], offered.op, sample(kind)}]}

        assert Simple.well_formed?(simple),
               "operators(#{inspect(kind)}) offers #{inspect(offered.op)}, which " <>
                 "well_formed?/1 rejects in a clause"
      end
    end

    test "every offered operator round-trips through source for its kind" do
      for kind <- Vocabulary.value_kinds(), offered <- Simple.operators(kind) do
        simple = %Simple{connective: nil, clauses: [{[root: "amount"], offered.op, sample(kind)}]}

        source = Simple.to_source(simple)

        assert String.contains?(source, offered.lexeme),
               "operators(#{inspect(kind)}) offers #{inspect(offered.lexeme)}, but the " <>
                 "clause renders as #{inspect(source)} - the offered spelling is not the " <>
                 "one to_source/2 writes"

        assert {:ok, ^simple} = Simple.from_source(source),
               "#{inspect(source)}, built from an offered operator, does not read back as " <>
                 "the same value"
      end
    end

    test "never offers an operator outside the subset" do
      outside = [
        "=",
        "+",
        "-",
        "*",
        "/",
        "%",
        "and",
        "AND",
        "or",
        "OR",
        "not",
        "NOT",
        "::",
        "ago"
      ]

      for kind <- Vocabulary.value_kinds() do
        offered = Simple.operators(kind) |> Enum.map(& &1.lexeme)

        assert offered -- outside == offered,
               "operators(#{inspect(kind)}) offers #{inspect(offered -- (offered -- outside))}, " <>
                 "which no clause can carry"
      end
    end

    test "offers `IN` for a list and nothing else, and never offers it elsewhere" do
      assert Simple.operators(:list) == [
               %{op: :in, lexeme: "IN", label: "is one of", arity: 2}
             ]

      for kind <- Vocabulary.value_kinds(), kind != :list do
        refute :in in Enum.map(Simple.operators(kind), & &1.op),
               "operators(#{inspect(kind)}) offers IN, whose right-hand side is a list"
      end
    end

    test "offers no ordered comparison for a boolean" do
      ops = Simple.operators(:boolean) |> Enum.map(& &1.op)

      for op <- [:gt, :gte, :lt, :lte] do
        refute op in ops
      end
    end

    test "reads its labels and arities from the Vocabulary rather than a local table" do
      for kind <- Vocabulary.value_kinds(), offered <- Simple.operators(kind) do
        entry = Enum.find(Vocabulary.operators(), &(&1.lexeme == offered.lexeme))

        assert offered.label == entry.label
        assert offered.arity == entry.arity
        assert offered.op == entry.ast_op
      end
    end

    test "raises on a kind the vocabulary does not enumerate" do
      # `:float` used to be this test's example. It is a poor one since px-gv1:
      # a float is admitted, under the `:number` kind, so the raise would read
      # as a statement that floats are unsupported.
      refute :decimal in Vocabulary.value_kinds()
      assert_raise FunctionClauseError, fn -> Simple.operators(:decimal) end
    end

    test "offers the same operators for a float value as for an integer one" do
      # px-gv1 folded floats into `:number` rather than giving them a kind of
      # their own. That is what makes this assertion sayable at all: one kind,
      # one list, and no branch for an editor to get wrong.
      refute :float in Vocabulary.value_kinds()

      for offered <- Simple.operators(:number) do
        simple = %Simple{
          connective: nil,
          clauses: [{[root: "card", property: "amount"], offered.op, {:float, 19.99}}]
        }

        assert Simple.well_formed?(simple)
        assert Simple.from_source(Simple.to_source(simple)) == {:ok, simple}
      end
    end
  end

  # -- helpers ----------------------------------------------------------------

  defp strip_positions({:literal, value, _pos}), do: {:literal, value, nil}
  defp strip_positions({:identifier, name, _pos}), do: {:identifier, name, nil}

  defp strip_positions({:string_literal, value, style, _pos}),
    do: {:string_literal, value, style, nil}

  defp strip_positions({:duration, units, _pos}), do: {:duration, units, nil}

  defp strip_positions({:relative_date, duration, direction, _pos}),
    do: {:relative_date, strip_positions(duration), direction, nil}

  defp strip_positions({:list, elements, _pos}),
    do: {:list, Enum.map(elements, &strip_positions/1), nil}

  defp strip_positions({tag, op, left, right, _pos}) when tag in [:comparison, :membership],
    do: {tag, op, strip_positions(left), strip_positions(right), nil}

  defp strip_positions({tag, left, right, _pos}) when tag in [:logical_and, :logical_or],
    do: {tag, strip_positions(left), strip_positions(right), nil}

  defp strip_positions({:property_access, target, property, _pos}),
    do: {:property_access, strip_positions(target), property, nil}

  defp strip_positions({:bracket_access, target, key, _pos}),
    do: {:bracket_access, strip_positions(target), strip_positions(key), nil}

  defp sample(:string), do: {:string, "active", :single}
  defp sample(:number), do: {:integer, 500}
  defp sample(:boolean), do: {:boolean, true}
  defp sample(:date), do: {:date, ~D[2026-09-04]}
  defp sample(:datetime), do: {:datetime, ~U[2026-09-04 12:00:00Z]}
  defp sample(:duration), do: {:duration, [{3, "d"}]}
  defp sample(:list), do: {:list, [{:string, "payment", :single}, {:string, "review", :single}]}
end
