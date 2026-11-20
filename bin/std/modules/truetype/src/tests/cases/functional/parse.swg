#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func parseTestTableRecord(bytes: *Array'u8, tag: u32)->u64
{
    for index in readBigU16(bytes, 4)
    {
        let record = 12'u64 + cast(u64, index) * 16
        if readBigU32(bytes, record) == tag do
            return record
    }

    Swag.require(false, "font fixture must contain the requested table")
    return 0
}

#test
{
    let valueU16 = expect readU16(ReaderBytes, 0)
    Swag.require(valueU16 == 0x1234)

    let valueS16 = expect readS16(ReaderBytes, 2)
    Swag.require(valueS16 == -128)

    let valueU32 = expect readU32(ReaderBytes, 0)
    Swag.require(valueU32 == 0x1234FF80)

    let valueS32 = expect readS32(ReaderS32Bytes, 0)
    Swag.require(valueS32 == -128)

    let valueF2Dot14 = expect readF2Dot14(FixedPointBytes, 0)
    Swag.require(Math.abs(valueF2Dot14 - 0.5) < 0.0001)

    var err6Outcome: Swag.Error
    discard catch assertRange(ReaderBytes, 0, 16) as err6Outcome
    let err6 = err6Outcome.value()
    Swag.require(err6 != null)

    var errOverflowOutcome: Swag.Error
    discard catch assertRange(ReaderBytes, Swag.U64.Max, 1) as errOverflowOutcome
    let errOverflow = errOverflowOutcome.value()
    Swag.require(errOverflow != null)
}

#test
{
    Swag.require(peekU16(ReaderBytes, Swag.U64.Max) == 0)
    Swag.require(peekU16(ReaderBytes, Swag.U64.Max - 1) == 0)
    Swag.require(peekU24(ReaderBytes, Swag.U64.Max) == 0)
    Swag.require(peekU24(ReaderBytes, Swag.U64.Max - 1) == 0)
    Swag.require(peekU32(ReaderBytes, Swag.U64.Max) == 0)
    Swag.require(peekU32(ReaderBytes, Swag.U64.Max - 3) == 0)
}

