# PDF Backlog

This backlog covers the PDF family inside `std/gui`: the `Pdf` engine namespace under
`gui/src/controls/pdf` and the `PdfView` widget beside it.

PDF-specific evidence, investigations, and intended outcomes stay together here. Compiler issues belong in [compiler.frontend.md](compiler.frontend.md), [compiler.build.md](compiler.build.md),
[compiler.codegen.md](compiler.codegen.md), or [compiler.optimization.md](compiler.optimization.md). Language changes belong in
[language.design.md](language.design.md).
[README.md](README.md) has the whole layout.


## Entries

### std.gui.pdf.029 — A render cannot be cancelled or bounded in time

- Intent: `RenderOptions` bounds the output dimensions and pixel count and nothing else. A page
  with a pathological number of paths can take arbitrarily long. This concerns the headless
  callers — a batch export, a thumbnailer, a test — and, since the viewer decodes pages on a
  worker, the viewer itself: `PdfPageCache.abandonLoad` cannot stop a decode, only wait for it,
  so closing a document while the worker is inside `Reader.loadPage` blocks the GUI thread for
  what remains of that page. A historical measurement put the worst page of an external 90 MB,
  95-page scanned document with 1 073 images at 2.8 s through `Reader.loadPage`; that file is not
  in the stored corpus.
- Next: give `decodePage` and the render loop the same cancellation signal, checked between
  content-stream operators and between items, and have `PdfPageCache` raise it instead of
  waiting.
- Done when: a decode and a render both accept a cancellation signal and an optional work
  budget, report an interrupted result distinctly from a failed one, and closing a document
  never waits for a page.

### std.gui.pdf.036 — One worker serializes visible-page decoding

- Evidence: `PdfPageCache` owns one `Swag.Task`, one worker `Pdf.Reader` and one pending page.
  Scrolling past a slow page leaves paper placeholders until that worker catches up. A Reader
  is single-threaded; another worker needs its own mapping, object index and resource caches.
- Next: compare a bounded two-worker cache with the current one on a named large scanned
  fixture (the historical 90 MB, 95-page, 1 073-image document is external and not in the stored
  corpus, whose largest file is 2.6 MB; a generated equivalent can be shared with
  std.gui.pdf.031), measuring scroll-to-visible-page latency and the extra reader storage. Preserve
  document-close and cancellation behavior while defining page priority and publication.
- Done when: the comparison establishes a bounded scheduling policy and improves visible-page
  latency on the same fixture without unbounded queues or stale-page publication.
- Related: std.gui.pdf.025, std.gui.pdf.029, std.gui.pdf.037

### std.gui.pdf.031 — Document parsing has no adversarial corpus or overall resource budget

- Evidence: the stored corpus stays below three megabytes per file. Generated tests cover
  cross-reference repair (a blunted `startxref`) and incremental updates
  (`pdf.document.swg`), and filter tests reject a truncated run-length stream. None
  carries a hostile fixture. There is no document-level adversarial matrix for cyclic page
  trees, contradictory lengths, declared-size attacks or very large scans. The parser has local
  depth limits but no overall memory or node budget.
- Next: build the listed malformed-document corpus and define an overall document resource budget
  and a large-scan accounting fixture.
- Done when: a malformed corpus covers truncation, cycles, contradictory lengths and
  declared-size attacks with the expected error for each, a large fixture measures the full-file
  snapshot separately from lazy trailer/page indexing, and the parser refuses to allocate past
  a stated budget.

### std.gui.pdf.017 — Link annotation targets are not exposed by the reader

- Evidence: `Reader.loadOutline` already returns owned bookmark titles, hierarchy levels and
  page-space positions. It resolves direct and named destinations and local `GoTo` actions,
  including cyclic-name/outline protection; `documentoutline.swg` checks cropped and rotated
  destination coordinates. Swag Scope consumes this outline.
- Remaining: the page decoder does not read `/Annots`, so a link annotation exposes neither its
  bounds nor its `/Dest` or `/A` target. Bookmark destinations do not cover links within a page.
- Next: extract read-only link bounds and resolve local destinations through a shared destination
  resolver; expose URI targets as data and keep every action unexecuted.
- Done when: a link annotation reports its page bounds and local destination, URI or explicit
  unsupported-target result, with direct/named destination and malformed-action fixtures.
- Related: std.gui.pdf.003, app.scope.pdf.003

### std.gui.pdf.038 — PdfView has no facing-page layout

- Evidence: `PdfPageLayout` exposes Single and Continuous. `PdfView` already shares navigation,
  search, selection, and bounded page residency between them; it cannot place two pages per row.
- Next: add Facing and Continuous Facing through the existing layout and visible-range machinery,
  with an explicit cover-page rule that does not infer reading intent from page dimensions alone.
- Done when: both facing layouts preserve navigation, search, cross-page selection, and cache
  bounds; cover handling, unequal page sizes, gaps, and viewport resizing have regression coverage.
- Related: std.gui.pdf.039

### std.gui.pdf.039 — PdfView cannot fit a selected region to the viewport

