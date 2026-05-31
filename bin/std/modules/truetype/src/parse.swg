using Swag, Core

func scoreNameRecord(platformID, encodingID, languageID: u16)->s32
{
    var score = 0
    if platformID == 3
    {
        score += 40
        if encodingID == 10 do
            score += 20
        elif encodingID == 1 do
            score += 15
        if languageID == 0x0409 do
            score += 10
    }
    elif platformID == 0
    {
        score += 30
    }
    elif platformID == 1
    {
        score += 10
    }

    return score
}

func decodeNameRecord(nameTable: const [..] u8, stringOffset, recordOffset: u64)->String throw
{
    let platformID = readU16(nameTable, recordOffset + 0)
    let length     = readU16(nameTable, recordOffset + 8)
    let offset     = readU16(nameTable, recordOffset + 10)
    let raw        = getSlice(nameTable, stringOffset + offset, length)

    if platformID == 0 or platformID == 3
    {
        if (@countof(raw) & 1) != 0 do
            fail(0x91)

        var chars: Array'u16
        chars.resize(@countof(raw) / 2)
        for chars.count do
            chars[@index] = readU16(raw, cast(u64) @index * 2)
        return Utf8.fromUtf16(chars.toSlice())
    }

    return String.from(cast(string) raw)
}

func parseNames(faceData: *FaceImpl) throw
{
    let nameTable    = getTableSlice(faceData, TAG_NAME, 0x91)
    let count        = readU16(nameTable, 2)
    let stringOffset = readU16(nameTable, 4)

    var bestFamilyScore = -1
    var bestStyleScore  = -1

    for count
    {
        let base       = 6'u64 + cast(u64) @index * 12
        let platformID = readU16(nameTable, base + 0)
        let encodingID = readU16(nameTable, base + 2)
        let languageID = readU16(nameTable, base + 4)
        let nameID     = readU16(nameTable, base + 6)
        let score      = scoreNameRecord(platformID, encodingID, languageID)

        if nameID == NAME_ID_FAMILY and score > bestFamilyScore
        {
            faceData.face.familyName = decodeNameRecord(nameTable, stringOffset, base)
            bestFamilyScore   = score
        }
        elif nameID == NAME_ID_STYLE and score > bestStyleScore
        {
            faceData.face.styleName = decodeNameRecord(nameTable, stringOffset, base)
            bestStyleScore   = score
        }
    }

    if faceData.face.familyName.length == 0 do
        faceData.face.familyName = "Unknown"
    if faceData.face.styleName.length == 0 do
        faceData.face.styleName = "Regular"
}

func parsePost(faceData: *FaceImpl) throw
{
    let postTable = getTableSlice(faceData, TAG_POST, 0x94)
    let format    = readU32(postTable, 0)
    if format != 0x00010000 and format != 0x00020000 and format != 0x00025000 and format != 0x00030000 do
        fail(0x9A)

    faceData.face.underlinePosition  = readS16(postTable, 8)
    faceData.face.underlineThickness = readS16(postTable, 10)
}

func parseCMap(faceData: *FaceImpl) throw
{
    let cmapTable = getTableSlice(faceData, TAG_CMAP, 0x92)
    let count     = readU16(cmapTable, 2)

    var bestSlice: const [..] u8
    var bestScore = -1
    var bestFmt   = 0'u16

    for count
    {
        let base       = 4'u64 + cast(u64) @index * 8
        let platformID = readU16(cmapTable, base + 0)
        let encodingID = readU16(cmapTable, base + 2)
        let offset     = readU32(cmapTable, base + 4)
        let subTable   = getSlice(cmapTable, offset, @countof(cmapTable) - offset)
        let format     = readU16(subTable, 0)

        var score = scoreNameRecord(platformID, encodingID, 0)
        if format == 12 do
            score += 50
        elif format == 4 do
            score += 40
        else do
            continue

        if score > bestScore
        {
            bestSlice  = subTable
            bestScore  = score
            bestFmt    = format
        }
    }

    if bestFmt != 4 and bestFmt != 12 do
        fail(0x96)

    faceData.chosenCMap = bestSlice
    faceData.cmapFormat = bestFmt
}

func buildGlyphMetrics(faceData: *FaceImpl) throw
{
    let hmtx = getTableSlice(faceData, TAG_HMTX, 0x93)
    faceData.glyphMetrics.resize(faceData.face.glyphCount)

    var lastAdvance = 0'u16
    for faceData.face.glyphCount
    {
        var metric: GlyphMetric
        if @index < faceData.numLongMetrics
        {
            let base = cast(u64) @index * 4
            metric.advanceWidth    = readU16(hmtx, base + 0)
            metric.leftSideBearing = readS16(hmtx, base + 2)
            lastAdvance            = metric.advanceWidth
        }
        else
        {
            let base = cast(u64) faceData.numLongMetrics * 4 + cast(u64) (@index - faceData.numLongMetrics) * 2
            metric.advanceWidth    = lastAdvance
            metric.leftSideBearing = readS16(hmtx, base)
        }

        faceData.glyphMetrics[@index] = metric
    }
}

func buildGlyphLocations(faceData: *FaceImpl) throw
{
    let loca = getTableSlice(faceData, TAG_LOCA, 0x90)
    faceData.glyphLocations.resize(faceData.face.glyphCount + 1)

    if faceData.indexToLocFormat == 0
    {
        for faceData.glyphLocations.count do
            faceData.glyphLocations[@index] = cast(u32) readU16(loca, cast(u64) @index * 2) * 2
    }
    else
    {
        for faceData.glyphLocations.count do
            faceData.glyphLocations[@index] = readU32(loca, cast(u64) @index * 4)
    }
}

