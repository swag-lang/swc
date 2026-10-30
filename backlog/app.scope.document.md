# Swag Scope Document Viewer Backlog

This backlog covers Swag Scope's Markdown, HTML, PDF, office-document, and ebook reading surfaces.
Parser, layout, and renderer defects remain with their engines in [std.gui.markdown.md](std.gui.markdown.md),
[std.gui.html.md](std.gui.html.md), and [std.gui.pdf.md](std.gui.pdf.md); entries here own navigation, inspection, and application
integration around those engines.

### app.scope.document.001 — The full Markdown outline lacks reading-position tracking and history

- Evidence: `DocumentOutline` lists Markdown headings with depth and distinct source offsets
  and reveals them through `Markdown.View.revealHeading`. Filtering and keyboard navigation use
  source offsets. The full outline still keeps the last chosen row rather than following reading
  position; it has no breadcrumb path or navigation history, and its worker reads the complete
  source.
- Next: build a bounded heading index and synchronize the full outline with the document's
  current block; retain source offsets as identity and add bounded back/forward history.
- Done when: the visible section updates the full outline's selected heading/breadcrumb,
  and back/forward restores a reading location without retaining the whole source.
- Related: std.gui.markdown.005, app.scope.viewers.003

### app.scope.document.013 — The PDF bookmark panel has no filtering or navigation history

- Evidence: `PdfDocument.Panel` fills the shared `DocumentOutline` from `Pdf.Reader.loadOutline`
  and navigates through `PdfView.showPosition`. The panel has no filtering or back/forward
  state, and page-link annotations are not exposed by the engine (std.gui.pdf.017).
- Next: add filtering and a bounded page/position/zoom history to the existing bookmark panel,
  then route supported page links through the same navigation contract when the engine exposes them.
- Done when: bookmark filtering preserves hierarchy, back/forward restores page coordinates
  and zoom, and supported local links share the same behavior while invalid targets remain visible.
- Related: std.gui.pdf.017

### app.scope.document.010 — HTML has no reader-mode or page-level diagnostics

- Evidence: a professional local-page viewer needs both faithful layout and a way to understand an
  unreadable page. There is no extracted reading view, title/language/description summary,
  standards quirks indicator, or list of layout/parser warnings. A heading outline already ships
  through `DocumentOutline.bindHtml`; it does not expose those document facts or warnings.
- Next: surface document metadata and engine diagnostics first, then derive a clearly labelled
  reader view from semantic blocks without replacing faithful mode.
- Done when: title, language, metadata, headings, landmarks, and warnings are inspectable;
  reader mode preserves links and text order; and switching modes retains the logical location.
- Related: std.gui.html.017

### app.scope.document.016 — Image-only PDF pages do not explain why text search finds nothing

- Evidence: the PDF adapter forwards document search into `PdfView`, but its information surface
  does not distinguish a decoded page with no text from a page whose text has not been loaded.
  An image-only page gives no explanation that optical character recognition is unavailable.
- Next: expose the decoded page's text availability through the existing information surface,
  distinguishing loading, absent text, and unavailable decoding without scanning the whole file.
- Done when: searching an image-only page explains that OCR is absent, text-backed scans stay
  searchable, and a pending or failed page is not mislabeled as having no text.
- Related: std.gui.pdf.040, std.gui.pdf.041, std.gui.pdf.042

### app.scope.document.003 — Markdown links and resources have no trust or diagnostics surface

- Evidence: links activate and Markdown renders local raster and SVG images and embedded raster
  images, but the viewer does not list local and remote targets, broken anchors, missing images,
  blocked schemes, or resources outside the document directory. Embedded HTML shares the offline
  resource policy; the viewer does not expose each resource's resolution or the reason it was blocked.
- Next: inventory every parsed target and classify resolution, availability, scheme, and trust
  without fetching remote content implicitly.
- Done when: a resource panel links each target to source and rendered content, broken local
  references are explained, remote access requires explicit policy, and blocked content remains
  visible as a diagnostic.

### app.scope.document.002 — Markdown has no synchronized source and rendered split view

- Evidence: `.md` and `.markdown` now offer Markdown, Basic text, Binary, and Hexadecimal, so the
  source is reachable as its own view. There is still no synchronized split view and no mapping
  from a rendered block to its source range.
- Next: retain parser source ranges in the adapter and host rendered/source panes with a shared
  logical position.
- Done when: Rendered, Source, and Split modes preserve the nearest block, scroll can
  synchronize in either direction, search results map across modes, and large files stay streamed.
