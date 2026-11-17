#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func writeColorU16(bytes: *Array'u8, offset: u64, value: u16)
{
    bytes[offset]     = cast(u8, value >> 8)
    bytes[offset + 1] = cast(u8, value & 0xFF)
}

func colorTableRecord(bytes: *Array'u8, tag: u32)->u64
{
    for index in readBigU16(bytes, 4)
    {
        let record = 12'u64 + cast(u64, index) * 16
        if readBigU32(bytes, record) == tag do
            return record
    }

    Swag.require(false, "color fixture must contain the requested table")
    return 0
}

func buildColorFont()->Array'u8
{
    var source = loadFontBytes("arial.ttf")
    let tableCount = readBigU16(&source, 4)
    let directoryEnd = 12'u64 + cast(u64, tableCount) * 16

    var result: #returntype
    result.add(Swag.makeSlice(source.buffer, directoryEnd))
    result.resize(directoryEnd + 32)
    result.add(Swag.makeSlice(source.buffer + directoryEnd, source.count - directoryEnd))
    writeColorU16(&result, 4, tableCount + 2)

    for index in tableCount
    {
        let record = 12'u64 + cast(u64, index) * 16
        writeBigU32(&result, record + 8, readBigU32(&result, record + 8) + 32)
    }

    var colr: Array'u8
    colr.resize(32)
    writeColorU16(&colr, 0, 0)   // version
    writeColorU16(&colr, 2, 1)   // base glyph records
    writeBigU32(&colr, 4, 14)    // base glyph records offset
    writeBigU32(&colr, 8, 20)    // layer records offset
    writeColorU16(&colr, 12, 3)  // layer records
    writeColorU16(&colr, 14, 36) // 'A' base glyph
    writeColorU16(&colr, 16, 0)
    writeColorU16(&colr, 18, 3)
    writeColorU16(&colr, 20, 70)
    writeColorU16(&colr, 22, 0)
    writeColorU16(&colr, 24, 71)
    writeColorU16(&colr, 26, 1)
    writeColorU16(&colr, 28, 72)
    writeColorU16(&colr, 30, 0xFFFF) // foreground color

    while (result.count & 3) != 0 do
        result.add(0)
    let colrOffset = cast(u32, result.count)
    result.add(colr.toSlice())

    var cpal: Array'u8
    cpal.resize(32)
    writeColorU16(&cpal, 0, 0)  // CPAL v0
    writeColorU16(&cpal, 2, 2)  // entries per palette
    writeColorU16(&cpal, 4, 2)  // palettes
    writeColorU16(&cpal, 6, 4)  // color records
    writeBigU32(&cpal, 8, 16)   // color records offset
    writeColorU16(&cpal, 12, 0)
    writeColorU16(&cpal, 14, 2)
    // CPAL records are BGRA; API colors are ARGB.
    cpal[16] = 0x33; cpal[17] = 0x22; cpal[18] = 0x11; cpal[19] = 0xFF
    cpal[20] = 0x66; cpal[21] = 0x55; cpal[22] = 0x44; cpal[23] = 0xFF
    cpal[24] = 0x99; cpal[25] = 0x88; cpal[26] = 0x77; cpal[27] = 0x80
    cpal[28] = 0xCC; cpal[29] = 0xBB; cpal[30] = 0xAA; cpal[31] = 0xFF

    while (result.count & 3) != 0 do
        result.add(0)
    let cpalOffset = cast(u32, result.count)
    result.add(cpal.toSlice())

    let colrRecord = directoryEnd
    writeBigU32(&result, colrRecord, TAG_COLR)
    writeBigU32(&result, colrRecord + 4, 0)
    writeBigU32(&result, colrRecord + 8, colrOffset)
    writeBigU32(&result, colrRecord + 12, cast(u32, colr.count))
    let cpalRecord = directoryEnd + 16
    writeBigU32(&result, cpalRecord, TAG_CPAL)
    writeBigU32(&result, cpalRecord + 4, 0)
    writeBigU32(&result, cpalRecord + 8, cpalOffset)
    writeBigU32(&result, cpalRecord + 12, cast(u32, cpal.count))
    return result
}

#test
{
    var bytes = buildColorFont()
    let face = expect Face.load(bytes.toSlice())
    defer face.destroy()

    let base = face.glyphIndex('A')
    Swag.require(base == 36)

    let palette0 = expect face.getColorLayers(base)
    Swag.require(palette0.count == 3)
    Swag.require(palette0[0].glyphIndex == 70 and palette0[0].paletteIndex == 0)
    Swag.require(palette0[0].argb == 0xFF112233)
    Swag.require(palette0[1].glyphIndex == 71 and palette0[1].paletteIndex == 1)
    Swag.require(palette0[1].argb == 0xFF445566)
    Swag.require(palette0[2].glyphIndex == 72 and not palette0[2].hasColor and palette0[2].argb == 0)

    let palette1 = expect face.getColorLayers(base, 1)
    Swag.require(palette1.count == 3)
    Swag.require(palette1[0].argb == 0x80778899)
    Swag.require(palette1[1].argb == 0xFFAABBCC)
    Swag.require(not palette1[2].hasColor and palette1[2].argb == 0)

    let absent = expect face.getColorLayers(face.glyphIndex('B'))
    Swag.require(absent.isEmpty())

    var invalidGlyph: Swag.Error
    discard catch face.getColorLayers(face.glyphCount) as invalidGlyph
    Swag.require(invalidGlyph.value() != null)
    var invalidPalette: Swag.Error
    discard catch face.getColorLayers(base, 2) as invalidPalette
    Swag.require(invalidPalette.value() != null)
}

#test
{
    var bytes = loadFontBytes("arial.ttf")
    let face = expect Face.load(bytes.toSlice())
    defer face.destroy()

    let layers = expect face.getColorLayers(face.glyphIndex('A'))
    Swag.require(layers.isEmpty())
}

#test
{
    var bytes = buildColorFont()
    let colrRecord = colorTableRecord(&bytes, TAG_COLR)
    // The COLR layer table itself falls beyond the declared table extent.
    writeBigU32(&bytes, colrRecord + 12, 21)

    let face = expect Face.load(bytes.toSlice())
    defer face.destroy()
    var malformed: Swag.Error
    discard catch face.getColorLayers(36) as malformed
    Swag.require(malformed.value() != null)

    var offsetBytes = buildColorFont()
    let offsetRecord = colorTableRecord(&offsetBytes, TAG_COLR)
    let offsetTable = cast(u64, readBigU32(&offsetBytes, offsetRecord + 8))
    writeBigU32(&offsetBytes, offsetTable + 8, 0xFFFF_FFF0)
    let offsetFace = expect Face.load(offsetBytes.toSlice())
    defer offsetFace.destroy()
    var badLayerOffset: Swag.Error
    discard catch offsetFace.getColorLayers(36) as badLayerOffset
    Swag.require(badLayerOffset.value() != null)

    var paletteBytes = buildColorFont()
    let cpalRecord = colorTableRecord(&paletteBytes, TAG_CPAL)
    let cpalOffset = cast(u64, readBigU32(&paletteBytes, cpalRecord + 8))
    writeColorU16(&paletteBytes, cpalOffset + 12, 3)
    let paletteFace = expect Face.load(paletteBytes.toSlice())
    defer paletteFace.destroy()
    var badPaletteRange: Swag.Error
    discard catch paletteFace.getColorLayers(36) as badPaletteRange
    Swag.require(badPaletteRange.value() != null)
}
