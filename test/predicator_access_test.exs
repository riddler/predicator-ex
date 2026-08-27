defmodule PredicatorAccessTest do
  use ExUnit.Case, async: true

  import Predicator.ParseShape

  alias Predicator.Errors.UndefinedVariableError

  describe "nested context access" do
    test "simple nested access with string expressions" do
      context = %{"user" => %{"name" => %{"first" => "John", "last" => "Doe"}, "age" => 47}}

      assert Predicator.evaluate("user.name.first == \"John\"", context) == {:ok, true}
      assert Predicator.evaluate("user.name.last == \"Doe\"", context) == {:ok, true}
      assert Predicator.evaluate("user.age == 47", context) == {:ok, true}
      assert Predicator.evaluate("user.name.middle == \"X\"", context) == {:ok, :undefined}
    end

    test "nested access with atom keys" do
      context = %{user: %{name: %{first: "John"}, age: 47}}

      assert Predicator.evaluate("user.name.first == \"John\"", context) == {:ok, true}
      assert Predicator.evaluate("user.age > 18", context) == {:ok, true}
    end

    test "nested access with mixed key types" do
      context = %{"user" => %{profile: %{"name" => "John"}, age: 47}}

      assert Predicator.evaluate("user.profile.name == \"John\"", context) == {:ok, true}
      assert Predicator.evaluate("user.age >= 47", context) == {:ok, true}
    end

    test "nested access in complex expressions" do
      context = %{
        "user" => %{"name" => "John", "age" => 47},
        "config" => %{"enabled" => true, "level" => 3}
      }

      assert Predicator.evaluate("user.age > 18 AND config.enabled", context) == {:ok, true}

      assert Predicator.evaluate("user.name == \"John\" OR config.level > 5", context) ==
               {:ok, true}

      assert Predicator.evaluate("user.age < 18 AND config.enabled", context) == {:ok, false}
    end

    test "nested access with missing paths returns :undefined" do
      context = %{"user" => %{"name" => "John"}}

      assert Predicator.evaluate("user.profile.settings.theme == \"dark\"", context) ==
               {:ok, :undefined}

      assert Predicator.evaluate("missing.path.here == \"value\"", context) ==
               {:error,
                Predicator.Errors.put_position(UndefinedVariableError.new("missing"), {1, 1})}
    end

    test "nested access with non-map intermediate values" do
      context = %{"user" => %{"name" => "John Doe"}}

      # "name" is a string, not a map, so "user.name.first" should be :undefined
      assert Predicator.evaluate("user.name.first == \"John\"", context) == {:ok, :undefined}
    end

    test "deeply nested structures" do
      context = %{
        "app" => %{
          "database" => %{
            "config" => %{
              "host" => "localhost",
              "port" => 5432,
              "settings" => %{
                "ssl" => true,
                "timeout" => 30
              }
            }
          }
        }
      }

      assert Predicator.evaluate("app.database.config.host == \"localhost\"", context) ==
               {:ok, true}

      assert Predicator.evaluate("app.database.config.port == 5432", context) == {:ok, true}
      assert Predicator.evaluate("app.database.config.settings.ssl", context) == {:ok, true}

      assert Predicator.evaluate("app.database.config.settings.timeout > 25", context) ==
               {:ok, true}
    end

    test "nested access with list values" do
      context = %{
        "user" => %{
          "name" => "John",
          "hobbies" => ["reading", "coding", "gaming"],
          "limits" => [85, 92, 78]
        }
      }

      # Access the list itself
      {:ok, hobbies} = Predicator.evaluate("user.hobbies", context)
      assert hobbies == ["reading", "coding", "gaming"]

      # Use list in membership test
      assert Predicator.evaluate("\"coding\" in user.hobbies", context) == {:ok, true}
      assert Predicator.evaluate("\"dancing\" in user.hobbies", context) == {:ok, false}
    end
  end

  describe "evaluate/2 with bracket access expressions" do
    test "evaluates simple bracket access with string key" do
      context = %{"user" => %{"name" => "John", "age" => 30}}

      assert Predicator.evaluate("user['name']", context) == {:ok, "John"}
      assert Predicator.evaluate("user['age']", context) == {:ok, 30}
    end

    test "evaluates bracket access with atom keys" do
      context = %{"user" => %{:name => "John", :age => 30}}

      assert Predicator.evaluate("user['name']", context) == {:ok, "John"}
      assert Predicator.evaluate("user['age']", context) == {:ok, 30}
    end

    test "evaluates array access with numeric indices" do
      context = %{"items" => ["apple", "banana", "cherry"], "numbers" => [10, 20, 30]}

      assert Predicator.evaluate("items[0]", context) == {:ok, "apple"}
      assert Predicator.evaluate("items[1]", context) == {:ok, "banana"}
      assert Predicator.evaluate("numbers[2]", context) == {:ok, 30}
    end

    test "evaluates bracket access with variable key" do
      context = %{
        "user" => %{"name" => "John", "age" => 30},
        "key" => "name",
        "index" => 1,
        "items" => ["a", "b", "c"]
      }

      assert Predicator.evaluate("user[key]", context) == {:ok, "John"}
      assert Predicator.evaluate("items[index]", context) == {:ok, "b"}
    end

    test "evaluates chained bracket access" do
      context = %{
        "data" => %{
          "users" => [
            %{"name" => "John", "age" => 30},
            %{"name" => "Jane", "age" => 25}
          ]
        }
      }

      assert Predicator.evaluate("data['users'][0]['name']", context) == {:ok, "John"}
      assert Predicator.evaluate("data['users'][1]['age']", context) == {:ok, 25}
    end

    test "evaluates mixed dot notation and bracket access" do
      # Note: In the current implementation, dot notation creates nested identifiers
      # This tests that bracket access works alongside existing variable naming
      context = %{
        "user" => %{"name" => "John"},
        "settings" => %{"theme" => "dark"}
      }

      # Test that bracket access works
      assert Predicator.evaluate("user['name']", context) == {:ok, "John"}
      assert Predicator.evaluate("settings['theme']", context) == {:ok, "dark"}
    end

    test "evaluates bracket access with arithmetic expression key" do
      context = %{
        "items" => ["a", "b", "c", "d"],
        "offset" => 1,
        "multiplier" => 2
      }

      assert Predicator.evaluate("items[offset + 1]", context) == {:ok, "c"}
      assert Predicator.evaluate("items[offset * multiplier]", context) == {:ok, "c"}
    end

    test "evaluates bracket access in comparisons" do
      context = %{
        "user" => %{"age" => 30, "limit" => 95},
        "thresholds" => %{"min_age" => 18, "floor_limit" => 80}
      }

      assert Predicator.evaluate("user['age'] > 18", context) == {:ok, true}

      assert Predicator.evaluate("user['limit'] >= thresholds['floor_limit']", context) ==
               {:ok, true}

      assert Predicator.evaluate("user['age'] < thresholds['min_age']", context) == {:ok, false}
    end

    test "evaluates bracket access in arithmetic expressions" do
      context = %{
        "limits" => [85, 90, 78],
        "multipliers" => [2, 3, 4],
        "bonuses" => %{"effort" => 5, "attendance" => 3}
      }

      assert Predicator.evaluate("limits[0] + limits[1]", context) == {:ok, 175}
      assert Predicator.evaluate("limits[0] * multipliers[0]", context) == {:ok, 170}
      assert Predicator.evaluate("bonuses['effort'] + bonuses['attendance']", context) == {:ok, 8}
    end

    test "evaluates bracket access in logical expressions" do
      context = %{
        "user" => %{"active" => true, "verified" => true, "age" => 25},
        "settings" => %{"notifications" => false, "theme" => "dark"}
      }

      assert Predicator.evaluate("user['active'] AND user['verified']", context) == {:ok, true}

      assert Predicator.evaluate("user['active'] OR settings['notifications']", context) ==
               {:ok, true}

      assert Predicator.evaluate("NOT settings['notifications']", context) == {:ok, true}
    end

    test "evaluates complex nested bracket access expressions" do
      context = %{
        "company" => %{
          "departments" => [
            %{"name" => "Engineering", "employees" => [%{"name" => "John", "salary" => 80_000}]},
            %{"name" => "Marketing", "employees" => [%{"name" => "Jane", "salary" => 65_000}]}
          ]
        },
        "dept_index" => 0,
        "emp_index" => 0
      }

      assert Predicator.evaluate(
               "company['departments'][dept_index]['employees'][emp_index]['name']",
               context
             ) == {:ok, "John"}

      assert Predicator.evaluate(
               "company['departments'][0]['employees'][0]['salary'] > 75000",
               context
             ) == {:ok, true}
    end

    test "evaluates bracket access with function call keys" do
      context = %{
        "data" => %{"key_1" => "value1", "key_2" => "value2"},
        "keys" => ["key_1", "key_2"],
        "short" => "ab"
      }

      # Test with built-in len function (len("ab") = 2, so 2-1 = 1, keys[1] = "key_2")
      assert Predicator.evaluate("keys[len(short) - 1]", context) == {:ok, "key_2"}
    end

    test "evaluates bracket access with boolean keys" do
      context = %{
        "config" => %{true => "enabled", false => "disabled"},
        "status" => %{"active" => true, "debug" => false}
      }

      assert Predicator.evaluate("config[true]", context) == {:ok, "enabled"}
      assert Predicator.evaluate("config[false]", context) == {:ok, "disabled"}
      assert Predicator.evaluate("config[status['active']]", context) == {:ok, "enabled"}
    end

    test "evaluates bracket access with list membership" do
      context = %{
        "users" => [
          %{"name" => "John", "roles" => ["admin", "user"]},
          %{"name" => "Jane", "roles" => ["user"]}
        ],
        "admin_roles" => ["admin", "super_admin"]
      }

      assert Predicator.evaluate("'admin' in users[0]['roles']", context) == {:ok, true}
      assert Predicator.evaluate("users[0]['roles'] contains 'admin'", context) == {:ok, true}
      assert Predicator.evaluate("'admin' in users[1]['roles']", context) == {:ok, false}
    end

    test "returns :undefined for missing bracket access paths" do
      context = %{"user" => %{"name" => "John"}}

      assert Predicator.evaluate("user['missing_key']", context) == {:ok, :undefined}

      assert Predicator.evaluate("missing_object['key']", context) ==
               {:error,
                Predicator.Errors.put_position(
                  UndefinedVariableError.new("missing_object"),
                  {1, 1}
                )}

      assert Predicator.evaluate("user['name']['nested']", context) == {:ok, :undefined}
    end

    test "returns :undefined for out-of-bounds array access" do
      context = %{"items" => ["a", "b", "c"]}

      assert Predicator.evaluate("items[10]", context) == {:ok, :undefined}
      assert Predicator.evaluate("items[-1]", context) == {:ok, :undefined}
    end

    test "handles bracket access errors gracefully" do
      context = %{"data" => "not_a_map_or_list"}

      # Non-indexable object with string key returns :undefined
      assert Predicator.evaluate("data['key']", context) == {:ok, :undefined}

      # Non-indexable object with numeric key also returns :undefined
      assert Predicator.evaluate("data[0]", context) == {:ok, :undefined}
    end

    test "evaluates performance with deeply nested bracket access" do
      # Test that deeply nested access doesn't cause performance issues
      deeply_nested = %{
        "level1" => %{
          "level2" => %{
            "level3" => %{
              "level4" => %{
                "level5" => %{"final_value" => "success"}
              }
            }
          }
        }
      }

      context = %{"data" => deeply_nested}

      result =
        Predicator.evaluate(
          "data['level1']['level2']['level3']['level4']['level5']['final_value']",
          context
        )

      assert result == {:ok, "success"}
    end

    test "round-trip conversion with bracket access" do
      alias Predicator.Lexer
      alias Predicator.Visitors.StringVisitor

      expressions = [
        "user['name']",
        "items[0]",
        "data['users'][index]['profile']['settings']",
        "limits[0] + limits[1] > threshold['min']",
        "user['active'] AND config['enabled']"
      ]

      for expr <- expressions do
        {:ok, tokens} = Lexer.tokenize(expr)
        {:ok, ast} = Predicator.Parser.parse(tokens)
        regenerated = StringVisitor.visit(ast)

        # Parse the regenerated expression to ensure it's valid
        {:ok, tokens2} = Lexer.tokenize(regenerated)
        assert {:ok, _ast2} = parse_positionless(tokens2)
      end
    end
  end
end
