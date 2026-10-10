# TrueType Backlog

This backlog covers `std/truetype`, measured against the font libraries it competes with:
FreeType, stb_truetype, HarfBuzz for shaping, and msdfgen for distance fields.

Evidence, investigations, and intended outcomes owned by `bin/std/modules/truetype` stay together
here. Compiler and language work belongs in [compiler.core.md](compiler.core.md) and
[language.design.md](language.design.md). [README.md](README.md) has the whole layout.


## Entries

### std.truetype.001 — WOFF containers are rejected


Add WOFF decompression over the existing face parser using `Core`'s zlib support.

- Related: std.truetype.002

- Done when: WOFF fonts load through Face with the same glyph outlines, names, and metrics as their reconstructed sfnt data, and malformed compression or table lengths fail in focused fixtures.

### std.truetype.002 — WOFF2 containers are rejected


Add WOFF2 reconstruction and Brotli decompression as a separate format implementation.

- Related: std.truetype.001

- Done when: WOFF2 fonts load through Face with glyph outlines, names, and metrics matching reference sfnt reconstruction, and truncated Brotli data or invalid transforms fail cleanly.

### std.truetype.003 — No GSUB single-substitution processing

- `GPOS` is read for pair adjustment only and there is no `GSUB` processing. Implement
  single-substitution lookups first, with unsupported lookup kinds reported or documented.
- What the kerning work already provides: `src/gpos.swg` has coverage tables in both formats, class
  definitions in both formats, value-record decoding, and extension-lookup resolution. Every one of
  those is needed by the rest of `GPOS` and by `GSUB`, so shaping starts from the lookup navigation
  rather than from the bytes.
- Related: std.truetype.008, std.truetype.004, std.truetype.005, std.truetype.006, std.truetype.007

- Done when: A font fixture applies single-substitution lookups through the shaping API with the expected glyph IDs and clusters, while unsupported lookup kinds have an explicit result.

### std.truetype.004 — No GSUB multiple-substitution processing


Implement multiple-substitution lookups independently of the single-substitution path.

- Related: std.truetype.003

- Done when: A multiple-substitution fixture expands one glyph into the expected sequence without losing source-cluster mapping, independently of single-substitution tests.

### std.truetype.005 — No GSUB alternate-substitution processing


Implement alternate selection with an explicit feature/user-choice contract.

- Related: std.truetype.003

- Done when: A fixture exposes alternate glyph choices under an explicit feature or user selection, with a deterministic default and stable cluster mapping.

### std.truetype.006 — No GSUB ligature-substitution processing


Implement ligature substitution for declared features such as `liga`, including cluster mapping.

- Related: std.truetype.003

- Done when: A declared liga fixture substitutes the expected glyph for a sequence and maps the resulting ligature back to every source cluster it covers.

### std.truetype.007 — No GSUB contextual-substitution processing


Implement contextual and chaining-context application over the other supported substitution
lookups.

- Related: std.truetype.003, std.truetype.004, std.truetype.005, std.truetype.006

- Done when: Contextual and chaining lookups apply supported substitutions in font order to representative fixtures, while malformed references fail without reading outside table bounds.

### std.truetype.008 — Shaping has no decided module boundary


Decide whether shaping stays in `truetype` or becomes a separate module above face parsing. Record
the ownership and dependency rule before the shaping API expands.

- Related: std.truetype.003, std.truetype.009, std.truetype.012

- Done when: A recorded module decision assigns face parsing, shaping state, and Pixel consumption without a dependency cycle, and one small public shaping example compiles under that boundary.

### std.truetype.009 — Combining marks ignore GPOS attachment


Implement mark-to-base positioning so combining accents use the base glyph's anchors.

- Related: std.truetype.003, std.truetype.010, std.truetype.011

- Done when: A combining-mark fixture reads GPOS base and mark anchors and places the mark at the expected coordinates rather than at the base advance.

### std.truetype.010 — No GPOS mark-to-ligature attachment


Position marks against the selected component anchors of a ligature glyph.

- Related: std.truetype.009, std.truetype.006

- Done when: A fixture attaches marks to the selected component anchors of a ligature and preserves component and cluster identity through shaping.

### std.truetype.011 — No GPOS mark-to-mark attachment


Position one combining mark relative to another independently of base and ligature attachment.

- Related: std.truetype.009

