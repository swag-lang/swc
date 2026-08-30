# Swag Scope Font Viewer Backlog

The Font viewer already loads a file face, shows family/style/glyph count/units per em, renders an
editable specimen at several pixel sizes, and pages through mapped Unicode characters. This
backlog owns professional font inspection; shaping, font-format, hinting, and color-glyph engine work
remains in [font.truetype.md](font.truetype.md).

## Faces and coverage

### scope.font.001 — Font collections expose only their first face

- Evidence: `Face.countFaces` appears in the summary, but `Face.load(bytes)` selects one face and
  the viewer has no collection face list, family/style grouping, preview, or stable face identity.
- Next: extend the font loader/viewer boundary with indexed face loading and add a searchable face
  selector that replaces the specimen without reopening bytes.
- Complete when: every TTC/OTC face is named and selectable, duplicate/localized names remain
  distinguishable, switching releases old resources, selected face persists safely, and malformed
  faces do not hide valid siblings.

### scope.font.002 — The character map cannot search or jump to a glyph

- Evidence: navigation pages 192 mapped Unicode scalars with previous/next. There is no Go To by
  Unicode, character, glyph name, glyph ID, range/block/script, or text search.
- Next: build a bounded searchable cmap/glyph index and turn the range label into a Go To control.
- Complete when: `U+`, literal character, decimal/hex glyph ID, glyph name, Unicode block, and script
  queries reveal a cell; unmapped versus absent results are distinguished; and back/forward works.

### scope.font.003 — Unicode coverage and missing-glyph analysis are absent

- Evidence: the current map displays only characters the face maps. It does not summarize scripts,
  blocks, code pages, variation sequences, supplementary planes, symbol mappings, or holes in a
  requested repertoire.
- Next: calculate coverage from cmap subtables against Unicode block/script data and user-supplied
  sample text or ranges.
- Complete when: coverage counts identify cmap/subtable provenance, mapped aliases and variation
  selectors are visible, missing characters in pasted text can be listed, and large CJK coverage is
  virtualized.

### scope.font.004 — Font names, legal metadata, and embedding permissions are hidden

- Evidence: only family and style reach the document. Full/PostScript/unique/version names,
  copyright, designer/vendor, licence, description, dates, PANOSE, weight/width/classification,
  fsType embedding restrictions, and supported tables are absent.
- Next: expose original localized name records and normalized technical/legal properties through a
  read-only information panel.
- Complete when: all name records retain platform/language IDs, permissions are explained without
  legal inference, table inventory has offset/size/checksum status, values can be copied, and damaged
  metadata produces findings instead of aborting the specimen.
- Related: scope.viewers.006

## Glyph and typography inspection

### scope.font.005 — A glyph cell has no detail inspector

- Evidence: each cell paints a glyph and `U+` label only. Glyph ID/name, advance, bearings, bounding
  box, contours/points, components, instructions, anchors, color layers, substitutions, and mapped
  Unicode values cannot be inspected.
- Next: make map cells selectable and expose available outline/metric/mapping facts in a side panel,
  with unsupported table families explicitly labelled.
- Complete when: pointer and keyboard selection report glyph identity, mappings, advance/bearings,
  ink/control bounds, contour/component summary, hinting presence, and source table records; related
  glyphs and components are navigable.

### scope.font.006 — Font metrics cannot be visualized on the specimen or glyph

- Evidence: specimen text is rendered without baseline, ascent/descent, line gap, em square, advance,
  bearings, bounding boxes, kerning deltas, or pixel-grid overlays.
- Next: add optional typography guides to specimen and selected glyph views using exact face metrics.
- Complete when: font versus typographic/Windows metrics are distinguished, baseline and advances
  align with rendered output, pixel grid and hinted/unhinted outlines can be compared where
  available, and overlays scale correctly at every sample size.

### scope.font.007 — OpenType shaping features, script, and language cannot be inspected

