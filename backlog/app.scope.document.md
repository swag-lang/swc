# Swag Scope Document Viewer Backlog

This backlog covers Swag Scope's Markdown, HTML, PDF, office-document, and ebook reading surfaces.
Parser, layout, and renderer defects remain with their engines in [std.gui.markdown.md](std.gui.markdown.md),
[std.gui.html.md](std.gui.html.md), and [std.gui.pdf.md](std.gui.pdf.md); entries here own navigation, inspection, and application
integration around those engines.

## Markdown reading

### app.scope.document.001 — Markdown has no document outline or heading breadcrumbs

- Evidence: the viewer offers reading width and appearance, while heading hierarchy is only part of
  the rendered page. `Gui.Markdown.View` navigation work is already std.gui.markdown.005, but Swag Scope has no
  outline panel, filter, visible-section tracking, or heading history to present it.
- Next: define the viewer-side outline model and wire it to engine heading anchors as std.gui.markdown.005 lands.
- Complete when: headings form a filterable hierarchy, activating one reveals it, the current path
  follows scrolling, duplicate headings remain distinct, and keyboard navigation is complete.
- Related: std.gui.markdown.005

### app.scope.document.002 — Markdown cannot switch between rendered, source, and synchronized split views

- Evidence: `.md` and `.markdown` currently offer Markdown, Binary, and Hexadecimal, but not Basic
  text. There is no direct source inspection, synchronized split view, or mapping from a rendered
  block to its source range.
- Next: first expose Basic text through app.scope.text.025, then retain parser source ranges in the
  adapter and host rendered/source panes with a shared logical position.
- Complete when: Rendered, Source, and Split modes preserve the nearest block, scroll can
  synchronize in either direction, search results map across modes, and large files stay streamed.
- Related: app.scope.text.025

### app.scope.document.003 — Markdown links and resources have no trust or diagnostics surface

- Evidence: links can activate and images depend on engine work, but the viewer does not list local
  and remote targets, broken anchors, missing images, blocked schemes, or resources outside the
  document directory. The engine's std.gui.markdown.006 and preview security policy remain undecided.
- Next: inventory every parsed target and classify resolution, availability, scheme, and trust
  without fetching remote content implicitly.
- Complete when: a resource panel links each target to source and rendered content, broken local
  references are explained, remote access requires explicit policy, and blocked content remains
  visible as a diagnostic.
- Related: std.gui.markdown.001, std.gui.markdown.006

### app.scope.document.004 — Markdown reading position and presentation cannot be shared or exported

- Evidence: a reader cannot copy a stable link to a heading, export the rendered document, or save
  the active theme/measure as a self-contained reading artifact. Reopening also loses position.
- Next: define stable heading/block locators and a read-only export contract for HTML and paginated
  output after the shared print path exists.
- Complete when: a logical reading position restores through app.scope.viewers.003, heading links can be copied,
  self-contained HTML preserves safe local assets, and paginated output uses app.scope.viewers.002.
- Related: app.scope.viewers.003, app.scope.viewers.002

## HTML reading

### app.scope.document.005 — HTML decoding assumes UTF-8 instead of following document encoding rules

- Evidence: the adapter summary says `HTML · UTF-8 · streamed`; there is no BOM/header/meta charset
  decision, encoding override, confidence display, or byte mapping for decoding failures.
- Next: add bounded prescan and restart rules for BOM and early `meta charset`, then expose the same
  encoding selector and diagnostics as text where valid.
- Complete when: UTF-8, UTF-16, and supported legacy declarations decode predictably, late or
  conflicting declarations warn, invalid bytes remain traceable, and an override re-renders safely.
- Related: app.scope.text.004

### app.scope.document.006 — HTML has no DOM outline or element-to-page inspection

- Evidence: `HtmlView` is hosted as one rendered surface. A reader cannot browse element hierarchy,
  inspect tag/id/class/attributes, or select an element and see its box and source range.
- Next: expose a read-only DOM adapter with stable node identity and bidirectional selection between
  a virtual tree, source, and rendered box.
- Complete when: nodes can be filtered, collapsed, copied, and revealed; generated boxes identify
  their source node; malformed recovery is explicit; and huge repetitive DOMs remain virtualized.

### app.scope.document.007 — HTML cannot switch to source or a synchronized split view

- Evidence: choosing Code or Basic text discards the rendered position, active link, search match,
  and DOM node. There is no formatted source, line address, or live element mapping.
- Next: compose rendered, source, and split modes over the DOM/source ranges introduced by app.scope.document.006.
- Complete when: the selected element and scroll position map both ways, source retains exact bytes
  or declares normalization, search can target source or visible text, and scripts never execute.
- Related: app.scope.document.006

### app.scope.document.008 — HTML resource loading and blocking are invisible

- Evidence: local pages may reference stylesheets, images, fonts, frames, media, data URLs, and
  remote URLs, but the viewer has no resource list, status, size, origin, cache, or reason a resource
  was not rendered.
- Next: route all resource resolution through an observable offline-first request ledger with
  explicit budgets and policy decisions.
