# ADR-0021: Presence and containment answer a value for every operand

Status: proposed (2026-11-20)

## Context

A condition often needs to ask whether a value was supplied at all, and
predicator has no direct way to say it. A chain of `==` tests does not
serve, because a non-strict comparison involving `:undefined` or `null`
pushes `:undefined` (`docs/isa.md` section 5, the `compare` bullet). `===`
and `!==` work over every value, `:undefined` included (the same bullet),
so `x !== undefined` already answers whether `x` is defined; but a `===`
chain has to name every blank value one by one, and it cannot test a
string that holds only white space without the `trim` builtin, which a
host that runs with `builtins: false` does not have.

Containment has the opposite problem: it refuses where a condition wants an
answer. At ISA v6 the `in` and `contains` opcodes require a list container
and answer a `TypeMismatchError` for any other one (`docs/isa.md` section 5,
the `in` and `contains` bullets; `execute_membership/2` in
`lib/predicator/evaluator.ex` at `330dab6`). So `x contains "a"` with `x`
bound to `null` stops the whole program, even under an `OR` whose other side
is already `false`, and two strings have no substring test at all. `compare`
already takes the other road: a mismatched pair under a non-strict operator
answers `:undefined`, never an error.

Asking whether two lists share a member is the third gap. Today it is a
builtin call or a loop.

Every answer below was ruled by the operator, 2026-11-20. One record covers
all three, because they share one ISA version and one tier, and two records
would each have to cite the other for both.

## Decision

**Three additions, one ISA version.** The presence operators
`expr is [not] blank`, `expr is [not] present` and `expr is [not] defined`
answer `true` or `false` for every value. `in` and `contains` answer a value
for every operand: membership for a list container, a substring test for two
strings, and `:undefined` for every other pairing. A new infix operator,
`a intersects b`, answers whether two lists share a member. ISA v7 holds all
of it and ships in a minor release.

### What blank is

Blank is decided per value kind and does not recurse:

| Value | Blank | Defined |
|---|---|---|
| `:undefined` (an unbound root under the default `on_unbound`, a missing path) | yes | no |
| `null` | yes | yes |
| a string that is empty, or holds only the code points listed below | yes | yes |
| any other string | no | yes |
| a number, `0` and `0.0` included | no | yes |
| a boolean, `false` included | no | yes |
| a list with no members | yes | yes |
| a list with any member (`[""]`, `[null]` and `[[]]` included) | no | yes |
| an object with no keys | yes | yes |
| an object with any key | no | yes |
| a `Date` or a `DateTime` | no | yes |
| a duration, a zero-length one included | no | yes |

`false` and `0` are answers, not absences, so neither is blank.
`x is present` is exactly `x is not blank`. `x is defined` is exactly "x is
not `:undefined`", so `null`, `""` and `[]` are all defined.

The code points a blank string may hold are the Unicode White_Space set,
written out here so that a sibling implements this list rather than its own
language's trim:

- U+0009 through U+000D
- U+0020
- U+0085
- U+00A0
- U+1680
- U+2000 through U+200A
- U+2028
- U+2029
- U+202F
- U+205F
- U+3000

This is the set the `trim` builtin strips (`call_trim/2` in
`lib/predicator/functions/system_functions.ex` at `330dab6`, through Elixir's
`String.trim/1`; checked on Elixir 1.18.3, which strips exactly these 25 code
points). U+200B and U+FEFF are not in it, so a string holding only either is
not blank.

### The presence opcode never errors

The `presence` opcode answers `true` or `false` for every value it pops. The
`load` that puts an unbound root on the stack keeps its own contract: under
the default `on_unbound: :undefined` the root loads `:undefined`, so
`x is blank` is `true` and `x is defined` is `false`; under
`on_unbound: :error` that `load` fails as it does today and the program
answers that error before `presence` runs. Exempting the operand's `load`
would need a second form of `load`, a larger ISA change than this decision.

### Containment

Per pairing, for `needle in container` and `container contains needle`:

| Container | Needle | Answer | Changed from ISA v6 |
|---|---|---|---|
| either operand `:undefined` | | `:undefined` | no |
| a list | any value | `true` when a member equals the needle under `values_equal?/2`, else `false` | no |
| a string | a string | `true` when the needle occurs in the container, else `false` | yes - was a `TypeMismatchError` |
| a string | any other value | `:undefined` | yes - was a `TypeMismatchError` |
| `null`, a number, a boolean, a `Date`, a `DateTime`, a duration or an object | any value | `:undefined` | yes - was a `TypeMismatchError` |

The substring test is case-sensitive, by code point, with no normalization
and no locale, and the empty string occurs in every string. A list container
is unchanged: a string member is matched whole, never as a substring. `in`
stays the mirror of `contains`. Containment becomes total, as `compare`
already is, and the `TypeMismatchError` for `in` and `contains` is no longer
produced. Object containment is deliberately given no meaning here: an
object container answers `:undefined`.

The arithmetic opcodes keep rejecting a wrong-typed operand with a
`TypeMismatchError`. Making containment total changes no other opcode.

### What intersects answers

| Left | Right | Answer |
|---|---|---|
| either operand `:undefined` | | `:undefined` |
| a list | a list | `true` when some member of the left equals some member of the right under `values_equal?/2`, else `false` |
| any other pairing (a string, a number, a boolean, `null`, a `Date`, a `DateTime`, a duration or an object on either side) | | `:undefined` |

