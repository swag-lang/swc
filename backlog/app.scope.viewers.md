# Swag Scope Shared Viewer Backlog

This backlog covers contracts, behavior, coverage, and product boundaries shared by several
Swag Scope viewers. A capability owned by one viewer lives in its `app.scope.<viewer>.md` file;
window lifecycle and document management live in [app.scope.md](app.scope.md), while operating-system
integration belongs to [platform.portability.md](platform.portability.md). Reusable engine work remains in the owning standard-module backlog.

## Where the viewer family already stands

**Several readers stream bounded windows.** The hexadecimal viewer keeps one 256 KiB window
aligned to 64 KiB. Host file search reads 256 KiB chunks on timer ticks, although generic regular
expressions retain the whole source before matching. Proportional scrollbars and `revealMatch`
keep distant offsets reachable in the streamed text and hexadecimal readers. Whole-document
decoders and archive entry previews have their own limits; this is not a universal memory bound.

**Read-only, offline, nothing executes.** No script, embedded document, remote style sheet, or
network resource executes. For looking at a file before trusting it, that constraint is part of
the product rather than an absent editing feature.

**Hexadecimal, structure, and one host search read the same file.** The `Binary` viewer reports
field, value, offset, and meaning for the formats it recognizes, while every file retains the
hexadecimal fallback. Search hits can be revealed without loading preceding content.

**Every viewer ships in one executable.** Direct function bindings keep the viewer contract small
and remove plugin ABI, dynamic-loading, packaging, and version-skew failure modes.

## Registered viewer audit map

`createViewerPluginRegistry` registers seventeen viewers. Each has a focused test file; tests
elsewhere in the application add host search, replacement, streaming, and lifecycle coverage.
The linked owning suites are the live audit map; new behavior must add the state or interaction
that proves it.

| Viewer | Owning suite | Current core | Remaining reading capabilities and owner |
| --- | --- | --- | --- |
| Archive | [tests](../bin/apps/modules/swagscope/src/tests/viewer.archive.test.swg) | ZIP tree, stored/Deflate verification, entry preview through the normal viewer registry | nested provenance and format breadth; [app.scope.binary.008](app.scope.binary.md), [app.scope.binary.010](app.scope.binary.md) |
| Binary | [tests](../bin/apps/modules/swagscope/src/tests/viewer.binary.test.swg) | bounded hierarchical format reports, previews, navigation, filtering | reusable declarative schemas and findings; [app.scope.binary.md](app.scope.binary.md) |
| Code | [tests](../bin/apps/modules/swagscope/src/tests/viewer.code.test.swg) | bounded streamed source with lexical coloring and search | outline, folding, breadcrumbs, minimap, structure cues, references; [app.scope.text.md](app.scope.text.md) |
| Font | [tests](../bin/apps/modules/swagscope/src/tests/viewer.font.test.swg) | specimen plus paged glyph map | faces, glyph addressing, metrics, OpenType features, validation; [app.scope.font.md](app.scope.font.md) |
| Hexadecimal | [tests](../bin/apps/modules/swagscope/src/tests/viewer.hex.test.swg) | bounded typed grid, search inspector, analysis, offsets | templates, diff, structure links, accessibility; [app.scope.hexa.md](app.scope.hexa.md) |
| HTML | [tests](../bin/apps/modules/swagscope/src/tests/viewer.html.test.swg) | safe offline rendered document, zoom, visible-text search | DOM/source/box inspection, resource ledger, local history; [app.scope.document.md](app.scope.document.md) |
| Image | [tests](../bin/apps/modules/swagscope/src/tests/viewer.image.test.swg) | pan, zoom, fit, rotation, mirroring, animated and independent image sets | color/metadata plus histogram, pixel probe, comparison; [app.scope.image.md](app.scope.image.md) |
| InDesign | [tests](../bin/apps/modules/swagscope/src/tests/viewer.indesign.test.swg) | bounded native preview and IDML page reader | page composition, text selection, object inventory, and output fidelity; [InDesign roadmap](app.scope.indesign.md) |
| Markdown | [tests](../bin/apps/modules/swagscope/src/tests/viewer.markdown.test.swg) | rendered themes, reading measures, progressive layout, search | outline, synchronized source, resource security diagnostics; [app.scope.document.md](app.scope.document.md) |
| MIDI | [tests](../bin/apps/modules/swagscope/src/tests/viewer.midi.test.swg) | parsed tracks, notes, tempo/meter/key and piano roll | playback, mixer/event lanes, scalable timeline; [app.scope.midi.md](app.scope.midi.md) |
| OpenDocument | [tests](../bin/apps/modules/swagscope/src/tests/viewer.opendocument.test.swg) | safe ODT/ODS/ODP/ODG text, sheets, slides, and pages | complete ODF semantics, layout, accessibility, and conformance; [OpenDocument roadmap](app.scope.opendocument.md) |
| PDF | [tests](../bin/apps/modules/swagscope/src/tests/viewer.pdf.test.swg) | continuous page rendering, cross-page selection/copy, search, page jump, fit and zoom | thumbnails, bookmarks, facing layouts, components; [app.scope.document.md](app.scope.document.md) |
| Sound | [tests](../bin/apps/modules/swagscope/src/tests/viewer.sound.test.swg) | streamed playback, seek, volume/mute and bounded waveform | ranges, loop/scrub, spectrogram, meters and analysis; [app.scope.audio.md](app.scope.audio.md) |
| Subtitle | [tests](../bin/apps/modules/swagscope/src/tests/viewer.subtitle.test.swg) | timed searchable transcript with validated cue/time jumps | current-cue timeline, waveform/media check, source/styled modes; [app.scope.text.md](app.scope.text.md) |
| Table | [tests](../bin/apps/modules/swagscope/src/tests/viewer.table.test.swg) | parsed CSV/TSV grid and cell search | dialect control, typed columns, sort/filter, fixed-width input, bounded rows; [app.scope.text.md](app.scope.text.md) |
| Text | [tests](../bin/apps/modules/swagscope/src/tests/viewer.text.test.swg) | bounded decoded stream, encoding override, wrap, zoom, statistics and search | address/gutter, result panes, bookmarks, Unicode and pathological lines; [app.scope.text.md](app.scope.text.md) |
| Video | [tests](../bin/apps/modules/swagscope/src/tests/viewer.video.test.swg) | progressive A/V playback, seek, tracks and subtitles | chapters, bookmarks, direct frame/time addressing, inspection; [app.scope.video.md](app.scope.video.md) |