- Evidence: `PdfZoomMode` (`controls/pdf/view.swg`) exposes FitPage, FitWidth, and Free; no
  operation derives zoom and scroll position from a selected page-space region.
- Next: define whether Fit Selection accepts text bounds, an explicit rectangle, or both, and
  implement it using the same page-to-viewport transforms as selection and search highlighting.
- Done when: fitting a nonempty region keeps it visible with defined padding, empty selection
  has a defined result, and selection spanning pages works in every supported layout.
- Related: std.gui.pdf.038

### std.gui.pdf.040 — PdfView cannot move a text caret or extend selection from the keyboard

- Evidence: the widget already supports pointer selection across pages, double-click word
  selection, Ctrl+A and Ctrl+C. Arrow keys scroll; they do not move a text caret or extend a
  selection. `pdfview.swg` protects cross-page pointer copy.
- Next: add keyboard movement and selection extension over the existing `PdfTextPosition` model,
  preserving pointer behavior and distinguishing text navigation from viewport scrolling.
- Done when: keyboard selection crosses words, lines, and pages, respects modifiers, reveals
  its caret, and survives lazy page loading with tests at the widget boundary.
- Related: std.gui.pdf.041

### std.gui.pdf.041 — PDF copy has no choice between logical and visual text order

- Evidence: `PdfView.selectedText` joins each selected page's indexed text with line feeds.
  There is one extraction order and no caller-selected copy mode.
- Next: define logical and visual copy orders against the retained glyph/source coordinates,
  including columns, bidirectional runs, and page boundaries, then expose the selected policy.
- Done when: both forms preserve their documented order on independent text fixtures and
  copying a selection retains its exact range across pages.
- Related: std.gui.pdf.040, std.gui.pdf.042

### std.gui.pdf.042 — PdfView has no reflow reading mode

- Evidence: `PdfView` paints positioned page items; zoom and page layout preserve the source
  geometry. Neither the widget nor its text index composes a reading surface whose lines wrap
  to the viewport width.
- Next: define a reading-order contract and the supported text subset before composing a reflow
  surface, retaining a route from reflowed text to its source page and selection coordinates.
- Done when: supported text reflows on resize without losing search or selection, unsupported
  structures have an explicit fallback, and multi-column fixtures protect the chosen order.
- Related: std.gui.pdf.041

### std.gui.pdf.037 — Resident-page memory accounting omits retained resources

- Evidence: `PdfResidentPage.measure` records only `page.memoryUsage()`. The resident entry
  also holds renderer textures, resolved fonts and a lazily built text index. Item accounting
  includes text and path storage but cannot account for those resident resources. An earlier
  eight-page observation reported 18 MB resident while eviction freed 34 MB.
- Next: define which owned and shared allocations the budget covers, account for resident
  resources without double-counting shared typefaces, and compare against measured eviction.
- Done when: decode, first paint, text indexing and zoom update the documented accounting,
  evictions respect that budget, and a measured corpus comparison states the remaining error.
- Related: std.pixel.027, std.gui.pdf.036

### std.gui.pdf.001 — Encrypted documents are refused, including the empty-password case

- Intent: `indexDocument` fails the whole document as soon as an `/Encrypt` entry or a standard
  security handler is seen. Files encrypted with an *empty* user password are rejected along with
  files requiring a password. The reader has no decryption path for either case.
- Next: implement standard-security-handler decryption with distinct empty-password,
  password-required, and malformed-document outcomes.
- Done when: the standard security handler is implemented for revisions 2 through 6 — RC4 40
  and 128 bit, AES-128 and AES-256 — strings and streams are decrypted per object with the correct
  key derivation, a document that opens with the empty user password opens silently, and one that
  needs a real password reports that distinctly from a malformed file so a caller can ask for it.
- Note: this is a decryption capability, not an authoring one. Never weaken, strip, or bypass a
  permission flag the file declares, and keep encryption *writing* out of scope.

### std.gui.pdf.002 — One unsupported construct loses the whole page

- Intent: `loadPage` fails as a unit. A single JBIG2 scan or one JPEG 2000 photograph anywhere in
  a content stream costs the caller the entire page, including the text and vectors that decoded
  perfectly. For a viewer that is the difference between a page with a gap in it and a page that
  will not display. Other unsupported constructs are silently ignored or substituted instead;
  those paths also need an explicit limitation record.
- Next: return safely decoded page items with per-item limitation records instead of discarding the
  whole page for unsupported content.
- Done when: a page decodes as far as it can, each construct it could not represent is
  recorded against the item that needed it with enough detail to name the feature, `Page` exposes
  those limitations to the caller, and a document-level failure is reserved for input that cannot
  be parsed at all.
- Note: the messages reach a user through Swag Scope's failure reporting, so they are user-facing
  English and must read as such.
- Related: std.gui.pdf.011, std.gui.pdf.012, std.gui.pdf.014, std.gui.pdf.015

### std.gui.pdf.010 — Text render modes other than fill and invisible are drawn filled

