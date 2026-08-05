# TrueType Roadmap

This file is the roadmap for `std/truetype`, measured against the font libraries it competes with:
FreeType, stb_truetype, HarfBuzz for shaping, and msdfgen for distance fields.

It is not the repository's discovery backlog. Compiler, language, and cross-cutting
standard-library leads belong in the root [TODO.md](../../../../TODO.md). This file holds intent
about this module.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

## Where the module already stands

Eleven tables parsed — `cmap`, `glyf`, `head`, `hhea`, `hmtx`, `loca`, `maxp`, `name`, `post`,
`kern`, `OS/2`. Composite glyphs, a matrix transform, outline commands, grayscale rasterization,
vertical hinting, and both single- and multi-channel signed distance fields. Character map formats
4 and 12, both binary-searched. A `Face`/`GlyphSlot` model that mirrors FreeType closely enough to
be familiar on sight, and ten test files covering composites, hinting, kerning, lifecycle,
outlines, parsing and rendering.

Two things stand out as genuinely ahead of the field. MSDF generation lives in the module rather
than in a separate project, which is what GPU text actually wants — FreeType ships SDF but not
MSDF, and msdfgen is a distinct dependency everywhere else. And the rasterizer is fast; the
current implementation replaced one that was roughly sixteen times slower.

The gaps are about coverage: which fonts load at all, and whether text is positioned correctly.

---

## Tier A — Fonts that cannot load

### 1. Only bare TrueType files are accepted

- Problem: `parseFace` in `src/parse.swg` accepts a file whose first four bytes are `0x00010000` or
  `true`, and faults on anything else. That rejects three container formats that are not exotic:
  - `OTTO` — OpenType with CFF outlines. Every Adobe font, a large share of Google Fonts, and a
    great many system fonts are CFF rather than `glyf`.
  - `ttcf` — TrueType Collection. A single file holding several faces.
  - `wOFF` and `wOF2` — the web font containers, and the form most downloadable fonts arrive in.
- This is not theoretical, and it reaches the applications. `TypeFace.createFromHfont` in
  `bin/std/modules/pixel/src/text/typeface.win32.swg` calls `GetFontData(hdc, 0, 0, ...)`, which
  returns the whole font file — so for a collection it hands back a buffer starting with `ttcf`,
  and for an OpenType font a buffer starting with `OTTO`. Both then fail in `Face.load`. A stock
  Windows install ships several collections, and any user-installed OTF is in the same position.
- Fix, in value order:
  1. `ttcf`: read the collection header, expose a face index on `Face.load`. This is a small
     parser change and it unblocks a whole class of system fonts immediately.
  2. `OTTO`: a CFF charstring interpreter producing the same `Outline` the `glyf` loader produces.
     This is the largest single piece of work in the module, and it is what closes the gap with
     FreeType and stb_truetype on font coverage.
  3. WOFF and WOFF2: container decompression over the existing parser. WOFF is zlib, which
     `Core` already has; WOFF2 needs Brotli, so weigh it separately.

### 2. Kerning does not work on modern fonts

- Problem: `Face.hasKerning` and `Face.getKerning` read the legacy `kern` table. Modern fonts put
  kerning in `GPOS` and frequently ship no `kern` table at all, so `hasKerning` answers false and
  text renders unkerned.
- Consequence: this is not a hard failure, it is a quiet quality loss. Text looks slightly wrong
  everywhere and nothing reports it.
- Fix: read the `GPOS` pair-adjustment lookups. Full shaping is entry 3; kerning alone is a
  bounded subset of `GPOS` and worth doing first, because it fixes the visible problem at a
  fraction of the cost.

---

## Tier B — Text that is positioned wrongly

### 3. No shaping

- Problem: there is no `GSUB` or `GPOS` processing. A character maps to a glyph through `cmap` and
  advances by `hmtx`, and that is the whole pipeline.
- What that costs, in increasing severity:
  - No ligatures and no contextual alternates, so Latin text loses `fi`, `fl` and any stylistic
    feature the font declares.
  - No mark positioning, so every combining accent lands at a default offset rather than where the
    font says it belongs.
  - No script shaping at all. Arabic does not join. Indic scripts do not reorder or form
    conjuncts. Thai marks stack wrongly. For these scripts the output is not imperfect, it is
    incorrect.
- Fix: HarfBuzz is the reference implementation and the honest comparison. A full port is a
  project in its own right. A defensible staged path is `GPOS` kerning (entry 2), then `GSUB`
  ligature and substitution lookups, then mark attachment, and to state plainly in the module
  documentation which scripts are supported rather than failing silently on the rest.
- Sequencing note: decide early whether this module owns shaping or whether shaping becomes a
  separate module above it. FreeType and HarfBuzz are deliberately separate, and that separation
  has held up well for twenty years.

### 4. Character map coverage

- Formats 4 and 12 are implemented. Missing: format 0 and 6 for old and small fonts, format 13 for
  last-resort fonts, and format 14 for Unicode Variation Sequences.
- Format 14 is the one that matters — it selects between CJK regional variants and between the text
  and emoji presentations of the same code point.
- Small, well-bounded work.

---

## Tier C — Font classes not covered

### 5. Variable fonts

- No `fvar`, `gvar`, `avar` or `HVAR`. A variable font loads only at its default instance, so a
  single file that should provide a whole weight and width range provides one static face.
- Variable fonts are now the normal shipping form for large families, so this is a coverage gap
  rather than an exotic feature. It depends on entry 1 for CFF2-based variable fonts.

### 6. Color fonts and emoji

- No `COLR`/`CPAL` layered color, no `sbix` or `CBDT` bitmap strikes, no `SVG` table. Emoji do not
  render.
- `COLR` version 0 is the cheapest useful subset: layered glyph references with a palette, which
  the existing outline pipeline can already draw.

### 7. Vertical writing

- No `vhea` or `vmtx`. Vertical CJK layout has no metrics to work from.

### 8. TrueType bytecode hinting

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
