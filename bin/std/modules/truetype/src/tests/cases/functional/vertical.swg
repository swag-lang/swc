#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

const VerticalHeaderFixture: [36] u8 = [
    0x00, 0x01, 0x00, 0x00,
    0x02, 0xBC, 0xFF, 0x06, 0x00, 0x00,
    0x03, 0xE8, 0x00, 0x64, 0xFF, 0x9C, 0x03, 0x20,
    0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00,
    0x00, 0x02]

// Two long metrics followed by two top-side-bearing-only entries.
const VerticalLongMetricsFixture: [8] u8 = [
    0x03, 0xE8, 0x00, 0x64,
    0x03, 0x84, 0x00, 0xC8]

func writeTestU16(bytes: *Array'u8, offset: u64, value: u16)
{
    bytes[offset]     = cast(u8, value >> 8)
    bytes[offset + 1] = cast(u8, value & 0xFF)
}

func findTestTableRecord(bytes: *Array'u8, tag: u32)->u64
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

func buildVerticalFont()->Array'u8
{
    var source    = loadFontBytes("arial.ttf")
    let tableCount = readBigU16(&source, 4)
    let directoryEnd = 12'u64 + cast(u64, tableCount) * 16

    var result: #returntype
    result.add(Swag.makeSlice(source.buffer, directoryEnd))
    result.resize(directoryEnd + 32)
    result.add(Swag.makeSlice(source.buffer + directoryEnd, source.count - directoryEnd))
    writeTestU16(&result, 4, tableCount + 2)

    for index in tableCount
    {
        let record = 12'u64 + cast(u64, index) * 16
        writeBigU32(&result, record + 8, readBigU32(&result, record + 8) + 32)
    }

    result.resize((result.count + 3) & ~3'u64)
    let vheaOffset = cast(u32, result.count)
    result.add(VerticalHeaderFixture)
    result.resize((result.count + 3) & ~3'u64)
    let vmtxOffset = cast(u32, result.count)

    var verticalMetrics: Array'u8
    verticalMetrics.add(VerticalLongMetricsFixture)
    let maxpRecord = findTestTableRecord(&result, TAG_MAXP)
    let glyphCount = readBigU16(&result, readBigU32(&result, maxpRecord + 8) + 4)
    for glyphIndex in glyphCount
    {
        if glyphIndex < 2 do
            continue
        let topSideBearing = glyphIndex == 3 ? 400'u16 : 300'u16
        verticalMetrics.add(cast(u8, topSideBearing >> 8))
        verticalMetrics.add(cast(u8, topSideBearing & 0xFF))
    }
    result.add(verticalMetrics.toSlice())

    let vheaRecord = directoryEnd
    writeBigU32(&result, vheaRecord, TAG_VHEA)
    writeBigU32(&result, vheaRecord + 4, 0)
    writeBigU32(&result, vheaRecord + 8, vheaOffset)
    writeBigU32(&result, vheaRecord + 12, VerticalHeaderFixture.count)

    let vmtxRecord = directoryEnd + 16
    writeBigU32(&result, vmtxRecord, TAG_VMTX)
    writeBigU32(&result, vmtxRecord + 4, 0)
    writeBigU32(&result, vmtxRecord + 8, vmtxOffset)
    writeBigU32(&result, vmtxRecord + 12, cast(u32, verticalMetrics.count))

    // Make the horizontal advance visibly differ from the vertical one.
    let hmtxRecord = findTestTableRecord(&result, TAG_HMTX)
    let hmtxOffset  = cast(u64, readBigU32(&result, hmtxRecord + 8))
    writeTestU16(&result, hmtxOffset, 600)
    return result
}

func hasNoVerticalMetrics(face: *Face)->bool fail => (try face.getVerticalMetrics(0)) == null

#test
{
    var bytes = buildVerticalFont()
    let face  = expect Face.load(bytes.toSlice())
    defer face.destroy()

    let first = unwrap (expect face.getVerticalMetrics(0))
    let second = unwrap (expect face.getVerticalMetrics(1))
    let third = unwrap (expect face.getVerticalMetrics(2))
    let fourth = unwrap (expect face.getVerticalMetrics(3))
    Swag.require(first.advanceHeight == 1000 and first.topSideBearing == 100)
    Swag.require(second.advanceHeight == 900 and second.topSideBearing == 200)
    Swag.require(third.advanceHeight == 900 and third.topSideBearing == 300)
    Swag.require(fourth.advanceHeight == 900 and fourth.topSideBearing == 400)

    expect face.setPixelSize(32, 32)
    expect face.loadGlyph(0)
    Swag.require(face.glyph.metrics.horizontalAdvance == scale26_6(600, 32, face.unitsPerEm))
    Swag.require(face.glyph.metrics.verticalAdvance == scale26_6(1000, 32, face.unitsPerEm))
    Swag.require(face.glyph.metrics.verticalTopSideBearing == scale26_6(100, 32, face.unitsPerEm))
}

#test
{
    let bytes = loadFontBytes("arial.ttf")
    let face  = expect Face.load(bytes.toSlice())
    defer face.destroy()
    Swag.require(expect hasNoVerticalMetrics(face))

    var outcome: Swag.Error
    discard catch face.getVerticalMetrics(face.glyphCount) as outcome
    Swag.require(outcome.value() != null)
}

#test
{
    var bytes = buildVerticalFont()
    let vmtxRecord = findTestTableRecord(&bytes, TAG_VMTX)
    writeBigU32(&bytes, vmtxRecord + 12, 2)

    var outcome: Swag.Error
    catch checkFaceLoad(bytes.toSlice()) as outcome
    Swag.require(outcome.value() != null)
}