- Intent: `Tr` is stored and then only consulted to detect the invisible modes 3 and 7. Mode 1
  paints outlined text, mode 2 fills and strokes it, and modes 4 through 7 add the run to the clip
  path — the standard way to fill text with an image or a gradient. Modes 1, 2, 4, 5 and 6 are
  drawn as a plain fill; mode 7 paints nothing but also contributes no clip. Outlined display type
  therefore renders solid, and subsequent content ignores the missing text clip.
- Next: retain text render modes in items and implement stroke, fill-and-stroke, and text-clipping
  behavior.
- Done when: an item carries its render mode, stroke and fill-and-stroke modes paint with the
  stroke color and width, and the clipping modes contribute the run's outline to the clip.

### std.gui.pdf.019 — Text output cannot leave Windows-1252 and the fourteen standard faces

- Decoded text outside Windows-1252 can keep its horizontal CID TrueType program, glyph
  mapping and Unicode map when saved. This allows the FileSamples Wingdings and Symbol runs
  to be saved with the original font bytes and extracted characters.
- Authored text and edited runs still use Windows-1252 and the standard faces. The writer
  cannot author new runs in Greek, Cyrillic, Hebrew, CJK or emoji.
- Next: embed and subset TrueType/OpenType fonts with composite encoding and `ToUnicode` while
  retaining standard faces as the default.
- Done when: a TrueType or OpenType program can be embedded, subset to the glyphs used, with a
  Type0 composite font, an Identity-H encoding and a `/ToUnicode` map so the output stays
  searchable and copyable; the standard faces remain the default so a Latin document still carries
  no font program; and a character that cannot be represented is reported with enough context to
  name it.
- Related: std.gui.pdf.020, std.gui.pdf.021

### std.gui.pdf.025 — Decoding a page costs five times what MuPDF charges for it

- Evidence: a historical comparison with MuPDF 1.28.2 over the whole corpus, in release,
  alternated and best of three, measured `Reader.open` and `Reader.loadPage`, which are what
  [[Gui.PdfView]] runs. Opening the sixteen files cost 7.8 ms against 16.0 ms, the first page
  of each document about 2.4x MuPDF, and walking all 360 pages about 4.9x. A profile from that
  time put most of `decodePage` in the content parser, with images dominating (71% for 150
  draws) ahead of text (12% for 163 000 runs). The decoder has changed since.
- Next: rebaseline against MuPDF on a quiet machine by the same alternated method, then use
  accumulators inside `decodePage` to split image cost between the decode and the copy an
  image item takes (std.gui.pdf.026).
- Done when: the corpus decodes within twice MuPDF, measured the same way.
- Related: std.gui.pdf.026

### std.gui.pdf.030 — Corpus rendering has no fixed page goldens

- Evidence: `pdf.corpus.swg` renders pages and asserts `image.isValid()`. The two golden-tagged
  cases in `pdf.prepare.swg` compare prepared and unprepared renders of the same corpus page,
  so they prove preparation parity but also pass if both paths acquire the same rendering defect.
  The PDF corpus has no fixed page expectations spanning its document families.
- Intent: protect the decoded output against an independently reviewed stored image, including a
  regression that paints a valid page entirely black.
- Next: add independently reviewed fixed page goldens spanning the PDF corpus families and a
  valid-but-black-page regression.
- Done when: a representative page from each corpus family has a golden, the fixtures that
  exercise text, images, strokes and forms compare rendered output rather than model fields, and a
  round trip through the writer is judged on its rendered result.
- Related: std.gui.pdf.021

### std.gui.pdf.007 — A soft-masked text run takes one coverage for the whole run

- Intent: a graphics-state `/SMask` now reaches every mark, but a text run cannot take a coverage
  that varies across it: a run is drawn from the glyph atlas, which is the one texture the painter
  samples for it, so the mask is folded in as its mean over the run's box. That is exact for the
  uniform mask a faded layer uses and an approximation for a gradient crossing a line of text.
- Evidence: `maskItem` in `decode.swg` branches on the item kind — a path takes the coverage as an
  anchored texture brush, an image takes it in its own alpha channel, and only text averages it.
- Next: decide where the exact form belongs. Either the painter grows a second texture unit a text
  run can be modulated by, or a masked run is rasterized into an image item, which costs the run
  its resolution independence in the viewer.
- Done when: a gradient crossing a line of text darkens the letters it crosses rather than the
  whole run equally, or the entry is rewritten around a decision that says it may not.

### std.gui.pdf.003 — Annotation appearance streams are never drawn

- Intent: `/Annots` is not read. Links, form widgets, stamps, highlights, sticky notes, redaction
  marks and signature appearances all live in annotation appearance streams, and none of them
  reach the page. A commented or filled document renders as the blank form underneath it, with no
  indication that anything is missing.
- Next: decode and paint normal annotation appearance streams in order with their mapping and
  visibility flags, without executing actions.
- Done when: the normal appearance stream of each annotation is drawn in annotation order
  after the page content, with its `/Rect` to `/BBox` mapping and `/Matrix` applied, hidden and
  no-view flags honoured, and annotations without an appearance stream skipped rather than
  synthesized.
- Note: draw appearances only. Never execute an `/AA`, an `/A` action, or embedded JavaScript.
- Related: std.gui.pdf.017

