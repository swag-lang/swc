# sFileScope Shared Viewer Backlog

This backlog covers contracts, behavior, coverage, and product boundaries shared by several
sFileScope viewers. A capability owned by one viewer lives in its `filescope.<viewer>.md` file;
window lifecycle, document management, and operating-system integration live in
[filescope.md](filescope.md). Reusable engine work remains in the owning standard-module backlog.

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
and interchange expectations, then keeps only outcomes compatible with sFileScope's offline,
bounded, non-modifying role:

- [Visual Studio Code basic editing](https://code.visualstudio.com/docs/editing/codebasics) and
  [code navigation](https://code.visualstudio.com/docs/editing/editingevolved) for line/symbol
  navigation, folding, overview, history, and discoverable commands.
- [Visual Studio Code Markdown](https://code.visualstudio.com/docs/languages/markdown) for outline,
  source/preview synchronization, link validation, and explicit preview security.
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

## Registered viewer audit map

`viewerindex.swg` registers thirteen dedicated viewers; the host adds Basic text. Every existing
viewer now has one owning professional backlog, while Hexadecimal retains its earlier focused audit:

| Existing viewer | Current core | Professional backlog |
| --- | --- | --- |
| Basic text | bounded decoded text window | [filescope.text.md](filescope.text.md#shared-text-reading) |
| Code | bounded text plus lexical coloring | [filescope.text.md](filescope.text.md#source-code) |
| Markdown | rendered document, themes, reading widths | [filescope.document.md](filescope.document.md#markdown-reading) |
| HTML | offline rendered document | [filescope.document.md](filescope.document.md#html-reading) |
| Subtitles | parsed timed transcript | [filescope.text.md](filescope.text.md#timed-text) |
| Table | virtual parsed CSV/TSV rows | [filescope.text.md](filescope.text.md#tabular-text) |
| Image | pan/zoom/fit/rotate and animated frames | [filescope.image.md](filescope.image.md) |
| Video | progressive A/V playback and subtitles | [filescope.video.md](filescope.video.md) |
| PDF | rendered page, zoom, navigation, search | [filescope.document.md](filescope.document.md#pdf-presentation) |
| Sound | streamed playback and bounded waveform | [filescope.audio.md](filescope.audio.md) |
| Font | specimen and paged character map | [filescope.font.md](filescope.font.md) |
| MIDI | parsed tracks and piano roll | [filescope.midi.md](filescope.midi.md) |
| Binary | hierarchical structured report and previews | [filescope.binary.md](filescope.binary.md) |
| Hexadecimal | bounded typed byte grid | [filescope.hexa.md](filescope.hexa.md) |

## Shared reading behavior

### T-388 — Select-all in a streamed document silently means the resident window

- Evidence: the basic text and `Code` viewers use `RichEditCtrl`; Ctrl+A selects only their
  resident 256 KiB window. The Markdown viewer likewise selects only materialized blocks. The
  `Hexadecimal` viewer is the positive example because its bounded copy command names its 1 MiB
  limit before copying.
- Next: define one shared streamed-selection contract and apply it to basic text, Code, and
  Markdown without making a multi-gigabyte copy resident.
- Complete when: select-all reaches the whole file or the copy command says exactly which bounded
  part will leave, before the user pastes it.

### T-398 — A document cannot be printed

- Intent: a viewer that renders a document should be able to put it on paper through the same
  pagination contract as the rest of the GUI rather than through application-local paths.
- Next: define the application adapter once the GUI pagination and preview contract is ready.
- Complete when: text, code, Markdown, HTML, image, and hexadecimal dump views print through that
  contract, with actual-size or fit-to-page choices where they have meaning.
- Related: T-047, T-234, T-236

### B-043 — Viewer state is forgotten when a file or application closes

- Evidence: viewer-local choices such as zoom, fit mode, wrapping, encoding, selected track,
  playback volume, page, and scroll position live only in the current widget instance. Reopening a
  file always reconstructs a default view.
- Next: define versioned global defaults plus per-file state keyed by stable file identity, with an
  explicit list of safe fields each viewer may persist.
- Complete when: every registered viewer restores its useful reading state, stale identity never
  applies state to a replacement file, and one command resets either the current viewer or all
  viewer preferences.

### B-044 — Long viewer operations have no common progress and cancellation contract

- Evidence: viewers independently use workers and the host loading overlay, but parsing, indexing,
  waveform building, rendering, and search cannot consistently report units completed, yield a
  partial result, or distinguish cancellation from failure.
- Next: extend `ViewerCreateResult` with cancellable phases, determinate or indeterminate progress,
  partial-publication rules, and a shared terminal status.
- Complete when: opening and analysis operations remain interruptible, replacement files retire old
  work promptly, the overlay names the current phase, and cancellation never becomes an error.
- Related: B-025, T-459

### B-045 — External file replacement and growth have no viewer-wide reload policy

- Evidence: each viewer snapshots different combinations of path, size, decoded content, and open
  streams. A file changed by a build, download, logger, or editor can leave rendered content,
  offsets, matches, and metadata disagreeing without a shared notification.
- Next: add a host-owned file identity/version watcher and a viewer callback that can reload,
  follow append-only growth, or keep a labelled snapshot.
- Complete when: atomic replacement, append, truncation, deletion, and permission loss are
  distinguished; stale search results are retired; reload can preserve a valid logical position;
  and each viewer states whether live following is supported.
- Related: B-027, T-409

### B-046 — File facts are scattered across terse summaries instead of one inspectable panel

- Evidence: the host shows size and one viewer-supplied details string, while timestamps, canonical
  path, detected format, MIME claim, file identity, hashes, decoder choice, warnings, and
  format-specific metadata are either absent or hidden inside a viewer.
- Next: define a read-only information panel with common sections and an extension point for
  viewer-owned properties and warnings.
- Complete when: facts are selectable and copyable, byte sizes and dates have exact forms, format
  detection explains its evidence, hashes are cancellable for large files, and viewers can link a
  property to the content it describes.
- Related: B-031, T-405

### B-047 — Custom-painted viewers cannot expose a professional accessibility model

- Evidence: image, waveform, piano-roll, font-map, video-overlay, and hexadecimal surfaces paint
  meaning without semantic children. The toolkit itself still has no accessibility bridge, so
  keyboard focus alone cannot describe values, ranges, selection, or playback state.
- Next: specify the semantic tree and keyboard contract for every custom viewer while T-037 builds
  the toolkit bridge, beginning with roles, names, values, bounds, and change notifications.
- Complete when: each viewer has an accessibility fixture, all actions are keyboard reachable,
  focus order is stable, animation and playback state are announced without flooding, and the
  shipped platform bridge exposes the same model.
- Related: T-037, B-035

### B-048 — Viewer commands have no common discoverability or remapping surface

- Evidence: commands are split between icon-only bars, context menus, implicit mouse gestures, and
  hard-coded key handlers. There is no command palette, shortcut reference, conflict check, or
  consistent disabled-state explanation.
- Next: register viewer actions as named commands with default gestures, applicability, and a
  discoverable description before adding a palette and shortcut sheet.
- Complete when: every non-pointer-only action can be found and invoked by name, shortcuts can be
  inspected and remapped, conflicts are reported, and toolbar/menu/key execution share one state.
- Related: B-042, T-222

### B-049 — The viewer family has no release-quality compatibility matrix

- Evidence: every dedicated viewer has focused tests, but fixture depth varies from one golden to
  large synthesized parser suites. There is no declared matrix for real-world variants, malformed
  input, large files, cancellation, keyboard-only use, themes, DPI, or memory ceilings.
- Next: publish one matrix per registered viewer with representative public fixtures, required
  malformed cases, bounded-resource assertions, interaction checks, and visual states.
- Complete when: the application smoke validates every registered viewer in light and dark themes,
  the matrix names unsupported variants honestly, corpus licences are recorded, and regressions in
  format choice, cancellation, accessibility, or resource bounds fail a focused suite.
- Related: F-156

## Format coverage

`Today` uses **full** for a dedicated renderer, **structure** for a decoded `Binary` tree,
**signature** for identification and entropy only, **text** or **code** for those fallbacks, and
**none** for the hexadecimal fallback alone. The owning backlog is linked from each unfinished row.

#### Text and documents

| Family | Extensions | Today | Missing | Entry |
| --- | --- | --- | --- | --- |
| Plain text | `.txt` `.ini` `.cfg` | full, streamed | addresses, gutter, non-resident ranges | [B-050](filescope.text.md) |
| Other encodings | UTF-16/32, Windows-1252 | full, detected and overridable | legacy encodings and diagnostics | [B-052](filescope.text.md) |
| Source code | registered extensions, common build/config names, and shebang scripts | full, lexer coloring | outline, folding, overview | [B-054](filescope.text.md) |
| Markdown | `.md` `.markdown` | full | outline, synchronized source, resource diagnostics | [B-069](filescope.document.md) |
| HTML | `.html` `.htm` `.xhtml` | full | DOM/source/resource inspection; advanced engine layout | [B-074](filescope.document.md), [HTML roadmap](html.md) |
| JSON, XML, YAML, TOML | `.json` `.xml` `.yaml` `.toml` | code | folding and value tree | — |
| Diff and patch | `.diff` `.patch` | text | hunk coloring and navigation | [T-408](filescope.text.md) |
| Log | `.log` | text | level coloring, timestamps, tail | [T-409](filescope.text.md) |
| Subtitles | `.srt` `.vtt` `.ass` `.ssa` | timed transcript | cue navigation, source/styled modes, media check | [B-059](filescope.text.md) |
| Tabular text | `.csv` `.tsv` `.tab` | full up to 32 MiB | bounded streaming, dialect, sort/filter, types | [T-402](filescope.text.md), [B-063](filescope.text.md) |
| PDF | `.pdf` | page rendering | partial pages, thumbnails, outline, layout modes | [T-401](filescope.document.md), [B-079](filescope.document.md), [pdf.md](pdf.md) |
| Office OOXML | `.docx` `.xlsx` `.pptx` | structure | readable text and sheets | [T-407](filescope.document.md) |
| OpenDocument | `.odt` `.ods` `.odp` | structure | readable text and sheets | [T-407](filescope.document.md) |
| Legacy Office | `.doc` `.xls` `.ppt` | signature | out of scope | — |
| EPUB | `.epub` | structure | spine read through `HtmlView` | [T-415](filescope.document.md) |
| RTF | `.rtf` | text | — | — |
| Mail | `.eml` `.msg` | none | — | — |
| Notebook | `.ipynb` | code | rendered cells | — |
| reStructuredText, AsciiDoc | `.rst` `.adoc` | text | — | — |

#### Images

| Family | Extensions | Today | Missing | Entry |
| --- | --- | --- | --- | --- |
| Raster | `.bmp` `.gif` `.ico` `.jpg` `.png` `.tga` `.tiff` `.webp` | full | pixel, histogram, comparison, progressive huge-image tools | [B-096](filescope.image.md) |
| Vector | `.svg` | full | clipping, masks, markers, symbols | T-189, T-191, T-192, T-326 |
| Metadata | EXIF, ICC, XMP | none | panel, orientation, color management | [T-405](filescope.image.md) |
| Simple raster | `.qoi` `.pnm` `.ppm` | none | Pixel codecs | T-055 |
| Modern codecs | `.avif` `.heic` `.jxl` | none | Pixel codecs | T-203, T-204 |
| High dynamic range | `.exr` `.hdr` | none | Pixel codecs | T-207 |
| Layered | `.psd` `.xcf` | signature | Pixel importer | T-208 |
| GPU textures | `.dds` `.ktx2` | none | Pixel containers | T-205, T-206 |
| Camera RAW | `.cr2` `.nef` `.arw` `.dng` | signature | embedded preview extraction | [T-414](filescope.image.md) |

#### Audio and video

| Family | Extensions | Today | Missing | Entry |
| --- | --- | --- | --- | --- |
| WAV PCM and float | `.wav` | full, streamed | professional transport/analysis; ADPCM | [B-106](filescope.audio.md), T-169 |
| Raw YUV4MPEG2 video | `.y4m` | full, silent, streamed by frame | the format carries no sound | — |
| Motion JPEG video | `.avi` `.mp4` `.m4v` `.mov` | full with supported container audio | uncommon chroma layouts | T-426 |
| Compressed audio | `.mp3` `.flac` `.aac` `.ac3` `.eac3` | full, streamed | professional transport/analysis; remaining module coverage | [B-106](filescope.audio.md), T-166, T-168 |
| Video containers | `.mp4` `.mkv` `.webm` `.mov` `.avi` | AVI structure; others identified | ISO-BMFF and EBML trees | [T-412](filescope.binary.md) |
| Video playback | `.avi` `.mp4` `.m4v` `.mov` `.mkv` | Motion JPEG, uncompressed AVI, H.264, H.265, MPEG-4 Part 2 | professional transport/inspection; VP9 and AV1 | [B-117](filescope.video.md), [T-420](filescope.video.md) |
| MIDI | `.mid` `.midi` | piano roll and structure | playback, event lanes, scalable timeline | [B-142](filescope.midi.md) |

#### Binaries, containers, and developer artifacts

| Family | Extensions | Today | Missing | Entry |
| --- | --- | --- | --- | --- |
| Windows images | `.exe` `.dll` `.sys` | structure, complete | — | — |
| COFF and archives | `.obj` `.lib` `.a` | structure | — | — |
| ELF and Mach-O | `.so` `.elf` `.dylib` | structure | — | — |
| WebAssembly | `.wasm` | structure | — | — |
| RIFF | `.wav` `.avi` | structure | — | — |
| Swag chunk container | `.scc` | structure through `Core.Scc` | — | — |
| ZIP family | `.zip` `.jar` `.apk` `.vsix` | central directory | open an entry | [T-403](filescope.binary.md) |
| Other archives | `.7z` `.rar` `.tar` `.gz` `.xz` `.zst` `.cab` `.msi` | signature | listing, `tar`/`gzip` first | [T-403](filescope.binary.md) |
| TrueType fonts | `.ttf` `.ttc` | specimen and first-face character map | face selector, glyph/metric/coverage inspection | [B-130](filescope.font.md) |
| CFF and web fonts | `.otf` `.woff` `.woff2` | OTF specimen; WOFF structure | professional inspection; WOFF containers | [B-130](filescope.font.md), T-177, T-178 |
| Program databases | `.pdb` | signature | MSF streams and CodeView match | [T-413](filescope.binary.md) |
| Databases | `.sqlite` `.db` | signature | schema and bounded table browse | [T-410](filescope.binary.md) |
| Certificates and keys | `.pem` `.der` `.crt` `.p12` | none | ASN.1 and X.509 decode | [T-411](filescope.binary.md) |
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
