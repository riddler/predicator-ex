defmodule Predicator.VocabularyTest do
  use ExUnit.Case, async: true

  doctest Predicator.Vocabulary

  alias Predicator.Vocabulary

  defmodule TestProvider do
    @moduledoc false
    @behaviour Predicator.FunctionProvider

    @impl Predicator.FunctionProvider
    def functions do
      %{
        "host_lookup" => {1, :host_lookup},
        "host_ping" => {0, :host_ping},
        "host_slice" => {[2, 3], :host_slice}
      }
    end

    @spec host_lookup([term()], term()) :: {:ok, nil}
    def host_lookup(_args, _context), do: {:ok, nil}

    @spec host_ping([term()], term()) :: {:ok, nil}
    def host_ping(_args, _context), do: {:ok, nil}

    @spec host_slice([term()], term()) :: {:ok, nil}
    def host_slice(_args, _context), do: {:ok, nil}
  end

  describe "tokens/0" do
    test "every entry carries the five documented keys" do
      for entry <- Vocabulary.tokens() do
        assert %{
                 lexeme: lexeme,
                 token_type: token_type,
                 category: category,
                 display: display,
                 doc: doc
               } = entry

        assert is_binary(lexeme) and lexeme != ""
        assert is_atom(token_type)
        assert category in Vocabulary.categories()
        assert is_binary(display) and display != ""
        assert is_binary(doc) and doc != ""
      end
    end

    # An operator entry carries four more, and an entry outside an operator
    # category carries none of them - the same shape function_entry/0 has
    # against entry/0. Asserted as an exact key set in both directions so a
    # key added to one kind of entry and not documented on the other is
    # caught here.
    test "an entry carries exactly the keys its kind of thing has" do
      operators = MapSet.new(Vocabulary.operators(), & &1.lexeme)

      for entry <- Vocabulary.tokens() do
        expected =
          if entry.lexeme in operators do
            [
              :arity,
              :ast_op,
              :category,
              :display,
              :doc,
              :label,
              :lexeme,
              :token_type,
              :value_kinds
            ]
          else
            [:category, :display, :doc, :lexeme, :token_type]
          end

        assert entry |> Map.keys() |> Enum.sort() == expected,
               "the entry for #{inspect(entry.lexeme)} carries " <>
                 "#{inspect(entry |> Map.keys() |> Enum.sort())}"
      end
    end

    test "the operator keys carry the kinds of value they are documented to carry" do
      for entry <- Vocabulary.operators() do
        assert is_binary(entry.label) and entry.label != ""
        assert entry.arity in [0, 1, 2] or (is_list(entry.arity) and entry.arity != [])
        assert is_atom(entry.ast_op)
        assert entry.value_kinds == nil or is_list(entry.value_kinds)
      end
    end

    test "no doc ends in a period, so a consumer can punctuate it itself" do
      offenders =
        Vocabulary.tokens() |> Enum.map(& &1.doc) |> Enum.filter(&String.ends_with?(&1, "."))

      assert offenders == []
    end

    test "the display form contains the lexeme it describes" do
      for entry <- Vocabulary.tokens(), entry.category != :duration_unit do
        assert String.contains?(entry.display, entry.lexeme),
               "#{inspect(entry.display)} does not show #{inspect(entry.lexeme)}"
      end
    end

    test "lexemes are unique" do
      lexemes = Enum.map(Vocabulary.tokens(), & &1.lexeme)

      assert lexemes == Enum.uniq(lexemes)
    end

    test "carries no function entries" do
      refute Enum.any?(Vocabulary.tokens(), &(&1.category == :function))
    end
  end

  describe "categories/0 and by_category/1" do
    test "every category is populated" do
      for category <- Vocabulary.categories() do
        assert Vocabulary.by_category(category) != [],
               "category #{inspect(category)} has no entries"
      end
    end

    test "the categories partition tokens/0" do
      grouped =
        Vocabulary.categories()
        |> Enum.reject(&(&1 == :function))
        |> Enum.flat_map(&Vocabulary.by_category/1)

      assert Enum.sort_by(grouped, & &1.lexeme) == Enum.sort_by(Vocabulary.tokens(), & &1.lexeme)
    end

    test ":function delegates to functions/0" do
      assert Vocabulary.by_category(:function) == Vocabulary.functions()
    end

    test "an unknown category raises rather than reading as an empty one" do
      assert_raise FunctionClauseError, fn -> Vocabulary.by_category(:comparisons) end
    end
  end

  describe "operators/0" do
    test "spans exactly the value-combining categories" do
      assert Vocabulary.operators() |> Enum.map(& &1.category) |> Enum.uniq() |> Enum.sort() ==
               [:arithmetic, :cast, :comparison, :logical, :membership, :temporal]
    end

    test "includes the word-shaped operators alongside the symbols" do
      lexemes = Enum.map(Vocabulary.operators(), & &1.lexeme)

      assert "and" in lexemes
      assert "&&" in lexemes
      assert "contains" in lexemes
      refute "true" in lexemes
    end
  end

  describe "keywords/0" do
    test "holds the reserved words and no symbols or duration units" do
      lexemes = Enum.map(Vocabulary.keywords(), & &1.lexeme)

      assert "if" in lexemes
      assert "true" in lexemes
      assert "NOT" in lexemes
      refute "&&" in lexemes
      refute "d" in lexemes
      refute "mo" in lexemes
    end

    test "is a subset of tokens/0" do
      assert MapSet.subset?(
               MapSet.new(Vocabulary.keywords()),
               MapSet.new(Vocabulary.tokens())
             )
    end
  end

  describe "functions/1" do
    test "defaults to the builtin providers" do
      lexemes = Enum.map(Vocabulary.functions(), & &1.lexeme)

      assert "len" in lexemes
      assert "Math.abs" in lexemes
    end

    test "returns nothing when the builtins are turned off" do
      assert Vocabulary.functions(builtins: false) == []
    end

    test "resolves a host's own provider, which is the embedded-editor case" do
      entries = Vocabulary.functions(builtins: false, providers: [TestProvider])

      assert Enum.map(entries, & &1.lexeme) == ["host_lookup", "host_ping", "host_slice"]
    end

    test "displays a zero-arity call as an empty call and any other as an elided one" do
      entries =
        Vocabulary.functions(builtins: false, providers: [TestProvider])
        |> Map.new(&{&1.lexeme, &1.display})

      assert entries["host_ping"] == "host_ping()"
      assert entries["host_lookup"] == "host_lookup(...)"
      assert entries["host_slice"] == "host_slice(...)"
    end

    test "carries the arity and a nil doc" do
      entry = Enum.find(Vocabulary.functions(), &(&1.lexeme == "substring"))

      assert entry.arity == [2, 3]
      assert entry.doc == nil
      assert entry.category == :function
    end

    test "is sorted by name, since a dispatch map has no order" do
      lexemes = Enum.map(Vocabulary.functions(), & &1.lexeme)

      assert lexemes == Enum.sort(lexemes)
    end
  end

  describe "all/1" do
    test "is tokens/0 followed by functions/1 on the same opts" do
      assert Vocabulary.all(builtins: false) == Vocabulary.tokens()
      assert Vocabulary.all() == Vocabulary.tokens() ++ Vocabulary.functions()
    end
  end
end
