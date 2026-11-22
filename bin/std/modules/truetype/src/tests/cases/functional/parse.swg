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

func buildPredefinedCffCharset(charset: u8)->Array'u8
{
    var result: Array'u8
    result.add([
        0x01, 0x00, 0x04, 0x04,                       // Header
        0x00, 0x01, 0x01, 0x01, 0x02, 0x41,           // Name INDEX
        0x00, 0x01, 0x01, 0x01, 0x05,                 // Top DICT INDEX
        0x8C, 0x0F, 0xA2, 0x11,                       // charset 1, CharStrings offset 23
        0x00, 0x00, 0x00, 0x00,                       // String and GlobalSubrs INDEX
        0x00, 0x03, 0x01, 0x01, 0x02, 0x03, 0x04,     // Three-entry CharStrings INDEX
        0x0E, 0x0E, 0x0E])
    result[15] = 139 + charset
    return result
}

func buildCffExpertEncoding()->Array'u8
{
    var result: Array'u8
    result.add([
        0x01, 0x00, 0x04, 0x04,                       // Header
        0x00, 0x01, 0x01, 0x01, 0x02, 0x41,           // Name INDEX
        0x00, 0x01, 0x01, 0x01, 0x07,                 // Top DICT INDEX
        0x8C, 0x0F, 0x8C, 0x10, 0xA4, 0x11,           // charset 1, ExpertEncoding, CharStrings 25
        0x00, 0x00, 0x00, 0x00,                       // String and GlobalSubrs INDEX
        0x00, 0x03, 0x01, 0x01, 0x02, 0x03, 0x04,     // Three-entry CharStrings INDEX
        0x0E, 0x0E, 0x0E])
    return result
}

func buildCffWithFdSelectPrefix()->Array'u8
{
    var result: Array'u8
    result.add([0x01, 0x00, 0x04, 0x04, 0x00, 0x01, 0x01, 0x01, 0x02, 0x41])     // Header and Name INDEX end at 10.
    result.add([0x00, 0x01, 0x01, 0x01, 0x10, 0xF8, 0x1B, 0xF8, 0x1C, 0x8B, 0x0C, 0x1E, 0xC4, 0x0C, 0x24, 0xC9, 0x0C, 0x25, 0xBE, 0x11])     // Top DICT INDEX ends at 30.
    result.add([0x00, 0x02, 0x01, 0x01, 0x06, 0x0E, 0x41, 0x64, 0x6F, 0x62, 0x65, 0x49, 0x64, 0x65, 0x6E, 0x74, 0x69, 0x74, 0x79])           // Adobe and Identity String INDEX ends at 49.
    result.add([0x00, 0x00, 0x00, 0x01, 0x01, 0x01, 0x02, 0x0E])     // Empty Global Subrs and one-glyph CharStrings end at 57.
    result.add([0x00, 0x01, 0x01, 0x01, 0x01])     // One empty FD DICT; FDArray ends at 62.
    return result
}

func buildTwoGlyphCffWithFdSelectPrefix()->Array'u8
{
    var result: Array'u8

    // Header and Name INDEX end at 10.
    result.add([0x01, 0x00, 0x04, 0x04, 0x00, 0x01, 0x01, 0x01, 0x02, 0x41])

    // Top DICT INDEX ends at 30.
    result.add([0x00, 0x01, 0x01, 0x01, 0x10, 0xF8, 0x1B, 0xF8, 0x1C, 0x8B, 0x0C, 0x1E, 0xC6, 0x0C, 0x24, 0xCB, 0x0C, 0x25, 0xBE, 0x11])

    // Adobe and Identity String INDEX ends at 49.
    result.add([0x00, 0x02, 0x01, 0x01, 0x06, 0x0E, 0x41, 0x64, 0x6F, 0x62, 0x65, 0x49, 0x64, 0x65, 0x6E, 0x74, 0x69, 0x74, 0x79])

    // Empty Global Subrs and two-glyph CharStrings end at 59.
    result.add([0x00, 0x00, 0x00, 0x02, 0x01, 0x01, 0x02, 0x03, 0x0E, 0x0E])

    // One empty FD DICT; FDArray ends at 64.
    result.add([0x00, 0x01, 0x01, 0x01, 0x01])
    return result
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
    // The predefined Expert charsets map glyph IDs through their canonical SIDs.
    var expertBytes = buildPredefinedCffCharset(1)
    let expert      = expect parseCffFont(expertBytes.toSlice())
    Swag.require(expert.glyphNames[2].toString() == "exclamsmall")

    let expertSubsetBytes = buildPredefinedCffCharset(2)
    let expertSubset      = expect parseCffFont(expertSubsetBytes.toSlice())
    Swag.require(expertSubset.glyphNames[2].toString() == "dollaroldstyle")

    let encodingBytes  = buildCffExpertEncoding()
    let expertEncoding = expect parseCffFont(encodingBytes.toSlice())
    let code33         = expertEncoding.codeToGid.tryFind(33)
    Swag.require(code33 != null and code33.value == 2)
}

