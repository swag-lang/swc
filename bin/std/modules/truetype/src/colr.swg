using Swag, Core

// Two full validation vectors plus the leading glyph.
private const PackedBaseMinimum = 17

func readColorGlyphLayers(faceData: const *FaceImpl, baseGlyph: u32, paletteIndex: u16)->Array!{ColorGlyphLayer} fail
{
    var result: Array!{ColorGlyphLayer}
    if baseGlyph >= faceData.face.glyphCount
    {
        try fault(0x10)
    }

    let colrRecord = findTable(faceData, TAG_COLR)
    if not colrRecord.tag
    {
        return result
    }

    let colr = try getSlice(faceData.fontBytes(), colrRecord.offset, colrRecord.length)
    try assertRange(colr, 0, 14)
    let colrHeader  = colr.buffer
    let colrVersion = Math.make16(colrHeader[0], colrHeader[1])
    if colrVersion > 1
    {
        try fault(0x07)
    }

    // Both headers describe the v0 layer records in their first 14 bytes.
    let colrHeaderSize = colrVersion == 0 ? 14_u64 : 34_u64
    if colrVersion == 1
    {
        try assertRange(colr, 0, colrHeaderSize)
    }

    let baseGlyphCount     = Math.make16(colrHeader[2], colrHeader[3])
    let baseRecordsOffset  = cast(u64, readPackedOffset(colrHeader + 4, 4))
    let layerRecordsOffset = cast(u64, readPackedOffset(colrHeader + 8, 4))
    let layerRecordCount   = Math.make16(colrHeader[12], colrHeader[13])
    if baseGlyphCount and baseRecordsOffset < colrHeaderSize
    {
        try fault(0x08)
    }

    if layerRecordCount and layerRecordsOffset < colrHeaderSize
    {
        try fault(0x08)
    }

    try assertRange(colr, baseRecordsOffset, cast(u64, baseGlyphCount) * 6)
    try assertRange(colr, layerRecordsOffset, cast(u64, layerRecordCount) * 4)
    if baseGlyphCount and
       layerRecordCount and
       baseRecordsOffset < layerRecordsOffset + cast(u64, layerRecordCount) * 4 and
       layerRecordsOffset < baseRecordsOffset + cast(u64, baseGlyphCount) * 6
    {
        try fault(0x08)
    }

    let records = colr.buffer + baseRecordsOffset
    var selected: const [*] u8?
    if baseGlyphCount < PackedBaseMinimum
    {
        selected = try scanColorBases(records, baseGlyphCount, faceData.face.glyphCount, baseGlyph)
    }
    else
    {
        // Concurrent first queries can validate the same immutable records independently.
        let validated = &faceData.colorBaseGlyphsValidated
        if not validated.isRaised()
        {
            try validateColorBases(records, baseGlyphCount, faceData.face.glyphCount)
            cast #unconst (*Swag.AtomicFlag, validated).raise()
        }

        selected = findColorBaseGlyph(records, baseGlyphCount, baseGlyph)
    }

    if not selected
    {
        return result
    }

    let firstLayer = Math.make16(selected[2], selected[3])
    let layerCount = Math.make16(selected[4], selected[5])
    if cast(u32, firstLayer) + cast(u32, layerCount) > layerRecordCount
    {
        try fault(0x08)
    }

    let cpalRecord = findTable(faceData, TAG_CPAL)
    if not cpalRecord.tag
    {
        try fault(0x08)
    }

    let cpal = try getSlice(faceData.fontBytes(), cpalRecord.offset, cpalRecord.length)
    try assertRange(cpal, 0, 12)
    let cpalHeader  = cpal.buffer
    let cpalVersion = Math.make16(cpalHeader[0], cpalHeader[1])
    if cpalVersion > 1
    {
        try fault(0x07)
    }

    let paletteEntryCount  = Math.make16(cpalHeader[2], cpalHeader[3])
    let paletteCount       = Math.make16(cpalHeader[4], cpalHeader[5])
    let colorRecordCount   = Math.make16(cpalHeader[6], cpalHeader[7])
    let colorRecordsOffset = cast(u64, readPackedOffset(cpalHeader + 8, 4))
    if paletteIndex >= paletteCount
    {
        try fault(0x06)
    }

    let paletteIndicesEnd = 12_u64 + cast(u64, paletteCount) * 2
    let cpalHeaderSize    = paletteIndicesEnd + (cpalVersion == 0 ? 0 : 12)
    try assertRange(cpal, 0, cpalHeaderSize)

    // CPAL v1 appends three offsets for optional palette metadata.
    if cpalVersion == 1
    {
        let metadataSizes = [cast(u64, paletteCount) * 4,
                             cast(u64, paletteCount) * 2,
                             cast(u64, paletteEntryCount) * 2]
        for size, index in metadataSizes
        {
            let offset = try readU32(cpal, paletteIndicesEnd + cast(u64, index) * 4)
            if offset
            {
                if offset < cpalHeaderSize
                {
                    try fault(0x08)
                }

                try assertRange(cpal, offset, size)
            }
        }
    }

    if colorRecordCount and colorRecordsOffset < cpalHeaderSize
    {
        try fault(0x08)
    }

    try assertRange(cpal, colorRecordsOffset, cast(u64, colorRecordCount) * 4)

    let paletteIndexRecord = cpal.buffer + 12 + cast(u64, paletteIndex) * 2
    let paletteFirstColor  = Math.make16(paletteIndexRecord[0], paletteIndexRecord[1])
    if cast(u32, paletteFirstColor) + cast(u32, paletteEntryCount) > colorRecordCount
    {
        try fault(0x08)
    }

    // The record ranges already cover the layer run and the selected palette.
    let colors = cpal.buffer + colorRecordsOffset + cast(u64, paletteFirstColor) * 4
    let layers = result.emplaceAddress(layerCount)
    var record = colr.buffer + layerRecordsOffset + cast(u64, firstLayer) * 4
    for layerIndex in layerCount
    {
        let glyph = Math.make16(record[0], record[1])
        let entry = Math.make16(record[2], record[3])
        record += 4
        if glyph >= faceData.face.glyphCount
        {
            try fault(0x08)
        }

        var hasColor = false
        var argb     = 0_u32
        if entry != 0xFFFF
        {
            if entry >= paletteEntryCount
            {
                try fault(0x08)
            }

            let color = colors + cast(u64, entry) * 4
            argb     = Math.make32(color[3], color[2], color[1], color[0])
            hasColor = true
        }

        layers[layerIndex].init(glyph, entry, hasColor, argb)
    }

    return result
}

