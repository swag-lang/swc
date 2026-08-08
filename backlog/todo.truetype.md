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

Twelve tables parsed — `cmap`, `glyf`, `GPOS`, `head`, `hhea`, `hmtx`, `loca`, `maxp`, `name`,
`post`, `kern`, `OS/2` — plus the `ttcf` collection header. Composite glyphs, a matrix transform,
outline commands, grayscale rasterization, vertical hinting, and both single- and multi-channel
signed distance fields. Character map formats 0, 4, 6, 12 and 13, all binary-searched, and format
14 for variation sequences. Kerning from the `GPOS` `kern` feature, with the legacy `kern` table as
the fallback. A `Face`/`GlyphSlot` model that mirrors FreeType closely enough to be familiar on
sight, and eleven test files covering collections, composites, hinting, kerning, lifecycle,
outlines, parsing and rendering.

A collection is also searchable without being loaded: `Face.familyNameAt` reads one member's offset
table and `name` table and nothing else, so finding one face of `msgothic.ttc` costs a name lookup
rather than nine megabytes per candidate. That is what `pixel` selects a system face with.

Two things stand out as genuinely ahead of the field. MSDF generation lives in the module rather
than in a separate project, which is what GPU text actually wants — FreeType ships SDF but not
MSDF, and msdfgen is a distinct dependency everywhere else. And the rasterizer is fast; the
current implementation replaced one that was roughly sixteen times slower.

The gaps are about coverage: which fonts load at all, and whether text is positioned correctly.

---

## Tier A — Fonts that cannot load

### T-068 — CFF and web-font containers are still rejected

- `ttcf` collections now load, and `pixel` selects the right member of one. Two containers remain,
  and both are now reported by name rather than as an unknown format:
  - `OTTO` — OpenType with CFF outlines. Every Adobe font, a large share of Google Fonts, and a
    great many system fonts are CFF rather than `glyf`.
  - `wOFF` and `wOF2` — the web font containers, and the form most downloadable fonts arrive in.
- This is not theoretical, and it reaches the applications. `TypeFace.createFromHfont` in
  `bin/std/modules/pixel/src/text/typeface.win32.swg` hands `Face.load` whatever GDI returns for an
  installed font, and for an OpenType font that buffer starts with `OTTO`. Any user-installed OTF
  is refused, by name, and there is nothing above this module that can do anything about it.
- Fix, in value order:
  1. `OTTO`: a CFF charstring interpreter producing the same `Outline` the `glyf` loader produces.
     This is the largest single piece of work in the module, and it is what closes the gap with
     FreeType and stb_truetype on font coverage.
  2. WOFF and WOFF2: container decompression over the existing parser. WOFF is zlib, which
     `Core` already has; WOFF2 needs Brotli, so weigh it separately.

---

## Tier B — Text that is positioned wrongly

### T-069 — No shaping

- Problem: `GPOS` is read for pair adjustment only, and there is no `GSUB` processing at all. A
  character maps to a glyph through `cmap`, advances by `hmtx`, and is kerned. That is the whole
  pipeline.
- What that costs, in increasing severity:
  - No ligatures and no contextual alternates, so Latin text loses `fi`, `fl` and any stylistic
    feature the font declares.
  - No mark positioning, so every combining accent lands at a default offset rather than where the
    font says it belongs.
  - No script shaping at all. Arabic does not join. Indic scripts do not reorder or form
    conjuncts. Thai marks stack wrongly. For these scripts the output is not imperfect, it is
    incorrect.
- Fix: HarfBuzz is the reference implementation and the honest comparison. A full port is a
  project in its own right. The staged path now continues with `GSUB` ligature and substitution
  lookups, then mark attachment, and states plainly in the module documentation which scripts are
  supported rather than failing silently on the rest.
- What the kerning work already provides: `src/gpos.swg` has coverage tables in both formats, class
  definitions in both formats, value-record decoding, and extension-lookup resolution. Every one of
  those is needed by the rest of `GPOS` and by `GSUB`, so shaping starts from the lookup navigation
  rather than from the bytes.
- Sequencing note: decide early whether this module owns shaping or whether shaping becomes a
  separate module above it. FreeType and HarfBuzz are deliberately separate, and that separation
  has held up well for twenty years.

---

## Tier C — Font classes not covered

### T-070 — Variable fonts

- No `fvar`, `gvar`, `avar` or `HVAR`. A variable font loads only at its default instance, so a
  single file that should provide a whole weight and width range provides one static face.
- Variable fonts are now the normal shipping form for large families, so this is a coverage gap
  rather than an exotic feature. It depends on T-068 for CFF2-based variable fonts.

### T-071 — Color fonts and emoji

- No `COLR`/`CPAL` layered color, no `sbix` or `CBDT` bitmap strikes, no `SVG` table. Emoji do not
  render.
- `COLR` version 0 is the cheapest useful subset: layered glyph references with a palette, which
  the existing outline pipeline can already draw.
- The `cmap` format-14 subtable is read, so `Face.glyphIndexVariant` already resolves the emoji and
  text presentation selectors. What is missing is a glyph to draw for the emoji one.

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
