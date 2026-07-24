using Swag, Core

#[ConstExpr]
func imageTag(x1, x2, x3, x4: u32)->u32 => (x1 << 24) | (x2 << 16) | (x3 << 8) | x4

const TAG_CMAP = imageTag('c''u32, 'm''u32, 'a''u32, 'p''u32)
const TAG_GLYF = imageTag('g''u32, 'l''u32, 'y''u32, 'f''u32)
const TAG_HEAD = imageTag('h''u32, 'e''u32, 'a''u32, 'd''u32)
const TAG_HHEA = imageTag('h''u32, 'h''u32, 'e''u32, 'a''u32)
const TAG_HMTX = imageTag('h''u32, 'm''u32, 't''u32, 'x''u32)
const TAG_LOCA = imageTag('l''u32, 'o''u32, 'c''u32, 'a''u32)
const TAG_MAXP = imageTag('m''u32, 'a''u32, 'x''u32, 'p''u32)
const TAG_NAME = imageTag('n''u32, 'a''u32, 'm''u32, 'e''u32)
const TAG_POST = imageTag('p''u32, 'o''u32, 's''u32, 't''u32)
const TAG_KERN = imageTag('k''u32, 'e''u32, 'r''u32, 'n''u32)
const TAG_OS2  = imageTag('O''u32, 'S''u32, '/''u32, '2''u32)

struct TableRecord
{
    tag:    u32
    offset: u32
    length: u32
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

    fontData:         Array'u8
    tables:           Array'TableRecord
    glyphMetrics:     Array'GlyphMetric
    glyphLocations:   Array'u32
    chosenCMap:       #late const [..] u8
    cmapFormat:       u16
    unitsPerEm:       u16
    numLongMetrics:   u16
    lineGap:          s16
    macStyle:         u16
    indexToLocFormat: s16

    // Blue-zone metrics for vertical hinting, in font design units (0 = unknown).
    xHeight:   s16
    capHeight: s16

    outlinePoints:   Array'Vector
    outlineTags:     Array'u8
    outlineContours: Array's16
    bitmapPixels:    Array'u8

    // Horizontal kerning pairs from the legacy 'kern' table (format 0).
    // Key = (leftGlyph << 16) | rightGlyph, value = kerning in font design units.
    kernPairs: HashTable'(u32, s16)
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
    }
}

func getFaceImpl(face: #null *Face)->*FaceImpl throw
{
    if !face do
        fail(0x23)
    let safeFace = notnull face
    let faceData = cast(*FaceImpl) cast(*void) safeFace
    if !faceData do
        fail(0x23)
    return faceData
}

func getSlotImpl(slot: *GlyphSlot)->*FaceImpl throw
{
    return getFaceImpl(slot.face)
}

func findTable(faceData: *FaceImpl, tag: u32)->#null const *TableRecord
{
    for it in faceData.tables
    {
        if it.tag == tag do
            return &it
    }

    return null
}

func getTableSlice(faceData: *FaceImpl, tag: u32, missingCode: u8)->#null const [..] u8 throw
{
    let rec = findTable(faceData, tag)
    if !rec do
        fail(missingCode)
    return getSlice(faceData.fontData.toSlice(), rec.offset, rec.length)
}