#test
{
    // A custom format-1 charset range must fit the remaining CharStrings.
    var completeCharset = buildPredefinedCffCharset(33)
    completeCharset.add([0x01, 0x00, 0x02, 0x01])
    let parsed = expect parseCffFont(completeCharset.toSlice())
    Swag.require(parsed.glyphNames[2].toString() == "quotedbl")

    var overlongCharset = buildPredefinedCffCharset(33)
    overlongCharset.add([0x01, 0x00, 0x02, 0x02])

    var rejected: Swag.Error
    discard catch parseCffFont(overlongCharset.toSlice()) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // Format-1 CFF encoding ranges must stay within byte codes.
    var completeEncoding = buildCffExpertEncoding()
    completeEncoding[17] = 0xAE
    completeEncoding.add([0x01, 0x01, 0xFE, 0x01])
    let parsed  = expect parseCffFont(completeEncoding.toSlice())
    let code255 = parsed.codeToGid.tryFind(255)
    Swag.require(code255 != null and code255.value == 2)

    var overlongEncoding = buildCffExpertEncoding()
    overlongEncoding[17] = 0xAE
    overlongEncoding.add([0x01, 0x01, 0xFF, 0x01])

    var rejected: Swag.Error
    discard catch parseCffFont(overlongEncoding.toSlice()) as rejected
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
    // A custom charset SID must address a standard string or the String INDEX.
    var invalidSidBytes = buildPredefinedCffCharset(34)
    invalidSidBytes.add([0x00, 0x01, 0x87, 0x01, 0x87])

    var rejected: Swag.Error
    discard catch parseCffFont(invalidSidBytes.toSlice()) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // A CID font's FDSelect must contain one FD index per glyph.
    var truncated = buildCffWithFdSelectPrefix()
    truncated.add([0x00])

    var rejected: Swag.Error
    discard catch parseCffFont(truncated.toSlice()) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // Format-3 FDSelect requires its range count, each range pair, and the final sentinel.
    var missingCount = buildCffWithFdSelectPrefix()
    missingCount.add([0x03])

    var rejected: Swag.Error
    discard catch parseCffFont(missingCount.toSlice()) as rejected
    Swag.require(rejected.value() != null)

    var missingRange = buildCffWithFdSelectPrefix()
    missingRange.add([0x03, 0x00, 0x01])
    rejected = {}
    discard catch parseCffFont(missingRange.toSlice()) as rejected
    Swag.require(rejected.value() != null)

    var missingSentinel = buildCffWithFdSelectPrefix()
    missingSentinel.add([0x03, 0x00, 0x01, 0x00, 0x00, 0x00])
    rejected = {}
    discard catch parseCffFont(missingSentinel.toSlice()) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // FDSelect values must index an entry in the font's FDArray.
    var invalidFormat0 = buildCffWithFdSelectPrefix()
    invalidFormat0.add([0x00, 0x01])

    var rejected: Swag.Error
    discard catch parseCffFont(invalidFormat0.toSlice()) as rejected
    Swag.require(rejected.value() != null)

    var invalidFormat3 = buildCffWithFdSelectPrefix()
    invalidFormat3.add([0x03, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01])
    rejected = {}
    discard catch parseCffFont(invalidFormat3.toSlice()) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // A format-3 FDSelect sentinel must equal the number of glyphs in the face.
    var completeCoverage = buildCffWithFdSelectPrefix()
    completeCoverage.add([0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x01])
    let parsed = expect parseCffFont(completeCoverage.toSlice())
    Swag.require(parsed.fdSelect.count == 1)

    var outOfRangeSentinel = buildCffWithFdSelectPrefix()
    outOfRangeSentinel.add([0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x02])

    var rejected: Swag.Error
    discard catch parseCffFont(outOfRangeSentinel.toSlice()) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // A format-3 FDSelect must start its first range at GID 0.
    var completeCoverage = buildTwoGlyphCffWithFdSelectPrefix()
    completeCoverage.add([0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x02])
    let parsed = expect parseCffFont(completeCoverage.toSlice())
    Swag.require(parsed.fdSelect.count == 2)

    var missingGlyphZero = buildTwoGlyphCffWithFdSelectPrefix()
    missingGlyphZero.add([0x03, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x02])

    var rejected: Swag.Error
    discard catch parseCffFont(missingGlyphZero.toSlice()) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // Format-3 FDSelect range starts must increase strictly.
    var orderedRanges = buildTwoGlyphCffWithFdSelectPrefix()
    orderedRanges.add([0x03, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x02])
    let parsed = expect parseCffFont(orderedRanges.toSlice())
    Swag.require(parsed.fdSelect.count == 2)

    var duplicateRangeStart = buildTwoGlyphCffWithFdSelectPrefix()
    duplicateRangeStart.add([0x03, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02])

    var rejected: Swag.Error
    discard catch parseCffFont(duplicateRangeStart.toSlice()) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // Encoding format 1 ranges cannot assign more GIDs than CharStrings contains.
    const OverlongRange: [35] u8 = [
        0x01, 0x00, 0x04, 0x04,                                   // header
        0x00, 0x01, 0x01, 0x01, 0x02, 0x41,                       // Name INDEX
        0x00, 0x01, 0x01, 0x01, 0x05, 0xA2, 0x11, 0xAA, 0x10,     // Top DICT
        0x00, 0x00, 0x00, 0x00,                                   // String and GlobalSubrs INDEX
        0x00, 0x02, 0x01, 0x01, 0x02, 0x03, 0x0E, 0x0E,           // CharStrings INDEX
        0x01, 0x01, 0x41, 0x01                                    // Format-1 range: two GIDs, only one non-.notdef glyph
        ]
    var rejected: Swag.Error
    discard catch parseCffFont(OverlongRange) as rejected
    Swag.require(rejected.value() != null)

    // Format 0 has the same bound when its explicit code count exceeds the glyphs.
    const OverlongCodes: [35] u8 = [
        0x01, 0x00, 0x04, 0x04,                                   // header
        0x00, 0x01, 0x01, 0x01, 0x02, 0x41,                       // Name INDEX
        0x00, 0x01, 0x01, 0x01, 0x05, 0xA2, 0x11, 0xAA, 0x10,     // Top DICT
        0x00, 0x00, 0x00, 0x00,                                   // String and GlobalSubrs INDEX
        0x00, 0x02, 0x01, 0x01, 0x02, 0x03, 0x0E, 0x0E,           // CharStrings INDEX
        0x00, 0x02, 0x41, 0x42                                    // Format-0 encoding: two codes, one available GID
        ]
    rejected = {}
    discard catch parseCffFont(OverlongCodes) as rejected
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
    // CFF real nibble 0xD is reserved and must not be silently skipped.
    const ReservedRealNibble: [2] u8 = [30, 0xDF]
    var rejected: Swag.Error
    discard catch parseCffDict(ReservedRealNibble) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // A CFF real sign is only valid before its mantissa digits.
    const TrailingRealSign: [3] u8 = [30, 0x1E, 0x1F]
    var rejected: Swag.Error
    discard catch parseCffDict(TrailingRealSign) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // Applying 10^309 directly overflows before the finite 0.1 significand can scale it back.
    const FiniteLargeReal: [4] u8 = [0x0A, 0x1B, 0x30, 0x9F] // 0.1E309
    let parsed = expect readCffReal(FiniteLargeReal, 0)
    Swag.require(parsed.value > 9.99e307 and parsed.value < 1.01e308)
}

