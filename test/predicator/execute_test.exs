defmodule Predicator.ExecuteTest do
  use ExUnit.Case, async: true

  alias Predicator.{Compiled, Context, Errors}

  describe "execute/2,3 - input shapes" do
    test "accepts a source string" do
      assert {:ok, ctx} = Predicator.execute("x = 1", %{})
      assert ctx.data == %{"x" => 1}
    end

    test "accepts a pre-compiled instruction list" do
      {:ok, instructions} = Predicator.compile_program("x = 1")

      assert {:ok, ctx} = Predicator.execute(instructions, %{})
      assert ctx.data == %{"x" => 1}
    end

    test "accepts a %Compiled{}" do
      {:ok, compiled} = Predicator.compile_program_with_positions("x = 1")

      assert {:ok, ctx} = Predicator.execute(compiled, %{})
      assert ctx.data == %{"x" => 1}
    end

    test "%Compiled{} + :positions raises ArgumentError" do
      {:ok, compiled} = Predicator.compile_program_with_positions("x = 1")

      assert_raise ArgumentError, fn ->
        Predicator.execute(compiled, %{}, positions: %{})
      end
    end
  end

  describe "execute/2,3 - context shapes" do
    test "accepts a bare map, normalizing it into a %Context{}" do
      assert {:ok, %Context{} = ctx} = Predicator.execute("x = 1", %{})
      assert ctx.data == %{"x" => 1}
    end

    test "accepts a %Context{} directly" do
      context = Context.new(%{"y" => 1})

      assert {:ok, ctx} = Predicator.execute("x = y", context)
      assert ctx.data == %{"x" => 1, "y" => 1}
    end

    test "preserves custom functions through the round trip" do
      custom = %{"double" => {1, fn [n], _ctx -> {:ok, n * 2} end}}
      context = Context.new(%{}, functions: custom)

      assert {:ok, ctx} = Predicator.execute("x = double(21)", context)
      assert ctx.data == %{"x" => 42}
      assert ctx.functions == context.functions
    end

    test "preserves on_unbound through the round trip" do
      context = Context.new(%{}, on_unbound: :error)

      assert {:error, %Errors.UndefinedVariableError{} = error, _ctx} =
               Predicator.execute("x = missing", context)

      assert error.variable == "missing"
    end

    test "on_unbound defaults to :undefined for a bare map" do
      assert {:ok, ctx} = Predicator.execute("x = missing", %{})
      assert ctx.data == %{"x" => :undefined}
    end
  end

  describe "execute/2,3 - statement shapes" do
    test "an assignment to a simple identifier" do
      assert {:ok, ctx} = Predicator.execute("x = 1", %{})
      assert ctx.data == %{"x" => 1}
    end

    test "an assignment through property access, vivifying a map" do
      assert {:ok, ctx} = Predicator.execute("a.b = 1", %{})
      assert ctx.data == %{"a" => %{"b" => 1}}
    end

    test "an assignment through bracket access, vivifying a list" do
      assert {:ok, ctx} = Predicator.execute("xs[0] = 7", %{})
      assert ctx.data == %{"xs" => [7]}
    end

    test "an assignment through a computed bracket key" do
      assert {:ok, ctx} = Predicator.execute("a[k + 1] = 1", %{"k" => 0})
      assert ctx.data == %{"a" => [:undefined, 1], "k" => 0}
    end

    test "a bare expression statement is discarded via pop" do
      assert {:ok, ctx} = Predicator.execute("1 + 1", %{})
      assert ctx.data == %{}
    end

    test "a multi-statement program mixing assignments and expressions" do
      assert {:ok, ctx} = Predicator.execute("x = 1; x + 1; y = x + 2", %{})
      assert ctx.data == %{"x" => 1, "y" => 3}
    end
  end

  describe "execute/2,3 - error paths" do
    test "a parse error from the source clause" do
      assert {:error, %Errors.ParseError{}, %Context{}} = Predicator.execute("x =", %{})
    end

    test "the partial-context error path: prior writes survive, later statements do not run" do
      assert {:error, %Errors.EvaluationError{reason: "not_a_container"}, ctx} =
               Predicator.execute("a = 1; a.b = 2; c = 3", %{})

      assert ctx.data == %{"a" => 1}
      refute Map.has_key?(ctx.data, "c")
    end

    test "a store failure blames the lhs root, not the `=`" do
      # `a` is at column 8; the `=` this used to report is at column 12.
      assert {:error, %Errors.EvaluationError{reason: "not_a_container", position: {1, 8}}, _ctx} =
               Predicator.execute("a = 1; a.b = 2; d = 3", %{})
    end

    test "an invalid list index blames the lhs root" do
      assert {:error, %Errors.EvaluationError{reason: "invalid_index", position: {1, 13}}, _ctx} =
               Predicator.execute("xs = [1,2]; xs[0-1] = 9", %{})
    end

    test "span mode is unchanged: the caret is the lhs root, the underline the statement" do
      assert {:error, %Errors.EvaluationError{position: {1, 8}, span: {{1, 8}, {1, 15}}}, _ctx} =
               Predicator.execute("a = 1; a.b = 2; d = 3", %{}, spans: true)
    end
  end

  describe "execute/2,3 - halt shapes" do
    test "an expression-only program halts with an empty stack and succeeds" do
      assert {:ok, ctx} = Predicator.execute("1; 2; 3", %{"seed" => 1})
      assert ctx.data == %{"seed" => 1}
    end

    test "an empty-ish program (single expression statement) succeeds with unchanged data" do
      assert {:ok, ctx} = Predicator.execute("true", %{"a" => 1})
      assert ctx.data == %{"a" => 1}
    end
  end

  describe "compile_program/1 and compile_program_with_positions/1" do
    test "compile_program/1 returns an instruction list" do
      assert {:ok, instructions} = Predicator.compile_program("x = 1")
      assert instructions == [["lit", "x"], ["lit", 1], ["store", 1]]
    end

    test "compile_program/1 returns a binary error, not parse_program/2's raw 4-tuple" do
      assert {:error, message} = Predicator.compile_program("x =")
      assert is_binary(message)
    end

    test "compile_program_with_positions/1 returns a %Compiled{}" do
      assert {:ok, %Compiled{} = compiled} = Predicator.compile_program_with_positions("x = 1")
      assert compiled.instructions == [["lit", "x"], ["lit", 1], ["store", 1]]
      assert compiled.positions != %{}
    end
  end
end