## Entries

### app.scope.viewers.003 — Viewer state is forgotten when a file or application closes

- Recorded: 2026-08-29 08:36
- Updated: 2026-09-10 19:06 — Distinguish existing reload restoration from persistent per-file state
- Evidence: Markdown theme and reading width and Video subtitle presentation already persist as
  global preferences in `ViewerWindow.serialize`. `ViewerReadingState` also restores supported
  settings during an in-place reload. Per-file zoom, fit mode, wrapping, encoding,
  selected track, playback position/volume, page and scroll position have no identity-keyed restore
  contract and are reconstructed on reopening.
- Next: define versioned global defaults plus per-file state keyed by stable file identity, with an
  explicit list of safe fields each viewer may persist.
- Complete when: every registered viewer restores its useful reading state, stale identity never
  applies state to a replacement file, and one command resets either the current viewer or all
  viewer preferences.

### app.scope.viewers.005 — Automatic reload does not classify changes or offer a snapshot policy

- Recorded: 2026-08-29 08:36
- Updated: 2026-09-10 19:06 — Narrow to event classification and snapshot policy after automatic reload shipped
- Evidence: `ViewerFileWatch` already polls size, creation time and last-write time off-thread,
  waits for two stable observations, and asks the host to reload. `ViewerReadingState` restores
  supported reading settings and scroll positions, and old searches are retired. Reload tests
  cover edits, truncation, atomic replacement, temporary deletion and PDF/Markdown state. The
  watcher still collapses successful changes to one Boolean and suppresses metadata errors; it
  exposes neither stable file identity, append/replace/delete/permission-loss classification, nor
  a user choice to retain a labelled snapshot.
- Next: extend the existing watcher with typed change observations and stable identity, then
  let viewers declare reload, append-following, or labelled-snapshot behavior.
- Complete when: atomic replacement, append, truncation, deletion, and permission loss are
  distinguished; stale search results are retired; reload can preserve a valid logical position;
  and each viewer states whether live following is supported.
- Related: app.scope.hexa.008, app.scope.text.023

### app.scope.viewers.009 — The viewer family has no release-quality compatibility matrix

