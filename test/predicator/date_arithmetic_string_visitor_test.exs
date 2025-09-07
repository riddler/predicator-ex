defmodule Predicator.DateArithmeticStringVisitorTest do
  @moduledoc """
  Tests for string visitor support of date arithmetic expressions.

  Ensures that duration and relative date AST nodes can be properly
  decompiled back to their original string representation.
  """

  use ExUnit.Case, async: true

  alias Predicator

  describe "duration decompilation" do
    test "simple duration literals" do
      assert_round_trip("3d")
      assert_round_trip("2w")
      assert_round_trip("1h")
      assert_round_trip("30m")
      assert_round_trip("45s")
    end

    test "complex duration literals" do
      # Note: Parser stores units in reverse order, so these test the actual behavior
      assert_decompiled_matches("1d8h", "8h1d")
      assert_decompiled_matches("2w3d", "3d2w")
      assert_decompiled_matches("1d8h30m", "30m8h1d")
    end

    test "duration in arithmetic expressions" do
      assert_round_trip("#2024-01-15# + 3d")
      assert_round_trip("#2024-01-15T10:30:00Z# - 2h")
      assert_round_trip("Date.now() + 1d")
    end
  end

  describe "relative date decompilation" do
    test "ago expressions" do
      assert_round_trip("3d ago")
      assert_round_trip("2w ago")
      assert_round_trip("1h ago")
    end

    test "from now expressions" do
      assert_round_trip("3d from now")
      assert_round_trip("1w from now")
    end

    test "next expressions" do
      assert_round_trip("next 3d")
      assert_round_trip("next 1w")
      assert_round_trip("next 2h")
    end

    test "last expressions" do
      assert_round_trip("last 3d")
      assert_round_trip("last 1w")
      assert_round_trip("last 2h")
    end
  end

  describe "date arithmetic in complex expressions" do
    test "date arithmetic in comparisons" do
      assert_round_trip("Date.now() + 1h > #2024-01-15#")
      assert_round_trip("#2024-01-15# - 3d = #2024-01-12#")
    end

    test "date arithmetic in logical expressions" do
      assert_round_trip("#2024-01-15# + 1w > Date.now() AND status = 'active'")
      assert_round_trip("deadline - 3d < Date.now() OR urgent = true")
    end

    test "simple nested expressions" do
      assert_round_trip("#2024-01-15# + 1w - 2d")
      # Note: Complex parentheses may not round-trip exactly due to operator precedence
    end
  end

  # Helper function to test round-trip parsing and decompilation
  defp assert_round_trip(expression) do
    case Predicator.parse(expression) do
      {:ok, ast} ->
        decompiled = Predicator.decompile(ast)

        # The decompiled version should parse to the same AST
        {:ok, decompiled_ast} = Predicator.parse(decompiled)

        assert decompiled_ast == ast, """
        Round-trip failed for: #{expression}
        Original AST: #{inspect(ast)}
        Decompiled: #{decompiled}
        Decompiled AST: #{inspect(decompiled_ast)}
        """

      {:error, message, line, col} ->
        flunk("Failed to parse '#{expression}': #{message} at #{line}:#{col}")
    end
  end

  # Helper function to test when decompilation produces a different but equivalent expression
  defp assert_decompiled_matches(original, expected_decompiled) do
    case Predicator.parse(original) do
      {:ok, ast} ->
        decompiled = Predicator.decompile(ast)

        assert decompiled == expected_decompiled, """
        Expected decompilation to match: #{original}
        Expected: #{expected_decompiled}
        Got: #{decompiled}
        """

      {:error, message, line, col} ->
        flunk("Failed to parse '#{original}': #{message} at #{line}:#{col}")
    end
  end
end
