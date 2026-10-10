### Changed

- Ordering two lists, or two maps, now compares two date members, or two datetime members, by instant, as a top-level pair does: `[#2026-01-02#] > [#2025-12-31#]` is `true` where it was `false`; a pair at the same instant steps to the next member, and equality, membership and mixed date and datetime members keep their answers. The conformance corpus gains five `dates/` member cases, tier 1 moves from 65 to 70 cases, and the corpus hash advances from `sha256:bb60ec82...` to `sha256:ddc5cf82...`, so a sibling re-vendors at this release.
