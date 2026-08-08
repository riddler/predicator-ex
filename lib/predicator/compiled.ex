defmodule Predicator.Compiled do
  @moduledoc """
  A compiled program and its source-location table, as one value.

  Returned by `Predicator.compile_with_positions/1` and
  `Predicator.compile_with_spans/1`, and accepted directly by
  `Predicator.evaluate/3`, which threads the table itself - so the table cannot
  be dropped between compilation and evaluation (ADR-0009).

  ## What to store

  This struct is an in-memory Elixir value and is **not** a wire format. A
  consumer that persists a compiled program stores `compiled.instructions` - a
  bare JSON array, byte-identical to what `Predicator.compile/1` emits for the
  same source. Do not serialize the struct: `positions` and `segment_positions`
  both hold offsets into the source string the program was compiled from, and
  they are meaningless to anything that does not also hold that string.
  `segment_positions` is a second Elixir-side derived table, present for the
  same reason and with the same storage advice as `positions` - it is empty
  for a program compiling no assignment. An expression compiles no `store`, so
  `compile_with_positions/1` and `compile_with_spans/1` always return an empty
  one; `compile_program_with_positions/1` populates it whenever the program
  contains an assignment.

  A program loaded back from storage as a bare list evaluates fine and reports
  `position: nil` on runtime errors, which is correct - the source is gone.

  A consumer that wants positions back after a round trip should persist the
  *source*, not the table, and recompile with `compile_with_positions/1` (or
  `compile_with_spans/1`) on load - recompiling the same source is
  deterministic and yields an identical table every time. The table itself is
  a derived fact, the same reasoning ADR-0009 already applied to reject an
  `isa_version` field: a cached copy of a derived fact can disagree with the
  thing it claims to describe. Nothing checks that a `positions` table
  actually came from the `instructions` list it is attached to, so a table
  compiled from one source and attached to another source's instructions
  produces no error - just a confidently wrong position, which is worse than
  the honest `position: nil` an unpaired instruction list reports.

  ## Examples

      iex> compiled = Predicator.Compiled.new(
      ...>   [["load", "score"], ["lit", 85], ["compare", "GT"]],
      ...>   %{0 => {1, 1}, 1 => {1, 9}, 2 => {1, 7}}
      ...> )
      iex> compiled.instructions
      [["load", "score"], ["lit", 85], ["compare", "GT"]]
      iex> compiled.positions
      %{0 => {1, 1}, 1 => {1, 9}, 2 => {1, 7}}

  Recompiling the same source is deterministic, which is what makes
  "persist the source, recompile on load" a sound way to get positions back:

      iex> {:ok, first} = Predicator.compile_with_positions("score > 85")
      iex> {:ok, second} = Predicator.compile_with_positions("score > 85")
      iex> first == second
      true
  """

  alias Predicator.Types

  @typedoc """
  A compiled program paired with the source-location table for its
  instructions.

  `positions` is a `t:Predicator.Types.position_table/0` under
  `Predicator.compile_with_positions/1` and a
  `t:Predicator.Types.span_table/0` under `Predicator.compile_with_spans/1`.
  One field, not two: nothing below the façade distinguishes them -
  `Predicator.Evaluator` reads either without knowing which, and
  `Predicator.Errors.put_position/2` discriminates a `nil`, a point, and a span
  at the point of use.

  The struct deliberately carries no ISA version: it is computable from the
  instruction list by `Predicator.Instructions.required_isa/1`, and a stored
  copy of a derived fact can disagree with the list it claims to describe
  (ADR-0003, ADR-0009).

  `segment_positions` is a **new** field (px-ids), added rather than folded
  into `positions`: ADR-0009 treats adding a field to this struct as additive
  and reshaping `positions`'s meaning as not, so the per-store segment table
  gets its own field rather than changing what `positions` holds.
  """
  @type t :: %__MODULE__{
          instructions: Types.instruction_list(),
          positions: Types.position_table() | Types.span_table(),
          segment_positions: Types.segment_position_table()
        }

  defstruct instructions: [], positions: %{}, segment_positions: %{}

  @doc """
  Pairs an instruction list with a source-location table and, optionally, a
  segment-position table.

  For a caller who stored a bare instruction list and kept its tables
  separately - `Predicator.compile_with_positions/1`,
  `Predicator.compile_with_spans/1`, and `Predicator.compile_program_with_positions/1`
  build the struct themselves.

  ## Examples

      iex> compiled = Predicator.Compiled.new([["lit", 42]], %{0 => {1, 1}})
      iex> compiled.positions
      %{0 => {1, 1}}
      iex> compiled.segment_positions
      %{}

      iex> Predicator.Compiled.new([["lit", 42]]).positions
      %{}

      iex> compiled = Predicator.Compiled.new(
      ...>   [["lit", "a"], ["lit", "b"], ["lit", 1], ["store", 2]],
      ...>   %{0 => {1, 1}, 1 => {1, 2}, 2 => {1, 7}, 3 => {1, 1}},
      ...>   %{3 => [{1, 1}, {1, 2}]}
      ...> )
      iex> compiled.segment_positions
      %{3 => [{1, 1}, {1, 2}]}
  """
  @spec new(
          Types.instruction_list(),
          Types.position_table() | Types.span_table(),
          Types.segment_position_table()
        ) :: t()
  def new(instructions, positions \\ %{}, segment_positions \\ %{})
      when is_list(instructions) and is_map(positions) and is_map(segment_positions) do
    %__MODULE__{
      instructions: instructions,
      positions: positions,
      segment_positions: segment_positions
    }
  end
end