- Recorded: 2026-08-29 08:36
- Updated: 2026-09-07 13:22 — Replace stale copied test counts with links to the owning suites
- Evidence: all seventeen viewers now have focused tests and a viewer-specific golden, but fixture
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

### app.scope.viewers.006 — File facts have no common host-wide inspection contract

- Recorded: 2026-08-29 08:36
- Updated: 2026-09-06 07:51 — git: prompt 6
- Evidence: Image and Video already publish grouped metadata through the shared `MediaInfoPanel`,
  with translated property labels, row selection and a copy command. The host also shows size and
  a viewer-supplied summary. Canonical path, timestamps, file identity, hashes, detection evidence
  and warnings still lack one contract available across all seventeen viewers.
- Next: extend the existing information surface with host-owned file facts and optional viewer
  properties and warnings, including cancellable hashing and links back to the described content.
- Complete when: facts are selectable and copyable, byte sizes and dates have exact forms, format
  detection explains its evidence, hashes are cancellable for large files, and viewers can link a
  property to the content it describes.
- Related: app.scope.hexa.017, app.scope.image.011

### app.scope.viewers.011 — Attacker-controlled decoders share the application process

- Recorded: 2026-09-01 21:04
- Updated: 2026-09-06 07:51 — git: prompt 6
- Evidence: every registered viewer is a direct function callback compiled into `swagscope.exe`.
  A malformed image, font, document, archive, or media stream therefore reaches its decoder in the
  process that owns the window, history, clipboard access, and ordinary user token. Read-only and
  offline prevent intentional document actions, but they do not contain a parser defect.
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

- Recorded: 2026-09-01 21:04
- Updated: 2026-09-06 07:51 — git: prompt 6
- Evidence: `Viewer.Plugin` already carries an API version, stable key, selectors, icon, localized
  name, smoke fixture, and creation callback, but `createViewerPluginRegistry` names every plugin in
  source and the README explicitly records no runtime index, dynamic library, exported entry point,
  or ABI adapter. Adding separately distributed formats first needs the isolation boundary in
  app.scope.viewers.011 and a versioned contract.
- Next: define a local manifest and capability-negotiated wire contract on top of
  app.scope.viewers.011, including publisher identity, package provenance, selector precedence,
  compatibility ranges, resource limits, translations, icons, and an explicit install/update policy.
- Complete when: a separately packaged viewer can be installed, disabled, updated, and removed
  without rebuilding Swag Scope; incompatible, crashing, and duplicate-key packages are quarantined
  with an exact reason; built-ins retain deterministic precedence; and no external viewer executes
  in the application or shell-host process.
- Related: app.scope.viewers.011, platform.portability.072, platform.portability.073

### app.scope.viewers.013 — Five decoder families cannot claim files independently of their extension

- Recorded: 2026-09-05 06:02
- Updated: 2026-09-06 07:51 — git: prompt 6
- Evidence: `choices` reads the head of a file once and lets a descriptor claim it from its own
  bytes, and `html`, `code`, `pdf`, `font`, `midi`, `archive`, and `text` do. `image`, `video`,
  `sound`, `opendocument`, and `indesign` cannot: `Pixel.Image.decode`, `Video.Reader.open`, and
  `Audio.SoundFile.load` select a codec from the filename extension alone, and the two office
  viewers read `.fodt` against `.odt` and `.indd` against `.idml` to decide how to open the file.
  A JPEG named `.dat` is therefore still offered as bytes only, and a viewer that claimed it from
  its signature would then fail to open it.
- Next: give the three decoder registries a content-based lookup, as a signature predicate declared
  beside the extension list each codec already publishes plus one `decoderFor(bytes)` entry point
  per module, then add the missing probes and let the two office viewers decide their container
  from the head instead of the name.
- Complete when: a raster image, a video container, a sound file, an OpenDocument package, and an
  InDesign document are each offered their own viewer through a copy renamed to an extension
  nothing claims, and every viewer a probe offers can open the file it claimed.
- Related: app.scope.image.001, app.scope.viewers.012

### app.scope.viewers.002 — A document cannot be printed

- Recorded: 2026-08-17 11:01
- Updated: 2026-09-05 16:27 — git: Add unit tests for TaskProvider in providers.test.js
- Intent: a viewer that renders a document should be able to put it on paper through the same
  pagination contract as the rest of the GUI rather than through application-local paths.
