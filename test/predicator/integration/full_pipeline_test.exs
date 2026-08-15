defmodule Predicator.IntegrationTest do
  use ExUnit.Case, async: true

  alias Predicator.{Compiler, Evaluator, Lexer, Parser}
  alias Predicator.Errors.UndefinedVariableError

  describe "full pipeline integration" do
    test "string -> tokens -> ast -> instructions -> evaluation" do
      input = "score > 85"
      context = %{"score" => 90}

      # Lex
      {:ok, tokens} = Lexer.tokenize(input)

      # Parse
      {:ok, ast} = Parser.parse(tokens)

      # Compile
      instructions = Compiler.to_instructions(ast)

      assert instructions == [
               ["load", "score"],
               ["lit", 85],
               ["compare", "GT"]
             ]

      # Evaluate
      result = Evaluator.evaluate!(instructions, context)
      assert result == true
    end

    test "complex expression with parentheses" do
      input = "(age >= 18)"
      context = %{"age" => 21}

      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)
      instructions = Compiler.to_instructions(ast)

      assert instructions == [
               ["load", "age"],
               ["lit", 18],
               ["compare", "GTE"]
             ]

      result = Evaluator.evaluate!(instructions, context)
      assert result == true
    end

    test "string comparison" do
      input = "name == \"John\""
      context = %{"name" => "John"}

      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)
      instructions = Compiler.to_instructions(ast)

      assert instructions == [
               ["load", "name"],
               ["lit", "John"],
               ["compare", "EQ"]
             ]

      result = Evaluator.evaluate!(instructions, context)
      assert result == true
    end

    test "boolean comparison" do
      input = "active == true"
      context = %{"active" => true}

      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)
      instructions = Compiler.to_instructions(ast)

      assert instructions == [
               ["load", "active"],
               ["lit", true],
               ["compare", "EQ"]
             ]

      result = Evaluator.evaluate!(instructions, context)
      assert result == true
    end

    test "not equal comparison evaluates to false" do
      input = "status != \"active\""
      context = %{"status" => "active"}

      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)
      instructions = Compiler.to_instructions(ast)

      result = Evaluator.evaluate!(instructions, context)
      assert result == false
    end

    test "all comparison operators work correctly" do
      test_cases = [
        {"x > 5", %{"x" => 10}, true},
        {"x > 5", %{"x" => 3}, false},
        {"x < 5", %{"x" => 3}, true},
        {"x < 5", %{"x" => 10}, false},
        {"x >= 5", %{"x" => 5}, true},
        {"x >= 5", %{"x" => 4}, false},
        {"x <= 5", %{"x" => 5}, true},
        {"x <= 5", %{"x" => 6}, false},
        {"x == 5", %{"x" => 5}, true},
        {"x == 5", %{"x" => 6}, false},
        {"x != 5", %{"x" => 6}, true},
        {"x != 5", %{"x" => 5}, false}
      ]

      for {input, context, expected} <- test_cases do
        {:ok, tokens} = Lexer.tokenize(input)
        {:ok, ast} = Parser.parse(tokens)
        instructions = Compiler.to_instructions(ast)
        result = Evaluator.evaluate!(instructions, context)

        assert result == expected, "Failed for input: #{input} with context: #{inspect(context)}"
      end
    end

    test "handles missing context keys" do
      input = "missing_key > 5"
      context = %{}

      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)
      instructions = Compiler.to_instructions(ast)

      _result = Evaluator.evaluate!(instructions, context)
      result = Evaluator.evaluate(instructions, context)
      assert result == :undefined
    end

    test "nested context access integration" do
      input = "user.name.first == \"John\""
      context = %{"user" => %{"name" => %{"first" => "John", "last" => "Doe"}, "age" => 47}}

      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)
      instructions = Compiler.to_instructions(ast)

      assert instructions == [
               ["load", "user"],
               ["access", "name"],
               ["access", "first"],
               ["lit", "John"],
               ["compare", "EQ"]
             ]

      result = Evaluator.evaluate!(instructions, context)
      assert result == true
    end

    test "nested context access with numeric comparison" do
      input = "user.age > 18"
      context = %{"user" => %{"name" => "John", "age" => 47}}

      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)
      instructions = Compiler.to_instructions(ast)

      assert instructions == [
               ["load", "user"],
               ["access", "age"],
               ["lit", 18],
               ["compare", "GT"]
             ]

      result = Evaluator.evaluate!(instructions, context)
      assert result == true
    end

    test "nested context access with missing path" do
      input = "user.profile.name == \"John\""
      context = %{"user" => %{"name" => "John", "age" => 47}}

      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)
      instructions = Compiler.to_instructions(ast)

      assert instructions == [
               ["load", "user"],
               ["access", "profile"],
               ["access", "name"],
               ["lit", "John"],
               ["compare", "EQ"]
             ]

      result = Evaluator.evaluate!(instructions, context)
      assert result == :undefined
    end

    test "nested context access in complex expressions" do
      input = "user.name.first == \"John\" AND user.age >= 18"
      context = %{"user" => %{"name" => %{"first" => "John"}, "age" => 47}}

      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)
      instructions = Compiler.to_instructions(ast)

      result = Evaluator.evaluate!(instructions, context)
      assert result == true
    end

    test "mixed nested and simple context access" do
      input = "score > 85 AND user.name.first == \"John\""
      context = %{"score" => 90, "user" => %{"name" => %{"first" => "John"}}}

      {:ok, tokens} = Lexer.tokenize(input)
      {:ok, ast} = Parser.parse(tokens)
      instructions = Compiler.to_instructions(ast)

      result = Evaluator.evaluate!(instructions, context)
      assert result == true
    end
  end

  describe "make_list integration" do
    test "non-literal list evaluates in source order" do
      assert Predicator.evaluate("[x + 1, y]", %{"x" => 1, "y" => 5}) == {:ok, [2, 5]}
    end

    test "membership over a constructed list" do
      assert Predicator.evaluate("2 in [x + 1, y]", %{"x" => 1, "y" => 5}) == {:ok, true}
    end

    test "contains over a constructed list" do
      assert Predicator.evaluate("[x + 1, y] contains 5", %{"x" => 1, "y" => 5}) == {:ok, true}
    end

    test "nested non-literal lists" do
      assert Predicator.evaluate("[a, [b, c]]", %{"a" => 1, "b" => 2, "c" => 3}) ==
               {:ok, [1, [2, 3]]}
    end

    test "mixed-type non-literal list" do
      assert Predicator.evaluate("[name, score]", %{"name" => "x", "score" => 1}) ==
               {:ok, ["x", 1]}
    end

    test "unbound identifier inside a non-literal list returns an error tuple, not a raise" do
      # px-1e1: positioned at the variable's own load, not the "+" that rejected it.
      assert Predicator.evaluate("[x + 1]", %{}) ==
               {:error, Predicator.Errors.put_position(UndefinedVariableError.new("x"), {1, 2})}
    end

    test "all-literal fast path still compiles to a single lit instruction" do
      assert Predicator.compile("[1, 2, 3]") == {:ok, [["lit", [1, 2, 3]]]}
    end

    test "non-literal list compiles to element instructions followed by make_list" do
      assert Predicator.compile("[x + 1, y]") ==
               {:ok,
                [
                  ["load", "x"],
                  ["lit", 1],
                  ["add"],
                  ["load", "y"],
                  ["make_list", 2]
                ]}
    end

    test "round-trips a non-literal list back to parseable source" do
      {:ok, tokens} = Lexer.tokenize("[x + 1, y]")
      {:ok, ast} = Parser.parse(tokens)

      source = Predicator.decompile(ast)

      assert {:ok, _tokens} = Lexer.tokenize(source)
    end
  end

  describe "relative dates against Date context values" do
    test "a Date compares against 'from now'" do
      assert Predicator.evaluate("due_at < 2w from now", %{
               "due_at" => Date.add(Date.utc_today(), 10)
             }) == {:ok, true}

      assert Predicator.evaluate("due_at < 2w from now", %{
               "due_at" => Date.add(Date.utc_today(), 30)
             }) == {:ok, false}
    end

    test "a Date compares against 'ago'" do
      assert Predicator.evaluate("created_at > 3d ago", %{
               "created_at" => Date.add(Date.utc_today(), -1)
             }) == {:ok, true}

      assert Predicator.evaluate("created_at > 3d ago", %{
               "created_at" => Date.add(Date.utc_today(), -10)
             }) == {:ok, false}
    end

    test "a Date compares against 'next' and 'last'" do
      assert Predicator.evaluate("due_at < next 1mo", %{
               "due_at" => Date.add(Date.utc_today(), 5)
             }) == {:ok, true}

      assert Predicator.evaluate("due_at < next 1mo", %{
               "due_at" => Date.add(Date.utc_today(), 90)
             }) == {:ok, false}

      assert Predicator.evaluate("start_on > last 1y", %{
               "start_on" => Date.add(Date.utc_today(), -30)
             }) == {:ok, true}

      assert Predicator.evaluate("start_on > last 1y", %{
               "start_on" => Date.add(Date.utc_today(), -400)
             }) == {:ok, false}
    end
  end

  describe "cast integration" do
    test "a successful cast compares as its converted value" do
      assert Predicator.evaluate(~s("42"::integer > 5)) == {:ok, true}
    end

    test "a failed cast is :undefined and falsy at a jump" do
      assert Predicator.evaluate(~s("abc"::integer > 5)) == {:ok, :undefined}
    end

    test "a failed cast inside an AND chain short-circuits without erroring" do
      assert Predicator.evaluate(~s("abc"::integer > 5 and true)) == {:ok, :undefined}
    end

    test "the propagation rule reaches through a genuine access-miss undefined" do
      assert Predicator.evaluate(~s(user.missing::integer), %{"user" => %{}}) ==
               {:ok, :undefined}
    end

    test "postfix cast binds tighter than unary minus" do
      assert Predicator.evaluate(~s(-"1"::integer)) == {:ok, -1}
    end

    test "compiles and runs via Predicator.execute/2" do
      assert {:ok, context} = Predicator.execute(~s(x = "42"::integer), %{})
      assert context.data == %{"x" => 42}
    end
  end

  describe "the undefined literal (px-ocp)" do
    test "compiles to lit :undefined, never a load" do
      assert Predicator.compile("x === undefined") ==
               {:ok, [["load", "x"], ["lit", :undefined], ["compare", "STRICT_EQ"]]}
    end

    test "x == undefined propagates instead of answering" do
      assert Predicator.evaluate("x == undefined", %{"x" => 1}) == {:ok, :undefined}
    end

    test "x = undefined binds x to :undefined through Predicator.execute/2" do
      assert {:ok, context} = Predicator.execute("x = undefined", %{})
      assert context.data == %{"x" => :undefined}
    end
  end

  describe "the null literal (px-24y)" do
    test "compiles to lit nil, never a load" do
      assert Predicator.compile("x === null") ==
               {:ok, [["load", "x"], ["lit", nil], ["compare", "STRICT_EQ"]]}
    end

    test "x === null answers true for a variable genuinely bound to null" do
      assert Predicator.evaluate("x === null", %{"x" => nil}) == {:ok, true}
    end

    test "null === null (px-o9v D2, observed through the literal)" do
      assert Predicator.evaluate("null === null") == {:ok, true}
    end

    test "null == null propagates instead of answering (px-o9v D2)" do
      assert Predicator.evaluate("null == null") == {:ok, :undefined}
    end

    test "null === undefined is false - null and undefined are distinct" do
      assert Predicator.evaluate("null === undefined") == {:ok, false}
    end

    test "null in [null] tests identity" do
      assert Predicator.evaluate("null in [null]") == {:ok, true}
    end

    test "null::string collapses to :undefined under any cast" do
      assert Predicator.evaluate("null::string") == {:ok, :undefined}
    end

    test "not null is a TypeMismatchError" do
      assert {:error, %Predicator.Errors.TypeMismatchError{}} = Predicator.evaluate("not null")
    end
  end

  describe "fractional duration literals (px-5c5)" do
    test "a fractional duration literal compiles to expanded integer pairs" do
      assert Predicator.compile("1.5s") ==
               {:ok, [["duration", [[1, "s"], [500, "ms"]]]]}
    end

    test "an integer-only duration literal compiles byte-identical to before" do
      assert Predicator.compile("3d8h") ==
               {:ok, [["duration", [[3, "d"], [8, "h"]]]]}
    end

    test "'ago' with a fractional duration still works end to end" do
      assert Predicator.evaluate("1.5s ago < Date.now()", %{}) == {:ok, true}
    end

    test "'from now' with a fractional duration still works end to end" do
      assert Predicator.evaluate("Date.now() < 1.5s from now", %{}) == {:ok, true}
    end

    test "a fractional duration compares correctly in date arithmetic" do
      assert Predicator.evaluate("#2024-01-15T10:30:00Z# + 1.5s > #2024-01-15T10:30:00Z#", %{}) ==
               {:ok, true}
    end

    test "an inexact fraction is a compile error, not a silent :undefined" do
      assert {:error, %Predicator.Errors.ParseError{message: message}} =
               Predicator.compile("0.5ms")

      assert message =~ "not a whole number of milliseconds"
    end

    test "a post-expansion unit collision is a compile error" do
      assert {:error, %Predicator.Errors.ParseError{message: message}} =
               Predicator.compile("1.5s200ms")

      assert message =~ "names the 'ms' unit twice"
    end
  end
end
