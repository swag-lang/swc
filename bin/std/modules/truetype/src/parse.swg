using Swag, Core

const NAME_ID_FAMILY = 1'u16
const NAME_ID_STYLE  = 2'u16

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

func decodeNameRecord(nameTable: #null const [..] u8, stringOffset, recordOffset: u64)->String fail
{
    let platformID = readU16(nameTable, recordOffset + 0)
    let length     = readU16(nameTable, recordOffset + 8)
    let offset     = readU16(nameTable, recordOffset + 10)
    let raw        = getSlice(nameTable, stringOffset + offset, length)

    if platformID == 0 or platformID == 3
    {
        if (@countof(raw) & 1) != 0 do
            fault(0x91)

        var chars: Array'u16
        chars.resize(@countof(raw) / 2)
        for chars.count do
            chars[@index] = readU16(raw, cast(u64) @index * 2)
        return Utf8.fromUtf16(chars.toSlice())
    }

    return String.from(cast(#null string) raw)
}

func parseNames(faceData: *FaceImpl) fail
{
    let nameTable    = getTableSlice(faceData, TAG_NAME, 0x91)
    let count        = readU16(nameTable, 2)
    let stringOffset = readU16(nameTable, 4)

    var bestFamilyScore = -1
    var bestStyleScore  = -1
    var familyName: String
    var styleName:  String

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
            familyName      = decodeNameRecord(nameTable, stringOffset, base)
            bestFamilyScore = score
        }
        elif nameID == NAME_ID_STYLE and score > bestStyleScore
        {
            styleName      = decodeNameRecord(nameTable, stringOffset, base)
            bestStyleScore = score
        }
    }

    if familyName.length == 0 do
        familyName = "Unknown"
    if styleName.length == 0 do
        styleName = "Regular"
    faceData.face.setNames(familyName, styleName)
}

func parsePost(faceData: *FaceImpl) fail
{
    let postTable = getTableSlice(faceData, TAG_POST, 0x94)
    let format    = readU32(postTable, 0)
    if format != 0x00010000 and format != 0x00020000 and format != 0x00025000 and format != 0x00030000 do
        fault(0x9A)

    faceData.face.setUnderline(readS16(postTable, 8), readS16(postTable, 10))
}

// Parse x-height / cap-height from OS/2 (version >= 2). Missing or older tables
// leave them at 0, which disables vertical hinting for that face.
func parseOS2(faceData: *FaceImpl) fail
{
    let rec = findTable(faceData, TAG_OS2)
    if !rec do
        return

    let table = getSlice(faceData.fontData.toSlice(), rec.offset, rec.length)
    if @countof(table) < 4 do
        return

    let version = readU16(table, 0)
    if version >= 2 and @countof(table) >= 90
    {
        faceData.xHeight   = readS16(table, 86)
        faceData.capHeight = readS16(table, 88)
        faceData.face.setVerticalZones(faceData.xHeight, faceData.capHeight)
    }
}

func parseCMap(faceData: *FaceImpl) fail
{
    let cmapTable = getTableSlice(faceData, TAG_CMAP, 0x92)
    let count     = readU16(cmapTable, 2)

    var bestSlice: #null const [..] u8
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
            bestSlice = subTable
            bestScore = score
            bestFmt   = format
            faceData.face.selectCharMap(platformID, encodingID)
        }
    }

    if bestFmt != 4 and bestFmt != 12 do
        fault(0x96)

    faceData.chosenCMap = bestSlice!
    faceData.cmapFormat = bestFmt
}

func buildGlyphMetrics(faceData: *FaceImpl) fail
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

func buildGlyphLocations(faceData: *FaceImpl) fail
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

// Parse the legacy 'kern' table, keeping horizontal format-0 subtables only.
// Missing or unsupported tables simply leave the kerning map empty.
func parseKern(faceData: *FaceImpl) fail
{
    let rec = findTable(faceData, TAG_KERN)
    if !rec do
        return

    let table = getSlice(faceData.fontData.toSlice(), rec.offset, rec.length)
    if @countof(table) < 4 do
        return

    let nTables = readU16(table, 2)
    var offset  = 4'u64

    for nTables
    {
        if offset + 6 > @countof(table) do
            break

        let length     = readU16(table, offset + 2)
        let coverage   = readU16(table, offset + 4)
        let format     = coverage >> 8     // high byte: subtable format
        let horizontal = (coverage & 0x0001) != 0

        // Only horizontal format-0 pair tables; skip minimum/cross-stream variants.
        if format == 0 and horizontal and (coverage & 0x0002) == 0
        {
            let nPairs  = readU16(table, offset + 6)
            var pairOff = offset + 14     // after nPairs/searchRange/entrySelector/rangeShift
            for nPairs
            {
                if pairOff + 6 > @countof(table) do
                    break
                let left  = readU16(table, pairOff + 0)
                let right = readU16(table, pairOff + 2)
                let value = readS16(table, pairOff + 4)
                if value != 0
                {
                    let key = (cast(u32) left << 16) | cast(u32) right
                    faceData.kernPairs.add(key, value)
                }

                pairOff += 6
            }
        }

        if length == 0 do
            break
        offset += length
    }
}

func initFaceRecords(faceData: *FaceImpl)
{
    faceData.face.initializeRecords()
}

func parseFace(faceData: *FaceImpl) fail
{
    let data = faceData.fontData.toSlice()
    if @countof(data) < 12 do
        fault(0x02)

    if readU32(data, 0) != 0x00010000 and readU32(data, 0) != imageTag('t'u32, 'r'u32, 'u'u32, 'e'u32) do
        fault(0x02)

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
        fault(0xB9)

    faceData.unitsPerEm = readU16(head, 18)
    faceData.face.setHeader(faceData.unitsPerEm, readS16(head, 36), readS16(head, 38), readS16(head, 40), readS16(head, 42))
    faceData.macStyle         = readU16(head, 44)
    faceData.indexToLocFormat = readS16(head, 50)

    let hhea = getTableSlice(faceData, TAG_HHEA, 0x8F)
    if @countof(hhea) < 36 do
        fault(0x8F)

    let ascender  = readS16(hhea, 4)
    let descender = readS16(hhea, 6)
    faceData.lineGap = readS16(hhea, 8)
    faceData.face.setHorizontalMetrics(ascender, descender, faceData.lineGap, readS16(hhea, 10))
    faceData.numLongMetrics = readU16(hhea, 34)

    let maxp = getTableSlice(faceData, TAG_MAXP, 0x8E)
    if @countof(maxp) < 6 do
        fault(0x8E)

    faceData.face.setGlyphCount(readU16(maxp, 4))

    buildGlyphMetrics(faceData)
    buildGlyphLocations(faceData)
    parseCMap(faceData)
    parseNames(faceData)
    parsePost(faceData)
    parseKern(faceData)
    parseOS2(faceData)

    var style = StyleFlag.None
    if (faceData.macStyle & 0x0001) != 0 or faceData.face.styleName.contains(cast(string) "Bold") do
        style |= .Bold
    if (faceData.macStyle & 0x0002) != 0 or faceData.face.styleName.contains(cast(string) "Italic") do
        style |= .Italic
    faceData.face.setStyle(style)

    initFaceRecords(faceData)
}
