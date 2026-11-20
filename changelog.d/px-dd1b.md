### Fixed

- A string cast to `::datetime` whose instant falls outside `0000-01-01T00:00:00Z` through `9999-12-31T23:59:59.999999Z` once converted to UTC answers `:undefined` instead of raising or answering a year outside that range, and a datetime literal naming such an instant is refused as malformed instead of lexing to text that does not round-trip.
