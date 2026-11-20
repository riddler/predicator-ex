### Added

- `in` and `contains` on two strings are a substring test: `"cd" in "abcdef"` and `"abcdef" contains "cd"` answer `true`. The test is case-sensitive and by code point, with no normalization, and the empty string is contained in every string; a string inside a list is still matched whole.
- `a intersects b` answers `true` when the two lists share a member under the equality `in` uses, `false` otherwise (an empty list on either side included), and `:undefined` for an `:undefined` operand or an operand that is not a list. `intersects` is read as an operator only directly after an operand, so it stays an ordinary identifier everywhere else, and it is accepted in lower and upper case. It compiles to the new `intersects` opcode at ISA v7, in conformance tier 10, and `Predicator.Vocabulary`, `Predicator.Analysis`, `Predicator.AST` and `Predicator.Simple` know it.

### Changed

- `in` and `contains` no longer produce a `TypeMismatchError`. A `null`, number, boolean, date, datetime, duration or object container, or a string container with a needle that is not a string, answers `:undefined` where 9.5.x answered `TypeMismatchError` (operation `in` or `contains`, expected `list`); a list container and an `:undefined` operand answer as before. Upgrading: code that matched that `TypeMismatchError` to detect a container that is not a list now receives `:undefined`, or `true` or `false` for two strings, and the program goes on running, so an `OR` whose other side answers is no longer stopped by it.
