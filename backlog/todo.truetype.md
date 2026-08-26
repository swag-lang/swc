# TrueType Roadmap

This file is the roadmap for `std/truetype`, measured against the font libraries it competes with:
FreeType, stb_truetype, HarfBuzz for shaping, and msdfgen for distance fields.

It is not the repository's discovery backlog. Cross-cutting leads and defects belong in the
`findings.*` files, which hold evidence; compiler and language intent belongs in
[todo.compiler.md](todo.compiler.md) and [todo.language.md](todo.language.md). This file holds
intent about `bin/std/modules/truetype`. [README.md](README.md) has the whole layout.

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

### T-177 — WOFF containers are rejected

Add WOFF decompression over the existing face parser using `Core`'s zlib support.

- Related: T-178

### T-178 — WOFF2 containers are rejected

Add WOFF2 reconstruction and Brotli decompression as a separate format implementation.

- Related: T-177

---

## Tier B — Glyph substitution

### T-069 — No GSUB single-substitution processing

- `GPOS` is read for pair adjustment only and there is no `GSUB` processing. Implement
  single-substitution lookups first, with unsupported lookup kinds reported or documented.
- What the kerning work already provides: `src/gpos.swg` has coverage tables in both formats, class
  definitions in both formats, value-record decoding, and extension-lookup resolution. Every one of
  those is needed by the rest of `GPOS` and by `GSUB`, so shaping starts from the lookup navigation
  rather than from the bytes.
- Related: T-181, T-345, T-346, T-347, T-348

### T-345 — No GSUB multiple-substitution processing

Implement multiple-substitution lookups independently of the single-substitution path.

- Related: T-069

### T-346 — No GSUB alternate-substitution processing

Implement alternate selection with an explicit feature/user-choice contract.

- Related: T-069

### T-347 — No GSUB ligature-substitution processing

Implement ligature substitution for declared features such as `liga`, including cluster mapping.

- Related: T-069

### T-348 — No GSUB contextual-substitution processing

Implement contextual and chaining-context application over the other supported substitution
lookups.

- Related: T-069, T-345, T-346, T-347

### T-181 — Shaping has no decided module boundary

Decide whether shaping stays in `truetype` or becomes a separate module above face parsing. Record
the ownership and dependency rule before the shaping API expands.

- Related: T-069, T-179, T-180

## Tier B — Mark positioning

### T-179 — Combining marks ignore GPOS attachment

Implement mark-to-base positioning so combining accents use the base glyph's anchors.

- Related: T-069, T-349, T-350

### T-349 — No GPOS mark-to-ligature attachment

Position marks against the selected component anchors of a ligature glyph.

- Related: T-179, T-347

### T-350 — No GPOS mark-to-mark attachment

Position one combining mark relative to another independently of base and ligature attachment.

- Related: T-179

## Tier B — Script shaping

### T-180 — Arabic text is not shaped

Implement Arabic joining forms, direction-aware cluster processing, and required feature
application end to end.

- Related: T-069, T-179, T-351, T-352

### T-351 — Indic text is not shaped

Implement one explicitly named Indic shaping model, reordering, conjunct formation, and required
features as its own script-support deliverable.

- Related: T-069, T-179

### T-352 — Thai marks are not shaped

Implement Thai mark ordering and positioning independently of Arabic and Indic support.

- Related: T-179

---

## Tier C — Variable and color fonts

### T-070 — Variable fonts

- No `fvar`, `gvar`, `avar` or `HVAR`. A variable font loads only at its default instance, so a
  single file that should provide a whole weight and width range provides one static face.
- Variable fonts are now the normal shipping form for large families, so this is a coverage gap
  rather than an exotic feature. CFF2 variation data is part of this entry; the CFF1 charstring
  support already in the module is only its static foundation.

### T-071 — No COLR/CPAL layered color glyphs

- `COLR` version 0 is the cheapest useful subset: layered glyph references with a palette, which
  the existing outline pipeline can already draw.
- The `cmap` format-14 subtable is read, so `Face.glyphIndexVariant` already resolves the emoji and
  text presentation selectors. What is missing is a glyph to draw for the emoji one.
- Related: T-182, T-183, T-184

### T-182 — No `sbix` color bitmap strikes

Decode and select `sbix` strikes independently of layered COLR glyphs.

- Related: T-071, T-183

### T-183 — No CBDT/CBLC color bitmap strikes

Decode and select CBDT/CBLC strikes independently of Apple's `sbix` container.

- Related: T-071, T-182

### T-184 — No SVG glyph table

Parse and render the OpenType SVG table through Pixel's SVG support, with explicit recursion and
resource limits.

- Related: T-071, T-186

## Tier C — Writing direction and hinting

### T-072 — Vertical writing

- No `vhea` or `vmtx`. Vertical CJK layout has no metrics to work from.
- Small and well-bounded: the two tables mirror `hhea` and `hmtx`, which `parseFace` and
  `buildGlyphMetrics` already read, run-length compression included.

### T-073 — TrueType bytecode hinting

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