- Done when: A fixture places a second combining mark relative to the first mark's anchor, with the expected position independent of base and ligature attachment.

### std.truetype.012 — Arabic text is not shaped


Implement Arabic joining forms, direction-aware cluster processing, and required feature
application end to end.

- Related: std.truetype.003, std.truetype.009, std.truetype.013, std.truetype.014

- Done when: Representative Arabic text receives joining forms, direction-aware cluster order, and required features with glyph IDs and positions checked against a reference fixture.

### std.truetype.013 — Indic text is not shaped


Implement one explicitly named Indic shaping model, reordering, conjunct formation, and required
features as its own script-support deliverable.

- Related: std.truetype.003, std.truetype.009

- Done when: One explicitly named Indic script has tested reordering, conjunct formation, required features, and source-cluster mapping against reference shaping output.

### std.truetype.014 — Thai marks are not shaped


Implement Thai mark ordering and positioning independently of Arabic and Indic support.

- Related: std.truetype.009

- Done when: Thai marks are ordered and positioned for representative base and stacked-mark sequences with glyph IDs and offsets checked against reference fixtures.

### std.truetype.015 — Variable fonts

- No `fvar`, `gvar`, `avar` or `HVAR`. A variable font loads only at its default instance, so a
  single file that should provide a whole weight and width range provides one static face.
- Variable fonts are now the normal shipping form for large families, so this is a coverage gap
  rather than an exotic feature. CFF2 variation data is part of this entry; the CFF1 charstring
  support already in the module is only its static foundation.

- Done when: Default and non-default instances of representative TrueType and CFF2 variable fonts produce expected outlines and metrics across supported axes, with invalid variation tables rejected.

### std.truetype.016 — No COLR/CPAL layered color glyphs

- `COLR` version 0 is the cheapest useful subset: layered glyph references with a palette, which
  the existing outline pipeline can already draw.
- The `cmap` format-14 subtable is read, so `Face.glyphIndexVariant` already resolves the emoji and
  text presentation selectors. What is missing is a glyph to draw for the emoji one.
- Related: std.truetype.017, std.truetype.018, std.truetype.019

- Done when: A COLR version-0 fixture paints the expected ordered glyph layers in the selected CPAL palette, including text and emoji presentation selection.

### std.truetype.017 — No `sbix` color bitmap strikes


Decode and select `sbix` strikes independently of layered COLR glyphs.

- Related: std.truetype.016, std.truetype.018

- Done when: A fixture selects the documented sbix bitmap strike for requested pixel sizes, decodes its image, and falls back predictably when no usable strike exists.

### std.truetype.018 — No CBDT/CBLC color bitmap strikes


Decode and select CBDT/CBLC strikes independently of Apple's `sbix` container.

- Related: std.truetype.016, std.truetype.017

- Done when: A fixture selects and decodes the expected CBDT/CBLC color strike across requested sizes, including a malformed-table failure case.

### std.truetype.019 — No SVG glyph table


Parse and render the OpenType SVG table through Pixel's SVG support, with explicit recursion and
resource limits.

- Related: std.truetype.016, std.pixel.image.008

- Done when: An OpenType SVG glyph renders through Pixel with the expected bounds and colors, while external resources, recursive references, and oversized data are bounded or rejected.

### std.truetype.020 — Vertical writing

- No `vhea` or `vmtx`. Vertical CJK layout has no metrics to work from.
- Small and well-bounded: the two tables mirror `hhea` and `hmtx`, which `parseFace` and
  `buildGlyphMetrics` already read, run-length compression included.

- Done when: Vertical fonts expose vhea/vmtx advances and bearings for short and long metric runs, and a vertical CJK fixture uses those values rather than horizontal metrics.

### std.truetype.021 — TrueType bytecode hinting

- `Face.hintVertical` is a vertical hinting heuristic, not the TrueType interpreter — `fpgm`,
  `prep` and `cvt ` are not executed.
- Deliberately last. At the display densities this renderer targets, and with the DPI awareness
  the GUI now has, full bytecode hinting buys progressively less, and it is a large and fiddly
  piece of work. FreeType's own autohinter exists precisely because the interpreter is not always
  the right answer.

- Done when: A bounded TrueType bytecode interpreter executes fpgm, prep, and glyph instructions for representative hinted fixtures with expected pixel outlines, and malformed programs fail safely.

---
