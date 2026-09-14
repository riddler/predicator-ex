### Fixed

- A `\U` escape in a string literal is refused with the same error as `\u`:
  `"caf\U00e9"` no longer lexes silently to `cafU00e9`.
