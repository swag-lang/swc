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
    var source       = loadFontBytes("arial.ttf")
    let tableCount   = readBigU16(&source, 4)
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
    writeColorU16(&colr, 0, 0)       // version
    writeColorU16(&colr, 2, 1)       // base glyph records
    writeBigU32(&colr, 4, 14)        // base glyph records offset
    writeBigU32(&colr, 8, 20)        // layer records offset
    writeColorU16(&colr, 12, 3)      // layer records
    writeColorU16(&colr, 14, 36)     // 'A' base glyph
    writeColorU16(&colr, 16, 0)
    writeColorU16(&colr, 18, 3)
    writeColorU16(&colr, 20, 70)
    writeColorU16(&colr, 22, 0)
    writeColorU16(&colr, 24, 71)
    writeColorU16(&colr, 26, 1)
    writeColorU16(&colr, 28, 72)
    writeColorU16(&colr, 30, 0xFFFF)     // foreground color

    while (result.count & 3) != 0 do
        result.add(0)
    let colrOffset = cast(u32, result.count)
    result.add(colr.toSlice())

    var cpal: Array'u8
    cpal.resize(32)
    writeColorU16(&cpal, 0, 0)     // CPAL v0
    writeColorU16(&cpal, 2, 2)     // entries per palette
    writeColorU16(&cpal, 4, 2)     // palettes
    writeColorU16(&cpal, 6, 4)     // color records
    writeBigU32(&cpal, 8, 16)      // color records offset
    writeColorU16(&cpal, 12, 0)
    writeColorU16(&cpal, 14, 2)

    // CPAL records are BGRA; API colors are ARGB.
    cpal[16] = 0x33
    cpal[17] = 0x22
    cpal[18] = 0x11
    cpal[19] = 0xFF
    cpal[20] = 0x66
    cpal[21] = 0x55
    cpal[22] = 0x44
    cpal[23] = 0xFF
    cpal[24] = 0x99
    cpal[25] = 0x88
    cpal[26] = 0x77
    cpal[27] = 0x80
    cpal[28] = 0xCC
    cpal[29] = 0xBB
    cpal[30] = 0xAA
    cpal[31] = 0xFF

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

func buildTwoBaseColorFont(firstBase, secondBase: u16)->Array'u8
{
    var source     = buildColorFont()
    let colrRecord = colorTableRecord(&source, TAG_COLR)
    let colrOffset = cast(u64, readBigU32(&source, colrRecord + 8))
    let insertion  = colrOffset + 32

    var result: Array'u8
    result.add(Swag.makeSlice(source.buffer, insertion))
    result.resize(insertion + 8)
    result.add(Swag.makeSlice(source.buffer + insertion, source.count - insertion))

    let cpalRecord = colorTableRecord(&result, TAG_CPAL)
    let cpalOffset = readBigU32(&result, cpalRecord + 8)
    writeBigU32(&result, cpalRecord + 8, cpalOffset + 8)

    var layerRecords: Array'u8
    layerRecords.add(Swag.makeSlice(result.buffer + colrOffset + 20, 12))
    writeColorU16(&result, colrOffset + 2, 2)
    writeBigU32(&result, colrOffset + 8, 26)
    writeColorU16(&result, colrOffset + 14, firstBase)
    writeColorU16(&result, colrOffset + 20, secondBase)
    writeColorU16(&result, colrOffset + 22, 0)
    writeColorU16(&result, colrOffset + 24, 3)
    Memory.copy(cast(*void, result.storage() + colrOffset + 26),
                cast(const *void, unwrap layerRecords.buffer),
                12)
    writeBigU32(&result, colrRecord + 12, 38)
    return result
}

func buildCompositeColorFont(firstGlyph, secondGlyph, thirdGlyph: u16)->Array'u8
{
    var result     = buildColorFont()
    let colrRecord = colorTableRecord(&result, TAG_COLR)
    let colrOffset = cast(u64, readBigU32(&result, colrRecord + 8))
    writeColorU16(&result, colrOffset + 20, firstGlyph)
    writeColorU16(&result, colrOffset + 24, secondGlyph)
    writeColorU16(&result, colrOffset + 28, thirdGlyph)

    let cpalRecord = colorTableRecord(&result, TAG_CPAL)
    let cpalOffset = cast(u64, readBigU32(&result, cpalRecord + 8))
    result[cpalOffset + 23] = 0x80     // Palette 0, entry 1 is half-transparent.
    return result
}