#test
{
    // CFF INDEX offsets are one-based and must be monotonic. Otherwise a later
    // item can point backward even though the final offset remains in bounds.
    const BadCffIndex: [8] u8 = [0x00, 0x02, 0x01, 0x01, 0x03, 0x02, 0xAA, 0xBB]
    var rejected: Swag.Error
    discard catch readCffIndex(BadCffIndex, 0) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // A format-0 charset must contain one SID for every glyph after .notdef.
    const TruncatedCharset: [32] u8 = [
        0x01, 0x00, 0x04, 0x04,                                   // header
        0x00, 0x01, 0x01, 0x01, 0x02, 0x41,                       // Name INDEX
        0x00, 0x01, 0x01, 0x01, 0x05, 0xA2, 0x11, 0xAA, 0x0F,     // Top DICT
        0x00, 0x00, 0x00, 0x00,                                   // String and GlobalSubrs INDEX
        0x00, 0x02, 0x01, 0x01, 0x02, 0x03, 0x0E, 0x0E,           // CharStrings INDEX
        0x00     // Charset format 0, missing glyph SID
        ]
    var rejected: Swag.Error
    discard catch parseCffFont(TruncatedCharset) as rejected
    Swag.require(rejected.value() != null)

    // A format-0 encoding's declared code count must fit its table extent.
    const TruncatedEncoding: [33] u8 = [
        0x01, 0x00, 0x04, 0x04,                                   // header
        0x00, 0x01, 0x01, 0x01, 0x02, 0x41,                       // Name INDEX
        0x00, 0x01, 0x01, 0x01, 0x05, 0xA2, 0x11, 0xAA, 0x10,     // Top DICT
        0x00, 0x00, 0x00, 0x00,                                   // String and GlobalSubrs INDEX
        0x00, 0x02, 0x01, 0x01, 0x02, 0x03, 0x0E, 0x0E,           // CharStrings INDEX
        0x00, 0x01     // Encoding format 0, count 1, missing code
        ]
    rejected = {}
    discard catch parseCffFont(TruncatedEncoding) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    var faceData: FaceImpl
    faceData.face.setGlyphCount(1)
    faceData.indexToLocFormat = 2

    var rejected: Swag.Error
    discard catch buildGlyphLocations(&faceData) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // Short loca offsets must be non-decreasing across the glyph array.
    const Loca: [4] u8 = [0x00, 0x02, 0x00, 0x00]
    var faceData: FaceImpl
    faceData.face.setGlyphCount(1)
    faceData.indexToLocFormat = 0
    faceData.fontData.add(Loca)
    faceData.fontData.add([0x00, 0x00, 0x00, 0x00])
    faceData.tables.add({tag: TAG_LOCA, offset: 0, length: 4})
    faceData.tables.add({tag: TAG_GLYF, offset: 4, length: 4})

    var rejected: Swag.Error
    discard catch buildGlyphLocations(&faceData) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // The final loca entry cannot extend past the glyf table.
    const Loca: [4] u8 = [0x00, 0x00, 0x00, 0x03]
    var faceData: FaceImpl
    faceData.face.setGlyphCount(1)
    faceData.indexToLocFormat = 0
    faceData.fontData.add(Loca)
    faceData.fontData.add([0x00, 0x00, 0x00, 0x00])
    faceData.tables.add({tag: TAG_LOCA, offset: 0, length: 4})
    faceData.tables.add({tag: TAG_GLYF, offset: 4, length: 4})

    var rejected: Swag.Error
    discard catch buildGlyphLocations(&faceData) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // The public face loader rejects a descending loca pair before glyph loading.
    var bytes      = loadFontBytes("arial.ttf")
    let locaRecord = parseTestTableRecord(&bytes, TAG_LOCA)
    let locaOffset = readBigU32(&bytes, locaRecord + 8)
    let headRecord = parseTestTableRecord(&bytes, TAG_HEAD)
    let headOffset = readBigU32(&bytes, headRecord + 8)
    Swag.require(readBigU16(&bytes, headOffset + 50) == 1)
    writeBigU32(&bytes, locaOffset + 0, 4)
    writeBigU32(&bytes, locaOffset + 4, 0)

    var rejected: Swag.Error
    discard catch Face.load(bytes.toSlice()) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // The public face loader rejects a final loca entry beyond glyf's table extent.
    var bytes      = loadFontBytes("arial.ttf")
    let locaRecord = parseTestTableRecord(&bytes, TAG_LOCA)
    let locaOffset = readBigU32(&bytes, locaRecord + 8)
    let headRecord = parseTestTableRecord(&bytes, TAG_HEAD)
    let headOffset = readBigU32(&bytes, headRecord + 8)
    let maxpRecord = parseTestTableRecord(&bytes, TAG_MAXP)
    let maxpOffset = readBigU32(&bytes, maxpRecord + 8)
    let glyfRecord = parseTestTableRecord(&bytes, TAG_GLYF)
    let glyfLength = readBigU32(&bytes, glyfRecord + 12)
    let glyphCount = readBigU16(&bytes, maxpOffset + 4)
    Swag.require(readBigU16(&bytes, headOffset + 50) == 1)
    writeBigU32(&bytes, locaOffset + cast(u64, glyphCount) * 4, glyfLength + 1)

    var rejected: Swag.Error
    discard catch Face.load(bytes.toSlice()) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // hhea.numOfLongHorMetrics must name at least one metric and no more than
    // the face's glyph count.
    var bytes      = loadFontBytes("arial.ttf")
    let hheaRecord = parseTestTableRecord(&bytes, TAG_HHEA)
    let hheaOffset = readBigU32(&bytes, hheaRecord + 8)
    let maxpRecord = parseTestTableRecord(&bytes, TAG_MAXP)
    let maxpOffset = readBigU32(&bytes, maxpRecord + 8)
    let glyphCount = readBigU16(&bytes, maxpOffset + 4)
    writeBigU16(&bytes, hheaOffset + 34, 0)

    var rejected: Swag.Error
    discard catch Face.load(bytes.toSlice()) as rejected
    Swag.require(rejected.value() != null)

    bytes = loadFontBytes("arial.ttf")
    let resetHheaRecord = parseTestTableRecord(&bytes, TAG_HHEA)
    let resetHheaOffset = readBigU32(&bytes, resetHheaRecord + 8)
    writeBigU16(&bytes, resetHheaOffset + 34, glyphCount + 1)
    rejected = {}
    discard catch Face.load(bytes.toSlice()) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // Even an optional table the face parser does not otherwise consume must fit
    // within the font before its directory record is accepted.
    var bytes      = loadFontBytes("arial.ttf")
    let dsigRecord = parseTestTableRecord(&bytes, imageTag('D'u32, 'S'u32, 'I'u32, 'G'u32))
    writeBigU32(&bytes, dsigRecord + 8, cast(u32, bytes.count + 1))

    var rejected: Swag.Error
    discard catch Face.load(bytes.toSlice()) as rejected
    Swag.require(rejected.value() != null)
}

// A CFF real without its terminating nibble fails instead of reading zero bytes forever.
#test
{
    const UnterminatedReal: [2] u8 = [30, 0x12]
    var rejected: Swag.Error
    discard catch parseCffDict(UnterminatedReal) as rejected
    let error = rejected.value()
    Swag.require(error != null)
}

#test
{
    var err7Outcome: Swag.Error
    catch checkFaceLoad(BrokenFontBytes) as err7Outcome
    let err7 = err7Outcome.value()
    Swag.require(err7 != null)

    var empty:       Array'u8
    var err8Outcome: Swag.Error
    catch checkFaceLoad(empty.toSlice()) as err8Outcome
    let err8 = err8Outcome.value()
    Swag.require(err8 != null)
}
