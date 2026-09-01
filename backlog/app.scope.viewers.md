# Swag Scope Shared Viewer Backlog

This backlog covers contracts, behavior, coverage, and product boundaries shared by several
Swag Scope viewers. A capability owned by one viewer lives in its `scope.<viewer>.md` file;
window lifecycle, document management, and operating-system integration live in
[app.scope.md](app.scope.md). Reusable engine work remains in the owning standard-module backlog.

## Where the viewer family already stands

**Bounded streaming is the real differentiator.** The hexadecimal viewer keeps one 256 KiB window
aligned to 64 KiB, host search advances in asynchronous 256 KiB chunks, proportional scrollbars
keep distant offsets reachable, and `revealMatch` lets a viewer materialize only the window that
contains a hit. A multi-gigabyte file opens without first being materialized.

**Read-only, offline, nothing executes.** No script, embedded document, remote style sheet, or
network resource executes. For looking at a file before trusting it, that constraint is part of
the product rather than an absent editing feature.

**Hexadecimal, structure, and one host search read the same file.** The `Binary` viewer reports
field, value, offset, and meaning for the formats it recognizes, while every file retains the
hexadecimal fallback. Search hits can be revealed without loading preceding content.

**Every viewer ships in one executable.** Direct function bindings keep the viewer contract small
and remove plugin ABI, dynamic-loading, packaging, and version-skew failure modes.

## Professional baseline used by this audit

The backlog does not copy editing scope into this read-only application. It uses established
professional readers and inspectors to identify navigation, inspection, presentation, accessibility,
and interchange expectations, then keeps only outcomes compatible with Swag Scope's offline,
bounded, non-modifying role:

