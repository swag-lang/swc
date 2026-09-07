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

The table is ordered from the most recently updated domain down. The `Updated` column carries
the latest stamp any entry in that file holds — its `Updated` stamp when it has one, its
`Recorded` stamp otherwise — so the top rows are where the last work happened. Whoever changes a
domain file refreshes its row and moves it to its new place in the same change. Removing an entry
does not move a row: the backlog holds only what remains, and the removal itself lives in Git.
[repo.prompts.md](repo.prompts.md) has no entries; its row is set by hand when a prompt changes.

| File | Area | Updated |
| --- | --- | --- |
| [platform.portability.md](platform.portability.md) | Every operating-system port, target backend, and Windows-bound contract that must become portable | 2026-09-07 16:28 |
| [std.pixel.md](std.pixel.md) | `std/pixel` | 2026-09-07 16:07 |
| [std.video.md](std.video.md) | `std/video` | 2026-09-07 13:30 |
| [app.scope.viewers.md](app.scope.viewers.md) | Contracts and capabilities shared by several Swag Scope viewers | 2026-09-07 13:22 |
| [std.gui.html.md](std.gui.html.md) | The HTML engine behind `Gui.HtmlView` | 2026-09-07 13:14 |
| [repo.prompts.md](repo.prompts.md) | Copy-pasteable prompts for long-running campaigns | 2026-09-07 12:38 |
| [repo.tooling.md](repo.tooling.md) | The build, sandbox, and test harness | 2026-09-07 11:57 |
| [app.scope.video.md](app.scope.video.md) | The Swag Scope video viewer | 2026-09-07 11:56 |
| [compiler.optimization.md](compiler.optimization.md) | Backend optimization passes, register allocation, and generated-code performance | 2026-09-07 11:12 |
| [compiler.core.md](compiler.core.md) | Compiler frontend, backend, incrementality, services, and workspace build engine | 2026-09-07 10:43 |
| [std.gui.md](std.gui.md) | `std/gui` | 2026-09-06 21:57 |
| [runtime.allocator.md](runtime.allocator.md) | `bin/runtime`, and the allocator in particular | 2026-09-06 21:01 |
| [app.scope.document.md](app.scope.document.md) | The Swag Scope Markdown, HTML, PDF, office-document, and ebook viewers | 2026-09-06 19:13 |
| [language.design.md](language.design.md) | The Swag language and its syntax | 2026-09-06 17:53 |
| [app.capture.md](app.capture.md) | The Swag Capture application | 2026-09-06 17:42 |
| [app.scope.md](app.scope.md) | The Swag Scope application shell, document lifecycle, and window hosting | 2026-09-06 17:42 |
| [app.scope.midi.md](app.scope.midi.md) | The Swag Scope MIDI viewer | 2026-09-06 17:42 |
| [std.core.md](std.core.md) | `std/core` | 2026-09-06 17:42 |
| [std.gui.markdown.md](std.gui.markdown.md) | The Markdown engine behind `Gui.Markdown.View` | 2026-09-06 17:42 |
| [app.scope.audio.md](app.scope.audio.md) | The Swag Scope sound viewer | 2026-09-06 07:51 |
| [app.scope.binary.md](app.scope.binary.md) | The Swag Scope structured-binary and container viewer | 2026-09-06 07:51 |
| [app.scope.font.md](app.scope.font.md) | The Swag Scope font viewer | 2026-09-06 07:51 |
| [app.scope.hexa.md](app.scope.hexa.md) | The Swag Scope hexadecimal viewer | 2026-09-06 07:51 |
| [app.scope.image.md](app.scope.image.md) | The Swag Scope image viewer | 2026-09-06 07:51 |
| [app.scope.indesign.md](app.scope.indesign.md) | The Swag Scope InDesign viewer | 2026-09-06 07:51 |
| [app.scope.opendocument.md](app.scope.opendocument.md) | The Swag Scope OpenDocument decoder and reader | 2026-09-06 07:51 |
| [app.scope.text.md](app.scope.text.md) | The Swag Scope basic-text, code, subtitle, table, diff, and log viewers | 2026-09-06 07:51 |
| [app.vault.md](app.vault.md) | The Swag Vault application | 2026-09-06 07:51 |
| [compiler.command.doc.md](compiler.command.doc.md) | The `doc` command | 2026-09-06 07:51 |
| [compiler.distribution.md](compiler.distribution.md) | Release delivery, first use, local learning, and agent-grade command discovery | 2026-09-06 07:51 |
| [compiler.safety.md](compiler.safety.md) | Memory safety: the borrow rules, the sanity proofs, the runtime guards, and the unsafe surface | 2026-09-06 07:51 |
| [cpu.simd.md](cpu.simd.md) | Explicit SIMD, its compiler/backend capabilities, and optimized consumers | 2026-09-06 07:51 |
| [language.parallelism.md](language.parallelism.md) | Native concurrency and parallelism: task ownership, memory isolation, cancellation, runtime contracts, and migration | 2026-09-06 07:51 |
| [std.audio.md](std.audio.md) | `std/audio` | 2026-09-06 07:51 |
| [std.gui.pdf.md](std.gui.pdf.md) | The PDF engine and `PdfView` inside `std/gui` | 2026-09-06 07:51 |
| [std.pixel.image.md](std.pixel.image.md) | Image codecs, metadata, multi-image input, and SVG decoding in `std/pixel` | 2026-09-06 07:51 |
| [compiler.command.format.md](compiler.command.format.md) | The `format` command | 2026-09-05 16:27 |
| [std.truetype.md](std.truetype.md) | `std/truetype` | 2026-09-01 08:37 |

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
- Position expresses recency. A domain file is one list of entries from the most recently updated
  down: a new entry goes to the top, and an entry that takes an `Updated` stamp moves to the top.
  Identifiers never encode priority or age.
