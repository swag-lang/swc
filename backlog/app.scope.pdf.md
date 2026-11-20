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
  cannot preserve a rectangular image crop or a reconstructed table with provenance. Current-page
  and page-range PNG export now work at a chosen DPI; selected-text export with source provenance
  remains absent.
- Next: add a bounded page-region selection and magnifier using the existing page transforms;
  then export selected text and table cells with exact page/source bounds and an explicit
  ambiguous-layout report.
- Done when: a user can copy a page region as an image and a well-formed table as delimited text,
  navigate the selected source bounds, and see when the table structure cannot be inferred.
- Related: std.gui.pdf.039

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
  digital signatures, JavaScript actions, or security permissions. The viewer can export rendered
  page ranges, but cannot list or extract raw embedded images, fonts, or attachments.
- Next: define a safe document-components panel and add sections as the parser exposes each object
  family, beginning with annotations and attachments without executing actions.
- Done when: components link to page bounds or objects, attachment extraction is explicit and
  sanitized, embedded assets retain source provenance without silent conversion, signatures report
  cryptographic status and limits, layers can be toggled temporarily, form values are inspectable,
  and active content never runs.
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
