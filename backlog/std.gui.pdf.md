# PDF Backlog

This backlog covers the PDF family inside `std/gui`: the `Pdf` engine namespace under
`gui/src/controls/pdf` and the `PdfView` widget beside it.

PDF-specific evidence, investigations, and intended outcomes stay together here. Compiler and
language work belongs in [compiler.core.md](compiler.core.md) and [language.design.md](language.design.md).
[README.md](README.md) has the whole layout.

Entries are ordered from the most recently updated down. An entry disappears when it
ships; history lives in git, not here.

## Where the module already stands

The engine covers the path a normal office or academic
document takes end to end: classic indirect objects, compressed object streams, page trees with
inherited attributes, page rotation, the Flate, LZW, ASCII hexadecimal, ASCII85 and run-length
filters with the TIFF and PNG predictors at every supported depth, the complete text state, the
vector path and stroke geometry, simple and composite fonts with `/Widths`, `/W`, `/Differences`
and `/ToUnicode`, embedded TrueType, OpenType, Type 1, and bare CFF programs addressed the way the
file keys them,
and every sample representation a raster can use from one to sixteen bits per component across
the device, calibrated, ICC-based, indexed, Lab, separation and DeviceN spaces, with decode
arrays, stencil masks, soft masks and color key masks. Group 3 and Group 4 facsimile images
decode here, and four-component photographs decode through `pixel`, so the two encodings a
scanned or print-ready office document hides behind both reach the page. Transparency arrives
with them: constant alpha, every blend mode the format defines, and the graphics-state soft mask
a transparency group carries, which is how a drop shadow, a vignette and a gradient fade are all
written.

The following capabilities are already implemented.

- **It writes as well as it reads.** A `Document` is editable, and the writer emits a
  deterministic file within the limitations recorded below. Decoding and encoding a document
  does not preserve every feature of the source.
- **The substitute font path preserves declared advances.** When a program cannot be drawn, the face is
  chosen from the descriptor's own traits and the run is then condensed to the advances the
  document declared, per character code.
- **The corpus is real.** 354 pages from eleven LLVM and Polly documents produced by several
  generations of writers, plus five PDFBox fixtures, all decoded lazily through `Pdf.Reader`.
- **The widget paints vectors, not rasters.** `PdfView` keeps its decoded pages and draws their
  items straight through the frame's painter — the application renderer — so a zoom or scroll
  step is a transform change: images upload once per page, typefaces resolve once per page, path
  tessellations cache inside the decoded page, and no offline rasterization, readback, or
  texture re-upload sits between the page and the screen.
- **The widget reads a document, not a page.** Page sizes come from the page tree, so the whole
  column is laid out and scrollable before anything is decoded; pages are decoded on a worker as
  the viewport reaches them, bounded by a page count and a memory budget, and a page that has not
  arrived shows as the paper it will be. Selection and search run across page boundaries, and
  Fit Page, Fit Width and one-page-at-a-time are the same document seen differently.
- **A document caches decoded resources.** Fonts are cached by object. Images are cached by
  object and resource dictionary within `ImageCacheBudget`; stencils depend on the current fill
  color and bypass that cache. Pages still own copies, as described in the cost entries below.
- **Opening costs the trailer chain, not the file.** `startxref` is followed through `/Prev`
  across classic tables and cross-reference streams, an object is parsed the first time
  something reaches it, and an incremental update resolves to the revision its trailer names.
  The recorded comparison in std.gui.pdf.025 measured 7.8 ms against MuPDF's 16 ms for sixteen
  files; those historical timings need a fresh run before describing the current checkout.

The gaps are of three kinds: documents that will not open at all, pages that open and then render
as something other than what they mean, and a writer that can only express what it can itself
draw.

## Where this family lives, and why

This engine began as the standalone `std/pdf` module, and the question of whether that separation
was justified was examined and then decided the other way: a document viewer's rendering is
host-driven — the zoom, the monitor scale, and the visible region all belong to the widget showing
the page — so the engine lives beside its widget, exactly as the HTML and Markdown engines live
beside `HtmlView` and `MarkdownView`. `PdfView` owns the decoded page and paints its items
directly through the frame being drawn, the way `HtmlView` paints its layout; a fixed
rasterization handed to a generic image widget was the wrong architecture, and was what made
zooming freeze. The offline rasterization (`Page.render` over a CPU renderer) remains as the
headless boundary: tests, thumbnails, and export.

