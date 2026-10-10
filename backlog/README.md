# Backlog

The backlog lists unfinished work only. Remove an entry as soon as its outcome is complete,
invalid, or no longer wanted. Git is the history; do not keep completed entries, dated updates,
campaign logs, or summaries of shipped work here.

An entry may record a failed attempt only when it changes the next useful action. Keep that note
short and put it beside `Next:`. Do not preserve a sequence of experiments or validation results.

`repo.prompts.md` is the exception: it contains copy-pasteable prompts for long campaigns. Keep
campaign instructions and the current baseline needed to run them there; keep campaign results in
their proper reports and Git history.

## Domain files

Each domain has one `<scope>[.<subscope>...].md` file, named for where the work will be fixed.
Use the narrowest real owner. Examples include `std.truetype`, `std.pixel.image`,
`app.scope.midi`, and `compiler.command.doc`. Cross-cutting operating-system portability belongs
in [platform.portability.md](platform.portability.md).

The table below is a navigation index, ordered by file name. Add or remove a row with its domain
file. Do not add status, dates, or progress summaries to the index.

| File | Area |
| --- | --- |
| [app.capture.md](app.capture.md) | Swag Capture |
| [app.prism.md](app.prism.md) | Swag Prism |
| [app.scope.audio.md](app.scope.audio.md) | Swag Scope audio viewer |
| [app.scope.binary.md](app.scope.binary.md) | Swag Scope structured-binary and container viewer |
| [app.scope.document.md](app.scope.document.md) | Swag Scope document viewers |
| [app.scope.font.md](app.scope.font.md) | Swag Scope font viewer |
| [app.scope.hexa.md](app.scope.hexa.md) | Swag Scope hexadecimal viewer |
| [app.scope.image.md](app.scope.image.md) | Swag Scope image viewer |
| [app.scope.indesign.md](app.scope.indesign.md) | Swag Scope InDesign viewer |
| [app.scope.md](app.scope.md) | Swag Scope shell and document lifecycle |
| [app.scope.midi.md](app.scope.midi.md) | Swag Scope MIDI viewer |
| [app.scope.opendocument.md](app.scope.opendocument.md) | Swag Scope OpenDocument viewer |
| [app.scope.text.md](app.scope.text.md) | Swag Scope text and code viewers |
| [app.scope.video.md](app.scope.video.md) | Swag Scope video viewer |
| [app.scope.viewers.md](app.scope.viewers.md) | Contracts shared by Swag Scope viewers |
| [app.vault.md](app.vault.md) | Swag Vault |
| [compiler.command.doc.md](compiler.command.doc.md) | Compiler `doc` command |
| [compiler.command.format.md](compiler.command.format.md) | Compiler `format` command |
| [compiler.core.md](compiler.core.md) | Compiler frontend, backend, incrementality, and workspace builds |
| [compiler.distribution.md](compiler.distribution.md) | Release delivery and first use |
| [compiler.language.service.md](compiler.language.service.md) | Compiler-backed editor services |
| [compiler.optimization.md](compiler.optimization.md) | Backend optimization and generated-code performance |
| [compiler.safety.md](compiler.safety.md) | Memory safety and runtime guards |
| [cpu.simd.md](cpu.simd.md) | SIMD compiler and consumer work |
| [language.design.md](language.design.md) | Swag language and syntax |
| [language.parallelism.md](language.parallelism.md) | Native concurrency and parallelism |
| [platform.portability.md](platform.portability.md) | Operating-system ports and portable contracts |
| [repo.prompts.md](repo.prompts.md) | Prompts for long-running campaigns |
| [repo.tooling.md](repo.tooling.md) | Build, benchmark, and test tools |
| [runtime.allocator.md](runtime.allocator.md) | Runtime and allocator |
| [std.audio.md](std.audio.md) | `std/audio` |
| [std.core.md](std.core.md) | `std/core` |
| [std.gui.html.md](std.gui.html.md) | HTML engine in `std/gui` |
| [std.gui.markdown.md](std.gui.markdown.md) | Markdown engine in `std/gui` |
| [std.gui.md](std.gui.md) | `std/gui` |
| [std.gui.pdf.md](std.gui.pdf.md) | PDF engine and view in `std/gui` |
| [std.pixel.image.md](std.pixel.image.md) | Image codecs and SVG decoding in `std/pixel` |
| [std.pixel.md](std.pixel.md) | `std/pixel` |
| [std.truetype.md](std.truetype.md) | `std/truetype` |
| [std.video.md](std.video.md) | `std/video` |

## Entry format

Every entry has a stable file-scoped identifier. Never renumber or reuse an identifier. A deleted
identifier stays retired; a moved entry receives the next identifier in its destination file and
all live links are updated.

```markdown
### <scope>[.<subscope>...].NNN — Short unfinished outcome

- Next: the smallest concrete action that moves the work forward
- Done when: an observable condition for deleting this entry
- Evidence: the current fact that makes the work necessary (when useful)
- Related: <other-scope>.NNN (when applicable)
```

Prefer one independently finishable outcome per entry. `Next:` must name an action, not a broad
wish. `Done when:` must say what observable result lets the entry disappear. Keep evidence to the
minimum needed to choose or execute that action. Put useful dependencies in `Related:`. Do not add
timestamps, status fields, completed milestones, validation logs, or free-standing progress
sections.

Search the whole backlog before adding an entry. Update an existing entry when the same work
changes direction. Delete it when it is done, disproved, or dropped. The repository validator
checks identifiers, links, related entries, and the index:

```text
bin\swc.exe --num-cores 6 tools\tests\repository.swgs .
```
