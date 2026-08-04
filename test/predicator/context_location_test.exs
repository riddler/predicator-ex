defmodule Predicator.ContextLocationTest do
  use ExUnit.Case, async: true

  doctest Predicator.ContextLocation

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

  describe "put/3 with simple paths" do
    test "writes a single segment into an empty context" do
      assert {:ok, %{"name" => "Ada"}} = ContextLocation.put(%{}, ["name"], "Ada")
    end

    test "overwrites an existing scalar leaf" do
      assert {:ok, %{"name" => "Ada"}} =
               ContextLocation.put(%{"name" => "Grace"}, ["name"], "Ada")
    end

    test "overwrites a leaf that currently holds a map" do
      context = %{"user" => %{"name" => "Grace"}}

      assert {:ok, %{"user" => "replaced"}} = ContextLocation.put(context, ["user"], "replaced")
    end

    test "overwrites a leaf that currently holds a list" do
      context = %{"items" => [1, 2, 3]}

      assert {:ok, %{"items" => "replaced"}} = ContextLocation.put(context, ["items"], "replaced")
    end

    test "does not mutate the original context" do
      original = %{"user" => %{"id" => 1}}

      assert {:ok, updated} = ContextLocation.put(original, ["user", "name"], "Ada")
      assert original == %{"user" => %{"id" => 1}}
      assert updated["user"]["name"] == "Ada"
    end

    test "returns not_assignable for an empty path" do
      assert {:error, %LocationError{type: :not_assignable} = error} =
               ContextLocation.put(%{}, [], "Ada")

      assert error.details.expression_type == "empty location path"
    end
  end

  describe "put/3 with map vivification" do
    test "vivifies a deep path from an empty context" do
      assert {:ok, %{"user" => %{"profile" => %{"name" => "Ada"}}}} =
               ContextLocation.put(%{}, ["user", "profile", "name"], "Ada")
    end

    test "vivifies only the missing part of a partial path" do
      assert {:ok, %{"user" => %{"profile" => %{"name" => "Ada"}}}} =
               ContextLocation.put(%{"user" => %{}}, ["user", "profile", "name"], "Ada")
    end

    test "preserves existing sibling keys through vivification" do
      context = %{"user" => %{"id" => 1}, "other" => true}

      assert {:ok, updated} = ContextLocation.put(context, ["user", "profile", "name"], "Ada")

      assert updated == %{
               "user" => %{"id" => 1, "profile" => %{"name" => "Ada"}},
               "other" => true
             }
    end

    test "treats a nil intermediate as absent and vivifies it" do
      assert {:ok, %{"user" => %{"name" => "Ada"}}} =
               ContextLocation.put(%{"user" => nil}, ["user", "name"], "Ada")
    end

    test "treats an :undefined intermediate as absent and vivifies it" do
      assert {:ok, %{"user" => %{"name" => "Ada"}}} =
               ContextLocation.put(%{"user" => :undefined}, ["user", "name"], "Ada")
    end

    test "never consults atom keys" do
      assert {:ok, updated} = ContextLocation.put(%{user: %{}}, ["user", "name"], "Ada")
      assert updated == %{"user" => %{"name" => "Ada"}, user: %{}}
    end
  end

  describe "put/3 with list indices" do
    test "vivifies a list when the next segment is an integer" do
      assert {:ok, %{"items" => [:undefined, :undefined, "x"]}} =
               ContextLocation.put(%{}, ["items", 2], "x")
    end

    test "pads an existing short list with :undefined" do
      assert {:ok, %{"items" => [1, :undefined, "x"]}} =
               ContextLocation.put(%{"items" => [1]}, ["items", 2], "x")
    end

    test "appends exactly at the end of a list" do
      assert {:ok, %{"items" => [1, 2, "x"]}} =
               ContextLocation.put(%{"items" => [1, 2]}, ["items", 2], "x")
    end

    test "replaces an in-range element" do
      assert {:ok, %{"items" => [1, "x", 3]}} =
               ContextLocation.put(%{"items" => [1, 2, 3]}, ["items", 1], "x")
    end

    test "vivifies through a list index into a map" do
      assert {:ok, %{"data" => %{"users" => [%{"name" => "Ada"}]}}} =
               ContextLocation.put(%{}, ["data", "users", 0, "name"], "Ada")
    end

    test "descends into an existing list element" do
      context = %{"users" => [%{"name" => "Grace"}, %{"name" => "Ada"}]}

      assert {:ok, %{"users" => [%{"name" => "Grace"}, %{"name" => "Lin"}]}} =
               ContextLocation.put(context, ["users", 1, "name"], "Lin")
    end

    test "writes an integer key into an existing map" do
      assert {:ok, updated} = ContextLocation.put(%{"obj" => %{"a" => 1}}, ["obj", 0], "x")
      assert updated == %{"obj" => %{"a" => 1, 0 => "x"}}
    end

    test "returns invalid_index for a negative leaf index" do
      assert {:error, %LocationError{type: :invalid_index} = error} =
               ContextLocation.put(%{"items" => [1, 2]}, ["items", -1], "x")

      assert error.details.index == -1
      assert error.details.location == "items[-1]"
    end

    test "returns invalid_index for a negative interior index" do
      assert {:error, %LocationError{type: :invalid_index} = error} =
               ContextLocation.put(%{"items" => [1, 2]}, ["items", -1, "name"], "x")

      assert error.details.location == "items[-1]"
    end
  end

  describe "put/3 with container collisions" do
    test "returns not_a_container for a scalar intermediate" do
      assert {:error, %LocationError{type: :not_a_container} = error} =
               ContextLocation.put(%{"user" => 5}, ["user", "name"], "Ada")

      assert error.details.location == "user"
      assert error.details.segment == "user"
      assert error.details.value == 5
      assert error.details.value_type == "integer"
    end

    test "names the offending location deep in a path" do
      context = %{"user" => %{"profile" => "not a map"}}

      assert {:error, %LocationError{type: :not_a_container} = error} =
               ContextLocation.put(context, ["user", "profile", "name"], "Ada")

      assert error.details.location == "user.profile"
      assert error.message == "Cannot assign through non-container value at 'user.profile'"
    end

    test "returns not_a_container for a string leaf segment against a list" do
      assert {:error, %LocationError{type: :not_a_container} = error} =
               ContextLocation.put(%{"items" => [1]}, ["items", "name"], "x")

      assert error.details.location == "items.name"
      assert error.details.value == [1]
    end

    test "returns not_a_container for a string interior segment against a list" do
      assert {:error, %LocationError{type: :not_a_container} = error} =
               ContextLocation.put(%{"items" => [1]}, ["items", "name", "deep"], "x")

      assert error.details.location == "items.name"
    end

    test "does not destroy data when a collision is reported" do
      context = %{"user" => 5}

      assert {:error, %LocationError{}} = ContextLocation.put(context, ["user", "name"], "Ada")
      assert context == %{"user" => 5}
    end
  end

  describe "context_assign/4 expression forms" do
    test "assigns to a simple identifier" do
      assert {:ok, %{"user" => "Ada"}} = Predicator.context_assign(%{}, "user", "Ada")
    end

    test "assigns through property access, vivifying intermediates" do
      assert {:ok, %{"user" => %{"profile" => %{"name" => "Ada"}}}} =
               Predicator.context_assign(%{}, "user.profile.name", "Ada")
    end

    test "assigns into a list by index" do
      assert {:ok, %{"items" => ["x", 2, 3]}} =
               Predicator.context_assign(%{"items" => [1, 2, 3]}, "items[0]", "x")
    end

    test "assigns through a quoted bracket key" do
      assert {:ok, %{"user" => %{"settings" => %{"theme" => "dark"}}}} =
               Predicator.context_assign(%{}, "user.settings['theme']", "dark")
    end

    test "assigns through mixed bracket and property notation" do
      assert {:ok, %{"data" => %{"users" => [%{"name" => "Ada"}]}}} =
               Predicator.context_assign(%{}, "data['users'][0].name", "Ada")
    end

    test "resolves a variable bracket key against the pre-assignment context" do
      context = %{"index" => 1, "items" => [1, 2, 3]}

      assert {:ok, %{"index" => 1, "items" => [1, "x", 3]}} =
               Predicator.context_assign(context, "items[index]", "x")
    end

    test "composes sequentially to build a nested structure" do
      assert {:ok, context} = Predicator.context_assign(%{}, "user.profile.name", "Ada")
      assert {:ok, context} = Predicator.context_assign(context, "user.profile.age", 36)
      assert {:ok, context} = Predicator.context_assign(context, "user.tags[0]", "admin")

      assert context == %{
               "user" => %{
                 "profile" => %{"name" => "Ada", "age" => 36},
                 "tags" => ["admin"]
               }
             }
    end
  end

  describe "context_assign/4 error propagation" do
    test "surfaces parse errors unchanged" do
      assert {:error, %Predicator.Errors.ParseError{}} =
               Predicator.context_assign(%{}, "user.", "Ada")
    end

    test "surfaces not_assignable for literals" do
      assert {:error, %LocationError{type: :not_assignable}} =
               Predicator.context_assign(%{}, "42", "Ada")
    end

    test "surfaces not_assignable for function calls" do
      assert {:error, %LocationError{type: :not_assignable}} =
               Predicator.context_assign(%{"items" => [1]}, "len(items)", 1)
    end

    test "surfaces not_assignable for arithmetic expressions" do
      assert {:error, %LocationError{type: :not_assignable}} =
               Predicator.context_assign(%{"user" => %{"age" => 30}}, "user.age + 1", 31)
    end

    test "does not vivify an undefined bracket key variable" do
      assert {:error, %LocationError{type: :undefined_variable}} =
               Predicator.context_assign(%{"items" => [1]}, "items[missing]", "x")
    end

    test "propagates write-time collisions from put/3" do
      assert {:error, %LocationError{type: :not_a_container} = error} =
               Predicator.context_assign(%{"user" => 5}, "user.profile.name", "Ada")

      assert error.details.location == "user"
    end

    test "propagates invalid_index for a negative bracket index" do
      assert {:error, %LocationError{type: :invalid_index}} =
               Predicator.context_assign(%{"items" => [1, 2]}, "items[-1]", "x")
    end
  end
end
