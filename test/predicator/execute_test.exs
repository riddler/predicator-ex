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

    test "%Compiled{} + :segment_positions raises ArgumentError" do
      {:ok, compiled} = Predicator.compile_program_with_positions("x = 1")

      assert_raise ArgumentError, fn ->
        Predicator.execute(compiled, %{}, segment_positions: %{})
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

    test "a store failure blames the failing segment" do
      # `a` is at column 8; the `=` this used to report is at column 12.
      # Segment 0 is the lhs root here, so this position is unchanged by px-ids.
      assert {:error, %Errors.EvaluationError{reason: "not_a_container", position: {1, 8}}, _ctx} =
               Predicator.execute("a = 1; a.b = 2; d = 3", %{})
    end

    test "an invalid list index blames the failing segment" do
      # Was {1, 13} (the lhs root `xs`) before px-ids; now the key expression
      # `0-1` that produced the bad index.
      assert {:error, %Errors.EvaluationError{reason: "invalid_index", position: {1, 17}}, _ctx} =
               Predicator.execute("xs = [1,2]; xs[0-1] = 9", %{})
    end

    test "a deep chain blames the interior segment that actually failed" do
      # `a` is at column 15; the failing segment is `.b`, whose point position
      # is column 17, the property name `b` itself (docs/reference/ast.md).
      assert {:error, %Errors.EvaluationError{reason: "not_a_container", position: {1, 17}}, _ctx} =
               Predicator.execute(~s(a = {"b": 1}; a.b.c = 2), %{})
    end

    test "a bare instruction list with no segment table degrades to the store instruction's own entry" do
      assert {:error, %Errors.EvaluationError{reason: "not_a_container", position: nil}, ctx} =
               Predicator.execute([["lit", "a"], ["lit", "b"], ["lit", 2], ["store", 2]], %{
                 "a" => 1
               })

      assert ctx.data == %{"a" => 1}
    end

    test "span mode narrows to the failing segment; the caret is unchanged (D1)" do
      # Was span: {{1, 8}, {1, 15}} (the whole statement) before px-ids;
      # position: {1, 8} is unchanged because a chain node's span starts at
      # the chain root.
      assert {:error, %Errors.EvaluationError{position: {1, 8}, span: {{1, 8}, {1, 9}}}, _ctx} =
               Predicator.execute("a = 1; a.b = 2; d = 3", %{}, spans: true)
    end

    test "a bad segment blames the failing segment and names both accepted types" do
      # Was position: {1, 1} (the lhs root `a`) before px-ids; now the key
      # expression `true` that produced the bad segment.
      assert {:error,
              %Errors.TypeMismatchError{
                expected: :string,
                position: {1, 3},
                message: "Store requires a string or an integer, got true (boolean)"
              }, _ctx} = Predicator.execute("a[true] = 1", %{"a" => %{}})
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

    test "compile_program_with_positions/1 also carries a non-empty segment_positions table" do
      assert {:ok, %Compiled{} = compiled} = Predicator.compile_program_with_positions("a.b = 1")

      assert compiled.instructions == [["lit", "a"], ["lit", "b"], ["lit", 1], ["store", 2]]
      assert compiled.positions != %{}
      assert compiled.segment_positions == %{3 => [{1, 1}, {1, 3}]}
    end
  end

  describe "execute_value/2,3 - input shapes" do
    test "accepts a source string" do
      assert {:ok, 2, ctx} = Predicator.execute_value("x = 1; x + 1", %{})
      assert ctx.data == %{"x" => 1}
    end

    test "accepts a pre-compiled instruction list" do
      {:ok, instructions} = Predicator.compile_program("x = 1; x + 1")

      assert {:ok, 2, ctx} = Predicator.execute_value(instructions, %{})
      assert ctx.data == %{"x" => 1}
    end

    test "accepts a %Compiled{}" do
      {:ok, compiled} = Predicator.compile_program_with_positions("x = 1; x + 1")

      assert {:ok, 2, ctx} = Predicator.execute_value(compiled, %{})
      assert ctx.data == %{"x" => 1}
    end

    test "all three input shapes return the same value for the same program" do
      source = "x = 1; x + 1"
      {:ok, instructions} = Predicator.compile_program(source)
      {:ok, compiled} = Predicator.compile_program_with_positions(source)

      assert {:ok, 2, _ctx} = Predicator.execute_value(source, %{})
      assert {:ok, 2, _ctx} = Predicator.execute_value(instructions, %{})
      assert {:ok, 2, _ctx} = Predicator.execute_value(compiled, %{})
    end

    test "%Compiled{} + :positions raises ArgumentError" do
      {:ok, compiled} = Predicator.compile_program_with_positions("x = 1")

      assert_raise ArgumentError, fn ->
        Predicator.execute_value(compiled, %{}, positions: %{})
      end
    end

    test "%Compiled{} + :segment_positions raises ArgumentError" do
      {:ok, compiled} = Predicator.compile_program_with_positions("x = 1")

      assert_raise ArgumentError, fn ->
        Predicator.execute_value(compiled, %{}, segment_positions: %{})
      end
    end
  end

  describe "execute_value/2,3 - context shapes" do
    test "accepts a bare map, normalizing it into a %Context{}" do
      assert {:ok, 1, %Context{} = ctx} = Predicator.execute_value("x = 1; x", %{})
      assert ctx.data == %{"x" => 1}
    end

    test "accepts a %Context{} directly" do
      context = Context.new(%{"y" => 1})

      assert {:ok, 2, ctx} = Predicator.execute_value("x = y; x + 1", context)
      assert ctx.data == %{"x" => 1, "y" => 1}
    end

    test "preserves custom functions through the round trip" do
      custom = %{"double" => {1, fn [n], _ctx -> {:ok, n * 2} end}}
      context = Context.new(%{}, functions: custom)

      assert {:ok, 42, ctx} = Predicator.execute_value("x = double(21); x", context)
      assert ctx.data == %{"x" => 42}
      assert ctx.functions == context.functions
    end

    test "preserves on_unbound through the round trip" do
      context = Context.new(%{}, on_unbound: :error)

      assert {:error, %Errors.UndefinedVariableError{} = error, _ctx} =
               Predicator.execute_value("x = missing", context)

      assert error.variable == "missing"
    end
  end

  describe "execute_value/2,3 - the definition (last pop, not last statement)" do
    test "last statement is an expression: its value" do
      assert {:ok, 3, _ctx} = Predicator.execute_value("x = 1; x + 2", %{})
    end

    test "last statement is an assignment with an earlier expression statement: the earlier statement's value" do
      assert {:ok, 99, ctx} = Predicator.execute_value("x = 1; 99; y = 2", %{})
      assert ctx.data == %{"x" => 1, "y" => 2}
    end

    test "assignments only: :undefined" do
      assert {:ok, :undefined, ctx} = Predicator.execute_value("x = 1; y = 2", %{})
      assert ctx.data == %{"x" => 1, "y" => 2}
    end

    test "a hand-built list with a stack residue and no pop: :undefined" do
      assert {:ok, :undefined, _ctx} = Predicator.execute_value([["lit", 1]], %{})
    end
  end

  describe "execute_value/2,3 - error paths" do
    test "the partial-context error path: prior writes survive, later statements do not run" do
      assert {:error, %Errors.EvaluationError{reason: "not_a_container"}, ctx} =
               Predicator.execute_value("a = 1; a.b = 2; c = 3", %{})

      assert ctx.data == %{"a" => 1}
      refute Map.has_key?(ctx.data, "c")
    end

    test "a lexer error returns the input context normalized" do
      assert {:error, %Errors.ParseError{}, %Context{data: %{"seed" => 1}}} =
               Predicator.execute_value("x = @", %{"seed" => 1})
    end

    test "a parser error returns the input context normalized" do
      assert {:error, %Errors.ParseError{}, %Context{data: %{"seed" => 1}}} =
               Predicator.execute_value("x =", %{"seed" => 1})
    end
  end

  describe "execute/2,3 vs execute_value/2,3 - equivalence" do
    @equivalence_programs [
      "x = 1",
      "x = 1; x + 1",
      "1 + 1",
      "x = 1; y = 2",
      "a = 1; a.b = 2; c = 3",
      "x ="
    ]

    test "execute/2 and execute_value/2 agree on context and error for every program" do
      for program <- @equivalence_programs do
        execute_result = Predicator.execute(program, %{})

        value_result =
          case Predicator.execute_value(program, %{}) do
            {:ok, _value, ctx} -> {:ok, ctx}
            {:error, error, ctx} -> {:error, error, ctx}
          end

        assert execute_result == value_result,
               "execute/2 and execute_value/2 disagreed for #{inspect(program)}"
      end
    end
  end
end
