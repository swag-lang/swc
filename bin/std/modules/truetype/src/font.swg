using Swag, Core

#[ConstExpr]
func imageTag(x1, x2, x3, x4: u32)->u32 => (x1 << 24) | (x2 << 16) | (x3 << 8) | x4

const TAG_CMAP = imageTag('c'_u32, 'm'_u32, 'a'_u32, 'p'_u32)
const TAG_GLYF = imageTag('g'_u32, 'l'_u32, 'y'_u32, 'f'_u32)
const TAG_GPOS = imageTag('G'_u32, 'P'_u32, 'O'_u32, 'S'_u32)
const TAG_HEAD = imageTag('h'_u32, 'e'_u32, 'a'_u32, 'd'_u32)
const TAG_HHEA = imageTag('h'_u32, 'h'_u32, 'e'_u32, 'a'_u32)
const TAG_HMTX = imageTag('h'_u32, 'm'_u32, 't'_u32, 'x'_u32)
const TAG_VHEA = imageTag('v'_u32, 'h'_u32, 'e'_u32, 'a'_u32)
const TAG_VMTX = imageTag('v'_u32, 'm'_u32, 't'_u32, 'x'_u32)
const TAG_LOCA = imageTag('l'_u32, 'o'_u32, 'c'_u32, 'a'_u32)
const TAG_MAXP = imageTag('m'_u32, 'a'_u32, 'x'_u32, 'p'_u32)
const TAG_NAME = imageTag('n'_u32, 'a'_u32, 'm'_u32, 'e'_u32)
const TAG_POST = imageTag('p'_u32, 'o'_u32, 's'_u32, 't'_u32)
const TAG_KERN = imageTag('k'_u32, 'e'_u32, 'r'_u32, 'n'_u32)
const TAG_COLR = imageTag('C'_u32, 'O'_u32, 'L'_u32, 'R'_u32)
const TAG_CPAL = imageTag('C'_u32, 'P'_u32, 'A'_u32, 'L'_u32)
const TAG_OS2  = imageTag('O'_u32, 'S'_u32, '/'_u32, '2'_u32)
const TAG_CFF  = imageTag('C'_u32, 'F'_u32, 'F'_u32, ' '_u32)
const TAG_CFF2 = imageTag('C'_u32, 'F'_u32, 'F'_u32, '2'_u32)

// Container signatures found at offset zero of a font file. The sfnt wrappers
// carry TrueType or CFF outlines, and ttcf selects a collection member. WOFF1 is
// rebuilt as sfnt; WOFF2 is recognized so the parser can report it unsupported.
const TAG_SFNT = 0x0001_0000_u32
const TAG_TRUE = imageTag('t'_u32, 'r'_u32, 'u'_u32, 'e'_u32)
const TAG_TTCF = imageTag('t'_u32, 't'_u32, 'c'_u32, 'f'_u32)
const TAG_OTTO = imageTag('O'_u32, 'T'_u32, 'T'_u32, 'O'_u32)
const TAG_WOFF = imageTag('w'_u32, 'O'_u32, 'F'_u32, 'F'_u32)
const TAG_WOF2 = imageTag('w'_u32, 'O'_u32, 'F'_u32, '2'_u32)

// One ordered glyph layer from a version-0 `COLR` color glyph.
public struct ColorGlyphLayer
{
    public readonly
    {
        glyphIndex:   u16      // Glyph index to draw for this layer.
        paletteIndex: u16      // Entry in the selected `CPAL` palette; 0xFFFF means foreground.
        hasColor:     bool     // False when paletteIndex is the special foreground entry.
        argb:         u32      // Resolved color as 0xAARRGGBB; zero when hasColor is false.
    }
}

public impl ColorGlyphLayer
{
    internal mtd init(glyphIndex: u16, paletteIndex: u16, hasColor: bool, argb: u32)
    {
        .glyphIndex   = glyphIndex
        .paletteIndex = paletteIndex
        .hasColor     = hasColor
        .argb         = argb
    }
}

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

struct GposPairLookup
{
    firstSubtable: u64
    subtableCount: u32
}

// Forward names borrow the owned font data or a static vocabulary. The reverse index
// is only needed by callers that address glyphs by name.
struct GlyphNames
{
    entries: Array!{string}

    // Format 2 maps glyphs to the standard names or to Pascal strings in the font.
    // Only the custom strings need an index because their records have variable length.
    postIndices:      const [..] u8?
    late postStrings: const [..] u8
    postOffsets:      Array!{u32}

    byName: HashTable!{string, u32}
    ready:  Swag.AtomicFlag
    lock:   Swag.Mutex
}

