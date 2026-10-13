### Added

- `Predicator.AST.prewalk/3`, `postwalk/3` and `reduce/3` walk a parsed expression, statement or program in `Macro`'s shape, threading an accumulator, visiting children in source order and leaving each node's position untouched.