func blendExpectedColor(destination, source: u32, coverage: u8)->u32
{
    let sourceAlpha = (((source >> 24) & 255) * cast(u32, coverage) + 127) / 255
    if not sourceAlpha do
        return destination

    let destinationAlpha = (destination >> 24) & 255
    let outputAlpha      = sourceAlpha + (destinationAlpha * (255 - sourceAlpha) + 127) / 255
    let sourceRed        = (source >> 16) & 255
    let sourceGreen      = (source >> 8) & 255
    let sourceBlue       = source & 255
    let destinationRed   = (destination >> 16) & 255
    let destinationGreen = (destination >> 8) & 255
    let destinationBlue  = destination & 255

    let red = (sourceRed * sourceAlpha +
               (destinationRed * destinationAlpha * (255 - sourceAlpha) + 127) / 255 + outputAlpha / 2) / outputAlpha
    let green = (sourceGreen * sourceAlpha +
                 (destinationGreen * destinationAlpha * (255 - sourceAlpha) + 127) / 255 + outputAlpha / 2) / outputAlpha
    let blue = (sourceBlue * sourceAlpha +
                (destinationBlue * destinationAlpha * (255 - sourceAlpha) + 127) / 255 + outputAlpha / 2) / outputAlpha
    return (outputAlpha << 24) | (red << 16) | (green << 8) | blue
}

#test
{
    var bytes = buildColorFont()
    let face  = expect Face.load(bytes.toSlice())
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
    let face  = expect Face.load(bytes.toSlice())
    defer face.destroy()

    let layers = expect face.getColorLayers(face.glyphIndex('A'))
    Swag.require(layers.isEmpty())

    var noColorGlyph: Swag.Error
    discard catch face.loadColorGlyph(face.glyphIndex('A')) as noColorGlyph
    Swag.require(noColorGlyph.value() != null)
}

#test
{
    var bytes      = buildColorFont()
    let colrRecord = colorTableRecord(&bytes, TAG_COLR)

    // The COLR layer table itself falls beyond the declared table extent.
    writeBigU32(&bytes, colrRecord + 12, 21)

    let face = expect Face.load(bytes.toSlice())
    defer face.destroy()
    var malformed: Swag.Error
    discard catch face.getColorLayers(36) as malformed
    Swag.require(malformed.value() != null)

    var offsetBytes  = buildColorFont()
    let offsetRecord = colorTableRecord(&offsetBytes, TAG_COLR)
    let offsetTable  = cast(u64, readBigU32(&offsetBytes, offsetRecord + 8))
    writeBigU32(&offsetBytes, offsetTable + 8, 0xFFFF_FFF0)
    let offsetFace = expect Face.load(offsetBytes.toSlice())
    defer offsetFace.destroy()
    var badLayerOffset: Swag.Error
    discard catch offsetFace.getColorLayers(36) as badLayerOffset
    Swag.require(badLayerOffset.value() != null)

    var paletteBytes = buildColorFont()
    let cpalRecord   = colorTableRecord(&paletteBytes, TAG_CPAL)
    let cpalOffset   = cast(u64, readBigU32(&paletteBytes, cpalRecord + 8))
    writeColorU16(&paletteBytes, cpalOffset + 12, 3)
    let paletteFace = expect Face.load(paletteBytes.toSlice())
    defer paletteFace.destroy()
    var badPaletteRange: Swag.Error
    discard catch paletteFace.getColorLayers(36) as badPaletteRange
    Swag.require(badPaletteRange.value() != null)

    var emptyPaletteBytes = buildColorFont()
    let emptyColrRecord   = colorTableRecord(&emptyPaletteBytes, TAG_COLR)
    let emptyColrOffset   = cast(u64, readBigU32(&emptyPaletteBytes, emptyColrRecord + 8))
    for index in 3 do
        writeColorU16(&emptyPaletteBytes, emptyColrOffset + 22 + cast(u64, index) * 4, 0xFFFF)
    let emptyCpalRecord = colorTableRecord(&emptyPaletteBytes, TAG_CPAL)
    let emptyCpalOffset = cast(u64, readBigU32(&emptyPaletteBytes, emptyCpalRecord + 8))
    writeColorU16(&emptyPaletteBytes, emptyCpalOffset + 12, 3)
    let emptyPaletteFace = expect Face.load(emptyPaletteBytes.toSlice())
    defer emptyPaletteFace.destroy()
    var invalidEmptyPalette: Swag.Error
    discard catch emptyPaletteFace.getColorLayers(36) as invalidEmptyPalette
    Swag.require(invalidEmptyPalette.value() != null)
}

#test
{
    var duplicateBytes = buildTwoBaseColorFont(36, 36)
    let duplicateFace  = expect Face.load(duplicateBytes.toSlice())
    defer duplicateFace.destroy()
    var duplicate: Swag.Error
    discard catch duplicateFace.getColorLayers(36) as duplicate
    Swag.require(duplicate.value() != null)

    var unsortedBytes = buildTwoBaseColorFont(37, 36)
    let unsortedFace  = expect Face.load(unsortedBytes.toSlice())
    defer unsortedFace.destroy()
    var unsorted: Swag.Error
    discard catch unsortedFace.getColorLayers(36) as unsorted
    Swag.require(unsorted.value() != null)
}