impl GlyphNames
{
    mtd const count()->u64
    {
        if let indices = .postIndices {
            return indices.count / 2
        }
        return .entries.count
    }

    mtd const nameOf(glyphIndex: u32)->string?
    {
        if let indices = .postIndices
        {
            if glyphIndex >= indices.count / 2 {
                return null
            }
            return packedPostGlyphName(me, indices, glyphIndex)
        }

        if glyphIndex >= .entries.count {
            return null
        }
        let name = .entries[glyphIndex]
        return name.count ? name : null
    }

    mtd buildIndex()
    {
        let context = Swag.getContext()
        let previousAllocator = context.allocator

        // Allocate the reverse index with the same allocator as the forward names.
        context.allocator = .entries.allocator orelse .postOffsets.allocator orelse previousAllocator
        defer context.allocator = previousAllocator

        let glyphCount = .count()
        .byName.reserve(glyphCount * 2)
        for glyphIndex in glyphCount
        {
            if let name = .nameOf(cast(u32, glyphIndex)) {
                .byName.add(name, cast(u32, glyphIndex), updateValue: false)
            }
        }

        .ready.raise()
    }

    mtd glyphIndex(name: string)->u32
    {
        if not name.count or not .count() {
            return 0

        }
        if not .ready.isRaised()
        {
            Sync.scopedLock(&.lock)
            if not .ready.isRaised() {
                .buildIndex()
            }
        }

        return .byName.getOrDefault(name, 0)
    }
}

// Retains validated vertical metrics in their packed form until a caller needs
// stable addresses for the individual entries.
struct VerticalMetricTable
{
    late bytes:     const [..] u8
    late allocator: IAllocator
    glyphCount:     u32
    longCount:      u32
    lastAdvance:    u16
    values:         Array!{GlyphVerticalMetrics}
    ready:          Swag.AtomicFlag
    lock:           Swag.Mutex
}

impl VerticalMetricTable
{
    func create(bytes: const [..] u8, glyphCount, longCount: u32, allocator: IAllocator)->*VerticalMetricTable
    {
        let table = Memory.new!{VerticalMetricTable}(allocator)
        table.bytes      = bytes
        table.allocator  = allocator
        table.glyphCount = glyphCount
        table.longCount  = longCount
        let last = bytes.buffer + cast(u64, longCount - 1) * 4
        table.lastAdvance = Math.make16(last[0], last[1])
        return table
    }

    #[Swag.Inline]
    mtd const glyph(glyphIndex: u32)->GlyphVerticalMetrics
    {
        var result: #returntype
        if glyphIndex < .longCount
        {
            let entry   = .bytes.buffer + cast(u64, glyphIndex) * 4
            let advance = Math.make16(entry[0], entry[1])
            let bearing = cast #bit(s16, Math.make16(entry[2], entry[3]))
            result.set(advance, bearing)
        }
        else
        {
            let offset  = cast(u64, .longCount) * 4 + cast(u64, glyphIndex - .longCount) * 2
            let entry   = .bytes.buffer + offset
            let bearing = cast #bit(s16, Math.make16(entry[0], entry[1]))
            result.set(.lastAdvance, bearing)
        }

        return result
    }

    mtd entries()->const [..] GlyphVerticalMetrics
    {
        if not .ready.isRaised()
        {
            Sync.scopedLock(&.lock)
            if not .ready.isRaised()
            {
                .values = decodeVerticalMetrics(.bytes, .glyphCount, .longCount, .allocator)
                .ready.raise()
            }
        }

        return .values.toSlice()
    }
}

struct ProgramTables
{
    advances: Array!{u16}
    cmap:     HashTable!{u32, u32}
}

// Internal backing store for a public Face. The public Face is the first field so
// that a *Face can be reinterpreted as a *FaceImpl and vice versa.
struct FaceImpl
{
    face: Face

    late allocationAllocator: IAllocator

    fontData:               Array!{u8}
    fontSource:             FontSource
    tables:                 Array!{TableRecord}
    sfntDirectory:          const [..] u8?    // Validated directory borrowed from the owned sfnt bytes.
    verticalMetrics:        *VerticalMetricTable?
    ownsVerticalMetrics:    bool
    glyphLocations:         const [..] u8?
    late glyphOutlines:     const [..] u8
    late horizontalMetrics: const [..] u8
    late chosenCMap:        const [..] u8
    cmapFormat:             u16
    unitsPerEm:             u16
    numLongMetrics:         u16
    lineGap:                s16
    macStyle:               u16
    indexToLocFormat:       s16

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
    sharedCff:     *CffFont?
    type1:         Type1Font
    sharedType1:   const *Type1Font?

