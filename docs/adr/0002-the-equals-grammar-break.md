# ADR-0002: The `=` grammar break (4.0)

Status: accepted (2026-08-03)

## Context

Predicator has used `=` for equality since 1.0.0 (2025-08-19), matching SQL and
BASIC rather than the C-family languages most document authors actually know.
ADR-0001 opened a 3.6-4.0 arc around statifier's six upstream seams; seam 4 -
a safe statement layer over the existing expression language, so SCXML `assign`
gets a real target without `eval` - needs `=` for assignment. Predicator has no
spare punctuation for that: every other candidate (`:=`, `<-`) is unfamiliar to
the same audience `=`-as-equality was chosen for, and reusing `=` is only a
problem because `=` already means something else.

Two designs were on the table for resolving the collision, reviewed 2026-08-03
alongside ADR-0001 (decision 2 of that review).

**Position-dependent dual meaning.** `=` means equality in expression position
and assignment in statement position, disambiguated by where the parser is.
This keeps every existing `=` predicate parsing unchanged and costs no
migration at all. It was rejected because it makes `=` mean two different
things depending on context the document author is not necessarily tracking -
exactly the ambiguity `==`-only languages exist to avoid, and precisely the
kind of subtlety this library's own design gets credit for keeping out of user-
authored expressions. A rule string copy-pasted from a guard into a script body
would silently change meaning.

**Per-caller grammar config.** A parser option lets each caller pick the old or
new dialect, so existing integrations opt out indefinitely. Rejected: two
dialects of stored, user-authored rule strings is a support burden forever, for
a migration that is one loud parse error deep. Every stored predicate is either
already `==`-clean or trips the 3.8 warning and gets fixed; there is no
long-tail of documents that config would actually be protecting.

**Known-consumer survey.** Predicator's Hex usage base is small - about a year
old, one version line, and statifier is the only known consumer outside this
repo's own suite. statifier's W3C conformance corpus emitter already treats `=`
as foreign: `conf_predicator.xsl` rewrites every conformance-suite equality
(`$op='='` in the numeric-comparison template, `tools/corpus/scxml_w3/
conf_predicator.xsl`) to `==` before the SCXML documents it generates are ever
parsed by predicator, specifically because ECMAScript-style `==` is what the
corpus's own `cond` and `expr` attributes need. Statifier's generated documents
were never a source of expression-position `=`, so the break costs its main
consumer nothing beyond confirming this ADR's assumption.

## Decision

**`=` is removed from expression position entirely and reused for assignment,
valid only in statement position.** `==` and `===` remain the only equality
operators. There is one grammar, not two selected by position or by config:
`status = 'active'` is a parse error in 4.0, full stop, and `Var1 = Var2 + 1`
in a statement is assignment, full stop.

The uniform rule was chosen over the position-dependent alternative because it
matches every mainstream language a document author already knows - JavaScript,
Python, Ruby, Elixir's own `=` (pattern match, not equality, which is its own
argument against overloading it further) - none of them make `=` mean two
different things by position. One rule an author can state in a sentence beats
a rule that requires knowing which production they are inside.

The 3.8.0 deprecation warning (`px-8um.5`) is the migration story and the
entire notice period: parsing an expression-position `=` logs once, names
`==`, and gives consumers exactly one release to migrate before 4.0 turns the
same input into a parse error. No grace period beyond that one release was
designed in - the known-consumer survey above is what makes a single release
of notice sufficient rather than reckless.

## Consequences

- Shipping the statement layer (`px-tbv.1`, `px-tbv.2`) in the same release as
  the break is what makes taking the break worth it: `=` becomes assignment the
  same version it stops being available for anything else, so there is no
  window where `=` is reserved but unused.
- The instruction set is unaffected. `=` and `==` already both compiled to
  `["compare", "EQ"]` before this decision and continue to; the break is
  surface grammar only, so compiled artifacts and cross-language interchange
  (ADR-0001) are untouched.
- The Ruby and JavaScript siblings do not adopt this rule automatically. Their
  lexers still tokenize `=` as equality (see "The `=` grammar break (4.0)" in
  `docs/architecture.md`), so a rule string using `=` for equality parses in
  Ruby and JavaScript and fails to parse in Elixir on 4.0 - a documented,
  deliberate surface-syntax divergence until the siblings adopt the same break
  on their own schedule (`px-tbv.4`).
- A consumer who ignored or suppressed the 3.8 warning
  (`config :predicator, deprecation_warnings: false`) gets no further notice;
  4.0 simply stops parsing their expression-position `=`. That is the intended
  cost of suppressing the warning, not an oversight.
- Reopening position-dependent `=` or a per-caller grammar option means
  superseding this ADR, not adding a flag beside it.