- Do not group entries under `##` headings. Prose about the domain — what already stands, what is
  deliberately out of scope — sits before or after the list, never between entries; when prose
  sections precede the list, one `## Entries` heading opens it. State expected value inside an
  entry when it matters; the list does not rank.

An entry never receives a new identifier merely because its next action changes from investigation
to implementation. Rewrite it in place and retain any evidence that still matters.

## Date Every Entry

Every entry says when it was found and when it last changed, so the newest work reads off the
file without asking Git.

- The first line under the heading is `- Recorded: YYYY-MM-DD HH:MM`: the local date and time,
  on a 24-hour clock, at which the finding was written down. It never changes afterwards.
- Every later change to what the entry claims, plans, or requires — new evidence, a rewritten
  next action, a narrowed scope, a reworded title, a move from another domain — sets one
  `- Updated: YYYY-MM-DD HH:MM — what changed` line directly under `Recorded`. The note is one
  clause naming the change, not a diff; it replaces the previous note, since history lives in
  Git. An `Updated` stamp is never earlier than its `Recorded` stamp.
- Fixing a typo, a link, or the formatting is not an update.
- Stamps decide position. Whenever an entry is stamped, created or updated, move it to the top of
  its file, so the file reads from what moved last down.

Both stamps are read from the clock at the moment of writing, never guessed or copied from a
commit. `tools/tests.swgs` refuses to start a campaign while a stamp is missing or malformed, a
file's entries are out of order, or the inventory below is out of order;
`bin\swc.exe --num-cores 6 tools\tests\repository.swgs .` runs that check alone.

Entries written before this rule existed carry stamps derived from Git: `Recorded` is the commit
that introduced the entry, and an `Updated` note starting with `git:` names the commit that last
touched it. The next real change replaces that note.

## Write An Entry

One entry owns one independently finishable next outcome. That outcome may be an investigation, a
decision, or an implementation, but a contributor must be able to complete and remove the entry
without also completing unrelated work hidden under the same heading.

Every new entry uses this compact core:

```text
### <scope>[.<subscope>...].NNN — Short outcome or open question

- Recorded: YYYY-MM-DD HH:MM
- Updated: YYYY-MM-DD HH:MM — what changed (only once the entry has changed)
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
