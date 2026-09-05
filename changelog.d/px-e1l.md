### Added

- `Predicator.Simple.value_kind/1` maps a subset value to the
  `Predicator.Vocabulary.value_kind/0` that governs it, so a structured editor
  composes it with `operators/1` instead of keeping its own translation from
  scalar tags to kinds. A relative date answers `:datetime`, since `30d ago`
  is a point in time by the time anything compares it.
