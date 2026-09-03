# Swag Scope OpenDocument Backlog

This backlog owns the OpenDocument decoder and reader in Swag Scope. It is deliberately a
read-only product: opening a package must never execute a macro, a formula, a script, a linked
resource, or an embedded application. A feature-complete outcome means that a supported ODF
document keeps its readable semantics, layout, navigation, metadata, and safe local media, while
every unsupported component is named rather than silently discarded.

The current reader opens ODT, ODS, ODP, ODG, their templates, and Flat XML variants. It reads
basic text structure, common text emphasis, bounded package raster images, every spreadsheet sheet,
and every presentation slide or drawing page. It is a readable-content decoder, not yet an ODF
layout engine or a complete package model.

## Package conformance and safe ingestion

### app.scope.opendocument.001 — Package declarations, manifests, and components form one verified model

- Evidence: the reader selects a kind from `mimetype` and opens `content.xml`, with optional
  `styles.xml` and bounded picture entries. It does not read `META-INF/manifest.xml`, validate the
  package's declared parts or media types, inventory RDF metadata, or explain omitted components.
- Next: model the manifest, package parts, media types, checksums when present, and relationships
  before content decoding; expose one bounded component inventory for every package member.
- Complete when: a malformed or contradictory package fails with its exact component, every
  readable component has a verified source and media type, and omitted parts are visible to the
  reader without extracting or executing them.
- Related: app.scope.binary.010, app.scope.viewers.011

### app.scope.opendocument.002 — Every ODF family and version has an explicit reader contract

- Evidence: text, spreadsheet, presentation, and drawing packages are registered, but chart,
  image, formula, database, web, and master-document families have neither a selector nor a stated
  fallback. Version, extended, foreign, and vendor-specific markup is not classified.
- Next: publish a version and family support matrix covering package, template, and Flat XML forms;
  route every recognized family to a reader, safe component view, or explicit unsupported result.
- Complete when: a file's extension, manifest, and root element cannot disagree silently, and every
  ODF family has a tested and documented outcome.
- Related: app.scope.viewers.010, app.scope.binary.010

### app.scope.opendocument.003 — ODF XML decoding has a bounded namespace-aware recovery policy

- Evidence: the current tokenizer accepts the markup needed by the fixture corpus but does not
  retain namespace declarations, document-version facts, foreign elements, or a structured recovery
  record for malformed XML.
- Next: define a streaming ODF XML reader with namespace resolution, depth, attribute, text, and
  entity-expansion limits; retain unknown foreign subtrees as named components when safe.
- Complete when: compliant XML round-trips into the document model, malformed or oversized input
  stops at a deterministic limit, and ignored markup is reported with element and namespace names.
- Related: app.scope.binary.010, app.scope.viewers.011

### app.scope.opendocument.004 — Metadata, provenance, signatures, and encryption are inspectable

- Evidence: the bounded `meta.xml` title, subject, and creator are decoded and the title names the
  reader details, but dates, keywords, language, generator, user-defined fields, digital
  signatures, encryption, and package provenance are not inspected.
- Next: extend display-safe metadata and add a signature/encryption inventory; keep encrypted content
  locked until a future explicit password workflow can establish its own secure boundary.
- Complete when: title, subject, authors, dates, keywords, generator, language, and declared
  protection state are visible with their package source, and no protected or signed content is
  mistaken for verified readable content.
- Related: app.scope.document.017, app.scope.viewers.011

## Text documents and shared styles

### app.scope.opendocument.005 — Styles resolve through the complete ODF inheritance graph

- Evidence: automatic and named text styles retain a small emphasis subset and shallow inheritance
  from `styles.xml`; defaults, parent chains, list levels, page layouts, master pages, conditional
  mappings, and most properties are dropped.
- Next: build an immutable style graph with cycle diagnostics and a normalized reader style model
  that distinguishes inherited, direct, and default properties.
