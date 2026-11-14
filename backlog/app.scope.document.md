# Swag Scope Document Viewer Backlog

This backlog covers Swag Scope's Markdown, HTML, PDF, Office Open XML, and ebook reading surfaces.
Parser, layout, and renderer defects remain with their engines in [std.gui.markdown.md](std.gui.markdown.md),
[std.gui.html.md](std.gui.html.md), and [std.gui.pdf.md](std.gui.pdf.md); entries here own navigation, inspection, and application
integration around those engines.

### app.scope.document.024 — RTF reading omits advanced layout and encoded text variants

- Evidence: the Swag RTF reader now displays paragraphs, common inline styles, alignment, simple
  tables, Unicode escapes and Windows-1252 text. It names omitted images and embedded objects.
  It does not reproduce fonts, colors, page geometry, complex tables, fields or other code pages.
- Next: add a bounded font/color and paragraph model, supported code-page decoders, image extraction
  and a richer table layout without executing fields or loading linked resources.
- Done when: representative freely licensed RTF documents retain their reading order and common
  visual structure, unsupported content remains explicit, and all decoding remains native Swag.

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
  through `DocumentOutline.bindHtml`; it does not expose those document facts or warnings. An
  unstyled HTML page opened during the outline test starts at the left edge, where an optional
  reading layout could supply a comfortable measure without changing faithful rendering.
- Next: surface document metadata and engine diagnostics first, then derive a clearly labelled
  reader view from semantic blocks without replacing faithful mode.
- Done when: title, language, metadata, headings, landmarks, and warnings are inspectable;
  reader mode preserves links and text order; and switching modes retains the logical location.
- Related: std.gui.html.017

### app.scope.document.023 — Keep an HTML reading inset beside its outline

- Evidence: `viewer.html.filtered-outline.paper` shows the article starting at the window's left edge when the outline takes the right side. The headings and body text have no breathing room at that edge.
- Next: define a reading inset for the hosted HTML page while the side panel is visible, without changing the document's own CSS layout or clipping its content.
- Done when the full-window HTML golden keeps a readable gap beside the window edge at a narrow width and still preserves authored page margins.

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

### app.scope.document.020 — DOCX lacks faithful page reading

