# Swag Scope Document Viewer Backlog

This backlog covers Swag Scope's Markdown, HTML, PDF, Office Open XML, and ebook reading surfaces.
Parser, layout, and renderer defects remain with their engines in [std.gui.markdown.md](std.gui.markdown.md),
[std.gui.html.md](std.gui.html.md), and [std.gui.pdf.md](std.gui.pdf.md); entries here own navigation, inspection, and application
integration around those engines.

### app.scope.document.024 — RTF reading omits advanced layout and encoded text variants

- Evidence: the Swag RTF reader now displays paragraphs, common inline styles, alignment, simple
  tables, Unicode escapes and Windows-1252 text. Bounded embedded PNG and JPEG pictures retain
  their place in the prose; binary payloads and modern/compatibility picture pairs are handled
  without duplicate images. Bounded font/color tables now preserve character faces, half-point
  sizes, colors, highlights, paragraph spacing/indents and line spacing; group scopes and plain
  resets retain their meaning. Colored prose uses a paper background with reading margins.
  Unsupported style references, pictures and embedded objects remain explicit. Named RTF styles,
  page geometry, complex tables, fields and other code pages are still absent.
- Next: resolve named paragraph/character styles, add supported code-page decoders and richer
  table layout without executing fields or loading linked resources.
- Done when: representative freely licensed RTF documents retain their reading order and common
  visual structure, unsupported content remains explicit, and all decoding remains native Swag.

### app.scope.document.001 — The full Markdown outline reads the whole source and has no breadcrumb

- Evidence: `DocumentOutline` lists Markdown headings with depth and source offsets, marks the
  heading being read from the reader's first move on, and keeps the mark through its filter. Choosing a
  heading records the place left in `Viewer.History`; Alt+arrows and the lens return through
  `Markdown.View.revealBlock`. The outline worker still reads the complete source, a rendered
  link is not a recorded jump, and no breadcrumb names the enclosing sections.
- Next: build a bounded heading index instead of reading the whole file, then show the path of
  enclosing headings for the marked one.
- Done when: the outline of a very large document appears without retaining its whole source,
  and the visible section's enclosing headings are readable beside it.
- Related: std.gui.markdown.005, app.scope.viewers.003

### app.scope.document.013 — PDF page links do not join the back/forward history

- Evidence: bookmark, margin and typed-page jumps record their place in `Viewer.History` and
  Alt+arrows or the lens restore its page point and zoom. Page-link annotations are not exposed
  by the engine (std.gui.pdf.017), so a link inside a page cannot be followed or returned from,
  and a search reveal is not recorded as a jump.
- Next: when the engine exposes link annotations, route supported page links through
  `PdfDocument.Panel.showBookmark`'s navigation contract and name an unresolved target in place.
- Done when: supported local links share the bookmark history behavior while invalid targets
  remain visible.
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

### app.scope.document.005 — HTML encoding decisions have no override or conflict warnings

- Evidence: the information sheet names the encoding in force and what decided it (byte-order
  mark, declared label, or the bytes) from `HtmlView.encoding` and `encodingSource`. There is no
  manual override, no warning for a late or conflicting declaration, and no byte mapping for
  decoding failures.
- Next: add an override using the text viewer's supported encoding choices with explicit restart
  behavior, then report a declaration that arrives after the probe or contradicts a mark.
- Done when: late or conflicting declarations warn, invalid bytes remain traceable, and an
  override re-renders safely.
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

