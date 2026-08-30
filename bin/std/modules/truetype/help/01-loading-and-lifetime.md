# Loading fonts and glyphs

TrueType works from bytes already present in memory. A [[TrueType.Face]] parses
and owns a private copy of those bytes, so the source buffer does not need to
remain alive.

```swag
using Core, TrueType

let bytes = File.readAllBytes("Inter-Regular.ttf")
let face  = (try Face.load(bytes.toSlice()))!
defer face.destroy()
```

The input is a TrueType font with `glyf` outlines. OpenType files carrying CFF
outlines (`OTTO`) and WOFF containers are recognized and reported as unsupported,
so a failure names what the file actually is.

## Rendering-only subsets

PDF and similar document formats may embed a TrueType subset without the `name`
and `post` metadata required of an installable font. Use
[[TrueType.Face.loadSubset]] for those programs and provide the family identity
from the document's font descriptor. The outline, location, character-map, and
horizontal-metric tables are still validated normally.

```swag
let face = (try Face.loadSubset(embeddedBytes, "DocumentSans"))!
defer face.destroy()
```

Keep [[TrueType.Face.load]] for standalone font files; it deliberately remains
strict about their required metadata.

## Font collections

A `ttcf` collection packs several faces into one file, which is how Windows ships
many of its font families. [[TrueType.Face.countFaces]] reports how many a buffer
holds and [[TrueType.Face.loadAt]] selects one; [[TrueType.Face.load]] takes the
first. A bare font file answers a count of one, so the same code path serves both.

Looking for one member by name does not mean loading the others.
[[TrueType.Face.familyNameAt]] reads a face's `name` table and nothing else, so a
collection can be searched first and loaded once.

```swag
let bytes = File.readAllBytes("msgothic.ttc")
let count = try Face.countFaces(bytes.toSlice())
for count
{
    if (try Face.familyNameAt(bytes.toSlice(), Swag.index)) != "MS PGothic" do
        continue

    let face = (try Face.loadAt(bytes.toSlice(), Swag.index))!
    defer face.destroy()
    break
}
```

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

A variation selector qualifies the character before it, choosing between the forms
of one code point — a CJK regional variant, or the text and emoji presentations.
[[TrueType.Face.glyphIndexVariant]] resolves the pair and falls back to the plain
lookup when the face registers no distinct glyph, so it is always safe to call;
[[TrueType.Face.hasVariant]] answers whether the face registers the pair at all.

## Kerning

Kerning operates on glyph indices. Query [[TrueType.Face.hasKerning]] once, then
call [[TrueType.Face.getKerning]] only when the face carries kerning data.

The `GPOS` `kern` feature answers first, and the legacy `kern` table answers for any
pair it leaves at zero. Most modern faces ship only `GPOS`, which is why reading it
matters; a face carrying both states many of its pairs behind contextual lookups
that this module does not run, and its legacy table is the designer's own flattening
of exactly those rules. Reading both is what keeps either kind of face kerned.

Mark attachment and contextual positioning are still missing, and they need a shaper
rather than a wider kerning query.

```swag
if face.hasKerning()
{
    let left  = face.glyphIndex('A')
    let right = face.glyphIndex('V')
    let pen   = face.getKerning(left, right).x / 64.0
}
```