    // Unicode map built from the font's own encoding, for a program that ships no `cmap`.
    // A bare CFF or Type 1 file is addressed by name or by code, and this is what still
    // lets it answer a character lookup.
    programTables:       ProgramTables
    sharedProgramTables: const *ProgramTables?
    hasCMap:             bool

    // The color lookup checks a packed base directory once for each face.
    colorBaseGlyphsValidated: Swag.AtomicFlag

    // Current point scales are shared by all simple outlines of a composite glyph.
    pointScaleKey: u64 = Swag.U64.Max
    pointScaleX:   PointScale
    pointScaleY:   PointScale

    outlinePoints:     Array!{Vector}
    outlineTags:       Array!{u8}
    outlineContours:   Array!{s16}
    bitmapPixels:      Array!{u8}
    colorBitmapPixels: Array!{u8}

    // Mono strikes borrow the font bytes and use the size at which the slot was loaded.
    embeddedBitmapTables: EmbeddedBitmapTables
    emptyOutlineSize:      u32

    // A single ordered legacy kerning subtable can stay packed. Unordered or merged
    // pairs use the hash table with `(leftGlyph << 16) | rightGlyph` as the key.
    kernData:  const [..] u8?
    kernPairs: HashTable!{u32, s16}

    // Pair-adjustment subtables the GPOS 'kern' feature reaches, as offsets into
    // 'gposTable'. Class-based subtables describe a glyph-pair matrix far too large
    // to expand, so kerning is resolved per query rather than precomputed. These
    // answer before the legacy kerning pairs, which cover the pairs they leave at zero.
    gposTable:         const [..] u8?
    gposPairSubtables: Array!{u32}
    gposPairLookups:   Array!{GposPairLookup}

    // Names borrow the owned sfnt bytes or the static Macintosh glyph vocabulary.
    postNames:       GlyphNames
    sharedPostNames: *GlyphNames?
}

impl FaceImpl
{
    mtd opDrop()
    {
        // These buffers belong to the face, so release capacity instead of only
        // clearing elements; the reusable glyph workspace dies with the face too.
        .tables.free()
        if .ownsVerticalMetrics
        {
            let metrics   = unwrap .verticalMetrics
            let allocator = metrics.allocator
            Memory.delete(metrics, allocator)
        }

        .outlinePoints.free()
        .outlineTags.free()
        .outlineContours.free()
        .bitmapPixels.free()
        .colorBitmapPixels.free()
        .kernPairs.free()
        .gposPairSubtables.free()
        .gposPairLookups.free()
        Swag.drop(&.postNames)
        Swag.init(&.postNames, 1)
        .programTables.advances.free()
        .programTables.cmap.free()

        // A custom drop owns nested cleanup, so release each string and parser
        // table explicitly and reset its fields afterwards.
        .face.releaseMetadataStrings()
        Swag.init(&.face, 1)
        Swag.drop(&.cff)
        Swag.init(&.cff, 1)
        Swag.drop(&.type1)
        Swag.init(&.type1, 1)
        .fontData.free()
    }

    mtd const fontBytes()->const [..] u8
    {
        if .fontData.count {
            return .fontData.toSlice()
        }
        return .fontSource.faceBytes()
    }

    mtd loadCff(bytes: const [..] u8, cff2 = false) fail
    {
        .sharedCff = try .fontSource.cachedCff(bytes, cff2)
        if not .sharedCff
        {
            .cff = try parseCffProgram(bytes, cff2)
        }
    }

    #[Swag.Inline]
    mtd cffFont()->*CffFont => .sharedCff orelse &.cff

    #[Swag.Inline]
    mtd const cffFont()->const *CffFont => .sharedCff orelse &.cff

    mtd loadType1(bytes: const [..] u8) fail
    {
        .sharedType1 = try .fontSource.cachedType1(bytes)
        if not .sharedType1 {
            .type1 = try parseType1Font(bytes)
        }
    }

    #[Swag.Inline]
    mtd const type1Font()->const *Type1Font => .sharedType1 orelse &.type1

    #[Swag.Inline]
    mtd postGlyphNames()->*GlyphNames => .sharedPostNames orelse &.postNames

    #[Swag.Inline]
    mtd const postGlyphNames()->const *GlyphNames => .sharedPostNames orelse &.postNames

    #[Swag.Inline]
    mtd const charstringTables()->const *ProgramTables => .sharedProgramTables orelse &.programTables

