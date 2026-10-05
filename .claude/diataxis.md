---
# The docs manifest the documentation tools read. Generated from the family's manifest
# table: change a key there and regenerate. The two prose lines below may be sharpened.
product: predicator
family: statifier
audience: Elixir developers who let users or configuration express conditions
tone: "plain, second person, no marketing"
terminology:
  use:
    - execution
    - chart
    - document
    - revision
  avoid:
    - "run (noun)"
    - workflow instance
example_world: library-loan
docs_root: docs
quadrants:
  tutorials: docs/tutorials
  how_to: docs/guides
  reference: docs/reference
  explanation: docs/explanation
readme: README.md
reference_generator: ex_doc
publish: hexdocs
contributor_paths:
  - docs/adr
  - docs/plans
  - docs/spikes
  - docs/research
  - docs/design
  - docs/measurements
  - CLAUDE.md
executed_snippets:
  - test/docs_examples_test.exs
  - test/docs_adr_links_test.exs
readme_max_lines: 250
---

A small, safe predicate language: parse a rule, evaluate it against a context, in Elixir.
Examples are written in the library loan: a copy of a book lent to a patron, due, renewed, returned or lost.
