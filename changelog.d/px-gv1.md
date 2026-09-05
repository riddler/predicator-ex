### Added

- `Predicator.Simple` admits float literals. `card.amount >= 19.99` is now
  inside the picklist-renderable subset: `from_ast/1` and `from_source/1`
  read a non-negative float as the new `{:float, value}` scalar, and
  `to_ast/1` and `to_source/2` round-trip it under both laws. The exclusion
  was contingent on `Predicator.decompile/2` raising on a float, which
  px-ggb fixed.

  A float is **not** a new `Predicator.Vocabulary.value_kind/0`. Integers
  and floats are both `:number`, so `Predicator.Simple.operators/1` offers
  the same operators for either and an editor needs no new branch. A
  negative float stays outside, exactly as a negative integer does: the
  parser reads `-19.99` as a `unary` node, not as a literal.
