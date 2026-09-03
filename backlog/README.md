# Backlog

Everything this repository intends to do, and everything it has observed and not yet explained,
lives here. Each domain has one file: evidence, open decisions, and committed outcomes stay
together so an entry can mature without changing identity while it remains in that domain.

Only unfinished work belongs in the backlog. When an entry is resolved, invalidated, or completed,
delete it or cut it down to the part that genuinely remains. History lives in Git.

[repo.prompts.md](repo.prompts.md) is the one exception to the domain layout. It holds one copy-pasteable
prompt per long-running campaign, with the target, current measurements, and stopping condition.

Domain files use a fully qualified `<scope>[.<subscope>...].md` name, ordered from the broadest
real owner to the most specific domain needed to make the file unambiguous. There is no limit on
the number of scope segments. Every segment must describe a real ownership or domain boundary;
never invent a grouping level merely to make a name longer.

The scope follows the work the file actually owns. A whole standard module, or its general work
after specialized backlogs are split out, uses its module path, such as `std.truetype` or
`std.pixel`; a real subsystem adds its parent, such as the image-codec scope `std.pixel.image` or
`std.gui.html`; an
application capability uses the application hierarchy, such as `app.scope.midi`; and a compiler
command uses `compiler.command.doc`. A deliberately cross-cutting domain can remain `cpu.simd` or
`platform.portability` when no narrower owner contains the work.

## Areas

| File | Area |
| --- | --- |
| [app.capture.md](app.capture.md) | The Swag Capture application |
| [app.scope.md](app.scope.md) | The Swag Scope application shell, document lifecycle, and window hosting |
| [app.scope.audio.md](app.scope.audio.md) | The Swag Scope sound viewer |
| [app.scope.binary.md](app.scope.binary.md) | The Swag Scope structured-binary and container viewer |
| [app.scope.document.md](app.scope.document.md) | The Swag Scope Markdown, HTML, PDF, office-document, and ebook viewers |
| [app.scope.font.md](app.scope.font.md) | The Swag Scope font viewer |
| [app.scope.hexa.md](app.scope.hexa.md) | The Swag Scope hexadecimal viewer |
| [app.scope.image.md](app.scope.image.md) | The Swag Scope image viewer |
| [app.scope.indesign.md](app.scope.indesign.md) | The Swag Scope InDesign viewer |
| [app.scope.midi.md](app.scope.midi.md) | The Swag Scope MIDI viewer |
| [app.scope.opendocument.md](app.scope.opendocument.md) | The Swag Scope OpenDocument decoder and reader |
| [app.scope.text.md](app.scope.text.md) | The Swag Scope basic-text, code, subtitle, table, diff, and log viewers |
| [app.scope.video.md](app.scope.video.md) | The Swag Scope video viewer |
| [app.scope.viewers.md](app.scope.viewers.md) | Contracts and capabilities shared by several Swag Scope viewers |
| [app.vault.md](app.vault.md) | The Swag Vault application |
| [compiler.command.doc.md](compiler.command.doc.md) | The `doc` command |
| [compiler.command.format.md](compiler.command.format.md) | The `format` command |
| [compiler.core.md](compiler.core.md) | Compiler frontend, backend, incrementality, services, and workspace build engine |
| [compiler.optimization.md](compiler.optimization.md) | Backend optimization passes, register allocation, and generated-code performance |
| [compiler.safety.md](compiler.safety.md) | Borrow, lifetime, and sanity analysis |
| [cpu.simd.md](cpu.simd.md) | Explicit SIMD, its compiler/backend capabilities, and optimized consumers |
| [language.design.md](language.design.md) | The Swag language and its syntax |
| [platform.portability.md](platform.portability.md) | Every operating-system port, target backend, and Windows-bound contract that must become portable |
| [repo.prompts.md](repo.prompts.md) | Copy-pasteable prompts for long-running campaigns |
| [repo.tooling.md](repo.tooling.md) | The build, sandbox, and test harness |
| [runtime.allocator.md](runtime.allocator.md) | `bin/runtime`, and the allocator in particular |
| [std.audio.md](std.audio.md) | `std/audio` |
| [std.core.md](std.core.md) | `std/core` |
| [std.gui.md](std.gui.md) | `std/gui` |
| [std.gui.html.md](std.gui.html.md) | The HTML engine behind `Gui.HtmlView` |
| [std.gui.markdown.md](std.gui.markdown.md) | The Markdown engine behind `Gui.Markdown.View` |
| [std.gui.pdf.md](std.gui.pdf.md) | The PDF engine and `PdfView` inside `std/gui` |
| [std.pixel.md](std.pixel.md) | `std/pixel` |
| [std.pixel.image.md](std.pixel.image.md) | Image codecs, metadata, multi-image input, and SVG decoding in `std/pixel` |
| [std.truetype.md](std.truetype.md) | `std/truetype` |
| [std.video.md](std.video.md) | `std/video` |
| [std.win32.md](std.win32.md) | Windows native modules and their checked API boundary |

Put an entry in the domain where it will be investigated or fixed, not where it happened to be
noticed. Create a new domain file only when a real cluster forms; a category holding one isolated
entry costs more to navigate than it saves.

Operating-system work is the deliberate exception: every new OS backend, application port,
target-specific integration, and Windows-bound API or policy that must be extracted for portability
belongs in [platform.portability.md](platform.portability.md), whatever module or application owns the code.

## Number Every Entry

Every entry carries a file-scoped identifier in its heading:

```text
### app.scope.midi.001 — A short, descriptive title
```

- The identifier prefix is the complete file name without `.md`; `app.scope.midi.md` owns
  `app.scope.midi.*`.
- The suffix has exactly three digits. For a new entry, take one more than the greatest suffix ever
  allocated in that file. There is no repository-wide counter and no counter stored in this index.
- Never renumber or reuse an identifier inside a file. A deleted entry takes its suffix with it, so
  an old conversation, commit message, link, or code comment keeps its meaning.
- Renaming a domain preserves each entry's numeric suffix, changes its prefix with the file, and
  updates every live reference and Markdown fragment in the same change.
- Moving one entry to another domain changes its prefix and suffix. Allocate the destination
  file's next suffix and update every live reference and Markdown fragment in the same change.
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
### <scope>[.<subscope>...].NNN — Short outcome or open question

- Evidence: observation, reproduction, measurement, competitive gap, or other reason this remains
- Next: the smallest useful investigation or implementation step
- Complete when: observable condition for deleting the entry or rewriting its next action
- Related: <other-scope>[.<other-subscope>...].NNN (when applicable)
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
