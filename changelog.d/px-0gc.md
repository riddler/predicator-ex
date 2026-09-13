### Fixed

- A string literal keeps its non-ASCII characters: `"café"` and `"✓"` evaluate
  to themselves instead of to one truncated byte per codepoint.
- A `\u` escape in a string literal is refused with an error naming it, instead
  of silently decoding to the bare letter; predicator has no numeric escape, so
  the character is written directly.
