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

1. Deepen the shipped document readers, especially DOCX layout and styles, XLSX grid and cell
   formatting, PPTX slide geometry, EPUB navigation, and CBZ page handling. Keep the true reading
   surface ahead of each package's raw archive view. See [app.scope.document.md](app.scope.document.md).
2. Make the shipped readers dependable across representative real files: partial PDF pages,
   cancellation, navigation, search, first-content latency, memory bounds, and explicit failures.
   See [std.gui.pdf.md](std.gui.pdf.md) and the fixture matrix. Verify Encre and Papier across
   sibling scenarios, including previews and keyboard use.
3. Reassess new format selectors only after their existing neighbors meet this reading contract.
   Recorded candidates include Jupyter notebooks, OpenDocument (`.odt`, `.ods`, `.odp`), AVIF,
   HEIC, JPEG XL, embedded RAW previews, VP9, AV1, DjVu, XPS, CBR, other archives and legacy
   Office files. Keep those leads in their owning backlogs; do not schedule them ahead of fixes to
   current readers. See [app.scope.image.md](app.scope.image.md) and [std.video.md](std.video.md).

## Entries

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

- Evidence: the twenty-one registered viewers have focused tests and viewer-specific goldens. The
  fixture matrix now names all 118 canonical and variant files, checks
  each one's first viewer, and decodes the listed image inputs. EPUB, CBZ, DOCX, RTF, XLSX and PPTX have
  content and damaged-package cases. Five complete, openly licensed published documents add
  content checks for EPUB, Office and PDF, with source URLs and SHA-256 hashes. Text covers queued encoding changes, cancellation and CRLF
  search offsets; shared document outlines have
  their own [integration suite](../bin/apps/modules/swagscope/src/tests/cases/functional/viewer.outline.swg).
  These tests still do not declare a complete matrix for real-world variants,
  malformed input, large files, cancellation, keyboard-only use, themes, DPI, memory ceilings, or
  selection-to-first-content latency under rapid adjacent-file browsing.
- Next: publish one matrix per registered viewer with representative public fixtures, required
  malformed cases, bounded-resource assertions, interaction checks, visual states, and time-to-first-
  content budgets for cold open, warm open, and replacement before the previous viewer settles;
  measure peak resident memory, bytes read before first content, and adjacent-file navigation.
  Benchmark the same real corpus on the same machine against the category reference and record
  absolute thresholds before enforcing regressions.
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
  twenty-one registered viewers offline, including after a clean reboot; a release gate checks its
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
- Related: app.scope.hexa.008, app.scope.text.023

### app.scope.viewers.006 — File facts have no common host-wide inspection contract

- Evidence: Image and Video already publish grouped metadata through the shared `MediaInfoPanel`,
  with translated property labels, row selection and a copy command. The host also shows size and
  a viewer-supplied summary. Canonical path, timestamps, file identity, hashes, detection evidence
  and warnings still lack one contract available across all twenty-one viewers.
- Next: extend the existing information surface with host-owned file facts and optional viewer
  properties and warnings, including cancellable hashing and links back to the described content.
- Done when: facts are selectable and copyable, byte sizes and dates have exact forms, format
  detection explains its evidence, hashes are cancellable for large files, and viewers can link a
  property to the content it describes.
- Related: app.scope.hexa.017, app.scope.image.011

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
- Next: define the application adapter once the GUI pagination and preview contract is ready.
- Done when: text, code, Markdown, HTML, image, and hexadecimal dump views print through that
  contract, with actual-size or fit-to-page choices where they have meaning.
- Related: std.gui.030, platform.portability.086, std.gui.034

### app.scope.viewers.004 — Long viewer operations have no common progress and cancellation contract

- Evidence: viewers independently use workers and the host loading overlay, but parsing, indexing,
  waveform building, rendering, and search cannot consistently report units completed, yield a
  partial result, or distinguish cancellation from failure.
- Next: extend `Viewer.LifecycleApi` with cancellable phases, determinate or indeterminate progress,
  partial-publication rules, and a shared terminal status.
- Done when: opening and analysis operations remain interruptible, replacement files retire old
  work promptly, the overlay names the current phase, and cancellation never becomes an error.
- Related: app.scope.hexa.006, std.gui.pdf.029

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

### app.scope.viewers.008 — Viewer commands lack complete discovery and shortcut management