private func scanColorBases(records: const [*] u8, count: u16, glyphCount, baseGlyph: u32)->const [*] u8? fail
{
    var selected:      const [*] u8?
    var entry = records
    var previousGlyph: u16
    for index in count
    {
        let glyph = Math.make16(entry[0], entry[1])
        if glyph >= glyphCount or (index and glyph <= previousGlyph)
        {
            try fault(0x08)
        }

        if glyph == baseGlyph
        {
            selected = entry
        }

        previousGlyph = glyph
        entry         += 6
    }

    return selected
}

private func findColorBaseGlyph(records: const [*] u8, count: u16, baseGlyph: u32)->const [*] u8?
{
    var low  = 0_u64
    var high = cast(u64, count)
    while low < high
    {
        let index  = low + (high - low) / 2
        let record = records + index * 6
        let glyph  = Math.make16(record[0], record[1])
        if glyph == baseGlyph
        {
            return record
        }

        if glyph < baseGlyph
        {
            low = index + 1
        }
        else
        {
            high = index
        }
    }

    return null
}

private func validateColorBases(records: const [*] u8, count: u16, glyphCount: u32) fail
{
    var previousGlyph = Math.make16(records[0], records[1])
    var entry         = records + 6
    var remaining     = count - 1

    #static if Math.nativeToBigEndian(1_u16) != 1
    {
        // Gather the big-endian glyph indices out of eight six-byte records in 48 bytes.
        const ZeroByte = 0x80_u8
        const First    = cast(Math.Simd.U8x16, [1_u8, 0, 7, 6, 13, 12, ZeroByte, ZeroByte,
                                                ZeroByte, ZeroByte, ZeroByte, ZeroByte, ZeroByte, ZeroByte, ZeroByte, ZeroByte])
        const Middle = cast(Math.Simd.U8x16, [ZeroByte, ZeroByte, ZeroByte, ZeroByte, ZeroByte, ZeroByte, 3, 2,
                                              9, 8, 15, 14, ZeroByte, ZeroByte, ZeroByte, ZeroByte])
        const Last = cast(Math.Simd.U8x16, [ZeroByte, ZeroByte, ZeroByte, ZeroByte, ZeroByte, ZeroByte, ZeroByte, ZeroByte,
                                            ZeroByte, ZeroByte, ZeroByte, ZeroByte, 5, 4, 11, 10])
        var previous = Math.Simd.splat(previousGlyph)
        var unordered: Math.Simd.U16x8
        while remaining >= 8
        {
            let first          = Math.Simd.shuffle(Math.Simd.load(entry), First)
            let middle         = Math.Simd.shuffle(Math.Simd.load(entry + 16), Middle)
            let last           = Math.Simd.shuffle(Math.Simd.load(entry + 32), Last)
            let glyphs         = cast #bit(Math.Simd.U16x8, first | middle | last)
            let previousGlyphs = Math.Simd.align(previous, glyphs, 14)
            unordered |= glyphs <= previousGlyphs
            previous  = glyphs
            entry     += 48
            remaining -= 8
        }

        if Math.Simd.anyTrue(unordered)
        {
            try fault(0x08)
        }

        previousGlyph = previous[7]
    }

    for remaining
    {
        let glyph = Math.make16(entry[0], entry[1])
        if glyph <= previousGlyph
        {
            try fault(0x08)
        }

        previousGlyph = glyph
        entry         += 6
    }

    // A strictly increasing directory is bounded if its last glyph is valid.
    if previousGlyph >= glyphCount
    {
        try fault(0x08)
    }
}