### std.gui.pdf.005 — Axial and radial shadings are not painted

- Intent: the `sh` operator falls through the content switch and paints nothing, and a shading
  pattern used as a fill paints nothing. Type 2 and type 3 shadings with sampled, exponential and
  stitching functions cover the overwhelming majority of gradients in real documents.
- Next: evaluate the required function types and paint axial and radial shadings through the current
  clip and shading-pattern fills.
- Done when: `sh` paints an axial or radial shading through the current clip, a shading
  pattern selected by `scn` fills a path with the same code, the `/Function` types needed by those
  two are evaluated, and the remaining shading types are reported per item.
- Related: std.gui.pdf.006

### std.gui.pdf.006 — Tiling patterns are not painted

- Intent: a type 1 pattern is a content stream tiled over a region — hatching in engineering
  drawings, texture fills in presentations. None of it is drawn.
- Next: decode tiling-pattern cells once and tile them under the pattern matrix, preserving colored
  and uncolored paint behavior.
- Done when: a tiling pattern's cell is decoded once through the existing content parser,
  tiled over the filled region under the pattern matrix, and both paint types are handled, with
  the uncolored form taking its color from the `scn` operands.
- Related: std.gui.pdf.005

### std.gui.pdf.008 — Optional content is always drawn

- Intent: `BDC`, `BMC` and `EMC` fall through the content switch and `/OC` on an XObject is not
  read, so every optional content group is painted whatever its default configuration says. A
  drawing exported with construction layers off shows them on, and a multi-language artwork shows
  every language at once.
- Next: read the default optional-content configuration and apply visibility to marked content and
  `XObjects`.
- Done when: the catalog's `/OCProperties` default configuration decides which groups are
  visible, marked-content sections and XObjects belonging to a hidden group are skipped, and the
  group list is exposed so a caller can override the configuration.

### std.gui.pdf.011 — Type3 fonts are not decoded

- Intent: a Type3 font defines each glyph as a content stream under a `/FontMatrix`. Nothing here
  recognizes the subtype, so the run is handed to the substitute path, and its `/Widths` — which
  are in glyph space, not thousandths — are read as though they were normal metrics, so the text
  is both the wrong shape and the wrong size. Documents produced by older TeX toolchains and by
  drawing programs that embed bitmap fonts hit this.
- Next: decode Type3 `CharProcs` under their font and text matrices and interpret widths in glyph
  space.
- Done when: a Type3 glyph is drawn by running its `CharProc` through the existing content
  parser under the font matrix and the text matrix, and its widths are interpreted in glyph space.

### std.gui.pdf.012 — The `/Decode` array is not applied to a DCT image

- Evidence: direct, unmasked `DeviceCMYK` DCT images use the declared ink ranges before
  conversion to screen colours. The decoder handles subsampled four-component JPEG streams
  and a default-range stream survives saving with its original JPEG bytes. The 62-page check
  gains the public `cmykjpeg.pdf` page and improves the explicitly inverted stress page's
  mean RGB difference against PDFium from 20.40 to 12.49 channel levels. The other 60 pages
  have the same bitmap checksums in that comparison.
- Direct grayscale and RGB JPEGs also apply the declared component ranges before composition.
  The public mask page's mean RGB difference against PDFium drops from 8.64 to 1.25 levels.
  A large default JPEG soft mask loads in 16.29 ms, down from 24.15 ms, with the same raster.
- Direct grayscale and RGB DCT color keys now test the decoded JPEG samples before color
  mapping. The inverted grayscale fixture matches PDFium pixel for pixel. The partial-range
  RGB fixture's mean channel difference against PDFium drops from 62.31 to 0.47 levels.
- Composing the keyed RGB samples straight into RGBA reduces load on the large JPEG key
  fixture from 75.08 to 56.47 ms against the new key-aware reader, with identical Swag pixels.
- Resource-named DCT paths, CMYK masks and RGB `DecodeParms` remain open. Direct CMYK refers
  to device colours without an ICC transform.
- Done when: each DCT image path honours `/Decode` with coverage for ranges, masks and
  colour spaces.
- Related: std.gui.pdf.002

### std.gui.pdf.014 — JBIG2 images are refused

- Intent: `JBIG2Decode` is the modern successor to CCITT for scanned text, and is what recent
  scanner firmware and PDF optimizers emit.
- Next: implement bounded JBIG2 generic/text-region decoding including shared `JBIG2Globals`
  segments.
- Done when: the generic region and text region decoding procedures are implemented, including
  the embedded stream form with a shared `/JBIG2Globals` segment.
- Related: std.gui.pdf.002, std.gui.pdf.015

### std.gui.pdf.015 — JPEG 2000 images are refused

- Intent: `JPXDecode` appears in print production and in some scanner output. It is the largest
  single decoder on this list and the rarest of the three, which is why it sits last.
- Next: implement the PDF JPEG 2000 codestream subset or report it as an explicit per-item
  limitation.
- Done when: the codestream form used by PDF decodes, or the codec is removed from the
  recognized set and reported as a first-class limitation instead of being half-recognized.
- Related: std.gui.pdf.002

