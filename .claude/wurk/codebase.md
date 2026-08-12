# Project orientation: predicator-ex

A secure, non-evaluative condition engine: user-authored boolean predicates
compile to a flat instruction list run by a stack VM, with no `eval` anywhere.

## Layout

- `lib/predicator.ex` - the public façade.
- Pipeline and shared types, one file each: `lib/predicator/lexer.ex`,
  `lib/predicator/parser.ex`, `lib/predicator/types.ex`,
  `lib/predicator/compiler.ex`, `lib/predicator/evaluator.ex`,
  `lib/predicator/duration.ex`, `lib/predicator/context.ex`,
  `lib/predicator/context_location.ex`, `lib/predicator/cast.ex`,
  `lib/predicator/compiled.ex`, `lib/predicator/instructions.ex`,
  `lib/predicator/undefined.ex`, `lib/predicator/visitor.ex`.
- `lib/predicator/errors/` - five error structs:
  `lib/predicator/errors/evaluation_error.ex`,
  `lib/predicator/errors/location_error.ex`,
  `lib/predicator/errors/parse_error.ex`,
  `lib/predicator/errors/type_mismatch_error.ex`,
  `lib/predicator/errors/undefined_variable_error.ex`.
- `lib/predicator/functions/` - four builtin providers plus the behaviour:
  `lib/predicator/functions/date_functions.ex`,
  `lib/predicator/functions/json_functions.ex`,
  `lib/predicator/functions/math_functions.ex`,
  `lib/predicator/functions/system_functions.ex`,
  `lib/predicator/functions/provider.ex`.
- `lib/predicator/visitors/` - `lib/predicator/visitors/instructions_visitor.ex`,
  `lib/predicator/visitors/string_visitor.ex`.
- `lib/predicator/conformance/` and `lib/mix/tasks/corpus.generate.ex`,
  `lib/mix/tasks/corpus.coverage.ex` - the corpus tooling.
- `conformance/` - `conformance/cases/` is authored source;
  `conformance/corpus/` and `conformance/manifest.json` are **generated** by
  `mix corpus.generate`; plus `conformance/schema/`, `conformance/examples/`,
  `conformance/RATCHET.md`.

## Suites

One ExUnit suite under `test/`, 82 files, mirroring `lib/`: `test/predicator/**`
for unit tests, `test/predicator/integration/**` for end-to-end
`Predicator.evaluate/3` and `execute/2` cases, `test/predicator/conformance/**`
and `test/mix/tasks/**` for the corpus tooling. `test/predicator/isa_sync_test.exs`
and `test/predicator/conformance/corpus_freshness_test.exs` are binding tests -
they tie an exported artifact to its source and carry a sabotage note.

## The pipeline

```
source -> lexer -> parser -> AST -> compiler / InstructionsVisitor
  -> flat instruction list -> stack VM evaluator
```

Plus the round-trip path: `AST -> StringVisitor -> source`.

## Module families worth mining

The five error structs share one shape. The four function-provider modules
all implement the one-callback `Predicator.FunctionProvider` behaviour. The
two visitors both implement `Predicator.Visitor`. Any one member of a family
is the template for a new one.

## Terms of art

opcode, instruction list, ISA, corpus, conformance, ratchet, visitor,
provider, precedence, short-circuit, duration, span, `on_unbound`,
sentinel/`:undefined`, statement mode vs expression mode.

Best search keys: opcode names (`lit`, `load`, `compare`, `object_new`,
`jump_if_false`, `store`, `pop`, `cast`), `docs/isa.md` section numbers, AST
node tags.

## Reading rules

1. `docs/isa.md` is the authority for any instruction-set question. Describe
   an opcode's behavior against its ISA section rather than inferring intent
   from the evaluator clause that implements it.
2. Errors are values: `{:ok, result} | {:error, struct}`, never raised at a
   leaf (ADR-0004). Do not describe an error path as an exception path.
3. `conformance/corpus/*.json` and `conformance/manifest.json` are generated
   by `mix corpus.generate`; the authored source is `conformance/cases/*.json`.
   Never treat a generated file as the definition site.
4. Credo complexity suppressions in the lexer and parser are deliberate and
   carry explanatory comments; they are not findings.
