#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

enum FixtureBitmap
{
    Ink
    Blank
    TruncatedImage
    InvalidIndexOffset
    InvalidImageOffset
    ReversedImageOffsets
    UnsupportedDepth
}

func replaceBitmapTable(font: *Array!{u8}, oldTag, newTag: u32, data: const [..] u8)
{
    for index in readBigU16(font, 4)
    {
        let record = 12_u64 + cast(u64, index) * 16
        if readBigU32(font, record) != oldTag
        {
            continue
        }

        while (font.count & 3) != 0
        {
            font.add(0)
        }

        writeBigU32(font, record, newTag)
        writeBigU32(font, record + 8, cast(u32, font.count))
        writeBigU32(font, record + 12, cast(u32, data.count))
        font.add(data)
        return
    }

    Swag.require(false, "fixture must contain the input hinting table")
}

func buildEmbeddedBitmapFont(indexFormat: u16, fixture = FixtureBitmap.Ink, glyphIndex = 3_u16)->Array!{u8}
{
    let variableLength  = indexFormat == 1
    let indexSize       = variableLength ? 16_u32 : 20_u32
    let metrics: [8] u8 = [3, 3, 254, 3, 8, 0, 0, 0]

    var locations: Array!{u8}
    locations.resize(64 + indexSize)
    writeBigU32(&locations, 0, 0x00020000)
    writeBigU32(&locations, 4, 1)      // One bitmap size record.
    writeBigU32(&locations, 8, 56)     // Index array offset.
    writeBigU32(&locations, 12, 8 + indexSize)
    writeBigU32(&locations, 16, 1)     // One index header.
    writeBigU16(&locations, 48, glyphIndex)
    writeBigU16(&locations, 50, glyphIndex)
    locations[52] = 11     // Horizontal pixels per em.
    locations[53] = 12     // Vertical pixels per em.
    locations[54] = fixture == .UnsupportedDepth ? 2 : 1
    locations[55] = 1     // Horizontal bitmap metrics.
    writeBigU16(&locations, 56, glyphIndex)
    writeBigU16(&locations, 58, glyphIndex)
    writeBigU32(&locations, 60, fixture == .InvalidIndexOffset ? Swag.U32.Max : 8)
    writeBigU16(&locations, 64, indexFormat)
    writeBigU16(&locations, 66, variableLength ? 7 : 5)
    writeBigU32(&locations, 68, fixture == .InvalidImageOffset ? Swag.U32.Max : 4)

    var images: Array!{u8}
    images.resize(4)
    writeBigU32(&images, 0, 0x00020000)
    if variableLength
    {
        writeBigU32(&locations, 72, fixture == .ReversedImageOffsets ? 12 : 0)
        writeBigU32(&locations, 76, 10)
        images.add(metrics)
    }
    else
    {
        writeBigU32(&locations, 72, 2)
        for metric, index in metrics
        {
            locations[76 + index] = metric
        }
    }

    // Three 3-pixel rows run across byte boundaries. Give the blank glyph set
    // padding bits to check that ink detection ignores them.
    images.add(fixture == .Blank ? 0_u8 : 0xAD)
    if fixture != .TruncatedImage
    {
        images.add(fixture == .Blank ? 0x7F_u8 : 0x80)
    }

    var font = loadFontBytes("arial.ttf")
    replaceBitmapTable(&font, imageTag('f'_u32, 'p'_u32, 'g'_u32, 'm'_u32), imageTag('E'_u32, 'B'_u32, 'L'_u32, 'C'_u32), locations.toSlice())
    replaceBitmapTable(&font, imageTag('p'_u32, 'r'_u32, 'e'_u32, 'p'_u32), imageTag('E'_u32, 'B'_u32, 'D'_u32, 'T'_u32), images.toSlice())
    return font
}

