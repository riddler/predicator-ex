### Added

- `expr is blank`, `expr is present` and `expr is defined`, each with an optional `not` after `is`, answer `true` or `false` for every value: blank is undefined, null, a string that is empty or holds only Unicode White_Space, an empty list or an empty object; present is not blank; defined is not undefined. The words stay ordinary identifiers everywhere but directly after an operand. They compile to the new `presence` opcode at ISA v7, in a new conformance tier 10, and `Predicator.Vocabulary`, `Predicator.Analysis`, `Predicator.AST` and `Predicator.Simple` know them.

### Changed

- `Predicator.isa_version/0` answers 7. Every ISA v6 instruction list still runs unchanged; a list holding `presence` requires ISA v7.
