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
- Updated: 2026-09-27 18:11 — define WOFF acceptance.

Add WOFF decompression over the existing face parser using `Core`'s zlib support.

- Related: std.truetype.002

- Complete when: WOFF fonts load through Face with the same glyph outlines, names, and metrics as their reconstructed sfnt data, and malformed compression or table lengths fail in focused fixtures.

### std.truetype.002 — WOFF2 containers are rejected

- Recorded: 2026-08-05 07:43
- Updated: 2026-09-27 18:11 — define WOFF2 acceptance.

Add WOFF2 reconstruction and Brotli decompression as a separate format implementation.

- Related: std.truetype.001

- Complete when: WOFF2 fonts load through Face with glyph outlines, names, and metrics matching reference sfnt reconstruction, and truncated Brotli data or invalid transforms fail cleanly.

### std.truetype.003 — No GSUB single-substitution processing

- Recorded: 2026-08-07 18:19
- Updated: 2026-09-27 18:11 — define GSUB single-substitution acceptance.
- `GPOS` is read for pair adjustment only and there is no `GSUB` processing. Implement
  single-substitution lookups first, with unsupported lookup kinds reported or documented.
- What the kerning work already provides: `src/gpos.swg` has coverage tables in both formats, class
  definitions in both formats, value-record decoding, and extension-lookup resolution. Every one of
  those is needed by the rest of `GPOS` and by `GSUB`, so shaping starts from the lookup navigation
  rather than from the bytes.
- Related: std.truetype.008, std.truetype.004, std.truetype.005, std.truetype.006, std.truetype.007

- Complete when: A font fixture applies single-substitution lookups through the shaping API with the expected glyph IDs and clusters, while unsupported lookup kinds have an explicit result.

### std.truetype.004 — No GSUB multiple-substitution processing

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-27 18:11 — define GSUB multiple-substitution acceptance.

Implement multiple-substitution lookups independently of the single-substitution path.

- Related: std.truetype.003

- Complete when: A multiple-substitution fixture expands one glyph into the expected sequence without losing source-cluster mapping, independently of single-substitution tests.

### std.truetype.005 — No GSUB alternate-substitution processing

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-27 18:11 — define GSUB alternate-selection acceptance.

Implement alternate selection with an explicit feature/user-choice contract.

- Related: std.truetype.003

- Complete when: A fixture exposes alternate glyph choices under an explicit feature or user selection, with a deterministic default and stable cluster mapping.

### std.truetype.006 — No GSUB ligature-substitution processing

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-27 18:11 — define GSUB ligature acceptance.

Implement ligature substitution for declared features such as `liga`, including cluster mapping.

- Related: std.truetype.003

- Complete when: A declared liga fixture substitutes the expected glyph for a sequence and maps the resulting ligature back to every source cluster it covers.

### std.truetype.007 — No GSUB contextual-substitution processing

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-27 18:11 — define contextual-substitution acceptance.

Implement contextual and chaining-context application over the other supported substitution
lookups.

- Related: std.truetype.003, std.truetype.004, std.truetype.005, std.truetype.006

- Complete when: Contextual and chaining lookups apply supported substitutions in font order to representative fixtures, while malformed references fail without reading outside table bounds.

### std.truetype.008 — Shaping has no decided module boundary

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-27 18:11 — define shaping-boundary decision acceptance.

Decide whether shaping stays in `truetype` or becomes a separate module above face parsing. Record
the ownership and dependency rule before the shaping API expands.

- Related: std.truetype.003, std.truetype.009, std.truetype.012

- Complete when: A recorded module decision assigns face parsing, shaping state, and Pixel consumption without a dependency cycle, and one small public shaping example compiles under that boundary.

### std.truetype.009 — Combining marks ignore GPOS attachment

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-27 18:11 — define mark-to-base acceptance.

Implement mark-to-base positioning so combining accents use the base glyph's anchors.

- Related: std.truetype.003, std.truetype.010, std.truetype.011

- Complete when: A combining-mark fixture reads GPOS base and mark anchors and places the mark at the expected coordinates rather than at the base advance.

### std.truetype.010 — No GPOS mark-to-ligature attachment

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-27 18:11 — define mark-to-ligature acceptance.

Position marks against the selected component anchors of a ligature glyph.

- Related: std.truetype.009, std.truetype.006

- Complete when: A fixture attaches marks to the selected component anchors of a ligature and preserves component and cluster identity through shaping.

### std.truetype.011 — No GPOS mark-to-mark attachment

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-27 18:11 — define mark-to-mark acceptance.

Position one combining mark relative to another independently of base and ligature attachment.

- Related: std.truetype.009

- Complete when: A fixture places a second combining mark relative to the first mark's anchor, with the expected position independent of base and ligature attachment.

### std.truetype.012 — Arabic text is not shaped

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-27 18:11 — define Arabic-shaping acceptance.

Implement Arabic joining forms, direction-aware cluster processing, and required feature
application end to end.

