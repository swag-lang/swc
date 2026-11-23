# Swag Scope Shared Viewer Backlog

This backlog covers contracts, behavior, coverage, and product boundaries shared by several
Swag Scope viewers. A capability owned by one viewer lives in its `app.scope.<viewer>.md` file;
window lifecycle and document management live in [app.scope.md](app.scope.md), while operating-system
integration belongs to [platform.portability.md](platform.portability.md). Reusable engine work remains in the owning standard-module backlog.

## Reading-first delivery plan

Complete the formats already registered before adding more. A format counts as readable only when
its primary content opens in the intended order, navigation works, search or selection works where
meaningful, large or damaged input remains bounded, and unsupported content is named rather than
silently omitted. The [fixture matrix](../bin/apps/modules/swagscope/src/tests/datas/README.md)
records named and real-world variants; app.scope.viewers.009 tracks the remaining behavior and
performance checks per format. Implement every viewer and decoder in Swag without external viewer
libraries. Ship the built-in readers in one executable, with no separately installed codecs,
viewer packages, helper binaries, or network service required to open supported local files.

1. **Document fidelity.** Compare real Word, Excel, PowerPoint, LibreOffice and PDF files on the
   same corpus under app.scope.viewers.009. Start with authored pages and repeated sections in
   [DOCX](app.scope.docx.md) and [ODT](app.scope.odt.md), saved worksheet geometry and charts in
   [XLSX](app.scope.xlsx.md) and [ODS](app.scope.ods.md), and masters and drawings in
   [PPTX](app.scope.pptx.md) and [ODP](app.scope.odp.md). Keep the document ahead of its raw
   archive view. Include partial PDF rendering, bounded loading and explicit omissions in the
   comparison. [File Viewer Plus 7 documents and formats](https://fileviewerplus.com/support/supported_file_formats)
2. **PDF navigation, output and shared printing.** The bounded thumbnail rail and sequential,
   DPI-selectable export of up to 50 PDF pages are complete. Next extend the shared print path in
   app.scope.viewers.002 and add safe embedded-asset inspection in [PDF](app.scope.pdf.md). Use
   mixed text and scanned PDFs to establish search coverage before taking up OCR. Keep
   [EPUB](app.scope.epub.md) book-wide search and [CBZ](app.scope.comic.md) page layouts in their
   existing reader plans. [File Viewer Plus PDF controls](https://fileviewerplus.com/support/pdf_files),
   [scan and OCR workflow](https://fileviewerplus.com/whats_new)
3. **Formats that block opening.** Finish the ZIP integrity baseline and add TAR/GZIP first,
   then 7z and RAR under [Archive](app.scope.archive.md). Prioritize HEIC and embedded camera
   RAW previews for [Image](app.scope.image.md), WebM/VP9 in [Video](std.video.md), and qualify
   AAC-in-M4A in the coverage matrix for [Sound](app.scope.audio.md). AVIF, JPEG XL and AV1
   follow those first coverage gaps. [File Viewer Plus formats](https://fileviewerplus.com/file_types)
4. **Multi-file reading.** Build tabs under app.scope.001, then independently navigable
   side-by-side panes under app.scope.003 and multipage PDF/Office previews under app.scope.viewers.015.
   Compare folder search and preview navigation from the same directory and keep first-content
   latency, cancellation, keyboard use, Encre and Papier in the acceptance checks.
   [File Viewer Plus workspace](https://fileviewerplus.com/features), [folder search and previews](https://fileviewerplus.com/whats_new)

Additional format families such as DjVu, XPS, mail, Visio, Project, CAD and DICOM
remain product decisions after these priorities. Editing and batch conversion are separate
product capabilities. [File Viewer Plus coverage](https://fileviewerplus.com/support/supported_file_formats)

## Entries

### app.scope.viewers.015 — Explorer thumbnails do not yet reflect every reader

- Evidence: Image, Video, Comic, PDF, Sound (the sleeve its tags embed, else its waveform), EPUB
  (the cover its package names) and MIDI (its notes as a small piano roll, drums in a softer tone)
  can supply content thumbnails; a plugin decoder answering an empty image keeps the shared
  preview. Text, Code, Markdown and Subtitle still show a bounded source sample. Table draws a small
  CSV/TSV grid from at most 16 KiB; HTML and RTF draw text from their parsed documents;
  Archive, Binary, DOCX, ODT, ODS, ODP, EPUB without a cover, Font, Hex, PPTX and XLSX show neutral
  file facts. The old fallback's byte map
  was misleading for binary documents and is no longer used.
- Next: give each remaining visual reader a bounded thumbnail callback using its own decoded
  model: EPUB first spine page when no cover is named, Office first page/slide/sheet, and a font
  specimen. Keep archive and hexadecimal previews
  explicitly neutral when no single rendered page represents the file. Use the same page
  provider for a bounded scrollable PDF/Office preview after first-page previews work.
- Done when: every registered viewer either supplies a representative content image through its
  own decoder or deliberately declares a neutral preview; first-visible-preview latency,
  cancellation, damaged-file fallback, and both themes have focused coverage. A multipage
  preview releases stale requests when the selected file changes.
- Related: app.scope.viewers.009

### app.scope.viewers.003 — Viewer state is forgotten when a file or application closes

- Evidence: Markdown theme, reading width and zoom, and Video subtitle presentation already persist
  as global preferences in `ViewerWindow.onSerializeStateEvent`. `ViewerReadingState` also restores
  supported settings during an in-place reload. Per-file zoom, fit mode, wrapping, encoding,
  selected track, playback position/volume, page and scroll position have no identity-keyed restore
  contract and are reconstructed on reopening.
- Next: define versioned global defaults plus per-file state keyed by stable file identity, with an
  explicit list of safe fields each viewer may persist.
- Done when: every registered viewer restores its useful reading state, stale identity never
  applies state to a replacement file, and one command resets either the current viewer or all
  viewer preferences.

### app.scope.viewers.009 — The viewer family has no release-quality compatibility matrix

- Evidence: the 25 registered viewers have focused tests and viewer-specific goldens. The
  fixture matrix now names all 200 `viewer.*` files plus two standalone font variants, checks each
  entry's first viewer, and decodes the listed image inputs. EPUB, CBZ, DOCX, ODT, RTF, XLSX, ODS,
  PPTX and ODP have content and
  damaged-package cases. Seven complete, openly licensed published documents plus generated
  public-domain ODT/RTF story conversions add long-form checks for EPUB, office formats and PDF.
  Repository-generated examples now exercise a nested project ZIP/JAR, ELF and telemetry binary,
  multi-track MIDI, tagged field audio, a generated H.264 clip, a mixed text/scan PDF, an animated
  WebP and a two-page comic, a watershed SVG/ODP, an OFL font collection, and realistic code, text,
  subtitles, HTML and CSV. Their source, licence or generation steps and SHA-256 hashes are recorded
  in the fixture guide. Text covers queued encoding changes, cancellation and CRLF search offsets; shared
  document outlines have their own [integration suite](../bin/apps/modules/swagscope/src/tests/cases/functional/viewer.outline.swg).
  These tests still do not declare a complete matrix for real-world variants,
  malformed input, large files, cancellation, keyboard-only use, themes, DPI, memory ceilings, or
  selection-to-first-content latency under rapid adjacent-file browsing.
- Next: extend the fixture matrix beyond viewer selection and image decoding: map every fixture
  to content assertions, bounded-resource cases, interaction checks and visual states. Start with
  the weakest document readers and then fill behavior gaps in the archive and media variants from
  the delivery plan. For DOCX, require content assertions across generated and real Word-authored
  documents, each implemented or disclosed-unsupported feature in the DOCX backlog, its allowed
  external hyperlink schemes and unsafe-target cases, malformed package/relationship/optional-part
  cases, and bounded-load and replacement cases. Compare DOCX, XLSX, PPTX and PDF against File
  Viewer Plus 7 on the same machine and inputs.
  Measure cold and warm first-content latency, replacement cancellation, peak resident
  memory and bytes read before first content; set absolute thresholds before making performance a
  regression gate.
- Done when: the application smoke validates every registered viewer in light and dark themes,
  the matrix names unsupported variants honestly, corpus licences are recorded, and regressions in
  format choice, cancellation, accessibility, resource bounds, or preview latency fail a focused suite.

### app.scope.viewers.014 — A lone release executable is not a verified delivery contract

- Evidence: the [application README](../bin/apps/modules/swagscope/README.md) says the build contains
  every viewer in one executable but allows the publisher to place standard-module runtime files
  beside it. No clean, offline launch check proves that the executable alone opens every supported
  format. Separately packaged viewer support would also violate the product boundary.
- Next: inventory the release executable's non-OS imports and run it from an otherwise empty
  directory on a clean offline Windows profile. Statically include or embed required Swag runtime,
  codec, font, and viewer assets; keep any parser worker as a mode of the same executable.
- Done when: one `swagscope.exe` with no adjacent payload opens representative fixtures for all
  twenty-five registered viewers offline, including after a clean reboot; a release gate checks its
  import closure and installed-file manifest, and no reader calls an external decoder or service.
- Related: app.scope.viewers.009, app.scope.viewers.011

### app.scope.viewers.005 — Automatic reload does not classify changes or offer a snapshot policy

- Evidence: `ViewerFileWatch` already polls size, creation time and last-write time off-thread,
  waits for two stable observations, and asks the host to reload. `ViewerReadingState` restores
  supported reading settings and scroll positions, and old searches are retired. Reload tests
  cover edits, truncation, atomic replacement, temporary deletion and PDF/Markdown state. The
  watcher still collapses successful changes to one Boolean and suppresses metadata errors; it
  exposes neither stable file identity, append/replace/delete/permission-loss classification, nor
  a user choice to retain a labelled snapshot.
- Next: extend the existing watcher with typed change observations and stable identity, then
  let viewers declare reload, append-following, or labelled-snapshot behavior.
- Done when: atomic replacement, append, truncation, deletion, and permission loss are
  distinguished; stale search results are retired; reload can preserve a valid logical position;
  and each viewer states whether live following is supported.
- Related: app.scope.hexa.008, app.scope.log.001

### app.scope.viewers.006 — File facts have no common host-wide inspection contract

- Evidence: Image and Video already publish grouped metadata through the shared `MediaInfoPanel`,
  with translated property labels, row selection and a copy command. The host also shows size and
  a viewer-supplied summary. Office documents (DOCX, PPTX, XLSX and their OpenDocument
  counterparts) add the title, author, creation day and saving program their package names, read
  by `Package.DocumentProperties` with the document on the loading worker (XLSX still reads them on
  the GUI thread the first time the sheet asks); EPUB and comic books add their own metadata. Canonical path,
  timestamps, file identity, hashes, detection evidence and warnings still lack one contract
  across all registered viewers. [File Viewer Plus](https://fileviewerplus.com/features) documents
  signature-based identification, MIME, MD5 and EXIF in its inspector. A proposed identification
  and a rendered or decoded file are distinct results in the comparison.
- Next: extend the existing information surface with host-owned file facts and optional viewer
  properties and warnings, including cancellable hashing and links back to the described content.
- Done when: facts are selectable and copyable, byte sizes and dates have exact forms, format
  detection explains its evidence, hashes are cancellable for large files, and viewers can link a
  property to the content it describes.
- Related: app.scope.image.003

### app.scope.viewers.011 — Attacker-controlled decoders share the application process

- Evidence: every registered viewer is a direct function callback compiled into `swagscope.exe`.
  A malformed image, font, document, archive, or media stream therefore reaches its decoder in the
  process that owns the window, history, clipboard access, and ordinary user token. Read-only and
  offline prevent intentional document actions, but they do not contain a parser defect.
- Next: define a brokered open/render/report contract over host-owned read-only ranges, then move one
  high-risk decoder family into a disposable mode of the same executable with CPU, memory, time,
  file, network, process, and write limits before generalizing the boundary.
- Done when: decoder crash, hang, resource exhaustion, and malformed output cannot terminate or
  corrupt the main window; the worker cannot open arbitrary paths, write, use the network, or spawn
  processes; results are versioned and size-checked; cancellation kills only the affected job; and
  failure leaves the file available through bounded hexadecimal inspection.
- Related: app.scope.viewers.004, app.scope.viewers.009, platform.portability.040,
  platform.portability.072

### app.scope.viewers.013 — Three decoder families cannot claim files independently of their extension

- Evidence: `choices` reads the head of a file once and lets a descriptor claim it from its own
  bytes, and `html`, `code`, `pdf`, `font`, `midi`, `archive`, and `text` do. `image`, `video`,
  and `sound` cannot: `Pixel.Image.decode`, `Video.Reader.open`, and `Audio.SoundFile.load` select
  a codec from the filename extension alone.
  A JPEG named `.dat` is therefore still offered as bytes only, and a viewer that claimed it from
  its signature would then fail to open it.
- Next: give the three decoder registries a content-based lookup, as a signature predicate declared
  beside the extension list each codec already publishes plus one `decoderFor(bytes)` entry point
  per module, then add the missing probes.
- Done when: a raster image, a video container, and a sound file are each offered their own viewer through a copy renamed to an extension
  nothing claims, and every viewer a probe offers can open the file it claimed.
- Related: app.scope.image.001

### app.scope.viewers.002 — A document cannot be printed

- Intent: a viewer that renders a document should be able to put it on paper through the same
  pagination contract as the rest of the GUI rather than through application-local paths.
- Evidence: [File Viewer Plus](https://fileviewerplus.com/support/pdf_files) prints a page range
  through the system print dialog. Its [spreadsheet preview](https://fileviewerplus.com/support/spreadsheet_files)
  shows the page layout before printing.
- Next: use PDF as the first consumer of the GUI pagination and preview contract. Share the
  existing page-range selection with printing, then extend the adapter to other paginated formats.
- Done when: PDFs can preview and print a selected range, and Office, text, code, Markdown, HTML,
  image and hexadecimal dump views use the shared contract with actual-size or fit-to-page choices.
- Related: std.gui.030, platform.portability.086, std.gui.034

### app.scope.viewers.004 — Long viewer operations have no common progress and cancellation contract

- Evidence: viewers independently use workers and the host loading overlay, but parsing, indexing,
  waveform building, rendering, and search cannot consistently report units completed, yield a
  partial result, or distinguish cancellation from failure.
- Next: extend `Viewer.LifecycleApi` with cancellable phases, determinate or indeterminate progress,
  partial-publication rules, and a shared terminal status.
- Done when: opening and analysis operations remain interruptible, replacement files retire old
  work promptly, the overlay names the current phase, and cancellation never becomes an error.
- Related: std.gui.pdf.029

### app.scope.viewers.016 — Whole-file search has no inspectable result set or context projection

- Evidence: shared search supports case, whole-word, and regular-expression matching across the
  whole file, but exposes only one highlighted occurrence and a current/total counter. There is no
  retained matching-line view, surrounding context or whole-file match overview.
- Next: publish the streamed match index as a virtual result pane with configurable context lines
  and an optional matches-only projection over immutable source ranges.
- Done when: results show line, byte offset, matched text, and bounded before/after context;
  activating a row reveals the source; the overview represents the whole file; duplicate or
  overlapping matches remain unambiguous; context can be expanded locally; and closing the pane
  releases its index without changing the file.

### app.scope.viewers.017 — Regular-expression search has no declared resource budget

- Evidence: the generic file path reads chunks on timers but retains the complete source before
  evaluating a regular expression on the GUI thread. This preserves cross-chunk matches and
  document anchors at the cost of unbounded source retention. `Viewer.collectTextMatches` already
  skips zero-width matches and returns non-overlapping spans. `Parser.RegExp` has bounded DFA
  caches and a 20-million-step backtracking budget, but the viewer has no cumulative query memory,
  result-count or cancellation contract and cannot distinguish exhaustion from no match.
- Next: move evaluation behind a cancellable, budgeted query operation, retaining the existing
  anchor and nonzero-span semantics, and add adversarial plus boundary-spanning fixtures.
- Done when: regex compilation and matching have explicit time, memory, stack, and result
  limits; cancellation meets a measured latency; zero-length and overlapping matches advance
  deterministically; boundary-spanning results are correct or the documented maximum look-behind
  is enforced; and exhaustion is reported separately from no match.
- Related: app.scope.viewers.016, app.scope.viewers.004, app.scope.viewers.009

### app.scope.viewers.001 — Select-all in a streamed document silently means the resident window

- Evidence: the basic text and `Code` viewers use `RichEditCtrl`; Ctrl+A selects only their
  resident 256 KiB window. The Markdown viewer likewise selects only materialized blocks. The
  `Hexadecimal` viewer is the positive example because its bounded copy command names its 1 MiB
  limit before copying.
- Next: define one shared streamed-selection contract and apply it to basic text, Code, and
  Markdown without making a multi-gigabyte copy resident.
- Done when: select-all reaches the whole file or the copy command says exactly which bounded
  part will leave, before the user pastes it.

### app.scope.viewers.007 — Custom-painted viewers cannot expose a professional accessibility model

- Evidence: image, waveform, piano-roll, font-map, video-overlay, and hexadecimal surfaces paint
  meaning without semantic children. The toolkit itself still has no accessibility bridge, so
  keyboard focus alone cannot describe values, ranges, selection, or playback state.
- Next: specify the semantic tree and keyboard contract for every custom viewer while platform.portability.048 builds
  the toolkit bridge, beginning with roles, names, values, bounds, and change notifications.
- Done when: each viewer has an accessibility fixture, all actions are keyboard reachable,
  focus order is stable, animation and playback state are announced without flooding, and the
  shipped platform bridge exposes the same model.
- Related: platform.portability.048, app.scope.hexa.014

### app.scope.viewers.008 — Viewer commands need consistent discovery and state

- Evidence: Keyboard Shortcuts lists application commands and named actions in the active viewer.
  Some operations still live in compact menus, context menus, or raw key handlers with separate
  applicability checks. Disabled actions do not consistently say why they are unavailable.
- Next: connect the remaining operations and their applicability to the named viewer actions.
- Done when: every non-pointer-only action can be found and invoked by name, and the lens,
  compact controls, menus, and key handlers share its applicability and presentation.
- Related: app.scope.hexa.016

---

### app.scope.viewers.018 — Reading marks and notes have no document-independent home

- Evidence: PDF, EPUB, Markdown, HTML and Office readers have selection or location models but
  no read-only-source highlight and note store. [Okular](https://docs.kde.org/stable_kf6/en/okular/okular/annotations.html)
  annotates many document formats; [calibre](https://manual.calibre-ebook.com/viewer.html)
  groups book highlights by chapter. Writing marks into every input format would create a separate
  editing and compatibility contract.
- Next: define stable location anchors and a versioned local sidecar store for highlights, notes
  and named bookmarks, starting with EPUB and PDF; expose source change/conflict status.
- Done when: marks survive reopen and layout changes across supported readers, navigate back to
  the intended content, can be exported, and never silently alter an original document.
- Related: app.scope.epub.001, app.scope.viewers.003

### app.scope.viewers.019 — Text documents have no read-aloud path

- Evidence: [Okular](https://docs.kde.org/stable_kf6/en/okular/okular/menutools.html),
  [Acrobat Reader](https://helpx.adobe.com/uk/acrobat/using/reading-pdfs-reflow-accessibility-features.html)
  and [calibre](https://manual.calibre-ebook.com/viewer.html) can speak document text. Swag Scope
  exposes no such action or spoken-position cue across its text-bearing viewers.
- Next: establish one reading-order and sentence-position contract, first for EPUB and tagged PDF;
  choose a built-in Swag speech path or an operating-system facility already present on the host,
  without a downloaded voice, helper executable or viewer dependency.
- Done when: supported documents can speak current selection or continue from the reading position,
  highlight the spoken passage, pause and resume, and clearly report when the host has no voice;
  opening and visual reading never depend on speech availability.
- Related: app.scope.epub.001, std.gui.pdf.042, app.scope.viewers.014

### app.scope.viewers.020 — Container previews have no shared provenance or resource budget

- Evidence: Archive extracts stored and Deflate ZIP members into temporary files and opens them
  through `EmbeddedViewer`. That host uses the complete registry, including Archive, so its model
  is not restricted to one container level. Each child shows a member title, but there is no
  composed container path, source byte-range/compression provenance, or shared extraction budget
  across descendants. RIFF, SCC, and Binary report assets do not use this child-file contract.
- Next: replace the temporary-path-only seam with a virtual child-file contract carrying parent
  identity, member path, source offset, compression, sizes, checksum, and a shared resource budget.
- Done when: nested supported content retains its complete container path and parent route,
  decompression work and resident bytes are bounded across levels, traversal names cannot choose
  output paths, and raw extraction remains an explicit action.
- Related: app.scope.archive.001

## Format coverage

`Today` uses **full** for a dedicated renderer, **structure** for a decoded `Binary` tree,
**signature** for identification and entropy only, **text** or **code** for those fallbacks, and
**none** for no format-specific interpretation beyond generic byte inspection. The owning backlog is linked from each unfinished row.

#### Text and documents

| Family | Extensions | Today | Missing | Entry |
| --- | --- | --- | --- | --- |
| Plain text | `.txt` | full, streamed | addresses, gutter, non-resident ranges | [app.scope.text.002](app.scope.text.md) |
| Key/value configuration | `.ini` `.cfg` `.conf` `.properties` `.env` | code and raw text | sections, keys, dialect diagnostics | [app.scope.config.002](app.scope.config.md) |
| Other encodings | UTF-16/32, Windows-1252 | full, detected and overridable | legacy encodings and diagnostics | [app.scope.text.004](app.scope.text.md) |
| Source code | registered extensions, common build/config names, and shebang scripts | full, lexer coloring, explained detection, per-file persistent overrides | outline, folding, overview | [app.scope.code.001](app.scope.code.md), [app.scope.code.002](app.scope.code.md), [app.scope.code.003](app.scope.code.md) |
| Markdown | `.md` `.markdown` | rendered and raw text with filterable heading outline | current-section tracking, synchronized source, resource diagnostics | [app.scope.markdown.001](app.scope.markdown.md) |
| HTML | `.html` `.htm` `.xhtml` | rendered, code, and raw text | DOM/source/resource inspection; advanced engine layout | [app.scope.html.002](app.scope.html.md), [HTML roadmap](std.gui.html.md) |
| Archived HTML | `.mht` `.mhtml` | generic fallbacks | qualify a local page and embedded resources in the format matrix | [app.scope.viewers.009](app.scope.viewers.md), [app.scope.html.004](app.scope.html.md) |
| JSON and JSON Lines | `.json` `.jsonl` | code and raw text | semantic tree, paths, schema facts | [app.scope.json.001](app.scope.json.md) |
| XML | `.xml` `.xsd` `.xsl` `.xslt` | code and raw text | namespace-aware tree and paths | [app.scope.xml.001](app.scope.xml.md) |
| YAML and TOML | `.yaml` `.yml` `.toml` | code and raw text | typed tree and paths | [app.scope.config.001](app.scope.config.md) |
| Diff and patch | `.diff` `.patch` | text | parsed files/hunks, intraline and side-by-side views | [app.scope.diff.001](app.scope.diff.md) |
| Log | `.log` | text | entries, start-at-tail/follow, queries, structured fields, timelines | [app.scope.log.001](app.scope.log.md), [app.scope.log.002](app.scope.log.md) |
| Subtitles | `.srt` `.vtt` `.ass` `.ssa` | searchable cue timeline, overlap markers, cue-aware copy/export with parser-loss counts | source/styled modes, media check | [app.scope.subtitle.002](app.scope.subtitle.md), [app.scope.subtitle.003](app.scope.subtitle.md) |
| Tabular text | `.csv` `.tsv` `.tab` | table up to 32 MiB, and raw text | bounded streaming, dialect, sort/filter, types | [app.scope.table.001](app.scope.table.md), [app.scope.table.002](app.scope.table.md) |
| PDF | `.pdf` | page rendering, bookmarks, page-label navigation, responsive page thumbnails in the outline, bounded page-range PNG export | partial pages, facing pages, region/table selection, embedded-asset inventory | [app.scope.pdf.001](app.scope.pdf.md), [app.scope.pdf.006](app.scope.pdf.md), [app.scope.pdf.009](app.scope.pdf.md), [std.gui.pdf.038](std.gui.pdf.md) |
| DOCX | `.docx` | inherited typography, styled headings/outline, paragraphs, tables, pictures, numbered/bulleted lists, bounded default header/footer text, referenced footnotes/endnotes, classic comments, nested tables, vertical merges across grid spans and safe HTTP(S)/mailto hyperlinks | authored pages, per-section layout, comment-range fidelity, complex tables/drawings and other external-link schemes | [app.scope.docx.001](app.scope.docx.md), [app.scope.docx.003](app.scope.docx.md), [app.scope.docx.004](app.scope.docx.md) |
| XLSX | `.xlsx` | virtual sheets, authored geometry, row/column defaults and common cell/numeric styles | unsaved blank-region styles, frozen panes and search | [app.scope.xlsx.001](app.scope.xlsx.md) |
| PPTX | `.pptx`, `.ppsx`, `.pptm` | fitted slides, basic geometry, one-level uniform groups, simple solid connectors, static tables with horizontal and vertical merges, signed bar/column/line charts, positive single-series pies and masters, title list, five-slide preview rail, text and notes modes; VBA remains inert; legacy presentations and templates receive explicit rejection | table widths/styles/legacy `hMerge`, complex grouped geometry and connector arrowheads, area/scatter/combo/stacked charts and authored chart colors, advanced text fidelity, omission details, full-screen reading and lazy slides | [app.scope.pptx.002](app.scope.pptx.md), [app.scope.pptx.004](app.scope.pptx.md), [app.scope.pptx.005](app.scope.pptx.md), [app.scope.pptx.006](app.scope.pptx.md), [app.scope.pptx.008](app.scope.pptx.md), [app.scope.pptx.009](app.scope.pptx.md), [app.scope.pptx.010](app.scope.pptx.md) |
| ODT | `.odt` | styled prose, headings/outline, lists, simple tables and embedded pictures | authored pages, drawings and annotations | [app.scope.odt.001](app.scope.odt.md) |
| ODS | `.ods` | native sheets, saved formatted values, inherited cell paint and common geometry | complete number styles, drawings, exact geometry and search | [app.scope.ods.001](app.scope.ods.md) |
| ODP | `.odp` | fitted slides, basic styles/masters, positioned text/pictures, title list, text and notes modes | complete drawings, master placeholders and lazy slides | [app.scope.odp.001](app.scope.odp.md) |
| Legacy Office | `.doc` `.xls` `.ppt` | signature | out of scope | — |
| EPUB | `.epub` | chapters, EPUB 2/3 contents, passage-preserving zoom/columns and back/forward | book search, persistent position, paged/flow reading | [app.scope.epub.001](app.scope.epub.md), [app.scope.epub.002](app.scope.epub.md) |
| Comic book | `.cbz` | natural-order single image pages, page jump and optional right-to-left keys | spreads, continuous scroll and saved position | [app.scope.comic.001](app.scope.comic.md) |
| RTF | `.rtf` | formatted prose, inline PNG/JPEG pictures, simple tables and named omissions | richer fidelity and encoding coverage | [app.scope.rtf.001](app.scope.rtf.md) |
| Mail | `.eml` `.msg` | printable mail as text; CFB signature for binary MSG | — | — |
| Notebook | `.ipynb` | ordered Markdown/code cells, plain text outputs/errors, heading outline; active MIME content omitted | cell search, metadata and attachments | [app.scope.notebook.001](app.scope.notebook.md) |
| reStructuredText, AsciiDoc | `.rst` `.adoc` | text | — | — |

#### Images

| Family | Extensions | Today | Missing | Entry |
| --- | --- | --- | --- | --- |
| Raster | `.bmp` `.gif` `.ico` `.jpg` `.png` `.qoi` `.tga` `.tiff` `.webp` | full | pixel, histogram, comparison, progressive huge-image tools | [app.scope.image.001](app.scope.image.md) |
| Vector | `.svg` | full | masks, radial focal points | std.pixel.image.010, std.pixel.image.008 |
| Metadata | EXIF, ICC, XMP | PNG text and EXIF; JPEG/WebP ICC color space, PCS and `desc`/`mluc` names; namespace-qualified XMP title, creator, description, rights, subject, dates and creator tool | other ICC formats, other XMP schemas, color management | [app.scope.image.003](app.scope.image.md) |
| Simple raster | `.pnm` `.ppm` | none | Pixel codecs | — |
| HEIF still images | `.heic` | none | qualify still-image profiles and orientation first | [app.scope.viewers.009](app.scope.viewers.md) |
| Other modern codecs | `.avif` `.jxl` | none | Pixel codecs | std.pixel.image.026, std.pixel.image.027 |
| High dynamic range | `.exr` `.hdr` | EXR images and indexed parts | Radiance HDR codec | — |
| Layered | `.psd` `.xcf` | PSD composite and bounded indexed layer selector; XCF signature | — | — |
| GPU textures | `.dds` `.ktx2` | indexed levels, layers, faces, slices and visible-first bounded thumbnails; BC1–BC5 decode | compressed upload | std.pixel.image.041, std.pixel.image.042 |
| Camera RAW | `.cr2` `.nef` `.arw` `.dng` | signature | embedded preview extraction | [app.scope.image.012](app.scope.image.md) |

#### Audio and video

| Family | Extensions | Today | Missing | Entry |
| --- | --- | --- | --- | --- |
| WAV PCM and float | `.wav` | full, streamed | professional transport/analysis | [app.scope.audio.001](app.scope.audio.md) |
| Raw YUV4MPEG2 video | `.y4m` | full, silent, streamed by frame | the format carries no sound | — |
| Motion JPEG video | `.avi` `.mp4` `.m4v` `.mov` | full with supported container audio and generic chroma sampling | professional transport/inspection | [app.scope.video.001](app.scope.video.md) |
| Compressed audio | `.mp3` `.flac` `.aac` `.ac3` `.eac3` `.ec3` `.dts` `.ogg` `.oga` `.opus` | full, streamed | professional transport/analysis | [app.scope.audio.001](app.scope.audio.md) |
| MP4 audio | `.m4a` | AAC elementary streams and AAC in video containers | standalone AAC-in-M4A playback and MP4 tags | [app.scope.viewers.009](app.scope.viewers.md), [app.scope.audio.008](app.scope.audio.md) |
| Video containers | `.mp4` `.mkv` `.webm` `.mov` `.avi` | AVI structure; others identified | ISO-BMFF and EBML trees | [app.scope.binary.011](app.scope.binary.md) |
| Video playback | `.avi` `.mp4` `.m4v` `.mov` `.mkv` | Motion JPEG, uncompressed AVI, H.264, H.265, MPEG-4 Part 2 | professional transport/inspection; VP9 and AV1 | [app.scope.video.001](app.scope.video.md), [std.video.010](std.video.md), [std.video.011](std.video.md) |
| MIDI | `.mid` `.midi` | piano roll and structure | playback, event lanes, scalable timeline, optional score | [app.scope.midi.001](app.scope.midi.md), [app.scope.midi.014](app.scope.midi.md) |

#### Binaries, containers, and developer artifacts

| Family | Extensions | Today | Missing | Entry |
| --- | --- | --- | --- | --- |
| Windows images | `.exe` `.dll` `.sys` | structure | — | — |
| COFF and archives | `.obj` `.lib` `.a` | structure | — | — |
| ELF and Mach-O | `.so` `.elf` `.dylib` | structure | — | — |
| WebAssembly | `.wasm` | structure | — | — |
| RIFF | `.wav` `.avi` | structure | — | — |
| Swag chunk container | `.scc` | structure through `Core.Scc` | — | — |
| ZIP family | `.zip` `.jar` `.apk` `.vsix` | full tree and stored/Deflate entry preview | nested provenance, archive-wide integrity, encrypted/variant policy | [app.scope.viewers.020](app.scope.viewers.md), [app.scope.archive.002](app.scope.archive.md) |
| Other archives | `.7z` `.rar` `.tar` `.gz` `.xz` `.zst` `.cab` `.msi` | signature | listing, `tar`/`gzip` first | [app.scope.archive.001](app.scope.archive.md) |
| TrueType fonts | `.ttf` `.ttc` | specimen, collection-face selector, and character map | glyph/metric/coverage inspection | [app.scope.font.002](app.scope.font.md), [app.scope.font.003](app.scope.font.md) |
| CFF and web fonts | `.otf` `.woff` `.woff2` | CFF OpenType specimen; WOFF1 font engine | WOFF1 viewer routing; WOFF2 support | [std.truetype.002](std.truetype.md) |
| Program databases | `.pdb` | signature | MSF streams and CodeView match | [app.scope.binary.014](app.scope.binary.md) |
| Databases | `.sqlite` `.db` | signature | schema and bounded table browse | [app.scope.binary.012](app.scope.binary.md) |
| Certificates and keys | `.pem` `.der` `.crt` `.p12` | printable PEM as text; binary inspection otherwise | ASN.1 and X.509 decode | [app.scope.binary.013](app.scope.binary.md) |
| Managed code | `.class` `.dex` | signature | — | — |
| Crash dumps | `.dmp` | none | — | — |
| Disk images | `.iso` `.vhd` | none | — | — |
| Unknown | any | size and entropy; signature only when recognized | — | — |

---
