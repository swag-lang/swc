# Swag Scope InDesign Viewer Backlog

This backlog owns the read-only InDesign viewer under
`bin/apps/modules/swagscope/src/viewers/indesign`. Its goal is a dependable offline document
viewer, not an editor: opening, rendering, navigating, searching, inspecting, selecting and
exporting view data must never execute document content, contact the network, or rewrite a source
file. The current viewer validates native `.indd` headers, presents bounded saved XMP previews, and
builds an offline IDML page scene in Swag with page navigation, fit and explicit zoom, local linked
images, styled text, search, and visual regression fixtures.

IDML is the interoperable layout route. Native INDD may use its saved preview while native page
composition remains an explicitly separate capability. A feature-complete viewer is judged against
representative, openly licensed real documents and their visible reading workflow, never merely by
whether a JPEG preview decoded.

## First presentable content and document lifetime

### app.scope.indesign.001 — InDesign opening has no published latency and memory contract

- Evidence: the linked real IDML fixture has focused assertions that opening and selecting its QR
  page each complete below one second, but the viewer does not record cold/warm latency, first
  presentable page, peak retained bytes, page-turn latency, or behaviour on long publications.
- Next: define a reproducible performance corpus and measure native preview extraction, IDML index,
  first-page scene, cached page turn, search index, and peak memory separately. Publish a per-tier
  first-content budget and make the UI report staged progress rather than one undifferentiated open.
- Complete when: the performance suite proves first usable content within one second for every
  interactive corpus tier on the reference machine, cached turns remain below 100 ms, cold turns
  have a named budget, and a regression names the phase, document, page, and retained-byte cause.
- Related: app.scope.viewers.004, app.scope.viewers.009

### app.scope.indesign.002 — Native INDD pages rely on optional saved previews

- Evidence: the native path validates the duplicated master header and indexes saved XMP JPEG page
  previews. It cannot compose an INDD page when preview pixels are absent or stale, and has no
  object graph, source mapping, or fidelity claim beyond that preview.
- Next: identify the native page-composition records that can be safely interpreted in Swag, starting
  with page count, spread identity, page geometry, placed-image references, and text objects. Keep
  each decoded record bounded and expose an honest per-page rendering source.
- Complete when: every supported native page either has a reconstructed scene or clearly identified
  saved preview with freshness information; absent previews remain navigable and diagnosable; no
  native action, script, or plugin is executed.
- Related: app.scope.document.023, app.scope.indesign.018

### app.scope.indesign.003 — Page work is indexed eagerly instead of published progressively

- Evidence: one IDML load builds every page, story, style and linked-image record before the viewer
  can publish its first page. This is safe and works on the current fixtures, but it cannot scale to
  catalogue-sized packages at a market-viewer interaction latency.
- Next: split package discovery, page/spread indexing, first-page scene construction, remaining-page
  scene construction, and search text into cancellable stages with a bounded page-scene cache.
- Complete when: a first page can appear while later pages, thumbnails and search are still building;
  cancelling or replacing the file retires all pending work; cache eviction preserves only the
  declared neighbourhood and never changes rendered content.
- Related: app.scope.indesign.001, app.scope.viewers.004

## Page scene fidelity

### app.scope.indesign.004 — Linked text flows are estimated rather than laid out by composition rules

- Evidence: one story is now stored once and divided across linked frames proportionally to frame
  area. The local HTML engine performs line breaking, but it does not report exact frame overflow,
  balance columns, honour keep/widow/orphan rules, or carry a word into the next frame.
- Next: define a bounded frame-composer adapter over the HTML layout output, then flow paragraphs and
  permitted intra-paragraph breaks by measured height rather than an area estimate.
- Complete when: linked text consumes frames in source order with explicit overset state, unequal
  columns and cross-page chains balance by measured layout, and a layout fixture proves no duplicate,
  lost, or silently clipped text.
- Related: std.gui.html.010, app.scope.indesign.009

### app.scope.indesign.005 — IDML page geometry omits image fitting, transforms, masks, and effects

- Evidence: image frames resolve bounded embedded or local linked pixels. Axis-aligned inner image
  transforms and `GraphicBounds` preserve the tested crop rectangle, while path bounds, simple
  polygons, lines and oval frames have a local scene representation. Rotation/shear/reflection,
  clipping paths, opacity, blend modes, drop shadows, feathering, and content-aware fitting are not
  preserved.
- Next: retain frame and graphic transforms separately, add fit/crop/clip semantics before effects,
  and expose unsupported effects as item diagnostics rather than baking or hiding them.
- Complete when: a corpus of fitted, cropped, transformed and transparent images agrees with an
  InDesign reference at supported settings; unsupported effects remain visible with their bounds and
  a precise reason; source pixels are never silently resampled beyond declared limits.
- Related: std.gui.html.016, std.pixel.image.036

### app.scope.indesign.006 — Vector, paint, and stroke fidelity stops at simple solid shapes

