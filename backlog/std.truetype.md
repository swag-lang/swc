# TrueType Backlog

This backlog covers `std/truetype`, measured against the font libraries it competes with:
FreeType, stb_truetype, HarfBuzz for shaping, and msdfgen for distance fields.

Evidence, investigations, and intended outcomes owned by `bin/std/modules/truetype` stay together
here. Compiler and language work belongs in [compiler.core.md](compiler.core.md) and
[language.design.md](language.design.md). [README.md](README.md) has the whole layout.


## Entries

### std.truetype.001 — WOFF containers are rejected

- Evidence: `parse.swg` rejects the `wOFF` tag with "WOFF font containers are not supported".
- Next: add WOFF decompression over the existing face parser using `Core`'s zlib support.
- Done when: WOFF fonts load through Face with the same glyph outlines, names, and metrics as
  their reconstructed sfnt data, and malformed compression or table lengths fail in focused
  fixtures.
- Related: std.truetype.002

### std.truetype.002 — WOFF2 containers are rejected

- Evidence: `parse.swg` rejects the `wOF2` tag, and no Brotli decoder exists in `bin/std`.
- Next: add WOFF2 reconstruction and Brotli decompression as a separate format implementation.
- Done when: WOFF2 fonts load through Face with glyph outlines, names, and metrics matching
  reference sfnt reconstruction, and truncated Brotli data or invalid transforms fail cleanly.
- Related: std.truetype.001

### std.truetype.003 — No GSUB single-substitution processing

- Evidence: `GSUB` is not read. `src/gpos.swg` handles only pair adjustment, but it already has
  coverage tables and class definitions in both formats, value-record decoding, and
  extension-lookup resolution, all of which GSUB reuses.
- Next: implement single-substitution lookups over that lookup navigation, with unsupported
  lookup kinds reported or documented.
- Done when: a font fixture applies single-substitution lookups through the shaping API with
  the expected glyph IDs and clusters, while unsupported lookup kinds have an explicit result.
- Related: std.truetype.008, std.truetype.004, std.truetype.005, std.truetype.006,
  std.truetype.007

### std.truetype.004 — No GSUB multiple-substitution processing

- Next: implement multiple-substitution lookups independently of the single-substitution path.
- Done when: a multiple-substitution fixture expands one glyph into the expected sequence
  without losing source-cluster mapping, independently of single-substitution tests.
- Related: std.truetype.003

### std.truetype.005 — No GSUB alternate-substitution processing

- Next: implement alternate selection with an explicit feature/user-choice contract.
- Done when: a fixture exposes alternate glyph choices under an explicit feature or user
  selection, with a deterministic default and stable cluster mapping.
- Related: std.truetype.003

### std.truetype.006 — No GSUB ligature-substitution processing

- Next: implement ligature substitution for declared features such as `liga`, including
  cluster mapping.
- Done when: a declared `liga` fixture substitutes the expected glyph for a sequence and maps
  the resulting ligature back to every source cluster it covers.
- Related: std.truetype.003

### std.truetype.007 — No GSUB contextual-substitution processing

- Next: implement contextual and chaining-context application over the other supported
  substitution lookups.
- Done when: contextual and chaining lookups apply supported substitutions in font order to
  representative fixtures, while malformed references fail without reading outside table
  bounds.
- Related: std.truetype.003, std.truetype.004, std.truetype.005, std.truetype.006

### std.truetype.008 — Shaping has no decided module boundary

- Next: decide whether shaping stays in `truetype` or becomes a separate module above face
  parsing. Record the ownership and dependency rule before the shaping API expands.
- Done when: a recorded module decision assigns face parsing, shaping state, and Pixel
  consumption without a dependency cycle, and one small public shaping example compiles under
  that boundary.
- Related: std.truetype.003, std.truetype.009, std.truetype.012

### std.truetype.009 — Combining marks ignore GPOS attachment

- Evidence: `gpos.swg` reads pair adjustment only, with no mark-to-base lookups.
- Next: implement mark-to-base positioning so combining accents use the base glyph's anchors.
- Done when: a combining-mark fixture reads GPOS base and mark anchors and places the mark at
  the expected coordinates rather than at the base advance.
- Related: std.truetype.003, std.truetype.010, std.truetype.011

### std.truetype.010 — No GPOS mark-to-ligature attachment

- Next: position marks against the selected component anchors of a ligature glyph.
- Done when: a fixture attaches marks to the selected component anchors of a ligature and
  preserves component and cluster identity through shaping.
- Related: std.truetype.009, std.truetype.006

### std.truetype.011 — No GPOS mark-to-mark attachment

- Next: position one combining mark relative to another independently of base and ligature
  attachment.