- Related: std.gui.markdown.005

### app.scope.document.005 — HTML encoding decisions have no inspection or override controls

- Evidence: `HtmlView.detectDocumentEncoding` honors a BOM, scans early charset labels, and falls
  back to `Text.detectEncoding`, but the viewer exposes no detected encoding, decision source,
  manual override, or byte mapping for decoding failures.
- Next: expose the detected encoding and its provenance, then add an override using the text
  viewer's supported encoding choices and explicit restart behavior.
- Done when: the reader can inspect the chosen encoding, late or conflicting declarations
  warn, invalid bytes remain traceable, and an override re-renders safely.
- Related: app.scope.text.004

### app.scope.document.007 — HTML source and rendered views have no shared position or split layout

- Evidence: choosing Code or Basic text discards the rendered position, active link, search match,
  and DOM node. There is no formatted source, line address, or live element mapping.
- Next: compose rendered, source, and split modes over the DOM/source ranges introduced by app.scope.document.006.
- Done when: the selected element and scroll position map both ways, source retains exact bytes
  or declares normalization, search can target source or visible text, and scripts never execute.
- Related: app.scope.document.006

### app.scope.document.009 — HTML navigation has no history, address model, or fragment overview

- Evidence: `HtmlView` already follows same-document fragments and supported relative local HTML
  links, including a fragment in the destination. Other targets reach `sigLinkActivated`, which
  Swag Scope forwards to `Env.openUrl`. The application has no document address model,
  back/forward stack, visited state or broken-target overview around those engine operations.
- Next: expose local navigation transitions to the host and retain document, fragment, selection
  and scroll state in a navigation stack; distinguish external and blocked targets in its UI.
- Done when: back/forward restores scroll and selection, fragments and relative links resolve
  against the correct base, broken targets explain themselves, and external activation requires a
  deliberate command.

### app.scope.document.011 — A PDF the module cannot fully decode is shown as a failure, not as a page

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

### app.scope.document.022 — Jupyter notebooks have no document reader

- Evidence: `.ipynb` has no notebook renderer. The content probe offers the Text viewer for its
  raw JSON, alongside Binary and Hexadecimal. Markdown cells, code cells, execution order,
  attachments, stored images, tables, errors, and metadata lose their document structure. The
  intended reader presents stored content with cell/output search and an outline; kernel
  execution remains outside its contract.
- Next: parse notebook cells and render Markdown, syntax-colored source, plain text, bounded images,
  tables, and JSON output through existing viewers while defining a deny-by-default MIME and trust
  policy for HTML, SVG, JavaScript, widgets, and external resources.
- Done when: cell order, type, execution count, metadata, attachments, errors, and every stored
  output remain inspectable; outline and search address inputs and outputs separately; unsupported or
  suppressed rich output is named and available as source; large output is collapsed and bounded;
  and opening a notebook never starts a kernel, executes code, or fetches a resource.
- Related: app.scope.document.003, app.scope.text.024, app.scope.viewers.011

### app.scope.document.020 — Office Open XML files stop at the ZIP structure

- Evidence: `.docx`, `.xlsx`, and `.pptx` are selected only by the Archive and Binary viewers,
  so they still show a list of parts, as OpenDocument files do since their partial reader was
  withdrawn (app.scope.opendocument.023).
- Next: identify the shared document structure that can read paragraphs, headings, lists, tables,
  and spreadsheet cells for both office families, so the complete OpenDocument reader and this one
  do not grow two compatibility layers.
- Done when: Office Open XML documents open through readable document and table surfaces rather
  than only their ZIP hierarchy.
- Related: app.scope.text.015, app.scope.binary.010

### app.scope.document.021 — EPUB stops at the ZIP structure

- Evidence: `.epub` opens only in the Archive and Binary viewers, although an EPUB is a spine
  of XHTML documents that `HtmlView` already renders.
- Next: read `META-INF/container.xml` and the OPF manifest and spine through the shared ZIP
  reader, then feed the spine documents in order to the HTML view.
- Done when: the spine order is read from the container manifest and its documents stream into
  the reading column in order.
- Related: app.scope.binary.010

### app.scope.document.004 — Markdown reading position and presentation cannot be shared or exported

- Evidence: a reader cannot copy a stable link to a heading, export the rendered document, or save
  the active theme/measure as a self-contained reading artifact. Reopening also loses position.
