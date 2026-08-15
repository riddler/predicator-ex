defmodule Predicator.ParserStringTokenArityTest do
  @moduledoc """
  No parse path raises on a misplaced string literal, whatever the token's
  arity.

  `Lexer.token/0` is a union of five-element `{type, line, column, length,
  value}` tuples, except `:string`, which is seven elements (it also carries
  `quote_type` and `end_position`). Sixteen sites in `lib/predicator/parser.ex`
  once destructured the five-element shape directly in their error and
  fallback clauses, so a `:string` token reaching one of them matched no
  clause and raised (`CaseClauseError` or, at one site, `MatchError`) instead
  of returning `{:error, %Predicator.Errors.ParseError{}}`. Phase 1
  (px-yoq) routed every site through arity-blind accessors
  (`token_type/1`, `token_value/1`) and a shared constructor
  (`unexpected_token_error/2`) instead.

  This module tests the invariant two ways: a per-site table naming the
  parser function and the source that reaches it (so a failure names its
  clause), and a generative sweep that splices a string literal into
  well-formed sources at every whitespace boundary, which is not tied to any
  line number or clause list and so keeps working after the parser is
  refactored.
  """
  use ExUnit.Case

  # {site, entry point, source} - thirteen sites a string reaches from
  # source. Each source below was run against Predicator.compile/1 or
  # Predicator.compile_program/1 at HEAD (before the Phase 1 fix) and
  # confirmed to raise, and again after the fix to confirm the message and
  # error shape below - a source that already returns an error value before
  # the fix would be exercising some other, unrelated clause.
  @string_sites [
    {"parse/2 (:377)", :compile, ~s|score "a"|},
    {"finish_program/4 (:477)", :compile_program, ~s|x = 1 "a"|},
    {"parse_block/1 (:661)", :compile_program, ~s|if true "a" { x = 1 }|},
    {"finish_block/4 (:703)", :compile_program, ~s|if true { x = 1 "a" }|},
    {"postfix ']' (:1283)", :compile, ~s|a[0 "a"]|},
    {"postfix property (:1316)", :compile, ~s|a."b"|},
    {"postfix cast type (:1345)", :compile, ~s|a::"b"|},
    {"primary ')' (:1450)", :compile, ~s|(1 "a")|},
    {"parse_list/2 (:1714)", :compile, ~s|[1, 2 "a"]|},
    {"parse_object/2 (:1775)", :compile, ~s|{"a": 1 "b"}|},
    {"function args ')' (:1901)", :compile, ~s|f(1 "a")|},
    {"duration direction (:2015)", :compile, ~s|3d from "a"|},
    {"relative date (:2043)", :compile, ~s|next "a"|}
  ]

  describe "per-site sweep: a misplaced string literal from source" do
    for {site, entry, source} <- @string_sites do
      test "a misplaced string literal is an error value at #{site}" do
        assert {:error, %Predicator.Errors.ParseError{}} =
                 apply(Predicator, unquote(entry), [unquote(source)])
      end
    end
  end

  describe "per-site sweep: the three sites a string cannot reach from source" do
    # parse_function_call/3 ("Expected '(' after function name", :1930)
    # is unreachable from source at all - the lexer emits :function_name
    # only when a '(' immediately follows an identifier
    # (lexer.ex:545-553), so `len "a"` lexes `len` as a plain :identifier
    # and never enters parse_function_call/3. It is reachable through the
    # public Parser.parse/2, which accepts a token list directly, so this
    # entry builds one by hand. This is also the strongest test of the
    # fix among the three: the string token here is the real
    # seven-element shape, not a substitute.
    test "parse_function_call/3 'Expected (' after function name" do
      tokens = [
        {:function_name, 1, 1, 3, "len"},
        {:string, 1, 5, 3, "a", :double, {1, 8}},
        {:eof, 1, 8, 0, nil}
      ]

      assert {:error, message, line, col, span} = Predicator.Parser.parse(tokens)
      assert message == "Expected '(' after function name but found string \"a\""
      assert line == 1
      assert col == 5
      assert span == {{1, 5}, {1, 8}}
    end

    # parse_primary_token/2's catch-all (:1489) and parse_object_key/1's
    # generic clause (:1878) cannot receive a :string token by any route -
    # a dedicated :string clause matches ahead of each in both functions,
    # so a string literal in primary position or as an object key is
    # simply valid. These two entries use an ordinary five-element token
    # instead and assert the existing message text verbatim, to show the
    # arity-blind rewrite did not alter either message.
    test "parse_primary_token/2's catch-all is unchanged for a non-string token" do
      assert {:error,
              %Predicator.Errors.ParseError{
                message:
                  "Expected number, string, boolean, date, datetime, identifier, function call, list, object, or '(' but found ','"
              }} = Predicator.compile(",")
    end

    test "parse_object_key/1's generic clause is unchanged for a non-string token" do
      assert {:error,
              %Predicator.Errors.ParseError{
                message: "Expected identifier or string for object key but found number '1'"
              }} = Predicator.compile("{1: 2}")
    end
  end

  # A fixture list of well-formed sources - expressions, programs, lists,
  # objects, function calls, casts, property and bracket access, relative
  # dates - each re-emitted with a string literal spliced in at every
  # whitespace boundary. Three splices are used so the quote_type and
  # end_position slots are both exercised on an error path: a double-quoted
  # string, a single-quoted string, and a string containing a raw newline.
  @fixtures [
    ~s|score > 85|,
    ~s|[1, 2, 3]|,
    ~s|{"a": 1, "b": 2}|,
    ~s|f(1, 2)|,
    ~s|a.b[0]::string|,
    ~s|3d from now|,
    ~s|x = 1; y = 2|,
    ~s|if true { x = 1 } else { x = 2 }|,
    ~s|a AND b OR c|,
    ~s|x IN [1, 2, 3]|,
    ~s|if a { x = 1 } else if b { x = 2 } else { x = 3 }|,
    ~s|x::integer OR y::float|,
    ~s|3d ago|,
    ~s|x = 1; y = 2; z = 3|
  ]
  @splices [~s|"zz"|, ~s|'zz'|, ~s|"a\nb"|]
  @minimum_sources 200

  defp generated_sources do
    for fixture <- @fixtures,
        splice <- @splices,
        {_word, i} <- Enum.with_index(String.split(fixture, " ")),
        do: fixture |> String.split(" ") |> List.insert_at(i, splice) |> Enum.join(" ")
  end

  test "no source with a spliced-in string literal raises" do
    sources = generated_sources()

    # Guards against a fixture list that silently shrinks to nothing - the
    # same vacuous-pass guard isa_sync_test.exs uses for @opcode_count.
    assert length(sources) >= @minimum_sources

    for source <- sources do
      result = Predicator.compile_program(source)

      assert match?({:ok, _}, result) or
               match?({:error, %Predicator.Errors.ParseError{}}, result),
             "compile_program/1 did not return a value for #{inspect(source)}: " <>
               inspect(result)
    end
  end
end