- Evidence: the lens now exposes common and viewer actions, but some operations remain split
  between compact menus, context menus, and hard-coded key handlers. Scope still has no shortcut
  reference, conflict check, remapping, or consistent disabled-state explanation.
- Next: register every viewer action with a default gesture and applicability, then add shortcut
  reference, conflict handling, remapping, and shared state across lens, menu, and key execution.
- Done when: every non-pointer-only action can be found and invoked by name, shortcuts can be
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
| Markdown | `.md` `.markdown` | rendered and raw text with heading outline | outline filtering/current-section tracking, synchronized source, resource diagnostics | [app.scope.document.001](app.scope.document.md) |
| HTML | `.html` `.htm` `.xhtml` | rendered, code, and raw text | DOM/source/resource inspection; advanced engine layout | [app.scope.document.006](app.scope.document.md), [HTML roadmap](std.gui.html.md) |
| JSON and JSON Lines | `.json` `.jsonl` | code and raw text | semantic tree, paths, schema facts | [app.scope.text.024](app.scope.text.md) |
| XML | `.xml` `.xsd` `.xsl` `.xslt` | code and raw text | namespace-aware tree and paths | [app.scope.text.038](app.scope.text.md) |
| YAML and TOML | `.yaml` `.yml` `.toml` | code and raw text | typed tree and paths | [app.scope.text.039](app.scope.text.md) |
| Diff and patch | `.diff` `.patch` | text | parsed files/hunks, intraline and side-by-side views | [app.scope.text.022](app.scope.text.md) |
| Log | `.log` | text | entries, start-at-tail/follow, queries, structured fields, timelines | [app.scope.text.023](app.scope.text.md), [app.scope.text.034](app.scope.text.md) |
| Subtitles | `.srt` `.vtt` `.ass` `.ssa` | timed transcript with cue/time jump | previous/next/current cue, timeline, source/styled modes, media check | [app.scope.text.011](app.scope.text.md) |
| Tabular text | `.csv` `.tsv` `.tab` | table up to 32 MiB, and raw text | bounded streaming, dialect, sort/filter, types | [app.scope.text.015](app.scope.text.md), [app.scope.text.016](app.scope.text.md) |
| PDF | `.pdf` | page rendering, bookmarks, single-page and continuous layouts | partial pages, thumbnails, facing pages | [app.scope.document.011](app.scope.document.md), [app.scope.document.012](app.scope.document.md), [std.gui.pdf.038](std.gui.pdf.md), [std.gui.pdf.md](std.gui.pdf.md) |
| DOCX | `.docx` | paragraphs, simple tables and images in reading order | page geometry, styles, notes and fidelity | [app.scope.document.020](app.scope.document.md) |
| XLSX | `.xlsx` | ordered sheets and values in a bounded grid | formatted cells, authored layout and navigation | [app.scope.document.025](app.scope.document.md) |
| PPTX | `.pptx` | ordered slide text and pictures | slide geometry, masters, notes and presentation | [app.scope.document.026](app.scope.document.md) |
| OpenDocument | `.odt` `.ods` `.odp` | archive and binary structure | — | — |
| Legacy Office | `.doc` `.xls` `.ppt` | signature | out of scope | — |
| EPUB | `.epub` | spine chapters through `HtmlView` | TOC, book search, saved position, paged/flow reading | [app.scope.document.021](app.scope.document.md), [app.scope.document.028](app.scope.document.md) |
| Comic book | `.cbz` | natural-order single image pages | spreads, manga, continuous scroll and saved position | [app.scope.document.027](app.scope.document.md) |
| RTF | `.rtf` | bounded formatted reading with text, styles, simple tables and named omissions | richer fidelity and encoding coverage | [app.scope.document.024](app.scope.document.md) |
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
| Compressed audio | `.mp3` `.flac` `.aac` `.ac3` `.eac3` `.ec3` `.dts` `.ogg` `.oga` `.opus` | full, streamed | professional transport/analysis | [app.scope.audio.001](app.scope.audio.md) |
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
| ZIP family | `.zip` `.jar` `.apk` `.vsix` | full tree and stored/Deflate entry preview | nested provenance, archive-wide integrity, encrypted/variant policy | [app.scope.binary.008](app.scope.binary.md), [app.scope.binary.015](app.scope.binary.md) |
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
