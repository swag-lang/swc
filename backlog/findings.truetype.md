# TrueType Findings

Evidence about font parsing and rasterization that still needs investigation lives here. Completed
work is removed; history remains in git.

### F-154 — PDF-minimal TrueType subsets are rejected as incomplete OpenType fonts

- Area: bin/std
- Found while: rendering page 5 of
  `bin/std/modules/pdf/src/tests/unittests/datas/llvm-polly-impact-2011-slides.pdf`
- Observation: `TrueType.Face.load` rejects each embedded DejaVu subset with `name table missing`,
  so PDF rendering substitutes a system face even though the embedded outlines and metrics are
  usable. The loader correctly enforces the standalone OpenType profile, but has no profile for a
  TrueType program embedded in PDF.
- Evidence: the page's `FKFJSD+DejaVuSans` `/FontFile2` stream (object 103) decodes to 11,148 bytes
  and declares ten in-range tables: `cmap`, `cvt `, `fpgm`, `glyf`, `head`, `hhea`, `hmtx`, `loca`,
  `maxp`, and `prep`. All 13 `/FontFile2` streams in the document use that same table set and omit
  `name`, `post`, and `OS/2`. PDF Reference 1.4 section 5.8 requires exactly the nine outline and
  metric tables above, plus `cmap` for a simple font; `name`, `post`, and `OS/2` are not required.
  `parseFace` nevertheless calls strict `parseNames` and `parsePost`, and `parseNames` fails at
  `bin/std/modules/truetype/src/parse.swg:90` before any glyph is loaded.
- Next step: define an explicit embedded-font loading profile that preserves strict standalone
  loading, accepts absent metadata tables, and receives the family/style and underline metadata
  from the PDF font descriptor. Protect it with the object-103 subset and verify its glyph outlines
  rather than merely accepting the container.
