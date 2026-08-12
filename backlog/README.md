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

[prompts.md](prompts.md) is a third kind of file: one copy-pasteable prompt per long-running
campaign — generated-code performance, safety, compiler code mass, compilation speed, compiler
memory, and repository health. A campaign spans many sessions and many failed attempts, so each
prompt states the target, the numbers as they stand, and the condition under which the work is
allowed to stop.

## Intent

| File | Unit |
| --- | --- |
| [todo.compiler.md](todo.compiler.md) | `swc` itself: frontend, backend, incrementality, speed, memory, and what sits around it |
| [todo.language.md](todo.language.md) | The Swag language and its syntax — design questions open by choice |
| [todo.doc.md](todo.doc.md) | The `doc` command |
| [todo.format.md](todo.format.md) | The `format` command |
| [todo.runtime.md](todo.runtime.md) | `bin/runtime`, and the allocator in particular |
| [todo.portability.md](todo.portability.md) | Cross-platform boundaries in `bin/`, the runtime host ABI, and preparation for Linux |
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
| [findings.format.md](findings.format.md) | The `format` command and formatter defects |
| [findings.language.md](findings.language.md) | Language rules that surprise: overloaded spellings, defaults, and silent conversions |
| [findings.optimization.md](findings.optimization.md) | Backend optimization passes, register allocation, and generated-code performance |
| [findings.safety.md](findings.safety.md) | Borrow, lifetime, and sanity analysis |
| [findings.gui.md](findings.gui.md) | `std/gui`, and the widgets and dialogs it ships |
| [findings.scapture.md](findings.scapture.md) | The sCapture application |
| [findings.tooling.md](findings.tooling.md) | The build, the sandbox, and the test harness |

Put an entry in the file whose area it will be *fixed* in, not the one it was noticed from. Create
a new file only when a real cluster forms — a category holding one entry costs more to navigate
than it saves.

An application follows the same rule as a module: it gets its own `findings.<app>.md` beside its
`todo.<app>.md` once it has entries of its own, and a lead an application merely *exposed* stays in
the file of the unit that will fix it. So sCrypt has no findings file today: everything it has
surfaced so far will be fixed in `std/gui`, and an empty file would only be one more place to look.

## Number Every Entry

Every entry — finding or todo — carries a permanent identifier in its heading:

```
### F-023 — A menu bar does not follow a live language switch
### T-054 — No vector output
```

The identifier is how an entry is named everywhere else — in conversation, in a commit message, in
another backlog entry, in a code comment. A title gets rewritten, a position moves, and an entry
changes file; the identifier does not.

Next identifier: F-122
Next identifier: T-385

- Take the next identifier of the matching kind from the lines above, then advance that line. Each
  is a counter, not an entry count: it keeps rising as entries are deleted. The `F` counter is
  shared by every `findings.*` file, the `T` counter by every `todo.*` file.
- Never renumber and never reuse. A deleted entry takes its identifier with it, so `F-012` in an
  old commit message still means what it meant.
- In a `findings.*` file, keep entries sorted by identifier, ascending. A new entry always carries
  the highest identifier of its file, so it goes at the end; a deleted one leaves a gap, and the
  gap stays. Position is mechanical and carries no priority — it only makes an entry findable by
  its number.
- In a `todo.*` file, position IS priority: entries stay ordered by decreasing value, so a new
  entry goes wherever its value puts it, and identifiers appear out of order. The number says what
  an entry is called, never how much it matters.
- Use `##` sections to group contiguous entries that pursue the same capability. Section order
  preserves todo priority and global finding-identifier order; a section is navigation, not a
  campaign umbrella, and does not change the independence of the entries beneath it.
- A finding that graduates into a plan becomes a todo entry and takes a fresh `T` identifier; its
  `F` identifier retires with it. Name the finding it came from in the new entry.

## Write A Todo

One todo names one independently finishable outcome. A contributor must be able to take its
identifier, complete that outcome, and remove that entry without also having to complete another
missing capability hidden under the same heading.

- Keep together only the implementation steps and acceptance conditions required to make that one
  outcome correct.
- Give separate identifiers to capabilities that can ship, be tested, or be prioritized
  independently, even when they touch the same subsystem.
- State dependencies and useful coordination through a `Related:` line naming the other todo
  identifiers. A relationship never makes several outcomes one entry.
- Do not use one heading as a campaign umbrella over numbered work. Put shared context in the file
  introduction or tier introduction, then keep each entry independently actionable.

Use this compact shape; explanatory paragraphs and evidence may follow when they materially help
someone execute the item.

```
### T-000 — Short outcome

- Intent: the one missing result this entry delivers
- Complete when: observable acceptance condition
- Related: T-001, T-002 (when applicable)
```

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

[findings.language.md](findings.language.md) adds one field to that shape, between `Evidence` and
`Next step`, and every entry in that file carries it:

```
- Elsewhere: what the neighbouring languages do about the same question
```

A language rule is judged against alternatives that exist, so the entry states them before it
proposes anything: a wart nobody else has and a convention half the field shares lead to different
decisions. The line records what those languages do, not what Swag should do — several entries there
keep a rule Swag shares with exactly one other language. Do not add the field elsewhere; a defect in
`swc` has no neighbour to compare against.