- Complete when: a supported text, table, drawing, or presentation object receives the same
  resolved reader style regardless of where its ODF style was declared, and unsupported properties
  appear in the component inventory.
- Related: std.gui.html.019

### app.scope.opendocument.006 — Text semantics retain sections, fields, references, and editorial content

- Evidence: headings, paragraphs, lists, tables, links, and simple spans survive, but sections,
  bookmarks, reference marks, indexes, fields, variables, footnotes, endnotes, annotations,
  tracked changes, bibliography, and table-of-contents structure disappear.
- Next: define a safe semantic document tree for each textual ODF structure, including visible
  field values and change state without evaluating expressions or updating fields.
- Complete when: navigation, search, copy, and accessibility distinguish body text from notes,
  comments, changes, references, and generated structures, with every field showing its stored
  value and source rather than a computed result.
- Related: app.scope.viewers.001, app.scope.viewers.011

### app.scope.opendocument.007 — International typography and writing directions remain readable

- Evidence: the reader does not model language runs, script-specific fonts, bidirectional flow,
  writing modes, ruby, phonetic guides, tabs, hyphenation, or text rotation.
- Next: carry language, direction, writing mode, and typographic fallback facts into the reader
  model, then map the renderable subset into the shared text surface.
- Complete when: mixed-direction and multilingual documents preserve logical reading order,
  selection order, language metadata, and visible fallback notices where the shared renderer lacks
  a required shaping or layout capability.
- Related: std.gui.html.019, app.scope.viewers.001

### app.scope.opendocument.008 — Page layout, headers, footers, and print structure have a reader representation

- Evidence: ODT content flows as one HTML column; page size, margins, columns, page breaks,
  headers, footers, page numbers, background, and print ranges are lost.
- Next: add a paged read-only document model that can present continuous and page modes from
  resolved ODF page layouts without invoking a printer or modifying the package.
- Complete when: page boundaries, headers, footers, page-number fields, columns, and intentional
  breaks are visible and searchable in a stable reading order at arbitrary zoom.
- Related: app.scope.document.012, std.gui.html.001

### app.scope.opendocument.009 — ODF tables preserve spans, dimensions, and repeated structure

- Evidence: sheets and text tables retain basic cells, but merged cells, covered cells, row and
  column dimensions, repeated styles, header regions, and table layout rules are omitted. The
  shared HTML renderer cannot lay out `colspan` or `rowspan` safely.
- Next: complete span placement in the shared HTML table engine, then map ODF table geometry and
  headers into the table and document surfaces with bounded repeated-cell expansion.
- Complete when: a merged ODF table keeps cell identity, headers, spans, dimensions, and reading
  order in both document and spreadsheet views without corrupting adjacent cells.
- Related: std.gui.html.002, app.scope.text.015

## Drawings, media, and presentation

### app.scope.opendocument.010 — Local media resolves through a safe ODF resource model

- Evidence: a bounded count and size of package raster images becomes data URIs; vector images,
  thumbnails, media objects, image maps, binary blobs, unsupported codecs, and manifest media-type
  checks are absent. Remote references remain inert but are not shown as such.
- Next: resolve each local resource against the manifest, decode supported raster and vector forms
  under explicit byte and pixel limits, and report every blocked external or unsupported reference.
- Complete when: local media appears at its intended place with intrinsic and declared dimensions,
  every resource has source and media-type provenance, and no URI causes a network, filesystem, or
  application launch.
- Related: app.scope.image.002, std.pixel.image.001, app.scope.viewers.011

### app.scope.opendocument.011 — ODG pages render drawing primitives, groups, layers, and connectors

- Evidence: ODG currently exposes readable text boxes and bounded raster images per page; shapes,
  paths, transforms, groups, layers, z-order, text-on-path, connectors, and page geometry are not
  represented.
- Next: define a retained, bounded drawing scene that maps safe ODF primitives to existing vector
  and text painting without treating embedded scripts or objects as drawable content.