- Complete when: every requested resource shows resolved path/origin, type, bytes, result, and
  blocker; remote fetch is opt-in; traversal outside allowed roots is prevented; and entries link
  to the requesting node.
- Related: std.gui.html.019

### app.scope.document.009 — HTML navigation has no history, address model, or fragment overview

- Evidence: link activation is forwarded to the host, but same-document fragments, relative files,
  back/forward history, visited state, and broken targets do not form a coherent document session.
- Next: define a local-document navigation stack that distinguishes fragments, sibling files,
  external URLs, downloads, and blocked schemes.
- Complete when: back/forward restores scroll and selection, fragments and relative links resolve
  against the correct base, broken targets explain themselves, and external activation requires a
  deliberate command.

### app.scope.document.010 — HTML has no reader-mode or page-level diagnostics

- Evidence: a professional local-page viewer needs both faithful layout and a way to understand an
  unreadable page. There is no extracted reading view, title/language/description summary, outline,
  standards quirks indicator, or list of layout/parser warnings.
- Next: surface document metadata and engine diagnostics first, then derive a clearly labelled
  reader view from semantic blocks without replacing faithful mode.
- Complete when: title, language, metadata, headings, landmarks, and warnings are inspectable;
  reader mode preserves links and text order; and switching modes retains the logical location.
- Related: std.gui.html.017

This backlog covers application-owned PDF presentation and the document viewers built by composing
Swag Scope's existing HTML, table, and container facilities. Parser and renderer gaps owned by the
reusable engines remain in [std.gui.pdf.md](std.gui.pdf.md), [std.gui.html.md](std.gui.html.md), and [std.gui.md](std.gui.md).

## PDF presentation

### app.scope.document.011 — A PDF the module cannot fully decode is shown as a failure, not as a page

- Intent: the module's own coverage gaps now live in [std.gui.pdf.md](std.gui.pdf.md), which is the
  roadmap for `std/pdf`. What stays here is the viewer's half: `PdfViewer` reports whatever
  `loadPage` or `render` failed with and shows nothing, so a document with one unsupported
  construct anywhere reads as a broken file rather than as a page with a gap in it.
- Complete when: the viewer draws the part of a page that decoded, states the construct it could
  not represent in localized text beside it rather than as a raw module error, and keeps page
  navigation working across a page it could only partly decode.
- Note: never execute an embedded action, and keep interactive form filling out of the viewer.
- Related: std.gui.pdf.002

### app.scope.document.012 — PDF page navigation has no thumbnails or page-label lookup

- Evidence: the centered command bar provides previous/next and a clickable `current / total`
  readout with validated numeric page entry. There is no thumbnail strip, page-label lookup, or
  overview suitable for a long document.
- Next: render cancellable low-resolution thumbnails through a bounded cache and extend the page
  address control with PDF page labels.
- Complete when: thumbnails prioritize the visible neighborhood, direct numeric and page-label
  jumps validate input, the current page is selected, and thousand-page documents stay responsive.
- Related: std.gui.pdf.018

### app.scope.document.013 — PDF bookmarks and destinations have no viewer surface

- Evidence: the PDF engine does not yet read outlines, named destinations, or link targets (std.gui.pdf.017),
  and Swag Scope has no panel or history ready to present them once decoded.
- Next: define a filterable hierarchical bookmark/destination model and viewer navigation contract
  against the engine API planned by std.gui.pdf.017.
- Complete when: outline items, internal links, named destinations, and back/forward navigation
  preserve page plus coordinates and zoom; invalid destinations are visible rather than ignored.
- Related: std.gui.pdf.017

### app.scope.document.014 — PDF viewing is limited to one fitted page or actual size

- Evidence: `PdfView` exposes one `pageIndex`, Fit Page, Actual Size, and zoom buttons. There is no
  fit-width, continuous scroll, facing pages, cover-page rule, or presentation mode.
- Next: separate page layout from zoom and add Fit Width plus continuous single-page layout before
  facing-page composition.
- Complete when: Single, Continuous, Facing, and Continuous Facing modes share navigation and
  search; Fit Page/Width/Selection are distinct; page gaps and cover handling are correct; and
  decoded-page caching stays bounded.

### app.scope.document.015 — PDF pages cannot be rotated or viewed with box and geometry overlays

- Evidence: the viewer has no clockwise/counter-clockwise rotation, crop/media/bleed box display,
  page-size readout, coordinate probe, or temporary crop-to-content view.
- Next: add non-destructive per-document rotation and an optional page-geometry overlay backed by
  exact PDF page dictionaries.
- Complete when: rotation affects rendering, search bounds, selection, thumbnails, and print
  consistently; page boxes and dimensions are inspectable; and no command rewrites the PDF.

### app.scope.document.016 — PDF text selection, copy, and reading order are not a complete workflow

- Evidence: a page's text is indexed in reading order, a drag selects across the lines of the
  displayed page, a double click takes a word, and the search finds and selects on any page. The
  selection still stops at the page, there is no keyboard selection, no choice between logical and
  visual copy order, no reflow reading, and an image-only page says nothing about why a search
  finds nothing in it.