An empty list on either side answers `false`. `values_equal?/2`
(`lib/predicator/evaluator.ex` at `330dab6`) is the equality `in` already
uses: type-matched, dates and datetimes by instant, `null` equal to itself,
and `:undefined` equal to nothing.

### The words are read by position

`is`, `blank`, `present`, `defined` and `intersects` become operator words
only directly after a complete operand inside an expression, where no
program that parses today has an identifier; a statement that begins after
a block's closing brace is not such a position. Everywhere else they stay
ordinary identifiers, so none of them is a reserved word and no program that
parses today changes meaning. Each is accepted in lower case and in upper
case, as `in` and `IN` are.

`is [not] (blank | present | defined)` and `intersects` sit at the
precedence of the comparison operators, beside `in` and `contains`, and do
not chain: `a is blank is blank` is a parse error, and
`(a is blank) == true` parses. `not x is blank` parses as
`not (x is blank)`. The AST node for the presence operators is
`{:presence, kind, negated?, expr, pos}`, and the decompiler prints the
spelling the author wrote.

### The opcodes

| Opcode | Operands | Pops | Pushes | ISA | Tier |
|---|---|---|---|---|---|
| `presence` | `"blank"` or `"defined"` (string) | 1 | 1 (a boolean) | v7 | 10 |
| `intersects` | - | 2 | 1 | v7 | 10 |

After its operand, each spelling compiles to:

| Spelling | Instructions |
|---|---|
| `x is blank` | `["presence", "blank"]` |
| `x is not blank` | `["presence", "blank"]`, `["not"]` |
| `x is present` | `["presence", "blank"]`, `["not"]` |
| `x is not present` | `["presence", "blank"]` |
| `x is defined` | `["presence", "defined"]` |
| `x is not defined` | `["presence", "defined"]`, `["not"]` |

`presence` always pushes a boolean, so the `not` after it never rejects.
`a intersects b` compiles its two operands, left first, followed by
`["intersects"]`.

### One version, a minor release

ISA v7 holds `presence`, `intersects`, and the widened `in` and `contains`.
The widening needs no new name because `docs/isa.md` section 1
("Versioning", at `330dab6`) says so: "Adding an operand form or widening an
accepted type is a new version but not a new name." The same section's rule
for an additive version, "An additive version - new opcodes only, every
existing instruction list still valid - ships in a minor release", governs
the release: every v6 instruction list stays valid at v7, and the only
answers that change are errors becoming values. `Predicator.isa_version/0`
answers 7 in the release that ships it.

### Tier 10

Both new opcodes go in a new tier 10, so tiers 1 through 9 keep the opcode
sets `docs/isa.md` section 4 ("Tiers", at `330dab6`) gives them, and a
sibling's claim to pass tier 9 keeps its meaning while the sibling lags
([ADR-0003](0003-the-elixir-implementation-leads-the-isa.md)). The widened
`in` and `contains` stay in tier 3.

### A corpus case whose answer changes gets a new id

A conformance case whose expected answer this decision changes - an `in` or
`contains` case that expects a `TypeMismatchError` - is removed, and the
case with the new answer is added under a new id. No case is edited in
place. Case ids are "stable forever" (`conformance/schema/case.json`, the
`id` property, at `330dab6`), and `conformance/RATCHET.md` matches a
sibling's entry to the corpus on `(case_id, surface)`; an id edited in place
would let a sibling's entry go on claiming an answer the sibling never
verified, while a removed id is caught the next time the sibling vendors the
corpus.

### Alternatives turned down

- **Functions** (`blank(x)`, `intersects(a, b)`). A host that runs with
  `builtins: false` has none of them. An operator works there, reads like
  its siblings `in` and `contains`, and is in the vocabulary an editor
  completes from.
- **Reserved words.** Reserving `is`, `blank`, `present`, `defined` or
  `intersects` breaks every program that uses one as a variable name; that is
  a major release for no gain over reading them by position.
- **A major release.** Every answer that changes was an error before, and a
  major would move every `~> 9.x` requirement in the family for it.
- **Keeping the error for wrong shapes**, and adding only the two-string
  test. A condition over a `null` or a scalar would still stop the program
  under an `OR` whose other side has answered.
- **`false` as blank**, or blank recursing into lists and objects. A "no"
  would read as unanswered, and recursion is costly to state and surprising
  to read.
- **Three presence opcodes, or three operands.** More ISA for no new answer:
  `not` already supplies every negation.
- **`presence` in tier 1 and `intersects` in tier 3.** Tidier by topic, but
  every sibling's tier claim would stop being true the day it vendored the
  corpus, with no lag possible.

## Consequences

- **Answers change, in a minor release.** A host that called `in` or
  `contains` on a container other than a list now gets a boolean or
  `:undefined` where it got a `TypeMismatchError`. The changelog carries this
  under Changed, with an upgrading note.
- **The corpus moves.** New cases for the presence operators and
  `intersects` go in tier 10; new containment cases go in tier 3; each case
  whose answer changes is replaced under a new id. The manifest's
  `corpus_hash` and its ISA version move, and each sibling vendors the new
  corpus at the tag.
- **Siblings lag by tier.** A sibling at ISA v6 keeps every tier 1 through 9
  claim it has, except the tier 3 cases that are replaced under new ids,
  which its registry no longer matches until it implements the widening.
- **No status line moves here.** This record stays proposed until the code
  it decides ships in a published version.