- Next: define the application adapter once the GUI pagination and preview contract is ready.
- Complete when: text, code, Markdown, HTML, image, and hexadecimal dump views print through that
  contract, with actual-size or fit-to-page choices where they have meaning.
- Related: std.gui.030, platform.portability.086, std.gui.034

### app.scope.viewers.004 — Long viewer operations have no common progress and cancellation contract

- Recorded: 2026-08-29 08:36
- Updated: 2026-09-05 16:27 — git: Add unit tests for TaskProvider in providers.test.js
- Evidence: viewers independently use workers and the host loading overlay, but parsing, indexing,
  waveform building, rendering, and search cannot consistently report units completed, yield a
  partial result, or distinguish cancellation from failure.
- Next: extend `Viewer.LifecycleApi` with cancellable phases, determinate or indeterminate progress,
  partial-publication rules, and a shared terminal status.
- Complete when: opening and analysis operations remain interruptible, replacement files retire old
  work promptly, the overlay names the current phase, and cancellation never becomes an error.
- Related: app.scope.hexa.006, std.gui.pdf.029

### app.scope.viewers.001 — Select-all in a streamed document silently means the resident window

- Recorded: 2026-08-17 11:01
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Evidence: the basic text and `Code` viewers use `RichEditCtrl`; Ctrl+A selects only their
  resident 256 KiB window. The Markdown viewer likewise selects only materialized blocks. The
  `Hexadecimal` viewer is the positive example because its bounded copy command names its 1 MiB
  limit before copying.
- Next: define one shared streamed-selection contract and apply it to basic text, Code, and
  Markdown without making a multi-gigabyte copy resident.
- Complete when: select-all reaches the whole file or the copy command says exactly which bounded
  part will leave, before the user pastes it.

### app.scope.viewers.007 — Custom-painted viewers cannot expose a professional accessibility model

- Recorded: 2026-08-29 08:36
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
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

- Recorded: 2026-08-29 08:36
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Evidence: viewer commands now occupy one centered lower band, while dynamic zoom/page/range
  values use consistent clickable controls in the information band. Some operations remain split
  between compact menus, context menus, and hard-coded key handlers; there is no command palette,
  shortcut reference, conflict check, or consistent disabled-state explanation.
- Next: register viewer actions as named commands with default gestures, applicability, and a
  discoverable description before adding a palette and shortcut sheet.
- Complete when: every non-pointer-only action can be found and invoked by name, shortcuts can be
  inspected and remapped, conflicts are reported, and toolbar/menu/key execution share one state.
- Related: app.scope.hexa.016, std.gui.010

---

## Format coverage

`Today` uses **full** for a dedicated renderer, **structure** for a decoded `Binary` tree,
**signature** for identification and entropy only, **text** or **code** for those fallbacks, and
**none** for no format-specific interpretation beyond generic byte inspection. The owning backlog is linked from each unfinished row.

#### Text and documents

