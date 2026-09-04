### Added

- `Predicator.Simple` names the subset of the language a picklist-style editor
  can render - clauses joined by one connective - and reads it out of an AST or
  source with `from_ast/1` and `from_source/1`, which answer `:outside` for a
  valid expression outside the subset rather than treating it as an error.
- `Predicator.Simple.to_ast/1` and `to_source/2` write a subset value back, so
  an expression can be handed to a form and the edited value rendered to source
  the author recognises; `to_source/2` takes `Predicator.decompile/2`'s
  formatting options.
