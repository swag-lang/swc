# Pdf Roadmap

This file is the roadmap for the PDF family inside `std/gui` — the `Pdf` engine namespace under
`gui/src/controls/pdf` and the `PdfView` widget beside it — measured against the PDF engines it
competes with: PDFium, MuPDF, Poppler and pdf.js on the reading side, PDFBox and iText on the
document side, and QuestPDF, ReportLab and wkhtmltopdf on the writing side.

It is not the repository's discovery backlog. Defects and leads belong in the `findings.*` files,
which hold evidence; compiler and language intent belongs in [todo.compiler.md](todo.compiler.md)
and [todo.language.md](todo.language.md). This file holds intent about
`bin/std/modules/gui/src/controls/pdf`. [README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

## Where the module already stands

The engine covers the path a normal office or academic
document takes end to end: classic indirect objects, compressed object streams, page trees with
inherited attributes, page rotation, the Flate, LZW, ASCII hexadecimal, ASCII85 and run-length
filters with the TIFF and PNG predictors at every supported depth, the complete text state, the
vector path and stroke geometry, simple and composite fonts with `/Widths`, `/W`, `/Differences`
and `/ToUnicode`, embedded TrueType and OpenType programs addressed the way the file keys them,
and every sample representation a raster can use from one to sixteen bits per component across
the device, calibrated, ICC-based, indexed, Lab, separation and DeviceN spaces, with decode
arrays, stencil masks, soft masks and color key masks.

Three things stand out.

- **It writes as well as it reads.** Poppler and pdf.js do not write at all; PDFium's writer is an
  afterthought. A `Document` here is editable and round-trippable, and the writer emits a
  deterministic file.
- **The substitute font path is unusually careful.** When a program cannot be drawn, the face is
  chosen from the descriptor's own traits and the run is then condensed to the advances the
  document declared, per character code. Most readers let the substitute's own metrics drive the
  line, which is what turns a justified paragraph into one that misses its margin.
- **The corpus is real.** 354 pages from eleven LLVM and Polly documents produced by several
  generations of writers, plus five PDFBox fixtures, all decoded lazily through `Pdf.Reader`.
- **The widget renders what the host shows.** `PdfView` keeps the decoded page, rasterizes at the
  displayed scale — zoom and monitor scale included — and past a fixed pixel budget rasterizes
  the visible region alone, so a deep zoom costs the viewport rather than the page.

The gaps are of three kinds: documents that will not open at all, pages that open and then render
as something other than what they mean, and a writer that can only express what it can itself
draw.

## Where this family lives, and why

This engine began as the standalone `std/pdf` module, and the question of whether that separation
was justified was examined and then decided the other way: a document viewer's rendering is
host-driven — the zoom, the monitor scale, and the visible region all belong to the widget showing
the page — so the engine lives beside its widget, exactly as the HTML and Markdown engines live
beside `HtmlView` and `MarkdownView`. `PdfView` owns the decoded page and rasterizes the region
the viewport shows at the scale it is shown at; a fixed rasterization handed to a generic image
widget was the wrong architecture, and was what made zooming freeze.

One consequence is recorded rather than hidden: the writer (`Pdf.Document.encode`) now lives above
`pixel`, so [T-054](todo.pixel.md#t-054--no-vector-output) — PDF output from the painter — can no
longer be satisfied by calling into it from `pixel`. When that entry is taken up, either the
writer moves below both consumers or `pixel` grows its own, and that choice belongs to T-054.

---

## Tier A — Documents that do not open

### T-427 — Encrypted documents are refused, including the empty-password case

- Intent: `indexDocument` fails the whole document as soon as an `/Encrypt` entry or a standard
  security handler is seen. A large share of production files are encrypted with an *empty* user
  password, purely to declare permissions, and every competing reader opens them without ever
  asking the user anything. Today those files cannot be opened at all, which is the single largest
  category of documents this module rejects.
- Complete when: the standard security handler is implemented for revisions 2 through 6 — RC4 40
  and 128 bit, AES-128 and AES-256 — strings and streams are decrypted per object with the correct
  key derivation, a document that opens with the empty user password opens silently, and one that
  needs a real password reports that distinctly from a malformed file so a caller can ask for it.
- Note: this is a decryption capability, not an authoring one. Never weaken, strip, or bypass a
  permission flag the file declares, and keep encryption *writing* out of scope.
- Related: T-428

### T-428 — The cross-reference table is never read

- Intent: `scanObjects` finds objects by scanning the entire file for an `N G obj` pattern and
  keeps the last definition it meets. That is a good *repair* path and a poor *primary* one. Four
  consequences follow: a generation number is parsed and then discarded, so `5 0 obj` and `5 1 obj`
  collide; an incremental update is resolved by file order rather than by what the newest trailer
  says, so a file whose update reinstates an earlier object resolves to the wrong one; a stream
  whose `/Length` is a forward indirect reference costs a fresh scan to end of file, which is
  quadratic on a file that writes them consistently; and `Reader.open` parses every object in the
  document and expands every object stream before the first page is asked for, so opening is
  linear in the file rather than in the page requested. The corpus does not show this — its largest
  fixture is 2.6 MB.
- Complete when: `startxref` is followed through the `/Prev` chain across both classic tables and
  cross-reference streams, an object is located by number *and* generation through that index,
  free entries are honoured, the full scan remains as the fallback for a file whose index is
  damaged, an object is parsed on first use rather than at open, and opening a large document
  costs the trailer chain rather than the file.
- Related: T-427, T-461

---

## Tier B — Pages that do not render what they mean

### T-431 — One unsupported construct loses the whole page

- Intent: `loadPage` fails as a unit. A single JBIG2 scan, one CCITT logo, or one CMYK photograph
  anywhere in a content stream costs the caller the entire page, including the text and vectors
  that decoded perfectly. For a viewer that is the difference between a page with a gap in it and
  a page that will not display. It also means every entry below this one is, today, a way to lose
  a page rather than a way to lose a mark.
- Complete when: a page decodes as far as it can, each construct it could not represent is
  recorded against the item that needed it with enough detail to name the feature, `Page` exposes
  those limitations to the caller, and a document-level failure is reserved for input that cannot
  be parsed at all.
- Note: the messages reach a user through sFileScope's failure reporting, so they are user-facing
  English and must read as such.
- Related: T-442, T-443, T-444, T-445

### T-432 — Annotation appearance streams are never drawn

- Intent: `/Annots` is not read. Links, form widgets, stamps, highlights, sticky notes, redaction
  marks and signature appearances all live in annotation appearance streams, and none of them
  reach the page. A commented or filled document renders as the blank form underneath it, with no
  indication that anything is missing.
- Complete when: the normal appearance stream of each annotation is drawn in annotation order
  after the page content, with its `/Rect` to `/BBox` mapping and `/Matrix` applied, hidden and
  no-view flags honoured, and annotations without an appearance stream skipped rather than
  synthesized.
- Note: draw appearances only. Never execute an `/AA`, an `/A` action, or embedded JavaScript.
- Related: T-448

### T-434 — Constant alpha and blend modes are ignored

- Intent: `applyExtGState` reads `/LW` and `/Font` and nothing else. `/ca` and `/CA` are dropped,
  so a watermark set at ten percent is painted opaque and covers the text it was meant to sit
  behind; `/BM` is dropped, so a multiply overlay replaces what it should darken.
- Complete when: fill and stroke constant alpha modulate the item's color through the graphics
  state stack, the separable blend modes the painter can express are honoured, and a blend mode it
  cannot express is recorded as a limitation rather than silently normalized.
- Related: T-431, T-437

### T-435 — Axial and radial shadings are not painted

- Intent: the `sh` operator falls through the content switch and paints nothing, and a shading
  pattern used as a fill paints nothing. Type 2 and type 3 shadings with sampled, exponential and
  stitching functions cover the overwhelming majority of gradients in real documents.
- Complete when: `sh` paints an axial or radial shading through the current clip, a shading
  pattern selected by `scn` fills a path with the same code, the `/Function` types needed by those
  two are evaluated, and the remaining shading types are reported per item.
- Related: T-436

### T-436 — Tiling patterns are not painted

- Intent: a type 1 pattern is a content stream tiled over a region — hatching in engineering
  drawings, texture fills in presentations. None of it is drawn.
- Complete when: a tiling pattern's cell is decoded once through the existing content parser,
  tiled over the filled region under the pattern matrix, and both paint types are handled, with
  the uncolored form taking its color from the `scn` operands.
- Related: T-435

### T-437 — A soft mask named by an ExtGState is ignored

- Intent: `/SMask` in an `ExtGState` establishes a luminosity or alpha mask from a transparency
  group and is how a soft-edged vignette, a feathered shadow, or a gradient-masked image is
  expressed. Image-level `/SMask` is handled; the graphics-state one is not read at all.
- Complete when: a luminosity or alpha soft mask is rendered from its group and applied to
  subsequent marks, and `/None` restores the unmasked state.
- Related: T-434

### T-438 — Optional content is always drawn

- Intent: `BDC`, `BMC` and `EMC` fall through the content switch and `/OC` on an XObject is not
  read, so every optional content group is painted whatever its default configuration says. A
  drawing exported with construction layers off shows them on, and a multi-language artwork shows
  every language at once.
- Complete when: the catalog's `/OCProperties` default configuration decides which groups are
  visible, marked-content sections and XObjects belonging to a hidden group are skipped, and the
  group list is exposed so a caller can override the configuration.

### T-439 — A clip is only ever its bounding box

- Intent: `applyPendingClip` reduces the clip path to `controlBounds()`, which for a bezier
  includes its control points. The module documents this as deliberately conservative, and it is —
  but a page that clips an image to a circle, a map to a country outline, or a chart to a wedge
  shows the corners the author removed, and the bezier hull makes even a rectangle-adjacent clip
  larger than it should be. `Painter` already has clipping regions with set operations, so the
  capability exists one layer down.
- Complete when: a non-rectangular clip path is carried to the painter as a region rather than a
  rectangle, nesting intersects regions, and the even-odd form of `W*` is distinguished from `W`.
- Related: T-440

### T-440 — Text render modes other than fill and invisible are drawn filled

- Intent: `Tr` is stored and then only consulted to detect the invisible modes 3 and 7. Mode 1
  paints outlined text, mode 2 fills and strokes it, and modes 4 through 7 add the run to the clip
  path — the standard way to fill text with an image or a gradient. All of them are drawn as a
  plain fill in the fill color, so outlined display type renders solid and image-filled text
  renders as flat letters.
- Complete when: an item carries its render mode, stroke and fill-and-stroke modes paint with the
  stroke color and width, and the clipping modes contribute the run's outline to the clip.
- Related: T-439

---

## Tier B — Fonts a page cannot draw

### T-441 — Type1 and bare CFF programs fall back to a substitute face

- Intent: `readFontProgram` reads `FontFile` and a bare `FontFile3` into the resource, and then
  `TypeFace.create` refuses both, so every document that embeds a Type1 or CFF program is drawn
  with a system face that is not the one it embedded. That covers most of what Adobe tools, TeX
  distributions and a large share of Google Fonts produce. The substitution path is good enough
  that this failure is invisible — the page is subtly not the document, and nothing reports it.
- Complete when: an embedded Type1 or CFF program produces the glyphs the file addresses, and
  `fontprogram.test.swg` shows the corpus reaching those glyphs rather than a substitute.
- Related: [T-068](todo.truetype.md#t-068--opentype-cff-outlines-are-rejected), which is where the
  charstring interpreter belongs; this entry is the PDF-side addressing that sits on top of it —
  name-keyed simple fonts, and CID-keyed CFF reached through its charset.

### T-442 — Type3 fonts are not decoded

- Intent: a Type3 font defines each glyph as a content stream under a `/FontMatrix`. Nothing here
  recognizes the subtype, so the run is handed to the substitute path, and its `/Widths` — which
  are in glyph space, not thousandths — are read as though they were normal metrics, so the text
  is both the wrong shape and the wrong size. Documents produced by older TeX toolchains and by
  drawing programs that embed bitmap fonts hit this.
- Complete when: a Type3 glyph is drawn by running its `CharProc` through the existing content
  parser under the font matrix and the text matrix, and its widths are interpreted in glyph space.

---

## Tier B — Images a page cannot decode

### T-443 — A CMYK or YCCK JPEG fails the whole page

- Intent: a `DCTDecode` stream is handed to `Image.decode(".jpg", …)`, whose frame initializer
  reports `unsupported color space` for any frame that is not one or three components. Print-ready
  documents routinely carry four-component photographs, and one of them fails the page. The
  `/Decode` array is also not applied on the DCT path, so the inverted samples Adobe writers
  produce would still be wrong once the frame decodes.
- Complete when: a four-component JPEG decodes — through `pixel` gaining CMYK and YCCK support,
  which is where the frame work belongs — the Adobe transform marker selects between them, the
  `/Decode` array is honoured for a DCT image as it is for a sampled one, and the corpus carries a
  CMYK fixture.
- Related: T-431

### T-444 — CCITT Group 3 and Group 4 images are refused

- Intent: `CCITTFaxDecode` is named as an image codec and then rejected. It is the codec of
  scanned bilevel documents, which is a large fraction of the PDFs that exist at all; a scanned
  contract or invoice cannot be displayed.
- Complete when: one and two dimensional Group 3 and Group 4 decoding is implemented over the
  `/DecodeParms` geometry, with `/BlackIs1`, byte alignment and damaged-row recovery.
- Related: T-431

### T-445 — JBIG2 images are refused

- Intent: `JBIG2Decode` is the modern successor to CCITT for scanned text, and is what recent
  scanner firmware and PDF optimizers emit.
- Complete when: the generic region and text region decoding procedures are implemented, including
  the embedded stream form with a shared `/JBIG2Globals` segment.
- Related: T-431, T-444

### T-446 — JPEG 2000 images are refused

- Intent: `JPXDecode` appears in print production and in some scanner output. It is the largest
  single decoder on this list and the rarest of the three, which is why it sits last.
- Complete when: the codestream form used by PDF decodes, or the codec is removed from the
  recognized set and reported as a first-class limitation instead of being half-recognized.
- Related: T-431

---

## Tier C — What a reader cannot say about a document

### T-447 — A page's text cannot be extracted in reading order

- Intent: `Item.textValue` returns one show-string at a time, in paint order, with no geometry
  beyond the item transform. There is no way to get a page's text as text, to find a string in it,
  or to know where a match sits on the page. For a file viewer, "find in document" is the first
  thing asked of a PDF after it displays, and the information needed to build it — per-code
  advances and the text matrix — is already retained on every item and then thrown away at the
  API boundary.
- Complete when: a page yields its text with words and lines assembled from the item geometry
  rather than from the order the writer emitted, a search returns the page-space rectangles of
  each match, and each character maps back to a position so a selection can be drawn.
- Related: T-448

### T-448 — Outline, destinations, and link targets are not read

- Intent: the catalog's `/Outlines`, its `/Names` destination tree and the `/Dest` or `/A` of a
  link annotation are never read, so a document has no navigable structure: no bookmarks pane, and
  a link that is drawn (once T-432 lands) still cannot be followed.
- Complete when: the outline is exposed as a tree of titles and targets, a named or explicit
  destination resolves to a page index and a page-space position, and a link annotation reports
  its target — an internal destination, a URI, or neither.
- Related: T-432, T-447

### T-449 — Page labels, dates, and XMP metadata are not read

- Intent: `Metadata` carries the six Info strings. `/CreationDate` and `/ModDate` are not read, the
  `/Metadata` XMP stream is not read, and `/PageLabels` is not read — so a document numbered
  `i, ii, iii, 1, 2` reports pages 1 through 5 and no viewer built on this can show the number the
  page itself carries.
- Complete when: the two dates are parsed from the PDF date form, the XMP packet is exposed as
  bytes with its common Dublin Core fields surfaced, and a page reports its label.

---

## Tier C — The writer

### T-450 — Text output cannot leave Windows-1252 and the fourteen standard faces

- Intent: `Page.addText` accepts UTF-8 and `windows1252` then fails the whole `save` on the first
  character outside that page. No font can be embedded. A document generator that cannot write
  Greek, Cyrillic, Hebrew, any CJK script, or an emoji is not a document generator — it is a Latin
  memo generator, and every writing library it competes with embeds fonts as a matter of course.
- Complete when: a TrueType or OpenType program can be embedded, subset to the glyphs used, with a
  Type0 composite font, an Identity-H encoding and a `/ToUnicode` map so the output stays
  searchable and copyable; the standard faces remain the default so a Latin document still carries
  no font program; and a character that cannot be represented is reported with enough context to
  name it.
- Related: T-451, T-452

### T-451 — Pages cannot be merged, split, or reordered without being redrawn

- Intent: `Document` can add and remove whole `Page` values, but a page loaded from a reader has
  been decoded into items and can only be written back through the writer — which re-encodes its
  text with a standard face, rasterizes nothing it cannot express, and loses everything in T-452.
  Merging two documents and splitting one are the two most common things anyone does to a PDF, and
  neither can be done here without degrading the pages. There is also no insert-at-index and no
  reorder.
- Complete when: a page can be copied from one document to another at the object level — its
  content streams, resources and font programs carried across unchanged and renumbered — a page
  can be inserted at a position and moved, and a merge of two files that this module can open
  produces pages byte-identical in content to their sources.
- Related: T-450, T-455

### T-452 — A decoded page loses its fill rule, its clips, and its intra-run positions

- Intent: the round trip is lossier than it looks. `appendPath` emits `f`, `B` and `S` and never
  their star forms, so a path decoded with the even-odd rule is written back with the winding rule
  and a ring drawn as two contours fills solid. An item's clip is decoded and then never written,
  so trimmed content reappears. And a text item is written as one `Tj` with the standard face's own
  metrics even though `textAdvances` holds the exact advance the document gave every code, so
  letters inside a run drift wherever the substitute's metrics differ.
- Complete when: the even-odd rule survives a decode-encode cycle, a clipped item is written back
  inside `q W n … Q`, a text run is written as a `TJ` array carrying the retained per-code
  advances, and a round-trip test compares rendered pages rather than only re-reading the model.
- Related: T-450, T-460

### T-453 — An image is always rewritten as a Flate raster

- Intent: `encodeImagePixels` reduces every image to eight-bit gray or RGB and Flate-compresses
  it. A page that came in as a two-megabyte JPEG photograph leaves as a fifty-megabyte raster, a
  bilevel scan leaves as eight bits per pixel, and a palette image loses its palette. The same
  image used on twenty pages is written twenty times.
- Complete when: an image whose source is already a JPEG is passed through as `DCTDecode`, a
  bilevel or small-palette image is written at its natural depth or through an indexed space, and
  an image written more than once shares one object.

### T-454 — Links, outline, and page labels cannot be written

- Intent: the writer emits a catalog, a page tree, an info dictionary, content, fonts and images.
  There is no way to write a link, a bookmark, a page label, or a document date, so a generated
  report cannot have a clickable table of contents — which is most of what a generated report is
  for.
- Complete when: a page can carry link annotations to a URI or to another page, a document can
  carry an outline tree and page labels, and `/CreationDate` and `/ModDate` are written.
- Related: T-448, T-449

### T-455 — The writer emits only a classic cross-reference table

- Intent: every object is written uncompressed with a classic `xref` table, so a document with
  many small objects is larger than it needs to be, and there is no way to save a change to an
  existing file except by rewriting it whole — which, per T-451, degrades every page it did not
  originate.
- Complete when: objects can be written into object streams behind a cross-reference stream, and a
  document opened from a file can be saved as an incremental update that appends rather than
  rewrites.
- Related: T-451

---

## Tier D — Cost

### T-456 — Typefaces built for a document are never released

- Intent: a render now resolves each font resource once through a per-render cache, but the key
  is still a CRC32 over the complete font program — one hash per font per render, where one per
  document would do — and the typefaces registered in the process-wide `TypeFace` table are never
  released, so the table grows for the process lifetime as documents are opened and closed.
- Complete when: a font program is hashed at most once per open document, and the typefaces a
  document created are released with it.
- Related: T-457, T-458

### T-457 — Each render rebuilds its renderer and re-uploads its textures

- Intent: `PdfView` now keeps the decoded page across zoom and pan steps and rasterizes only the
  visible region past a pixel budget, but every `renderPage` call still builds a fresh
  `RenderCpu`, initializes it, and uploads the textures of the in-region images again. On an
  image-heavy page each zoom step re-uploads the same pixels; nothing carries over from one
  render of the same `Page` to the next.
- Complete when: consecutive renders of one page share a render context and the textures of
  unchanged images, and a zoom step on an image-heavy corpus page measurably stops re-paying the
  uploads.
- Related: T-428, T-456, T-459

### T-458 — An embedded font program is copied once per page that uses it

- Intent: `decodeFontResource` copies the decompressed font program into every page's
  `FontResource`. A hundred-page thesis with a four-hundred-kilobyte embedded family carries forty
  megabytes of duplicated font bytes when loaded as a `Document`, and the same duplication is paid
  again for every form XObject that names its own resources.
- Complete when: a decoded font program is shared between the pages that reference the same font
  object, and a `Document` load of the corpus costs one copy per distinct program.

### T-459 — A render cannot be cancelled or bounded in time

- Intent: `RenderOptions` bounds the output dimensions and pixel count and nothing else. A page
  with a pathological number of paths can take arbitrarily long, and the caller — a GUI thread in
  the only consumer that exists — has no way to abandon it when the user turns the page.
- Complete when: a render accepts a cancellation signal and an optional work budget, and reports
  an interrupted render distinctly from a failed one.
- Related: T-457

---

## Tier E — Proof

### T-460 — No rendered page is compared against a golden

- Intent: `corpus.test.swg` renders 354 pages and asserts `image.isValid()`. That catches a crash
  and a hard failure and nothing else: every entry in Tier B above would pass it today, and so
  would a regression that painted a page entirely black. The repository already has command-stream
  visual regression goldens in `pixel` and `gui`; this module has none.
- Complete when: a representative page from each corpus family has a golden, the fixtures that
  exercise text, images, strokes and forms compare rendered output rather than model fields, and a
  round trip through the writer is judged on its rendered result.
- Related: T-452

### T-461 — The corpus has no malformed, hostile, or large document

- Intent: every fixture is a well-formed file under three megabytes produced by a working writer.
  Nothing exercises a truncated stream, a cyclic page tree, a lying `/Length`, an object that
  claims a billion entries, or a hundred-megabyte scan — and the parser has no overall memory or
  node budget to catch one, only the local depth limits it already carries.
- Complete when: a malformed corpus covers truncation, cycles, contradictory lengths and
  declared-size attacks with the expected error for each, a large fixture makes the open cost of
  T-428 measurable, and the parser refuses to allocate past a stated budget.
- Related: T-428

---

## Out of scope

**Executing anything the document carries.** Actions, additional actions, embedded JavaScript, and
launch or submit behaviour are read as data at most, and never run. This is a permanent boundary,
not a gap.

**Encryption authoring.** T-427 decrypts what a reader must open. Writing an encrypted document,
and anything that would strip or weaken a permission a file declares, stays out.

**Interactive form filling.** Drawing a form widget's appearance is T-432; a field model with
values, validation, calculation order and appearance regeneration is a separate product and no
consumer needs it.

**Digital signature creation and validation.** Both need a certificate and trust story this
repository does not have.

**PDF/A, PDF/UA and tagged output.** Conformance is a claim about a whole pipeline, not a writer
feature, and claiming it without validation would be worse than not claiming it. Revisit only if
a consumer needs the claim.