- Evidence: the DOCX reader shows ordered body paragraphs, simple tables, direct run formatting,
  headings, page-break separators and bounded raster images. It loses page size and margins,
  section columns, styles and themes, headers and footers, footnotes, comments, floating objects,
  and complex table geometry. [Word Read Mode](https://support.microsoft.com/en-gb/word/read-documents-in-word)
  preserves navigable pages and adapts them to the reading surface.
- Next: resolve styles and relationships before laying out page and section geometry; compare
  representative real producer documents page by page, then add document-wide search, selection,
  and position restore without materializing every page at open.
- Done when: authored pages, text flow, images and table structure remain recognizable across a
  freely licensed DOCX corpus, unsupported constructs are named at their location, and the first
  page appears without decoding the full package.
- Related: app.scope.binary.010

### app.scope.document.025 — XLSX lacks a true workbook reading surface

- Evidence: the XLSX reader orders sheets and shows values or uncached formula expressions in a
  512-column grid, but drops widths, heights, number formats, styles, merged cells, hidden ranges,
  frozen panes, filters, comments and charts. [Excel's frozen panes](https://support.microsoft.com/en-gb/excel/get-started/freeze-panes-to-lock-rows-and-columns)
  illustrate why authored grid navigation matters to reading.
- Next: preserve workbook view state and resolve styles, dimensions, merges and number formats;
  add virtual cell addressing, sheet-wide search and selection before read-only chart previews.
- Done when: real workbooks show their authored grid and formatted values, frozen and hidden regions
  behave as declared, formulas never execute, large sheets stay bounded, and every omitted construct
  is explicitly reported.
- Related: app.scope.text.015, app.scope.text.017

### app.scope.document.026 — PPTX lacks slide geometry and presentation reading

- Evidence: the PPTX reader shows ordered slide text, embedded raster images and some direct text
  styling, but flattens object placement, themes, masters, shapes and backgrounds. It also omits
  speaker notes and a slide overview. [PowerPoint Reading and Slide Show views](https://support.microsoft.com/en-us/powerpoint/how-certain-features-behave-in-web-based-powerpoint)
  retain slide navigation and notes.
- Next: resolve slide masters and relationships into bounded slide canvases with shapes, pictures
  and text placement; then add thumbnails, notes and a full-screen reading path. Declare a safe
  policy for animation, embedded media and external links.
- Done when: a real presentation is recognizable slide by slide at authored aspect ratio, notes
  and navigation remain available, unsupported effects are explicit, and slide 1 appears without
  decoding every slide.
- Related: app.scope.binary.010

### app.scope.document.021 — EPUB chapter reading needs complete navigation

- Evidence: `.epub` now reads `META-INF/container.xml`, the OPF manifest and spine, and opens
  each XHTML document through the HTML reader in declared order. ZIP extraction is bounded and
  rejects escaping paths. The first fixtures cover spine ordering and a nested package root.
  There is no EPUB table of contents, book-wide search or position restore, and extraction prepares
  every package member before the first chapter is shown.
- Next: expose EPUB 2 NCX and EPUB 3 navigation/landmarks, resolve chapter fragments and local
  footnotes, add book-wide search with chapter/all-book scope and stable chapter positions,
  explicit bookmarks and link back/forward, then lazily extract resources needed for the visible chapter.
- Done when: TOC, previous/next, links, footnotes, search, bookmarks, history and position restore work across a
  representative EPUB 2/3 corpus without delaying first content for the whole package.
- Related: app.scope.binary.010

### app.scope.document.027 — CBZ has page turns but no complete comic reading modes

- Evidence: `Viewers.Comic` lists image members in natural filename order and opens one page through
  `EmbeddedViewer`; the controls only offer previous and next. A dedicated reader such as
  [OpenComic](https://github.com/ollm/OpenComic) offers right-to-left manga, double-page spreads,
  continuous webtoon scroll, bookmarks and reading-position restore.
- Next: add a bounded page index with thumbnails and stable positions, then single/spread/continuous
  layouts, right-to-left order, cover alignment and per-page fit/zoom. Read safe `ComicInfo.xml`
  metadata when present without treating it as an image page.
- Done when: natural order, nested folders, spreads, manga direction, tall pages and damaged
  members remain readable and navigable across real CBZ books; page changes never require
  extracting all images first, and unsupported image pages are named in place.
- Related: app.scope.image.005, app.scope.viewers.003

### app.scope.document.028 — EPUB has no adjustable book-reading layout

- Evidence: each spine document is currently shown as one HTML chapter, with no book-level paged
  layout, continuous flow choice, reading width, type scale, line spacing or margin policy.
  [calibre's viewer](https://manual.calibre-ebook.com/viewer.html) supports paged and flow modes.
- Next: add book-owned paged and continuous modes over the existing HTML layout, preserve a logical
  location while typography or viewport size changes, and keep navigation and search mapped to
  that location.
- Done when: readers can choose fit-to-width flow or pages, adjust typography without corrupting
  authored content, and reopen at the same logical passage across window and theme changes.
- Related: app.scope.document.021, app.scope.viewers.003

### app.scope.document.029 — Reading marks and notes have no document-independent home

- Evidence: PDF, EPUB, Markdown, HTML and Office readers have selection or location models but
  no read-only-source highlight and note store. [Okular](https://docs.kde.org/stable_kf6/en/okular/okular/annotations.html)
  annotates many document formats; [calibre](https://manual.calibre-ebook.com/viewer.html)
  groups book highlights by chapter. Writing marks into every input format would create a separate
  editing and compatibility contract.
- Next: define stable location anchors and a versioned local sidecar store for highlights, notes
  and named bookmarks, starting with EPUB and PDF; expose source change/conflict status.
- Done when: marks survive reopen and layout changes across supported readers, navigate back to
  the intended content, can be exported, and never silently alter an original document.
- Related: app.scope.document.021, app.scope.viewers.003

### app.scope.document.030 — Text documents have no read-aloud path

- Evidence: [Okular](https://docs.kde.org/stable_kf6/en/okular/okular/menutools.html),
  [Acrobat Reader](https://helpx.adobe.com/uk/acrobat/using/reading-pdfs-reflow-accessibility-features.html)
  and [calibre](https://manual.calibre-ebook.com/viewer.html) can speak document text. Swag Scope
  exposes no such action or spoken-position cue across its text-bearing viewers.
- Next: establish one reading-order and sentence-position contract, first for EPUB and tagged PDF;
  choose a built-in Swag speech path or an operating-system facility already present on the host,
  without a downloaded voice, helper executable or viewer dependency.
- Done when: supported documents can speak current selection or continue from the reading position,
  highlight the spoken passage, pause and resume, and clearly report when the host has no voice;
  opening and visual reading never depend on speech availability.
- Related: app.scope.document.021, std.gui.pdf.042, app.scope.viewers.014

### app.scope.document.031 — PDF inspection has no region and table selection tools

- Evidence: the PDF view supports text selection, search and copy, while
  [Okular's PDF tools](https://docs.kde.org/stable_kf6/en/okular/okular/menutools.html)
  include area copy, table selection and a temporary magnifier. The current selection model
  cannot preserve a rectangular image crop or a reconstructed table with provenance.
- Next: add a bounded page-region selection and magnifier using the existing page transforms;
  then extract text cells from selected rows and columns with an explicit ambiguous-layout report.
- Done when: a user can copy a page region as an image and a well-formed table as delimited text,
  navigate the selected source bounds, and see when the table structure cannot be inferred.
- Related: std.gui.pdf.039, app.scope.document.019

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