### std.gui.pdf.018 — Page labels, dates, and XMP metadata are not read

- Intent: `Metadata` carries the six Info strings. `/CreationDate` and `/ModDate` are not read, the
  `/Metadata` XMP stream is not read, and `/PageLabels` is not read — so a document numbered
  `i, ii, iii, 1, 2` reports pages 1 through 5 and no viewer built on this can show the number the
  page itself carries.
- Next: read creation/modification dates, XMP metadata, and page labels with their stated source
  forms.
- Done when: the two dates are parsed from the PDF date form, the XMP packet is exposed as
  bytes with its common Dublin Core fields surfaced, and a page reports its label.

### std.gui.pdf.020 — Pages cannot be merged, split, or reordered without being redrawn

- Intent: `Document` can add and remove whole `Page` values, but a page loaded from a reader has
  been decoded into items and can only be written back through the writer — which re-encodes its
  text with a standard face, rasterizes nothing it cannot express, and loses everything in std.gui.pdf.021.
  Merging two documents and splitting one are the two most common things anyone does to a PDF, and
  neither can be done here without degrading the pages. There is also no insert-at-index and no
  reorder.
- Next: copy and renumber page object graphs without redrawing and add insert-at-index and reorder
  operations.
- Done when: a page can be copied from one document to another at the object level — its
  content streams, resources and font programs carried across unchanged and renumbered — a page
  can be inserted at a position and moved, and a merge of two files that this module can open
  produces pages byte-identical in content to their sources.
- Related: std.gui.pdf.019, std.gui.pdf.024

### std.gui.pdf.021 — A decoded page loses its fill rule, its clips, and its intra-run positions

- Intent: the round trip is lossier than it looks. `appendPath` emits `f`, `B` and `S` and never
  their star forms, so a path decoded with the even-odd rule is written back with the winding rule
  and a ring drawn as two contours fills solid. An item's clip is decoded and then never written,
  so trimmed content reappears. And a text item is written as one `Tj` with the standard face's own
  metrics even though `textAdvances` holds the exact advance the document gave every code, so
  letters inside a run drift wherever the substitute's metrics differ.
- Next: preserve fill rules, clips, and per-code text advances through writing and compare the
  round-trip rendering.
- Done when: the even-odd rule survives a decode-encode cycle, a clipped item is written back
  inside `q W n … Q`, a text run is written as a `TJ` array carrying the retained per-code
  advances, and a round-trip test compares rendered pages rather than only re-reading the model.
- Related: std.gui.pdf.019, std.gui.pdf.030

### std.gui.pdf.022 — Preserve encoded and natural-depth images

- Intent: preserve the original encoded samples and natural depth when the PDF can carry them.
  Retaining a source JPEG avoids expensive recompression, and an indexed image can use its palette.
- Evidence: shared image objects
  cut save time from 1,410 to 197 ms on eight pages using one photo. The output shrinks
  from 9.81 to 1.23 MB. PDFium renders every saved page identically. Opaque images
  skip compression of redundant soft masks.
- Evidence: one-bit gray streams
  cut save time from 125 to 51 ms on the PDF.js bilevel scan. The output renders
  identically through PDFium.
- Evidence: PNG Sub prediction
  brings the large smooth RGB case from 135 to 65 ms to save and cuts its size
  from 1.23 to 0.63 MB. The saved pages retain their PDFium rasters.
- Evidence: retained RGB JPEG streams
  cut the large public JPEG save from 588 to 0.58 ms and reduce the output from
  11.95 to 1.43 MB. Both public RGB JPEG pages render exactly as the originals
  through PDFium.
- Retaining a CMYK JPEG and its inverted ink ranges brings the public CMYK stress page
  from 223 to 0.20 ms to save and from 5.47 to 0.83 MB. PDFium renders the saved page
  byte for byte like the source.
- Retaining indexed Flate images and device palettes brings the public indexed fixture
  from 65.56 to 0.15 ms to save and from 355 to 275 kB. PDFium renders the saved page
  pixel for pixel like the source. Different palettes for equal packed samples keep distinct
  image objects.
- Gray and RGB JPEG streams with default or inverted component directions also survive saving.
  Three public-derived range variants save in 0.14–0.46 ms, down from 104–557 ms, with
  unchanged raw JPEG bytes and PDFium raster. A fourth case retains explicit interpolation.
- JPEGs with direct gray or RGB color keys retain their original compressed data and mask
  bounds. Three derived fixtures save in 0.18–0.46 ms, down from 175–572 ms. PDFium renders
  the stored JPEGs identically at scales 1 and 0.44, and differing keys remain distinct.
- Next: retain fractional JPEG decode ranges and encode newly authored palette images.
- Done when: an image whose source is already a JPEG is passed through as `DCTDecode`, a
  bilevel or small-palette image is written at its natural depth or through an indexed space, and
  an image written more than once shares one object.

### std.gui.pdf.023 — Links, outline, and page labels cannot be written

- Intent: the writer emits a catalog, a page tree, an info dictionary, content, fonts and images.
  There is no way to write a link, a bookmark, a page label, or a document date, so a generated
  report cannot have a clickable table of contents — which is most of what a generated report is
  for.