- Related: std.truetype.003, std.truetype.009, std.truetype.013, std.truetype.014

- Complete when: Representative Arabic text receives joining forms, direction-aware cluster order, and required features with glyph IDs and positions checked against a reference fixture.

### std.truetype.013 — Indic text is not shaped

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-27 18:11 — define Indic-script acceptance.

Implement one explicitly named Indic shaping model, reordering, conjunct formation, and required
features as its own script-support deliverable.

- Related: std.truetype.003, std.truetype.009

- Complete when: One explicitly named Indic script has tested reordering, conjunct formation, required features, and source-cluster mapping against reference shaping output.

### std.truetype.014 — Thai marks are not shaped

- Recorded: 2026-08-05 07:43
- Updated: 2026-09-27 18:11 — define Thai-mark acceptance.

Implement Thai mark ordering and positioning independently of Arabic and Indic support.

- Related: std.truetype.009

- Complete when: Thai marks are ordered and positioned for representative base and stacked-mark sequences with glyph IDs and offsets checked against reference fixtures.

### std.truetype.015 — Variable fonts

- Recorded: 2026-08-05 07:43
- Updated: 2026-09-27 18:11 — define variable-font acceptance.
- No `fvar`, `gvar`, `avar` or `HVAR`. A variable font loads only at its default instance, so a
  single file that should provide a whole weight and width range provides one static face.
- Variable fonts are now the normal shipping form for large families, so this is a coverage gap
  rather than an exotic feature. CFF2 variation data is part of this entry; the CFF1 charstring
  support already in the module is only its static foundation.

- Complete when: Default and non-default instances of representative TrueType and CFF2 variable fonts produce expected outlines and metrics across supported axes, with invalid variation tables rejected.

### std.truetype.016 — No COLR/CPAL layered color glyphs

- Recorded: 2026-08-05 07:43
- Updated: 2026-09-27 18:11 — define COLR and CPAL acceptance.
- `COLR` version 0 is the cheapest useful subset: layered glyph references with a palette, which
  the existing outline pipeline can already draw.
- The `cmap` format-14 subtable is read, so `Face.glyphIndexVariant` already resolves the emoji and
  text presentation selectors. What is missing is a glyph to draw for the emoji one.
- Related: std.truetype.017, std.truetype.018, std.truetype.019

- Complete when: A COLR version-0 fixture paints the expected ordered glyph layers in the selected CPAL palette, including text and emoji presentation selection.

### std.truetype.017 — No `sbix` color bitmap strikes

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-27 18:11 — define sbix-strike acceptance.

Decode and select `sbix` strikes independently of layered COLR glyphs.

- Related: std.truetype.016, std.truetype.018

- Complete when: A fixture selects the documented sbix bitmap strike for requested pixel sizes, decodes its image, and falls back predictably when no usable strike exists.

### std.truetype.018 — No CBDT/CBLC color bitmap strikes

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-27 18:11 — define CBDT and CBLC acceptance.

Decode and select CBDT/CBLC strikes independently of Apple's `sbix` container.

- Related: std.truetype.016, std.truetype.017

- Complete when: A fixture selects and decodes the expected CBDT/CBLC color strike across requested sizes, including a malformed-table failure case.

### std.truetype.019 — No SVG glyph table

- Recorded: 2026-08-05 07:43
- Updated: 2026-09-27 18:11 — define SVG-glyph acceptance.

Parse and render the OpenType SVG table through Pixel's SVG support, with explicit recursion and
resource limits.

- Related: std.truetype.016, std.pixel.image.008

- Complete when: An OpenType SVG glyph renders through Pixel with the expected bounds and colors, while external resources, recursive references, and oversized data are bounded or rejected.

### std.truetype.020 — Vertical writing

- Recorded: 2026-08-05 07:43
- Updated: 2026-09-27 18:11 — define vertical-metrics acceptance.
- No `vhea` or `vmtx`. Vertical CJK layout has no metrics to work from.
- Small and well-bounded: the two tables mirror `hhea` and `hmtx`, which `parseFace` and
  `buildGlyphMetrics` already read, run-length compression included.

- Complete when: Vertical fonts expose vhea/vmtx advances and bearings for short and long metric runs, and a vertical CJK fixture uses those values rather than horizontal metrics.

### std.truetype.021 — TrueType bytecode hinting

- Recorded: 2026-08-05 07:43
- Updated: 2026-09-27 18:11 — define TrueType-hinting acceptance.
- `Face.hintVertical` is a vertical hinting heuristic, not the TrueType interpreter — `fpgm`,
  `prep` and `cvt ` are not executed.
- Deliberately last. At the display densities this renderer targets, and with the DPI awareness
  the GUI now has, full bytecode hinting buys progressively less, and it is a large and fiddly
  piece of work. FreeType's own autohinter exists precisely because the interpreter is not always
  the right answer.

- Complete when: A bounded TrueType bytecode interpreter executes fpgm, prep, and glyph instructions for representative hinted fixtures with expected pixel outlines, and malformed programs fail safely.
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
