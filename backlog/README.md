# Backlog

Everything this repository intends to do, and everything it has observed and not yet explained,
lives here. Each domain has one file: evidence, open decisions, and committed outcomes stay
together so an entry can mature without moving or changing identity.

Only unfinished work belongs in the backlog. When an entry is resolved, invalidated, or completed,
delete it or cut it down to the part that genuinely remains. History lives in Git.

[repo.prompts.md](repo.prompts.md) is the one exception to the domain layout. It holds one copy-pasteable
prompt per long-running campaign, with the target, current measurements, and stopping condition.

Domain files use `<family>.<what>.md`: the family groups related surfaces (`app`, `compiler`,
`gui`, `platform`, `scope`, `std`, and so on), while the second part names the exact owner.

## Areas

| File | Area |
| --- | --- |
| [app.capture.md](app.capture.md) | The Swag Capture application |
| [app.scope.md](app.scope.md) | The Swag Scope application shell, document lifecycle, and window hosting |
| [app.vault.md](app.vault.md) | The Swag Vault application |
| [command.doc.md](command.doc.md) | The `doc` command |
| [command.format.md](command.format.md) | The `format` command |
| [compiler.core.md](compiler.core.md) | Compiler frontend, backend, incrementality, services, and workspace build engine |
| [compiler.optimization.md](compiler.optimization.md) | Backend optimization passes, register allocation, and generated-code performance |
| [compiler.safety.md](compiler.safety.md) | Borrow, lifetime, and sanity analysis |
| [cpu.simd.md](cpu.simd.md) | Explicit SIMD, its compiler/backend capabilities, and optimized consumers |
| [font.truetype.md](font.truetype.md) | `std/truetype` |
| [gui.html.md](gui.html.md) | The HTML engine behind `Gui.HtmlView` |
| [gui.markdown.md](gui.markdown.md) | The Markdown engine behind `Gui.Markdown.View` |
| [gui.pdf.md](gui.pdf.md) | The PDF engine and `PdfView` inside `std/gui` |
| [language.design.md](language.design.md) | The Swag language and its syntax |
| [pixel.image.md](pixel.image.md) | `std/pixel` |
| [platform.portability.md](platform.portability.md) | Every operating-system port, target backend, and Windows-bound contract that must become portable |
| [platform.win32.md](platform.win32.md) | Windows native modules and their checked API boundary |
| [repo.tooling.md](repo.tooling.md) | The build, sandbox, and test harness |
| [runtime.allocator.md](runtime.allocator.md) | `bin/runtime`, and the allocator in particular |
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
| [std.audio.md](std.audio.md) | `std/audio` |
| [std.core.md](std.core.md) | `std/core` |
| [std.gui.md](std.gui.md) | `std/gui` |
| [std.video.md](std.video.md) | `std/video` |

Put an entry in the domain where it will be investigated or fixed, not where it happened to be
noticed. Create a new domain file only when a real cluster forms; a category holding one isolated
entry costs more to navigate than it saves.

Operating-system work is the deliberate exception: every new OS backend, application port,
target-specific integration, and Windows-bound API or policy that must be extracted for portability
belongs in [platform.portability.md](platform.portability.md), whatever module or application owns the code.

## Number Every Entry

Every entry carries a permanent identifier in its heading:

```text
### B-001 — A short, descriptive title
```

Next identifier: B-642

- `B-*` is the identifier family for every new entry. Take the number above and advance the
  counter in the same change.
- Every active entry uses `B-*`; the former `T-*` and `F-*` families are closed.
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
- Related: B-001, B-168, B-203 (when applicable)
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