- Evidence: rectangles, ovals, rounded corners, polygon clips, simple lines, solid fills, strokes
  and triangle arrowheads render locally. Gradients, patterns, compound paths, non-rounded corner
  treatments, dashes, end caps, joins, miter policy, arrows beyond triangles, transparency groups,
  and overprint are absent.
- Next: introduce one scene paint model with solid, gradient, pattern, stroke and group opacity
  primitives, mapping each IDML construct at a time and retaining an unsupported-item warning.
- Complete when: supported vectors remain resolution independent at every zoom, the scene matches
  reference pages for strokes and fills, group ordering is stable, and unsupported paint never
  disappears without a diagnostic.
- Related: app.scope.indesign.005, std.gui.044

### app.scope.indesign.007 — Masters, layers, spreads, and overrides are flattened into pages

- Evidence: master-page items are appended to matching pages, but facing-page spread geometry,
  master overrides, layers, hidden/nonprinting items, locked state, page transitions, alternate
  layouts, and bleed/slug geometry are not represented as document semantics.
- Next: retain a page-tree model for document, spread, master, layer and item identity before adding
  optional visible overlays and layer toggles.
- Complete when: single, facing and continuous layouts preserve page/spread identity; master and
  override provenance is inspectable; hidden/nonprinting policy is explicit; and layer visibility
  changes only the temporary viewer scene.
- Related: app.scope.indesign.012, app.scope.indesign.014

### app.scope.indesign.008 — Tables, anchored objects, notes, and generated content lose document meaning

- Evidence: text is reduced to styled paragraph and character HTML. Tables, cell geometry, anchored
  objects, footnotes/endnotes, cross-references, text variables, page-number markers, indexes, table
  of contents, and conditional text have no semantic or rendered model.
- Next: add an IDML semantic intermediate representation for inline, block, table, anchor, note and
  generated-content nodes, with source identity and a safe fallback for unsupported fields.
- Complete when: tables, notes and anchored content have correct reading order and visible geometry;
  generated values name their source/fallback state; search, copy and inspection preserve identities;
  and no field or cross-reference is evaluated as executable content.
- Related: app.scope.indesign.004, app.scope.indesign.011

## Typography and language

### app.scope.indesign.009 — Typography retains only a subset of InDesign composition controls

- Evidence: the IDML renderer carries family class, CJK fallback, size, fill, alignment, weight,
  italic, auto-leading, indents, paragraph spacing, frame insets, fixed text columns and gutters,
  bullets, capitalization, tracking, underline, strike-through, superscript and subscript. It does
  not retain style inheritance, glyph scaling, kerning, ligatures, baseline grids,
  hyphenation/kinsoku, drop caps, paragraph rules/shading, numbering, or exact font substitution.
- Next: normalize inherited paragraph/character/object styles into a resolved typography record and
  add controls in descending visible impact, starting with list numbering, paragraph rules/shading,
  hyphenation/kinsoku and baseline shift.
- Complete when: a multilingual typography corpus renders inherited styles deterministically,
  reports every substituted or unsupported font/feature, and shows no unlabelled fallback that
  changes reading order or hides a glyph.
- Related: app.scope.indesign.004, std.gui.html.018

### app.scope.indesign.010 — CJK and complex-script fidelity depends on an optional system typeface

- Evidence: the HTML renderer requests a CJK face through Swag and falls back safely when the
  platform has none. This keeps opening dependency-free, but a minimal installation cannot promise
  the intended Japanese, Chinese, Korean, Indic, RTL, ruby, vertical, warichu, tate-chu-yoko, or
  OpenType shaping result.
- Next: choose a redistributable font/resource policy compatible with the no-external-dependency
  product rule, then add script shaping and CJK layout only where the local renderer can make its
  result stable across supported platforms.
- Complete when: the declared language corpus has deterministic bundled-or-explicitly-reported font
  coverage, ruby and vertical text have a readable supported rendering, RTL order is correct, and
  font absence never turns visible text into silent tofu.
- Related: std.truetype.003, std.gui.html.018

## Reader and inspection workflow

### app.scope.indesign.011 — InDesign text selection stops at the rendered page scene

- Evidence: each local HTML page supports pointer selection, Ctrl+A, Ctrl+C, selection paint and
  plain-text visual copy without document-supplied markup. Search switches to the rendered page,
  but no selection spans frames/pages, no story/frame locator exists, and visual versus logical copy
  order is not distinguished.
- Next: retain story run and frame coordinates through layout and expose a read-only selection model
  shared by pointer, keyboard, search and Copy.
- Complete when: selection crosses supported frames/pages in logical order, visual copy is an
  explicit alternative, copied text carries no hidden markup, search reveals the exact run, and
  unsupported/reordered text reports its limitation.
- Related: app.scope.indesign.004, app.scope.viewers.007

### app.scope.indesign.012 — Pages have no thumbnail, outline, spread, layer, or object navigator

- Evidence: the page readout has previous/next, a page menu, and bounded direct numeric navigation.
  A reader cannot scan thumbnails, document sections, masters, layers, links, stories, or
  page-size/bleed information.
