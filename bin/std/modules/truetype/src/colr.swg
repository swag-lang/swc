using Swag, Core

private func findColorTableIndex(faceData: const *FaceImpl, tag: u32)->u32
{
    for index in faceData.tables.count
    {
        if faceData.tables[index].tag == tag do
            return cast(u32, index)
    }

    return Swag.U32.Max
}

func readColorGlyphLayers(faceData: const *FaceImpl, baseGlyph: u32,
                          paletteIndex: u16)->Array'ColorGlyphLayer fail
{
    var result: Array'ColorGlyphLayer
    if baseGlyph >= faceData.face.glyphCount do
        try fault(0x10)

    let colrIndex = findColorTableIndex(faceData, TAG_COLR)
    if colrIndex == Swag.U32.Max do
        return result
    let colrRecord = faceData.tables[colrIndex]
    let colr = try getSlice(faceData.fontData.toSlice(), colrRecord.offset, colrRecord.length)
    try assertRange(colr, 0, 14)

    if try readU16(colr, 0) != 0 do
        try fault(0x07)

    let baseGlyphCount = try readU16(colr, 2)
    let baseRecordsOffset = cast(u64, try readU32(colr, 4))
    let layerRecordsOffset = cast(u64, try readU32(colr, 8))
    let layerRecordCount = try readU16(colr, 12)
    if baseGlyphCount and baseRecordsOffset < 14 do
        try fault(0x08)
    if layerRecordCount and layerRecordsOffset < 14 do
        try fault(0x08)
    try assertRange(colr, baseRecordsOffset, cast(u64, baseGlyphCount) * 6)
    try assertRange(colr, layerRecordsOffset, cast(u64, layerRecordCount) * 4)
    if baseGlyphCount and layerRecordCount and
       baseRecordsOffset < layerRecordsOffset + cast(u64, layerRecordCount) * 4 and
       layerRecordsOffset < baseRecordsOffset + cast(u64, baseGlyphCount) * 6 do
        try fault(0x08)

    var baseRecord = 0'u64
    var foundBase = false
    var previousBaseGlyph = 0'u16
    var hasPreviousBaseGlyph = false
    for index in baseGlyphCount
    {
        let record = baseRecordsOffset + cast(u64, index) * 6
        let glyph = try readU16(colr, record)
        if glyph >= faceData.face.glyphCount or
           (hasPreviousBaseGlyph and glyph <= previousBaseGlyph) do
            try fault(0x08)
        if glyph == baseGlyph
        {
            baseRecord = record
            foundBase = true
        }
        previousBaseGlyph = glyph
        hasPreviousBaseGlyph = true
    }
    if not foundBase do
        return result

    let selected = baseRecord
    let firstLayer = try readU16(colr, selected + 2)
    let layerCount = try readU16(colr, selected + 4)
    if cast(u32, firstLayer) + cast(u32, layerCount) > layerRecordCount do
        try fault(0x08)

    let cpalIndex = findColorTableIndex(faceData, TAG_CPAL)
    if cpalIndex == Swag.U32.Max do
        try fault(0x08)
    let cpalRecord = faceData.tables[cpalIndex]
    let cpal = try getSlice(faceData.fontData.toSlice(), cpalRecord.offset, cpalRecord.length)
    try assertRange(cpal, 0, 12)
    if try readU16(cpal, 0) != 0 do
        try fault(0x07)

    let paletteEntryCount = try readU16(cpal, 2)
    let paletteCount = try readU16(cpal, 4)
    let colorRecordCount = try readU16(cpal, 6)
    let colorRecordsOffset = cast(u64, try readU32(cpal, 8))
    if paletteIndex >= paletteCount do
        try fault(0x06)
    try assertRange(cpal, 12, cast(u64, paletteCount) * 2)
    if colorRecordCount and colorRecordsOffset < 12 + cast(u64, paletteCount) * 2 do
        try fault(0x08)
    try assertRange(cpal, colorRecordsOffset, cast(u64, colorRecordCount) * 4)

    let paletteFirstColor = try readU16(cpal, 12 + cast(u64, paletteIndex) * 2)
    if cast(u32, paletteFirstColor) + cast(u32, paletteEntryCount) > colorRecordCount do
        try fault(0x08)

    for layerIndex in layerCount
    {
        let record = layerRecordsOffset + (cast(u64, firstLayer) + layerIndex) * 4
        let glyph = try readU16(colr, record)
        let entry = try readU16(colr, record + 2)
        if glyph >= faceData.face.glyphCount do
            try fault(0x08)

        var hasColor = false
        var argb = 0'u32
        if entry != 0xFFFF
        {
            if entry >= paletteEntryCount do
                try fault(0x08)
            let colorRecord = cast(u32, paletteFirstColor) + cast(u32, entry)
            if colorRecord >= colorRecordCount do
                try fault(0x08)
            let colorOffset = colorRecordsOffset + cast(u64, colorRecord) * 4
            let blue  = cast(u32, try readU8(cpal, colorOffset))
            let green = cast(u32, try readU8(cpal, colorOffset + 1))
            let red   = cast(u32, try readU8(cpal, colorOffset + 2))
            let alpha = cast(u32, try readU8(cpal, colorOffset + 3))
            argb = (alpha << 24) | (red << 16) | (green << 8) | blue
            hasColor = true
        }

        var layer: ColorGlyphLayer
        layer.init(glyph, entry, hasColor, argb)
        result.add(layer)
    }

    return result
}
