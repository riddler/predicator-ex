### Added

- `Predicator.Simple.operators/1` answers, for one kind of value
  (`:string`, `:number`, `:boolean`, `:date`, `:datetime`, `:duration` or
  `:list`), which operators a picklist row should offer, each with the atom to
  put in a clause, the spelling `to_source/2` renders, a label and an arity.
- `Predicator.Vocabulary`'s operator entries carry four new keys - `:label`,
  `:arity`, `:ast_op` and `:value_kinds` - so an editor's operator control is
  read from the same enumeration the lexer is checked against rather than from
  a second copy of the grammar. `Predicator.Vocabulary.value_kinds/0`
  enumerates the kinds.

### Changed

- `Predicator.Vocabulary.tokens/0` and `operators/0` return entries carrying
  the four operator keys for operator-category lexemes. Entries outside those
  categories are unchanged, and no existing key moved or changed meaning.

### Fixed

- `Predicator.Simple`'s documentation attributed the float-literal exclusion to
  the bead that shipped the module. It is caused by `Predicator.decompile/2`
  raising on a float literal, and now cites that defect (px-ggb) instead.
