using Swag, Core

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

    let colr        = try getSlice(faceData.fontBytes(), colrRecord.offset, colrRecord.length)
    let colrVersion = try readU16(colr, 0)
    if colrVersion > 1
    {
        try fault(0x07)
    }

    // Both headers describe the v0 layer records in their first 14 bytes.
    let colrHeaderSize = colrVersion == 0 ? 14_u64 : 34_u64
    try assertRange(colr, 0, colrHeaderSize)

    let baseGlyphCount     = try readU16(colr, 2)
    let baseRecordsOffset  = cast(u64, try readU32(colr, 4))
    let layerRecordsOffset = cast(u64, try readU32(colr, 8))
    let layerRecordCount   = try readU16(colr, 12)
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

    var baseRecord           = 0_u64
    var foundBase            = false
    var previousBaseGlyph    = 0_u16
    var hasPreviousBaseGlyph = false
    for index in baseGlyphCount
    {
        let record = baseRecordsOffset + cast(u64, index) * 6
        let glyph  = try readU16(colr, record)
        if glyph >= faceData.face.glyphCount or
           (hasPreviousBaseGlyph and glyph <= previousBaseGlyph)
        {
            try fault(0x08)
        }

        if glyph == baseGlyph
        {
            baseRecord = record
            foundBase  = true
        }

        previousBaseGlyph    = glyph
        hasPreviousBaseGlyph = true
    }

    if not foundBase
    {
        return result
    }

    let selected   = baseRecord
    let firstLayer = try readU16(colr, selected + 2)
    let layerCount = try readU16(colr, selected + 4)
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
    let cpalVersion = try readU16(cpal, 0)
    if cpalVersion > 1
    {
        try fault(0x07)
    }

    let paletteEntryCount  = try readU16(cpal, 2)
    let paletteCount       = try readU16(cpal, 4)
    let colorRecordCount   = try readU16(cpal, 6)
    let colorRecordsOffset = cast(u64, try readU32(cpal, 8))
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

    let paletteFirstColor = try readU16(cpal, 12 + cast(u64, paletteIndex) * 2)
    if cast(u32, paletteFirstColor) + cast(u32, paletteEntryCount) > colorRecordCount
    {
        try fault(0x08)
    }

    for layerIndex in layerCount
    {
        let record = layerRecordsOffset + (cast(u64, firstLayer) + layerIndex) * 4
        let glyph  = try readU16(colr, record)
        let entry  = try readU16(colr, record + 2)
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

            let colorRecord = cast(u32, paletteFirstColor) + cast(u32, entry)
            if colorRecord >= colorRecordCount
            {
                try fault(0x08)
            }

            let colorOffset = colorRecordsOffset + cast(u64, colorRecord) * 4
            let blue        = cast(u32, try readU8(cpal, colorOffset))
            let green       = cast(u32, try readU8(cpal, colorOffset + 1))
            let red         = cast(u32, try readU8(cpal, colorOffset + 2))
            let alpha       = cast(u32, try readU8(cpal, colorOffset + 3))
            argb     = (alpha << 24) | (red << 16) | (green << 8) | blue
            hasColor = true
        }

        var layer: ColorGlyphLayer
        layer.init(glyph, entry, hasColor, argb)
        result.add(layer)
    }

    return result
}
