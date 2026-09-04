#global if #command == Swag.CompilerCommand.Test

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
    let dir  = Path.directoryName(loc.fileName)
    var path = Path.combine(dir, "datas", fileName)
    Swag.assert(File.exists(path))
    return path
}

func loadFontBytes(fileName: string = "segoeui.ttf")->Array'u8
{
    let bytes = expect File.readAllBytes(getTestDataPath(fileName))
    return bytes
}

func writeBigU32(buffer: *Array'u8, offset: u64, value: u32)
{
    buffer[offset + 0] = cast(u8) ((value >> 24) & 0xFF)
    buffer[offset + 1] = cast(u8) ((value >> 16) & 0xFF)
    buffer[offset + 2] = cast(u8) ((value >> 8) & 0xFF)
    buffer[offset + 3] = cast(u8) (value & 0xFF)
}

func readBigU16(buffer: *Array'u8, offset: u64)->u16
{
    return cast(u16) buffer[offset] << 8 | buffer[offset + 1]
}

func readBigU32(buffer: *Array'u8, offset: u64)->u32
{
    return cast(u32) buffer[offset] << 24 | cast(u32) buffer[offset + 1] << 16 | cast(u32) buffer[offset + 2] << 8 | buffer[offset + 3]
}

// Packs the named font files into one `ttcf` collection, so a collection can be
// exercised without checking a second multi-megabyte binary into the repository.
//
// Every table record addresses the whole file rather than its own offset table, so
// each font's records are shifted by wherever that font landed after the header.
func buildFontCollection(fileNames: const [..] string)->Array'u8
{
    var result: retval

    let headerSize = 12 + cast(u64) fileNames.count * 4
    result.resize(headerSize)

    var fontOffsets: Array'u32
    for name in fileNames
    {
        // Every offset table is four-byte aligned, which is what a real collection does.
        result.resize((result.count + 3) & ~3'u64)
        let fontOffset = cast(u32) result.count
        fontOffsets.add(fontOffset)

        let font = loadFontBytes(name)
        result.add(font.toSlice())

        let tableCount = readBigU16(&result, cast(u64) fontOffset + 4)
        for index in tableCount
        {
            let record = cast(u64) fontOffset + 12 + cast(u64) index * 16
            writeBigU32(&result, record + 8, readBigU32(&result, record + 8) + fontOffset)
        }
    }

    writeBigU32(&result, 0, imageTag('t'u32, 't'u32, 'c'u32, 'f'u32))
    writeBigU32(&result, 4, 0x0001_0000)
    writeBigU32(&result, 8, cast(u32) fileNames.count)
    for offset, index in fontOffsets do
        writeBigU32(&result, 12 + cast(u64) index * 4, offset)

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
        Swag.assert(.face != null)
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
    let safeFace = face!
    return cast(*FaceImpl) cast(*void) safeFace
}

func getOutlineBounds(outline: const *Outline)->BBox
{
    var result: retval
    result.xMin = Swag.S32.Max
    result.yMin = Swag.S32.Max
    result.xMax = Swag.S32.Min
    result.yMax = Swag.S32.Min

    if outline.pointCount <= 0
    {
        result = {}
        return result
    }

    let pts = outline.points!
    for index in cast(u32) outline.pointCount
    {
        let pt = pts[index]
        result.xMin = Math.min(result.xMin, pt.x)
        result.yMin = Math.min(result.yMin, pt.y)
        result.xMax = Math.max(result.xMax, pt.x)
        result.yMax = Math.max(result.yMax, pt.y)
    }

    return result
}

func countBitmapCoverage(bitmap: const *Bitmap)->u32
{
    if !bitmap.buffer do
        return 0

    var count = 0'u32
    for index in cast(u64) bitmap.width * bitmap.rows
    {
        if bitmap.buffer[index] != 0 do
            count += 1
    }

    return count
}

func findPointWithNonZeroY(outline: const *Outline)->u32
{
    Swag.assert(outline != null)
    let pts = outline.points!
    for index in cast(u32) outline.pointCount
    {
        if pts[index].y != 0 do
            return index
    }

    Swag.assert(false)
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