- Evidence: the DOCX reader retains ordered paragraphs, simple tables, bounded raster images,
  page-break separators and common inherited paragraph/character styles. Document defaults,
  parent styles, basic theme fonts/colors, sizes, emphasis, spacing and indents are resolved;
  styled headings populate the filterable outline. Broken optional styles retain readable prose
  and a visible simplification notice. Authored page size/margins, section columns, headers,
  footers, footnotes, comments, floating objects and complex table geometry remain absent.
  [Word Read Mode](https://support.microsoft.com/en-gb/word/read-documents-in-word)
  preserves navigable pages and adapts them to the reading surface.
- Next: lay out page and section geometry, then headers, footers and footnotes; extend numbering,
  tabs, table styles and complex-script font/theme fidelity with real producer fixtures. Add
  document-wide search, selection and position restore without materializing every page at open.
- Done when: authored pages, text flow, images and table structure remain recognizable across a
  freely licensed DOCX corpus, unsupported constructs are named at their location, and the first
  page appears without decoding the full package.
- Related: app.scope.binary.010

### app.scope.document.025 — XLSX lacks a true workbook reading surface

- Evidence: the XLSX reader orders sheets and shows values or uncached formula expressions in a
  512-column grid. One sheet is shown at a time, starting with the saved active sheet; the
  filterable outline, arrows and Ctrl+Page Up/Down switch sheets. Hidden and very-hidden sheets
  stay hidden until explicitly revealed. The native grid preserves declared column widths, row
  heights, sparse addresses, disjoint merged cells and hidden rows/columns; a separate command
  reveals hidden ranges. Cell selection, keyboard moves, copy and a theme-aware text view support
  reading. Only visible rows are painted, including million-row address spans. Direct and base
  XFs now retain font size/emphasis, colors, solid fills, common borders, alignment, wrapping and
  Normal-font indents. Spreadsheet theme/indexed colors and luminance tints are resolved; numeric
  overflow stays explicit. Common built-in and custom currency, grouped decimal, percentage,
  date and elapsed-time formats retain both Excel date systems and the fictitious 1900 leap day.
  Unsupported formats keep the stored value and a notice; unsupported visual effects are labelled
  simplified. Saved cells now inherit custom row XFs and then column XFs when their own style
  is absent; explicit cell XF zero remains an override. Producer output and a LibreOffice re-save
  confirm this precedence. Unsaved blank regions still have no inherited paint. Exact named
  font matching, frozen panes, filters, comments
  and charts remain absent. [Excel's frozen panes](https://support.microsoft.com/en-gb/excel/get-started/freeze-panes-to-lock-rows-and-columns)
  illustrate why authored grid navigation matters to reading.
- Next: paint inherited styles in unsaved blank regions and resolve named font families, then preserve frozen panes and add
  rectangular selection, direct cell addressing and sheet-wide search before read-only chart
  previews. Extend numeric formatting to conditions, fractions, scientific notation and localized
  date profiles with producer fixtures; keep unsupported codes explicit.
- Done when: real workbooks show their authored grid and formatted values, frozen and hidden regions
  behave as declared, formulas never execute, large sheets stay bounded, and every omitted construct
  is explicitly reported.
- Related: app.scope.text.015, app.scope.text.017

### app.scope.document.026 — PPTX lacks slide geometry and presentation reading

- Evidence: the PPTX reader now fits individual slides at authored aspect ratio, retaining text
  and raster-picture geometry, solid colors, basic theme colors/text sizes, simple rectangles,
  static master objects and inherited placeholder bounds. Slide titles appear in the shared
  outline; arrows, Page Up/Down and a theme-aware text mode support reading. Unsupported geometry
  falls back to a labelled simplified layout. The real Apache POI sample and a widescreen deck
  cover inherited title placement, authored colors, pictures and navigation. Charts, complex
  drawings, complete text inheritance and a thumbnail overview remain absent. A dedicated
  theme-aware notes reader now exposes bounded speaker prose and emphasis through the lens,
  follows slide navigation and omits notes-page thumbnails, footers and counters.
  [PowerPoint Reading and Slide Show views](https://support.microsoft.com/en-us/powerpoint/how-certain-features-behave-in-web-based-powerpoint)
  retain slide navigation and notes.
- Next: add a thumbnail overview, then lazy slide decoding so the first canvas
  can appear before the rest of the deck is projected. Extend shapes, paragraph styles, color
  transforms and font/theme inheritance with producer fixtures. Keep animation, embedded media
  and external actions inert and make omitted content explicit.
- Done when: a real presentation is recognizable slide by slide at authored aspect ratio, notes
  and navigation remain available, unsupported effects are explicit, and slide 1 appears without
  decoding every slide.
- Related: app.scope.binary.010

### app.scope.document.021 — EPUB chapter reading needs complete navigation

- Evidence: EPUB 2 NCX and EPUB 3 contents now expose authored titles, hierarchy and chapter
  fragments in the shared filterable outline. Internal spine links keep the chapter counter in
  sync. Zoom and column choices preserve the visible text passage; bounded Back/Forward history
  returns to that passage across chapter and fragment visits, through the lens or Alt+arrows.
  Book-wide search, landmarks, non-spine footnotes, persistent position restore and bookmarks
  remain absent. Extraction still prepares every package member before the first chapter is shown.
- Next: add book-wide search with chapter/all-book scope and stable chapter positions, then
  bookmarks, persistent reading positions and lazy extraction of the visible chapter's resources.
- Done when: TOC, previous/next, links, footnotes, search, bookmarks, history and position restore work across a
  representative EPUB 2/3 corpus without delaying first content for the whole package.
- Related: app.scope.binary.010

### app.scope.document.027 — CBZ has page turns but no complete comic reading modes

- Evidence: `Viewers.Comic` lists image members in natural filename order and opens one page through
  `EmbeddedViewer`. Previous and next controls are available, and a lens option maps left/right
  keys to manga reading order. A clickable page counter accepts a one-based page number. There is
  still no thumbnail index or multi-page reading layout. A dedicated reader such as
  [OpenComic](https://github.com/ollm/OpenComic) offers right-to-left manga, double-page spreads,
  continuous webtoon scroll, bookmarks and reading-position restore.
- Next: add a bounded page index with thumbnails and stable positions, then single/spread/continuous
  layouts, right-to-left spreads, cover alignment and per-page fit/zoom. Read safe `ComicInfo.xml`
  metadata when present without treating it as an image page.
- Done when: natural order, nested folders, spreads, manga direction, tall pages and damaged
  members remain readable and navigable across real CBZ books; page changes never require
  extracting all images first, and unsupported image pages are named in place.
- Related: app.scope.image.005, app.scope.viewers.003

### app.scope.document.028 — EPUB needs paged layout and persistent logical reading positions

- Evidence: the chapter reader offers compact, comfortable and wide default reading measures,
  plus zoom. A logical text location preserves the visible passage through those changes, while
  authored CSS keeps priority. There is no book-level paged/continuous-flow choice, line-spacing
  control or persistent position restore, and ordinary viewport reflow still keeps pixel scroll.
- Next: build book-owned paged and continuous modes over the HTML layout, retain a logical
  location across viewport changes, and connect it to navigation, search and safe position restore.
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

### app.scope.document.032 — OpenDocument reading needs fuller Writer/Calc/Impress fidelity

- Evidence: ODT omits physical pages, headers/footers, notes, comments and complex drawings.
  ODS uses saved formatted strings; raw typed values lack full ODF number-style reconstruction.
  Its charts, annotations, advanced geometry and exact font metrics are simplified. ODP fits
  common positioned text, rectangles and raster pictures with basic style/master inheritance,
  with speaker notes available in a separate theme-aware prose reader. Group transforms and
  unsupported drawings fall back to text; media, gradients,
  full master placeholder geometry and complex shapes are not reproduced. Slides are loaded eagerly.
- Next: cover ODS number styles when saved display strings are absent, expose unsupported
  components explicitly, deepen Impress master/shape fidelity and defer off-screen slide work.
- Done when: genuine LibreOffice files retain common authored layout and components; notes
  can be inspected separately; unsupported content remains explicit; navigation stays responsive
  and cancellation/package budgets hold on large and damaged documents.

### app.scope.document.033 — EPUB contents do not follow the reading position

- Evidence: `DocumentOutline.follow` marks the Markdown, HTML, DOCX, ODT and PDF heading in view
  as soon as the headings are published or the outline is opened, and follows every scroll after
  that. EPUB contents are addressed by chapter and fragment, and nothing maps the reading
  position of the chapter shown back to its contents entry, so none is marked.
- Next: map an EPUB reading position (chapter and source offset in its document) to the last
  contents entry at or before it, and give the EPUB outline a `follow` callback.
- Done when: an EPUB outline marks the entry being read at open and while scrolling and turning
  chapters, with its picture recorded.
- Related: app.scope.document.001, app.scope.document.021