func initFaceRecords(faceData: *FaceImpl)
{
    faceData.face.faceCount       = 1
    faceData.face.faceIndex       = 0
    faceData.face.glyph.face      = &faceData.face
    faceData.face.glyph.format    = .None
    faceData.face.glyph.bitmap.pixelMode = .Gray
    faceData.face.glyph.bitmap.grayCount = 256

    faceData.face.size.face       = &faceData.face

    faceData.face.charMap.face       = &faceData.face
    faceData.face.charMap.platformID = 3
    faceData.face.charMap.encodingID = 1
}

func parseFace(faceData: *FaceImpl) throw
{
    let data = faceData.fontData.toSlice()
    if @countof(data) < 12 do
        fail(0x02)

    if readU32(data, 0) != 0x00010000 and readU32(data, 0) != imageTag('t''u32, 'r''u32, 'u''u32, 'e''u32) do
        fail(0x02)

    let numTables = readU16(data, 4)
    faceData.tables.resize(numTables)

    for numTables
    {
        let base = 12'u64 + cast(u64) @index * 16
        faceData.tables[@index].tag    = readU32(data, base + 0)
        faceData.tables[@index].offset = readU32(data, base + 8)
        faceData.tables[@index].length = readU32(data, base + 12)
    }

    let head = getTableSlice(faceData, TAG_HEAD, 0x8E)
    if @countof(head) < 54 do
        fail(0xB9)

    faceData.unitsPerEm               = readU16(head, 18)
    faceData.face.unitsPerEm          = faceData.unitsPerEm
    faceData.face.bbox.xMin           = readS16(head, 36)
    faceData.face.bbox.yMin           = readS16(head, 38)
    faceData.face.bbox.xMax           = readS16(head, 40)
    faceData.face.bbox.yMax           = readS16(head, 42)
    faceData.macStyle                 = readU16(head, 44)
    faceData.indexToLocFormat         = readS16(head, 50)

    let hhea = getTableSlice(faceData, TAG_HHEA, 0x8F)
    if @countof(hhea) < 36 do
        fail(0x8F)

    faceData.face.ascender            = readS16(hhea, 4)
    faceData.face.descender           = readS16(hhea, 6)
    faceData.lineGap                  = readS16(hhea, 8)
    faceData.face.height              = cast(s16) (faceData.face.ascender - faceData.face.descender + faceData.lineGap)
    faceData.face.maxAdvanceWidth     = readS16(hhea, 10)
    faceData.numLongMetrics           = readU16(hhea, 34)

    let maxp = getTableSlice(faceData, TAG_MAXP, 0x8E)
    if @countof(maxp) < 6 do
        fail(0x8E)

    faceData.face.glyphCount = readU16(maxp, 4)

    buildGlyphMetrics(faceData)
    buildGlyphLocations(faceData)
    parseCMap(faceData)
    parseNames(faceData)
    parsePost(faceData)

    faceData.face.style = .None
    if (faceData.macStyle & 0x0001) != 0 or faceData.face.styleName.contains("Bold") do
        faceData.face.style |= .Bold
    if (faceData.macStyle & 0x0002) != 0 or faceData.face.styleName.contains("Italic") do
        faceData.face.style |= .Italic

    initFaceRecords(faceData)
}

func lookupCMap4(cmap: const [..] u8, charCode: u32)->u32 throw
{
    if charCode > 0xFFFF do
        return 0

    let segCount      = readU16(cmap, 6) / 2
    let endCodesOff   = 14'u64
    let startCodesOff = endCodesOff + cast(u64) segCount * 2 + 2
    let deltasOff     = startCodesOff + cast(u64) segCount * 2
    let rangesOff     = deltasOff + cast(u64) segCount * 2

    for segCount
    {
        let idx       = cast(u64) @index
        let endCode   = readU16(cmap, endCodesOff + idx * 2)
        if charCode > endCode do
            continue

        let startCode = readU16(cmap, startCodesOff + idx * 2)
        if charCode < startCode do
            return 0

        let delta     = readS16(cmap, deltasOff + idx * 2)
        let range     = readU16(cmap, rangesOff + idx * 2)
        if !range do
            return cast(u32) ((cast(s32) charCode + delta) & 0xFFFF)

        let rangePos  = rangesOff + idx * 2
        let glyphPos  = rangePos + range + cast(u64) (charCode - startCode) * 2
        if glyphPos + 2 > @countof(cmap) do
            return 0

        var glyph = readU16(cmap, glyphPos)
        if glyph do
            glyph = cast(u16) ((cast(s32) glyph + delta) & 0xFFFF)
        return glyph
    }

    return 0
}

func lookupCMap12(cmap: const [..] u8, charCode: u32)->u32 throw
{
    let numGroups = readU32(cmap, 12)
    var left      = 0'u32
    var right     = numGroups

    while left < right
    {
        let mid       = left + (right - left) / 2
        let base      = 16'u64 + cast(u64) mid * 12
        let startCode = readU32(cmap, base + 0)
        let endCode   = readU32(cmap, base + 4)
        if charCode < startCode
        {
            right = mid
            continue
        }

        if charCode > endCode
        {
            left = mid + 1
            continue
        }

        return readU32(cmap, base + 8) + (charCode - startCode)
    }

    return 0
}

func lookupGlyphIndex(faceData: *FaceImpl, charCode: u32)->u32 throw
{
    if faceData.cmapFormat == 4 do
        return lookupCMap4(faceData.chosenCMap, charCode)
    if faceData.cmapFormat == 12 do
        return lookupCMap12(faceData.chosenCMap, charCode)
    fail(0x96)
    return 0
}