- Evidence: editable sample text uses the default GUI font path only. There is no script/language/
  direction choice, GSUB/GPOS feature list, per-feature toggle, glyph-run trace, or before/after
  comparison; the engine gaps are tracked in `font.truetype.md`.
- Next: define a viewer shaping trace and control surface that can expose supported features as the
  shaping engine gains them, beginning with current kerning/ligature behavior.
- Complete when: chosen script, language, direction, features, glyph IDs, clusters, advances, and
  positioning are visible; toggles update the specimen; unsupported tables/features say so; and
  original text-to-glyph mapping remains inspectable.
- Related: font.truetype.003, font.truetype.009, font.truetype.008

### scope.font.008 — Variable-font axes and named instances cannot be explored

- Evidence: font.truetype.015 records that the font engine lacks variable fonts, while the viewer has no axis
  sliders, ranges/defaults, named instances, STAT/avar information, or comparison at two locations.
- Next: specify the axis/instance viewer model and connect it when font.truetype.015 exposes variation-aware
  faces and glyph metrics.
- Complete when: axes show tag/name/min/default/max/current values, named instances select exact
  coordinates, specimen/map/metrics update together, out-of-range input is rejected, and two
  instances can be compared.
- Related: font.truetype.015

### scope.font.009 — Color, bitmap, SVG, and vertical glyph capabilities have no viewer modes

- Evidence: font.truetype.016/font.truetype.017/font.truetype.018/font.truetype.019/font.truetype.020 track missing font-engine features. The viewer cannot
  identify which glyphs use COLR/CPAL, bitmap strikes, SVG, or vertical metrics, select palettes or
  strikes, or compare fallback outline rendering.
- Next: reserve explicit glyph-source and writing-mode controls, then connect each engine capability
  without silently flattening it into the default monochrome horizontal view.
- Complete when: available source layers/strikes/palettes are listed, vertical specimen and metrics
  are correct, fallback is labelled, and the glyph inspector links to underlying tables.
- Related: font.truetype.016, font.truetype.020, font.truetype.017, font.truetype.018, font.truetype.019

### scope.font.010 — Specimen presets and size controls are fixed

- Evidence: the sample text is editable, but specimen sizes are compiled constants and there are no
  multilingual presets, paragraph/waterfall/glyph modes, point-versus-pixel/DPI choice, line-height,
  letter-spacing, background/foreground, or compare string.
- Next: make specimen layout a reusable profile with direct size entry and curated script/test
  presets that do not assume the font covers them.
- Complete when: sizes and units are editable, waterfall/paragraph/single-glyph modes exist,
  direction and basic spacing controls are explicit, missing characters are marked, profiles reset,
  and scope.viewers.003 can persist safe preferences.

## Validation and interchange

### scope.font.011 — Font structural problems are not collected as actionable findings

- Evidence: open either succeeds or returns one failure reason. Table checksums, overlapping/out-of-
  bounds records, inconsistent metrics, broken cmap mappings, invalid glyph contours/components,
  naming conflicts, and suspicious embedding flags are not summarized while valid content remains
  viewable.
- Next: add a severity-based validation report from loader recovery points and cross-table checks,
  with byte-range links into Binary/Hex.
- Complete when: partial fonts show every safe face/glyph plus findings, checks state their scope,
  each finding identifies table/record/byte range, and clean files list the validation profile used.
- Related: scope.hexa.002, scope.binary.006

### scope.font.012 — Glyphs and specimens cannot be copied or exported with provenance

- Evidence: the viewer offers no Copy Character/Glyph Name/Outline, Copy Specimen Image, export SVG,
  or coverage report. A user cannot distinguish a Unicode character from a particular font glyph in
  clipboard output.
- Next: add textual identity copy and rendered specimen/glyph image export first, followed by vector
  outline export only where the source can be represented faithfully.
- Complete when: copied text, glyph ID/name, Unicode mappings, raster output, optional outline, and
  coverage report state face index, variation coordinates, size, features, palette, and conversion;
  restricted embedding is surfaced before exporting font-derived data.