- Next: design selection and copy across page boundaries on the ordered text model, preserving
  glyph/source coordinates for exact and logical forms.
- Complete when: text can be selected by pointer and keyboard across lines and pages, copied as
  logical or visual order, search and selection agree, and image-only pages state that OCR is absent.

### app.scope.document.017 — PDF annotations, attachments, forms, layers, and signatures are hidden

- Evidence: engine tasks cover annotation appearance (std.gui.pdf.003) and optional content (std.gui.pdf.008), but the
  viewer has no read-only inventory for annotations, embedded files, AcroForm fields, layers,
  digital signatures, JavaScript actions, or security permissions.
- Next: define a safe document-components panel and add sections as the parser exposes each object
  family, beginning with annotations and attachments without executing actions.
- Complete when: components link to page bounds or objects, attachment extraction is explicit and
  sanitized, signatures report cryptographic status and limits, layers can be toggled temporarily,
  form values are inspectable, and active content never runs.
- Related: std.gui.pdf.003, std.gui.pdf.008

### app.scope.document.018 — Password-protected PDFs have no application interaction

- Evidence: std.gui.pdf.001 records that encrypted documents are refused, and the viewer result can only
  return a terminal failure string. There is no secure password prompt, retry policy, permissions
  summary, or credential lifetime decision.
- Next: extend progressive viewer opening with a credential request that never persists or logs the
  password, then connect it to the engine work from std.gui.pdf.001.
- Complete when: empty and entered passwords can unlock supported encryption, cancellation returns
  to a stable viewer state, retry is bounded, permissions are shown, and secrets leave memory when
  the document closes.
- Related: std.gui.pdf.001

### app.scope.document.019 — PDF pages and embedded assets cannot be exported for inspection

- Evidence: Swag Scope can render pages but offers no copy-page-image, save selected pages as
  images, extract an embedded image/font/attachment, or export selected text with provenance.
- Next: define read-only extraction commands with exact object/page origin and explicit raw versus
  rendered output.
- Complete when: current or selected pages can be copied/rendered at chosen DPI, supported embedded
  assets can be saved without silent conversion, filenames are sanitized, and unsupported or
  lossy extraction is explained.

## Packaged documents

### app.scope.document.020 — Office Open XML files stop at the ZIP structure

- Intent: `.docx`, `.xlsx`, and `.pptx` still show a list of parts. OpenDocument files now have
  their own reader, but the Microsoft Office family needs the same readable-content boundary.
- Next: identify the shared document structure that can read paragraphs, headings, lists, tables,
  and spreadsheet cells without expanding the OpenDocument decoder into an Office compatibility
  layer.
- Complete when: Office Open XML documents open through readable document and table surfaces rather
  than only their ZIP hierarchy.
- Related: app.scope.text.015, app.scope.binary.010

### app.scope.document.021 — EPUB stops at the ZIP structure

- Intent: an EPUB is a spine of HTML documents, and the HTML view already renders them.
- Complete when: the spine order is read from the container manifest and its documents stream into
  the reading column in order.
- Related: app.scope.binary.010

## Native InDesign documents

### app.scope.document.023 — Native InDesign rendering needs native page composition

- Evidence: Swag Scope validates the duplicated master-page header, indexes every saved XMP JPEG
  page preview, and decodes selected pages on demand through a bounded LRU cache. The visual result
  is no longer a metadata substitute, but a preview is optional, may be stale, and does not expose
  the native page-layout object graph, text selection, links, or output fidelity.
- Next: add a preview-thumbnail navigator over the on-demand cache, then identify the native page
  composition records that can be interpreted in Swag for documents with no saved preview pixels.
- Complete when: every supported page has a clearly sourced visual rendering, navigation preserves
  page identity and loading state, absent or stale preview data is named plainly, and no native
  object is executed to render the document.
- Related: app.scope.indesign.002, app.scope.indesign.012, app.scope.indesign.018

## Developer documents

### app.scope.document.022 — Jupyter notebooks have no document reader

- Evidence: `.ipynb` has no registered viewer and therefore offers only Binary and Hexadecimal,
  despite being a textual JSON container. Markdown cells, code cells, execution order,
  attachments, stored images, tables, errors, and metadata lose their document structure. GitHub
  renders notebooks as static HTML without activating custom JavaScript, while Visual Studio Code
  adds cell/output search and outline and hides rich outputs in untrusted workspaces. Those are the
  relevant reader behaviors; kernel execution is not.
- Next: parse notebook cells and render Markdown, syntax-colored source, plain text, bounded images,
  tables, and JSON output through existing viewers while defining a deny-by-default MIME and trust
  policy for HTML, SVG, JavaScript, widgets, and external resources.
- Complete when: cell order, type, execution count, metadata, attachments, errors, and every stored
  output remain inspectable; outline and search address inputs and outputs separately; unsupported or
  suppressed rich output is named and available as source; large output is collapsed and bounded;
  and opening a notebook never starts a kernel, executes code, or fetches a resource.
- Related: app.scope.document.003, app.scope.text.024, app.scope.text.025, app.scope.viewers.011
