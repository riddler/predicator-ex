defmodule Predicator.Visitors.StringVisitorTest do
  use ExUnit.Case, async: true

  alias Predicator.Visitors.StringVisitor

  doctest Predicator.Visitors.StringVisitor

  @corpus [
    "42",
    ~s("hello"),
    "'hello'",
    "score",
    "a > 1",
    "a + 1 * 2",
    "-a",
    "a in [1, 2]",
    "a > 1 AND b < 2",
    "a > 1 OR b < 2",
    "NOT a",
    "[a, b, 3]",
    "[]",
    "{a: 1, \"b\": x}",
    "{'c d': 1}",
    "{}",
    "len(upper(name))",
    "a[0][1]",
    "user.name.first",
    "3d8h",
    "3d ago",
    "next 2w",
    "score::integer",
    "\"42\"::integer",
    "x::integer::string",
    "(1 + 2)::string",
    "(-1)::integer",
    "(a AND b)::boolean",
    "a::integer + b::float > 3",
    "f(x)::integer",
    "a.b::string",
    "list[0]::integer"
  ]

  describe "raw parser output" do
    test "every corpus expression round-trips from raw parser output" do
      for source <- @corpus do
        {:ok, ast} = Predicator.parse(source)

        # No normalization step: the visitors take parser output as it comes.
        assert {:ok, reparsed} = Predicator.parse(Predicator.decompile(ast))
        assert Predicator.ASTShape.strip(reparsed) == Predicator.ASTShape.strip(ast)
      end
    end
  end

  describe "visit/2 - literal nodes" do
    test "converts integer literal to string" do
      ast = {:literal, 42, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "42"
    end

    test "converts negative integer literal to string" do
      ast = {:literal, -15, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "-15"
    end

    test "converts zero to string" do
      ast = {:literal, 0, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "0"
    end

    test "converts boolean true literal to string" do
      ast = {:literal, true, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "true"
    end

    test "converts boolean false literal to string" do
      ast = {:literal, false, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "false"
    end

    test "converts string literal with quotes" do
      ast = {:literal, "hello", nil}
      result = StringVisitor.visit(ast, [])

      assert result == ~s("hello")
    end

    test "converts empty string literal" do
      ast = {:literal, "", nil}
      result = StringVisitor.visit(ast, [])

      assert result == ~s("")
    end

    test "converts string with escaped quotes" do
      ast = {:literal, "hello \"world\"", nil}
      result = StringVisitor.visit(ast, [])

      assert result == ~s("hello \\"world\\"")
    end

    test "converts string with special characters" do
      ast = {:literal, "line1\nline2\ttab", nil}
      result = StringVisitor.visit(ast, [])

      assert result == "\"line1\nline2\ttab\""
    end

    test "converts list literal" do
      ast = {:literal, [1, 2, 3], nil}
      result = StringVisitor.visit(ast, [])

      assert result == "[1, 2, 3]"
    end

    test "converts mixed type list literal" do
      ast = {:literal, [1, "hello", true], nil}
      result = StringVisitor.visit(ast, [])

      assert result == ~s([1, "hello", true])
    end

    test "converts empty list literal" do
      ast = {:literal, [], nil}
      result = StringVisitor.visit(ast, [])

      assert result == "[]"
    end
  end

  describe "visit/2 - identifier nodes" do
    test "converts simple identifier" do
      ast = {:identifier, "score", nil}
      result = StringVisitor.visit(ast, [])

      assert result == "score"
    end

    test "converts identifier with underscores" do
      ast = {:identifier, "user_age", nil}
      result = StringVisitor.visit(ast, [])

      assert result == "user_age"
    end

    test "converts identifier with numbers" do
      ast = {:identifier, "var123", nil}
      result = StringVisitor.visit(ast, [])

      assert result == "var123"
    end
  end

  describe "visit/2 - comparison nodes" do
    test "converts greater than comparison" do
      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "score > 85"
    end

    test "converts less than comparison" do
      ast = {:comparison, :lt, {:identifier, "age", nil}, {:literal, 18, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "age < 18"
    end

    test "converts greater than or equal comparison" do
      ast = {:comparison, :gte, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "score >= 85"
    end

    test "converts less than or equal comparison" do
      ast = {:comparison, :lte, {:identifier, "age", nil}, {:literal, 65, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "age <= 65"
    end

    test "converts equality comparison" do
      ast = {:comparison, :eq, {:identifier, "name", nil}, {:literal, "John", nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == ~s(name == "John")
    end

    test "converts not equal comparison" do
      ast = {:comparison, :ne, {:identifier, "status", nil}, {:literal, "inactive", nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == ~s(status != "inactive")
    end

    test "converts literal-to-literal comparison" do
      ast = {:comparison, :gt, {:literal, 10, nil}, {:literal, 5, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "10 > 5"
    end

    test "converts identifier-to-identifier comparison" do
      ast = {:comparison, :eq, {:identifier, "score", nil}, {:identifier, "threshold", nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "score == threshold"
    end

    test "converts boolean comparisons" do
      ast = {:comparison, :eq, {:identifier, "active", nil}, {:literal, true, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "active == true"
    end
  end

  describe "visit/2 - spacing options" do
    test "normal spacing (default)" do
      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      result = StringVisitor.visit(ast, spacing: :normal)

      assert result == "score > 85"
    end

    test "compact spacing" do
      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      result = StringVisitor.visit(ast, spacing: :compact)

      assert result == "score>85"
    end

    test "verbose spacing" do
      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      result = StringVisitor.visit(ast, spacing: :verbose)

      assert result == "score  >  85"
    end

    test "spacing affects all operators" do
      operators_and_expected = [
        {:gt, "score  >  85"},
        {:lt, "score  <  85"},
        {:gte, "score  >=  85"},
        {:lte, "score  <=  85"},
        {:eq, "score  ==  85"},
        {:ne, "score  !=  85"}
      ]

      for {op, expected} <- operators_and_expected do
        ast = {:comparison, op, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
        result = StringVisitor.visit(ast, spacing: :verbose)
        assert result == expected
      end
    end
  end

  describe "visit/2 - parentheses options" do
    test "minimal parentheses (default)" do
      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      result = StringVisitor.visit(ast, parentheses: :minimal)

      assert result == "score > 85"
    end

    test "explicit parentheses" do
      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      result = StringVisitor.visit(ast, parentheses: :explicit)

      assert result == "(score > 85)"
    end

    test "no parentheses" do
      ast = {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil}
      result = StringVisitor.visit(ast, parentheses: :none)

      assert result == "score > 85"
    end
  end

  describe "visit/2 - combined options" do
    test "explicit parentheses with compact spacing" do
      ast = {:comparison, :gte, {:identifier, "age", nil}, {:literal, 18, nil}, nil}
      result = StringVisitor.visit(ast, parentheses: :explicit, spacing: :compact)

      assert result == "(age>=18)"
    end

    test "verbose spacing with explicit parentheses" do
      ast = {:comparison, :ne, {:identifier, "name", nil}, {:literal, "test", nil}, nil}
      result = StringVisitor.visit(ast, parentheses: :explicit, spacing: :verbose)

      assert result == "(name  !=  \"test\")"
    end
  end

  describe "visit/2 - integration with parser output" do
    test "round-trip with simple expression" do
      alias Predicator.Lexer

      original = "score > 85"
      {:ok, tokens} = Lexer.tokenize(original)
      {:ok, ast} = Predicator.Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])

      assert result == original
    end

    test "round-trip with string comparison" do
      alias Predicator.Lexer

      original = ~s(name == "John")
      {:ok, tokens} = Lexer.tokenize(original)
      {:ok, ast} = Predicator.Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])

      assert result == original
    end

    test "round-trip with boolean comparison" do
      alias Predicator.Lexer

      original = "active == true"
      {:ok, tokens} = Lexer.tokenize(original)
      {:ok, ast} = Predicator.Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])

      assert result == original
    end

    test "round-trip with all comparison operators" do
      alias Predicator.Lexer

      expressions = [
        "x > 5",
        "x < 5",
        "x >= 5",
        "x <= 5",
        "x == 5",
        "x != 5"
      ]

      for original <- expressions do
        {:ok, tokens} = Lexer.tokenize(original)
        {:ok, ast} = Predicator.Parser.parse(tokens)
        result = StringVisitor.visit(ast, [])

        assert result == original, "Failed round-trip for: #{original}"
      end
    end

    test "round-trip with property access" do
      alias Predicator.Lexer

      original = "user.name"
      {:ok, tokens} = Lexer.tokenize(original)
      {:ok, ast} = Predicator.Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])

      assert result == original
    end

    test "round-trip with chained property access" do
      alias Predicator.Lexer

      original = ~s(user.profile.email == "test@example.com")
      {:ok, tokens} = Lexer.tokenize(original)
      {:ok, ast} = Predicator.Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])

      assert result == original
    end

    test "round-trip with mixed property and bracket access" do
      alias Predicator.Lexer

      original = ~s(user.settings["theme"].name)
      {:ok, tokens} = Lexer.tokenize(original)
      {:ok, ast} = Predicator.Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])

      assert result == original
    end

    test "handles parenthesized expressions" do
      alias Predicator.Lexer

      # Note: Parser removes unnecessary parentheses from AST
      original = "(score > 85)"
      {:ok, tokens} = Lexer.tokenize(original)
      {:ok, ast} = Predicator.Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])
      # Parentheses are removed by parser since they're not needed
      assert result == "score > 85"

      # But we can add them back with explicit mode
      result_explicit = StringVisitor.visit(ast, parentheses: :explicit)
      assert result_explicit == "(score > 85)"
    end

    test "handles complex expressions with whitespace normalization" do
      alias Predicator.Lexer

      original_with_extra_spaces = "  score   >    85  "
      {:ok, tokens} = Lexer.tokenize(original_with_extra_spaces)
      {:ok, ast} = Predicator.Parser.parse(tokens)

      result = StringVisitor.visit(ast, [])

      # StringVisitor normalizes spacing
      assert result == "score > 85"
    end
  end

  describe "visit/2 - edge cases" do
    test "handles strings with quotes that need escaping" do
      ast =
        {:comparison, :eq, {:identifier, "message", nil}, {:literal, ~s(He said "hello"), nil},
         nil}

      result = StringVisitor.visit(ast, [])

      assert result == ~s(message == "He said \\"hello\\"")
    end

    test "handles empty string comparisons" do
      ast = {:comparison, :ne, {:identifier, "name", nil}, {:literal, "", nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == ~s(name != "")
    end

    test "handles zero comparisons" do
      ast = {:comparison, :gt, {:identifier, "count", nil}, {:literal, 0, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "count > 0"
    end

    test "handles negative number comparisons" do
      ast = {:comparison, :lt, {:identifier, "temp", nil}, {:literal, -10, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "temp < -10"
    end
  end

  describe "visit/2 - logical operators" do
    test "formats simple logical AND" do
      ast = {:logical_and, {:literal, true, nil}, {:literal, false, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "true AND false"
    end

    test "formats simple logical OR" do
      ast = {:logical_or, {:literal, true, nil}, {:literal, false, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "true OR false"
    end

    test "formats simple logical NOT" do
      ast = {:logical_not, {:literal, true, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "NOT true"
    end

    test "formats logical AND with comparisons" do
      ast =
        {:logical_and, {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil},
         {:comparison, :gte, {:identifier, "age", nil}, {:literal, 18, nil}, nil}, nil}

      result = StringVisitor.visit(ast, [])

      assert result == "score > 85 AND age >= 18"
    end

    test "formats logical OR with comparisons" do
      ast =
        {:logical_or,
         {:comparison, :eq, {:identifier, "role", nil}, {:literal, "admin", nil}, nil},
         {:comparison, :eq, {:identifier, "role", nil}, {:literal, "manager", nil}, nil}, nil}

      result = StringVisitor.visit(ast, [])

      assert result == ~s(role == "admin" OR role == "manager")
    end

    test "formats logical NOT with comparison" do
      ast =
        {:logical_not,
         {:comparison, :eq, {:identifier, "expired", nil}, {:literal, true, nil}, nil}, nil}

      result = StringVisitor.visit(ast, [])

      assert result == "NOT expired == true"
    end

    test "formats nested logical NOT" do
      ast = {:logical_not, {:logical_not, {:literal, false, nil}, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "NOT NOT false"
    end

    test "formats complex nested logical expression" do
      # (score > 85 AND age >= 18) OR admin = true
      ast =
        {:logical_or,
         {:logical_and, {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil},
          {:comparison, :gte, {:identifier, "age", nil}, {:literal, 18, nil}, nil}, nil},
         {:comparison, :eq, {:identifier, "admin", nil}, {:literal, true, nil}, nil}, nil}

      result = StringVisitor.visit(ast, [])

      assert result == "score > 85 AND age >= 18 OR admin == true"
    end

    test "formats logical operators with compact spacing" do
      ast = {:logical_and, {:literal, true, nil}, {:literal, false, nil}, nil}
      result = StringVisitor.visit(ast, spacing: :compact)

      assert result == "trueANDfalse"
    end

    test "formats logical operators with verbose spacing" do
      ast = {:logical_or, {:literal, true, nil}, {:literal, false, nil}, nil}
      result = StringVisitor.visit(ast, spacing: :verbose)

      assert result == "true  OR  false"
    end

    test "formats logical operators with explicit parentheses" do
      ast = {:logical_and, {:literal, true, nil}, {:literal, false, nil}, nil}
      result = StringVisitor.visit(ast, parentheses: :explicit)

      assert result == "(true AND false)"
    end

    test "formats logical NOT with explicit parentheses" do
      ast = {:logical_not, {:literal, true, nil}, nil}
      result = StringVisitor.visit(ast, parentheses: :explicit)

      assert result == "(NOT true)"
    end

    test "formats logical NOT with no parentheses mode" do
      ast = {:logical_not, {:literal, false, nil}, nil}
      result = StringVisitor.visit(ast, parentheses: :none)

      assert result == "NOT false"
    end

    test "formats complex logical expression with all formatting options" do
      ast =
        {:logical_not, {:logical_and, {:literal, true, nil}, {:literal, false, nil}, nil}, nil}

      result = StringVisitor.visit(ast, spacing: :verbose, parentheses: :explicit)

      assert result == "(NOT  (true  AND  false))"
    end

    test "formats left-associative AND operations" do
      # ((true AND false) AND true)
      ast =
        {:logical_and, {:logical_and, {:literal, true, nil}, {:literal, false, nil}, nil},
         {:literal, true, nil}, nil}

      result = StringVisitor.visit(ast, [])

      assert result == "true AND false AND true"
    end

    test "formats left-associative OR operations" do
      # ((true OR false) OR true)
      ast =
        {:logical_or, {:logical_or, {:literal, true, nil}, {:literal, false, nil}, nil},
         {:literal, true, nil}, nil}

      result = StringVisitor.visit(ast, [])

      assert result == "true OR false OR true"
    end

    test "formats mixed comparison and logical operations" do
      # score > 85 AND NOT expired
      ast =
        {:logical_and, {:comparison, :gt, {:identifier, "score", nil}, {:literal, 85, nil}, nil},
         {:logical_not, {:identifier, "expired", nil}, nil}, nil}

      result = StringVisitor.visit(ast, [])

      assert result == "score > 85 AND NOT expired"
    end
  end

  describe "visit/2 - integration with parser" do
    test "round-trip with logical AND expression" do
      alias Predicator.Lexer

      expression = "score > 85 AND age >= 18"
      {:ok, tokens} = Lexer.tokenize(expression)
      {:ok, ast} = Predicator.Parser.parse(tokens)
      result = StringVisitor.visit(ast, [])

      assert result == expression
    end

    test "round-trip with logical OR expression" do
      alias Predicator.Lexer

      expression = ~s(role == "admin" OR role == "manager")
      {:ok, tokens} = Lexer.tokenize(expression)
      {:ok, ast} = Predicator.Parser.parse(tokens)
      result = StringVisitor.visit(ast, [])

      assert result == expression
    end

    test "round-trip with logical NOT expression" do
      alias Predicator.Lexer

      expression = "NOT expired == true"
      {:ok, tokens} = Lexer.tokenize(expression)
      {:ok, ast} = Predicator.Parser.parse(tokens)
      result = StringVisitor.visit(ast, [])

      assert result == expression
    end

    test "round-trip with complex logical expression" do
      alias Predicator.Lexer

      expression = "score > 85 AND age >= 18 OR admin == true"
      {:ok, tokens} = Lexer.tokenize(expression)
      {:ok, ast} = Predicator.Parser.parse(tokens)
      result = StringVisitor.visit(ast, [])

      assert result == expression
    end
  end

  describe "visit/2 - arithmetic operators" do
    test "converts addition expression" do
      ast = {:arithmetic, :add, {:identifier, "a", nil}, {:identifier, "b", nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "a + b"
    end

    test "converts subtraction expression" do
      ast = {:arithmetic, :subtract, {:literal, 10, nil}, {:literal, 3, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "10 - 3"
    end

    test "converts multiplication expression" do
      ast = {:arithmetic, :multiply, {:identifier, "x", nil}, {:literal, 2, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "x * 2"
    end

    test "converts division expression" do
      ast = {:arithmetic, :divide, {:literal, 100, nil}, {:identifier, "divisor", nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "100 / divisor"
    end

    test "converts modulo expression" do
      ast = {:arithmetic, :modulo, {:identifier, "n", nil}, {:literal, 5, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "n % 5"
    end

    test "converts nested arithmetic expressions" do
      # (a + b) * c
      inner_add = {:arithmetic, :add, {:identifier, "a", nil}, {:identifier, "b", nil}, nil}
      ast = {:arithmetic, :multiply, inner_add, {:identifier, "c", nil}, nil}
      result = StringVisitor.visit(ast, [])

      # The `+` binds looser than `*`, so the left child needs parens or the
      # string would re-parse as a + (b * c) - a different AST (px-ek5).
      assert result == "(a + b) * c"
    end

    test "converts arithmetic with explicit parentheses mode" do
      ast = {:arithmetic, :add, {:identifier, "x", nil}, {:literal, 5, nil}, nil}
      result = StringVisitor.visit(ast, parentheses: :explicit)

      assert result == "(x + 5)"
    end

    test "converts arithmetic with compact spacing" do
      ast = {:arithmetic, :multiply, {:literal, 3, nil}, {:literal, 4, nil}, nil}
      result = StringVisitor.visit(ast, spacing: :compact)

      assert result == "3*4"
    end

    test "converts arithmetic with verbose spacing" do
      ast = {:arithmetic, :subtract, {:identifier, "total", nil}, {:literal, 10, nil}, nil}
      result = StringVisitor.visit(ast, spacing: :verbose)

      assert result == "total  -  10"
    end
  end

  describe "visit/2 - unary operators" do
    test "converts unary minus expression" do
      ast = {:unary, :minus, {:identifier, "x", nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "-x"
    end

    test "converts unary minus with literal" do
      ast = {:unary, :minus, {:literal, 42, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "-42"
    end

    test "converts unary bang (logical NOT) expression" do
      ast = {:unary, :bang, {:identifier, "active", nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "!active"
    end

    test "converts unary bang with boolean literal" do
      ast = {:unary, :bang, {:literal, true, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "!true"
    end

    test "converts nested unary expressions" do
      # !(-x)
      inner_minus = {:unary, :minus, {:identifier, "x", nil}, nil}
      ast = {:unary, :bang, inner_minus, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "!-x"
    end

    test "converts unary with function call" do
      # !(len(name))
      function_call = {:function_call, "len", [{:identifier, "name", nil}], nil}
      ast = {:unary, :bang, function_call, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "!len(name)"
    end
  end

  describe "visit/2 - equality operators" do
    test "converts equality (==) expression" do
      ast = {:comparison, :eq, {:identifier, "x", nil}, {:identifier, "y", nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "x == y"
    end

    test "converts inequality (!=) with equality syntax" do
      ast = {:comparison, :ne, {:identifier, "status", nil}, {:literal, "active", nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == ~s(status != "active")
    end

    test "converts equality with explicit parentheses" do
      ast = {:comparison, :eq, {:literal, 1, nil}, {:literal, 1, nil}, nil}
      result = StringVisitor.visit(ast, parentheses: :explicit)

      assert result == "(1 == 1)"
    end

    test "converts equality with compact spacing" do
      ast = {:comparison, :eq, {:identifier, "a", nil}, {:identifier, "b", nil}, nil}
      result = StringVisitor.visit(ast, spacing: :compact)

      assert result == "a==b"
    end
  end

  describe "visit/2 - mixed operator expressions" do
    test "converts arithmetic within comparison" do
      # x + y > 10
      arithmetic = {:arithmetic, :add, {:identifier, "x", nil}, {:identifier, "y", nil}, nil}
      ast = {:comparison, :gt, arithmetic, {:literal, 10, nil}, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "x + y > 10"
    end

    test "converts unary in logical expression" do
      # !active AND !expired
      left_unary = {:unary, :bang, {:identifier, "active", nil}, nil}
      right_unary = {:unary, :bang, {:identifier, "expired", nil}, nil}
      ast = {:logical_and, left_unary, right_unary, nil}
      result = StringVisitor.visit(ast, [])

      assert result == "!active AND !expired"
    end

    test "converts complex nested expression" do
      # !(x + y == 10)
      arithmetic = {:arithmetic, :add, {:identifier, "x", nil}, {:identifier, "y", nil}, nil}
      equality = {:comparison, :eq, arithmetic, {:literal, 10, nil}, nil}
      ast = {:unary, :bang, equality, nil}
      result = StringVisitor.visit(ast, [])

      # Comparison binds looser than unary `!`, so the operand needs parens
      # or the string would re-parse as (!x) + y == 10 (px-ek5).
      assert result == "!(x + y == 10)"
    end
  end

  describe "visit/2 - object keys" do
    test "renders each key style as it was written" do
      for source <- ["{a: 1}", ~s({"a b": 1}), "{'a b': 1}"] do
        {:ok, ast} = Predicator.parse(source)
        assert StringVisitor.visit(ast, []) == source
      end
    end

    test "escapes a quote character inside a key" do
      {:ok, ast} = Predicator.parse(~s({"say \\"hi\\"": 1}))
      decompiled = StringVisitor.visit(ast, [])

      assert decompiled == ~s({"say \\"hi\\"": 1})
      assert Predicator.parse(decompiled) == {:ok, ast}
    end

    test "renders a hand-built key from its style" do
      identifier_key =
        {:object, [{{:object_key, "a", :identifier, nil}, {:literal, 1, nil}}], nil}

      assert StringVisitor.visit(identifier_key, []) == "{a: 1}"

      double_key = {:object, [{{:object_key, "a b", :double, nil}, {:literal, 1, nil}}], nil}
      assert StringVisitor.visit(double_key, []) == ~s({"a b": 1})
    end
  end

  describe "visit/2 - program and assignment round-trip" do
    test "single-statement program round-trips" do
      assert_program_round_trip("a = 1")
    end

    test "multi-statement program round-trips" do
      assert_program_round_trip("a = 1; b = a + 1")
    end

    test "trailing semicolon normalizes away on re-parse" do
      {:ok, ast} = Predicator.parse_program("a = 1;")
      decompiled = Predicator.decompile(ast)

      assert decompiled == "a = 1"
      assert Predicator.parse_program(decompiled) == {:ok, ast}
    end

    test "assignment to a property/bracket chain round-trips" do
      assert_program_round_trip("user.items[0].name = 'Ada'")
    end

    test "mixed assignment and expression statements round-trip" do
      assert_program_round_trip("a = 1; b = a + 1; a > 0")
    end

    test "renders a program as its statements joined by \"; \"" do
      {:ok, ast} = Predicator.parse_program("a = 1; b = 2; a > b")
      assert StringVisitor.visit(ast, []) == "a = 1; b = 2; a > b"
    end

    test "renders an assignment as \"lhs = rhs\"" do
      ast = {:assignment, {:identifier, "a", nil}, {:literal, 1, nil}, nil}
      assert StringVisitor.visit(ast, []) == "a = 1"
    end

    test "statement separator and assignment spacing ignore the :spacing option" do
      {:ok, ast} = Predicator.parse_program("a = 1; b = 2")
      assert StringVisitor.visit(ast, spacing: :compact) == "a = 1; b = 2"
      assert StringVisitor.visit(ast, spacing: :verbose) == "a = 1; b = 2"
    end

    defp assert_program_round_trip(source) do
      {:ok, ast} = Predicator.parse_program(source)
      decompiled = Predicator.decompile(ast)

      assert Predicator.parse_program(decompiled) == {:ok, ast}
    end
  end

  describe "visit/2 - :eq renders as valid 4.0 source" do
    test "a hand-built :eq comparison renders \"==\"" do
      ast = {:comparison, :eq, {:identifier, "a", nil}, {:literal, 1, nil}, nil}

      assert StringVisitor.visit(ast, []) == "a == 1"
    end

    test "the rendered string re-parses to :equal_equal, not :eq" do
      ast = {:comparison, :eq, {:identifier, "a", nil}, {:literal, 1, nil}, nil}
      decompiled = StringVisitor.visit(ast, [])

      assert {:ok, {:comparison, :equal_equal, _left, _right, _pos}} =
               Predicator.parse(decompiled)
    end
  end

  describe "visit/2 - cast nodes" do
    test "renders a simple cast as \"expr::type\"" do
      ast = {:cast, {:identifier, "score", nil}, "integer", nil}

      assert StringVisitor.visit(ast, []) == "score::integer"
    end

    test "renders a cast of a string literal" do
      ast = {:cast, {:string_literal, "42", :double, nil}, "integer", nil}

      assert StringVisitor.visit(ast, []) == "\"42\"::integer"
    end

    test "chains casts without parenthesizing the inner cast" do
      inner = {:cast, {:identifier, "x", nil}, "integer", nil}
      ast = {:cast, inner, "string", nil}

      assert StringVisitor.visit(ast, []) == "x::integer::string"
    end

    test "parenthesizes an arithmetic operand" do
      inner = {:arithmetic, :add, {:literal, 1, nil}, {:literal, 2, nil}, nil}
      ast = {:cast, inner, "string", nil}

      assert StringVisitor.visit(ast, []) == "(1 + 2)::string"
    end

    test "parenthesizes a unary minus operand" do
      inner = {:unary, :minus, {:literal, 1, nil}, nil}
      ast = {:cast, inner, "integer", nil}

      assert StringVisitor.visit(ast, []) == "(-1)::integer"
    end

    test "parenthesizes a logical operand" do
      inner = {:logical_and, {:identifier, "a", nil}, {:identifier, "b", nil}, nil}
      ast = {:cast, inner, "boolean", nil}

      assert StringVisitor.visit(ast, []) == "(a AND b)::boolean"
    end

    test "parenthesizes a comparison operand" do
      inner = {:comparison, :gt, {:identifier, "a", nil}, {:literal, 1, nil}, nil}
      ast = {:cast, inner, "boolean", nil}

      assert StringVisitor.visit(ast, []) == "(a > 1)::boolean"
    end

    test "does not parenthesize a property access operand" do
      inner = {:property_access, {:identifier, "a", nil}, "b", nil}
      ast = {:cast, inner, "string", nil}

      assert StringVisitor.visit(ast, []) == "a.b::string"
    end

    test "does not parenthesize a bracket access operand" do
      inner = {:bracket_access, {:identifier, "list", nil}, {:literal, 0, nil}, nil}
      ast = {:cast, inner, "integer", nil}

      assert StringVisitor.visit(ast, []) == "list[0]::integer"
    end

    test "does not parenthesize a function call operand" do
      inner = {:function_call, "f", [{:identifier, "x", nil}], nil}
      ast = {:cast, inner, "integer", nil}

      assert StringVisitor.visit(ast, []) == "f(x)::integer"
    end

    test "a cast does not need parentheses as an arithmetic operand" do
      ast =
        {:arithmetic, :add, {:cast, {:identifier, "x", nil}, "integer", nil}, {:literal, 1, nil},
         nil}

      assert StringVisitor.visit(ast, []) == "x::integer + 1"
    end

    test "does not add parentheses in :none mode even when precedence would otherwise require them" do
      inner = {:arithmetic, :add, {:literal, 1, nil}, {:literal, 2, nil}, nil}
      ast = {:cast, inner, "string", nil}

      assert StringVisitor.visit(ast, parentheses: :none) == "1 + 2::string"
    end

    test "explicit mode adds no parens around a primary operand (matches :minimal)" do
      ast = {:cast, {:identifier, "score", nil}, "integer", nil}

      assert StringVisitor.visit(ast, parentheses: :explicit) == "score::integer"
    end

    test "explicit mode relies on the operand's own self-wrapping, not cast-level wrapping" do
      # The arithmetic child already self-wraps under :explicit, so the cast
      # clause does not need to (and does not) add a second layer of parens.
      inner = {:arithmetic, :add, {:literal, 1, nil}, {:literal, 2, nil}, nil}
      ast = {:cast, inner, "string", nil}

      assert StringVisitor.visit(ast, parentheses: :explicit) == "(1 + 2)::string"
    end

    test "the round-trip: nested casts inside a larger expression" do
      {:ok, ast} = Predicator.parse("a::integer + b::float > 3")
      decompiled = StringVisitor.visit(ast, [])

      assert {:ok, reparsed} = Predicator.parse(decompiled)
      assert Predicator.ASTShape.strip(reparsed) == Predicator.ASTShape.strip(ast)
    end
  end

  # px-ek5: :minimal defaulted to emitting no parentheses at all, so a string
  # like "1 + 2 * 3" from {:arithmetic, :multiply, {:arithmetic, :add, 1, 2}, 3}
  # re-parsed to a different AST (1 + (2 * 3)) than the one it came from. These
  # tests cover the precedence-aware fix: a child needs parens exactly when
  # rendering it bare would change how the string re-parses.
  describe "visit/2 - :minimal adds parens exactly when precedence requires it" do
    test "parenthesizes a looser left child of a tighter parent" do
      # (1 + 2) * 3
      inner = {:arithmetic, :add, {:literal, 1, nil}, {:literal, 2, nil}, nil}
      ast = {:arithmetic, :multiply, inner, {:literal, 3, nil}, nil}

      assert StringVisitor.visit(ast, []) == "(1 + 2) * 3"
    end

    test "parenthesizes a looser right child of a tighter parent" do
      # 3 * (1 + 2)
      inner = {:arithmetic, :add, {:literal, 1, nil}, {:literal, 2, nil}, nil}
      ast = {:arithmetic, :multiply, {:literal, 3, nil}, inner, nil}

      assert StringVisitor.visit(ast, []) == "3 * (1 + 2)"
    end

    test "does not parenthesize when precedence already holds the shape" do
      # 1 + 2 * 3, unambiguous as-is
      inner = {:arithmetic, :multiply, {:literal, 2, nil}, {:literal, 3, nil}, nil}
      ast = {:arithmetic, :add, {:literal, 1, nil}, inner, nil}

      assert StringVisitor.visit(ast, []) == "1 + 2 * 3"
    end

    test "parenthesizes a same-precedence right child to preserve left-associativity" do
      # 1 - (2 - 3): without parens this would re-parse as (1 - 2) - 3
      inner = {:arithmetic, :subtract, {:literal, 2, nil}, {:literal, 3, nil}, nil}
      ast = {:arithmetic, :subtract, {:literal, 1, nil}, inner, nil}

      assert StringVisitor.visit(ast, []) == "1 - (2 - 3)"
    end

    test "does not parenthesize a same-precedence left child (matches left-associativity)" do
      # (1 - 2) - 3 renders as "1 - 2 - 3", which re-parses to the same AST
      inner = {:arithmetic, :subtract, {:literal, 1, nil}, {:literal, 2, nil}, nil}
      ast = {:arithmetic, :subtract, inner, {:literal, 3, nil}, nil}

      assert StringVisitor.visit(ast, []) == "1 - 2 - 3"
    end

    test "parenthesizes a looser logical_or child under logical_and" do
      # (a OR b) AND c
      inner_or =
        {:logical_or, {:identifier, "a", nil}, {:identifier, "b", nil}, nil}

      ast = {:logical_and, inner_or, {:identifier, "c", nil}, nil}

      assert StringVisitor.visit(ast, []) == "(a OR b) AND c"
    end

    test "does not parenthesize logical_and under logical_or (already correct shape)" do
      # a AND b OR c, unambiguous as-is
      inner_and =
        {:logical_and, {:identifier, "a", nil}, {:identifier, "b", nil}, nil}

      ast = {:logical_or, inner_and, {:identifier, "c", nil}, nil}

      assert StringVisitor.visit(ast, []) == "a AND b OR c"
    end

    test "parenthesizes a looser operand under NOT" do
      # NOT (a AND b)
      inner_and =
        {:logical_and, {:identifier, "a", nil}, {:identifier, "b", nil}, nil}

      ast = {:logical_not, inner_and, nil}

      assert StringVisitor.visit(ast, []) == "NOT (a AND b)"
    end

    test "parenthesizes a looser operand under unary minus" do
      # -(1 + 2)
      inner = {:arithmetic, :add, {:literal, 1, nil}, {:literal, 2, nil}, nil}
      ast = {:unary, :minus, inner, nil}

      assert StringVisitor.visit(ast, []) == "-(1 + 2)"
    end

    test "parenthesizes a looser operand under unary bang" do
      # !(a AND b)
      inner_and =
        {:logical_and, {:identifier, "a", nil}, {:identifier, "b", nil}, nil}

      ast = {:unary, :bang, inner_and, nil}

      assert StringVisitor.visit(ast, []) == "!(a AND b)"
    end

    test "does not add parens in :none mode even when precedence would otherwise require them" do
      inner = {:arithmetic, :add, {:literal, 1, nil}, {:literal, 2, nil}, nil}
      ast = {:arithmetic, :multiply, inner, {:literal, 3, nil}, nil}

      assert StringVisitor.visit(ast, parentheses: :none) == "1 + 2 * 3"
    end

    test "spacing mode does not suppress the parentheses" do
      inner = {:arithmetic, :add, {:literal, 1, nil}, {:literal, 2, nil}, nil}
      ast = {:arithmetic, :multiply, inner, {:literal, 3, nil}, nil}

      assert StringVisitor.visit(ast, spacing: :compact) == "(1+2)*3"
      assert StringVisitor.visit(ast, spacing: :verbose) == "(1  +  2)  *  3"
    end

    test "the expression-layer round-trip: (1 + 2) * 3" do
      {:ok, ast} = Predicator.parse("(1 + 2) * 3")
      decompiled = Predicator.decompile(ast)

      assert Predicator.parse(decompiled) == {:ok, ast}
    end

    test "the statement-layer round-trip: x = (1 + 2) * 3" do
      {:ok, ast} = Predicator.parse_program("x = (1 + 2) * 3")
      decompiled = Predicator.decompile(ast)

      assert Predicator.parse_program(decompiled) == {:ok, ast}
    end

    @precedence_corpus [
      "1 + 2 * 3",
      "(1 + 2) * 3",
      "3 * (1 + 2)",
      "1 - 2 - 3",
      "1 - (2 - 3)",
      "10 / 2 / 5",
      "a AND b OR c",
      "(a OR b) AND c",
      "NOT (a AND b)",
      "NOT a AND b",
      "-(1 + 2)",
      "!(a AND b)",
      "a > 1 AND b < 2 OR c == 3",
      "(a > 1 AND b < 2) OR c == 3",
      "a > 1 AND (b < 2 OR c == 3)",
      "1 + 2 * 3 - 4 / 2",
      "x = (1 + 2) * 3",
      "x = 1 + 2 * 3",
      "score::integer",
      "x::integer::string",
      "(1 + 2)::string",
      "(-1)::integer",
      "(a AND b)::boolean",
      "a::integer + b::float > 3",
      "f(x)::integer",
      "a.b::string",
      "list[0]::integer"
    ]

    test "a corpus of precedence-sensitive expressions round-trips under default :minimal" do
      for source <- @precedence_corpus do
        {:ok, ast} = Predicator.parse_program(source)
        decompiled = Predicator.decompile(ast)

        assert {:ok, reparsed} = Predicator.parse_program(decompiled)

        assert Predicator.ASTShape.strip(reparsed) == Predicator.ASTShape.strip(ast),
               "Failed round-trip for: #{source} -> #{decompiled}"
      end
    end
  end

  describe "visit/2 - unsupported nodes (if/block)" do
    test "declines a bare if node instead of raising" do
      ast = {:if, {:identifier, "a", nil}, {:block, [], nil}, nil, {1, 1}}

      assert {:error, %Predicator.Errors.EvaluationError{reason: "unsupported_node"} = error} =
               StringVisitor.visit(ast, [])

      assert error.position == {1, 1}
    end

    test "declines a bare block node - the hand-built-AST case" do
      assert {:error, %Predicator.Errors.EvaluationError{reason: "unsupported_node"}} =
               StringVisitor.visit({:block, [], nil}, [])
    end

    test "decompile/2 declines a program containing a bare if" do
      {:ok, ast} = Predicator.parse_program("if a { x = 1 }")

      assert {:error, %Predicator.Errors.EvaluationError{reason: "unsupported_node"} = error} =
               Predicator.decompile(ast)

      [{:if, _condition, _then_block, _else_block, if_annotation}] = elem(ast, 1)
      assert error.position == if_annotation
    end

    test "decompile/2 declines a program containing an if/else" do
      {:ok, ast} = Predicator.parse_program("if a { x = 1 } else { x = 2 }")

      assert {:error, %Predicator.Errors.EvaluationError{reason: "unsupported_node"}} =
               Predicator.decompile(ast)
    end

    test "decompile/2 declines an else-if chain - the nested case" do
      {:ok, ast} = Predicator.parse_program("if a { x = 1 } else if b { x = 2 }")

      assert {:error, %Predicator.Errors.EvaluationError{reason: "unsupported_node"}} =
               Predicator.decompile(ast)
    end

    test "negative control: decompile/2 on an ordinary expression still returns a binary" do
      {:ok, ast} = Predicator.parse("a > 1")

      assert Predicator.decompile(ast) == "a > 1"
    end

    test "negative control: decompile/2 on a program of assignments still returns a binary" do
      {:ok, ast} = Predicator.parse_program("a = 1; b = 2")

      assert Predicator.decompile(ast) == "a = 1; b = 2"
    end
  end
end
