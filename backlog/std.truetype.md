# TrueType Backlog

This backlog covers `std/truetype`, measured against the font libraries it competes with:
FreeType, stb_truetype, HarfBuzz for shaping, and msdfgen for distance fields.

Evidence, investigations, and intended outcomes owned by `bin/std/modules/truetype` stay together
here. Compiler and language work belongs in [compiler.core.md](compiler.core.md) and
[language.design.md](language.design.md). [README.md](README.md) has the whole layout.

Entries are ordered from the most recently updated down. An entry disappears when it
ships; history lives in git, not here.

## Where the module already stands

Twelve TrueType tables parsed — `cmap`, `glyf`, `GPOS`, `head`, `hhea`, `hmtx`, `loca`, `maxp`,
`name`, `post`, `kern`, `OS/2` — plus the `ttcf` collection header, OpenType and bare CFF programs,
and Type 1 programs. The outline path handles quadratic `glyf` contours and cubic Type 1/Type 2
charstrings, composite glyphs, matrix transforms, grayscale rasterization, vertical hinting, and
both single- and multi-channel signed distance fields. Character map formats 0, 4, 6, 12 and 13
are binary-searched, with format 14 for variation sequences. Kerning comes from the `GPOS` `kern`
feature, with the legacy `kern` table as fallback. A `Face`/`GlyphSlot` model mirrors FreeType
closely enough to be familiar on sight, with tests covering collections, charstrings, composites,
hinting, kerning, lifecycle, outlines, parsing and rendering.

A collection is also searchable without being loaded: `Face.familyNameAt` reads one member's offset
table and `name` table and nothing else, so finding one face of `msgothic.ttc` costs a name lookup
rather than nine megabytes per candidate. That is what `pixel` selects a system face with.

MSDF generation and grayscale rasterization both live in the module. Their current implementations
are covered by the distance-field and rendering tests; performance comparisons require a dated,
reproducible workload rather than a general ranking against other font libraries.

The gaps are about coverage: which fonts load at all, and whether text is positioned correctly.

## Entries

### std.truetype.001 — WOFF containers are rejected

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules

Add WOFF decompression over the existing face parser using `Core`'s zlib support.

- Related: std.truetype.002

### std.truetype.002 — WOFF2 containers are rejected

- Recorded: 2026-08-05 07:43
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules

Add WOFF2 reconstruction and Brotli decompression as a separate format implementation.

- Related: std.truetype.001

### std.truetype.003 — No GSUB single-substitution processing

- Recorded: 2026-08-07 18:19
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- `GPOS` is read for pair adjustment only and there is no `GSUB` processing. Implement
  single-substitution lookups first, with unsupported lookup kinds reported or documented.
- What the kerning work already provides: `src/gpos.swg` has coverage tables in both formats, class
  definitions in both formats, value-record decoding, and extension-lookup resolution. Every one of
  those is needed by the rest of `GPOS` and by `GSUB`, so shaping starts from the lookup navigation
  rather than from the bytes.
- Related: std.truetype.008, std.truetype.004, std.truetype.005, std.truetype.006, std.truetype.007

### std.truetype.004 — No GSUB multiple-substitution processing

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules

Implement multiple-substitution lookups independently of the single-substitution path.

- Related: std.truetype.003

### std.truetype.005 — No GSUB alternate-substitution processing

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules

Implement alternate selection with an explicit feature/user-choice contract.

- Related: std.truetype.003

### std.truetype.006 — No GSUB ligature-substitution processing

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules

Implement ligature substitution for declared features such as `liga`, including cluster mapping.

- Related: std.truetype.003

### std.truetype.007 — No GSUB contextual-substitution processing

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules

Implement contextual and chaining-context application over the other supported substitution
lookups.

- Related: std.truetype.003, std.truetype.004, std.truetype.005, std.truetype.006

### std.truetype.008 — Shaping has no decided module boundary

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules

Decide whether shaping stays in `truetype` or becomes a separate module above face parsing. Record
the ownership and dependency rule before the shaping API expands.

- Related: std.truetype.003, std.truetype.009, std.truetype.012

### std.truetype.009 — Combining marks ignore GPOS attachment

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules

Implement mark-to-base positioning so combining accents use the base glyph's anchors.

- Related: std.truetype.003, std.truetype.010, std.truetype.011

