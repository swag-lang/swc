using Swag, Core

private const TagEblc                = imageTag('E'_u32, 'B'_u32, 'L'_u32, 'C'_u32)
private const TagEbdt                = imageTag('E'_u32, 'B'_u32, 'D'_u32, 'T'_u32)
private const BitmapVersion          = 0x00020000_u32
private const BitmapSizeRecordBytes  = 48_u64
private const BitmapIndexRecordBytes = 8_u64
private const BigBitmapMetricsBytes  = 8_u64

struct EmbeddedBitmapTables
{
    disabled:  bool
    locations: const [..] u8?
    data:      const [..] u8?
}

private struct EmbeddedBitmapImage
{
    pixels: const [..] u8?
    width:  u8
    rows:   u8
    left:   s8
    top:    s8
}

private impl EmbeddedBitmapTables
{
    mtd locate(faceData: *FaceImpl) fail
    {
        .disabled = true
        let locationsRecord = findTable(faceData, TagEblc)
        if not locationsRecord.tag
        {
            return
        }

        let dataRecord = findTable(faceData, TagEbdt)
        if not dataRecord.tag
        {
            return
        }

        let bytes     = faceData.fontBytes()
        let locations = try getSlice(bytes, locationsRecord.offset, locationsRecord.length)
        let data      = try getSlice(bytes, dataRecord.offset, dataRecord.length)
        if peekU32(locations, 0) == BitmapVersion and peekU32(data, 0) == BitmapVersion
        {
            .locations = locations
            .data      = data
            .disabled  = false
        }
    }

    mtd const findGlyph(xPpem, yPpem: u16, glyph: u32)->EmbeddedBitmapImage fail
    {
        let locations = .locations
        let images    = .data
        if not locations or not images
        {
            return {}
        }

        let strikeCount = try readU32(locations, 4)
        let strikes     = try getSlice(locations, 8, cast(u64, strikeCount) * BitmapSizeRecordBytes)
        for strike in strikeCount
        {
            let record = cast(u64, strike) * BitmapSizeRecordBytes
            if strikes[record + 44] != xPpem or
               strikes[record + 45] != yPpem or
               strikes[record + 46] != 1 or
               (strikes[record + 47] & 1) == 0
            {
                continue
            }

            if glyph < peekU16(strikes, record + 40) or glyph > peekU16(strikes, record + 42)
            {
                continue
            }

            let offset = cast(u64, peekU32(strikes, record))
            if offset < strikes.count + 8
            {
                try fault(0x09)
            }

            let indices = try getSlice(locations, offset, peekU32(strikes, record + 4))
            let image   = try findEmbeddedBitmapInStrike(indices, images, peekU32(strikes, record + 8), glyph)
            if image.pixels
            {
                return image
            }
        }

        return {}
    }
}

private func embeddedBitmapImage(metrics, pixels: const [..] u8)->EmbeddedBitmapImage =>
{pixels, metrics[1], metrics[0], cast #bit(s8, metrics[2]), cast #bit(s8, metrics[3])}

private func readEmbeddedBitmapImage(indices, images: const [..] u8, offset, glyph: u64)->EmbeddedBitmapImage fail
{
    let format      = try readU16(indices, offset)
    let imageFormat = try readU16(indices, offset + 2)
    let imageBase   = cast(u64, try readU32(indices, offset + 4))
    if imageBase < 4
    {
        try fault(0x09)
    }

    // Format 7 stores metrics with each image. The two offsets delimit this glyph.
    if format == 1 and imageFormat == 7
    {
        let entry = offset + 8 + glyph * 4
        let start = try readU32(indices, entry)
        let end   = try readU32(indices, entry + 4)
        if end < start
        {
            try fault(0x09)
        }

        if end == start
        {
            return {}
        }

        let image   = try getSlice(images, imageBase + start, end - start)
        let metrics = try getSlice(image, 0, BigBitmapMetricsBytes)
        return embeddedBitmapImage(metrics, image[BigBitmapMetricsBytes to])
    }

    // Format 5 uses the same metrics and image length for every glyph in the range.
    if format == 2 and imageFormat == 5
    {
        let length  = cast(u64, try readU32(indices, offset + 8))
        let metrics = try getSlice(indices, offset + 12, BigBitmapMetricsBytes)
        return embeddedBitmapImage(metrics, try getSlice(images, imageBase + glyph * length, length))
    }

    return {}
}

private func findEmbeddedBitmapInStrike(indices, images: const [..] u8, count: u32, glyph: u32)->EmbeddedBitmapImage fail
{
    let records = cast(u64, count) * BitmapIndexRecordBytes
    try assertRange(indices, 0, records)

    // A strike lists nonoverlapping glyph ranges in ascending order.
    var first = 0_u64
    var end   = cast(u64, count)
    while first < end
    {
        let middle     = first + (end - first) / 2
        let record     = middle * BitmapIndexRecordBytes
        let startGlyph = peekU16(indices, record)
        let endGlyph   = peekU16(indices, record + 2)
        if glyph > endGlyph
        {
            first = middle + 1
        }
        else if glyph < startGlyph
        {
            end = middle
        }
        else
        {
            let offset = cast(u64, peekU32(indices, record + 4))
            if offset < records
            {
                try fault(0x09)
            }

            return try readEmbeddedBitmapImage(indices, images, offset, glyph - startGlyph)
        }
    }

    return {}
}

func renderEmbeddedBitmap(faceData: *FaceImpl, slot: *GlyphSlot)
{
    let size = faceData.emptyOutlineSize
    if not size
    {
        return
    }

    // Bitmap tables are optional. On a missing or broken strike, the empty outline
    // still loads and renders as it would without those tables.
    let tables = &faceData.embeddedBitmapTables
    if not tables.locations
    {
        catch tables.locate(faceData)
        if tables.disabled
        {
            return
        }
    }

    let image = catch tables.findGlyph(cast(u16, size >> 16), cast(u16, size & 0xFFFF), slot.index) orelse {}
    let input = image.pixels
    if not input
    {
        return
    }

    let rows       = cast(u32, image.rows)
    let width      = cast(u32, image.width)
    let pixelCount = rows * width
    if not pixelCount or input.count < (pixelCount + 7) / 8
    {
        return
    }

    faceData.bitmapPixels.resize(pixelCount)
    let pixels = faceData.bitmapPixels.storage()
    var hasInk = false
    for pixel in pixelCount
    {
        let mask    = 128_u8 >> (pixel & 7)
        let covered = (input[pixel >> 3] & mask) != 0
        pixels[pixel] = covered ? 255 : 0
        hasInk        = hasInk or covered
    }

    if hasInk
    {
        slot.setBitmap(rows, width, cast(s32, width), pixels, .Gray, image.left, image.top)
    }
}
