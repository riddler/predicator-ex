### Fixed

- The string writer escapes a backslash inside a string literal, in both
  quote styles, so a value containing one survives parse-then-decompile
  instead of rendering source that parses back differently - or, for a value
  of a single backslash, source that does not parse at all. The quote style
  asked for is still the style that comes back.
