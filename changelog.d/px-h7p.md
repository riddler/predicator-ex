### Fixed

- An invalid date literal's error message keeps its non-ASCII characters:
  `#2024-01-1é#` reports the character instead of one truncated byte, so the
  message a host reads is valid UTF-8.