- Next: define a virtualized document navigator with page thumbnails first, then outline, spreads,
  layers and object filters over stable scene identities.
- Complete when: long documents navigate without eager full-resolution rendering, each entry reveals
  its page/object, thumbnails state their source/freshness, and filters retain keyboard navigation
  and selection.
- Related: app.scope.indesign.003, app.scope.indesign.007

### app.scope.indesign.013 — Links, fonts, swatches, styles, metadata, and warnings are not inspectable

- Evidence: linked image recovery is bounded and offline, and the page summary names its count of
  missing image resources. Its resolution path, image metadata, individual missing resources, style
  inheritance, swatches, fonts, XMP, package version, page warnings and unsupported constructs have
  no application panel.
- Next: expose a read-only resource and document-facts ledger with origin, size, hash-on-demand,
  resolution result, visual bounds, style/font use, and decoder warning source links.
- Complete when: every placed resource and unsupported scene item can be located and explained;
  facts are selectable/copyable; local paths are privacy-safe by default; and no inspection action
  fetches a resource or mutates the package.
- Related: app.scope.viewers.006, app.scope.indesign.015

### app.scope.indesign.014 — Reader modes and state stop at one page, fit modes, and transient zoom

- Evidence: the viewer offers page choice, fit page, fit width, explicit zoom and page-local search.
  It has no continuous/facing/spread layout, presentation mode, page rotation, history, restore of
  page/zoom, or per-page annotations of decoding status.
- Next: separate reading layout, zoom and page identity, then add continuous pages before
  facing/spread and presentation modes.
- Complete when: all reading modes share selection/search/history, page position and zoom restore
  safely through file identity, adjacent-page cache policy is bounded, and rotation/geometry apply
  consistently where a page scene supports them.
- Related: app.scope.viewers.003, app.scope.indesign.003

### app.scope.indesign.015 — The InDesign surface has no accessibility or keyboard-complete object model

- Evidence: page navigation and zoom have keyboard actions, but page text, images, errors, missing
  links, document outline and future object selection have no semantic tree or accessible names.
- Next: map document, page, story, heading, table, image, link, warning and selection to the shared
  viewer accessibility contract before custom inspector controls multiply.
- Complete when: keyboard-only navigation reaches every reader action, the focused page/object and
  decode warning are announced meaningfully, text selection works without a pointer, and fixtures
  exercise the same semantic tree exposed to the platform bridge.
- Related: app.scope.viewers.007, platform.portability.048

## Safety, compatibility, and proof

### app.scope.indesign.016 — Linked resources can still read author-chosen absolute local paths

- Evidence: the viewer never fetches a network URL, enforces image byte/pixel budgets, and retries a
  same-folder basename when an InDesign absolute link is stale. A valid direct `file:` URI may still
  cause the renderer to inspect an arbitrary readable local image.
- Next: define a document-root capability policy with an explicit user command for broader local
  resolution, privacy-redacted diagnostics, and a test for traversal, UNC, malformed URI, oversized
  image, cyclic link and stale moved-package cases.
- Complete when: ordinary opening reads only the declared document root, no remote/UNC path is
  contacted, expansion requires a deliberate scoped choice, all resource attempts are visible, and
  missing art remains a labelled frame rather than a failed document.
- Related: app.scope.indesign.013, app.scope.viewers.011

### app.scope.indesign.017 — Malformed, encrypted, very large, and version-diverse packages lack a full defensive matrix

- Evidence: archive entry and frame counts, embedded data, linked image bytes and pixels are bounded,
  but the reader has no package-wide work/time budget, cancellation checkpoints, ZIP method matrix,
  encryption policy, central-directory consistency report, or per-version compatibility declaration.
- Next: build adversarial IDML/INDD fixtures and a failure taxonomy covering archive structure,
  compression ratio, XML depth/size, integer transforms, recursive resources, damaged previews and
  unsupported version records.
- Complete when: every bad input stops with a local, actionable category; partial safe page output is
  preserved when possible; cancellation is prompt; no limit relies on allocation failure; and no
  malformed document can stall or crash the host.
- Related: app.scope.viewers.004, app.scope.viewers.011

### app.scope.indesign.018 — The compatibility corpus does not prove viewer-grade output fidelity

- Evidence: tests include synthetic native records, CC-licensed native/IDML documents, an MIT
  editorial IDML package with real linked art, visible goldens, and a one-second interaction budget.
  They do not yet cover multiple InDesign versions, facing publications, long stories, transparency,
  tables, multilingual typography, missing assets, malformed archives, cold/warm performance, DPI,
  theme, accessibility, or visual comparison against a declared reference export.
- Next: publish the versioned public corpus, licences, expected support tier and performance hardware;
  add golden/reference comparison rules and a strict matrix for safety, latency and interaction.
- Complete when: each supported construct has an openly licensed real fixture plus a malformed
  sibling, visual and semantic tests identify the reference, performance budgets run reproducibly,
  and unsupported constructs are named in the compatibility report instead of inferred from gaps.
- Related: app.scope.indesign.001, app.scope.indesign.017, app.scope.viewers.009
