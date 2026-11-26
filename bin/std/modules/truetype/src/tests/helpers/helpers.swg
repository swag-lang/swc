#global if #command == Swag.CompilerCommand.Test
#global internal

using Swag, Core

struct OutlineCounter
{
    moves:  u32
    lines:  u32
    conics: u32
}

// Returns the OWNED path: a 'string' view would dangle as soon as the intermediate
// 'Path.combine' results are dropped (caught by the owner-view escape analysis).
func getTestDataPath(fileName: string, loc = #callerlocation)->String
{
    let path = Path.combine(testSourceRoot(loc), "datas", fileName)
    Swag.require(File.exists(path))
    return path
}

func loadFontBytes(fileName: string = "segoeui.ttf")->Array'u8 => expect File.readAllBytes(getTestDataPath(fileName))

func writeBigU32(buffer: *Array'u8, offset: u64, value: u32)
{
    buffer[offset + 0] = cast(u8, ((value >> 24) & 0xFF))
    buffer[offset + 1] = cast(u8, ((value >> 16) & 0xFF))
    buffer[offset + 2] = cast(u8, ((value >> 8) & 0xFF))
    buffer[offset + 3] = cast(u8, (value & 0xFF))
}

func writeBigU16(buffer: *Array'u8, offset: u64, value: u16)
{
    buffer[offset]     = cast(u8, value >> 8)
    buffer[offset + 1] = cast(u8, value & 0xFF)
}

func readBigU16(buffer: *Array'u8, offset: u64)->u16 => cast(u16, buffer[offset]) << 8 | buffer[offset + 1]

func readBigU32(buffer: *Array'u8, offset: u64)->u32 => cast(u32, buffer[offset]) << 24 |
                                                        cast(u32, buffer[offset + 1]) << 16 |
                                                        cast(u32, buffer[offset + 2]) << 8 |
                                                        buffer[offset + 3]

// Replaces the sfnt `post` table with a small synthetic name map for parser tests.
func buildPostFormat2Font(sfnt: const [..] u8, firstGlyph, firstNameIndex: u16, secondGlyph, secondNameIndex: u16, customNames: const [..] string, truncate: bool = false)->Array'u8 fail
{
    var glyphCount = 0'u16
    var postRecord = 0'u64
    let tableCount = try readU16(sfnt, 4)
    for index in tableCount
    {
        let record = 12'u64 + cast(u64, index) * 16
        let tag    = try readU32(sfnt, record)
        if tag == imageTag('m'u32, 'a'u32, 'x'u32, 'p'u32)
        {
            let offset = try readU32(sfnt, record + 8)
            glyphCount = try readU16(sfnt, offset + 4)
        }
        elif tag == imageTag('p'u32, 'o'u32, 's'u32, 't'u32)
        {
            postRecord = record
        }
    }

    Swag.require(glyphCount > secondGlyph)
    Swag.require(postRecord != 0)

    var post: Array'u8
    post.resize(34 + cast(u64, glyphCount) * 2)
    writeBigU32(&post, 0, 0x00020000)
    writeBigU16(&post, 32, glyphCount)
    writeBigU16(&post, 34 + cast(u64, firstGlyph) * 2, firstNameIndex)
    writeBigU16(&post, 34 + cast(u64, secondGlyph) * 2, secondNameIndex)
    for name in customNames
    {
        post.add(cast(u8, name.count))
        post.add(cast(const [..] u8, name))
    }

    if truncate and post.count do
        post.resize(post.count - 1)

    var result: Array'u8
    result.add(sfnt)
    while (result.count & 3) != 0 do
        result.add(0)
    let postOffset = cast(u32, result.count)
    result.add(post.toSlice())
    writeBigU32(&result, postRecord + 8, postOffset)
    writeBigU32(&result, postRecord + 12, cast(u32, post.count))
    return result
}

func buildPostFormat25Font(sfnt: const [..] u8, glyphIndex: u16, standardNameIndex: u8)->Array'u8 fail
{
    var postRecord = 0'u64
    var maxpOffset = Swag.U32.Max
    var hheaOffset = Swag.U32.Max
    let tableCount = try readU16(sfnt, 4)
    for index in tableCount
    {
        let record = 12'u64 + cast(u64, index) * 16
        let tag    = try readU32(sfnt, record)
        if tag == imageTag('p'u32, 'o'u32, 's'u32, 't'u32) do
            postRecord = record
        elif tag == imageTag('m'u32, 'a'u32, 'x'u32, 'p'u32) do
            maxpOffset = try readU32(sfnt, record + 8)
        elif tag == imageTag('h'u32, 'h'u32, 'e'u32, 'a'u32) do
            hheaOffset = try readU32(sfnt, record + 8)
    }

    Swag.require(postRecord != 0 and maxpOffset != Swag.U32.Max and hheaOffset != Swag.U32.Max)
    Swag.require(258 > glyphIndex)

    var post: Array'u8
    post.resize(34 + 258)
    writeBigU32(&post, 0, 0x00025000)
    writeBigU16(&post, 32, 258)
    post[34 + glyphIndex] = cast(u8, cast(s16, standardNameIndex) - cast(s16, glyphIndex))

    var result: Array'u8
    result.add(sfnt)
    writeBigU16(&result, maxpOffset + 4, 258)
    writeBigU16(&result, hheaOffset + 34, 258)
    while (result.count & 3) != 0 do
        result.add(0)
    let postOffset = cast(u32, result.count)
    result.add(post.toSlice())
    writeBigU32(&result, postRecord + 8, postOffset)
    writeBigU32(&result, postRecord + 12, cast(u32, post.count))
    return result
}

func buildPostFormat3Font(sfnt: const [..] u8)->Array'u8 fail
{
    var postRecord = 0'u64
    let tableCount = try readU16(sfnt, 4)
    for index in tableCount
    {
        let record = 12'u64 + cast(u64, index) * 16
        if try readU32(sfnt, record) == imageTag('p'u32, 'o'u32, 's'u32, 't'u32) do
            postRecord = record
    }

    Swag.require(postRecord != 0)

    var post: Array'u8
    post.resize(32)
    writeBigU32(&post, 0, 0x00030000)
    var result: Array'u8
    result.add(sfnt)
    while (result.count & 3) != 0 do
        result.add(0)
    let postOffset = cast(u32, result.count)
    result.add(post.toSlice())
    writeBigU32(&result, postRecord + 8, postOffset)
    writeBigU32(&result, postRecord + 12, cast(u32, post.count))
    return result
}

func truncatePostTable(font: *Array'u8, length: u32)
{
    for index in readBigU16(font, 4)
    {
        let record = 12'u64 + cast(u64, index) * 16
        if readBigU32(font, record) == imageTag('p'u32, 'o'u32, 's'u32, 't'u32)
        {
            writeBigU32(font, record + 12, length)
            return
        }
    }

    Swag.panic("post table missing from test font", #curlocation)
}

func buildPostFormat1Font(sfnt: const [..] u8)->Array'u8 fail
{
    var maxpOffset = Swag.U32.Max
    var hheaOffset = Swag.U32.Max
    var postRecord = 0'u64
    let tableCount = try readU16(sfnt, 4)
    for index in tableCount
    {
        let record = 12'u64 + cast(u64, index) * 16
        let tag    = try readU32(sfnt, record)
        if tag == imageTag('m'u32, 'a'u32, 'x'u32, 'p'u32) do
            maxpOffset = try readU32(sfnt, record + 8)
        elif tag == imageTag('h'u32, 'h'u32, 'e'u32, 'a'u32) do
            hheaOffset = try readU32(sfnt, record + 8)
        elif tag == imageTag('p'u32, 'o'u32, 's'u32, 't'u32) do
            postRecord = record
    }

    Swag.require(maxpOffset != Swag.U32.Max and hheaOffset != Swag.U32.Max and postRecord != 0)

    var result: Array'u8
    result.add(sfnt)
    writeBigU16(&result, maxpOffset + 4, 258)
    writeBigU16(&result, hheaOffset + 34, 258)

    var post: Array'u8
    post.resize(32)
    writeBigU32(&post, 0, 0x00010000)
    while (result.count & 3) != 0 do
        result.add(0)
    let postOffset = cast(u32, result.count)
    result.add(post.toSlice())
    writeBigU32(&result, postRecord + 8, postOffset)
    writeBigU32(&result, postRecord + 12, cast(u32, post.count))
    return result
}

// Wraps an sfnt font in WOFF1, compressing tables where zlib saves space.
func buildWoffFont(sfnt: const [..] u8, reverseBlocks = false)->Array'u8 fail
{
    let numTables = try readU16(sfnt, 4)
    var result: Array'u8
    result.resize(44 + cast(u64, numTables) * 20)
    writeBigU32(&result, 0, TAG_WOFF)
    writeBigU32(&result, 4, try readU32(sfnt, 0))
    writeBigU16(&result, 12, numTables)
    writeBigU32(&result, 16, cast(u32, sfnt.count))

    var zlib: Compress.ZLib
    for position in numTables
    {
        let index         = reverseBlocks ? numTables - 1 - position : position
        let sfntRecord    = 12'u64 + cast(u64, index) * 16
        let tag           = try readU32(sfnt, sfntRecord)
        let checksum      = try readU32(sfnt, sfntRecord + 4)
        let offset        = try readU32(sfnt, sfntRecord + 8)
        let length        = try readU32(sfnt, sfntRecord + 12)
        let original      = try getSlice(sfnt, offset, length)
        let compressed    = try zlib.compress(original)
        let useCompressed = compressed.count < original.count
        let payload       = useCompressed ? compressed.toSlice() : original

        while (result.count & 3) != 0 do
            result.add(0)
        let woffOffset = cast(u32, result.count)
        result.add(payload)

        let woffRecord = 44'u64 + cast(u64, index) * 20
        writeBigU32(&result, woffRecord, tag)
        writeBigU32(&result, woffRecord + 4, woffOffset)
        writeBigU32(&result, woffRecord + 8, cast(u32, payload.count))
        writeBigU32(&result, woffRecord + 12, length)
        writeBigU32(&result, woffRecord + 16, checksum)
    }

    writeBigU32(&result, 8, cast(u32, result.count))
    return result
}

// Packs the named font files into one `ttcf` collection, so a collection can be
// exercised without checking a second multi-megabyte binary into the repository.
//
// Every table record addresses the whole file rather than its own offset table, so
// each font's records are shifted by wherever that font landed after the header.
func buildFontCollection(fileNames: const [..] string)->Array'u8
{
    var result: #returntype

    let headerSize = 12 + cast(u64, fileNames.count) * 4
    result.resize(headerSize)

    var fontOffsets: Array'u32
    for name in fileNames
    {
        // Every offset table is four-byte aligned, which is what a real collection does.
        result.resize((result.count + 3) & ~3'u64)
        let fontOffset = cast(u32, result.count)
        fontOffsets.add(fontOffset)

        let font = loadFontBytes(name)
        result.add(font.toSlice())

        let tableCount = readBigU16(&result, cast(u64, fontOffset) + 4)
        for index in tableCount
        {
            let record = cast(u64, fontOffset) + 12 + cast(u64, index) * 16
            writeBigU32(&result, record + 8, readBigU32(&result, record + 8) + fontOffset)
        }
    }

    writeBigU32(&result, 0, imageTag('t'u32, 't'u32, 'c'u32, 'f'u32))
    writeBigU32(&result, 4, 0x0001_0000)
    writeBigU32(&result, 8, cast(u32, fileNames.count))
    for offset, index in fontOffsets do
        writeBigU32(&result, 12 + cast(u64, index) * 4, offset)

    return result
}

struct FaceScope
{
    bytes: Array'u8
    face:  *Face?
}

impl FaceScope
{
    mtd init(fileName: string = "segoeui.ttf")
    {
        .bytes = loadFontBytes(fileName)

        .face = expect Face.load(.bytes.toSlice())
        Swag.require(.face != null)
    }

    mtd opDrop()
    {
        if .face
        {
            .face.destroy()
            .face = null
        }
    }
}

func getFaceData(face: *Face?)->*FaceImpl
{
    let safeFace = unwrap face
    return cast(*FaceImpl, cast(*void, safeFace))
}

func countBitmapCoverage(bitmap: const *Bitmap)->u32
{
    if not bitmap.buffer do
        return 0

    var count = 0'u32
    for index in cast(u64, bitmap.width) * bitmap.rows
    {
        if bitmap.buffer[index] != 0 do
            count += 1
    }

    return count
}

func findPointWithNonZeroY(outline: const *Outline)->u32
{
    Swag.require(outline != null)
    let pts = unwrap outline.points
    for index in cast(u32, outline.pointCount)
    {
        if pts[index].y != 0 do
            return index
    }

    Swag.require(false)
    return 0
}

const ReaderBytes:     [8] u8 = [0x12, 0x34, 0xFF, 0x80, 0x80, 0x00, 0x00, 0x01]
const ReaderS32Bytes:  [4] u8 = [0xFF, 0xFF, 0xFF, 0x80]
const FixedPointBytes: [2] u8 = [0x20, 0x00]
const BrokenFontBytes: [8] u8 = ['b'u8, 'a'u8, 'd'u8, 0x00, 0x01, 0x02, 0x03, 0x04]

const Cmap4Fixture: [32] u8 = [
    0x00, 0x04, 0x00, 0x20, 0x00, 0x00, 0x00, 0x04,
    0x00, 0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 0x41,
    0xFF, 0xFF, 0x00, 0x00, 0x00, 0x41, 0xFF, 0xFF,
    0xFF, 0xC2, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]

const Cmap12Fixture: [28] u8 = [
    0x00, 0x0C, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x1C,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x01,
    0x00, 0x01, 0x00, 0x00,
    0x00, 0x01, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x07]

// One trimmed run of three codes starting at 'A'.
const Cmap6Fixture: [16] u8 = [
    0x00, 0x06,
    0x00, 0x10,
    0x00, 0x00,
    0x00, 0x41,
    0x00, 0x03,
    0x00, 0x05, 0x00, 0x06, 0x00, 0x07]

// A trimmed Unicode run of three codes beginning at U+1F600.
const Cmap10Fixture: [26] u8 = [
    0x00, 0x0A,
    0x00, 0x00,
    0x00, 0x00, 0x00, 0x1A,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x01, 0xF6, 0x00,
    0x00, 0x00, 0x00, 0x03,
    0x00, 0x07, 0x00, 0x00, 0x00, 0x09]

// One group folding every code from 'A' to 'Z' onto glyph 9, which is the shape of
// a last-resort face.
const Cmap13Fixture: [28] u8 = [
    0x00, 0x0D, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x1C,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x01,
    0x00, 0x00, 0x00, 0x41,
    0x00, 0x00, 0x00, 0x5A,
    0x00, 0x00, 0x00, 0x09]

// A whole 'cmap' table pairing a Windows format-4 subtable, which maps 'A' to glyph
// 3, with a Unicode format-14 subtable declaring two variation selectors:
// U+FE0E covers U+0041 through U+0043 by default, and U+FE0F maps U+0042 to glyph 42.
const CmapVariationFixture: [101] u8 = [
    0x00, 0x00,
    0x00, 0x02,
    0x00, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x14,
    0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x34,
    0x00, 0x04, 0x00, 0x20, 0x00, 0x00, 0x00, 0x04,
    0x00, 0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 0x41,
    0xFF, 0xFF, 0x00, 0x00, 0x00, 0x41, 0xFF, 0xFF,
    0xFF, 0xC2, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x0E,
    0x00, 0x00, 0x00, 0x31,
    0x00, 0x00, 0x00, 0x02,
    0x00, 0xFE, 0x0E, 0x00, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x00,
    0x00, 0xFE, 0x0F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x28,
    0x00, 0x00, 0x00, 0x01,
    0x00, 0x00, 0x41, 0x02,
    0x00, 0x00, 0x00, 0x01,
    0x00, 0x00, 0x42, 0x00, 0x2A]

// A twelve-byte OpenType header declaring no table at all. The container is one this
// module reads, so the failure has to come from the missing tables rather than the
// signature.
const OpenTypeCffBytes: [12] u8 = ['O'u8, 'T'u8, 'T'u8, 'O'u8, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
const WoffBytes:        [12] u8 = ['w'u8, 'O'u8, 'F'u8, 'F'u8, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
const Woff2Bytes:       [12] u8 = ['w'u8, 'O'u8, 'F'u8, '2'u8, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]

// Rejected loads are caught by tests without weakening the successful face type.
func checkFaceLoad(bytes: const [..] u8) fail { (try Face.load(bytes)).destroy() }
func checkFaceLoadAt(bytes: const [..] u8, index: u32) fail { (try Face.loadAt(bytes, index)).destroy() }

// Returns the module's test root for test cases and shared helpers.
func testSourceRoot(loc: Swag.SourceCodeLocation = #callerlocation)->String
{
    var directory = Path.directoryName(loc.fileName)
    while directory != null
    {
        if Path.fileName(directory) == "cases" or Path.fileName(directory) == "helpers" do
            return unwrap Path.directoryName(directory)
        directory = Path.directoryName(directory)
    }

    Swag.require(false, "test source is outside cases or helpers")
    return ""
}