- Next: define stable heading/block locators and a read-only export contract for HTML and paginated
  output after the shared print path exists.
- Done when: a logical reading position restores through app.scope.viewers.003, heading links can be copied,
  self-contained HTML preserves safe local assets, and paginated output uses app.scope.viewers.002.
- Related: app.scope.viewers.003, app.scope.viewers.002

### app.scope.document.006 — HTML has no DOM outline or element-to-page inspection

- Evidence: `HtmlView` is hosted as one rendered surface. A reader cannot browse element hierarchy,
  inspect tag/id/class/attributes, or select an element and see its box and source range.
- Next: expose a read-only DOM adapter with stable node identity and bidirectional selection between
  a virtual tree, source, and rendered box.
- Done when: nodes can be filtered, collapsed, copied, and revealed; generated boxes identify
  their source node; malformed recovery is explicit; and huge repetitive DOMs remain virtualized.

### app.scope.document.008 — HTML resource loading and blocking are invisible

- Evidence: local pages may reference stylesheets, images, fonts, frames, media, data URLs, and
  remote URLs, but the viewer has no resource list, status, size, origin, cache, or reason a resource
  was not rendered.
- Next: route all resource resolution through an observable offline-first request ledger with
  explicit budgets and policy decisions.
- Done when: every requested resource shows resolved path/origin, type, bytes, result, and
  blocker; remote fetch is opt-in; traversal outside allowed roots is prevented; and entries link
  to the requesting node.
- Related: std.gui.html.019

### app.scope.document.012 — PDF page navigation has no thumbnails or page-label lookup

- Evidence: the information group provides previous/next and a clickable `current / total`
  readout with validated numeric page entry. There is no thumbnail strip, page-label lookup, or
  overview suitable for a long document.
- Next: render cancellable low-resolution thumbnails through a bounded cache and extend the page
  address control with PDF page labels.
- Done when: thumbnails prioritize the visible neighborhood, direct numeric and page-label
  jumps validate input, the current page is selected, and thousand-page documents stay responsive.
- Related: std.gui.pdf.018

### app.scope.document.015 — PDF pages cannot be rotated or viewed with box and geometry overlays

- Evidence: the viewer has no clockwise/counter-clockwise rotation, crop/media/bleed box display,
  page-size readout, coordinate probe, or temporary crop-to-content view.
- Next: add non-destructive per-document rotation and an optional page-geometry overlay backed by
  exact PDF page dictionaries.
- Done when: rotation affects rendering, search bounds, selection, thumbnails, and print
  consistently; page boxes and dimensions are inspectable; and no command rewrites the PDF.

### app.scope.document.017 — PDF annotations, attachments, forms, layers, and signatures are hidden

- Evidence: engine tasks cover annotation appearance (std.gui.pdf.003) and optional content (std.gui.pdf.008), but the
  viewer has no read-only inventory for annotations, embedded files, AcroForm fields, layers,
  digital signatures, JavaScript actions, or security permissions.
- Next: define a safe document-components panel and add sections as the parser exposes each object
  family, beginning with annotations and attachments without executing actions.
- Done when: components link to page bounds or objects, attachment extraction is explicit and
  sanitized, signatures report cryptographic status and limits, layers can be toggled temporarily,
  form values are inspectable, and active content never runs.
- Related: std.gui.pdf.003, std.gui.pdf.008

### app.scope.document.018 — Password-protected PDFs have no application interaction

- Evidence: std.gui.pdf.001 records that encrypted documents are refused, and the viewer result can only
  return a terminal failure string. There is no secure password prompt, retry policy, permissions
  summary, or credential lifetime decision.
- Next: extend progressive viewer opening with a credential request that never persists or logs the
  password, then connect it to the engine work from std.gui.pdf.001.
- Done when: empty and entered passwords can unlock supported encryption, cancellation returns
  to a stable viewer state, retry is bounded, permissions are shown, and secrets leave memory when
  the document closes.
- Related: std.gui.pdf.001

### app.scope.document.019 — PDF pages and embedded assets cannot be exported for inspection

- Evidence: Swag Scope can render pages but offers no copy-page-image, save selected pages as
  images, extract an embedded image/font/attachment, or export selected text with provenance.
- Next: define read-only extraction commands with exact object/page origin and explicit raw versus
  rendered output.
- Done when: current or selected pages can be copied/rendered at chosen DPI, supported embedded
  assets can be saved without silent conversion, filenames are sanitized, and unsupported or
  lossy extraction is explained.
