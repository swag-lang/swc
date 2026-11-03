#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func metadataTableRecord(bytes: *Array'u8, tag: u32)->u64
{
    for index in readBigU16(bytes, 4)
    {
        let record = 12'u64 + cast(u64, index) * 16
        if readBigU32(bytes, record) == tag do
            return record
    }

    Swag.assert(false, "font fixture must contain the requested metadata table")
    return 0
}

func writeMetadataU16(bytes: *Array'u8, offset: u64, value: u16)
{
    bytes[offset]     = cast(u8, value >> 8)
    bytes[offset + 1] = cast(u8, value & 255)
}

#test
{
    var bytes   = buildFontCollection(["arial.ttf", "arialbd.ttf"])
    let regular = expect Face.metadataAt(bytes.toSlice(), 0)
    let bold    = expect Face.metadataAt(bytes.toSlice(), 1)
    Swag.assert(regular.familyName == "Arial" and bold.familyName == "Arial")
    Swag.assert(regular.styleName == "Regular" and bold.styleName == "Bold")
    Swag.assert(regular.weight == 400 and bold.weight == 700)
    Swag.assert(regular.widthClass == 5 and bold.widthClass == 5)
    Swag.assert(regular.style == .None and (bold.style & .Bold) != 0)

    Swag.assert(regular.typographicFamilyName == "Arial" and bold.typographicFamilyName == "Arial")
    Swag.assert(regular.typographicStyleName == "Regular" and bold.typographicStyleName == "Bold")
    bytes.fill(0)
    bytes.free()
    Swag.assert(regular.familyName == "Arial" and bold.styleName == "Bold")
}

#test
{
    var bytes      = loadFontBytes("arial.ttf")
    let os2Record  = metadataTableRecord(&bytes, TAG_OS2)
    let headRecord = metadataTableRecord(&bytes, TAG_HEAD)
    let os2        = cast(u64, readBigU32(&bytes, os2Record + 8))
    let head       = cast(u64, readBigU32(&bytes, headRecord + 8))
    writeMetadataU16(&bytes, os2 + 4, 600)
    writeMetadataU16(&bytes, os2 + 6, 3)
    writeMetadataU16(&bytes, os2 + 62, 0x200)
    writeMetadataU16(&bytes, head + 44, 0)
    writeMetadataU16(&bytes, os2, 0)
    let older = expect Face.metadataAt(bytes.toSlice(), 0)
    Swag.assert((older.style & .Italic) == 0)
    writeMetadataU16(&bytes, os2, 4)
    let condensed = expect Face.metadataAt(bytes.toSlice(), 0)
    Swag.assert(condensed.weight == 600 and condensed.widthClass == 3)
    Swag.assert((condensed.style & .Italic) != 0 and (condensed.style & .Bold) == 0)

    writeMetadataU16(&bytes, os2 + 4, 1001)
    writeMetadataU16(&bytes, os2 + 6, 10)
    writeMetadataU16(&bytes, os2 + 62, 0)
    let invalid = expect Face.metadataAt(bytes.toSlice(), 0)
    Swag.assert(invalid.weight == 400 and invalid.widthClass == 5 and invalid.style == .None)

    writeBigU32(&bytes, os2Record, 0)
    writeMetadataU16(&bytes, head + 44, 3)
    let fallback = expect Face.metadataAt(bytes.toSlice(), 0)
    Swag.assert(fallback.weight == 700 and fallback.widthClass == 5)
    Swag.assert((fallback.style & .Bold) != 0 and (fallback.style & .Italic) != 0)
}

#test
{
    var bytes = loadFontBytes("arial.ttf")
    var outcome: Swag.Error
    discard catch Face.metadataAt(bytes.toSlice(), 1) as outcome
    Swag.assert(outcome.value() != null)

    outcome = {}
    let os2Record = metadataTableRecord(&bytes, TAG_OS2)
    writeBigU32(&bytes, os2Record + 12, 7)
    discard catch Face.metadataAt(bytes.toSlice(), 0) as outcome
    Swag.assert(outcome.value() != null)

    outcome = {}
    writeBigU32(&bytes, os2Record, 0)
    let headRecord = metadataTableRecord(&bytes, TAG_HEAD)
    writeBigU32(&bytes, headRecord + 12, 45)
    discard catch Face.metadataAt(bytes.toSlice(), 0) as outcome
    Swag.assert(outcome.value() != null)

    outcome = {}
    discard catch Face.metadataAt(WoffBytes, 0) as outcome
    Swag.assert(outcome.value() != null)
}

// A catalog can inspect metadata even when glyph data is unavailable.
#test
{
    var bytes = loadFontBytes("arial.ttf")
    let glyf  = metadataTableRecord(&bytes, TAG_GLYF)
    let loca  = metadataTableRecord(&bytes, TAG_LOCA)
    writeBigU32(&bytes, glyf, 0)
    writeBigU32(&bytes, loca, 0)
    let metadata = expect Face.metadataAt(bytes.toSlice(), 0)
    Swag.assert(metadata.familyName == "Arial" and metadata.weight == 400)
    var outcome: Swag.Error
    catch checkFaceLoad(bytes.toSlice()) as outcome
    Swag.assert(outcome.value() != null)
}

// Typographic records do not replace the legacy names used by the existing Face API.
#test
{
    var bytes  = loadFontBytes("arialbd.ttf")
    let record = metadataTableRecord(&bytes, TAG_NAME)
    let table  = cast(u64, readBigU32(&bytes, record + 8))
    for index in readBigU16(&bytes, table + 2)
    {
        let nameId = table + 6 + cast(u64, index) * 12 + 6
        let value  = readBigU16(&bytes, nameId)
        if value == 1 do
            writeMetadataU16(&bytes, nameId, 16)
        elif value == 2 do
            writeMetadataU16(&bytes, nameId, 17)
    }

    let metadata = expect Face.metadataAt(bytes.toSlice(), 0)
    Swag.assert(metadata.familyName == "Unknown" and metadata.styleName == "Regular")
    Swag.assert(metadata.typographicFamilyName == "Arial" and metadata.typographicStyleName == "Bold")
    bytes.fill(0)
    bytes.free()
    Swag.assert(metadata.typographicFamilyName == "Arial" and metadata.typographicStyleName == "Bold")
}
