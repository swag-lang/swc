# TrueType Backlog

This backlog covers `std/truetype`, measured against the font libraries it competes with:
FreeType, stb_truetype, HarfBuzz for shaping, and msdfgen for distance fields.

Evidence, investigations, and intended outcomes owned by `bin/std/modules/truetype` stay together
here. Compiler and language work belongs in [compiler.core.md](compiler.core.md) and
[language.design.md](language.design.md). [README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
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

Two things stand out as genuinely ahead of the field. MSDF generation lives in the module rather
than in a separate project, which is what GPU text actually wants — FreeType ships SDF but not
MSDF, and msdfgen is a distinct dependency everywhere else. And the rasterizer is fast; the
current implementation replaced one that was roughly sixteen times slower.

The gaps are about coverage: which fonts load at all, and whether text is positioned correctly.

---

## Tier A — Font containers and outlines

### font.truetype.001 — WOFF containers are rejected

Add WOFF decompression over the existing face parser using `Core`'s zlib support.

- Related: font.truetype.002

### font.truetype.002 — WOFF2 containers are rejected

Add WOFF2 reconstruction and Brotli decompression as a separate format implementation.

- Related: font.truetype.001

---

## Tier B — Glyph substitution

### font.truetype.003 — No GSUB single-substitution processing

- `GPOS` is read for pair adjustment only and there is no `GSUB` processing. Implement
  single-substitution lookups first, with unsupported lookup kinds reported or documented.
- What the kerning work already provides: `src/gpos.swg` has coverage tables in both formats, class
  definitions in both formats, value-record decoding, and extension-lookup resolution. Every one of
  those is needed by the rest of `GPOS` and by `GSUB`, so shaping starts from the lookup navigation
  rather than from the bytes.
- Related: font.truetype.008, font.truetype.004, font.truetype.005, font.truetype.006, font.truetype.007

### font.truetype.004 — No GSUB multiple-substitution processing

Implement multiple-substitution lookups independently of the single-substitution path.

- Related: font.truetype.003

### font.truetype.005 — No GSUB alternate-substitution processing

Implement alternate selection with an explicit feature/user-choice contract.

- Related: font.truetype.003

### font.truetype.006 — No GSUB ligature-substitution processing

Implement ligature substitution for declared features such as `liga`, including cluster mapping.

- Related: font.truetype.003

### font.truetype.007 — No GSUB contextual-substitution processing

Implement contextual and chaining-context application over the other supported substitution
lookups.

- Related: font.truetype.003, font.truetype.004, font.truetype.005, font.truetype.006

### font.truetype.008 — Shaping has no decided module boundary

Decide whether shaping stays in `truetype` or becomes a separate module above face parsing. Record
the ownership and dependency rule before the shaping API expands.

- Related: font.truetype.003, font.truetype.009, font.truetype.012

## Tier B — Mark positioning

### font.truetype.009 — Combining marks ignore GPOS attachment

Implement mark-to-base positioning so combining accents use the base glyph's anchors.

- Related: font.truetype.003, font.truetype.010, font.truetype.011

### font.truetype.010 — No GPOS mark-to-ligature attachment

Position marks against the selected component anchors of a ligature glyph.

- Related: font.truetype.009, font.truetype.006

### font.truetype.011 — No GPOS mark-to-mark attachment

Position one combining mark relative to another independently of base and ligature attachment.

- Related: font.truetype.009

## Tier B — Script shaping

### font.truetype.012 — Arabic text is not shaped

Implement Arabic joining forms, direction-aware cluster processing, and required feature
application end to end.

- Related: font.truetype.003, font.truetype.009, font.truetype.013, font.truetype.014

### font.truetype.013 — Indic text is not shaped

Implement one explicitly named Indic shaping model, reordering, conjunct formation, and required
features as its own script-support deliverable.

- Related: font.truetype.003, font.truetype.009

### font.truetype.014 — Thai marks are not shaped

Implement Thai mark ordering and positioning independently of Arabic and Indic support.

- Related: font.truetype.009

---

## Tier C — Variable and color fonts

### font.truetype.015 — Variable fonts

- No `fvar`, `gvar`, `avar` or `HVAR`. A variable font loads only at its default instance, so a
  single file that should provide a whole weight and width range provides one static face.
- Variable fonts are now the normal shipping form for large families, so this is a coverage gap
  rather than an exotic feature. CFF2 variation data is part of this entry; the CFF1 charstring
  support already in the module is only its static foundation.

### font.truetype.016 — No COLR/CPAL layered color glyphs

- `COLR` version 0 is the cheapest useful subset: layered glyph references with a palette, which
  the existing outline pipeline can already draw.
- The `cmap` format-14 subtable is read, so `Face.glyphIndexVariant` already resolves the emoji and
  text presentation selectors. What is missing is a glyph to draw for the emoji one.
- Related: font.truetype.017, font.truetype.018, font.truetype.019

### font.truetype.017 — No `sbix` color bitmap strikes

Decode and select `sbix` strikes independently of layered COLR glyphs.

- Related: font.truetype.016, font.truetype.018

### font.truetype.018 — No CBDT/CBLC color bitmap strikes

Decode and select CBDT/CBLC strikes independently of Apple's `sbix` container.

- Related: font.truetype.016, font.truetype.017

### font.truetype.019 — No SVG glyph table

Parse and render the OpenType SVG table through Pixel's SVG support, with explicit recursion and
resource limits.

- Related: font.truetype.016, pixel.image.008

## Tier C — Writing direction and hinting

### font.truetype.020 — Vertical writing

- No `vhea` or `vmtx`. Vertical CJK layout has no metrics to work from.
- Small and well-bounded: the two tables mirror `hhea` and `hmtx`, which `parseFace` and
  `buildGlyphMetrics` already read, run-length compression included.

### font.truetype.021 — TrueType bytecode hinting

- `Face.hintVertical` is a vertical hinting heuristic, not the TrueType interpreter — `fpgm`,
  `prep` and `cvt ` are not executed.
- Deliberately last. At the display densities this renderer targets, and with the DPI awareness
  the GUI now has, full bytecode hinting buys progressively less, and it is a large and fiddly
  piece of work. FreeType's own autohinter exists precisely because the interpreter is not always
  the right answer.

---

## Out of scope

**Font file authoring.** Writing, subsetting, or editing font files is a different problem from
reading them, and nothing in this repository needs it.

**A system font database.** Enumerating installed fonts, resolving a family name to a file, and
walking a fallback chain when a glyph is missing are all real needs, but they belong above this
module — `pixel` already owns the platform side of that in `src/text/typeface.win32.swg`. Keep
this module about the bytes of one face.
