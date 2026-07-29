# Loading fonts and glyphs

TrueType works from bytes already present in memory. A [[TrueType.Face]] parses
and owns a private copy of those bytes, so the source buffer does not need to
remain alive.

```swag
using Core, TrueType

let bytes = File.readAllBytes("Inter-Regular.ttf")
let face  = notnull (try Face.load(bytes.toSlice()))
defer face.destroy()
```

The input is a standalone TrueType font with `glyf` outlines.

## The reusable glyph slot

Each face exposes one [[TrueType.GlyphSlot]] through [[TrueType.Face.glyph]].
Every call to [[TrueType.Face.loadGlyph]] or [[TrueType.Face.loadChar]] replaces
the slot's outline and bitmap storage.

```swag
try face.setPixelSize(0, 32)
try face.loadChar('A')

let advance  = face.glyph.advance.x / 64.0
let commands = face.glyph.outline.decompose()
```

The array returned by [[TrueType.Outline.decompose]] is owned and can be retained.
Raw point arrays and [[TrueType.Bitmap.buffer]] are borrowed: consume or copy them
before loading or rendering another glyph, and never use them after destroying
the face.

## Character and glyph indices

Use [[TrueType.Face.glyphIndex]] when caching or laying out glyphs by index. Index
zero is the conventional missing-glyph entry, so a zero result means that the
requested character has no distinct glyph. Use [[TrueType.Face.loadChar]] for the
simple one-step path.

Kerning also operates on glyph indices. Query [[TrueType.Face.hasKerning]] once,
then call [[TrueType.Face.getKerning]] only when the face contains supported
legacy kerning pairs.
