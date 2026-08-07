---
name: create-issue
description: Create beads (bd) issues with type, priority, labels, and dependency links
argument-hint: ["issue title or description"]
---

# Create Issue (beads)

Create a new issue in the beads (`bd`) tracker. All task tracking in this project
is beads - no GitHub issues, no markdown TODO lists (see CLAUDE.md).

## Gather the details

From `$ARGUMENTS` if provided; otherwise ask the user for:

- **Title** - short, imperative (e.g. "Add a len() function for strings and lists")
- **Description** - context, acceptance criteria, relevant file paths or grammar rules
- **Type** - task, bug, feature, epic, or chore
- **Priority** - 0 (urgent) through 3 (low); default 2 if the user has no preference
- **Related work** (optional) - existing issue IDs this blocks, depends on, or was
  discovered from

Infer type and priority from the description when they are obvious; only ask about
what is genuinely ambiguous. Do not interrogate the user field by field.

## Create the issue

Full form:

```bash
bd create "Title here" --type task --priority 2 --description "Longer context..." \
  --acceptance "What has to be true for this to be done"
```

Quick capture (when the user just wants it recorded fast, e.g. mid-task discovered
work):

```bash
bd q "Title here"
```

Check `bd create --help` if unsure of exact flag names in the installed version.

## Link dependencies

When the user names related work, link it:

```bash
bd link <new-id> --depends-on <other-id>
bd link <new-id> --discovered-from <other-id>
```

Use `discovered-from` for work found mid-task; use dependency links so `bd ready`
reflects the real build order (lexer before parser, parser before compiler, and so
on). Epics mirror the roadmap arcs - if the new issue belongs to an epic, link it
as a child.

## Apply labels

- Add at least one **`area:`** label to every issue that will change files in this
  repo - `area:lexer-parser`, `area:evaluator`, `area:context`, `area:functions`,
  `area:visitors`, `area:api`, `area:conformance`, `area:skills`, `area:docs`,
  `area:build`. The vocabulary and the paths each covers are in
  [CLAUDE.md](../../../CLAUDE.md#area-labels). This is not a topical tag: it is
  what lets a batch picker tell whether two issues collide, so label by the paths
  in the acceptance criteria, not by subject matter.

  Three that come up constantly:
  - **`area:build`** covers `mix.exs`, `mix.lock`, `.quality.exs`, `.credo.exs`,
    `coveralls.json`, `mise.toml`, `.gitignore`, and `.github/**`. It is
    exclusive - a bead carrying it batches with nothing and lands on `main`
    alone.
  - **`area:api`** covers `lib/predicator.ex` and the error structs. A bead that
    adds a function *and* exposes it carries both `area:functions` and
    `area:api`, which is correct: it does touch both.
  - **`area:conformance`** covers the corpus subtree - `conformance/**`,
    `lib/predicator/conformance/**`, `lib/mix/tasks/corpus.*.ex`, and their
    tests. It is *not* `area:build`: regenerating or extending the corpus
    touches no build file. A conformance bead that does edit `mix.exs` or
    `coveralls.json` carries both labels and lands alone, like any other.
- Add topical labels the user mentions (e.g. `tooling`, `workflow`, `quality`).
- Add the **`upstream`** label when the issue's work happens in the Ruby or
  JavaScript sibling implementation or in a downstream consumer rather than here,
  so it can be swept into their trackers later. An `upstream` issue changes no
  files here, so it takes no `area:` label. **A change to the instruction set is
  not automatically `upstream`** - the Elixir side of it is real work in this
  repo (ADR-0003); file the sibling-side adoption as its own `upstream` bead if
  it needs tracking; it is never a dependency of the Elixir work (ADR-0003).

```bash
bd update <id> --add-label area:lexer-parser --add-label area:api
```

## Report back

Print the created issue ID and title, e.g.:

```
Created px-b57: Add a len() function for strings and lists (task, p2)
Linked: depends-on px-a42; labeled: area:functions, area:api
```

Do not commit, push, or sync the beads database unless explicitly asked.
