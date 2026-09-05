### Fixed

- The string writer escapes a backslash inside a quoted object key, in both
  quote styles, so `{'a\b': 1}` survives parse-then-decompile instead of
  rendering source that parses back to a different key - or, for a key ending
  in a backslash, source that does not parse at all. Quoted keys now go
  through the same escaping helper as string literals rather than a second
  copy of it.
