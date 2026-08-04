defmodule Predicator.EqualsDeprecationTest do
  # async: false because the config gate is global application state.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Predicator.Visitors.StringVisitor

  defp parse_log(expression) do
    capture_log(fn -> Predicator.parse(expression) end)
  end

  describe "deprecation warning for `=`" do
    test "warns when `=` is used as an equality operator" do
      assert parse_log("a = 1") =~ "[predicator]"
    end

    test "names `==` as the replacement and 4.0 as the breaking release" do
      log = parse_log("a = 1")

      assert log =~ "`=`"
      assert log =~ "`==`"
      assert log =~ "4.0"
      assert log =~ "deprecation_warnings: false"
    end

    test "reports the line and column of the `=`" do
      assert parse_log("a\n= 1") =~ "line 2, column 1"
    end

    test "does not warn for `==`" do
      assert parse_log("a == 1") == ""
    end

    test "does not warn for `===`" do
      assert parse_log("a === 1") == ""
    end

    test "does not warn for `>=`, `<=`, `!=`, or `!==`" do
      assert parse_log("a >= 1") == ""
      assert parse_log("a <= 1") == ""
      assert parse_log("a != 1") == ""
      assert parse_log("a !== 1") == ""
    end

    test "does not warn for an expression with no comparison at all" do
      assert parse_log("a") == ""
    end

    test "does not warn for an `=` inside a string literal" do
      assert parse_log("a == '='") == ""
    end

    test "warns exactly once for an expression with several `=` operators" do
      log = parse_log("a = 1 or b = 2 or c = 3")

      assert length(Regex.scan(~r/\[predicator\]/, log)) == 1
    end

    test "reports the position of the first `=` when there are several" do
      assert parse_log("a = 1 or b = 2") =~ "line 1, column 3"
    end

    test "warns and still returns the parse error for a malformed expression" do
      log = capture_log(fn -> assert {:error, _message, 1, 4} = Predicator.parse("a =") end)

      assert log =~ "[predicator]"
    end

    test "does not warn for an empty token list or a bare EOF" do
      assert capture_log(fn -> Predicator.Parser.parse([]) end) == ""
      assert capture_log(fn -> Predicator.Parser.parse([{:eof, 1, 1, 0, nil}]) end) == ""
    end
  end

  describe "entry points" do
    test "Predicator.evaluate/3 warns" do
      log = capture_log(fn -> assert {:ok, true} = Predicator.evaluate("a = 1", %{"a" => 1}) end)

      assert log =~ "[predicator]"
    end

    test "Predicator.evaluate!/3 warns" do
      log = capture_log(fn -> assert Predicator.evaluate!("a = 1", %{"a" => 1}) end)

      assert log =~ "[predicator]"
    end

    test "Predicator.compile/1 warns" do
      log = capture_log(fn -> assert {:ok, _instructions} = Predicator.compile("a = 1") end)

      assert log =~ "[predicator]"
    end

    test "Predicator.parse/1 warns" do
      assert parse_log("a = 1") =~ "[predicator]"
    end

    test "Predicator.context_assign/4 warns for an expression containing `=`" do
      log =
        capture_log(fn ->
          assert {:error, _error} = Predicator.context_assign(%{}, "a = 1", 5)
        end)

      assert log =~ "[predicator]"
    end
  end

  describe "config gate" do
    setup do
      on_exit(fn -> Application.delete_env(:predicator, :deprecation_warnings) end)
      :ok
    end

    test "is silent when deprecation_warnings is false" do
      Application.put_env(:predicator, :deprecation_warnings, false)

      assert parse_log("a = 1") == ""
    end

    test "warns when deprecation_warnings is true" do
      Application.put_env(:predicator, :deprecation_warnings, true)

      assert parse_log("a = 1") =~ "[predicator]"
    end

    test "warns when deprecation_warnings is unset" do
      Application.delete_env(:predicator, :deprecation_warnings)

      assert parse_log("a = 1") =~ "[predicator]"
    end
  end

  describe "behavior is otherwise unchanged" do
    test ~s(`=` still compiles to ["compare", "EQ"]) do
      capture_log(fn ->
        assert {:ok, [["load", "a"], ["lit", 1], ["compare", "EQ"]]} = Predicator.compile("a = 1")
      end)
    end

    test "`=` and `==` produce identical instructions" do
      capture_log(fn ->
        assert Predicator.compile("a = 1") == Predicator.compile("a == 1")
      end)
    end

    test "`=` still evaluates to the same result as `==`" do
      context = %{"a" => 1}

      capture_log(fn ->
        assert Predicator.evaluate("a = 1", context) == Predicator.evaluate("a == 1", context)
        assert Predicator.evaluate("a = 2", context) == Predicator.evaluate("a == 2", context)
      end)
    end

    test "StringVisitor still renders an `:eq` node as `=`" do
      assert StringVisitor.visit({:comparison, :eq, {:identifier, "a"}, {:literal, 1}}) == "a = 1"
    end
  end
end