- Next: add writer support for link annotations, outline trees, page labels, and document dates.
- Done when: a page can carry link annotations to a URI or to another page, a document can
  carry an outline tree and page labels, and `/CreationDate` and `/ModDate` are written.
- Related: std.gui.pdf.017, std.gui.pdf.018

### std.gui.pdf.024 — The writer emits only a classic cross-reference table

- Intent: every object is written uncompressed with a classic `xref` table, so a document with
  many small objects is larger than it needs to be, and there is no way to save a change to an
  existing file except by rewriting it whole — which, per std.gui.pdf.020, degrades every page it did not
  originate.
- Next: add object/cross-reference streams and incremental append-only saves for documents opened
  from files.
- Done when: objects can be written into object streams behind a cross-reference stream, and a
  document opened from a file can be saved as an incremental update that appends rather than
  rewrites.
- Related: std.gui.pdf.020

### std.gui.pdf.026 — An image is copied once per page item that shows it

- Evidence: shared decoded images
  take 16 warmed loads of the same large JPEG page from 228 to 0.072 ms and
  lower peak memory from 624,876 to 79,212 KiB. Pages keep their own references
  and isolate page-specific alpha edits.
- Evidence: sharing device images across page resources
  reduces four warmed page loads on the public shared-resource document from 49 to 1.8 ms.
  Named spaces keep their resource context and all 52 supported rasters match.
- Related: std.gui.pdf.025.

### std.gui.pdf.043 — Store a page item's representation in a tagged union

- Evidence: `Pdf.Item` keeps its text (`String` and two arrays), path (`LinePathList`) and image
  (`Image`) storage alive whatever its `kind`, and its accessors test `kind` by hand
  ([item.swg](../bin/std/modules/gui/src/controls/pdf/item.swg)).
- Next: move the text, path and image members under `union(ItemKind)`, keeping the transform,
  colors, clip, blend and mask beside it; turn `createText`, `createPath` and `createImage` into
  case transitions and the `kind` tests into `is` and `switch`; run the PDF tests and the Swag
  Scope PDF viewer tests.
- Done when: an item holds only its own kind's storage, and the PDF module and viewer tests pass.
- Related: language.design.055.

---

### std.gui.pdf.044 — PDF packed samples and mask composition remain scalar

- Evidence: default 8-bit gray/CMYK conversion, standard soft masks, single-component color
  keys, RGB/alpha composition and one-bit mask expansion already have packed paths in
  `decode.image.swg`. Different-size masks use exact quotient-and-remainder coordinates.
  Non-default decode arrays, other sample widths and remaining composition paths still need
  separate profiling and vectorization.
- Inverting complete RGB samples in a packed pass and resolving color-key bounds once per
  image reduces load on the public mask fixture from 58.49 to 27.48 ms. Its matching CPU
  total goes from 73.41 to 43.38 ms against PDFium's 58.06 ms, with identical Swag pixels.
- Next: vectorize remaining decode arrays, packed and 16-bit samples, color-key comparisons,
  mask scaling, and remaining alpha composition.
- Done when: PDF image fixtures preserve pixels across remaining bit depths, masks, decode
  arrays, and indexed spaces, with separate conversion benchmarks.
- Related: std.core.042, std.core.044, std.core.047.

### std.gui.pdf.045 — First-page rendering trails PDFium on FileSamples

- Evidence: a Linux x86-64 Release recheck at `3bb8cc76d7` used one Swag worker
  and nine interleaved runs after warm-up. Both paths materialized a BGRA bitmap with a 1200 px
  long side. PDFium 159.0.8149.0 used its raw bitmap API. Times are medians in milliseconds.

  | Fixture | Swag open | Swag load | Swag render | Swag total | PDFium total |
  | --- | ---: | ---: | ---: | ---: | ---: |
  | `sample1.pdf` | 0.49 | 16.27 | 61.07 | 77.79 | 29.54 |
  | `sample2.pdf` | 0.19 | 3.05 | 20.21 | 23.64 | 4.66 |
  | `sample3.pdf` | 1.08 | 7.00 | 47.74 | 55.81 | 11.02 |

  On `sample1`, Swag spends 14.6 ms building the images during page load and 18.4 ms shading
  textured triangles. PDFium decodes the image pixels during rendering. Its native profile shows
  JPEG entropy decoding, AVX2 IDCT and color conversion, and scanline resampling. On `sample2`,
  Swag spends 7.6 ms shading textured triangles and 5.8 ms shading bitmap glyphs.

  On `sample3`, Swag records commands in 18.6 ms, including 12.3 ms for glyph cache misses,
  and executes them in 24.5 ms. It submits about 53,000 solid triangles. The three pages produce
  603, 845 and 937 Swag text items versus 166, 33 and 142 PDFium text objects. The PDF parser
  emits one item per string inside a `TJ` array. PDFium's profile shows FreeType and AGG
  scanline compositing, while Swag runs a triangle pipeline for those draws.

  Rendering the same `sample3` page again still rebuilt 433 glyph cache entries. A diagnostic
  variant that retained the CPU renderer cut that repaint from 45.8 to 31.4 ms with the same
  raster CRC-32. `PdfView` already keeps its renderer and page textures and prepares geometry on
  a worker, outside this bitmap benchmark. At 2400 px, an experimental bitmap-only font policy
  cut the Swag raster time on `sample1` from about 304 to 154 ms and on `sample3` from 130 to 66 ms.
  The pixel checksums changed. The automatic font policy selects MSDF at larger device sizes,
  which made MSDF shading alone cost 133 ms on `sample1` at that scale.