| Family | Extensions | Today | Missing | Entry |
| --- | --- | --- | --- | --- |
| Plain text | `.txt` | full, streamed | addresses, gutter, non-resident ranges | [app.scope.text.002](app.scope.text.md) |
| Key/value configuration | `.ini` `.cfg` `.conf` `.properties` `.env` | code and raw text | sections, keys, dialect diagnostics | [app.scope.text.040](app.scope.text.md) |
| Other encodings | UTF-16/32, Windows-1252 | full, detected and overridable | legacy encodings and diagnostics | [app.scope.text.004](app.scope.text.md) |
| Source code | registered extensions, common build/config names, and shebang scripts | full, lexer coloring | outline, folding, overview | [app.scope.text.006](app.scope.text.md) |
| Markdown | `.md` `.markdown` | rendered and raw text | outline, synchronized source, resource diagnostics | [app.scope.document.001](app.scope.document.md) |
| HTML | `.html` `.htm` `.xhtml` | rendered, code, and raw text | DOM/source/resource inspection; advanced engine layout | [app.scope.document.006](app.scope.document.md), [HTML roadmap](std.gui.html.md) |
| JSON and JSON Lines | `.json` `.jsonl` | code and raw text | semantic tree, paths, schema facts | [app.scope.text.024](app.scope.text.md) |
| XML | `.xml` `.xsd` `.xsl` `.xslt` | code and raw text | namespace-aware tree and paths | [app.scope.text.038](app.scope.text.md) |
| YAML and TOML | `.yaml` `.yml` `.toml` | code and raw text | typed tree and paths | [app.scope.text.039](app.scope.text.md) |
| Diff and patch | `.diff` `.patch` | text | parsed files/hunks, intraline and side-by-side views | [app.scope.text.022](app.scope.text.md) |
| Log | `.log` | text | entries, start-at-tail/follow, queries, structured fields, timelines | [app.scope.text.023](app.scope.text.md), [app.scope.text.034](app.scope.text.md) |
| Subtitles | `.srt` `.vtt` `.ass` `.ssa` | timed transcript with cue/time jump | previous/next/current cue, timeline, source/styled modes, media check | [app.scope.text.011](app.scope.text.md) |
| Tabular text | `.csv` `.tsv` `.tab` | table up to 32 MiB, and raw text | bounded streaming, dialect, sort/filter, types | [app.scope.text.015](app.scope.text.md), [app.scope.text.016](app.scope.text.md) |
| PDF | `.pdf` | page rendering, single-page and continuous layouts | partial pages, thumbnails, outline, facing pages | [app.scope.document.011](app.scope.document.md), [app.scope.document.012](app.scope.document.md), [app.scope.document.014](app.scope.document.md), [std.gui.pdf.md](std.gui.pdf.md) |
| Office OOXML | `.docx` `.xlsx` `.pptx` | structure | readable text and sheets | [app.scope.document.020](app.scope.document.md) |
| OpenDocument | `.odt` `.ott` `.fodt` `.ods` `.ots` `.fods` `.odp` `.otp` `.fodp` `.odg` `.otg` `.fodg` | readable text, sheets, slides, and drawing pages | layout, semantics, inspection, and fidelity | [OpenDocument roadmap](app.scope.opendocument.md) |
| Legacy Office | `.doc` `.xls` `.ppt` | signature | out of scope | — |
| EPUB | `.epub` | structure | spine read through `HtmlView` | [app.scope.document.021](app.scope.document.md) |
| RTF | `.rtf` | raw text, recognized from its content | a safe document renderer | — |
| Mail | `.eml` `.msg` | printable mail as text; CFB signature for binary MSG | — | — |
| Notebook | `.ipynb` | raw text, recognized from its content | safe rendered cells and stored outputs | [app.scope.document.022](app.scope.document.md) |
| reStructuredText, AsciiDoc | `.rst` `.adoc` | text | — | — |

#### Images

| Family | Extensions | Today | Missing | Entry |
| --- | --- | --- | --- | --- |
| Raster | `.bmp` `.gif` `.ico` `.jpg` `.png` `.qoi` `.tga` `.tiff` `.webp` | full | pixel, histogram, comparison, progressive huge-image tools | [app.scope.image.001](app.scope.image.md) |
| Vector | `.svg` | full | masks, radial focal points | std.pixel.image.010, std.pixel.image.008 |
| Metadata | EXIF, ICC, XMP | PNG text and interpreted EXIF panel; opaque profile records | applied orientation, ICC identity, XMP properties, color management | [app.scope.image.011](app.scope.image.md) |
| Simple raster | `.pnm` `.ppm` | none | Pixel codecs | — |
| Modern codecs | `.avif` `.heic` `.jxl` | none | Pixel codecs | std.pixel.image.026, std.pixel.image.027 |
| High dynamic range | `.exr` `.hdr` | EXR images and indexed parts | Radiance HDR codec | — |
| Layered | `.psd` `.xcf` | PSD composite and indexed layers; XCF signature | descriptive layer navigation | [app.scope.image.008](app.scope.image.md) |
| GPU textures | `.dds` `.ktx2` | indexed levels, layers, faces, and slices, including BC1–BC5 decode | subresource labels and compressed upload | [app.scope.image.008](app.scope.image.md), std.pixel.image.041, std.pixel.image.042 |
| Camera RAW | `.cr2` `.nef` `.arw` `.dng` | signature | embedded preview extraction | [app.scope.image.012](app.scope.image.md) |

#### Audio and video

