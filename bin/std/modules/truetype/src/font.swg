using Swag, Core

#[ConstExpr]
func imageTag(x1, x2, x3, x4: u32)->u32 => (x1 << 24) | (x2 << 16) | (x3 << 8) | x4

const TAG_CMAP = imageTag('c'u32, 'm'u32, 'a'u32, 'p'u32)
const TAG_GLYF = imageTag('g'u32, 'l'u32, 'y'u32, 'f'u32)
const TAG_GPOS = imageTag('G'u32, 'P'u32, 'O'u32, 'S'u32)
const TAG_HEAD = imageTag('h'u32, 'e'u32, 'a'u32, 'd'u32)
const TAG_HHEA = imageTag('h'u32, 'h'u32, 'e'u32, 'a'u32)
const TAG_HMTX = imageTag('h'u32, 'm'u32, 't'u32, 'x'u32)
const TAG_LOCA = imageTag('l'u32, 'o'u32, 'c'u32, 'a'u32)
const TAG_MAXP = imageTag('m'u32, 'a'u32, 'x'u32, 'p'u32)
const TAG_NAME = imageTag('n'u32, 'a'u32, 'm'u32, 'e'u32)
const TAG_POST = imageTag('p'u32, 'o'u32, 's'u32, 't'u32)
const TAG_KERN = imageTag('k'u32, 'e'u32, 'r'u32, 'n'u32)
const TAG_OS2  = imageTag('O'u32, 'S'u32, '/'u32, '2'u32)
const TAG_CFF  = imageTag('C'u32, 'F'u32, 'F'u32, ' 'u32)

// Container signatures found at offset zero of a font file. Only the two bare
// sfnt spellings carry `glyf` outlines this module can read; the rest name a
// container it recognizes well enough to say so.
const TAG_SFNT = 0x0001_0000'u32
const TAG_TRUE = imageTag('t'u32, 'r'u32, 'u'u32, 'e'u32)
const TAG_TTCF = imageTag('t'u32, 't'u32, 'c'u32, 'f'u32)
const TAG_OTTO = imageTag('O'u32, 'T'u32, 'T'u32, 'O'u32)
const TAG_WOFF = imageTag('w'u32, 'O'u32, 'F'u32, 'F'u32)
const TAG_WOF2 = imageTag('w'u32, 'O'u32, 'F'u32, '2'u32)

struct TableRecord
{
    tag:    u32
    offset: u32
    length: u32
}

// Where a face's glyph outlines come from.
//
// The three forms differ only in how a glyph index becomes a set of points; everything
// downstream — scaling, hinting, rasterization, distance fields — sees the same outline.
enum OutlineSource
{
    Glyf      // TrueType quadratic outlines in a `glyf` table.
    Cff       // Type 2 charstrings, from an OpenType `CFF ` table or a bare CFF program.
    Type1     // Type 1 charstrings, from a PFB, PFA, or bare font program.
}

struct GlyphMetric
{
    advanceWidth:    u16
    leftSideBearing: s16
}

// Internal backing store for a public Face. The public Face is the first field so
// that a *Face can be reinterpreted as a *FaceImpl and vice versa.
struct FaceImpl
{
    face: Face

    late allocationAllocator: IAllocator

    fontData:         Array'u8
    tables:           Array'TableRecord
    glyphMetrics:     Array'GlyphMetric
    glyphLocations:   Array'u32
    late chosenCMap:  const [..] u8
    cmapFormat:       u16
    unitsPerEm:       u16
    numLongMetrics:   u16
    lineGap:          s16
    macStyle:         u16
    indexToLocFormat: s16

    // Format-14 subtable holding the Unicode variation sequences, when the face
    // declares one. It supplements the selected map instead of replacing it.
    variationCMap: const [..] u8?

    // Blue-zone metrics for vertical hinting, in font design units (0 = unknown).
    xHeight:   s16
    capHeight: s16

    // PostScript outlines and the tables that address them. Only the source named by
    // `outlineSource` is populated.
    outlineSource: OutlineSource = OutlineSource.Glyf
    cff:           CffFont
    type1:         Type1Font

    // Unicode map built from the font's own encoding, for a program that ships no `cmap`.
    // A bare CFF or Type 1 file is addressed by name or by code, and this is what still
    // lets it answer a character lookup.
    syntheticCMap: HashTable'(u32, u32)
    hasCMap:       bool

    outlinePoints:   Array'Vector
    outlineTags:     Array'u8
    outlineContours: Array's16
    bitmapPixels:    Array'u8

    // Horizontal kerning pairs from the legacy 'kern' table (format 0).
    // Key = (leftGlyph << 16) | rightGlyph, value = kerning in font design units.
    kernPairs: HashTable'(u32, s16)

    // Pair-adjustment subtables the GPOS 'kern' feature reaches, as offsets into
    // 'gposTable'. Class-based subtables describe a glyph-pair matrix far too large
    // to expand, so kerning is resolved per query rather than precomputed. These
    // answer before 'kernPairs', which covers the pairs they leave at zero.
    gposTable:         const [..] u8?
    gposPairSubtables: Array'u32
}

impl FaceImpl
{
    mtd opDrop()
    {
        .fontData.clear()
        .tables.clear()
        .glyphMetrics.clear()
        .glyphLocations.clear()
        .outlinePoints.clear()
        .outlineTags.clear()
        .outlineContours.clear()
        .bitmapPixels.clear()
        .kernPairs.free()
        .gposPairSubtables.clear()
        .syntheticCMap.free()
    }

    // Returns the glyph a name selects, or zero when the face cannot be addressed by name.
    mtd glyphIndexByName(name: string)->u32
    {
        let key = String.from(name)
        switch .outlineSource
        {
        case .Cff:   return .cff.nameToGid.getOrDefault(key, 0)
        case .Type1: return .type1.nameToGid.getOrDefault(key, 0)
        case .Glyf:  return 0
        }
    }

    // Returns the glyph the font's own built-in encoding places at one code.
    mtd glyphIndexByCode(code: u32)->u32
    {
        switch .outlineSource
        {
        case .Cff:   return .cff.codeToGid.getOrDefault(code, 0)
        case .Type1: return .type1.codeToGid.getOrDefault(code, 0)
        case .Glyf:  return 0
        }
    }

    // Returns the character identifier map of a CID-keyed CFF, or nothing for another font.
    mtd glyphIndexByCid(cid: u32)->u32
    {
        if .outlineSource != .Cff or !.cff.isCid do
            return 0
        return .cff.cidToGid.getOrDefault(cid, 0)
    }
}

func getFaceImpl(face: *Face?)->*FaceImpl fail
{
    if !face do
        fault(0x23)
    let safeFace = face!
    return cast(*FaceImpl) cast(*void) safeFace
}

func getSlotImpl(slot: *GlyphSlot)->*FaceImpl fail
{
    return getFaceImpl(slot.face)
}

func findTable(faceData: *FaceImpl, tag: u32)->const *TableRecord?
{
    for it in faceData.tables
    {
        if it.tag == tag do
            return it
    }

    return null
}

func getTableSlice(faceData: *FaceImpl, tag: u32, missingCode: u8)->const [..] u8? fail
{
    let rec = findTable(faceData, tag)
    if !rec do
        fault(missingCode)
    let r = rec!
    return getSlice(faceData.fontData.toSlice(), r.offset, r.length)
}
