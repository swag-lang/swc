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

[design/](design/README.md) is the one subfolder: a design campaign whose entries need their
specification, mockups and renders beside them. It keeps the entry format of a domain file and
disappears when its entries are done.

The table below is a navigation index, ordered by file name. Add or remove a row with its domain
file. Do not add status, dates, or progress summaries to the index.

| File | Area |
| --- | --- |
| [app.capture.md](app.capture.md) | Swag Capture |
| [app.scope.archive.md](app.scope.archive.md) | Swag Scope archive viewer |
| [app.scope.audio.md](app.scope.audio.md) | Swag Scope audio viewer |
| [app.scope.binary.md](app.scope.binary.md) | Swag Scope structured binary viewer |
| [app.scope.code.md](app.scope.code.md) | Swag Scope code viewer |
| [app.scope.comic.md](app.scope.comic.md) | Swag Scope comic book viewer |
| [app.scope.config.md](app.scope.config.md) | Swag Scope configuration viewer |
| [app.scope.diff.md](app.scope.diff.md) | Swag Scope diff viewer |
| [app.scope.docx.md](app.scope.docx.md) | Swag Scope DOCX viewer |
| [app.scope.epub.md](app.scope.epub.md) | Swag Scope EPUB viewer |
| [app.scope.font.md](app.scope.font.md) | Swag Scope font viewer |
| [app.scope.hexa.md](app.scope.hexa.md) | Swag Scope hexadecimal viewer |
| [app.scope.html.md](app.scope.html.md) | Swag Scope HTML viewer |
| [app.scope.image.md](app.scope.image.md) | Swag Scope image viewer |
| [app.scope.json.md](app.scope.json.md) | Swag Scope JSON viewer |
| [app.scope.log.md](app.scope.log.md) | Swag Scope log viewer |
| [app.scope.markdown.md](app.scope.markdown.md) | Swag Scope Markdown viewer |
| [app.scope.md](app.scope.md) | Swag Scope shell and document lifecycle |
| [app.scope.midi.md](app.scope.midi.md) | Swag Scope MIDI viewer |
| [app.scope.notebook.md](app.scope.notebook.md) | Swag Scope notebook viewer |
| [app.scope.odp.md](app.scope.odp.md) | Swag Scope ODP viewer |
| [app.scope.ods.md](app.scope.ods.md) | Swag Scope ODS viewer |
| [app.scope.odt.md](app.scope.odt.md) | Swag Scope ODT viewer |
| [app.scope.pdf.md](app.scope.pdf.md) | Swag Scope PDF viewer |
| [app.scope.pptx.md](app.scope.pptx.md) | Swag Scope PPTX viewer |
| [app.scope.rtf.md](app.scope.rtf.md) | Swag Scope RTF viewer |
| [app.scope.subtitle.md](app.scope.subtitle.md) | Swag Scope subtitle viewer |
| [app.scope.table.md](app.scope.table.md) | Swag Scope table viewer |
| [app.scope.text.md](app.scope.text.md) | Swag Scope plain text viewer |
| [app.scope.video.md](app.scope.video.md) | Swag Scope video viewer |
| [app.scope.viewers.md](app.scope.viewers.md) | Contracts shared by Swag Scope viewers |
| [app.scope.xlsx.md](app.scope.xlsx.md) | Swag Scope XLSX viewer |
| [app.scope.xml.md](app.scope.xml.md) | Swag Scope XML viewer |
| [app.vault.md](app.vault.md) | Swag Vault |
| [clones.md](clones.md) | Independent application clones |
| [compiler.build.md](compiler.build.md) | Workspace compilation, caching, parallelism and compiler build performance |
| [compiler.codegen.md](compiler.codegen.md) | Lowering, ABI, Micro backend and emitted-code generation |
| [compiler.command.doc.md](compiler.command.doc.md) | Compiler `doc` command |
| [compiler.command.format.md](compiler.command.format.md) | Compiler `format` command |
| [compiler.command.help.md](compiler.command.help.md) | Help and examples commands |
| [compiler.command.md](compiler.command.md) | Shared compiler command contracts |
| [compiler.command.test.md](compiler.command.test.md) | Test selection and failure reporting |
| [compiler.frontend.md](compiler.frontend.md) | Lexer, parser, semantic analysis and diagnostics |
| [compiler.optimization.md](compiler.optimization.md) | Transformations and performance of generated Swag programs |
| [compiler.query.md](compiler.query.md) | Semantic queries and verified source edits |
| [compiler.safety.md](compiler.safety.md) | Memory safety and runtime guards |
| [design/design.silence.md](design/design.silence.md) | Silence charter migration: themes, controls, dialogs and applications under `bin/` |
| [language.design.md](language.design.md) | Swag language and syntax |
| [language.parallelism.md](language.parallelism.md) | Native concurrency and parallelism |
| [platform.portability.md](platform.portability.md) | Operating-system ports and portable contracts |
| [repo.prompts.md](repo.prompts.md) | Prompts for long-running campaigns |
| [repo.tooling.md](repo.tooling.md) | Build, benchmark, and test tools |
| [runtime.allocator.md](runtime.allocator.md) | Runtime allocator |
| [std.audio.md](std.audio.md) | `std/audio` |
| [std.core.md](std.core.md) | `std/core` |
| [std.gui.html.md](std.gui.html.md) | HTML engine in `std/gui` |
| [std.gui.markdown.md](std.gui.markdown.md) | Markdown engine in `std/gui` |
| [std.gui.md](std.gui.md) | `std/gui` |
| [std.gui.pdf.md](std.gui.pdf.md) | PDF engine and view in `std/gui` |
| [std.pixel.image.md](std.pixel.image.md) | Image codecs and SVG decoding in `std/pixel` |
| [std.pixel.md](std.pixel.md) | `std/pixel` |
| [std.screen.md](std.screen.md) | `std/screen` live acquisition |
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
changes direction. Delete it when it is done, disproved, or dropped. The former repository
backlog validator was retired with the Swag tool scripts; review identifiers, links, related
entries, and this index against the contract above.
