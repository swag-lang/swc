# Backlog

Everything this repository intends to do, and everything it has observed and not yet explained.
Two kinds of file, two different jobs. Write to the right one.

- **`todo.<unit>.md` holds intent**: what a unit should become, and in which order. Entries are
  ordered by decreasing value, not by decreasing effort, and are measured against what the unit
  competes with.
- **`findings.<area>.md` holds evidence**: something observed, with a reproduction and a next
  investigation step. An entry is a lead worth preserving, not a commitment to implement it.

Both hold only what is *not done*. When a task resolves, invalidates, or completes the
investigation of an entry, delete that entry — or cut it down to the part that genuinely remains.
Never keep done or investigated material as a record: history lives in git. A finding that
graduates into a plan moves to the matching `todo.*` file and disappears from the `findings.*` one.

## Intent

| File | Unit |
| --- | --- |
| [todo.compiler.md](todo.compiler.md) | `swc` itself: frontend, backend, incrementality, speed, memory, and what sits around it |
| [todo.language.md](todo.language.md) | The Swag language and its syntax — design questions open by choice |
| [todo.doc.md](todo.doc.md) | The `doc` command |
| [todo.format.md](todo.format.md) | The `format` command |
| [todo.runtime.md](todo.runtime.md) | `bin/runtime`, and the allocator in particular |
| [todo.core.md](todo.core.md) | `std/core` |
| [todo.gui.md](todo.gui.md) | `std/gui` |
| [todo.pixel.md](todo.pixel.md) | `std/pixel` |
| [todo.audio.md](todo.audio.md) | `std/audio` |
| [todo.truetype.md](todo.truetype.md) | `std/truetype` |
| [todo.scapture.md](todo.scapture.md) | The sCapture application |
| [todo.scrypt.md](todo.scrypt.md) | The sCrypt application |

## Evidence

| File | Area |
| --- | --- |
| [findings.compiler.md](findings.compiler.md) | Frontend, semantic analysis, and code generation defects |
| [findings.optimization.md](findings.optimization.md) | Backend optimization passes, register allocation, and generated-code performance |
| [findings.safety.md](findings.safety.md) | Borrow, lifetime, and sanity analysis |
| [findings.gui.md](findings.gui.md) | `std/gui` and the applications built on it |
| [findings.tooling.md](findings.tooling.md) | The build, the sandbox, and the test harness |

Put an entry in the file whose area it will be *fixed* in, not the one it was noticed from. Create
a new file only when a real cluster forms — a category holding one entry costs more to navigate
than it saves.

## Number Every Finding

Every finding carries a permanent identifier in its heading:

```
### F-023 — A menu bar does not follow a live language switch
```

The identifier is how a finding is named everywhere else — in conversation, in a commit message, in
a `todo.*` entry, in a code comment. A title gets rewritten, a position moves, and an entry changes
file; the identifier does not.

Next identifier: F-041

- Take the next identifier from the line above, then advance it. It is the counter, not the entry
  count: it keeps rising as entries are deleted, and it is shared by every `findings.*` file.
- Never renumber and never reuse. A deleted entry takes its identifier with it, so `F-012` in an
  old commit message still means what it meant.
- Keep each file sorted by identifier, ascending. A new entry always carries the highest identifier
  of its file, so it goes at the end; a deleted one leaves a gap, and the gap stays. Position is
  mechanical and carries no priority — it only makes an entry findable by its number.

## Write A Finding

Search the `findings.*` files before adding an entry: enrich an existing item instead of creating a
duplicate. Add an entry when the issue needs separate investigation, broader design work, or
stronger evidence; fix it immediately instead when it is sufficiently understood, relevant to the
current task, and safe to validate.

Use this compact format. Keep observations factual and make the next step actionable.

```
### F-000 — Short descriptive title

- Area: compiler | bin/std | language | tooling | documentation
- Found while: task, test, or file that exposed the issue
- Observation: awkward behavior, suspected defect, or optimization opportunity
- Evidence: reproduction, relevant paths, measurements, or diagnostics
- Next step: smallest useful investigation
- Related: issue, pull request, or backlog entry if applicable
```
