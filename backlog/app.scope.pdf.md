# Swag Scope PDF Viewer Backlog

Application integration for PDF reading and inspection. Parser, layout, and renderer work
lives in [std.gui.pdf.md](std.gui.pdf.md).

### app.scope.pdf.003 — PDF page links do not join the back/forward history

- Evidence: bookmark, margin and typed-page jumps record their place in `Viewer.History` and
  Alt+arrows or the lens restore its page point and zoom. Page-link annotations are not exposed
  by the engine (std.gui.pdf.017), so a link inside a page cannot be followed or returned from,
  and a search reveal is not recorded as a jump.
- Next: when the engine exposes link annotations, route supported page links through
  `PdfDocument.Panel.showBookmark`'s navigation contract and name an unresolved target in place.
- Done when: supported local links share the bookmark history behavior while invalid targets
  remain visible.
- Related: std.gui.pdf.017

### app.scope.pdf.005 — Image-only PDF pages are named only when a search finds nothing

- Evidence: once the document's text has been extracted for search, `PdfView.textCoverage`
  counts pages with no text and pages whose text failed to decode, and a search that found
  nothing says so beside its `0/0`. The information sheet starts that extraction itself
  (`PdfView.extractText`) and, once `PdfView.sigTextExtracted` reports it done, says whether the
  pages carry text: on every page, none, or missing on how many, then how many could not be read.
  A search that finds words in a partly scanned document says, in the tooltip of its count, how
  many pages were not searched (`Viewer.ExplainSearch`); the count itself carries no mark.
  [File Viewer Plus 7](https://fileviewerplus.com/whats_new) can recognize text in scanned pages
  and save a searchable PDF.
- Next: mark the count when pages could not be searched and test it with a mixed text and
  scanned PDF. Use those same fixtures to establish the OCR coverage needed in a later pass.
- Done when: a reader can tell, without searching, that a document or some of its pages have no
  text layer, and a found count over such a document says which pages it could not cover.
- Related: std.gui.pdf.040, std.gui.pdf.041, std.gui.pdf.042

### app.scope.pdf.001 — A PDF the module cannot fully decode is shown as a failure, not as a page

- Evidence: `PdfDocument.Panel` forwards any load or render failure to `services.failed`, so one
  unsupported construct reads as a broken file rather than as a page with a gap. Engine coverage
  gaps live in [std.gui.pdf.md](std.gui.pdf.md).
- Next: once std.gui.pdf.002 lets `loadPage` return a partial page with limitation records, draw
  the decoded part and show each limitation as localized text beside the page instead of failing
  the viewer; never execute an embedded action or offer form filling.
- Done when: the viewer draws the part of a page that decoded, states the construct it could
  not represent in localized text beside it rather than as a raw module error, and keeps page
  navigation working across a page it could only partly decode.
- Related: std.gui.pdf.002

### app.scope.pdf.009 — PDF inspection has no region and table selection tools

- Evidence: the PDF view supports text selection, search and copy, while
  [Okular's PDF tools](https://docs.kde.org/stable_kf6/en/okular/okular/menutools.html)
  include area copy, table selection and a temporary magnifier. The current selection model
  cannot preserve a rectangular image crop or a reconstructed table with provenance.
- Next: add a bounded page-region selection and magnifier using the existing page transforms;
  then extract text cells from selected rows and columns with an explicit ambiguous-layout report.
- Done when: a user can copy a page region as an image and a well-formed table as delimited text,
  navigate the selected source bounds, and see when the table structure cannot be inferred.
- Related: std.gui.pdf.039, app.scope.pdf.008

### app.scope.pdf.002 — PDF page navigation has no thumbnails

- Evidence: the information group provides previous/next and a clickable readout that names the
  page by the label the document gives it (`/PageLabels`) beside its position, and the page dialog
  accepts a position or a label. There is no thumbnail strip or overview suitable for a long
  document. [File Viewer Plus 7](https://fileviewerplus.com/support/pdf_files) documents four
  PDF viewing modes.
- Next: render cancellable low-resolution thumbnails through a bounded cache, starting near
  the current page and reusing the PDF renderer.
- Done when: thumbnails prioritize the visible neighborhood, the current page is selected, and
  thousand-page documents stay responsive.
- Related: std.gui.pdf.018

### app.scope.pdf.004 — PDF pages cannot be rotated or viewed with box and geometry overlays

- Evidence: the viewer has no clockwise/counter-clockwise rotation, crop/media/bleed box display,
  page-size readout, coordinate probe, or temporary crop-to-content view.
- Next: add non-destructive per-document rotation and an optional page-geometry overlay backed by
  exact PDF page dictionaries.
- Done when: rotation affects rendering, search bounds, selection, thumbnails, and print
  consistently; page boxes and dimensions are inspectable; and no command rewrites the PDF.

### app.scope.pdf.006 — PDF annotations, attachments, forms, layers, and signatures are hidden

- Evidence: engine tasks cover annotation appearance (std.gui.pdf.003) and optional content (std.gui.pdf.008), but the
  viewer has no read-only inventory for annotations, embedded files, AcroForm fields, layers,
  digital signatures, JavaScript actions, or security permissions.
- Next: define a safe document-components panel and add sections as the parser exposes each object
  family, beginning with annotations and attachments without executing actions.
- Done when: components link to page bounds or objects, attachment extraction is explicit and
  sanitized, signatures report cryptographic status and limits, layers can be toggled temporarily,
  form values are inspectable, and active content never runs.
- Related: std.gui.pdf.003, std.gui.pdf.008

### app.scope.pdf.007 — Password-protected PDFs have no application interaction

- Evidence: std.gui.pdf.001 records that encrypted documents are refused, and the viewer result can only
  return a terminal failure string. There is no secure password prompt, retry policy, permissions
  summary, or credential lifetime decision.
- Next: extend progressive viewer opening with a credential request that never persists or logs the
  password, then connect it to the engine work from std.gui.pdf.001.
- Done when: empty and entered passwords can unlock supported encryption, cancellation returns
  to a stable viewer state, retry is bounded, permissions are shown, and secrets leave memory when
  the document closes.
- Related: std.gui.pdf.001

### app.scope.pdf.008 — PDF pages and embedded assets cannot be exported for inspection

- Evidence: Swag Scope can render pages but offers no copy-page-image, save selected pages as
  images, extract an embedded image/font/attachment, or export selected text with provenance.
  [File Viewer Plus 7](https://fileviewerplus.com/support/pdf_files) exports page ranges and
  offers a DPI choice for PNG and JPEG output.
- Next: start with copy or export of a selected page range at a chosen DPI. Retain the page
  origin and share the range selection with printing, then add raw extraction of embedded assets.
- Done when: current or selected pages can be copied/rendered at chosen DPI, supported embedded
  assets can be saved without silent conversion, filenames are sanitized, and unsupported or
  lossy extraction is explained.
- Related: app.scope.viewers.002
