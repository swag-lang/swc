# Swag Scope Font Viewer Backlog

The Font viewer already loads a file face, shows family/style/glyph count/units per em, renders an
editable specimen at several pixel sizes, and pages through mapped Unicode characters. This
backlog owns professional font inspection; shaping, font-format, hinting, and color-glyph engine work
remains in [std.truetype.md](std.truetype.md).

### app.scope.font.007 — OpenType shaping features, script, and language cannot be inspected

- Evidence: editable sample text draws the loaded face through the ordinary Pixel font path.
  There is no script/language/
  direction choice, GSUB/GPOS feature list, per-feature toggle, glyph-run trace, or before/after
  comparison; the engine gaps are tracked in `std.truetype.md`.
- Next: define a viewer shaping trace and control surface that can expose supported features as the
  shaping engine gains them, beginning with current kerning/ligature behavior.
- Done when: chosen script, language, direction, features, glyph IDs, clusters, advances, and
  positioning are visible; toggles update the specimen; unsupported tables/features say so; and
  original text-to-glyph mapping remains inspectable.
- Related: std.truetype.003, std.truetype.009, std.truetype.008

### app.scope.font.002 — The character map cannot search glyph names, IDs, blocks or scripts

- Evidence: navigation pages 192 mapped Unicode scalars with previous/next, and the clickable range
  readout jumps to several common Unicode blocks. A character typed into the lens, its `U+` code
  point, or a `#`-prefixed decimal/hex glyph ID shows the matching map cell selected. Glyph IDs use
  a bounded inverse cmap built with the page index; the first mapped Unicode alias is shown.
  Unmapped glyph IDs and IDs outside the face have distinct disabled explanations. Exact post/CFF
  glyph-name lookup now resolves a mapped glyph through the worker-built inverse cmap. A bounded
  back/forward history covers character, glyph-ID, glyph-name, block and range-menu jumps. Block
  and script names are not yet query destinations.
- Progress: character, glyph-ID, exact glyph-name and block-menu jumps return through the map's
  bounded history; post/CFF names are indexed once during font loading. Unicode script queries and
  queryable Unicode block names remain open.
- Next: make Unicode block and script queries select the first mapped cell in that range. Use
  generated Unicode property data rather than maintaining a hand-written script table.
- Done when: glyph-name, Unicode-block and script queries reveal a cell, and map jumps have
  bounded back/forward history.

### app.scope.font.003 — Unicode coverage and missing-glyph analysis are absent

- Evidence: the current map displays only characters the face maps. The loading worker counts
  once the characters the face maps in each block the map jumps to (Basic Latin, Latin-1
  Supplement, Greek and Coptic, Cyrillic, General Punctuation and Symbols); the information sheet
  gives those counts, and the lens and the range menu offer a block the face maps nothing of
  disabled. Other scripts, code pages, variation sequences,
  supplementary planes, symbol mappings, and holes in a requested repertoire are not summarized.
- Next: calculate coverage from cmap subtables against Unicode block/script data and user-supplied
  sample text or ranges.
- Done when: coverage counts identify cmap/subtable provenance, mapped aliases and variation
  selectors are visible, missing characters in pasted text can be listed, and large CJK coverage is
  virtualized.

### app.scope.font.004 — Font names, legal metadata, and embedding permissions are hidden

- Evidence: the information sheet gives family, style, units per em, the version, designer
  and copyright notice the face declares, its OS/2 weight class with the name of the nearest
  hundred, and its `fsType` embedding permissions named as the specification names them
  (`TrueType.FaceMetadata.embedding`). Full/PostScript/unique names, vendor, licence, description,
  dates, PANOSE, width/classification, localized name records and supported tables are absent.
- Next: expose original localized name records and normalized technical/legal properties through a
  read-only information panel.
- Done when: all name records retain platform/language IDs, permissions are explained without
  legal inference, table inventory has offset/size/checksum status, values can be copied, and damaged
  metadata produces findings instead of aborting the specimen.
- Related: app.scope.viewers.006

### app.scope.font.005 — A glyph cell has no detail inspector

- Evidence: each cell paints a glyph and `U+` label. A click on a cell marks its character, as the
  lens's Show command does; the information sheet then gives its code point and glyph index, and
  the lens copies it. There is no keyboard selection, and glyph name, advance, bearings, bounding
  box, contours/points, components, instructions, anchors, color layers and substitutions cannot be
  inspected.