#test
{
    var bytes = buildCompositeColorFont(36, 36, 36)
    let face  = expect Face.load(bytes.toSlice())
    defer face.destroy()
    expect face.setPixelSize(0, 48)

    let base = face.glyphIndex('A')
    expect face.loadGlyph(base, .Render)
    let baseMetrics = face.glyph.metrics
    let baseLeft    = face.glyph.bitmapLeft
    let baseTop     = face.glyph.bitmapTop
    let gray        = face.glyph.bitmap
    Swag.require(gray.pixelMode == .Gray)
    var mask: Array'u8
    for row in gray.rows do
        mask.add(expect gray.row(row))

    let foreground = 0x8000FF00'u32
    expect face.loadColorGlyph(base, 0, foreground)
    let colorBitmap = face.glyph.bitmap
    Swag.require(face.glyph.index == base)
    Swag.require(face.glyph.metrics.width == baseMetrics.width and face.glyph.metrics.height == baseMetrics.height)
    Swag.require(face.glyph.bitmapLeft == baseLeft and face.glyph.bitmapTop == baseTop)
    Swag.require(colorBitmap.width == gray.width and colorBitmap.rows == gray.rows)
    Swag.require(colorBitmap.pitch == cast(s32, colorBitmap.width * 4))
    Swag.require(colorBitmap.pixelMode == .ColorRgba and colorBitmap.pixelMode.bytesPerPixel() == 4)

    for y in colorBitmap.rows
    {
        let maskRow = cast(u64, y) * colorBitmap.width
        let rgba    = expect colorBitmap.row(y)
        for x in colorBitmap.width
        {
            let coverage = mask[maskRow + x]
            var expected = 0'u32
            expected = blendExpectedColor(expected, 0xFF112233, coverage)
            expected = blendExpectedColor(expected, 0x80445566, coverage)
            expected = blendExpectedColor(expected, foreground, coverage)
            let offset = cast(u64, x) * 4
            let actual = (cast(u32, rgba[offset + 3]) << 24) |
                         (cast(u32, rgba[offset + 0]) << 16) |
                         (cast(u32, rgba[offset + 1]) << 8) |
                         rgba[offset + 2]
            Swag.require(actual == expected)
        }
    }

    expect face.loadColorGlyph(base, 1, foreground)
    let alternate = face.glyph.bitmap
    for y in alternate.rows
    {
        let maskRow = cast(u64, y) * alternate.width
        let rgba    = expect alternate.row(y)
        for x in alternate.width
        {
            let coverage = mask[maskRow + x]
            var expected = 0'u32
            expected = blendExpectedColor(expected, 0x80778899, coverage)
            expected = blendExpectedColor(expected, 0xFFAABBCC, coverage)
            expected = blendExpectedColor(expected, foreground, coverage)
            let offset = cast(u64, x) * 4
            let actual = (cast(u32, rgba[offset + 3]) << 24) |
                         (cast(u32, rgba[offset + 0]) << 16) |
                         (cast(u32, rgba[offset + 1]) << 8) |
                         rgba[offset + 2]
            Swag.require(actual == expected)
        }
    }

    expect face.loadGlyph(base, .Render)
    Swag.require(face.glyph.bitmap.pixelMode == .Gray)
}

#test
{
    var bytes = buildCompositeColorFont(36, 37, 38)
    let face  = expect Face.load(bytes.toSlice())
    defer face.destroy()
    expect face.setPixelSize(0, 48)

    var hasBounds = false
    var left      = 0
    var right     = 0
    var top       = 0
    var bottom    = 0
    for glyph in [36'u32, 37, 38]
    {
        expect face.loadGlyph(glyph, .Render)
        let bitmap = face.glyph.bitmap
        if not bitmap.width or not bitmap.rows do
            continue
        let itemLeft   = face.glyph.bitmapLeft
        let itemRight  = itemLeft + cast(s32, bitmap.width)
        let itemTop    = face.glyph.bitmapTop
        let itemBottom = itemTop - cast(s32, bitmap.rows)
        if not hasBounds
        {
            left      = itemLeft
            right     = itemRight
            top       = itemTop
            bottom    = itemBottom
            hasBounds = true
        }
        else
        {
            left   = Math.min(left, itemLeft)
            right  = Math.max(right, itemRight)
            top    = Math.max(top, itemTop)
            bottom = Math.min(bottom, itemBottom)
        }
    }

    expect face.loadColorGlyph(36, 0)
    let bitmap = face.glyph.bitmap
    Swag.require(hasBounds)
    Swag.require(bitmap.pixelMode == .ColorRgba)
    Swag.require(bitmap.width == cast(u32, right - left) and bitmap.rows == cast(u32, top - bottom))
    Swag.require(face.glyph.bitmapLeft == left and face.glyph.bitmapTop == top)
    Swag.require(face.glyph.index == 36)
}
