# Backlog

Everything this repository intends to do, and everything it has observed and not yet explained,
lives here. Each domain has one file: evidence, open decisions, and committed outcomes stay
together so an entry can mature without moving or changing identity.

Only unfinished work belongs in the backlog. When an entry is resolved, invalidated, or completed,
delete it or cut it down to the part that genuinely remains. History lives in Git.

[prompts.md](prompts.md) is the one exception to the domain layout. It holds one copy-pasteable
prompt per long-running campaign, with the target, current measurements, and stopping condition.

## Areas

| File | Area |
| --- | --- |
| [audio.md](audio.md) | `std/audio` |
| [compiler.md](compiler.md) | Compiler frontend, backend, incrementality, services, and workspace build engine |
| [core.md](core.md) | `std/core` |
| [doc.md](doc.md) | The `doc` command |
| [scope.md](scope.md) | The Swag Scope application shell, document lifecycle, window hosting, and system integration |
| [scope.audio.md](scope.audio.md) | The Swag Scope sound viewer |
| [scope.binary.md](scope.binary.md) | The Swag Scope structured-binary and container viewer |
| [scope.document.md](scope.document.md) | The Swag Scope Markdown, HTML, PDF, office-document, and ebook viewers |
| [scope.font.md](scope.font.md) | The Swag Scope font viewer |
| [scope.hexa.md](scope.hexa.md) | The Swag Scope hexadecimal viewer |
| [scope.image.md](scope.image.md) | The Swag Scope image viewer |
| [scope.midi.md](scope.midi.md) | The Swag Scope MIDI viewer |
| [scope.text.md](scope.text.md) | The Swag Scope basic-text, code, subtitle, table, diff, and log viewers |
| [scope.video.md](scope.video.md) | The Swag Scope video viewer |
| [scope.viewers.md](scope.viewers.md) | Contracts and capabilities shared by several Swag Scope viewers |
| [format.md](format.md) | The `format` command |
| [gui.md](gui.md) | `std/gui` |
| [html.md](html.md) | The HTML engine behind `Gui.HtmlView` |
| [language.md](language.md) | The Swag language and its syntax |
| [markdown.md](markdown.md) | The Markdown engine behind `Gui.Markdown.View` |
| [optimization.md](optimization.md) | Backend optimization passes, register allocation, and generated-code performance |
| [pdf.md](pdf.md) | The PDF engine and `PdfView` inside `std/gui` |
| [pixel.md](pixel.md) | `std/pixel` |
| [portability.md](portability.md) | Cross-platform boundaries in `bin/`, the runtime host ABI, and preparation for Linux |
| [runtime.md](runtime.md) | `bin/runtime`, and the allocator in particular |
| [safety.md](safety.md) | Borrow, lifetime, and sanity analysis |
| [simd.md](simd.md) | Explicit SIMD, its compiler/backend capabilities, and optimized consumers |
| [capture.md](capture.md) | The Swag Capture application |
| [tooling.md](tooling.md) | The build, sandbox, and test harness |
| [truetype.md](truetype.md) | `std/truetype` |
| [vault.md](vault.md) | The Swag Vault application |
| [video.md](video.md) | `std/video` |
| [win32.md](win32.md) | Windows native modules and their checked API boundary |

Put an entry in the domain where it will be investigated or fixed, not where it happened to be
noticed. Create a new domain file only when a real cluster forms; a category holding one isolated
entry costs more to navigate than it saves.

## Number Every Entry

Every entry carries a permanent identifier in its heading:

```text
### B-001 — A short, descriptive title
```

Next identifier: B-160

- `B-*` is the identifier family for every new entry. Take the number above and advance the
  counter in the same change.
- Existing identifiers below `F-203` and `T-572` are permanent legacy identifiers. Their prefix
  records how the entry entered the old split backlog; it no longer controls its location, shape,
  or maturity. Those two families are closed to new allocations.
- Never renumber or reuse an identifier. A deleted entry takes its identifier with it, so an old
  conversation, commit message, link, or code comment keeps its meaning.
- Position expresses expected value where entries are comparable. Put an untriaged lead at the end
  of the closest relevant section until its priority is understood; move it when evidence changes
  that judgment. Identifiers never encode priority.
- Use `##` sections to group entries pursuing the same capability. Sections aid navigation; they do
  not turn independent entries into one campaign.

An entry never receives a new identifier merely because its next action changes from investigation
to implementation. Rewrite it in place and retain any evidence that still matters.

## Write An Entry

One entry owns one independently finishable next outcome. That outcome may be an investigation, a
decision, or an implementation, but a contributor must be able to complete and remove the entry
without also completing unrelated work hidden under the same heading.

Every new entry uses this compact core:

```text
### B-000 — Short outcome or open question

- Evidence: observation, reproduction, measurement, competitive gap, or other reason this remains
- Next: the smallest useful investigation or implementation step
- Complete when: observable condition for deleting the entry or rewriting its next action
- Related: B-001, T-002, F-003 (when applicable)
```

Explanatory paragraphs and additional fields may follow when they materially help execution. For
example, a language-design entry should include `Elsewhere:` with what neighboring languages do,
while a defect may include `Found while:` and a precise reproduction.

For an investigation, `Complete when` names the evidence or decision required to stop investigating.
If that result establishes implementation work, update `Next` and `Complete when` in the same entry.
For committed work, `Complete when` names the externally observable acceptance condition.

Search the whole backlog before adding an entry. Enrich an existing entry instead of creating a
duplicate, and express dependencies through `Related:` rather than combining outcomes that can be
prioritized, implemented, or shipped independently.
