### Fixed

- `Predicator.decompile/2` renders a float literal instead of raising, so
  `amount == 1.5` survives parse-then-decompile like any other literal.