    // The validated hmtx table stores the first advances explicitly. All short metrics reuse
    // the last long advance. Bare PostScript faces supply their own charstring advances.
    mtd const glyphAdvance(glyphIndex: u32)->u16
    {
        if not .numLongMetrics {
            return .charstringTables().advances[glyphIndex]

        }
        let index = Math.min(glyphIndex, cast(u32, .numLongMetrics - 1))
        let entry = .horizontalMetrics.buffer + cast(u64, index) * 4
        return Math.make16(entry[0], entry[1])
    }

    // Reads a validated pair of offsets for a glyph whose index the caller has checked.
    #[Swag.Inline]
    mtd const glyphByteRange(glyphIndex: u32)->{ start: u32, stop: u32 }
    {
        let locations = .glyphLocations
        if not locations {
            return {0, 0}
        }
        if .indexToLocFormat == 0
        {
            let entry = locations.buffer + cast(u64, glyphIndex) * 2
            return {readPackedOffset(entry, 2) * 2, readPackedOffset(entry + 2, 2) * 2}
        }

        let entry = locations.buffer + cast(u64, glyphIndex) * 4
        return {readPackedOffset(entry, 4), readPackedOffset(entry + 4, 4)}
    }

    // Returns the glyph selected by a PostScript glyph name, or zero when no name matches.
    //
    // CFF1 and Type 1 names come from their charstring programs. CFF2 and TrueType use
    // the names in `post` formats 1, 2, or 2.5.
    // When a name occurs more than once, the lowest glyph index is returned.
    mtd glyphIndexByName(name: string)->u32
    {
        switch #complete .outlineSource
        {
        case .Cff:
            let font = .cffFont()
            return font.isCff2 ? .postGlyphNames().glyphIndex(name) : font.glyphNames.glyphIndex(name)

        case .Type1:
            return .type1Font().nameToGid.getOrDefault(name, 0)

        case .Glyf:
            return .postGlyphNames().glyphIndex(name)
        }
    }

    // Returns the glyph name held at an index, or null when unavailable.
    mtd const glyphName(glyphIndex: u32)->string?
    {
        if glyphIndex >= .face.glyphCount {
            return null

        }
        switch #complete .outlineSource
        {
        case .Cff:
            let font = .cffFont()
            return font.isCff2 ? .postGlyphNames().nameOf(glyphIndex) : font.glyphNames.nameOf(glyphIndex)

        case .Type1:
            let names = &.type1Font().glyphNames
            if glyphIndex >= names.count {
                return null
            }
            if not names[glyphIndex].count {
                return null
            }
            return names[glyphIndex]

        case .Glyf:
            return .postGlyphNames().nameOf(glyphIndex)
        }
    }

    // Returns the glyph the font's own built-in encoding places at one code.
    mtd glyphIndexByCode(code: u32)->u32
    {
        switch #complete .outlineSource
        {
        case .Cff:   return .cffFont().glyphIndexByCode(code)
        case .Type1: return .type1Font().codeToGid.getOrDefault(code, 0)
        case .Glyf:  return 0
        }
    }

    // Returns the character identifier map of a CID-keyed CFF, or nothing for another font.
    mtd glyphIndexByCid(cid: u32)->u32
    {
        if .outlineSource != .Cff {
            return 0

        }
        let font = .cffFont()
        return font.isCid ? font.glyphIndexByCid(cid) : 0
    }
}

func getFaceImpl(face: *Face?)->*FaceImpl fail
{
    if not face {
        try fault(0x23)
    }
    let safeFace = unwrap face
    return cast(*FaceImpl, cast(*void, safeFace))
}

func getSlotImpl(slot: *GlyphSlot)->*FaceImpl fail => try getFaceImpl(slot.face)

func findTable(faceData: const *FaceImpl, tag: u32)->TableRecord
{
    if let directory = faceData.sfntDirectory
    {
        let target = Math.nativeToBigEndian(tag)
        var entry  = cast(const [*] u32, directory.buffer)
        for directory.count / 16
        {
            if entry[0] == target
            {
                return {tag: tag, offset: Math.bigEndianToNative(entry[2]), length: Math.bigEndianToNative(entry[3])}
            }
            entry += 4
        }

        return {}
    }

    for it in faceData.tables
    {
        if it.tag == tag
        {
            return it[]
        }
    }

    return {}
}

func getTableSlice(faceData: *FaceImpl, tag: u32, missingCode: u8)->const [..] u8 fail
{
    let record = findTable(faceData, tag)
    if not record.tag
    {
        try fault(missingCode)
    }

    return try getSlice(faceData.fontBytes(), record.offset, record.length)
}