One consequence is recorded rather than hidden: the writer (`Pdf.Document.encode`) now lives above
`pixel`, so [std.pixel.005](std.pixel.md#stdpixel005--no-painter-native-pdf-output) — PDF output from the painter — can no
longer be satisfied by calling into it from `pixel`. When that entry is taken up, either the
writer moves below both consumers or `pixel` grows its own, and that choice belongs to std.pixel.005.

## Entries

### std.gui.pdf.038 — PdfView has no facing-page layout

- Recorded: 2026-08-29 08:36
- Updated: 2026-09-12 06:10 — Move the remaining layout work from retired app.scope.document.014 to its shared widget owner.
- Evidence: `PdfPageLayout` exposes Single and Continuous. `PdfView` already shares navigation,
  search, selection, and bounded page residency between them; it cannot place two pages per row.
- Next: add Facing and Continuous Facing through the existing layout and visible-range machinery,
  with an explicit cover-page rule that does not infer reading intent from page dimensions alone.
- Complete when: both facing layouts preserve navigation, search, cross-page selection, and cache
  bounds; cover handling, unequal page sizes, gaps, and viewport resizing have regression coverage.
- Related: std.gui.pdf.039

### std.gui.pdf.039 — PdfView cannot fit a selected region to the viewport

- Recorded: 2026-09-12 06:10
- Evidence: split from retired app.scope.document.014. `PdfZoomMode` exposes FitPage, FitWidth,
  and Free; no operation derives zoom and scroll position from a selected page-space region.
- Next: define whether Fit Selection accepts text bounds, an explicit rectangle, or both, and
  implement it using the same page-to-viewport transforms as selection and search highlighting.
- Complete when: fitting a nonempty region keeps it visible with defined padding, empty selection
  has a defined result, and selection spanning pages works in every supported layout.
- Related: std.gui.pdf.038

### std.gui.pdf.040 — PdfView cannot move a text caret or extend selection from the keyboard

- Recorded: 2026-09-12 06:10
- Evidence: split from app.scope.document.016. The widget already supports pointer selection
  across pages, double-click word selection, Ctrl+A and Ctrl+C. Arrow keys scroll; they do not
  move a text caret or extend a selection. `pdfview.test.swg` protects cross-page pointer copy.
- Next: add keyboard movement and selection extension over the existing `PdfTextPosition` model,
  preserving pointer behavior and distinguishing text navigation from viewport scrolling.
- Complete when: keyboard selection crosses words, lines, and pages, respects modifiers, reveals
  its caret, and survives lazy page loading with tests at the widget boundary.
- Related: std.gui.pdf.041

### std.gui.pdf.041 — PDF copy has no choice between logical and visual text order

- Recorded: 2026-09-12 06:10
- Evidence: split from app.scope.document.016. `PdfView.selectedText` joins each selected page's
  indexed text with line feeds. There is one extraction order and no caller-selected copy mode.
- Next: define logical and visual copy orders against the retained glyph/source coordinates,
  including columns, bidirectional runs, and page boundaries, then expose the selected policy.
- Complete when: both forms preserve their documented order on independent text fixtures and
  copying a selection retains its exact range across pages.
- Related: std.gui.pdf.040, std.gui.pdf.042

### std.gui.pdf.042 — PdfView has no reflow reading mode

- Recorded: 2026-09-12 06:10
- Evidence: split from app.scope.document.016. `PdfView` paints positioned page items; zoom and
  page layout preserve the source geometry. Neither the widget nor its text index composes a
  reading surface whose lines wrap to the viewport width.
- Next: define a reading-order contract and the supported text subset before composing a reflow
  surface, retaining a route from reflowed text to its source page and selection coordinates.
- Complete when: supported text reflows on resize without losing search or selection, unsupported
  structures have an explicit fallback, and multi-column fixtures protect the chosen order.
- Related: std.gui.pdf.041

### std.gui.pdf.036 — One worker serializes visible-page decoding

- Recorded: 2026-09-07 20:45
- Updated: 2026-09-11 22:34 — Separate decoding concurrency from resident-memory accounting.
- Evidence: `PdfPageCache` owns one `Swag.Task`, one worker `Pdf.Reader` and one pending page.
  Scrolling past a slow page leaves paper placeholders until that worker catches up. A Reader
  is single-threaded; another worker needs its own mapping, object index and resource caches.
- Next: compare a bounded two-worker cache with the current one on the recorded 90 MB corpus
  document, measuring scroll-to-visible-page latency and the extra reader storage. Preserve
  document-close and cancellation behavior while defining page priority and publication.
- Complete when: the comparison establishes a bounded scheduling policy and improves visible-page
  latency on the same fixture without unbounded queues or stale-page publication.
- Related: std.gui.pdf.025, std.gui.pdf.029, std.gui.pdf.037

### std.gui.pdf.037 — Resident-page memory accounting omits retained resources

- Recorded: 2026-09-11 22:34
- Evidence: split from std.gui.pdf.036. `PdfResidentPage.measure` records only
  `page.memoryUsage()`. The resident entry also holds renderer textures, resolved fonts and a
  lazily built text index. Item accounting includes text and path storage but cannot account for
  those resident resources. The historical eight-page observation reported 18 MB while eviction
  freed 34 MB; it is not a new measurement of this checkout.
- Next: define which owned and shared allocations the budget covers, account for resident
  resources without double-counting shared typefaces, and compare against measured eviction.
- Complete when: decode, first paint, text indexing and zoom update the documented accounting,
  evictions respect that budget, and a measured corpus comparison states the remaining error.
- Related: std.pixel.027, std.gui.pdf.028, std.gui.pdf.036

### std.gui.pdf.029 — A render cannot be cancelled or bounded in time

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-07 20:45 — git: A decode that cannot be abandoned now blocks closing a document
- Intent: `RenderOptions` bounds the output dimensions and pixel count and nothing else. A page
  with a pathological number of paths can take arbitrarily long. This concerns the headless
  callers — a batch export, a thumbnailer, a test — and, since the viewer decodes pages on a
  worker, the viewer itself: `PdfPageCache.abandonLoad` cannot stop a decode, only wait for it,
  so closing a document while the worker is inside `Reader.loadPage` blocks the GUI thread for
  what remains of that page. The corpus measurement in std.gui.pdf.025 puts the worst page of a
  90 MB scanned document at 2.8 s.
- Next: give `decodePage` and the render loop the same cancellation signal, checked between
  content-stream operators and between items, and have `PdfPageCache` raise it instead of
  waiting.
- Complete when: a decode and a render both accept a cancellation signal and an optional work
  budget, report an interrupted result distinctly from a failed one, and closing a document
  never waits for a page.

### std.gui.pdf.001 — Encrypted documents are refused, including the empty-password case

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-06 07:51 — git: prompt 6
- Intent: `indexDocument` fails the whole document as soon as an `/Encrypt` entry or a standard
  security handler is seen. Files encrypted with an *empty* user password are rejected along with
  files requiring a password. The reader has no decryption path for either case.
- Complete when: the standard security handler is implemented for revisions 2 through 6 — RC4 40
  and 128 bit, AES-128 and AES-256 — strings and streams are decrypted per object with the correct
  key derivation, a document that opens with the empty user password opens silently, and one that
  needs a real password reports that distinctly from a malformed file so a caller can ask for it.
- Note: this is a decryption capability, not an authoring one. Never weaken, strip, or bypass a
  permission flag the file declares, and keep encryption *writing* out of scope.
- Note: the object index is now read from the file's own trailer chain, so a decrypted string or
  stream is decrypted per object as it is parsed rather than in a pass over everything.

### std.gui.pdf.002 — One unsupported construct loses the whole page

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-06 07:51 — git: prompt 6
- Intent: `loadPage` fails as a unit. A single JBIG2 scan or one JPEG 2000 photograph anywhere in
  a content stream costs the caller the entire page, including the text and vectors that decoded
  perfectly. For a viewer that is the difference between a page with a gap in it and a page that
  will not display. Other unsupported constructs are silently ignored or substituted instead;
  those paths also need an explicit limitation record.
- Complete when: a page decodes as far as it can, each construct it could not represent is
  recorded against the item that needed it with enough detail to name the feature, `Page` exposes
  those limitations to the caller, and a document-level failure is reserved for input that cannot
  be parsed at all.
- Note: the messages reach a user through Swag Scope's failure reporting, so they are user-facing
  English and must read as such.
- Related: std.gui.pdf.011, std.gui.pdf.012, std.gui.pdf.014, std.gui.pdf.015

### std.gui.pdf.010 — Text render modes other than fill and invisible are drawn filled

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-06 07:51 — git: prompt 6
- Intent: `Tr` is stored and then only consulted to detect the invisible modes 3 and 7. Mode 1
  paints outlined text, mode 2 fills and strokes it, and modes 4 through 7 add the run to the clip
  path — the standard way to fill text with an image or a gradient. Modes 1, 2, 4, 5 and 6 are
  drawn as a plain fill; mode 7 paints nothing but also contributes no clip. Outlined display type
  therefore renders solid, and subsequent content ignores the missing text clip.
- Complete when: an item carries its render mode, stroke and fill-and-stroke modes paint with the
  stroke color and width, and the clipping modes contribute the run's outline to the clip.

### std.gui.pdf.019 — Text output cannot leave Windows-1252 and the fourteen standard faces

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-06 07:51 — git: prompt 6
- Intent: `Page.addText` accepts UTF-8 and `windows1252` then fails the whole `save` on the first
  character outside that encoding. No font can be embedded, so the writer cannot express text
  such as Greek, Cyrillic, Hebrew, CJK or emoji.
- Complete when: a TrueType or OpenType program can be embedded, subset to the glyphs used, with a
  Type0 composite font, an Identity-H encoding and a `/ToUnicode` map so the output stays
  searchable and copyable; the standard faces remain the default so a Latin document still carries
  no font program; and a character that cannot be represented is reported with enough context to
  name it.
- Related: std.gui.pdf.020, std.gui.pdf.021

### std.gui.pdf.025 — Decoding a page costs five times what MuPDF charges for it

- Recorded: 2026-08-29 21:50
- Updated: 2026-09-06 07:51 — git: prompt 6
- Evidence: the recorded, undated comparison against MuPDF 1.28.2 used the whole corpus, alternating the two so both saw
  the same machine, in release configuration and taking the best of three. Opening the sixteen
  files cost 7.8 ms against 16.0 ms. The first page of each
  document cost 123 ms against 51.5 ms. Walking all 360 pages cost 1 262 ms against 259 ms.
  These are historical measurements, not validation of the current checkout.
- Note: this is measured on `Reader.open` and `Reader.loadPage`, which is what the viewer runs:
  [[Gui.PdfView]] paints the decoded page through the application's renderer, so the offline
  `Page.render` path is not on it. A stopwatch is only usable here when the machine is quiet;
  the same binary varies threefold across runs under load, and every conclusion below came from
  a counter or from two builds alternated in one sitting.
- Next: decoding a page splits, from accumulators inside `decodePage` in one run, into 1.4% of
  stream decompression, 1.9% of fonts, and the rest inside the content parser: images are 71% of
  it for 150 draws, text 12% for 163 000 runs, paths 0.3%. So the next thing to understand is why
  one image costs what a thousand text runs cost, and how much of that is the copy an image item
  takes rather than the decode itself.
- Complete when: the corpus decodes within twice MuPDF, measured the same way.
- Related: std.gui.pdf.026

### std.gui.pdf.031 — Document parsing has no adversarial corpus or overall resource budget

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-06 07:51 — git: prompt 6
- Intent: the stored PDF corpus stays below three megabytes per file. Generated tests cover
  cross-reference repair and incremental updates, and filter tests already reject a truncated
  run-length stream. There is no document-level adversarial matrix for cyclic page trees,
  contradictory lengths, declared-size attacks or very large scans. The parser has local depth
  limits but no overall memory or node budget.
- Note: two of these now have a test each — a blunted `startxref` falls through to the repair
  scan, and an incremental update resolves to the revision its trailer names — but they build
  their fixture at run time rather than carrying one, and neither is a hostile input.
- Complete when: a malformed corpus covers truncation, cycles, contradictory lengths and
  declared-size attacks with the expected error for each, a large fixture shows that opening
  costs the trailer chain rather than the file, and the parser refuses to allocate past a stated
  budget.

### std.gui.pdf.030 — Corpus rendering has no fixed page goldens

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-05 16:27 — git: Add unit tests for TaskProvider in providers.test.js
- Evidence: `pdf.corpus.test.swg` renders pages and asserts `image.isValid()`. The two golden-tagged
  cases in `pdf.prepare.test.swg` compare prepared and unprepared renders of the same corpus page,
  so they prove preparation parity but also pass if both paths acquire the same rendering defect.
  The PDF corpus has no fixed page expectations spanning its document families.
- Intent: protect the decoded output against an independently reviewed stored image, including a
  regression that paints a valid page entirely black.
- Complete when: a representative page from each corpus family has a golden, the fixtures that
  exercise text, images, strokes and forms compare rendered output rather than model fields, and a
  round trip through the writer is judged on its rendered result.
- Related: std.gui.pdf.021

### std.gui.pdf.017 — Outline, destinations, and link targets are not read

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-03 13:14 — git: Search a PDF's text on a worker instead of decoding every page on the GUI thread
- Intent: the catalog's `/Outlines`, its `/Names` destination tree and the `/Dest` or `/A` of a
  link annotation are never read, so a document has no navigable structure: no bookmarks pane, and
  a link that is drawn (once std.gui.pdf.003 lands) still cannot be followed.
- Complete when: the outline is exposed as a tree of titles and targets, a named or explicit
  destination resolves to a page index and a page-space position, and a link annotation reports
  its target — an internal destination, a URI, or neither.
- Related: std.gui.pdf.003

### std.gui.pdf.007 — A soft-masked text run takes one coverage for the whole run

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-03 06:44 — git: Implement soft mask support in PDF rendering
- Intent: a graphics-state `/SMask` now reaches every mark, but a text run cannot take a coverage
  that varies across it: a run is drawn from the glyph atlas, which is the one texture the painter
  samples for it, so the mask is folded in as its mean over the run's box. That is exact for the
  uniform mask a faded layer uses and an approximation for a gradient crossing a line of text.
- Evidence: `maskItem` in `decode.swg` branches on the item kind — a path takes the coverage as an
  anchored texture brush, an image takes it in its own alpha channel, and only text averages it.
- Next: decide where the exact form belongs. Either the painter grows a second texture unit a text
  run can be modulated by, or a masked run is rasterized into an image item, which costs the run
  its resolution independence in the viewer.
- Complete when: a gradient crossing a line of text darkens the letters it crosses rather than the
  whole run equally, or the entry is rewritten around a decision that says it may not.

### std.gui.pdf.003 — Annotation appearance streams are never drawn

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Intent: `/Annots` is not read. Links, form widgets, stamps, highlights, sticky notes, redaction
  marks and signature appearances all live in annotation appearance streams, and none of them
  reach the page. A commented or filled document renders as the blank form underneath it, with no
  indication that anything is missing.
- Complete when: the normal appearance stream of each annotation is drawn in annotation order
  after the page content, with its `/Rect` to `/BBox` mapping and `/Matrix` applied, hidden and
  no-view flags honoured, and annotations without an appearance stream skipped rather than
  synthesized.
- Note: draw appearances only. Never execute an `/AA`, an `/A` action, or embedded JavaScript.
- Related: std.gui.pdf.017

### std.gui.pdf.005 — Axial and radial shadings are not painted

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Intent: the `sh` operator falls through the content switch and paints nothing, and a shading
  pattern used as a fill paints nothing. Type 2 and type 3 shadings with sampled, exponential and
  stitching functions cover the overwhelming majority of gradients in real documents.
- Complete when: `sh` paints an axial or radial shading through the current clip, a shading
  pattern selected by `scn` fills a path with the same code, the `/Function` types needed by those
  two are evaluated, and the remaining shading types are reported per item.
- Related: std.gui.pdf.006

### std.gui.pdf.006 — Tiling patterns are not painted

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Intent: a type 1 pattern is a content stream tiled over a region — hatching in engineering
  drawings, texture fills in presentations. None of it is drawn.
- Complete when: a tiling pattern's cell is decoded once through the existing content parser,
  tiled over the filled region under the pattern matrix, and both paint types are handled, with
  the uncolored form taking its color from the `scn` operands.
- Related: std.gui.pdf.005

### std.gui.pdf.008 — Optional content is always drawn

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Intent: `BDC`, `BMC` and `EMC` fall through the content switch and `/OC` on an XObject is not
  read, so every optional content group is painted whatever its default configuration says. A
  drawing exported with construction layers off shows them on, and a multi-language artwork shows
  every language at once.
- Complete when: the catalog's `/OCProperties` default configuration decides which groups are
  visible, marked-content sections and XObjects belonging to a hidden group are skipped, and the
  group list is exposed so a caller can override the configuration.

### std.gui.pdf.011 — Type3 fonts are not decoded

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Intent: a Type3 font defines each glyph as a content stream under a `/FontMatrix`. Nothing here
  recognizes the subtype, so the run is handed to the substitute path, and its `/Widths` — which
  are in glyph space, not thousandths — are read as though they were normal metrics, so the text
  is both the wrong shape and the wrong size. Documents produced by older TeX toolchains and by
  drawing programs that embed bitmap fonts hit this.
- Complete when: a Type3 glyph is drawn by running its `CharProc` through the existing content
  parser under the font matrix and the text matrix, and its widths are interpreted in glyph space.

### std.gui.pdf.012 — The `/Decode` array is not applied to a DCT image

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Intent: four-component frames decode now, but a DCT image is the one sample representation whose
  `/Decode` array is ignored, because the frame reaches this module already converted to screen
  colours. A file that states its inks are stored complemented through that array rather than
  through the Adobe marker therefore renders inverted, and a partial range on a gray or colour
  photograph is dropped silently.
- Evidence: `decodeImage` hands `DCTDecode` straight to `Image.decode(".jpg", …)` and returns its
  colour result; every sampled representation beside it goes through `readSamplePlane`, which does
  read `/Decode`. The four-component path in `pixel` applies the Adobe complement itself, which is
  what a standalone CMYK JPEG needs and what a `/Decode` array would then apply twice.
- Next: decide where ink values are allowed to exist — either a four-component frame comes back from
  `pixel` as inks and this module converts them, or the decoder takes the decode ranges as an
  option — then apply the array on the DCT path for every component count.
- Complete when: a DCT image honours `/Decode` exactly as a sampled image does, and a fixture
  carries a CMYK photograph inverted through that array.
- Related: std.gui.pdf.002

### std.gui.pdf.014 — JBIG2 images are refused

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Intent: `JBIG2Decode` is the modern successor to CCITT for scanned text, and is what recent
  scanner firmware and PDF optimizers emit.
- Complete when: the generic region and text region decoding procedures are implemented, including
  the embedded stream form with a shared `/JBIG2Globals` segment.
- Related: std.gui.pdf.002, std.gui.pdf.015

### std.gui.pdf.015 — JPEG 2000 images are refused

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Intent: `JPXDecode` appears in print production and in some scanner output. It is the largest
  single decoder on this list and the rarest of the three, which is why it sits last.
- Complete when: the codestream form used by PDF decodes, or the codec is removed from the
  recognized set and reported as a first-class limitation instead of being half-recognized.
- Related: std.gui.pdf.002

### std.gui.pdf.018 — Page labels, dates, and XMP metadata are not read

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Intent: `Metadata` carries the six Info strings. `/CreationDate` and `/ModDate` are not read, the
  `/Metadata` XMP stream is not read, and `/PageLabels` is not read — so a document numbered
  `i, ii, iii, 1, 2` reports pages 1 through 5 and no viewer built on this can show the number the
  page itself carries.
- Complete when: the two dates are parsed from the PDF date form, the XMP packet is exposed as
  bytes with its common Dublin Core fields surfaced, and a page reports its label.

### std.gui.pdf.020 — Pages cannot be merged, split, or reordered without being redrawn

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Intent: `Document` can add and remove whole `Page` values, but a page loaded from a reader has
  been decoded into items and can only be written back through the writer — which re-encodes its
  text with a standard face, rasterizes nothing it cannot express, and loses everything in std.gui.pdf.021.
  Merging two documents and splitting one are the two most common things anyone does to a PDF, and
  neither can be done here without degrading the pages. There is also no insert-at-index and no
  reorder.
- Complete when: a page can be copied from one document to another at the object level — its
  content streams, resources and font programs carried across unchanged and renumbered — a page
  can be inserted at a position and moved, and a merge of two files that this module can open
  produces pages byte-identical in content to their sources.
- Related: std.gui.pdf.019, std.gui.pdf.024

### std.gui.pdf.021 — A decoded page loses its fill rule, its clips, and its intra-run positions

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Intent: the round trip is lossier than it looks. `appendPath` emits `f`, `B` and `S` and never
  their star forms, so a path decoded with the even-odd rule is written back with the winding rule
  and a ring drawn as two contours fills solid. An item's clip is decoded and then never written,
  so trimmed content reappears. And a text item is written as one `Tj` with the standard face's own
  metrics even though `textAdvances` holds the exact advance the document gave every code, so
  letters inside a run drift wherever the substitute's metrics differ.
- Complete when: the even-odd rule survives a decode-encode cycle, a clipped item is written back
  inside `q W n … Q`, a text run is written as a `TJ` array carrying the retained per-code
  advances, and a round-trip test compares rendered pages rather than only re-reading the model.
- Related: std.gui.pdf.019, std.gui.pdf.030

### std.gui.pdf.022 — An image is always rewritten as a Flate raster

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Intent: `encodeImagePixels` reduces every image to eight-bit gray or RGB and Flate-compresses
  it. A page that came in as a two-megabyte JPEG photograph leaves as a fifty-megabyte raster, a
  bilevel scan leaves as eight bits per pixel, and a palette image loses its palette. The same
  image used on twenty pages is written twenty times.
- Complete when: an image whose source is already a JPEG is passed through as `DCTDecode`, a
  bilevel or small-palette image is written at its natural depth or through an indexed space, and
  an image written more than once shares one object.

### std.gui.pdf.023 — Links, outline, and page labels cannot be written

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Intent: the writer emits a catalog, a page tree, an info dictionary, content, fonts and images.
  There is no way to write a link, a bookmark, a page label, or a document date, so a generated
  report cannot have a clickable table of contents — which is most of what a generated report is
  for.
- Complete when: a page can carry link annotations to a URI or to another page, a document can
  carry an outline tree and page labels, and `/CreationDate` and `/ModDate` are written.
- Related: std.gui.pdf.017, std.gui.pdf.018

### std.gui.pdf.024 — The writer emits only a classic cross-reference table

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Intent: every object is written uncompressed with a classic `xref` table, so a document with
  many small objects is larger than it needs to be, and there is no way to save a change to an
  existing file except by rewriting it whole — which, per std.gui.pdf.020, degrades every page it did not
  originate.
- Complete when: objects can be written into object streams behind a cross-reference stream, and a
  document opened from a file can be saved as an incremental update that appends rather than
  rewrites.
- Related: std.gui.pdf.020

### std.gui.pdf.026 — An image is copied once per page item that shows it

- Recorded: 2026-08-29 21:50
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Evidence: a decoded image is kept per document, so the second page showing a slide template
  does not decode it again — but it does copy it. `Item.image` is an owned `Image`, because
  `Reader.loadPage` states that a page owns what it retains and stays valid after its reader is
  released. A 2316x1154 template is eight megabytes per page that shows it, and the corpus pays
  that on a hundred of its cache hits.
- Next: measure the split between the copies and the decodes by counting cache hits and misses
  before designing anything; the fix needs either a shared buffer in `Core`, which does not
  exist, or a narrower ownership contract for `Page`, which is a decision rather than a change.
- Complete when: showing the same image on a hundred pages costs one copy of it, or the entry is
  rewritten around the ownership decision that says it may not.
- Related: std.gui.pdf.028, std.gui.pdf.025

### std.gui.pdf.028 — An embedded font program is copied once per page that uses it

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Intent: the *work* of decoding a font is now paid once per document, but each page still takes
  its own copy of the bytes, so a hundred-page thesis with a four-hundred-kilobyte embedded family
  still carries forty megabytes of duplicated font data. Sharing the bytes instead of copying them
  runs into the contract `Reader.loadPage` states — a page owns what it retains and stays valid
  after its reader is released — so it needs a shared buffer, which `Core` does not have, or a
  decision to narrow that contract.
- Complete when: `Core` publishes a shared byte buffer or the page ownership contract is settled,
  a decoded font program is shared between the pages that reference the same font object, and a
  `Document` load of the corpus costs one copy per distinct program.

---

## Out of scope

**Executing anything the document carries.** Actions, additional actions, embedded JavaScript, and
launch or submit behaviour are read as data at most, and never run. This is a permanent boundary,
not a gap.

**Encryption authoring.** std.gui.pdf.001 decrypts what a reader must open. Writing an encrypted document,
and anything that would strip or weaken a permission a file declares, stays out.

**Interactive form filling.** Drawing a form widget's appearance is std.gui.pdf.003; a field model with
values, validation, calculation order and appearance regeneration is a separate product and no
consumer needs it.

**Digital signature creation and validation.** Both need a certificate and trust story this
repository does not have.

**PDF/A, PDF/UA and tagged output.** Conformance is a claim about a whole pipeline, not a writer
feature, and claiming it without validation would be worse than not claiming it. Revisit only if
a consumer needs the claim.