#test
{
    // Exponent accumulation must reject values that cannot fit its signed counter.
    const OversizedExponent: [7] u8 = [0x1B, 0x21, 0x47, 0x48, 0x36, 0x48, 0xF0]
    var rejected: Swag.Error
    discard catch readCffReal(OversizedExponent, 0) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // A syntactically valid real whose final value exceeds f64 must fail instead of returning infinity.
    const InfiniteReal: [3] u8 = [0x1B, 0x30, 0x9F] // 1E309
    var rejected: Swag.Error
    discard catch readCffReal(InfiniteReal, 0) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // Escaped CFF DICT operators require a second byte.
    const TruncatedEscape: [1] u8 = [0x0C]
    var rejected: Swag.Error
    discard catch parseCffDict(TruncatedEscape) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // Compact positive and negative integers require their continuation byte.
    const TruncatedPositive: [1] u8 = [0xF7]
    var rejected: Swag.Error
    discard catch parseCffDict(TruncatedPositive) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // The 16-bit integer marker requires both bytes of its operand.
    const MissingWord: [1] u8 = [0x1C]
    const ShortWord:   [2] u8 = [0x1C, 0x00]
    var rejected: Swag.Error
    discard catch parseCffDict(MissingWord) as rejected
    Swag.require(rejected.value() != null)

    rejected = {}
    discard catch parseCffDict(ShortWord) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    const TruncatedNegative: [1] u8 = [0xFB]
    var rejected: Swag.Error
    discard catch parseCffDict(TruncatedNegative) as rejected
    Swag.require(rejected.value() != null)
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