### std.truetype.010 — No GPOS mark-to-ligature attachment

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules

Position marks against the selected component anchors of a ligature glyph.

- Related: std.truetype.009, std.truetype.006

### std.truetype.011 — No GPOS mark-to-mark attachment

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules

Position one combining mark relative to another independently of base and ligature attachment.

- Related: std.truetype.009

### std.truetype.012 — Arabic text is not shaped

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules

Implement Arabic joining forms, direction-aware cluster processing, and required feature
application end to end.

- Related: std.truetype.003, std.truetype.009, std.truetype.013, std.truetype.014

### std.truetype.013 — Indic text is not shaped

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules

Implement one explicitly named Indic shaping model, reordering, conjunct formation, and required
features as its own script-support deliverable.

- Related: std.truetype.003, std.truetype.009

### std.truetype.014 — Thai marks are not shaped

- Recorded: 2026-08-05 07:43
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules

Implement Thai mark ordering and positioning independently of Arabic and Indic support.

- Related: std.truetype.009

### std.truetype.015 — Variable fonts

- Recorded: 2026-08-05 07:43
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- No `fvar`, `gvar`, `avar` or `HVAR`. A variable font loads only at its default instance, so a
  single file that should provide a whole weight and width range provides one static face.
- Variable fonts are now the normal shipping form for large families, so this is a coverage gap
  rather than an exotic feature. CFF2 variation data is part of this entry; the CFF1 charstring
  support already in the module is only its static foundation.

### std.truetype.016 — No COLR/CPAL layered color glyphs

- Recorded: 2026-08-05 07:43
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- `COLR` version 0 is the cheapest useful subset: layered glyph references with a palette, which
  the existing outline pipeline can already draw.
- The `cmap` format-14 subtable is read, so `Face.glyphIndexVariant` already resolves the emoji and
  text presentation selectors. What is missing is a glyph to draw for the emoji one.
- Related: std.truetype.017, std.truetype.018, std.truetype.019

### std.truetype.017 — No `sbix` color bitmap strikes

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules

Decode and select `sbix` strikes independently of layered COLR glyphs.

- Related: std.truetype.016, std.truetype.018

### std.truetype.018 — No CBDT/CBLC color bitmap strikes

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules

Decode and select CBDT/CBLC strikes independently of Apple's `sbix` container.

- Related: std.truetype.016, std.truetype.017

### std.truetype.019 — No SVG glyph table

- Recorded: 2026-08-05 07:43
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules

Parse and render the OpenType SVG table through Pixel's SVG support, with explicit recursion and
resource limits.

- Related: std.truetype.016, std.pixel.image.008

### std.truetype.020 — Vertical writing

- Recorded: 2026-08-05 07:43
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- No `vhea` or `vmtx`. Vertical CJK layout has no metrics to work from.
- Small and well-bounded: the two tables mirror `hhea` and `hmtx`, which `parseFace` and
  `buildGlyphMetrics` already read, run-length compression included.

### std.truetype.021 — TrueType bytecode hinting

- Recorded: 2026-08-05 07:43
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- `Face.hintVertical` is a vertical hinting heuristic, not the TrueType interpreter — `fpgm`,
  `prep` and `cvt ` are not executed.
- Deliberately last. At the display densities this renderer targets, and with the DPI awareness
  the GUI now has, full bytecode hinting buys progressively less, and it is a large and fiddly
  piece of work. FreeType's own autohinter exists precisely because the interpreter is not always
  the right answer.

---

## Out of scope

**Font file authoring.** Writing, subsetting, or editing font files is a different problem from
reading them. The current PDF writer uses standard faces; future PDF font embedding and
subsetting belongs to [std.gui.pdf.019](std.gui.pdf.md), which must settle its writer dependency
before extending this reader module.

**A system font database.** Enumerating installed fonts, resolving a family name to a file, and
walking a fallback chain when a glyph is missing belong above this module. `pixel` now owns
scalar fallback, coverage policy, and per-glyph rendering in `src/text/font.swg`; its Windows
backend only discovers installed fonts and retrieves their bytes. Cluster selection remains in
[std.pixel.028](std.pixel.md#stdpixel028--fallback-selection-does-not-yet-preserve-shaping-clusters).
Keep this module about the bytes of one face.