- Complete when: a drawing page preserves page size, object bounds, transforms, grouping, layer
  visibility, stacking order, connectors, and selectable text; unsupported primitives are named.
- Related: std.pixel.image.012, app.scope.image.004

### app.scope.opendocument.012 — ODP slides retain master layouts, notes, objects, and show structure

- Evidence: the reader selects plain slide text and local images, but masters, layout placeholders,
  notes, handout content, custom shows, timings, transitions, animations, charts, embedded objects,
  and media are absent.
- Next: model slide masters, page geometry, placeholders, notes, and a safe static object scene;
  show animation and transition facts without playing active content automatically.
- Complete when: slide, master, note, and handout content can be navigated independently, static
  layout matches the stored page geometry, and every dynamic object or transition has an explicit
  read-only representation.
- Related: app.scope.opendocument.010, app.scope.opendocument.011

### app.scope.opendocument.013 — Charts, formulas, equations, and embedded documents have safe previews

- Evidence: chart and formula packages, embedded document objects, MathML, OLE objects, and
  document-in-document frames are currently skipped or reduced to surrounding text.
- Next: decode stored chart data, MathML, and safe embedded-document thumbnails into static reader
  components; retain object type, source, and activation policy beside each preview.
- Complete when: an embedded object is never executed, yet its readable stored preview, data, or
  source component is reachable, searchable where textual, and clearly marked when unavailable.
- Related: app.scope.document.017, app.scope.viewers.011

## Spreadsheets

### app.scope.opendocument.014 — Spreadsheet values, formats, and formula provenance are typed and inspectable

- Evidence: ODS displays source or cached values and never evaluates formulas, but type, locale,
  number/date/time/currency/percentage formats, errors, booleans, rich text, validation, named
  expressions, and formula text are not shown consistently.
- Next: store typed cell values, cached display values, formula text, error state, locale, and
  number format separately; expose them through an inspector without calculation.
- Complete when: every visible cell can show its stored value, formatted value, formula, type,
  validation, and cached result without the viewer evaluating any expression.
- Related: app.scope.text.016, app.scope.viewers.011

### app.scope.opendocument.015 — Spreadsheet layout and navigation match a large-sheet reader

- Evidence: every sheet opens through the virtual table, but frozen panes, row and column size,
  hidden state, filters, sorting, outline groups, named ranges, print areas, cell anchors, and
  cross-sheet references are not navigable.
- Next: preserve sheet geometry and view settings, add named-range and address navigation, and
  make filters or sort state inspectable as stored document facts rather than recalculated output.
- Complete when: a large workbook keeps stable headers and frozen regions, can jump to a cell,
  named range, reference, or sheet, and identifies hidden, filtered, grouped, or out-of-print data.
- Related: app.scope.text.015, app.scope.opendocument.009

### app.scope.opendocument.016 — Spreadsheet visual and analytical components stay safe and explicit

- Evidence: conditional formatting, sparklines, scenarios, pivot tables, data pilots, charts,
  comments, hyperlinks, drawing objects, and sheet protection are not surfaced.
- Next: add static visual summaries and component panes backed only by stored ODF data; make any
  unavailable recalculation, refresh, macro, or external-data action a visible refusal.
- Complete when: a reader can inspect the stored rule, source, and cached presentation of every
  spreadsheet component without recalculation, data refresh, or external access.
- Related: app.scope.opendocument.013, app.scope.opendocument.014

## Reader interaction, accessibility, and quality

### app.scope.opendocument.017 — Document navigation, outline, thumbnails, and search share one model

- Evidence: sheets, slides, and drawing pages have a compact selector and cross-surface search;
  text documents have no generated outline, long presentations have no thumbnails, and search
  results do not carry semantic destination, page, or object context.
- Next: derive one document navigator from headings, bookmarks, sheets, ranges, slides, pages,
  notes, and supported objects; use it for outline, thumbnails, search context, and direct jumps.
