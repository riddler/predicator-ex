defmodule Predicator.InstructionError do
  @type t :: %__MODULE__{
    error: String.t(),
    instructions: list(),
    predicate: String.t(),
    instruction_pointer: non_neg_integer()
  }

  defstruct [
    error: "Non valid predicate instruction",
    instructions: nil,
    predicate: nil,
    instruction_pointer: nil
  ]
end