- The follow-up against `bbb9380105` measured the same files on Linux with one Swag worker pinned
  to one CPU. The numbers are medians in milliseconds of 14 interleaved measurements per
  variant after warm-up. Each measurement reopened the file and materialized page one as BGRA.

  | Fixture | 1200 px Swag before | Swag after | PDFium 159 | 2400 px Swag before | Swag after | PDFium 159 |
  | --- | ---: | ---: | ---: | ---: | ---: | ---: |
  | `sample1.pdf` | 86.62 | 57.50 | 28.50 | 318.11 | 142.90 | 44.27 |
  | `sample2.pdf` | 24.00 | 16.70 | 5.83 | 94.71 | 52.40 | 12.67 |
  | `sample3.pdf` | 53.16 | 44.75 | 11.60 | 155.71 | 90.63 | 19.95 |

  The CPU renderer now blends bitmap glyph masks directly in SIMD spans, shades interior
  texture spans with the original bilinear weights, and accumulates stroke coverage without
  entering the general fragment shader. MSDF taps convert packed atlas texels and floor their
  coordinates with SIMD. PDF text decoding retains the Unicode text, font codes and advances
  in the same pass. At 1200 px all three complete images match the baseline byte for byte.
  At 2400 px the PDF bitmap export uses device-sized bitmap glyphs for eligible axis-aligned
  runs. That changes some text pixels and avoids the cost of constructing and sampling MSDFs.

  AGG composites coverage spans. On `sample3`, most of Swag's 53,000 path triangles came
  from eight thin strokes with a 0.14-point on/off dash pattern. At 1200 px a repeat spans
  about 0.4 pixels. Averaging the coverage made those rules visibly lighter in a test. The
  exact stroke path still generates their geometry. A timing probe measured about 5 ms
  recording paths, 7–8 ms rasterizing stroke overlaps, and 14–15 ms recording text.
  [PDFium AGG backend](https://pdfium.googlesource.com/pdfium/+/refs/heads/chromium/8164/core/fxge/agg/cfx_agg_devicedriver.cpp)

  On `sample1`, page loading still takes about 16 ms, including about 12 ms in the JPEG
  stream read and decode. Swag materializes the images and their mask at the stored
  resolution. PDFium can defer JPEG decoding until render and uses a decoder that
  exposes scanlines. [PDFium JPEG decoding](https://github.com/chromium/pdfium/blob/main/core/fxcodec/jpeg/jpegmodule.cpp)
- Against `eab46cd563`, the sampled stroke optimizations take `sample3.pdf` from 46.09
  to 43.75 ms at 1200 px and from 77.51 to 74.89 ms at 2400 px. The same one-core
  PDFium 159 runs take 11.96 and 18.71 ms. These are medians of 14 interleaved
  measurements after warm-up. Both paths reopen the file and materialize the first
  page as BGRA each time.

  At 1200 px, about 21,000 of the 50,500 solid-stroke triangles on that page have no
  pixel centre inside their axis-aligned bounds. The CPU renderer rejects those
  triangles before accumulating coverage and uses the painter's recorded extrema to
  bound axis-aligned batches. Short spans reuse their edge values for coverage. The
  raster comparison matches byte for byte on every FileSamples document at 600,
  1200, and 2400 px. Timing changes on `sample1.pdf` and `sample2.pdf` were small.
  The painter still emits the full dash geometry. Caching character-to-glyph
  lookups during PDF recording showed little benefit in isolation.
- A comparison covered 31 pages at 1200 px, including 26 public PDFs. Swag's packed grayscale
  conversion cuts the PDF.js one-bit scan from 422 to 121 ms with the same bitmap CRC-32.
  PDFium takes 26 ms. On the PDFBox JPEG and scan, most of the remaining time is in
  scaled image painting. The curves fixture submits about 3.15 million stroke
  triangles. Nested clips add polygon intersection at load and stencil writes at render.
  The transformed-text fixture spends about 0.79 s in MSDF triangle draws.
- Device-space clip intersection brings the 1200 px public clip fixture from 244 to 54 ms end to end. Loading
  takes about 8 ms in both engines. PDFium takes 43 ms total. The curved strokes
  fixture remains dominated by multi-segment and dashed stroke geometry.
- Separable image resampling takes the PDFBox JPEG from about 38 to 12 ms and its bilevel scan from 46 to 11 ms
  at 1200 px. PDFium takes 4 and 2 ms respectively. Texture rendering remains the
  largest Swag cost for those two pages.
- Packed joins and dashes take the dense 1200 px curve page from 1531 to 898 ms. PDFium takes 343 ms.
  The CPU painter blends the union of stroke bodies, caps and joins once per
  path, moving the curve fixture's mean RGB closer to PDFium. The geometry walk
  still creates every dash outline and the rasterizer samples four subrows.
- Indexed image decoding
  brings the 1200 px indexed stress page from 389 to 55 ms. Palette conversion
  now happens once per entry. The page loads in 20 ms, down from 356 ms.
  PDFium takes 34 ms total. All 43 supported cases retain their bitmap CRC-32.
- Sixteen-bit RGB images
  take the PDF.js fixture from 130 to 49 ms total at 1200 px. SIMD quantization
  cuts load from 98 to 18 ms with identical RGB. PDFium takes 20 ms.
- SIMD for cached image rows
  reduces the 2400 px PDFBox scan from 42 to 28 ms. PDFium takes 6 ms.
  All 43 supported pages retain the same bitmap CRC-32.
- Transformed glyph outlines
  take the transformed text fixture from 974 to 389 ms at 1200 px and from
  5133 to 1372 ms at 2400 px. PDFium takes 163 and 292 ms. Cached glyph
  outlines improve mean RGB agreement and preserve PDF advances.
- Applying soft mask coverage
  brings the transformed mask fixture from 927 to 174 ms at 1200 px.
  PDFium takes 106 ms. The 43 supported cases keep their bitmap checksums.
- Shared PNG predictor kernels
  take the public Flate predictor page from 107 to 71 ms at 1200 px and reduce
  loading from 68 to 37 ms. PDFium takes 48 ms overall. All 43 supported cases
  retain their bitmap checksums.
- Reusing translated soft masks
  cuts load from 69 to 38 ms on the transformed mask fixture. At 1200 px the
  total goes from 174 to 113 ms against PDFium's 94 ms. All 43 supported cases
  retain their bitmap checksums.
- Packed sampling for reduced images
  cuts 2400 px render time on the transformed mask fixture from 233 to
  111 ms and brings the total from 274 to 161 ms against PDFium's 233 ms.
  All 43 supported cases retain their bitmap checksums.
- The 62-page comparison
  now measures FileSamples at 28.21, 9.56 and 21.72 ms at 1200 px. In the same
  series PDFium takes 25.35, 4.54 and 11.00 ms. Swag is ahead on the large CCITT,
  bilevel and gray scans at both tested sizes. The two new image paths preserve
  every supported Swag raster checksum. The remaining curve and transformed-text
  gaps call for reducing compound stroke and glyph scan conversion work. Keeping
  encoded images available could let bitmap rendering decode at the requested size.
- Merging equally oriented intervals in the CPU scan converter reduces the compound curve
  page from 688 to 645 ms at 1200 px and from 1484 to 1405 ms at 2400 px. In the same
  one-core series PDFium takes 231 and 448 ms. At 1200 px, 60 of 61 supported pages keep
  their previous bitmap checksum. The remaining forms page differs by at most one byte per
  color channel because overlapping spans add their coverage in a different order.
- Scan conversion of transformed substitute glyphs takes the transformed-text stress page
  from 296 to 184 ms at 1200 px and from 1168 to 313 ms at 2400 px. PDFium takes 147 and
  236 ms in the same one-core series. Before the change, the MSDF shader alone takes about
  0.95 s at 2400 px. In the expanded comparison at 1200 px all other 86 supported pages keep
  their checksums. The stress page's mean RGB difference from PDFium is 21.61 to 21.56 at
  1200 px and 17.11 to 17.30 at 2400 px out of 255 levels.
- Collecting stroke fragments directly as intervals and merging neighboring overlaps takes
  the dense curve page from 663 to 465 ms at 1200 px and from 1419 to 948 ms at 2400 px.
  PDFium takes 277 and 448 ms in those series. Of 88 pages, 87 keep their bitmap checksums
  and the remaining forms page differs by one level in one pixel. The native stroke comparison
  goes from 34.86 to 29.77 ms against AGG's 19.27 ms with the same Swag coverage.
- Borrowing single-Flate inputs and reserving a bounded raster row estimate takes the
  public RGB16 page from 12.44 to 9.51 ms of load and from 21.53 to 19.29 ms total.
  The same runs measure PDFium at 16.69 ms. Seven tested pages keep their bitmap checksums.
- Scan conversion and an opaque RGB span compositor reduce the advanced blend-mode page
  from 315 to 248 ms in the first series, then from 195 to 90 ms in the opaque-span series.
  PDFium takes 81 ms in the latter. Mean RGB difference from PDFium changes from 2.52 to
  2.44 levels at 1200 px. The group and graphics-state controls retain identical pixels.
- Packed constant CCITT tables take the six-image CCITT fixture from 0.178 to 0.107 ms
  of load, and the large fax page from 5.95 to 5.74 ms. The three measured rasters are exact
  matches for the previous Swag output.
- Done when: the first-page gap has a stage-level explanation and the dominant work is within 1.25×
  of an equivalent PDFium render, or a concrete fidelity or safety tradeoff justifies the remainder.
- Related: app.scope.viewers.009.