- Complete when: every supported semantic destination can be reached by keyboard, pointer, search,
  or outline with a stable visible location and no forced materialization of unrelated content.
- Related: app.scope.document.011, app.scope.viewers.001

### app.scope.opendocument.018 — Selection, copy, links, and accessibility preserve document meaning

- Evidence: generated HTML offers basic visible text and explicit links, but structure-aware copy,
  reading order, object descriptions, table headers, language, keyboard shortcuts, focus order,
  high-contrast presentation, and assistive-technology metadata are incomplete.
- Next: map the ODF semantic tree into selection and accessibility contracts, and define an explicit
  activation ledger for internal, local, and external links.
- Complete when: copy exports logical document text with enough structure to retain headings,
  lists, tables, notes, and link destinations; keyboard and assistive readers can reach every
  visible component; and activating a link always requires a deliberate user action.
- Related: app.scope.viewers.001, app.scope.viewers.011

### app.scope.opendocument.019 — Reader views support page, continuous, fit, zoom, and print-safe output

- Evidence: text, presentations, and drawings expose zoom; presentations and drawings select one
  page at a time, and spreadsheets use their virtual table. There is no continuous-page view,
  fit policy, document overview, print preview, or static export path.
- Next: define view modes per document family and a render-to-image/PDF contract that uses only the
  decoded read-only model, never the source office application.
- Complete when: a reader can choose continuous, page, fit-width, fit-page, and overview modes
  where meaningful, while export and print preview identify their source model, DPI, pagination,
  and every fidelity limitation.
- Related: app.scope.document.012, app.scope.viewers.012

### app.scope.opendocument.020 — Decoder limits, failures, and cancellation are observable under hostile input

- Evidence: XML, table, image, and ZIP entry limits exist, but the full package has no uniform
  resource budget, cancellation, progress model, fuzz corpus, or viewer-visible explanation of
  which safe limit stopped a document.
- Next: establish cumulative budgets for archive members, XML nodes, style graph size, images,
  pages, objects, decoded pixels, and render time; add cancellation checkpoints and a corpus of
  corrupt, adversarial, and oversized ODF packages.
- Complete when: every stop is bounded, cancelable, attributed to a named limit or component, and
  regression-tested against decompression bombs, malformed XML, cyclic styles, oversized repeats,
  malformed media, and unsupported encryption.
- Related: app.scope.binary.008, app.scope.viewers.011

### app.scope.opendocument.021 — Interoperability and visual fidelity are measured against real ODF producers

- Evidence: unit fixtures and immutable CC0 ODT, ODS, and ODP samples cover basic external input,
  but there is no versioned producer matrix, semantic comparison, visual baseline, or regression
  corpus for ODG, complex styles, spreadsheets, and presentations.
- Next: curate license-clean documents from multiple ODF producers and versions, record their
  provenance and expected semantic facts, and add targeted render goldens with manual review.
- Complete when: every supported feature has an externally produced fixture, expected omissions are
  explicit, visual regressions are reviewed before acceptance, and the corpus covers malformed as
  well as interoperable input.
- Related: app.scope.opendocument.020, app.scope.viewers.010

### app.scope.opendocument.022 — Feature completeness has a reproducible acceptance report

- Evidence: the current implementation and tests prove a useful readable subset, but no report
  connects package conformance, semantic retention, visual layout, safety, accessibility, and
  performance to the advertised OpenDocument support level.
- Next: define a machine-readable support matrix and release audit that consumes the fixture corpus,
  reports each ODF feature as rendered, inspectable, intentionally omitted, or unsupported, and
  links every remaining gap to this backlog.
- Complete when: a release can publish one reproducible reader-capability report for each supported
  ODF family and version, with no undocumented loss of document content or unsafe behavior.
- Related: app.scope.opendocument.001, app.scope.opendocument.021
