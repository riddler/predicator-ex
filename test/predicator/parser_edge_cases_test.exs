defmodule Predicator.ParserEdgeCasesTest do
  use ExUnit.Case

  alias Predicator.Lexer

  describe "parser error handling" do
    test "handles empty token list" do
      {:error, message, line, col, _span} = parse_positionless([])
      assert message == "Unexpected end of input"
      assert line == 1
      assert col == 1
    end

    test "handles unexpected end of input" do
      {:ok, tokens} = Lexer.tokenize("x +")
      {:error, message, line, _col, _span} = parse_positionless(tokens)
      assert String.contains?(message, "end of input")
      assert line == 1
    end

    test "handles unexpected token" do
      {:ok, tokens} = Lexer.tokenize("(")
      {:error, message, line, col, _span} = parse_positionless(tokens)
      assert String.contains?(message, "Expected")
      assert line == 1
      assert col > 0
    end

    test "handles missing closing paren" do
      {:ok, tokens} = Lexer.tokenize("(x")
      {:error, message, line, _col, _span} = parse_positionless(tokens)
      assert String.contains?(message, "Expected ')' but found end of input")
      assert line == 1
    end

    test "handles missing closing bracket in list" do
      {:ok, tokens} = Lexer.tokenize("[1, 2")
      {:error, message, line, _col, _span} = parse_positionless(tokens)
      assert String.contains?(message, "Expected")
      assert line == 1
    end

    test "handles missing closing brace in object" do
      {:ok, tokens} = Lexer.tokenize("{name: 'test'")
      {:error, message, line, _col, _span} = parse_positionless(tokens)
      assert String.contains?(message, "Expected")
      assert line == 1
    end

    test "handles invalid object key" do
      {:ok, tokens} = Lexer.tokenize("{123: 'value'}")
      {:error, message, line, _col, _span} = parse_positionless(tokens)
      assert String.contains?(message, "Expected identifier or string for object key")
      assert line == 1
    end

    test "handles missing colon in object" do
      {:ok, tokens} = Lexer.tokenize("{name 'test'}")
      {:error, message, line, _col, _span} = parse_positionless(tokens)
      assert String.contains?(message, "Expected ':' after object key")
      assert line == 1
    end

    test "handles missing value after colon in object" do
      {:ok, tokens} = Lexer.tokenize("{name:}")
      {:error, message, line, _col, _span} = parse_positionless(tokens)
      assert String.contains?(message, "Expected")
      assert line == 1
    end
  end

  describe "primary expression parsing" do
    test "parses boolean literals" do
      {:ok, tokens} = Lexer.tokenize("true")
      {:ok, ast} = parse_positionless(tokens)
      assert ast == {:literal, true}
    end

    test "parses date literals" do
      {:ok, tokens} = Lexer.tokenize("#2024-01-15#")
      {:ok, ast} = parse_positionless(tokens)
      assert match?({:literal, %Date{}}, ast)
    end

    test "parses datetime literals" do
      {:ok, tokens} = Lexer.tokenize("#2024-01-15T10:30:00Z#")
      {:ok, ast} = parse_positionless(tokens)
      assert match?({:literal, %DateTime{}}, ast)
    end

    test "parses float literals" do
      {:ok, tokens} = Lexer.tokenize("3.14")
      {:ok, ast} = parse_positionless(tokens)
      assert ast == {:literal, 3.14}
    end

    test "parses string literals with quote types" do
      {:ok, tokens} = Lexer.tokenize("'single quoted'")
      {:ok, ast} = parse_positionless(tokens)
      assert ast == {:string_literal, "single quoted", :single}
    end
  end

  describe "list parsing edge cases" do
    test "parses empty list" do
      {:ok, tokens} = Lexer.tokenize("[]")
      {:ok, ast} = parse_positionless(tokens)
      assert ast == {:list, []}
    end

    test "parses single element list" do
      {:ok, tokens} = Lexer.tokenize("[42]")
      {:ok, ast} = parse_positionless(tokens)
      assert ast == {:list, [{:literal, 42}]}
    end

    test "parses nested lists" do
      {:ok, tokens} = Lexer.tokenize("[[1, 2], [3, 4]]")
      {:ok, ast} = parse_positionless(tokens)

      expected =
        {:list,
         [
           {:list, [{:literal, 1}, {:literal, 2}]},
           {:list, [{:literal, 3}, {:literal, 4}]}
         ]}

      assert ast == expected
    end
  end

  describe "object parsing edge cases" do
    test "parses empty object" do
      {:ok, tokens} = Lexer.tokenize("{}")
      {:ok, ast} = parse_positionless(tokens)
      assert ast == {:object, []}
    end

    test "parses object with identifier key" do
      {:ok, tokens} = Lexer.tokenize("{name: 'John'}")
      {:ok, ast} = parse_positionless(tokens)

      expected =
        {:object, [{{:object_key, "name", :identifier}, {:string_literal, "John", :single}}]}

      assert ast == expected
    end

    test "parses object with string key" do
      {:ok, tokens} = Lexer.tokenize("{\"key\": 'value'}")
      {:ok, ast} = parse_positionless(tokens)
      expected = {:object, [{{:object_key, "key", :double}, {:string_literal, "value", :single}}]}
      assert ast == expected
    end

    test "parses nested objects" do
      {:ok, tokens} = Lexer.tokenize("{user: {name: 'John'}}")
      {:ok, ast} = parse_positionless(tokens)

      expected =
        {:object,
         [
           {{:object_key, "user", :identifier},
            {:object, [{{:object_key, "name", :identifier}, {:string_literal, "John", :single}}]}}
         ]}

      assert ast == expected
    end
  end

  describe "function call parsing" do
    test "parses function with no arguments" do
      {:ok, tokens} = Lexer.tokenize("len()")
      {:ok, ast} = parse_positionless(tokens)
      assert ast == {:function_call, "len", []}
    end

    test "parses function with single argument" do
      {:ok, tokens} = Lexer.tokenize("len('test')")
      {:ok, ast} = parse_positionless(tokens)
      expected = {:function_call, "len", [{:string_literal, "test", :single}]}
      assert ast == expected
    end

    test "parses function with multiple arguments" do
      {:ok, tokens} = Lexer.tokenize("max(1, 2, 3)")
      {:ok, ast} = parse_positionless(tokens)
      expected = {:function_call, "max", [{:literal, 1}, {:literal, 2}, {:literal, 3}]}
      assert ast == expected
    end

    test "parses qualified function calls" do
      {:ok, tokens} = Lexer.tokenize("Math.pow(2, 3)")
      {:ok, ast} = parse_positionless(tokens)
      expected = {:function_call, "Math.pow", [{:literal, 2}, {:literal, 3}]}
      assert ast == expected
    end
  end

  describe "bracket access parsing" do
    test "parses simple bracket access" do
      {:ok, tokens} = Lexer.tokenize("arr[0]")
      {:ok, ast} = parse_positionless(tokens)
      expected = {:bracket_access, {:identifier, "arr"}, {:literal, 0}}
      assert ast == expected
    end

    test "parses nested bracket access" do
      {:ok, tokens} = Lexer.tokenize("matrix[0][1]")
      {:ok, ast} = parse_positionless(tokens)

      expected =
        {:bracket_access, {:bracket_access, {:identifier, "matrix"}, {:literal, 0}},
         {:literal, 1}}

      assert ast == expected
    end

    test "parses bracket access with expression key" do
      {:ok, tokens} = Lexer.tokenize("arr[i + 1]")
      {:ok, ast} = parse_positionless(tokens)

      expected =
        {:bracket_access, {:identifier, "arr"},
         {:arithmetic, :add, {:identifier, "i"}, {:literal, 1}}}

      assert ast == expected
    end
  end

  describe "property access parsing" do
    test "parses simple property access" do
      {:ok, tokens} = Lexer.tokenize("obj.prop")
      {:ok, ast} = parse_positionless(tokens)
      expected = {:property_access, {:identifier, "obj"}, "prop"}
      assert ast == expected
    end

    test "parses chained property access" do
      {:ok, tokens} = Lexer.tokenize("user.profile.name")
      {:ok, ast} = parse_positionless(tokens)
      expected = {:property_access, {:property_access, {:identifier, "user"}, "profile"}, "name"}
      assert ast == expected
    end

    test "parses mixed bracket and property access" do
      {:ok, tokens} = Lexer.tokenize("users[0].name")
      {:ok, ast} = parse_positionless(tokens)

      expected =
        {:property_access, {:bracket_access, {:identifier, "users"}, {:literal, 0}}, "name"}

      assert ast == expected
    end
  end

  describe "unary expressions" do
    test "parses unary minus on numbers" do
      {:ok, tokens} = Lexer.tokenize("-42")
      {:ok, ast} = parse_positionless(tokens)
      assert ast == {:unary, :minus, {:literal, 42}}
    end

    test "parses unary bang on boolean" do
      {:ok, tokens} = Lexer.tokenize("!true")
      {:ok, ast} = parse_positionless(tokens)
      assert ast == {:logical_not, {:literal, true}}
    end

    test "parses nested unary expressions" do
      {:ok, tokens} = Lexer.tokenize("--x")
      {:ok, ast} = parse_positionless(tokens)
      expected = {:unary, :minus, {:unary, :minus, {:identifier, "x"}}}
      assert ast == expected
    end
  end

  describe "complex nested expressions" do
    test "parses function calls in arithmetic" do
      {:ok, tokens} = Lexer.tokenize("len(name) + 5")
      {:ok, ast} = parse_positionless(tokens)

      expected =
        {:arithmetic, :add, {:function_call, "len", [{:identifier, "name"}]}, {:literal, 5}}

      assert ast == expected
    end

    test "parses object access in comparisons" do
      {:ok, tokens} = Lexer.tokenize("user.age >= 18")
      {:ok, ast} = parse_positionless(tokens)

      expected =
        {:comparison, :gte, {:property_access, {:identifier, "user"}, "age"}, {:literal, 18}}

      assert ast == expected
    end

    test "parses list membership with complex expressions" do
      {:ok, tokens} = Lexer.tokenize("user.role in ['admin', 'manager']")
      {:ok, ast} = parse_positionless(tokens)

      expected =
        {:membership, :in, {:property_access, {:identifier, "user"}, "role"},
         {:list, [{:string_literal, "admin", :single}, {:string_literal, "manager", :single}]}}

      assert ast == expected
    end
  end

  # px-yoq: a `:string` token is seven elements, not the five-element shape
  # every arity-blind error site now reads positionally. These pin the bead's
  # named reproductions, which raised a CaseClauseError (or, for "next \"a\"",
  # a MatchError) before the fix.
  describe "a string literal in a rejected position" do
    test "limit \"a\" is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{}} = Predicator.compile(~s|limit "a"|)

      assert {:error, %Predicator.Errors.ParseError{}} =
               Predicator.compile_program(~s|limit "a"|)
    end

    test "5 \"a\" is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{}} = Predicator.compile(~s|5 "a"|)
    end

    test "true \"a\" is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{}} = Predicator.compile(~s|true "a"|)
    end

    test "a multi-line string literal in a rejected position is a parse error" do
      assert {:error, %Predicator.Errors.ParseError{} = error} =
               Predicator.compile(~s|[1, 2 "ab\ncd"]|)

      assert {_start, {end_line, _end_col}} = error.span
      assert end_line == 2
    end

    test "next \"a\" is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{}} = Predicator.compile(~s|next "a"|)
    end
  end

  # px-5c5 (fractional durations) introduced the `:fractional_number` token -
  # a five-element token like `:integer` and `:float`, so token_type/1 and
  # token_value/1 already read it fine, but `format_token/2` had no clause
  # for it and none of its 53 clauses is a catch-all. Any misplaced
  # fractional duration literal (`1.5s`) raised `FunctionClauseError` from
  # `format_token/2` instead of returning a `ParseError`, the same class of
  # bug px-yoq fixed for `:string` above. These pin the reproductions found
  # while fixing it; `1.5s` is never itself invalid (a fractional number is
  # always a valid duration start), so every source below places it after a
  # complete expression or in a position the grammar rejects outright.
  describe "a fractional duration literal in a rejected position" do
    test "limit 1.5s is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{message: message}} =
               Predicator.compile(~s|limit 1.5s|)

      assert message == "Unexpected token number '1.5' after expression"
    end

    test "f(1 1.5s) is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{}} = Predicator.compile(~s|f(1 1.5s)|)
    end

    test "[1, 2 1.5s] is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{}} = Predicator.compile(~s|[1, 2 1.5s]|)
    end

    test "(1 1.5s) is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{}} = Predicator.compile(~s|(1 1.5s)|)
    end

    test "a[0 1.5s] is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{}} = Predicator.compile(~s|a[0 1.5s]|)
    end

    test "3d from 1.5s is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{}} = Predicator.compile(~s|3d from 1.5s|)
    end

    test "x = 1 1.5s is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{}} =
               Predicator.compile_program(~s|x = 1 1.5s|)
    end

    test "if true 1.5s { x = 1 } is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{}} =
               Predicator.compile_program(~s|if true 1.5s { x = 1 }|)
    end

    test "if true { x = 1 1.5s } is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{}} =
               Predicator.compile_program(~s|if true { x = 1 1.5s }|)
    end

    test "a.1.5s is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{}} = Predicator.compile(~s|a.1.5s|)
    end

    test "a::1.5s is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{}} = Predicator.compile(~s|a::1.5s|)
    end

    test "{\"a\": 1 1.5s} is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{}} =
               Predicator.compile_program(~s|{"a": 1 1.5s}|)
    end

    test "{1.5s: 1} is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{}} = Predicator.compile(~s|{1.5s: 1}|)
    end
  end

  # px-ty0: format_token/2 also had no `:dot` clause - a separate,
  # pre-existing gap from :fractional_number's above (this one predates the
  # px-5c5 branch entirely), found while fixing that one. Decision 4 in
  # docs/research/260814-px-5c5-fractional-durations-decisions.md deliberately
  # rejects the leading-dot duration spelling ("`.5s`" is meant to be a parse
  # error), so these pin that it fails as a `ParseError` *value* rather than
  # raising `FunctionClauseError`. Unlike a misplaced fractional number, a
  # bare `.` is never itself a complete expression, so these repros put it
  # where the grammar expects a fresh primary token (an expression start, an
  # object key, a cast type name, the `now` keyword after `from`) rather than
  # after a complete expression - a `.` following any expression is always
  # consumed by postfix property-access parsing first, which is what keeps
  # "1 . 2" (below) a distinct, already-working case.
  describe "a bare '.' in a rejected position" do
    test ".5s is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{message: message}} =
               Predicator.compile(~s|.5s|)

      assert message ==
               "Expected number, string, boolean, date, datetime, identifier, " <>
                 "function call, list, object, or '(' but found '.'"
    end

    test ".5 is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{}} = Predicator.compile(~s|.5|)
    end

    test "a . . b is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{message: message}} =
               Predicator.compile(~s|a . . b|)

      assert message == "Expected property name after '.' but found '.'"
    end

    test "a::. is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{message: message}} =
               Predicator.compile(~s|a::.|)

      assert message == "Expected a type name after '::' but found '.'"
    end

    test "3d from . is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{message: message}} =
               Predicator.compile(~s|3d from .|)

      assert message == "Expected 'now' after 'from' but found '.'"
    end

    test "{.: 1} is a parse error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{message: message}} =
               Predicator.compile(~s|{.: 1}|)

      assert message == "Expected identifier or string for object key but found '.'"
    end

    test "1 . 2 keeps returning its existing property-name error, not a raise" do
      assert {:error, %Predicator.Errors.ParseError{message: message}} =
               Predicator.compile(~s|1 . 2|)

      assert message == "Expected property name after '.' but found number '2'"
    end
  end

  # These assertions are about AST *shape*, so they read the slot-free form;
  # positions and spans have their own suites.
  defp parse_positionless(input) do
    result =
      if is_binary(input),
        do: Predicator.parse(input),
        else: Predicator.Parser.parse(input)

    case result do
      {:ok, ast} -> {:ok, Predicator.ASTShape.strip(ast)}
      other -> other
    end
  end
end