- Done when: a fixture places a second combining mark relative to the first mark's anchor, with
  the expected position independent of base and ligature attachment.
- Related: std.truetype.009

### std.truetype.012 — Arabic text is not shaped

- Next: implement Arabic joining forms, direction-aware cluster processing, and required
  feature application end to end.
- Done when: representative Arabic text receives joining forms, direction-aware cluster order,
  and required features with glyph IDs and positions checked against a reference fixture.
- Related: std.truetype.003, std.truetype.009, std.truetype.013, std.truetype.014

### std.truetype.013 — Indic text is not shaped

- Next: implement one explicitly named Indic shaping model, reordering, conjunct formation, and
  required features as its own script-support deliverable.
- Done when: one explicitly named Indic script has tested reordering, conjunct formation,
  required features, and source-cluster mapping against reference shaping output.
- Related: std.truetype.003, std.truetype.009

### std.truetype.014 — Thai marks are not shaped

- Next: implement Thai mark ordering and positioning independently of Arabic and Indic support.
- Done when: Thai marks are ordered and positioned for representative base and stacked-mark
  sequences with glyph IDs and offsets checked against reference fixtures.
- Related: std.truetype.009

### std.truetype.015 — Variable fonts load only at their default instance

- Evidence: no `fvar`, `gvar`, `avar` or `HVAR` is read, so a single file that should provide a
  whole weight and width range provides one static face. CFF2 variation data is part of this
  entry; the CFF1 charstring support already in the module is only its static foundation.
- Next: read `fvar` axes and apply `gvar` deltas to TrueType outlines for a named instance,
  then add `avar` normalization and `HVAR` metrics.
- Done when: default and non-default instances of representative TrueType and CFF2 variable
  fonts produce expected outlines and metrics across supported axes, with invalid variation
  tables rejected.

### std.truetype.016 — No COLR/CPAL layered color glyphs

- Evidence: the `cmap` format-14 subtable is read, so `Face.glyphIndexVariant` already resolves
  the emoji and text presentation selectors. What is missing is a glyph to draw for the emoji
  one.
- Next: implement `COLR` version 0, the cheapest useful subset: layered glyph references with a
  palette, which the existing outline pipeline can already draw.
- Done when: a COLR version-0 fixture paints the expected ordered glyph layers in the selected
  CPAL palette, including text and emoji presentation selection.
- Related: std.truetype.017, std.truetype.018, std.truetype.019

### std.truetype.017 — No `sbix` color bitmap strikes

- Next: decode and select `sbix` strikes independently of layered COLR glyphs.
- Done when: a fixture selects the documented `sbix` bitmap strike for requested pixel sizes,
  decodes its image, and falls back predictably when no usable strike exists.
- Related: std.truetype.016, std.truetype.018

### std.truetype.018 — No CBDT/CBLC color bitmap strikes

- Next: decode and select CBDT/CBLC strikes independently of Apple's `sbix` container.
- Done when: a fixture selects and decodes the expected CBDT/CBLC color strike across requested
  sizes, including a malformed-table failure case.
- Related: std.truetype.016, std.truetype.017

### std.truetype.019 — No SVG glyph table

- Next: parse and render the OpenType SVG table through Pixel's SVG support, with explicit
  recursion and resource limits.
- Done when: an OpenType SVG glyph renders through Pixel with the expected bounds and colors,
  while external resources, recursive references, and oversized data are bounded or rejected.
- Related: std.truetype.016, std.pixel.image.008

### std.truetype.020 — Vertical writing has no metrics

- Evidence: no `vhea` or `vmtx`, so vertical CJK layout has no metrics to work from. The two
  tables mirror `hhea` and `hmtx`, which `parseFace` and `buildGlyphMetrics` already read,
  run-length compression included.
- Next: parse `vhea`/`vmtx` beside the horizontal metrics and expose vertical advances and
  bearings on Face.
- Done when: vertical fonts expose vhea/vmtx advances and bearings for short and long metric
  runs, and a vertical CJK fixture uses those values rather than horizontal metrics.

### std.truetype.021 — TrueType bytecode hinting

- Evidence: `Face.hintVertical` is a vertical hinting heuristic, not the TrueType interpreter;
  `fpgm`, `prep` and `cvt ` are not executed. At the display densities this renderer targets,
  full bytecode hinting buys progressively less, so this stays last.
- Next: none until a measured rendering defect at a target density justifies a bounded
  interpreter.
- Done when: a bounded TrueType bytecode interpreter executes fpgm, prep, and glyph
  instructions for representative hinted fixtures with expected pixel outlines, and malformed
  programs fail safely.

---