| Family | Extensions | Today | Missing | Entry |
| --- | --- | --- | --- | --- |
| WAV PCM and float | `.wav` | full, streamed | professional transport/analysis | [app.scope.audio.001](app.scope.audio.md) |
| Raw YUV4MPEG2 video | `.y4m` | full, silent, streamed by frame | the format carries no sound | — |
| Motion JPEG video | `.avi` `.mp4` `.m4v` `.mov` | full with supported container audio and generic chroma sampling | professional transport/inspection | [app.scope.video.001](app.scope.video.md) |
| Compressed audio | `.mp3` `.flac` `.aac` `.ac3` `.eac3` | full, streamed | professional transport/analysis | [app.scope.audio.001](app.scope.audio.md) |
| Video containers | `.mp4` `.mkv` `.webm` `.mov` `.avi` | AVI structure; others identified | ISO-BMFF and EBML trees | [app.scope.binary.011](app.scope.binary.md) |
| Video playback | `.avi` `.mp4` `.m4v` `.mov` `.mkv` | Motion JPEG, uncompressed AVI, H.264, H.265, MPEG-4 Part 2 | professional transport/inspection; VP9 and AV1 | [app.scope.video.001](app.scope.video.md), [std.video.010](std.video.md), [std.video.011](std.video.md) |
| MIDI | `.mid` `.midi` | piano roll and structure | playback, event lanes, scalable timeline | [app.scope.midi.001](app.scope.midi.md) |

#### Binaries, containers, and developer artifacts

| Family | Extensions | Today | Missing | Entry |
| --- | --- | --- | --- | --- |
| Windows images | `.exe` `.dll` `.sys` | structure | — | — |
| COFF and archives | `.obj` `.lib` `.a` | structure | — | — |
| ELF and Mach-O | `.so` `.elf` `.dylib` | structure | — | — |
| WebAssembly | `.wasm` | structure | — | — |
| RIFF | `.wav` `.avi` | structure | — | — |
| Swag chunk container | `.scc` | structure through `Core.Scc` | — | — |
| ZIP family | `.zip` `.jar` `.apk` `.vsix` | full tree and stored/Deflate entry preview | nested archive provenance, encryption, more methods | [app.scope.binary.008](app.scope.binary.md), [app.scope.binary.010](app.scope.binary.md) |
| Other archives | `.7z` `.rar` `.tar` `.gz` `.xz` `.zst` `.cab` `.msi` | signature | listing, `tar`/`gzip` first | [app.scope.binary.010](app.scope.binary.md) |
| TrueType fonts | `.ttf` `.ttc` | specimen and first-face character map | face selector, glyph/metric/coverage inspection | [app.scope.font.001](app.scope.font.md) |
| CFF and web fonts | `.otf` `.woff` `.woff2` | CFF OpenType structure; WOFF/WOFF2 signatures | CFF specimen registration; WOFF containers | [app.scope.font.013](app.scope.font.md), std.truetype.001, std.truetype.002 |
| Program databases | `.pdb` | signature | MSF streams and CodeView match | [app.scope.binary.014](app.scope.binary.md) |
| Databases | `.sqlite` `.db` | signature | schema and bounded table browse | [app.scope.binary.012](app.scope.binary.md) |
| Certificates and keys | `.pem` `.der` `.crt` `.p12` | printable PEM as text; binary inspection otherwise | ASN.1 and X.509 decode | [app.scope.binary.013](app.scope.binary.md) |
| Managed code | `.class` `.dex` | signature | — | — |
| Crash dumps | `.dmp` | none | — | — |
| Disk images | `.iso` `.vhd` | none | — | — |
| Unknown | any | size and entropy; signature only when recognized | — | — |

---

## Out of scope

**Editing anything.** Read-only is the product guarantee. Byte replacement, insertion, deletion,
undo, save, raw-disk writing, and process-memory writing belong to a different application and risk
model.

**General format conversion and batch processing.** These remain outside the reading workflow.
Proposed explicit exports of a selected frame or reading result create a separate artifact and
must preserve the source file.

**Legacy binary Office rendering.** `.doc`, `.xls`, and `.ppt` do not justify a fidelity claim; the
CFB signature is what the `Binary` viewer currently identifies.

**Packer and protector identification.** A signature database maintained against active evasion is
not a durable repository capability. Entropy and an honest signature line are.

**Hosted and cloud formats.** Remote accounts and network-backed documents are outside the offline product boundary.

**3D model preview.** Pixel is a 2D renderer, and an untrusted wireframe is not worth the subsystem.