func checkBitmapGlyph(face: *Face)
{
    Swag.require(face.glyph.index == 3 and face.glyph.outline.pointCount == 0)
    Swag.require(face.glyph.bitmapLeft == -2 and face.glyph.bitmapTop == 3)
    let bitmap = &face.glyph.bitmap
    Swag.require(bitmap.width == 3 and bitmap.rows == 3 and bitmap.pitch == 3)
    Swag.require(bitmap.pixelMode == .Gray)
    let expected: [9] u8 = [255, 0, 255, 0, 255, 255, 0, 255, 255]
    for row in 3
    {
        let pixels = expect bitmap.row(cast(u32, row))
        for column in 3
        {
            Swag.require(pixels[column] == expected[row * 3 + column])
        }
    }
}

#test
{
    let formats: [2] u16 = [1, 2]
    for format in formats
    {
        let bytes = buildEmbeddedBitmapFont(format)
        let face  = expect Face.load(bytes.toSlice())
        defer face.destroy()
        expect face.setPixelSize(11, 12)
        expect face.loadChar(' ', .Render)
        checkBitmapGlyph(face)
    }
}

#test
{
    let bytes = buildEmbeddedBitmapFont(1)
    let face  = expect Face.load(bytes.toSlice())
    defer face.destroy()
    expect face.setPixelSize(11, 12)
    expect face.loadChar(' ')
    Swag.require(face.glyph.bitmap.width == 0)
    let advance = face.glyph.advance.x
    expect face.setPixelSize(12, 12)
    expect face.renderGlyph()
    checkBitmapGlyph(face)
    Swag.require(face.glyph.advance.x == advance)

    expect face.loadChar(' ', .Render)
    Swag.require(face.glyph.bitmap.width == 0)
    expect face.setPixelSize(11, 12)
    expect face.loadChar('A', .Render)
    Swag.require(face.glyph.outline.pointCount > 0 and face.glyph.bitmap.width > 0)
    expect face.loadChar(' ', .Render)
    checkBitmapGlyph(face)
}

#test
{
    let formats:  [2] u16 = [1, 2]
    let variants: [6] FixtureBitmap = [.Blank, .TruncatedImage, .InvalidIndexOffset, .InvalidImageOffset, .ReversedImageOffsets, .UnsupportedDepth]
    for format in formats
    {
        for variant in variants
        {
            if format == 2 and variant == .ReversedImageOffsets
            {
                continue
            }

            let bytes = buildEmbeddedBitmapFont(format, variant)
            let face  = expect Face.load(bytes.toSlice())
            defer face.destroy()
            expect face.setPixelSize(11, 12)
            expect face.loadChar(' ', .Render)
            Swag.require(face.glyph.bitmap.width == 0 and face.glyph.bitmap.rows == 0)
        }
    }
}

#test
{
    let original = loadFontBytes("arial.ttf")
    let baseline = expect Face.load(original.toSlice())
    defer baseline.destroy()
    expect baseline.setPixelSize(11, 12)
    expect baseline.loadChar('A', .Render)
    let glyphIndex = cast(u16, baseline.glyph.index)

    let bytes = buildEmbeddedBitmapFont(1, glyphIndex: glyphIndex)
    let face  = expect Face.load(bytes.toSlice())
    defer face.destroy()
    expect face.setPixelSize(11, 12)
    expect face.loadChar('A', .Render)
    let bitmap    = &face.glyph.bitmap
    let reference = &baseline.glyph.bitmap
    Swag.require(face.glyph.outline.pointCount > 0 and bitmap.width > 0)
    Swag.require(bitmap.width == reference.width and bitmap.rows == reference.rows)
    Swag.require(face.glyph.bitmapLeft == baseline.glyph.bitmapLeft and face.glyph.bitmapTop == baseline.glyph.bitmapTop)
    for row in bitmap.rows
    {
        let pixels   = expect bitmap.row(cast(u32, row))
        let expected = expect reference.row(cast(u32, row))
        for value, column in pixels
        {
            Swag.require(value == expected[column])
        }
    }
}