- Next: make map cells selectable and expose available outline/metric/mapping facts in a side panel,
  with unsupported table families explicitly labelled.
- Done when: keyboard selection reports glyph identity; available mappings, advance/bearings,
  ink/control bounds, contour/component summary, hinting presence, and source table records are
  inspectable; related glyphs and components are navigable.

### app.scope.font.006 — Font metrics cannot be visualized on the specimen or glyph

- Evidence: specimen text is rendered without baseline, ascent/descent, line gap, em square, advance,
  bearings, bounding boxes, kerning deltas, or pixel-grid overlays.
- Next: add optional typography guides to specimen and selected glyph views using exact face metrics.
- Done when: font versus typographic/Windows metrics are distinguished, baseline and advances
  align with rendered output, pixel grid and hinted/unhinted outlines can be compared where
  available, and overlays scale correctly at every sample size.

### app.scope.font.008 — Variable-font axes and named instances cannot be explored

- Evidence: std.truetype.015 records that the font engine lacks variable fonts, while the viewer has no axis
  sliders, ranges/defaults, named instances, STAT/avar information, or comparison at two locations.
- Next: specify the axis/instance viewer model and connect it when std.truetype.015 exposes variation-aware
  faces and glyph metrics.
- Done when: axes show tag/name/min/default/max/current values, named instances select exact
  coordinates, specimen/map/metrics update together, out-of-range input is rejected, and two
  instances can be compared.
- Related: std.truetype.015

### app.scope.font.009 — Color, bitmap, SVG, and vertical glyph capabilities have no viewer modes

- Evidence: std.truetype.016/std.truetype.017/std.truetype.018/std.truetype.019 track remaining
  font-engine features; vertical metrics are available. The viewer cannot identify which glyphs
  use COLR/CPAL, bitmap strikes, SVG, or vertical metrics, select palettes or
  strikes, or compare fallback outline rendering.
- Next: reserve explicit glyph-source and writing-mode controls, then connect each engine capability
  without silently flattening it into the default monochrome horizontal view.
- Done when: available source layers/strikes/palettes are listed, vertical specimen and metrics
  are correct, fallback is labelled, and the glyph inspector links to underlying tables.
- Related: std.truetype.016, std.truetype.017, std.truetype.018, std.truetype.019

### app.scope.font.010 — Make specimen presets and size controls configurable

- Evidence: the sample text is editable, but specimen sizes are compiled constants and there are no
  multilingual presets, paragraph/waterfall/glyph modes, point-versus-pixel/DPI choice, line-height,
  letter-spacing, background/foreground, or compare string.
- Next: make specimen layout a reusable profile with direct size entry and curated script/test
  presets that do not assume the font covers them.
- Done when: sizes and units are editable, waterfall/paragraph/single-glyph modes exist,
  direction and basic spacing controls are explicit, missing characters are marked, profiles reset,
  and app.scope.viewers.003 can persist safe preferences.

### app.scope.font.011 — Font structural problems are not collected as actionable findings

- Evidence: open either succeeds or returns one failure reason. Table checksums, overlapping/out-of-
  bounds records, inconsistent metrics, broken cmap mappings, invalid glyph contours/components,
  naming conflicts, and suspicious embedding flags are not summarized while valid content remains
  viewable.
- Next: add a severity-based validation report from loader recovery points and cross-table checks,
  with byte-range links into Binary/Hex.
- Done when: partial fonts show every safe face/glyph plus findings, checks state their scope,
  each finding identifies table/record/byte range, and clean files list the validation profile used.
- Related: app.scope.hexa.002, app.scope.binary.006

### app.scope.font.012 — Glyphs and specimens cannot be copied or exported with provenance

- Evidence: the viewer offers no Copy Character/Glyph Name/Outline, Copy Specimen Image, export SVG,
  or coverage report. A user cannot distinguish a Unicode character from a particular font glyph in
  clipboard output.
  [File Viewer Plus 7](https://fileviewerplus.com/open/ttf) exports a TTF specimen as an image.
  Scope's sampler can attach face and glyph identity to the equivalent output.
- Next: add textual identity copy and rendered specimen/glyph image export first, followed by vector
  outline export only where the source can be represented faithfully.
- Done when: copied text, glyph ID/name, Unicode mappings, raster output, optional outline, and
  coverage report state face index, variation coordinates, size, features, palette, and conversion;
  restricted embedding is surfaced before exporting font-derived data.
- Related: app.scope.font.003