- [Apple Quick Look](https://support.apple.com/guide/mac-help/preview-a-file-mh14119/mac) and the
  [Windows preview-handler model](https://learn.microsoft.com/en-us/windows/win32/shell/preview-handlers)
  for selection-to-preview latency, adjacent-file browsing, shell hosting, bounded lifetime, and
  low-integrity out-of-process isolation.
- [Visual Studio Code basic editing](https://code.visualstudio.com/docs/editing/codebasics) and
  [code navigation](https://code.visualstudio.com/docs/editing/editingevolved) for line/symbol
  navigation, folding, overview, history, and discoverable commands.
- [Visual Studio Code JSON](https://code.visualstudio.com/docs/languages/json) for property
  navigation, structural folding, schema explanation, and an explicit offline policy.
- [Visual Studio Code Markdown](https://code.visualstudio.com/docs/languages/markdown) for outline,
  source/preview synchronization, link validation, and explicit preview security.
- [GitHub's non-code file views](https://docs.github.com/en/repositories/working-with-files/using-files/working-with-non-code-files)
  and [Visual Studio Code notebooks](https://code.visualstudio.com/docs/datascience/jupyter-notebooks)
  for static notebook rendering, cell/output search, outline, rich comparison, and suppression of
  active output from untrusted notebooks.
- [Adobe Acrobat page thumbnails and bookmarks](https://helpx.adobe.com/acrobat/using/page-thumbnails-bookmarks-pdfs.html)
  for long-document page and destination navigation.
- [LibreOffice CSV import](https://help.libreoffice.org/latest/en-US/text/scalc/guide/csv_files.html)
  and [frozen rows and columns](https://help.libreoffice.org/latest/en-US/text/scalc/guide/line_fix.html)
  for explicit table dialect, typed columns, sorting/filtering, and stable headers.
- [Audacity playback](https://manual.audacityteam.org/man/playback.html) for range selection and
  looping over a waveform.
- [VLC playback](https://docs.videolan.me/vlc-user/desktop/3.0/en/basic/playback.html) for media
  bookmarks, chapter navigation, and direct time addressing.
- [Gwenview](https://docs.kde.org/stable_kf6/en/gwenview/gwenview/gwenview.pdf) for metadata-aware,
  color-managed image reading.
- [FontForge's font view](https://fontforge.org/docs/ui/mainviews/fontview.html) and
  [metrics view](https://fontforge.org/docs/ui/mainviews/metricsview.html) for glyph addressing,
  metrics, coverage, and OpenType-feature inspection.
- [Subtitle Edit](https://github.com/SubtitleEdit/docs) for source/list modes, cue quality
  indicators, video, waveform/spectrogram, synchronization, and shortcut-driven navigation.
- [MuseScore Studio](https://handbook.musescore.org/) for score navigation, timeline, mixer,
  playback, and configurable MIDI import.
- [7-Zip](https://www.7-zip.org/) for broad archive-family coverage and its explicit Test/CRC
  workflow, and [010 Editor Binary Templates](https://www.sweetscape.com/010editor/manual/IntroTemplates.htm)
  for reusable hierarchical byte-to-field inspection.

## Registered viewer audit map

`createViewerPluginRegistry` registers fifteen viewers. The September 2026 audit found one focused
test file per viewer, 123 tests in those files, and 25 viewer-specific PNG goldens. Tests elsewhere
in the application add host search, replacement, streaming, and lifecycle coverage. The counts are
an audit snapshot, not a target: new behavior must add the state or interaction that proves it.

| Viewer | Tests / goldens | Current core | Professional frontier and owner |
| --- | ---: | --- | --- |
| Archive | 6 / 1 | ZIP tree, stored/Deflate verification, entry preview through the normal viewer registry | nested provenance and 7-Zip-class format breadth; [app.scope.binary.008](app.scope.binary.md), [app.scope.binary.010](app.scope.binary.md) |
| Binary | 23 / 4 | bounded hierarchical format reports, previews, navigation, filtering | reusable 010-Editor-class declarative schemas and findings; [app.scope.binary.md](app.scope.binary.md) |
| Code | 7 / 1 | bounded streamed source with lexical coloring and search | VS Code-class outline, folding, breadcrumbs, minimap, structure cues, references; [app.scope.text.md](app.scope.text.md#source-code) |
| Font | 4 / 2 | specimen plus paged glyph map | FontForge-class faces, glyph addressing, metrics, OpenType features, validation; [app.scope.font.md](app.scope.font.md) |
| Hexadecimal | 25 / 4 | bounded typed grid, search inspector, analysis, offsets | templates, diff, structure links, accessibility; [app.scope.hexa.md](app.scope.hexa.md) |
| HTML | 3 / 1 | safe offline rendered document, zoom, visible-text search | DOM/source/box inspection, resource ledger, local history; [app.scope.document.md](app.scope.document.md#html-reading) |
| Image | 4 / 1 | pan, zoom, fit, rotation, mirroring, animated frames | Gwenview-class color/metadata plus histogram, pixel probe, comparison; [app.scope.image.md](app.scope.image.md) |
| Markdown | 7 / 2 | rendered themes, reading measures, progressive layout, search | VS Code-class outline, synchronized source, resource security diagnostics; [app.scope.document.md](app.scope.document.md#markdown-reading) |
| MIDI | 3 / 1 | parsed tracks, notes, tempo/meter/key and piano roll | MuseScore-class playback, mixer/event lanes, scalable timeline; [app.scope.midi.md](app.scope.midi.md) |
| PDF | 5 / 2 | page rendering, search, page jump, fit and zoom | Acrobat-class thumbnails, bookmarks, continuous/facing layouts, components; [app.scope.document.md](app.scope.document.md#pdf-presentation) |
| Sound | 9 / 1 | streamed playback, seek, volume/mute and bounded waveform | Audacity-class ranges, loop/scrub, spectrogram, meters and analysis; [app.scope.audio.md](app.scope.audio.md) |
| Subtitle | 3 / 1 | timed searchable transcript with validated cue/time jumps | Subtitle Edit-class current-cue timeline, waveform/media check, source/styled modes; [app.scope.text.md](app.scope.text.md#timed-text) |
| Table | 5 / 1 | parsed CSV/TSV grid and cell search | Calc-class dialect control, typed columns, sort/filter, fixed-width input, bounded rows; [app.scope.text.md](app.scope.text.md#tabular-text) |
| Text | 2 / 1 | bounded decoded stream, encoding override, wrap, zoom, statistics and search | raw alternatives, address/gutter, result panes, bookmarks, Unicode and pathological lines; [app.scope.text.md](app.scope.text.md#shared-text-reading) |
| Video | 17 / 2 | progressive A/V playback, seek, tracks, subtitles and frame stepping | VLC-class chapters, bookmarks, direct frame/time addressing, inspection; [app.scope.video.md](app.scope.video.md) |

## Shared reading behavior

### app.scope.viewers.001 — Select-all in a streamed document silently means the resident window

- Evidence: the basic text and `Code` viewers use `RichEditCtrl`; Ctrl+A selects only their
  resident 256 KiB window. The Markdown viewer likewise selects only materialized blocks. The
  `Hexadecimal` viewer is the positive example because its bounded copy command names its 1 MiB
  limit before copying.
- Next: define one shared streamed-selection contract and apply it to basic text, Code, and
  Markdown without making a multi-gigabyte copy resident.
- Complete when: select-all reaches the whole file or the copy command says exactly which bounded
  part will leave, before the user pastes it.

### app.scope.viewers.002 — A document cannot be printed

- Intent: a viewer that renders a document should be able to put it on paper through the same
  pagination contract as the rest of the GUI rather than through application-local paths.
- Next: define the application adapter once the GUI pagination and preview contract is ready.
- Complete when: text, code, Markdown, HTML, image, and hexadecimal dump views print through that
  contract, with actual-size or fit-to-page choices where they have meaning.
- Related: std.gui.030, std.gui.031, std.gui.034

### app.scope.viewers.003 — Viewer state is forgotten when a file or application closes

- Evidence: viewer-local choices such as zoom, fit mode, wrapping, encoding, selected track,
  playback volume, page, and scroll position live only in the current widget instance. Reopening a
  file always reconstructs a default view.
- Next: define versioned global defaults plus per-file state keyed by stable file identity, with an
  explicit list of safe fields each viewer may persist.
- Complete when: every registered viewer restores its useful reading state, stale identity never
  applies state to a replacement file, and one command resets either the current viewer or all
  viewer preferences.

### app.scope.viewers.004 — Long viewer operations have no common progress and cancellation contract

- Evidence: viewers independently use workers and the host loading overlay, but parsing, indexing,
  waveform building, rendering, and search cannot consistently report units completed, yield a
  partial result, or distinguish cancellation from failure.
- Next: extend `ViewerCreateResult` with cancellable phases, determinate or indeterminate progress,
  partial-publication rules, and a shared terminal status.
- Complete when: opening and analysis operations remain interruptible, replacement files retire old
  work promptly, the overlay names the current phase, and cancellation never becomes an error.
- Related: app.scope.hexa.006, std.gui.pdf.029

### app.scope.viewers.005 — External file replacement and growth have no viewer-wide reload policy

- Evidence: each viewer snapshots different combinations of path, size, decoded content, and open
  streams. A file changed by a build, download, logger, or editor can leave rendered content,
  offsets, matches, and metadata disagreeing without a shared notification.
- Next: add a host-owned file identity/version watcher and a viewer callback that can reload,
  follow append-only growth, or keep a labelled snapshot.
- Complete when: atomic replacement, append, truncation, deletion, and permission loss are
  distinguished; stale search results are retired; reload can preserve a valid logical position;
  and each viewer states whether live following is supported.
- Related: app.scope.hexa.008, app.scope.text.023

### app.scope.viewers.006 — File facts are scattered across terse summaries instead of one inspectable panel

- Evidence: the host shows size and one viewer-supplied details string, while timestamps, canonical
  path, detected format, MIME claim, file identity, hashes, decoder choice, warnings, and
  format-specific metadata are either absent or hidden inside a viewer.
- Next: define a read-only information panel with common sections and an extension point for
  viewer-owned properties and warnings.
- Complete when: facts are selectable and copyable, byte sizes and dates have exact forms, format
  detection explains its evidence, hashes are cancellable for large files, and viewers can link a
  property to the content it describes.
- Related: app.scope.hexa.017, app.scope.image.011

### app.scope.viewers.007 — Custom-painted viewers cannot expose a professional accessibility model

- Evidence: image, waveform, piano-roll, font-map, video-overlay, and hexadecimal surfaces paint
  meaning without semantic children. The toolkit itself still has no accessibility bridge, so
  keyboard focus alone cannot describe values, ranges, selection, or playback state.
- Next: specify the semantic tree and keyboard contract for every custom viewer while platform.portability.048 builds
  the toolkit bridge, beginning with roles, names, values, bounds, and change notifications.
- Complete when: each viewer has an accessibility fixture, all actions are keyboard reachable,
  focus order is stable, animation and playback state are announced without flooding, and the
  shipped platform bridge exposes the same model.
- Related: platform.portability.048, app.scope.hexa.014

### app.scope.viewers.008 — Viewer commands have no common discoverability or remapping surface

- Evidence: viewer commands now occupy one centered lower band, while dynamic zoom/page/range
  values use consistent clickable controls in the information band. Some operations remain split
  between compact menus, context menus, and hard-coded key handlers; there is no command palette,
  shortcut reference, conflict check, or consistent disabled-state explanation.
- Next: register viewer actions as named commands with default gestures, applicability, and a
  discoverable description before adding a palette and shortcut sheet.
- Complete when: every non-pointer-only action can be found and invoked by name, shortcuts can be
  inspected and remapped, conflicts are reported, and toolbar/menu/key execution share one state.
- Related: app.scope.hexa.016, std.gui.010

### app.scope.viewers.009 — The viewer family has no release-quality compatibility matrix

- Evidence: all fifteen viewers now have focused tests and a viewer-specific golden, but fixture
  depth still ranges from two owning Text tests plus host integration cases to the large Binary,
  Hexadecimal, and Video suites. The audit still found no declared matrix for real-world variants,
  malformed input, large files, cancellation, keyboard-only use, themes, DPI, memory ceilings, or
  selection-to-first-content latency under rapid adjacent-file browsing.
- Next: publish one matrix per registered viewer with representative public fixtures, required
  malformed cases, bounded-resource assertions, interaction checks, visual states, and time-to-first-
  content budgets for cold open, warm open, and replacement before the previous viewer settles.
- Complete when: the application smoke validates every registered viewer in light and dark themes,
  the matrix names unsupported variants honestly, corpus licences are recorded, and regressions in
  format choice, cancellation, accessibility, resource bounds, or preview latency fail a focused suite.

### app.scope.viewers.010 — Eight viewers keep stale chrome after a live language change

- Evidence: Archive, Binary, Font, Hexadecimal, MIDI, Text, and Video handle `LanguageChanged` and
  now have focused tests for that path. Code, HTML, Image, Markdown, PDF, Sound, Subtitle, and Table
  own localized tooltips, labels, menus, or details but do not refresh them until the viewer is
  recreated. Text previously refreshed only its statistics line; its wrap, encoding, and zoom
  tooltips were stale until this audit.
- Next: give every remaining viewer one idempotent `retranslate` method, update dynamic state text
  without resetting selection/playback/scroll, and exercise the live transition in its owning test.
- Complete when: switching among every shipped language updates all visible and tooltip text in
  every viewer without reconstructing it, changing its logical state, or leaving mixed-language
  chrome, and the fifteen focused suites protect the behavior.

### app.scope.viewers.011 — Attacker-controlled decoders share the application process

- Evidence: every registered viewer is a direct function callback compiled into `swagscope.exe`.
  A malformed image, font, document, archive, or media stream therefore reaches its decoder in the
  process that owns the window, history, clipboard access, and ordinary user token. Read-only and
  offline prevent intentional document actions, but they do not contain a parser defect. Windows
  preview handlers establish the relevant baseline: they run out of process, use low integrity by
  default, and prefer a stream so the host controls what the preview can read.
- Next: define a brokered open/render/report contract over host-owned read-only ranges, then move one
  high-risk decoder family into a disposable worker with CPU, memory, time, file, network, process,
  and write limits before generalizing the boundary.
- Complete when: decoder crash, hang, resource exhaustion, and malformed output cannot terminate or
  corrupt the main window; the worker cannot open arbitrary paths, write, use the network, or spawn
  processes; results are versioned and size-checked; cancellation kills only the affected job; and
  failure leaves the file available through bounded hexadecimal inspection.
- Related: app.scope.viewers.004, app.scope.viewers.009, platform.portability.040,
  platform.portability.072

### app.scope.viewers.012 — The viewer API cannot load an external viewer

- Evidence: `Viewer.Plugin` already carries an API version, stable key, selectors, icon, localized
  name, smoke fixture, and creation callback, but `createViewerPluginRegistry` names every plugin in
  source and the README explicitly records no runtime index, dynamic library, exported entry point,
  or ABI adapter. Quick Look extensions and 010 Editor's shared template repository show the value
  of adding formats without rebuilding the host; their distribution risks also make an unversioned,
  in-process library the wrong next step.
- Next: define a local manifest and capability-negotiated wire contract on top of
  app.scope.viewers.011, including publisher identity, package provenance, selector precedence,
  compatibility ranges, resource limits, translations, icons, and an explicit install/update policy.
- Complete when: a separately packaged viewer can be installed, disabled, updated, and removed
  without rebuilding Swag Scope; incompatible, crashing, and duplicate-key packages are quarantined
  with an exact reason; built-ins retain deterministic precedence; and no external viewer executes
  in the application or shell-host process.
- Related: app.scope.viewers.011, platform.portability.072, platform.portability.073

## Format coverage

`Today` uses **full** for a dedicated renderer, **structure** for a decoded `Binary` tree,
**signature** for identification and entropy only, **text** or **code** for those fallbacks, and
**none** for the hexadecimal fallback alone. The owning backlog is linked from each unfinished row.

#### Text and documents

| Family | Extensions | Today | Missing | Entry |
| --- | --- | --- | --- | --- |
| Plain text | `.txt` | full, streamed | addresses, gutter, non-resident ranges | [app.scope.text.002](app.scope.text.md) |
| Key/value configuration | `.ini` `.cfg` `.conf` `.properties` `.env` | code; no raw text | raw text, sections, keys, dialect diagnostics | [app.scope.text.025](app.scope.text.md), [app.scope.text.040](app.scope.text.md) |
| Other encodings | UTF-16/32, Windows-1252 | full, detected and overridable | legacy encodings and diagnostics | [app.scope.text.004](app.scope.text.md) |
| Source code | registered extensions, common build/config names, and shebang scripts | full, lexer coloring | outline, folding, overview | [app.scope.text.006](app.scope.text.md) |
| Markdown | `.md` `.markdown` | rendered; no raw text | raw text, outline, synchronized source, resource diagnostics | [app.scope.text.025](app.scope.text.md), [app.scope.document.001](app.scope.document.md) |
| HTML | `.html` `.htm` `.xhtml` | rendered and code | basic text, DOM/source/resource inspection; advanced engine layout | [app.scope.text.025](app.scope.text.md), [app.scope.document.006](app.scope.document.md), [HTML roadmap](std.gui.html.md) |
| JSON and JSON Lines | `.json` `.jsonl` | code / signature | raw text, semantic tree, paths, schema facts | [app.scope.text.024](app.scope.text.md), [app.scope.text.025](app.scope.text.md) |
| XML | `.xml` `.xsd` `.xsl` `.xslt` | code | raw text, namespace-aware tree and paths | [app.scope.text.025](app.scope.text.md), [app.scope.text.038](app.scope.text.md) |
| YAML and TOML | `.yaml` `.yml` `.toml` | code | raw text, typed tree and paths | [app.scope.text.025](app.scope.text.md), [app.scope.text.039](app.scope.text.md) |
| Diff and patch | `.diff` `.patch` | text | parsed files/hunks, intraline and side-by-side views | [app.scope.text.022](app.scope.text.md) |
| Log | `.log` | text | entries, tail/follow, queries, structured fields, timelines | [app.scope.text.023](app.scope.text.md), [app.scope.text.034](app.scope.text.md) |
| Subtitles | `.srt` `.vtt` `.ass` `.ssa` | timed transcript with cue/time jump | previous/next/current cue, timeline, source/styled modes, media check | [app.scope.text.011](app.scope.text.md) |
| Tabular text | `.csv` `.tsv` `.tab` | table up to 32 MiB; no raw text | raw text, bounded streaming, dialect, sort/filter, types | [app.scope.text.015](app.scope.text.md), [app.scope.text.016](app.scope.text.md), [app.scope.text.025](app.scope.text.md) |
| PDF | `.pdf` | page rendering | partial pages, thumbnails, outline, layout modes | [app.scope.document.011](app.scope.document.md), [app.scope.document.012](app.scope.document.md), [std.gui.pdf.md](std.gui.pdf.md) |
| Office OOXML | `.docx` `.xlsx` `.pptx` | structure | readable text and sheets | [app.scope.document.020](app.scope.document.md) |
| OpenDocument | `.odt` `.ods` `.odp` | structure | readable text and sheets | [app.scope.document.020](app.scope.document.md) |
| Legacy Office | `.doc` `.xls` `.ppt` | signature | out of scope | — |
| EPUB | `.epub` | structure | spine read through `HtmlView` | [app.scope.document.021](app.scope.document.md) |
| RTF | `.rtf` | signature | raw text or a safe document renderer | [app.scope.text.025](app.scope.text.md) |
| Mail | `.eml` `.msg` | none | — | — |
| Notebook | `.ipynb` | signature | raw JSON plus safe rendered cells and stored outputs | [app.scope.text.025](app.scope.text.md), [app.scope.document.022](app.scope.document.md) |
| reStructuredText, AsciiDoc | `.rst` `.adoc` | text | — | — |

#### Images

| Family | Extensions | Today | Missing | Entry |
| --- | --- | --- | --- | --- |
| Raster | `.bmp` `.gif` `.ico` `.jpg` `.png` `.qoi` `.tga` `.tiff` `.webp` | full | pixel, histogram, comparison, progressive huge-image tools | [app.scope.image.001](app.scope.image.md) |
| Vector | `.svg` | full | masks, radial focal points | std.pixel.image.010, std.pixel.image.008 |
| Metadata | EXIF, ICC, XMP | none | panel, orientation, color management | [app.scope.image.011](app.scope.image.md) |
| Simple raster | `.pnm` `.ppm` | none | Pixel codecs | — |
| Modern codecs | `.avif` `.heic` `.jxl` | none | Pixel codecs | std.pixel.image.026, std.pixel.image.027 |
| High dynamic range | `.exr` `.hdr` | EXR flattened image | Radiance HDR codec | — |
| Layered | `.psd` `.xcf` | PSD flattened composite; XCF signature | layer collection model | [app.scope.image.008](app.scope.image.md) |
| GPU textures | `.dds` `.ktx2` | base image, including BC1–BC5 decode | mip/array selection and compressed upload | std.pixel.image.041, std.pixel.image.042 |
| Camera RAW | `.cr2` `.nef` `.arw` `.dng` | signature | embedded preview extraction | [app.scope.image.012](app.scope.image.md) |

#### Audio and video

| Family | Extensions | Today | Missing | Entry |
| --- | --- | --- | --- | --- |
| WAV PCM and float | `.wav` | full, streamed | professional transport/analysis | [app.scope.audio.001](app.scope.audio.md) |
| Raw YUV4MPEG2 video | `.y4m` | full, silent, streamed by frame | the format carries no sound | — |
| Motion JPEG video | `.avi` `.mp4` `.m4v` `.mov` | full with supported container audio and generic chroma sampling | professional transport/inspection | [app.scope.video.001](app.scope.video.md) |
| Compressed audio | `.mp3` `.flac` `.aac` `.ac3` `.eac3` | full, streamed | professional transport/analysis | [app.scope.audio.001](app.scope.audio.md) |
| Video containers | `.mp4` `.mkv` `.webm` `.mov` `.avi` | AVI structure; others identified | ISO-BMFF and EBML trees | [app.scope.binary.011](app.scope.binary.md) |
| Video playback | `.avi` `.mp4` `.m4v` `.mov` `.mkv` | Motion JPEG, uncompressed AVI, H.264, H.265, MPEG-4 Part 2 | professional transport/inspection; VP9 and AV1 | [app.scope.video.001](app.scope.video.md), [app.scope.video.014](app.scope.video.md) |
| MIDI | `.mid` `.midi` | piano roll and structure | playback, event lanes, scalable timeline | [app.scope.midi.001](app.scope.midi.md) |

#### Binaries, containers, and developer artifacts

| Family | Extensions | Today | Missing | Entry |
| --- | --- | --- | --- | --- |
| Windows images | `.exe` `.dll` `.sys` | structure, complete | — | — |
| COFF and archives | `.obj` `.lib` `.a` | structure | — | — |
| ELF and Mach-O | `.so` `.elf` `.dylib` | structure | — | — |
| WebAssembly | `.wasm` | structure | — | — |
| RIFF | `.wav` `.avi` | structure | — | — |
| Swag chunk container | `.scc` | structure through `Core.Scc` | — | — |
| ZIP family | `.zip` `.jar` `.apk` `.vsix` | full tree and stored/Deflate entry preview | nested archive provenance, encryption, more methods | [app.scope.binary.008](app.scope.binary.md), [app.scope.binary.010](app.scope.binary.md) |
| Other archives | `.7z` `.rar` `.tar` `.gz` `.xz` `.zst` `.cab` `.msi` | signature | listing, `tar`/`gzip` first | [app.scope.binary.010](app.scope.binary.md) |
| TrueType fonts | `.ttf` `.ttc` | specimen and first-face character map | face selector, glyph/metric/coverage inspection | [app.scope.font.001](app.scope.font.md) |
| CFF and web fonts | `.otf` `.woff` `.woff2` | OTF specimen; WOFF structure | professional inspection; WOFF containers | [app.scope.font.001](app.scope.font.md), std.truetype.001, std.truetype.002 |
| Program databases | `.pdb` | signature | MSF streams and CodeView match | [app.scope.binary.014](app.scope.binary.md) |
| Databases | `.sqlite` `.db` | signature | schema and bounded table browse | [app.scope.binary.012](app.scope.binary.md) |
| Certificates and keys | `.pem` `.der` `.crt` `.p12` | none | ASN.1 and X.509 decode | [app.scope.binary.013](app.scope.binary.md) |
| Managed code | `.class` `.dex` | signature | — | — |
| Crash dumps | `.dmp` | none | — | — |
| Disk images | `.iso` `.vhd` | none | — | — |
| Unknown | any | signature, size, entropy | — | — |

## Out of scope

**Editing anything.** Read-only is the product guarantee. Byte replacement, insertion, deletion,
undo, save, raw-disk writing, and process-memory writing belong to a different application and risk
model.

**Format conversion and batch processing.** They require a write path this application deliberately
does not have.

**Legacy binary Office rendering.** `.doc`, `.xls`, and `.ppt` do not justify a fidelity claim; the
CFB structure is what the `Binary` viewer can honestly show.

**Packer and protector identification.** A signature database maintained against active evasion is
not a durable repository capability. Entropy and an honest signature line are.

**Hosted and cloud formats.** They would embed third-party credentials in a compiler repository.

**3D model preview.** Pixel is a 2D renderer, and an untrusted wireframe is not worth the subsystem.
