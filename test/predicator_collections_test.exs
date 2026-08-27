defmodule PredicatorCollectionsTest do
  use ExUnit.Case, async: true

  import Predicator.ParseShape

  alias Predicator.Errors.UndefinedVariableError

  describe "list literals and membership operators" do
    test "evaluates list literals" do
      assert Predicator.evaluate("[1, 2, 3]", %{}) == {:ok, [1, 2, 3]}
      assert Predicator.evaluate("[]", %{}) == {:ok, []}
      assert Predicator.evaluate(~s(["admin", "manager"]), %{}) == {:ok, ["admin", "manager"]}
      assert Predicator.evaluate("[true, false]", %{}) == {:ok, [true, false]}
    end

    test "evaluates 'in' operator with literals" do
      assert Predicator.evaluate("1 in [1, 2, 3]", %{}) == {:ok, true}
      assert Predicator.evaluate("4 in [1, 2, 3]", %{}) == {:ok, false}
      assert Predicator.evaluate(~s("admin" in ["admin", "manager"]), %{}) == {:ok, true}
      assert Predicator.evaluate(~s("user" in ["admin", "manager"]), %{}) == {:ok, false}
      assert Predicator.evaluate("true in [true, false]", %{}) == {:ok, true}
      assert Predicator.evaluate("false in [true]", %{}) == {:ok, false}
    end

    test "evaluates 'contains' operator with literals" do
      assert Predicator.evaluate("[1, 2, 3] contains 2", %{}) == {:ok, true}
      assert Predicator.evaluate("[1, 2, 3] contains 4", %{}) == {:ok, false}
      assert Predicator.evaluate(~s(["admin", "manager"] contains "admin"), %{}) == {:ok, true}
      assert Predicator.evaluate(~s(["admin", "manager"] contains "user"), %{}) == {:ok, false}
      assert Predicator.evaluate("[true, false] contains false", %{}) == {:ok, true}
      assert Predicator.evaluate("[true] contains false", %{}) == {:ok, false}
    end

    test "evaluates 'in' operator with variables" do
      context = %{"role" => "admin", "permissions" => ["read", "write"]}

      assert Predicator.evaluate(~s(role in ["admin", "manager"]), context) == {:ok, true}
      assert Predicator.evaluate(~s(role in ["user", "guest"]), context) == {:ok, false}
      assert Predicator.evaluate(~s("write" in permissions), context) == {:ok, true}
      assert Predicator.evaluate(~s("delete" in permissions), context) == {:ok, false}
    end

    test "evaluates 'contains' operator with variables" do
      context = %{"roles" => ["admin", "manager"], "active" => true}

      assert Predicator.evaluate(~s(roles contains "admin"), context) == {:ok, true}
      assert Predicator.evaluate(~s(roles contains "user"), context) == {:ok, false}
      assert Predicator.evaluate("[true, false] contains active", context) == {:ok, true}
    end

    test "works with lowercase membership operators" do
      assert Predicator.evaluate("1 in [1, 2, 3]", %{}) == {:ok, true}
      assert Predicator.evaluate("1 IN [1, 2, 3]", %{}) == {:ok, true}
      assert Predicator.evaluate("[1, 2] contains 1", %{}) == {:ok, true}
      assert Predicator.evaluate("[1, 2] CONTAINS 1", %{}) == {:ok, true}
    end

    test "combines with logical operators" do
      context = %{"role" => "admin", "active" => true, "permissions" => ["read", "write"]}

      assert Predicator.evaluate(~s(role in ["admin", "manager"] AND active), context) ==
               {:ok, true}

      assert Predicator.evaluate(~s(role in ["admin", "manager"] OR active), context) ==
               {:ok, true}

      assert Predicator.evaluate(~s(NOT role in ["user", "guest"]), context) == {:ok, true}

      assert Predicator.evaluate(~s(permissions contains "write" AND active), context) ==
               {:ok, true}
    end

    test "handles empty lists" do
      assert Predicator.evaluate("1 in []", %{}) == {:ok, false}
      assert Predicator.evaluate("[] contains 1", %{}) == {:ok, false}
    end

    test "handles type mismatches" do
      # Different types should not match
      assert Predicator.evaluate(~s("1" in [1, 2, 3]), %{}) == {:ok, false}
      assert Predicator.evaluate(~s(1 in ["1", "2", "3"]), %{}) == {:ok, false}
      assert Predicator.evaluate("[1, 2, 3] contains \"1\"", %{}) == {:ok, false}
    end

    test "returns an UndefinedVariableError for an unbound root variable" do
      assert Predicator.evaluate("missing_var in [1, 2, 3]", %{}) ==
               {:error,
                Predicator.Errors.put_position(UndefinedVariableError.new("missing_var"), {1, 1})}

      assert Predicator.evaluate("[1, 2, 3] contains missing_var", %{}) ==
               {:error,
                Predicator.Errors.put_position(
                  UndefinedVariableError.new("missing_var"),
                  {1, 20}
                )}
    end

    test "parses list expressions correctly" do
      {:ok, ast} = parse_positionless("[1, 2, 3]")
      assert match?({:list, [_literal1, _literal2, _literal3]}, ast)

      {:ok, ast} = parse_positionless("1 in [1, 2, 3]")
      assert match?({:membership, :in, {:literal, 1}, {:list, _elements}}, ast)

      {:ok, ast} = parse_positionless("[1, 2] contains 1")
      assert match?({:membership, :contains, {:list, _elements}, {:literal, 1}}, ast)
    end

    test "compiles list expressions correctly" do
      {:ok, instructions} = Predicator.compile("[1, 2, 3]")
      assert instructions == [["lit", [1, 2, 3]]]

      {:ok, instructions} = Predicator.compile("1 in [1, 2, 3]")
      assert instructions == [["lit", 1], ["lit", [1, 2, 3]], ["in"]]

      {:ok, instructions} = Predicator.compile("[1, 2] contains 1")
      assert instructions == [["lit", [1, 2]], ["lit", 1], ["contains"]]
    end

    test "decompiles list expressions" do
      {:ok, ast} = Predicator.parse("[1, 2, 3]")
      assert Predicator.decompile(ast) == "[1, 2, 3]"

      {:ok, ast} = Predicator.parse("1 in [1, 2, 3]")
      assert Predicator.decompile(ast) == "1 IN [1, 2, 3]"

      {:ok, ast} = Predicator.parse("[1, 2] contains 1")
      assert Predicator.decompile(ast) == "[1, 2] CONTAINS 1"
    end

    test "works with complex expressions" do
      context = %{
        "user_roles" => ["admin", "manager"],
        "permissions" => ["read", "write", "delete"],
        "active" => true
      }

      result =
        Predicator.evaluate(
          ~s(user_roles contains "admin" AND permissions contains "delete"),
          context
        )

      assert result == {:ok, true}

      result =
        Predicator.evaluate(
          ~s(user_roles contains "guest" OR permissions contains "read"),
          context
        )

      assert result == {:ok, true}

      result = Predicator.evaluate(~s(NOT user_roles contains "guest" AND active), context)
      assert result == {:ok, true}
    end

    test "handles error cases" do
      # IN with non-list on right side
      result = Predicator.evaluate("1 in 2", %{})
      assert {:error, _message} = result

      # CONTAINS with non-list on left side
      result = Predicator.evaluate("1 contains 2", %{})
      assert {:error, _message} = result
    end
  end

  describe "object literals" do
    test "evaluates simple object literals" do
      assert Predicator.evaluate("{}", %{}) == {:ok, %{}}
      assert Predicator.evaluate("{name: \"John\"}", %{}) == {:ok, %{"name" => "John"}}

      assert Predicator.evaluate("{age: 30, active: true}", %{}) ==
               {:ok, %{"age" => 30, "active" => true}}
    end

    test "evaluates object literals with variable references" do
      context = %{"username" => "alice", "limit" => 95}

      assert Predicator.evaluate("{user: username, points: limit}", context) ==
               {:ok, %{"user" => "alice", "points" => 95}}
    end

    test "evaluates nested object literals" do
      expected = %{
        "user" => %{"name" => "Bob", "role" => "admin"},
        "settings" => %{"theme" => "dark"}
      }

      assert Predicator.evaluate(
               ~s|{user: {name: "Bob", role: "admin"}, settings: {theme: "dark"}}|,
               %{}
             ) ==
               {:ok, expected}
    end

    test "evaluates object literals with string keys" do
      assert Predicator.evaluate(~s|{"first name": "John", "last name": "Doe"}|, %{}) ==
               {:ok, %{"first name" => "John", "last name" => "Doe"}}
    end

    test "evaluates object literals with expression values" do
      context = %{"base" => 100, "rate" => 0.1}

      assert Predicator.evaluate("{total: base + base * rate}", context) ==
               {:ok, %{"total" => 110.0}}
    end

    test "object equality and comparison" do
      context = %{"user_data" => %{"limit" => 85}}

      assert Predicator.evaluate("{limit: 85} == user_data", context) == {:ok, true}
      assert Predicator.evaluate("{limit: 90} != user_data", context) == {:ok, true}
      assert Predicator.evaluate("{} == {}", %{}) == {:ok, true}
      assert Predicator.evaluate("{} != {name: \"test\"}", %{}) == {:ok, true}
    end

    test "parses object expressions correctly" do
      {:ok, ast} = parse_positionless("{name: \"John\"}")

      assert match?(
               {:object,
                [{{:object_key, "name", :identifier}, {:string_literal, "John", :double}}]},
               ast
             )

      {:ok, ast} = parse_positionless("{}")
      assert match?({:object, []}, ast)
    end

    test "compiles object expressions correctly" do
      {:ok, instructions} = Predicator.compile("{}")
      assert instructions == [["object_new"]]

      {:ok, instructions} = Predicator.compile("{name: \"John\"}")
      assert instructions == [["object_new"], ["lit", "John"], ["object_set", "name"]]

      {:ok, instructions} = Predicator.compile("{name: \"John\", age: 30}")

      assert instructions == [
               ["object_new"],
               ["lit", "John"],
               ["object_set", "name"],
               ["lit", 30],
               ["object_set", "age"]
             ]
    end

    test "handles undefined variables in object values" do
      assert Predicator.evaluate("{name: missing_var}", %{}) == {:ok, %{"name" => :undefined}}
    end

    test "decompiles object expressions" do
      {:ok, ast} = Predicator.parse("{}")
      assert Predicator.decompile(ast) == "{}"

      {:ok, ast} = Predicator.parse("{name: \"John\"}")
      assert Predicator.decompile(ast) == ~s({name: "John"})

      {:ok, ast} = Predicator.parse(~s|{"first name": "John", "last name": "Doe"}|)
      assert Predicator.decompile(ast) == ~s({"first name": "John", "last name": "Doe"})

      {:ok, ast} = Predicator.parse("{age: 30, active: true}")
      assert Predicator.decompile(ast) == "{age: 30, active: true}"
    end

    test "object round-trip consistency" do
      expressions = [
        "{}",
        "{name: \"John\"}",
        "{age: 30, active: true}",
        ~s|{"first name": "John"}|,
        "{user: {name: \"Bob\", role: \"admin\"}}",
        "{total: price + tax}"
      ]

      for expr <- expressions do
        {:ok, ast} = Predicator.parse(expr)
        decompiled = Predicator.decompile(ast)
        {:ok, ast2} = Predicator.parse(decompiled)

        # ASTs should be equivalent after round-trip
        assert ast == ast2, "Round-trip failed for: #{expr}"
      end
    end
  end
end
