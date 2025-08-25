defmodule Predicator.ContextLocationTest do
  use ExUnit.Case, async: true

  alias Predicator
  alias Predicator.{ContextLocation, Lexer, Parser}
  alias Predicator.Errors.LocationError

  describe "resolve/2 with simple identifiers" do
    test "resolves simple identifier" do
      {:ok, tokens} = Lexer.tokenize("user")
      {:ok, ast} = Parser.parse(tokens)

      assert {:ok, ["user"]} = ContextLocation.resolve(ast, %{})
    end

    test "resolves identifier with context" do
      {:ok, tokens} = Lexer.tokenize("score")
      {:ok, ast} = Parser.parse(tokens)

      assert {:ok, ["score"]} = ContextLocation.resolve(ast, %{"score" => 100})
    end
  end

  describe "resolve/2 with property access" do
    test "resolves single property access" do
      {:ok, tokens} = Lexer.tokenize("user.name")
      {:ok, ast} = Parser.parse(tokens)

      assert {:ok, ["user", "name"]} = ContextLocation.resolve(ast, %{})
    end

    test "resolves nested property access" do
      {:ok, tokens} = Lexer.tokenize("user.profile.settings")
      {:ok, ast} = Parser.parse(tokens)

      assert {:ok, ["user", "profile", "settings"]} = ContextLocation.resolve(ast, %{})
    end

    test "resolves deep nested property access" do
      {:ok, tokens} = Lexer.tokenize("app.config.database.connection.host")
      {:ok, ast} = Parser.parse(tokens)

      expected = ["app", "config", "database", "connection", "host"]
      assert {:ok, ^expected} = ContextLocation.resolve(ast, %{})
    end
  end

  describe "resolve/2 with bracket access" do
    test "resolves bracket access with integer literal" do
      {:ok, tokens} = Lexer.tokenize("items[0]")
      {:ok, ast} = Parser.parse(tokens)

      assert {:ok, ["items", 0]} = ContextLocation.resolve(ast, %{})
    end

    test "resolves bracket access with negative integer" do
      {:ok, tokens} = Lexer.tokenize("items[-1]")
      {:ok, ast} = Parser.parse(tokens)

      assert {:ok, ["items", -1]} = ContextLocation.resolve(ast, %{})
    end

    test "resolves bracket access with string literal" do
      {:ok, tokens} = Lexer.tokenize("obj['key']")
      {:ok, ast} = Parser.parse(tokens)

      assert {:ok, ["obj", "key"]} = ContextLocation.resolve(ast, %{})
    end

    test "resolves bracket access with double quote string" do
      {:ok, tokens} = Lexer.tokenize(~s(obj["property"]))
      {:ok, ast} = Parser.parse(tokens)

      assert {:ok, ["obj", "property"]} = ContextLocation.resolve(ast, %{})
    end

    test "resolves bracket access with variable key" do
      {:ok, tokens} = Lexer.tokenize("items[index]")
      {:ok, ast} = Parser.parse(tokens)

      context = %{"items" => [1, 2, 3], "index" => 1}
      assert {:ok, ["items", 1]} = ContextLocation.resolve(ast, context)
    end

    test "resolves bracket access with string variable key" do
      {:ok, tokens} = Lexer.tokenize("config[key]")
      {:ok, ast} = Parser.parse(tokens)

      context = %{"config" => %{"theme" => "dark"}, "key" => "theme"}
      assert {:ok, ["config", "theme"]} = ContextLocation.resolve(ast, context)
    end
  end

  describe "resolve/2 with mixed notation" do
    test "resolves property then bracket access" do
      {:ok, tokens} = Lexer.tokenize("user.settings['theme']")
      {:ok, ast} = Parser.parse(tokens)

      assert {:ok, ["user", "settings", "theme"]} = ContextLocation.resolve(ast, %{})
    end

    test "resolves bracket then property access" do
      {:ok, tokens} = Lexer.tokenize("users[0].name")
      {:ok, ast} = Parser.parse(tokens)

      assert {:ok, ["users", 0, "name"]} = ContextLocation.resolve(ast, %{})
    end

    test "resolves complex mixed access" do
      {:ok, tokens} = Lexer.tokenize("data['users'][0].profile['settings'].theme")
      {:ok, ast} = Parser.parse(tokens)

      expected = ["data", "users", 0, "profile", "settings", "theme"]
      assert {:ok, ^expected} = ContextLocation.resolve(ast, %{})
    end

    test "resolves chained bracket access" do
      {:ok, tokens} = Lexer.tokenize("matrix[0][1]")
      {:ok, ast} = Parser.parse(tokens)

      assert {:ok, ["matrix", 0, 1]} = ContextLocation.resolve(ast, %{})
    end

    test "resolves mixed with variable keys" do
      {:ok, tokens} = Lexer.tokenize("data.items[index]['name']")
      {:ok, ast} = Parser.parse(tokens)

      context = %{"data" => %{"items" => []}, "index" => 2}
      assert {:ok, ["data", "items", 2, "name"]} = ContextLocation.resolve(ast, context)
    end
  end

  describe "resolve/2 error cases - not assignable" do
    test "rejects literal values" do
      {:ok, tokens} = Lexer.tokenize("42")
      {:ok, ast} = Parser.parse(tokens)

      assert {:error, %LocationError{type: :not_assignable}} =
               ContextLocation.resolve(ast, %{})
    end

    test "rejects string literals" do
      {:ok, tokens} = Lexer.tokenize("'hello'")
      {:ok, ast} = Parser.parse(tokens)

      assert {:error, %LocationError{type: :not_assignable}} =
               ContextLocation.resolve(ast, %{})
    end

    test "rejects boolean literals" do
      {:ok, tokens} = Lexer.tokenize("true")
      {:ok, ast} = Parser.parse(tokens)

      assert {:error, %LocationError{type: :not_assignable}} =
               ContextLocation.resolve(ast, %{})
    end

    test "rejects function calls" do
      {:ok, tokens} = Lexer.tokenize("len(items)")
      {:ok, ast} = Parser.parse(tokens)

      assert {:error, %LocationError{type: :not_assignable}} =
               ContextLocation.resolve(ast, %{})
    end

    test "rejects arithmetic expressions" do
      {:ok, tokens} = Lexer.tokenize("user.age + 1")
      {:ok, ast} = Parser.parse(tokens)

      assert {:error, %LocationError{type: :not_assignable}} =
               ContextLocation.resolve(ast, %{})
    end

    test "rejects comparison expressions" do
      {:ok, tokens} = Lexer.tokenize("score > 80")
      {:ok, ast} = Parser.parse(tokens)

      assert {:error, %LocationError{type: :not_assignable}} =
               ContextLocation.resolve(ast, %{})
    end

    test "rejects logical expressions" do
      {:ok, tokens} = Lexer.tokenize("active AND enabled")
      {:ok, ast} = Parser.parse(tokens)

      assert {:error, %LocationError{type: :not_assignable}} =
               ContextLocation.resolve(ast, %{})
    end

    test "rejects unary expressions" do
      {:ok, tokens} = Lexer.tokenize("-score")
      {:ok, ast} = Parser.parse(tokens)

      assert {:error, %LocationError{type: :not_assignable}} =
               ContextLocation.resolve(ast, %{})
    end

    test "rejects list literals" do
      {:ok, tokens} = Lexer.tokenize("[1, 2, 3]")
      {:ok, ast} = Parser.parse(tokens)

      assert {:error, %LocationError{type: :not_assignable}} =
               ContextLocation.resolve(ast, %{})
    end
  end

  describe "resolve/2 error cases - bracket key issues" do
    test "rejects undefined variable as bracket key" do
      {:ok, tokens} = Lexer.tokenize("items[missing_var]")
      {:ok, ast} = Parser.parse(tokens)

      assert {:error, %LocationError{type: :undefined_variable}} =
               ContextLocation.resolve(ast, %{})
    end

    test "rejects invalid key types" do
      {:ok, tokens} = Lexer.tokenize("items[key]")
      {:ok, ast} = Parser.parse(tokens)

      # Boolean key value should be rejected
      context = %{"items" => [], "key" => true}

      assert {:error, %LocationError{type: :invalid_key}} =
               ContextLocation.resolve(ast, context)
    end

    test "rejects computed expressions as bracket keys" do
      {:ok, tokens} = Lexer.tokenize("items[index + 1]")
      {:ok, ast} = Parser.parse(tokens)

      assert {:error, %LocationError{type: :computed_key}} =
               ContextLocation.resolve(ast, %{})
    end

    test "rejects function calls as bracket keys" do
      {:ok, tokens} = Lexer.tokenize("items[len(other)]")
      {:ok, ast} = Parser.parse(tokens)

      assert {:error, %LocationError{type: :computed_key}} =
               ContextLocation.resolve(ast, %{})
    end
  end

  describe "context_location/3 public API" do
    test "resolves simple identifier through public API" do
      assert {:ok, ["user"]} = Predicator.context_location("user", %{})
    end

    test "resolves property access through public API" do
      assert {:ok, ["user", "name"]} = Predicator.context_location("user.name", %{})
    end

    test "resolves bracket access through public API" do
      assert {:ok, ["items", 0]} = Predicator.context_location("items[0]", %{})
    end

    test "resolves mixed notation through public API" do
      expected = ["data", "users", 0, "profile"]
      assert {:ok, ^expected} = Predicator.context_location("data.users[0]['profile']", %{})
    end

    test "resolves with variable bracket keys through public API" do
      context = %{"items" => [], "index" => 5}
      assert {:ok, ["items", 5]} = Predicator.context_location("items[index]", context)
    end

    test "returns parsing errors for invalid syntax" do
      assert {:error, %Predicator.Errors.ParseError{}} =
               Predicator.context_location("user.", %{})
    end

    test "returns location errors for non-assignable expressions" do
      assert {:error, %LocationError{type: :not_assignable}} =
               Predicator.context_location("42", %{})
    end

    test "handles empty context" do
      assert {:ok, ["user"]} = Predicator.context_location("user", %{})
    end

    test "supports both string and atom context keys" do
      context = %{:items => [], "index" => 2}
      assert {:ok, ["items", 2]} = Predicator.context_location("items[index]", context)
    end
  end

  describe "real-world SCXML scenarios" do
    test "user profile assignment location" do
      location_expr = "user.profile.settings['theme']"

      assert {:ok, ["user", "profile", "settings", "theme"]} =
               Predicator.context_location(location_expr, %{})
    end

    test "array item property assignment" do
      location_expr = "users[0].name"

      assert {:ok, ["users", 0, "name"]} =
               Predicator.context_location(location_expr, %{})
    end

    test "dynamic key assignment" do
      location_expr = "config[section].enabled"
      context = %{"config" => %{}, "section" => "database"}

      assert {:ok, ["config", "database", "enabled"]} =
               Predicator.context_location(location_expr, context)
    end

    test "nested array assignment" do
      location_expr = "matrix[row][col]"
      context = %{"matrix" => [], "row" => 1, "col" => 3}

      assert {:ok, ["matrix", 1, 3]} =
               Predicator.context_location(location_expr, context)
    end

    test "complex datamodel path" do
      location_expr = "scxml.datamodel['variables'].counters[0].value"

      assert {:ok, ["scxml", "datamodel", "variables", "counters", 0, "value"]} =
               Predicator.context_location(location_expr, %{})
    end
  end

  describe "edge cases and boundary conditions" do
    test "handles very deep nesting" do
      deep_expr = "a.b.c.d.e.f.g.h.i.j"
      expected = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]
      assert {:ok, ^expected} = Predicator.context_location(deep_expr, %{})
    end

    test "handles mixed deep nesting with brackets" do
      deep_expr = "a[0].b['c'].d[1].e"
      expected = ["a", 0, "b", "c", "d", 1, "e"]
      assert {:ok, ^expected} = Predicator.context_location(deep_expr, %{})
    end

    test "handles single character identifiers" do
      assert {:ok, ["x"]} = Predicator.context_location("x", %{})
      assert {:ok, ["x", "y"]} = Predicator.context_location("x.y", %{})
    end

    test "handles numeric strings as bracket keys" do
      context = %{"obj" => %{}, "key" => "123"}
      assert {:ok, ["obj", "123"]} = Predicator.context_location("obj[key]", context)
    end

    test "handles zero as bracket key" do
      assert {:ok, ["items", 0]} = Predicator.context_location("items[0]", %{})

      context = %{"items" => [], "zero" => 0}
      assert {:ok, ["items", 0]} = Predicator.context_location("items[zero]", context)
    end

    test "handles empty string as bracket key" do
      context = %{"obj" => %{}, "key" => ""}
      assert {:ok, ["obj", ""]} = Predicator.context_location("obj[key]", context)
    end
  end
end
